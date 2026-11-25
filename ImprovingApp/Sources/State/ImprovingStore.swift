import Foundation
import Combine
import SwiftUI
import UIKit
import AppleWatchReader
import WhoopBLE
import WhoopProtocol

struct MetricWindowSeries {
    let dates: [String]
    let values: [Double?]
    let realPoints: [Double]
    let windowRangeLabel: String
    let canStepForward: Bool
    let canStepBackward: Bool
}

enum SyncBannerState: Equatable {
    case hidden
    case syncing(String)
    case synced(String)
    case notice(String)
}

@MainActor
final class ImprovingStore: ObservableObject {

    private struct PersistedSnapshot: Codable {
        var userProfile: UserPhysiologyProfile
        var isDarkMode: Bool
        var hasImportedOrPairedRealData: Bool
        var realHistory: [String: RealBiometricDaySummary]
        var journalCheckins: [String: [String: JournalCheckState]]
        var journalMoodByDate: [String: Int]
        var geminiApiKey: String
        var selectedGeminiModel: String
        var mealsByDate: [String: [NutritionMealItem]]
        var hydrationGlassesByDate: [String: Int]
        var smartAlarmEnabled: Bool
        var wakeOffsetMinutes: Int
        var sleepGoalPct: Int
        var visibleTabs: [MainTab]
        var sectionCoachingCache: [String: SectionCoachingCard]?
        var processedAutoSyncSignatures: [String]?
        var lastAutoSyncStatus: String?
        var shortcutSyncName: String?
        var autoRunShortcutOnOpen: Bool?
        var workoutRoutines: [WorkoutRoutineTemplate]?
        var strengthLogs: [StrengthLoggedSet]?
        var manualNutrientsByDate: [String: [String: Double]]?
        var hiddenJournalHabitIds: [String]?
        var customJournalHabits: [CustomJournalHabit]?
        var journalNotesByDate: [String: String]?
        var notificationSettings: SmartNotificationSettings?
        var savedFoodsLibrary: [SavedFoodLibraryItem]?
        var customNutritionGoals: CustomNutritionGoals?
        var homeLayout: HomeLayoutPreferences?
        var coachThreads: [CoachChatThread]?
        var activeCoachThreadId: String?
        var labReports: [LabReportRecord]?
        var weeklyAiInsightsCache: [String: WeeklyAiReviewInsight]?
    }

    @Published var userProfile: UserPhysiologyProfile = {
        var p = UserPhysiologyProfile()
        p.onboardingCompleted = false
        return p
    }()
    @Published var dayOffset: Int = 0
    @Published var hasImportedOrPairedRealData: Bool = false
    @Published var realHistory: [String: RealBiometricDaySummary] = [:]
    @Published var simulatedHistory: [String: RealBiometricDaySummary] = [:]
    @Published var journalCheckinsByDate: [String: [String: JournalCheckState]] = [:]
    @Published var journalMoodByDate: [String: Int] = [:]
    @Published var mealsByDate: [String: [NutritionMealItem]] = [:]
    @Published var hydrationGlassesByDate: [String: Int] = [:]
    @Published var manualNutrientsByDate: [String: [String: Double]] = [:]
    @Published var hiddenJournalHabitIds: Set<String> = []
    @Published var customJournalHabits: [CustomJournalHabit] = []
    @Published var journalNotesByDate: [String: String] = [:]
    @Published var notificationSettings: SmartNotificationSettings = SmartNotificationSettings()
    @Published var notificationStatusText: String = "Avisos listos para configurar"
    @Published var savedFoodsLibrary: [SavedFoodLibraryItem] = []
    @Published var customNutritionGoals: CustomNutritionGoals = CustomNutritionGoals()
    @Published var selectedNutritionTrendTab: NutritionTrendTab = .score
    @Published var selectedHealthMetric: HealthMetricKind = .hrv
    @Published var selectedHealthRange: String = "30 d"
    @Published var selectedNutrientKey: String = "Proteína"
    @Published var selectedTrendItem: EffortTrendItem? = nil
    @Published var selectedWorkoutItem: EffortEventItem? = nil
    @Published var selectedBodyMetric: BodyCompositionMetricKind = .weight
    @Published var homeLayout: HomeLayoutPreferences = HomeLayoutPreferences()
    @Published var pendingNutritionLaunchMode: NutritionComposerInitialMode? = nil
    @Published var labReports: [LabReportRecord] = []
    @Published var weeklyAiInsightsCache: [String: WeeklyAiReviewInsight] = [:]
    @Published var isGeneratingWeeklyReviewAI: Bool = false

    @Published var smartAlarmEnabled: Bool = true
    @Published var wakeOffsetMinutes: Int = 0
    @Published var sleepGoalPct: Int = 100
    @Published var visibleTabs: Set<MainTab> = Set(MainTab.allCases)

    @Published var whoopConnected: Bool = false
    @Published var whoopScanning: Bool = false
    @Published var whoopDeviceName: String = "WHOOP 5.0"
    @Published var whoopBatteryPct: Int? = nil
    @Published var bleLogs: [String] = [
        "Conecta WHOOP BLE, Apple Health en vivo o importa exportar.zip para ver tus datos reales"
    ]
    @Published var whoopPacketsReceived: Int = 0

    @Published var healthKitAuthorized: Bool = false
    @Published var healthKitSyncing: Bool = false
    @Published var healthKitLastSyncText: String = "Listo"

    // Automatic Apple Shortcuts / Files Folder Bridge (Zero Paid Entitlements!)
    @Published var isAutoSyncing: Bool = false
    @Published var autoSyncStatusText: String = "Listo · Esperando Atajos o carpeta Improving"
    @Published var syncBannerState: SyncBannerState = .hidden
    @Published var shortcutSyncName: String = "Sync Improving"
    @Published var autoRunShortcutOnOpen: Bool = false
    private var processedAutoSyncSignatures: Set<String> = []
    private var lastShortcutTriggerAt: Date? = nil
    private var awaitingShortcutCallback: Bool = false
    private var lastIngestedPayloadHash: Int? = nil
    private var lastIngestedPayloadAt: Date? = nil
    private var syncBannerDismissTask: Task<Void, Never>? = nil
    private var shortcutTimeoutTask: Task<Void, Never>? = nil
    private var backgroundRecheckTask: Task<Void, Never>? = nil
    private var inboxDirectorySource: DispatchSourceFileSystemObject? = nil
    private var autoSyncSubdirSource: DispatchSourceFileSystemObject? = nil
    private var healthSyncFileSource: DispatchSourceFileSystemObject? = nil
    private var shortcutsLatestFileSource: DispatchSourceFileSystemObject? = nil
    private var pendingInboxRescan: (force: Bool, showBanner: Bool)? = nil
    private var lastActiveCalendarDayIso: String = ""

    @Published var importStatus: ExportImportStatus = ExportImportStatus()
    @Published var geminiApiKey: String = ""
    @Published var selectedGeminiModel: String = "auto"
    @Published var coachMessages: [CoachChatMessage] = []
    @Published var coachThreads: [CoachChatThread] = []
    @Published var activeCoachThreadId: String? = nil
    @Published var isCoachThinking: Bool = false
    private var activeCoachInteractionId: String? = nil

    // Background debounced persistence queue (zero main-thread JSON serialization jank!)
    private let persistenceQueue = DispatchQueue(label: "com.improving.persist.queue", qos: .utility)
    private var pendingPersistWorkItem: DispatchWorkItem? = nil

    // 4-Hour Time-Aware Section Coaching Cache
    @Published var sectionCoachingCache: [String: SectionCoachingCard] = [:]
    @Published var loadingCoachingSections: Set<CoachingSection> = []
    @Published var dataRevision: Int = 0
    private var coachingTasks: [CoachingSection: Task<Void, Never>] = [:]
    private var lastHeadlineBySection: [CoachingSection: String] = [:]

    @Published var strengthSets: [(id: String, exercise: String, reps: Int, weightKg: Double, completed: Bool)] = []
    @Published var workoutRoutines: [WorkoutRoutineTemplate] = []
    @Published var strengthLogs: [StrengthLoggedSet] = []
    @Published var restTimerRunning: Bool = false
    @Published var restTimerSeconds: Int = 90

    let whoopBleReader = WhoopBLEReader()
    private var cancellables: Set<AnyCancellable> = []
    private var bleStreamTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?

    let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var persistenceURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("improving_store_v3.json")
    }

    init() {
        loadPersistedState()
        if !hasImportedOrPairedRealData && simulatedHistory.isEmpty {
            simulatedHistory = WhoopPhysiologyEngine.generateTwoYearSimulatedHistory(profile: userProfile)
        }
        seedPreviewOnlyItemsIfNeeded()
        bindWhoopBle()
        bindHealthKit()
        // Ensure `En mi iPhone / Improving` folder is visible in Files app & run ONE silent sync on cold launch only!
        _ = ShortcutsHealthSyncImporter.autoSyncInboxURL
        scanAutoSyncInboxIfNeeded(force: false, showBanner: false)
        refreshSmartNotificationSchedules(promptPermission: false)
        publishWidgetSnapshot(triggerReload: true, forceReload: true)
    }

    deinit {
        pendingPersistWorkItem?.cancel()
        bleStreamTask?.cancel()
        timerTask?.cancel()
        syncBannerDismissTask?.cancel()
        shortcutTimeoutTask?.cancel()
        backgroundRecheckTask?.cancel()
        inboxDirectorySource?.cancel()
        autoSyncSubdirSource?.cancel()
        healthSyncFileSource?.cancel()
        shortcutsLatestFileSource?.cancel()
        for task in coachingTasks.values { task.cancel() }
    }

    private func seedPreviewOnlyItemsIfNeeded() {
        guard !hasImportedOrPairedRealData else {
            // Zero fabricated strength sets when user has real data
            strengthSets = []
            return
        }
        let todayIso = isoFormatter.string(from: Date())
        if mealsByDate[todayIso] == nil {
            mealsByDate[todayIso] = [
                NutritionMealItem(id: "m1", title: "Bowl de avena, huevos y frutos rojos", timeLabel: "08:30", kcal: 540, proteinG: 36, carbsG: 58, fatG: 16, qualityScore: 88),
                NutritionMealItem(id: "m2", title: "Salmón a la plancha con arroz jazmín y aguacate", timeLabel: "14:15", kcal: 680, proteinG: 52, carbsG: 62, fatG: 22, qualityScore: 86),
                NutritionMealItem(id: "m3", title: "Pechuga de pavo, boniato asado y verduras", timeLabel: "20:45", kcal: 450, proteinG: 38, carbsG: 42, fatG: 12, qualityScore: 84),
            ]
        }
        if strengthSets.isEmpty {
            strengthSets = [
                ("s1", "Press banca inclinado", 8, 70, true),
                ("s2", "Press banca inclinado", 8, 72.5, true),
                ("s3", "Remo con barra", 10, 65, false),
                ("s4", "Sentadilla búlgara", 10, 40, false),
            ]
        }
    }

    private func clearPreviewSeededArtifactsOnRealData() {
        strengthSets = []
        // Strip only seeded preview meal IDs ("m1", "m2", "m3") while keeping any meals the user manually logged!
        for (iso, list) in mealsByDate {
            let filtered = list.filter { !["m1", "m2", "m3"].contains($0.id) }
            if filtered.isEmpty {
                mealsByDate.removeValue(forKey: iso)
            } else {
                mealsByDate[iso] = filtered
            }
        }
    }

    // MARK: - Strict Zero-Fabrication Active History

    var activeHistory: [String: RealBiometricDaySummary] {
        hasImportedOrPairedRealData ? realHistory : simulatedHistory
    }

    var selectedDate: Date {
        let startToday = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(byAdding: .day, value: -dayOffset, to: startToday) ?? startToday
    }

    var selectedDateIso: String {
        isoFormatter.string(from: selectedDate)
    }

    var currentDaySummary: RealBiometricDaySummary? {
        if hasImportedOrPairedRealData {
            return realHistory[selectedDateIso]
        }
        return simulatedHistory[selectedDateIso]
    }

    var latestAvailableDay: RealBiometricDaySummary? {
        activeHistory.keys.sorted().last.flatMap { activeHistory[$0] }
    }

    var earliestAvailableDate: Date {
        if let firstIso = activeHistory.keys.sorted().first, let d = isoFormatter.date(from: firstIso) {
            return min(d, Calendar.current.date(byAdding: .year, value: -3, to: Date()) ?? d)
        }
        return Calendar.current.date(byAdding: .year, value: -3, to: Date()) ?? Date()
    }

    var dateLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        if dayOffset == 0 {
            f.dateFormat = "'Hoy,' d MMM"
            return f.string(from: Date()).replacingOccurrences(of: ".", with: "")
        }
        if dayOffset == 1 {
            f.dateFormat = "'Ayer,' d MMM"
            return f.string(from: selectedDate).replacingOccurrences(of: ".", with: "")
        }
        f.dateFormat = "EEE, d MMM"
        return f.string(from: selectedDate).capitalized.replacingOccurrences(of: ".", with: "")
    }

    var fullDateLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "d 'de' MMMM 'de' yyyy"
        return f.string(from: selectedDate)
    }

    var monthYearLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "MMM yyyy"
        return f.string(from: selectedDate).replacingOccurrences(of: ".", with: "")
    }

    var dataAvailability: DataAvailabilitySnapshot {
        let d = currentDaySummary
        return DataAvailabilitySnapshot(
            hasRecoveryData: d?.recoveryPct != nil,
            hasStrainData: d?.strainPct != nil,
            hasSleepData: (d?.asleepMinutes ?? 0) > 0 || d?.sleepPct != nil,
            hasHrvData: d?.hrvMs != nil,
            hasRestingHrData: d?.restingHrBpm != nil,
            hasRespData: d?.respRateRpm != nil,
            hasSpo2Data: d?.spo2Percent != nil,
            hasTempData: d?.wristTempAbsoluteC != nil || d?.wristTempDeltaC != nil,
            hasStressData: d?.stressScore != nil || !(d?.stressSamples5m.isEmpty ?? true) || !(d?.stressSeries24h.isEmpty ?? true),
            hasEnergyData: d?.energyBankPercent != nil || !(d?.energySamples5m.isEmpty ?? true) || !(d?.energySeries24h.isEmpty ?? true),
            hasWorkoutData: !(d?.workouts.isEmpty ?? true)
        )
    }

    // MARK: - Strict Real Metrics (Zero Fabricated Defaults)

    var strainPercent: Int { currentDaySummary?.strainPct ?? 0 }
    var strain21: Double { currentDaySummary?.strain21 ?? 0 }
    var recoveryPercent: Int { currentDaySummary?.recoveryPct ?? 0 }
    var sleepPercent: Int { currentDaySummary?.sleepPct ?? 0 }
    var hrvMs: Double { currentDaySummary?.hrvMs ?? 0 }
    var restingHrBpm: Double { currentDaySummary?.restingHrBpm ?? 0 }
    var liveHrBpm: Int? { currentDaySummary?.liveHrBpm }
    var respRateRpm: Double { currentDaySummary?.respRateRpm ?? 0 }
    var spo2Value: Double? { currentDaySummary?.spo2Percent }
    var spo2DisplayDouble: Double { currentDaySummary?.spo2Percent ?? 0 }
    var wristTempDeltaC: Double { currentDaySummary?.wristTempDeltaC ?? 0 }
    var wristTempAbsoluteC: Double? {
        if let abs = currentDaySummary?.wristTempAbsoluteC { return abs }
        if let delta = currentDaySummary?.wristTempDeltaC { return AppleHealthExportImporter.round1(35.8 + delta) }
        return nil
    }

    var stressSamplesToday: [TimedBiometricPoint] {
        guard let d = currentDaySummary else { return [] }
        if !d.stressSamples5m.isEmpty { return d.stressSamples5m }
        if !d.stressSeries24h.isEmpty {
            return d.stressSeries24h.enumerated().map { TimedBiometricPoint(minuteOfDay: $0.offset * 60, value: $0.element) }
        }
        return []
    }

    var energySamplesToday: [TimedBiometricPoint] {
        guard let d = currentDaySummary else { return [] }
        if !d.energySamples5m.isEmpty { return d.energySamples5m }
        if !d.energySeries24h.isEmpty {
            return d.energySeries24h.enumerated().map { TimedBiometricPoint(minuteOfDay: $0.offset * 60, value: $0.element) }
        }
        return []
    }

    /// Daily mean physiological stress (stored in `stressScore` for trends & daily averages).
    var stressScore: Int { currentDaySummary?.stressScore ?? 0 }

    /// Live/Latest real physiological stress reading (exact last 5-min bucket from today's HR timeline!).
    /// Fixes the "always stuck at 23" issue where the 24h mean barely moves due to 7+ hours of low sleeping stress.
    var currentStressScore: Int {
        if let last = stressSamplesToday.last {
            return min(max(Int(last.value.rounded()), 1), 100)
        }
        return stressScore
    }

    /// Displayed dial value: live/latest reading on Today (`dayOffset == 0`), daily average on past days (`dayOffset > 0`).
    var displayStressScore: Int {
        if dayOffset == 0 && !stressSamplesToday.isEmpty {
            return currentStressScore
        }
        return stressAvg ?? stressScore
    }

    var stressMax: Int? {
        let vals = stressSamplesToday.map(\.value)
        return vals.max().map { Int($0.rounded()) }
    }
    var stressMin: Int? {
        let vals = stressSamplesToday.map(\.value)
        return vals.min().map { Int($0.rounded()) }
    }
    var stressAvg: Int? {
        let vals = stressSamplesToday.map(\.value)
        if !vals.isEmpty {
            return Int((vals.reduce(0, +) / Double(vals.count)).rounded())
        }
        return currentDaySummary?.stressScore
    }
    var lastStressSampleTimeLabel: String? {
        guard let last = stressSamplesToday.last else { return nil }
        return String(format: "%02d:%02d", (last.minuteOfDay / 60) % 24, last.minuteOfDay % 60)
    }

    var stressStatusLabel: String {
        guard dataAvailability.hasStressData else { return "Sin datos" }
        let s = displayStressScore
        if s < 30 { return "Bajo" }
        if s < 60 { return "Moderado" }
        return "Alto"
    }

    var latestVo2MaxRecord: (value: Double, dateIso: String)? {
        if let today = currentDaySummary?.vo2MaxMlKgMin { return (today, selectedDateIso) }
        return activeHistory.values
            .filter { $0.dateIso <= selectedDateIso && $0.vo2MaxMlKgMin != nil }
            .sorted { $0.dateIso < $1.dateIso }
            .last
            .flatMap { d in d.vo2MaxMlKgMin.map { ($0, d.dateIso) } }
    }

    var latestHrRecoveryRecord: (value: Double, dateIso: String)? {
        if let today = currentDaySummary?.hrRecoveryBpm { return (today, selectedDateIso) }
        return activeHistory.values
            .filter { $0.dateIso <= selectedDateIso && $0.hrRecoveryBpm != nil }
            .sorted { $0.dateIso < $1.dateIso }
            .last
            .flatMap { d in d.hrRecoveryBpm.map { ($0, d.dateIso) } }
    }

    func trainingLoadAnalysis(tab: TrainingLoadTab, spanDays: Int = 30, windowPageOffset: Int = 0) -> TrainingLoadAnalysis {
        WhoopPhysiologyEngine.computeTrainingLoadAnalysis(
            tab: tab,
            history: activeHistory,
            strengthLogs: strengthLogs,
            anchorDate: selectedDate,
            spanDays: spanDays,
            windowPageOffset: windowPageOffset
        )
    }

    func muscleGroupSnapshots(for date: Date? = nil) -> [MuscleGroupSnapshot] {
        WhoopPhysiologyEngine.computeMuscleGroupSnapshots(
            history: activeHistory,
            strengthLogs: strengthLogs,
            anchorDate: date ?? selectedDate
        )
    }

    func toggleRoutinePin(_ id: String) {
        if let idx = workoutRoutines.firstIndex(where: { $0.id == id }) {
            workoutRoutines[idx].isPinned.toggle()
            persistState()
        }
    }

    func saveRoutine(_ routine: WorkoutRoutineTemplate) {
        if let idx = workoutRoutines.firstIndex(where: { $0.id == routine.id }) {
            workoutRoutines[idx] = routine
        } else {
            workoutRoutines.insert(routine, at: 0)
        }
        persistState()
    }

    func deleteRoutine(_ id: String) {
        workoutRoutines.removeAll { $0.id == id }
        persistState()
    }

    func logCompletedStrengthSession(
        title: String,
        durationMin: Int,
        kcal: Int,
        sets: [StrengthLoggedSet]
    ) {
        let completedOnly = sets.filter(\.completed)
        for s in completedOnly {
            strengthLogs.append(s)
        }
        let totalSets = completedOnly.count
        let totalVol = completedOnly.reduce(0.0) { $0 + Double($1.reps) * $1.weightKg }
        let muscleNames = Array(Set(completedOnly.flatMap { $0.primaryMuscles.map(\.rawValue) }))
        let estKcal = kcal > 0 ? kcal : max(durationMin * 5, totalSets * 12)
        let ws = WhoopPhysiologyEngine.computeWorkoutStrain(
            durationMin: max(durationMin, 5),
            kcal: estKcal,
            avgHrBpm: 0,
            rhrBpm: restingHrBpm > 30 ? restingHrBpm : 55.0,
            maxHrBpm: Double(WhoopPhysiologyEngine.computeMaxHeartRate(profile: userProfile)),
            banisterB: userProfile.sex.banisterB
        )
        let nowFmt = DateFormatter()
        nowFmt.dateFormat = "HH:mm"
        let endStr = nowFmt.string(from: Date())
        let startStr = nowFmt.string(from: Date().addingTimeInterval(-Double(max(durationMin, 5) * 60)))

        var d = currentDaySummary ?? RealBiometricDaySummary(dateIso: selectedDateIso)
        let ev = EffortEventItem(
            id: UUID().uuidString,
            title: title,
            timeRange: "\(startStr) - \(endStr)",
            durationMin: max(durationMin, 5),
            avgHrBpm: 0,
            strainScore: ws.strain21,
            strainPct: ws.strainPct,
            categoryLabel: "Fuerza",
            kcal: estKcal,
            distanceKm: nil,
            elevationM: nil,
            dateIso: selectedDateIso,
            startEpochSec: Int64(Date().timeIntervalSince1970) - Int64(max(durationMin, 5) * 60),
            totalSets: totalSets > 0 ? totalSets : nil,
            totalVolumeKg: totalVol > 0 ? AppleHealthExportImporter.round1(totalVol) : nil,
            targetMuscles: muscleNames.isEmpty ? nil : muscleNames
        )
        d.workouts.insert(ev, at: 0)
        d.strengthMinutes += max(durationMin, 5)
        if hasImportedOrPairedRealData {
            realHistory[selectedDateIso] = d
        } else {
            simulatedHistory[selectedDateIso] = d
        }
        dataRevision += 1
        persistState()
    }

    var energyPercent: Int { currentDaySummary?.energyBankPercent ?? 0 }
    var stepsCount: Int? { currentDaySummary?.stepsCount }
    var vo2Max: Double? { currentDaySummary?.vo2MaxMlKgMin }
    var latestVo2Max: Double? {
        if let today = currentDaySummary?.vo2MaxMlKgMin { return today }
        return activeHistory.values
            .filter { $0.dateIso <= selectedDateIso && $0.vo2MaxMlKgMin != nil }
            .sorted { $0.dateIso < $1.dateIso }
            .last?.vo2MaxMlKgMin
    }
    var latestHrRecoveryBpm: Double? {
        if let today = currentDaySummary?.hrRecoveryBpm { return today }
        return activeHistory.values
            .filter { $0.dateIso <= selectedDateIso && $0.hrRecoveryBpm != nil }
            .sorted { $0.dateIso < $1.dateIso }
            .last?.hrRecoveryBpm
    }
    var latestBodyWeightKg: Double? {
        if let w = currentDaySummary?.bodyWeightKg { return w }
        return activeHistory.values
            .filter { $0.dateIso <= selectedDateIso && $0.bodyWeightKg != nil }
            .sorted { $0.dateIso < $1.dateIso }
            .last?.bodyWeightKg
    }
    var latestBodyFatPct: Double? {
        if let v = currentDaySummary?.bodyFatPct { return v }
        return activeHistory.values
            .filter { $0.dateIso <= selectedDateIso && $0.bodyFatPct != nil }
            .sorted { $0.dateIso < $1.dateIso }
            .last?.bodyFatPct
    }
    var latestLeanMassKg: Double? {
        if let v = currentDaySummary?.leanMassKg { return v }
        return activeHistory.values
            .filter { $0.dateIso <= selectedDateIso && $0.leanMassKg != nil }
            .sorted { $0.dateIso < $1.dateIso }
            .last?.leanMassKg
    }
    var latestBloodPressure: (sys: Int, dia: Int)? {
        if let s = currentDaySummary?.systolicBp, let d = currentDaySummary?.diastolicBp { return (s, d) }
        if let rec = activeHistory.values
            .filter({ $0.dateIso <= selectedDateIso && $0.systolicBp != nil && $0.diastolicBp != nil })
            .sorted(by: { $0.dateIso < $1.dateIso })
            .last,
           let s = rec.systolicBp, let d = rec.diastolicBp {
            return (s, d)
        }
        return nil
    }
    var cgmMgDl: Int? { currentDaySummary?.glucoseMgDl }
    var workoutsToday: [EffortEventItem] { currentDaySummary?.workouts ?? [] }
    var mealsToday: [NutritionMealItem] { mealsByDate[selectedDateIso] ?? [] }
    var totalProteinToday: Int {
        mealsToday.reduce(0) { $0 + $1.proteinG } + Int(manualNutrientAmount(for: "Proteína").rounded())
    }
    var totalCarbsToday: Int {
        mealsToday.reduce(0) { $0 + $1.carbsG } + Int(manualNutrientAmount(for: "Carbohidratos").rounded())
    }
    var totalFatToday: Int {
        mealsToday.reduce(0) { $0 + $1.fatG } + Int(manualNutrientAmount(for: "Grasas").rounded())
    }
    var totalCaloriesToday: Int {
        let mealKcal = mealsToday.reduce(0) { $0 + $1.kcal }
        let extraMacroKcal = manualNutrientAmount(for: "Proteína") * 4.0
            + manualNutrientAmount(for: "Carbohidratos") * 4.0
            + manualNutrientAmount(for: "Grasas") * 9.0
        return mealKcal + Int(extraMacroKcal.rounded())
    }
    var totalHydrationTodayMl: Double {
        manualNutrientAmount(for: "Hidratación")
    }
    var totalCaffeineTodayMg: Double {
        mealsToday.compactMap(\.caffeineMg).reduce(0, +) + manualNutrientAmount(for: "Cafeína")
    }
    var totalAlcoholTodayDrinks: Double {
        mealsToday.compactMap(\.alcoholDrinks).reduce(0, +) + manualNutrientAmount(for: "Alcohol")
    }
    var totalCalciumTodayMg: Double {
        mealsToday.compactMap(\.calciumMg).reduce(0, +) + manualNutrientAmount(for: "Calcio")
    }
    var foodQualityScore: Int? {
        nutritionScore(for: selectedDateIso)
    }

    var effectiveNutritionGoals: (kcal: Int, fatG: Int, carbsG: Int, proteinG: Int) {
        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: userProfile)
        return (
            kcal: customNutritionGoals.caloriesKcal ?? norms.maintenanceCaloriesKcal,
            fatG: customNutritionGoals.fatG ?? norms.fatGoalG,
            carbsG: customNutritionGoals.carbsG ?? norms.carbsGoalG,
            proteinG: customNutritionGoals.proteinG ?? norms.proteinGoalG
        )
    }

    var savedFoodsCounts: (favorites: Int, recipes: Int, meals: Int) {
        let favs = savedFoodsLibrary.filter { $0.kind == .favorite }.count
        let recs = savedFoodsLibrary.filter { $0.kind == .recipe }.count
        let mls = savedFoodsLibrary.filter { $0.kind == .meal }.count
        return (favs, recs, mls)
    }

    func nutritionScore(for dateIso: String) -> Int? {
        let meals = mealsByDate[dateIso] ?? []
        guard !meals.isEmpty else { return nil }
        let totalKcal = max(meals.reduce(0) { $0 + max($1.kcal, 50) }, 1)
        let weighted = meals.reduce(0.0) { acc, m in
            acc + Double(m.qualityScore) * Double(max(m.kcal, 50))
        }
        return min(max(Int((weighted / Double(totalKcal)).rounded()), 1), 100)
    }

    func nutritionScoreStatus(for score: Int?) -> (label: String, color: Color) {
        guard let s = score else { return ("sin datos", BevelColors.textMuted) }
        if s >= 80 { return ("excelente", BevelColors.greenPrimary) }
        if s >= 60 { return ("bueno", Color(hex: 0x60A5FA)) }
        if s >= 40 { return ("aceptable", Color(hex: 0x8BA0FF)) }
        return ("mejorable", BevelColors.amberStart)
    }

    func nutritionDayTotals(for dateIso: String) -> (kcal: Int, fatG: Double, carbsG: Double, proteinG: Double, score: Int?, mealCount: Int) {
        let meals = mealsByDate[dateIso] ?? []
        let extraP = manualNutrientAmount(for: "Proteína", dateIso: dateIso)
        let extraC = manualNutrientAmount(for: "Carbohidratos", dateIso: dateIso)
        let extraF = manualNutrientAmount(for: "Grasas", dateIso: dateIso)
        let p = Double(meals.reduce(0) { $0 + $1.proteinG }) + extraP
        let c = Double(meals.reduce(0) { $0 + $1.carbsG }) + extraC
        let f = Double(meals.reduce(0) { $0 + $1.fatG }) + extraF
        let mealKcal = meals.reduce(0) { $0 + $1.kcal }
        let kcal = mealKcal + Int((extraP * 4.0 + extraC * 4.0 + extraF * 9.0).rounded())
        return (kcal, f, c, p, nutritionScore(for: dateIso), meals.count)
    }

    func burnedCalories(for dateIso: String) -> Int {
        let bmr = WhoopPhysiologyEngine.computeBmrKcalPerDay(profile: userProfile)
        guard let d = activeHistory[dateIso] else { return bmr }
        if let active = d.activeKcal, active > 0 {
            return bmr + active
        }
        let wkKcal = d.workouts.reduce(0) { $0 + $1.kcal }
        return bmr + wkKcal
    }

    func netEnergyKcal(for dateIso: String) -> (net: Int, consumed: Int, burned: Int) {
        let consumed = nutritionDayTotals(for: dateIso).kcal
        let burned = burnedCalories(for: dateIso)
        return (consumed - burned, consumed, burned)
    }

    func dailyFoodQualityFactors(for dateIso: String) -> NutritionQualityFactors {
        let meals = mealsByDate[dateIso] ?? []
        var total = NutritionQualityFactors()
        for meal in meals {
            let f = meal.qualityFactors ?? GeminiCoachService.inferQualityFactors(
                title: meal.title,
                qualityScore: meal.qualityScore,
                alcoholDrinks: meal.alcoholDrinks ?? 0
            )
            total = total + f
        }
        let manualAlc = manualNutrientAmount(for: "Alcohol", dateIso: dateIso)
        if manualAlc > 0 {
            total.alcohol -= manualAlc * 4.0
        }
        return total
    }

    func updateNutritionGoals(_ goals: CustomNutritionGoals) {
        customNutritionGoals = goals
        dataRevision += 1
        persistState()
    }

    func saveFoodToLibrary(_ item: SavedFoodLibraryItem) {
        if let idx = savedFoodsLibrary.firstIndex(where: { $0.id == item.id }) {
            savedFoodsLibrary[idx] = item
        } else {
            savedFoodsLibrary.insert(item, at: 0)
        }
        persistState()
    }

    func removeFoodFromLibrary(id: String) {
        savedFoodsLibrary.removeAll { $0.id == id }
        persistState()
    }

    func toggleMealFavorite(_ meal: NutritionMealItem) {
        var updated = meal
        updated.isFavorite.toggle()
        saveMeal(updated)
        if updated.isFavorite {
            let libItem = SavedFoodLibraryItem(
                id: "fav_\(updated.id)",
                kind: .favorite,
                emoji: updated.emoji ?? GeminiCoachService.inferEmoji(forTitle: updated.title),
                title: updated.title,
                kcal: updated.kcal,
                proteinG: updated.proteinG,
                carbsG: updated.carbsG,
                fatG: updated.fatG,
                qualityScore: updated.qualityScore,
                caffeineMg: updated.caffeineMg,
                alcoholDrinks: updated.alcoholDrinks,
                calciumMg: updated.calciumMg,
                qualityFactors: updated.qualityFactors
            )
            saveFoodToLibrary(libItem)
        } else {
            removeFoodFromLibrary(id: "fav_\(updated.id)")
        }
    }

    func logLibraryFoodToday(_ item: SavedFoodLibraryItem) {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        let meal = NutritionMealItem(
            id: UUID().uuidString,
            title: item.title,
            timeLabel: fmt.string(from: Date()),
            kcal: item.kcal,
            proteinG: item.proteinG,
            carbsG: item.carbsG,
            fatG: item.fatG,
            qualityScore: item.qualityScore,
            caffeineMg: item.caffeineMg,
            alcoholDrinks: item.alcoholDrinks,
            calciumMg: item.calciumMg,
            emoji: item.emoji,
            qualityFactors: item.qualityFactors,
            isFavorite: item.kind == .favorite
        )
        saveMeal(meal)
    }

    var sleepDurationText: String {
        guard let m = currentDaySummary?.asleepMinutes, m > 0 else { return "--" }
        return "\(m / 60) h \(String(format: "%02d", m % 60)) min"
    }

    var sleepInBedText: String {
        guard let m = currentDaySummary?.inBedMinutes, m > 0 else { return "--" }
        return "\(m / 60) h \(String(format: "%02d", m % 60)) min"
    }

    var sleepWindowMinutes: ClosedRange<Int>? {
        guard let sess = currentDaySummary?.sleepSession,
              let sStr = sess.startTimeLabel,
              let eStr = sess.endTimeLabel else { return nil }
        let parseMin: (String) -> Int? = { txt in
            let parts = txt.split(separator: ":")
            guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
            return h * 60 + m
        }
        guard let sm = parseMin(sStr), let em = parseMin(eStr) else { return nil }
        let clampedStart = sm > em ? 0 : sm
        return clampedStart...max(em, clampedStart + 30)
    }

    /// Computes real average bedtime / wind-down / wake time from the user's last 30 days of actual sleep sessions (nil if no sleep data!).
    var realSleepScheduleLabels: (windDown: String, bedtime: String, wakeTime: String)? {
        let recent = trailingCalendarSummaries(days: 30)
        var bedMins: [Int] = []
        var wakeMins: [Int] = []
        let parseMin: (String) -> Int? = { txt in
            let parts = txt.split(separator: ":")
            guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
            return h * 60 + m
        }
        for item in recent {
            guard let sess = item.summary?.sleepSession else { continue }
            if let s = sess.startTimeLabel.flatMap(parseMin) {
                // Shift early-morning bedtimes (00:00..08:00) past 24:00 for circular averaging around midnight
                bedMins.append(s < 480 ? s + 1440 : s)
            }
            if let e = sess.endTimeLabel.flatMap(parseMin) {
                wakeMins.append(e)
            }
        }
        guard !bedMins.isEmpty, !wakeMins.isEmpty else { return nil }
        let avgBedRaw = Int((Double(bedMins.reduce(0, +)) / Double(bedMins.count)).rounded())
        let avgBed = ((avgBedRaw % 1440) + 1440) % 1440
        let avgWind = (((avgBedRaw - 30) % 1440) + 1440) % 1440
        let avgWake = Int((Double(wakeMins.reduce(0, +)) / Double(wakeMins.count)).rounded()) % 1440

        let fmt: (Int) -> String = { String(format: "%d:%02d", $0 / 60, $0 % 60) }
        return (fmt(avgWind), fmt(avgBed), fmt(avgWake))
    }

    var strainStatusText: String {
        guard dataAvailability.hasStrainData && strainPercent > 0 else { return "Sin esfuerzo" }
        let target = optimalEffortRange
        let frac = Double(strainPercent) / 100.0
        if frac > target.upperBound { return "Sobrecarga" }
        if strainPercent >= 75 { return "Alto" }
        if frac >= target.lowerBound { return "Óptimo" }
        if strainPercent < 15 { return "Ligero" }
        return "Moderado"
    }

    var recoveryStatusText: String {
        guard dataAvailability.hasRecoveryData else { return "Sin datos" }
        if recoveryPercent >= 67 { return "Óptima" }
        if recoveryPercent >= 34 { return "Moderada" }
        return "Baja"
    }

    var sleepStatusText: String {
        guard dataAvailability.hasSleepData else { return "Sin datos" }
        if sleepPercent >= 85 { return "Excelente" }
        if sleepPercent >= 70 { return "Normal" }
        return "Bajo"
    }

    var hasEverHadAnyRecordedData: Bool {
        !activeHistory.isEmpty
    }

    var optimalEffortRange: ClosedRange<Double> {
        let recBasis: Int = {
            if dataAvailability.hasRecoveryData { return recoveryPercent }
            if let recentRec = trailingCalendarSummaries(days: 7).compactMap({ $0.summary?.recoveryPct }).last {
                return recentRec
            }
            return 65
        }()
        return WhoopPhysiologyEngine.optimalTargetRange(
            for: recBasis,
            profile: userProfile
        )
    }

    var effortTargetRangeText: String {
        let r = optimalEffortRange
        return "\(Int((r.lowerBound * 100).rounded()))%–\(Int((r.upperBound * 100).rounded()))%"
    }

    // MARK: - 4-Hour Time-Aware Section Coaching Engine

    func currentFourHourBlockInfo(for date: Date = Date()) -> (blockIndex: Int, slotId: String, generatedAtLabel: String, nextUpdateLabel: String) {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        let minute = cal.component(.minute, from: date)
        let blockIdx = hour / 4 // 0..5 -> 00:00, 04:00, 08:00, 12:00, 16:00, 20:00
        let todayIso = isoFormatter.string(from: date)
        let generatedAt = String(format: "%02d:%02d", hour, minute)
        let nextHour = ((blockIdx + 1) * 4) % 24
        let nextUpdate = String(format: "%02d:00", nextHour)
        return (blockIdx, "\(todayIso)_b\(blockIdx)", generatedAt, nextUpdate)
    }

    func coachingSlotKey(for section: CoachingSection, now: Date = Date()) -> String {
        let info = currentFourHourBlockInfo(for: now)
        return "\(section.rawValue)_\(info.slotId)_\(selectedDateIso)_r\(dataRevision)"
    }

    func coachingCard(for section: CoachingSection) -> SectionCoachingCard? {
        sectionCoachingCache[coachingSlotKey(for: section)]
    }

    func isLoadingCoaching(for section: CoachingSection) -> Bool {
        loadingCoachingSections.contains(section)
    }

    private func buildSectionFacts(for section: CoachingSection) -> (facts: [String], hasData: Bool) {
        let av = dataAvailability
        let d = currentDaySummary
        var facts: [String] = []

        switch section {
        case .hoy:
            if av.hasRecoveryData { facts.append("Recuperación \(recoveryPercent)% (\(recoveryStatusText))") }
            if av.hasStrainData { facts.append("Esfuerzo \(strainPercent)% (Strain \(String(format: "%.1f", strain21))/21, objetivo \(effortTargetRangeText))") }
            if av.hasSleepData { facts.append("Sueño \(sleepDurationText) con puntuación \(sleepPercent)%") }
            if av.hasHrvData { facts.append(String(format: "VFC nocturna %.1f ms", locale: Locale(identifier: "es_ES"), hrvMs)) }
            if av.hasRestingHrData { facts.append(String(format: "FCR durmiendo %.1f ppm", locale: Locale(identifier: "es_ES"), restingHrBpm)) }
            if av.hasEnergyData { facts.append("Batería de energía al \(energyPercent)%") }
            if av.hasStressData {
                if dayOffset == 0 && !stressSamplesToday.isEmpty {
                    facts.append("Estrés actual \(currentStressScore)/100 (\(stressStatusLabel)) con media diaria \(stressAvg ?? stressScore)/100")
                } else {
                    facts.append("Estrés medio \(stressScore)/100 (\(stressStatusLabel))")
                }
            }
            if let steps = stepsCount { facts.append("\(steps) pasos acumulados") }
            return (facts, av.hasAnyRecordedData)

        case .esfuerzo:
            if av.hasStrainData { facts.append("Esfuerzo diario \(strainPercent)% (Strain \(String(format: "%.1f", strain21))/21, estado \(strainStatusText))") }
            if av.hasRecoveryData { facts.append("Rango objetivo óptimo según recuperación \(recoveryPercent)%: \(effortTargetRangeText)") }
            if let kcal = d?.activeKcal { facts.append("Calorías activas: \(kcal) kcal") }
            if let steps = stepsCount { facts.append("Pasos: \(steps)") }
            if let hr = liveHrBpm { facts.append("FC diurna media: \(hr) ppm") }
            if !workoutsToday.isEmpty {
                let wDesc = workoutsToday.map { w in
                    var s = "\(w.title) de \(w.durationMin) min (\(w.strainPct)% esfuerzo"
                    if w.kcal > 0 { s += ", \(w.kcal) kcal" }
                    if w.avgHrBpm > 0 { s += ", FC media \(w.avgHrBpm) ppm" }
                    s += ")"
                    return s
                }.joined(separator: "; ")
                facts.append("Entrenamientos: \(wDesc)")
            }
            let z = d?.hrZoneMinutes ?? []
            if z.reduce(0, +) > 0 {
                facts.append("Minutos por zonas de FC Z1-Z5: \(z.enumerated().map { "Z\($0.offset + 1) \($0.element)m" }.joined(separator: ", "))")
            }
            return (facts, av.hasStrainData || av.hasWorkoutData)

        case .recuperacion:
            if av.hasRecoveryData { facts.append("Recuperación \(recoveryPercent)% (\(recoveryStatusText))") }
            if av.hasHrvData {
                let recentHrv = trailingCalendarSummaries(days: 30).compactMap { $0.summary?.hrvMs }
                let avg30 = recentHrv.isEmpty ? nil : (recentHrv.reduce(0, +) / Double(recentHrv.count))
                if let a = avg30 {
                    facts.append(String(format: "VFC nocturna %.1f ms frente a tu media de 30 días de %.1f ms", locale: Locale(identifier: "es_ES"), hrvMs, a))
                } else {
                    facts.append(String(format: "VFC nocturna %.1f ms", locale: Locale(identifier: "es_ES"), hrvMs))
                }
            }
            if av.hasRestingHrData {
                let recentRhr = trailingCalendarSummaries(days: 30).compactMap { $0.summary?.restingHrBpm }
                let avg30 = recentRhr.isEmpty ? nil : (recentRhr.reduce(0, +) / Double(recentRhr.count))
                if let a = avg30 {
                    facts.append(String(format: "FC en reposo durmiendo %.1f ppm frente a tu media de 30 días de %.1f ppm", locale: Locale(identifier: "es_ES"), restingHrBpm, a))
                } else {
                    facts.append(String(format: "FC en reposo durmiendo %.1f ppm", locale: Locale(identifier: "es_ES"), restingHrBpm))
                }
            }
            if av.hasRespData { facts.append(String(format: "Frecuencia respiratoria %.1f rpm", locale: Locale(identifier: "es_ES"), respRateRpm)) }
            if let sp = spo2Value { facts.append(String(format: "SpO2 nocturna %.1f%%", locale: Locale(identifier: "es_ES"), sp)) }
            if let t = wristTempAbsoluteC {
                let dStr = d?.wristTempDeltaC.map { String(format: " (desviación %+.1f °C)", locale: Locale(identifier: "es_ES"), $0) } ?? ""
                facts.append(String(format: "Temperatura muñeca %.1f °C%@", locale: Locale(identifier: "es_ES"), t, dStr))
            }
            return (facts, av.hasRecoveryData || av.hasHrvData || av.hasRestingHrData)

        case .sueno:
            let sess = d?.sleepSession
            if av.hasSleepData { facts.append("Puntuación del sueño \(sleepPercent)% (\(sleepStatusText)), duración real dormida \(sleepDurationText)") }
            if let bed = d?.inBedMinutes, bed > 0 { facts.append("Tiempo en cama \(sleepInBedText)") }
            if let s = sess?.startTimeLabel, let e = sess?.endTimeLabel { facts.append("Horario real: acostado \(s) hasta despertar \(e)") }
            if let eff = sess?.efficiencyPct { facts.append("Eficiencia del sueño \(eff)%") }
            if let deep = d?.deepMinutes, deep > 0 { facts.append("Sueño profundo \(deep) min") }
            if let rem = d?.remMinutes, rem > 0 { facts.append("Sueño MOR \(rem) min") }
            if let lat = sess?.latencyMinutes { facts.append("Latencia para dormirse \(lat) min") }
            if let dip = sess?.hrDipPct { facts.append(String(format: "Disminución nocturna de FC %.1f%%", locale: Locale(identifier: "es_ES"), dip)) }
            if let debt = d?.sleepDebtMinutes, debt > 0 { facts.append("Deuda de sueño acumulada \(debt) min") }
            return (facts, av.hasSleepData)

        case .estres:
            let samples = stressSamplesToday
            if av.hasStressData {
                facts.append("Estrés actual \(displayStressScore)/100 (\(stressStatusLabel)), media diaria \(stressAvg ?? stressScore)/100 con \(samples.count) muestras reales")
            }
            if let mx = stressMax, let mn = stressMin { facts.append("Rango del día: mínimo \(mn) y pico máximo \(mx)") }
            if let peak = samples.max(by: { $0.value < $1.value }) {
                let hhmm = String(format: "%02d:%02d", (peak.minuteOfDay / 60) % 24, peak.minuteOfDay % 60)
                facts.append("Pico más alto alrededor de las \(hhmm) con \(Int(peak.value.rounded()))/100")
            }
            let stepMin = samples.count > 40 ? 5 : 60
            let highMin = samples.filter { $0.value >= 65 }.count * stepMin
            let lowMin = samples.filter { $0.value < 35 }.count * stepMin
            if !samples.isEmpty {
                facts.append("Tiempo en estrés alto: \(highMin) min; en estrés bajo: \(lowMin / 60) h \(lowMin % 60) min")
            }
            return (facts, av.hasStressData)

        case .energia:
            let samples = energySamplesToday
            if av.hasEnergyData { facts.append("Nivel actual de batería de energía: \(energyPercent)%") }
            if let first = samples.first {
                let t = String(format: "%02d:%02d", (first.minuteOfDay / 60) % 24, first.minuteOfDay % 60)
                facts.append("Inicio continuo a las \(t) desde \(Int(first.value.rounded()))% heredado de la jornada previa")
            }
            if let peak = samples.max(by: { $0.value < $1.value }) {
                let t = String(format: "%02d:%02d", (peak.minuteOfDay / 60) % 24, peak.minuteOfDay % 60)
                facts.append("Pico de recarga de \(Int(peak.value.rounded()))% a las \(t)")
                if let first = samples.first, let last = samples.last {
                    let charged = max(Int((peak.value - first.value).rounded()), 0)
                    let drained = max(Int((peak.value - last.value).rounded()), 0)
                    facts.append("Balance del día: +\(charged)% cargado y -\(drained)% gastado")
                }
            }
            return (facts, av.hasEnergyData)

        case .fitness:
            let last30 = trailingCalendarSummaries(days: 30)
            let w30 = last30.flatMap { $0.summary?.workouts ?? [] }
            let last7 = trailingCalendarSummaries(days: 7)
            let strain7 = last7.compactMap { $0.summary?.strainPct }
            let strMin7 = last7.compactMap { $0.summary?.strengthMinutes }.reduce(0, +)
            if !w30.isEmpty {
                let mins30 = w30.reduce(0) { $0 + $1.durationMin }
                let kcal30 = w30.reduce(0) { $0 + $1.kcal }
                facts.append("Últimos 30 días: \(w30.count) sesiones, \(mins30 / 60) h \(mins30 % 60) min y \(kcal30) kcal")
            }
            if !strain7.isEmpty {
                let avg7 = Int((Double(strain7.reduce(0, +)) / Double(strain7.count)).rounded())
                facts.append("Esfuerzo medio 7 días: \(avg7)%; fuerza 7 días: \(strMin7) min")
            }
            if let vo2 = latestVo2Max { facts.append(String(format: "VO2 máx. %.1f mL/kg·min", locale: Locale(identifier: "es_ES"), vo2)) }
            if let hrr = latestHrRecoveryBpm { facts.append("Recuperación de FC 1 min: \(Int(hrr.rounded())) ppm") }
            if av.hasRecoveryData { facts.append("Recuperación actual para entrenar: \(recoveryPercent)%") }
            if !workoutsToday.isEmpty {
                facts.append("Entrenamientos hoy: \(workoutsToday.map { "\($0.title) \($0.durationMin)m" }.joined(separator: ", "))")
            }
            return (facts, !facts.isEmpty)
        }
    }

    func refreshCoachingIfNeeded(for section: CoachingSection, force: Bool = false) {
        let now = Date()
        let info = currentFourHourBlockInfo(for: now)
        let key = coachingSlotKey(for: section, now: now)
        if !force && sectionCoachingCache[key] != nil { return }

        coachingTasks[section]?.cancel()
        loadingCoachingSections.insert(section)

        let ctx = buildBiometricContextJson()
        let secFacts = buildSectionFacts(for: section)
        let missing = dataAvailability.missingCategoryNames
        let prevHead = lastHeadlineBySection[section] ?? sectionCoachingCache[key]?.headline
        let apiKey = geminiApiKey
        let model = selectedGeminiModel
        let userName = userProfile.userName
        let selIso = selectedDateIso
        let isToday = dayOffset == 0

        coachingTasks[section] = Task { [weak self] in
            let card = await GeminiCoachService.shared.generateSectionCoaching(
                section: section,
                currentDate: now,
                selectedDateIso: selIso,
                isViewingToday: isToday,
                userName: userName,
                biometricContextJson: ctx.json,
                sectionFacts: secFacts.facts,
                missingCategories: missing,
                previousHeadline: prevHead,
                hasSectionData: secFacts.hasData,
                slotKey: key,
                generatedAtLabel: info.generatedAtLabel,
                nextUpdateLabel: info.nextUpdateLabel,
                apiKey: apiKey,
                selectedModel: model
            )
            await MainActor.run {
                guard let self, !Task.isCancelled else { return }
                self.sectionCoachingCache[key] = card
                self.lastHeadlineBySection[section] = card.headline
                self.loadingCoachingSections.remove(section)
                // Keep cache bounded to latest 35 entries
                if self.sectionCoachingCache.count > 35 {
                    let dropKeys = self.sectionCoachingCache.keys.sorted().prefix(self.sectionCoachingCache.count - 35)
                    for k in dropKeys { self.sectionCoachingCache.removeValue(forKey: k) }
                }
                self.persistState()
            }
        }
    }

    // MARK: - Trailing Calendar Days Helper (Sparse, Zero-Fabrication!)

    func trailingCalendarSummaries(days: Int, endingAt endDate: Date? = nil) -> [(iso: String, summary: RealBiometricDaySummary?)] {
        let anchor = Calendar.current.startOfDay(for: endDate ?? selectedDate)
        return (0..<days).reversed().compactMap { back in
            guard let d = Calendar.current.date(byAdding: .day, value: -back, to: anchor) else { return nil }
            let iso = isoFormatter.string(from: d)
            return (iso, activeHistory[iso])
        }
    }

    private func buildTrendItem(
        id: String,
        title: String,
        currentValue: Double?,
        valueFormatter: (Double) -> String,
        unitText: String,
        series: [Double?],
        bandLow: Double,
        bandHigh: Double,
        lineColorHex: UInt64,
        detailNote: String
    ) -> EffortTrendItem {
        let realVals = series.compactMap { $0 }
        guard let cur = currentValue else {
            return EffortTrendItem(
                id: id,
                title: title,
                valueText: "No hay datos",
                unitText: "",
                statusText: "No hay tendencias disponibles",
                statusTone: .noData,
                points: series,
                bandLow: bandLow,
                bandHigh: bandHigh,
                lineColorHex: lineColorHex,
                detailNote: detailNote,
                hasData: false
            )
        }
        let tone: TrendStatusTone
        let status: String
        if realVals.count < 2 {
            tone = .normal
            status = "Dato registrado"
        } else if cur < bandLow {
            tone = .below
            status = "Debajo de lo normal"
        } else if cur > bandHigh {
            tone = .above
            status = "Por encima de lo normal"
        } else {
            tone = .normal
            status = "Rango normal"
        }
        return EffortTrendItem(
            id: id,
            title: title,
            valueText: valueFormatter(cur),
            unitText: unitText,
            statusText: status,
            statusTone: tone,
            points: series,
            bandLow: bandLow,
            bandHigh: bandHigh,
            lineColorHex: lineColorHex,
            detailNote: detailNote,
            hasData: true
        )
    }

    var effortTrends: [EffortTrendItem] {
        let window = trailingCalendarSummaries(days: 14)
        let bmr = Double(WhoopPhysiologyEngine.computeBmrKcalPerDay(profile: userProfile))
        let workoutMinToday: Double? = workoutsToday.isEmpty ? nil : Double(workoutsToday.reduce(0) { $0 + $1.durationMin })
        let totalEnergyToday: Double? = currentDaySummary?.activeKcal.map { Double($0) + bmr }
        let perfDeltaToday: Double? = (currentDaySummary?.strainPct != nil && currentDaySummary?.recoveryPct != nil)
            ? Double(strainPercent) - (optimalEffortRange.lowerBound * 100.0 + optimalEffortRange.upperBound * 100.0) / 2.0
            : nil

        return [
            buildTrendItem(
                id: "t_strain", title: "Puntuación del Esfuerzo",
                currentValue: currentDaySummary?.strainPct.map { Double($0) },
                valueFormatter: { "\(Int($0.rounded()))" }, unitText: "%",
                series: window.map { $0.summary?.strainPct.map { Double($0) } },
                bandLow: 45, bandHigh: 84, lineColorHex: 0xF5B942,
                detailNote: "Evolución de tu esfuerzo cardiovascular y muscular diario."
            ),
            buildTrendItem(
                id: "t_dur", title: "Duración del ejercicio",
                currentValue: workoutMinToday,
                valueFormatter: { "\(Int($0.rounded()))" }, unitText: "min",
                series: window.map { item in
                    guard let ws = item.summary?.workouts, !ws.isEmpty else { return nil }
                    return Double(ws.reduce(0) { $0 + $1.durationMin })
                },
                bandLow: 25, bandHigh: 90, lineColorHex: 0xEC7D42,
                detailNote: "Minutos activos acumulados en tus sesiones."
            ),
            buildTrendItem(
                id: "t_day_hr", title: "FC diurna",
                currentValue: liveHrBpm.map { Double($0) },
                valueFormatter: { "\(Int($0.rounded()))" }, unitText: "ppm",
                series: window.map { $0.summary?.liveHrBpm.map { Double($0) } },
                bandLow: 55, bandHigh: 78, lineColorHex: 0xEC7D42,
                detailNote: "Frecuencia cardíaca media durante tus horas de vigilia."
            ),
            buildTrendItem(
                id: "t_kcal", title: "Energía total",
                currentValue: totalEnergyToday,
                valueFormatter: { "\(Int($0.rounded()))" }, unitText: "kcal",
                series: window.map { $0.summary?.activeKcal.map { Double($0) + bmr } },
                bandLow: bmr + 300, bandHigh: bmr + 1100, lineColorHex: 0xEC7D42,
                detailNote: "Suma de metabolismo basal y energía activa registrada."
            ),
            buildTrendItem(
                id: "t_steps", title: "Número de pasos",
                currentValue: stepsCount.map { Double($0) },
                valueFormatter: { "\(Int($0.rounded()))" }, unitText: "",
                series: window.map { $0.summary?.stepsCount.map { Double($0) } },
                bandLow: 7000, bandHigh: 13000, lineColorHex: 0xEC7D42,
                detailNote: "Pasos reales acumulados diariamente."
            ),
            buildTrendItem(
                id: "t_perf", title: "Rendimiento del Esfuerzo",
                currentValue: perfDeltaToday,
                valueFormatter: { String(format: "%+.0f", $0) }, unitText: "%",
                series: window.map { item in
                    guard let st = item.summary?.strainPct, let rec = item.summary?.recoveryPct else { return nil }
                    let r = WhoopPhysiologyEngine.optimalTargetRange(for: rec)
                    return Double(st) - (r.lowerBound + r.upperBound) * 50.0
                },
                bandLow: -12, bandHigh: 14, lineColorHex: 0x7FA8F8,
                detailNote: "Desviación frente a tu zona óptima según recuperación."
            )
        ]
    }

    /// Returns Bevel-style 60-day personal normal range for a Health Monitor vital (falling back to clinical
    /// age/sex/height/weight norms when fewer than 5 real readings exist in the trailing 60-day window).
    func personalVitalNormalBand(for kind: HealthMetricKind) -> (low: Double, high: Double, isPersonal: Bool) {
        let window60 = trailingCalendarSummaries(days: 60)
        let extractor: (RealBiometricDaySummary) -> Double? = { d in
            switch kind {
            case .respiratoryRate: return d.respRateRpm
            case .restingHeartRate: return d.restingHrBpm
            case .hrv: return d.hrvMs
            case .oxygenSaturation: return d.spo2Percent
            case .wristTemperature:
                return d.wristTempAbsoluteC ?? d.wristTempDeltaC.map { AppleHealthExportImporter.round1(35.8 + $0) }
            case .sleepDuration:
                return d.asleepMinutes.map { Double($0) / 60.0 }
            }
        }
        // Prefer strictly prior days when >= 7 prior days exist so today's anomaly doesn't mask itself
        let priorOnly = window60.dropLast().compactMap { $0.summary.flatMap(extractor) }
        let pool = priorOnly.count >= 7 ? priorOnly : window60.compactMap { $0.summary.flatMap(extractor) }
        return WhoopPhysiologyEngine.computePersonalVitalNormalBand(
            kind: kind,
            trailingValues: pool,
            profile: userProfile
        )
    }

    var recoveryTrends: [EffortTrendItem] {
        let window = trailingCalendarSummaries(days: 14)
        let hrvBand = personalVitalNormalBand(for: .hrv)
        let rhrBand = personalVitalNormalBand(for: .restingHeartRate)
        let respBand = personalVitalNormalBand(for: .respiratoryRate)
        let spo2Band = personalVitalNormalBand(for: .oxygenSaturation)
        let tempBand = personalVitalNormalBand(for: .wristTemperature)
        return [
            buildTrendItem(
                id: "r_rec", title: "Puntuación de Recuperación",
                currentValue: currentDaySummary?.recoveryPct.map { Double($0) },
                valueFormatter: { "\(Int($0.rounded()))" }, unitText: "%",
                series: window.map { $0.summary?.recoveryPct.map { Double($0) } },
                bandLow: 55, bandHigh: 92, lineColorHex: 0x3BD671,
                detailNote: "Capacidad de tu sistema nervioso autónomo para asimilar carga."
            ),
            buildTrendItem(
                id: "r_hrv", title: "VFC en reposo",
                currentValue: currentDaySummary?.hrvMs,
                valueFormatter: { String(format: "%.1f", locale: Locale(identifier: "es_ES"), $0) }, unitText: "ms",
                series: window.map { $0.summary?.hrvMs },
                bandLow: hrvBand.low, bandHigh: hrvBand.high, lineColorHex: 0x3BD671,
                detailNote: "Variabilidad de la frecuencia cardíaca consolidada durante el sueño."
            ),
            buildTrendItem(
                id: "r_rhr", title: "FC en reposo",
                currentValue: currentDaySummary?.restingHrBpm,
                valueFormatter: { String(format: "%.1f", locale: Locale(identifier: "es_ES"), $0) }, unitText: "ppm",
                series: window.map { $0.summary?.restingHrBpm },
                bandLow: rhrBand.low, bandHigh: rhrBand.high, lineColorHex: 0x3BD671,
                detailNote: "Frecuencia cardíaca media sostenida durante el descanso nocturno."
            ),
            buildTrendItem(
                id: "r_resp", title: "Frecuencia respiratoria",
                currentValue: currentDaySummary?.respRateRpm,
                valueFormatter: { String(format: "%.1f", locale: Locale(identifier: "es_ES"), $0) }, unitText: "rpm",
                series: window.map { $0.summary?.respRateRpm },
                bandLow: respBand.low, bandHigh: respBand.high, lineColorHex: 0x3BD671,
                detailNote: "Respiraciones por minuto registradas durante el sueño."
            ),
            buildTrendItem(
                id: "r_spo2", title: "Saturación de oxígeno",
                currentValue: currentDaySummary?.spo2Percent,
                valueFormatter: { String(format: "%.1f", locale: Locale(identifier: "es_ES"), $0) }, unitText: "%",
                series: window.map { $0.summary?.spo2Percent },
                bandLow: spo2Band.low, bandHigh: spo2Band.high, lineColorHex: 0x3BD671,
                detailNote: "Porcentaje de saturación capilar periférica de oxígeno."
            ),
            buildTrendItem(
                id: "r_temp", title: "Temperatura de la muñeca",
                currentValue: wristTempAbsoluteC,
                valueFormatter: { String(format: "%.1f", locale: Locale(identifier: "es_ES"), $0) }, unitText: "°C",
                series: window.map { item in
                    item.summary?.wristTempAbsoluteC ?? item.summary?.wristTempDeltaC.map { 35.8 + $0 }
                },
                bandLow: tempBand.low, bandHigh: tempBand.high, lineColorHex: 0x3BD671,
                detailNote: "Temperatura media de la piel durante la noche anterior."
            )
        ]
    }

    var sleepTrends: [EffortTrendItem] {
        let window = trailingCalendarSummaries(days: 14)
        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: userProfile)
        let hmFmt: (Double) -> String = { mins in
            let m = Int(mins.rounded())
            return "\(m / 60) h \(m % 60) min"
        }
        return [
            buildTrendItem(
                id: "s_score", title: "Puntuación del Sueño",
                currentValue: currentDaySummary?.sleepPct.map { Double($0) },
                valueFormatter: { "\(Int($0.rounded()))" }, unitText: "%",
                series: window.map { $0.summary?.sleepPct.map { Double($0) } },
                bandLow: 75, bandHigh: 96, lineColorHex: 0xA78BFA,
                detailNote: "Puntuación combinada de duración, eficiencia y fases reparadoras."
            ),
            buildTrendItem(
                id: "s_dur", title: "Duración del sueño",
                currentValue: currentDaySummary?.asleepMinutes.map { Double($0) },
                valueFormatter: hmFmt, unitText: "",
                series: window.map { $0.summary?.asleepMinutes.map { Double($0) } },
                bandLow: norms.sleepLowHours * 60.0, bandHigh: norms.sleepHighHours * 60.0, lineColorHex: 0x93A8F8,
                detailNote: "Horas netas de sueño excluyendo despertares nocturnos."
            ),
            buildTrendItem(
                id: "s_rem", title: "Sueño MOR",
                currentValue: currentDaySummary?.remMinutes.flatMap { $0 > 0 ? Double($0) : nil },
                valueFormatter: hmFmt, unitText: "",
                series: window.map { $0.summary?.remMinutes.flatMap { $0 > 0 ? Double($0) : nil } },
                bandLow: 70, bandHigh: 130, lineColorHex: 0x93A8F8,
                detailNote: "Tiempo en fase de movimiento ocular rápido (REM)."
            ),
            buildTrendItem(
                id: "s_deep", title: "Sueño profundo",
                currentValue: currentDaySummary?.deepMinutes.flatMap { $0 > 0 ? Double($0) : nil },
                valueFormatter: hmFmt, unitText: "",
                series: window.map { $0.summary?.deepMinutes.flatMap { $0 > 0 ? Double($0) : nil } },
                bandLow: 55, bandHigh: 115, lineColorHex: 0x93A8F8,
                detailNote: "Sueño de ondas lentas restaurador."
            ),
            buildTrendItem(
                id: "s_dip", title: "Disminución de la FC",
                currentValue: currentDaySummary?.sleepSession?.hrDipPct,
                valueFormatter: { String(format: "%.0f", $0) }, unitText: "%",
                series: window.map { $0.summary?.sleepSession?.hrDipPct },
                bandLow: 10, bandHigh: 20, lineColorHex: 0x93A8F8,
                detailNote: "Descenso de la frecuencia cardíaca nocturna respecto al día."
            ),
            buildTrendItem(
                id: "s_eff", title: "Eficiencia del sueño",
                currentValue: currentDaySummary?.sleepSession?.efficiencyPct.map { Double($0) },
                valueFormatter: { "\(Int($0.rounded()))" }, unitText: "%",
                series: window.map { $0.summary?.sleepSession?.efficiencyPct.map { Double($0) } },
                bandLow: 85, bandHigh: 98, lineColorHex: 0x3BD671,
                detailNote: "Porcentaje del tiempo en cama que pasaste dormido."
            ),
            buildTrendItem(
                id: "s_lat", title: "Tiempo que tardas en dormirte",
                currentValue: currentDaySummary?.sleepSession?.latencyMinutes.map { Double($0) },
                valueFormatter: { "\(Int($0.rounded())) min" }, unitText: "",
                series: window.map { $0.summary?.sleepSession?.latencyMinutes.map { Double($0) } },
                bandLow: 5, bandHigh: 25, lineColorHex: 0x93A8F8,
                detailNote: "Latencia desde que te acuestas hasta conciliar el sueño."
            )
        ]
    }

    var stressTrends: [EffortTrendItem] {
        let window = trailingCalendarSummaries(days: 14)
        let sleepStressToday: Double? = {
            guard let sw = sleepWindowMinutes else { return nil }
            let vals = stressSamplesToday.filter { sw.contains($0.minuteOfDay) }.map(\.value)
            guard !vals.isEmpty else { return nil }
            return vals.reduce(0, +) / Double(vals.count)
        }()
        return [
            buildTrendItem(
                id: "st_score", title: "Puntuación del Estrés",
                currentValue: stressAvg.map { Double($0) },
                valueFormatter: { "\(Int($0.rounded()))" }, unitText: "",
                series: window.map { $0.summary?.stressScore.map { Double($0) } },
                bandLow: 15, bandHigh: 45, lineColorHex: 0x56D5C6,
                detailNote: "Nivel medio diario de estrés fisiológico."
            ),
            buildTrendItem(
                id: "st_sleep", title: "Estrés del sueño",
                currentValue: sleepStressToday,
                valueFormatter: { "\(Int($0.rounded()))" }, unitText: "",
                series: window.map { item in
                    guard let s = item.summary, !s.stressSamples5m.isEmpty else { return nil }
                    let night = s.stressSamples5m.filter { $0.minuteOfDay < 480 }.map(\.value)
                    guard !night.isEmpty else { return nil }
                    return night.reduce(0, +) / Double(night.count)
                },
                bandLow: 2, bandHigh: 18, lineColorHex: 0x56D5C6,
                detailNote: "Activación simpática durante tus horas de sueño."
            )
        ]
    }

    func trendExtractor(for trendId: String) -> (RealBiometricDaySummary) -> Double? {
        let bmr = Double(WhoopPhysiologyEngine.computeBmrKcalPerDay(profile: userProfile))
        switch trendId {
        case "t_strain":
            return { $0.strainPct.map { Double($0) } }
        case "t_dur":
            return { d in d.workouts.isEmpty ? nil : Double(d.workouts.reduce(0) { $0 + $1.durationMin }) }
        case "t_day_hr":
            return { $0.liveHrBpm.map { Double($0) } }
        case "t_kcal":
            return { $0.activeKcal.map { Double($0) + bmr } }
        case "t_steps":
            return { $0.stepsCount.map { Double($0) } }
        case "t_perf":
            return { d in
                guard let st = d.strainPct, let rec = d.recoveryPct else { return nil }
                let r = WhoopPhysiologyEngine.optimalTargetRange(for: rec)
                return Double(st) - (r.lowerBound + r.upperBound) * 50.0
            }
        case "r_rec":
            return { $0.recoveryPct.map { Double($0) } }
        case "r_hrv":
            return { $0.hrvMs }
        case "r_rhr":
            return { $0.restingHrBpm }
        case "r_resp":
            return { $0.respRateRpm }
        case "r_spo2":
            return { $0.spo2Percent }
        case "r_temp":
            return { $0.wristTempAbsoluteC ?? $0.wristTempDeltaC.map { AppleHealthExportImporter.round1(35.8 + $0) } }
        case "s_score":
            return { $0.sleepPct.map { Double($0) } }
        case "s_dur":
            return { $0.asleepMinutes.map { Double($0) } }
        case "s_rem":
            return { $0.remMinutes.flatMap { $0 > 0 ? Double($0) : nil } }
        case "s_deep":
            return { $0.deepMinutes.flatMap { $0 > 0 ? Double($0) : nil } }
        case "s_dip":
            return { $0.sleepSession?.hrDipPct }
        case "s_eff":
            return { $0.sleepSession?.efficiencyPct.map { Double($0) } }
        case "s_lat":
            return { $0.sleepSession?.latencyMinutes.map { Double($0) } }
        case "st_score":
            return { $0.stressScore.map { Double($0) } }
        case "st_sleep":
            return { d in
                guard !d.stressSamples5m.isEmpty else { return nil }
                let night = d.stressSamples5m.filter { $0.minuteOfDay < 480 }.map(\.value)
                guard !night.isEmpty else { return nil }
                return night.reduce(0, +) / Double(night.count)
            }
        default:
            return { $0.recoveryPct.map { Double($0) } }
        }
    }

    // MARK: - Paginated Time-Window Metric Series (7 d | 30 d | 3 M | 6 M | 1 A with < / > arrows!)

    func metricWindowSeries(
        for kind: HealthMetricKind,
        spanDays: Int,
        windowPageOffset: Int
    ) -> MetricWindowSeries {
        let cal = Calendar.current
        let anchorToday = cal.startOfDay(for: selectedDate)
        let endDate = cal.date(byAdding: .day, value: -(windowPageOffset * spanDays), to: anchorToday) ?? anchorToday
        let startDate = cal.date(byAdding: .day, value: -(spanDays - 1), to: endDate) ?? endDate

        let outFmt = DateFormatter()
        outFmt.locale = Locale(identifier: "es_ES")
        outFmt.dateFormat = spanDays >= 180 ? "MMM yy" : "d MMM"

        let rangeFmt = DateFormatter()
        rangeFmt.locale = Locale(identifier: "es_ES")
        rangeFmt.dateFormat = spanDays >= 180 ? "d MMM yyyy" : "d MMM"

        var labels: [String] = []
        var values: [Double?] = []
        var realPts: [Double] = []
        labels.reserveCapacity(spanDays)
        values.reserveCapacity(spanDays)

        for i in 0..<spanDays {
            guard let d = cal.date(byAdding: .day, value: i, to: startDate) else { continue }
            let iso = isoFormatter.string(from: d)
            let lbl = outFmt.string(from: d).replacingOccurrences(of: ".", with: "")
            labels.append(lbl)
            let summary = activeHistory[iso]
            let v: Double? = switch kind {
            case .respiratoryRate: summary?.respRateRpm
            case .restingHeartRate: summary?.restingHrBpm
            case .hrv: summary?.hrvMs
            case .oxygenSaturation: summary?.spo2Percent
            case .wristTemperature: summary?.wristTempAbsoluteC ?? summary?.wristTempDeltaC.map { AppleHealthExportImporter.round1(35.8 + $0) }
            case .sleepDuration: summary?.asleepMinutes.map { Double($0) / 60.0 }
            }
            values.append(v)
            if let v { realPts.append(v) }
        }

        let rangeLabel = "\(rangeFmt.string(from: startDate).replacingOccurrences(of: ".", with: "")) – \(rangeFmt.string(from: endDate).replacingOccurrences(of: ".", with: ""))"
        let earliestIso = activeHistory.keys.sorted().first ?? "2020-01-01"
        let earliestDt = isoFormatter.date(from: earliestIso) ?? earliestAvailableDate
        let canBack = startDate > earliestDt

        return MetricWindowSeries(
            dates: labels,
            values: values,
            realPoints: realPts,
            windowRangeLabel: rangeLabel,
            canStepForward: windowPageOffset > 0,
            canStepBackward: canBack
        )
    }

    func customWindowSeries(
        spanDays: Int,
        windowPageOffset: Int,
        extractor: (RealBiometricDaySummary) -> Double?
    ) -> MetricWindowSeries {
        let cal = Calendar.current
        let anchorToday = cal.startOfDay(for: selectedDate)
        let endDate = cal.date(byAdding: .day, value: -(windowPageOffset * spanDays), to: anchorToday) ?? anchorToday
        let startDate = cal.date(byAdding: .day, value: -(spanDays - 1), to: endDate) ?? endDate

        let outFmt = DateFormatter()
        outFmt.locale = Locale(identifier: "es_ES")
        outFmt.dateFormat = spanDays >= 180 ? "MMM yy" : "d MMM"
        let rangeFmt = DateFormatter()
        rangeFmt.locale = Locale(identifier: "es_ES")
        rangeFmt.dateFormat = spanDays >= 180 ? "d MMM yyyy" : "d MMM"

        var labels: [String] = []
        var values: [Double?] = []
        var realPts: [Double] = []
        for i in 0..<spanDays {
            guard let d = cal.date(byAdding: .day, value: i, to: startDate) else { continue }
            let iso = isoFormatter.string(from: d)
            labels.append(outFmt.string(from: d).replacingOccurrences(of: ".", with: ""))
            let v = activeHistory[iso].flatMap(extractor)
            values.append(v)
            if let v { realPts.append(v) }
        }
        let rangeLabel = "\(rangeFmt.string(from: startDate).replacingOccurrences(of: ".", with: "")) – \(rangeFmt.string(from: endDate).replacingOccurrences(of: ".", with: ""))"
        let earliestIso = activeHistory.keys.sorted().first ?? "2020-01-01"
        let earliestDt = isoFormatter.date(from: earliestIso) ?? earliestAvailableDate
        return MetricWindowSeries(
            dates: labels,
            values: values,
            realPoints: realPts,
            windowRangeLabel: rangeLabel,
            canStepForward: windowPageOffset > 0,
            canStepBackward: startDate > earliestDt
        )
    }

    // MARK: - Diario Completion (>= 20 Manual Items) & Strict 30-Day Real Insight Engine

    static let diarioRequiredManualCount: Int = 20
    static let diarioRequiredTrackingDays: Int = 30

    static let journalCatalog: [(id: String, emoji: String, title: String, isAuto: Bool)] = [
        // Manual daily & nightly habits (strictly ignoring .unset!)
        ("fish_oil", "💊", "Aceite de pescado", false),
        ("sexual_activity", "❣️", "Actividad sexual", false),
        ("alcohol", "🍷", "Alcohol", false),
        ("ashwagandha", "💊", "Ashwagandha", false),
        ("added_sugar", "🍬", "Azúcar añadido", false),
        ("caffeine", "☕", "Cafeína", false),
        ("creatine", "💊", "Creatina", false),
        ("turmeric", "🫚", "Cúrcuma", false),
        ("low_carb", "🥖", "Dieta baja en carbohidratos", false),
        ("keto", "🥑", "Dieta keto", false),
        ("illness", "😷", "Enfermedad", false),
        ("fever", "🤒", "Fiebre", false),
        ("physio", "🚶", "Fisioterapia", false),
        ("injury", "🩹", "Lesión", false),
        ("morning_sun", "☀️", "Luz del sol por la mañana", false),
        ("dairy", "🥛", "Lácteos", false),
        ("magnesium", "💊", "Magnesio", false),
        ("pain_meds", "℞", "Medicación para el dolor", false),
        ("probiotic", "🦠", "Probiótico", false),
        ("shared_bed", "🛏️", "Cama compartida", false),
        ("late_meal", "🍽️", "Comer tarde", false),
        ("device_bed", "📱", "Dispositivo en la cama", false),
        ("sleep_interrupt", "🥱", "Interrupción del sueño", false),
        ("reading_bed", "📖", "Lectura en la cama", false),
        // Automatic habits evaluated from real watch / Apple Health data
        ("a_noise", "🔊", "Ruido al dormir de 50+ dB", true),
        ("a_strength", "🏋️", "20+ minutos de fuerza", true),
        ("a_daylight", "☀️", "20+ minutos de luz natural", true),
        ("a_steps", "👟", "10.000+ pasos", true),
        ("a_cardio", "🏃", "20+ minutos de cardio", true),
        ("a_z2", "🟠", "30+ minutos en la zona 2", true),
        ("a_stress", "💢", "50+ puntuación del Estrés", true),
        ("a_strain", "😮‍💨", "Objetivo de Esfuerzo superado", true),
    ]

    static let manualHabitIds: [String] = journalCatalog.filter { !$0.isAuto }.map(\.id)

    var allCatalogAndCustomEntries: [(id: String, emoji: String, title: String, isAuto: Bool)] {
        let customTuples = customJournalHabits.map { (id: $0.id, emoji: $0.emoji, title: $0.title, isAuto: false) }
        return Self.journalCatalog + customTuples
    }

    var allTrackableManualHabitIds: [String] {
        Self.manualHabitIds + customJournalHabits.map(\.id)
    }

    var requiredManualCountForCompletion: Int {
        let visibleManualTriStates = allTrackableManualHabitIds.filter { !hiddenJournalHabitIds.contains($0) }.count
        let moodVisible = hiddenJournalHabitIds.contains("mood") ? 0 : 1
        let hydVisible = hiddenJournalHabitIds.contains("hydration") ? 0 : 1
        let totalVisibleSlots = max(visibleManualTriStates + moodVisible + hydVisible, 1)
        return min(Self.diarioRequiredManualCount, totalVisibleSlots)
    }

    /// Counts strictly MANUAL (non-automatic) Diario items completed on `dateIso` (tri-state ✓/✕ + mood + hydration).
    func manualCompletedCount(for dateIso: String) -> Int {
        let map = journalCheckinsByDate[dateIso] ?? [:]
        var count = 0
        for id in allTrackableManualHabitIds {
            if let st = map[id], st != .unset {
                count += 1
            }
        }
        if journalMoodByDate[dateIso] != nil { count += 1 }
        if (hydrationGlassesByDate[dateIso] ?? 0) > 0 || (manualNutrientsByDate[dateIso]?["hidratacion_extra_ml"] ?? 0) > 0 {
            count += 1
        }
        return count
    }

    /// A day receives the Diario checkmark badge when the user completes >= `requiredManualCountForCompletion` manual entries (20 by default, or all active habits if customized < 20).
    func isDiarioDayCompleted(for dateIso: String) -> Bool {
        manualCompletedCount(for: dateIso) >= requiredManualCountForCompletion
    }

    func hasAnyJournalActivity(for dateIso: String) -> Bool {
        if manualCompletedCount(for: dateIso) > 0 { return true }
        let note = (journalNotesByDate[dateIso] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return !note.isEmpty
    }

    /// Number of distinct dates on which the user has logged at least one manual Diario entry.
    var totalManualDiarioDaysLogged: Int {
        let validIds = allTrackableManualHabitIds
        var dates = Set<String>()
        for (iso, map) in journalCheckinsByDate {
            if validIds.contains(where: { (map[$0] ?? .unset) != .unset }) {
                dates.insert(iso)
            }
        }
        for iso in journalMoodByDate.keys { dates.insert(iso) }
        for (iso, g) in hydrationGlassesByDate where g > 0 { dates.insert(iso) }
        for (iso, n) in journalNotesByDate where !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { dates.insert(iso) }
        return dates.count
    }

    /// Calendar span (in days, inclusive) from the user's earliest manual Diario entry to `selectedDate`.
    var manualDiarioSpanDays: Int {
        let validIds = allTrackableManualHabitIds
        var earliestIso: String? = nil
        for (iso, map) in journalCheckinsByDate {
            if validIds.contains(where: { (map[$0] ?? .unset) != .unset }) {
                if earliestIso == nil || iso < earliestIso! { earliestIso = iso }
            }
        }
        for iso in journalMoodByDate.keys {
            if earliestIso == nil || iso < earliestIso! { earliestIso = iso }
        }
        guard let firstIso = earliestIso, let firstDate = isoFormatter.date(from: firstIso) else { return 0 }
        let cal = Calendar.current
        let diff = cal.dateComponents([.day], from: cal.startOfDay(for: firstDate), to: cal.startOfDay(for: selectedDate)).day ?? 0
        return max(diff + 1, 1)
    }

    func automaticHabitState(id: String, day: RealBiometricDaySummary?) -> JournalCheckState {
        guard let d = day else { return .unset }
        switch id {
        case "a_steps":
            guard let s = d.stepsCount else { return .unset }
            return s >= 10000 ? .yes : .no
        case "a_cardio":
            let cardioMin = d.workouts.filter { $0.categoryLabel != "Fuerza" }.reduce(0) { $0 + $1.durationMin }
            if d.workouts.isEmpty && d.activeKcal == nil && d.stepsCount == nil { return .unset }
            return cardioMin >= 20 ? .yes : .no
        case "a_strength":
            if d.workouts.isEmpty && d.strengthMinutes == 0 && d.activeKcal == nil && d.stepsCount == nil { return .unset }
            return d.strengthMinutes >= 20 ? .yes : .no
        case "a_daylight":
            guard let dl = d.daylightMinutes else { return .unset }
            return dl >= 20 ? .yes : .no
        case "a_z2":
            let totalZ = d.hrZoneMinutes.reduce(0, +)
            guard totalZ > 0 else { return .unset }
            return (d.hrZoneMinutes.count > 1 ? d.hrZoneMinutes[1] : 0) >= 30 ? .yes : .no
        case "a_stress":
            guard let st = d.stressScore else { return .unset }
            return st >= 50 ? .yes : .no
        case "a_strain":
            guard let st = d.strainPct, let rec = d.recoveryPct else { return .unset }
            let upper = WhoopPhysiologyEngine.optimalTargetRange(for: rec).upperBound * 100.0
            return Double(st) > upper ? .yes : .no
        case "a_noise":
            guard let n = d.sleepNoiseOver50Db else { return .unset }
            return n ? .yes : .no
        default:
            return .unset
        }
    }

    /// Strict 30-day real tracking engine for Diario ✨ Información:
    /// - If the user has NOT filled out the Diario form (0 manual entries logged), ZERO metrics are computed or unlocked!
    /// - Each habit requires at least 30 days of elapsed tracking (daysSpanCount >= 30 || loggedDaysCount >= 30) AND both ✓ and ✕ occurrences before computing impact %.
    func computeJournalImpacts(for target: JournalImpactTarget) -> [JournalHabitImpactItem] {
        let hasUserFilledForm = totalManualDiarioDaysLogged > 0
        let cal = Calendar.current
        let anchor = cal.startOfDay(for: selectedDate)
        var last90Isos: [String] = []
        last90Isos.reserveCapacity(90)
        for back in (0..<90).reversed() {
            if let d = cal.date(byAdding: .day, value: -back, to: anchor) {
                last90Isos.append(isoFormatter.string(from: d))
            }
        }

        var items: [JournalHabitImpactItem] = []
        for entry in allCatalogAndCustomEntries {
            var yesVals: [Double] = []
            var noVals: [Double] = []
            var firstLoggedIso: String? = nil
            var totalExplicitDays = 0

            for iso in last90Isos {
                let state: JournalCheckState
                if entry.isAuto {
                    guard hasUserFilledForm, let day = activeHistory[iso] else { continue }
                    state = automaticHabitState(id: entry.id, day: day)
                } else {
                    state = journalCheckinsByDate[iso]?[entry.id] ?? .unset
                }

                guard state != .unset else { continue }
                if firstLoggedIso == nil { firstLoggedIso = iso }
                totalExplicitDays += 1

                guard let day = activeHistory[iso] else { continue }
                let outcomeOpt: Int? = (target == .recovery) ? day.recoveryPct : day.sleepPct
                guard let outcome = outcomeOpt else { continue }

                if state == .yes { yesVals.append(Double(outcome)) }
                else if state == .no { noVals.append(Double(outcome)) }
            }

            let spanDays: Int = {
                guard let fIso = firstLoggedIso, let fDate = isoFormatter.date(from: fIso) else { return 0 }
                let d = cal.dateComponents([.day], from: cal.startOfDay(for: fDate), to: anchor).day ?? 0
                return max(d + 1, 1)
            }()

            let yCount = yesVals.count
            let nCount = noVals.count
            let reached30Days = hasUserFilledForm && (spanDays >= Self.diarioRequiredTrackingDays || totalExplicitDays >= Self.diarioRequiredTrackingDays)

            let tier: JournalReliabilityTier
            let impact: Int
            if reached30Days && yCount >= 5 && nCount >= 5 {
                tier = .high
                let meanY = yesVals.reduce(0, +) / Double(yCount)
                let meanN = noVals.reduce(0, +) / Double(nCount)
                impact = Int((meanY - meanN).rounded())
            } else if reached30Days && yCount >= 1 && nCount >= 1 {
                tier = .low
                let meanY = yesVals.reduce(0, +) / Double(yCount)
                let meanN = noVals.reduce(0, +) / Double(nCount)
                impact = Int((meanY - meanN).rounded())
            } else {
                tier = .locked
                impact = 0
            }

            items.append(JournalHabitImpactItem(
                id: entry.id,
                emoji: entry.emoji,
                title: entry.title,
                impactPct: impact,
                yesCount: yCount,
                noCount: nCount,
                loggedDaysCount: totalExplicitDays,
                daysSpanCount: spanDays,
                reliability: tier,
                isAutomatic: entry.isAuto
            ))
        }

        return items.sorted { a, b in
            if a.reliability != b.reliability {
                let rank: (JournalReliabilityTier) -> Int = { $0 == .high ? 0 : ($0 == .low ? 1 : 2) }
                return rank(a.reliability) < rank(b.reliability)
            }
            if a.reliability != .locked && abs(a.impactPct) != abs(b.impactPct) {
                return abs(a.impactPct) > abs(b.impactPct)
            }
            if a.isAutomatic != b.isAutomatic {
                return !a.isAutomatic // Show manual habits first when locked
            }
            return (a.yesCount + a.noCount) > (b.yesCount + b.noCount)
        }
    }

    // MARK: - User Actions & Date Selection

    func completeOnboarding(_ profile: UserPhysiologyProfile) {
        var p = profile
        p.onboardingCompleted = true
        p.profileSetupVersion = max(p.profileSetupVersion, 2)
        userProfile = p
        recomputeMetricsForCurrentProfile()
        persistState()
    }

    func replayOnboarding() {
        userProfile.onboardingCompleted = false
        persistState()
    }

    func updateProfile(_ profile: UserPhysiologyProfile) {
        var p = profile
        p.ageYears = p.effectiveAgeYears
        userProfile = p
        recomputeMetricsForCurrentProfile()
        persistState()
    }

    /// Recalculates Sleep Score, Sleep Debt, Recovery %, Strain % / Strain 21, Workout Strain,
    /// and Energy Bank across stored days immediately whenever age/birthDate, sex, height, or weight changes!
    func recomputeMetricsForCurrentProfile() {
        let profile = userProfile
        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: profile)
        let targetSleepMin = norms.sleepTargetHours * 60.0
        let maxHr = Double(norms.maxHrBpm)
        let respCenter = (norms.respLowRpm + norms.respHighRpm) / 2.0

        if !hasImportedOrPairedRealData {
            simulatedHistory = WhoopPhysiologyEngine.generateTwoYearSimulatedHistory(profile: profile)
        }

        if !realHistory.isEmpty {
            let sortedIsos = realHistory.keys.sorted()
            var priorLnHrv: [Double] = []
            var priorRhr: [Double] = []
            var priorResp: [Double] = []
            var updated: [String: RealBiometricDaySummary] = [:]
            updated.reserveCapacity(realHistory.count)

            for iso in sortedIsos {
                guard var day = realHistory[iso] else { continue }

                // 1. Age/Sex-calibrated Sleep Score & Sleep Debt
                if let asleep = day.asleepMinutes, asleep > 0 {
                    let awakeCnt = day.sleepSession?.stages.filter { $0.stage == .awake }.count ?? 0
                    day.sleepPct = WhoopPhysiologyEngine.computeBevelSleepScore(
                        asleepMinutes: asleep,
                        inBedMinutes: day.inBedMinutes,
                        deepMinutes: day.deepMinutes,
                        remMinutes: day.remMinutes,
                        awakeMinutes: day.awakeMinutes,
                        awakeCount: awakeCnt,
                        hrDipPct: day.sleepSession?.hrDipPct,
                        targetMinutes: targetSleepMin,
                        deepTargetPct: norms.deepTargetPct,
                        remTargetPct: norms.remTargetPct
                    )
                    day.sleepDebtMinutes = max(Int(targetSleepMin.rounded()) - asleep, 0)
                }

                // 2. Causal 60-day Recovery % with user's age/sex/body cohort calibration
                let lnHrvBase = WhoopPhysiologyEngine.computeRollingBaseline(
                    priorValues: priorLnHrv,
                    populationMean: log(max(norms.hrvExpectedMs, 15.0)),
                    populationSigma: 0.25,
                    floorSigma: 0.14
                )
                let rhrBase = WhoopPhysiologyEngine.computeRollingBaseline(
                    priorValues: priorRhr,
                    populationMean: norms.restingHrExpected,
                    populationSigma: 4.0,
                    floorSigma: 1.8
                )
                let respBase = WhoopPhysiologyEngine.computeRollingBaseline(
                    priorValues: priorResp,
                    populationMean: respCenter,
                    populationSigma: 0.9,
                    floorSigma: 0.45
                )

                if let newRec = WhoopPhysiologyEngine.computeBevelRecoveryPercent(
                    hrvMs: day.hrvMs,
                    rhrBpm: day.restingHrBpm,
                    respRpm: day.respRateRpm,
                    spo2Pct: day.spo2Percent,
                    wristTempDeltaC: day.wristTempDeltaC,
                    lnHrvBaseline: lnHrvBase,
                    rhrBaseline: rhrBase,
                    respBaseline: respBase,
                    profile: profile,
                    sleepPct: day.sleepPct
                ) {
                    day.recoveryPct = newRec
                }

                if let h = day.hrvMs, h > 2.0 { priorLnHrv.append(log(h)) }
                if let r = day.restingHrBpm { priorRhr.append(r) }
                if let rr = day.respRateRpm { priorResp.append(rr) }

                // 3. Age/Sex/Weight/Height-calibrated Workout & Daily Strain (Tanaka MaxHR + Banister B + Mifflin BMR)
                let rhrRef = day.restingHrBpm ?? rhrBase.mean
                if !day.workouts.isEmpty {
                    day.workouts = day.workouts.map { w in
                        let ws = WhoopPhysiologyEngine.computeWorkoutStrain(
                            durationMin: w.durationMin,
                            kcal: w.kcal,
                            avgHrBpm: w.avgHrBpm,
                            rhrBpm: rhrRef,
                            maxHrBpm: maxHr,
                            banisterB: profile.sex.banisterB
                        )
                        return EffortEventItem(
                            id: w.id,
                            title: w.title,
                            timeRange: w.timeRange,
                            durationMin: w.durationMin,
                            avgHrBpm: w.avgHrBpm,
                            strainScore: ws.strain21,
                            strainPct: ws.strainPct,
                            categoryLabel: w.categoryLabel,
                            kcal: w.kcal,
                            distanceKm: w.distanceKm,
                            elevationM: w.elevationM,
                            dateIso: w.dateIso,
                            startEpochSec: w.startEpochSec,
                            avgPowerW: w.avgPowerW,
                            avgCadenceRpm: w.avgCadenceRpm,
                            hrZoneMinutes6: w.hrZoneMinutes6,
                            hrRecovery1MinBpm: w.hrRecovery1MinBpm,
                            totalSets: w.totalSets,
                            totalVolumeKg: w.totalVolumeKg,
                            targetMuscles: w.targetMuscles
                        )
                    }
                }

                if let st = WhoopPhysiologyEngine.computeBevelStrain(
                    profile: profile,
                    rhrBpm: rhrRef,
                    hrZoneMinutes: day.hrZoneMinutes,
                    workouts: day.workouts,
                    activeKcal: day.activeKcal.map { Double($0) }
                ) {
                    day.strain21 = st.strain21
                    day.strainPct = st.strainPct
                }

                updated[iso] = day
            }
            recomputeContinuousEnergy(in: &updated)
            realHistory = updated
        }

        sectionCoachingCache.removeAll()
        dataRevision += 1
    }

    /// Re-integrates the continuous cross-day Body Battery timeline across all stored days
    /// (preserves exact midnight handoff, handles Apple Watch Low Power Mode sleep gaps, and eliminates stale curve seams).
    private func recomputeContinuousEnergy(in history: inout [String: RealBiometricDaySummary]) {
        let sortedIsos = history.keys.sorted()
        var prevDayDate: Date? = nil
        var prevDayEndEnergy: Double? = nil
        var prevDayEndEpoch: Int64? = nil
        let cal = Calendar.current

        for iso in sortedIsos {
            guard var day = history[iso] else { continue }
            let curDate = isoFormatter.date(from: iso)
            let dayStartEp: Int64? = curDate.map { Int64(cal.startOfDay(for: $0).timeIntervalSince1970) }
            let hasRealSleep = (day.sleepSession != nil) || ((day.asleepMinutes ?? 0) > 0)

            guard !day.stressSamples5m.isEmpty || hasRealSleep else {
                if let lastE = day.energySamples5m.last?.value ?? day.energyBankPercent.map({ Double($0) }) {
                    prevDayEndEnergy = lastE
                    prevDayEndEpoch = day.energySamples5m.last?.epochSec
                    prevDayDate = curDate
                }
                continue
            }

            let isContinuous: Bool = {
                guard let prevE = prevDayEndEnergy, let pDate = prevDayDate, let cDate = curDate, prevE.isFinite else { return false }
                let gapDays = cal.dateComponents([.day], from: pDate, to: cDate).day ?? 99
                guard gapDays == 1 else { return false }
                if let pEp = prevDayEndEpoch, let firstEp = day.stressSamples5m.first?.epochSec {
                    return (firstEp - pEp) <= 24 * 3600
                }
                return true
            }()

            let initialEnergy: Double = {
                if isContinuous, let carried = prevDayEndEnergy {
                    return carried
                }
                if hasRealSleep {
                    return Double(max(min((day.recoveryPct ?? day.sleepPct ?? 65) - 34, 48), 22))
                }
                return Double(max(min((day.recoveryPct ?? 65) - 24, 65), 22))
            }()

            let workoutSpans: [ClosedRange<Int64>] = day.workouts.compactMap { w in
                guard let s = w.startEpochSec, w.durationMin > 0 else { return nil }
                return s...(s + Int64(w.durationMin * 60))
            }

            let energy5m = AppleHealthExportImporter.buildContinuousFiveMinuteEnergySamples(
                stressSamples: day.stressSamples5m,
                startingEnergy: initialEnergy,
                recoveryPct: day.recoveryPct,
                sleepPct: day.sleepPct,
                sleepStartEpoch: day.sleepSession?.startEpochSec,
                sleepEndEpoch: day.sleepSession?.endEpochSec,
                workoutSpans: workoutSpans,
                asleepMinutes: day.asleepMinutes,
                dayStartEpoch: dayStartEp
            )

            if let lastE = energy5m.last {
                day.energySamples5m = energy5m
                day.energyBankPercent = Int(lastE.value.rounded())
                prevDayEndEnergy = lastE.value
                prevDayEndEpoch = lastE.epochSec
                prevDayDate = curDate
                history[iso] = day
            }
        }
    }

    func shiftDay(_ delta: Int) {
        dayOffset = max(dayOffset + delta, 0)
    }

    func selectDayOffset(_ offset: Int) {
        dayOffset = max(offset, 0)
    }

    func selectDate(_ date: Date) {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let targetStart = cal.startOfDay(for: date)
        let diff = cal.dateComponents([.day], from: targetStart, to: todayStart).day ?? 0
        dayOffset = max(diff, 0)
    }

    func setDarkMode(_ dark: Bool) {
        BevelColors.isDarkMode = dark
        objectWillChange.send()
        persistState()
    }

    func toggleTabVisibility(_ tab: MainTab) {
        if visibleTabs.contains(tab) && visibleTabs.count > 1 {
            visibleTabs.remove(tab)
        } else {
            visibleTabs.insert(tab)
        }
        persistState()
    }

    func setJournalCheck(habitId: String, state: JournalCheckState) {
        var map = journalCheckinsByDate[selectedDateIso] ?? [:]
        map[habitId] = state
        journalCheckinsByDate[selectedDateIso] = map
        persistState()
        if dayOffset == 0 {
            refreshSmartNotificationSchedules(promptPermission: false)
        }
    }

    func setJournalMood(_ mood: Int) {
        journalMoodByDate[selectedDateIso] = mood
        persistState()
        if dayOffset == 0 {
            refreshSmartNotificationSchedules(promptPermission: false)
        }
    }

    func isHabitHidden(_ id: String) -> Bool {
        hiddenJournalHabitIds.contains(id)
    }

    func toggleHabitHidden(_ id: String) {
        if hiddenJournalHabitIds.contains(id) {
            hiddenJournalHabitIds.remove(id)
        } else {
            hiddenJournalHabitIds.insert(id)
        }
        persistState()
    }

    func resetHiddenHabits() {
        hiddenJournalHabitIds.removeAll()
        persistState()
    }

    func addCustomJournalHabit(emoji: String, title: String, isNightHabit: Bool) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        let cleanEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "✨" : String(emoji.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2))
        let item = CustomJournalHabit(
            id: "custom_\(UUID().uuidString.prefix(8))",
            emoji: cleanEmoji,
            title: cleanTitle,
            isNightHabit: isNightHabit
        )
        customJournalHabits.append(item)
        persistState()
    }

    func deleteCustomJournalHabit(id: String) {
        customJournalHabits.removeAll { $0.id == id }
        hiddenJournalHabitIds.remove(id)
        persistState()
    }

    func journalNote(for dateIso: String? = nil) -> String {
        journalNotesByDate[dateIso ?? selectedDateIso] ?? ""
    }

    func setJournalNote(_ note: String, for dateIso: String? = nil) {
        let iso = dateIso ?? selectedDateIso
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            journalNotesByDate.removeValue(forKey: iso)
        } else {
            journalNotesByDate[iso] = trimmed
        }
        sectionCoachingCache.removeAll()
        dataRevision += 1
        persistState()
        if iso == isoFormatter.string(from: Date()) {
            refreshSmartNotificationSchedules(promptPermission: false)
        }
    }

    // MARK: - Persisted Nutrition & Nutrient Tracking

    private static func normalizedNutrientBucketKey(_ raw: String) -> String {
        let low = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
        if low.contains("carb") { return "carbohidratos" }
        if low.contains("prote") { return "proteina" }
        if low.contains("gras") { return "grasas" }
        if low.contains("hidra") || low.contains("agua") { return "hidratacion" }
        if low.contains("cafe") { return "cafeina" }
        if low.contains("alco") { return "alcohol" }
        return "calcio"
    }

    func manualNutrientAmount(for key: String, dateIso: String? = nil) -> Double {
        let iso = dateIso ?? selectedDateIso
        let bucket = Self.normalizedNutrientBucketKey(key)
        if bucket == "hidratacion" {
            let glassesMl = Double(hydrationGlassesByDate[iso] ?? 0) * 250.0
            let extraMl = manualNutrientsByDate[iso]?["hidratacion_extra_ml"] ?? 0.0
            return max(0, glassesMl + extraMl)
        }
        return max(0, manualNutrientsByDate[iso]?[bucket] ?? 0.0)
    }

    func addNutrientAmount(key: String, amount: Double, dateIso: String? = nil) {
        guard amount > 0 else { return }
        let iso = dateIso ?? selectedDateIso
        let bucket = Self.normalizedNutrientBucketKey(key)
        if bucket == "hidratacion" {
            if abs(amount - 250.0) < 0.1 {
                hydrationGlassesByDate[iso] = (hydrationGlassesByDate[iso] ?? 0) + 1
            } else {
                var dayMap = manualNutrientsByDate[iso] ?? [:]
                dayMap["hidratacion_extra_ml"] = (dayMap["hidratacion_extra_ml"] ?? 0.0) + amount
                manualNutrientsByDate[iso] = dayMap
            }
        } else {
            var dayMap = manualNutrientsByDate[iso] ?? [:]
            dayMap[bucket] = (dayMap[bucket] ?? 0.0) + amount
            manualNutrientsByDate[iso] = dayMap
        }
        dataRevision += 1
        persistState()
    }

    func resetNutrientAmount(key: String, dateIso: String? = nil) {
        let iso = dateIso ?? selectedDateIso
        let bucket = Self.normalizedNutrientBucketKey(key)
        if bucket == "hidratacion" {
            hydrationGlassesByDate.removeValue(forKey: iso)
            manualNutrientsByDate[iso]?.removeValue(forKey: "hidratacion_extra_ml")
        } else {
            manualNutrientsByDate[iso]?.removeValue(forKey: bucket)
        }
        dataRevision += 1
        persistState()
    }

    func addHydrationGlass() {
        hydrationGlassesByDate[selectedDateIso] = (hydrationGlassesByDate[selectedDateIso] ?? 0) + 1
        persistState()
    }

    func saveMeal(_ meal: NutritionMealItem, for dateIso: String? = nil) {
        let iso = dateIso ?? selectedDateIso
        var list = mealsByDate[iso] ?? []
        if let idx = list.firstIndex(where: { $0.id == meal.id }) {
            list[idx] = meal
        } else {
            list.insert(meal, at: 0)
        }
        mealsByDate[iso] = list
        sectionCoachingCache.removeAll()
        dataRevision += 1
        persistState()
    }

    func deleteMeal(id: String, for dateIso: String? = nil) {
        let iso = dateIso ?? selectedDateIso
        guard var list = mealsByDate[iso] else { return }
        list.removeAll { $0.id == id }
        if list.isEmpty {
            mealsByDate.removeValue(forKey: iso)
        } else {
            mealsByDate[iso] = list
        }
        sectionCoachingCache.removeAll()
        dataRevision += 1
        persistState()
    }

    func addQuickMeal(title: String, kcal: Int, protein: Int, carbs: Int, fat: Int) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        saveMeal(
            NutritionMealItem(
                id: UUID().uuidString,
                title: title,
                timeLabel: f.string(from: Date()),
                kcal: kcal,
                proteinG: protein,
                carbsG: carbs,
                fatG: fat,
                qualityScore: 85
            )
        )
    }

    // MARK: - Smart Local Notifications & Real Wake Alarm

    var tonightSleepNeedBreakdown: (baseMin: Int, debtMin: Int, strainExtraMin: Int, totalMin: Int) {
        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: userProfile)
        let baseMin = Int((norms.sleepTargetHours * 60.0).rounded())
        let todayIso = isoFormatter.string(from: Date())
        let refDay = activeHistory[todayIso] ?? currentDaySummary
        let debt = refDay?.sleepDebtMinutes ?? 0
        let stPct = refDay?.strainPct ?? 0
        let extra = stPct > 70 ? 25 : (stPct > 45 ? 10 : 0)
        return (baseMin, debt, extra, baseMin + debt + extra)
    }

    var computedSleepPlan: ComputedSleepNotificationPlan {
        LocalNotificationManager.computeSleepNotificationPlan(
            wakeHour: notificationSettings.smartAlarmHour,
            wakeMinute: notificationSettings.smartAlarmMinute,
            sleepNeedMinutes: tonightSleepNeedBreakdown.totalMin,
            leadMinutes: notificationSettings.bedtimeLeadMinutes
        )
    }

    func setSmartAlarmEnabled(_ enabled: Bool, promptPermission: Bool = true) {
        smartAlarmEnabled = enabled
        persistState()
        refreshSmartNotificationSchedules(promptPermission: promptPermission && enabled)
    }

    func updateNotificationSettings(_ updated: SmartNotificationSettings, promptPermission: Bool = true) {
        notificationSettings = updated
        persistState()
        refreshSmartNotificationSchedules(promptPermission: promptPermission)
    }

    func refreshSmartNotificationSchedules(promptPermission: Bool = false) {
        let todayIso = isoFormatter.string(from: Date())
        let alreadyLogged = hasAnyJournalActivity(for: todayIso)
        let need = tonightSleepNeedBreakdown
        let todaySummary = activeHistory[todayIso] ?? currentDaySummary
        let stPct = todaySummary?.strainPct ?? 0
        let hasSt = todaySummary?.strainPct != nil
        let cfg = notificationSettings
        let alarmOn = smartAlarmEnabled
        let uName = userProfile.displayFirstName

        Task { @MainActor [weak self] in
            let status = await LocalNotificationManager.shared.syncAllSchedules(
                settings: cfg,
                smartAlarmEnabled: alarmOn,
                todayJournalAlreadyLogged: alreadyLogged,
                sleepNeedMinutes: need.totalMin,
                sleepDebtMinutes: need.debtMin,
                strainPercent: stPct,
                hasStrainData: hasSt,
                userName: uName,
                promptPermissionIfNeeded: promptPermission
            )
            self?.notificationStatusText = status
        }
    }

    func triggerTestLocalNotification() {
        let uName = userProfile.displayFirstName
        Task { @MainActor [weak self] in
            let status = await LocalNotificationManager.shared.sendTestNotification(userName: uName)
            self?.notificationStatusText = status
        }
    }

    // MARK: - Individual Workout Selection, Editing & Deletion

    func selectWorkout(_ workout: EffortEventItem) {
        var enriched = workout
        if enriched.dateIso == nil {
            enriched.dateIso = selectedDateIso
        }
        selectedWorkoutItem = enriched
    }

    func updateWorkout(_ updated: EffortEventItem, originalDateIso: String? = nil) {
        let targetIso = updated.dateIso ?? originalDateIso ?? selectedDateIso
        var d = activeHistory[targetIso] ?? RealBiometricDaySummary(dateIso: targetIso)
        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: userProfile)
        let rhrRef = d.restingHrBpm ?? norms.restingHrExpected
        let ws = WhoopPhysiologyEngine.computeWorkoutStrain(
            durationMin: max(updated.durationMin, 1),
            kcal: max(updated.kcal, 0),
            avgHrBpm: max(updated.avgHrBpm, 0),
            rhrBpm: rhrRef,
            maxHrBpm: Double(norms.maxHrBpm),
            banisterB: userProfile.sex.banisterB
        )

        var recalc = updated
        recalc.dateIso = targetIso
        recalc.strainScore = ws.strain21
        recalc.strainPct = ws.strainPct

        if let idx = d.workouts.firstIndex(where: { $0.id == recalc.id }) {
            d.workouts[idx] = recalc
        } else {
            d.workouts.insert(recalc, at: 0)
        }
        d.strengthMinutes = d.workouts.filter { $0.categoryLabel == "Fuerza" }.reduce(0) { $0 + $1.durationMin }
        if let st = WhoopPhysiologyEngine.computeBevelStrain(
            profile: userProfile,
            rhrBpm: rhrRef,
            hrZoneMinutes: d.hrZoneMinutes,
            workouts: d.workouts,
            activeKcal: d.activeKcal.map { Double($0) }
        ) {
            d.strain21 = st.strain21
            d.strainPct = st.strainPct
        }

        if hasImportedOrPairedRealData {
            realHistory[targetIso] = d
        } else {
            simulatedHistory[targetIso] = d
        }
        selectedWorkoutItem = recalc
        sectionCoachingCache.removeAll()
        dataRevision += 1
        persistState()
    }

    func deleteWorkout(id: String, dateIso: String? = nil) {
        let targetIso = dateIso ?? selectedWorkoutItem?.dateIso ?? selectedDateIso
        guard var d = activeHistory[targetIso] else { return }
        d.workouts.removeAll { $0.id == id }
        d.strengthMinutes = d.workouts.filter { $0.categoryLabel == "Fuerza" }.reduce(0) { $0 + $1.durationMin }

        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: userProfile)
        let rhrRef = d.restingHrBpm ?? norms.restingHrExpected
        if let st = WhoopPhysiologyEngine.computeBevelStrain(
            profile: userProfile,
            rhrBpm: rhrRef,
            hrZoneMinutes: d.hrZoneMinutes,
            workouts: d.workouts,
            activeKcal: d.activeKcal.map { Double($0) }
        ) {
            d.strain21 = st.strain21
            d.strainPct = st.strainPct
        } else if d.workouts.isEmpty && (d.activeKcal ?? 0) == 0 {
            d.strain21 = nil
            d.strainPct = nil
        }

        if hasImportedOrPairedRealData {
            realHistory[targetIso] = d
        } else {
            simulatedHistory[targetIso] = d
        }
        if selectedWorkoutItem?.id == id {
            selectedWorkoutItem = nil
        }
        sectionCoachingCache.removeAll()
        dataRevision += 1
        persistState()
    }

    func workoutIntradaySamples(for workout: EffortEventItem) -> [TimedBiometricPoint] {
        let iso = workout.dateIso ?? selectedDateIso
        guard let day = activeHistory[iso], !day.stressSamples5m.isEmpty else { return [] }
        // Parse `HH:mm - HH:mm` from `timeRange` when available
        let parts = workout.timeRange.components(separatedBy: "-")
        if parts.count == 2 {
            let parseHHMM: (String) -> Int? = { raw in
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                let tokens = trimmed.split(separator: ":")
                guard tokens.count == 2, let h = Int(tokens[0]), let m = Int(tokens[1]) else { return nil }
                return h * 60 + m
            }
            if let sMin = parseHHMM(parts[0]), let eMin = parseHHMM(parts[1]), eMin >= sMin {
                let window = max(0, sMin - 5)...min(1439, eMin + 5)
                let slice = day.stressSamples5m.filter { window.contains($0.minuteOfDay) }
                if slice.count >= 2 { return slice }
            }
        }
        if let sEp = workout.startEpochSec, workout.durationMin > 0 {
            let eEp = sEp + Int64(workout.durationMin * 60)
            let slice = day.stressSamples5m.filter { pt in
                guard let ep = pt.epochSec else { return false }
                return ep >= (sEp - 300) && ep <= (eEp + 300)
            }
            if slice.count >= 2 { return slice }
        }
        return []
    }

    func addEffortEvent(title: String, durationMin: Int, kcal: Int) {
        var d = currentDaySummary ?? RealBiometricDaySummary(dateIso: selectedDateIso)
        let ws = WhoopPhysiologyEngine.computeWorkoutStrain(durationMin: durationMin, kcal: kcal, avgHrBpm: 0)
        let ev = EffortEventItem(
            id: UUID().uuidString,
            title: title,
            timeRange: "Hoy",
            durationMin: durationMin,
            avgHrBpm: 0,
            strainScore: ws.strain21,
            strainPct: ws.strainPct,
            categoryLabel: "Actividad",
            kcal: kcal,
            dateIso: selectedDateIso
        )
        d.workouts.insert(ev, at: 0)
        if hasImportedOrPairedRealData {
            realHistory[selectedDateIso] = d
        } else {
            simulatedHistory[selectedDateIso] = d
        }
        dataRevision += 1
        persistState()
    }

    func toggleSetCompleted(_ id: String) {
        if let idx = strengthSets.firstIndex(where: { $0.id == id }) {
            strengthSets[idx].completed.toggle()
        }
    }

    func addStrengthSet(exercise: String = "Press militar", reps: Int = 10, weightKg: Double = 45) {
        strengthSets.append((UUID().uuidString, exercise, reps, weightKg, false))
    }

    func toggleRestTimer() {
        restTimerRunning.toggle()
        timerTask?.cancel()
        if restTimerRunning {
            timerTask = Task {
                while !Task.isCancelled && restTimerRunning && restTimerSeconds > 0 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if !Task.isCancelled && restTimerRunning {
                        restTimerSeconds = max(restTimerSeconds - 1, 0)
                        if restTimerSeconds == 0 { restTimerRunning = false }
                    }
                }
            }
        } else {
            restTimerSeconds = 90
        }
    }

    // MARK: - Apple Health & WHOOP Export Importer

    func importExportFiles(urls: [URL]) {
        guard !urls.isEmpty else { return }
        importStatus = ExportImportStatus(
            isImporting: true,
            summaryMessage: "Leyendo exportación de Apple Health / WHOOP..."
        )
        let profileSnapshot = userProfile
        let priorSnapshot = realHistory
        Task.detached(priority: .userInitiated) {
            let result = WhoopExportImporter.importURLs(urls, profile: profileSnapshot, priorHistory: priorSnapshot)
            await MainActor.run {
                if let err = result.errorMessage, result.days.isEmpty {
                    self.importStatus = ExportImportStatus(isImporting: false, errorMessage: err)
                    return
                }
                self.applyImportedResult(result, navigateToLatest: true)
            }
        }
    }

    private func applyImportedResult(_ result: ExportParseResult, navigateToLatest: Bool) {
        self.hasImportedOrPairedRealData = true
        self.clearPreviewSeededArtifactsOnRealData()
        var merged = WhoopExportImporter.mergeDays(existing: self.realHistory, imported: result.days)
        self.recomputeContinuousEnergy(in: &merged)
        self.realHistory = merged
        for (iso, map) in result.journalByDate {
            var dayJournal = self.journalCheckinsByDate[iso] ?? [:]
            for (k, v) in map { dayJournal[k] = v }
            self.journalCheckinsByDate[iso] = dayJournal
        }
        if navigateToLatest {
            if let latestIso = result.latestDateIso, let latestDate = self.isoFormatter.date(from: latestIso) {
                self.selectDate(latestDate)
            } else {
                self.dayOffset = 0
            }
        }
        let rangeText = (result.earliestDateIso != nil && result.latestDateIso != nil)
            ? "\(result.earliestDateIso!) – \(result.latestDateIso!)"
            : ""
        let hrvDaysCount = result.days.values.filter { $0.hrvMs != nil }.count
        var summary = "✓ \(result.days.count) días reales importados"
        if hrvDaysCount > 0 { summary += " · \(hrvDaysCount) días VFC" }
        if result.workoutsCount > 0 { summary += " · \(result.workoutsCount) entrenamientos" }
        self.importStatus = ExportImportStatus(
            isImporting: false,
            importedDaysCount: result.days.count,
            importedWorkoutsCount: result.workoutsCount,
            dateRangeLabel: rangeText,
            summaryMessage: summary,
            errorMessage: nil
        )
        self.dataRevision += 1
        self.persistState()
        self.publishWidgetSnapshot(triggerReload: true, forceReload: true)
        self.refreshSmartNotificationSchedules(promptPermission: false)
    }

    // MARK: - Zero-Entitlement Automatic Sync Bridge (Apple Shortcuts x-callback-url + Files Watcher + Top Floating Bubble)

    /// Builds Apple's official `shortcuts://x-callback-url/run-shortcut` URL so Shortcuts runs the user's sync shortcut
    /// and automatically returns straight back into Improving (`improving://sync?from=shortcut_ok`).
    static func buildShortcutCallbackURL(shortcutName: String) -> URL? {
        let trimmed = shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var comps = URLComponents()
        comps.scheme = "shortcuts"
        comps.host = "x-callback-url"
        comps.path = "/run-shortcut"
        comps.queryItems = [
            URLQueryItem(name: "name", value: trimmed),
            URLQueryItem(name: "x-success", value: "improving://sync?from=shortcut_ok"),
            URLQueryItem(name: "x-cancel", value: "improving://sync?from=shortcut_cancel"),
            URLQueryItem(name: "x-error", value: "improving://sync?from=shortcut_error")
        ]
        return comps.url
    }

    func updateShortcutSyncConfig(name: String, autoRunOnOpen: Bool) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        shortcutSyncName = cleaned.isEmpty ? "Sync Improving" : cleaned
        autoRunShortcutOnOpen = autoRunOnOpen
        persistState()
    }

    func presentSyncBanner(_ state: SyncBannerState, autoDismissAfter seconds: Double? = nil) {
        syncBannerDismissTask?.cancel()
        withAnimation(.spring(response: 0.44, dampingFraction: 0.80)) {
            syncBannerState = state
        }
        if let seconds {
            syncBannerDismissTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                    self.syncBannerState = .hidden
                }
            }
        }
    }

    /// Deliberate deep pull-to-refresh on `HoyScreen` (>= 135 pt pull):
    /// Quietly runs the user's sync shortcut (if configured) or refreshes inbox/HealthKit WITHOUT vibrating!
    func handlePullToRefresh() async {
        if autoRunShortcutOnOpen {
            triggerShortcutRefreshSync(userInitiated: true)
            try? await Task.sleep(nanoseconds: 350_000_000)
            return
        }
        presentSyncBanner(.syncing("Sincronizando…"))
        scanAutoSyncInboxIfNeeded(force: true, showBanner: true)
        #if os(iOS)
        if healthKitAuthorized && !healthKitSyncing {
            connectAndSyncAppleHealth()
        }
        #endif
        try? await Task.sleep(nanoseconds: 550_000_000)
    }

    /// Called whenever the app becomes `.active`.
    /// Strict anti-reload & zero-vibration policy: ONLY handles midnight calendar rollover and explicit return
    /// from a user-triggered Shortcut. Never reloads, flashes banners, or vibrates on normal app switching!
    func handleAppBecameActive() {
        // Refresh calendar day rollover so overnight suspended apps immediately show Today!
        let todayIso = isoFormatter.string(from: Date())
        if !lastActiveCalendarDayIso.isEmpty && lastActiveCalendarDayIso != todayIso {
            dataRevision += 1
        }
        lastActiveCalendarDayIso = todayIso

        // Only clear pending shortcut state when returning without x-callback; NEVER read UIPasteboard here
        // (eliminates recurring iOS "Permitir pegar desde Atajos" popups and reopen loops).
        if awaitingShortcutCallback {
            awaitingShortcutCallback = false
            shortcutTimeoutTask?.cancel()
            scanAutoSyncInboxIfNeeded(force: false, showBanner: false)
        }
    }

    private func scheduleSilentAutomationRechecks() {
        // Disabled background polling loops to keep the app calm, battery-friendly, and free of constant reloads.
        backgroundRecheckTask?.cancel()
    }

    /// Launches the user's Apple Shortcut via `shortcuts://x-callback-url/run-shortcut`, shows the floating
    /// `"Sincronizando…"` bubble above the date, and automatically reloads + updates all metrics on return.
    @discardableResult
    func triggerShortcutRefreshSync(userInitiated: Bool) -> Bool {
        if !userInitiated, let last = lastShortcutTriggerAt, Date().timeIntervalSince(last) < 90.0 {
            return false
        }

        guard let url = Self.buildShortcutCallbackURL(shortcutName: shortcutSyncName) else {
            scanAutoSyncInboxIfNeeded(force: true, showBanner: true)
            return false
        }

        lastShortcutTriggerAt = Date()
        awaitingShortcutCallback = true
        autoSyncStatusText = "Ejecutando atajo «\(shortcutSyncName)»…"
        presentSyncBanner(.syncing("Sincronizando…"))

        // Safety timeout: never let the floating bubble stay stuck if user switches away from Shortcuts
        shortcutTimeoutTask?.cancel()
        shortcutTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 22_000_000_000)
            guard !Task.isCancelled, let self, self.awaitingShortcutCallback else { return }
            self.awaitingShortcutCallback = false
            self.scanAutoSyncInboxIfNeeded(force: true, showBanner: true)
        }

        #if os(iOS)
        UIApplication.shared.open(url, options: [:]) { [weak self] opened in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !opened {
                    self.awaitingShortcutCallback = false
                    self.shortcutTimeoutTask?.cancel()
                    self.scanAutoSyncInboxIfNeeded(force: true, showBanner: true)
                }
            }
        }
        return true
        #else
        return false
        #endif
    }

    /// Live filesystem watchers on BOTH `En mi iPhone / Improving` and `AutoSync` directories PLUS direct
    /// file-level vnode watchers on `health_sync.json` & `shortcuts_latest.json` so in-place APFS overwrites
    /// from Apple Shortcuts trigger an immediate reload!
    private func startInboxDirectoryWatcher() {
        func makeDirWatcher(for dirURL: URL) -> DispatchSourceFileSystemObject? {
            let fd = open(dirURL.path, O_EVTONLY)
            guard fd >= 0 else { return nil }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .extend, .attrib], queue: .main)
            source.setEventHandler { [weak self] in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    self?.attachDirectSyncFileWatchers()
                    self?.scanAutoSyncInboxIfNeeded(force: false, showBanner: true)
                }
            }
            source.setCancelHandler {
                close(fd)
            }
            source.resume()
            return source
        }
        inboxDirectorySource = makeDirWatcher(for: ShortcutsHealthSyncImporter.publicDocumentsURL)
        autoSyncSubdirSource = makeDirWatcher(for: ShortcutsHealthSyncImporter.autoSyncInboxURL)
        attachDirectSyncFileWatchers()
    }

    private func attachDirectSyncFileWatchers() {
        func makeFileWatcher(for fileURL: URL) -> DispatchSourceFileSystemObject? {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
            let fd = open(fileURL.path, O_EVTONLY)
            guard fd >= 0 else { return nil }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .extend, .attrib, .rename, .delete],
                queue: .main
            )
            source.setEventHandler { [weak self] in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    self?.scanAutoSyncInboxIfNeeded(force: false, showBanner: true)
                    self?.attachDirectSyncFileWatchers()
                }
            }
            source.setCancelHandler {
                close(fd)
            }
            source.resume()
            return source
        }

        let healthSyncURL = ShortcutsHealthSyncImporter.publicDocumentsURL.appendingPathComponent("health_sync.json")
        healthSyncFileSource?.cancel()
        healthSyncFileSource = makeFileWatcher(for: healthSyncURL)

        let latestEnvURL = ShortcutsHealthSyncImporter.latestShortcutsEnvelopeURL
        shortcutsLatestFileSource?.cancel()
        shortcutsLatestFileSource = makeFileWatcher(for: latestEnvURL)
    }

    func scanAutoSyncInboxIfNeeded(force: Bool = false, showBanner: Bool = false) {
        // Never silently drop a fresh sync event while another scan is still running: queue it!
        if isAutoSyncing {
            let prev = pendingInboxRescan
            pendingInboxRescan = (force: (prev?.force ?? false) || force, showBanner: (prev?.showBanner ?? false) || showBanner)
            return
        }
        let files = ShortcutsHealthSyncImporter.discoverInboxFiles()
        let pending: [(URL, String)] = files.compactMap { url in
            let sig = ShortcutsHealthSyncImporter.fileSignature(for: url)
            let alreadySeen = processedAutoSyncSignatures.contains(sig)
            if !force && alreadySeen { return nil }
            // On forced refresh (pull-to-refresh / shortcut callback), avoid re-parsing multi-MB exportar.zip archives whose signature didn't change!
            if force && alreadySeen && !ShortcutsHealthSyncImporter.isLightweightAutoSyncFile(url: url) {
                return nil
            }
            return (url, sig)
        }
        guard !pending.isEmpty else {
            if force {
                let hhmm = Self.currentHHMM()
                autoSyncStatusText = "Revisado a las \(hhmm) · Sin archivos nuevos en Atajos/Carpeta"
                if showBanner {
                    presentSyncBanner(.synced("Sincronizado"), autoDismissAfter: 1.8)
                }
            }
            return
        }

        isAutoSyncing = true
        autoSyncStatusText = "Sincronizando desde Atajos / Carpeta..."
        if showBanner || syncBannerState != .hidden {
            presentSyncBanner(.syncing("Sincronizando…"))
        }
        let profileSnapshot = userProfile
        let priorSnapshot = realHistory
        let pendingURLs = pending.map(\.0)
        let pendingSigs = pending.map(\.1)
        let newestFileName = pendingURLs.last?.lastPathComponent ?? "Atajos"

        Task.detached(priority: .userInitiated) {
            let result = WhoopExportImporter.importURLs(pendingURLs, profile: profileSnapshot, priorHistory: priorSnapshot)
            await MainActor.run {
                self.isAutoSyncing = false
                if !result.days.isEmpty {
                    // Only mark signatures as processed AFTER a valid parse so partial mid-write reads are NEVER blacklisted!
                    for s in pendingSigs { self.processedAutoSyncSignatures.insert(s) }
                    let shouldJump = !self.hasImportedOrPairedRealData
                    self.applyImportedResult(result, navigateToLatest: shouldJump)
                    let hhmm = Self.currentHHMM()
                    let latestReading = Self.formatLatestReadingTag(from: result.days)
                    self.autoSyncStatusText = "✓ Sync \(hhmm) (\(newestFileName)) · \(result.days.count)d\(latestReading)"
                    self.persistState()
                    if showBanner || self.syncBannerState != .hidden {
                        self.presentSyncBanner(.synced("Sincronizado"), autoDismissAfter: 2.1)
                    }
                } else {
                    if force {
                        self.autoSyncStatusText = result.errorMessage ?? "Archivo detectado sin muestras válidas (\(newestFileName))"
                    }
                    if showBanner || self.syncBannerState != .hidden {
                        self.presentSyncBanner(.hidden)
                    }
                    // Retry once after 1.1s in case Apple Shortcuts was still flushing `health_sync.json`!
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: 1_100_000_000)
                        self?.scanAutoSyncInboxIfNeeded(force: false, showBanner: showBanner)
                    }
                }

                // Drain any queued rescan that arrived while this sync was running!
                if let queued = self.pendingInboxRescan {
                    self.pendingInboxRescan = nil
                    self.scanAutoSyncInboxIfNeeded(force: queued.force, showBanner: queued.showBanner)
                }
            }
        }
    }

    static func formatLatestReadingTag(from days: [String: RealBiometricDaySummary]) -> String {
        guard let latestIso = days.keys.sorted().last, let d = days[latestIso] else { return "" }
        let shortDay: String = {
            let inFmt = DateFormatter()
            inFmt.locale = Locale(identifier: "en_US_POSIX")
            inFmt.dateFormat = "yyyy-MM-dd"
            guard let dt = inFmt.date(from: latestIso) else { return latestIso }
            let outFmt = DateFormatter()
            outFmt.locale = Locale(identifier: "es_ES")
            outFmt.dateFormat = "d MMM"
            return outFmt.string(from: dt).replacingOccurrences(of: ".", with: "")
        }()
        if let lastMin = d.stressSamples5m.last?.minuteOfDay {
            let timeStr = String(format: "%02d:%02d", (lastMin / 60) % 24, lastMin % 60)
            return " · Últ. FC \(shortDay) \(timeStr)"
        }
        return " · Hasta \(shortDay)"
    }

    func handleIncomingURL(_ url: URL) {
        // 1. File opened via Share Sheet / Files app ("Abrir en Improving")
        if url.isFileURL {
            importExportFiles(urls: [url])
            return
        }

        // 2. Custom URL Scheme: improving://open or improving://sync[?from=shortcut_ok | ?source=clipboard | ?data=... | ?payload=...]
        guard url.scheme?.lowercased() == "improving" else { return }
        if url.host?.lowercased() == "open" {
            publishWidgetSnapshot(triggerReload: true, forceReload: true)
            return
        }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = comps?.queryItems ?? []
        let fromParam = items.first(where: { $0.name.lowercased() == "from" })?.value?.lowercased()
        let sourceParam = items.first(where: { $0.name.lowercased() == "source" })?.value?.lowercased()
        let rawParam = items.first(where: { $0.name.lowercased() == "data" || $0.name.lowercased() == "payload" || $0.name.lowercased() == "text" })?.value

        // Clear pending shortcut callback & refresh anti-loop timestamp immediately!
        if let from = fromParam, from.hasPrefix("shortcut") {
            awaitingShortcutCallback = false
            shortcutTimeoutTask?.cancel()
            lastShortcutTriggerAt = Date()

            if from == "shortcut_cancel" {
                autoSyncStatusText = "Sincronización cancelada"
                presentSyncBanner(.hidden)
                return
            }
            if from == "shortcut_error" {
                autoSyncStatusText = "No se pudo ejecutar «\(shortcutSyncName)» · Revisa el nombre en Dispositivos"
                presentSyncBanner(.notice("Revisa nombre del atajo"), autoDismissAfter: 2.6)
                return
            }
            // from == "shortcut_ok": scan inbox only (direct URL payload arrives via ?data= without touching Pasteboard!)
            scanAutoSyncInboxIfNeeded(force: false, showBanner: true)
            return
        }

        if sourceParam == "clipboard" {
            presentSyncBanner(.syncing("Sincronizando…"))
            let paste = UIPasteboard.general.string ?? ""
            ingestRawShortcutsPayload(paste, sourceLabel: "Sync Improving")
            return
        }

        if let raw = rawParam, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            presentSyncBanner(.syncing("Sincronizando…"))
            let decoded: String = {
                if raw.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
                    return raw
                }
                let plusFixed = raw.replacingOccurrences(of: "+", with: " ")
                if let pct = plusFixed.removingPercentEncoding, pct.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
                    return pct
                }
                if let b64 = Data(base64Encoded: raw), let str = String(data: b64, encoding: .utf8), !str.isEmpty {
                    return str
                }
                return raw
            }()
            ingestRawShortcutsPayload(decoded, sourceLabel: "Sync Improving")
            return
        }

        // Default: scan `En mi iPhone / Improving` & `AutoSync` inbox immediately!
        scanAutoSyncInboxIfNeeded(force: true, showBanner: true)
    }

    func ingestRawShortcutsPayload(_ text: String, sourceLabel: String = "Atajos de Apple") {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            autoSyncStatusText = "No había datos de Salud en \(sourceLabel)"
            presentSyncBanner(.hidden)
            return
        }
        // Dedupe back-to-back callback + clipboard URL delivery of the exact same payload within 4s
        let payloadHash = trimmed.hashValue
        if let prevHash = lastIngestedPayloadHash, let prevAt = lastIngestedPayloadAt,
           prevHash == payloadHash, Date().timeIntervalSince(prevAt) < 4.0 {
            presentSyncBanner(.synced("Sincronizado"), autoDismissAfter: 1.8)
            return
        }
        lastIngestedPayloadHash = payloadHash
        lastIngestedPayloadAt = Date()
        isAutoSyncing = true
        autoSyncStatusText = "Procesando \(sourceLabel)..."
        presentSyncBanner(.syncing("Sincronizando…"))
        let profileSnapshot = userProfile
        let priorSnapshot = realHistory

        Task.detached(priority: .userInitiated) {
            let result = ShortcutsHealthSyncImporter.parseRawText(
                trimmed,
                sourceName: sourceLabel,
                profile: profileSnapshot,
                priorHistory: priorSnapshot
            )
            await MainActor.run {
                self.isAutoSyncing = false
                if !result.days.isEmpty {
                    let shouldJump = !self.hasImportedOrPairedRealData
                    self.applyImportedResult(result, navigateToLatest: shouldJump)
                    let hhmm = Self.currentHHMM()
                    let latestReading = Self.formatLatestReadingTag(from: result.days)
                    self.autoSyncStatusText = "✓ \(sourceLabel) \(hhmm) · \(result.days.count)d\(latestReading)"
                    self.persistState()
                    self.presentSyncBanner(.synced("Sincronizado"), autoDismissAfter: 2.1)
                } else {
                    self.autoSyncStatusText = result.errorMessage ?? "Sin lecturas válidas en \(sourceLabel)"
                    self.presentSyncBanner(.hidden)
                }
            }
        }
    }

    private static func currentHHMM() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }

    // MARK: - HealthKit & WHOOP Live Connectors (Full 60-Day Bevel Pipeline + Continuous Energy!)

    func connectAndSyncAppleHealth() {
        #if os(iOS)
        healthKitSyncing = true
        healthKitLastSyncText = "Conectando..."
        Task {
            do {
                try await HealthKitReader.shared.requestAuthorization()
                self.healthKitAuthorized = HealthKitReader.shared.isAuthorized
                self.healthKitLastSyncText = "Sincronizando 60 días..."
                let historySnaps = await HealthKitReader.shared.syncHistoryDays(days: 60)
                self.ingestHealthKitSnapshots(historySnaps)
                let realDays = self.realHistory.count
                let hrvDays = self.realHistory.values.filter { $0.hrvMs != nil }.count
                self.healthKitLastSyncText = "Sincronizado (\(realDays)d · \(hrvDays) VFC)"
            } catch {
                self.healthKitLastSyncText = error.localizedDescription
            }
            self.healthKitSyncing = false
        }
        #endif
    }

    private func bindHealthKit() {
        #if os(iOS)
        HealthKitReader.shared.$latestSnapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snap in
                guard let self, let snap else { return }
                self.ingestHealthKitSnapshots([snap])
            }
            .store(in: &cancellables)
        #endif
    }

    #if os(iOS)
    private func ingestHealthKitSnapshots(_ snapshots: [DailyHealthSnapshot]) {
        guard !snapshots.isEmpty else { return }
        let sorted = snapshots.sorted { $0.day < $1.day }
        let cal = Calendar.current
        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: userProfile)
        let maxHr = Double(WhoopPhysiologyEngine.computeMaxHeartRate(profile: userProfile))
        let popLnHrv = log(max(norms.hrvExpectedMs, 15.0))
        let popRhr = norms.restingHrExpected
        let popResp = (norms.respLowRpm + norms.respHighRpm) / 2.0

        let timeFmt = DateFormatter()
        timeFmt.locale = Locale(identifier: "en_US_POSIX")
        timeFmt.dateFormat = "HH:mm"
        let fullFmt = DateFormatter()
        fullFmt.locale = Locale(identifier: "es_ES")
        fullFmt.dateFormat = "dd/MM/yy 'a las' H:mm"

        // Seed causal baselines from any existing realHistory strictly BEFORE the first synced snapshot
        let firstIso = isoFormatter.string(from: sorted[0].day)
        var priorLnHrv: [Double] = []
        var priorRhr: [Double] = []
        var priorResp: [Double] = []
        var priorTemp: [Double] = []
        var prevDayEndEnergy: Double? = nil
        var prevDayIso: String? = nil

        for iso in realHistory.keys.sorted() where iso < firstIso {
            if let old = realHistory[iso] {
                if let h = old.hrvMs, h > 2 { priorLnHrv.append(log(h)) }
                if let r = old.restingHrBpm { priorRhr.append(r) }
                if let rr = old.respRateRpm { priorResp.append(rr) }
                if let t = old.wristTempAbsoluteC { priorTemp.append(t) }
                if let lastE = old.energySamples5m.last?.value ?? old.energyBankPercent.map({ Double($0) }) {
                    prevDayEndEnergy = lastE
                    prevDayIso = iso
                }
            }
        }

        var updatedAny = false

        for snap in sorted {
            let iso = isoFormatter.string(from: snap.day)
            var d = realHistory[iso] ?? RealBiometricDaySummary(dateIso: iso)
            var hasReal = false

            // 1. Sleeping HRV (Bevel/WHOOP beat-to-beat RMSSD over Entire Sleep, with clean fallback!)
            if snap.hrv.sampleCount > 0 && snap.hrv.weightedHRV > 2.0 {
                d.hrvMs = AppleHealthExportImporter.round1(snap.hrv.weightedHRV)
                d.hrvMethodLabel = snap.hrv.method
                hasReal = true
            }

            // 2. Sleeping RHR (prefer sleeping mean HR when measured, fallback Apple Resting HR)
            if snap.heartRate.sleepingMeanHR > 25.0 {
                d.restingHrBpm = AppleHealthExportImporter.round1(snap.heartRate.sleepingMeanHR)
                hasReal = true
            } else if snap.heartRate.restingHR > 25.0 {
                d.restingHrBpm = AppleHealthExportImporter.round1(snap.heartRate.restingHR)
                hasReal = true
            }

            // 3. Daytime HR (strictly outside sleep window)
            if let live = snap.liveHeartRate, live > 28.0 {
                d.liveHrBpm = Int(live.rounded())
                hasReal = true
            }

            // 4. Vitals (strictly optional — zero fake 14.5 / 98.0 defaults!)
            if let resp = snap.vitals.meanRespiratoryRate, resp > 5.0 {
                d.respRateRpm = AppleHealthExportImporter.round1(resp)
                hasReal = true
            }
            if let spo2 = snap.vitals.meanSpO2, spo2 >= 60.0 {
                d.spo2Percent = AppleHealthExportImporter.round1(spo2)
                hasReal = true
            }
            if let tAbs = snap.vitals.tempAbsoluteCelsius {
                d.wristTempAbsoluteC = AppleHealthExportImporter.round1(tAbs)
                let tBase = priorTemp.isEmpty ? tAbs : (priorTemp.suffix(30).reduce(0, +) / Double(min(priorTemp.count, 30)))
                d.wristTempDeltaC = AppleHealthExportImporter.round1(tAbs - tBase)
                hasReal = true
            } else if let tDelta = snap.vitals.tempDeltaCelsius {
                d.wristTempDeltaC = AppleHealthExportImporter.round1(tDelta)
                hasReal = true
            }

            // 5. Sleep session + hypnogram stages + overnight vitals + Bevel Sleep Score
            var sleepStartEp: Int64? = nil
            var sleepEndEp: Int64? = nil
            if let sl = snap.sleep, sl.totalAsleepMinutes > 0 {
                let asleepMin = Int(sl.totalAsleepMinutes.rounded())
                let inBedMin = Int(sl.inBedMinutes.rounded())
                let deepMin = sl.deepMinutes > 0 ? Int(sl.deepMinutes.rounded()) : nil
                let remMin = sl.remMinutes > 0 ? Int(sl.remMinutes.rounded()) : nil
                let coreMin = sl.coreMinutes > 0 ? Int(sl.coreMinutes.rounded()) : nil
                let awakeMin = sl.awakeMinutes > 0 ? Int(sl.awakeMinutes.rounded()) : nil

                sleepStartEp = Int64(sl.startDate.timeIntervalSince1970)
                sleepEndEp = Int64(sl.endDate.timeIntervalSince1970)

                let awakeBlocks = sl.stages.filter { $0.stageCode == 0 }.count
                let continuityPct: Int? = awakeBlocks > 0
                    ? max(20, min(100, 100 - awakeBlocks * 7 - Int((sl.awakeMinutes) * 0.8)))
                    : nil

                let hrDipPct: Double? = {
                    guard let dayHr = d.liveHrBpm, dayHr > 0, snap.heartRate.sleepingMeanHR > 25 else { return nil }
                    return AppleHealthExportImporter.round1(max(-10.0, min(40.0, (Double(dayHr) - snap.heartRate.sleepingMeanHR) / Double(dayHr) * 100.0)))
                }()

                let stageBlocks: [SleepStageBlock] = sl.stages.enumerated().map { idx, st in
                    let kind: SleepStageKind = switch st.stageCode {
                    case 0: .awake
                    case 1: .rem
                    case 3: .deep
                    default: .core
                    }
                    return SleepStageBlock(
                        id: "hk_st_\(iso)_\(idx)",
                        stage: kind,
                        startEpochSec: Int64(st.startDate.timeIntervalSince1970),
                        endEpochSec: Int64(st.endDate.timeIntervalSince1970)
                    )
                }

                let toTimed: ([TimedHealthSample]) -> [TimedBiometricPoint] = { arr in
                    arr.map { s in
                        let c = cal.dateComponents([.hour, .minute], from: s.date)
                        let mod = (c.hour ?? 0) * 60 + (c.minute ?? 0)
                        return TimedBiometricPoint(
                            minuteOfDay: mod,
                            value: AppleHealthExportImporter.round1(s.value),
                            epochSec: Int64(s.date.timeIntervalSince1970)
                        )
                    }
                }

                d.asleepMinutes = asleepMin
                d.inBedMinutes = inBedMin
                d.deepMinutes = deepMin
                d.remMinutes = remMin
                d.coreMinutes = coreMin
                d.awakeMinutes = awakeMin
                d.sleepDebtMinutes = max(Int((norms.sleepTargetHours * 60.0).rounded()) - asleepMin, 0)
                d.sleepPct = WhoopPhysiologyEngine.computeBevelSleepScore(
                    asleepMinutes: asleepMin,
                    inBedMinutes: inBedMin > 0 ? inBedMin : nil,
                    deepMinutes: deepMin,
                    remMinutes: remMin,
                    awakeMinutes: awakeMin,
                    awakeCount: awakeBlocks,
                    hrDipPct: hrDipPct,
                    targetMinutes: norms.sleepTargetHours * 60.0,
                    deepTargetPct: norms.deepTargetPct,
                    remTargetPct: norms.remTargetPct
                )
                d.sleepSession = SleepSessionDetail(
                    startEpochSec: sleepStartEp,
                    endEpochSec: sleepEndEp,
                    startTimeLabel: timeFmt.string(from: sl.startDate),
                    endTimeLabel: timeFmt.string(from: sl.endDate),
                    startDateTimeLabel: fullFmt.string(from: sl.startDate),
                    sourceName: sl.sourceName,
                    awakeSeconds: awakeMin.map { $0 * 60 },
                    remSeconds: remMin.map { $0 * 60 },
                    coreSeconds: coreMin.map { $0 * 60 },
                    deepSeconds: deepMin.map { $0 * 60 },
                    latencyMinutes: sl.latencyMinutes,
                    efficiencyPct: Int(sl.efficiencyPct.rounded()),
                    hrDipPct: hrDipPct,
                    continuityPct: continuityPct,
                    stages: stageBlocks,
                    sleepHrSamples: toTimed(snap.sleepHrSamples),
                    sleepHrvSamples: toTimed(snap.sleepHrvSamples),
                    sleepRespSamples: toTimed(snap.sleepRespSamples),
                    sleepSpo2Samples: toTimed(snap.sleepSpo2Samples)
                )
                hasReal = true
            }

            // 6. Activity, Workouts, HR Zones & Bevel Strain
            if let steps = snap.steps { d.stepsCount = steps; hasReal = true }
            if let kcal = snap.activeCalories { d.activeKcal = Int(kcal.rounded()); hasReal = true }
            if let v = snap.vo2Max { d.vo2MaxMlKgMin = AppleHealthExportImporter.round1(v); hasReal = true }
            if let hrr = snap.hrRecoveryBpm { d.hrRecoveryBpm = AppleHealthExportImporter.round1(hrr); hasReal = true }
            if let w = snap.bodyWeightKg { d.bodyWeightKg = AppleHealthExportImporter.round1(w); hasReal = true }
            if let f = snap.bodyFatPct { d.bodyFatPct = AppleHealthExportImporter.round1(f); hasReal = true }
            if let l = snap.leanMassKg { d.leanMassKg = AppleHealthExportImporter.round1(l); hasReal = true }
            if let s = snap.systolicBp { d.systolicBp = s; hasReal = true }
            if let dia = snap.diastolicBp { d.diastolicBp = dia; hasReal = true }
            if let dl = snap.daylightMinutes { d.daylightMinutes = dl; hasReal = true }
            if let noise = snap.sleepNoiseOver50Db { d.sleepNoiseOver50Db = noise; hasReal = true }

            let rhrBaseline = WhoopPhysiologyEngine.computeRollingBaseline(
                priorValues: priorRhr, populationMean: popRhr, populationSigma: 3.5, floorSigma: 2.0
            )
            let lnHrvBaseline = WhoopPhysiologyEngine.computeRollingBaseline(
                priorValues: priorLnHrv, populationMean: popLnHrv, populationSigma: 0.24, floorSigma: 0.14
            )
            let respBaseline = WhoopPhysiologyEngine.computeRollingBaseline(
                priorValues: priorResp, populationMean: popResp, populationSigma: 0.9, floorSigma: 0.5
            )
            let rhrRef = d.restingHrBpm ?? rhrBaseline.mean

            var workoutSpans: [ClosedRange<Int64>] = []
            if !snap.workouts.isEmpty {
                var strengthMins = 0
                d.workouts = snap.workouts.map { w in
                    if w.isStrength { strengthMins += w.durationMinutes }
                    let sEp = Int64(w.startDate.timeIntervalSince1970)
                    let eEp = max(Int64(w.endDate.timeIntervalSince1970), sEp + Int64(w.durationMinutes * 60))
                    workoutSpans.append(sEp...eEp)
                    let ws = WhoopPhysiologyEngine.computeWorkoutStrain(
                        durationMin: w.durationMinutes,
                        kcal: w.activeCalories,
                        avgHrBpm: w.avgHeartRate,
                        rhrBpm: rhrRef,
                        maxHrBpm: maxHr,
                        banisterB: userProfile.sex.banisterB
                    )
                    return EffortEventItem(
                        id: w.id.uuidString,
                        title: w.name,
                        timeRange: "\(timeFmt.string(from: w.startDate)) - \(timeFmt.string(from: w.endDate))",
                        durationMin: w.durationMinutes,
                        avgHrBpm: w.avgHeartRate,
                        strainScore: ws.strain21,
                        strainPct: ws.strainPct,
                        categoryLabel: w.isStrength ? "Fuerza" : "Cardio",
                        kcal: w.activeCalories,
                        dateIso: iso
                    )
                }
                d.strengthMinutes = strengthMins
                hasReal = true
            }

            if !snap.intradayHrSamples.isEmpty {
                let hrTuples: [(Int64, Int, Double)] = snap.intradayHrSamples.map { s in
                    let ep = Int64(s.date.timeIntervalSince1970)
                    let c = cal.dateComponents([.hour, .minute], from: s.date)
                    return (ep, (c.hour ?? 0) * 60 + (c.minute ?? 0), s.value)
                }
                d.hrZoneMinutes = AppleHealthExportImporter.computeHrZoneMinutes(
                    samples: hrTuples.map { ($0.0, $0.2) },
                    workoutSpans: workoutSpans,
                    maxHr: maxHr,
                    rhr: rhrRef
                )
                hasReal = true
            }

            // 7. Bevel Adaptive Recovery % (strictly from real measured sensors + Low Power Mode sleep resilience)
            d.recoveryPct = WhoopPhysiologyEngine.computeBevelRecoveryPercent(
                hrvMs: d.hrvMs,
                rhrBpm: d.restingHrBpm,
                respRpm: d.respRateRpm,
                spo2Pct: d.spo2Percent,
                wristTempDeltaC: d.wristTempDeltaC,
                lnHrvBaseline: lnHrvBaseline,
                rhrBaseline: rhrBaseline,
                respBaseline: respBaseline,
                profile: userProfile,
                sleepPct: d.sleepPct
            )

            // 8. Bevel Calibrated Strain
            if let strainPair = WhoopPhysiologyEngine.computeBevelStrain(
                profile: userProfile,
                rhrBpm: rhrRef,
                hrZoneMinutes: d.hrZoneMinutes,
                workouts: d.workouts,
                activeKcal: d.activeKcal.map { Double($0) }
            ) {
                d.strain21 = strainPair.strain21
                d.strainPct = strainPair.strainPct
                hasReal = true
            }

            // 9. 5-Minute Stress + CONTINUOUS Cross-Day Energy Bank (ZERO midnight jump + Low Power Mode sleep resilience!)
            var stress5m: [TimedBiometricPoint] = []
            if !snap.intradayHrSamples.isEmpty {
                let hrTuples: [(Int64, Int, Double)] = snap.intradayHrSamples.map { s in
                    let ep = Int64(s.date.timeIntervalSince1970)
                    let c = cal.dateComponents([.hour, .minute], from: s.date)
                    return (ep, (c.hour ?? 0) * 60 + (c.minute ?? 0), s.value)
                }
                let hrvFactor: Double = {
                    guard let h = d.hrvMs, h > 2 else { return 1.0 }
                    let ratio = exp(lnHrvBaseline.mean) / h
                    return min(max(ratio, 0.72), 1.40)
                }()
                stress5m = AppleHealthExportImporter.buildFiveMinuteStressSamples(
                    hrSamples: hrTuples,
                    rhrRef: rhrRef,
                    maxHr: maxHr,
                    hrvFactor: hrvFactor,
                    sleepStartEpoch: sleepStartEp,
                    sleepEndEpoch: sleepEndEp
                )
                if !stress5m.isEmpty {
                    d.stressSamples5m = stress5m
                    d.stressScore = Int((stress5m.map(\.value).reduce(0, +) / Double(stress5m.count)).rounded())
                    hasReal = true
                }
            }

            let hasRecordedSleepToday = (sleepStartEp != nil && sleepEndEp != nil) || ((d.asleepMinutes ?? 0) > 0)
            if !stress5m.isEmpty || hasRecordedSleepToday {
                let isConsecutiveDay: Bool = {
                    guard let prevIso = prevDayIso,
                          let prevDt = isoFormatter.date(from: prevIso),
                          let diff = cal.dateComponents([.day], from: prevDt, to: snap.day).day else { return false }
                    return diff == 1
                }()
                let startingEnergy: Double = {
                    if isConsecutiveDay, let carried = prevDayEndEnergy {
                        return carried
                    }
                    if hasRecordedSleepToday {
                        return Double(max(min((d.recoveryPct ?? d.sleepPct ?? 65) - 34, 48), 22))
                    }
                    return Double(d.recoveryPct ?? d.sleepPct ?? 58)
                }()

                let energy5m = AppleHealthExportImporter.buildContinuousFiveMinuteEnergySamples(
                    stressSamples: stress5m,
                    startingEnergy: startingEnergy,
                    recoveryPct: d.recoveryPct,
                    sleepPct: d.sleepPct,
                    sleepStartEpoch: sleepStartEp,
                    sleepEndEpoch: sleepEndEp,
                    workoutSpans: workoutSpans,
                    asleepMinutes: d.asleepMinutes,
                    dayStartEpoch: Int64(cal.startOfDay(for: snap.day).timeIntervalSince1970)
                )
                if let lastPt = energy5m.last {
                    d.energySamples5m = energy5m
                    d.energyBankPercent = Int(lastPt.value.rounded())
                    prevDayEndEnergy = lastPt.value
                    prevDayIso = iso
                    hasReal = true
                }
            }

            // Advance causal baselines AFTER computing today
            if let h = d.hrvMs, h > 2 { priorLnHrv.append(log(h)) }
            if let r = d.restingHrBpm { priorRhr.append(r) }
            if let rr = d.respRateRpm { priorResp.append(rr) }
            if let t = d.wristTempAbsoluteC { priorTemp.append(t) }

            if hasReal {
                realHistory[iso] = d
                updatedAny = true
            }
        }

        if updatedAny {
            hasImportedOrPairedRealData = true
            clearPreviewSeededArtifactsOnRealData()
            healthKitAuthorized = true
            dataRevision += 1
            persistState()
        }
    }
    #endif

    func toggleWhoopScan() {
        if whoopScanning {
            whoopBleReader.stopScanning()
            whoopScanning = false
        } else {
            whoopScanning = true
            whoopBleReader.startScanning(for: nil)
        }
    }

    func disconnectWhoop() {
        whoopBleReader.disconnect()
        whoopConnected = false
        whoopScanning = false
    }

    func forceWhoopSync() {
        whoopBleReader.setRealtimeHR(enabled: true)
        whoopBleReader.requestHistoricalData()
    }

    private func bindWhoopBle() {
        whoopBleReader.$connectionState
            .receive(on: RunLoop.main)
            .sink { [weak self] st in
                guard let self else { return }
                self.whoopConnected = (st == .ready)
                self.whoopScanning = (st == .scanning)
                if st == .ready {
                    self.whoopDeviceName = self.whoopBleReader.strapName ?? "WHOOP 5.0"
                }
            }
            .store(in: &cancellables)

        whoopBleReader.$latestBatteryPercent
            .receive(on: RunLoop.main)
            .sink { [weak self] pct in
                if let pct { self?.whoopBatteryPct = pct }
            }
            .store(in: &cancellables)

        bleStreamTask = Task { [weak self] in
            guard let self else { return }
            for await reading in self.whoopBleReader.readings {
                if Task.isCancelled { break }
                self.whoopPacketsReceived += 1
                switch reading {
                case .standardHeartRate(let bpm, let rrMs, _, let ts):
                    let iso = self.isoFormatter.string(from: ts)
                    var d = self.realHistory[iso] ?? RealBiometricDaySummary(dateIso: iso)
                    d.liveHrBpm = bpm
                    if !rrMs.isEmpty {
                        var sqDiffs: [Double] = []
                        for i in 1..<rrMs.count {
                            let diff = Double(rrMs[i] - rrMs[i - 1])
                            sqDiffs.append(diff * diff)
                        }
                        if !sqDiffs.isEmpty {
                            let rmssd = sqrt(sqDiffs.reduce(0, +) / Double(sqDiffs.count))
                            if (8.0...220.0).contains(rmssd) {
                                d.hrvMs = AppleHealthExportImporter.round1(rmssd)
                            }
                        }
                    }
                    self.realHistory[iso] = d
                    self.hasImportedOrPairedRealData = true
                    self.clearPreviewSeededArtifactsOnRealData()
                case .battery(let pct, _, _, _):
                    self.whoopBatteryPct = pct
                case .log(let msg):
                    self.bleLogs = ([msg] + self.bleLogs).prefix(20).map { $0 }
                default:
                    break
                }
            }
        }
    }

    // MARK: - AI Coach Context & Multi-Turn Chat

    private func buildBiometricContextJson() -> (json: String, highlights: [String]) {
        let av = dataAvailability
        let d = currentDaySummary
        var highlights: [String] = []
        if av.hasRecoveryData { highlights.append("recuperación del \(recoveryPercent)%") }
        if av.hasStrainData { highlights.append("esfuerzo del \(strainPercent)%") }
        if av.hasSleepData { highlights.append("sueño de \(sleepDurationText) con puntuación \(sleepPercent)%") }
        if av.hasHrvData { highlights.append(String(format: "VFC de %.1f ms", locale: Locale(identifier: "es_ES"), hrvMs)) }
        if av.hasRestingHrData { highlights.append(String(format: "FC en reposo de %.1f ppm", locale: Locale(identifier: "es_ES"), restingHrBpm)) }
        if av.hasRespData { highlights.append(String(format: "FR de %.1f rpm", locale: Locale(identifier: "es_ES"), respRateRpm)) }
        if let sp = spo2Value { highlights.append(String(format: "SpO2 de %.1f%%", locale: Locale(identifier: "es_ES"), sp)) }
        if av.hasStressData { highlights.append("estrés actual de \(displayStressScore) y media diaria de \(stressAvg ?? stressScore) sobre 100") }
        if av.hasEnergyData { highlights.append("batería de energía al \(energyPercent)%") }
        if let steps = stepsCount { highlights.append("\(steps) pasos") }

        let dayJournal = journalCheckinsByDate[selectedDateIso] ?? [:]
        let allManualSpecs = allCatalogAndCustomEntries.filter { !$0.isAuto }
        let yesHabits = allManualSpecs.filter { dayJournal[$0.id] == .yes }.map(\.title)
        let noHabits = allManualSpecs.filter { dayJournal[$0.id] == .no }.map(\.title)
        let noteToday = journalNote(for: selectedDateIso)
        if !noteToday.isEmpty {
            highlights.append("nota del diario: «\(noteToday)»")
        }
        if totalCaloriesToday > 0 {
            highlights.append("nutrición hoy: \(totalCaloriesToday) kcal (\(totalProteinToday)g P, \(totalCarbsToday)g C, \(totalFatToday)g G)")
        }

        let recentNotes: [String: String] = {
            var dict: [String: String] = [:]
            for item in trailingCalendarSummaries(days: 7) {
                let n = (journalNotesByDate[item.iso] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !n.isEmpty { dict[item.iso] = n }
            }
            return dict
        }()

        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: userProfile)
        let perfil: [String: Any] = [
            "nombre": userProfile.displayFirstName.isEmpty ? "Usuario" : userProfile.displayFirstName,
            "nombre_completo": userProfile.fullName.isEmpty ? "Usuario" : userProfile.fullName,
            "fecha_nacimiento": userProfile.birthDateIso ?? "NO_INDICADA",
            "edad": Int(userProfile.effectiveAgeYears.rounded(.down)),
            "sexo": userProfile.sex.rawValue,
            "peso_kg": latestBodyWeightKg ?? userProfile.weightKg,
            "altura_cm": userProfile.heightCm,
            "imc": norms.bmi,
            "fc_max_tanaka": norms.maxHrBpm,
            "vfc_esperada_ms": norms.hrvExpectedMs,
            "meta_sueno_h": norms.sleepTargetHours,
            "meta_hidratacion_l": norms.hydrationGoalLiters
        ]

        var metricas: [String: Any] = [:]
        metricas["recuperacion_pct"] = av.hasRecoveryData ? (recoveryPercent as Any) : "NO_DISPONIBLE"
        metricas["esfuerzo_pct"] = av.hasStrainData ? (strainPercent as Any) : "NO_DISPONIBLE"
        metricas["strain_21"] = av.hasStrainData ? (strain21 as Any) : "NO_DISPONIBLE"
        metricas["sueno_pct"] = av.hasSleepData ? (sleepPercent as Any) : "NO_DISPONIBLE"
        metricas["sueno_duracion"] = av.hasSleepData ? (sleepDurationText as Any) : "NO_DISPONIBLE"
        metricas["sueno_profundo_min"] = (d?.deepMinutes ?? 0) > 0 ? ((d?.deepMinutes ?? 0) as Any) : "NO_DISPONIBLE"
        metricas["sueno_rem_min"] = (d?.remMinutes ?? 0) > 0 ? ((d?.remMinutes ?? 0) as Any) : "NO_DISPONIBLE"
        metricas["vfc_ms"] = av.hasHrvData ? (hrvMs as Any) : "NO_DISPONIBLE"
        metricas["fc_reposo_ppm"] = av.hasRestingHrData ? (restingHrBpm as Any) : "NO_DISPONIBLE"
        metricas["frecuencia_respiratoria_rpm"] = av.hasRespData ? (respRateRpm as Any) : "NO_DISPONIBLE"
        metricas["spo2_pct"] = spo2Value.map { $0 as Any } ?? "NO_DISPONIBLE"
        metricas["temperatura_muneca_c"] = wristTempAbsoluteC.map { $0 as Any } ?? "NO_DISPONIBLE"
        metricas["estres_actual"] = av.hasStressData ? (displayStressScore as Any) : "NO_DISPONIBLE"
        metricas["estres_medio"] = av.hasStressData ? ((stressAvg ?? stressScore) as Any) : "NO_DISPONIBLE"
        metricas["energia_pct"] = av.hasEnergyData ? (energyPercent as Any) : "NO_DISPONIBLE"
        metricas["pasos"] = stepsCount.map { $0 as Any } ?? "NO_DISPONIBLE"
        metricas["vo2_max"] = latestVo2Max.map { $0 as Any } ?? "NO_DISPONIBLE"
        if workoutsToday.isEmpty {
            metricas["entrenamientos_hoy"] = "NINGUNO"
        } else {
            metricas["entrenamientos_hoy"] = workoutsToday.map { "\($0.title) \($0.durationMin)min \($0.kcal)kcal" }
        }

        let diarioHoy: [String: Any] = [
            "marcados_si": yesHabits,
            "marcados_no": noHabits,
            "nota_del_dia": noteToday.isEmpty ? "SIN_NOTA" : noteToday,
            "notas_recientes_7d": recentNotes
        ]

        let nutricionHoy: [String: Any] = [
            "kcal_ingeridas": totalCaloriesToday,
            "proteina_g": totalProteinToday,
            "carbos_g": totalCarbsToday,
            "grasas_g": totalFatToday,
            "calidad_media": foodQualityScore.map { $0 as Any } ?? "SIN_COMIDAS",
            "hidratacion_ml": Int(totalHydrationTodayMl.rounded()),
            "cafeina_mg": Int(totalCaffeineTodayMg.rounded()),
            "alcohol_bebidas": totalAlcoholTodayDrinks,
            "comidas_registradas": mealsToday.map { "\($0.timeLabel) \($0.title) (\($0.kcal) kcal, P:\($0.proteinG)g C:\($0.carbsG)g G:\($0.fatG)g)" }
        ]

        let latestLabsSummary: [[String: Any]] = latestBiomarkersByName.prefix(14).map { b in
            [
                "nombre": b.name,
                "valor": b.value,
                "unidad": b.unit,
                "estado": b.status.rawValue,
                "categoria": b.category
            ]
        }

        let bioSnap = biologicalAgeSnapshot()
        let edadBiologicaDict: [String: Any] = [
            "edad_biologica_anos": bioSnap.hasData ? bioSnap.eval.bioAgeYears : bioSnap.eval.chronoAgeYears,
            "edad_cronologica_anos": bioSnap.eval.chronoAgeYears,
            "diferencia_total_anos": bioSnap.hasData ? bioSnap.eval.deltaYears : 0.0,
            "impacto_sueno_anos": bioSnap.eval.sleepDelta,
            "impacto_actividad_anos": bioSnap.eval.activityDelta,
            "impacto_fitness_anos": bioSnap.eval.fitnessDelta,
            "impacto_vfc_anos": bioSnap.eval.autonomicDelta,
            "impacto_cuerpo_anos": bioSnap.eval.bodyDelta,
            "impacto_analiticas_anos": bioSnap.eval.bloodLabsDelta
        ]

        let nowFmt = DateFormatter()
        nowFmt.dateFormat = "HH:mm"
        var payload: [String: Any] = [
            "hora_local_actual": nowFmt.string(from: Date()),
            "fecha_seleccionada": selectedDateIso,
            "origen_datos": hasImportedOrPairedRealData ? "Apple Health / Sensores reales" : "Modo vista previa",
            "perfil": perfil,
            "metricas_hoy": metricas,
            "edad_biologica": edadBiologicaDict,
            "diario_hoy": diarioHoy,
            "nutricion_hoy": nutricionHoy
        ]
        if !latestLabsSummary.isEmpty {
            payload["analiticas_recientes"] = latestLabsSummary
        }

        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
           let str = String(data: data, encoding: .utf8) {
            return (str, highlights)
        }
        return ("{}", highlights)
    }

    /// Context-aware suggested questions adapted to today's actual physiological metrics!
    var dynamicCoachSuggestions: [CoachDynamicSuggestion] {
        var list: [CoachDynamicSuggestion] = []
        let avail = dataAvailability
        let debt = currentDaySummary?.sleepDebtMinutes ?? 0

        if avail.hasRecoveryData && recoveryPercent < 50 {
            list.append(CoachDynamicSuggestion(
                id: "low_rec",
                icon: "heart.text.square.fill",
                title: "Recuperación baja (\(recoveryPercent)%)",
                subtitle: "¿Qué hago hoy para remontar?",
                prompt: "Hoy tengo la recuperación en \(recoveryPercent)%. Analiza mis constantes reales y dime cómo plantear el día y el entrenamiento."
            ))
        } else if avail.hasRecoveryData && recoveryPercent >= 72 {
            list.append(CoachDynamicSuggestion(
                id: "high_rec",
                icon: "flame.fill",
                title: "Recuperación alta (\(recoveryPercent)%)",
                subtitle: "Plan de sesión intensa",
                prompt: "Hoy amanecí con \(recoveryPercent)% de recuperación. ¿Qué entrenamiento me recomiendas aprovechar según mi carga y frescura muscular?"
            ))
        } else {
            list.append(CoachDynamicSuggestion(
                id: "train_today",
                icon: "figure.run",
                title: "¿Entreno fuerte hoy?",
                subtitle: "Según mi recuperación real",
                prompt: "¿Debería entrenar fuerte hoy o ir suave según mis datos reales?"
            ))
        }

        if debt >= 35 {
            list.append(CoachDynamicSuggestion(
                id: "sleep_debt",
                icon: "moon.zzz.fill",
                title: "Deuda de sueño (\(debt) min)",
                subtitle: "Cómo recuperarla esta semana",
                prompt: "Tengo \(debt) minutos de deuda de sueño y dormí \(sleepDurationText). Dame un plan realista para recuperarla sin arruinar mis horarios."
            ))
        } else {
            list.append(CoachDynamicSuggestion(
                id: "sleep_check",
                icon: "moon.stars.fill",
                title: "Analizar mi sueño",
                subtitle: "Fases y descanso real",
                prompt: "Analiza mi última noche de sueño y dime qué puedo mejorar hoy"
            ))
        }

        if let nutScore = foodQualityScore, nutScore < 65 {
            list.append(CoachDynamicSuggestion(
                id: "nut_fix",
                icon: "fork.knife",
                title: "Mejorar mi nutrición (\(nutScore))",
                subtitle: "Qué cenar hoy para equilibrar",
                prompt: "Mi puntuación de nutrición hoy está en \(nutScore) con \(totalCaloriesToday) kcal y \(totalProteinToday) g de proteína. ¿Qué cena rápida me ayuda a cuadrar el día?"
            ))
        } else if !latestBiomarkersByName.isEmpty {
            list.append(CoachDynamicSuggestion(
                id: "lab_review",
                icon: "cross.case.fill",
                title: "Revisar mi analítica",
                subtitle: "\(latestBiomarkersByName.count) biomarcadores guardados",
                prompt: "Revisa los biomarcadores de mi última analítica junto con mi sueño y recuperación, y dime qué prioridades tengo."
            ))
        } else {
            list.append(CoachDynamicSuggestion(
                id: "open_food",
                icon: "fork.knife",
                title: "¿Qué me conviene cenar hoy?",
                subtitle: "Adaptado a mi gasto real",
                prompt: "Con mi actividad y comida de hoy, ¿qué cena me recomiendas para dormir mejor y recuperar bien?"
            ))
        }

        return list
    }

    func sendCoachPrompt(_ rawPrompt: String, jpegImageData: Data? = nil, attachedPhotoFilename: String? = nil) {
        let trimmed = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = trimmed.isEmpty && jpegImageData != nil ? "Analiza esta imagen en relación con mis datos reales de salud y entrenamiento." : trimmed
        guard !prompt.isEmpty, !isCoachThinking else { return }

        let now = Date()
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"
        let tsLabel = timeFmt.string(from: now)

        let historySnap = Array(coachMessages.suffix(16))
        let userMsg = CoachChatMessage(
            id: UUID().uuidString,
            isUser: true,
            text: prompt,
            timestampLabel: tsLabel,
            isSuggestionChip: false,
            attachedPhotoFilename: attachedPhotoFilename
        )
        coachMessages.append(userMsg)
        syncCurrentChatIntoThreads(updatedAtLabel: tsLabel)
        isCoachThinking = true

        let ctx = buildBiometricContextJson()
        let key = geminiApiKey
        let model = selectedGeminiModel
        let userName = userProfile.userName
        let missing = dataAvailability.missingCategoryNames
        let prevId = activeCoachInteractionId

        Task { [weak self] in
            let result = await GeminiCoachService.shared.askLiveCoach(
                prompt: prompt,
                apiKey: key,
                selectedModel: model,
                userName: userName,
                currentDate: now,
                biometricContextJson: ctx.json,
                availableHighlights: ctx.highlights,
                missingCategories: missing,
                history: historySnap,
                previousInteractionId: prevId,
                jpegImageData: jpegImageData
            )
            await MainActor.run {
                guard let self else { return }
                self.isCoachThinking = false
                if let newId = result.interactionId {
                    self.activeCoachInteractionId = newId
                }
                let replyFmt = DateFormatter()
                replyFmt.dateFormat = "HH:mm"
                let replyTs = replyFmt.string(from: Date())
                self.coachMessages.append(
                    CoachChatMessage(
                        id: UUID().uuidString,
                        isUser: false,
                        verdictTitle: result.verdictTitle.isEmpty ? nil : result.verdictTitle,
                        text: result.text,
                        bullets: result.bullets,
                        timestampLabel: replyTs,
                        isSuggestionChip: false,
                        modelUsed: result.modelUsed
                    )
                )
                self.syncCurrentChatIntoThreads(updatedAtLabel: replyTs)
            }
        }
    }

    private func syncCurrentChatIntoThreads(updatedAtLabel: String) {
        guard !coachMessages.isEmpty else { return }
        let todayIso = isoFormatter.string(from: Date())
        let firstUserText = coachMessages.first(where: { $0.isUser })?.text ?? "Conversación"
        let cleanTitle = String(firstUserText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(48))

        if let activeId = activeCoachThreadId, let idx = coachThreads.firstIndex(where: { $0.id == activeId }) {
            coachThreads[idx].messages = coachMessages
            coachThreads[idx].updatedAtLabel = updatedAtLabel
            if coachThreads[idx].title.isEmpty { coachThreads[idx].title = cleanTitle }
            let updated = coachThreads.remove(at: idx)
            coachThreads.insert(updated, at: 0)
        } else {
            let newId = UUID().uuidString
            activeCoachThreadId = newId
            let thread = CoachChatThread(
                id: newId,
                title: cleanTitle.isEmpty ? "Consulta Coach IA" : cleanTitle,
                dateIso: todayIso,
                updatedAtLabel: updatedAtLabel,
                messages: coachMessages
            )
            coachThreads.insert(thread, at: 0)
        }
        if coachThreads.count > 30 {
            coachThreads = Array(coachThreads.prefix(30))
        }
        persistState()
    }

    func selectCoachThread(_ id: String) {
        guard let thread = coachThreads.first(where: { $0.id == id }) else { return }
        activeCoachThreadId = thread.id
        coachMessages = thread.messages
        activeCoachInteractionId = nil
        isCoachThinking = false
        persistState()
    }

    func deleteCoachThread(_ id: String) {
        coachThreads.removeAll { $0.id == id }
        if activeCoachThreadId == id {
            if let next = coachThreads.first {
                activeCoachThreadId = next.id
                coachMessages = next.messages
            } else {
                activeCoachThreadId = nil
                coachMessages = []
            }
            activeCoachInteractionId = nil
        }
        persistState()
    }

    func startNewCleanChat() {
        coachMessages = []
        activeCoachThreadId = nil
        activeCoachInteractionId = nil
        isCoachThinking = false
        persistState()
    }

    // MARK: - Home Layout Customization (N2)

    func toggleHomeSection(_ kind: HomeSectionKind) {
        if homeLayout.hiddenSections.contains(kind) {
            homeLayout.hiddenSections.removeAll { $0 == kind }
        } else {
            // Keep at least 1 section visible
            let visibleCount = HomeSectionKind.allCases.filter { !homeLayout.hiddenSections.contains($0) }.count
            if visibleCount > 1 {
                homeLayout.hiddenSections.append(kind)
            }
        }
        persistState()
    }

    func moveHomeSection(_ kind: HomeSectionKind, direction: Int) {
        var order = homeLayout.normalizedOrder
        guard let idx = order.firstIndex(of: kind) else { return }
        let target = idx + direction
        guard order.indices.contains(target) else { return }
        order.swapAt(idx, target)
        homeLayout.sectionOrder = order
        persistState()
    }

    func toggleHealthMonitorMetric(_ kind: HealthMetricKind) {
        if homeLayout.hiddenHealthMetrics.contains(kind) {
            homeLayout.hiddenHealthMetrics.removeAll { $0 == kind }
        } else {
            let visibleCount = HealthMetricKind.allCases.filter { !homeLayout.hiddenHealthMetrics.contains($0) }.count
            if visibleCount > 1 {
                homeLayout.hiddenHealthMetrics.append(kind)
            }
        }
        persistState()
    }

    func resetHomeLayout() {
        homeLayout = HomeLayoutPreferences()
        persistState()
    }

    // MARK: - Manual Scale & Blood Pressure Logging + Lab Reports / Biomarkers (P2 & N6)

    func logManualScaleReading(
        date: Date = Date(),
        weightKg: Double?,
        bodyFatPct: Double?,
        leanMassKg: Double?,
        systolicBp: Int?,
        diastolicBp: Int?
    ) {
        let iso = isoFormatter.string(from: date)
        var d = activeHistory[iso] ?? RealBiometricDaySummary(dateIso: iso)
        if let w = weightKg, w > 20, w < 300 {
            d.bodyWeightKg = AppleHealthExportImporter.round1(w)
            userProfile.weightKg = AppleHealthExportImporter.round1(w)
        }
        if let f = bodyFatPct, f >= 2, f <= 70 {
            d.bodyFatPct = AppleHealthExportImporter.round1(f)
            userProfile.bodyFatPct = AppleHealthExportImporter.round1(f)
        }
        if let l = leanMassKg, l > 15, l < 220 {
            d.leanMassKg = AppleHealthExportImporter.round1(l)
        } else if let w = d.bodyWeightKg, let f = d.bodyFatPct {
            d.leanMassKg = AppleHealthExportImporter.round1(w * (1.0 - f / 100.0))
        }
        if let sys = systolicBp, let dia = diastolicBp, sys >= 70, sys <= 240, dia >= 40, dia <= 150 {
            d.systolicBp = sys
            d.diastolicBp = dia
        }

        if hasImportedOrPairedRealData {
            realHistory[iso] = d
        } else {
            simulatedHistory[iso] = d
        }
        dataRevision += 1
        persistState()
    }

    func bodyMetricSeries(for kind: BodyCompositionMetricKind, spanDays: Int, windowPageOffset: Int) -> MetricWindowSeries {
        customWindowSeries(spanDays: spanDays, windowPageOffset: windowPageOffset) { day in
            switch kind {
            case .weight: return day.bodyWeightKg
            case .bodyFat: return day.bodyFatPct
            case .leanMass: return day.leanMassKg
            case .bloodPressure: return day.systolicBp.map { Double($0) }
            }
        }
    }

    func bodyMetricHistoryEntries(for kind: BodyCompositionMetricKind, limit: Int = 40) -> [(dateIso: String, primary: String, secondary: String?)] {
        let sorted = activeHistory.keys.sorted(by: >)
        var out: [(String, String, String?)] = []
        for iso in sorted {
            guard let d = activeHistory[iso] else { continue }
            switch kind {
            case .weight:
                if let v = d.bodyWeightKg {
                    out.append((iso, String(format: "%.1f kg", locale: Locale(identifier: "es_ES"), v), d.bodyFatPct.map { String(format: "Grasa %.1f%%", locale: Locale(identifier: "es_ES"), $0) }))
                }
            case .bodyFat:
                if let v = d.bodyFatPct {
                    out.append((iso, String(format: "%.1f %%", locale: Locale(identifier: "es_ES"), v), d.bodyWeightKg.map { String(format: "Peso %.1f kg", locale: Locale(identifier: "es_ES"), $0) }))
                }
            case .leanMass:
                if let v = d.leanMassKg {
                    out.append((iso, String(format: "%.1f kg", locale: Locale(identifier: "es_ES"), v), d.bodyWeightKg.map { String(format: "Peso %.1f kg", locale: Locale(identifier: "es_ES"), $0) }))
                }
            case .bloodPressure:
                if let sys = d.systolicBp, let dia = d.diastolicBp {
                    let tone = (sys < 125 && dia < 82) ? "Óptima" : ((sys < 135 && dia < 88) ? "Normal" : "Elevada")
                    out.append((iso, "\(sys)/\(dia) mmHg", tone))
                }
            }
            if out.count >= limit { break }
        }
        return out
    }

    /// Unified 30-day Biological Age snapshot (Wearables + Body Composition + Blood Test Biomarkers).
    func biologicalAgeSnapshot() -> (
        eval: BiologicalAgeEvaluation,
        hasData: Bool,
        meanRhr: Double?,
        meanHrv: Double?,
        meanSleep: Double?,
        meanSteps: Int?,
        vo2Val: Double?
    ) {
        let recent30 = trailingCalendarSummaries(days: 30)
        let rhrVals = recent30.compactMap { $0.summary?.restingHrBpm }
        let hrvVals = recent30.compactMap { $0.summary?.hrvMs }
        let sleepVals = recent30.compactMap { $0.summary?.asleepMinutes.map { Double($0) / 60.0 } }
        let stepsVals = recent30.compactMap { $0.summary?.stepsCount }
        let vo2Val = latestVo2Max
        let biomarkers = latestBiomarkersByName

        let meanRhr = rhrVals.isEmpty ? nil : (rhrVals.reduce(0, +) / Double(rhrVals.count))
        let meanHrv = hrvVals.isEmpty ? nil : (hrvVals.reduce(0, +) / Double(hrvVals.count))
        let meanSleep = sleepVals.isEmpty ? nil : (sleepVals.reduce(0, +) / Double(sleepVals.count))
        let meanSteps = stepsVals.isEmpty ? nil : (stepsVals.reduce(0, +) / stepsVals.count)

        let hasData = meanRhr != nil || meanHrv != nil || meanSleep != nil || meanSteps != nil || vo2Val != nil || !biomarkers.isEmpty
        let eval = WhoopPhysiologyEngine.computeBiologicalAge(
            profile: userProfile,
            meanRhr: meanRhr,
            meanHrv: meanHrv,
            meanSleepHours: meanSleep,
            meanSteps: meanSteps,
            vo2Max: vo2Val,
            latestWeightKg: latestBodyWeightKg,
            latestBodyFatPct: latestBodyFatPct,
            labBiomarkers: biomarkers
        )
        return (eval, hasData, meanRhr, meanHrv, meanSleep, meanSteps, vo2Val)
    }

    var latestBiomarkersByName: [LabBiomarkerItem] {
        let sortedReports = labReports.sorted { $0.dateIso > $1.dateIso }
        var seen = Set<String>()
        var result: [LabBiomarkerItem] = []
        for rep in sortedReports {
            for b in rep.biomarkers {
                let key = b.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
                if seen.insert(key).inserted {
                    result.append(b)
                }
            }
        }
        return result
    }

    func saveLabReport(_ report: LabReportRecord) {
        if let idx = labReports.firstIndex(where: { $0.id == report.id }) {
            labReports[idx] = report
        } else {
            labReports.insert(report, at: 0)
        }
        labReports.sort { $0.dateIso > $1.dateIso }
        dataRevision += 1
        persistState()
    }

    func deleteLabReport(id: String) {
        labReports.removeAll { $0.id == id }
        dataRevision += 1
        persistState()
    }

    func addManualBiomarker(_ item: LabBiomarkerItem, dateIso: String? = nil) {
        let iso = dateIso ?? isoFormatter.string(from: Date())
        if let idx = labReports.firstIndex(where: { $0.dateIso == iso && $0.title == "Biomarcadores manuales" }) {
            labReports[idx].biomarkers.insert(item, at: 0)
        } else {
            let rep = LabReportRecord(
                id: UUID().uuidString,
                dateIso: iso,
                title: "Biomarcadores manuales",
                sourceLabel: "Registro manual",
                summary: "Registro manual de biomarcadores clínicos.",
                biomarkers: [item]
            )
            labReports.insert(rep, at: 0)
        }
        labReports.sort { $0.dateIso > $1.dateIso }
        dataRevision += 1
        persistState()
    }

    // MARK: - Weekly Review Computation & AI Analysis (N5)

    func computeWeeklyReview(anchorDate: Date? = nil) -> WeeklyReviewReport {
        let cal = Calendar.current
        let anchor = cal.startOfDay(for: anchorDate ?? selectedDate)
        let curDates: [Date] = (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: anchor) }
        let prevDates: [Date] = (7..<14).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: anchor) }

        let curIsos = curDates.map { isoFormatter.string(from: $0) }
        let prevIsos = prevDates.map { isoFormatter.string(from: $0) }
        let curDays = curIsos.compactMap { activeHistory[$0] }
        let prevDays = prevIsos.compactMap { activeHistory[$0] }

        func avgInt(_ vals: [Int]) -> Int? {
            guard !vals.isEmpty else { return nil }
            return Int((Double(vals.reduce(0, +)) / Double(vals.count)).rounded())
        }
        func avgDbl(_ vals: [Double]) -> Double? {
            guard !vals.isEmpty else { return nil }
            return vals.reduce(0, +) / Double(vals.count)
        }

        let avgRec = avgInt(curDays.compactMap(\.recoveryPct))
        let prevRec = avgInt(prevDays.compactMap(\.recoveryPct))
        let avgHrv = avgDbl(curDays.compactMap(\.hrvMs))
        let prevHrv = avgDbl(prevDays.compactMap(\.hrvMs))
        let avgRhr = avgDbl(curDays.compactMap(\.restingHrBpm))
        let prevRhr = avgDbl(prevDays.compactMap(\.restingHrBpm))
        let avgSleepMin = avgInt(curDays.compactMap(\.asleepMinutes).filter { $0 > 0 })
        let prevSleepMin = avgInt(prevDays.compactMap(\.asleepMinutes).filter { $0 > 0 })
        let avgSleepPct = avgInt(curDays.compactMap(\.sleepPct))
        let sleepDebt = curDays.last?.sleepDebtMinutes ?? curDays.compactMap(\.sleepDebtMinutes).last ?? 0
        let avgStrain = avgInt(curDays.compactMap(\.strainPct))
        let prevStrain = avgInt(prevDays.compactMap(\.strainPct))

        let curWorkouts = curDays.flatMap(\.workouts)
        let prevWorkouts = prevDays.flatMap(\.workouts)
        let totalWkMin = curWorkouts.reduce(0) { $0 + $1.durationMin }

        let cardioAnalysis = trainingLoadAnalysis(tab: .cardio, spanDays: 14, windowPageOffset: 0)

        let curNutScores = curIsos.compactMap { nutritionScore(for: $0) }
        let prevNutScores = prevIsos.compactMap { nutritionScore(for: $0) }
        let avgNut = avgInt(curNutScores)
        let prevNut = avgInt(prevNutScores)

        let curNetVals = curIsos.compactMap { iso -> Int? in
            let meals = mealsByDate[iso] ?? []
            guard !meals.isEmpty else { return nil }
            return netEnergyKcal(for: iso).net
        }
        let avgNet = avgInt(curNetVals)
        let avgSteps = avgInt(curDays.compactMap(\.stepsCount).filter { $0 > 0 })

        // Top checked habits during this 7-day window
        var habitCounts: [String: Int] = [:]
        for iso in curIsos {
            for (hid, st) in (journalCheckinsByDate[iso] ?? [:]) where st == .yes {
                habitCounts[hid, default: 0] += 1
            }
        }
        let catalogMap = Dictionary(uniqueKeysWithValues: allCatalogAndCustomEntries.map { ($0.id, ($0.emoji, $0.title)) })
        let topHabits: [(emoji: String, title: String, count: Int)] = habitCounts
            .sorted { $0.value > $1.value }
            .prefix(4)
            .compactMap { k, v in
                guard let meta = catalogMap[k] else { return nil }
                return (meta.0, meta.1, v)
            }

        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "es_ES")
        fmt.dateFormat = "d MMM"
        let startLbl = curDates.first.map { fmt.string(from: $0).replacingOccurrences(of: ".", with: "") } ?? ""
        let endLbl = curDates.last.map { fmt.string(from: $0).replacingOccurrences(of: ".", with: "") } ?? ""
        let weekKey = "\(curIsos.first ?? "")_\(curIsos.last ?? "")_r\(dataRevision)"

        return WeeklyReviewReport(
            weekKey: weekKey,
            dateRangeLabel: "\(startLbl) – \(endLbl)",
            daysWithData: curDays.count,
            avgRecovery: avgRec,
            recoveryDelta: (avgRec != nil && prevRec != nil) ? (avgRec! - prevRec!) : nil,
            avgHrv: avgHrv,
            hrvDelta: (avgHrv != nil && prevHrv != nil) ? (avgHrv! - prevHrv!) : nil,
            avgRhr: avgRhr,
            rhrDelta: (avgRhr != nil && prevRhr != nil) ? (avgRhr! - prevRhr!) : nil,
            avgSleepMinutes: avgSleepMin,
            sleepMinutesDelta: (avgSleepMin != nil && prevSleepMin != nil) ? (avgSleepMin! - prevSleepMin!) : nil,
            avgSleepPct: avgSleepPct,
            sleepDebtMinutes: sleepDebt,
            avgStrainPct: avgStrain,
            strainDelta: (avgStrain != nil && prevStrain != nil) ? (avgStrain! - prevStrain!) : nil,
            workoutsCount: curWorkouts.count,
            totalWorkoutMinutes: totalWkMin,
            workoutsDelta: curWorkouts.count - prevWorkouts.count,
            cardioLoadCurrent: cardioAnalysis.currentLoad,
            cardioLoadState: cardioAnalysis.currentState,
            avgNutritionScore: avgNut,
            nutritionScoreDelta: (avgNut != nil && prevNut != nil) ? (avgNut! - prevNut!) : nil,
            avgNetEnergyKcal: avgNet,
            avgSteps: avgSteps,
            topHabits: topHabits
        )
    }

    func generateWeeklyReviewAI(report: WeeklyReviewReport, force: Bool = false) {
        if !force, weeklyAiInsightsCache[report.weekKey] != nil { return }
        guard !isGeneratingWeeklyReviewAI else { return }
        isGeneratingWeeklyReviewAI = true
        let key = geminiApiKey
        let model = selectedGeminiModel
        let uName = userProfile.displayFirstName

        Task { [weak self] in
            let insight = await GeminiCoachService.shared.generateWeeklyReviewInsight(
                report: report,
                userName: uName,
                apiKey: key,
                selectedModel: model
            )
            await MainActor.run {
                guard let self else { return }
                self.isGeneratingWeeklyReviewAI = false
                self.weeklyAiInsightsCache[report.weekKey] = insight
                self.persistState()
            }
        }
    }

    // MARK: - WidgetKit Shared Snapshot Bridge (N7)

    func publishWidgetSnapshot(triggerReload: Bool = true, forceReload: Bool = false) {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let todayIso = isoFormatter.string(from: todayStart)
        let yesterdayIso = cal.date(byAdding: .day, value: -1, to: todayStart).map { isoFormatter.string(from: $0) } ?? ""

        let targetDay: RealBiometricDaySummary? = activeHistory[todayIso] ?? latestAvailableDay ?? currentDaySummary
        let targetIso = targetDay?.dateIso ?? todayIso
        let dateLbl: String = {
            if targetIso == todayIso { return "Hoy" }
            if targetIso == yesterdayIso { return "Ayer" }
            if let dt = isoFormatter.date(from: targetIso) {
                let fmt = DateFormatter()
                fmt.locale = Locale(identifier: "es_ES")
                fmt.dateFormat = "d MMM"
                return fmt.string(from: dt).replacingOccurrences(of: ".", with: "")
            }
            return "Hoy"
        }()

        let nutTotals = nutritionDayTotals(for: todayIso)
        let goals = effectiveNutritionGoals
        let sleepDur: String = {
            if let m = targetDay?.asleepMinutes, m > 0 {
                return "\(m / 60)h \(String(format: "%02d", m % 60))m"
            }
            return "--"
        }()

        let recForTarget: Int = targetDay?.recoveryPct
            ?? trailingCalendarSummaries(days: 7).compactMap({ $0.summary?.recoveryPct }).last
            ?? 65
        let optRange = WhoopPhysiologyEngine.optimalTargetRange(for: recForTarget, profile: userProfile)
        let optLo = Int((optRange.lowerBound * 100.0).rounded())
        let optHi = Int((optRange.upperBound * 100.0).rounded())

        let snap = ImprovingWidgetSnapshot(
            dateIso: targetIso,
            dateLabel: dateLbl,
            strainPct: targetDay?.strainPct ?? 0,
            recoveryPct: targetDay?.recoveryPct,
            sleepPct: targetDay?.sleepPct,
            energyPct: targetDay?.energyBankPercent,
            stressScore: targetDay?.stressSamples5m.last.map { Int($0.value.rounded()) } ?? targetDay?.stressScore,
            hrvMs: targetDay?.hrvMs,
            restingHrBpm: targetDay?.restingHrBpm,
            sleepDurationText: sleepDur,
            nutritionScore: nutTotals.score,
            caloriesToday: nutTotals.kcal,
            caloriesGoal: goals.kcal,
            proteinG: Int(nutTotals.proteinG.rounded()),
            carbsG: Int(nutTotals.carbsG.rounded()),
            fatG: Int(nutTotals.fatG.rounded()),
            stepsCount: targetDay?.stepsCount,
            optimalStrainLowPct: optLo,
            optimalStrainHighPct: optHi,
            updatedAt: Date()
        )
        WidgetSnapshotStore.save(snap, triggerReload: triggerReload, forceReload: forceReload)
    }

    func updateGeminiConfig(apiKey: String, model: String) {
        geminiApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        selectedGeminiModel = model
        dataRevision += 1
        persistState()
    }

    // MARK: - Async Debounced Background Persistence (P3 — Zero Main-Thread Jank!)

    private func buildPersistedSnapshot() -> PersistedSnapshot {
        PersistedSnapshot(
            userProfile: userProfile,
            isDarkMode: BevelColors.isDarkMode,
            hasImportedOrPairedRealData: hasImportedOrPairedRealData,
            realHistory: realHistory,
            journalCheckins: journalCheckinsByDate,
            journalMoodByDate: journalMoodByDate,
            geminiApiKey: geminiApiKey,
            selectedGeminiModel: selectedGeminiModel,
            mealsByDate: mealsByDate,
            hydrationGlassesByDate: hydrationGlassesByDate,
            smartAlarmEnabled: smartAlarmEnabled,
            wakeOffsetMinutes: wakeOffsetMinutes,
            sleepGoalPct: sleepGoalPct,
            visibleTabs: Array(visibleTabs),
            sectionCoachingCache: sectionCoachingCache,
            processedAutoSyncSignatures: Array(processedAutoSyncSignatures.prefix(80)),
            lastAutoSyncStatus: autoSyncStatusText,
            shortcutSyncName: shortcutSyncName,
            autoRunShortcutOnOpen: autoRunShortcutOnOpen,
            workoutRoutines: workoutRoutines,
            strengthLogs: strengthLogs,
            manualNutrientsByDate: manualNutrientsByDate,
            hiddenJournalHabitIds: Array(hiddenJournalHabitIds),
            customJournalHabits: customJournalHabits,
            journalNotesByDate: journalNotesByDate,
            notificationSettings: notificationSettings,
            savedFoodsLibrary: savedFoodsLibrary,
            customNutritionGoals: customNutritionGoals,
            homeLayout: homeLayout,
            coachThreads: Array(coachThreads.prefix(30)),
            activeCoachThreadId: activeCoachThreadId,
            labReports: labReports,
            weeklyAiInsightsCache: weeklyAiInsightsCache
        )
    }

    func persistState(immediate: Bool = false) {
        let snap = buildPersistedSnapshot()
        let targetURL = persistenceURL
        publishWidgetSnapshot(triggerReload: true)

        pendingPersistWorkItem?.cancel()
        if immediate {
            pendingPersistWorkItem = nil
            persistenceQueue.sync {
                if let data = try? JSONEncoder().encode(snap) {
                    try? data.write(to: targetURL, options: .atomic)
                }
            }
            return
        }

        let work = DispatchWorkItem {
            if let data = try? JSONEncoder().encode(snap) {
                try? data.write(to: targetURL, options: .atomic)
            }
        }
        pendingPersistWorkItem = work
        persistenceQueue.asyncAfter(deadline: .now() + 0.28, execute: work)
    }

    func flushPersistenceNow() {
        persistState(immediate: true)
    }

    private func loadPersistedState() {
        guard let data = try? Data(contentsOf: persistenceURL),
              let snap = try? JSONDecoder().decode(PersistedSnapshot.self, from: data) else {
            return
        }
        userProfile = snap.userProfile
        // One-time migration: older builds bypassed onboarding (`profileSetupVersion == 0`), so present the
        // high-craft motion graphics onboarding & profile setup once while preserving 100% of stored realHistory!
        if userProfile.profileSetupVersion < 2 {
            userProfile.onboardingCompleted = false
        }
        BevelColors.isDarkMode = snap.isDarkMode
        hasImportedOrPairedRealData = snap.hasImportedOrPairedRealData
        realHistory = snap.realHistory
        journalCheckinsByDate = snap.journalCheckins
        journalMoodByDate = snap.journalMoodByDate
        geminiApiKey = snap.geminiApiKey
        // Automatically migrate retired Gemini 2.0 / 2.5-flash-lite defaults to live Auto-Discovery ("auto")
        if snap.selectedGeminiModel == "gemini-2.5-flash-lite" || snap.selectedGeminiModel == "gemini-2.0-flash" || snap.selectedGeminiModel.isEmpty {
            selectedGeminiModel = "auto"
        } else {
            selectedGeminiModel = snap.selectedGeminiModel
        }
        mealsByDate = snap.mealsByDate
        hydrationGlassesByDate = snap.hydrationGlassesByDate
        smartAlarmEnabled = snap.smartAlarmEnabled
        wakeOffsetMinutes = snap.wakeOffsetMinutes
        sleepGoalPct = snap.sleepGoalPct
        if !snap.visibleTabs.isEmpty { visibleTabs = Set(snap.visibleTabs) }
        if let cached = snap.sectionCoachingCache { sectionCoachingCache = cached }
        if let sigs = snap.processedAutoSyncSignatures { processedAutoSyncSignatures = Set(sigs) }
        if let status = snap.lastAutoSyncStatus, !status.isEmpty { autoSyncStatusText = status }
        if let sName = snap.shortcutSyncName, !sName.isEmpty {
            // Migrate legacy two-shortcut names cleanly to the single unified `Sync Improving` master shortcut
            if sName == "Sync Improving (Automático)" || sName == "Sync Improving (1 Toque)" {
                shortcutSyncName = "Sync Improving"
            } else {
                shortcutSyncName = sName
            }
        }
        if let autoRun = snap.autoRunShortcutOnOpen { autoRunShortcutOnOpen = autoRun }
        if let routines = snap.workoutRoutines { workoutRoutines = routines }
        if let logs = snap.strengthLogs { strengthLogs = logs }
        if let manualNut = snap.manualNutrientsByDate { manualNutrientsByDate = manualNut }
        if let hiddenIds = snap.hiddenJournalHabitIds { hiddenJournalHabitIds = Set(hiddenIds) }
        if let customHabits = snap.customJournalHabits { customJournalHabits = customHabits }
        if let notes = snap.journalNotesByDate { journalNotesByDate = notes }
        if let notifCfg = snap.notificationSettings { notificationSettings = notifCfg }
        if let library = snap.savedFoodsLibrary { savedFoodsLibrary = library }
        if let nutGoals = snap.customNutritionGoals { customNutritionGoals = nutGoals }
        if let layout = snap.homeLayout { homeLayout = layout }
        if let threads = snap.coachThreads {
            coachThreads = threads
            if let activeId = snap.activeCoachThreadId,
               let activeThread = threads.first(where: { $0.id == activeId }) {
                activeCoachThreadId = activeId
                coachMessages = activeThread.messages
            } else if let first = threads.first {
                activeCoachThreadId = first.id
                coachMessages = first.messages
            }
        }
        if let labs = snap.labReports { labReports = labs }
        if let wkCache = snap.weeklyAiInsightsCache { weeklyAiInsightsCache = wkCache }

        // One-time self-healing migration for days corrupted by the v1 3-decimal kcal multiplier (>6,000 kcal -> 100% strain)
        var sanitizedCorruptStrain = false
        for (iso, day) in realHistory {
            if let k = day.activeKcal, k > 6_000 {
                var clean = day
                clean.activeKcal = nil
                clean.strainPct = nil
                clean.strain21 = nil
                realHistory[iso] = clean
                sanitizedCorruptStrain = true
            }
        }
        if sanitizedCorruptStrain {
            processedAutoSyncSignatures.removeAll()
        }

        // Self-healing migration for nights affected by Apple Watch Low Power Mode (under-charged Body Battery
        // or missing Recovery % despite real recorded sleep): recompute immediately on launch!
        let needsLowPowerEnergyHeal = realHistory.values.contains { day in
            guard let asleep = day.asleepMinutes, asleep >= 180 else { return false }
            if day.recoveryPct == nil || day.energySamples5m.isEmpty { return true }
            if (day.sleepPct ?? 0) >= 65 && day.energySamples5m.count >= 2 {
                let gain = zip(day.energySamples5m, day.energySamples5m.dropFirst()).reduce(0.0) { acc, pair in
                    acc + max(pair.1.value - pair.0.value, 0.0)
                }
                if gain < 15.0 { return true }
            }
            return false
        }
        if needsLowPowerEnergyHeal {
            recomputeMetricsForCurrentProfile()
            persistState()
        }
    }
}

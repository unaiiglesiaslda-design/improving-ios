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

    static let currentSchemaVersion = 4
    static let geminiKeychainAccount = "gemini_api_key_v1"

    struct PersistedSnapshot: Codable {
        var schemaVersion: Int?
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
        var journalEventTimesByDate: [String: [String: String]]?
        var notificationSettings: SmartNotificationSettings?
        var savedFoodsLibrary: [SavedFoodLibraryItem]?
        var customNutritionGoals: CustomNutritionGoals?
        var homeLayout: HomeLayoutPreferences?
        var coachThreads: [CoachChatThread]?
        var activeCoachThreadId: String?
        var labReports: [LabReportRecord]?
        var weeklyAiInsightsCache: [String: WeeklyAiReviewInsight]?
        var cloudAIEnabled: Bool?
        var allowKeylessAIFallback: Bool?
        var redactPIIFromAI: Bool?
        var healthKitPreviouslyAuthorized: Bool?
        var napMinutesByDate: [String: Int]?
        var journalQuantitiesByDate: [String: [String: Double]]?
        var coachMemoryNotes: [String]?
        var globalGoalMode: GlobalGoalMode?
        var nutritionRecipes: [NutritionRecipeTemplate]?
        var cycleTrackingSettings: CycleTrackingSettings?
        var autoDeloadModeActive: Bool?
    }

    static weak var activeSharedStore: ImprovingStore?
    @Published var pendingDeepLinkRoute: DeepLinkRequest? = nil
    @Published var whoopLiveHrBpm: Int? = nil

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
    @Published var journalEventTimesByDate: [String: [String: String]] = [:]
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
    @Published var napMinutesByDate: [String: Int] = [:]
    @Published var journalQuantitiesByDate: [String: [String: Double]] = [:]
    @Published var coachMemoryNotes: [String] = []
    @Published var globalGoalMode: GlobalGoalMode = .longevidad
    @Published var nutritionRecipes: [NutritionRecipeTemplate] = []
    @Published var cycleTrackingSettings: CycleTrackingSettings = CycleTrackingSettings()
    @Published var autoDeloadModeActive: Bool = false
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
    var healthKitPreviouslyAuthorized: Bool = false
    var lastWhoopHistoryCommitAt: Date? = nil
    var whoopPendingRrBuffer: [Double] = []
    var inboxDebounceTask: Task<Void, Never>? = nil

    // Revision-keyed derived metrics memoization cache (non-@Published: zero SwiftUI invalidation loops!)
    var derivedCacheFingerprint: String = ""
    var cachedTrainingLoad: [String: TrainingLoadAnalysis] = [:]
    var cachedEffortTargets: [String: (
        range: ClosedRange<Double>,
        baselineStrainPct: Double?,
        sampleCount: Int,
        cardioState: TrainingLoadState?,
        sleepDebtMin: Int?,
        recBasis: Int
    )] = [:]
    var cachedBioAge: (
        eval: BiologicalAgeEvaluation,
        hasData: Bool,
        meanRhr: Double?,
        meanHrv: Double?,
        meanSleep: Double?,
        meanSteps: Int?,
        vo2Val: Double?
    )? = nil
    var cachedWeeklyReviews: [String: WeeklyReviewReport] = [:]
    var cachedJournalImpacts: [JournalImpactTarget: [JournalHabitImpactItem]] = [:]
    var cachedVitalBands: [HealthMetricKind: (low: Double, high: Double, isPersonal: Bool)] = [:]

    func ensureDerivedCacheFresh() {
        let fp = "\(dataRevision)#\(selectedDateIso)#\(hasImportedOrPairedRealData)#\(realHistory.count)#\(strengthLogs.count)#\(labReports.count)#\(journalCheckinsByDate.count)#\(mealsByDate.count)#\(napMinutesByDate.count)#\(sleepGoalPct)#\(globalGoalMode.rawValue)#\(autoDeloadModeActive)#\(cycleTrackingSettings.isEnabled)"
        if derivedCacheFingerprint != fp {
            derivedCacheFingerprint = fp
            cachedTrainingLoad.removeAll(keepingCapacity: true)
            cachedEffortTargets.removeAll(keepingCapacity: true)
            cachedBioAge = nil
            cachedWeeklyReviews.removeAll(keepingCapacity: true)
            cachedJournalImpacts.removeAll(keepingCapacity: true)
            cachedVitalBands.removeAll(keepingCapacity: true)
        }
    }

    // Automatic Apple Shortcuts / Files Folder Bridge (Zero Paid Entitlements!)
    @Published var isAutoSyncing: Bool = false
    @Published var autoSyncStatusText: String = "Listo · Esperando Atajos o carpeta Improving"
    @Published var syncBannerState: SyncBannerState = .hidden
    @Published var shortcutSyncName: String = "Sync Improving"
    @Published var autoRunShortcutOnOpen: Bool = false
    var processedAutoSyncSignatures: Set<String> = []
    var processedAutoSyncSignaturesOrder: [String] = []
    var lastShortcutTriggerAt: Date? = nil
    var awaitingShortcutCallback: Bool = false
    var lastIngestedPayloadHash: Int? = nil
    var lastIngestedPayloadAt: Date? = nil
    var syncBannerDismissTask: Task<Void, Never>? = nil
    var shortcutTimeoutTask: Task<Void, Never>? = nil
    var backgroundRecheckTask: Task<Void, Never>? = nil
    var inboxDirectorySource: DispatchSourceFileSystemObject? = nil
    var autoSyncSubdirSource: DispatchSourceFileSystemObject? = nil
    var healthSyncFileSource: DispatchSourceFileSystemObject? = nil
    var shortcutsLatestFileSource: DispatchSourceFileSystemObject? = nil
    var pendingInboxRescan: (force: Bool, showBanner: Bool)? = nil
    var lastActiveCalendarDayIso: String = ""

    @Published var importStatus: ExportImportStatus = ExportImportStatus()
    @Published var geminiApiKey: String = ""
    @Published var selectedGeminiModel: String = "auto"
    @Published var cloudAIEnabled: Bool = true
    @Published var allowKeylessAIFallback: Bool = false
    @Published var redactPIIFromAI: Bool = false
    @Published var persistenceRecoveryNotice: String? = nil
    @Published var coachMessages: [CoachChatMessage] = []
    @Published var coachThreads: [CoachChatThread] = []
    @Published var activeCoachThreadId: String? = nil
    @Published var isCoachThinking: Bool = false
    @Published var lastCoachErrorMessage: String? = nil
    var activeCoachInteractionId: String? = nil
    var coachReplyTask: Task<Void, Never>? = nil
    var sectionCoachingTimestamps: [String: TimeInterval] = [:]

    // Background debounced persistence queue (zero main-thread JSON serialization jank!)
    let persistenceQueue = DispatchQueue(label: "com.improving.persist.queue", qos: .utility)
    var pendingPersistWorkItem: DispatchWorkItem? = nil

    // 4-Hour Time-Aware Section Coaching Cache
    @Published var sectionCoachingCache: [String: SectionCoachingCard] = [:]
    @Published var loadingCoachingSections: Set<CoachingSection> = []
    @Published var dataRevision: Int = 0
    var coachingTasks: [CoachingSection: Task<Void, Never>] = [:]
    var lastHeadlineBySection: [CoachingSection: String] = [:]

    @Published var strengthSets: [(id: String, exercise: String, reps: Int, weightKg: Double, completed: Bool)] = []
    @Published var workoutRoutines: [WorkoutRoutineTemplate] = []
    @Published var strengthLogs: [StrengthLoggedSet] = []
    @Published var restTimerRunning: Bool = false
    @Published var restTimerSeconds: Int = 90
    var restTimerEndDate: Date? = nil

    let whoopBleReader = WhoopBLEReader()
    var cancellables: Set<AnyCancellable> = []
    var bleStreamTask: Task<Void, Never>?
    var timerTask: Task<Void, Never>?

    let isoFormatter: DateFormatter = AppFormatters.isoDay

    let customPersistenceURL: URL?

    var persistenceURL: URL {
        if let custom = customPersistenceURL {
            try? FileManager.default.createDirectory(at: custom.deletingLastPathComponent(), withIntermediateDirectories: true)
            return custom
        }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("improving_store_v3.json")
    }

    init(persistenceURL: URL? = nil, headlessBackground: Bool = false) {
        self.customPersistenceURL = persistenceURL
        loadPersistedState()
        if headlessBackground {
            return
        }
        if persistenceURL == nil {
            Self.activeSharedStore = self
        }
        if !hasImportedOrPairedRealData && simulatedHistory.isEmpty {
            simulatedHistory = WhoopPhysiologyEngine.generateTwoYearSimulatedHistory(profile: userProfile)
        }
        seedPreviewOnlyItemsIfNeeded()
        bindWhoopBle()
        bindHealthKit()
        // Ensure `En mi iPhone / Improving` folder is visible in Files app & watch live filesystem writes!
        _ = ShortcutsHealthSyncImporter.autoSyncInboxURL
        if persistenceURL == nil {
            startInboxDirectoryWatcher()
        }
        scanAutoSyncInboxIfNeeded(force: false, showBanner: false)
        #if os(iOS)
        if healthKitPreviouslyAuthorized {
            healthKitAuthorized = true
            Task {
                await HealthKitReader.shared.restoreBackgroundObserversIfAuthorized()
            }
        }
        #endif
        refreshSmartNotificationSchedules(promptPermission: false)
        publishWidgetSnapshot(triggerReload: true, forceReload: false)
    }

    deinit {
        pendingPersistWorkItem?.cancel()
        bleStreamTask?.cancel()
        timerTask?.cancel()
        syncBannerDismissTask?.cancel()
        shortcutTimeoutTask?.cancel()
        backgroundRecheckTask?.cancel()
        inboxDebounceTask?.cancel()
        inboxDirectorySource?.cancel()
        autoSyncSubdirSource?.cancel()
        healthSyncFileSource?.cancel()
        shortcutsLatestFileSource?.cancel()
        for task in coachingTasks.values { task.cancel() }
    }

    func seedPreviewOnlyItemsIfNeeded() {
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

    func clearPreviewSeededArtifactsOnRealData() {
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
        activeHistory.keys.max().flatMap { activeHistory[$0] }
    }

    var earliestAvailableDate: Date {
        if let firstIso = activeHistory.keys.min(), let d = isoFormatter.date(from: firstIso) {
            return min(d, Calendar.current.date(byAdding: .year, value: -3, to: Date()) ?? d)
        }
        return Calendar.current.date(byAdding: .year, value: -3, to: Date()) ?? Date()
    }

    var dateLabel: String {
        if dayOffset == 0 {
            return "Hoy, " + AppFormatters.dMMM.string(from: Date()).replacingOccurrences(of: ".", with: "")
        }
        if dayOffset == 1 {
            return "Ayer, " + AppFormatters.dMMM.string(from: selectedDate).replacingOccurrences(of: ".", with: "")
        }
        let wd = AppFormatters.weekdayShortEs.string(from: selectedDate).capitalized.replacingOccurrences(of: ".", with: "")
        let dm = AppFormatters.dMMM.string(from: selectedDate).replacingOccurrences(of: ".", with: "")
        return "\(wd), \(dm)"
    }

    var fullDateLabel: String {
        AppFormatters.dMMMMyyyy.string(from: selectedDate)
    }

    var monthYearLabel: String {
        AppFormatters.shortMonthYearEs.string(from: selectedDate).replacingOccurrences(of: ".", with: "")
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
        ensureDerivedCacheFresh()
        let key = "\(tab.rawValue)#\(spanDays)#\(windowPageOffset)"
        if let hit = cachedTrainingLoad[key] {
            return hit
        }
        let computed = WhoopPhysiologyEngine.computeTrainingLoadAnalysis(
            tab: tab,
            history: activeHistory,
            strengthLogs: strengthLogs,
            anchorDate: selectedDate,
            spanDays: spanDays,
            windowPageOffset: windowPageOffset
        )
        cachedTrainingLoad[key] = computed
        return computed
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
        sets: [StrengthLoggedSet],
        rpe: Int? = nil
    ) {
        let completedOnly = sets.filter(\.completed)
        for s in completedOnly {
            strengthLogs.append(s)
        }
        let totalSets = completedOnly.count
        let totalVol = completedOnly.reduce(0.0) { $0 + Double($1.reps) * $1.weightKg }
        let muscleNames = Array(Set(completedOnly.flatMap { $0.primaryMuscles.map(\.rawValue) }))
        let estKcal = kcal > 0 ? kcal : max(durationMin * 5, totalSets * 12)
        let clampedRpe = rpe.map { min(max($0, 1), 10) }
        let ws = WhoopPhysiologyEngine.computeWorkoutStrain(
            durationMin: max(durationMin, 5),
            kcal: estKcal,
            avgHrBpm: 0,
            rhrBpm: restingHrBpm > 30 ? restingHrBpm : 55.0,
            maxHrBpm: Double(WhoopPhysiologyEngine.computeMaxHeartRate(profile: userProfile)),
            banisterB: userProfile.sex.banisterB,
            totalSets: totalSets,
            totalVolumeKg: totalVol,
            rpe: clampedRpe
        )
        let nowFmt = DateFormatter()
        nowFmt.dateFormat = "HH:mm"
        let cal = Calendar.current
        let now = Date()
        let timeComp = cal.dateComponents([.hour, .minute], from: now)
        let selectedEndDate = cal.date(
            bySettingHour: timeComp.hour ?? 12,
            minute: timeComp.minute ?? 0,
            second: 0,
            of: selectedDate
        ) ?? selectedDate
        let clampedDuration = max(durationMin, 5)
        let selectedStartDate = selectedEndDate.addingTimeInterval(-Double(clampedDuration * 60))
        let endStr = nowFmt.string(from: selectedEndDate)
        let startStr = nowFmt.string(from: selectedStartDate)

        var d = realHistory[selectedDateIso] ?? currentDaySummary ?? RealBiometricDaySummary(dateIso: selectedDateIso)
        let ev = EffortEventItem(
            id: UUID().uuidString,
            title: title,
            timeRange: "\(startStr) - \(endStr)",
            durationMin: clampedDuration,
            avgHrBpm: 0,
            strainScore: ws.strain21,
            strainPct: ws.strainPct,
            categoryLabel: "Fuerza",
            kcal: estKcal,
            distanceKm: nil,
            elevationM: nil,
            dateIso: selectedDateIso,
            startEpochSec: Int64(selectedStartDate.timeIntervalSince1970),
            totalSets: totalSets > 0 ? totalSets : nil,
            totalVolumeKg: totalVol > 0 ? AppleHealthExportImporter.round1(totalVol) : nil,
            targetMuscles: muscleNames.isEmpty ? nil : muscleNames,
            rpe: clampedRpe
        )
        d.workouts.insert(ev, at: 0)
        d.strengthMinutes += clampedDuration
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
        }
        // Always persist real user-logged workouts in realHistory so they survive restart & first wearable sync!
        realHistory[selectedDateIso] = d
        if !hasImportedOrPairedRealData {
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
        let w = latestBodyWeightKg ?? userProfile.weightKg
        let modeKcal = Int((Double(norms.maintenanceCaloriesKcal) * globalGoalMode.kcalMultiplier).rounded())
        let modeProt = Int((w * globalGoalMode.proteinGramsPerKg).rounded())
        let modeFat = max(Int((Double(modeKcal) * 0.27 / 9.0).rounded()), 45)
        let modeCarbs = max((modeKcal - modeProt * 4 - modeFat * 9) / 4, 80)
        return (
            kcal: customNutritionGoals.caloriesKcal ?? modeKcal,
            fatG: customNutritionGoals.fatG ?? modeFat,
            carbsG: customNutritionGoals.carbsG ?? modeCarbs,
            proteinG: customNutritionGoals.proteinG ?? modeProt
        )
    }

    var hasCustomNutritionGoalOverrides: Bool {
        customNutritionGoals.caloriesKcal != nil ||
        customNutritionGoals.fatG != nil ||
        customNutritionGoals.carbsG != nil ||
        customNutritionGoals.proteinG != nil
    }

    func clearCustomNutritionGoals() {
        customNutritionGoals = CustomNutritionGoals()
        dataRevision += 1
        persistState()
    }

    var savedFoodsCounts: (favorites: Int, recipes: Int, meals: Int) {
        let favs = savedFoodsLibrary.filter { $0.kind == .favorite }.count
        let recs = savedFoodsLibrary.filter { $0.kind == .recipe }.count
        let mls = savedFoodsLibrary.filter { $0.kind == .meal }.count
        return (favs, recs, mls)
    }

    static func isZeroCalorieCaffeineOnlyDrink(_ m: NutritionMealItem) -> Bool {
        m.kcal == 0 && m.proteinG == 0 && m.carbsG == 0 && m.fatG == 0 && (m.caffeineMg ?? 0) > 0
    }

    func nutritionScore(for dateIso: String) -> Int? {
        let meals = (mealsByDate[dateIso] ?? []).filter { !Self.isZeroCalorieCaffeineOnlyDrink($0) }
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
        let foodMeals = meals.filter { !Self.isZeroCalorieCaffeineOnlyDrink($0) }
        let extraP = manualNutrientAmount(for: "Proteína", dateIso: dateIso)
        let extraC = manualNutrientAmount(for: "Carbohidratos", dateIso: dateIso)
        let extraF = manualNutrientAmount(for: "Grasas", dateIso: dateIso)
        let p = Double(meals.reduce(0) { $0 + $1.proteinG }) + extraP
        let c = Double(meals.reduce(0) { $0 + $1.carbsG }) + extraC
        let f = Double(meals.reduce(0) { $0 + $1.fatG }) + extraF
        let mealKcal = meals.reduce(0) { $0 + $1.kcal }
        let kcal = mealKcal + Int((extraP * 4.0 + extraC * 4.0 + extraF * 9.0).rounded())
        return (kcal, f, c, p, nutritionScore(for: dateIso), foodMeals.count)
    }

    func burnedCalories(for dateIso: String) -> Int {
        let bmr = WhoopPhysiologyEngine.computeBmrKcalPerDay(profile: userProfile)
        let todayIso = isoFormatter.string(from: Date())
        let effectiveBmr: Int = {
            if let basal = activeHistory[dateIso]?.basalKcal, basal > 100 {
                return basal
            }
            if dateIso == todayIso {
                let comps = Calendar.current.dateComponents([.hour, .minute], from: Date())
                let elapsedMin = Double((comps.hour ?? 12) * 60 + (comps.minute ?? 0))
                let frac = min(max(elapsedMin / 1440.0, 0.08), 1.0)
                return Int((Double(bmr) * frac).rounded())
            }
            return bmr
        }()
        guard let d = activeHistory[dateIso] else { return effectiveBmr }
        if let active = d.activeKcal, active > 0 {
            return effectiveBmr + active
        }
        let wkKcal = d.workouts.reduce(0) { $0 + $1.kcal }
        return effectiveBmr + wkKcal
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
        !realHistory.isEmpty || hasImportedOrPairedRealData
    }

    /// Strictly causal personalized optimal Strain target for `dateIso` (combining exact continuous Recovery %,
    /// trailing 28-day personal Strain baseline, 3-day acute spike check, EWMA Cardio Load state, and sleep debt).
    func personalizedEffortTarget(for dateIso: String? = nil, includeCardioLoad: Bool = true) -> (
        range: ClosedRange<Double>,
        baselineStrainPct: Double?,
        sampleCount: Int,
        cardioState: TrainingLoadState?,
        sleepDebtMin: Int?,
        recBasis: Int
    ) {
        ensureDerivedCacheFresh()
        let targetIso = dateIso ?? selectedDateIso
        let cacheKey = "\(targetIso)#\(includeCardioLoad ? 1 : 0)"
        if let hit = cachedEffortTargets[cacheKey] {
            return hit
        }
        let anchorDate = isoFormatter.date(from: targetIso) ?? selectedDate
        let cal = Calendar.current
        let anchorStart = cal.startOfDay(for: anchorDate)

        var prior28Strains: [Double] = []
        var recent3Strains: [Double] = []
        var recent7Rec: Int? = nil

        for back in 1...28 {
            guard let dt = cal.date(byAdding: .day, value: -back, to: anchorStart) else { continue }
            let iso = isoFormatter.string(from: dt)
            guard let day = activeHistory[iso] else { continue }
            if let st = day.strainPct, st > 0 {
                prior28Strains.append(Double(st))
                if back <= 3 { recent3Strains.append(Double(st)) }
            }
            if back <= 7, recent7Rec == nil, let r = day.recoveryPct {
                recent7Rec = r
            }
        }

        let targetDay = activeHistory[targetIso]
        let recBasis: Int = targetDay?.recoveryPct ?? recent7Rec ?? 65
        let baseMean: Double? = prior28Strains.isEmpty ? nil : (prior28Strains.reduce(0, +) / Double(prior28Strains.count))
        let r3Mean: Double? = recent3Strains.isEmpty ? nil : (recent3Strains.reduce(0, +) / Double(recent3Strains.count))

        let cardioState: TrainingLoadState? = {
            guard includeCardioLoad else { return nil }
            let analysis = trainingLoadAnalysis(tab: .cardio, spanDays: 30, windowPageOffset: 0)
            guard analysis.hasAnyData else { return nil }
            if targetIso == selectedDateIso {
                return analysis.currentState == .calibrating ? nil : analysis.currentState
            }
            if let pt = analysis.points.first(where: { $0.dateIso == targetIso }) {
                return pt.state == .calibrating ? nil : pt.state
            }
            return nil
        }()

        let debtMin = targetDay?.sleepDebtMinutes
        let vitalAlert = healthMonitorAlert(for: targetIso)
        let baseRange = WhoopPhysiologyEngine.optimalTargetRange(
            for: recBasis,
            profile: userProfile,
            baselineStrainPct: baseMean,
            baselineSampleCount: prior28Strains.count,
            cardioLoadState: cardioState,
            sleepDebtMinutes: debtMin,
            recent3DayAvgStrainPct: r3Mean,
            unhealthyVitalsCount: vitalAlert.count
        )
        let deloadMult = autoDeloadModeActive ? 0.85 : 1.0
        let modeDelta = globalGoalMode.strainAdjustmentDelta
        let adjLow = min(max((baseRange.lowerBound + modeDelta * 0.6) * deloadMult, 0.10), 0.78)
        let adjHigh = min(max((baseRange.upperBound + modeDelta) * deloadMult, adjLow + 0.12), 0.96)
        let range = adjLow...adjHigh
        let res = (range, baseMean, prior28Strains.count, cardioState, debtMin, recBasis)
        cachedEffortTargets[cacheKey] = res
        return res
    }

    /// WHOOP-style Health Monitor multi-vital alert (fires protective warning + automatic strain cap when 2+ overnight vitals deviate negatively).
    func healthMonitorAlert(for dateIso: String? = nil) -> HealthMonitorPhysiologicalAlert {
        let iso = dateIso ?? selectedDateIso
        guard let d = activeHistory[iso] else {
            return HealthMonitorPhysiologicalAlert(flaggedVitals: [], count: 0, isCritical: false, strainReductionPct: 0, headline: "", advice: "")
        }
        var flagged: [String] = []
        let lutealCalibrated = currentCyclePhaseSnapshot?.isLutealCalibrationActive == true
        let lutealTempAllowance = lutealCalibrated ? 0.38 : 0.0

        if let hrv = d.hrvMs, hrv > 2.0 {
            let b = personalVitalNormalBand(for: .hrv)
            let ev = WhoopPhysiologyEngine.evaluateVital(value: hrv, bandLow: b.low, bandHigh: b.high, higherIsBetter: true, hasData: true)
            if ev.isBelowBand && (ev.severity == .borderlineWarning || ev.severity == .alertOutOfRange) {
                flagged.append("VFC baja")
            }
        }
        if let rhr = d.restingHrBpm, rhr > 25.0 {
            let b = personalVitalNormalBand(for: .restingHeartRate)
            let ev = WhoopPhysiologyEngine.evaluateVital(value: rhr, bandLow: b.low, bandHigh: b.high, lowerIsBetter: true, hasData: true)
            if ev.isAboveBand && (ev.severity == .borderlineWarning || ev.severity == .alertOutOfRange) {
                flagged.append("FCR elevada")
            }
        }
        if let rr = d.respRateRpm, rr > 5.0 {
            let b = personalVitalNormalBand(for: .respiratoryRate)
            let ev = WhoopPhysiologyEngine.evaluateVital(value: rr, bandLow: b.low, bandHigh: b.high, lowerIsBetter: true, hasData: true)
            if ev.isAboveBand && (ev.severity == .borderlineWarning || ev.severity == .alertOutOfRange) {
                flagged.append("FR elevada")
            }
        }
        if let spo2 = d.spo2Percent, spo2 > 60.0 {
            let b = personalVitalNormalBand(for: .oxygenSaturation)
            let ev = WhoopPhysiologyEngine.evaluateVital(value: spo2, bandLow: b.low, bandHigh: b.high, higherIsBetter: true, hasData: true)
            if ev.isBelowBand && (ev.severity == .borderlineWarning || ev.severity == .alertOutOfRange) {
                flagged.append("SpO₂ baja")
            }
        }
        let tempAbs: Double? = d.wristTempAbsoluteC ?? d.wristTempDeltaC.map { AppleHealthExportImporter.round1(35.8 + $0) }
        if let t = tempAbs {
            let b = personalVitalNormalBand(for: .wristTemperature)
            let ev = WhoopPhysiologyEngine.evaluateVital(value: t, bandLow: b.low, bandHigh: b.high + lutealTempAllowance, hasData: true)
            if (ev.isAboveBand || ev.isBelowBand) && (ev.severity == .borderlineWarning || ev.severity == .alertOutOfRange) {
                flagged.append(ev.isAboveBand ? "Temp. elevada" : "Temp. baja")
            }
        }

        let cnt = flagged.count
        let isCrit = cnt >= 2
        let reduction = cnt >= 3 ? 20 : (cnt == 2 ? 14 : 0)
        let headline = cnt >= 3
            ? "Alerta fisiológica (\(cnt) constantes alteradas)"
            : (cnt == 2 ? "Señal de estrés fisiológico (2 constantes)" : "")
        let advice = isCrit
            ? "\(flagged.joined(separator: " · ")). Posible fatiga acumulada o inicio de resfriado: objetivo de esfuerzo reducido un \(reduction)% automáticamente."
            : ""
        return HealthMonitorPhysiologicalAlert(
            flaggedVitals: flagged,
            count: cnt,
            isCritical: isCrit,
            strainReductionPct: reduction,
            headline: headline,
            advice: advice
        )
    }

    var sleepConsistencyPct: Int? {
        let recent = trailingCalendarSummaries(days: 6)
        let parseMin: (String) -> Int? = { txt in
            let parts = txt.split(separator: ":")
            guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
            return h * 60 + m
        }
        let pairs: [(Int, Int)] = recent.compactMap { item in
            guard let sess = item.summary?.sleepSession,
                  let s = sess.startTimeLabel.flatMap(parseMin),
                  let e = sess.endTimeLabel.flatMap(parseMin) else { return nil }
            return (s, e)
        }
        return WhoopPhysiologyEngine.computeSleepConsistencyPercent(sessions: pairs)
    }

    var optimalEffortRange: ClosedRange<Double> {
        personalizedEffortTarget(for: selectedDateIso).range
    }

    var effortTargetRangeText: String {
        let r = optimalEffortRange
        return "\(Int((r.lowerBound * 100).rounded()))%–\(Int((r.upperBound * 100).rounded()))%"
    }

    /// Transparent 1-line physiological explanation of today's personalized Optimal Strain range.
    var effortTargetCalibrationCaption: String {
        let info = personalizedEffortTarget(for: selectedDateIso)
        let alert = healthMonitorAlert(for: selectedDateIso)
        var parts: [String] = ["Rec. \(info.recBasis)%"]
        parts.append("Modo \(globalGoalMode.rawValue)")
        if autoDeloadModeActive {
            parts.append("Descarga -15%")
        }
        if alert.isCritical {
            parts.append("protección -\(alert.strainReductionPct)% (\(alert.count) constantes)")
        }
        if let base = info.baselineStrainPct, info.sampleCount >= 3 {
            parts.append("media 28 d \(Int(base.rounded()))%")
        }
        if let st = info.cardioState {
            parts.append("carga \(st.rawValue.lowercased())")
        }
        if let debt = info.sleepDebtMin, debt > 30 {
            parts.append("deuda sueño \(debt) min")
        }
        return "Calibrado a ti · " + parts.joined(separator: " · ")
    }

    // MARK: - Global Goal Mode, Cycle Tracking, Auto-Deload, Morning Briefing & Strength Overload

    func setGlobalGoalMode(_ mode: GlobalGoalMode) {
        globalGoalMode = mode
        sleepGoalPct = mode.recommendedSleepMode.rawValue
        invalidateSectionCoachingCache(sections: CoachingSection.allCases)
        dataRevision += 1
        persistState()
        refreshSmartNotificationSchedules(promptPermission: false)
    }

    func toggleAutoDeloadMode(_ active: Bool? = nil) {
        autoDeloadModeActive = active ?? !autoDeloadModeActive
        invalidateSectionCoachingCache(sections: [.hoy, .esfuerzo, .fitness])
        dataRevision += 1
        persistState()
    }

    var currentCyclePhaseSnapshot: CyclePhaseSnapshot? {
        var cfg = cycleTrackingSettings
        if !cfg.isEnabled && userProfile.sex == .female && !cfg.lastPeriodStartIso.isEmpty {
            cfg.isEnabled = true
        }
        return WhoopPhysiologyEngine.computeCyclePhase(settings: cfg, referenceDate: selectedDate)
    }

    func updateCycleTrackingSettings(_ settings: CycleTrackingSettings) {
        cycleTrackingSettings = settings
        dataRevision += 1
        persistState()
    }

    var overtrainingAssessment: OvertrainingDeloadAssessment {
        let recent = trailingCalendarSummaries(days: 10).compactMap(\.summary)
        let cardioAnalysis = trainingLoadAnalysis(tab: .cardio, spanDays: 30, windowPageOffset: 0)
        let chronic = max(Double(cardioAnalysis.optimalLow + cardioAnalysis.optimalHigh) / 2.0, 15.0)
        let acute = Double(cardioAnalysis.currentLoad)
        let acwr = cardioAnalysis.hasAnyData ? (acute / chronic) : 1.0
        return WhoopPhysiologyEngine.computeOvertrainingDeloadAssessment(
            recentDays: recent,
            acwr: acwr,
            deloadModeActive: autoDeloadModeActive
        )
    }

    func exercisePerformanceSnapshot(for exerciseName: String) -> ExercisePerformanceSnapshot {
        let rec = dataAvailability.hasRecoveryData ? recoveryPercent : 70
        return WhoopPhysiologyEngine.computeExercisePerformanceSnapshot(
            exerciseName: exerciseName,
            logs: strengthLogs,
            recoveryPct: rec,
            deloadActive: autoDeloadModeActive || overtrainingAssessment.riskLevel == 2
        )
    }

    var morningBriefingSnapshot: MorningBriefingSnapshot {
        let av = dataAvailability
        let name = userProfile.displayFirstName.isEmpty ? "Atleta" : userProfile.displayFirstName
        let recText = av.hasRecoveryData ? "Recuperación \(recoveryPercent)%" : "Sin lectura de recuperación"
        let need = tonightSleepNeedBreakdown
        let plan = computedSleepPlan
        let sleepText = av.hasSleepData
            ? "Dormiste \(sleepDurationText) (\(sleepPercent)%). Esta noche necesitas \(need.totalMin / 60)h \(String(format: "%02d", need.totalMin % 60))m (acuéstate a las \(plan.bedtimeLabel))."
            : "Objetivo de sueño para hoy: \(need.totalMin / 60)h \(String(format: "%02d", need.totalMin % 60))m (hora recomendada \(plan.bedtimeLabel))."
        let effortText = "Rango de esfuerzo óptimo hoy: \(effortTargetRangeText)\(autoDeloadModeActive ? " (Semana de Descarga −15%)" : "")."
        let goals = effectiveNutritionGoals
        let nutText = "Meta Modo \(globalGoalMode.rawValue): \(goals.kcal) kcal · \(goals.proteinG)g proteína · \(goals.carbsG)g carbos · \(goals.fatG)g grasas."
        let vAlert = healthMonitorAlert(for: selectedDateIso)
        let deload = overtrainingAssessment
        return MorningBriefingSnapshot(
            greetingTitle: "Briefing del día · \(name)",
            recoveryBadge: recText,
            sleepSummary: sleepText,
            effortPlanText: effortText,
            nutritionPlanText: nutText,
            vitalAlertText: vAlert.isCritical ? vAlert.headline + ": " + vAlert.flaggedVitals.joined(separator: ", ") : nil,
            deloadAlertText: deload.riskLevel >= 1 ? "\(deload.statusTitle) (ACWR \(String(format: "%.2f", locale: Locale(identifier: "es_ES"), deload.acwr)))" : nil,
            goalMode: globalGoalMode
        )
    }

}

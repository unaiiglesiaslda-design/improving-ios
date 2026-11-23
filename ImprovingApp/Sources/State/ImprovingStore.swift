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
    @Published var selectedHealthMetric: HealthMetricKind = .hrv
    @Published var selectedHealthRange: String = "30 d"
    @Published var selectedNutrientKey: String = "proteina"
    @Published var selectedTrendItem: EffortTrendItem? = nil

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
    @Published var shortcutSyncName: String = "Sync Improving (Automático)"
    @Published var autoRunShortcutOnOpen: Bool = false
    private var processedAutoSyncSignatures: Set<String> = []
    private var lastShortcutTriggerAt: Date? = nil
    private var awaitingShortcutCallback: Bool = false
    private var syncBannerDismissTask: Task<Void, Never>? = nil
    private var shortcutTimeoutTask: Task<Void, Never>? = nil
    private var backgroundRecheckTask: Task<Void, Never>? = nil
    private var inboxDirectorySource: DispatchSourceFileSystemObject? = nil
    private var autoSyncSubdirSource: DispatchSourceFileSystemObject? = nil

    @Published var importStatus: ExportImportStatus = ExportImportStatus()
    @Published var geminiApiKey: String = ""
    @Published var selectedGeminiModel: String = "gemini-2.5-flash"
    @Published var coachMessages: [CoachChatMessage] = []
    @Published var isCoachThinking: Bool = false
    private var activeCoachInteractionId: String? = nil

    // 4-Hour Time-Aware Section Coaching Cache
    @Published var sectionCoachingCache: [String: SectionCoachingCard] = [:]
    @Published var loadingCoachingSections: Set<CoachingSection> = []
    @Published var dataRevision: Int = 0
    private var coachingTasks: [CoachingSection: Task<Void, Never>] = [:]
    private var lastHeadlineBySection: [CoachingSection: String] = [:]

    @Published var strengthSets: [(id: String, exercise: String, reps: Int, weightKg: Double, completed: Bool)] = []
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
        // Ensure `En mi iPhone / Improving` folder is visible in Files app, watch for live writes & scan on startup
        _ = ShortcutsHealthSyncImporter.autoSyncInboxURL
        startInboxDirectoryWatcher()
        scanAutoSyncInboxIfNeeded(showBanner: true)
    }

    deinit {
        bleStreamTask?.cancel()
        timerTask?.cancel()
        syncBannerDismissTask?.cancel()
        shortcutTimeoutTask?.cancel()
        backgroundRecheckTask?.cancel()
        inboxDirectorySource?.cancel()
        autoSyncSubdirSource?.cancel()
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

    var stressScore: Int { currentDaySummary?.stressScore ?? 0 }
    var stressMax: Int? {
        let vals = stressSamplesToday.map(\.value)
        return vals.max().map { Int($0.rounded()) }
    }
    var stressMin: Int? {
        let vals = stressSamplesToday.map(\.value)
        return vals.min().map { Int($0.rounded()) }
    }
    var stressAvg: Int? {
        if let sc = currentDaySummary?.stressScore { return sc }
        let vals = stressSamplesToday.map(\.value)
        guard !vals.isEmpty else { return nil }
        return Int((vals.reduce(0, +) / Double(vals.count)).rounded())
    }
    var lastStressSampleTimeLabel: String? {
        guard let last = stressSamplesToday.last else { return nil }
        return String(format: "%02d:%02d", (last.minuteOfDay / 60) % 24, last.minuteOfDay % 60)
    }

    var stressStatusLabel: String {
        guard dataAvailability.hasStressData else { return "Sin datos" }
        if stressScore < 30 { return "Bajo" }
        if stressScore < 58 { return "Moderado" }
        return "Alto"
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
    var totalCaloriesToday: Int { mealsToday.reduce(0) { $0 + $1.kcal } }
    var totalProteinToday: Int { mealsToday.reduce(0) { $0 + $1.proteinG } }
    var totalCarbsToday: Int { mealsToday.reduce(0) { $0 + $1.carbsG } }
    var totalFatToday: Int { mealsToday.reduce(0) { $0 + $1.fatG } }
    var foodQualityScore: Int? {
        let m = mealsToday
        guard !m.isEmpty else { return nil }
        return m.reduce(0) { $0 + $1.qualityScore } / m.count
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
        guard dataAvailability.hasStrainData else { return "Sin datos" }
        let target = optimalEffortRange
        let frac = Double(strainPercent) / 100.0
        if frac > target.upperBound { return "Sobrecarga" }
        if strainPercent >= 75 { return "Alto" }
        if frac >= target.lowerBound { return "Óptimo" }
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
        WhoopPhysiologyEngine.optimalTargetRange(
            for: dataAvailability.hasRecoveryData ? recoveryPercent : 65,
            profile: userProfile
        )
    }

    var effortTargetRangeText: String {
        guard dataAvailability.hasRecoveryData else { return "--" }
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
            if av.hasStressData { facts.append("Estrés medio \(stressScore)/100 (\(stressStatusLabel))") }
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
            if av.hasStressData { facts.append("Estrés medio \(stressScore)/100 (\(stressStatusLabel)) con \(samples.count) muestras reales") }
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

    var recoveryTrends: [EffortTrendItem] {
        let window = trailingCalendarSummaries(days: 14)
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
                bandLow: 55, bandHigh: 95, lineColorHex: 0x3BD671,
                detailNote: "Variabilidad de la frecuencia cardíaca consolidada durante el sueño."
            ),
            buildTrendItem(
                id: "r_rhr", title: "FC en reposo",
                currentValue: currentDaySummary?.restingHrBpm,
                valueFormatter: { String(format: "%.1f", locale: Locale(identifier: "es_ES"), $0) }, unitText: "ppm",
                series: window.map { $0.summary?.restingHrBpm },
                bandLow: 45, bandHigh: 56, lineColorHex: 0x3BD671,
                detailNote: "Frecuencia cardíaca media sostenida durante el descanso nocturno."
            ),
            buildTrendItem(
                id: "r_resp", title: "Frecuencia respiratoria",
                currentValue: currentDaySummary?.respRateRpm,
                valueFormatter: { String(format: "%.1f", locale: Locale(identifier: "es_ES"), $0) }, unitText: "rpm",
                series: window.map { $0.summary?.respRateRpm },
                bandLow: 13.8, bandHigh: 16.8, lineColorHex: 0x3BD671,
                detailNote: "Respiraciones por minuto registradas durante el sueño."
            ),
            buildTrendItem(
                id: "r_spo2", title: "Saturación de oxígeno",
                currentValue: currentDaySummary?.spo2Percent,
                valueFormatter: { String(format: "%.1f", locale: Locale(identifier: "es_ES"), $0) }, unitText: "%",
                series: window.map { $0.summary?.spo2Percent },
                bandLow: 95.0, bandHigh: 100.0, lineColorHex: 0x3BD671,
                detailNote: "Porcentaje de saturación capilar periférica de oxígeno."
            ),
            buildTrendItem(
                id: "r_temp", title: "Temperatura de la muñeca",
                currentValue: wristTempAbsoluteC,
                valueFormatter: { String(format: "%.1f", locale: Locale(identifier: "es_ES"), $0) }, unitText: "°C",
                series: window.map { item in
                    item.summary?.wristTempAbsoluteC ?? item.summary?.wristTempDeltaC.map { 35.8 + $0 }
                },
                bandLow: 35.4, bandHigh: 36.4, lineColorHex: 0x3BD671,
                detailNote: "Temperatura media de la piel durante la noche anterior."
            )
        ]
    }

    var sleepTrends: [EffortTrendItem] {
        let window = trailingCalendarSummaries(days: 14)
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
                bandLow: 400, bandHigh: 540, lineColorHex: 0x93A8F8,
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

    /// Counts strictly MANUAL (non-automatic) Diario items completed on `dateIso` (tri-state ✓/✕ + mood + hydration).
    func manualCompletedCount(for dateIso: String) -> Int {
        let map = journalCheckinsByDate[dateIso] ?? [:]
        var count = 0
        for id in Self.manualHabitIds {
            if let st = map[id], st != .unset {
                count += 1
            }
        }
        if journalMoodByDate[dateIso] != nil { count += 1 }
        if (hydrationGlassesByDate[dateIso] ?? 0) > 0 { count += 1 }
        return count
    }

    /// A day receives the Diario checkmark badge ONLY when the user completed >= 20 manual (non-automatic) entries!
    func isDiarioDayCompleted(for dateIso: String) -> Bool {
        manualCompletedCount(for: dateIso) >= Self.diarioRequiredManualCount
    }

    /// Number of distinct dates on which the user has logged at least one manual Diario entry.
    var totalManualDiarioDaysLogged: Int {
        var dates = Set<String>()
        for (iso, map) in journalCheckinsByDate {
            if Self.manualHabitIds.contains(where: { (map[$0] ?? .unset) != .unset }) {
                dates.insert(iso)
            }
        }
        for iso in journalMoodByDate.keys { dates.insert(iso) }
        for (iso, g) in hydrationGlassesByDate where g > 0 { dates.insert(iso) }
        return dates.count
    }

    /// Calendar span (in days, inclusive) from the user's earliest manual Diario entry to `selectedDate`.
    var manualDiarioSpanDays: Int {
        var earliestIso: String? = nil
        for (iso, map) in journalCheckinsByDate {
            if Self.manualHabitIds.contains(where: { (map[$0] ?? .unset) != .unset }) {
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
        for entry in Self.journalCatalog {
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
                    profile: profile
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
                            dateIso: w.dateIso
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
            realHistory = updated
        }

        sectionCoachingCache.removeAll()
        dataRevision += 1
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
    }

    func setJournalMood(_ mood: Int) {
        journalMoodByDate[selectedDateIso] = mood
        persistState()
    }

    func addHydrationGlass() {
        hydrationGlassesByDate[selectedDateIso] = (hydrationGlassesByDate[selectedDateIso] ?? 0) + 1
        persistState()
    }

    func addQuickMeal(title: String, kcal: Int, protein: Int, carbs: Int, fat: Int) {
        var list = mealsByDate[selectedDateIso] ?? []
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        list.insert(
            NutritionMealItem(
                id: UUID().uuidString,
                title: title,
                timeLabel: f.string(from: Date()),
                kcal: kcal,
                proteinG: protein,
                carbsG: carbs,
                fatG: fat,
                qualityScore: 88
            ),
            at: 0
        )
        mealsByDate[selectedDateIso] = list
        persistState()
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
        self.realHistory = WhoopExportImporter.mergeDays(existing: self.realHistory, imported: result.days)
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
        shortcutSyncName = cleaned.isEmpty ? "Sync Improving (Automático)" : cleaned
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

    /// Pull-to-refresh on `HoyScreen`:
    /// - When `autoRunShortcutOnOpen == false` (default 100% silent in-app mode): stays inside Improving,
    ///   animates the top floating `Sincronizando…` -> `Sincronizado` bubble, and reloads the latest data from
    ///   `En mi iPhone / Improving` (plus live HealthKit if authorized) WITHOUT ever jumping out to the Shortcuts app!
    /// - When `autoRunShortcutOnOpen == true`: launches `shortcuts://x-callback-url/run-shortcut` directly.
    func handlePullToRefresh() async {
        if autoRunShortcutOnOpen {
            triggerShortcutRefreshSync(userInitiated: true)
            try? await Task.sleep(nanoseconds: 350_000_000)
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        presentSyncBanner(.syncing("Sincronizando…"))
        scanAutoSyncInboxIfNeeded(force: true, showBanner: true)
        #if os(iOS)
        if healthKitAuthorized && !healthKitSyncing {
            connectAndSyncAppleHealth()
        }
        #endif
        try? await Task.sleep(nanoseconds: 550_000_000)
    }

    /// Called whenever the app becomes `.active` (reopen / reload / returning from Shortcuts).
    /// Enforces a 90s anti-loop cooldown so returning from `x-callback-url` NEVER triggers an infinite loop!
    func handleAppBecameActive() {
        // 1. Returned manually from Shortcuts without x-callback firing yet -> read fresh file immediately
        if awaitingShortcutCallback {
            awaitingShortcutCallback = false
            shortcutTimeoutTask?.cancel()
            presentSyncBanner(.syncing("Sincronizando…"))
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 350_000_000)
                self?.scanAutoSyncInboxIfNeeded(force: true, showBanner: true)
            }
            return
        }

        // 2. Anti-loop cooldown (90s): if we just ran/returned from the shortcut, only check folder silently
        if let last = lastShortcutTriggerAt, Date().timeIntervalSince(last) < 90.0 {
            scanAutoSyncInboxIfNeeded(force: false, showBanner: true)
            return
        }

        // 3. Reopening / reloading app:
        //    - If `autoRunShortcutOnOpen == true`: jump to Shortcuts via x-callback-url
        //    - If `autoRunShortcutOnOpen == false` (silent 100% background Personal Automation mode):
        //      NEVER leave Improving! Scan immediately AND re-check at +1.8s & +4.2s to catch background
        //      iOS Personal Automation writes ("Al abrir Improving -> Ejecutar inmediatamente") with the top bubble!
        if autoRunShortcutOnOpen && !shortcutSyncName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 320_000_000)
                guard let self else { return }
                self.triggerShortcutRefreshSync(userInitiated: false)
            }
        } else {
            scanAutoSyncInboxIfNeeded(force: false, showBanner: true)
            scheduleSilentAutomationRechecks()
        }
    }

    private func scheduleSilentAutomationRechecks() {
        backgroundRecheckTask?.cancel()
        backgroundRecheckTask = Task { @MainActor [weak self] in
            for delayNs: UInt64 in [1_800_000_000, 2_400_000_000] {
                try? await Task.sleep(nanoseconds: delayNs)
                guard !Task.isCancelled, let self else { return }
                self.scanAutoSyncInboxIfNeeded(force: false, showBanner: true)
            }
        }
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

        if userInitiated {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
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

    /// Live filesystem watchers on BOTH `En mi iPhone / Improving` and `AutoSync`: detects `health_sync.json` writes
    /// even from background iOS Personal Automations while Improving stays in the foreground!
    private func startInboxDirectoryWatcher() {
        func makeWatcher(for dirURL: URL) -> DispatchSourceFileSystemObject? {
            let fd = open(dirURL.path, O_EVTONLY)
            guard fd >= 0 else { return nil }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .extend, .attrib], queue: .main)
            source.setEventHandler { [weak self] in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    self?.scanAutoSyncInboxIfNeeded(force: false, showBanner: true)
                }
            }
            source.setCancelHandler {
                close(fd)
            }
            source.resume()
            return source
        }
        inboxDirectorySource = makeWatcher(for: ShortcutsHealthSyncImporter.publicDocumentsURL)
        autoSyncSubdirSource = makeWatcher(for: ShortcutsHealthSyncImporter.autoSyncInboxURL)
    }

    func scanAutoSyncInboxIfNeeded(force: Bool = false, showBanner: Bool = false) {
        guard !isAutoSyncing else { return }
        let files = ShortcutsHealthSyncImporter.discoverInboxFiles()
        let pending: [(URL, String)] = files.compactMap { url in
            let sig = ShortcutsHealthSyncImporter.fileSignature(for: url)
            if !force && processedAutoSyncSignatures.contains(sig) { return nil }
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

        Task.detached(priority: .userInitiated) {
            let result = WhoopExportImporter.importURLs(pendingURLs, profile: profileSnapshot, priorHistory: priorSnapshot)
            await MainActor.run {
                self.isAutoSyncing = false
                for s in pendingSigs { self.processedAutoSyncSignatures.insert(s) }
                if !result.days.isEmpty {
                    let shouldJump = !self.hasImportedOrPairedRealData
                    self.applyImportedResult(result, navigateToLatest: shouldJump)
                    let hhmm = Self.currentHHMM()
                    let hrvCount = result.days.values.filter { $0.hrvMs != nil }.count
                    let latestDay = result.latestDateIso.flatMap { result.days[$0] }
                    let kcalTag = latestDay?.activeKcal.map { " · \($0) kcal" } ?? ""
                    let strainTag = latestDay?.strainPct.map { " · Esf \($0)%" } ?? ""
                    self.autoSyncStatusText = "✓ Sync \(hhmm) · \(result.days.count)d (\(hrvCount) VFC)\(kcalTag)\(strainTag)"
                    self.persistState()
                    if showBanner || self.syncBannerState != .hidden {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        self.presentSyncBanner(.synced("Sincronizado"), autoDismissAfter: 2.1)
                    }
                } else {
                    if force {
                        self.autoSyncStatusText = result.errorMessage ?? "Archivo detectado sin muestras válidas"
                    }
                    if showBanner || self.syncBannerState != .hidden {
                        self.presentSyncBanner(.hidden)
                    }
                }
            }
        }
    }

    func handleIncomingURL(_ url: URL) {
        // 1. File opened via Share Sheet / Files app ("Abrir en Improving")
        if url.isFileURL {
            importExportFiles(urls: [url])
            return
        }

        // 2. Custom URL Scheme: improving://sync[?from=shortcut_ok | ?source=clipboard | ?data=... | ?payload=...]
        guard url.scheme?.lowercased() == "improving" else { return }
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
            // from == "shortcut_ok": keep floating "Sincronizando…" bubble while parsing the newly written file!
            presentSyncBanner(.syncing("Sincronizando…"))
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 280_000_000)
                self?.scanAutoSyncInboxIfNeeded(force: true, showBanner: true)
            }
            return
        }

        if sourceParam == "clipboard" {
            presentSyncBanner(.syncing("Sincronizando…"))
            let paste = UIPasteboard.general.string ?? ""
            ingestRawShortcutsPayload(paste, sourceLabel: "Atajos (Portapapeles)")
            return
        }

        if let raw = rawParam, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            presentSyncBanner(.syncing("Sincronizando…"))
            let decoded: String = {
                if let b64 = Data(base64Encoded: raw), let str = String(data: b64, encoding: .utf8), !str.isEmpty {
                    return str
                }
                return raw
            }()
            ingestRawShortcutsPayload(decoded, sourceLabel: "Atajos (URL)")
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
                    let hrvCount = result.days.values.filter { $0.hrvMs != nil }.count
                    let latestDay = result.latestDateIso.flatMap { result.days[$0] }
                    let kcalTag = latestDay?.activeKcal.map { " · \($0) kcal" } ?? ""
                    let strainTag = latestDay?.strainPct.map { " · Esf \($0)%" } ?? ""
                    self.autoSyncStatusText = "✓ \(sourceLabel) \(hhmm) · \(result.days.count)d (\(hrvCount) VFC)\(kcalTag)\(strainTag)"
                    self.persistState()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
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

            // 7. Bevel Adaptive Recovery % (strictly from real measured sensors)
            d.recoveryPct = WhoopPhysiologyEngine.computeBevelRecoveryPercent(
                hrvMs: d.hrvMs,
                rhrBpm: d.restingHrBpm,
                respRpm: d.respRateRpm,
                spo2Pct: d.spo2Percent,
                wristTempDeltaC: d.wristTempDeltaC,
                lnHrvBaseline: lnHrvBaseline,
                rhrBaseline: rhrBaseline,
                respBaseline: respBaseline,
                profile: userProfile
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

            // 9. 5-Minute Stress + CONTINUOUS Cross-Day Energy Bank (ZERO midnight jump!)
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
                let stress5m = AppleHealthExportImporter.buildFiveMinuteStressSamples(
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
                        if sleepStartEp != nil {
                            return 32.0
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
                        workoutSpans: workoutSpans
                    )
                    if let lastPt = energy5m.last {
                        d.energySamples5m = energy5m
                        d.energyBankPercent = Int(lastPt.value.rounded())
                        prevDayEndEnergy = lastPt.value
                        prevDayIso = iso
                    }
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
        if av.hasStressData { highlights.append("estrés medio de \(stressScore) sobre 100") }
        if av.hasEnergyData { highlights.append("batería de energía al \(energyPercent)%") }
        if let steps = stepsCount { highlights.append("\(steps) pasos") }

        let dayJournal = journalCheckinsByDate[selectedDateIso] ?? [:]
        let yesHabits = Self.journalCatalog.filter { !$0.isAuto && dayJournal[$0.id] == .yes }.map(\.title)
        let noHabits = Self.journalCatalog.filter { !$0.isAuto && dayJournal[$0.id] == .no }.map(\.title)

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
        metricas["estres_medio"] = av.hasStressData ? (stressScore as Any) : "NO_DISPONIBLE"
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
            "marcados_no": noHabits
        ]

        let nowFmt = DateFormatter()
        nowFmt.dateFormat = "HH:mm"
        let payload: [String: Any] = [
            "hora_local_actual": nowFmt.string(from: Date()),
            "fecha_seleccionada": selectedDateIso,
            "origen_datos": hasImportedOrPairedRealData ? "Apple Health / Sensores reales" : "Modo vista previa",
            "perfil": perfil,
            "metricas_hoy": metricas,
            "diario_hoy": diarioHoy
        ]

        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
           let str = String(data: data, encoding: .utf8) {
            return (str, highlights)
        }
        return ("{}", highlights)
    }

    func sendCoachPrompt(_ rawPrompt: String) {
        let prompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isCoachThinking else { return }

        let now = Date()
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"
        let tsLabel = timeFmt.string(from: now)

        let historySnap = Array(coachMessages.suffix(16))
        let userMsg = CoachChatMessage(id: UUID().uuidString, isUser: true, text: prompt, timestampLabel: tsLabel, isSuggestionChip: false)
        coachMessages.append(userMsg)
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
                previousInteractionId: prevId
            )
            await MainActor.run {
                guard let self else { return }
                self.isCoachThinking = false
                if let newId = result.interactionId {
                    self.activeCoachInteractionId = newId
                }
                let replyFmt = DateFormatter()
                replyFmt.dateFormat = "HH:mm"
                self.coachMessages.append(
                    CoachChatMessage(
                        id: UUID().uuidString,
                        isUser: false,
                        verdictTitle: result.verdictTitle.isEmpty ? nil : result.verdictTitle,
                        text: result.text,
                        bullets: result.bullets,
                        timestampLabel: replyFmt.string(from: Date()),
                        isSuggestionChip: false,
                        modelUsed: result.modelUsed
                    )
                )
            }
        }
    }

    func startNewCleanChat() {
        coachMessages = []
        activeCoachInteractionId = nil
        isCoachThinking = false
    }

    func updateGeminiConfig(apiKey: String, model: String) {
        geminiApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        selectedGeminiModel = model
        dataRevision += 1
        persistState()
    }

    // MARK: - Persistence

    func persistState() {
        let snap = PersistedSnapshot(
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
            autoRunShortcutOnOpen: autoRunShortcutOnOpen
        )
        if let data = try? JSONEncoder().encode(snap) {
            try? data.write(to: persistenceURL, options: .atomic)
        }
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
        selectedGeminiModel = snap.selectedGeminiModel
        mealsByDate = snap.mealsByDate
        hydrationGlassesByDate = snap.hydrationGlassesByDate
        smartAlarmEnabled = snap.smartAlarmEnabled
        wakeOffsetMinutes = snap.wakeOffsetMinutes
        sleepGoalPct = snap.sleepGoalPct
        if !snap.visibleTabs.isEmpty { visibleTabs = Set(snap.visibleTabs) }
        if let cached = snap.sectionCoachingCache { sectionCoachingCache = cached }
        if let sigs = snap.processedAutoSyncSignatures { processedAutoSyncSignatures = Set(sigs) }
        if let status = snap.lastAutoSyncStatus, !status.isEmpty { autoSyncStatusText = status }
        if let sName = snap.shortcutSyncName, !sName.isEmpty { shortcutSyncName = sName }
        if let autoRun = snap.autoRunShortcutOnOpen { autoRunShortcutOnOpen = autoRun }

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
    }
}

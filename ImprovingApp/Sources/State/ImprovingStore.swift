import Foundation
import Combine
import SwiftUI
import AppleWatchReader
import WhoopBLE
import WhoopProtocol

@MainActor
final class ImprovingStore: ObservableObject {

    private struct PersistedSnapshot: Codable {
        var userProfile: UserPhysiologyProfile
        var isDarkMode: Bool
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
    }

    @Published var userProfile: UserPhysiologyProfile = UserPhysiologyProfile()
    @Published var dayOffset: Int = 0
    @Published var realHistory: [String: RealBiometricDaySummary] = [:]
    @Published var journalCheckinsByDate: [String: [String: JournalCheckState]] = [:]
    @Published var journalMoodByDate: [String: Int] = [:]
    @Published var mealsByDate: [String: [NutritionMealItem]] = [:]
    @Published var hydrationGlassesByDate: [String: Int] = [:]
    @Published var selectedHealthMetric: HealthMetricKind = .hrv
    @Published var selectedHealthRange: String = "30 d"
    @Published var selectedNutrientKey: String = "proteina"

    @Published var smartAlarmEnabled: Bool = true
    @Published var wakeOffsetMinutes: Int = 0
    @Published var sleepGoalPct: Int = 100
    @Published var visibleTabs: Set<MainTab> = Set(MainTab.allCases)

    @Published var whoopConnected: Bool = false
    @Published var whoopScanning: Bool = false
    @Published var whoopDeviceName: String = "WHOOP"
    @Published var whoopBatteryPct: Int? = nil
    @Published var bleLogs: [String] = []
    @Published var whoopPacketsReceived: Int = 0

    @Published var healthKitAuthorized: Bool = false
    @Published var healthKitSyncing: Bool = false
    @Published var healthKitLastSyncText: String = "Pendiente"

    @Published var importStatus: ExportImportStatus = ExportImportStatus()
    @Published var geminiApiKey: String = ""
    @Published var selectedGeminiModel: String = "gemini-2.5-flash"
    @Published var coachMessages: [CoachChatMessage] = [
        CoachChatMessage(
            id: "welcome",
            isUser: false,
            text: "Hola, soy tu coach de Improving en iPhone. Analizo tu recuperación, sueño, VFC y carga real de Apple Health o WHOOP.",
            timestampLabel: "Ahora",
            isSuggestionChip: false
        )
    ]
    @Published var isCoachThinking: Bool = false

    @Published var strengthSets: [(id: String, exercise: String, reps: Int, weightKg: Double, completed: Bool)] = [
        ("s1", "Press banca inclinado", 8, 70, true),
        ("s2", "Press banca inclinado", 8, 72.5, true),
        ("s3", "Remo con barra", 10, 65, false),
        ("s4", "Sentadilla búlgara", 10, 40, false),
    ]
    @Published var restTimerRunning: Bool = false
    @Published var restTimerSeconds: Int = 90

    let whoopBleReader = WhoopBLEReader()
    private var cancellables: Set<AnyCancellable> = []
    private var bleStreamTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?

    private let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var persistenceURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("improving_store_v1.json")
    }

    init() {
        loadPersistedState()
        bindWhoopBle()
        bindHealthKit()
    }

    deinit {
        bleStreamTask?.cancel()
        timerTask?.cancel()
    }

    // MARK: - Current Day Computations

    var selectedDate: Date {
        Calendar.current.date(byAdding: .day, value: -dayOffset, to: Date()) ?? Date()
    }

    var selectedDateIso: String {
        isoFormatter.string(from: selectedDate)
    }

    var currentDaySummary: RealBiometricDaySummary? {
        realHistory[selectedDateIso] ?? latestAvailableDay
    }

    var latestAvailableDay: RealBiometricDaySummary? {
        realHistory.keys.sorted().last.flatMap { realHistory[$0] }
    }

    var dateLabel: String {
        if dayOffset == 0 {
            let f = DateFormatter()
            f.locale = Locale(identifier: "es_ES")
            f.dateFormat = "'Hoy,' d MMM"
            return f.string(from: Date()).replacingOccurrences(of: ".", with: "")
        } else {
            let f = DateFormatter()
            f.locale = Locale(identifier: "es_ES")
            f.dateFormat = "EEE d MMM"
            return f.string(from: selectedDate).capitalized.replacingOccurrences(of: ".", with: "")
        }
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
            hasTempData: d?.wristTempDeltaC != nil,
            hasStressData: d?.stressScore != nil || !(d?.stressSeries24h.isEmpty ?? true),
            hasEnergyData: d?.energyBankPercent != nil || !(d?.energySeries24h.isEmpty ?? true),
            hasWorkoutData: !(d?.workouts.isEmpty ?? true)
        )
    }

    var strainPercent: Int { currentDaySummary?.strainPct ?? 0 }
    var strain21: Double { currentDaySummary?.strain21 ?? 0 }
    var recoveryPercent: Int { currentDaySummary?.recoveryPct ?? 0 }
    var sleepPercent: Int { currentDaySummary?.sleepPct ?? 0 }
    var hrvMs: Double { currentDaySummary?.hrvMs ?? 0 }
    var restingHrBpm: Double { currentDaySummary?.restingHrBpm ?? 0 }
    var liveHrBpm: Int { currentDaySummary?.liveHrBpm ?? Int(restingHrBpm.rounded()) }
    var respRateRpm: Double { currentDaySummary?.respRateRpm ?? 0 }
    var spo2Percent: Int { currentDaySummary?.spo2Percent ?? 0 }
    var wristTempDeltaC: Double { currentDaySummary?.wristTempDeltaC ?? 0 }
    var stressScore: Int { currentDaySummary?.stressScore ?? 0 }
    var energyPercent: Int { currentDaySummary?.energyBankPercent ?? 0 }
    var stepsCount: Int { currentDaySummary?.stepsCount ?? 0 }
    var workoutsToday: [EffortEventItem] { currentDaySummary?.workouts ?? [] }

    var sleepDurationText: String {
        guard let m = currentDaySummary?.asleepMinutes, m > 0 else { return "--" }
        return "\(m / 60) h \(String(format: "%02d", m % 60)) min"
    }

    var strainStatusText: String {
        guard dataAvailability.hasStrainData else { return "Sin datos" }
        let target = WhoopPhysiologyEngine.optimalTargetRange(for: max(recoveryPercent, 50))
        let frac = Double(strainPercent) / 100.0
        if frac > target.upperBound { return "Sobrecarga" }
        if frac >= target.lowerBound { return "Óptimo" }
        return strainPercent >= 65 ? "Alto" : "Moderado"
    }

    var recoveryStatusText: String {
        guard dataAvailability.hasRecoveryData else { return "Sin datos" }
        if recoveryPercent >= 67 { return "Óptima" }
        if recoveryPercent >= 34 { return "Moderada" }
        return "Baja"
    }

    var optimalEffortRange: ClosedRange<Double> {
        WhoopPhysiologyEngine.optimalTargetRange(for: recoveryPercent > 0 ? recoveryPercent : 70)
    }

    var effortTargetRangeText: String {
        let r = optimalEffortRange
        return "\(Int((r.lowerBound * 100).rounded()))%–\(Int((r.upperBound * 100).rounded()))%"
    }

    var activeCoachingSummary: String {
        guard dataAvailability.hasAnyRecordedData else {
            return "Conecta Apple Health, tu pulsera WHOOP o importa tu archivo de Salud (exportar.zip / export.xml) para calcular tu lectura diaria real."
        }
        let rec = recoveryPercent
        let s = strainPercent
        let hrvStr = hrvMs > 0 ? String(format: "%.1f ms", hrvMs) : "en calibración"
        if Double(s) / 100.0 > optimalEffortRange.upperBound {
            return "Has superado tu franja óptima de esfuerzo (\(s)% frente a \(effortTargetRangeText)). Prioriza hidratación y descanso temprano con tu VFC en \(hrvStr)."
        }
        if rec >= 67 {
            return "Amaneces con \(rec)% de recuperación y \(sleepDurationText) de sueño. Tu sistema nervioso (\(hrvStr)) está preparado para asimilar carga de calidad hoy."
        }
        return "Recuperación en \(rec)% y esfuerzo en \(s)%. Ajusta tu sesión dentro de \(effortTargetRangeText) para mantener tu tendencia positiva."
    }

    // MARK: - Actions

    func completeOnboarding(_ profile: UserPhysiologyProfile) {
        var p = profile
        p.onboardingCompleted = true
        userProfile = p
        persistState()
    }

    func updateProfile(_ profile: UserPhysiologyProfile) {
        userProfile = profile
        persistState()
    }

    func shiftDay(_ delta: Int) {
        dayOffset = max(dayOffset - delta, 0)
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
                qualityScore: 84
            ),
            at: 0
        )
        mealsByDate[selectedDateIso] = list
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
        Task.detached(priority: .userInitiated) {
            let result = WhoopExportImporter.importURLs(urls, profile: profileSnapshot)
            await MainActor.run {
                if let err = result.errorMessage, result.days.isEmpty {
                    self.importStatus = ExportImportStatus(isImporting: false, errorMessage: err)
                    return
                }
                self.realHistory = WhoopExportImporter.mergeDays(existing: self.realHistory, imported: result.days)
                for (iso, map) in result.journalByDate {
                    var dayJournal = self.journalCheckinsByDate[iso] ?? [:]
                    for (k, v) in map { dayJournal[k] = v }
                    self.journalCheckinsByDate[iso] = dayJournal
                }
                if let latest = self.realHistory.keys.sorted().last,
                   let latestDate = self.isoFormatter.date(from: latest) {
                    let diff = Calendar.current.dateComponents([.day], from: latestDate, to: Date()).day ?? 0
                    self.dayOffset = max(diff, 0)
                }
                let rangeText: String
                if let a = result.earliestDateIso, let b = result.latestDateIso {
                    rangeText = "\(a) – \(b)"
                } else {
                    rangeText = ""
                }
                var summary = "✓ \(result.days.count) días reales importados"
                if result.workoutsCount > 0 { summary += " · \(result.workoutsCount) entrenamientos" }
                self.importStatus = ExportImportStatus(
                    isImporting: false,
                    importedDaysCount: result.days.count,
                    importedWorkoutsCount: result.workoutsCount,
                    dateRangeLabel: rangeText,
                    summaryMessage: summary,
                    errorMessage: nil
                )
                self.persistState()
            }
        }
    }

    // MARK: - HealthKit & WHOOP Live Connectors

    func connectAndSyncAppleHealth() {
        #if os(iOS)
        healthKitSyncing = true
        Task {
            do {
                try await HealthKitReader.shared.requestAuthorization()
                self.healthKitAuthorized = HealthKitReader.shared.isAuthorized
                if let snap = await HealthKitReader.shared.syncLatestMetrics() {
                    self.ingestHealthKitSnapshot(snap)
                }
                self.healthKitLastSyncText = "Sincronizado"
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
                self.ingestHealthKitSnapshot(snap)
            }
            .store(in: &cancellables)
        #endif
    }

    #if os(iOS)
    private func ingestHealthKitSnapshot(_ snap: DailyHealthSnapshot) {
        let iso = isoFormatter.string(from: snap.day)
        var d = realHistory[iso] ?? RealBiometricDaySummary(dateIso: iso)
        if snap.hrv.weightedHRV > 0 { d.hrvMs = AppleHealthExportImporter.round1(snap.hrv.weightedHRV) }
        if snap.heartRate.restingHR > 0 { d.restingHrBpm = AppleHealthExportImporter.round1(snap.heartRate.restingHR) }
        if let live = snap.liveHeartRate { d.liveHrBpm = Int(live.rounded()) }
        if snap.vitals.meanRespiratoryRate > 0 { d.respRateRpm = AppleHealthExportImporter.round1(snap.vitals.meanRespiratoryRate) }
        if snap.vitals.meanSpO2 > 0 { d.spo2Percent = Int(snap.vitals.meanSpO2.rounded()) }
        if snap.vitals.tempDeltaCelsius != 0 { d.wristTempDeltaC = AppleHealthExportImporter.round1(snap.vitals.tempDeltaCelsius) }
        if let sl = snap.sleep {
            d.asleepMinutes = Int(sl.totalAsleepMinutes.rounded())
            d.inBedMinutes = Int(sl.inBedMinutes.rounded())
            d.deepMinutes = Int(sl.deepMinutes.rounded())
            d.remMinutes = Int(sl.remMinutes.rounded())
            d.sleepPct = min(max(Int(((sl.totalAsleepMinutes / 480.0) * 80.0 + sl.efficiencyPct * 0.2).rounded()), 20), 100)
            d.sleepDebtMinutes = max(480 - (d.asleepMinutes ?? 0), 0)
        }
        if snap.steps > 0 { d.stepsCount = snap.steps }
        if snap.activeCalories > 0 { d.activeKcal = Int(snap.activeCalories.rounded()) }
        if !snap.workouts.isEmpty {
            d.workouts = snap.workouts.map { w in
                EffortEventItem(
                    id: w.id.uuidString,
                    title: w.name,
                    timeRange: "Apple Health",
                    durationMin: w.durationMinutes,
                    avgHrBpm: w.avgHeartRate > 0 ? w.avgHeartRate : 134,
                    strainScore: AppleHealthExportImporter.round1(min(20.5, Double(w.activeCalories) / 65.0 + 3.0)),
                    strainPct: min(max(w.activeCalories / 8 + 15, 5), 98),
                    categoryLabel: "Watch",
                    kcal: w.activeCalories
                )
            }
        }
        if let hrv = d.hrvMs, let rhr = d.restingHrBpm {
            d.recoveryPct = WhoopPhysiologyEngine.computeRecoveryPercent(
                hrvMs: hrv,
                rhrBpm: rhr,
                respRpm: d.respRateRpm ?? 15.2,
                spo2Pct: Double(d.spo2Percent ?? 98),
                wristTempDeltaC: d.wristTempDeltaC ?? 0.0,
                sleepScorePct: d.sleepPct ?? 78
            )
        }
        realHistory[iso] = d
        healthKitAuthorized = true
        healthKitLastSyncText = "Actualizado"
        persistState()
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
                    self.whoopDeviceName = self.whoopBleReader.strapName ?? "WHOOP"
                }
            }
            .store(in: &cancellables)

        whoopBleReader.$latestBatteryPercent
            .receive(on: RunLoop.main)
            .assign(to: &$whoopBatteryPct)

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

    // MARK: - AI Coach

    func sendCoachPrompt(_ rawPrompt: String) {
        let prompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        let userMsg = CoachChatMessage(id: UUID().uuidString, isUser: true, text: prompt, timestampLabel: "Ahora", isSuggestionChip: false)
        coachMessages.append(userMsg)
        isCoachThinking = true

        let summary = "Recuperación \(recoveryPercent)%, Esfuerzo \(strainPercent)%, Sueño \(sleepDurationText), VFC \(hrvMs) ms, FCR \(restingHrBpm) ppm, Energía \(energyPercent)%, Estrés \(stressScore)/100"
        let key = geminiApiKey
        let model = selectedGeminiModel
        Task {
            let reply = await GeminiCoachService.shared.generateLiveCoachReply(
                prompt: prompt,
                apiKey: key,
                selectedModel: model,
                contextSummary: summary
            )
            await MainActor.run {
                self.isCoachThinking = false
                self.coachMessages.append(
                    CoachChatMessage(id: UUID().uuidString, isUser: false, text: reply, timestampLabel: "Ahora", isSuggestionChip: false)
                )
            }
        }
    }

    func startNewCleanChat() {
        coachMessages = [coachMessages.first].compactMap { $0 }
    }

    func updateGeminiConfig(apiKey: String, model: String) {
        geminiApiKey = apiKey
        selectedGeminiModel = model
        persistState()
    }

    // MARK: - Series Helpers for Charts

    func metricSeries(for kind: HealthMetricKind, spanDays: Int) -> [(String, Double)] {
        let sorted = realHistory.values.sorted { $0.dateIso < $1.dateIso }.suffix(spanDays)
        return sorted.compactMap { d in
            let v: Double?
            switch kind {
            case .respiratoryRate: v = d.respRateRpm
            case .restingHeartRate: v = d.restingHrBpm
            case .hrv: v = d.hrvMs
            case .oxygenSaturation: v = d.spo2Percent.map(Double.init)
            case .wristTemperature: v = d.wristTempDeltaC
            case .sleepDuration: v = d.asleepMinutes.map { Double($0) / 60.0 }
            }
            return v.map { (String(d.dateIso.suffix(5)), $0) }
        }
    }

    // MARK: - Persistence

    func persistState() {
        let snap = PersistedSnapshot(
            userProfile: userProfile,
            isDarkMode: BevelColors.isDarkMode,
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
            visibleTabs: Array(visibleTabs)
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
        BevelColors.isDarkMode = snap.isDarkMode
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
    }
}

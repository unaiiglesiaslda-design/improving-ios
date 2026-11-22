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
    }

    @Published var userProfile: UserPhysiologyProfile = {
        var p = UserPhysiologyProfile()
        p.onboardingCompleted = true
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
    @Published var whoopBatteryPct: Int? = 86
    @Published var bleLogs: [String] = [
        "Simulación activa: 730 días (2 años) de historial WHOOP cargado",
        "Pulsa Escanear o Importar para usar tus datos reales de Apple Health / WHOOP"
    ]
    @Published var whoopPacketsReceived: Int = 0

    @Published var healthKitAuthorized: Bool = false
    @Published var healthKitSyncing: Bool = false
    @Published var healthKitLastSyncText: String = "Activo"

    @Published var importStatus: ExportImportStatus = ExportImportStatus()
    @Published var geminiApiKey: String = ""
    @Published var selectedGeminiModel: String = "gemini-2.5-flash"
    @Published var coachMessages: [CoachChatMessage] = [
        CoachChatMessage(
            id: "welcome",
            isUser: false,
            text: "Hola, soy tu coach de Improving. Analizo tu recuperación (79%), esfuerzo (82%), sueño (7 h 58 min) y VFC (77,5 ms) en tiempo real.",
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
        return dir.appendingPathComponent("improving_store_v2.json")
    }

    init() {
        loadPersistedState()
        if simulatedHistory.isEmpty {
            simulatedHistory = WhoopPhysiologyEngine.generateTwoYearSimulatedHistory(profile: userProfile)
        }
        seedDefaultMealsIfNeeded()
        bindWhoopBle()
        bindHealthKit()
    }

    deinit {
        bleStreamTask?.cancel()
        timerTask?.cancel()
    }

    private func seedDefaultMealsIfNeeded() {
        let todayIso = isoFormatter.string(from: Date())
        if mealsByDate[todayIso] == nil {
            mealsByDate[todayIso] = [
                NutritionMealItem(id: "m1", title: "Bowl de avena, huevos y frutos rojos", timeLabel: "08:30", kcal: 540, proteinG: 36, carbsG: 58, fatG: 16, qualityScore: 88),
                NutritionMealItem(id: "m2", title: "Salmón a la plancha con arroz jazmín y aguacate", timeLabel: "14:15", kcal: 680, proteinG: 52, carbsG: 62, fatG: 22, qualityScore: 86),
                NutritionMealItem(id: "m3", title: "Pechuga de pavo, boniato asado y verduras", timeLabel: "20:45", kcal: 450, proteinG: 38, carbsG: 42, fatG: 12, qualityScore: 84),
            ]
            hydrationGlassesByDate[todayIso] = 8
        }
    }

    var activeHistory: [String: RealBiometricDaySummary] {
        (hasImportedOrPairedRealData && !realHistory.isEmpty) ? realHistory : simulatedHistory
    }

    var selectedDate: Date {
        Calendar.current.date(byAdding: .day, value: -dayOffset, to: Date()) ?? Date()
    }

    var selectedDateIso: String {
        isoFormatter.string(from: selectedDate)
    }

    var currentDaySummary: RealBiometricDaySummary? {
        activeHistory[selectedDateIso] ?? latestAvailableDay
    }

    var latestAvailableDay: RealBiometricDaySummary? {
        activeHistory.keys.sorted().last.flatMap { activeHistory[$0] }
    }

    var dateLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        if dayOffset == 0 {
            f.dateFormat = "'Hoy,' d MMM"
            return f.string(from: Date()).replacingOccurrences(of: ".", with: "")
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
    var spo2DisplayDouble: Double { Double(spo2Percent) + 0.2 }
    var wristTempDeltaC: Double { currentDaySummary?.wristTempDeltaC ?? 0 }
    var wristTempAbsoluteC: Double { 35.8 + wristTempDeltaC }
    var stressScore: Int { currentDaySummary?.stressScore ?? 0 }
    var stressMax: Int {
        let s = currentDaySummary?.stressSeries24h ?? []
        return Int((s.max() ?? 77).rounded())
    }
    var stressMin: Int {
        let s = currentDaySummary?.stressSeries24h ?? []
        return Int((s.min() ?? 2).rounded())
    }
    var stressAvg: Int { stressScore > 0 ? stressScore : 35 }
    var stressStatusLabel: String {
        if stressScore < 30 { return "Bajo" }
        if stressScore < 58 { return "Moderado" }
        return "Alto"
    }
    var energyPercent: Int { currentDaySummary?.energyBankPercent ?? 0 }
    var stepsCount: Int { currentDaySummary?.stepsCount ?? 0 }
    var vo2Max: Double { currentDaySummary?.vo2MaxMlKgMin ?? 44.3 }
    var cgmMgDl: Int { currentDaySummary?.glucoseMgDl ?? 94 }
    var workoutsToday: [EffortEventItem] { currentDaySummary?.workouts ?? [] }
    var mealsToday: [NutritionMealItem] { mealsByDate[selectedDateIso] ?? mealsByDate[isoFormatter.string(from: Date())] ?? [] }
    var totalCaloriesToday: Int { mealsToday.reduce(0) { $0 + $1.kcal } }
    var totalProteinToday: Int { mealsToday.reduce(0) { $0 + $1.proteinG } }
    var totalCarbsToday: Int { mealsToday.reduce(0) { $0 + $1.carbsG } }
    var totalFatToday: Int { mealsToday.reduce(0) { $0 + $1.fatG } }
    var foodQualityScore: Int {
        let m = mealsToday
        return m.isEmpty ? 86 : (m.reduce(0) { $0 + $1.qualityScore } / m.count)
    }

    var sleepDurationText: String {
        guard let m = currentDaySummary?.asleepMinutes, m > 0 else { return "--" }
        return "\(m / 60) h \(String(format: "%02d", m % 60)) min"
    }

    var sleepInBedText: String {
        guard let m = currentDaySummary?.inBedMinutes, m > 0 else { return "--" }
        return "\(m / 60) h \(String(format: "%02d", m % 60)) min"
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

    var optimalEffortRange: ClosedRange<Double> {
        WhoopPhysiologyEngine.optimalTargetRange(for: recoveryPercent > 0 ? recoveryPercent : 79)
    }

    var effortTargetRangeText: String {
        let r = optimalEffortRange
        return "\(Int((r.lowerBound * 100).rounded()))%–\(Int((r.upperBound * 100).rounded()))%"
    }

    var activeCoachingSummary: String {
        guard dataAvailability.hasAnyRecordedData else {
            return "Conecta Apple Health, tu pulsera WHOOP o importa tu archivo de Salud (exportar.zip / export.xml) para calcular tu lectura diaria real."
        }
        let debt = currentDaySummary?.sleepDebtMinutes ?? 36
        let needMin = 480 + debt + (strainPercent > 75 ? 31 : 12)
        return "Toca encarrilar la noche hacia el descanso. Cierras el día con un \(strainPercent)% de esfuerzo y tu cuerpo necesita dormir \(needMin / 60) h \(String(format: "%02d", needMin % 60)) min para dejar a cero los \(debt) minutos de deuda acumulada, así que suelta pantallas ya y busca tu cama pensando en despertar fresco a las 07:40."
    }

    // MARK: - Trend Lists for Esfuerzo, Recuperación & Sueño

    var effortTrends: [EffortTrendItem] {
        let recent = recentSeries(days: 14)
        return [
            EffortTrendItem(
                id: "t_strain",
                title: "Puntuación del Esfuerzo",
                valueText: "\(strainPercent)",
                unitText: "%",
                statusText: "Rango normal",
                statusTone: .normal,
                points: recent.map { Double($0.strainPct ?? 72) },
                bandLow: 58,
                bandHigh: 84,
                lineColorHex: 0xF97316,
                detailNote: "Evolución de tu esfuerzo cardiovascular y muscular diario."
            ),
            EffortTrendItem(
                id: "t_dur",
                title: "Duración del ejercicio",
                valueText: "\(workoutsToday.first?.durationMin ?? 86)",
                unitText: "min",
                statusText: "Por encima de tu media",
                statusTone: .above,
                points: recent.map { Double($0.workouts.first?.durationMin ?? 55) },
                bandLow: 40,
                bandHigh: 75,
                lineColorHex: 0xFB923C,
                detailNote: "Minutos activos acumulados en tus sesiones."
            ),
            EffortTrendItem(
                id: "t_perf",
                title: "Rendimiento del Esfuerzo",
                valueText: "+6",
                unitText: "%",
                statusText: "Dentro del objetivo",
                statusTone: .normal,
                points: recent.map { Double($0.strainPct ?? 74) },
                bandLow: 60,
                bandHigh: 84,
                lineColorHex: 0x0EA5E9,
                detailNote: "Alineación frente a tu zona óptima según recuperación."
            )
        ]
    }

    var recoveryTrends: [EffortTrendItem] {
        let recent = recentSeries(days: 14)
        return [
            EffortTrendItem(
                id: "r_rec",
                title: "Recuperación diaria",
                valueText: "\(recoveryPercent)",
                unitText: "%",
                statusText: "Verde · Óptima",
                statusTone: .normal,
                points: recent.map { Double($0.recoveryPct ?? 76) },
                bandLow: 60,
                bandHigh: 92,
                lineColorHex: 0x16A34A,
                detailNote: "Capacidad de tu sistema nervioso autónomo para asimilar carga."
            ),
            EffortTrendItem(
                id: "r_hrv",
                title: "VFC en reposo",
                valueText: String(format: "%.1f", locale: Locale(identifier: "es_ES"), hrvMs),
                unitText: "ms",
                statusText: "Rango normal",
                statusTone: .normal,
                points: recent.map { $0.hrvMs ?? 74.0 },
                bandLow: 68.6,
                bandHigh: 107.4,
                lineColorHex: 0x22C55E,
                detailNote: "Variabilidad de la frecuencia cardíaca consolidada en sueño profundo."
            ),
            EffortTrendItem(
                id: "r_rhr",
                title: "FC en reposo",
                valueText: String(format: "%.1f", locale: Locale(identifier: "es_ES"), restingHrBpm),
                unitText: "ppm",
                statusText: "Óptimo",
                statusTone: .normal,
                points: recent.map { $0.restingHrBpm ?? 49.0 },
                bandLow: 46,
                bandHigh: 56,
                lineColorHex: 0x0EA5E9,
                detailNote: "Frecuencia cardíaca mínima sostenida durante el descanso nocturno."
            )
        ]
    }

    var sleepTrends: [EffortTrendItem] {
        let recent = recentSeries(days: 14)
        return [
            EffortTrendItem(
                id: "s_score",
                title: "Calidad del sueño",
                valueText: "\(sleepPercent)",
                unitText: "%",
                statusText: "Óptimo",
                statusTone: .normal,
                points: recent.map { Double($0.sleepPct ?? 88) },
                bandLow: 78,
                bandHigh: 96,
                lineColorHex: 0x6366F1,
                detailNote: "Puntuación combinada de duración, eficiencia y fases reparadoras."
            ),
            EffortTrendItem(
                id: "s_dur",
                title: "Tiempo dormido",
                valueText: sleepDurationText,
                unitText: "",
                statusText: "Rango normal",
                statusTone: .normal,
                points: recent.map { Double($0.asleepMinutes ?? 455) / 60.0 },
                bandLow: 7.0,
                bandHigh: 8.8,
                lineColorHex: 0x818CF8,
                detailNote: "Horas netas de sueño excluyendo despertares nocturnos."
            )
        ]
    }

    private func recentSeries(days: Int) -> [RealBiometricDaySummary] {
        let all = activeHistory.values.sorted { $0.dateIso < $1.dateIso }
        return Array(all.suffix(days))
    }

    // MARK: - User Actions

    func completeOnboarding(_ profile: UserPhysiologyProfile) {
        var p = profile
        p.onboardingCompleted = true
        userProfile = p
        persistState()
    }

    func replayOnboarding() {
        userProfile.onboardingCompleted = false
        persistState()
    }

    func updateProfile(_ profile: UserPhysiologyProfile) {
        userProfile = profile
        persistState()
    }

    func shiftDay(_ delta: Int) {
        dayOffset = min(max(dayOffset + delta, 0), max(activeHistory.count - 1, 0))
    }

    func selectDayOffset(_ offset: Int) {
        dayOffset = max(offset, 0)
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
        hydrationGlassesByDate[selectedDateIso] = (hydrationGlassesByDate[selectedDateIso] ?? 8) + 1
        persistState()
    }

    func addQuickMeal(title: String, kcal: Int, protein: Int, carbs: Int, fat: Int) {
        var list = mealsByDate[selectedDateIso] ?? mealsToday
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
        let ev = EffortEventItem(
            id: UUID().uuidString,
            title: title,
            timeRange: "Hoy",
            durationMin: durationMin,
            avgHrBpm: 144,
            strainScore: 13.8,
            strainPct: 74,
            categoryLabel: "Actividad",
            kcal: kcal
        )
        d.workouts.insert(ev, at: 0)
        if hasImportedOrPairedRealData {
            realHistory[selectedDateIso] = d
        } else {
            simulatedHistory[selectedDateIso] = d
        }
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
                self.hasImportedOrPairedRealData = true
                self.realHistory = WhoopExportImporter.mergeDays(existing: self.realHistory, imported: result.days)
                for (iso, map) in result.journalByDate {
                    var dayJournal = self.journalCheckinsByDate[iso] ?? [:]
                    for (k, v) in map { dayJournal[k] = v }
                    self.journalCheckinsByDate[iso] = dayJournal
                }
                self.dayOffset = 0
                let rangeText = (result.earliestDateIso != nil && result.latestDateIso != nil)
                    ? "\(result.earliestDateIso!) – \(result.latestDateIso!)"
                    : ""
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
        var d = realHistory[iso] ?? activeHistory[iso] ?? RealBiometricDaySummary(dateIso: iso)
        var hasReal = false
        if snap.hrv.weightedHRV > 0 { d.hrvMs = AppleHealthExportImporter.round1(snap.hrv.weightedHRV); hasReal = true }
        if snap.heartRate.restingHR > 0 { d.restingHrBpm = AppleHealthExportImporter.round1(snap.heartRate.restingHR); hasReal = true }
        if let live = snap.liveHeartRate { d.liveHrBpm = Int(live.rounded()); hasReal = true }
        if snap.vitals.meanRespiratoryRate > 0 { d.respRateRpm = AppleHealthExportImporter.round1(snap.vitals.meanRespiratoryRate); hasReal = true }
        if snap.vitals.meanSpO2 > 0 { d.spo2Percent = Int(snap.vitals.meanSpO2.rounded()); hasReal = true }
        if snap.vitals.tempDeltaCelsius != 0 { d.wristTempDeltaC = AppleHealthExportImporter.round1(snap.vitals.tempDeltaCelsius); hasReal = true }
        if let sl = snap.sleep {
            d.asleepMinutes = Int(sl.totalAsleepMinutes.rounded())
            d.inBedMinutes = Int(sl.inBedMinutes.rounded())
            d.deepMinutes = Int(sl.deepMinutes.rounded())
            d.remMinutes = Int(sl.remMinutes.rounded())
            d.sleepPct = min(max(Int(((sl.totalAsleepMinutes / 480.0) * 80.0 + sl.efficiencyPct * 0.2).rounded()), 20), 100)
            d.sleepDebtMinutes = max(480 - (d.asleepMinutes ?? 0), 0)
            hasReal = true
        }
        if snap.steps > 0 { d.stepsCount = snap.steps; hasReal = true }
        if snap.activeCalories > 0 { d.activeKcal = Int(snap.activeCalories.rounded()); hasReal = true }
        if !snap.workouts.isEmpty {
            d.workouts = snap.workouts.map { w in
                EffortEventItem(
                    id: w.id.uuidString,
                    title: w.name,
                    timeRange: "Apple Health",
                    durationMin: w.durationMinutes,
                    avgHrBpm: w.avgHeartRate > 0 ? w.avgHeartRate : 138,
                    strainScore: AppleHealthExportImporter.round1(min(20.5, Double(w.activeCalories) / 65.0 + 3.0)),
                    strainPct: min(max(w.activeCalories / 8 + 15, 5), 98),
                    categoryLabel: "Watch",
                    kcal: w.activeCalories
                )
            }
            hasReal = true
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
        if hasReal {
            realHistory[iso] = d
            hasImportedOrPairedRealData = true
            healthKitAuthorized = true
            healthKitLastSyncText = "Actualizado"
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
                    var d = self.realHistory[iso] ?? self.activeHistory[iso] ?? RealBiometricDaySummary(dateIso: iso)
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
        let sorted = activeHistory.values.sorted { $0.dateIso < $1.dateIso }.suffix(spanDays)
        let inFmt = isoFormatter
        let outFmt = DateFormatter()
        outFmt.locale = Locale(identifier: "es_ES")
        outFmt.dateFormat = "d MMM"
        return sorted.compactMap { d in
            let v: Double?
            switch kind {
            case .respiratoryRate: v = d.respRateRpm
            case .restingHeartRate: v = d.restingHrBpm
            case .hrv: v = d.hrvMs
            case .oxygenSaturation: v = d.spo2Percent.map { Double($0) + 0.2 }
            case .wristTemperature: v = d.wristTempDeltaC.map { 35.8 + $0 }
            case .sleepDuration: v = d.asleepMinutes.map { Double($0) / 60.0 }
            }
            guard let val = v else { return nil }
            let label = inFmt.date(from: d.dateIso).map { outFmt.string(from: $0).replacingOccurrences(of: ".", with: "") } ?? String(d.dateIso.suffix(5))
            return (label, val)
        }
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
    }
}

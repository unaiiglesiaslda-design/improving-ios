import Foundation
import Combine
import SwiftUI
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
    @Published var whoopBatteryPct: Int? = nil
    @Published var bleLogs: [String] = [
        "Conecta WHOOP BLE, Apple Health en vivo o importa exportar.zip para ver tus datos reales"
    ]
    @Published var whoopPacketsReceived: Int = 0

    @Published var healthKitAuthorized: Bool = false
    @Published var healthKitSyncing: Bool = false
    @Published var healthKitLastSyncText: String = "Listo"

    @Published var importStatus: ExportImportStatus = ExportImportStatus()
    @Published var geminiApiKey: String = ""
    @Published var selectedGeminiModel: String = "gemini-2.5-flash"
    @Published var coachMessages: [CoachChatMessage] = []
    @Published var isCoachThinking: Bool = false
    private var activeCoachInteractionId: String? = nil

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
        seedDefaultMealsIfNeeded()
        bindWhoopBle()
        bindHealthKit()
    }

    deinit {
        bleStreamTask?.cancel()
        timerTask?.cancel()
    }

    private func seedDefaultMealsIfNeeded() {
        guard !hasImportedOrPairedRealData else { return }
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

    /// STRICT ZERO-FABRICATION: When real data is imported/paired, returns ONLY the exact selected date's record (nil if nothing was recorded that day).
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

    // MARK: - Strict Real Metrics (No Fabricated Defaults)

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
        WhoopPhysiologyEngine.optimalTargetRange(for: dataAvailability.hasRecoveryData ? recoveryPercent : 65)
    }

    var effortTargetRangeText: String {
        guard dataAvailability.hasRecoveryData else { return "--" }
        let r = optimalEffortRange
        return "\(Int((r.lowerBound * 100).rounded()))%–\(Int((r.upperBound * 100).rounded()))%"
    }

    var activeCoachingSummary: String {
        let av = dataAvailability
        if !av.hasAnyRecordedData {
            if hasImportedOrPairedRealData {
                return "No hay mediciones recopiladas en Apple Health ni en tu reloj para el \(fullDateLabel). Usa las flechas o el calendario para ver los días con registros."
            }
            return "Conecta Apple Health, tu pulsera WHOOP o importa tu archivo exportar.zip para ver tu lectura diaria real."
        }
        var parts: [String] = []
        if av.hasRecoveryData { parts.append("recuperación del \(recoveryPercent)%") }
        if av.hasStrainData { parts.append("esfuerzo en \(strainPercent)%") }
        if av.hasSleepData { parts.append("sueño de \(sleepDurationText)") }
        if av.hasHrvData { parts.append(String(format: "VFC de %.1f ms", locale: Locale(identifier: "es_ES"), hrvMs)) }
        if av.hasEnergyData { parts.append("energía al \(energyPercent)%") }

        let joined = parts.joined(separator: ", ")
        if let debt = currentDaySummary?.sleepDebtMinutes, debt > 0 {
            let needMin = 480 + debt + (strainPercent > 75 ? 25 : 10)
            return "Lectura real del día: \(joined). Para recuperar los \(debt) min de deuda acumulada, apunta a dormir \(needMin / 60) h \(String(format: "%02d", needMin % 60)) min esta noche."
        }
        return "Lectura real del día: \(joined). Ajusta la intensidad y el descanso en función de tus señales registradas."
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
                detailNote: "Frecuencia cardíaca mínima sostenida durante el descanso."
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

    // MARK: - Diario Real 90-Day Statistical Correlation & Reliability Engine

    static let journalCatalog: [(id: String, emoji: String, title: String, isAuto: Bool)] = [
        // Automatic habits evaluated from real watch / Apple Health data
        ("a_noise", "🔊", "Ruido al dormir de 50+ dB", true),
        ("a_strength", "🏋️", "20+ minutos de fuerza", true),
        ("a_daylight", "☀️", "20+ minutos de luz natural", true),
        ("a_steps", "👟", "10.000+ pasos", true),
        ("a_cardio", "🏃", "20+ minutos de cardio", true),
        ("a_z2", "🟠", "30+ minutos en la zona 2", true),
        ("a_stress", "💢", "50+ puntuación del Estrés", true),
        ("a_strain", "😮‍💨", "Objetivo de Esfuerzo superado", true),
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
    ]

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

    func computeJournalImpacts(for target: JournalImpactTarget) -> [JournalHabitImpactItem] {
        let cal = Calendar.current
        let anchor = cal.startOfDay(for: selectedDate)
        var last90Isos: [String] = []
        last90Isos.reserveCapacity(90)
        for back in 0..<90 {
            if let d = cal.date(byAdding: .day, value: -back, to: anchor) {
                last90Isos.append(isoFormatter.string(from: d))
            }
        }

        var items: [JournalHabitImpactItem] = []
        for entry in Self.journalCatalog {
            var yesVals: [Double] = []
            var noVals: [Double] = []

            for iso in last90Isos {
                guard let day = activeHistory[iso] else { continue }
                let outcomeOpt: Int? = (target == .recovery) ? day.recoveryPct : day.sleepPct
                guard let outcome = outcomeOpt else { continue }

                let state: JournalCheckState
                if entry.isAuto {
                    state = automaticHabitState(id: entry.id, day: day)
                } else {
                    state = journalCheckinsByDate[iso]?[entry.id] ?? .unset
                }

                switch state {
                case .yes: yesVals.append(Double(outcome))
                case .no: noVals.append(Double(outcome))
                case .unset: break // Strictly ignore unselected entries!
                }
            }

            let yCount = yesVals.count
            let nCount = noVals.count
            let tier: JournalReliabilityTier
            let impact: Int
            if yCount >= 5 && nCount >= 5 {
                tier = .high
                let meanY = yesVals.reduce(0, +) / Double(yCount)
                let meanN = noVals.reduce(0, +) / Double(nCount)
                impact = Int((meanY - meanN).rounded())
            } else if yCount >= 1 && nCount >= 1 {
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
            return (a.yesCount + a.noCount) > (b.yesCount + b.noCount)
        }
    }

    // MARK: - User Actions & Date Selection

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
        let ev = EffortEventItem(
            id: UUID().uuidString,
            title: title,
            timeRange: "Hoy",
            durationMin: durationMin,
            avgHrBpm: 0,
            strainScore: AppleHealthExportImporter.round1(min(Double(durationMin) / 5.0, 20.0)),
            strainPct: min(max(durationMin, 10), 95),
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
                if let latestIso = result.latestDateIso, let latestDate = self.isoFormatter.date(from: latestIso) {
                    self.selectDate(latestDate)
                } else {
                    self.dayOffset = 0
                }
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
        var d = realHistory[iso] ?? RealBiometricDaySummary(dateIso: iso)
        var hasReal = false
        if snap.hrv.weightedHRV > 0 { d.hrvMs = AppleHealthExportImporter.round1(snap.hrv.weightedHRV); hasReal = true }
        if snap.heartRate.restingHR > 0 { d.restingHrBpm = AppleHealthExportImporter.round1(snap.heartRate.restingHR); hasReal = true }
        if let live = snap.liveHeartRate { d.liveHrBpm = Int(live.rounded()); hasReal = true }
        if snap.vitals.meanRespiratoryRate > 0 { d.respRateRpm = AppleHealthExportImporter.round1(snap.vitals.meanRespiratoryRate); hasReal = true }
        if snap.vitals.meanSpO2 > 0 { d.spo2Percent = AppleHealthExportImporter.round1(snap.vitals.meanSpO2); hasReal = true }
        if snap.vitals.tempDeltaCelsius != 0 { d.wristTempDeltaC = AppleHealthExportImporter.round1(snap.vitals.tempDeltaCelsius); hasReal = true }
        if let sl = snap.sleep, sl.totalAsleepMinutes > 0 {
            d.asleepMinutes = Int(sl.totalAsleepMinutes.rounded())
            d.inBedMinutes = Int(sl.inBedMinutes.rounded())
            if sl.deepMinutes > 0 { d.deepMinutes = Int(sl.deepMinutes.rounded()) }
            if sl.remMinutes > 0 { d.remMinutes = Int(sl.remMinutes.rounded()) }
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
                    avgHrBpm: w.avgHeartRate > 0 ? w.avgHeartRate : 0,
                    strainScore: AppleHealthExportImporter.round1(min(20.5, Double(w.activeCalories) / 65.0 + 3.0)),
                    strainPct: min(max(w.activeCalories / 8 + 15, 5), 98),
                    categoryLabel: "Watch",
                    kcal: w.activeCalories,
                    dateIso: iso
                )
            }
            hasReal = true
        }
        if let hrv = d.hrvMs, let rhr = d.restingHrBpm {
            d.recoveryPct = WhoopPhysiologyEngine.computeRecoveryPercent(
                hrvMs: hrv,
                rhrBpm: rhr,
                respRpm: d.respRateRpm ?? 15.2,
                spo2Pct: d.spo2Percent ?? 98.0,
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

    // MARK: - AI Coach (Exact Android 3-Tier Engine + Zero-Fabrication JSON Context)

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
        let yesHabits = Self.journalCatalog.filter { dayJournal[$0.id] == .yes }.map(\.title)
        let noHabits = Self.journalCatalog.filter { dayJournal[$0.id] == .no }.map(\.title)

        let payload: [String: Any] = [
            "fecha_seleccionada": selectedDateIso,
            "origen_datos": hasImportedOrPairedRealData ? "Apple Health / Sensores reales" : "Modo vista previa",
            "perfil": [
                "nombre": userProfile.userName.isEmpty ? "Usuario" : userProfile.userName,
                "edad": Int(userProfile.ageYears),
                "sexo": userProfile.sex.rawValue,
                "peso_kg": latestBodyWeightKg ?? userProfile.weightKg,
                "altura_cm": userProfile.heightCm
            ],
            "metricas_hoy": [
                "recuperacion_pct": av.hasRecoveryData ? recoveryPercent : "NO_DISPONIBLE",
                "esfuerzo_pct": av.hasStrainData ? strainPercent : "NO_DISPONIBLE",
                "strain_21": av.hasStrainData ? strain21 : "NO_DISPONIBLE",
                "sueno_pct": av.hasSleepData ? sleepPercent : "NO_DISPONIBLE",
                "sueno_duracion": av.hasSleepData ? sleepDurationText : "NO_DISPONIBLE",
                "sueno_profundo_min": (d?.deepMinutes ?? 0) > 0 ? (d?.deepMinutes ?? 0) : "NO_DISPONIBLE",
                "sueno_rem_min": (d?.remMinutes ?? 0) > 0 ? (d?.remMinutes ?? 0) : "NO_DISPONIBLE",
                "vfc_ms": av.hasHrvData ? hrvMs : "NO_DISPONIBLE",
                "fc_reposo_ppm": av.hasRestingHrData ? restingHrBpm : "NO_DISPONIBLE",
                "frecuencia_respiratoria_rpm": av.hasRespData ? respRateRpm : "NO_DISPONIBLE",
                "spo2_pct": spo2Value ?? "NO_DISPONIBLE",
                "temperatura_muneca_c": wristTempAbsoluteC ?? "NO_DISPONIBLE",
                "estres_medio": av.hasStressData ? stressScore : "NO_DISPONIBLE",
                "energia_pct": av.hasEnergyData ? energyPercent : "NO_DISPONIBLE",
                "pasos": stepsCount ?? "NO_DISPONIBLE",
                "vo2_max": latestVo2Max ?? "NO_DISPONIBLE",
                "entrenamientos_hoy": workoutsToday.isEmpty ? "NINGUNO" : workoutsToday.map { "\($0.title) \($0.durationMin)min \($0.kcal)kcal" }
            ],
            "diario_hoy": [
                "marcados_si": yesHabits,
                "marcados_no": noHabits
            ]
        ]

        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
           let str = String(data: data, encoding: .utf8) {
            return (str, highlights)
        }
        return ("{}", highlights)
    }

    func sendCoachPrompt(_ rawPrompt: String) {
        let prompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        let userMsg = CoachChatMessage(id: UUID().uuidString, isUser: true, text: prompt, timestampLabel: "Ahora", isSuggestionChip: false)
        coachMessages.append(userMsg)
        isCoachThinking = true

        let ctx = buildBiometricContextJson()
        let key = geminiApiKey
        let model = selectedGeminiModel
        let userName = userProfile.userName
        let missing = dataAvailability.missingCategoryNames
        let historySnap = Array(coachMessages.dropLast().suffix(8))
        let prevId = activeCoachInteractionId

        Task {
            let result = await GeminiCoachService.shared.askLiveCoach(
                prompt: prompt,
                apiKey: key,
                selectedModel: model,
                userName: userName,
                biometricContextJson: ctx.json,
                availableHighlights: ctx.highlights,
                missingCategories: missing,
                history: historySnap,
                previousInteractionId: prevId
            )
            await MainActor.run {
                self.isCoachThinking = false
                if let newId = result.interactionId {
                    self.activeCoachInteractionId = newId
                }
                self.coachMessages.append(
                    CoachChatMessage(
                        id: UUID().uuidString,
                        isUser: false,
                        verdictTitle: result.verdictTitle,
                        text: result.text,
                        bullets: result.bullets,
                        timestampLabel: "Ahora",
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
    }

    func updateGeminiConfig(apiKey: String, model: String) {
        geminiApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        selectedGeminiModel = model
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

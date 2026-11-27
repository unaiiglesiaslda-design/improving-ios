import Foundation
import SwiftUI

enum MainTab: String, CaseIterable, Codable, Identifiable {
    case hoy = "HOY"
    case diario = "DIARIO"
    case fitness = "FITNESS"
    case biologia = "BIOLOGIA"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hoy: return "Inicio"
        case .diario: return "Diario"
        case .fitness: return "Fitness"
        case .biologia: return "Biología"
        }
    }

    var systemIcon: String {
        switch self {
        case .hoy: return "house.fill"
        case .diario: return "book.fill"
        case .fitness: return "figure.run"
        case .biologia: return "heart.fill"
        }
    }
}

enum OverlayRoute: String, Equatable, Hashable, Identifiable {
    case none
    case esfuerzo
    case recuperacion
    case suenoDetail
    case sleepSessionDetail
    case sleepNeedDetail
    case estres
    case energia
    case nutricion
    case nutrientDetail
    case nutritionTrends
    case journalInsights
    case healthMetricDetail
    case trendMetricDetail
    case trainingLoad
    case cardioMetricDetail
    case workoutDetail
    case bodyCompositionDetail
    case weeklyReview
    case allCategories
    case askBevel
    case dispositivos

    var id: String { rawValue }
}

enum HomeSectionKind: String, CaseIterable, Codable, Identifiable, Hashable {
    case heroRings = "Anillos principales"
    case stressEnergy = "Estrés y Energía"
    case healthMonitor = "Monitor de salud"
    case cardioLoad = "Carga cardíaca"
    case nutrition = "Nutrición"
    case weeklyReview = "Resumen semanal"
    case recentActivity = "Actividad reciente"

    var id: String { rawValue }

    var systemIcon: String {
        switch self {
        case .heroRings: return "circle.circle.fill"
        case .stressEnergy: return "bolt.heart.fill"
        case .healthMonitor: return "waveform.path.ecg"
        case .cardioLoad: return "figure.run"
        case .nutrition: return "fork.knife"
        case .weeklyReview: return "calendar.badge.checkmark"
        case .recentActivity: return "flame.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .heroRings: return "Esfuerzo, Recuperación, Sueño y Coaching IA"
        case .stressEnergy: return "Dial de estrés intradía y Batería Corporal"
        case .healthMonitor: return "FR, FCR, VFC, SpO₂, Temperatura y Sueño"
        case .cardioLoad: return "Carga cardiovascular EWMA de los últimos días"
        case .nutrition: return "Alimentos de hoy, puntuación y macros"
        case .weeklyReview: return "Comparativa 7 días + conclusiones de Gemini IA"
        case .recentActivity: return "Último entrenamiento registrado del día"
        }
    }
}

struct HomeLayoutPreferences: Codable, Equatable {
    var sectionOrder: [HomeSectionKind] = HomeSectionKind.allCases
    var hiddenSections: [HomeSectionKind] = []
    var hiddenHealthMetrics: [HealthMetricKind] = []
    var isCompactMode: Bool = false

    enum CodingKeys: String, CodingKey {
        case sectionOrder, hiddenSections, hiddenHealthMetrics, isCompactMode
    }

    init(
        sectionOrder: [HomeSectionKind] = HomeSectionKind.allCases,
        hiddenSections: [HomeSectionKind] = [],
        hiddenHealthMetrics: [HealthMetricKind] = [],
        isCompactMode: Bool = false
    ) {
        self.sectionOrder = sectionOrder
        self.hiddenSections = hiddenSections
        self.hiddenHealthMetrics = hiddenHealthMetrics
        self.isCompactMode = isCompactMode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sectionOrder = try c.decodeIfPresent([HomeSectionKind].self, forKey: .sectionOrder) ?? HomeSectionKind.allCases
        hiddenSections = try c.decodeIfPresent([HomeSectionKind].self, forKey: .hiddenSections) ?? []
        hiddenHealthMetrics = try c.decodeIfPresent([HealthMetricKind].self, forKey: .hiddenHealthMetrics) ?? []
        isCompactMode = try c.decodeIfPresent(Bool.self, forKey: .isCompactMode) ?? false
    }

    var normalizedOrder: [HomeSectionKind] {
        var result = sectionOrder.filter { HomeSectionKind.allCases.contains($0) }
        for kind in HomeSectionKind.allCases where !result.contains(kind) {
            result.append(kind)
        }
        return result
    }

    func isSectionVisible(_ kind: HomeSectionKind) -> Bool {
        !hiddenSections.contains(kind)
    }

    func isHealthMetricVisible(_ kind: HealthMetricKind) -> Bool {
        !hiddenHealthMetrics.contains(kind)
    }
}

enum BodyCompositionMetricKind: String, CaseIterable, Codable, Identifiable {
    case weight = "Peso"
    case bodyFat = "Grasa corporal"
    case leanMass = "Masa magra"
    case bloodPressure = "Presión arterial"

    var id: String { rawValue }

    var unit: String {
        switch self {
        case .weight, .leanMass: return "kg"
        case .bodyFat: return "%"
        case .bloodPressure: return "mmHg"
        }
    }

    var systemIcon: String {
        switch self {
        case .weight: return "scalemass.fill"
        case .bodyFat: return "drop.triangle.fill"
        case .leanMass: return "figure.strengthtraining.traditional"
        case .bloodPressure: return "heart.text.square.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .weight: return BevelColors.skyBlue
        case .bodyFat: return BevelColors.amberStart
        case .leanMass: return BevelColors.bioTeal
        case .bloodPressure: return BevelColors.coralHigh
        }
    }

    var explanation: String {
        switch self {
        case .weight: return "Evolución de tu peso corporal registrado desde Apple Salud o tu báscula manual."
        case .bodyFat: return "Porcentaje estimado de grasa corporal respecto a tu peso total."
        case .leanMass: return "Peso de músculo, hueso y agua corporal (masa libre de grasa)."
        case .bloodPressure: return "Lecturas de tensión sistólica y diastólica en milímetros de mercurio (mmHg)."
        }
    }
}

enum LabBiomarkerStatus: String, Codable, CaseIterable {
    case optimal = "Óptimo"
    case normal = "Normal"
    case low = "Bajo"
    case high = "Alto"

    var color: Color {
        switch self {
        case .optimal: return BevelColors.greenPrimary
        case .normal: return BevelColors.skyBlue
        case .low: return BevelColors.amberStart
        case .high: return BevelColors.coralHigh
        }
    }
}

struct LabBiomarkerItem: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var name: String
    var value: Double
    var unit: String
    var refMin: Double?
    var refMax: Double?
    var optimalMin: Double?
    var optimalMax: Double?
    var status: LabBiomarkerStatus
    var category: String
}

struct LabReportRecord: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var dateIso: String
    var title: String
    var sourceLabel: String
    var summary: String
    var biomarkers: [LabBiomarkerItem]
}

struct WeeklyAiReviewInsight: Codable, Equatable {
    var weekKey: String
    var headline: String
    var takeaways: [String]
    var generatedAtLabel: String
    var modelUsed: String
    var isLiveAI: Bool
}

struct WeeklyReviewReport: Equatable {
    let weekKey: String
    let dateRangeLabel: String
    let daysWithData: Int
    let avgRecovery: Int?
    let recoveryDelta: Int?
    let avgHrv: Double?
    let hrvDelta: Double?
    let avgRhr: Double?
    let rhrDelta: Double?
    let avgSleepMinutes: Int?
    let sleepMinutesDelta: Int?
    let avgSleepPct: Int?
    let sleepDebtMinutes: Int
    let avgStrainPct: Int?
    let strainDelta: Int?
    let workoutsCount: Int
    let totalWorkoutMinutes: Int
    let workoutsDelta: Int
    let cardioLoadCurrent: Int
    let cardioLoadState: TrainingLoadState
    let avgNutritionScore: Int?
    let nutritionScoreDelta: Int?
    let avgNetEnergyKcal: Int?
    let avgSteps: Int?
    let topHabits: [(emoji: String, title: String, count: Int)]

    static func == (lhs: WeeklyReviewReport, rhs: WeeklyReviewReport) -> Bool {
        lhs.weekKey == rhs.weekKey &&
            lhs.daysWithData == rhs.daysWithData &&
            lhs.avgRecovery == rhs.avgRecovery &&
            lhs.avgSleepPct == rhs.avgSleepPct &&
            lhs.avgStrainPct == rhs.avgStrainPct &&
            lhs.workoutsCount == rhs.workoutsCount &&
            lhs.avgNutritionScore == rhs.avgNutritionScore
    }
}

enum NutritionComposerInitialMode: String, Equatable {
    case standard
    case camera
    case photoLibrary
    case barcode
}

enum CoachingSection: String, CaseIterable, Codable, Identifiable {
    case hoy
    case esfuerzo
    case recuperacion
    case sueno
    case estres
    case energia
    case fitness
    case diario

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hoy: return "Resumen del día"
        case .esfuerzo: return "Esfuerzo"
        case .recuperacion: return "Recuperación"
        case .sueno: return "Sueño"
        case .estres: return "Estrés"
        case .energia: return "Energía"
        case .fitness: return "Fitness"
        case .diario: return "Diario"
        }
    }
}

enum CoachPersonalityTone: String, Codable, CaseIterable, Identifiable {
    case directo = "Directo"
    case cientifico = "Científico"
    case empatico = "Empático"
    case entrenador = "Exigente"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .directo: return "bolt.fill"
        case .cientifico: return "atom"
        case .empatico: return "heart.circle.fill"
        case .entrenador: return "flame.fill"
        }
    }

    var shortSubtitle: String {
        switch self {
        case .directo: return "Claro, al grano y accionable"
        case .cientifico: return "Fisiología, mecanismos y evidencia"
        case .empatico: return "Cercano, motivador y sin presión"
        case .entrenador: return "Estilo alto rendimiento, exigente y disciplinado"
        }
    }

    var systemDirective: String {
        switch self {
        case .directo:
            return "Tono directo, claro y práctico: ve al grano desde la primera línea con acciones concretas sin rodeos."
        case .cientifico:
            return "Tono científico y analítico: explica el porqué fisiológico (sistema nervioso autónomo, glucógeno, ritmo circadiano, biomarcadores) con precisión y rigor accesible."
        case .empatico:
            return "Tono cercano, empático y comprensivo: valida el esfuerzo del usuario, reduce fricción mental y propone pasos realistas y sostenibles."
        case .entrenador:
            return "Tono de entrenador de alto rendimiento exigente: reta al usuario con disciplina constructiva, foco en excelencia y cero excusas vacías, respetando siempre su seguridad fisiológica."
        }
    }
}

enum CoachDetailLevel: String, Codable, CaseIterable, Identifiable {
    case breve = "Breve"
    case equilibrado = "Equilibrado"
    case detallado = "Detallado"

    var id: String { rawValue }

    var systemDirective: String {
        switch self {
        case .breve:
            return "Extensión BREVE: máximo 2 a 3 frases directas o 3 viñetas muy cortas. Cero paja."
        case .equilibrado:
            return "Extensión EQUILIBRADA: 1 a 2 párrafos claros y escaneables con cifras clave y recomendación práctica."
        case .detallado:
            return "Extensión DETALLADA: profundiza en el porqué de cada métrica, conecta causas (nutrición, hábitos, sueño, analíticas, clima) y da un plan paso a paso completo."
        }
    }
}

struct ArchivedAiInsight: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let dateIso: String
    let sectionRaw: String
    let sectionTitle: String
    let emoji: String
    let headline: String
    let body: String
    let createdAtEpoch: Double
}

struct DynamicStrainNutritionSnapshot: Equatable {
    let isEnabled: Bool
    let isManualOverrideBlocking: Bool
    let phaseTitle: String
    let phaseIcon: String
    let strain21: Double
    let kcalDelta: Int
    let carbsDeltaG: Int
    let proteinDeltaG: Int
    let extraHydrationMl: Int
    let electrolyteNote: String?
    let summaryText: String
    let isHighLoad: Bool
    let isRestDay: Bool
}

struct SectionCoachingCard: Codable, Equatable {
    let section: CoachingSection
    let emoji: String
    let headline: String
    let body: String
    let slotKey: String
    let generatedAtLabel: String
    let nextUpdateLabel: String
    let isLiveAI: Bool
}

enum HealthMetricKind: String, CaseIterable, Codable, Identifiable {
    case respiratoryRate = "RESP_RATE"
    case restingHeartRate = "RHR"
    case hrv = "HRV"
    case oxygenSaturation = "SPO2"
    case wristTemperature = "WRIST_TEMP"
    case sleepDuration = "SLEEP_DURATION"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .respiratoryRate: return "Frecuencia respiratoria"
        case .restingHeartRate: return "FC en reposo"
        case .hrv: return "VFC en reposo"
        case .oxygenSaturation: return "Saturación de oxígeno"
        case .wristTemperature: return "Temperatura de la muñeca"
        case .sleepDuration: return "Duración del sueño"
        }
    }

    var shortLabel: String {
        switch self {
        case .respiratoryRate: return "FR"
        case .restingHeartRate: return "FCR"
        case .hrv: return "VFC"
        case .oxygenSaturation: return "SpO₂"
        case .wristTemperature: return "Temp."
        case .sleepDuration: return "Sueño"
        }
    }

    var unit: String {
        switch self {
        case .respiratoryRate: return "rpm"
        case .restingHeartRate: return "ppm"
        case .hrv: return "ms"
        case .oxygenSaturation: return "%"
        case .wristTemperature: return "°C"
        case .sleepDuration: return ""
        }
    }
}

enum TrendStatusTone: String, Codable {
    case normal, below, above, noData
}

struct EffortTrendItem: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let valueText: String
    let unitText: String
    let statusText: String
    let statusTone: TrendStatusTone
    let points: [Double?]
    let bandLow: Double
    let bandHigh: Double
    let lineColorHex: UInt64
    let detailNote: String
    var hasData: Bool = true
}

struct EffortEventItem: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var timeRange: String
    var durationMin: Int
    var avgHrBpm: Int // 0 means no HR recorded
    var strainScore: Double
    var strainPct: Int
    var categoryLabel: String
    var kcal: Int
    var distanceKm: Double? = nil
    var elevationM: Double? = nil
    var dateIso: String? = nil
    var startEpochSec: Int64? = nil
    var avgPowerW: Double? = nil
    var avgCadenceRpm: Double? = nil
    var hrZoneMinutes6: [Int]? = nil // [Z0, Z1, Z2, Z3, Z4, Z5]
    var hrRecovery1MinBpm: Double? = nil
    var totalSets: Int? = nil
    var totalVolumeKg: Double? = nil
    var targetMuscles: [String]? = nil
    var rpe: Int? = nil // 1...10 Perceived Exertion (WHOOP Strength Trainer style)

    enum CodingKeys: String, CodingKey {
        case id, title, timeRange, durationMin, avgHrBpm, strainScore, strainPct
        case categoryLabel, kcal, distanceKm, elevationM, dateIso
        case startEpochSec, avgPowerW, avgCadenceRpm, hrZoneMinutes6
        case hrRecovery1MinBpm, totalSets, totalVolumeKg, targetMuscles, rpe
    }

    init(
        id: String,
        title: String,
        timeRange: String,
        durationMin: Int,
        avgHrBpm: Int,
        strainScore: Double,
        strainPct: Int,
        categoryLabel: String,
        kcal: Int,
        distanceKm: Double? = nil,
        elevationM: Double? = nil,
        dateIso: String? = nil,
        startEpochSec: Int64? = nil,
        avgPowerW: Double? = nil,
        avgCadenceRpm: Double? = nil,
        hrZoneMinutes6: [Int]? = nil,
        hrRecovery1MinBpm: Double? = nil,
        totalSets: Int? = nil,
        totalVolumeKg: Double? = nil,
        targetMuscles: [String]? = nil,
        rpe: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.timeRange = timeRange
        self.durationMin = durationMin
        self.avgHrBpm = avgHrBpm
        self.strainScore = strainScore
        self.strainPct = strainPct
        self.categoryLabel = categoryLabel
        self.kcal = kcal
        self.distanceKm = distanceKm
        self.elevationM = elevationM
        self.dateIso = dateIso
        self.startEpochSec = startEpochSec
        self.avgPowerW = avgPowerW
        self.avgCadenceRpm = avgCadenceRpm
        self.hrZoneMinutes6 = hrZoneMinutes6
        self.hrRecovery1MinBpm = hrRecovery1MinBpm
        self.totalSets = totalSets
        self.totalVolumeKg = totalVolumeKg
        self.targetMuscles = targetMuscles
        self.rpe = rpe
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        timeRange = try c.decode(String.self, forKey: .timeRange)
        durationMin = try c.decode(Int.self, forKey: .durationMin)
        avgHrBpm = try c.decodeIfPresent(Int.self, forKey: .avgHrBpm) ?? 0
        strainScore = try c.decodeIfPresent(Double.self, forKey: .strainScore) ?? 0
        strainPct = try c.decodeIfPresent(Int.self, forKey: .strainPct) ?? 0
        categoryLabel = try c.decodeIfPresent(String.self, forKey: .categoryLabel) ?? "Actividad"
        kcal = try c.decodeIfPresent(Int.self, forKey: .kcal) ?? 0
        distanceKm = try c.decodeIfPresent(Double.self, forKey: .distanceKm)
        elevationM = try c.decodeIfPresent(Double.self, forKey: .elevationM)
        dateIso = try c.decodeIfPresent(String.self, forKey: .dateIso)
        startEpochSec = try c.decodeIfPresent(Int64.self, forKey: .startEpochSec)
        avgPowerW = try c.decodeIfPresent(Double.self, forKey: .avgPowerW)
        avgCadenceRpm = try c.decodeIfPresent(Double.self, forKey: .avgCadenceRpm)
        hrZoneMinutes6 = try c.decodeIfPresent([Int].self, forKey: .hrZoneMinutes6)
        hrRecovery1MinBpm = try c.decodeIfPresent(Double.self, forKey: .hrRecovery1MinBpm)
        totalSets = try c.decodeIfPresent(Int.self, forKey: .totalSets)
        totalVolumeKg = try c.decodeIfPresent(Double.self, forKey: .totalVolumeKg)
        targetMuscles = try c.decodeIfPresent([String].self, forKey: .targetMuscles)
        rpe = try c.decodeIfPresent(Int.self, forKey: .rpe)
    }
}

/// Proactive WHOOP-style Health Monitor physiological alert when 2+ overnight vitals deviate negatively simultaneously.
struct HealthMonitorPhysiologicalAlert: Equatable {
    let flaggedVitals: [String]
    let count: Int
    let isCritical: Bool
    let strainReductionPct: Int
    let headline: String
    let advice: String
}

/// WHOOP Healthspan-style Pace of Aging multiplier (0.3x ... 2.5x; <1.0x = aging slower than chronological pace).
struct PaceOfAgingSnapshot: Equatable {
    let multiplier: Double
    let statusLabel: String
    let deltaVsPrior30d: Double?
    let explanation: String
}

/// WHOOP Sleep Coach 3-mode target selector for tonight's sleep plan.
enum SleepCoachMode: Int, CaseIterable, Identifiable {
    case peak = 100
    case perform = 85
    case getBy = 70

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .peak: return "Rendir"
        case .perform: return "Mantener"
        case .getBy: return "Mínimo"
        }
    }

    var badgeText: String { "\(rawValue)%" }

    var subtitle: String {
        switch self {
        case .peak: return "Máxima recuperación y rendimiento mañana"
        case .perform: return "Equilibrio sostenible para tu rutina activa"
        case .getBy: return "Mínimo funcional para días muy ajustados"
        }
    }
}

struct TimedBiometricPoint: Codable, Equatable, Hashable {
    let minuteOfDay: Int // 0...1439
    let value: Double
    var epochSec: Int64? = nil
}

enum SleepStageKind: String, Codable, Hashable {
    case awake, rem, core, deep
}

struct SleepStageBlock: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let stage: SleepStageKind
    let startEpochSec: Int64
    let endEpochSec: Int64

    var durationSec: Int64 { max(endEpochSec - startEpochSec, 0) }
}

struct SleepSessionDetail: Codable, Equatable {
    var startEpochSec: Int64? = nil
    var endEpochSec: Int64? = nil
    var startTimeLabel: String? = nil
    var endTimeLabel: String? = nil
    var startDateTimeLabel: String? = nil
    var sourceName: String? = nil
    var awakeSeconds: Int? = nil
    var remSeconds: Int? = nil
    var coreSeconds: Int? = nil
    var deepSeconds: Int? = nil
    var latencyMinutes: Int? = nil
    var efficiencyPct: Int? = nil
    var hrDipPct: Double? = nil
    var continuityPct: Int? = nil
    var stages: [SleepStageBlock] = []
    var sleepHrSamples: [TimedBiometricPoint] = []
    var sleepHrvSamples: [TimedBiometricPoint] = []
    var sleepRespSamples: [TimedBiometricPoint] = []
    var sleepSpo2Samples: [TimedBiometricPoint] = []
}

enum JournalCheckState: String, Codable {
    case unset, yes, no
}

enum JournalImpactTarget: String, CaseIterable, Identifiable {
    case recovery = "Recuperación"
    case sleep = "Sueño"
    case hrv = "VFC"
    case stress = "Estrés"

    var id: String { rawValue }

    var unitSuffix: String {
        switch self {
        case .recovery, .sleep: return "%"
        case .hrv: return " ms"
        case .stress: return " pts"
        }
    }

    var higherIsBetter: Bool {
        self != .stress
    }
}

enum JournalTrendWindow: Int, CaseIterable, Identifiable {
    case days30 = 30
    case months6 = 180
    case all = 3650

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .days30: return "30 días"
        case .months6: return "6 meses"
        case .all: return "Todo"
        }
    }
}

enum JournalReliabilityTier: String, Codable {
    case high, low, locked
}

struct JournalHabitImpactItem: Identifiable, Equatable {
    let id: String
    let emoji: String
    let title: String
    let impactPct: Int
    let yesCount: Int
    let noCount: Int
    let loggedDaysCount: Int
    let daysSpanCount: Int
    let reliability: JournalReliabilityTier
    let isAutomatic: Bool
    var unitSuffix: String = "%"
    var higherIsBetter: Bool = true

    var daysRemainingFor30d: Int {
        max(30 - max(loggedDaysCount, daysSpanCount), 0)
    }

    var isBeneficialImpact: Bool {
        higherIsBetter ? impactPct >= 0 : impactPct <= 0
    }

    var formattedImpactText: String {
        let sign = impactPct > 0 ? "+" : ""
        return "\(sign)\(impactPct)\(unitSuffix)"
    }
}

enum NutritionTrendTab: String, CaseIterable, Identifiable {
    case score = "Puntuación de nutrición"
    case macroBalance = "Equilibrio macro"
    case netEnergy = "Energía neta"

    var id: String { rawValue }
}

enum FoodQualityFactorKind: String, CaseIterable, Codable, Identifiable {
    case wholeGrains
    case excessSugar
    case excessSodium
    case vegetables
    case healthyFats
    case fruit
    case nutsLegumes
    case omega3
    case redMeat
    case processedMeat
    case alcohol

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .wholeGrains: return "🌾"
        case .excessSugar: return "🍰"
        case .excessSodium: return "🧂"
        case .vegetables: return "🥬"
        case .healthyFats: return "🥑"
        case .fruit: return "🍓"
        case .nutsLegumes: return "🥜"
        case .omega3: return "🐟"
        case .redMeat: return "🥩"
        case .processedMeat: return "🌭"
        case .alcohol: return "🍷"
        }
    }

    var title: String {
        switch self {
        case .wholeGrains: return "Cereales integrales"
        case .excessSugar: return "Exceso de azúcar"
        case .excessSodium: return "Exceso de sodio"
        case .vegetables: return "Verdura"
        case .healthyFats: return "Grasas saludables"
        case .fruit: return "Fruta"
        case .nutsLegumes: return "Frutos secos/legumbres"
        case .omega3: return "Omega-3"
        case .redMeat: return "Carne roja"
        case .processedMeat: return "Carne procesada"
        case .alcohol: return "Alcohol"
        }
    }

    var isPositive: Bool {
        switch self {
        case .wholeGrains, .vegetables, .healthyFats, .fruit, .nutsLegumes, .omega3:
            return true
        case .excessSugar, .excessSodium, .redMeat, .processedMeat, .alcohol:
            return false
        }
    }

    /// Relative safe-threshold marker position along track (0...1) for negative factors matching Bevel UI.
    var safeThresholdFraction: Double? {
        switch self {
        case .excessSugar: return 0.50
        case .excessSodium: return 0.58
        case .redMeat, .processedMeat, .alcohol: return 0.35
        default: return nil
        }
    }

    var maxTrackMagnitude: Double {
        isPositive ? 12.0 : 14.0
    }

    var explanation: String {
        switch self {
        case .wholeGrains: return "Avena, pan 100% integral, quinoa o arroz integral aportan fibra prebiótica y estabilizan la glucosa."
        case .excessSugar: return "Los azúcares añadidos por encima del umbral seguro disparan picos glucémicos y reducen la puntuación nutricional."
        case .excessSodium: return "Un exceso de sodio por encima del umbral seguro eleva la retención hídrica y la carga cardiovascular."
        case .vegetables: return "Verduras y hortalizas aportan micronutrientes, potasio, antioxidantes y saciedad."
        case .healthyFats: return "Aguacate, aceite de oliva virgen extra, nueces y semillas protegen el perfil lipídico y hormonal."
        case .fruit: return "Fruta entera fresca aporta polifenoles, vitamina C y fibra soluble."
        case .nutsLegumes: return "Legumbres y frutos secos suman proteína vegetal, magnesio y fibra fermentable."
        case .omega3: return "Pescado azul (salmón, sardinas, atún), chía o nueces reducen la inflamación y favorecen la VFC."
        case .redMeat: return "Un consumo elevado de carne roja en el día penaliza ligeramente la calidad nutricional global."
        case .processedMeat: return "Embutidos y carnes ultraprocesadas suman sodio, nitritos y grasas saturadas."
        case .alcohol: return "El alcohol deteriora directamente la arquitectura de sueño REM, la VFC nocturna y la recuperación."
        }
    }
}

struct NutritionQualityFactors: Codable, Equatable, Hashable {
    var wholeGrains: Double = 0
    var excessSugar: Double = 0
    var excessSodium: Double = 0
    var vegetables: Double = 0
    var healthyFats: Double = 0
    var fruit: Double = 0
    var nutsLegumes: Double = 0
    var omega3: Double = 0
    var redMeat: Double = 0
    var processedMeat: Double = 0
    var alcohol: Double = 0

    enum CodingKeys: String, CodingKey {
        case wholeGrains, excessSugar, excessSodium, vegetables, healthyFats
        case fruit, nutsLegumes, omega3, redMeat, processedMeat, alcohol
    }

    init(
        wholeGrains: Double = 0,
        excessSugar: Double = 0,
        excessSodium: Double = 0,
        vegetables: Double = 0,
        healthyFats: Double = 0,
        fruit: Double = 0,
        nutsLegumes: Double = 0,
        omega3: Double = 0,
        redMeat: Double = 0,
        processedMeat: Double = 0,
        alcohol: Double = 0
    ) {
        self.wholeGrains = wholeGrains
        self.excessSugar = excessSugar
        self.excessSodium = excessSodium
        self.vegetables = vegetables
        self.healthyFats = healthyFats
        self.fruit = fruit
        self.nutsLegumes = nutsLegumes
        self.omega3 = omega3
        self.redMeat = redMeat
        self.processedMeat = processedMeat
        self.alcohol = alcohol
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        wholeGrains = try c.decodeIfPresent(Double.self, forKey: .wholeGrains) ?? 0
        excessSugar = try c.decodeIfPresent(Double.self, forKey: .excessSugar) ?? 0
        excessSodium = try c.decodeIfPresent(Double.self, forKey: .excessSodium) ?? 0
        vegetables = try c.decodeIfPresent(Double.self, forKey: .vegetables) ?? 0
        healthyFats = try c.decodeIfPresent(Double.self, forKey: .healthyFats) ?? 0
        fruit = try c.decodeIfPresent(Double.self, forKey: .fruit) ?? 0
        nutsLegumes = try c.decodeIfPresent(Double.self, forKey: .nutsLegumes) ?? 0
        omega3 = try c.decodeIfPresent(Double.self, forKey: .omega3) ?? 0
        redMeat = try c.decodeIfPresent(Double.self, forKey: .redMeat) ?? 0
        processedMeat = try c.decodeIfPresent(Double.self, forKey: .processedMeat) ?? 0
        alcohol = try c.decodeIfPresent(Double.self, forKey: .alcohol) ?? 0
    }

    func value(for kind: FoodQualityFactorKind) -> Double {
        switch kind {
        case .wholeGrains: return wholeGrains
        case .excessSugar: return excessSugar
        case .excessSodium: return excessSodium
        case .vegetables: return vegetables
        case .healthyFats: return healthyFats
        case .fruit: return fruit
        case .nutsLegumes: return nutsLegumes
        case .omega3: return omega3
        case .redMeat: return redMeat
        case .processedMeat: return processedMeat
        case .alcohol: return alcohol
        }
    }

    var hasAnyNonZero: Bool {
        FoodQualityFactorKind.allCases.contains { abs(value(for: $0)) > 0.05 }
    }

    static func + (lhs: NutritionQualityFactors, rhs: NutritionQualityFactors) -> NutritionQualityFactors {
        NutritionQualityFactors(
            wholeGrains: lhs.wholeGrains + rhs.wholeGrains,
            excessSugar: lhs.excessSugar + rhs.excessSugar,
            excessSodium: lhs.excessSodium + rhs.excessSodium,
            vegetables: lhs.vegetables + rhs.vegetables,
            healthyFats: lhs.healthyFats + rhs.healthyFats,
            fruit: lhs.fruit + rhs.fruit,
            nutsLegumes: lhs.nutsLegumes + rhs.nutsLegumes,
            omega3: lhs.omega3 + rhs.omega3,
            redMeat: lhs.redMeat + rhs.redMeat,
            processedMeat: lhs.processedMeat + rhs.processedMeat,
            alcohol: lhs.alcohol + rhs.alcohol
        )
    }
}

struct NutritionMealItem: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var timeLabel: String
    var kcal: Int
    var proteinG: Int
    var carbsG: Int
    var fatG: Int
    var qualityScore: Int
    var caffeineMg: Double? = nil
    var alcoholDrinks: Double? = nil
    var calciumMg: Double? = nil
    var fiberG: Double? = nil
    var sugarG: Double? = nil
    var sodiumMg: Double? = nil
    var potassiumMg: Double? = nil
    var magnesiumMg: Double? = nil
    var ironMg: Double? = nil
    var vitaminDMcg: Double? = nil
    var omega3G: Double? = nil
    var aiNotes: String? = nil
    var photoFilename: String? = nil
    var emoji: String? = nil
    var qualityFactors: NutritionQualityFactors? = nil
    var isFavorite: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, title, timeLabel, kcal, proteinG, carbsG, fatG, qualityScore
        case caffeineMg, alcoholDrinks, calciumMg
        case fiberG, sugarG, sodiumMg, potassiumMg, magnesiumMg, ironMg, vitaminDMcg, omega3G
        case aiNotes, photoFilename, emoji, qualityFactors, isFavorite
    }

    init(
        id: String,
        title: String,
        timeLabel: String,
        kcal: Int,
        proteinG: Int,
        carbsG: Int,
        fatG: Int,
        qualityScore: Int,
        caffeineMg: Double? = nil,
        alcoholDrinks: Double? = nil,
        calciumMg: Double? = nil,
        fiberG: Double? = nil,
        sugarG: Double? = nil,
        sodiumMg: Double? = nil,
        potassiumMg: Double? = nil,
        magnesiumMg: Double? = nil,
        ironMg: Double? = nil,
        vitaminDMcg: Double? = nil,
        omega3G: Double? = nil,
        aiNotes: String? = nil,
        photoFilename: String? = nil,
        emoji: String? = nil,
        qualityFactors: NutritionQualityFactors? = nil,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.title = title
        self.timeLabel = timeLabel
        self.kcal = kcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.qualityScore = qualityScore
        self.caffeineMg = caffeineMg
        self.alcoholDrinks = alcoholDrinks
        self.calciumMg = calciumMg
        self.fiberG = fiberG
        self.sugarG = sugarG
        self.sodiumMg = sodiumMg
        self.potassiumMg = potassiumMg
        self.magnesiumMg = magnesiumMg
        self.ironMg = ironMg
        self.vitaminDMcg = vitaminDMcg
        self.omega3G = omega3G
        self.aiNotes = aiNotes
        self.photoFilename = photoFilename
        self.emoji = emoji
        self.qualityFactors = qualityFactors
        self.isFavorite = isFavorite
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        timeLabel = try c.decode(String.self, forKey: .timeLabel)
        kcal = try c.decodeIfPresent(Int.self, forKey: .kcal) ?? 0
        proteinG = try c.decodeIfPresent(Int.self, forKey: .proteinG) ?? 0
        carbsG = try c.decodeIfPresent(Int.self, forKey: .carbsG) ?? 0
        fatG = try c.decodeIfPresent(Int.self, forKey: .fatG) ?? 0
        qualityScore = try c.decodeIfPresent(Int.self, forKey: .qualityScore) ?? 80
        caffeineMg = try c.decodeIfPresent(Double.self, forKey: .caffeineMg)
        alcoholDrinks = try c.decodeIfPresent(Double.self, forKey: .alcoholDrinks)
        calciumMg = try c.decodeIfPresent(Double.self, forKey: .calciumMg)
        fiberG = try c.decodeIfPresent(Double.self, forKey: .fiberG)
        sugarG = try c.decodeIfPresent(Double.self, forKey: .sugarG)
        sodiumMg = try c.decodeIfPresent(Double.self, forKey: .sodiumMg)
        potassiumMg = try c.decodeIfPresent(Double.self, forKey: .potassiumMg)
        magnesiumMg = try c.decodeIfPresent(Double.self, forKey: .magnesiumMg)
        ironMg = try c.decodeIfPresent(Double.self, forKey: .ironMg)
        vitaminDMcg = try c.decodeIfPresent(Double.self, forKey: .vitaminDMcg)
        omega3G = try c.decodeIfPresent(Double.self, forKey: .omega3G)
        aiNotes = try c.decodeIfPresent(String.self, forKey: .aiNotes)
        photoFilename = try c.decodeIfPresent(String.self, forKey: .photoFilename)
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji)
        qualityFactors = try c.decodeIfPresent(NutritionQualityFactors.self, forKey: .qualityFactors)
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
    }

    var effectiveFiberG: Double {
        if let f = fiberG { return f }
        let veg = qualityFactors?.vegetables ?? 0
        let wg = qualityFactors?.wholeGrains ?? 0
        let fr = qualityFactors?.fruit ?? 0
        let base = Double(carbsG) * (qualityScore >= 80 ? 0.14 : 0.07)
        let vegBonus = (veg + wg + fr) * 3.2
        return max(0, (base + vegBonus * 0.5).rounded())
    }

    var effectiveSugarG: Double {
        if let s = sugarG { return s }
        let excess = (qualityFactors?.excessSugar ?? 0) * 14.0
        let fr = (qualityFactors?.fruit ?? 0) * 8.0
        return max(0, (Double(carbsG) * (qualityScore < 65 ? 0.28 : 0.11) + excess + fr * 0.4).rounded())
    }

    var effectiveSodiumMg: Double {
        if let na = sodiumMg { return na }
        let exNa = qualityFactors?.excessSodium ?? 0
        let pm = qualityFactors?.processedMeat ?? 0
        let excess = (exNa + pm) * 420.0
        return max(0, (Double(kcal) * 0.85 + excess).rounded())
    }

    var effectivePotassiumMg: Double {
        if let k = potassiumMg { return k }
        let veg = qualityFactors?.vegetables ?? 0
        let fr = qualityFactors?.fruit ?? 0
        let vegFruit = (veg + fr) * 340.0
        return max(0, (Double(kcal) * 1.15 + vegFruit).rounded())
    }

    var effectiveMagnesiumMg: Double {
        if let mg = magnesiumMg { return mg }
        let wg = qualityFactors?.wholeGrains ?? 0
        let veg = qualityFactors?.vegetables ?? 0
        let hf = qualityFactors?.healthyFats ?? 0
        let whole = (wg + veg + hf) * 42.0
        return max(0, (Double(kcal) * 0.14 + whole).rounded())
    }

    var effectiveIronMg: Double {
        if let fe = ironMg { return fe }
        let veg = qualityFactors?.vegetables ?? 0
        return max(0, (Double(proteinG) * 0.11) + veg * 1.1)
    }

    var effectiveVitaminDMcg: Double {
        if let vd = vitaminDMcg { return vd }
        let low = title.lowercased()
        let rich = (low.contains("salmón") || low.contains("huevo") || low.contains("atún") || low.contains("lácteo") || low.contains("leche")) ? 4.5 : 0.8
        let om3 = qualityFactors?.omega3 ?? 0
        return rich + om3 * 3.2
    }

    var effectiveOmega3G: Double {
        if let o3 = omega3G { return o3 }
        let low = title.lowercased()
        let fishBonus = (low.contains("salmón") || low.contains("sardina") || low.contains("atún") || low.contains("nueces") || low.contains("chía")) ? 1.4 : 0.15
        let om3 = qualityFactors?.omega3 ?? 0
        return fishBonus + om3 * 0.9
    }
}

struct SavedFoodLibraryItem: Identifiable, Codable, Equatable, Hashable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case favorite = "Favoritos"
        case recipe = "Recetas"
        case meal = "Comidas"
        var id: String { rawValue }
    }

    let id: String
    var kind: Kind
    var emoji: String
    var title: String
    var kcal: Int
    var proteinG: Int
    var carbsG: Int
    var fatG: Int
    var qualityScore: Int
    var caffeineMg: Double? = nil
    var alcoholDrinks: Double? = nil
    var calciumMg: Double? = nil
    var qualityFactors: NutritionQualityFactors? = nil
}

struct CustomNutritionGoals: Codable, Equatable, Hashable {
    var caloriesKcal: Int? = nil
    var fatG: Int? = nil
    var carbsG: Int? = nil
    var proteinG: Int? = nil
}

struct AnalyzedMealEstimate: Equatable {
    var title: String
    var emoji: String = "🍽️"
    var kcal: Int
    var proteinG: Int
    var carbsG: Int
    var fatG: Int
    var caffeineMg: Double
    var alcoholDrinks: Double
    var calciumMg: Double
    var qualityScore: Int
    var qualityFactors: NutritionQualityFactors = NutritionQualityFactors()
    var aiSummary: String
    var usedLiveAI: Bool
    var modelUsed: String
}

struct CustomJournalHabit: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var emoji: String
    var title: String
    var isNightHabit: Bool
}

struct SmartNotificationSettings: Codable, Equatable {
    var journalReminderEnabled: Bool = false
    var journalReminderHour: Int = 22
    var journalReminderMinute: Int = 0
    var bedtimeReminderEnabled: Bool = false
    var bedtimeLeadMinutes: Int = 30
    var smartAlarmHour: Int = 7
    var smartAlarmMinute: Int = 30
    var smartAlarmWindowMinutes: Int = 20

    enum CodingKeys: String, CodingKey {
        case journalReminderEnabled, journalReminderHour, journalReminderMinute
        case bedtimeReminderEnabled, bedtimeLeadMinutes
        case smartAlarmHour, smartAlarmMinute, smartAlarmWindowMinutes
    }

    init(
        journalReminderEnabled: Bool = false,
        journalReminderHour: Int = 22,
        journalReminderMinute: Int = 0,
        bedtimeReminderEnabled: Bool = false,
        bedtimeLeadMinutes: Int = 30,
        smartAlarmHour: Int = 7,
        smartAlarmMinute: Int = 30,
        smartAlarmWindowMinutes: Int = 20
    ) {
        self.journalReminderEnabled = journalReminderEnabled
        self.journalReminderHour = journalReminderHour
        self.journalReminderMinute = journalReminderMinute
        self.bedtimeReminderEnabled = bedtimeReminderEnabled
        self.bedtimeLeadMinutes = bedtimeLeadMinutes
        self.smartAlarmHour = smartAlarmHour
        self.smartAlarmMinute = smartAlarmMinute
        self.smartAlarmWindowMinutes = smartAlarmWindowMinutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        journalReminderEnabled = try c.decodeIfPresent(Bool.self, forKey: .journalReminderEnabled) ?? false
        journalReminderHour = try c.decodeIfPresent(Int.self, forKey: .journalReminderHour) ?? 22
        journalReminderMinute = try c.decodeIfPresent(Int.self, forKey: .journalReminderMinute) ?? 0
        bedtimeReminderEnabled = try c.decodeIfPresent(Bool.self, forKey: .bedtimeReminderEnabled) ?? false
        bedtimeLeadMinutes = try c.decodeIfPresent(Int.self, forKey: .bedtimeLeadMinutes) ?? 30
        smartAlarmHour = try c.decodeIfPresent(Int.self, forKey: .smartAlarmHour) ?? 7
        smartAlarmMinute = try c.decodeIfPresent(Int.self, forKey: .smartAlarmMinute) ?? 30
        smartAlarmWindowMinutes = try c.decodeIfPresent(Int.self, forKey: .smartAlarmWindowMinutes) ?? 20
    }
}

enum CoachUndoPayload: Codable, Equatable, Hashable {
    case deleteMeal(mealId: String, dateIso: String)
    case restoreMeal(meal: NutritionMealItem, dateIso: String, removeFromDateIso: String?)
    case restoreNutrientDay(dateIso: String, previousGlasses: Int?, previousManualMap: [String: Double]?)
    case restoreNutritionGoals(goals: CustomNutritionGoals)
    case restoreJournalHabit(dateIso: String, habitId: String, previousState: JournalCheckState?, previousTime: String?)
    case restoreJournalNoteAndMood(dateIso: String, previousNote: String?, previousMood: Int?)
    case deleteCustomHabit(habitId: String)
    case deleteWorkout(workoutId: String, dateIso: String)
    case restoreWorkout(workout: EffortEventItem, dateIso: String)
    case restoreBodyMeasurement(dateIso: String, prevWeight: Double?, prevFat: Double?, prevLean: Double?, prevSys: Int?, prevDia: Int?)
    case deleteRoutine(routineId: String)
}

struct CoachSuggestedMealOption: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let title: String
    let emoji: String
    let description: String
    let kcal: Int
    let proteinG: Int
    let carbsG: Int
    let fatG: Int
    let fiberG: Double
    let qualityScore: Int
    var isLogged: Bool = false
}

struct CoachAppliedAction: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let icon: String
    let badgeColorHex: UInt64
    let title: String
    let detail: String
    var isUndone: Bool = false
    var undoPayload: CoachUndoPayload? = nil
    var launchedRoutineId: String? = nil
    var suggestedMeals: [CoachSuggestedMealOption] = []

    enum CodingKeys: String, CodingKey {
        case id, icon, badgeColorHex, title, detail, isUndone, undoPayload, launchedRoutineId, suggestedMeals
    }

    init(
        id: String,
        icon: String,
        badgeColorHex: UInt64,
        title: String,
        detail: String,
        isUndone: Bool = false,
        undoPayload: CoachUndoPayload? = nil,
        launchedRoutineId: String? = nil,
        suggestedMeals: [CoachSuggestedMealOption] = []
    ) {
        self.id = id
        self.icon = icon
        self.badgeColorHex = badgeColorHex
        self.title = title
        self.detail = detail
        self.isUndone = isUndone
        self.undoPayload = undoPayload
        self.launchedRoutineId = launchedRoutineId
        self.suggestedMeals = suggestedMeals
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        icon = try c.decode(String.self, forKey: .icon)
        badgeColorHex = try c.decode(UInt64.self, forKey: .badgeColorHex)
        title = try c.decode(String.self, forKey: .title)
        detail = try c.decode(String.self, forKey: .detail)
        isUndone = try c.decodeIfPresent(Bool.self, forKey: .isUndone) ?? false
        undoPayload = try c.decodeIfPresent(CoachUndoPayload.self, forKey: .undoPayload)
        launchedRoutineId = try c.decodeIfPresent(String.self, forKey: .launchedRoutineId)
        suggestedMeals = try c.decodeIfPresent([CoachSuggestedMealOption].self, forKey: .suggestedMeals) ?? []
    }
}

struct CoachChatMessage: Identifiable, Codable, Hashable {
    let id: String
    let isUser: Bool
    var verdictTitle: String? = nil
    let text: String
    var bullets: [String] = []
    let timestampLabel: String
    let isSuggestionChip: Bool
    var modelUsed: String? = nil
    var attachedPhotoFilename: String? = nil
    var appliedActions: [CoachAppliedAction] = []

    enum CodingKeys: String, CodingKey {
        case id, isUser, verdictTitle, text, bullets, timestampLabel, isSuggestionChip, modelUsed, attachedPhotoFilename, appliedActions
    }

    init(
        id: String,
        isUser: Bool,
        verdictTitle: String? = nil,
        text: String,
        bullets: [String] = [],
        timestampLabel: String,
        isSuggestionChip: Bool,
        modelUsed: String? = nil,
        attachedPhotoFilename: String? = nil,
        appliedActions: [CoachAppliedAction] = []
    ) {
        self.id = id
        self.isUser = isUser
        self.verdictTitle = verdictTitle
        self.text = text
        self.bullets = bullets
        self.timestampLabel = timestampLabel
        self.isSuggestionChip = isSuggestionChip
        self.modelUsed = modelUsed
        self.attachedPhotoFilename = attachedPhotoFilename
        self.appliedActions = appliedActions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        isUser = try c.decode(Bool.self, forKey: .isUser)
        verdictTitle = try c.decodeIfPresent(String.self, forKey: .verdictTitle)
        text = try c.decode(String.self, forKey: .text)
        bullets = try c.decodeIfPresent([String].self, forKey: .bullets) ?? []
        timestampLabel = try c.decode(String.self, forKey: .timestampLabel)
        isSuggestionChip = try c.decodeIfPresent(Bool.self, forKey: .isSuggestionChip) ?? false
        modelUsed = try c.decodeIfPresent(String.self, forKey: .modelUsed)
        attachedPhotoFilename = try c.decodeIfPresent(String.self, forKey: .attachedPhotoFilename)
        appliedActions = try c.decodeIfPresent([CoachAppliedAction].self, forKey: .appliedActions) ?? []
    }
}

struct CoachChatThread: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var title: String
    var dateIso: String
    var updatedAtLabel: String
    var messages: [CoachChatMessage]
}

struct CoachDynamicSuggestion: Identifiable, Equatable {
    let id: String
    let icon: String
    let title: String
    let subtitle: String
    let prompt: String
}

struct MetricFloatingAiInsight: Equatable {
    let shortPillText: String
    let expandedHeadline: String
    let shortExpandedMessage: String
    let expandedMessage: String
    let structureIndex: Int
    let variationSeed: Int
}

enum BiologicalSexOption: String, CaseIterable, Codable {
    case male = "Hombre"
    case female = "Mujer"
    case nonBinary = "No binario"

    var banisterB: Double {
        switch self {
        case .male: return 1.92
        case .female: return 1.67
        case .nonBinary: return 1.795
        }
    }
}

struct UserPhysiologyProfile: Codable, Equatable {
    var userName: String = ""
    var lastName: String = ""
    var birthDateIso: String? = nil // yyyy-MM-dd
    var ageYears: Double = 24.0
    var sex: BiologicalSexOption = .male
    var weightKg: Double = 70.0
    var heightCm: Double = 176.0
    var bodyFatPct: Double? = nil
    var restingHrCalibrationBpm: Double? = nil
    var hrvCalibrationMs: Double? = nil
    var profilePhotoPath: String? = nil
    var profileSetupVersion: Int = 0
    var onboardingCompleted: Bool = false

    private static let isoBirthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let displayBirthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    init(
        userName: String = "",
        lastName: String = "",
        birthDateIso: String? = nil,
        ageYears: Double = 24.0,
        sex: BiologicalSexOption = .male,
        weightKg: Double = 70.0,
        heightCm: Double = 176.0,
        bodyFatPct: Double? = nil,
        restingHrCalibrationBpm: Double? = nil,
        hrvCalibrationMs: Double? = nil,
        profilePhotoPath: String? = nil,
        profileSetupVersion: Int = 0,
        onboardingCompleted: Bool = false
    ) {
        self.userName = userName
        self.lastName = lastName
        self.birthDateIso = birthDateIso
        self.ageYears = ageYears
        self.sex = sex
        self.weightKg = weightKg
        self.heightCm = heightCm
        self.bodyFatPct = bodyFatPct
        self.restingHrCalibrationBpm = restingHrCalibrationBpm
        self.hrvCalibrationMs = hrvCalibrationMs
        self.profilePhotoPath = profilePhotoPath
        self.profileSetupVersion = profileSetupVersion
        self.onboardingCompleted = onboardingCompleted
    }

    enum CodingKeys: String, CodingKey {
        case userName, lastName, birthDateIso, ageYears, sex, weightKg, heightCm, bodyFatPct
        case restingHrCalibrationBpm, hrvCalibrationMs, profilePhotoPath, profileSetupVersion, onboardingCompleted
    }

    /// Backward-compatible decoder so existing saved snapshots migrate cleanly without losing history.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userName = try c.decodeIfPresent(String.self, forKey: .userName) ?? ""
        lastName = try c.decodeIfPresent(String.self, forKey: .lastName) ?? ""
        birthDateIso = try c.decodeIfPresent(String.self, forKey: .birthDateIso)
        ageYears = try c.decodeIfPresent(Double.self, forKey: .ageYears) ?? 24.0
        sex = try c.decodeIfPresent(BiologicalSexOption.self, forKey: .sex) ?? .male
        weightKg = try c.decodeIfPresent(Double.self, forKey: .weightKg) ?? 70.0
        heightCm = try c.decodeIfPresent(Double.self, forKey: .heightCm) ?? 176.0
        bodyFatPct = try c.decodeIfPresent(Double.self, forKey: .bodyFatPct)
        restingHrCalibrationBpm = try c.decodeIfPresent(Double.self, forKey: .restingHrCalibrationBpm)
        hrvCalibrationMs = try c.decodeIfPresent(Double.self, forKey: .hrvCalibrationMs)
        profilePhotoPath = try c.decodeIfPresent(String.self, forKey: .profilePhotoPath)
        profileSetupVersion = try c.decodeIfPresent(Int.self, forKey: .profileSetupVersion) ?? 0
        onboardingCompleted = try c.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
    }

    /// Dynamically computed chronological age in fractional years from `birthDateIso` (or fallback `ageYears`).
    /// Uses pure thread-safe calendar parsing (zero shared `DateFormatter` data races across `Task.detached`!).
    var effectiveAgeYears: Double {
        guard let iso = birthDateIso, let dt = AppFormatters.parseIsoDay(iso) else {
            return min(max(ageYears, 13.0), 99.0)
        }
        let secs = Date().timeIntervalSince(dt)
        let yrs = secs / (365.2425 * 86_400.0)
        return min(max((yrs * 10.0).rounded() / 10.0, 13.0), 99.0)
    }

    var birthDate: Date {
        if let iso = birthDateIso, let dt = AppFormatters.parseIsoDay(iso) {
            return dt
        }
        let wholeYears = Int(ageYears.rounded())
        return Calendar.current.date(byAdding: .year, value: -max(min(wholeYears, 95), 13), to: Date()) ?? Date()
    }

    mutating func setBirthDate(_ date: Date) {
        let cal = Calendar.current
        let clamped = min(date, cal.date(byAdding: .year, value: -13, to: Date()) ?? date)
        birthDateIso = AppFormatters.isoDayString(from: clamped)
        ageYears = effectiveAgeYears
    }

    var formattedBirthDate: String {
        Self.displayBirthFormatter.string(from: birthDate).replacingOccurrences(of: ".", with: "")
    }

    var fullName: String {
        [userName, lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var displayFirstName: String {
        let first = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return first.isEmpty ? fullName : first
    }

    var initials: String {
        let first = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let f = first.first, let l = last.first {
            return "\(String(f).uppercased())\(String(l).uppercased())"
        }
        let parts = fullName.split(whereSeparator: \.isWhitespace)
        if parts.count >= 2, let a = parts[0].first, let b = parts[1].first {
            return "\(String(a).uppercased())\(String(b).uppercased())"
        }
        if !first.isEmpty {
            return String(first.prefix(2)).uppercased()
        }
        return "IM"
    }
}

struct RealBiometricDaySummary: Codable, Equatable, Identifiable {
    var id: String { dateIso }
    let dateIso: String // yyyy-MM-dd
    var liveHrBpm: Int?
    var restingHrBpm: Double?
    var hrvMs: Double?
    var hrvMethodLabel: String?
    var syncDiagnosticLine: String?
    var respRateRpm: Double?
    var wristTempDeltaC: Double?
    var wristTempAbsoluteC: Double?
    var spo2Percent: Double?
    var asleepMinutes: Int?
    var inBedMinutes: Int?
    var deepMinutes: Int?
    var remMinutes: Int?
    var coreMinutes: Int?
    var awakeMinutes: Int?
    var sleepPct: Int?
    var sleepDebtMinutes: Int?
    var sleepSession: SleepSessionDetail?
    var strain21: Double?
    var strainPct: Int?
    var recoveryPct: Int?
    var stressScore: Int?
    var energyBankPercent: Int?
    var stepsCount: Int?
    var vo2MaxMlKgMin: Double?
    var hrRecoveryBpm: Double?
    var glucoseMgDl: Int?
    var activeKcal: Int?
    var basalKcal: Int? = nil
    var daylightMinutes: Int?
    var sleepNoiseOver50Db: Bool?
    var bodyWeightKg: Double?
    var bodyFatPct: Double?
    var leanMassKg: Double?
    var systolicBp: Int?
    var diastolicBp: Int?
    var hrZoneMinutes: [Int]
    var hrZone0Minutes: Int? = nil
    var distanceKm: Double? = nil
    var elevationM: Double? = nil
    var avgPowerW: Double? = nil
    var avgCadenceRpm: Double? = nil
    var stressSeries24h: [Double]
    var energySeries24h: [Double]
    var stressSamples5m: [TimedBiometricPoint]
    var energySamples5m: [TimedBiometricPoint]
    var strengthMinutes: Int
    var workouts: [EffortEventItem]

    enum CodingKeys: String, CodingKey {
        case dateIso, liveHrBpm, restingHrBpm, hrvMs, hrvMethodLabel, syncDiagnosticLine
        case respRateRpm, wristTempDeltaC, wristTempAbsoluteC, spo2Percent
        case asleepMinutes, inBedMinutes, deepMinutes, remMinutes, coreMinutes, awakeMinutes
        case sleepPct, sleepDebtMinutes, sleepSession
        case strain21, strainPct, recoveryPct, stressScore, energyBankPercent
        case stepsCount, vo2MaxMlKgMin, hrRecoveryBpm, glucoseMgDl, activeKcal
        case daylightMinutes, sleepNoiseOver50Db, bodyWeightKg, bodyFatPct, leanMassKg
        case systolicBp, diastolicBp, hrZoneMinutes, hrZone0Minutes
        case distanceKm, elevationM, avgPowerW, avgCadenceRpm
        case stressSeries24h, energySeries24h, stressSamples5m, energySamples5m
        case strengthMinutes, workouts
    }

    init(
        dateIso: String,
        liveHrBpm: Int? = nil,
        restingHrBpm: Double? = nil,
        hrvMs: Double? = nil,
        hrvMethodLabel: String? = nil,
        syncDiagnosticLine: String? = nil,
        respRateRpm: Double? = nil,
        wristTempDeltaC: Double? = nil,
        wristTempAbsoluteC: Double? = nil,
        spo2Percent: Double? = nil,
        asleepMinutes: Int? = nil,
        inBedMinutes: Int? = nil,
        deepMinutes: Int? = nil,
        remMinutes: Int? = nil,
        coreMinutes: Int? = nil,
        awakeMinutes: Int? = nil,
        sleepPct: Int? = nil,
        sleepDebtMinutes: Int? = nil,
        sleepSession: SleepSessionDetail? = nil,
        strain21: Double? = nil,
        strainPct: Int? = nil,
        recoveryPct: Int? = nil,
        stressScore: Int? = nil,
        energyBankPercent: Int? = nil,
        stepsCount: Int? = nil,
        vo2MaxMlKgMin: Double? = nil,
        hrRecoveryBpm: Double? = nil,
        glucoseMgDl: Int? = nil,
        activeKcal: Int? = nil,
        daylightMinutes: Int? = nil,
        sleepNoiseOver50Db: Bool? = nil,
        bodyWeightKg: Double? = nil,
        bodyFatPct: Double? = nil,
        leanMassKg: Double? = nil,
        systolicBp: Int? = nil,
        diastolicBp: Int? = nil,
        hrZoneMinutes: [Int] = [0, 0, 0, 0, 0],
        hrZone0Minutes: Int? = nil,
        distanceKm: Double? = nil,
        elevationM: Double? = nil,
        avgPowerW: Double? = nil,
        avgCadenceRpm: Double? = nil,
        stressSeries24h: [Double] = [],
        energySeries24h: [Double] = [],
        stressSamples5m: [TimedBiometricPoint] = [],
        energySamples5m: [TimedBiometricPoint] = [],
        strengthMinutes: Int = 0,
        workouts: [EffortEventItem] = []
    ) {
        self.dateIso = dateIso
        self.liveHrBpm = liveHrBpm
        self.restingHrBpm = restingHrBpm
        self.hrvMs = hrvMs
        self.hrvMethodLabel = hrvMethodLabel
        self.syncDiagnosticLine = syncDiagnosticLine
        self.respRateRpm = respRateRpm
        self.wristTempDeltaC = wristTempDeltaC
        self.wristTempAbsoluteC = wristTempAbsoluteC
        self.spo2Percent = spo2Percent
        self.asleepMinutes = asleepMinutes
        self.inBedMinutes = inBedMinutes
        self.deepMinutes = deepMinutes
        self.remMinutes = remMinutes
        self.coreMinutes = coreMinutes
        self.awakeMinutes = awakeMinutes
        self.sleepPct = sleepPct
        self.sleepDebtMinutes = sleepDebtMinutes
        self.sleepSession = sleepSession
        self.strain21 = strain21
        self.strainPct = strainPct
        self.recoveryPct = recoveryPct
        self.stressScore = stressScore
        self.energyBankPercent = energyBankPercent
        self.stepsCount = stepsCount
        self.vo2MaxMlKgMin = vo2MaxMlKgMin
        self.hrRecoveryBpm = hrRecoveryBpm
        self.glucoseMgDl = glucoseMgDl
        self.activeKcal = activeKcal
        self.daylightMinutes = daylightMinutes
        self.sleepNoiseOver50Db = sleepNoiseOver50Db
        self.bodyWeightKg = bodyWeightKg
        self.bodyFatPct = bodyFatPct
        self.leanMassKg = leanMassKg
        self.systolicBp = systolicBp
        self.diastolicBp = diastolicBp
        self.hrZoneMinutes = hrZoneMinutes
        self.hrZone0Minutes = hrZone0Minutes
        self.distanceKm = distanceKm
        self.elevationM = elevationM
        self.avgPowerW = avgPowerW
        self.avgCadenceRpm = avgCadenceRpm
        self.stressSeries24h = stressSeries24h
        self.energySeries24h = energySeries24h
        self.stressSamples5m = stressSamples5m
        self.energySamples5m = energySamples5m
        self.strengthMinutes = strengthMinutes
        self.workouts = workouts
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dateIso = try c.decode(String.self, forKey: .dateIso)
        liveHrBpm = try c.decodeIfPresent(Int.self, forKey: .liveHrBpm)
        restingHrBpm = try c.decodeIfPresent(Double.self, forKey: .restingHrBpm)
        hrvMs = try c.decodeIfPresent(Double.self, forKey: .hrvMs)
        hrvMethodLabel = try c.decodeIfPresent(String.self, forKey: .hrvMethodLabel)
        syncDiagnosticLine = try c.decodeIfPresent(String.self, forKey: .syncDiagnosticLine)
        respRateRpm = try c.decodeIfPresent(Double.self, forKey: .respRateRpm)
        wristTempDeltaC = try c.decodeIfPresent(Double.self, forKey: .wristTempDeltaC)
        wristTempAbsoluteC = try c.decodeIfPresent(Double.self, forKey: .wristTempAbsoluteC)
        spo2Percent = try c.decodeIfPresent(Double.self, forKey: .spo2Percent)
        asleepMinutes = try c.decodeIfPresent(Int.self, forKey: .asleepMinutes)
        inBedMinutes = try c.decodeIfPresent(Int.self, forKey: .inBedMinutes)
        deepMinutes = try c.decodeIfPresent(Int.self, forKey: .deepMinutes)
        remMinutes = try c.decodeIfPresent(Int.self, forKey: .remMinutes)
        coreMinutes = try c.decodeIfPresent(Int.self, forKey: .coreMinutes)
        awakeMinutes = try c.decodeIfPresent(Int.self, forKey: .awakeMinutes)
        sleepPct = try c.decodeIfPresent(Int.self, forKey: .sleepPct)
        sleepDebtMinutes = try c.decodeIfPresent(Int.self, forKey: .sleepDebtMinutes)
        sleepSession = try c.decodeIfPresent(SleepSessionDetail.self, forKey: .sleepSession)
        strain21 = try c.decodeIfPresent(Double.self, forKey: .strain21)
        strainPct = try c.decodeIfPresent(Int.self, forKey: .strainPct)
        recoveryPct = try c.decodeIfPresent(Int.self, forKey: .recoveryPct)
        stressScore = try c.decodeIfPresent(Int.self, forKey: .stressScore)
        energyBankPercent = try c.decodeIfPresent(Int.self, forKey: .energyBankPercent)
        stepsCount = try c.decodeIfPresent(Int.self, forKey: .stepsCount)
        vo2MaxMlKgMin = try c.decodeIfPresent(Double.self, forKey: .vo2MaxMlKgMin)
        hrRecoveryBpm = try c.decodeIfPresent(Double.self, forKey: .hrRecoveryBpm)
        glucoseMgDl = try c.decodeIfPresent(Int.self, forKey: .glucoseMgDl)
        activeKcal = try c.decodeIfPresent(Int.self, forKey: .activeKcal)
        daylightMinutes = try c.decodeIfPresent(Int.self, forKey: .daylightMinutes)
        sleepNoiseOver50Db = try c.decodeIfPresent(Bool.self, forKey: .sleepNoiseOver50Db)
        bodyWeightKg = try c.decodeIfPresent(Double.self, forKey: .bodyWeightKg)
        bodyFatPct = try c.decodeIfPresent(Double.self, forKey: .bodyFatPct)
        leanMassKg = try c.decodeIfPresent(Double.self, forKey: .leanMassKg)
        systolicBp = try c.decodeIfPresent(Int.self, forKey: .systolicBp)
        diastolicBp = try c.decodeIfPresent(Int.self, forKey: .diastolicBp)
        hrZoneMinutes = try c.decodeIfPresent([Int].self, forKey: .hrZoneMinutes) ?? [0, 0, 0, 0, 0]
        hrZone0Minutes = try c.decodeIfPresent(Int.self, forKey: .hrZone0Minutes)
        distanceKm = try c.decodeIfPresent(Double.self, forKey: .distanceKm)
        elevationM = try c.decodeIfPresent(Double.self, forKey: .elevationM)
        avgPowerW = try c.decodeIfPresent(Double.self, forKey: .avgPowerW)
        avgCadenceRpm = try c.decodeIfPresent(Double.self, forKey: .avgCadenceRpm)
        stressSeries24h = try c.decodeIfPresent([Double].self, forKey: .stressSeries24h) ?? []
        energySeries24h = try c.decodeIfPresent([Double].self, forKey: .energySeries24h) ?? []
        stressSamples5m = try c.decodeIfPresent([TimedBiometricPoint].self, forKey: .stressSamples5m) ?? []
        energySamples5m = try c.decodeIfPresent([TimedBiometricPoint].self, forKey: .energySamples5m) ?? []
        strengthMinutes = try c.decodeIfPresent(Int.self, forKey: .strengthMinutes) ?? 0
        workouts = try c.decodeIfPresent([EffortEventItem].self, forKey: .workouts) ?? []
    }
}

struct ExportImportStatus: Equatable {
    var isImporting: Bool = false
    var importedDaysCount: Int = 0
    var importedWorkoutsCount: Int = 0
    var dateRangeLabel: String = ""
    var summaryMessage: String? = nil
    var errorMessage: String? = nil
}

struct DataAvailabilitySnapshot: Equatable {
    var hasRecoveryData: Bool = false
    var hasStrainData: Bool = false
    var hasSleepData: Bool = false
    var hasHrvData: Bool = false
    var hasRestingHrData: Bool = false
    var hasRespData: Bool = false
    var hasSpo2Data: Bool = false
    var hasTempData: Bool = false
    var hasStressData: Bool = false
    var hasEnergyData: Bool = false
    var hasWorkoutData: Bool = false

    var hasAnyRecordedData: Bool {
        hasRecoveryData || hasStrainData || hasSleepData || hasHrvData ||
            hasRestingHrData || hasRespData || hasSpo2Data || hasTempData ||
            hasStressData || hasEnergyData || hasWorkoutData
    }

    var missingCategoryNames: [String] {
        var list: [String] = []
        if !hasRecoveryData { list.append("Recuperación") }
        if !hasStrainData { list.append("Esfuerzo") }
        if !hasSleepData { list.append("Sueño") }
        if !hasHrvData { list.append("VFC") }
        if !hasRestingHrData { list.append("FC en reposo") }
        if !hasRespData { list.append("Frecuencia respiratoria") }
        if !hasSpo2Data { list.append("SpO₂") }
        if !hasTempData { list.append("Temperatura muñeca") }
        if !hasStressData { list.append("Estrés") }
        if !hasEnergyData { list.append("Reservas de energía") }
        return list
    }
}

enum CardioMetricRoute: String, CaseIterable, Identifiable {
    case activitiesDuration = "Duración de actividades"
    case activitiesEnergy = "Energía en actividades"
    case vo2Max = "VO₂ máx."
    case hrRecovery = "Recuperación de frecuencia cardíaca"
    case cardioFocus = "Foco cardiovascular"
    case hrZones = "Zonas de frecuencia cardíaca"
    case strengthSets = "Total series"
    case strengthVolume = "Volumen total"
    case muscleGroups = "Grupos musculares"

    var id: String { rawValue }
}

enum TrainingLoadTab: String, CaseIterable, Identifiable {
    case cardio = "Cardiovascular"
    case muscular = "Muscular"

    var id: String { rawValue }
}

// MARK: - Fitness Training Load, Anatomical Muscle Freshness & Routines Models

enum TrainingLoadState: String, CaseIterable, Codable, Identifiable {
    case calibrating = "Calibrando"
    case detraining = "Desentrenamiento"
    case peaking = "Pico de forma"
    case maintaining = "Manteniéndose"
    case productive = "Productivo"
    case fatigued = "Fatigado"
    case overtraining = "Entrenamiento excesivo"

    var id: String { rawValue }

    static var cardioOrder: [TrainingLoadState] {
        [.calibrating, .detraining, .peaking, .maintaining, .productive, .fatigued, .overtraining]
    }

    static var muscularOrder: [TrainingLoadState] {
        [.calibrating, .detraining, .peaking, .maintaining, .productive, .overtraining]
    }

    var accentColor: Color {
        switch self {
        case .calibrating: return BevelColors.textSecondary
        case .detraining: return BevelColors.skyBlue
        case .peaking: return BevelColors.bioTeal
        case .maintaining: return BevelColors.greenPrimary
        case .productive: return BevelColors.emeraldEnd
        case .fatigued: return BevelColors.amberStart
        case .overtraining: return BevelColors.coralHigh
        }
    }
}

struct TrainingLoadDayPoint: Identifiable, Equatable {
    var id: String { dateIso }
    let dateIso: String
    let shortDateLabel: String
    let load: Double
    let optLow: Double
    let optHigh: Double
    let state: TrainingLoadState
}

struct TrainingLoadBreakdownRow: Identifiable, Equatable {
    var id: String { state.rawValue }
    let state: TrainingLoadState
    let days: Int
    let percent: Int
}

struct TrainingLoadAnalysis: Equatable {
    let tab: TrainingLoadTab
    let currentLoad: Int
    let currentState: TrainingLoadState
    let optimalLow: Int
    let optimalHigh: Int
    let gaugeMax: Int
    let points: [TrainingLoadDayPoint]
    let breakdown: [TrainingLoadBreakdownRow]
    let hasAnyData: Bool
}

struct StandardizedBandEvaluation: Equatable {
    let labels: [String]
    let activeSegmentIndex: Int
    let categoryTitle: String
    let pointerFraction: Double
    let cohortSubtitle: String
    let activeColor: Color
}

struct MetricTrendPeriodRow: Identifiable, Equatable {
    let id: Int // periodDays: 3, 7, 14, 30, 90
    let periodDays: Int
    let delta: Double?
    let sparklinePoints: [Double]

    var label: String { "\(periodDays) día(s)" }
}

enum MuscleGroupKind: String, CaseIterable, Codable, Identifiable {
    case abdominales = "Abdominales"
    case pantorrillas = "Pantorrillas"
    case flexoresCadera = "Flexores de cadera"
    case gluteos = "Glúteos"
    case cuadriceps = "Cuádriceps"
    case isquiotibiales = "Isquiotibiales"
    case hombros = "Hombros"
    case triceps = "Tríceps"
    case pectorales = "Pectorales"
    case dorsales = "Dorsales"
    case abductores = "Abductores"
    case aductores = "Aductores"
    case antebrazo = "Antebrazo"
    case biceps = "Bíceps"
    case cuello = "Cuello"
    case lumbares = "Lumbares"
    case manguitoRotador = "Manguito rotador"
    case oblicuos = "Oblicuos"
    case espaldaAlta = "Parte superior de la espalda"
    case trapecio = "Trapecio"

    var id: String { rawValue }

    var isFrontDominant: Bool {
        switch self {
        case .pectorales, .hombros, .biceps, .antebrazo, .abdominales, .oblicuos,
             .flexoresCadera, .cuadriceps, .aductores, .abductores, .cuello:
            return true
        case .trapecio, .espaldaAlta, .manguitoRotador, .dorsales, .triceps,
             .lumbares, .gluteos, .isquiotibiales, .pantorrillas:
            return false
        }
    }
}

enum MuscleFreshnessState: String, CaseIterable, Codable, Identifiable {
    case recovered = "Recuperado"
    case fatigued = "Fatigado"
    case exhausted = "Agotado"
    case calibrating = "Calibrando"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .recovered: return BevelColors.greenPrimary
        case .fatigued: return BevelColors.amberStart
        case .exhausted: return BevelColors.coralHigh
        case .calibrating: return BevelColors.textMuted
        }
    }
}

struct MuscleGroupSnapshot: Identifiable, Equatable {
    var id: String { muscle.rawValue }
    let muscle: MuscleGroupKind
    let freshnessPct: Int
    let state: MuscleFreshnessState
    let recentSets: Int
    let recentVolumeKg: Double
    let loadScore: Int

    var filledBars: Int {
        if state == .calibrating { return 5 }
        return min(max(Int((Double(freshnessPct) / 20.0).rounded()), 1), 5)
    }
}

struct WorkoutRoutineExercise: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var name: String
    var targetSets: Int
    var targetReps: Int
    var defaultWeightKg: Double
    var primaryMuscles: [MuscleGroupKind]
    var secondaryMuscles: [MuscleGroupKind]
}

struct WorkoutRoutineTemplate: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var name: String
    var category: String // "Fuerza", "Cardio", "Movilidad"
    var iconName: String
    var isPinned: Bool
    var exercises: [WorkoutRoutineExercise]
}

struct DeepLinkRequest: Equatable {
    enum Destination: String, Equatable {
        case hoy
        case diario
        case fitness
        case biologia
        case nutricion
        case sueno
        case esfuerzo
        case dispositivos
        case askBevel
    }
    let id: UUID = UUID()
    let destination: Destination
}

enum StrengthSetKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case effective = "Efectiva"
    case warmup = "Calentamiento"
    case dropSet = "Drop set"
    case superset = "Superserie"

    var id: String { rawValue }

    var shortBadge: String {
        switch self {
        case .effective: return "EF"
        case .warmup: return "CAL"
        case .dropSet: return "DROP"
        case .superset: return "SS"
        }
    }
}

struct StrengthLoggedSet: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let dateIso: String
    var exercise: String
    var reps: Int
    var weightKg: Double
    var primaryMuscles: [MuscleGroupKind]
    var secondaryMuscles: [MuscleGroupKind]
    var completed: Bool
    var setKind: StrengthSetKind = .effective
    var rpe: Int? = nil
    var rir: Int? = nil

    enum CodingKeys: String, CodingKey {
        case id, dateIso, exercise, reps, weightKg, primaryMuscles, secondaryMuscles, completed
        case setKind, rpe, rir
    }

    init(
        id: String,
        dateIso: String,
        exercise: String,
        reps: Int,
        weightKg: Double,
        primaryMuscles: [MuscleGroupKind],
        secondaryMuscles: [MuscleGroupKind],
        completed: Bool,
        setKind: StrengthSetKind = .effective,
        rpe: Int? = nil,
        rir: Int? = nil
    ) {
        self.id = id
        self.dateIso = dateIso
        self.exercise = exercise
        self.reps = reps
        self.weightKg = weightKg
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.completed = completed
        self.setKind = setKind
        self.rpe = rpe
        self.rir = rir
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        dateIso = try c.decode(String.self, forKey: .dateIso)
        exercise = try c.decode(String.self, forKey: .exercise)
        reps = try c.decodeIfPresent(Int.self, forKey: .reps) ?? 10
        weightKg = try c.decodeIfPresent(Double.self, forKey: .weightKg) ?? 0
        primaryMuscles = try c.decodeIfPresent([MuscleGroupKind].self, forKey: .primaryMuscles) ?? [.pectorales]
        secondaryMuscles = try c.decodeIfPresent([MuscleGroupKind].self, forKey: .secondaryMuscles) ?? []
        completed = try c.decodeIfPresent(Bool.self, forKey: .completed) ?? true
        setKind = try c.decodeIfPresent(StrengthSetKind.self, forKey: .setKind) ?? .effective
        rpe = try c.decodeIfPresent(Int.self, forKey: .rpe)
        rir = try c.decodeIfPresent(Int.self, forKey: .rir)
    }

    /// Epley 1-Rep Max estimation (`weight * (1 + reps / 30)`).
    var estimatedOneRepMaxKg: Double {
        guard weightKg > 0, reps > 0 else { return 0 }
        if reps == 1 { return weightKg }
        return weightKg * (1.0 + Double(min(reps, 20)) / 30.0)
    }
}

struct StrengthCatalogExercise: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let category: String // "Empuje", "Tirón", "Pierna", "Core y Accesorios"
    let equipment: String // "Barra", "Mancuernas", "Máquina / Polea", "Peso corporal"
    let primaryMuscles: [MuscleGroupKind]
    let secondaryMuscles: [MuscleGroupKind]
    let defaultWeightKg: Double
    let defaultReps: Int

    static let all: [StrengthCatalogExercise] = [
        // Empuje (Pecho, Hombros, Tríceps)
        StrengthCatalogExercise(id: "press_banca_barra", name: "Press banca con barra", category: "Empuje", equipment: "Barra", primaryMuscles: [.pectorales], secondaryMuscles: [.triceps, .hombros], defaultWeightKg: 60, defaultReps: 8),
        StrengthCatalogExercise(id: "press_inclinado_manc", name: "Press inclinado con mancuernas", category: "Empuje", equipment: "Mancuernas", primaryMuscles: [.pectorales, .hombros], secondaryMuscles: [.triceps], defaultWeightKg: 24, defaultReps: 10),
        StrengthCatalogExercise(id: "fondos_paralelas", name: "Fondos en paralelas", category: "Empuje", equipment: "Peso corporal", primaryMuscles: [.pectorales, .triceps], secondaryMuscles: [.hombros], defaultWeightKg: 10, defaultReps: 10),
        StrengthCatalogExercise(id: "aperturas_polea", name: "Cruces en polea", category: "Empuje", equipment: "Máquina / Polea", primaryMuscles: [.pectorales], secondaryMuscles: [.hombros], defaultWeightKg: 20, defaultReps: 12),
        StrengthCatalogExercise(id: "press_militar_barra", name: "Press militar de pie", category: "Empuje", equipment: "Barra", primaryMuscles: [.hombros], secondaryMuscles: [.triceps, .trapecio, .abdominales], defaultWeightKg: 40, defaultReps: 8),
        StrengthCatalogExercise(id: "press_hombro_manc", name: "Press de hombros con mancuernas", category: "Empuje", equipment: "Mancuernas", primaryMuscles: [.hombros], secondaryMuscles: [.triceps], defaultWeightKg: 18, defaultReps: 10),
        StrengthCatalogExercise(id: "elevaciones_laterales", name: "Elevaciones laterales", category: "Empuje", equipment: "Mancuernas", primaryMuscles: [.hombros], secondaryMuscles: [.trapecio], defaultWeightKg: 10, defaultReps: 15),
        StrengthCatalogExercise(id: "extension_triceps_polea", name: "Extensión de tríceps en polea", category: "Empuje", equipment: "Máquina / Polea", primaryMuscles: [.triceps], secondaryMuscles: [.antebrazo], defaultWeightKg: 25, defaultReps: 12),
        StrengthCatalogExercise(id: "press_frances", name: "Press francés (rompecráneos)", category: "Empuje", equipment: "Barra", primaryMuscles: [.triceps], secondaryMuscles: [.antebrazo], defaultWeightKg: 28, defaultReps: 10),
        StrengthCatalogExercise(id: "flexiones", name: "Flexiones de pecho", category: "Empuje", equipment: "Peso corporal", primaryMuscles: [.pectorales], secondaryMuscles: [.triceps, .hombros, .abdominales], defaultWeightKg: 0, defaultReps: 15),

        // Tirón (Espalda, Bíceps, Trapecio, Manguito)
        StrengthCatalogExercise(id: "dominadas", name: "Dominadas", category: "Tirón", equipment: "Peso corporal", primaryMuscles: [.dorsales, .espaldaAlta], secondaryMuscles: [.biceps, .antebrazo], defaultWeightKg: 0, defaultReps: 8),
        StrengthCatalogExercise(id: "jalon_pecho", name: "Jalón al pecho en polea", category: "Tirón", equipment: "Máquina / Polea", primaryMuscles: [.dorsales], secondaryMuscles: [.biceps, .espaldaAlta], defaultWeightKg: 55, defaultReps: 10),
        StrengthCatalogExercise(id: "remo_barra", name: "Remo con barra Pendlay", category: "Tirón", equipment: "Barra", primaryMuscles: [.espaldaAlta, .dorsales], secondaryMuscles: [.lumbares, .biceps, .trapecio], defaultWeightKg: 60, defaultReps: 8),
        StrengthCatalogExercise(id: "remo_mancuerna", name: "Remo con mancuerna a una mano", category: "Tirón", equipment: "Mancuernas", primaryMuscles: [.dorsales, .espaldaAlta], secondaryMuscles: [.biceps, .antebrazo], defaultWeightKg: 28, defaultReps: 10),
        StrengthCatalogExercise(id: "remo_gironda", name: "Remo sentado en polea baja", category: "Tirón", equipment: "Máquina / Polea", primaryMuscles: [.espaldaAlta, .dorsales], secondaryMuscles: [.biceps, .trapecio], defaultWeightKg: 50, defaultReps: 12),
        StrengthCatalogExercise(id: "face_pull", name: "Face Pull en polea alta", category: "Tirón", equipment: "Máquina / Polea", primaryMuscles: [.manguitoRotador, .espaldaAlta], secondaryMuscles: [.trapecio, .hombros], defaultWeightKg: 22, defaultReps: 15),
        StrengthCatalogExercise(id: "encogimientos_trapecio", name: "Encogimientos de trapecio", category: "Tirón", equipment: "Mancuernas", primaryMuscles: [.trapecio], secondaryMuscles: [.antebrazo], defaultWeightKg: 30, defaultReps: 12),
        StrengthCatalogExercise(id: "curl_biceps_barra", name: "Curl de bíceps con barra Z", category: "Tirón", equipment: "Barra", primaryMuscles: [.biceps], secondaryMuscles: [.antebrazo], defaultWeightKg: 30, defaultReps: 10),
        StrengthCatalogExercise(id: "curl_martillo", name: "Curl martillo con mancuernas", category: "Tirón", equipment: "Mancuernas", primaryMuscles: [.biceps, .antebrazo], secondaryMuscles: [], defaultWeightKg: 14, defaultReps: 12),

        // Pierna (Cuádriceps, Isquiotibiales, Glúteos, Pantorrillas, Lumbares)
        StrengthCatalogExercise(id: "sentadilla_barra", name: "Sentadilla trasera con barra", category: "Pierna", equipment: "Barra", primaryMuscles: [.cuadriceps, .gluteos], secondaryMuscles: [.lumbares, .isquiotibiales, .abdominales], defaultWeightKg: 85, defaultReps: 8),
        StrengthCatalogExercise(id: "prensa_piernas", name: "Prensa de piernas 45°", category: "Pierna", equipment: "Máquina / Polea", primaryMuscles: [.cuadriceps, .gluteos], secondaryMuscles: [.isquiotibiales], defaultWeightKg: 140, defaultReps: 10),
        StrengthCatalogExercise(id: "sentadilla_bulgara", name: "Sentadilla búlgara con mancuernas", category: "Pierna", equipment: "Mancuernas", primaryMuscles: [.cuadriceps, .gluteos], secondaryMuscles: [.isquiotibiales, .flexoresCadera], defaultWeightKg: 18, defaultReps: 10),
        StrengthCatalogExercise(id: "peso_muerto_rumano", name: "Peso muerto rumano (RDL)", category: "Pierna", equipment: "Barra", primaryMuscles: [.isquiotibiales, .gluteos], secondaryMuscles: [.lumbares, .antebrazo, .trapecio], defaultWeightKg: 80, defaultReps: 8),
        StrengthCatalogExercise(id: "peso_muerto_conv", name: "Peso muerto convencional", category: "Pierna", equipment: "Barra", primaryMuscles: [.gluteos, .isquiotibiales, .lumbares], secondaryMuscles: [.trapecio, .espaldaAlta, .antebrazo], defaultWeightKg: 100, defaultReps: 5),
        StrengthCatalogExercise(id: "hip_thrust", name: "Hip Thrust con barra", category: "Pierna", equipment: "Barra", primaryMuscles: [.gluteos], secondaryMuscles: [.isquiotibiales, .lumbares], defaultWeightKg: 90, defaultReps: 10),
        StrengthCatalogExercise(id: "extension_cuadriceps", name: "Extensión de cuádriceps en máquina", category: "Pierna", equipment: "Máquina / Polea", primaryMuscles: [.cuadriceps], secondaryMuscles: [], defaultWeightKg: 50, defaultReps: 12),
        StrengthCatalogExercise(id: "curl_femoral", name: "Curl femoral tumbado/sentado", category: "Pierna", equipment: "Máquina / Polea", primaryMuscles: [.isquiotibiales], secondaryMuscles: [.pantorrillas], defaultWeightKg: 45, defaultReps: 12),
        StrengthCatalogExercise(id: "elevacion_talones", name: "Elevación de gemelos de pie", category: "Pierna", equipment: "Máquina / Polea", primaryMuscles: [.pantorrillas], secondaryMuscles: [], defaultWeightKg: 60, defaultReps: 15),

        // Core y Accesorios
        StrengthCatalogExercise(id: "plancha_abdominal", name: "Plancha abdominal isométrica", category: "Core y Accesorios", equipment: "Peso corporal", primaryMuscles: [.abdominales, .oblicuos], secondaryMuscles: [.lumbares, .hombros], defaultWeightKg: 0, defaultReps: 45),
        StrengthCatalogExercise(id: "elevacion_piernas", name: "Elevación de piernas colgado", category: "Core y Accesorios", equipment: "Peso corporal", primaryMuscles: [.abdominales, .flexoresCadera], secondaryMuscles: [.antebrazo, .oblicuos], defaultWeightKg: 0, defaultReps: 12),
        StrengthCatalogExercise(id: "crunch_polea", name: "Crunch abdominal en polea alta", category: "Core y Accesorios", equipment: "Máquina / Polea", primaryMuscles: [.abdominales], secondaryMuscles: [.oblicuos], defaultWeightKg: 35, defaultReps: 15),
        StrengthCatalogExercise(id: "paseo_granjero", name: "Paseo del granjero (Farmer's Walk)", category: "Core y Accesorios", equipment: "Mancuernas", primaryMuscles: [.antebrazo, .trapecio], secondaryMuscles: [.abdominales, .oblicuos, .pantorrillas], defaultWeightKg: 28, defaultReps: 30)
    ]
}

struct ExercisePerformanceSnapshot: Equatable {
    let exerciseName: String
    let lastDateIso: String?
    let lastWeightKg: Double?
    let lastReps: Int?
    let bestWeightKg: Double
    let bestOneRepMaxKg: Double
    let totalHistoricalSets: Int
    let suggestedWeightKg: Double
    let suggestedReps: Int
    let progressionBadge: String
    let progressionAdvice: String
}

// MARK: - Quantified Journal & Caffeine / Meal Timing Models (Apartado 1.2)

struct JournalHabitDosageSpec: Equatable {
    let habitId: String
    let unit: String
    let step: Double
    let minVal: Double
    let maxVal: Double
    let defaultYesValue: Double
    let highThreshold: Double
    let presets: [Double]

    static func spec(for habitId: String) -> JournalHabitDosageSpec? {
        switch habitId {
        case "caffeine":
            return JournalHabitDosageSpec(habitId: "caffeine", unit: "mg", step: 40, minVal: 40, maxVal: 600, defaultYesValue: 120, highThreshold: 200, presets: [80, 160, 240, 320])
        case "alcohol":
            return JournalHabitDosageSpec(habitId: "alcohol", unit: "copas", step: 1, minVal: 1, maxVal: 10, defaultYesValue: 1, highThreshold: 2, presets: [1, 2, 3, 4])
        case "hydration":
            return JournalHabitDosageSpec(habitId: "hydration", unit: "L", step: 0.5, minVal: 0.5, maxVal: 6.0, defaultYesValue: 2.5, highThreshold: 2.5, presets: [1.5, 2.0, 2.5, 3.0])
        case "late_meal":
            return JournalHabitDosageSpec(habitId: "late_meal", unit: "h antes", step: 0.5, minVal: 0.5, maxVal: 5.0, defaultYesValue: 1.5, highThreshold: 2.5, presets: [1.0, 1.5, 2.0, 3.0])
        case "screens":
            return JournalHabitDosageSpec(habitId: "screens", unit: "min", step: 15, minVal: 15, maxVal: 180, defaultYesValue: 45, highThreshold: 60, presets: [15, 30, 60, 90])
        case "sauna", "cold_shower", "meditation", "stretching", "reading":
            return JournalHabitDosageSpec(habitId: habitId, unit: "min", step: 5, minVal: 5, maxVal: 90, defaultYesValue: 15, highThreshold: 20, presets: [10, 15, 20, 30])
        default:
            return nil
        }
    }

    func formatValue(_ v: Double) -> String {
        if step < 1.0 {
            return String(format: "%.1f %@", locale: Locale(identifier: "es_ES"), v, unit)
        }
        return "\(Int(v.rounded())) \(unit)"
    }
}

struct CaffeineAndMealTimingSnapshot: Equatable {
    let totalCaffeineTodayMg: Double
    let lastCaffeineTimeLabel: String?
    let estimatedCaffeineAtBedtimeMg: Double
    let caffeineClearForSleep: Bool
    let firstMealTimeLabel: String?
    let lastMealTimeLabel: String?
    let eatingWindowHours: Double?
    let fastingHours: Double?
    let hoursFromLastMealToBedtime: Double?
    let statusSummary: String
}

// MARK: - Global Goal Modes, Coach Memory & Morning Briefing (Apartado 1.4 & 2.3)

enum GlobalGoalMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case rendimiento = "Rendimiento"
    case longevidad = "Longevidad"
    case definicion = "Definición"
    case volumen = "Volumen"
    case recuperacion = "Recuperación"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .rendimiento: return "bolt.heart.fill"
        case .longevidad: return "hourglass.badge.plus"
        case .definicion: return "flame.fill"
        case .volumen: return "figure.strengthtraining.traditional"
        case .recuperacion: return "leaf.fill"
        }
    }

    var emoji: String {
        switch self {
        case .rendimiento: return "⚡"
        case .longevidad: return "⏳"
        case .definicion: return "🔥"
        case .volumen: return "💪"
        case .recuperacion: return "🌿"
        }
    }

    var shortSubtitle: String {
        switch self {
        case .rendimiento: return "Máxima potencia aeróbica y fuerza; carbohidratos peri-entreno"
        case .longevidad: return "Optimiza VO₂ máx., Zona 2, fibra, sueño y ritmo de envejecimiento"
        case .definicion: return "Déficit calórico controlado (−15%) con alta proteína (2,2 g/kg)"
        case .volumen: return "Superávit limpio (+12%) y sobrecarga progresiva hipertrofia"
        case .recuperacion: return "Prioriza reparación autónoma, sueño al 100% y baja inflamación"
        }
    }

    var kcalMultiplier: Double {
        switch self {
        case .rendimiento: return 1.04
        case .longevidad: return 0.98
        case .definicion: return 0.85
        case .volumen: return 1.12
        case .recuperacion: return 1.00
        }
    }

    var proteinGramsPerKg: Double {
        switch self {
        case .rendimiento: return 1.9
        case .longevidad: return 1.8
        case .definicion: return 2.2
        case .volumen: return 2.0
        case .recuperacion: return 1.8
        }
    }

    var strainAdjustmentDelta: Double {
        switch self {
        case .rendimiento: return 0.05
        case .longevidad: return 0.0
        case .definicion: return -0.02
        case .volumen: return 0.03
        case .recuperacion: return -0.12
        }
    }

    var recommendedSleepMode: SleepCoachMode {
        switch self {
        case .rendimiento, .recuperacion: return .peak
        case .longevidad, .volumen, .definicion: return .perform
        }
    }

    var coachSystemDirective: String {
        switch self {
        case .rendimiento:
            return "MODO ACTIVO: RENDIMIENTO. Prioriza periodización de intensidad, recarga de glucógeno y máxima potencia en días verdes."
        case .longevidad:
            return "MODO ACTIVO: LONGEVIDAD. Prioriza ≥150 min/sem en Zona 2, VO2 máx., consistencia del sueño, fibra ≥30g y reducir el Ritmo de Envejecimiento."
        case .definicion:
            return "MODO ACTIVO: DEFINICIÓN. Prioriza saciedad, déficit del 15%, proteína a 2.2 g/kg y preservar fuerza muscular sin sobreentrenar."
        case .volumen:
            return "MODO ACTIVO: VOLUMEN MUSCULAR. Prioriza superávit limpio (+12%), progresión de cargas en Strength Builder y sueño profundo reparador."
        case .recuperacion:
            return "MODO ACTIVO: RECUPERACIÓN. Prioriza bajar estrés simpático, sueño al 100%, hidratación, movilidad y evitar picos de esfuerzo."
        }
    }
}

struct MorningBriefingSnapshot: Equatable {
    let greetingTitle: String
    let recoveryBadge: String
    let sleepSummary: String
    let effortPlanText: String
    let nutritionPlanText: String
    let vitalAlertText: String?
    let deloadAlertText: String?
    let goalMode: GlobalGoalMode
}

// MARK: - Multi-Ingredient Recipes & Quantified Micronutrients (Apartado 1.5)

struct NutritionRecipeIngredient: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var name: String
    var grams: Int
    var kcal: Int
    var proteinG: Int
    var carbsG: Int
    var fatG: Int
    var fiberG: Double = 0
}

struct NutritionRecipeTemplate: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var title: String
    var emoji: String
    var servings: Int
    var ingredients: [NutritionRecipeIngredient]

    var safeServings: Int { max(servings, 1) }
    var kcalPerServing: Int { ingredients.reduce(0) { $0 + $1.kcal } / safeServings }
    var proteinPerServing: Int { ingredients.reduce(0) { $0 + $1.proteinG } / safeServings }
    var carbsPerServing: Int { ingredients.reduce(0) { $0 + $1.carbsG } / safeServings }
    var fatPerServing: Int { ingredients.reduce(0) { $0 + $1.fatG } / safeServings }
    var fiberPerServing: Double { ingredients.reduce(0.0) { $0 + $1.fiberG } / Double(safeServings) }
}

struct MicronutrientDailySnapshot: Identifiable, Equatable {
    let id: String
    let name: String
    let unit: String
    let currentValue: Double
    let targetValue: Double
    let isUpperLimit: Bool
    let icon: String
    let accentHex: UInt64

    var progressFraction: Double {
        guard targetValue > 0 else { return 0 }
        return min(max(currentValue / targetValue, 0.0), 1.35)
    }

    var statusText: String {
        if isUpperLimit {
            return currentValue <= targetValue ? "Dentro del límite" : "Exceso"
        }
        let pct = Int(((currentValue / max(targetValue, 1)) * 100).rounded())
        return "\(pct)% de la meta"
    }
}

// MARK: - Monthly Performance Assessment (MPA 7d/30d/90d) & Longevity Zones (Apartado 1.6)

enum PerformanceAssessmentPeriod: Int, CaseIterable, Identifiable {
    case weekly7d = 7
    case monthly30d = 30
    case quarterly90d = 90

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .weekly7d: return "7 días"
        case .monthly30d: return "30 días (MPA)"
        case .quarterly90d: return "90 días"
        }
    }

    var badgeTitle: String {
        switch self {
        case .weekly7d: return "EVALUACIÓN SEMANAL"
        case .monthly30d: return "EVALUACIÓN MENSUAL (MPA)"
        case .quarterly90d: return "EVALUACIÓN TRIMESTRAL"
        }
    }
}

struct LongevityZoneProgressSnapshot: Equatable {
    let weeklyZone1To3Minutes: Int
    let targetZone1To3Minutes: Int
    let weeklyZone4To5Minutes: Int
    let targetZone4To5Minutes: Int
    let weeklyStrengthSessions: Int
    let targetStrengthSessions: Int
    let weeklyStrengthMinutes: Int
    let overallCompliancePct: Int
}

// MARK: - Sleep Latency, Circadian Alignment & Menstrual Cycle (Apartado 1.7 & 1.8)

struct CircadianAndLatencySnapshot: Equatable {
    let estimatedLatencyMinutes: Int?
    let latencyStatus: String
    let alignmentPct: Int?
    let midpointDeviationMinutes: Int?
    let typicalMidpointLabel: String?
    let lastNightMidpointLabel: String?
    let summaryText: String
}

enum MenstrualCyclePhase: String, Codable, CaseIterable, Identifiable, Hashable {
    case menstrual = "Menstrual"
    case follicular = "Folicular"
    case ovulatory = "Ovulatoria"
    case luteal = "Lútea"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .menstrual: return "drop.circle.fill"
        case .follicular: return "sparkles"
        case .ovulatory: return "sun.max.fill"
        case .luteal: return "moon.circle.fill"
        }
    }
}

struct CycleTrackingSettings: Codable, Equatable, Hashable {
    var isEnabled: Bool = false
    var lastPeriodStartIso: String = ""
    var cycleLengthDays: Int = 28
    var periodDurationDays: Int = 5
}

struct CyclePhaseSnapshot: Equatable {
    let phase: MenstrualCyclePhase
    let dayOfCycle: Int
    let cycleLengthDays: Int
    let daysUntilNextPeriod: Int
    let expectedTempShiftC: Double
    let trainingAdvice: String
    let nutritionAdvice: String
    let isLutealCalibrationActive: Bool
}

// MARK: - Unified Cross-Domain Causal Engine & Auto-Deload Detector (Apartado 2.1 & 2.2)

struct UnifiedCausalInsight: Identifiable, Equatable {
    let id: String
    let categoryBadge: String
    let icon: String
    let title: String
    let impactBadge: String
    let isPositive: Bool
    let detail: String
    let sampleDays: Int
}

struct OvertrainingDeloadAssessment: Equatable {
    let riskLevel: Int // 0 = Óptimo, 1 = Vigilancia, 2 = Descarga Recomendada
    let statusTitle: String
    let acwr: Double
    let hrv3DaySlopeMs: Double
    let recentAvgRpe: Double
    let triggers: [String]
    let recommendation: String
    let deloadWeightFactor: Double
}

// MARK: - Caffeine Pharmacokinetic Window & Beverage Sources (5.5h Half-Life, 20 mg Sleep Threshold)

enum CaffeineWindowPhase: String, Equatable {
    case postWakeDelay = "Espera inicial"
    case optimal = "Ventana óptima"
    case caution = "Precaución"
    case tooLate = "Demasiado tarde"
}

struct CaffeineBeverageSource: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let servingLabel: String
    let mg: Double
    let emoji: String

    var displayTitle: String { "\(name) (\(servingLabel))" }

    static let commonSources: [CaffeineBeverageSource] = [
        CaffeineBeverageSource(id: "green_tea", name: "Té verde", servingLabel: "240 ml", mg: 28, emoji: "🍵"),
        CaffeineBeverageSource(id: "cola", name: "Cola", servingLabel: "330 ml", mg: 34, emoji: "🥤"),
        CaffeineBeverageSource(id: "diet_cola", name: "Coca-Cola light", servingLabel: "355 ml", mg: 46, emoji: "🥤"),
        CaffeineBeverageSource(id: "black_tea", name: "Té negro", servingLabel: "240 ml", mg: 47, emoji: "🫖"),
        CaffeineBeverageSource(id: "mountain_dew", name: "Mountain Dew", servingLabel: "355 ml", mg: 55, emoji: "🥫"),
        CaffeineBeverageSource(id: "instant_coffee", name: "Café soluble", servingLabel: "240 ml", mg: 60, emoji: "☕"),
        CaffeineBeverageSource(id: "espresso", name: "Espresso", servingLabel: "30 ml", mg: 65, emoji: "☕"),
        CaffeineBeverageSource(id: "red_bull", name: "Red Bull", servingLabel: "250 ml", mg: 80, emoji: "⚡"),
        CaffeineBeverageSource(id: "filter_coffee", name: "Café de filtro", servingLabel: "240 ml", mg: 95, emoji: "☕"),
        CaffeineBeverageSource(id: "double_espresso", name: "Espresso doble", servingLabel: "60 ml", mg: 130, emoji: "☕"),
        CaffeineBeverageSource(id: "monster", name: "Monster Energy", servingLabel: "473 ml", mg: 160, emoji: "⚡"),
        CaffeineBeverageSource(id: "cold_brew", name: "Cold Brew", servingLabel: "350 ml", mg: 200, emoji: "🧊")
    ]
}

struct CaffeineLoggedIntake: Identifiable, Equatable {
    let id: String
    let title: String
    let mg: Double
    let timeLabel: String
    let minuteOfDay: Int
}

struct CaffeineDecayCurvePoint: Equatable {
    let minuteOffsetFromWake: Double
    let mg: Double
}

struct CaffeineWindowTimelineSnapshot: Equatable {
    let wakeMinute: Int
    let optimalStartMinute: Int
    let cutoffMinute: Int
    let cautionEndMinute: Int
    let bedtimeMinute: Int
    let nowMinute: Int
    let currentBodyMg: Double
    let totalTodayMg: Double
    let residualAtBedtimeMg: Double
    let phase: CaffeineWindowPhase
    let minutesRemainingInOptimal: Int
    let minutesUntilOptimalStarts: Int
    let sleepThresholdMg: Double
    let curvePoints: [CaffeineDecayCurvePoint]
    let intakes: [CaffeineLoggedIntake]

    var totalSpanMinutes: Double {
        Double(max(bedtimeMinute - wakeMinute, 360))
    }

    var nowProgressFraction: Double {
        let clamped = min(max(Double(nowMinute - wakeMinute) / totalSpanMinutes, 0.0), 1.0)
        return clamped
    }

    var delayFraction: Double {
        min(max(Double(optimalStartMinute - wakeMinute) / totalSpanMinutes, 0.04), 0.20)
    }

    var optimalEndFraction: Double {
        min(max(Double(cutoffMinute - wakeMinute) / totalSpanMinutes, delayFraction + 0.15), 0.65)
    }

    var cautionEndFraction: Double {
        min(max(Double(cautionEndMinute - wakeMinute) / totalSpanMinutes, optimalEndFraction + 0.08), 0.80)
    }

    static func formatMinuteOfDay(_ minute: Int) -> String {
        let norm = ((minute % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", norm / 60, norm % 60)
    }

    var wakeLabel: String { Self.formatMinuteOfDay(wakeMinute) }
    var optimalStartLabel: String { Self.formatMinuteOfDay(optimalStartMinute) }
    var cutoffLabel: String { Self.formatMinuteOfDay(cutoffMinute) }
    var bedtimeLabel: String { Self.formatMinuteOfDay(bedtimeMinute) }

    var axisTickLabels: [String] {
        let step = Int((totalSpanMinutes / 4.0).rounded())
        return (0...4).map { idx in
            Self.formatMinuteOfDay(wakeMinute + idx * step)
        }
    }
}

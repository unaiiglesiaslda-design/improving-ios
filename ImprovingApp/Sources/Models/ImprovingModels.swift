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
    case sleepNeedDetail
    case estres
    case energia
    case nutricion
    case nutrientDetail
    case healthMetricDetail
    case trendMetricDetail
    case trainingLoad
    case cardioMetricDetail
    case askBevel
    case dispositivos

    var id: String { rawValue }
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
        case .oxygenSaturation: return "Oxígeno en sangre"
        case .wristTemperature: return "Temperatura en muñeca"
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
    case normal, below, above
}

struct EffortTrendItem: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let valueText: String
    let unitText: String
    let statusText: String
    let statusTone: TrendStatusTone
    let points: [Double]
    let bandLow: Double
    let bandHigh: Double
    let lineColorHex: UInt64
    let detailNote: String
}

struct EffortEventItem: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let timeRange: String
    let durationMin: Int
    let avgHrBpm: Int
    let strainScore: Double
    let strainPct: Int
    let categoryLabel: String
    let kcal: Int
}

struct SleepStageSegment: Identifiable, Codable, Hashable {
    let id: String
    let stageName: String
    let startFrac: Double
    let endFrac: Double
    let durationMin: Int
    let colorHex: UInt64
}

enum JournalCheckState: String, Codable {
    case unset, yes, no
}

struct JournalHabitItem: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let category: String
    let state: JournalCheckState
    let impactPct: Int
    let detailText: String
}

struct NutritionMealItem: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let timeLabel: String
    let kcal: Int
    let proteinG: Int
    let carbsG: Int
    let fatG: Int
    let qualityScore: Int
}

struct CoachChatMessage: Identifiable, Codable, Hashable {
    let id: String
    let isUser: Bool
    let text: String
    let timestampLabel: String
    let isSuggestionChip: Bool
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
    var ageYears: Double = 24.0
    var sex: BiologicalSexOption = .male
    var weightKg: Double = 70.0
    var heightCm: Double = 176.0
    var bodyFatPct: Double? = nil
    var restingHrCalibrationBpm: Double? = nil
    var hrvCalibrationMs: Double? = nil
    var onboardingCompleted: Bool = false
}

struct RealBiometricDaySummary: Codable, Equatable, Identifiable {
    var id: String { dateIso }
    let dateIso: String // yyyy-MM-dd
    var liveHrBpm: Int?
    var restingHrBpm: Double?
    var hrvMs: Double?
    var respRateRpm: Double?
    var wristTempDeltaC: Double?
    var spo2Percent: Int?
    var asleepMinutes: Int?
    var inBedMinutes: Int?
    var deepMinutes: Int?
    var remMinutes: Int?
    var sleepPct: Int?
    var sleepDebtMinutes: Int?
    var strain21: Double?
    var strainPct: Int?
    var recoveryPct: Int?
    var stressScore: Int?
    var energyBankPercent: Int?
    var stepsCount: Int?
    var vo2MaxMlKgMin: Double?
    var glucoseMgDl: Int?
    var activeKcal: Int?
    var hrZoneMinutes: [Int] // 5 elements Z1..Z5
    var stressSeries24h: [Double]
    var energySeries24h: [Double]
    var strengthMinutes: Int
    var workouts: [EffortEventItem]

    init(
        dateIso: String,
        liveHrBpm: Int? = nil,
        restingHrBpm: Double? = nil,
        hrvMs: Double? = nil,
        respRateRpm: Double? = nil,
        wristTempDeltaC: Double? = nil,
        spo2Percent: Int? = nil,
        asleepMinutes: Int? = nil,
        inBedMinutes: Int? = nil,
        deepMinutes: Int? = nil,
        remMinutes: Int? = nil,
        sleepPct: Int? = nil,
        sleepDebtMinutes: Int? = nil,
        strain21: Double? = nil,
        strainPct: Int? = nil,
        recoveryPct: Int? = nil,
        stressScore: Int? = nil,
        energyBankPercent: Int? = nil,
        stepsCount: Int? = nil,
        vo2MaxMlKgMin: Double? = nil,
        glucoseMgDl: Int? = nil,
        activeKcal: Int? = nil,
        hrZoneMinutes: [Int] = [0, 0, 0, 0, 0],
        stressSeries24h: [Double] = [],
        energySeries24h: [Double] = [],
        strengthMinutes: Int = 0,
        workouts: [EffortEventItem] = []
    ) {
        self.dateIso = dateIso
        self.liveHrBpm = liveHrBpm
        self.restingHrBpm = restingHrBpm
        self.hrvMs = hrvMs
        self.respRateRpm = respRateRpm
        self.wristTempDeltaC = wristTempDeltaC
        self.spo2Percent = spo2Percent
        self.asleepMinutes = asleepMinutes
        self.inBedMinutes = inBedMinutes
        self.deepMinutes = deepMinutes
        self.remMinutes = remMinutes
        self.sleepPct = sleepPct
        self.sleepDebtMinutes = sleepDebtMinutes
        self.strain21 = strain21
        self.strainPct = strainPct
        self.recoveryPct = recoveryPct
        self.stressScore = stressScore
        self.energyBankPercent = energyBankPercent
        self.stepsCount = stepsCount
        self.vo2MaxMlKgMin = vo2MaxMlKgMin
        self.glucoseMgDl = glucoseMgDl
        self.activeKcal = activeKcal
        self.hrZoneMinutes = hrZoneMinutes
        self.stressSeries24h = stressSeries24h
        self.energySeries24h = energySeries24h
        self.strengthMinutes = strengthMinutes
        self.workouts = workouts
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
}

enum CardioMetricRoute: String, CaseIterable, Identifiable {
    case activitiesDuration = "Actividades y duración"
    case cardioLoad = "Carga cardiovascular"
    case vo2Max = "VO₂ máx"
    case hrRecovery = "Recuperación de FC"

    var id: String { rawValue }
}

enum TrainingLoadTab: String, CaseIterable, Identifiable {
    case cardio = "Cardiovascular"
    case muscular = "Muscular"

    var id: String { rawValue }
}

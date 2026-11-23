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
    case journalInsights
    case healthMetricDetail
    case trendMetricDetail
    case trainingLoad
    case cardioMetricDetail
    case askBevel
    case dispositivos

    var id: String { rawValue }
}

enum CoachingSection: String, CaseIterable, Codable, Identifiable {
    case hoy
    case esfuerzo
    case recuperacion
    case sueno
    case estres
    case energia
    case fitness

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
        }
    }
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
    let title: String
    let timeRange: String
    let durationMin: Int
    let avgHrBpm: Int // 0 means no HR recorded
    let strainScore: Double
    let strainPct: Int
    let categoryLabel: String
    let kcal: Int
    var distanceKm: Double? = nil
    var elevationM: Double? = nil
    var dateIso: String? = nil
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
    var id: String { rawValue }
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

    var daysRemainingFor30d: Int {
        max(30 - max(loggedDaysCount, daysSpanCount), 0)
    }
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
    var verdictTitle: String? = nil
    let text: String
    var bullets: [String] = []
    let timestampLabel: String
    let isSuggestionChip: Bool
    var modelUsed: String? = nil
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
    var effectiveAgeYears: Double {
        guard let iso = birthDateIso, let dt = Self.isoBirthFormatter.date(from: iso) else {
            return min(max(ageYears, 13.0), 99.0)
        }
        let secs = Date().timeIntervalSince(dt)
        let yrs = secs / (365.2425 * 86_400.0)
        return min(max((yrs * 10.0).rounded() / 10.0, 13.0), 99.0)
    }

    var birthDate: Date {
        if let iso = birthDateIso, let dt = Self.isoBirthFormatter.date(from: iso) {
            return dt
        }
        let wholeYears = Int(ageYears.rounded())
        return Calendar.current.date(byAdding: .year, value: -max(min(wholeYears, 95), 13), to: Date()) ?? Date()
    }

    mutating func setBirthDate(_ date: Date) {
        let cal = Calendar.current
        let clamped = min(date, cal.date(byAdding: .year, value: -13, to: Date()) ?? date)
        birthDateIso = Self.isoBirthFormatter.string(from: clamped)
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
    var daylightMinutes: Int?
    var sleepNoiseOver50Db: Bool?
    var bodyWeightKg: Double?
    var bodyFatPct: Double?
    var leanMassKg: Double?
    var systolicBp: Int?
    var diastolicBp: Int?
    var hrZoneMinutes: [Int]
    var stressSeries24h: [Double]
    var energySeries24h: [Double]
    var stressSamples5m: [TimedBiometricPoint]
    var energySamples5m: [TimedBiometricPoint]
    var strengthMinutes: Int
    var workouts: [EffortEventItem]

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
        self.stressSeries24h = stressSeries24h
        self.energySeries24h = energySeries24h
        self.stressSamples5m = stressSamples5m
        self.energySamples5m = energySamples5m
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

    var id: String { rawValue }
}

enum TrainingLoadTab: String, CaseIterable, Identifiable {
    case cardio = "Cardiovascular"
    case muscular = "Muscular"

    var id: String { rawValue }
}

import Foundation
import SwiftUI

struct PersonalizedPhysiologyNorms: Equatable {
    // 1. Anthropometry & Body Composition (Height + Weight + Age + Sex)
    let bmi: Double
    let bmiOptimalLow: Double
    let bmiOptimalHigh: Double
    let bmiStatusLabel: String
    let healthyWeightLowKg: Double
    let healthyWeightHighKg: Double
    let optimalBodyFatLowPct: Double
    let optimalBodyFatHighPct: Double
    let optimalLeanMassLowPct: Double
    let optimalLeanMassHighPct: Double

    // 2. Cardiopulmonary & Autonomic Vitals (Age + Sex + Height + BMI)
    let maxHrBpm: Int
    let bmrKcal: Int
    let hrvLowMs: Double
    let hrvHighMs: Double
    let hrvExpectedMs: Double
    let rhrLowBpm: Double
    let rhrHighBpm: Double
    let restingHrExpected: Double
    let respLowRpm: Double
    let respHighRpm: Double
    let spo2LowPct: Double
    let spo2HighPct: Double
    let wristTempLowC: Double
    let wristTempHighC: Double
    let vo2GoodThreshold: Double
    let vo2ExcellentThreshold: Double
    let hrrGoodThresholdBpm: Int
    let vo2CohortSubtitle: String

    // 3. Sleep & Longevity Movement (NSF / AASM Age & Sex Bands)
    let sleepLowHours: Double
    let sleepHighHours: Double
    let sleepTargetHours: Double
    let deepTargetPct: Double
    let remTargetPct: Double
    let dailyStepsGoal: Int
    let weeklyZone23GoalMin: Int
    let weeklyZone45GoalMin: Int
    let weeklyStrengthGoalMin: Int

    // 4. Metabolism, Macros, Hydration & Caffeine (IOM / EFSA / NIH)
    let maintenanceCaloriesKcal: Int
    let proteinGoalG: Int
    let fatGoalG: Int
    let carbsGoalG: Int
    let fiberGoalG: Int
    let hydrationGoalLiters: Double
    let caffeineLimitMg: Double
}

struct LabBiomarkerAgeImpact: Identifiable, Equatable {
    let id: String
    let biomarker: LabBiomarkerItem
    let deltaYears: Double // negative = resta edad biológica, positive = suma edad biológica
}

struct BiologicalAgeEvaluation: Equatable {
    let chronoAgeYears: Double
    let bioAgeYears: Double
    let deltaYears: Double // negative = biologically younger than chronological age
    let sleepDelta: Double
    let activityDelta: Double
    let fitnessDelta: Double
    let vo2Delta: Double
    let rhrDelta: Double
    let autonomicDelta: Double
    let bodyDelta: Double
    let bloodLabsDelta: Double
    let labImpacts: [LabBiomarkerAgeImpact]
    let hasSleep: Bool
    let hasActivity: Bool
    let hasVo2: Bool
    let hasRhr: Bool
    let hasHrv: Bool
    let hasBody: Bool
    let hasBloodLabs: Bool
    var sleepConsistencyDelta: Double = 0.0
    var weeklyZonesDelta: Double = 0.0
    var weeklyStrengthDelta: Double = 0.0
    var hasSleepConsistency: Bool = false
    var hasWeeklyZones: Bool = false
    var hasWeeklyStrength: Bool = false
}

struct PersonalBaselineStats: Equatable {
    let mean: Double
    let sigma: Double
    let count: Int
}

enum VitalRangeSeverity: String {
    case optimalExcellent
    case normal
    case borderlineWarning
    case alertOutOfRange
    case noData
}

struct VitalEvaluation {
    let statusLabel: String
    let normalizedPosition: Double
    let severity: VitalRangeSeverity
    let isAboveBand: Bool
    let isBelowBand: Bool
}

enum WhoopPhysiologyEngine {

    static func computeMaxHeartRate(profile: UserPhysiologyProfile, observedPeakBpm: Int = 0) -> Int {
        let age = profile.effectiveAgeYears
        let tanaka = Int((208.0 - 0.7 * age).rounded())
        return min(max(max(tanaka, observedPeakBpm), 125), 225)
    }

    /// Mifflin-St Jeor Resting Metabolic Rate (modern clinical standard, superior accuracy over 1919 Harris-Benedict).
    static func computeBmrKcalPerDay(profile: UserPhysiologyProfile) -> Int {
        let w = min(max(profile.weightKg, 32.0), 220.0)
        let h = min(max(profile.heightCm, 130.0), 225.0)
        let a = profile.effectiveAgeYears
        let base = 10.0 * w + 6.25 * h - 5.0 * a
        let bmr: Double
        switch profile.sex {
        case .male: bmr = base + 5.0
        case .female: bmr = base - 161.0
        case .nonBinary: bmr = base - 78.0
        }
        return max(Int(bmr.rounded()), 1000)
    }

    // Unified rolling baseline priors across AppleHealthExportImporter, HealthKitReader & ImprovingStore
    static let baselinePopulationHrvSigma = 0.24
    static let baselineFloorHrvSigma = 0.14
    static let baselinePopulationRhrSigma = 3.8
    static let baselineFloorRhrSigma = 1.9
    static let baselinePopulationRespSigma = 0.9
    static let baselineFloorRespSigma = 0.45

    /// Cumulative rolling sleep debt (minutes) with exponential daily carry-over (0.70 decay)
    /// so consecutive short nights accumulate realistic sleep debt and good nights pay it back smoothly!
    static func updateCumulativeSleepDebt(
        previousDebtMinutes: Double,
        asleepMinutes: Int,
        targetMinutes: Double
    ) -> Int {
        let nightlyDiff = targetMinutes - Double(asleepMinutes) // >0 deficit, <0 surplus payback
        let decayedPrev = max(0.0, previousDebtMinutes) * 0.70
        let updated: Double
        if nightlyDiff >= 0 {
            updated = min(decayedPrev + nightlyDiff, 360.0)
        } else {
            // Surplus sleep pays down existing debt at 0.85x efficiency
            updated = max(0.0, decayedPrev + nightlyDiff * 0.85)
        }
        return Int(updated.rounded())
    }

    /// Master clinical & sports-physiology personalization engine (exact parity with Android `WhoopPhysiologyEngine.kt`).
    /// Computes every optimal range, vital band, sleep duration/architecture target, VO2/HRR cohort,
    /// macro/hydration/caffeine target, and movement goal from `(birthDate/age, sex, heightCm, weightKg)`.
    static func computePersonalizedNorms(profile: UserPhysiologyProfile, observedPeakHrBpm: Int = 0) -> PersonalizedPhysiologyNorms {
        let r1 = AppleHealthExportImporter.round1
        let age = min(max(profile.effectiveAgeYears, 13.0), 95.0)
        let weight = min(max(profile.weightKg, 32.0), 220.0)
        let heightCm = min(max(profile.heightCm, 130.0), 225.0)
        let heightM = heightCm / 100.0
        let isFemale = profile.sex == .female
        let isMale = profile.sex == .male
        let isTeen = age < 18.0
        let isSenior = age >= 65.0

        // 1. BMI & Healthy Weight Range by Height & Age (WHO + geriatric lean-mass buffer)
        let bmi = r1(weight / (heightM * heightM))
        let (bmiOptLow, bmiOptHigh): (Double, Double) = {
            if isTeen { return (17.5, 23.5) }
            if isSenior { return (21.0, 27.0) }
            return (18.5, 24.9)
        }()
        let healthyWeightLow = r1(bmiOptLow * heightM * heightM)
        let healthyWeightHigh = r1(bmiOptHigh * heightM * heightM)
        let bmiStatus: String = {
            if bmi < bmiOptLow { return "Por debajo del rango" }
            if bmi <= bmiOptHigh { return "Peso óptimo" }
            if bmi <= bmiOptHigh + 4.5 { return "Por encima del rango" }
            return "Peso elevado"
        }()

        // Optimal Body Fat % & Lean Mass % (ACE / Gallagher norms by Sex & Age decade)
        let (bfLow, bfHigh): (Double, Double) = {
            switch profile.sex {
            case .male:
                if age < 20.0 { return (8.0, 17.0) }
                if age < 40.0 { return (10.0, 19.0) }
                if age < 60.0 { return (11.0, 21.0) }
                return (13.0, 24.0)
            case .female:
                if age < 20.0 { return (16.0, 25.0) }
                if age < 40.0 { return (18.0, 27.0) }
                if age < 60.0 { return (20.0, 30.0) }
                return (22.0, 33.0)
            case .nonBinary:
                if age < 20.0 { return (12.0, 21.0) }
                if age < 40.0 { return (14.0, 23.0) }
                if age < 60.0 { return (15.5, 25.5) }
                return (17.5, 28.5)
            }
        }()
        let leanLow = r1(100.0 - bfHigh)
        let leanHigh = r1(100.0 - bfLow)

        // 2. Autonomic & Cardiopulmonary Vitals (HRV RMSSD, RHR, RR, SpO2, Skin Temp)
        let maxHr = computeMaxHeartRate(profile: profile, observedPeakBpm: observedPeakHrBpm)

        // HRV RMSSD decays exponentially with age (Nunan / Shaffer & Ginsberg / WHOOP norms),
        // slightly higher in young adult women (Koenig & Thayer 2016), dampened at high BMI
        let hrvAgeBase = 88.0 * exp(-0.022 * max(0.0, age - 18.0))
        let hrvSexAdj = (isFemale && age < 52.0) ? 2.5 : 0.0
        let hrvBmiAdj = bmi > 26.5 ? -min((bmi - 26.5) * 0.85, 9.0) : 0.0
        let hrvExpected = r1(min(max(hrvAgeBase + hrvSexAdj + hrvBmiAdj, 22.0), 105.0))
        let hrvHalfBand = max(6.5, hrvExpected * 0.22)
        let hrvLow = r1(max(hrvExpected - hrvHalfBand, 15.0))
        let hrvHigh = r1(min(hrvExpected + hrvHalfBand, 135.0))

        // Resting HR: sex stroke-volume offset (+3.5 bpm female), gentle age drift, height & BMI effects
        let rhrSexBase: Double = switch profile.sex {
        case .male: 54.0
        case .female: 57.5
        case .nonBinary: 55.8
        }
        let rhrAgeAdj = max(0.0, age - 24.0) * 0.11
        let rhrHeightAdj = -min(max((heightCm - 172.0) * 0.08, -2.2), 2.2)
        let rhrBmiAdj = bmi > 25.0 ? min((bmi - 25.0) * 0.45, 6.5) : 0.0
        let rhrExpected = r1(min(max(rhrSexBase + rhrAgeAdj + rhrHeightAdj + rhrBmiAdj, 46.0), 74.0))
        let rhrLow = r1(max(rhrExpected - 5.5, 40.0))
        let rhrHigh = r1(min(rhrExpected + 6.5, 84.0))

        // Nocturnal Respiratory Rate: slightly lower in taller frames (larger vital capacity)
        let rrBase = 14.5
            + (isFemale ? 0.4 : 0.0)
            + (isTeen ? 0.5 : 0.0)
            + (isSenior ? 0.5 : 0.0)
            - min(max((heightCm - 172.0) * 0.025, -0.6), 0.6)
        let rrLow = r1(min(max(rrBase - 1.4, 11.5), 16.0))
        let rrHigh = r1(min(max(rrBase + 1.4, 14.5), 19.5))

        // SpO2 & Wrist Skin Temp
        let spo2Low = age >= 60.0 ? 94.5 : 95.5
        let spo2High = age >= 60.0 ? 99.0 : 99.5
        let tempSeniorShift = isSenior ? -0.15 : 0.0
        let wristTempLow = r1((isFemale ? 35.4 : 35.3) + tempSeniorShift)
        let wristTempHigh = r1((isFemale ? 36.3 : 36.1) + tempSeniorShift)

        // VO2max & HRR targets by Age & Sex (FRIEND / ACSM standards — nonBinary uses true midpoint!)
        let decadeDrop = (max(0.0, age - 24.0) / 10.0) * 3.2
        let vo2GoodBase: Double = switch profile.sex {
        case .male: 48.0
        case .female: 39.5
        case .nonBinary: 43.75
        }
        let vo2ExcellentBase: Double = switch profile.sex {
        case .male: 55.2
        case .female: 45.2
        case .nonBinary: 50.2
        }
        let hrrSexAdj: Double = switch profile.sex {
        case .male: 0.0
        case .female: 1.5
        case .nonBinary: 0.75
        }
        let vo2Good = r1(max(vo2GoodBase - decadeDrop, 22.0))
        let vo2Excellent = r1(max(vo2ExcellentBase - decadeDrop, 26.0))
        let hrrGood = min(max(Int((32.0 - max(0.0, age - 30.0) * 0.25 - hrrSexAdj).rounded()), 16), 36)
        let ageBandStr: String = {
            if age < 20 { return "< 20" }
            if age < 30 { return "20–29" }
            if age < 40 { return "30–39" }
            if age < 50 { return "40–49" }
            if age < 60 { return "50–59" }
            return "60+"
        }()
        let sexCohortStr = isFemale ? "mujeres" : (isMale ? "hombres" : "adultos")
        let vo2Cohort = "Estandarizado para \(ageBandStr) años · \(sexCohortStr)"

        // 3. Sleep Duration & Restorative Architecture (NSF / AASM / Ohayon age bands)
        let femaleSleepAdj = isFemale ? 0.15 : 0.0
        let (sleepLow, sleepHigh, sleepTargetRaw, deepTarget, remTarget): (Double, Double, Double, Double, Double) = {
            if age < 18.0 { return (8.0, 10.0, 9.0, 20.0, 22.0) }
            if age <= 25.0 { return (7.3, 9.0, 8.0, 18.0, 22.0) }
            if age < 45.0 { return (7.0, 8.8, 7.8, 16.0, 21.0) }
            if age < 65.0 { return (7.0, 8.5, 7.6, 13.5, 20.0) }
            return (6.8, 8.3, 7.4, 11.5, 19.0)
        }()
        let sleepTarget = r1(sleepTargetRaw + femaleSleepAdj)

        let stepsGoal: Int = {
            if age < 18.0 { return 10_000 }
            if age <= 45.0 { return 8_500 }
            if age < 65.0 { return 8_000 }
            return 7_000
        }()
        let weeklyZ23 = isTeen ? 180 : 150
        let weeklyZ45 = age >= 60.0 ? 20 : 30
        let weeklyStrength = age >= 50.0 ? 90 : 60

        // 4. Metabolism, Macros, Hydration & Caffeine (IOM / EFSA / NIH)
        let bmr = computeBmrKcalPerDay(profile: profile)
        let activityMult = age >= 65.0 ? 1.32 : (age < 25.0 ? 1.42 : 1.38)
        let maintenanceKcal = min(max(Int((Double(bmr) * activityMult).rounded()), 1300), 4500)
        let effectiveWeightForProtein = weight > healthyWeightHigh
            ? healthyWeightHigh + (weight - healthyWeightHigh) * 0.40
            : weight
        let proteinPerKg: Double = {
            if age >= 55.0 { return 1.95 } // Anabolic resistance buffer in older adults
            return isFemale ? 1.75 : 1.85
        }()
        let proteinGoal = min(max(Int((effectiveWeightForProtein * proteinPerKg).rounded()), 65), 250)
        let fatPerKg = isFemale ? 0.98 : 0.90
        let fatGoal = min(max(Int((effectiveWeightForProtein * fatPerKg).rounded()), 45), 130)
        let carbsGoal = min(max(Int((Double(maintenanceKcal - (proteinGoal * 4 + fatGoal * 9)) / 4.0).rounded()), 90), 480)
        let fiberGoal = min(max(Int((Double(maintenanceKcal) / 1000.0 * 14.0).rounded()), 22), 42)

        let rawHydrationL = (weight * 0.035) + (isMale ? 0.15 : 0.0) + (heightCm >= 182.0 ? 0.15 : 0.0)
        let hydrationL = r1(min(max(rawHydrationL, 1.8), 4.2))
        let caffeineLimit: Double = isTeen
            ? Double(Int((min(weight * 2.5, 100.0) / 10.0).rounded()) * 10)
            : Double(Int((min(weight * 5.5, 400.0) / 10.0).rounded()) * 10)

        return PersonalizedPhysiologyNorms(
            bmi: bmi,
            bmiOptimalLow: bmiOptLow,
            bmiOptimalHigh: bmiOptHigh,
            bmiStatusLabel: bmiStatus,
            healthyWeightLowKg: healthyWeightLow,
            healthyWeightHighKg: healthyWeightHigh,
            optimalBodyFatLowPct: bfLow,
            optimalBodyFatHighPct: bfHigh,
            optimalLeanMassLowPct: leanLow,
            optimalLeanMassHighPct: leanHigh,
            maxHrBpm: maxHr,
            bmrKcal: bmr,
            hrvLowMs: hrvLow,
            hrvHighMs: hrvHigh,
            hrvExpectedMs: hrvExpected,
            rhrLowBpm: rhrLow,
            rhrHighBpm: rhrHigh,
            restingHrExpected: rhrExpected,
            respLowRpm: rrLow,
            respHighRpm: rrHigh,
            spo2LowPct: spo2Low,
            spo2HighPct: spo2High,
            wristTempLowC: wristTempLow,
            wristTempHighC: wristTempHigh,
            vo2GoodThreshold: vo2Good,
            vo2ExcellentThreshold: vo2Excellent,
            hrrGoodThresholdBpm: hrrGood,
            vo2CohortSubtitle: vo2Cohort,
            sleepLowHours: sleepLow,
            sleepHighHours: sleepHigh,
            sleepTargetHours: sleepTarget,
            deepTargetPct: deepTarget,
            remTargetPct: remTarget,
            dailyStepsGoal: stepsGoal,
            weeklyZone23GoalMin: weeklyZ23,
            weeklyZone45GoalMin: weeklyZ45,
            weeklyStrengthGoalMin: weeklyStrength,
            maintenanceCaloriesKcal: maintenanceKcal,
            proteinGoalG: proteinGoal,
            fatGoalG: fatGoal,
            carbsGoalG: carbsGoal,
            fiberGoalG: fiberGoal,
            hydrationGoalLiters: hydrationL,
            caffeineLimitMg: caffeineLimit
        )
    }

    /// Evaluates clinical blood test biomarkers (PhenoAge / cardiometabolic longevity weighting)
    /// into individual and aggregate biological-age adjustments (negative = younger, positive = older).
    static func computeBloodLabsAgeImpact(
        biomarkers: [LabBiomarkerItem]
    ) -> (totalDelta: Double, impacts: [LabBiomarkerAgeImpact]) {
        guard !biomarkers.isEmpty else { return (0.0, []) }

        var rawEntries: [(item: LabBiomarkerItem, rawDelta: Double)] = []
        rawEntries.reserveCapacity(biomarkers.count)

        func hasToken(_ text: String, _ token: String) -> Bool {
            let escaped = NSRegularExpression.escapedPattern(for: token)
            let pattern = "(?:^|[^a-z0-9])\(escaped)(?:$|[^a-z0-9])"
            return text.range(of: pattern, options: .regularExpression) != nil
        }

        for item in biomarkers {
            let key = item.name
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let cat = item.category
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))

            // 1. Clinical longevity weighting (word-boundary safe so "alt" never matches "alto", "got" never matches "gota", "ade" never matches "adenosina")
            let isHdl = hasToken(key, "hdl")
            let isVitD = key.contains("vitamina d") || key.contains("25-oh") || key.contains("vitamin d")
            let isStrictlyLowerProtective = hasToken(key, "pcr") || hasToken(key, "crp") ||
                hasToken(key, "ldl") || key.contains("apob") || key.contains("lp(a)") ||
                key.contains("homociste")
            let isLowerIsBetter = isStrictlyLowerProtective || key.contains("hba1c") ||
                key.contains("glicosilada") || key.contains("triglicer") || key.contains("insulina") ||
                hasToken(key, "homa") || key.contains("acido urico") ||
                hasToken(key, "ggt") || hasToken(key, "alt") || hasToken(key, "gpt") ||
                hasToken(key, "ast") || hasToken(key, "got")

            let isHighImpact = isLowerIsBetter || isHdl || key.contains("glucosa") || key.contains("glucose") ||
                key.contains("colesterol") || key.contains("albumina") || key.contains("creatinina") ||
                hasToken(key, "egfr") || key.contains("filtrado") || hasToken(key, "rdw") || hasToken(key, "ade") ||
                hasToken(key, "vcm") || key.contains("leucocit") || key.contains("linfocit") ||
                key.contains("fosfatasa alcalina") || cat.contains("metabol") || cat.contains("lipid") || cat.contains("inflam")

            let isModerateImpact = isVitD || key.contains("ferritin") || key.contains("b12") ||
                key.contains("folic") || key.contains("folato") || key.contains("hierro") ||
                key.contains("magnesio") || key.contains("zinc") || key.contains("omega") ||
                key.contains("tsh") || key.contains("t4") || key.contains("t3") ||
                key.contains("testosteron") || key.contains("cortisol") || key.contains("dhea") ||
                key.contains("hemoglobina") || key.contains("hematocrito") || key.contains("plaquet") ||
                cat.contains("hormon") || cat.contains("vitamin") || cat.contains("hematol")

            let weight: Double = isHighImpact ? 1.0 : (isModerateImpact ? 0.70 : 0.45)

            // Severity multiplier (1.0 .. 1.75) when outside laboratory reference bounds
            func outOfRangeSeverity(isHigh: Bool) -> Double {
                guard let lo = item.refMin, let hi = item.refMax, hi > lo else { return 1.15 }
                let span = max(hi - lo, 0.001)
                let overshoot = isHigh ? max(item.value - hi, 0.0) : max(lo - item.value, 0.0)
                let frac = overshoot / span
                return min(max(1.0 + frac * 1.1, 1.0), 1.75)
            }

            let rawDelta: Double
            switch item.status {
            case .optimal:
                if let oLo = item.optimalMin, let oHi = item.optimalMax, oHi > oLo,
                   item.value >= oLo, item.value <= oHi {
                    rawDelta = -0.38 * weight
                } else {
                    rawDelta = -0.32 * weight
                }

            case .normal:
                if let oLo = item.optimalMin, let oHi = item.optimalMax, oHi > oLo,
                   item.value >= oLo, item.value <= oHi {
                    rawDelta = -0.24 * weight
                } else if let rLo = item.refMin, let rHi = item.refMax, rHi > rLo {
                    let frac = (item.value - rLo) / (rHi - rLo)
                    if isHdl {
                        rawDelta = frac >= 0.55 ? -0.18 * weight : 0.04 * weight
                    } else if isLowerIsBetter {
                        rawDelta = frac <= 0.45 ? -0.16 * weight : (frac >= 0.85 ? 0.08 * weight : -0.02 * weight)
                    } else {
                        rawDelta = (frac >= 0.20 && frac <= 0.80) ? -0.08 * weight : 0.04 * weight
                    }
                } else {
                    rawDelta = -0.06 * weight
                }

            case .high:
                if isHdl {
                    // High HDL is cardioprotective -> subtracts biological age!
                    rawDelta = -0.32 * weight
                } else if isVitD && item.value <= 100.0 {
                    rawDelta = -0.12 * weight
                } else {
                    let sev = outOfRangeSeverity(isHigh: true)
                    let highBase = isLowerIsBetter ? 0.56 : 0.46
                    rawDelta = highBase * weight * sev
                }

            case .low:
                // Only strictly protective atherogenic/inflammatory markers reward below-range lows;
                // low HbA1c, insulin, uric acid, liver enzymes or glucose are NOT rewarded as youth!
                if isStrictlyLowerProtective {
                    rawDelta = -0.14 * weight
                } else {
                    let sev = outOfRangeSeverity(isHigh: false)
                    let lowBase = isHdl ? 0.56 : 0.46
                    rawDelta = lowBase * weight * sev
                }
            }

            rawEntries.append((item, rawDelta))
        }

        // Prevent panel-size inflation (40 normal markers must not artificially grant a massive youth bonus vs 6 markers)
        let panelCountNormalizer = rawEntries.count > 8
            ? pow(8.0 / Double(rawEntries.count), 0.35)
            : 1.0
        let normalizedRawSum = rawEntries.reduce(0.0) { $0 + $1.rawDelta } * panelCountNormalizer
        let capNeg = -3.5
        let capPos = 4.5
        let capScale: Double = {
            if normalizedRawSum < capNeg { return abs(capNeg / normalizedRawSum) }
            if normalizedRawSum > capPos { return capPos / normalizedRawSum }
            return 1.0
        }()
        let finalScale = panelCountNormalizer * capScale

        let impacts = rawEntries
            .map { entry -> LabBiomarkerAgeImpact in
                let scaled = AppleHealthExportImporter.round1(entry.rawDelta * finalScale)
                return LabBiomarkerAgeImpact(
                    id: entry.item.id,
                    biomarker: entry.item,
                    deltaYears: scaled
                )
            }
            .sorted { abs($0.deltaYears) > abs($1.deltaYears) }

        let totalDelta = AppleHealthExportImporter.round1(min(max(normalizedRawSum, capNeg), capPos))
        return (totalDelta, impacts)
    }

    /// Computes Biological Age calibrated strictly against the user's OWN age, sex, height, and weight norms
    /// (so a 62-year-old is evaluated against 62-year-old clinical norms, NOT 24-year-old norms!),
    /// incorporating real blood-test biomarkers when uploaded in Biología.
    static func computeBiologicalAge(
        profile: UserPhysiologyProfile,
        meanRhr: Double?,
        meanHrv: Double?,
        meanSleepHours: Double?,
        meanSteps: Int?,
        vo2Max: Double?,
        latestWeightKg: Double? = nil,
        latestBodyFatPct: Double? = nil,
        labBiomarkers: [LabBiomarkerItem] = [],
        sleepConsistencyPct: Int? = nil,
        weeklyZone1To3Min: Int? = nil,
        weeklyZone4To5Min: Int? = nil,
        weeklyStrengthMin: Int? = nil
    ) -> BiologicalAgeEvaluation {
        let norms = computePersonalizedNorms(profile: profile)
        let chrono = profile.effectiveAgeYears

        var sleepDelta = 0.0
        if let s = meanSleepHours {
            // U-shaped clinical sleep-longevity curve:
            // - Short sleep (< target) ages progressively up to +2.2 yrs
            // - Optimal restorative window [target .. target + 0.85h] subtracts up to -0.65 yrs
            // - Chronic excessive oversleep (> target + 0.85h, e.g. >9-10h) penalizes up to +1.4 yrs
            let target = norms.sleepTargetHours
            if s < target {
                sleepDelta = min((target - s) * 0.85, 2.2)
            } else if s <= target + 0.85 {
                let extra = s - target
                // Peaks around target + 0.35h (-0.65 yrs), tapers cleanly toward 0 near target + 0.85h
                let distFromPeak = abs(extra - 0.35)
                sleepDelta = min(max(-0.65 + distFromPeak * 0.9, -0.65), -0.15)
            } else {
                let oversleep = s - (target + 0.85)
                sleepDelta = min(max(oversleep * 0.72, 0.05), 1.4)
            }
        }

        // WHOOP Healthspan Pillar 2: Sleep Consistency % (-0.6 to +0.8 yrs)
        var sleepConsDelta = 0.0
        if let cons = sleepConsistencyPct {
            if cons >= 80 {
                sleepConsDelta = -min(Double(cons - 75) * 0.024, 0.6)
            } else if cons < 68 {
                sleepConsDelta = min(Double(68 - cons) * 0.025, 0.8)
            }
        }

        var activityDelta = 0.0
        if let st = meanSteps {
            let ratio = Double(st) / Double(max(norms.dailyStepsGoal, 4000))
            activityDelta = min(max((1.0 - ratio) * 1.8, -1.6), 2.0)
        }

        // WHOOP Healthspan Pillars: Weekly HR Zones (1-3 aerobic >= 150m, 4-5 VO2 >= 25m) & Weekly Strength (>= 60m)
        var zonesDelta = 0.0
        let hasZones = (weeklyZone1To3Min != nil || weeklyZone4To5Min != nil)
        if hasZones {
            let z13 = Double(weeklyZone1To3Min ?? 0)
            let z45 = Double(weeklyZone4To5Min ?? 0)
            let aerobicScore = min(z13 / 150.0, 1.4)
            let highScore = min(z45 / 25.0, 1.4)
            let combined = aerobicScore * 0.65 + highScore * 0.35
            zonesDelta = min(max((0.85 - combined) * 0.85, -0.7), 0.7)
        }

        var strengthDelta = 0.0
        let hasStrength = weeklyStrengthMin != nil
        if let sMin = weeklyStrengthMin {
            let ratio = min(Double(sMin) / 75.0, 1.5)
            strengthDelta = min(max((0.75 - ratio) * 0.65, -0.5), 0.5)
        }

        var vo2Delta = 0.0
        if let v = vo2Max {
            vo2Delta = min(max((norms.vo2GoodThreshold - v) * 0.18, -2.5), 2.8)
        }
        var rhrDelta = 0.0
        if let r = meanRhr {
            rhrDelta = min(max((r - norms.restingHrExpected) * 0.14, -1.8), 2.2)
        }
        let fitnessDelta = vo2Delta + rhrDelta

        var autonomicDelta = 0.0
        if let h = meanHrv, h > 2.0 {
            let lnDiff = log(norms.hrvExpectedMs) - log(h)
            autonomicDelta = min(max(lnDiff * 2.2, -1.8), 2.2)
        }

        let hasBody = latestWeightKg != nil || latestBodyFatPct != nil || profile.profileSetupVersion >= 2
        var bodyDelta = 0.0
        if let bf = latestBodyFatPct {
            if bf > norms.optimalBodyFatHighPct {
                bodyDelta = min((bf - norms.optimalBodyFatHighPct) * 0.18, 2.2)
            } else if bf < norms.optimalBodyFatLowPct {
                bodyDelta = min((norms.optimalBodyFatLowPct - bf) * 0.16, 1.2)
            } else {
                bodyDelta = -0.4
            }
        } else {
            let w = latestWeightKg ?? profile.weightKg
            let hm = max(profile.heightCm / 100.0, 1.2)
            let curBmi = w / (hm * hm)
            if curBmi > norms.bmiOptimalHigh {
                bodyDelta = min((curBmi - norms.bmiOptimalHigh) * 0.25, 2.2)
            } else if curBmi < norms.bmiOptimalLow {
                bodyDelta = min((norms.bmiOptimalLow - curBmi) * 0.22, 1.4)
            } else if latestWeightKg != nil {
                bodyDelta = -0.3
            }
        }

        let labsEval = computeBloodLabsAgeImpact(biomarkers: labBiomarkers)
        let bloodLabsDelta = labsEval.totalDelta

        let rSleep = AppleHealthExportImporter.round1(sleepDelta)
        let rSleepCons = AppleHealthExportImporter.round1(sleepConsDelta)
        let rActivity = AppleHealthExportImporter.round1(activityDelta)
        let rZones = AppleHealthExportImporter.round1(zonesDelta)
        let rStrength = AppleHealthExportImporter.round1(strengthDelta)
        let rVo2 = AppleHealthExportImporter.round1(vo2Delta)
        let rRhr = AppleHealthExportImporter.round1(rhrDelta)
        let rFitness = AppleHealthExportImporter.round1(rVo2 + rRhr)
        let rAutonomic = AppleHealthExportImporter.round1(autonomicDelta)
        let rBody = AppleHealthExportImporter.round1(bodyDelta)

        let rawTotal = rSleep + rSleepCons + rActivity + rZones + rStrength + rFitness + rAutonomic + rBody + bloodLabsDelta
        let clampedDelta = AppleHealthExportImporter.round1(min(max(rawTotal, -9.5), 9.5))
        let bioAge = AppleHealthExportImporter.round1(max(14.0, chrono + clampedDelta))

        return BiologicalAgeEvaluation(
            chronoAgeYears: AppleHealthExportImporter.round1(chrono),
            bioAgeYears: bioAge,
            deltaYears: clampedDelta,
            sleepDelta: rSleep,
            activityDelta: rActivity,
            fitnessDelta: rFitness,
            vo2Delta: rVo2,
            rhrDelta: rRhr,
            autonomicDelta: rAutonomic,
            bodyDelta: rBody,
            bloodLabsDelta: bloodLabsDelta,
            labImpacts: labsEval.impacts,
            hasSleep: meanSleepHours != nil,
            hasActivity: meanSteps != nil,
            hasVo2: vo2Max != nil,
            hasRhr: meanRhr != nil,
            hasHrv: (meanHrv ?? 0) > 2.0,
            hasBody: hasBody,
            hasBloodLabs: !labBiomarkers.isEmpty,
            sleepConsistencyDelta: rSleepCons,
            weeklyZonesDelta: rZones,
            weeklyStrengthDelta: rStrength,
            hasSleepConsistency: sleepConsistencyPct != nil,
            hasWeeklyZones: hasZones,
            hasWeeklyStrength: hasStrength
        )
    }

    static func evaluateVital(
        value: Double,
        bandLow: Double,
        bandHigh: Double,
        lowerIsBetter: Bool = false,
        higherIsBetter: Bool = false,
        hasData: Bool = true
    ) -> VitalEvaluation {
        guard hasData else {
            return VitalEvaluation(statusLabel: "Sin datos", normalizedPosition: 0.5, severity: .noData, isAboveBand: false, isBelowBand: false)
        }
        let span = max(bandHigh - bandLow, 0.1)
        if value < bandLow {
            let pos = max(0.12, 0.26 - ((bandLow - value) / span) * 0.18)
            if lowerIsBetter {
                return VitalEvaluation(statusLabel: "Óptimo", normalizedPosition: pos, severity: .optimalExcellent, isAboveBand: false, isBelowBand: true)
            }
            return VitalEvaluation(statusLabel: "Bajo", normalizedPosition: pos, severity: .borderlineWarning, isAboveBand: false, isBelowBand: true)
        }
        if value > bandHigh {
            let pos = min(0.88, 0.74 + ((value - bandHigh) / span) * 0.18)
            if higherIsBetter {
                return VitalEvaluation(statusLabel: "Óptimo", normalizedPosition: pos, severity: .optimalExcellent, isAboveBand: true, isBelowBand: false)
            }
            return VitalEvaluation(statusLabel: "Alto", normalizedPosition: pos, severity: .borderlineWarning, isAboveBand: true, isBelowBand: false)
        }
        let frac = (value - bandLow) / span
        let pos = 0.28 + frac * 0.44
        if lowerIsBetter && frac < 0.28 {
            return VitalEvaluation(statusLabel: "Óptimo", normalizedPosition: 0.18, severity: .optimalExcellent, isAboveBand: false, isBelowBand: true)
        }
        return VitalEvaluation(statusLabel: "Normal", normalizedPosition: pos, severity: .normal, isAboveBand: false, isBelowBand: false)
    }

    // MARK: - Bevel / WHOOP Beat-to-Beat RMSSD & Entire Sleep HRV Engine

    /// Computes true beat-to-beat RMSSD (ms) from contiguous RR interval segments (ms),
    /// applying Bevel/WHOOP absolute (300–2000 ms) and relative ectopic/artifact beat filtering.
    static func computeRmssdFromRRSegments(_ segments: [[Double]]) -> Double? {
        let allValid = segments.flatMap { $0 }.filter { (300.0...2000.0).contains($0) }
        guard allValid.count >= 5 else { return nil }

        let sorted = allValid.sorted()
        let medRR = sorted.count % 2 == 1
            ? sorted[sorted.count / 2]
            : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2.0
        guard medRR >= 300.0 && medRR <= 2000.0 else { return nil }

        // Bevel/WHOOP artifact filter: reject beats > 25% away from local median RR or jumps > 300 ms / 30% of median
        let maxDev = medRR * 0.25
        let maxJump = min(300.0, medRR * 0.30)

        var sqDiffSum = 0.0
        var diffCount = 0

        for seg in segments {
            var prevClean: Double? = nil
            for rr in seg {
                guard (300.0...2000.0).contains(rr), abs(rr - medRR) <= maxDev else {
                    prevClean = nil
                    continue
                }
                if let p = prevClean {
                    let d = abs(rr - p)
                    if d <= maxJump {
                        sqDiffSum += d * d
                        diffCount += 1
                    }
                }
                prevClean = rr
            }
        }

        guard diffCount >= 4 else { return nil }
        let rmssd = sqrt(sqDiffSum / Double(diffCount))
        return (3.0...350.0).contains(rmssd) ? rmssd : nil
    }

    /// Computes true beat-to-beat RMSSD (ms) from Apple Health `<InstantaneousBeatsPerMinute bpm="..." time="..."/>` readings.
    /// Uses exact sub-second beat-to-beat `time` differences when available (identical to HealthKit `HKHeartbeatSeriesQuery`),
    /// splits segments across sensor dropouts (> 2.2s gaps), and falls back to `60_000 / bpm` when `time` lacks sub-second precision.
    static func computeRmssdFromBeatEntries(_ entries: [(timeSec: Double?, hasSubsecond: Bool, bpm: Double)]) -> Double? {
        guard entries.count >= 5 else { return nil }

        let subsecondCount = entries.filter { $0.timeSec != nil && $0.hasSubsecond }.count
        if subsecondCount >= 5 {
            var segments: [[Double]] = []
            var cur: [Double] = []
            var prevT: Double? = nil
            for e in entries {
                guard let t = e.timeSec else {
                    if !cur.isEmpty { segments.append(cur); cur = [] }
                    prevT = nil
                    continue
                }
                if let p = prevT {
                    var dt = t - p
                    if dt < -43_200.0 { dt += 86_400.0 } // midnight wrap
                    let rrMs = dt * 1000.0
                    if (300.0...2000.0).contains(rrMs) {
                        cur.append(rrMs)
                    } else {
                        if !cur.isEmpty { segments.append(cur); cur = [] }
                    }
                }
                prevT = t
            }
            if !cur.isEmpty { segments.append(cur) }
            if let exactRmssd = computeRmssdFromRRSegments(segments) {
                return exactRmssd
            }
        }

        // Fallback when timestamps are integer-only or absent: convert BPM -> RR and split across > 2.2s time gaps
        var segments: [[Double]] = []
        var cur: [Double] = []
        var prevT: Double? = nil
        for e in entries {
            guard (30.0...200.0).contains(e.bpm) else {
                if !cur.isEmpty { segments.append(cur); cur = [] }
                prevT = e.timeSec
                continue
            }
            if let t = e.timeSec, let p = prevT {
                var dt = t - p
                if dt < -43_200.0 { dt += 86_400.0 }
                if dt > 2.2 || dt < 0 {
                    if !cur.isEmpty { segments.append(cur); cur = [] }
                }
            }
            cur.append(60_000.0 / e.bpm)
            prevT = e.timeSec
        }
        if !cur.isEmpty { segments.append(cur) }
        return computeRmssdFromRRSegments(segments)
    }

    /// Computes true beat-to-beat RMSSD (ms) from Apple Health `<InstantaneousBeatsPerMinute>` BPM readings.
    static func computeRmssdFromBeatBpms(_ bpms: [Double]) -> Double? {
        let rr = bpms.compactMap { bpm -> Double? in
            guard (30.0...200.0).contains(bpm) else { return nil }
            return 60_000.0 / bpm
        }
        return computeRmssdFromRRSegments([rr])
    }

    /// Outlier-cleaned mean for sleeping HR:
    /// Preserves genuine REM-sleep HR rises (e.g. 60–72 bpm during dreaming) while stripping extreme
    /// optical/motion glitches (> max(4.5 * robustSigma, 28 bpm) away from night median).
    static func aggregateSleepingHr(_ samples: [Double]) -> Double? {
        let valid = samples.filter { (28.0...135.0).contains($0) && $0.isFinite }
        guard !valid.isEmpty else { return nil }
        if valid.count < 5 {
            return valid.reduce(0, +) / Double(valid.count)
        }
        let sorted = valid.sorted()
        let med = sorted.count % 2 == 1
            ? sorted[sorted.count / 2]
            : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2.0
        let absDevs = sorted.map { abs($0 - med) }.sorted()
        let mad = absDevs.count % 2 == 1
            ? absDevs[absDevs.count / 2]
            : (absDevs[absDevs.count / 2 - 1] + absDevs[absDevs.count / 2]) / 2.0
        let maxDev = max(4.5 * 1.4826 * mad, 28.0)
        let cleaned = valid.filter { abs($0 - med) <= maxDev }
        let pool = cleaned.isEmpty ? valid : cleaned
        return pool.reduce(0, +) / Double(pool.count)
    }

    /// Computes Bevel-style 60-day personal normal range for a Health Monitor vital.
    /// Uses the user's own trailing 60-day rolling baseline (robust median/MAD) once >= 5 real readings exist,
    /// and seamlessly falls back to clinical age/sex/body norms when sparse (or for sleep duration target).
    static func computePersonalVitalNormalBand(
        kind: HealthMetricKind,
        trailingValues: [Double],
        profile: UserPhysiologyProfile
    ) -> (low: Double, high: Double, isPersonal: Bool) {
        let norms = computePersonalizedNorms(profile: profile)
        let r1 = AppleHealthExportImporter.round1
        let vals = Array(trailingValues.filter(\.isFinite).suffix(60))

        switch kind {
        case .hrv:
            let valid = vals.filter { (3.0...350.0).contains($0) }
            guard valid.count >= 5 else { return (norms.hrvLowMs, norms.hrvHighMs, false) }
            let lnVals = valid.map { log($0) }
            let base = computeRollingBaseline(
                priorValues: lnVals,
                populationMean: log(max(norms.hrvExpectedMs, 15.0)),
                populationSigma: 0.22,
                floorSigma: 0.14
            )
            let low = r1(max(exp(base.mean - 1.25 * base.sigma), 12.0))
            let high = r1(min(exp(base.mean + 1.25 * base.sigma), 180.0))
            return (low, max(high, low + 8.0), true)

        case .restingHeartRate:
            let valid = vals.filter { (28.0...130.0).contains($0) }
            guard valid.count >= 5 else { return (norms.rhrLowBpm, norms.rhrHighBpm, false) }
            let base = computeRollingBaseline(
                priorValues: valid,
                populationMean: norms.restingHrExpected,
                populationSigma: 3.5,
                floorSigma: 2.2
            )
            let low = r1(max(base.mean - 1.35 * base.sigma, 34.0))
            let high = r1(min(base.mean + 1.35 * base.sigma, 105.0))
            return (low, max(high, low + 5.0), true)

        case .respiratoryRate:
            let valid = vals.filter { (6.0...38.0).contains($0) }
            guard valid.count >= 5 else { return (norms.respLowRpm, norms.respHighRpm, false) }
            let center = (norms.respLowRpm + norms.respHighRpm) / 2.0
            let base = computeRollingBaseline(
                priorValues: valid,
                populationMean: center,
                populationSigma: 0.9,
                floorSigma: 0.55
            )
            let low = r1(max(base.mean - 1.35 * base.sigma, 9.0))
            let high = r1(min(base.mean + 1.35 * base.sigma, 26.0))
            return (low, max(high, low + 1.4), true)

        case .oxygenSaturation:
            let valid = vals.filter { (70.0...100.0).contains($0) }
            guard valid.count >= 5 else { return (norms.spo2LowPct, norms.spo2HighPct, false) }
            let base = computeRollingBaseline(
                priorValues: valid,
                populationMean: max(norms.spo2LowPct + 1.8, 97.0),
                populationSigma: 1.0,
                floorSigma: 0.7
            )
            // Keep clinical safety floor so hypoxemia (< norms.spo2LowPct) is never labeled Normal
            let low = r1(max(norms.spo2LowPct, min(base.mean - 1.35 * base.sigma, 96.5)))
            let high = r1(min(100.0, max(base.mean + 1.20 * base.sigma, norms.spo2HighPct)))
            return (low, max(high, low + 1.5), true)

        case .wristTemperature:
            let valid = vals.filter { (30.0...41.0).contains($0) }
            guard valid.count >= 5 else { return (norms.wristTempLowC, norms.wristTempHighC, false) }
            let center = (norms.wristTempLowC + norms.wristTempHighC) / 2.0
            let base = computeRollingBaseline(
                priorValues: valid,
                populationMean: center,
                populationSigma: 0.35,
                floorSigma: 0.25
            )
            let low = r1(max(base.mean - 1.40 * base.sigma, 33.5))
            let high = r1(min(base.mean + 1.40 * base.sigma, 38.5))
            return (low, max(high, low + 0.6), true)

        case .sleepDuration:
            // Sleep duration normal band stays anchored to clinical NSF/AASM age targets
            return (norms.sleepLowHours, norms.sleepHighHours, false)
        }
    }

    /// Aggregates HRV readings across Entire Sleep ("Todo el sueño") using Bevel's outlier-cleaned mean:
    /// strips extreme motion/artifact spikes (> 3.0 robust MAD sigma from night median) before averaging.
    static func aggregateEntireSleepHrv(_ samples: [Double]) -> Double? {
        let valid = samples.filter { (3.0...350.0).contains($0) && $0.isFinite }
        guard !valid.isEmpty else { return nil }
        if valid.count < 4 {
            return valid.reduce(0, +) / Double(valid.count)
        }
        let sorted = valid.sorted()
        let med = sorted.count % 2 == 1
            ? sorted[sorted.count / 2]
            : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2.0
        let absDevs = sorted.map { abs($0 - med) }.sorted()
        let mad = absDevs.count % 2 == 1
            ? absDevs[absDevs.count / 2]
            : (absDevs[absDevs.count / 2 - 1] + absDevs[absDevs.count / 2]) / 2.0
        let robustSigma = max(1.4826 * mad, med * 0.18, 12.0)
        let cleaned = valid.filter { abs($0 - med) <= 3.0 * robustSigma }
        let pool = cleaned.isEmpty ? valid : cleaned
        return pool.reduce(0, +) / Double(pool.count)
    }

    // MARK: - Causal 60-Day Personal Rolling Baseline (Matches Bevel Personal Normal Range!)

    static func computeRollingBaseline(
        priorValues: [Double],
        populationMean: Double,
        populationSigma: Double,
        floorSigma: Double
    ) -> PersonalBaselineStats {
        let window = Array(priorValues.suffix(60))
        let n = window.count
        guard n > 0 else {
            return PersonalBaselineStats(mean: populationMean, sigma: max(populationSigma, floorSigma), count: 0)
        }
        let sorted = window.sorted()
        let med = sorted.count % 2 == 1 ? sorted[sorted.count / 2] : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2.0
        let absDevs = sorted.map { abs($0 - med) }.sorted()
        let mad = absDevs.count % 2 == 1 ? absDevs[absDevs.count / 2] : (absDevs[absDevs.count / 2 - 1] + absDevs[absDevs.count / 2]) / 2.0
        let robustSigma = max(1.4826 * mad, floorSigma)

        // Winsorized mean (clamps extreme outliers > 3 SD so single illness nights don't skew baseline)
        let clamped = window.map { min(max($0, med - 3.0 * robustSigma), med + 3.0 * robustSigma) }
        let wMean = clamped.reduce(0, +) / Double(clamped.count)

        if n < 7 {
            let w = Double(n) / 7.0
            let blendedMean = (1.0 - w) * populationMean + w * wMean
            let blendedSigma = (1.0 - w) * populationSigma + w * robustSigma
            return PersonalBaselineStats(mean: blendedMean, sigma: max(blendedSigma, floorSigma), count: n)
        }
        return PersonalBaselineStats(mean: wMean, sigma: robustSigma, count: n)
    }

    // MARK: - Bevel-Aligned Adaptive Recovery % (Zero Fabricated Sensors, Log-HRV + Sleeping RHR Z-Score!)

    /// Computes Bevel-aligned Recovery (1...99%) strictly from sensors that were ACTUALLY measured on this day,
    /// incorporating personal 60-day rolling baselines AND optional age/sex/body cohort calibration when `profile` is provided.
    /// In Apple Watch Low Power Mode overnight (when both HRV & RHR are skipped, but a real `sleepPct` was recorded),
    /// gracefully evaluates recovery from real sleep quality + any measured secondary vitals without fabricating HRV/RHR.
    /// Returns `nil` if NEITHER HRV, RHR, nor `sleepPct` was recorded.
    static func computeBevelRecoveryPercent(
        hrvMs: Double?,
        rhrBpm: Double?,
        respRpm: Double?,
        spo2Pct: Double?,
        wristTempDeltaC: Double?,
        lnHrvBaseline: PersonalBaselineStats,
        rhrBaseline: PersonalBaselineStats,
        respBaseline: PersonalBaselineStats,
        profile: UserPhysiologyProfile? = nil,
        sleepPct: Int? = nil
    ) -> Int? {
        guard hrvMs != nil || rhrBpm != nil || sleepPct != nil else { return nil }

        let profileNorms = profile.map { computePersonalizedNorms(profile: $0) }
        let spo2Floor = profileNorms?.spo2LowPct ?? 95.0

        // Low Power Mode overnight fallback: watchOS skipped background HRV & RHR,
        // but recorded a real sleep session (`sleepPct`). Compute grounded recovery from
        // real sleep + any measured Resp/SpO2/Temp without fabricating HRV or RHR!
        if hrvMs == nil && rhrBpm == nil, let slp = sleepPct {
            var score = 20.0 + Double(min(max(slp, 10), 100)) * 0.70
            if let resp = respRpm, resp > 5.0 {
                let zResp = (respBaseline.mean - resp) / max(respBaseline.sigma, 0.5)
                score += min(max(zResp, -2.5), 1.0) * 4.0
            }
            if let spo2 = spo2Pct, spo2 < spo2Floor {
                score -= (spo2Floor - spo2) * 3.2
            }
            if let tempD = wristTempDeltaC, abs(tempD) > 0.55 {
                score -= (abs(tempD) - 0.55) * 14.0
            }
            return min(max(Int(score.rounded()), 15), 92)
        }

        // Avoid cold-start double-dipping: when count < 7, `computeRollingBaseline` ALREADY blends
        // population prior into `.mean`. Ramp cohort weight smoothly from 0% (count=0) to 15% (count>=7),
        // independently for HRV and RHR using their own sample counts!
        let hrvCohortWeight: Double = {
            guard profileNorms != nil else { return 0.0 }
            return min(Double(lnHrvBaseline.count) / 7.0, 1.0) * 0.15
        }()
        let rhrCohortWeight: Double = {
            guard profileNorms != nil else { return 0.0 }
            return min(Double(rhrBaseline.count) / 7.0, 1.0) * 0.15
        }()

        // Bevel weights: ~62% Sleeping HRV (log-normal z-score) + ~33% Sleeping RHR + ~5% secondary vitals
        var weightedZ = 0.0
        var totalWeight = 0.0

        if let hrv = hrvMs, hrv > 2.0 {
            let personalZ = (log(hrv) - lnHrvBaseline.mean) / max(lnHrvBaseline.sigma, 0.12)
            let effZ: Double
            if let norms = profileNorms, hrvCohortWeight > 0 {
                let cohortZ = (log(hrv) - log(max(norms.hrvExpectedMs, 15.0))) / 0.28
                effZ = (1.0 - hrvCohortWeight) * personalZ + hrvCohortWeight * cohortZ
            } else {
                effZ = personalZ
            }
            let clampedZ = min(max(effZ, -2.8), 2.8)
            weightedZ += 0.62 * clampedZ
            totalWeight += 0.62
        }

        if let rhr = rhrBpm, rhr > 25.0 {
            let personalZ = (rhrBaseline.mean - rhr) / max(rhrBaseline.sigma, 1.8)
            let effZ: Double
            if let norms = profileNorms, rhrCohortWeight > 0 {
                let cohortZ = (norms.restingHrExpected - rhr) / 5.0
                effZ = (1.0 - rhrCohortWeight) * personalZ + rhrCohortWeight * cohortZ
            } else {
                effZ = personalZ
            }
            let clampedZ = min(max(effZ, -2.8), 2.8)
            weightedZ += 0.33 * clampedZ
            totalWeight += 0.33
        }

        // When HRV was skipped (e.g. Apple Watch Low Power Mode) and only daytime RHR exists,
        // lightly stabilize Recovery with real sleep quality so a single RHR sample doesn't swing wildly.
        if hrvMs == nil, let slp = sleepPct {
            let sleepZ = min(max((Double(slp) - 65.0) / 18.0, -2.2), 2.0)
            weightedZ += 0.22 * sleepZ
            totalWeight += 0.22
        }

        if let resp = respRpm, resp > 5.0 {
            let zResp = (respBaseline.mean - resp) / max(respBaseline.sigma, 0.5)
            // Only penalize elevated respiratory rate or slight bonus
            let clampedZ = min(max(zResp, -2.5), 1.0)
            weightedZ += 0.05 * clampedZ
            totalWeight += 0.05
        }

        guard totalWeight > 0 else { return nil }
        let normalizedZ = weightedZ / totalWeight

        // Logistic curve centered at ~63% when at personal baseline (z = 0):
        // z = -2.0 -> ~14%, z = -1.0 -> ~34%, z = 0.0 -> ~62%, z = +1.0 -> ~84%, z = +2.0 -> ~95%
        var score = 100.0 / (1.0 + exp(-1.18 * (normalizedZ + 0.42)))

        // Secondary clinical stress penalties ONLY when genuinely measured and abnormal
        if let spo2 = spo2Pct, spo2 < spo2Floor {
            score -= (spo2Floor - spo2) * 3.2
        }
        if let tempD = wristTempDeltaC, abs(tempD) > 0.55 {
            score -= (abs(tempD) - 0.55) * 14.0
        }

        return min(max(Int(score.rounded()), 1), 99)
    }

    // Legacy compatibility helper used by unit tests
    static func computeRecoveryPercent(
        hrvMs: Double,
        rhrBpm: Double,
        respRpm: Double,
        spo2Pct: Double,
        wristTempDeltaC: Double,
        sleepScorePct: Int,
        hrvMean: Double = 72.0,
        hrvSigma: Double = 8.0,
        rhrMean: Double = 51.0,
        rhrSigma: Double = 2.8,
        respMean: Double = 15.2,
        respSigma: Double = 0.6
    ) -> Int {
        let lnMean = log(max(hrvMean, 10.0))
        let lnSd = max(hrvSigma / max(hrvMean, 10.0), 0.14)
        return computeBevelRecoveryPercent(
            hrvMs: hrvMs,
            rhrBpm: rhrBpm,
            respRpm: respRpm,
            spo2Pct: spo2Pct,
            wristTempDeltaC: wristTempDeltaC,
            lnHrvBaseline: PersonalBaselineStats(mean: lnMean, sigma: lnSd, count: 30),
            rhrBaseline: PersonalBaselineStats(mean: rhrMean, sigma: rhrSigma, count: 30),
            respBaseline: PersonalBaselineStats(mean: respMean, sigma: respSigma, count: 30)
        ) ?? 50
    }

    // MARK: - Bevel-Calibrated Cardiovascular Strain (0–100% & WHOOP 0–21)

    /// Computes Strain strictly from real HR zone minutes, real workouts, and real active calories.
    /// Calibrated to match original Bevel:
    /// - Rest day (~250 kcal, 0 workouts): ~14–22%
    /// - Single 300 kcal strength session (~500 kcal total): ~35–48% (workout itself ~24%)
    /// - Hard 60-min cardio day (~900 kcal, Z2–Z4): ~70–82%
    static func computeBevelStrain(
        profile: UserPhysiologyProfile,
        rhrBpm: Double,
        hrZoneMinutes: [Int],
        workouts: [EffortEventItem],
        activeKcal: Double?
    ) -> (strain21: Double, strainPct: Int)? {
        let hasZones = hrZoneMinutes.reduce(0, +) > 0
        let hasWorkouts = !workouts.isEmpty
        let kcal = activeKcal ?? 0
        guard hasZones || hasWorkouts || kcal >= 25 else { return nil }

        let b = profile.sex.banisterB
        let maxHr = Double(computeMaxHeartRate(profile: profile))
        let hrr = max(maxHr - rhrBpm, 40.0)
        let bmr = Double(computeBmrKcalPerDay(profile: profile))

        // 1. HR-zone Banister TRIMP (exact Z1..Z5 intensity weights, adjusted for age cardiovascular load)
        let age = profile.effectiveAgeYears
        let ageZoneFactor = 1.0 + min(max((age - 25.0) * 0.0045, -0.04), 0.22)
        let zoneWeights = [0.65, 1.35, 2.35, 3.80, 5.60]
        var zoneTrimp = 0.0
        for (idx, mins) in hrZoneMinutes.prefix(5).enumerated() where mins > 0 {
            zoneTrimp += Double(mins) * zoneWeights[idx] * ageZoneFactor
        }

        // 2. Workout physiological load (HR TRIMP + mechanical/muscular strength tonnage, sets & RPE when logged)
        var workoutLoad = 0.0
        for w in workouts {
            var baseLoad = 0.0
            if w.avgHrBpm > 0 {
                let frac = min(max((Double(w.avgHrBpm) - rhrBpm) / hrr, 0.25), 0.98)
                let rate = frac * 0.64 * exp(b * frac)
                baseLoad = Double(w.durationMin) * rate * 1.15
            } else if w.kcal > 0 {
                baseLoad = (Double(w.kcal) / max(bmr, 1100.0)) * 165.0
            } else {
                baseLoad = Double(w.durationMin) * 0.55 * ageZoneFactor
            }
            let rpeVal = w.rpe.map { Double(min(max($0, 1), 10)) }
            let rpeMult = rpeVal.map { 0.72 + 0.055 * $0 } ?? 1.0
            if w.avgHrBpm == 0, let rv = rpeVal {
                baseLoad *= (0.82 + 0.036 * rv)
            }
            // Add neuromuscular load for logged strength sessions (sets, tonnage & RPE) so heavy lifting matches WHOOP Strength Trainer!
            let setsBonus = Double(w.totalSets ?? 0) * 1.65
            let volBonus = min((w.totalVolumeKg ?? 0) / 400.0, 24.0)
            let muscularLoad = (setsBonus + volBonus) * rpeMult
            workoutLoad += max(baseLoad, muscularLoad) + min(baseLoad, muscularLoad) * 0.35
        }

        // 3. Passive daily active energy load (normalized to personal BMR)
        let passiveKcalLoad = kcal > 0 ? (kcal / max(bmr, 1100.0)) * 95.0 : 0.0

        // Smooth monotonic load: never drops when adding a small HR-zone signal on top of passive calories
        let cardioCore = max(zoneTrimp, workoutLoad)
        let totalLoad = max(passiveKcalLoad, cardioCore + passiveKcalLoad * 0.35)

        // Exponential diminishing-return Bevel curve: 100 * (1 - exp(-L / 108))
        let pctDouble = 100.0 * (1.0 - exp(-max(totalLoad, 0.5) / 108.0))
        let pct = min(max(Int(pctDouble.rounded()), 1), 100)
        let strain21 = AppleHealthExportImporter.round1(min(max((pctDouble / 100.0) * 20.8, 0.2), 21.0))
        return (strain21, pct)
    }

    static func computeWorkoutStrain(
        durationMin: Int,
        kcal: Int,
        avgHrBpm: Int,
        rhrBpm: Double = 55.0,
        maxHrBpm: Double = 192.0,
        banisterB: Double = 1.92,
        totalSets: Int = 0,
        totalVolumeKg: Double = 0,
        rpe: Int? = nil
    ) -> (strain21: Double, strainPct: Int) {
        var cardioLoad: Double
        if avgHrBpm > 40 {
            let frac = min(max((Double(avgHrBpm) - rhrBpm) / max(maxHrBpm - rhrBpm, 40.0), 0.22), 0.98)
            cardioLoad = Double(durationMin) * frac * 0.64 * exp(banisterB * frac) * 1.15
        } else if kcal > 0 {
            cardioLoad = Double(kcal) * 0.095
        } else {
            cardioLoad = Double(durationMin) * 0.52
        }
        let rpeVal = rpe.map { Double(min(max($0, 1), 10)) }
        let rpeMult = rpeVal.map { 0.72 + 0.055 * $0 } ?? 1.0
        if avgHrBpm <= 40, let rv = rpeVal {
            cardioLoad *= (0.82 + 0.036 * rv)
        }
        let muscularLoad = (Double(max(totalSets, 0)) * 1.65 + min(max(totalVolumeKg, 0) / 400.0, 24.0)) * rpeMult
        let load = muscularLoad > 0 ? (max(cardioLoad, muscularLoad) + min(cardioLoad, muscularLoad) * 0.35) : cardioLoad
        let pctDouble = 100.0 * (1.0 - exp(-max(load, 1.0) / 108.0))
        let pct = min(max(Int(pctDouble.rounded()), 2), 98)
        let s21 = AppleHealthExportImporter.round1(min(max((pctDouble / 100.0) * 20.8, 0.4), 20.8))
        return (s21, pct)
    }

    /// WHOOP-style Sleep Consistency % (0–100%) from circular bedtime & wake-time standard deviation across trailing nights.
    static func computeSleepConsistencyPercent(sessions: [(startMinuteOfDay: Int, endMinuteOfDay: Int)]) -> Int? {
        guard sessions.count >= 2 else { return nil }
        // Shift post-midnight bedtimes (00:00..08:00) by +1440 for circular continuity around midnight
        let beds = sessions.map { Double($0.startMinuteOfDay < 480 ? $0.startMinuteOfDay + 1440 : $0.startMinuteOfDay) }
        let wakes = sessions.map { Double($0.endMinuteOfDay) }

        func sd(_ vals: [Double]) -> Double {
            let mean = vals.reduce(0, +) / Double(vals.count)
            let variance = vals.reduce(0.0) { $0 + pow($1 - mean, 2) } / Double(vals.count)
            return sqrt(variance)
        }
        let avgSdMin = (sd(beds) + sd(wakes)) / 2.0
        // 0 min SD -> 100%, 20 min SD -> ~84%, 45 min SD -> ~68%, 90 min SD -> ~46%, 150 min SD -> ~27%
        let score = 100.0 * exp(-avgSdMin / 115.0)
        return min(max(Int(score.rounded()), 10), 100)
    }

    /// WHOOP Healthspan-style Pace of Aging multiplier (0.3x ... 2.5x).
    /// Compares recent 30d biological age trajectory vs prior 30d baseline when available.
    static func computePaceOfAging(
        currentEval: BiologicalAgeEvaluation,
        priorEval: BiologicalAgeEvaluation?
    ) -> PaceOfAgingSnapshot {
        // Base physiological pace anchored at 1.0x (negative bio delta slows aging below 1.0x)
        var pace = 1.0 + currentEval.deltaYears * 0.085
        let trendDelta: Double?
        if let prev = priorEval {
            let diff = AppleHealthExportImporter.round1(currentEval.deltaYears - prev.deltaYears)
            trendDelta = diff
            // Recent improvement (diff < 0) decelerates current pace; worsening accelerates it
            pace += min(max(diff * 0.35, -0.45), 0.55)
        } else {
            trendDelta = nil
        }
        let clamped = AppleHealthExportImporter.round1(min(max(pace, 0.3), 2.5))
        let status: String
        let detail: String
        if clamped <= 0.85 {
            status = "Más lento que el promedio"
            detail = "Tus hábitos y biomarcadores recientes frenan el desgaste fisiológico."
        } else if clamped <= 1.15 {
            status = "Ritmo equilibrado"
            detail = "Envejeces en línea con tu edad cronológica; mejorar sueño o VO₂ máx. reducirá este ritmo."
        } else {
            status = "Ritmo acelerado"
            detail = "Tus métricas recientes muestran carga o descanso subóptimo; prioriza sueño, VFC y actividad aeróbica."
        }
        return PaceOfAgingSnapshot(
            multiplier: clamped,
            statusLabel: status,
            deltaVsPrior30d: trendDelta,
            explanation: detail
        )
    }

    // MARK: - Bevel-Calibrated Sleep Score % (Strictly Measured Components + Age/Sex Restorative Targets!)

    static func computeBevelSleepScore(
        asleepMinutes: Int,
        inBedMinutes: Int?,
        deepMinutes: Int?,
        remMinutes: Int?,
        awakeMinutes: Int?,
        awakeCount: Int,
        hrDipPct: Double?,
        targetMinutes: Double = 480.0,
        deepTargetPct: Double = 16.0,
        remTargetPct: Double = 20.0
    ) -> Int {
        var scoreSum = 0.0
        var weightSum = 0.0

        // 1. Duration (45% weight) — 100% at age-personalized targetMinutes
        let durScore = min(max(Double(asleepMinutes) / max(targetMinutes, 300.0), 0.10), 1.0) * 100.0
        scoreSum += 0.45 * durScore
        weightSum += 0.45

        // 2. Efficiency (15% weight) — only if inBedMinutes exists
        if let bed = inBedMinutes, bed > 0 {
            let effPct = min(max(Double(asleepMinutes) / Double(bed) * 100.0, 40.0), 100.0)
            // Bevel treats >= 94% efficiency as 100 score, 75% as ~50
            let effScore = min(max((effPct - 60.0) / 35.0, 0.0), 1.0) * 100.0
            scoreSum += 0.15 * effScore
            weightSum += 0.15
        }

        // 3. Restorative stages (REM + Deep, 20% weight) — targets adapt cleanly with age!
        if let d = deepMinutes, let r = remMinutes, (d + r) > 0, asleepMinutes > 0 {
            let deepPct = Double(d) / Double(asleepMinutes) * 100.0
            let remPct = Double(r) / Double(asleepMinutes) * 100.0
            let deepScore = min(max(deepPct / max(deepTargetPct, 10.0), 0.0), 1.0) * 100.0
            let remScore = min(max(remPct / max(remTargetPct, 14.0), 0.0), 1.0) * 100.0
            scoreSum += 0.20 * (0.5 * deepScore + 0.5 * remScore)
            weightSum += 0.20
        }

        // 4. Continuity (10% weight) — reward uninterrupted staged nights (awakeCount == 0 -> 100%) instead of dropping the weight!
        let hasStageTracking = (deepMinutes != nil || remMinutes != nil || inBedMinutes != nil || awakeMinutes != nil)
        if hasStageTracking {
            let aw = max(awakeMinutes ?? 0, 0)
            let contScore: Double = (awakeCount == 0 && aw == 0)
                ? 100.0
                : Double(max(20, min(100, 100 - awakeCount * 7 - Int(Double(aw) * 0.8))))
            scoreSum += 0.10 * contScore
            weightSum += 0.10
        }

        // 5. Heart Rate Dip (10% weight) — only if real HR dip was measured
        if let dip = hrDipPct {
            let dipScore = min(max(dip / 15.0, 0.0), 1.0) * 100.0
            scoreSum += 0.10 * dipScore
            weightSum += 0.10
        }

        let finalScore = weightSum > 0 ? (scoreSum / weightSum) : durScore
        return min(max(Int(finalScore.rounded()), 10), 100)
    }

    /// Computes a personalized, continuous daily Optimal Strain target range (0..1):
    /// 1. Smooth continuous curve driven by exact Recovery % (zero staircase jumps at 45%/70%).
    /// 2. Anchored to the user's real trailing 28-day daily Strain baseline (blended with a healthy floor so
    ///    sedentary weeks never spiral to zero while respecting each athlete's real training volume).
    /// 3. Modulated downward by accumulated Cardio Training Load fatigue (EWMA), 3-day strain spikes, and sleep debt.
    /// 4. Uses age only as an initial prior that smoothly fades out once 14+ days of real user history exist.
    static func optimalTargetRange(
        for recoveryPct: Int,
        profile: UserPhysiologyProfile? = nil,
        baselineStrainPct: Double? = nil,
        baselineSampleCount: Int = 0,
        cardioLoadState: TrainingLoadState? = nil,
        sleepDebtMinutes: Int? = nil,
        recent3DayAvgStrainPct: Double? = nil,
        unhealthyVitalsCount: Int = 0
    ) -> ClosedRange<Double> {
        let r = min(max(Double(recoveryPct), 0.0), 100.0) / 100.0

        // 1. Continuous physiological recovery midpoint (18% at 0% rec -> 52% at 70% -> 68% at 100%)
        let recoveryMid = 0.18 + 0.50 * pow(r, 1.08)

        // 2. Personal 28-day strain baseline blend (ramps smoothly to 65% personal weight at 14+ real days)
        var mid = recoveryMid
        if let rawBase = baselineStrainPct, rawBase.isFinite, baselineSampleCount >= 3 {
            let historyWeight = min(Double(baselineSampleCount) / 14.0, 1.0) * 0.65
            // Gentle floor (24%) prevents a sick/sedentary week from collapsing healthy targets to near zero
            let effectiveBase = min(max(rawBase / 100.0, 0.24), 0.78)
            // Recovery multiplier scales around 1.0x at ~60% recovery (0.58x at 0% -> 1.28x at 100%)
            let recMultiplier = 0.58 + 0.70 * r
            // Safety ceiling ensures red recovery days never ask for excessive strain even for high-volume athletes
            let recoveryCeiling = 0.32 + 0.54 * r
            let personalMid = min(max(effectiveBase * recMultiplier, 0.16), recoveryCeiling)
            mid = (1.0 - historyWeight) * recoveryMid + historyWeight * personalMid
        }

        // 3. Cumulative fatigue modulation (EWMA Cardio Load + 3-day acute spike + Sleep Debt)
        if let state = cardioLoadState {
            switch state {
            case .overtraining:
                mid -= 0.14
            case .fatigued:
                mid -= 0.08
            case .productive, .calibrating:
                break
            case .maintaining:
                mid += 0.01
            case .peaking:
                if recoveryPct >= 60 { mid += 0.03 }
            case .detraining:
                if recoveryPct >= 55 { mid += 0.04 }
            }
        }

        if let r3 = recent3DayAvgStrainPct, let base = baselineStrainPct, r3 > base + 12.0 {
            let spikePenalty = min(((r3 - base) - 12.0) * 0.003, 0.06)
            mid -= spikePenalty
        }

        if let debt = sleepDebtMinutes, debt > 30 {
            let debtPenalty = min(Double(debt - 30) / 600.0, 0.08)
            mid -= debtPenalty
        }

        // 3b. WHOOP Health Monitor illness / physiological stress auto-protection when 2+ vitals deviate negatively!
        if unhealthyVitalsCount >= 3 {
            mid = min(mid - 0.20, 0.36)
        } else if unhealthyVitalsCount == 2 {
            mid = min(mid - 0.14, 0.44)
        }

        // 4. Age acts ONLY as a gentle calibration prior when history is sparse (fades to 0 at 14+ days!)
        if let p = profile {
            let agePriorWeight = max(0.0, 1.0 - Double(baselineSampleCount) / 14.0)
            if agePriorWeight > 0.01 {
                let age = p.effectiveAgeYears
                let ageShift: Double = {
                    if age < 25.0 { return 0.015 }
                    if age <= 45.0 { return 0.0 }
                    if age < 60.0 { return -0.03 }
                    return -0.06
                }()
                mid += ageShift * agePriorWeight
            }
        }

        // Dynamic band width: slightly narrower on low recovery (±9%), wider on high recovery (±12%)
        let halfWidth = 0.09 + 0.03 * r
        let rawLo = min(max(mid - halfWidth, 0.12), 0.72)
        let rawHi = min(max(mid + halfWidth, rawLo + 0.16), 0.88)
        let lo = (rawLo * 100.0).rounded() / 100.0
        let hi = max((rawHi * 100.0).rounded() / 100.0, lo + 0.16)
        return lo...min(hi, 0.90)
    }

    // MARK: - Preview Simulator (ONLY used before user imports Apple Health or connects a device; continuous energy!)

    static func generateTwoYearSimulatedHistory(profile: UserPhysiologyProfile, endDate: Date = Date()) -> [String: RealBiometricDaySummary] {
        let totalDays = 90 // Lightweight 90-day preview before real data is imported
        let norms = computePersonalizedNorms(profile: profile)
        let targetSleepMin = norms.sleepTargetHours * 60.0
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        let shortDtFmt = DateFormatter()
        shortDtFmt.locale = Locale(identifier: "es_ES")
        shortDtFmt.dateFormat = "dd/MM/yy"

        var map: [String: RealBiometricDaySummary] = [:]
        map.reserveCapacity(totalDays)
        var carriedEnergy: Double = 36.0

        for i in 0..<totalDays {
            let dayOffset = (totalDays - 1) - i
            guard let date = cal.date(byAdding: .day, value: -dayOffset, to: endDate) else { continue }
            let iso = fmt.string(from: date)
            let dayStartEpoch = Int64(cal.startOfDay(for: date).timeIntervalSince1970)

            let progress = Double(i) / Double(totalDays)
            let w1 = sin(Double(i) * 2.0 * .pi / 7.0)
            let w2 = cos(Double(i) * 2.0 * .pi / 28.0)
            let hash = ((i &* 1_103_515_245 &+ 12_345) >> 16) & 0x7FFF
            let noise = Double((hash % 200) - 100) / 100.0

            let hrv = AppleHealthExportImporter.round1(min(max(norms.hrvExpectedMs * 0.96 + progress * 6.5 + w2 * 4.0 + noise * 5.5, 18.0), 125.0))
            let rhr = AppleHealthExportImporter.round1(min(max(norms.restingHrExpected - progress * 2.0 - w2 * 1.1 + noise * 1.8, 40.0), 78.0))
            let respCenter = (norms.respLowRpm + norms.respHighRpm) / 2.0
            let resp = AppleHealthExportImporter.round1(min(max(respCenter + noise * 0.4, 11.5), 19.0))
            let spo2 = AppleHealthExportImporter.round1(min(max(norms.spo2LowPct + 1.4 + noise * 0.9, 93.5), 99.5))
            let tempDelta = AppleHealthExportImporter.round1(min(max(w2 * 0.14 + noise * 0.18, -0.4), 0.5))
            let tempAbs = AppleHealthExportImporter.round1(((norms.wristTempLowC + norms.wristTempHighC) / 2.0) + tempDelta)

            let weekday = cal.component(.weekday, from: date)
            let isWeekend = (weekday == 1 || weekday == 7)
            let asleepMin = min(max(Int((targetSleepMin * 0.94 + (isWeekend ? 26.0 : 0.0) + w1 * 16.0 + noise * 20.0).rounded()), 330), 600)
            let inBedMin = asleepMin + 16 + (hash % 12)
            let deepMin = Int((Double(asleepMin) * (norms.deepTargetPct / 100.0)).rounded())
            let remMin = Int((Double(asleepMin) * (norms.remTargetPct / 100.0)).rounded())
            let awakeMin = max(inBedMin - asleepMin, 6)
            let coreMin = max(asleepMin - deepMin - remMin, 110)
            let sleepPct = computeBevelSleepScore(
                asleepMinutes: asleepMin, inBedMinutes: inBedMin,
                deepMinutes: deepMin, remMinutes: remMin,
                awakeMinutes: awakeMin, awakeCount: 2, hrDipPct: 13.5,
                targetMinutes: targetSleepMin,
                deepTargetPct: norms.deepTargetPct,
                remTargetPct: norms.remTargetPct
            )

            let trainFactor: Double = switch weekday {
            case 2, 4, 6: 0.65
            case 3, 5: 0.48
            case 7: 0.78
            default: 0.22
            }
            let z1 = max(Int((14.0 + trainFactor * 22.0).rounded()), 4)
            let z2 = max(Int((8.0 + trainFactor * 18.0).rounded()), 0)
            let z3 = max(Int((trainFactor * 12.0).rounded()), 0)
            let z4 = max(Int(((trainFactor - 0.5) * 10.0).rounded()), 0)
            let zones = [z1, z2, z3, z4, 0]

            let wTitle: String? = switch weekday {
            case 2: "Entrenamiento de fuerza"
            case 3: "Carrera base"
            case 4: "Fuerza tren inferior"
            case 6: "Cardio + intervalos"
            case 7: "Tirada larga"
            default: nil
            }
            let wDur = wTitle != nil ? min(max(z1 + z2 + z3 + z4, 35), 82) : 0
            let wKcal = wTitle != nil ? (wDur * 8 + 60) : 0
            let wStrain = wTitle != nil ? computeWorkoutStrain(durationMin: wDur, kcal: wKcal, avgHrBpm: 142, rhrBpm: rhr) : (0.0, 0)
            let workouts: [EffortEventItem] = wTitle.map {
                [EffortEventItem(
                    id: "sim_\(dayOffset)",
                    title: $0,
                    timeRange: "18:00 - \(18 + wDur / 60):\(String(format: "%02d", wDur % 60))",
                    durationMin: wDur,
                    avgHrBpm: 142,
                    strainScore: wStrain.0,
                    strainPct: wStrain.1,
                    categoryLabel: $0.contains("Fuerza") || $0.contains("fuerza") ? "Fuerza" : "Cardio",
                    kcal: wKcal,
                    dateIso: iso
                )]
            } ?? []

            let activeKcal = wKcal + 280 + (hash % 180)
            let strainTuple = computeBevelStrain(profile: profile, rhrBpm: rhr, hrZoneMinutes: zones, workouts: workouts, activeKcal: Double(activeKcal)) ?? (4.0, 20)

            let recPct = computeBevelRecoveryPercent(
                hrvMs: hrv, rhrBpm: rhr, respRpm: resp, spo2Pct: spo2,
                wristTempDeltaC: tempDelta,
                lnHrvBaseline: PersonalBaselineStats(mean: log(max(norms.hrvExpectedMs, 15.0)), sigma: 0.20, count: 30),
                rhrBaseline: PersonalBaselineStats(mean: norms.restingHrExpected, sigma: 3.0, count: 30),
                respBaseline: PersonalBaselineStats(mean: respCenter, sigma: 0.7, count: 30),
                profile: profile
            ) ?? 65
            let stressBase = min(max(Int((22.0 + (100.0 - Double(recPct)) * 0.22 + Double(strainTuple.strainPct) * 0.18).rounded()), 12), 68)

            // Continuous 5-minute stress & energy (carries carriedEnergy seamlessly across midnight!)
            var stress5m: [TimedBiometricPoint] = []
            var energy5m: [TimedBiometricPoint] = []
            var curE = carriedEnergy
            let sleepPeakTarget = min(max(Double(recPct) * 0.96 + 8.0, 62.0), 99.0)

            if dayOffset <= 14 {
                stress5m.reserveCapacity(288)
                energy5m.reserveCapacity(288)
                let sleepEndSlot = 96 // 08:00
                let sleepStartSlot = 6 // 00:30
                let chargeStep = max((sleepPeakTarget - curE) / Double(sleepEndSlot - sleepStartSlot), 0.25)

                for slot in 0..<288 {
                    let minOfDay = slot * 5
                    let isSleep = slot >= sleepStartSlot && slot <= sleepEndSlot
                    let isWk = wTitle != nil && slot >= 216 && slot <= 228
                    let wave = sin(Double(slot) * 0.35 + Double(dayOffset)) * 5.0 + cos(Double(slot) * 0.14) * 3.0
                    let st = AppleHealthExportImporter.round1(min(max((isSleep ? 9.0 : (isWk ? 74.0 : Double(stressBase))) + wave, 2.0), 94.0))
                    let ep = dayStartEpoch + Int64(minOfDay * 60)
                    stress5m.append(TimedBiometricPoint(minuteOfDay: minOfDay, value: st, epochSec: ep))

                    if isSleep {
                        curE = min(sleepPeakTarget, curE + chargeStep)
                    } else {
                        let drain = 0.08 + (st / 100.0) * 0.62 + (isWk ? 0.55 : 0.0)
                        curE = max(5.0, curE - drain)
                    }
                    energy5m.append(TimedBiometricPoint(minuteOfDay: minOfDay, value: AppleHealthExportImporter.round1(curE), epochSec: ep))
                }
            } else {
                curE = max(12.0, min(95.0, sleepPeakTarget - Double(strainTuple.strainPct) * 0.72))
            }
            carriedEnergy = curE

            var sleepDetail: SleepSessionDetail? = nil
            if dayOffset <= 14 {
                let startMin = 30
                let sleepStartEpoch = dayStartEpoch + Int64(startMin * 60)
                let sleepEndEpoch = sleepStartEpoch + Int64(inBedMin * 60)
                let endMin = (startMin + inBedMin) % 1440
                let startLabel = String(format: "%d:%02d", startMin / 60, startMin % 60)
                let endLabel = String(format: "%d:%02d", endMin / 60, endMin % 60)

                var stages: [SleepStageBlock] = []
                let pattern: [(SleepStageKind, Double)] = [
                    (.core, 0.08), (.deep, 0.11), (.core, 0.10), (.awake, 0.02),
                    (.core, 0.12), (.rem, 0.09), (.core, 0.13), (.deep, 0.07),
                    (.core, 0.11), (.rem, 0.08), (.awake, 0.02), (.core, 0.07)
                ]
                var cursor = sleepStartEpoch
                let totalSpan = Double(sleepEndEpoch - sleepStartEpoch)
                for (pIdx, seg) in pattern.enumerated() {
                    let dur = Int64((totalSpan * seg.1).rounded())
                    let next = min(cursor + dur, sleepEndEpoch)
                    stages.append(SleepStageBlock(id: "sim_st_\(dayOffset)_\(pIdx)", stage: seg.0, startEpochSec: cursor, endEpochSec: next))
                    cursor = next
                }

                var hrPts: [TimedBiometricPoint] = []
                for m in stride(from: 0, through: inBedMin, by: 6) {
                    let ep = sleepStartEpoch + Int64(m * 60)
                    let v = AppleHealthExportImporter.round1(rhr + 1.5 + sin(Double(m) * 0.04) * 3.4)
                    hrPts.append(TimedBiometricPoint(minuteOfDay: (startMin + m) % 1440, value: v, epochSec: ep))
                }
                var hrvPts: [TimedBiometricPoint] = []
                for m in stride(from: 45, through: max(inBedMin - 20, 45), by: 95) {
                    let ep = sleepStartEpoch + Int64(m * 60)
                    let v = AppleHealthExportImporter.round1(hrv + sin(Double(m) * 0.02) * 12.0)
                    hrvPts.append(TimedBiometricPoint(minuteOfDay: (startMin + m) % 1440, value: v, epochSec: ep))
                }
                var respPts: [TimedBiometricPoint] = []
                for m in stride(from: 10, through: inBedMin, by: 16) {
                    let ep = sleepStartEpoch + Int64(m * 60)
                    let v = AppleHealthExportImporter.round1(resp + sin(Double(m) * 0.06) * 0.9)
                    respPts.append(TimedBiometricPoint(minuteOfDay: (startMin + m) % 1440, value: v, epochSec: ep))
                }
                var spo2Pts: [TimedBiometricPoint] = []
                for m in stride(from: 35, through: inBedMin, by: 55) {
                    let ep = sleepStartEpoch + Int64(m * 60)
                    let v = AppleHealthExportImporter.round1(min(max(spo2 + cos(Double(m) * 0.05) * 1.2, 93.5), 99.5))
                    spo2Pts.append(TimedBiometricPoint(minuteOfDay: (startMin + m) % 1440, value: v, epochSec: ep))
                }

                sleepDetail = SleepSessionDetail(
                    startEpochSec: sleepStartEpoch,
                    endEpochSec: sleepEndEpoch,
                    startTimeLabel: startLabel,
                    endTimeLabel: endLabel,
                    startDateTimeLabel: "\(shortDtFmt.string(from: date)) a las \(startLabel)",
                    sourceName: "Vista previa",
                    awakeSeconds: awakeMin * 60,
                    remSeconds: remMin * 60,
                    coreSeconds: coreMin * 60,
                    deepSeconds: deepMin * 60,
                    latencyMinutes: 7,
                    efficiencyPct: min(max(Int((Double(asleepMin) / Double(max(inBedMin, 1)) * 100.0).rounded()), 60), 99),
                    hrDipPct: 13.5,
                    continuityPct: 92,
                    stages: stages,
                    sleepHrSamples: hrPts,
                    sleepHrvSamples: hrvPts,
                    sleepRespSamples: respPts,
                    sleepSpo2Samples: spo2Pts
                )
            }

            map[iso] = RealBiometricDaySummary(
                dateIso: iso,
                liveHrBpm: Int(rhr.rounded()) + 16,
                restingHrBpm: rhr,
                hrvMs: hrv,
                respRateRpm: resp,
                wristTempDeltaC: tempDelta,
                wristTempAbsoluteC: tempAbs,
                spo2Percent: spo2,
                asleepMinutes: asleepMin,
                inBedMinutes: inBedMin,
                deepMinutes: deepMin,
                remMinutes: remMin,
                coreMinutes: coreMin,
                awakeMinutes: awakeMin,
                sleepPct: sleepPct,
                sleepDebtMinutes: max(Int(targetSleepMin.rounded()) - asleepMin, 0),
                sleepSession: sleepDetail,
                strain21: strainTuple.strain21,
                strainPct: strainTuple.strainPct,
                recoveryPct: recPct,
                stressScore: stressBase,
                energyBankPercent: Int(curE.rounded()),
                stepsCount: max(norms.dailyStepsGoal - 1200 + (hash % 3800), 3000),
                vo2MaxMlKgMin: AppleHealthExportImporter.round1(norms.vo2GoodThreshold + progress * 2.2),
                hrRecoveryBpm: AppleHealthExportImporter.round1(Double(norms.hrrGoodThresholdBpm) + progress * 2.5),
                activeKcal: activeKcal,
                daylightMinutes: 25 + (hash % 30),
                sleepNoiseOver50Db: (hash % 5 == 0),
                bodyWeightKg: profile.weightKg,
                hrZoneMinutes: zones,
                stressSeries24h: [],
                energySeries24h: [],
                stressSamples5m: stress5m,
                energySamples5m: energy5m,
                strengthMinutes: (wTitle?.localizedCaseInsensitiveContains("fuerza") == true) ? wDur : 0,
                workouts: workouts
            )
        }
        return map
    }

    // MARK: - Acute/Chronic EWMA Training Load Engine (Cardio & Muscular — Matches Bevel 7-State Breakdown!)

    /// Computes genuine Bevel-style Acute (7d EWMA) vs Chronic (28d EWMA) Cardio or Muscular Training Load
    /// strictly from real recorded workouts, HR zones, active calories, and logged strength sets.
    static func computeTrainingLoadAnalysis(
        tab: TrainingLoadTab,
        history: [String: RealBiometricDaySummary],
        strengthLogs: [StrengthLoggedSet],
        anchorDate: Date,
        spanDays: Int,
        windowPageOffset: Int
    ) -> TrainingLoadAnalysis {
        let cal = Calendar.current
        let anchorStart = cal.startOfDay(for: anchorDate)
        let windowEnd = cal.date(byAdding: .day, value: -(windowPageOffset * spanDays), to: anchorStart) ?? anchorStart
        let windowStart = cal.date(byAdding: .day, value: -(spanDays - 1), to: windowEnd) ?? windowEnd
        // Warmup 42 days prior to windowStart so chronic EWMA & calibration status are causal and smooth
        let warmupDays = 42
        let simStart = cal.date(byAdding: .day, value: -warmupDays, to: windowStart) ?? windowStart
        let totalSimDays = (cal.dateComponents([.day], from: simStart, to: windowEnd).day ?? (spanDays + warmupDays)) + 1

        let isoFmt = DateFormatter()
        isoFmt.locale = Locale(identifier: "en_US_POSIX")
        isoFmt.dateFormat = "yyyy-MM-dd"
        let shortFmt = DateFormatter()
        shortFmt.locale = Locale(identifier: "es_ES")
        shortFmt.dateFormat = spanDays >= 180 ? "MMM yy" : "d MMM"

        let setsByDay = Dictionary(grouping: strengthLogs.filter(\.completed), by: \.dateIso)
        let firstHistoryIso = history.keys.sorted().first ?? isoFmt.string(from: anchorStart)

        let alphaAcute = 2.0 / (7.0 + 1.0)
        let alphaChronic = 2.0 / (28.0 + 1.0)
        var acute = 0.0
        var chronic = 0.0
        var activeDaysSeen = 0
        var anyDataFound = false

        var windowPoints: [TrainingLoadDayPoint] = []
        windowPoints.reserveCapacity(spanDays)

        for offset in 0..<max(totalSimDays, 1) {
            guard let dt = cal.date(byAdding: .day, value: offset, to: simStart) else { continue }
            let iso = isoFmt.string(from: dt)
            let summary = history[iso]

            let dailyStimulus: Double
            if tab == .cardio {
                if let d = summary {
                    let workoutStim = d.workouts.reduce(0.0) { acc, w in
                        acc + Double(w.strainPct) * 0.42
                    }
                    let zoneSum = d.hrZoneMinutes.reduce(0, +)
                    let zoneStim: Double = {
                        guard zoneSum > 0 else { return 0 }
                        let weights = [0.22, 0.48, 0.85, 1.35, 1.95]
                        return d.hrZoneMinutes.prefix(5).enumerated().reduce(0.0) { $0 + Double($1.element) * weights[$1.offset] } * 0.55
                    }()
                    let strainStim = d.strainPct.map { Double($0) * 0.28 } ?? 0
                    dailyStimulus = max(workoutStim, max(zoneStim, strainStim))
                } else {
                    dailyStimulus = 0.0
                }
            } else {
                // Muscular load: real strength workouts (HealthKit / Shortcuts) + logged strength sets & tonnage
                let wkStrengthStim: Double = (summary?.workouts ?? []).reduce(0.0) { acc, w in
                    let isStr = w.categoryLabel.localizedCaseInsensitiveContains("fuerza")
                        || w.title.localizedCaseInsensitiveContains("fuerza")
                        || w.title.localizedCaseInsensitiveContains("strength")
                        || w.title.localizedCaseInsensitiveContains("core")
                    guard isStr else { return acc }
                    let base = max(Double(w.strainPct) * 1.45, Double(w.durationMin) * 0.88)
                    return acc + base
                }
                let daySets = setsByDay[iso] ?? []
                let loggedStim: Double = daySets.isEmpty ? 0.0 : (Double(daySets.count) * 1.85 + daySets.reduce(0.0) { $0 + Double($1.reps) * $1.weightKg } / 260.0)
                let minFallback = (wkStrengthStim == 0 && (summary?.strengthMinutes ?? 0) > 0) ? Double(summary?.strengthMinutes ?? 0) * 0.85 : 0.0
                dailyStimulus = max(wkStrengthStim, max(loggedStim, minFallback))
            }

            if dailyStimulus > 0.5 {
                activeDaysSeen += 1
                anyDataFound = true
            }

            acute = alphaAcute * dailyStimulus + (1.0 - alphaAcute) * acute
            chronic = alphaChronic * dailyStimulus + (1.0 - alphaChronic) * chronic

            let optLow = max((chronic * 0.78).rounded(), chronic > 0.4 ? 1.0 : 0.0)
            let optHigh = max((chronic * 1.32).rounded(), optLow + (chronic > 0.4 ? 1.0 : 0.0))

            let daysSinceFirst: Int = {
                guard let fDt = isoFmt.date(from: firstHistoryIso) else { return 0 }
                return max(cal.dateComponents([.day], from: cal.startOfDay(for: fDt), to: dt).day ?? 0, 0)
            }()

            let state: TrainingLoadState
            if daysSinceFirst < 21 || activeDaysSeen < 5 || chronic < 1.2 {
                state = .calibrating
            } else {
                let ratio = acute / max(chronic, 0.8)
                if ratio < 0.65 {
                    state = .detraining
                } else if ratio < 0.82 && chronic >= 10.0 {
                    state = .peaking
                } else if ratio < 1.02 {
                    state = .maintaining
                } else if ratio <= 1.32 {
                    state = .productive
                } else if tab == .cardio && ratio <= 1.56 {
                    state = .fatigued
                } else {
                    state = .overtraining
                }
            }

            if dt >= windowStart && dt <= windowEnd {
                windowPoints.append(
                    TrainingLoadDayPoint(
                        dateIso: iso,
                        shortDateLabel: shortFmt.string(from: dt).replacingOccurrences(of: ".", with: ""),
                        load: AppleHealthExportImporter.round1(acute),
                        optLow: optLow,
                        optHigh: optHigh,
                        state: state
                    )
                )
            }
        }

        let order = tab == .cardio ? TrainingLoadState.cardioOrder : TrainingLoadState.muscularOrder
        let totalPts = max(windowPoints.count, 1)
        let breakdown: [TrainingLoadBreakdownRow] = order.map { st in
            let cnt = windowPoints.filter { $0.state == st }.count
            let pct = windowPoints.isEmpty ? 0 : Int((Double(cnt) / Double(totalPts) * 100.0).rounded())
            return TrainingLoadBreakdownRow(state: st, days: cnt, percent: pct)
        }

        let latest = windowPoints.last
        let curLoad = Int((latest?.load ?? 0).rounded())
        let optL = Int((latest?.optLow ?? 0).rounded())
        let optH = max(Int((latest?.optHigh ?? 0).rounded()), optL + (anyDataFound ? 1 : 0))
        let peakInWindow = Int(ceil(max(Double(max(curLoad, optH)) * 1.4, (windowPoints.map(\.load).max() ?? 0) * 1.15)))
        let gaugeMax = max(peakInWindow, tab == .cardio ? 6 : 12)

        return TrainingLoadAnalysis(
            tab: tab,
            currentLoad: curLoad,
            currentState: latest?.state ?? .calibrating,
            optimalLow: optL,
            optimalHigh: optH,
            gaugeMax: gaugeMax,
            points: windowPoints,
            breakdown: breakdown,
            hasAnyData: anyDataFound
        )
    }

    // MARK: - 5-Segment Standardized Cohort Evaluators (VO₂ máx. & HRR — Exact Bevel Thresholds)

    static func standardizeVo2Max(_ value: Double, profile: UserPhysiologyProfile) -> StandardizedBandEvaluation {
        let age = profile.effectiveAgeYears
        let isFemale = profile.sex == .female
        let decadeShift = (max(0.0, age - 24.0) / 10.0) * 3.2
        // FRIEND / ACSM / Bevel 5-band thresholds (20-29 Male baseline: 40.1 / 48.0 / 55.2 / 61.8)
        let t1 = AppleHealthExportImporter.round1(max((isFemale ? 33.0 : 40.1) - decadeShift, 18.0))
        let t2 = AppleHealthExportImporter.round1(max((isFemale ? 39.5 : 48.0) - decadeShift, 22.0))
        let t3 = AppleHealthExportImporter.round1(max((isFemale ? 45.2 : 55.2) - decadeShift, 26.0))
        let t4 = AppleHealthExportImporter.round1(max((isFemale ? 51.0 : 61.8) - decadeShift, 30.0))

        let fmt: (Double) -> String = { String(format: "%.1f", locale: Locale(identifier: "es_ES"), $0) }
        let labels = ["<\(fmt(t1))", fmt(t1), fmt(t2), fmt(t3), ">\(fmt(t4))"]

        let segIdx: Int
        let title: String
        let color: Color
        let ptr: Double
        if value < t1 {
            segIdx = 0; title = "Bajo"; color = BevelColors.coralHigh
            ptr = min(max(value / max(t1, 1.0) * 0.19, 0.04), 0.19)
        } else if value < t2 {
            segIdx = 1; title = "Aceptable"; color = BevelColors.amberStart
            ptr = 0.20 + min(max((value - t1) / max(t2 - t1, 1.0), 0), 1) * 0.20
        } else if value < t3 {
            segIdx = 2; title = "Bueno"; color = BevelColors.greenPrimary
            ptr = 0.40 + min(max((value - t2) / max(t3 - t2, 1.0), 0), 1) * 0.20
        } else if value < t4 {
            segIdx = 3; title = "Excelente"; color = BevelColors.bioTeal
            ptr = 0.60 + min(max((value - t3) / max(t4 - t3, 1.0), 0), 1) * 0.20
        } else {
            segIdx = 4; title = "Superior"; color = BevelColors.skyBlue
            ptr = 0.80 + min(max((value - t4) / 10.0, 0), 1) * 0.16
        }

        let ageBand: String = {
            if age < 20 { return "0 - 19" }
            if age < 30 { return "20 - 29" }
            if age < 40 { return "30 - 39" }
            if age < 50 { return "40 - 49" }
            if age < 60 { return "50 - 59" }
            return "60+"
        }()
        let sexWord = isFemale ? "mujeres" : (profile.sex == .male ? "hombres" : "adultos")
        return StandardizedBandEvaluation(
            labels: labels,
            activeSegmentIndex: segIdx,
            categoryTitle: title,
            pointerFraction: ptr,
            cohortSubtitle: "Estandarizado para \(ageBand) \(sexWord)",
            activeColor: color
        )
    }

    static func standardizeHrRecovery(_ bpm: Double, profile: UserPhysiologyProfile) -> StandardizedBandEvaluation {
        let age = profile.effectiveAgeYears
        let ageDrop = max(0.0, age - 29.0) * 0.22
        let t1 = AppleHealthExportImporter.round1(max(15.0 - ageDrop * 0.4, 10.0))
        let t2 = AppleHealthExportImporter.round1(max(32.0 - ageDrop * 0.7, 20.0))
        let t3 = AppleHealthExportImporter.round1(max(40.0 - ageDrop * 0.8, 28.0))
        let t4 = AppleHealthExportImporter.round1(max(49.0 - ageDrop * 0.9, 36.0))

        let fmt: (Double) -> String = { String(format: "%.1f", locale: Locale(identifier: "es_ES"), $0) }
        let labels = ["<\(fmt(t1))", fmt(t1), fmt(t2), fmt(t3), ">\(fmt(t4))"]

        let segIdx: Int
        let title: String
        let color: Color
        let ptr: Double
        if bpm < t1 {
            segIdx = 0; title = "Bajo"; color = BevelColors.coralHigh
            ptr = min(max(bpm / max(t1, 1.0) * 0.19, 0.04), 0.19)
        } else if bpm < t2 {
            segIdx = 1; title = "Aceptable"; color = BevelColors.amberStart
            ptr = 0.20 + min(max((bpm - t1) / max(t2 - t1, 1.0), 0), 1) * 0.20
        } else if bpm < t3 {
            segIdx = 2; title = "Bueno"; color = BevelColors.greenPrimary
            ptr = 0.40 + min(max((bpm - t2) / max(t3 - t2, 1.0), 0), 1) * 0.20
        } else if bpm < t4 {
            segIdx = 3; title = "Excelente"; color = BevelColors.bioTeal
            ptr = 0.60 + min(max((bpm - t3) / max(t4 - t3, 1.0), 0), 1) * 0.20
        } else {
            segIdx = 4; title = "Superior"; color = BevelColors.skyBlue
            ptr = 0.80 + min(max((bpm - t4) / 14.0, 0), 1) * 0.16
        }

        let ageBand: String = {
            if age < 30 { return "0 - 29" }
            if age < 40 { return "30 - 39" }
            if age < 50 { return "40 - 49" }
            if age < 60 { return "50 - 59" }
            return "60+"
        }()
        return StandardizedBandEvaluation(
            labels: labels,
            activeSegmentIndex: segIdx,
            categoryTitle: title,
            pointerFraction: ptr,
            cohortSubtitle: "Estandarizado para \(ageBand)",
            activeColor: color
        )
    }

    // MARK: - 7-Day Rolling Average Multi-Period Trend Analysis (3d / 7d / 14d / 30d / 90d)

    static func computeMultiPeriodTrendRows(
        history: [String: RealBiometricDaySummary],
        anchorDate: Date,
        extractor: (RealBiometricDaySummary) -> Double?
    ) -> [MetricTrendPeriodRow] {
        let cal = Calendar.current
        let isoFmt = DateFormatter()
        isoFmt.locale = Locale(identifier: "en_US_POSIX")
        isoFmt.dateFormat = "yyyy-MM-dd"
        let anchor = cal.startOfDay(for: anchorDate)

        // Extract dated values up to anchorDate across last 120 days
        var dated: [(dayIndex: Int, value: Double)] = []
        for back in (0..<120).reversed() {
            guard let dt = cal.date(byAdding: .day, value: -back, to: anchor) else { continue }
            let iso = isoFmt.string(from: dt)
            if let v = history[iso].flatMap(extractor), v.isFinite {
                dated.append((119 - back, v))
            }
        }

        let periods = [3, 7, 14, 30, 90]
        guard !dated.isEmpty else {
            return periods.map { MetricTrendPeriodRow(id: $0, periodDays: $0, delta: nil, sparklinePoints: []) }
        }

        // Build daily linearly interpolated series across short gaps (<= 14 days) so multi-month gaps never fabricate fake straight lines!
        guard let firstDay = dated.first?.dayIndex, let lastDay = dated.last?.dayIndex else {
            return periods.map { MetricTrendPeriodRow(id: $0, periodDays: $0, delta: nil, sparklinePoints: []) }
        }
        var daily: [Double?] = Array(repeating: nil, count: 120)
        for idx in 0..<dated.count {
            let cur = dated[idx]
            daily[cur.dayIndex] = cur.value
            if idx + 1 < dated.count {
                let nxt = dated[idx + 1]
                let gap = nxt.dayIndex - cur.dayIndex
                if gap > 1 && gap <= 14 {
                    for step in 1..<gap {
                        let frac = Double(step) / Double(gap)
                        daily[cur.dayIndex + step] = cur.value + (nxt.value - cur.value) * frac
                    }
                }
            }
        }

        // 7-day trailing rolling average at each day
        var rolling7: [Double?] = Array(repeating: nil, count: 120)
        for d in firstDay...lastDay {
            let lo = max(firstDay, d - 6)
            let vals = (lo...d).compactMap { daily[$0] }
            if !vals.isEmpty {
                rolling7[d] = vals.reduce(0, +) / Double(vals.count)
            }
        }

        return periods.map { p in
            let endIdx = lastDay
            let startIdx = max(firstDay, endIdx - p)
            let slice = (startIdx...endIdx).compactMap { rolling7[$0] }
            guard slice.count >= 2, let firstV = slice.first, let lastV = slice.last else {
                return MetricTrendPeriodRow(id: p, periodDays: p, delta: nil, sparklinePoints: [])
            }
            let delta = AppleHealthExportImporter.round1(lastV - firstV)
            return MetricTrendPeriodRow(id: p, periodDays: p, delta: delta, sparklinePoints: slice)
        }
    }

    // MARK: - 6-Zone Heart Rate Thresholds (Z0..Z5 Karvonen / Tanaka)

    static func hrZoneRangesBpm(profile: UserPhysiologyProfile, restingHrBpm: Double?) -> [(zone: Int, low: Int, high: Int)] {
        let maxHr = Double(computeMaxHeartRate(profile: profile))
        let rhr = restingHrBpm ?? computePersonalizedNorms(profile: profile).restingHrExpected
        let hrr = max(maxHr - rhr, 45.0)
        let z1Low = Int((rhr + hrr * 0.50).rounded())
        let z2Low = Int((rhr + hrr * 0.60).rounded())
        let z3Low = Int((rhr + hrr * 0.70).rounded())
        let z4Low = Int((rhr + hrr * 0.80).rounded())
        let z5Low = Int((rhr + hrr * 0.90).rounded())
        let zMax = Int(maxHr.rounded())
        return [
            (0, Int(rhr.rounded()), max(z1Low - 1, Int(rhr.rounded()) + 10)),
            (1, z1Low, max(z2Low - 1, z1Low + 5)),
            (2, z2Low, max(z3Low - 1, z2Low + 5)),
            (3, z3Low, max(z4Low - 1, z3Low + 5)),
            (4, z4Low, max(z5Low - 1, z4Low + 5)),
            (5, z5Low, max(zMax, z5Low + 5))
        ]
    }

    // MARK: - 20-Muscle Anatomical Freshness & Load Engine (Zero Fabricated Workouts!)

    static func computeMuscleGroupSnapshots(
        history: [String: RealBiometricDaySummary],
        strengthLogs: [StrengthLoggedSet],
        anchorDate: Date
    ) -> [MuscleGroupSnapshot] {
        let cal = Calendar.current
        let anchorStart = cal.startOfDay(for: anchorDate)
        let isoFmt = DateFormatter()
        isoFmt.locale = Locale(identifier: "en_US_POSIX")
        isoFmt.dateFormat = "yyyy-MM-dd"

        var fatigueMap: [MuscleGroupKind: Double] = [:]
        var setsMap: [MuscleGroupKind: Int] = [:]
        var volMap: [MuscleGroupKind: Double] = [:]
        var trainedCountMap: [MuscleGroupKind: Int] = [:]
        var loadMap: [MuscleGroupKind: Double] = [:]

        // Look back 14 days for physiological freshness decay (48-72h half-life) and 30 days for volume/load
        let setsByDay = Dictionary(grouping: strengthLogs.filter(\.completed), by: \.dateIso)

        for back in 0..<30 {
            guard let dt = cal.date(byAdding: .day, value: -back, to: anchorStart) else { continue }
            let iso = isoFmt.string(from: dt)
            let hoursAgo = Double(back * 24 + 12)
            let decay = exp(-hoursAgo / 56.0) // ~39h half-life (~85-95% recovered after 5 days)
            let loadDecay = exp(-Double(back) / 10.0)

            // 1. Explicit logged strength sets (exact exercise -> muscle mapping!)
            if let daySets = setsByDay[iso] {
                for s in daySets {
                    let vol = Double(s.reps) * max(s.weightKg, 10.0)
                    for m in s.primaryMuscles {
                        setsMap[m, default: 0] += 1
                        volMap[m, default: 0] += vol
                        trainedCountMap[m, default: 0] += 1
                        loadMap[m, default: 0] += (4.5 + vol / 220.0) * loadDecay
                        if back < 14 {
                            fatigueMap[m, default: 0] += (11.5 + min(vol / 180.0, 9.0)) * decay
                        }
                    }
                    for m in s.secondaryMuscles {
                        volMap[m, default: 0] += vol * 0.4
                        trainedCountMap[m, default: 0] += 1
                        loadMap[m, default: 0] += (2.0 + vol / 440.0) * loadDecay
                        if back < 14 {
                            fatigueMap[m, default: 0] += (5.2 + min(vol / 380.0, 4.5)) * decay
                        }
                    }
                }
            }

            // 2. Synced HealthKit / Shortcuts workouts (skip logged strength workouts when explicit setsByDay already accounted for them to avoid 2× fatigue!)
            let hasExplicitStrengthSets = !(setsByDay[iso]?.isEmpty ?? true)
            if let day = history[iso] {
                for w in day.workouts {
                    if hasExplicitStrengthSets && w.categoryLabel == "Fuerza" && (w.totalSets != nil || w.targetMuscles != nil) {
                        continue
                    }
                    let mapping = inferMusclesForWorkout(w)
                    let baseStim = max(Double(w.strainPct) * 1.15, Double(w.durationMin) * 0.65)
                    for m in mapping.primary {
                        trainedCountMap[m, default: 0] += 1
                        loadMap[m, default: 0] += baseStim * 0.45 * loadDecay
                        if back < 14 {
                            fatigueMap[m, default: 0] += baseStim * 1.05 * decay
                        }
                    }
                    for m in mapping.secondary {
                        trainedCountMap[m, default: 0] += 1
                        loadMap[m, default: 0] += baseStim * 0.22 * loadDecay
                        if back < 14 {
                            fatigueMap[m, default: 0] += baseStim * 0.48 * decay
                        }
                    }
                }
            }
        }

        return MuscleGroupKind.allCases.map { muscle in
            let trained = trainedCountMap[muscle, default: 0] > 0
            let rawFatigue = fatigueMap[muscle, default: 0]
            let freshness = min(max(Int((100.0 - min(rawFatigue, 88.0)).rounded()), 12), 100)
            let state: MuscleFreshnessState
            if !trained {
                state = .calibrating
            } else if freshness >= 80 {
                state = .recovered
            } else if freshness >= 45 {
                state = .fatigued
            } else {
                state = .exhausted
            }
            return MuscleGroupSnapshot(
                muscle: muscle,
                freshnessPct: trained ? freshness : 100,
                state: state,
                recentSets: setsMap[muscle, default: 0],
                recentVolumeKg: AppleHealthExportImporter.round1(volMap[muscle, default: 0]),
                loadScore: Int(loadMap[muscle, default: 0].rounded())
            )
        }
    }

    static func inferMusclesForWorkout(_ w: EffortEventItem) -> (primary: [MuscleGroupKind], secondary: [MuscleGroupKind]) {
        if let explicit = w.targetMuscles, !explicit.isEmpty {
            let parsed = explicit.compactMap { MuscleGroupKind(rawValue: $0) }
            if !parsed.isEmpty { return (parsed, []) }
        }
        let low = "\(w.title) \(w.categoryLabel)".lowercased()
        if low.contains("pierna") || low.contains("inferior") || low.contains("sentadilla") {
            return ([.cuadriceps, .gluteos, .isquiotibiales], [.pantorrillas, .abdominales, .lumbares])
        }
        if low.contains("empuje") || low.contains("pecho") || low.contains("push") {
            return ([.pectorales, .triceps, .hombros], [.abdominales])
        }
        if low.contains("tirón") || low.contains("espalda") || low.contains("pull") {
            return ([.dorsales, .espaldaAlta, .biceps], [.antebrazo, .trapecio])
        }
        if low.contains("fuerza") || low.contains("strength") {
            return ([.pectorales, .dorsales, .triceps], [.hombros, .abdominales])
        }
        if low.contains("bici") || low.contains("ciclismo") || low.contains("cycling") {
            return ([.cuadriceps, .gluteos, .pantorrillas], [.isquiotibiales, .flexoresCadera])
        }
        if low.contains("carrera") || low.contains("run") || low.contains("caminat") || low.contains("hiit") {
            return ([.cuadriceps, .pantorrillas, .isquiotibiales], [.gluteos, .flexoresCadera, .abdominales])
        }
        if low.contains("nataci") || low.contains("swim") || low.contains("remo") || low.contains("row") {
            return ([.dorsales, .hombros, .espaldaAlta], [.abdominales, .triceps, .biceps])
        }
        if low.contains("core") || low.contains("abdom") || low.contains("pilates") {
            return ([.abdominales, .oblicuos], [.lumbares, .flexoresCadera])
        }
        return ([.cuadriceps, .gluteos], [.abdominales, .pantorrillas])
    }

    // MARK: - Apartado 1.1: Strength Builder Progressive Overload, PR & 1RM Engine

    static func computeExercisePerformanceSnapshot(
        exerciseName: String,
        logs: [StrengthLoggedSet],
        recoveryPct: Int,
        deloadActive: Bool = false
    ) -> ExercisePerformanceSnapshot {
        let key = exerciseName.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES")).trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = logs.filter {
            $0.completed &&
            $0.setKind != .warmup &&
            $0.exercise.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES")).trimmingCharacters(in: .whitespacesAndNewlines) == key
        }
        let catalogDefault = StrengthCatalogExercise.all.first {
            $0.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES")) == key
        }

        guard !matching.isEmpty else {
            let defW = catalogDefault?.defaultWeightKg ?? 40.0
            let defR = catalogDefault?.defaultReps ?? 10
            return ExercisePerformanceSnapshot(
                exerciseName: exerciseName,
                lastDateIso: nil,
                lastWeightKg: nil,
                lastReps: nil,
                bestWeightKg: 0,
                bestOneRepMaxKg: 0,
                totalHistoricalSets: 0,
                suggestedWeightKg: defW,
                suggestedReps: defR,
                progressionBadge: "Base inicial",
                progressionAdvice: "Primer registro de este ejercicio: empieza con \(Int(defW)) kg × \(defR) reps a RIR 2."
            )
        }

        let sortedByDate = matching.sorted { $0.dateIso > $1.dateIso }
        let latestIso = sortedByDate.first?.dateIso
        let latestSessionSets = sortedByDate.filter { $0.dateIso == latestIso }
        let topLastSet = latestSessionSets.max(by: { $0.estimatedOneRepMaxKg < $1.estimatedOneRepMaxKg }) ?? sortedByDate[0]
        let bestWeight = matching.map(\.weightKg).max() ?? topLastSet.weightKg
        let best1RM = AppleHealthExportImporter.round1(matching.map(\.estimatedOneRepMaxKg).max() ?? topLastSet.estimatedOneRepMaxKg)

        var sugW = topLastSet.weightKg
        var sugR = topLastSet.reps
        let badge: String
        let advice: String

        if deloadActive {
            sugW = max(0, (topLastSet.weightKg * 0.85 / 2.5).rounded() * 2.5)
            badge = "Descarga −15%"
            advice = "Modo descarga activo: reduce carga a \(String(format: "%.1f", locale: Locale(identifier: "es_ES"), sugW)) kg × \(sugR) reps para disipar fatiga neuromuscular."
        } else if recoveryPct >= 67 {
            if topLastSet.weightKg > 0 {
                sugW = topLastSet.weightKg + 2.5
                badge = "Sobrecarga +2,5 kg"
                advice = "Recuperación óptima (\(recoveryPct)%): sube de \(Int(topLastSet.weightKg)) kg a \(String(format: "%.1f", locale: Locale(identifier: "es_ES"), sugW)) kg o añade +1 rep para superar tu 1RM (\(String(format: "%.1f", locale: Locale(identifier: "es_ES"), best1RM)) kg)."
            } else {
                sugR = topLastSet.reps + 2
                badge = "Sobrecarga +2 reps"
                advice = "Recuperación óptima (\(recoveryPct)%): busca \(sugR) repeticiones (+2 vs última sesión)."
            }
        } else if recoveryPct >= 34 {
            badge = "Consolidar (+1 rep)"
            sugR = min(topLastSet.reps + 1, 20)
            advice = "Recuperación moderada (\(recoveryPct)%): mantén \(Int(topLastSet.weightKg)) kg e intenta \(sugR) reps limpias."
        } else {
            sugW = max(0, (topLastSet.weightKg * 0.90 / 2.5).rounded() * 2.5)
            badge = "Protección −10%"
            advice = "Recuperación baja (\(recoveryPct)%): prioriza técnica con \(String(format: "%.1f", locale: Locale(identifier: "es_ES"), sugW)) kg (RPE ≤ 7)."
        }

        return ExercisePerformanceSnapshot(
            exerciseName: exerciseName,
            lastDateIso: latestIso,
            lastWeightKg: topLastSet.weightKg,
            lastReps: topLastSet.reps,
            bestWeightKg: bestWeight,
            bestOneRepMaxKg: best1RM,
            totalHistoricalSets: matching.count,
            suggestedWeightKg: sugW,
            suggestedReps: sugR,
            progressionBadge: badge,
            progressionAdvice: advice
        )
    }

    // MARK: - Apartado 1.2 & 1.5: Caffeine Half-Life (5h) & Meal-to-Bedtime / Fasting Window Engine

    static func parseTimeLabelToMinutes(_ label: String) -> Int? {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ":")
        guard parts.count >= 2,
              let h = Int(parts[0].filter(\.isNumber)),
              let m = Int(parts[1].prefix(2).filter(\.isNumber)),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return h * 60 + m
    }

    static func computeCaffeineAndMealTiming(
        meals: [NutritionMealItem],
        bedtimeMinutesOfDay: Int = 23 * 60,
        manualCaffeineMg: Double? = nil,
        manualCaffeineTime: String? = nil
    ) -> CaffeineAndMealTimingSnapshot {
        // Half-life T_1/2 = 5.0 hours (300 minutes)
        let halfLifeMin = 300.0
        let bedAdj = bedtimeMinutesOfDay < 360 ? bedtimeMinutesOfDay + 1440 : bedtimeMinutesOfDay

        var totalCaff = 0.0
        var residualAtBed = 0.0
        var latestCaffMin: Int? = nil
        var latestCaffLabel: String? = nil

        var mealMinutes: [(min: Int, label: String)] = []

        for m in meals {
            let tMin = parseTimeLabelToMinutes(m.timeLabel)
            if let tm = tMin, m.kcal >= 40 {
                mealMinutes.append((tm, m.timeLabel))
            }
            if let c = m.caffeineMg, c > 0 {
                totalCaff += c
                let intakeMin = tMin ?? (10 * 60)
                let elapsedMin = Double(max(bedAdj - intakeMin, 30))
                residualAtBed += c * pow(0.5, elapsedMin / halfLifeMin)
                if latestCaffMin == nil || intakeMin > (latestCaffMin ?? 0) {
                    latestCaffMin = intakeMin
                    latestCaffLabel = m.timeLabel
                }
            }
        }

        if totalCaff == 0, let manC = manualCaffeineMg, manC > 0 {
            totalCaff = manC
            let intakeMin = manualCaffeineTime.flatMap(parseTimeLabelToMinutes) ?? (14 * 60)
            let elapsedMin = Double(max(bedAdj - intakeMin, 30))
            residualAtBed = manC * pow(0.5, elapsedMin / halfLifeMin)
            latestCaffLabel = manualCaffeineTime ?? "14:00"
        }

        let sortedMeals = mealMinutes.sorted { $0.min < $1.min }
        let firstMeal = sortedMeals.first
        let lastMeal = sortedMeals.last

        let eatingWindowH: Double? = {
            guard let f = firstMeal, let l = lastMeal, l.min >= f.min else { return nil }
            return AppleHealthExportImporter.round1(Double(l.min - f.min) / 60.0)
        }()
        let fastingH: Double? = eatingWindowH.map { AppleHealthExportImporter.round1(max(24.0 - $0, 8.0)) }
        let mealToBedH: Double? = lastMeal.map { l in
            let diffMin = max(bedAdj - l.min, 0)
            return AppleHealthExportImporter.round1(Double(diffMin) / 60.0)
        }

        let rBedCaff = AppleHealthExportImporter.round1(residualAtBed)
        let isCaffClear = rBedCaff <= 35.0

        var summaryParts: [String] = []
        if totalCaff > 0 {
            summaryParts.append(isCaffClear
                ? "Cafeína al dormir: \(Int(rBedCaff)) mg (óptimo ≤35 mg)"
                : "Alerta cafeína: ~\(Int(rBedCaff)) mg activos al acostarte")
        }
        if let gap = mealToBedH {
            summaryParts.append(gap >= 2.8
                ? "Última comida \(String(format: "%.1f", locale: Locale(identifier: "es_ES"), gap)) h antes de dormir (óptimo)"
                : "Cena cercana al sueño (\(String(format: "%.1f", locale: Locale(identifier: "es_ES"), gap)) h antes)")
        }
        if let fast = fastingH, let win = eatingWindowH, sortedMeals.count >= 2 {
            summaryParts.append("Ayuno \(Int(fast.rounded())):\(Int(win.rounded()))")
        }

        return CaffeineAndMealTimingSnapshot(
            totalCaffeineTodayMg: AppleHealthExportImporter.round1(totalCaff),
            lastCaffeineTimeLabel: latestCaffLabel,
            estimatedCaffeineAtBedtimeMg: rBedCaff,
            caffeineClearForSleep: isCaffClear,
            firstMealTimeLabel: firstMeal?.label,
            lastMealTimeLabel: lastMeal?.label,
            eatingWindowHours: eatingWindowH,
            fastingHours: fastingH,
            hoursFromLastMealToBedtime: mealToBedH,
            statusSummary: summaryParts.isEmpty ? "Sin cafeína ni cenas tardías registradas hoy" : summaryParts.joined(separator: " · ")
        )
    }

    // MARK: - Apartado 1.7: Sleep Onset Latency & Circadian Midpoint Alignment Engine

    static func computeCircadianAndLatency(
        currentDay: RealBiometricDaySummary?,
        recentSessions: [SleepSessionDetail]
    ) -> CircadianAndLatencySnapshot {
        let sess = currentDay?.sleepSession
        let latencyOpt: Int? = {
            guard let d = currentDay, let inBed = d.inBedMinutes, let asleep = d.asleepMinutes, inBed > asleep else {
                if let awake = sess?.awakeSeconds, awake > 120 {
                    return min(max(Int((Double(awake) / 60.0 * 0.38).rounded()), 5), 45)
                }
                return nil
            }
            let totalGap = max(inBed - asleep, 4)
            let awakeMin = (sess?.awakeSeconds ?? 0) / 60
            let onset = awakeMin > 0 && totalGap > awakeMin ? (totalGap - awakeMin / 2) : Int((Double(totalGap) * 0.45).rounded())
            return min(max(onset, 4), 75)
        }()

        let latStatus: String = {
            guard let lat = latencyOpt else { return "Sin datos" }
            if lat < 8 { return "Muy rápida (posible deuda)" }
            if lat <= 22 { return "Óptima (8–22 min)" }
            if lat <= 35 { return "Moderada" }
            return "Prolongada (>35 min)"
        }()

        func midpointMinutes(_ s: SleepSessionDetail) -> Int? {
            guard let start = s.startTimeLabel.flatMap(parseTimeLabelToMinutes),
                  let end = s.endTimeLabel.flatMap(parseTimeLabelToMinutes) else { return nil }
            let adjStart = start < 720 ? start + 1440 : start
            let adjEnd = end < adjStart ? end + 1440 : end
            return ((adjStart + adjEnd) / 2) % 1440
        }

        func formatMinutes(_ m: Int) -> String {
            let norm = ((m % 1440) + 1440) % 1440
            return String(format: "%02d:%02d", norm / 60, norm % 60)
        }

        let validMidpoints = recentSessions.compactMap(midpointMinutes)
        let currentMid = sess.flatMap(midpointMinutes)

        var alignPct: Int? = nil
        var devMin: Int? = nil
        var typLabel: String? = nil
        var curLabel: String? = currentMid.map(formatMinutes)

        if validMidpoints.count >= 2, let curM = currentMid {
            // Circular-safe average around midnight (00:00..06:00)
            let shifted = validMidpoints.map { $0 > 720 ? $0 - 1440 : $0 }
            let avgShifted = Int((Double(shifted.reduce(0, +)) / Double(shifted.count)).rounded())
            let curShifted = curM > 720 ? curM - 1440 : curM
            let diff = abs(curShifted - avgShifted)
            devMin = diff
            typLabel = formatMinutes(avgShifted)
            let score = 100.0 * exp(-Double(diff) / 85.0)
            alignPct = min(max(Int(score.rounded()), 15), 100)
        }

        let summary: String = {
            if let a = alignPct, let d = devMin, let typ = typLabel {
                return "Alineación circadiana \(a)% (desviación \(d) min vs punto medio habitual \(typ))"
            }
            if let lat = latencyOpt {
                return "Latencia estimada para conciliar el sueño: \(lat) min (\(latStatus))"
            }
            return "Registra varias noches con horario para calibrar tu ritmo circadiano."
        }()

        return CircadianAndLatencySnapshot(
            estimatedLatencyMinutes: latencyOpt,
            latencyStatus: latStatus,
            alignmentPct: alignPct,
            midpointDeviationMinutes: devMin,
            typicalMidpointLabel: typLabel,
            lastNightMidpointLabel: curLabel,
            summaryText: summary
        )
    }

    // MARK: - Apartado 1.8: Menstrual Cycle Phase & Luteal Physiological Calibration Engine

    static func computeCyclePhase(
        settings: CycleTrackingSettings,
        referenceDate: Date = Date()
    ) -> CyclePhaseSnapshot? {
        guard settings.isEnabled,
              !settings.lastPeriodStartIso.isEmpty,
              let startDt = AppFormatters.isoDay.date(from: settings.lastPeriodStartIso) else {
            return nil
        }
        let cal = Calendar.current
        let cycleLen = min(max(settings.cycleLengthDays, 21), 38)
        let periodLen = min(max(settings.periodDurationDays, 3), 8)
        let rawDays = cal.dateComponents([.day], from: cal.startOfDay(for: startDt), to: cal.startOfDay(for: referenceDate)).day ?? 0
        let dayOfCycle = ((rawDays % cycleLen) + cycleLen) % cycleLen + 1
        let daysUntilNext = max(cycleLen - dayOfCycle + 1, 1)
        let ovulationDay = max(cycleLen - 14, periodLen + 3)

        let phase: MenstrualCyclePhase
        let tempShift: Double
        let trainAdv: String
        let nutAdv: String
        let lutealCal: Bool

        if dayOfCycle <= periodLen {
            phase = .menstrual
            tempShift = 0.0
            lutealCal = false
            trainAdv = "Fase menstrual (Día \(dayOfCycle)): hormonas en nivel basal. Buena tolerancia a fuerza moderada y Zona 2; escucha tu energía."
            nutAdv = "Prioriza hierro biodisponible, vitamina C, magnesio y omega-3 antiinflamatorio."
        } else if dayOfCycle < ovulationDay - 1 {
            phase = .follicular
            tempShift = -0.05
            lutealCal = false
            trainAdv = "Fase folicular (Día \(dayOfCycle)): máxima sensibilidad a la insulina y recuperación rápida. Ideal para PRs de fuerza y HIIT."
            nutAdv = "Aprovecha mayor tolerancia a carbohidratos complejos peri-entreno y proteína alta."
        } else if dayOfCycle <= ovulationDay + 1 {
            phase = .ovulatory
            tempShift = 0.10
            lutealCal = false
            trainAdv = "Fase ovulatoria (Día \(dayOfCycle)): pico de fuerza máxima. Cuida calentamiento articular y estabilidad de rodilla/hombro."
            nutAdv = "Mantén hidratación alta (+400 ml) y antioxidantes naturales."
        } else {
            phase = .luteal
            tempShift = 0.32
            lutealCal = true
            trainAdv = "Fase lútea (Día \(dayOfCycle)): progesterona alta eleva tu temperatura basal (+\(String(format: "%.2f", locale: Locale(identifier: "es_ES"), tempShift)) °C) y FCR. Prioriza Zona 2 y controla el RPE."
            nutAdv = "Tu gasto basal sube ~100–200 kcal/día: prioriza proteína, fibra, magnesio y electrolitos antes de dormir."
        }

        return CyclePhaseSnapshot(
            phase: phase,
            dayOfCycle: dayOfCycle,
            cycleLengthDays: cycleLen,
            daysUntilNextPeriod: daysUntilNext,
            expectedTempShiftC: tempShift,
            trainingAdvice: trainAdv,
            nutritionAdvice: nutAdv,
            isLutealCalibrationActive: lutealCal
        )
    }

    // MARK: - Apartado 2.2: Predictive Overtraining & Auto-Deload Engine

    static func computeOvertrainingDeloadAssessment(
        recentDays: [RealBiometricDaySummary],
        acwr: Double,
        deloadModeActive: Bool = false
    ) -> OvertrainingDeloadAssessment {
        let sorted = recentDays.sorted { $0.dateIso < $1.dateIso }
        let last3Hrv = sorted.suffix(4).compactMap(\.hrvMs)
        var hrvSlope = 0.0
        if last3Hrv.count >= 3 {
            let n = last3Hrv.count
            hrvSlope = AppleHealthExportImporter.round1((last3Hrv[n - 1] - last3Hrv[0]) / Double(max(n - 1, 1)))
        }

        let recentWorkouts = sorted.suffix(7).flatMap(\.workouts)
        let rpeValues = recentWorkouts.compactMap(\.rpe)
        let avgRpe = rpeValues.isEmpty ? 7.0 : AppleHealthExportImporter.round1(Double(rpeValues.reduce(0, +)) / Double(rpeValues.count))
        let latestDebt = sorted.last?.sleepDebtMinutes ?? 0

        var triggers: [String] = []
        var score = 0

        if acwr > 1.32 {
            score += 2
            triggers.append(String(format: "Ratio Agudo/Crónico alto (ACWR %.2f > 1,30)", locale: Locale(identifier: "es_ES"), acwr))
        } else if acwr > 1.18 {
            score += 1
            triggers.append(String(format: "Carga aguda creciente (ACWR %.2f)", locale: Locale(identifier: "es_ES"), acwr))
        }

        if last3Hrv.count >= 3 && hrvSlope <= -2.2 {
            score += 2
            triggers.append(String(format: "VFC descendente 3 noches (%+.1f ms/día)", locale: Locale(identifier: "es_ES"), hrvSlope))
        }

        if avgRpe >= 8.4 && rpeValues.count >= 2 {
            score += 1
            triggers.append(String(format: "RPE medio exigente (%.1f/10)", locale: Locale(identifier: "es_ES"), avgRpe))
        }

        if latestDebt >= 75 {
            score += 1
            triggers.append("Deuda de sueño acumulada (\(latestDebt) min)")
        }

        let riskLevel: Int
        let title: String
        let rec: String
        if deloadModeActive {
            riskLevel = 2
            title = "Semana de Descarga Activa (−15%)"
            rec = "El modo Auto-Deload está protegiendo tu sistema nervioso: las cargas del Strength Builder y tu objetivo de esfuerzo se han reducido un 15% para supercompensar."
        } else if score >= 3 {
            riskLevel = 2
            title = "Descarga Recomendada (Riesgo de Sobreentrenamiento)"
            rec = "Se acumulan señales de fatiga neuromuscular y autónoma. Activa la Semana de Descarga (−15% peso/esfuerzo durante 4–5 días) para evitar estancamiento o lesión."
        } else if score >= 1 {
            riskLevel = 1
            title = "Carga Exigente en Vigilancia"
            rec = "Tu carga de entrenamiento es alta pero asimilable si mantienes el sueño al 100% y moderas el RPE en sesiones accesorias."
        } else {
            riskLevel = 0
            title = "Asimilación Neuromuscular Óptima"
            rec = "Equilibrio agudo/crónico saludable y VFC estable: tienes vía libre para aplicar sobrecarga progresiva."
        }

        return OvertrainingDeloadAssessment(
            riskLevel: riskLevel,
            statusTitle: title,
            acwr: AppleHealthExportImporter.round1(acwr),
            hrv3DaySlopeMs: hrvSlope,
            recentAvgRpe: avgRpe,
            triggers: triggers,
            recommendation: rec,
            deloadWeightFactor: (deloadModeActive || riskLevel == 2) ? 0.85 : 1.0
        )
    }

    // MARK: - Apartado 2.1: Unified Cross-Domain Causal Engine (Nutrition + Blood + Strength + Sleep D -> D+1)

    static func computeUnifiedCausalInsights(
        history: [String: RealBiometricDaySummary],
        mealsByDate: [String: [NutritionMealItem]],
        strengthLogs: [StrengthLoggedSet],
        labReports: [LabReportRecord],
        profile: UserPhysiologyProfile,
        weather: WeatherPhysiologySnapshot? = nil
    ) -> [UnifiedCausalInsight] {
        let sortedIsos = history.keys.sorted()
        let cal = Calendar.current
        var insights: [UnifiedCausalInsight] = []

        func nextDaySummary(after iso: String) -> RealBiometricDaySummary? {
            guard let dt = AppFormatters.isoDay.date(from: iso),
                  let nextDt = cal.date(byAdding: .day, value: 1, to: dt) else { return nil }
            let nextIso = AppFormatters.isoDay.string(from: nextDt)
            return history[nextIso]
        }

        // 1. Protein adequacy (D) -> Next-Day Recovery & HRV (D+1), Dinner timing -> Deep Sleep & RHR, Caffeine -> Deep Sleep & HRV, Nutrition Quality -> Stress
        let targetProt = Int((profile.weightKg * 1.65).rounded())
        var highProtRec: [Double] = []
        var lowProtRec: [Double] = []
        var highProtHrv: [Double] = []
        var lowProtHrv: [Double] = []
        var earlyMealDeep: [Double] = []
        var lateMealDeep: [Double] = []
        var earlyMealRhr: [Double] = []
        var lateMealRhr: [Double] = []
        var cleanCaffHrv: [Double] = []
        var lateCaffHrv: [Double] = []
        var cleanCaffRec: [Double] = []
        var lateCaffRec: [Double] = []
        var highQualStress: [Double] = []
        var lowQualStress: [Double] = []

        for (iso, rawMeals) in mealsByDate where !rawMeals.isEmpty {
            let foodMeals = rawMeals.filter { !($0.kcal == 0 && $0.proteinG == 0 && $0.carbsG == 0 && $0.fatG == 0 && ($0.caffeineMg ?? 0) > 0) }
            guard let nextDay = nextDaySummary(after: iso) else { continue }
            let totalProt = foodMeals.reduce(0) { $0 + $1.proteinG }
            if !foodMeals.isEmpty {
                if let rec = nextDay.recoveryPct {
                    if totalProt >= targetProt { highProtRec.append(Double(rec)) }
                    else { lowProtRec.append(Double(rec)) }
                }
                if let hrv = nextDay.hrvMs, hrv > 2 {
                    if totalProt >= targetProt { highProtHrv.append(hrv) }
                    else { lowProtHrv.append(hrv) }
                }
                let totalKcal = max(foodMeals.reduce(0) { $0 + max($1.kcal, 50) }, 1)
                let avgScore = foodMeals.reduce(0.0) { $0 + Double($1.qualityScore) * Double(max($1.kcal, 50)) } / Double(totalKcal)
                if let st = history[iso]?.stressScore ?? nextDay.stressScore {
                    if avgScore >= 75.0 { highQualStress.append(Double(st)) }
                    else if avgScore < 65.0 { lowQualStress.append(Double(st)) }
                }
            }

            let timing = computeCaffeineAndMealTiming(meals: rawMeals)
            if let gap = timing.hoursFromLastMealToBedtime {
                if let deepSec = nextDay.sleepSession?.deepSeconds ?? nextDay.deepMinutes.map({ $0 * 60 }) {
                    let deepMin = Double(deepSec) / 60.0
                    if gap >= 2.8 { earlyMealDeep.append(deepMin) }
                    else { lateMealDeep.append(deepMin) }
                }
                if let rhr = nextDay.restingHrBpm, rhr > 25 {
                    if gap >= 2.8 { earlyMealRhr.append(rhr) }
                    else { lateMealRhr.append(rhr) }
                }
            }

            if timing.totalCaffeineTodayMg > 0 {
                let isClean = timing.estimatedCaffeineAtBedtimeMg <= 25.0
                if let hrv = nextDay.hrvMs, hrv > 2 {
                    if isClean { cleanCaffHrv.append(hrv) }
                    else { lateCaffHrv.append(hrv) }
                }
                if let rec = nextDay.recoveryPct {
                    if isClean { cleanCaffRec.append(Double(rec)) }
                    else { lateCaffRec.append(Double(rec)) }
                }
            }
        }

        if highProtRec.count >= 2 && lowProtRec.count >= 2 {
            let avgH = highProtRec.reduce(0, +) / Double(highProtRec.count)
            let avgL = lowProtRec.reduce(0, +) / Double(lowProtRec.count)
            let diff = Int((avgH - avgL).rounded())
            if abs(diff) >= 2 {
                var extraHrv = ""
                if highProtHrv.count >= 2 && lowProtHrv.count >= 2 {
                    let hDiff = AppleHealthExportImporter.round1((highProtHrv.reduce(0, +) / Double(highProtHrv.count)) - (lowProtHrv.reduce(0, +) / Double(lowProtHrv.count)))
                    if abs(hDiff) >= 1.0 {
                        extraHrv = String(format: " y tu VFC varía %+.1f ms", locale: Locale(identifier: "es_ES"), hDiff)
                    }
                }
                insights.append(UnifiedCausalInsight(
                    id: "cross_protein_recovery",
                    categoryBadge: "NUTRICIÓN → RECUPERACIÓN (D+1)",
                    icon: "fork.knife",
                    title: "Proteína ≥ \(targetProt) g y Recuperación al día siguiente",
                    impactBadge: String(format: "%+d%% Rec.", diff),
                    isPositive: diff >= 0,
                    detail: "En tus días alcanzando ≥\(targetProt) g de proteína, tu Recuperación del día siguiente promedia \(Int(avgH.rounded()))% frente a \(Int(avgL.rounded()))%\(extraHrv).",
                    sampleDays: highProtRec.count + lowProtRec.count
                ))
            }
        }

        if earlyMealDeep.count >= 2 && lateMealDeep.count >= 2 {
            let avgE = earlyMealDeep.reduce(0, +) / Double(earlyMealDeep.count)
            let avgL = lateMealDeep.reduce(0, +) / Double(lateMealDeep.count)
            let diff = Int((avgE - avgL).rounded())
            if abs(diff) >= 3 {
                var extraRhr = ""
                if earlyMealRhr.count >= 2 && lateMealRhr.count >= 2 {
                    let rDiff = AppleHealthExportImporter.round1((earlyMealRhr.reduce(0, +) / Double(earlyMealRhr.count)) - (lateMealRhr.reduce(0, +) / Double(lateMealRhr.count)))
                    if abs(rDiff) >= 0.8 {
                        extraRhr = String(format: " (FCR nocturna %+.1f ppm)", locale: Locale(identifier: "es_ES"), rDiff)
                    }
                }
                insights.append(UnifiedCausalInsight(
                    id: "cross_meal_timing_deep",
                    categoryBadge: "CENA → SUEÑO PROFUNDO (D+1)",
                    icon: "moon.stars.fill",
                    title: "Cenar ≥ 3 h antes de dormir vs Sueño Profundo",
                    impactBadge: String(format: "%+d min", diff),
                    isPositive: diff >= 0,
                    detail: "Dejar al menos 2,8–3 h de digestión antes de acostarte se asocia con \(Int(avgE.rounded())) min de sueño profundo frente a \(Int(avgL.rounded())) min en cenas tardías\(extraRhr).",
                    sampleDays: earlyMealDeep.count + lateMealDeep.count
                ))
            }
        }

        if cleanCaffHrv.count >= 2 && lateCaffHrv.count >= 2 {
            let avgC = cleanCaffHrv.reduce(0, +) / Double(cleanCaffHrv.count)
            let avgL = lateCaffHrv.reduce(0, +) / Double(lateCaffHrv.count)
            let diff = AppleHealthExportImporter.round1(avgC - avgL)
            if abs(diff) >= 1.5 {
                var recBit = ""
                if cleanCaffRec.count >= 2 && lateCaffRec.count >= 2 {
                    let avgCleanRec = cleanCaffRec.reduce(0, +) / Double(cleanCaffRec.count)
                    let avgLateRec = lateCaffRec.reduce(0, +) / Double(lateCaffRec.count)
                    let rDiff = Int((avgCleanRec - avgLateRec).rounded())
                    if abs(rDiff) >= 2 {
                        recBit = String(format: " (%+d%% Recuperación)", rDiff)
                    }
                }
                let avgCStr = String(format: "%.1f", locale: Locale(identifier: "es_ES"), avgC)
                let avgLStr = String(format: "%.1f", locale: Locale(identifier: "es_ES"), avgL)
                insights.append(UnifiedCausalInsight(
                    id: "cross_caffeine_hrv",
                    categoryBadge: "CAFEÍNA → VFC NOCTURNA (D+1)",
                    icon: "cup.and.saucer.fill",
                    title: "Acostarte con <25 mg de cafeína residual",
                    impactBadge: String(format: "%+.1f ms VFC", locale: Locale(identifier: "es_ES"), diff),
                    isPositive: diff >= 0,
                    detail: "Cuando llegas a dormir con cafeína residual baja, tu VFC nocturna promedia \(avgCStr) ms frente a \(avgLStr) ms con cafeína tardía\(recBit).",
                    sampleDays: cleanCaffHrv.count + lateCaffHrv.count
                ))
            }
        }

        if highQualStress.count >= 2 && lowQualStress.count >= 2 {
            let avgH = highQualStress.reduce(0, +) / Double(highQualStress.count)
            let avgL = lowQualStress.reduce(0, +) / Double(lowQualStress.count)
            let diff = Int((avgH - avgL).rounded())
            if abs(diff) >= 3 {
                insights.append(UnifiedCausalInsight(
                    id: "cross_quality_stress",
                    categoryBadge: "CALIDAD NUTRICIONAL → ESTRÉS",
                    icon: "leaf.fill",
                    title: "Comida real (calidad ≥75) y Estrés diario",
                    impactBadge: String(format: "%+d pts Estrés", diff),
                    isPositive: diff <= 0,
                    detail: "Los días con puntuación nutricional ≥75 tu estrés medio es \(Int(avgH.rounded()))/100 frente a \(Int(avgL.rounded()))/100 cuando bajas de 65.",
                    sampleDays: highQualStress.count + lowQualStress.count
                ))
            }
        }

        // 2. Zone 2 Aerobic Sessions (D) -> Next-Day HRV (D+1)
        var z2Hrv: [Double] = []
        var noZ2Hrv: [Double] = []
        for iso in sortedIsos {
            guard let day = history[iso], let nextDay = nextDaySummary(after: iso), let nextHrv = nextDay.hrvMs else { continue }
            let zm = day.hrZoneMinutes
            let z2Min = (zm.count > 0 ? zm[0] : 0) + (zm.count > 1 ? zm[1] : 0)
            if z2Min >= 25 { z2Hrv.append(nextHrv) }
            else { noZ2Hrv.append(nextHrv) }
        }
        if z2Hrv.count >= 2 && noZ2Hrv.count >= 2 {
            let avgZ = z2Hrv.reduce(0, +) / Double(z2Hrv.count)
            let avgN = noZ2Hrv.reduce(0, +) / Double(noZ2Hrv.count)
            let diff = AppleHealthExportImporter.round1(avgZ - avgN)
            if abs(diff) >= 1.0 {
                insights.append(UnifiedCausalInsight(
                    id: "cross_zone2_hrv",
                    categoryBadge: "CARDIO ZONA 2 → VFC (D+1)",
                    icon: "figure.run",
                    title: "Sesiones en Zona 2 (≥25 min) y tono vagal",
                    impactBadge: String(format: "%+.1f ms VFC", locale: Locale(identifier: "es_ES"), diff),
                    isPositive: diff >= 0,
                    detail: "Tras días con ≥25 min aeróbicos en Zona 1–2, tu VFC nocturna promedia \(String(format: "%.1f", locale: Locale(identifier: "es_ES"), avgZ)) ms frente a \(String(format: "%.1f", locale: Locale(identifier: "es_ES"), avgN)) ms.",
                    sampleDays: z2Hrv.count + noZ2Hrv.count
                ))
            }
        }

        // 3. Blood Biomarkers × Biometrics & Nutrition cross-insight (multi-marker clinical correlation)
        if let latestLab = labReports.sorted(by: { $0.dateIso > $1.dateIso }).first, !latestLab.biomarkers.isEmpty {
            let recent14 = sortedIsos.suffix(14).compactMap { history[$0] }
            let hrvVals14 = recent14.compactMap(\.hrvMs)
            let rhrVals14 = recent14.compactMap(\.restingHrBpm)
            let avgHrv14: Double? = hrvVals14.isEmpty ? nil : (hrvVals14.reduce(0, +) / Double(hrvVals14.count))
            let avgRhr14: Double? = rhrVals14.isEmpty ? nil : (rhrVals14.reduce(0, +) / Double(rhrVals14.count))
            let outOfRange = latestLab.biomarkers.filter { $0.status != .normal }
            var bioBits: [String] = []
            if let h = avgHrv14 { bioBits.append(String(format: "VFC 14d %.0f ms", h)) }
            if let r = avgRhr14 { bioBits.append(String(format: "FCR 14d %.0f ppm", r)) }
            let bioContext = bioBits.isEmpty ? "" : " Cruzado con tu \(bioBits.joined(separator: " y ")):"
            for flag in outOfRange.prefix(2) {
                let valStr = String(format: "%.1f", locale: Locale(identifier: "es_ES"), flag.value)
                insights.append(UnifiedCausalInsight(
                    id: "cross_blood_\(flag.id)",
                    categoryBadge: "SANGRE × BIOMETRÍA × NUTRICIÓN",
                    icon: "cross.case.fill",
                    title: "Analítica: \(flag.name) (\(valStr) \(flag.unit))",
                    impactBadge: flag.status.rawValue,
                    isPositive: false,
                    detail: "Fuera de rango en tu analítica (\(latestLab.dateIso)).\(bioContext) priorizar micronutrientes clave, sueño ≥85% y carga controlada acelerará su normalización y mejorará tu Edad Biológica.",
                    sampleDays: max(recent14.count, 1)
                ))
            }
        }

        // 4. Real-Time Weather × Cardiovascular Drift insight
        if let w = weather, w.heatStressLevel >= 1 {
            insights.append(UnifiedCausalInsight(
                id: "cross_weather_thermal",
                categoryBadge: "CLIMA × PULSO Y RECUPERACIÓN",
                icon: w.sfSymbol,
                title: "\(w.cityName): \(Int(w.temperatureC.rounded())) °C · \(w.humidityPct)% hum. · UV \(Int(w.uvIndex.rounded()))",
                impactBadge: w.estimatedHrDriftBpm > 0 ? "+\(w.estimatedHrDriftBpm) ppm FC" : "Clima",
                isPositive: false,
                detail: w.effortImpactSummary,
                sampleDays: 1
            ))
        }

        if insights.isEmpty {
            insights.append(UnifiedCausalInsight(
                id: "cross_ready_calibration",
                categoryBadge: "MOTOR CAUSAL UNIFICADO",
                icon: "sparkles",
                title: "Cruce Nutrición × Analíticas × Biometría activo",
                impactBadge: "100 % Local",
                isPositive: true,
                detail: "A medida que registres comidas, cafeína, hábitos y sueño en días consecutivos, verás aquí cómo tu proteína, hora de cena, cafeína residual y analíticas modifican tu VFC, FCR y sueño profundo.",
                sampleDays: sortedIsos.count
            ))
        }

        return insights
    }

    // MARK: - Caffeine Pharmacokinetic Window Engine (5.5h Half-Life, 20 mg Sleep Threshold)

    static let caffeineHalfLifeHours: Double = 5.5
    static let caffeineSleepThresholdMg: Double = 20.0

    /// Exact clearance time in minutes for a caffeine load (`totalMg`) to fall below `thresholdMg` (20 mg) using T½ = 5.5 h.
    /// Matches clinical pharmacokinetic benchmarks: 28 mg -> 2h 40m, 80 mg -> 11h, 160 mg -> 16h 30m, 200 mg -> 18h 16m.
    static func caffeineClearanceMinutes(
        totalMg: Double,
        halfLifeHours: Double = caffeineHalfLifeHours,
        thresholdMg: Double = caffeineSleepThresholdMg
    ) -> Int {
        guard totalMg > thresholdMg, halfLifeHours > 0.5 else { return 0 }
        let hours = halfLifeHours * log2(totalMg / thresholdMg)
        return max(0, Int((hours * 60.0).rounded()))
    }

    static func formatClearanceDuration(_ totalMinutes: Int) -> String {
        guard totalMinutes > 0 else { return "0 min" }
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h == 0 { return "\(m) min" }
        if m == 0 { return "\(h) h" }
        return "\(h) h \(m) min"
    }

    static func computeCaffeineWindowTimeline(
        meals: [NutritionMealItem],
        wakeMinuteOfDay: Int,
        bedtimeMinuteOfDay: Int,
        nowMinuteOfDay: Int,
        manualCaffeineMg: Double? = nil,
        manualCaffeineTime: String? = nil,
        halfLifeHours: Double = caffeineHalfLifeHours,
        sleepThresholdMg: Double = caffeineSleepThresholdMg
    ) -> CaffeineWindowTimelineSnapshot {
        let wake = ((wakeMinuteOfDay % 1440) + 1440) % 1440
        var bedAdj = ((bedtimeMinuteOfDay % 1440) + 1440) % 1440
        if bedAdj <= wake + 360 { bedAdj += 1440 }
        // Clamp awake span to realistic 12..18h window
        let span = min(max(bedAdj - wake, 720), 1080)
        bedAdj = wake + span

        // Normalize current clock minute onto [wake ... bedAdj] timeline
        var nowAdj = ((nowMinuteOfDay % 1440) + 1440) % 1440
        if nowAdj < wake - 120 { nowAdj += 1440 }
        let nowClamped = min(max(nowAdj, wake), bedAdj)

        // Physiological phase boundaries:
        // 1. Delay (0..90m post-wake)
        // 2. Optimal window (wake+90m .. bedtime-10h, minimum 3h wide)
        // 3. Caution window (~2h after cutoff)
        // 4. Too late / sleep-risk zone (final ~8h before bedtime)
        let optStart = wake + 90
        let cutoff = min(max(optStart + 180, bedAdj - 600), bedAdj - 360)
        let cautionEnd = min(cutoff + 135, bedAdj - 240)

        let halfLifeMin = halfLifeHours * 60.0
        var intakes: [CaffeineLoggedIntake] = []
        for m in meals {
            guard let mg = m.caffeineMg, mg > 0 else { continue }
            var tMin = parseTimeLabelToMinutes(m.timeLabel) ?? (wake + 120)
            if tMin < wake - 120 { tMin += 1440 }
            intakes.append(CaffeineLoggedIntake(
                id: m.id,
                title: m.title,
                mg: mg,
                timeLabel: m.timeLabel,
                minuteOfDay: tMin
            ))
        }
        if intakes.isEmpty, let manMg = manualCaffeineMg, manMg > 0 {
            let lbl = manualCaffeineTime ?? CaffeineWindowTimelineSnapshot.formatMinuteOfDay(wake + 120)
            var tMin = parseTimeLabelToMinutes(lbl) ?? (wake + 120)
            if tMin < wake - 120 { tMin += 1440 }
            intakes.append(CaffeineLoggedIntake(
                id: "manual_caffeine",
                title: "Cafeína registrada (Diario)",
                mg: manMg,
                timeLabel: lbl,
                minuteOfDay: tMin
            ))
        }
        intakes.sort { $0.minuteOfDay < $1.minuteOfDay }

        func concentration(at minute: Double) -> Double {
            var sum = 0.0
            for item in intakes {
                let dt = minute - Double(item.minuteOfDay)
                if dt >= 0 {
                    // Rapid 25-min absorption ramp + 5.5h exponential decay
                    let absorption = dt < 25.0 ? (0.35 + 0.65 * (dt / 25.0)) : 1.0
                    sum += item.mg * absorption * pow(0.5, dt / halfLifeMin)
                }
            }
            return sum
        }

        let steps = 64
        var curve: [CaffeineDecayCurvePoint] = []
        curve.reserveCapacity(steps + 1)
        for i in 0...steps {
            let frac = Double(i) / Double(steps)
            let offset = frac * Double(span)
            let t = Double(wake) + offset
            curve.append(CaffeineDecayCurvePoint(minuteOffsetFromWake: offset, mg: concentration(at: t)))
        }

        let nowBody = AppleHealthExportImporter.round1(concentration(at: Double(nowClamped)))
        let bedResidual = AppleHealthExportImporter.round1(concentration(at: Double(bedAdj)))
        let totalToday = AppleHealthExportImporter.round1(intakes.reduce(0.0) { $0 + $1.mg })

        let phase: CaffeineWindowPhase
        if nowClamped < optStart {
            phase = .postWakeDelay
        } else if nowClamped <= cutoff {
            phase = .optimal
        } else if nowClamped <= cautionEnd {
            phase = .caution
        } else {
            phase = .tooLate
        }

        let remOpt = phase == .optimal ? max(cutoff - nowClamped, 0) : 0
        let waitOpt = phase == .postWakeDelay ? max(optStart - nowClamped, 0) : 0

        return CaffeineWindowTimelineSnapshot(
            wakeMinute: wake,
            optimalStartMinute: optStart,
            cutoffMinute: cutoff,
            cautionEndMinute: cautionEnd,
            bedtimeMinute: bedAdj,
            nowMinute: nowClamped,
            currentBodyMg: nowBody,
            totalTodayMg: totalToday,
            residualAtBedtimeMg: bedResidual,
            phase: phase,
            minutesRemainingInOptimal: remOpt,
            minutesUntilOptimalStarts: waitOpt,
            sleepThresholdMg: sleepThresholdMg,
            curvePoints: curve,
            intakes: intakes
        )
    }

    static func isDrinkSafeForSleepNow(
        drinkMg: Double,
        snapshot: CaffeineWindowTimelineSnapshot,
        halfLifeHours: Double = caffeineHalfLifeHours
    ) -> Bool {
        let halfLifeMin = halfLifeHours * 60.0
        let minutesUntilBed = Double(max(snapshot.bedtimeMinute - snapshot.nowMinute, 0))
        let addedResidualAtBed = drinkMg * pow(0.5, minutesUntilBed / halfLifeMin)
        return (snapshot.residualAtBedtimeMg + addedResidualAtBed) <= snapshot.sleepThresholdMg
    }

    // MARK: - Hyper-Personalized Physiological Twin, Proactive Immunity Radar, Simulator, Post-Workout Audit & Periodization

    static func computePersonalSensitivityTwin(
        history: [String: RealBiometricDaySummary],
        mealsByDate: [String: [NutritionMealItem]],
        profile: UserPhysiologyProfile,
        bedtimeMinuteOfDay: Int = 23 * 60 + 15
    ) -> PersonalSensitivityTwinSnapshot {
        let norms = computePersonalizedNorms(profile: profile)
        let sortedIsos = history.keys.sorted()
        let cal = Calendar(identifier: .gregorian)
        func nextIso(_ iso: String) -> String? {
            guard let dt = AppFormatters.parseIsoDay(iso),
                  let nx = cal.date(byAdding: .day, value: 1, to: dt) else { return nil }
            return AppFormatters.isoDayString(from: nx)
        }

        var cleanCaffHrv: [Double] = []
        var modCaffHrv: [Double] = []
        var cleanCaffDeep: [Double] = []
        var modCaffDeep: [Double] = []
        var dinnerShortRec: [Double] = []
        var dinnerMedRec: [Double] = []
        var dinnerLongRec: [Double] = []
        var sleepBuckets: [Int: [Double]] = [:]
        var strainPairs: [(strain: Double, nextHrv: Double)] = []
        var pairedDays = 0

        for iso in sortedIsos {
            if let cur = history[iso], let asleep = cur.asleepMinutes, asleep >= 240, let rec = cur.recoveryPct {
                let halfHourBucket = min(max(Int((Double(asleep) / 30.0).rounded()), 10), 20)
                sleepBuckets[halfHourBucket, default: []].append(Double(rec))
            }
            guard let nxIso = nextIso(iso), let nextDay = history[nxIso] else { continue }
            if let cur = history[iso], let st = cur.strain21, st > 1.0, let nh = nextDay.hrvMs, nh > 5 {
                strainPairs.append((st, nh))
            }
            let meals = mealsByDate[iso] ?? []
            guard !meals.isEmpty else { continue }
            pairedDays += 1

            let timing = computeCaffeineAndMealTiming(meals: meals, bedtimeMinutesOfDay: bedtimeMinuteOfDay)
            if timing.totalCaffeineTodayMg >= 40 {
                let hasAfternoonLoad = timing.estimatedCaffeineAtBedtimeMg >= 18.0
                if let nh = nextDay.hrvMs, nh > 5 {
                    if hasAfternoonLoad { modCaffHrv.append(nh) } else { cleanCaffHrv.append(nh) }
                }
                if let dp = nextDay.deepMinutes, dp > 5 {
                    if hasAfternoonLoad { modCaffDeep.append(Double(dp)) } else { cleanCaffDeep.append(Double(dp)) }
                }
            }
            if let gap = timing.hoursFromLastMealToBedtime, let nRec = nextDay.recoveryPct {
                if gap < 2.3 { dinnerShortRec.append(Double(nRec)) }
                else if gap < 3.3 { dinnerMedRec.append(Double(nRec)) }
                else { dinnerLongRec.append(Double(nRec)) }
            }
        }

        var halfLife = 5.5
        var caffLabel = "Metabolismo medio (~5,5 h)"
        if cleanCaffHrv.count >= 3 && modCaffHrv.count >= 3 {
            let cMean = cleanCaffHrv.reduce(0, +) / Double(cleanCaffHrv.count)
            let mMean = modCaffHrv.reduce(0, +) / Double(modCaffHrv.count)
            let dropPct = cMean > 1 ? ((cMean - mMean) / cMean) * 100.0 : 0
            var deepDrop = 0.0
            if cleanCaffDeep.count >= 2 && modCaffDeep.count >= 2 {
                let cd = cleanCaffDeep.reduce(0, +) / Double(cleanCaffDeep.count)
                let md = modCaffDeep.reduce(0, +) / Double(modCaffDeep.count)
                deepDrop = cd - md
            }
            if dropPct >= 9.0 || deepDrop >= 14.0 {
                halfLife = 7.0
                caffLabel = "Sensible / lento (~7,0 h)"
            } else if dropPct <= 2.5 && deepDrop <= 4.0 {
                halfLife = 4.3
                caffLabel = "Metabolizador rápido (~4,3 h)"
            }
        }

        let clearanceMin95 = caffeineClearanceMinutes(totalMg: 95.0, halfLifeHours: halfLife, thresholdMg: 20.0)
        let normBed = ((bedtimeMinuteOfDay % 1440) + 1440) % 1440
        let cutoffMin = (((normBed - clearanceMin95) % 1440) + 1440) % 1440
        let cutoffLabel = String(format: "%02d:%02d", cutoffMin / 60, cutoffMin % 60)

        var optDinnerH = 3.0
        let shortAvg = dinnerShortRec.count >= 2 ? (dinnerShortRec.reduce(0, +) / Double(dinnerShortRec.count)) : nil
        let medAvg = dinnerMedRec.count >= 2 ? (dinnerMedRec.reduce(0, +) / Double(dinnerMedRec.count)) : nil
        let longAvg = dinnerLongRec.count >= 2 ? (dinnerLongRec.reduce(0, +) / Double(dinnerLongRec.count)) : nil
        if let l = longAvg, let m = medAvg, l >= m + 4.0 {
            optDinnerH = 3.5
        } else if let s = shortAvg, let m = medAvg, s >= m - 1.5 && (longAvg == nil || s >= longAvg! - 1.5) {
            optDinnerH = 2.3
        }

        var optSleepH = norms.sleepTargetHours
        let validSleepBuckets = sleepBuckets.filter { $0.value.count >= 3 }
        if let best = validSleepBuckets.max(by: {
            ($0.value.reduce(0, +) / Double($0.value.count)) < ($1.value.reduce(0, +) / Double($1.value.count))
        }) {
            optSleepH = min(max(Double(best.key) * 0.5, 6.5), 9.5)
        }

        var strainSweet = 14.5
        if strainPairs.count >= 8 {
            let allHrvMean = strainPairs.map(\.nextHrv).reduce(0, +) / Double(strainPairs.count)
            let safeHigh = strainPairs.filter { $0.strain >= 12.0 && $0.nextHrv >= allHrvMean * 0.92 }.map(\.strain)
            if safeHigh.count >= 2 {
                let topSlice = safeHigh.sorted().suffix(4)
                let topMean = topSlice.reduce(0, +) / Double(topSlice.count)
                strainSweet = min(max(AppleHealthExportImporter.round1(topMean), 11.5), 18.5)
            }
        }

        let calibrated = pairedDays >= 6 || validSleepBuckets.count >= 2
        let optSleepStr = String(format: "%.1f h", locale: Locale(identifier: "es_ES"), optSleepH)
        let optDinStr = String(format: "%.1f h", locale: Locale(identifier: "es_ES"), optDinnerH)
        let sweetStr = String(format: "%.1f", locale: Locale(identifier: "es_ES"), strainSweet)
        let summary = calibrated
            ? "Tu gemelo fisiológico rinde mejor durmiendo \(optSleepStr), cenando ≥\(optDinStr) antes, cortando café a las \(cutoffLabel) (\(caffLabel.lowercased())) y con techo dulce de Strain \(sweetStr)."
            : "Calibrando tu gemelo personal (\(pairedDays)/6 días cruzados): referencia actual \(optSleepStr) de sueño, corte de café \(cutoffLabel) y cena \(optDinStr) antes de dormir."

        return PersonalSensitivityTwinSnapshot(
            isCalibrated: calibrated,
            pairedDaysCount: pairedDays,
            caffeineHalfLifeHours: halfLife,
            caffeineSensitivityLabel: caffLabel,
            recommendedCaffeineCutoffLabel: cutoffLabel,
            optimalDinnerLeadHours: optDinnerH,
            personalOptimalSleepHours: optSleepH,
            personalStrainSweetSpot: strainSweet,
            summaryText: summary
        )
    }

    static func computeProactiveImmunityRadar(
        todaySummary: RealBiometricDaySummary?,
        trailing60Summaries: [RealBiometricDaySummary],
        acwr: Double,
        journalToday: [String: JournalCheckState],
        moodToday: Int?,
        noteToday: String
    ) -> ProactiveImmunityRadarSnapshot {
        let prior = trailing60Summaries.dropLast()
        func mean(_ vals: [Double]) -> Double? {
            guard vals.count >= 4 else { return nil }
            return vals.reduce(0, +) / Double(vals.count)
        }
        let baseHrv = mean(prior.compactMap(\.hrvMs))
        let baseRhr = mean(prior.compactMap(\.restingHrBpm))
        let baseResp = mean(prior.compactMap(\.respRateRpm))
        let tempPriorVals: [Double] = prior.compactMap { s in
            if let a = s.wristTempAbsoluteC { return a }
            if let d = s.wristTempDeltaC { return 35.8 + d }
            return nil
        }
        let baseTemp = mean(tempPriorVals)

        var signals: [String] = []
        var score = 0

        if let curHrv = todaySummary?.hrvMs, let bHrv = baseHrv, bHrv > 5 {
            let pct = ((curHrv - bHrv) / bHrv) * 100.0
            if pct <= -18.0 {
                score += 2
                signals.append(String(format: "VFC %.0f%% bajo tu base", pct))
            } else if pct <= -11.0 {
                score += 1
                signals.append(String(format: "VFC %.0f%% vs base", pct))
            }
        }
        if let curRhr = todaySummary?.restingHrBpm, let bRhr = baseRhr {
            let delta = curRhr - bRhr
            if delta >= 4.5 {
                score += 2
                signals.append(String(format: "FCR +%.1f ppm", locale: Locale(identifier: "es_ES"), delta))
            } else if delta >= 2.8 {
                score += 1
                signals.append(String(format: "FCR +%.1f ppm", locale: Locale(identifier: "es_ES"), delta))
            }
        }
        let curTempVal: Double? = todaySummary?.wristTempAbsoluteC ?? todaySummary?.wristTempDeltaC.map { 35.8 + $0 }
        if let curTemp = curTempVal, let bTemp = baseTemp {
            let tDelta = curTemp - bTemp
            if tDelta >= 0.40 {
                score += 2
                signals.append(String(format: "Temp. muñeca +%.2f °C", locale: Locale(identifier: "es_ES"), tDelta))
            } else if tDelta >= 0.25 {
                score += 1
                signals.append(String(format: "Temp. muñeca +%.2f °C", locale: Locale(identifier: "es_ES"), tDelta))
            }
        } else if let relDelta = todaySummary?.wristTempDeltaC, relDelta >= 0.40 {
            score += 2
            signals.append(String(format: "Temp. muñeca +%.2f °C", locale: Locale(identifier: "es_ES"), relDelta))
        }
        if let curResp = todaySummary?.respRateRpm, let bResp = baseResp {
            let rDelta = curResp - bResp
            if rDelta >= 1.3 {
                score += 2
                signals.append(String(format: "FR +%.1f rpm", locale: Locale(identifier: "es_ES"), rDelta))
            }
        }
        if acwr >= 1.42 {
            score += 1
            signals.append(String(format: "Carga aguda ACWR %.2f", locale: Locale(identifier: "es_ES"), acwr))
        }
        if let debt = todaySummary?.sleepDebtMinutes, debt >= 95 {
            score += 1
            signals.append("Deuda de sueño \(debt) min")
        }

        let lowNote = noteToday.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
        let negativeNoteHit = ["enferm", "fiebre", "garganta", "escalofrio", "roto", "agotad", "mareo", "lesion", "dolor fuerte", "destrozad"]
            .contains(where: { lowNote.contains($0) })
        let hasFeverOrIllness = journalToday["fever"] == .yes || journalToday["illness"] == .yes
        let hasInjury = journalToday["injury"] == .yes
        let lowMood = (moodToday ?? 3) <= 2

        if hasFeverOrIllness {
            score += 3
            signals.append("Síntomas marcados en Diario")
        } else if negativeNoteHit || lowMood {
            score += 1
            signals.append(lowMood ? "Ánimo/energía baja (\(moodToday ?? 2)/5)" : "Fatiga descrita en nota")
        }

        var mismatch: String? = nil
        if let rec = todaySummary?.recoveryPct, todaySummary?.hasRecordedSleep == true,
           rec >= 65 && (hasFeverOrIllness || hasInjury || lowMood || negativeNoteHit) {
            let reason = hasFeverOrIllness ? "síntomas de enfermedad" : (hasInjury ? "molestia/lesión activa" : "fatiga subjetiva alta en tu Diario")
            mismatch = "Tu biometría marca \(rec)% en verde, pero reportas \(reason): priorizamos cómo te sientes y recortamos el esfuerzo objetivo un 20%."
        }

        let riskLevel: Int = score >= 4 ? 2 : (score >= 2 ? 1 : 0)
        let confidence = min(94, 55 + signals.count * 10)
        let strainCut = riskLevel == 2 ? 32 : (riskLevel == 1 || mismatch != nil ? 18 : 0)
        let extraWater = riskLevel == 2 ? 750 : (riskLevel == 1 ? 400 : 0)
        let earlyBed = riskLevel == 2 ? 45 : (riskLevel == 1 ? 25 : 0)

        let headline: String
        let summary: String
        if riskLevel == 2 {
            headline = "Alerta temprana: posible sobrecarga o estrés inmunitario"
            summary = "Se han desviado a la vez \(signals.joined(separator: ", ")). Recorta hoy el esfuerzo un \(strainCut)%, añade +\(extraWater) ml con electrolitos y adelanta el sueño \(earlyBed) min."
        } else if riskLevel == 1 {
            headline = "Vigilancia autonómica preventiva"
            summary = "Señales leves acumuladas (\(signals.joined(separator: ", "))). Prioriza Zona 2 o técnica limpia, +\(extraWater) ml de agua y adelanta tu descanso \(earlyBed) min."
        } else if let m = mismatch {
            headline = "Ajuste inteligente por sensación subjetiva"
            summary = m
        } else {
            headline = "Sistema inmune y autónomo estables"
            summary = "Tus constantes nocturnas y sensaciones del Diario están alineadas con tu base personal."
        }

        return ProactiveImmunityRadarSnapshot(
            riskLevel: riskLevel,
            headline: headline,
            summary: summary,
            confidencePct: confidence,
            signals: signals,
            strainReductionPct: strainCut,
            extraHydrationMl: extraWater,
            earlierBedtimeMin: earlyBed,
            subjectiveMismatchText: mismatch
        )
    }

    static func simulateWhatIfScenario(
        input: WhatIfScenarioInput,
        currentRecoveryPct: Int,
        baseHrvMs: Double,
        baseRhrBpm: Double,
        twin: PersonalSensitivityTwinSnapshot,
        bedtimeMinuteOfDay: Int = 23 * 60 + 15
    ) -> WhatIfSimulationResult {
        var recDelta = 0.0
        var hrvDelta = 0.0
        var deepDelta = 0.0
        var rhrDelta = 0.0

        let sleepDiff = input.sleepHours - twin.personalOptimalSleepHours
        if sleepDiff < 0 {
            recDelta += sleepDiff * 9.5
            hrvDelta += sleepDiff * 4.2
            deepDelta += sleepDiff * 14.0
            rhrDelta += abs(sleepDiff) * 1.4
        } else {
            recDelta += min(sleepDiff * 5.0, 9.0)
            hrvDelta += min(sleepDiff * 2.4, 5.0)
            deepDelta += min(sleepDiff * 9.0, 16.0)
            rhrDelta -= min(sleepDiff * 0.8, 1.8)
        }

        if input.alcoholDrinks > 0 {
            let d = input.alcoholDrinks
            recDelta -= (d * 7.5 + max(0, d - 2.0) * 3.5)
            hrvDelta -= (d * 4.8 + max(0, d - 2.0) * 2.2)
            deepDelta -= d * 6.5
            rhrDelta += d * 2.1
        }

        let normBed = ((bedtimeMinuteOfDay % 1440) + 1440) % 1440
        let caffMin = min(max(input.caffeineHour, 5), 23) * 60
        let elapsedMin = Double(normBed >= caffMin ? (normBed - caffMin) : (normBed + 1440 - caffMin))
        let residualCaff = input.caffeineMg > 0
            ? AppleHealthExportImporter.round1(input.caffeineMg * pow(0.5, elapsedMin / (twin.caffeineHalfLifeHours * 60.0)))
            : 0.0
        if residualCaff > 20.0 {
            let excess = residualCaff - 20.0
            recDelta -= min(excess * 0.22, 16.0)
            hrvDelta -= min(excess * 0.12, 9.0)
            deepDelta -= min(excess * 0.45, 28.0)
            rhrDelta += min(excess * 0.05, 3.0)
        }

        let dinnerGapDiff = input.dinnerLeadHours - twin.optimalDinnerLeadHours
        if dinnerGapDiff < -0.4 {
            let lateHours = abs(dinnerGapDiff)
            recDelta -= lateHours * 4.2
            hrvDelta -= lateHours * 2.3
            deepDelta -= lateHours * 8.5
            rhrDelta += lateHours * 1.3
        } else if dinnerGapDiff >= 0.3 {
            recDelta += 3.0
            hrvDelta += 1.6
            deepDelta += 6.0
            rhrDelta -= 0.7
        }

        if input.highStrainSession {
            recDelta -= 5.5
            hrvDelta -= 2.8
            deepDelta += 5.0
            rhrDelta += 1.5
        }
        if input.magnesiumOrSauna {
            recDelta += 4.5
            hrvDelta += 2.8
            deepDelta += 9.0
            rhrDelta -= 0.9
        }

        let baseRec = min(max(currentRecoveryPct, 35), 92)
        let predRec = min(max(Int((Double(baseRec) + recDelta).rounded()), 12), 99)
        let cleanRecDelta = predRec - baseRec
        let cleanHrvDelta = AppleHealthExportImporter.round1(hrvDelta)
        let cleanDeepDelta = Int(deepDelta.rounded())
        let cleanRhrDelta = AppleHealthExportImporter.round1(rhrDelta)

        var mitigations: [String] = []
        if input.alcoholDrinks >= 1 {
            mitigations.append("Añade 600–800 ml de agua con electrolitos antes de dormir y termina la última copa ≥3 h antes de acostarte.")
        }
        if residualCaff > 20 {
            mitigations.append("Con tu metabolismo (\(twin.caffeineSensitivityLabel.lowercased())), llegarías a la cama con \(Int(residualCaff)) mg de cafeína: adelanta el café antes de las \(twin.recommendedCaffeineCutoffLabel) o pasa a descafeinado.")
        }
        if input.dinnerLeadHours < twin.optimalDinnerLeadHours - 0.3 {
            mitigations.append(String(format: "Adelanta la cena para dejar ≥%.1f h de digestión y dar un paseo suave de 10 min post-cena.", locale: Locale(identifier: "es_ES"), twin.optimalDinnerLeadHours))
        }
        if input.sleepHours < twin.personalOptimalSleepHours - 0.4 {
            mitigations.append("Programa 20 min de siesta o NSDR mañana antes de las 15:30 para compensar el recorte de sueño.")
        }
        if mitigations.isEmpty {
            mitigations.append("Protocolo excelente: mantén habitación fresca (18 °C) y sin pantallas los últimos 30 min para consolidar esa recarga.")
        }

        let verdict: String = predRec >= 67
            ? "Mañana en verde estimado (\(predRec)%)"
            : (predRec >= 34 ? "Recuperación moderada estimada (\(predRec)%)" : "Riesgo alto de día en rojo (\(predRec)%)")
        let hrvSign = String(format: "%+.1f ms VFC", locale: Locale(identifier: "es_ES"), cleanHrvDelta)
        let deepSign = String(format: "%+d min sueño profundo", cleanDeepDelta)
        let rhrSign = String(format: "%+.1f ppm FCR", locale: Locale(identifier: "es_ES"), cleanRhrDelta)
        let recSign = cleanRecDelta >= 0 ? "+\(cleanRecDelta)" : "\(cleanRecDelta)"
        let explanation = "Partiendo de tu base personal (\(Int(baseHrvMs.rounded())) ms VFC · \(Int(baseRhrBpm.rounded())) ppm FCR), este escenario mueve tu recuperación \(recSign)% (\(hrvSign), \(deepSign), \(rhrSign))."

        return WhatIfSimulationResult(
            predictedRecoveryPct: predRec,
            recoveryDeltaPct: cleanRecDelta,
            hrvDeltaMs: cleanHrvDelta,
            deepSleepDeltaMin: cleanDeepDelta,
            rhrDeltaBpm: cleanRhrDelta,
            residualCaffeineAtBedMg: residualCaff,
            verdictTitle: verdict,
            explanation: explanation,
            mitigationSteps: mitigations
        )
    }

    static func computePostWorkoutAudit(
        workout: EffortEventItem,
        recoveryPct: Int?,
        profile: UserPhysiologyProfile,
        weather: WeatherPhysiologySnapshot?,
        intradayHrSamples: [TimedBiometricPoint] = []
    ) -> PostWorkoutPhysiologyAudit {
        let norms = computePersonalizedNorms(profile: profile)
        let maxHr = Double(max(norms.maxHrBpm, 150))
        let hrPct = workout.avgHrBpm > 0 ? (Double(workout.avgHrBpm) / maxHr) * 100.0 : 0

        var measuredDrift = 0
        if intradayHrSamples.count >= 6 {
            let mid = intradayHrSamples.count / 2
            let firstHalf = intradayHrSamples.prefix(mid).map(\.value)
            let secondHalf = intradayHrSamples.suffix(intradayHrSamples.count - mid).map(\.value)
            let m1 = firstHalf.reduce(0, +) / Double(firstHalf.count)
            let m2 = secondHalf.reduce(0, +) / Double(secondHalf.count)
            measuredDrift = max(0, Int((m2 - m1).rounded()))
        }
        let thermalBpm = weather?.estimatedHrDriftBpm ?? 0
        let totalDrift = max(measuredDrift, workout.durationMin >= 35 ? thermalBpm : thermalBpm / 2)

        let durHours = Double(max(workout.durationMin, 10)) / 60.0
        let highIntensity = hrPct >= 76.0 || workout.strainScore >= 13.0 || (workout.rpe ?? 0) >= 8
        let carbsPerKgHour = highIntensity ? 0.95 : 0.55
        let refillCarbs = max(20, Int((profile.weightKg * carbsPerKgHour * min(durHours, 2.5)).rounded()))
        let refillProt = max(25, Int((profile.weightKg * 0.38).rounded()))
        let baseSweatMl = Int((durHours * (highIntensity ? 720.0 : 480.0)).rounded())
        let weatherSweatExtra = Int((Double(weather?.extraHydrationMl ?? 0) * min(durHours, 1.5) * 0.65).rounded())
        let rehydMl = max(350, baseSweatMl + weatherSweatExtra)
        let sodiumMg = Int((Double(rehydMl) * (thermalBpm >= 5 ? 0.85 : 0.55)).rounded())

        let rec = recoveryPct ?? 65
        let effLabel: String
        let effHex: UInt64
        let matchLabel: String
        if rec < 40 && highIntensity {
            effLabel = "Sobrecarga sobre fatiga"
            effHex = 0xF97316
            matchLabel = "Exigente con recuperación baja (\(rec)%)"
        } else if totalDrift >= 8 {
            effLabel = "Deriva cardíaca elevada (+\(totalDrift) ppm)"
            effHex = 0xF5B942
            matchLabel = thermalBpm >= 4 ? "Impacto térmico por clima (\(thermalBpm) ppm)" : "Desacoplamiento aeróbico en 2ª mitad"
        } else {
            effLabel = "Asimilación fisiológica óptima"
            effHex = 0x3BD671
            matchLabel = recoveryPct != nil ? "Alineado con tu recuperación (\(rec)%)" : "Estímulo bien tolerado"
        }

        var summary = "Estímulo \(matchLabel.lowercased())."
        if totalDrift >= 4 {
            let thermNote = thermalBpm >= 4 ? " (incluye +\(thermalBpm) ppm por calor/humedad)" : ""
            summary += " Deriva estimada de +\(totalDrift) ppm\(thermNote)."
        }
        summary += " Ventana post-entreno ideal: \(refillCarbs) g de carbohidratos + \(refillProt) g de proteína y \(rehydMl) ml de agua con ~\(sodiumMg) mg de sodio."

        return PostWorkoutPhysiologyAudit(
            efficiencyLabel: effLabel,
            efficiencyColorHex: effHex,
            cardiacDriftBpm: totalDrift,
            thermalContributionBpm: thermalBpm,
            intensityMatchLabel: matchLabel,
            glycogenRefillCarbsG: refillCarbs,
            proteinRefillG: refillProt,
            rehydrationMl: rehydMl,
            sodiumMg: sodiumMg,
            summaryText: summary
        )
    }

    static func computeAdaptiveMicrocycle(
        plan: GoalEventPlan,
        anchorDate: Date,
        recoveryPct: Int?,
        freshMuscles: [String],
        autoDeload: Bool
    ) -> AdaptiveMicrocycleSnapshot {
        let cal = Calendar(identifier: .gregorian)
        let startToday = cal.startOfDay(for: anchorDate)
        let targetDt = AppFormatters.parseIsoDay(plan.targetDateIso).map { cal.startOfDay(for: $0) } ?? cal.date(byAdding: .day, value: 42, to: startToday)!
        let daysRem = max(0, cal.dateComponents([.day], from: startToday, to: targetDt).day ?? 0)
        let rec = recoveryPct ?? 65

        let (phaseName, badgeHex): (String, UInt64) = {
            if autoDeload || (recoveryPct != nil && rec < 36) { return ("Descarga Adaptativa", 0xF97316) }
            if daysRem <= 10 { return ("Taper Pre-Evento (\(daysRem)d)", 0x38BDF8) }
            if daysRem <= 24 { return ("Pico Específico", 0xA78BFA) }
            if daysRem <= 49 { return ("Construcción Progresiva", 0x3BD671) }
            return ("Base Aeróbica y Fuerza", 0x60A5FA)
        }()

        let wdShort = ["Dom", "Lun", "Mar", "Mié", "Jue", "Vie", "Sáb"]
        let focusLow = plan.sportFocus.lowercased()
        let isEndurance = focusLow.contains("carrer") || focusLow.contains("marat") || focusLow.contains("resist") || focusLow.contains("cicl") || focusLow.contains("triat")
        let isStrength = focusLow.contains("fuerza") || focusLow.contains("hipertrof") || focusLow.contains("muscul") || focusLow.contains("volumen")
        let topMuscle = freshMuscles.first ?? "tren superior"

        var dayPlans: [AdaptiveMicrocycleDayPlan] = []
        var todayRx = ""

        for offset in 0..<7 {
            guard let dt = cal.date(byAdding: .day, value: offset, to: startToday) else { continue }
            let iso = AppFormatters.isoDayString(from: dt)
            let wdIdx = max(0, min(6, cal.component(.weekday, from: dt) - 1))
            let isToday = (offset == 0)

            var title: String
            var tag: String
            var strainRng: String
            var hex: UInt64

            switch wdIdx {
            case 1:
                title = isEndurance ? "Rodaje Zona 2 + Core" : "Fuerza Principal (\(topMuscle))"
                tag = "Moderado"; strainRng = "11–14"; hex = 0x38BDF8
            case 2:
                title = isStrength ? "Hipertrofia Tracción / Pierna" : "Series Umbral / Calidad"
                tag = "Clave"; strainRng = "14–17"; hex = 0xF59E0B
            case 3:
                title = "Zona 2 suave o Movilidad activa"
                tag = "Recuperación"; strainRng = "6–9"; hex = 0x34D399
            case 4:
                title = isEndurance ? "Tempo específico + Fuerza preventiva" : "Fuerza Empuje / Sobrecarga"
                tag = "Moderado-Alto"; strainRng = "13–16"; hex = 0x60A5FA
            case 5:
                title = "Descanso activo · Paseo + Estiramientos"
                tag = "Ligero"; strainRng = "4–7"; hex = 0x34D399
            case 6:
                title = isEndurance ? "Tirada larga aeróbica" : "Sesión completa / Metabólico"
                tag = "Sesión Reina"; strainRng = "15–18"; hex = 0xA78BFA
            default:
                title = "Descanso total y recarga de sueño"
                tag = "Descanso"; strainRng = "3–6"; hex = 0x64748B
            }

            if daysRem <= 10 && tag == "Sesión Reina" {
                title = "Activación corta al ritmo objetivo (-40% vol.)"
                tag = "Taper"; strainRng = "9–12"; hex = 0x38BDF8
            }

            if isToday {
                if autoDeload || (recoveryPct != nil && rec < 38) {
                    title = "Movilidad + 25 min Zona 1 (adaptado a tu recuperación)"
                    tag = "Adaptado"; strainRng = "5–8"; hex = 0xF97316
                } else if recoveryPct != nil && rec >= 75 && tag == "Moderado" {
                    tag = "Verde Óptimo"; strainRng = "14–17"; hex = 0x3BD671
                }
                todayRx = "Hoy (\(phaseName)): \(title) · Strain objetivo \(strainRng)."
            }

            dayPlans.append(AdaptiveMicrocycleDayPlan(
                id: iso,
                dayShortLabel: wdShort[wdIdx],
                isToday: isToday,
                sessionTitle: title,
                intensityTag: tag,
                targetStrainRange: strainRng,
                accentHex: hex
            ))
        }

        return AdaptiveMicrocycleSnapshot(
            plan: plan,
            daysRemaining: daysRem,
            phaseName: phaseName,
            phaseBadgeColorHex: badgeHex,
            todayPrescription: todayRx,
            days: dayPlans
        )
    }
}

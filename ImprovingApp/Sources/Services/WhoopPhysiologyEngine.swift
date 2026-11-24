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

struct BiologicalAgeEvaluation: Equatable {
    let chronoAgeYears: Double
    let bioAgeYears: Double
    let deltaYears: Double // negative = biologically younger than chronological age
    let sleepDelta: Double
    let activityDelta: Double
    let fitnessDelta: Double
    let autonomicDelta: Double
    let bodyDelta: Double
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

    static func computeBmrKcalPerDay(profile: UserPhysiologyProfile) -> Int {
        let w = min(max(profile.weightKg, 32.0), 220.0)
        let h = min(max(profile.heightCm, 130.0), 225.0)
        let a = profile.effectiveAgeYears
        let bmr: Double
        switch profile.sex {
        case .male: bmr = 88.362 + 13.397 * w + 4.799 * h - 5.677 * a
        case .female: bmr = 447.593 + 9.247 * w + 3.098 * h - 4.330 * a
        case .nonBinary: bmr = 267.9775 + 11.322 * w + 3.9485 * h - 5.0035 * a
        }
        return max(Int(bmr.rounded()), 1000)
    }

    /// Master clinical & sports-physiology personalization engine (exact parity with Android `WhoopPhysiologyEngine.kt`).
    /// Computes every optimal range, vital band, sleep duration/architecture target, VO2/HRR cohort,
    /// macro/hydration/caffeine target, and movement goal from `(birthDate/age, sex, heightCm, weightKg)`.
    static func computePersonalizedNorms(profile: UserPhysiologyProfile) -> PersonalizedPhysiologyNorms {
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
        let maxHr = computeMaxHeartRate(profile: profile)

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

        // VO2max & HRR targets by Age & Sex (FRIEND / ACSM standards)
        let decadeDrop = (max(0.0, age - 24.0) / 10.0) * 3.2
        let vo2Good = r1(max((isFemale ? 39.5 : 48.0) - decadeDrop, 22.0))
        let vo2Excellent = r1(max((isFemale ? 45.2 : 55.2) - decadeDrop, 26.0))
        let hrrGood = min(max(Int((32.0 - max(0.0, age - 30.0) * 0.25 - (isFemale ? 1.5 : 0.0)).rounded()), 16), 36)
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

    /// Computes Biological Age calibrated strictly against the user's OWN age, sex, height, and weight norms
    /// (so a 62-year-old is evaluated against 62-year-old clinical norms, NOT 24-year-old norms!).
    static func computeBiologicalAge(
        profile: UserPhysiologyProfile,
        meanRhr: Double?,
        meanHrv: Double?,
        meanSleepHours: Double?,
        meanSteps: Int?,
        vo2Max: Double?,
        latestWeightKg: Double? = nil
    ) -> BiologicalAgeEvaluation {
        let norms = computePersonalizedNorms(profile: profile)
        let chrono = profile.effectiveAgeYears

        var sleepDelta = 0.0
        if let s = meanSleepHours {
            // Optimal around user's age-specific target; penalties for chronic short sleep or excessive oversleep
            let deficit = norms.sleepTargetHours - s
            sleepDelta = deficit >= 0
                ? min(deficit * 0.85, 2.2)
                : max(deficit * 0.45, -1.2)
        }

        var activityDelta = 0.0
        if let st = meanSteps {
            let ratio = Double(st) / Double(max(norms.dailyStepsGoal, 4000))
            activityDelta = min(max((1.0 - ratio) * 1.8, -1.6), 2.0)
        }

        var fitnessDelta = 0.0
        if let v = vo2Max {
            fitnessDelta += min(max((norms.vo2GoodThreshold - v) * 0.18, -2.5), 2.8)
        }
        if let r = meanRhr {
            fitnessDelta += min(max((r - norms.restingHrExpected) * 0.14, -1.8), 2.2)
        }

        var autonomicDelta = 0.0
        if let h = meanHrv, h > 2.0 {
            let lnDiff = log(norms.hrvExpectedMs) - log(h)
            autonomicDelta = min(max(lnDiff * 2.2, -1.8), 2.2)
        }

        var bodyDelta = 0.0
        let w = latestWeightKg ?? profile.weightKg
        let hm = max(profile.heightCm / 100.0, 1.2)
        let curBmi = w / (hm * hm)
        if curBmi > norms.bmiOptimalHigh {
            bodyDelta = min((curBmi - norms.bmiOptimalHigh) * 0.25, 2.2)
        } else if curBmi < norms.bmiOptimalLow {
            bodyDelta = min((norms.bmiOptimalLow - curBmi) * 0.22, 1.4)
        }

        let rawTotal = sleepDelta + activityDelta + fitnessDelta + autonomicDelta + bodyDelta
        let clampedDelta = AppleHealthExportImporter.round1(min(max(rawTotal, -7.5), 7.5))
        let bioAge = AppleHealthExportImporter.round1(max(14.0, chrono + clampedDelta))

        return BiologicalAgeEvaluation(
            chronoAgeYears: AppleHealthExportImporter.round1(chrono),
            bioAgeYears: bioAge,
            deltaYears: clampedDelta,
            sleepDelta: AppleHealthExportImporter.round1(sleepDelta),
            activityDelta: AppleHealthExportImporter.round1(activityDelta),
            fitnessDelta: AppleHealthExportImporter.round1(fitnessDelta),
            autonomicDelta: AppleHealthExportImporter.round1(autonomicDelta),
            bodyDelta: AppleHealthExportImporter.round1(bodyDelta)
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

        // Blend 85% personal rolling baseline + 15% age/sex/body expected physiology so autonomic reserve
        // reflects that e.g. 45 ms HRV has a different physiological meaning at 20 vs 62 years old!
        let cohortWeight: Double = {
            guard profileNorms != nil else { return 0.0 }
            if lnHrvBaseline.count < 7 { return 0.30 }
            return 0.15
        }()

        // Bevel weights: ~62% Sleeping HRV (log-normal z-score) + ~33% Sleeping RHR + ~5% secondary vitals
        var weightedZ = 0.0
        var totalWeight = 0.0

        if let hrv = hrvMs, hrv > 2.0 {
            let personalZ = (log(hrv) - lnHrvBaseline.mean) / max(lnHrvBaseline.sigma, 0.12)
            let effZ: Double
            if let norms = profileNorms, cohortWeight > 0 {
                let cohortZ = (log(hrv) - log(max(norms.hrvExpectedMs, 15.0))) / 0.28
                effZ = (1.0 - cohortWeight) * personalZ + cohortWeight * cohortZ
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
            if let norms = profileNorms, cohortWeight > 0 {
                let cohortZ = (norms.restingHrExpected - rhr) / 5.0
                effZ = (1.0 - cohortWeight) * personalZ + cohortWeight * cohortZ
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

        // 2. Workout physiological load (uses real workout HR relative to Tanaka HRR, otherwise BMR-normalized kcal)
        var workoutLoad = 0.0
        for w in workouts {
            if w.avgHrBpm > 0 {
                let frac = min(max((Double(w.avgHrBpm) - rhrBpm) / hrr, 0.25), 0.98)
                let rate = frac * 0.64 * exp(b * frac)
                workoutLoad += Double(w.durationMin) * rate * 1.15
            } else if w.kcal > 0 {
                workoutLoad += (Double(w.kcal) / max(bmr, 1100.0)) * 165.0
            } else {
                workoutLoad += Double(w.durationMin) * 0.55 * ageZoneFactor
            }
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
        banisterB: Double = 1.92
    ) -> (strain21: Double, strainPct: Int) {
        let load: Double
        if avgHrBpm > 40 {
            let frac = min(max((Double(avgHrBpm) - rhrBpm) / max(maxHrBpm - rhrBpm, 40.0), 0.22), 0.98)
            load = Double(durationMin) * frac * 0.64 * exp(banisterB * frac) * 1.15
        } else if kcal > 0 {
            load = Double(kcal) * 0.095
        } else {
            load = Double(durationMin) * 0.52
        }
        let pctDouble = 100.0 * (1.0 - exp(-max(load, 1.0) / 108.0))
        let pct = min(max(Int(pctDouble.rounded()), 2), 98)
        let s21 = AppleHealthExportImporter.round1(min(max((pctDouble / 100.0) * 20.8, 0.4), 20.8))
        return (s21, pct)
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

        // 4. Continuity (10% weight) — only if awake blocks exist
        if let aw = awakeMinutes, awakeCount > 0 {
            let contScore = Double(max(20, min(100, 100 - awakeCount * 7 - Int(Double(aw) * 0.8))))
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

    static func optimalTargetRange(for recoveryPct: Int, profile: UserPhysiologyProfile? = nil) -> ClosedRange<Double> {
        let base: ClosedRange<Double> = switch recoveryPct {
        case 70...100: 0.62...0.84
        case 45..<70: 0.42...0.65
        default: 0.22...0.45
        }
        guard let p = profile else { return base }
        let age = p.effectiveAgeYears
        // Gentle age-calibrated training capacity shift (younger adults tolerate slightly higher ceiling; 55+ protects autonomic reserve)
        let shift: Double = {
            if age < 25.0 { return 0.03 }
            if age <= 45.0 { return 0.0 }
            if age < 60.0 { return -0.04 }
            return -0.08
        }()
        let lo = min(max(base.lowerBound + shift, 0.14), 0.78)
        let hi = min(max(base.upperBound + shift, lo + 0.16), 0.92)
        return lo...hi
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

        // Build daily linearly interpolated series from first recorded value to latest recorded value for smooth 7-day rolling averages
        let firstDay = dated.first!.dayIndex
        let lastDay = dated.last!.dayIndex
        var daily: [Double?] = Array(repeating: nil, count: 120)
        for idx in 0..<dated.count {
            let cur = dated[idx]
            daily[cur.dayIndex] = cur.value
            if idx + 1 < dated.count {
                let nxt = dated[idx + 1]
                let gap = nxt.dayIndex - cur.dayIndex
                if gap > 1 {
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

            // 2. Synced HealthKit / Shortcuts workouts (mapped physiologically to active muscle groups)
            if let day = history[iso] {
                for w in day.workouts {
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
}

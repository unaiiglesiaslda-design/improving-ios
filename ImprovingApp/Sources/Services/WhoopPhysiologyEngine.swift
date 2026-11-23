import Foundation
import SwiftUI

struct PersonalizedPhysiologyNorms: Equatable {
    let maxHrBpm: Int
    let bmrKcal: Int
    let sleepTargetHours: Double
    let bmi: Double
    let hrvLowMs: Double
    let hrvHighMs: Double
    let rhrLowBpm: Double
    let rhrHighBpm: Double
    let respLowRpm: Double
    let respHighRpm: Double
    let sleepLowHours: Double
    let sleepHighHours: Double
    let hydrationGoalLiters: Double
    let proteinGoalG: Int
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
        let tanaka = Int((208.0 - 0.7 * profile.ageYears).rounded())
        return min(max(max(tanaka, observedPeakBpm), 130), 225)
    }

    static func computeBmrKcalPerDay(profile: UserPhysiologyProfile) -> Int {
        let w = profile.weightKg, h = profile.heightCm, a = profile.ageYears
        let bmr: Double
        switch profile.sex {
        case .male: bmr = 88.362 + 13.397 * w + 4.799 * h - 5.677 * a
        case .female: bmr = 447.593 + 9.247 * w + 3.098 * h - 4.330 * a
        case .nonBinary: bmr = 267.9775 + 11.322 * w + 3.9485 * h - 5.0035 * a
        }
        return max(Int(bmr.rounded()), 1000)
    }

    static func computePersonalizedNorms(profile: UserPhysiologyProfile) -> PersonalizedPhysiologyNorms {
        let maxHr = computeMaxHeartRate(profile: profile)
        let bmr = computeBmrKcalPerDay(profile: profile)
        let hm = max(profile.heightCm / 100.0, 1.2)
        let bmi = AppleHealthExportImporter.round1(profile.weightKg / (hm * hm))
        let hrvAge = max(25.0, min(105.0, 88.0 * exp(-0.020 * max(0.0, profile.ageYears - 18.0))))
        let hrvLow = AppleHealthExportImporter.round1(hrvAge * 0.78)
        let hrvHigh = AppleHealthExportImporter.round1(hrvAge * 1.24)
        let rhrBase = profile.sex == .female ? 57.0 : 53.0
        let rhrLow = AppleHealthExportImporter.round1(rhrBase - 6.0)
        let rhrHigh = AppleHealthExportImporter.round1(rhrBase + 7.0)
        let sleepTarget = profile.ageYears < 18 ? 8.8 : 8.0
        let hydro = AppleHealthExportImporter.round1(max(profile.weightKg * 0.037, 2.2))

        return PersonalizedPhysiologyNorms(
            maxHrBpm: maxHr,
            bmrKcal: bmr,
            sleepTargetHours: sleepTarget,
            bmi: bmi,
            hrvLowMs: hrvLow,
            hrvHighMs: hrvHigh,
            rhrLowBpm: rhrLow,
            rhrHighBpm: rhrHigh,
            respLowRpm: 13.5,
            respHighRpm: 16.8,
            sleepLowHours: 7.0,
            sleepHighHours: 9.0,
            hydrationGoalLiters: hydro,
            proteinGoalG: max(Int((profile.weightKg * 1.8).rounded()), 95)
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

    /// Computes true beat-to-beat RMSSD (ms) from Apple Health `<InstantaneousBeatsPerMinute>` BPM readings.
    static func computeRmssdFromBeatBpms(_ bpms: [Double]) -> Double? {
        let rr = bpms.compactMap { bpm -> Double? in
            guard (30.0...200.0).contains(bpm) else { return nil }
            return 60_000.0 / bpm
        }
        return computeRmssdFromRRSegments([rr])
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

    /// Computes Bevel-aligned Recovery (1...99%) strictly from sensors that were ACTUALLY measured on this day.
    /// Returns `nil` if NEITHER HRV nor RHR was recorded.
    static func computeBevelRecoveryPercent(
        hrvMs: Double?,
        rhrBpm: Double?,
        respRpm: Double?,
        spo2Pct: Double?,
        wristTempDeltaC: Double?,
        lnHrvBaseline: PersonalBaselineStats,
        rhrBaseline: PersonalBaselineStats,
        respBaseline: PersonalBaselineStats
    ) -> Int? {
        guard hrvMs != nil || rhrBpm != nil else { return nil }

        // Bevel weights: ~60% Sleeping HRV (log-normal z-score) + ~35% Sleeping RHR + ~5% secondary vitals if abnormal
        var weightedZ = 0.0
        var totalWeight = 0.0

        if let hrv = hrvMs, hrv > 2.0 {
            let zHrv = (log(hrv) - lnHrvBaseline.mean) / max(lnHrvBaseline.sigma, 0.12)
            let clampedZ = min(max(zHrv, -2.8), 2.8)
            weightedZ += 0.62 * clampedZ
            totalWeight += 0.62
        }

        if let rhr = rhrBpm, rhr > 25.0 {
            let zRhr = (rhrBaseline.mean - rhr) / max(rhrBaseline.sigma, 1.8)
            let clampedZ = min(max(zRhr, -2.8), 2.8)
            weightedZ += 0.33 * clampedZ
            totalWeight += 0.33
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
        if let spo2 = spo2Pct, spo2 < 95.0 {
            score -= (95.0 - spo2) * 3.2
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

        // 1. HR-zone Banister TRIMP (exact Z1..Z5 intensity weights)
        let zoneWeights = [0.65, 1.35, 2.35, 3.80, 5.60]
        var zoneTrimp = 0.0
        for (idx, mins) in hrZoneMinutes.prefix(5).enumerated() where mins > 0 {
            zoneTrimp += Double(mins) * zoneWeights[idx]
        }

        // 2. Workout physiological load (uses real workout HR if present, otherwise real workout kcal/duration)
        var workoutLoad = 0.0
        for w in workouts {
            if w.avgHrBpm > 0 {
                let frac = min(max((Double(w.avgHrBpm) - rhrBpm) / hrr, 0.25), 0.98)
                let rate = frac * 0.64 * exp(b * frac)
                workoutLoad += Double(w.durationMin) * rate * 1.15
            } else if w.kcal > 0 {
                workoutLoad += Double(w.kcal) * 0.095
            } else {
                workoutLoad += Double(w.durationMin) * 0.55
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

    // MARK: - Bevel-Calibrated Sleep Score % (Strictly Measured Components Only!)

    static func computeBevelSleepScore(
        asleepMinutes: Int,
        inBedMinutes: Int?,
        deepMinutes: Int?,
        remMinutes: Int?,
        awakeMinutes: Int?,
        awakeCount: Int,
        hrDipPct: Double?,
        targetMinutes: Double = 480.0
    ) -> Int {
        var scoreSum = 0.0
        var weightSum = 0.0

        // 1. Duration (45% weight) — 100% at targetMinutes
        let durScore = min(max(Double(asleepMinutes) / max(targetMinutes, 300.0), 0.10), 1.0) * 100.0
        scoreSum += 0.45 * durScore
        weightSum += 0.45

        // 2. Efficiency (15% weight) — only if inBedMinutes exists
        if let bed = inBedMinutes, bed > 0 {
            let effPct = min(max(Double(asleepMinutes) / Double(bed) * 100.0, 40.0), 100.0)
            // Bevel treats ≥ 94% efficiency as 100 score, 75% as ~50
            let effScore = min(max((effPct - 60.0) / 35.0, 0.0), 1.0) * 100.0
            scoreSum += 0.15 * effScore
            weightSum += 0.15
        }

        // 3. Restorative stages (REM + Deep, 20% weight) — only if stage data exists!
        if let d = deepMinutes, let r = remMinutes, (d + r) > 0, asleepMinutes > 0 {
            let deepPct = Double(d) / Double(asleepMinutes) * 100.0 // target ~15-20%
            let remPct = Double(r) / Double(asleepMinutes) * 100.0  // target ~20-25%
            let deepScore = min(max(deepPct / 16.0, 0.0), 1.0) * 100.0
            let remScore = min(max(remPct / 20.0, 0.0), 1.0) * 100.0
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

    static func optimalTargetRange(for recoveryPct: Int) -> ClosedRange<Double> {
        switch recoveryPct {
        case 70...100: return 0.62...0.84
        case 45..<70: return 0.42...0.65
        default: return 0.22...0.45
        }
    }

    // MARK: - Preview Simulator (ONLY used before user imports Apple Health or connects a device; continuous energy!)

    static func generateTwoYearSimulatedHistory(profile: UserPhysiologyProfile, endDate: Date = Date()) -> [String: RealBiometricDaySummary] {
        let totalDays = 90 // Lightweight 90-day preview before real data is imported
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

            let hrv = AppleHealthExportImporter.round1(min(max(66.0 + progress * 8.5 + w2 * 4.5 + noise * 6.0, 42.0), 104.0))
            let rhr = AppleHealthExportImporter.round1(min(max(52.0 - progress * 2.5 - w2 * 1.1 + noise * 1.8, 43.0), 63.0))
            let resp = AppleHealthExportImporter.round1(min(max(15.1 + noise * 0.4, 13.5), 17.2))
            let spo2 = AppleHealthExportImporter.round1(min(max(96.6 + noise * 1.0, 94.8), 99.0))
            let tempDelta = AppleHealthExportImporter.round1(min(max(w2 * 0.14 + noise * 0.18, -0.4), 0.5))
            let tempAbs = AppleHealthExportImporter.round1(35.7 + tempDelta)

            let weekday = cal.component(.weekday, from: date)
            let isWeekend = (weekday == 1 || weekday == 7)
            let asleepMin = min(max(Int((440.0 + (isWeekend ? 28.0 : 0.0) + w1 * 18.0 + noise * 22.0).rounded()), 350), 530)
            let inBedMin = asleepMin + 16 + (hash % 12)
            let deepMin = Int((Double(asleepMin) * 0.17).rounded())
            let remMin = Int((Double(asleepMin) * 0.22).rounded())
            let awakeMin = max(inBedMin - asleepMin, 6)
            let coreMin = max(asleepMin - deepMin - remMin, 120)
            let sleepPct = computeBevelSleepScore(
                asleepMinutes: asleepMin, inBedMinutes: inBedMin,
                deepMinutes: deepMin, remMinutes: remMin,
                awakeMinutes: awakeMin, awakeCount: 2, hrDipPct: 13.5
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

            let recPct = computeRecoveryPercent(
                hrvMs: hrv, rhrBpm: rhr, respRpm: resp, spo2Pct: spo2,
                wristTempDeltaC: tempDelta, sleepScorePct: sleepPct,
                hrvMean: 70.0, hrvSigma: 11.0, rhrMean: 51.0, rhrSigma: 3.0
            )
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
                sleepDebtMinutes: max(480 - asleepMin, 0),
                sleepSession: sleepDetail,
                strain21: strainTuple.strain21,
                strainPct: strainTuple.strainPct,
                recoveryPct: recPct,
                stressScore: stressBase,
                energyBankPercent: Int(curE.rounded()),
                stepsCount: 7400 + (hash % 5200),
                vo2MaxMlKgMin: AppleHealthExportImporter.round1(42.0 + progress * 2.4),
                hrRecoveryBpm: AppleHealthExportImporter.round1(27.0 + progress * 3.0),
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
}

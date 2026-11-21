import Foundation

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
        let ageShift = (profile.ageYears - 25.0) * 0.85
        let hrvLow = AppleHealthExportImporter.round1(max(55.0 - ageShift * 0.5, 28.0))
        let hrvHigh = AppleHealthExportImporter.round1(max(105.0 - ageShift, hrvLow + 22.0))
        let rhrBase = profile.restingHrCalibrationBpm ?? (profile.sex == .female ? 54.0 : 50.0)
        let rhrLow = AppleHealthExportImporter.round1(max(rhrBase - 6.0, 36.0))
        let rhrHigh = AppleHealthExportImporter.round1(rhrBase + 9.0)
        let sleepTarget = profile.ageYears < 22 ? 8.5 : 7.8
        let hydro = AppleHealthExportImporter.round1(max(profile.weightKg * 0.035, 1.8))

        return PersonalizedPhysiologyNorms(
            maxHrBpm: maxHr,
            bmrKcal: bmr,
            sleepTargetHours: sleepTarget,
            bmi: bmi,
            hrvLowMs: hrvLow,
            hrvHighMs: hrvHigh,
            rhrLowBpm: rhrLow,
            rhrHighBpm: rhrHigh,
            respLowRpm: 13.4,
            respHighRpm: 16.6,
            sleepLowHours: 7.0,
            sleepHighHours: 9.0,
            hydrationGoalLiters: hydro
        )
    }

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
        let zHrv = (hrvMs - hrvMean) / max(hrvSigma, 1.0)
        let zRhr = (rhrMean - rhrBpm) / max(rhrSigma, 0.8)
        let zSleep = (Double(sleepScorePct) / 100.0 - 0.85) / 0.12
        let zResp = (respMean - respRpm) / max(respSigma, 0.3)
        let zTemp = -abs(wristTempDeltaC) / 1.0
        let compositeZ = 0.55 * zHrv + 0.20 * zRhr + 0.15 * zSleep + 0.05 * zResp + 0.05 * zTemp
        var score = 100.0 / (1.0 + exp(-1.6 * (compositeZ + 0.20)))
        if spo2Pct < 95.0 { score -= (95.0 - spo2Pct) * 1.6 }
        if wristTempDeltaC > 0.5 && zRhr < -1.0 { score *= 0.75 }
        return min(max(Int(score.rounded()), 1), 99)
    }

    static func computeStrainAndEffort(
        profile: UserPhysiologyProfile,
        rhrBpm: Double,
        hrZoneMinutes: [Int],
        effortEvents: [EffortEventItem],
        completedStrengthSets: Int,
        totalStrengthVolumeKg: Int
    ) -> (Double, Int) {
        let b = profile.sex.banisterB
        let floorRate = 0.10 * 0.64 * exp(b * 0.10)
        let mids = [0.55, 0.65, 0.75, 0.85, 0.95]
        var trimp = 0.0
        for (idx, mins) in hrZoneMinutes.prefix(5).enumerated() where mins > 0 {
            let x = mids[idx]
            let rate = x * 0.64 * exp(b * x)
            trimp += Double(mins) * max(rate - floorRate, 0.0)
        }
        let workoutTrimp = effortEvents.reduce(0.0) { acc, ev in
            let frac = min(max((Double(ev.avgHrBpm) - rhrBpm) / max(Double(computeMaxHeartRate(profile: profile)) - rhrBpm, 40.0), 0.25), 0.98)
            return acc + Double(ev.durationMin) * frac * 0.64 * exp(b * frac)
        }
        let musc = Double(completedStrengthSets) * 2.1 + Double(totalStrengthVolumeKg) / 900.0
        let total = max(trimp, workoutTrimp * 0.85) + musc
        let maxRef = 320.0 * (b / 1.92)
        let s21 = min(max(21.0 * log(1.0 + total / 38.0) / log(1.0 + maxRef / 38.0), 0.0), 21.0)
        let pct = min(max(Int((100.0 * log(1.0 + total) / log(1.0 + maxRef)).rounded()), 1), 100)
        return (AppleHealthExportImporter.round1(s21), pct)
    }

    static func optimalTargetRange(for recoveryPct: Int) -> ClosedRange<Double> {
        switch recoveryPct {
        case 70...100: return 0.56...0.80
        case 45..<70: return 0.40...0.64
        default: return 0.22...0.45
        }
    }
}

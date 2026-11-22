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
    let normalizedPosition: Double // 0.08 ... 0.92 (0.26..0.74 is normal band)
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
        let hrvLow = 68.6
        let hrvHigh = 107.4
        let rhrLow = 46.0
        let rhrHigh = 56.0
        let sleepTarget = 8.2
        let hydro = AppleHealthExportImporter.round1(max(profile.weightKg * 0.037, 2.4))

        return PersonalizedPhysiologyNorms(
            maxHrBpm: maxHr,
            bmrKcal: bmr,
            sleepTargetHours: sleepTarget,
            bmi: bmi,
            hrvLowMs: hrvLow,
            hrvHighMs: hrvHigh,
            rhrLowBpm: rhrLow,
            rhrHighBpm: rhrHigh,
            respLowRpm: 13.8,
            respHighRpm: 16.8,
            sleepLowHours: 7.0,
            sleepHighHours: 9.0,
            hydrationGoalLiters: hydro
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
        case 70...100: return 0.62...0.84
        case 45..<70: return 0.42...0.65
        default: return 0.22...0.45
        }
    }

    // MARK: - Deterministic 730-Day (2-Year) WHOOP Simulator (1:1 Parity with Android WhoopTwoYearSimulator.kt)

    static func generateTwoYearSimulatedHistory(profile: UserPhysiologyProfile, endDate: Date = Date()) -> [String: RealBiometricDaySummary] {
        let totalDays = 730
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"

        var map: [String: RealBiometricDaySummary] = [:]
        map.reserveCapacity(totalDays)

        for i in 0..<totalDays {
            let dayOffset = (totalDays - 1) - i
            guard let date = cal.date(byAdding: .day, value: -dayOffset, to: endDate) else { continue }
            let iso = fmt.string(from: date)

            if dayOffset == 0 {
                // Exact Android HoyScreen hero snapshot (82% Esfuerzo, 79% Recuperación, 92% Sueño 7h 58m, 35 Estrés, 71% Energía)
                let stress24: [Double] = [
                    14, 10, 8, 5, 2, 6, 9, 14, 26, 38, 42, 36,
                    34, 41, 32, 29, 38, 68, 77, 54, 41, 33, 27, 22
                ]
                let energy24: [Double] = [
                    54, 60, 66, 73, 80, 86, 91, 95, 96, 92, 89, 86,
                    83, 81, 82, 79, 77, 75, 73, 72, 72, 71, 71, 71
                ]
                let workout = EffortEventItem(
                    id: "sim_today_0",
                    title: "Tirada Larga Aeróbica",
                    timeRange: "17:30 - 18:56",
                    durationMin: 86,
                    avgHrBpm: 148,
                    strainScore: 15.8,
                    strainPct: 82,
                    categoryLabel: "Cardio",
                    kcal: 999
                )
                map[iso] = RealBiometricDaySummary(
                    dateIso: iso,
                    liveHrBpm: 68,
                    restingHrBpm: 48.2,
                    hrvMs: 77.5,
                    respRateRpm: 15.2,
                    wristTempDeltaC: 0.1,
                    spo2Percent: 97,
                    asleepMinutes: 478, // 7 h 58 min
                    inBedMinutes: 492,
                    deepMinutes: 102,
                    remMinutes: 118,
                    sleepPct: 92,
                    sleepDebtMinutes: 36,
                    strain21: 16.4,
                    strainPct: 82,
                    recoveryPct: 79,
                    stressScore: 35,
                    energyBankPercent: 71,
                    stepsCount: 12480,
                    vo2MaxMlKgMin: 44.3,
                    glucoseMgDl: 94,
                    activeKcal: 999,
                    hrZoneMinutes: [45, 16, 7, 1, 0],
                    stressSeries24h: stress24,
                    energySeries24h: energy24,
                    strengthMinutes: 42,
                    workouts: [workout]
                )
                continue
            }

            let progress = Double(i) / Double(totalDays)
            let w1 = sin(Double(i) * 2.0 * .pi / 7.0)
            let w2 = cos(Double(i) * 2.0 * .pi / 28.0)
            let w3 = sin(Double(i) * 2.0 * .pi / 90.0)
            let hash = ((i &* 1_103_515_245 &+ 12_345) >> 16) & 0x7FFF
            let noise = Double((hash % 200) - 100) / 100.0

            let hrv = AppleHealthExportImporter.round1(min(max(64.0 + progress * 11.5 + w2 * 3.5 + noise * 5.2, 42.0), 106.0))
            let rhr = AppleHealthExportImporter.round1(min(max(53.0 - progress * 3.8 - w2 * 1.1 + noise * 1.6, 43.0), 65.0))
            let resp = AppleHealthExportImporter.round1(min(max(15.3 - progress * 0.25 + w3 * 0.3 + noise * 0.4, 13.2), 17.8))
            let spo2 = min(max(Int((97.2 + noise * 1.2).rounded()), 95), 99)
            let tempDelta = AppleHealthExportImporter.round1(min(max(w2 * 0.14 + noise * 0.20, -0.5), 0.6))

            let weekday = cal.component(.weekday, from: date)
            let isWeekend = (weekday == 1 || weekday == 7)
            let asleepMin = min(max(Int((436.0 + (isWeekend ? 32.0 : 0.0) + w1 * 18.0 + noise * 24.0).rounded()), 340), 540)
            let inBedMin = asleepMin + 18 + (hash % 14)
            let deepMin = Int((Double(asleepMin) * 0.20).rounded())
            let remMin = Int((Double(asleepMin) * 0.23).rounded())
            let sleepPct = min(max(Int(((Double(asleepMin) / 480.0) * 84.0 + 10.0).rounded()), 54), 98)

            let trainFactor: Double = switch weekday {
            case 2, 4, 6: 0.72
            case 3, 5: 0.56
            case 7: 0.82
            default: 0.28
            }
            let z1 = max(Int((18.0 + trainFactor * 26.0).rounded()), 8)
            let z2 = max(Int((10.0 + trainFactor * 22.0).rounded()), 4)
            let z3 = max(Int((trainFactor * 14.0).rounded()), 0)
            let z4 = max(Int(((trainFactor - 0.5) * 12.0).rounded()), 0)
            let zones = [z1, z2, z3, z4, 0]

            let strainPct = min(max(Int((trainFactor * 88.0 + noise * 9.0).rounded()), 18), 94)
            let strain21 = AppleHealthExportImporter.round1(Double(strainPct) / 100.0 * 20.4)
            let hrvNorm = min(max((hrv - 48.0) / 42.0, 0), 1)
            let rhrNorm = min(max((58.0 - rhr) / 14.0, 0), 1)
            let recPct = min(max(Int(((0.52 * hrvNorm + 0.24 * rhrNorm + 0.24 * (Double(sleepPct) / 100.0)) * 100.0).rounded()), 28), 97)
            let stress = min(max(Int((20.0 + (1.0 - hrvNorm) * 24.0 + trainFactor * 14.0 + noise * 5.0).rounded()), 14), 68)
            let energy = min(max(recPct - Int(Double(strainPct) * 0.22) + 10, 28), 96)
            let vo2 = AppleHealthExportImporter.round1(41.2 + progress * 3.1 + w3 * 0.25)

            let wTitle: String? = switch weekday {
            case 2: "Fuerza Tren Superior"
            case 3: "Carrera Base Zona 2"
            case 4: "Fuerza Pierna e Hip Thrust"
            case 5: "Movilidad y Cardio Ligero"
            case 6: "Full Body + Intervalos"
            case 7: "Tirada Larga Aeróbica"
            default: nil
            }
            let wDur = wTitle != nil ? min(max(z1 + z2 + z3 + z4, 38), 92) : 0
            let wKcal = wDur * 10 + 110
            let workouts: [EffortEventItem] = wTitle.map {
                [EffortEventItem(
                    id: "sim_\(dayOffset)",
                    title: $0,
                    timeRange: "18:00 - \(18 + wDur / 60):\(String(format: "%02d", wDur % 60))",
                    durationMin: wDur,
                    avgHrBpm: 141,
                    strainScore: strain21,
                    strainPct: strainPct,
                    categoryLabel: $0.contains("Fuerza") ? "Fuerza" : "Cardio",
                    kcal: wKcal
                )]
            } ?? []

            let s24 = (0..<24).map { hr -> Double in
                let sleepMult = (1...8).contains(hr) ? 0.45 : 1.0
                let bump = (wTitle != nil && (17...19).contains(hr)) ? 24.0 : 0.0
                let wave = sin(Double(hr) / 23.0 * 3.0 * .pi) * 7.0
                return min(max(Double(stress) * sleepMult + bump + wave, 4), 92)
            }
            let peakE = min(max(Double(recPct) * 0.94, 58), 97)
            let startE = max(peakE - 30.0, 24)
            let e24 = (0..<24).map { hr -> Double in
                if hr <= 8 {
                    return startE + (peakE - startE) * (Double(hr) / 8.0)
                }
                let t = Double(hr - 8) / 15.0
                return min(max(peakE - (peakE - Double(energy)) * t, 12), 99)
            }

            map[iso] = RealBiometricDaySummary(
                dateIso: iso,
                liveHrBpm: Int(rhr.rounded()) + 14,
                restingHrBpm: rhr,
                hrvMs: hrv,
                respRateRpm: resp,
                wristTempDeltaC: tempDelta,
                spo2Percent: spo2,
                asleepMinutes: asleepMin,
                inBedMinutes: inBedMin,
                deepMinutes: deepMin,
                remMinutes: remMin,
                sleepPct: sleepPct,
                sleepDebtMinutes: max(480 - asleepMin, 12),
                strain21: strain21,
                strainPct: strainPct,
                recoveryPct: recPct,
                stressScore: stress,
                energyBankPercent: energy,
                stepsCount: 7400 + (hash % 5400),
                vo2MaxMlKgMin: vo2,
                glucoseMgDl: 92 + (hash % 9),
                activeKcal: wKcal,
                hrZoneMinutes: zones,
                stressSeries24h: s24,
                energySeries24h: e24,
                strengthMinutes: (wTitle?.contains("Fuerza") == true) ? wDur : 0,
                workouts: workouts
            )
        }
        return map
    }
}

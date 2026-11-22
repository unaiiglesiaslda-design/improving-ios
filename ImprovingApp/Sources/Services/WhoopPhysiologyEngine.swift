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
            let hr = ev.avgHrBpm > 0 ? Double(ev.avgHrBpm) : (rhrBpm + 75.0)
            let frac = min(max((hr - rhrBpm) / max(Double(computeMaxHeartRate(profile: profile)) - rhrBpm, 40.0), 0.25), 0.98)
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

    // MARK: - Deterministic 730-Day (2-Year) Preview Simulator (ONLY used BEFORE real Apple Health / WHOOP import)

    static func generateTwoYearSimulatedHistory(profile: UserPhysiologyProfile, endDate: Date = Date()) -> [String: RealBiometricDaySummary] {
        let totalDays = 730
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        let shortDtFmt = DateFormatter()
        shortDtFmt.locale = Locale(identifier: "es_ES")
        shortDtFmt.dateFormat = "dd/MM/yy"

        var map: [String: RealBiometricDaySummary] = [:]
        map.reserveCapacity(totalDays)

        for i in 0..<totalDays {
            let dayOffset = (totalDays - 1) - i
            guard let date = cal.date(byAdding: .day, value: -dayOffset, to: endDate) else { continue }
            let iso = fmt.string(from: date)
            let dayStartEpoch = Int64(cal.startOfDay(for: date).timeIntervalSince1970)

            let progress = Double(i) / Double(totalDays)
            let w1 = sin(Double(i) * 2.0 * .pi / 7.0)
            let w2 = cos(Double(i) * 2.0 * .pi / 28.0)
            let w3 = sin(Double(i) * 2.0 * .pi / 90.0)
            let hash = ((i &* 1_103_515_245 &+ 12_345) >> 16) & 0x7FFF
            let noise = Double((hash % 200) - 100) / 100.0

            let isToday = dayOffset == 0
            let hrv = isToday ? 77.5 : AppleHealthExportImporter.round1(min(max(64.0 + progress * 11.5 + w2 * 3.5 + noise * 5.2, 42.0), 106.0))
            let rhr = isToday ? 48.2 : AppleHealthExportImporter.round1(min(max(53.0 - progress * 3.8 - w2 * 1.1 + noise * 1.6, 43.0), 65.0))
            let resp = isToday ? 15.2 : AppleHealthExportImporter.round1(min(max(15.3 - progress * 0.25 + w3 * 0.3 + noise * 0.4, 13.2), 17.8))
            let spo2 = isToday ? 96.4 : AppleHealthExportImporter.round1(min(max(96.5 + noise * 1.1, 94.5), 99.2))
            let tempDelta = isToday ? 0.1 : AppleHealthExportImporter.round1(min(max(w2 * 0.14 + noise * 0.20, -0.5), 0.6))
            let tempAbs = AppleHealthExportImporter.round1(35.7 + tempDelta)

            let weekday = cal.component(.weekday, from: date)
            let isWeekend = (weekday == 1 || weekday == 7)
            let asleepMin = isToday ? 478 : min(max(Int((436.0 + (isWeekend ? 32.0 : 0.0) + w1 * 18.0 + noise * 24.0).rounded()), 340), 540)
            let inBedMin = isToday ? 492 : asleepMin + 16 + (hash % 14)
            let deepMin = isToday ? 102 : Int((Double(asleepMin) * 0.18).rounded())
            let remMin = isToday ? 118 : Int((Double(asleepMin) * 0.22).rounded())
            let awakeMin = max(inBedMin - asleepMin, 6)
            let coreMin = max(asleepMin - deepMin - remMin, 120)
            let sleepPct = isToday ? 92 : min(max(Int(((Double(asleepMin) / 480.0) * 84.0 + 10.0).rounded()), 54), 98)

            let trainFactor: Double = switch weekday {
            case 2, 4, 6: 0.72
            case 3, 5: 0.56
            case 7: 0.82
            default: 0.28
            }
            let z1 = isToday ? 45 : max(Int((18.0 + trainFactor * 26.0).rounded()), 8)
            let z2 = isToday ? 16 : max(Int((10.0 + trainFactor * 22.0).rounded()), 4)
            let z3 = isToday ? 7 : max(Int((trainFactor * 14.0).rounded()), 0)
            let z4 = isToday ? 1 : max(Int(((trainFactor - 0.5) * 12.0).rounded()), 0)
            let zones = [z1, z2, z3, z4, 0]

            let strainPct = isToday ? 82 : min(max(Int((trainFactor * 88.0 + noise * 9.0).rounded()), 18), 94)
            let strain21 = isToday ? 16.4 : AppleHealthExportImporter.round1(Double(strainPct) / 100.0 * 20.4)
            let hrvNorm = min(max((hrv - 48.0) / 42.0, 0), 1)
            let rhrNorm = min(max((58.0 - rhr) / 14.0, 0), 1)
            let recPct = isToday ? 79 : min(max(Int(((0.52 * hrvNorm + 0.24 * rhrNorm + 0.24 * (Double(sleepPct) / 100.0)) * 100.0).rounded()), 28), 97)
            let stress = isToday ? 35 : min(max(Int((20.0 + (1.0 - hrvNorm) * 24.0 + trainFactor * 14.0 + noise * 5.0).rounded()), 14), 68)
            let energy = isToday ? 71 : min(max(recPct - Int(Double(strainPct) * 0.22) + 10, 28), 96)
            let vo2 = isToday ? 44.3 : AppleHealthExportImporter.round1(41.2 + progress * 3.1 + w3 * 0.25)

            let wTitle: String? = isToday ? "Tirada Larga Aeróbica" : {
                switch weekday {
                case 2: return "Fuerza Tren Superior"
                case 3: return "Carrera Base Zona 2"
                case 4: return "Fuerza Pierna e Hip Thrust"
                case 5: return "Movilidad y Cardio Ligero"
                case 6: return "Full Body + Intervalos"
                case 7: return "Tirada Larga Aeróbica"
                default: return nil
                }
            }()
            let wDur = isToday ? 86 : (wTitle != nil ? min(max(z1 + z2 + z3 + z4, 38), 92) : 0)
            let wKcal = isToday ? 999 : (wDur * 10 + 110)
            let workouts: [EffortEventItem] = wTitle.map {
                [EffortEventItem(
                    id: "sim_\(dayOffset)",
                    title: $0,
                    timeRange: isToday ? "17:30 - 18:56" : "18:00 - \(18 + wDur / 60):\(String(format: "%02d", wDur % 60))",
                    durationMin: wDur,
                    avgHrBpm: isToday ? 148 : 141,
                    strainScore: isToday ? 15.8 : strain21,
                    strainPct: strainPct,
                    categoryLabel: $0.contains("Fuerza") ? "Fuerza" : "Cardio",
                    kcal: wKcal,
                    dateIso: iso
                )]
            } ?? []

            // Generate 5-minute intraday series (only for recent 14 days to keep memory tiny & fast!)
            var stress5m: [TimedBiometricPoint] = []
            var energy5m: [TimedBiometricPoint] = []
            var s24: [Double] = []
            var e24: [Double] = []
            let peakE = min(max(Double(recPct) * 0.96, 62), 98)
            let startE = max(peakE - 34.0, 22)

            for hr in 0..<24 {
                let sleepMult = (1...8).contains(hr) ? 0.35 : 1.0
                let bump = (wTitle != nil && (17...19).contains(hr)) ? 26.0 : 0.0
                let wave = sin(Double(hr) / 23.0 * 3.0 * .pi) * 7.0
                s24.append(AppleHealthExportImporter.round1(min(max(Double(stress) * sleepMult + bump + wave, 3), 92)))
                let ev: Double = hr <= 8
                    ? startE + (peakE - startE) * (Double(hr) / 8.0)
                    : min(max(peakE - (peakE - Double(energy)) * (Double(hr - 8) / 15.0), 12), 99)
                e24.append(AppleHealthExportImporter.round1(ev))
            }

            var sleepDetail: SleepSessionDetail? = nil
            if dayOffset <= 14 {
                stress5m.reserveCapacity(288)
                energy5m.reserveCapacity(288)
                var curEnergy = startE
                for slot in 0..<288 {
                    let minOfDay = slot * 5
                    let hrF = Double(minOfDay) / 60.0
                    let isSleep = hrF >= 0.5 && hrF <= 8.2
                    let isWorkout = wTitle != nil && hrF >= 17.5 && hrF <= 19.0
                    let microWave = sin(Double(slot) * 0.42 + Double(dayOffset)) * 5.2 + cos(Double(slot) * 0.17) * 3.4
                    let baseSt = isSleep ? Double(stress) * 0.30 : (isWorkout ? 72.0 : Double(stress) * 1.06)
                    let stVal = AppleHealthExportImporter.round1(min(max(baseSt + microWave, 2.0), 94.0))
                    let ep = dayStartEpoch + Int64(minOfDay * 60)
                    stress5m.append(TimedBiometricPoint(minuteOfDay: minOfDay, value: stVal, epochSec: ep))

                    if isSleep {
                        curEnergy = min(peakE, curEnergy + (peakE - startE) / 92.0)
                    } else {
                        let drain = (stVal / 100.0) * 0.52 + (isWorkout ? 0.48 : 0.10)
                        curEnergy = max(Double(energy) - 4.0, curEnergy - drain)
                    }
                    energy5m.append(TimedBiometricPoint(minuteOfDay: minOfDay, value: AppleHealthExportImporter.round1(min(max(curEnergy, 10), 99)), epochSec: ep))
                }

                // Detailed simulated SleepSessionDetail for preview
                let startMin = 30 // 00:30
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
                    let v = AppleHealthExportImporter.round1(rhr + 3.2 + sin(Double(m) * 0.04) * 3.8 + cos(Double(m) * 0.13) * 2.1)
                    hrPts.append(TimedBiometricPoint(minuteOfDay: (startMin + m) % 1440, value: v, epochSec: ep))
                }
                var hrvPts: [TimedBiometricPoint] = []
                for m in stride(from: 45, through: max(inBedMin - 20, 45), by: 95) {
                    let ep = sleepStartEpoch + Int64(m * 60)
                    let v = AppleHealthExportImporter.round1(hrv + sin(Double(m) * 0.02) * 14.0)
                    hrvPts.append(TimedBiometricPoint(minuteOfDay: (startMin + m) % 1440, value: v, epochSec: ep))
                }
                var respPts: [TimedBiometricPoint] = []
                for m in stride(from: 10, through: inBedMin, by: 16) {
                    let ep = sleepStartEpoch + Int64(m * 60)
                    let v = AppleHealthExportImporter.round1(resp + sin(Double(m) * 0.06) * 1.1)
                    respPts.append(TimedBiometricPoint(minuteOfDay: (startMin + m) % 1440, value: v, epochSec: ep))
                }
                var spo2Pts: [TimedBiometricPoint] = []
                for m in stride(from: 35, through: inBedMin, by: 55) {
                    let ep = sleepStartEpoch + Int64(m * 60)
                    let v = AppleHealthExportImporter.round1(min(max(spo2 + cos(Double(m) * 0.05) * 1.4, 93.0), 99.5))
                    spo2Pts.append(TimedBiometricPoint(minuteOfDay: (startMin + m) % 1440, value: v, epochSec: ep))
                }

                sleepDetail = SleepSessionDetail(
                    startEpochSec: sleepStartEpoch,
                    endEpochSec: sleepEndEpoch,
                    startTimeLabel: startLabel,
                    endTimeLabel: endLabel,
                    startDateTimeLabel: "\(shortDtFmt.string(from: date)) a las \(startLabel)",
                    sourceName: "Simulación Improving",
                    awakeSeconds: awakeMin * 60,
                    remSeconds: remMin * 60,
                    coreSeconds: coreMin * 60,
                    deepSeconds: deepMin * 60,
                    latencyMinutes: 7,
                    efficiencyPct: min(max(Int((Double(asleepMin) / Double(max(inBedMin, 1)) * 100.0).rounded()), 60), 99),
                    hrDipPct: 14.2,
                    continuityPct: 94,
                    stages: stages,
                    sleepHrSamples: hrPts,
                    sleepHrvSamples: hrvPts,
                    sleepRespSamples: respPts,
                    sleepSpo2Samples: spo2Pts
                )
            }

            map[iso] = RealBiometricDaySummary(
                dateIso: iso,
                liveHrBpm: isToday ? 68 : Int(rhr.rounded()) + 14,
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
                sleepDebtMinutes: isToday ? 36 : max(480 - asleepMin, 0),
                sleepSession: sleepDetail,
                strain21: strain21,
                strainPct: strainPct,
                recoveryPct: recPct,
                stressScore: stress,
                energyBankPercent: energy,
                stepsCount: isToday ? 12480 : 7400 + (hash % 5400),
                vo2MaxMlKgMin: vo2,
                hrRecoveryBpm: isToday ? 29.0 : AppleHealthExportImporter.round1(26.0 + progress * 5.0),
                glucoseMgDl: isToday ? 94 : 92 + (hash % 9),
                activeKcal: wKcal,
                daylightMinutes: 25 + (hash % 35),
                sleepNoiseOver50Db: (hash % 5 == 0),
                bodyWeightKg: profile.weightKg,
                bodyFatPct: 16.2,
                leanMassKg: AppleHealthExportImporter.round1(profile.weightKg * 0.838),
                systolicBp: 112,
                diastolicBp: 68,
                hrZoneMinutes: zones,
                stressSeries24h: s24,
                energySeries24h: e24,
                stressSamples5m: stress5m,
                energySamples5m: energy5m,
                strengthMinutes: (wTitle?.contains("Fuerza") == true) ? wDur : (isToday ? 42 : 0),
                workouts: workouts
            )
        }
        return map
    }
}

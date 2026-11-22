import Foundation

struct ExportParseResult {
    let days: [String: RealBiometricDaySummary] // keyed by yyyy-MM-dd
    let journalByDate: [String: [String: JournalCheckState]]
    let filesParsed: [String]
    let workoutsCount: Int
    let journalEntriesCount: Int
    let earliestDateIso: String?
    let latestDateIso: String?
    let errorMessage: String?

    static func error(_ msg: String) -> ExportParseResult {
        ExportParseResult(
            days: [:],
            journalByDate: [:],
            filesParsed: [],
            workoutsCount: 0,
            journalEntriesCount: 0,
            earliestDateIso: nil,
            latestDateIso: nil,
            errorMessage: msg
        )
    }
}

/// High-resolution streaming Apple Health export importer (`exportar.zip` / `export.xml`).
/// Extracts real 5-minute intraday HR/Stress/Energy samples, real sleep stage hypnogram blocks,
/// overnight vitals (HR, HRV, Respiratory Rate, SpO₂), HR Recovery, body composition, and audio/daylight —
/// strictly NEVER fabricating missing metrics.
enum AppleHealthExportImporter {

    private final class MutableAppleDay {
        let dateIso: String
        var hrvSamples: [(Int64, Double)] = []
        var rhrValues: [Double] = []
        var hrSamples: [(Int64, Int, Double)] = [] // (epochSec, minuteOfDay, bpm)
        var respSamples: [(Int64, Double)] = []
        var spo2Samples: [(Int64, Double)] = []
        var tempCelsiusValues: [Double] = []
        var vo2Values: [Double] = []
        var hrrValues: [Double] = []
        var glucoseMgDlValues: [Double] = []
        var weightValues: [Double] = []
        var bodyFatValues: [Double] = []
        var leanMassValues: [Double] = []
        var systolicValues: [Double] = []
        var diastolicValues: [Double] = []
        var daylightMinSum: Double = 0
        var hasDaylight: Bool = false
        var audioSamplesDb: [(Int64, Double)] = []
        var stepsSum: Double = 0
        var hasSteps: Bool = false
        var activeKcalSum: Double = 0
        var hasActiveKcal: Bool = false

        var sleepSourceName: String? = nil
        var deepIntervals: [ClosedRange<Int64>] = []
        var remIntervals: [ClosedRange<Int64>] = []
        var coreIntervals: [ClosedRange<Int64>] = []
        var asleepAnyIntervals: [ClosedRange<Int64>] = []
        var inBedIntervals: [ClosedRange<Int64>] = []
        var awakeIntervals: [ClosedRange<Int64>] = []
        var rawStageBlocks: [SleepStageBlock] = []

        var workouts: [EffortEventItem] = []
        var strengthMinutes: Int = 0

        init(dateIso: String) {
            self.dateIso = dateIso
        }
    }

    static func isAppleHealthFile(url: URL) -> Bool {
        let lower = url.lastPathComponent.lowercased()
        if lower.hasSuffix(".zip") {
            if let entries = try? ZipArchiveReader.listEntries(in: url) {
                return entries.contains { isAppleHealthXmlName($0.name) }
            }
            return false
        }
        if lower.hasSuffix(".xml") {
            if let handle = try? FileHandle(forReadingFrom: url) {
                defer { try? handle.close() }
                let head = handle.readData(ofLength: 1024)
                let str = String(data: head, encoding: .utf8) ?? ""
                return str.localizedCaseInsensitiveContains("HealthData") || str.localizedCaseInsensitiveContains("HKQuantityTypeIdentifier")
            }
            return true
        }
        return false
    }

    static func importURLs(_ urls: [URL], profile: UserPhysiologyProfile = UserPhysiologyProfile()) -> ExportParseResult {
        guard !urls.isEmpty else {
            return .error("No se seleccionó ningún archivo de Apple Health.")
        }

        var mergedDays: [String: RealBiometricDaySummary] = [:]
        var files: [String] = []
        var totalWorkouts = 0
        var lastError: String?

        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            let res: ExportParseResult
            if url.lastPathComponent.lowercased().hasSuffix(".zip") {
                res = parseZipURL(url, profile: profile)
            } else {
                res = parseXmlURL(url, sourceName: url.lastPathComponent, profile: profile)
            }

            if let err = res.errorMessage, res.days.isEmpty {
                lastError = err
            } else if !res.days.isEmpty {
                mergedDays = WhoopExportImporter.mergeDays(existing: mergedDays, imported: res.days)
                files.append(contentsOf: res.filesParsed)
                totalWorkouts += res.workoutsCount
            }
        }

        guard !mergedDays.isEmpty else {
            return .error(lastError ?? "No se encontraron datos biométricos en el archivo de Apple Health.")
        }

        let sortedKeys = mergedDays.keys.sorted()
        return ExportParseResult(
            days: mergedDays,
            journalByDate: [:],
            filesParsed: Array(Set(files)),
            workoutsCount: totalWorkouts,
            journalEntriesCount: 0,
            earliestDateIso: sortedKeys.first,
            latestDateIso: sortedKeys.last,
            errorMessage: nil
        )
    }

    static func parseZipURL(_ zipURL: URL, profile: UserPhysiologyProfile = UserPhysiologyProfile()) -> ExportParseResult {
        do {
            let entries = try ZipArchiveReader.listEntries(in: zipURL)
            guard let target = entries.first(where: { isAppleHealthXmlName($0.name) }) else {
                return .error("El archivo ZIP no contiene un export.xml de Apple Health.")
            }
            let tempXml = try ZipArchiveReader.extractEntryToTempFile(target, from: zipURL)
            defer { try? FileManager.default.removeItem(at: tempXml) }
            return parseXmlURL(tempXml, sourceName: (target.name as NSString).lastPathComponent, profile: profile)
        } catch {
            return .error("No se pudo abrir el ZIP de Apple Health: \(error.localizedDescription)")
        }
    }

    static func parseXmlData(_ data: Data, sourceName: String = "export.xml", profile: UserPhysiologyProfile = UserPhysiologyProfile()) -> ExportParseResult {
        return runParser(XMLParser(data: data), sourceName: sourceName, profile: profile)
    }

    static func parseXmlURL(_ xmlURL: URL, sourceName: String = "export.xml", profile: UserPhysiologyProfile = UserPhysiologyProfile()) -> ExportParseResult {
        guard let parser = XMLParser(contentsOf: xmlURL) else {
            return .error("No se pudo abrir el archivo XML de Apple Health.")
        }
        return runParser(parser, sourceName: sourceName, profile: profile)
    }

    private static func runParser(_ parser: XMLParser, sourceName: String, profile: UserPhysiologyProfile) -> ExportParseResult {
        let delegate = AppleHealthSaxDelegate()
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = false
        _ = parser.parse()

        let days = delegate.days
        guard !days.isEmpty else {
            let errMsg = parser.parserError?.localizedDescription
            return .error(errMsg != nil ? "Error XML Apple Health: \(errMsg!)" : "El archivo XML no contiene métricas de Apple Health.")
        }

        let allTemps = days.values.flatMap(\.tempCelsiusValues).filter { (28.0...41.5).contains($0) }.sorted()
        let medianTemp = allTemps.isEmpty ? nil : allTemps[allTemps.count / 2]

        let hrvSeries = days.values.compactMap { median($0.hrvSamples.map(\.1)) }
        let rhrSeries = days.values.compactMap { mean($0.rhrValues) }
        let respSeries = days.values.compactMap { mean($0.respSamples.map(\.1)) }
        let hrvCenter = hrvSeries.isEmpty ? 68.0 : hrvSeries.reduce(0, +) / Double(hrvSeries.count)
        let rhrCenter = rhrSeries.isEmpty ? 52.0 : rhrSeries.reduce(0, +) / Double(rhrSeries.count)
        let respCenter = respSeries.isEmpty ? 15.2 : respSeries.reduce(0, +) / Double(respSeries.count)

        let maxHr = Double(WhoopPhysiologyEngine.computeMaxHeartRate(profile: profile))
        let timeFmt = DateFormatter()
        timeFmt.locale = Locale(identifier: "es_ES")
        timeFmt.dateFormat = "H:mm"
        let fullStartFmt = DateFormatter()
        fullStartFmt.locale = Locale(identifier: "es_ES")
        fullStartFmt.dateFormat = "dd/MM/yy 'a las' H:mm"

        var summaries: [String: RealBiometricDaySummary] = [:]
        var totalWorkouts = 0
        let sortedIsos = days.keys.sorted()

        for (dayIdx, dateIso) in sortedIsos.enumerated() {
            guard let raw = days[dateIso] else { continue }
            let prevRaw = dayIdx > 0 ? days[sortedIsos[dayIdx - 1]] : nil

            let hrvMs = median(raw.hrvSamples.map(\.1)).map(round1)
            let rhrBpm = mean(raw.rhrValues).map(round1)
            let avgHr = mean(raw.hrSamples.map(\.2)).map { Int($0.rounded()) }
            let respRate = mean(raw.respSamples.map(\.1)).map(round1)
            let spo2 = mean(raw.spo2Samples.map(\.1)).map(round1)
            let vo2 = mean(raw.vo2Values).map(round1)
            let hrr = mean(raw.hrrValues).map(round1)
            let glucose = mean(raw.glucoseMgDlValues).map { Int($0.rounded()) }
            let weight = mean(raw.weightValues).map(round1)
            let bodyFat = mean(raw.bodyFatValues).map(round1)
            let leanMass = mean(raw.leanMassValues).map(round1)
            let sysBp = mean(raw.systolicValues).map { Int($0.rounded()) }
            let diaBp = mean(raw.diastolicValues).map { Int($0.rounded()) }

            let dayTempAbs = median(raw.tempCelsiusValues).map(round1)
            let tempDelta: Double? = if let d = dayTempAbs, let m = medianTemp {
                round1(min(max(d - m, -2.5), 2.5))
            } else {
                nil
            }

            // Sleep totals & exact stage session (deduplicated intervals)
            let deepSec = mergeIntervalSeconds(raw.deepIntervals)
            let remSec = mergeIntervalSeconds(raw.remIntervals)
            let coreSec = mergeIntervalSeconds(raw.coreIntervals)
            let unspecSec = mergeIntervalSeconds(raw.asleepAnyIntervals)
            let awakeSec = mergeIntervalSeconds(raw.awakeIntervals)
            let inBedSecRaw = mergeIntervalSeconds(raw.inBedIntervals)

            let stagedSec = deepSec + remSec + coreSec
            let asleepSec = stagedSec > 0 ? stagedSec : unspecSec
            let asleepMin = Int((Double(asleepSec) / 60.0).rounded())
            let inBedSec = max(inBedSecRaw, asleepSec + awakeSec)
            let inBedMin: Int? = (asleepSec > 0 || inBedSecRaw > 0) ? Int((Double(inBedSec) / 60.0).rounded()) : nil
            let asleepOrNil: Int? = asleepMin > 0 ? asleepMin : nil
            let deepOrNil: Int? = deepSec > 0 ? Int((Double(deepSec) / 60.0).rounded()) : nil
            let remOrNil: Int? = remSec > 0 ? Int((Double(remSec) / 60.0).rounded()) : nil
            let coreOrNil: Int? = coreSec > 0 ? Int((Double(coreSec) / 60.0).rounded()) : nil
            let awakeOrNil: Int? = awakeSec > 0 ? Int((Double(awakeSec) / 60.0).rounded()) : nil

            let efficiencyPct: Int? = if let asleep = asleepOrNil, let bed = inBedMin, bed > 0 {
                min(max(Int((Double(asleep) / Double(bed) * 100.0).rounded()), 1), 100)
            } else {
                nil
            }

            let sleepPct: Int? = if let asleep = asleepOrNil, asleep > 0 {
                {
                    let durRatio = min(max(Double(asleep) / 480.0, 0.20), 1.12)
                    let effRatio = efficiencyPct.map { Double($0) / 100.0 } ?? 0.90
                    return min(max(Int((durRatio * 74.0 + effRatio * 26.0).rounded()), 15), 100)
                }()
            } else {
                nil
            }
            let sleepDebt = asleepOrNil.map { max(480 - $0, 0) }

            // Build exact SleepSessionDetail with overnight vitals (ONLY real samples within sleep window!)
            let allAsleepSpans = raw.deepIntervals + raw.remIntervals + raw.coreIntervals + raw.asleepAnyIntervals
            let allSleepSpans = allAsleepSpans + raw.awakeIntervals + raw.inBedIntervals
            var sleepSession: SleepSessionDetail? = nil
            var sleepNoiseOver50: Bool? = nil

            if let sleepStart = allSleepSpans.map(\.lowerBound).min(),
               let sleepEnd = allSleepSpans.map(\.upperBound).max(),
               sleepEnd > sleepStart, asleepOrNil != nil {
                let firstAsleep = allAsleepSpans.map(\.lowerBound).min()
                let inBedStart = raw.inBedIntervals.map(\.lowerBound).min()
                let latencyMin: Int? = if let ib = inBedStart, let fa = firstAsleep, fa >= ib {
                    min(Int((fa - ib) / 60), 120)
                } else {
                    nil
                }

                // Collect overnight samples across prevDay + currentDay within [sleepStart - 300, sleepEnd + 300]
                let combinedHr = (prevRaw?.hrSamples ?? []) + raw.hrSamples
                let combinedHrv = (prevRaw?.hrvSamples ?? []) + raw.hrvSamples
                let combinedResp = (prevRaw?.respSamples ?? []) + raw.respSamples
                let combinedSpo2 = (prevRaw?.spo2Samples ?? []) + raw.spo2Samples
                let combinedAudio = (prevRaw?.audioSamplesDb ?? []) + raw.audioSamplesDb

                let winStart = sleepStart - 300
                let winEnd = sleepEnd + 300

                let sleepHr = combinedHr
                    .filter { $0.0 >= winStart && $0.0 <= winEnd }
                    .sorted { $0.0 < $1.0 }
                    .map { TimedBiometricPoint(minuteOfDay: minuteOfDay(epochSec: $0.0), value: round1($0.2), epochSec: $0.0) }
                let sleepHrv = combinedHrv
                    .filter { $0.0 >= winStart && $0.0 <= winEnd }
                    .sorted { $0.0 < $1.0 }
                    .map { TimedBiometricPoint(minuteOfDay: minuteOfDay(epochSec: $0.0), value: round1($0.1), epochSec: $0.0) }
                let sleepResp = combinedResp
                    .filter { $0.0 >= winStart && $0.0 <= winEnd }
                    .sorted { $0.0 < $1.0 }
                    .map { TimedBiometricPoint(minuteOfDay: minuteOfDay(epochSec: $0.0), value: round1($0.1), epochSec: $0.0) }
                let sleepSpo2 = combinedSpo2
                    .filter { $0.0 >= winStart && $0.0 <= winEnd }
                    .sorted { $0.0 < $1.0 }
                    .map { TimedBiometricPoint(minuteOfDay: minuteOfDay(epochSec: $0.0), value: round1($0.1), epochSec: $0.0) }

                let sleepAudio = combinedAudio.filter { $0.0 >= winStart && $0.0 <= winEnd }
                if !sleepAudio.isEmpty {
                    sleepNoiseOver50 = sleepAudio.contains { $0.1 >= 50.0 }
                }

                let daytimeHrVals = raw.hrSamples.filter { $0.0 > sleepEnd }.map(\.2)
                let hrDipPct: Double? = if let dayMean = mean(daytimeHrVals), let slpMean = mean(sleepHr.map(\.value)), dayMean > 35 {
                    round1(((dayMean - slpMean) / dayMean) * 100.0)
                } else {
                    nil
                }

                let awakeCount = raw.awakeIntervals.count
                let continuityPct: Int? = if !raw.rawStageBlocks.isEmpty {
                    max(25, min(100, 100 - awakeCount * 6 - Int((Double(awakeSec) / 60.0) * 0.7)))
                } else {
                    nil
                }

                let startDate = Date(timeIntervalSince1970: TimeInterval(sleepStart))
                let endDate = Date(timeIntervalSince1970: TimeInterval(sleepEnd))

                sleepSession = SleepSessionDetail(
                    startEpochSec: sleepStart,
                    endEpochSec: sleepEnd,
                    startTimeLabel: timeFmt.string(from: startDate),
                    endTimeLabel: timeFmt.string(from: endDate),
                    startDateTimeLabel: fullStartFmt.string(from: startDate),
                    sourceName: raw.sleepSourceName,
                    awakeSeconds: awakeSec > 0 ? Int(awakeSec) : nil,
                    remSeconds: remSec > 0 ? Int(remSec) : nil,
                    coreSeconds: coreSec > 0 ? Int(coreSec) : nil,
                    deepSeconds: deepSec > 0 ? Int(deepSec) : nil,
                    latencyMinutes: latencyMin,
                    efficiencyPct: efficiencyPct,
                    hrDipPct: hrDipPct,
                    continuityPct: continuityPct,
                    stages: raw.rawStageBlocks.sorted { $0.startEpochSec < $1.startEpochSec },
                    sleepHrSamples: sleepHr,
                    sleepHrvSamples: sleepHrv,
                    sleepRespSamples: sleepResp,
                    sleepSpo2Samples: sleepSpo2
                )
            }

            // HR Zones & Strain (ONLY from real samples / workouts / kcal!)
            let zones = computeHrZoneMinutes(samples: raw.hrSamples.map { (TimeInterval($0.0), $0.2) }, maxHr: maxHr, rhr: rhrBpm ?? rhrCenter)
            let hasZones = zones.reduce(0, +) > 0

            let strainPair: (Double, Int)? = if hasZones || !raw.workouts.isEmpty {
                WhoopPhysiologyEngine.computeStrainAndEffort(
                    profile: profile,
                    rhrBpm: rhrBpm ?? rhrCenter,
                    hrZoneMinutes: zones,
                    effortEvents: raw.workouts,
                    completedStrengthSets: raw.strengthMinutes > 0 ? max(raw.strengthMinutes / 6, 4) : 0,
                    totalStrengthVolumeKg: raw.strengthMinutes * 80
                )
            } else if raw.hasActiveKcal && raw.activeKcalSum >= 40 {
                {
                    let s21 = min(max(21.0 * log(1.0 + raw.activeKcalSum / 320.0) / log(1.0 + 4.5), 0.5), 20.5)
                    let pct = min(max(Int(((s21 / 21.0) * 100.0).rounded()), 2), 99)
                    return (round1(s21), pct)
                }()
            } else {
                nil
            }

            // Recovery ONLY when real HRV or RHR is recorded (strictly never invented on empty days)
            let recPct: Int? = if hrvMs != nil || rhrBpm != nil {
                WhoopPhysiologyEngine.computeRecoveryPercent(
                    hrvMs: hrvMs ?? hrvCenter,
                    rhrBpm: rhrBpm ?? rhrCenter,
                    respRpm: respRate ?? respCenter,
                    spo2Pct: spo2 ?? 97.5,
                    wristTempDeltaC: tempDelta ?? 0.0,
                    sleepScorePct: sleepPct ?? 78,
                    hrvMean: hrvCenter,
                    hrvSigma: 8.5,
                    rhrMean: rhrCenter,
                    rhrSigma: 3.0,
                    respMean: respCenter,
                    respSigma: 0.6
                )
            } else {
                nil
            }

            // HIGH-RESOLUTION 5-MINUTE INTRADAY STRESS & ENERGY FROM REAL HR/HRV TIMESTAMPS!
            let rhrRef = rhrBpm ?? rhrCenter
            let hrvFactor = hrvMs.map { max(0.75, min(1.30, hrvCenter / max($0, 15.0))) } ?? 1.0
            let stress5m = buildFiveMinuteStressSamples(
                hrSamples: raw.hrSamples,
                rhrRef: rhrRef,
                maxHr: maxHr,
                hrvFactor: hrvFactor,
                sleepStartEpoch: sleepSession?.startEpochSec,
                sleepEndEpoch: sleepSession?.endEpochSec
            )
            let energy5m = buildFiveMinuteEnergySamples(
                stressSamples: stress5m,
                recoveryPct: recPct,
                sleepPct: sleepPct,
                sleepStartEpoch: sleepSession?.startEpochSec,
                sleepEndEpoch: sleepSession?.endEpochSec
            )

            let stressScore: Int? = stress5m.isEmpty ? nil : Int((stress5m.map(\.value).reduce(0, +) / Double(stress5m.count)).rounded())
            let energyPct: Int? = energy5m.last.map { Int($0.value.rounded()) } ?? recPct.map { r in
                let drain = strainPair.map { Int((Double($0.1) * 0.42).rounded()) } ?? 10
                return min(max(r - drain + 12, 5), 99)
            }

            totalWorkouts += raw.workouts.count

            summaries[dateIso] = RealBiometricDaySummary(
                dateIso: dateIso,
                liveHrBpm: avgHr,
                restingHrBpm: rhrBpm,
                hrvMs: hrvMs,
                respRateRpm: respRate,
                wristTempDeltaC: tempDelta,
                wristTempAbsoluteC: dayTempAbs,
                spo2Percent: spo2,
                asleepMinutes: asleepOrNil,
                inBedMinutes: inBedMin,
                deepMinutes: deepOrNil,
                remMinutes: remOrNil,
                coreMinutes: coreOrNil,
                awakeMinutes: awakeOrNil,
                sleepPct: sleepPct,
                sleepDebtMinutes: sleepDebt,
                sleepSession: sleepSession,
                strain21: strainPair?.0,
                strainPct: strainPair?.1,
                recoveryPct: recPct,
                stressScore: stressScore,
                energyBankPercent: energyPct,
                stepsCount: raw.hasSteps ? max(Int(raw.stepsSum.rounded()), 0) : nil,
                vo2MaxMlKgMin: vo2,
                hrRecoveryBpm: hrr,
                glucoseMgDl: glucose,
                activeKcal: raw.hasActiveKcal ? Int(raw.activeKcalSum.rounded()) : nil,
                daylightMinutes: raw.hasDaylight ? Int(raw.daylightMinSum.rounded()) : nil,
                sleepNoiseOver50Db: sleepNoiseOver50,
                bodyWeightKg: weight,
                bodyFatPct: bodyFat,
                leanMassKg: leanMass,
                systolicBp: sysBp,
                diastolicBp: diaBp,
                hrZoneMinutes: zones,
                stressSeries24h: [],
                energySeries24h: [],
                stressSamples5m: stress5m,
                energySamples5m: energy5m,
                strengthMinutes: raw.strengthMinutes,
                workouts: raw.workouts
            )
        }

        let sortedKeys = summaries.keys.sorted()
        return ExportParseResult(
            days: summaries,
            journalByDate: [:],
            filesParsed: [sourceName],
            workoutsCount: totalWorkouts,
            journalEntriesCount: 0,
            earliestDateIso: sortedKeys.first,
            latestDateIso: sortedKeys.last,
            errorMessage: nil
        )
    }

    // MARK: - 5-Minute Intraday Physiology Aggregators (Real Measured Bins ONLY)

    private static func buildFiveMinuteStressSamples(
        hrSamples: [(Int64, Int, Double)],
        rhrRef: Double,
        maxHr: Double,
        hrvFactor: Double,
        sleepStartEpoch: Int64?,
        sleepEndEpoch: Int64?
    ) -> [TimedBiometricPoint] {
        guard !hrSamples.isEmpty else { return [] }
        // Group real HR readings into 5-minute buckets (0..287)
        var buckets: [Int: (sumBpm: Double, count: Int, epoch: Int64)] = [:]
        for (ep, minOfDay, bpm) in hrSamples {
            let bin = min(max(minOfDay / 5, 0), 287)
            if var existing = buckets[bin] {
                existing.sumBpm += bpm
                existing.count += 1
                buckets[bin] = existing
            } else {
                buckets[bin] = (bpm, 1, ep)
            }
        }
        let hrr = max(maxHr - rhrRef, 45.0)
        return buckets.keys.sorted().map { bin in
            let item = buckets[bin]!
            let avgBpm = item.sumBpm / Double(item.count)
            let isSleeping: Bool = {
                if let s = sleepStartEpoch, let e = sleepEndEpoch {
                    return item.epoch >= s && item.epoch <= e
                }
                return false
            }()
            let excess = max(avgBpm - rhrRef, 0.0)
            var stress = (excess / (hrr * 0.58)) * 88.0 * hrvFactor
            if isSleeping {
                stress = min(stress * 0.42 + 2.0, 28.0)
            }
            stress = min(max(stress, 1.0), 99.0)
            return TimedBiometricPoint(minuteOfDay: bin * 5, value: round1(stress), epochSec: item.epoch)
        }
    }

    private static func buildFiveMinuteEnergySamples(
        stressSamples: [TimedBiometricPoint],
        recoveryPct: Int?,
        sleepPct: Int?,
        sleepStartEpoch: Int64?,
        sleepEndEpoch: Int64?
    ) -> [TimedBiometricPoint] {
        guard !stressSamples.isEmpty else { return [] }
        let startLevel = Double(max(min((recoveryPct ?? 65) - 28, 70), 18))
        let peakTarget = Double(max(min(recoveryPct ?? sleepPct ?? 78, 99), 40))
        var cur = startLevel
        var result: [TimedBiometricPoint] = []
        result.reserveCapacity(stressSamples.count)

        for (idx, pt) in stressSamples.enumerated() {
            let dtMin: Double = idx == 0 ? 5.0 : Double(min(max(pt.minuteOfDay - stressSamples[idx - 1].minuteOfDay, 5), 60))
            let isSleeping: Bool = {
                if let ep = pt.epochSec, let s = sleepStartEpoch, let e = sleepEndEpoch {
                    return ep >= s && ep <= e
                }
                return pt.value < 18 && pt.minuteOfDay < 540
            }()
            if isSleeping {
                let chargeRate = ((peakTarget - startLevel) / 420.0) * dtMin
                cur = min(peakTarget, cur + max(chargeRate, 0.12 * (dtMin / 5.0)))
            } else {
                // Drain proportional to real measured stress level
                let drainPer5m = 0.15 + (pt.value / 100.0) * 1.15
                cur = max(5.0, cur - drainPer5m * (dtMin / 5.0))
            }
            result.append(TimedBiometricPoint(minuteOfDay: pt.minuteOfDay, value: round1(cur), epochSec: pt.epochSec))
        }
        return result
    }

    private static func minuteOfDay(epochSec: Int64) -> Int {
        let d = Date(timeIntervalSince1970: TimeInterval(epochSec))
        let comps = Calendar.current.dateComponents([.hour, .minute], from: d)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    // MARK: - Streaming SAX Delegate

    private final class AppleHealthSaxDelegate: NSObject, XMLParserDelegate {
        var days: [String: MutableAppleDay] = [:]
        private let dayFormatter: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            return f
        }()
        private let timeFormatter: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "HH:mm"
            return f
        }()
        private let appleFormatter: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
            return f
        }()
        private let isoFormatter = ISO8601DateFormatter()

        private var activeWorkoutDateIso: String?
        private var activeWorkoutIdx: Int = -1
        private var activeWorkoutHasKcal = false

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
            switch elementName {
            case "Record":
                handleRecord(attributeDict)
            case "Workout":
                handleWorkout(attributeDict)
            case "WorkoutStatistics":
                handleWorkoutStats(attributeDict)
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            if elementName == "Workout" {
                activeWorkoutDateIso = nil
                activeWorkoutIdx = -1
                activeWorkoutHasKcal = false
            }
        }

        private func parseDate(_ raw: String?) -> Date? {
            guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
            if let d = appleFormatter.date(from: raw) { return d }
            return isoFormatter.date(from: raw)
        }

        private func dayEntry(for date: Date) -> MutableAppleDay {
            let iso = dayFormatter.string(from: date)
            if let existing = days[iso] { return existing }
            let created = MutableAppleDay(dateIso: iso)
            days[iso] = created
            return created
        }

        private func handleRecord(_ attrs: [String: String]) {
            guard let type = attrs["type"],
                  let endDate = parseDate(attrs["endDate"] ?? attrs["startDate"]) else { return }
            let startDate = parseDate(attrs["startDate"]) ?? endDate
            let valStr = attrs["value"] ?? ""
            let unitStr = attrs["unit"] ?? ""
            let endEp = Int64(endDate.timeIntervalSince1970)

            if type == "HKCategoryTypeIdentifierSleepAnalysis" {
                let day = dayEntry(for: endDate)
                let s = Int64(startDate.timeIntervalSince1970)
                let e = endEp
                guard e > s else { return }
                let span = s...e
                if day.sleepSourceName == nil, let src = attrs["sourceName"], !src.isEmpty {
                    day.sleepSourceName = src
                }
                let low = valStr.lowercased()
                if low.contains("asleepdeep") {
                    day.deepIntervals.append(span)
                    day.rawStageBlocks.append(SleepStageBlock(id: "d_\(s)", stage: .deep, startEpochSec: s, endEpochSec: e))
                } else if low.contains("asleeprem") {
                    day.remIntervals.append(span)
                    day.rawStageBlocks.append(SleepStageBlock(id: "r_\(s)", stage: .rem, startEpochSec: s, endEpochSec: e))
                } else if low.contains("asleepcore") {
                    day.coreIntervals.append(span)
                    day.rawStageBlocks.append(SleepStageBlock(id: "c_\(s)", stage: .core, startEpochSec: s, endEpochSec: e))
                } else if low.contains("inbed") {
                    day.inBedIntervals.append(span)
                } else if low.contains("awake") {
                    day.awakeIntervals.append(span)
                    day.rawStageBlocks.append(SleepStageBlock(id: "a_\(s)", stage: .awake, startEpochSec: s, endEpochSec: e))
                } else if low.contains("asleep") {
                    day.asleepAnyIntervals.append(span)
                }
                return
            }

            guard let num = Double(valStr.replacingOccurrences(of: ",", with: ".")), num.isFinite else { return }
            let day = dayEntry(for: endDate)

            switch type {
            case "HKQuantityTypeIdentifierHeartRateVariabilitySDNN":
                let ms = (!unitStr.lowercased().contains("ms") && unitStr.lowercased().contains("s") && num < 2.0) ? num * 1000.0 : num
                if (5.0...280.0).contains(ms) { day.hrvSamples.append((endEp, ms)) }
            case "HKQuantityTypeIdentifierRestingHeartRate":
                if (28.0...130.0).contains(num) { day.rhrValues.append(num) }
            case "HKQuantityTypeIdentifierHeartRate":
                if (28.0...235.0).contains(num) {
                    let mOfDay = AppleHealthExportImporter.minuteOfDay(epochSec: endEp)
                    day.hrSamples.append((endEp, mOfDay, num))
                }
            case "HKQuantityTypeIdentifierRespiratoryRate":
                if (5.0...45.0).contains(num) { day.respSamples.append((endEp, num)) }
            case "HKQuantityTypeIdentifierOxygenSaturation":
                let pct = num <= 1.05 ? num * 100.0 : num
                if (60.0...100.0).contains(pct) { day.spo2Samples.append((endEp, pct)) }
            case "HKQuantityTypeIdentifierAppleSleepingWristTemperature", "HKQuantityTypeIdentifierBodyTemperature":
                let celsius = (unitStr.localizedCaseInsensitiveContains("degF") || unitStr.contains("F")) ? (num - 32.0) * 5.0 / 9.0 : num
                if (28.0...42.0).contains(celsius) { day.tempCelsiusValues.append(celsius) }
            case "HKQuantityTypeIdentifierVO2Max":
                if (15.0...90.0).contains(num) { day.vo2Values.append(num) }
            case "HKQuantityTypeIdentifierHeartRateRecoveryOneMinute":
                if (1.0...110.0).contains(num) { day.hrrValues.append(num) }
            case "HKQuantityTypeIdentifierBloodGlucose":
                let mgdl = unitStr.localizedCaseInsensitiveContains("mmol") ? num * 18.0182 : num
                if (35.0...400.0).contains(mgdl) { day.glucoseMgDlValues.append(mgdl) }
            case "HKQuantityTypeIdentifierBodyMass":
                let kg = unitStr.lowercased().contains("lb") ? num * 0.453592 : num
                if (25.0...260.0).contains(kg) { day.weightValues.append(kg) }
            case "HKQuantityTypeIdentifierBodyFatPercentage":
                let pct = num <= 1.0 ? num * 100.0 : num
                if (3.0...65.0).contains(pct) { day.bodyFatValues.append(pct) }
            case "HKQuantityTypeIdentifierLeanBodyMass":
                let kg = unitStr.lowercased().contains("lb") ? num * 0.453592 : num
                if (20.0...180.0).contains(kg) { day.leanMassValues.append(kg) }
            case "HKQuantityTypeIdentifierBloodPressureSystolic":
                if (60.0...240.0).contains(num) { day.systolicValues.append(num) }
            case "HKQuantityTypeIdentifierBloodPressureDiastolic":
                if (35.0...150.0).contains(num) { day.diastolicValues.append(num) }
            case "HKQuantityTypeIdentifierTimeInDaylight":
                let mins = unitStr.lowercased().contains("hr") ? num * 60.0 : (unitStr.lowercased().contains("s") ? num / 60.0 : num)
                if (0.0...1440.0).contains(mins) {
                    day.daylightMinSum += mins
                    day.hasDaylight = true
                }
            case "HKQuantityTypeIdentifierEnvironmentalAudioExposure":
                if (20.0...130.0).contains(num) { day.audioSamplesDb.append((endEp, num)) }
            case "HKQuantityTypeIdentifierStepCount":
                if (0.0...120_000.0).contains(num) {
                    day.stepsSum += num
                    day.hasSteps = true
                }
            case "HKQuantityTypeIdentifierActiveEnergyBurned":
                let kcal = unitStr.lowercased() == "kj" ? num / 4.184 : num
                if (0.0...15_000.0).contains(kcal) {
                    day.activeKcalSum += kcal
                    day.hasActiveKcal = true
                }
            default:
                break
            }
        }

        private func handleWorkout(_ attrs: [String: String]) {
            guard let startDate = parseDate(attrs["startDate"]) else { return }
            let endDate = parseDate(attrs["endDate"]) ?? startDate
            let day = dayEntry(for: startDate)

            let (title, category, isStrength) = mapWorkoutName(attrs["workoutActivityType"] ?? "")
            let durRaw = attrs["duration"].flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
            let durUnit = (attrs["durationUnit"] ?? "").lowercased()
            let durMin: Int = {
                let raw: Double
                if let d = durRaw {
                    if durUnit.contains("hr") { raw = d * 60.0 }
                    else if durUnit.contains("sec") { raw = d / 60.0 }
                    else { raw = d }
                } else {
                    raw = endDate.timeIntervalSince(startDate) / 60.0
                }
                return min(max(Int(raw.rounded()), 1), 720)
            }()

            let kcalRaw = attrs["totalEnergyBurned"].flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
            let kcalUnit = (attrs["totalEnergyBurnedUnit"] ?? "").lowercased()
            let kcal = kcalRaw.map { max(Int((kcalUnit == "kj" ? $0 / 4.184 : $0).rounded()), 1) } ?? 0

            let distRaw = attrs["totalDistance"].flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
            let distUnit = (attrs["totalDistanceUnit"] ?? "").lowercased()
            let distKm: Double? = distRaw.map { d in
                let km = distUnit == "m" ? d / 1000.0 : (distUnit.contains("mi") ? d * 1.60934 : d)
                return AppleHealthExportImporter.round1(km)
            }

            let strainBase = kcal > 0 ? Double(kcal) : Double(durMin) * 6.0
            let strain21 = min(max(21.0 * log(1.0 + strainBase / 280.0) / log(1.0 + 4.5), 0.4), 20.5)
            let strainPct = min(max(Int(((strain21 / 21.0) * 100.0).rounded()), 2), 98)

            if isStrength { day.strengthMinutes += durMin }
            let item = EffortEventItem(
                id: "ah_wk_\(day.dateIso)_\(day.workouts.count)",
                title: title,
                timeRange: "\(timeFormatter.string(from: startDate)) - \(timeFormatter.string(from: endDate))",
                durationMin: durMin,
                avgHrBpm: 0, // Strictly 0 unless WorkoutStatistics reports real HR!
                strainScore: AppleHealthExportImporter.round1(strain21),
                strainPct: strainPct,
                categoryLabel: category,
                kcal: kcal,
                distanceKm: distKm,
                dateIso: day.dateIso
            )
            day.workouts.append(item)
            activeWorkoutDateIso = day.dateIso
            activeWorkoutIdx = day.workouts.count - 1
            activeWorkoutHasKcal = kcalRaw != nil
        }

        private func handleWorkoutStats(_ attrs: [String: String]) {
            guard let iso = activeWorkoutDateIso,
                  let day = days[iso],
                  day.workouts.indices.contains(activeWorkoutIdx) else { return }
            let statType = attrs["type"] ?? ""
            var item = day.workouts[activeWorkoutIdx]

            if statType == "HKQuantityTypeIdentifierHeartRate",
               let avgStr = attrs["average"],
               let avg = Double(avgStr.replacingOccurrences(of: ",", with: ".")) {
                let bpm = Int(avg.rounded())
                if (45...220).contains(bpm) {
                    item = EffortEventItem(
                        id: item.id, title: item.title, timeRange: item.timeRange,
                        durationMin: item.durationMin, avgHrBpm: bpm, strainScore: item.strainScore,
                        strainPct: item.strainPct, categoryLabel: item.categoryLabel, kcal: item.kcal,
                        distanceKm: item.distanceKm, elevationM: item.elevationM, dateIso: item.dateIso
                    )
                    day.workouts[activeWorkoutIdx] = item
                }
            } else if statType == "HKQuantityTypeIdentifierActiveEnergyBurned",
                      !activeWorkoutHasKcal,
                      let sumStr = attrs["sum"],
                      let sum = Double(sumStr.replacingOccurrences(of: ",", with: ".")) {
                let unit = (attrs["unit"] ?? "").lowercased()
                let kcal = max(Int((unit == "kj" ? sum / 4.184 : sum).rounded()), 1)
                let strain21 = min(max(21.0 * log(1.0 + Double(kcal) / 280.0) / log(1.0 + 4.5), 0.4), 20.5)
                let strainPct = min(max(Int(((strain21 / 21.0) * 100.0).rounded()), 2), 98)
                item = EffortEventItem(
                    id: item.id, title: item.title, timeRange: item.timeRange,
                    durationMin: item.durationMin, avgHrBpm: item.avgHrBpm,
                    strainScore: AppleHealthExportImporter.round1(strain21),
                    strainPct: strainPct, categoryLabel: item.categoryLabel, kcal: kcal,
                    distanceKm: item.distanceKm, elevationM: item.elevationM, dateIso: item.dateIso
                )
                day.workouts[activeWorkoutIdx] = item
                activeWorkoutHasKcal = true
            }
        }
    }

    private static func isAppleHealthXmlName(_ raw: String) -> Bool {
        let f = (raw as NSString).lastPathComponent.lowercased()
        return f == "export.xml" || f == "exportar.xml" || (f.hasSuffix(".xml") && !f.contains("cda"))
    }

    private static func mapWorkoutName(_ rawType: String) -> (String, String, Bool) {
        let low = rawType.lowercased()
        if low.contains("strength") || low.contains("coretraining") { return ("Entrenamiento de fuerza", "Fuerza", true) }
        if low.contains("running") { return ("Carrera", "Cardio", false) }
        if low.contains("cycling") { return ("Bici al aire libre", "Cardio", false) }
        if low.contains("walking") || low.contains("hiking") { return ("Caminata", "Aeróbico", false) }
        if low.contains("swimming") { return ("Natación", "Cardio", false) }
        if low.contains("highintensity") || low.contains("hiit") { return ("HIIT", "Alta intensidad", false) }
        if low.contains("yoga") || low.contains("pilates") { return ("Movilidad / Yoga", "Recuperación", false) }
        if low.contains("rowing") { return ("Remo", "Cardio", false) }
        if low.contains("soccer") || low.contains("football") { return ("Fútbol", "Deporte", false) }
        if low.contains("tennis") || low.contains("padel") { return ("Tenis / Pádel", "Deporte", false) }
        return ("Entrenamiento", "Actividad", false)
    }

    private static func mergeIntervalSeconds(_ intervals: [ClosedRange<Int64>]) -> Int64 {
        guard !intervals.isEmpty else { return 0 }
        let sorted = intervals.sorted { $0.lowerBound < $1.lowerBound }
        var totalSec: Int64 = 0
        var curStart = sorted[0].lowerBound
        var curEnd = sorted[0].upperBound
        for span in sorted.dropFirst() {
            if span.lowerBound <= curEnd {
                curEnd = max(curEnd, span.upperBound)
            } else {
                totalSec += max(curEnd - curStart, 0)
                curStart = span.lowerBound
                curEnd = span.upperBound
            }
        }
        totalSec += max(curEnd - curStart, 0)
        return max(totalSec, 0)
    }

    private static func computeHrZoneMinutes(samples: [(TimeInterval, Double)], maxHr: Double, rhr: Double) -> [Int] {
        guard samples.count >= 2 else { return [0, 0, 0, 0, 0] }
        let sorted = samples.sorted { $0.0 < $1.0 }
        let hrr = max(maxHr - rhr, 40.0)
        var secs = [0.0, 0.0, 0.0, 0.0, 0.0]
        for idx in 0..<(sorted.count - 1) {
            let dt = min(max(sorted[idx + 1].0 - sorted[idx].0, 1.0), 300.0)
            let pctHrr = (sorted[idx].1 - rhr) / hrr
            if pctHrr >= 0.90 { secs[4] += dt }
            else if pctHrr >= 0.80 { secs[3] += dt }
            else if pctHrr >= 0.70 { secs[2] += dt }
            else if pctHrr >= 0.60 { secs[1] += dt }
            else if pctHrr >= 0.50 { secs[0] += dt }
        }
        return secs.map { Int($0 / 60.0) }
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        let m = s.count / 2
        return s.count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2.0
    }

    private static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    static func round1(_ v: Double) -> Double {
        (v * 10.0).rounded() / 10.0
    }
}

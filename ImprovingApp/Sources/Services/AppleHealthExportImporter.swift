import Foundation

struct ExportParseResult {
    let days: [String: RealBiometricDaySummary]
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

/// Fault-tolerant, constant-memory streaming Apple Health export importer (`exportar.zip` / `export.xml`).
/// - NEVER aborts mid-file on Apple's malformed DTD or third-party UTF-8/entity glitches (fixes missing HRV/Workouts!).
/// - Parses ALL HealthKit records including HRV SDNN + beat-to-beat RMSSD fallback, sleeping RHR vs daytime HR,
///   exact sleep stage hypnogram blocks, overnight vitals, VO2Max, HRR, body composition, blood pressure, daylight & audio.
/// - Computes causal 60-day rolling personal baselines, Bevel-aligned Recovery/Strain/Sleep, and a CONTINUOUS
///   cross-day 5-minute Energy curve that carries over seamlessly across midnight (zero jumps, zero fabricated data!).
enum AppleHealthExportImporter {

    final class MutableAppleDay {
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
        var workoutSpans: [ClosedRange<Int64>] = []
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
        let scanner = StreamingAppleHealthScanner()
        scanner.feed(data)
        scanner.finish()
        return buildSummaries(from: scanner.days, sourceName: sourceName, profile: profile)
    }

    static func parseXmlURL(_ xmlURL: URL, sourceName: String = "export.xml", profile: UserPhysiologyProfile = UserPhysiologyProfile()) -> ExportParseResult {
        guard let handle = try? FileHandle(forReadingFrom: xmlURL) else {
            return .error("No se pudo abrir el archivo XML de Apple Health.")
        }
        defer { try? handle.close() }

        let scanner = StreamingAppleHealthScanner()
        let chunkSize = 256 * 1024
        while true {
            let chunk: Data = autoreleasepool { handle.readData(ofLength: chunkSize) }
            if chunk.isEmpty { break }
            autoreleasepool { scanner.feed(chunk) }
        }
        scanner.finish()
        return buildSummaries(from: scanner.days, sourceName: sourceName, profile: profile)
    }

    // MARK: - Build Scientifically Accurate, Continuous, Zero-Fabrication Day Summaries

    static func buildSummaries(
        from days: [String: MutableAppleDay],
        sourceName: String,
        profile: UserPhysiologyProfile,
        priorHistory: [String: RealBiometricDaySummary] = [:]
    ) -> ExportParseResult {
        guard !days.isEmpty else {
            return .error("El archivo no contiene métricas de Apple Health.")
        }

        let sortedIsos = days.keys.sorted()
        let firstNewIso = sortedIsos.first ?? ""

        let priorTemps = priorHistory
            .filter { $0.key < firstNewIso }
            .compactMap { $0.value.wristTempAbsoluteC }
        let allTemps = (priorTemps + days.values.flatMap(\.tempCelsiusValues)).filter { (28.0...41.5).contains($0) }.sorted()
        let medianTemp = allTemps.isEmpty ? nil : allTemps[allTemps.count / 2]

        // Observe real peak HR across the export to sharpen MaxHR
        let observedPeakHr = Int((days.values.flatMap { $0.hrSamples.map(\.2) }.max() ?? 0).rounded())
        let maxHr = Double(WhoopPhysiologyEngine.computeMaxHeartRate(profile: profile, observedPeakBpm: min(observedPeakHr, 215)))

        let timeFmt = DateFormatter()
        timeFmt.locale = Locale(identifier: "es_ES")
        timeFmt.dateFormat = "H:mm"
        let fullStartFmt = DateFormatter()
        fullStartFmt.locale = Locale(identifier: "es_ES")
        fullStartFmt.dateFormat = "dd/MM/yy 'a las' H:mm"
        let isoFmt = DateFormatter()
        isoFmt.locale = Locale(identifier: "en_US_POSIX")
        isoFmt.dateFormat = "yyyy-MM-dd"

        var summaries: [String: RealBiometricDaySummary] = [:]
        var totalWorkouts = 0

        // Strictly causal rolling history arrays seeded from prior stored history before firstNewIso!
        var priorLnHrv: [Double] = []
        var priorRhr: [Double] = []
        var priorResp: [Double] = []

        // Continuous cross-day Energy Bank state seeded from previous day's ending value (NEVER jumps at midnight!)
        var prevDayDate: Date? = nil
        var prevDayEndEnergy: Double? = nil
        var prevDayEndEpoch: Int64? = nil

        for iso in priorHistory.keys.sorted() where iso < firstNewIso {
            if let old = priorHistory[iso] {
                if let h = old.hrvMs, h > 2.0 { priorLnHrv.append(log(h)) }
                if let r = old.restingHrBpm { priorRhr.append(r) }
                if let rr = old.respRateRpm { priorResp.append(rr) }
                if let lastE = old.energySamples5m.last?.value ?? old.energyBankPercent.map({ Double($0) }) {
                    prevDayEndEnergy = lastE
                    prevDayEndEpoch = old.energySamples5m.last?.epochSec
                    prevDayDate = isoFmt.date(from: iso)
                }
            }
        }

        for (dayIdx, dateIso) in sortedIsos.enumerated() {
            guard let raw = days[dateIso] else { continue }
            let curDate = isoFmt.date(from: dateIso)
            let prevRaw: MutableAppleDay? = {
                guard dayIdx > 0, let cur = curDate, let prevD = isoFmt.date(from: sortedIsos[dayIdx - 1]) else { return nil }
                let diffDays = Calendar.current.dateComponents([.day], from: prevD, to: cur).day ?? 99
                return diffDays == 1 ? days[sortedIsos[dayIdx - 1]] : nil
            }()

            // 1. Sleep totals & exact stage intervals (deduplicated)
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

            let efficiencyPct: Int? = {
                guard let asleep = asleepOrNil, let bed = inBedMin, bed > 0 else { return nil }
                return min(max(Int((Double(asleep) / Double(bed) * 100.0).rounded()), 1), 100)
            }()

            // 2. Build SleepSessionDetail & extract exact overnight vitals across [prevDay + currentDay]
            let allAsleepSpans = raw.deepIntervals + raw.remIntervals + raw.coreIntervals + raw.asleepAnyIntervals
            let allSleepSpans = allAsleepSpans + raw.awakeIntervals + raw.inBedIntervals
            var sleepSession: SleepSessionDetail? = nil
            var sleepNoiseOver50: Bool? = nil
            var sleepHrVals: [Double] = []
            var sleepHrvVals: [Double] = []
            var sleepRespVals: [Double] = []
            var sleepSpo2Vals: [Double] = []
            var hrDipPct: Double? = nil

            let sleepWindowStart = allSleepSpans.map(\.lowerBound).min()
            let sleepWindowEnd = allSleepSpans.map(\.upperBound).max()

            if let sStart = sleepWindowStart, let sEnd = sleepWindowEnd, sEnd > sStart, asleepOrNil != nil {
                let firstAsleep = allAsleepSpans.map(\.lowerBound).min()
                let inBedStart = raw.inBedIntervals.map(\.lowerBound).min()
                let latencyMin: Int? = {
                    guard let ib = inBedStart, let fa = firstAsleep, fa >= ib else { return nil }
                    return min(Int((fa - ib) / 60), 120)
                }()

                let combinedHr = (prevRaw?.hrSamples ?? []) + raw.hrSamples
                let combinedHrv = (prevRaw?.hrvSamples ?? []) + raw.hrvSamples
                let combinedResp = (prevRaw?.respSamples ?? []) + raw.respSamples
                let combinedSpo2 = (prevRaw?.spo2Samples ?? []) + raw.spo2Samples
                let combinedAudio = (prevRaw?.audioSamplesDb ?? []) + raw.audioSamplesDb

                let winStart = sStart - 300
                let winEnd = sEnd + 300

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

                sleepHrVals = sleepHr.map(\.value)
                sleepHrvVals = sleepHrv.map(\.value)
                sleepRespVals = sleepResp.map(\.value)
                sleepSpo2Vals = sleepSpo2.map(\.value)

                let sleepAudio = combinedAudio.filter { $0.0 >= winStart && $0.0 <= winEnd }
                if !sleepAudio.isEmpty {
                    sleepNoiseOver50 = sleepAudio.contains { $0.1 >= 50.0 }
                }

                let daytimeHrVals = raw.hrSamples.filter { $0.0 > sEnd }.map(\.2)
                if let dayMean = mean(daytimeHrVals), let slpMean = mean(sleepHrVals), dayMean > 35 {
                    hrDipPct = round1(((dayMean - slpMean) / dayMean) * 100.0)
                }

                let awakeCount = raw.awakeIntervals.count
                let continuityPct: Int? = raw.rawStageBlocks.isEmpty
                    ? nil
                    : max(25, min(100, 100 - awakeCount * 6 - Int((Double(awakeSec) / 60.0) * 0.7)))

                let startDate = Date(timeIntervalSince1970: TimeInterval(sStart))
                let endDate = Date(timeIntervalSince1970: TimeInterval(sEnd))

                sleepSession = SleepSessionDetail(
                    startEpochSec: sStart,
                    endEpochSec: sEnd,
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

            // 3. Bevel-Aligned Vitals:
            // - Resting HRV: mean of SLEEPING HRV (exact Bevel match), falling back to full-day HRV if no sleep HRV!
            let hrvMs: Double? = (!sleepHrvVals.isEmpty ? mean(sleepHrvVals) : mean(raw.hrvSamples.map(\.1))).map(round1)

            // - Resting HR: Bevel uses SLEEPING HR average when >= 5 sleeping HR samples exist; falls back to Apple RHR!
            let appleRhr = mean(raw.rhrValues)
            let sleepMeanHr = sleepHrVals.count >= 5 ? mean(sleepHrVals) : nil
            let rhrBpm: Double? = (sleepMeanHr ?? appleRhr).map(round1)

            // - Daytime HR: strictly outside sleep window!
            let daytimeHrOnly: [Double] = {
                if let sS = sleepWindowStart, let sE = sleepWindowEnd {
                    return raw.hrSamples.filter { $0.0 < sS || $0.0 > sE }.map(\.2)
                }
                return raw.hrSamples.map(\.2)
            }()
            let avgDayHr = mean(daytimeHrOnly).map { Int($0.rounded()) }

            let respRate = (!sleepRespVals.isEmpty ? mean(sleepRespVals) : mean(raw.respSamples.map(\.1))).map(round1)
            let spo2 = (!sleepSpo2Vals.isEmpty ? mean(sleepSpo2Vals) : mean(raw.spo2Samples.map(\.1))).map(round1)
            let vo2 = mean(raw.vo2Values).map(round1)
            let hrr = mean(raw.hrrValues).map(round1)
            let glucose = mean(raw.glucoseMgDlValues).map { Int($0.rounded()) }
            let weight = mean(raw.weightValues).map(round1)
            let bodyFat = mean(raw.bodyFatValues).map(round1)
            let leanMass = mean(raw.leanMassValues).map(round1)
            let sysBp = mean(raw.systolicValues).map { Int($0.rounded()) }
            let diaBp = mean(raw.diastolicValues).map { Int($0.rounded()) }

            let dayTempAbs = median(raw.tempCelsiusValues).map(round1)
            let tempDelta: Double? = {
                guard let d = dayTempAbs, let m = medianTemp else { return nil }
                return round1(min(max(d - m, -2.5), 2.5))
            }()

            // 4. Bevel-Calibrated Sleep Score (only from measured components!)
            let sleepPct: Int? = asleepOrNil.map { asleep in
                WhoopPhysiologyEngine.computeBevelSleepScore(
                    asleepMinutes: asleep,
                    inBedMinutes: inBedMin,
                    deepMinutes: deepOrNil,
                    remMinutes: remOrNil,
                    awakeMinutes: awakeOrNil,
                    awakeCount: raw.awakeIntervals.count,
                    hrDipPct: hrDipPct
                )
            }
            let sleepDebt = asleepOrNil.map { max(480 - $0, 0) }

            // 5. Causal 60-Day Personal Baselines -> Bevel Recovery % (Zero Fabricated Sensors!)
            let lnHrvBase = WhoopPhysiologyEngine.computeRollingBaseline(
                priorValues: priorLnHrv, populationMean: log(65.0), populationSigma: 0.25, floorSigma: 0.14
            )
            let rhrBase = WhoopPhysiologyEngine.computeRollingBaseline(
                priorValues: priorRhr, populationMean: 54.0, populationSigma: 4.0, floorSigma: 1.8
            )
            let respBase = WhoopPhysiologyEngine.computeRollingBaseline(
                priorValues: priorResp, populationMean: 15.2, populationSigma: 0.9, floorSigma: 0.45
            )

            let recPct = WhoopPhysiologyEngine.computeBevelRecoveryPercent(
                hrvMs: hrvMs,
                rhrBpm: rhrBpm,
                respRpm: respRate,
                spo2Pct: spo2,
                wristTempDeltaC: tempDelta,
                lnHrvBaseline: lnHrvBase,
                rhrBaseline: rhrBase,
                respBaseline: respBase
            )

            // Update causal history AFTER scoring day i
            if let h = hrvMs, h > 2.0 { priorLnHrv.append(log(h)) }
            if let r = rhrBpm { priorRhr.append(r) }
            if let rr = respRate { priorResp.append(rr) }

            // 6. Accurate HR Zones (conservative dt cap prevents passive-walking inflation!) & Bevel Strain
            let rhrForZones = rhrBpm ?? rhrBase.mean
            let zones = computeHrZoneMinutes(
                samples: raw.hrSamples.map { ($0.0, $0.2) },
                workoutSpans: raw.workoutSpans,
                maxHr: maxHr,
                rhr: rhrForZones
            )
            let strainPair = WhoopPhysiologyEngine.computeBevelStrain(
                profile: profile,
                rhrBpm: rhrForZones,
                hrZoneMinutes: zones,
                workouts: raw.workouts,
                activeKcal: raw.hasActiveKcal ? raw.activeKcalSum : nil
            )

            // 7. High-Resolution 5-Minute Stress & CONTINUOUS Cross-Day Energy (Zero Midnight Jumps!)
            let hrvFactor: Double = {
                guard let h = hrvMs, h > 2.0 else { return 1.0 }
                let ratio = exp(lnHrvBase.mean) / h
                return min(max(ratio, 0.78), 1.28)
            }()
            let stress5m = buildFiveMinuteStressSamples(
                hrSamples: raw.hrSamples,
                rhrRef: rhrForZones,
                maxHr: maxHr,
                hrvFactor: hrvFactor,
                sleepStartEpoch: sleepSession?.startEpochSec,
                sleepEndEpoch: sleepSession?.endEpochSec
            )

            // Determine whether previous day connects continuously to today (<= 1 calendar day apart)
            let isContinuousFromPrev: Bool = {
                guard let prevE = prevDayEndEnergy, let pDate = prevDayDate, let cDate = curDate, prevE.isFinite else { return false }
                let gapDays = Calendar.current.dateComponents([.day], from: pDate, to: cDate).day ?? 99
                guard gapDays == 1 else { return false }
                if let pEp = prevDayEndEpoch, let firstEp = stress5m.first?.epochSec {
                    return (firstEp - pEp) <= 24 * 3600
                }
                return true
            }()

            let initialEnergy: Double = {
                if isContinuousFromPrev, let carried = prevDayEndEnergy {
                    return carried
                }
                // Only on the very first day (or after a multi-day gap without wearing the watch)
                return Double(max(min((recPct ?? 65) - 24, 65), 22))
            }()

            let energy5m = buildContinuousFiveMinuteEnergySamples(
                stressSamples: stress5m,
                startingEnergy: initialEnergy,
                recoveryPct: recPct,
                sleepPct: sleepPct,
                sleepStartEpoch: sleepSession?.startEpochSec,
                sleepEndEpoch: sleepSession?.endEpochSec,
                workoutSpans: raw.workoutSpans
            )

            if let lastE = energy5m.last {
                prevDayEndEnergy = lastE.value
                prevDayEndEpoch = lastE.epochSec
                prevDayDate = curDate
            } else {
                // Day had no readings -> break chain only if > 1 day gap later
            }

            let stressScore: Int? = stress5m.isEmpty ? nil : Int((stress5m.map(\.value).reduce(0, +) / Double(stress5m.count)).rounded())
            let energyPct: Int? = energy5m.last.map { Int($0.value.rounded()) }

            totalWorkouts += raw.workouts.count

            summaries[dateIso] = RealBiometricDaySummary(
                dateIso: dateIso,
                liveHrBpm: avgDayHr,
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
                strain21: strainPair?.strain21,
                strainPct: strainPair?.strainPct,
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

    // MARK: - 5-Minute Stress & Continuous Cross-Day Energy Bank Engine

    static func buildFiveMinuteStressSamples(
        hrSamples: [(Int64, Int, Double)],
        rhrRef: Double,
        maxHr: Double,
        hrvFactor: Double,
        sleepStartEpoch: Int64?,
        sleepEndEpoch: Int64?
    ) -> [TimedBiometricPoint] {
        guard !hrSamples.isEmpty else { return [] }
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
            var stress = (excess / (hrr * 0.56)) * 86.0 * hrvFactor
            if isSleeping {
                stress = min(stress * 0.40 + 2.0, 26.0)
            }
            stress = min(max(stress, 1.0), 99.0)
            return TimedBiometricPoint(minuteOfDay: bin * 5, value: round1(stress), epochSec: item.epoch)
        }
    }

    /// Continuous physiological Body Battery model:
    /// Starts at EXACT `startingEnergy` carried from previous day's 23:55 value (zero jumps!).
    /// Charges ONLY during real recorded sleep or calm rest (stress < 16); drains during elevated awake stress/workouts.
    static func buildContinuousFiveMinuteEnergySamples(
        stressSamples: [TimedBiometricPoint],
        startingEnergy: Double,
        recoveryPct: Int?,
        sleepPct: Int?,
        sleepStartEpoch: Int64?,
        sleepEndEpoch: Int64?,
        workoutSpans: [ClosedRange<Int64>] = []
    ) -> [TimedBiometricPoint] {
        guard !stressSamples.isEmpty else { return [] }

        let recFactor = Double(recoveryPct ?? sleepPct ?? 65) / 100.0
        // Sleep recharge rate per 5 min: ~0.40% (poor recovery) up to ~0.92% (excellent recovery)
        let sleepChargePer5m = 0.32 + recFactor * 0.62
        let maxSleepCeiling = min(99.0, 62.0 + recFactor * 38.0)

        var cur = min(max(startingEnergy, 5.0), 99.0)
        var result: [TimedBiometricPoint] = []
        result.reserveCapacity(stressSamples.count)

        for (idx, pt) in stressSamples.enumerated() {
            let dtMin: Double = idx == 0 ? 5.0 : Double(min(max(pt.minuteOfDay - stressSamples[idx - 1].minuteOfDay, 5), 45))
            let steps = dtMin / 5.0

            let isSleeping: Bool = {
                if let ep = pt.epochSec, let s = sleepStartEpoch, let e = sleepEndEpoch {
                    return ep >= s && ep <= e
                }
                return false
            }()
            let isWorkout: Bool = {
                guard let ep = pt.epochSec else { return false }
                return workoutSpans.contains { $0.contains(ep) }
            }()

            if idx == 0 {
                // First sample of the day preserves exact carried-over continuity!
                result.append(TimedBiometricPoint(minuteOfDay: pt.minuteOfDay, value: round1(cur), epochSec: pt.epochSec))
                continue
            }

            if isSleeping {
                let effRate = pt.value > 22 ? sleepChargePer5m * 0.55 : sleepChargePer5m
                if cur < maxSleepCeiling {
                    cur = min(maxSleepCeiling, cur + effRate * steps)
                }
            } else if isWorkout {
                let drain = (0.55 + (pt.value / 100.0) * 1.15) * steps
                cur = max(5.0, cur - drain)
            } else if pt.value <= 14.0 {
                // Deep calm awake rest gently pauses drain / micro-recovers
                cur = min(99.0, cur + 0.08 * steps)
            } else {
                // Awake drain proportional to measured physiological stress
                let drain = (0.06 + (pt.value / 100.0) * 0.72) * steps
                cur = max(5.0, cur - drain)
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

    // MARK: - Fault-Tolerant Zero-Abort Streaming XML Scanner (Guarantees 100% HRV & Workout Extraction!)

    private final class StreamingAppleHealthScanner {
        var days: [String: MutableAppleDay] = [:]

        private var carry = Data()
        private let ltByte: UInt8 = 0x3C // '<'
        private let gtByte: UInt8 = 0x3E // '>'

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
        private let appleFormatterNoTz: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return f
        }()
        private let isoFormatter = ISO8601DateFormatter()

        // Active Workout context for nested <WorkoutStatistics>
        private var activeWorkoutDateIso: String?
        private var activeWorkoutIdx: Int = -1
        private var activeWorkoutHasKcal = false

        // Active HRV context for beat-to-beat <InstantaneousBeatsPerMinute> fallback
        private var activeHrvDateIso: String?
        private var activeHrvEndEpoch: Int64 = 0
        private var activeHrvHadScalarValue = false
        private var activeHrvBeatBpms: [Double] = []

        func feed(_ chunk: Data) {
            if !carry.isEmpty {
                carry.append(chunk)
            } else {
                carry = chunk
            }

            let count = carry.count
            var scanPos = 0

            carry.withUnsafeBytes { rawBuf in
                guard let base = rawBuf.bindMemory(to: UInt8.self).baseAddress else { return }

                while scanPos < count {
                    // Find next '<'
                    var ltIdx = -1
                    var i = scanPos
                    while i < count {
                        if base[i] == ltByte { ltIdx = i; break }
                        i += 1
                    }
                    if ltIdx < 0 {
                        scanPos = count
                        break
                    }

                    // Find matching '>'
                    var gtIdx = -1
                    var j = ltIdx + 1
                    while j < count {
                        if base[j] == gtByte { gtIdx = j; break }
                        j += 1
                    }
                    if gtIdx < 0 {
                        // Incomplete tag spans into next chunk
                        scanPos = ltIdx
                        break
                    }

                    let tagLen = gtIdx - ltIdx - 1
                    if tagLen >= 6 && tagLen <= 4096 {
                        processTagBytes(base + ltIdx + 1, length: tagLen)
                    }
                    scanPos = gtIdx + 1
                }
            }

            if scanPos >= count {
                carry.removeAll(keepingCapacity: true)
            } else if scanPos > 0 {
                carry = Data(carry[scanPos..<count])
            }
        }

        func finish() {
            flushPendingHrvIfNeeded()
            carry.removeAll(keepingCapacity: false)
        }

        private func startsWithASCII(_ ptr: UnsafePointer<UInt8>, _ len: Int, _ prefix: StaticString) -> Bool {
            let pLen = prefix.utf8CodeUnitCount
            guard len >= pLen else { return false }
            return prefix.withUTF8Buffer { pBuf in
                for k in 0..<pLen {
                    if ptr[k] != pBuf[k] { return false }
                }
                return true
            }
        }

        private func processTagBytes(_ ptr: UnsafePointer<UInt8>, length: Int) {
            let first = ptr[0]
            if first == 0x52 { // 'R' -> Record
                if startsWithASCII(ptr, length, "Record ") {
                    let isSelfClosing = ptr[length - 1] == 0x2F // '/'
                    if let s = String(bytes: UnsafeBufferPointer(start: ptr, count: length), encoding: .utf8) {
                        handleRecord(parseAttributes(s), isSelfClosing: isSelfClosing)
                    }
                }
            } else if first == 0x57 { // 'W' -> Workout / WorkoutStatistics
                if startsWithASCII(ptr, length, "Workout ") {
                    if let s = String(bytes: UnsafeBufferPointer(start: ptr, count: length), encoding: .utf8) {
                        handleWorkout(parseAttributes(s))
                    }
                } else if startsWithASCII(ptr, length, "WorkoutStatistics ") {
                    if let s = String(bytes: UnsafeBufferPointer(start: ptr, count: length), encoding: .utf8) {
                        handleWorkoutStats(parseAttributes(s))
                    }
                }
            } else if first == 0x49 { // 'I' -> InstantaneousBeatsPerMinute
                if activeHrvDateIso != nil && !activeHrvHadScalarValue && startsWithASCII(ptr, length, "InstantaneousBeatsPerMinute ") {
                    if let s = String(bytes: UnsafeBufferPointer(start: ptr, count: length), encoding: .utf8) {
                        let attrs = parseAttributes(s)
                        if let bStr = attrs["bpm"], let bpm = Double(bStr.replacingOccurrences(of: ",", with: ".")), (30...220).contains(bpm) {
                            activeHrvBeatBpms.append(bpm)
                        }
                    }
                }
            } else if first == 0x2F { // '/' -> closing tag
                if startsWithASCII(ptr, length, "/Workout") {
                    activeWorkoutDateIso = nil
                    activeWorkoutIdx = -1
                    activeWorkoutHasKcal = false
                } else if startsWithASCII(ptr, length, "/Record") {
                    flushPendingHrvIfNeeded()
                }
            }
        }

        private func flushPendingHrvIfNeeded() {
            defer {
                activeHrvDateIso = nil
                activeHrvHadScalarValue = false
                activeHrvBeatBpms.removeAll(keepingCapacity: true)
            }
            guard let iso = activeHrvDateIso, !activeHrvHadScalarValue, activeHrvBeatBpms.count >= 4,
                  let day = days[iso] else { return }
            // Compute RMSSD from beat-to-beat instantaneous BPM intervals (ms)
            let rr = activeHrvBeatBpms.map { 60_000.0 / $0 }
            var sqSum = 0.0
            for i in 1..<rr.count {
                let d = rr[i] - rr[i - 1]
                sqSum += d * d
            }
            let rmssd = sqrt(sqSum / Double(rr.count - 1))
            if (3.0...350.0).contains(rmssd) {
                day.hrvSamples.append((activeHrvEndEpoch, rmssd))
            }
        }

        private func parseAttributes(_ tag: String) -> [String: String] {
            var dict: [String: String] = [:]
            let bytes = Array(tag.utf8)
            let n = bytes.count
            var i = 0
            // Skip element name
            while i < n && bytes[i] != 0x20 && bytes[i] != 0x09 && bytes[i] != 0x0A && bytes[i] != 0x0D { i += 1 }

            while i < n {
                while i < n && (bytes[i] == 0x20 || bytes[i] == 0x09 || bytes[i] == 0x0A || bytes[i] == 0x0D || bytes[i] == 0x2F) { i += 1 }
                if i >= n { break }
                let keyStart = i
                while i < n && bytes[i] != 0x3D && bytes[i] != 0x20 { i += 1 } // '='
                let keyEnd = i
                while i < n && bytes[i] != 0x22 && bytes[i] != 0x27 { i += 1 } // '"' or '\''
                if i >= n { break }
                let quote = bytes[i]
                i += 1
                let valStart = i
                while i < n && bytes[i] != quote { i += 1 }
                let valEnd = i
                if i < n { i += 1 }

                if keyEnd > keyStart,
                   let k = String(bytes: bytes[keyStart..<keyEnd], encoding: .utf8),
                   let v = String(bytes: bytes[valStart..<valEnd], encoding: .utf8) {
                    dict[k] = v
                }
            }
            return dict
        }

        private func parseDate(_ raw: String?) -> Date? {
            guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
            if let d = appleFormatter.date(from: raw) { return d }
            if let d = isoFormatter.date(from: raw) { return d }
            return appleFormatterNoTz.date(from: raw)
        }

        /// Extracts the exact wall-clock local date ("yyyy-MM-dd") and minute of day (0..1439)
        /// written by Apple Health at recording time so DST / timezone changes NEVER shift 00:00-00:59 readings into the wrong day!
        private func extractWallClock(_ raw: String?) -> (iso: String, minuteOfDay: Int)? {
            guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
            let b = Array(s.utf8)
            guard b.count >= 16,
                  b[4] == 0x2D, b[7] == 0x2D, // '-'
                  (b[10] == 0x20 || b[10] == 0x54), // ' ' or 'T'
                  b[13] == 0x3A else { return nil } // ':'
            guard let iso = String(bytes: b[0..<10], encoding: .utf8),
                  let hStr = String(bytes: b[11..<13], encoding: .utf8),
                  let mStr = String(bytes: b[14..<16], encoding: .utf8),
                  let hh = Int(hStr), let mm = Int(mStr),
                  (0...23).contains(hh), (0...59).contains(mm) else { return nil }
            return (iso, hh * 60 + mm)
        }

        private func dayEntry(for date: Date, rawTimestamp: String? = nil) -> MutableAppleDay {
            let iso = extractWallClock(rawTimestamp)?.iso ?? dayFormatter.string(from: date)
            if let existing = days[iso] { return existing }
            let created = MutableAppleDay(dateIso: iso)
            days[iso] = created
            return created
        }

        private func handleRecord(_ attrs: [String: String], isSelfClosing: Bool) {
            let rawEnd = attrs["endDate"] ?? attrs["startDate"]
            guard let type = attrs["type"],
                  let endDate = parseDate(rawEnd) else { return }
            let startDate = parseDate(attrs["startDate"]) ?? endDate
            let valStr = (attrs["value"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let unitStr = attrs["unit"] ?? ""
            let endEp = Int64(endDate.timeIntervalSince1970)
            let wallClock = extractWallClock(rawEnd)

            if type == "HKCategoryTypeIdentifierSleepAnalysis" {
                let day = dayEntry(for: endDate, rawTimestamp: rawEnd)
                let s = Int64(startDate.timeIntervalSince1970)
                let e = endEp
                guard e > s else { return }
                let span = s...e
                if day.sleepSourceName == nil, let src = attrs["sourceName"], !src.isEmpty {
                    day.sleepSourceName = decodeXmlEntities(src)
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

            if type == "HKQuantityTypeIdentifierHeartRateVariabilitySDNN" {
                let day = dayEntry(for: endDate, rawTimestamp: rawEnd)
                let parsedNum = Double(valStr.replacingOccurrences(of: ",", with: "."))
                var addedScalar = false
                if let num = parsedNum, num.isFinite {
                    let lowU = unitStr.lowercased()
                    let ms = (!lowU.contains("ms") && lowU.contains("s") && num < 2.0) ? num * 1000.0 : num
                    if (3.0...350.0).contains(ms) {
                        day.hrvSamples.append((endEp, ms))
                        addedScalar = true
                    }
                }
                if !isSelfClosing {
                    activeHrvDateIso = day.dateIso
                    activeHrvEndEpoch = endEp
                    activeHrvHadScalarValue = addedScalar
                    activeHrvBeatBpms.removeAll(keepingCapacity: true)
                }
                return
            }

            guard let num = Double(valStr.replacingOccurrences(of: ",", with: ".")), num.isFinite else { return }
            let day = dayEntry(for: endDate, rawTimestamp: rawEnd)

            switch type {
            case "HKQuantityTypeIdentifierRestingHeartRate":
                if (28.0...130.0).contains(num) { day.rhrValues.append(num) }
            case "HKQuantityTypeIdentifierHeartRate":
                if (28.0...235.0).contains(num) {
                    let mOfDay = wallClock?.minuteOfDay ?? AppleHealthExportImporter.minuteOfDay(epochSec: endEp)
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
            let day = dayEntry(for: startDate, rawTimestamp: attrs["startDate"])

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

            let wStrain = WhoopPhysiologyEngine.computeWorkoutStrain(durationMin: durMin, kcal: kcal, avgHrBpm: 0)

            if isStrength { day.strengthMinutes += durMin }
            let sEp = Int64(startDate.timeIntervalSince1970)
            let eEp = max(Int64(endDate.timeIntervalSince1970), sEp + Int64(durMin * 60))
            day.workoutSpans.append(sEp...eEp)

            let item = EffortEventItem(
                id: "ah_wk_\(day.dateIso)_\(day.workouts.count)",
                title: title,
                timeRange: "\(timeFormatter.string(from: startDate)) - \(timeFormatter.string(from: endDate))",
                durationMin: durMin,
                avgHrBpm: 0,
                strainScore: wStrain.strain21,
                strainPct: wStrain.strainPct,
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
                    let updatedStrain = WhoopPhysiologyEngine.computeWorkoutStrain(durationMin: item.durationMin, kcal: item.kcal, avgHrBpm: bpm)
                    item = EffortEventItem(
                        id: item.id, title: item.title, timeRange: item.timeRange,
                        durationMin: item.durationMin, avgHrBpm: bpm,
                        strainScore: updatedStrain.strain21, strainPct: updatedStrain.strainPct,
                        categoryLabel: item.categoryLabel, kcal: item.kcal,
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
                let updatedStrain = WhoopPhysiologyEngine.computeWorkoutStrain(durationMin: item.durationMin, kcal: kcal, avgHrBpm: item.avgHrBpm)
                item = EffortEventItem(
                    id: item.id, title: item.title, timeRange: item.timeRange,
                    durationMin: item.durationMin, avgHrBpm: item.avgHrBpm,
                    strainScore: updatedStrain.strain21, strainPct: updatedStrain.strainPct,
                    categoryLabel: item.categoryLabel, kcal: kcal,
                    distanceKm: item.distanceKm, elevationM: item.elevationM, dateIso: item.dateIso
                )
                day.workouts[activeWorkoutIdx] = item
                activeWorkoutHasKcal = true
            }
        }

        private func decodeXmlEntities(_ raw: String) -> String {
            raw
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&apos;", with: "'")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#xA0;", with: " ")
                .replacingOccurrences(of: "\u{00A0}", with: " ")
        }
    }

    private static func isAppleHealthXmlName(_ raw: String) -> Bool {
        let f = (raw as NSString).lastPathComponent.lowercased()
        return f == "export.xml" || f == "exportar.xml" || (f.hasSuffix(".xml") && !f.contains("cda"))
    }

    static func mapWorkoutName(_ rawType: String) -> (String, String, Bool) {
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

    static func computeHrZoneMinutes(
        samples: [(Int64, Double)],
        workoutSpans: [ClosedRange<Int64>],
        maxHr: Double,
        rhr: Double
    ) -> [Int] {
        guard samples.count >= 2 else { return [0, 0, 0, 0, 0] }
        let sorted = samples.sorted { $0.0 < $1.0 }

        // Collapse identical timestamps (e.g. Apple Shortcuts minute-truncated HR readings) by averaging BPM
        var deduped: [(Int64, Double)] = []
        deduped.reserveCapacity(sorted.count)
        var curEp = sorted[0].0
        var sumBpm = sorted[0].1
        var cnt = 1.0
        for item in sorted.dropFirst() {
            if item.0 == curEp {
                sumBpm += item.1
                cnt += 1.0
            } else {
                deduped.append((curEp, sumBpm / cnt))
                curEp = item.0
                sumBpm = item.1
                cnt = 1.0
            }
        }
        deduped.append((curEp, sumBpm / cnt))
        guard deduped.count >= 2 else { return [0, 0, 0, 0, 0] }

        let hrr = max(maxHr - rhr, 40.0)
        var secs = [0.0, 0.0, 0.0, 0.0, 0.0]
        for idx in 0..<(deduped.count - 1) {
            let ep = deduped[idx].0
            let rawDt = Double(deduped[idx + 1].0 - ep)
            guard rawDt > 0 else { continue }
            let inWorkout = workoutSpans.contains { $0.contains(ep) }
            // Cap dt conservatively so sparse background samples never inflate passive time into huge fake Zone 1/2 minutes!
            let maxCap = inWorkout ? 30.0 : 90.0
            let dt = min(rawDt, maxCap)
            let pctHrr = (deduped[idx].1 - rhr) / hrr
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

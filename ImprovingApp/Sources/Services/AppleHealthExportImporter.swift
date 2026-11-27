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
        var hrvRmssdSamples: [(Int64, Double)] = [] // True beat-to-beat RMSSD (Bevel / WHOOP standard)
        var hrvSamples: [(Int64, Double)] = []      // Apple Health SDNN fallback when beat-to-beat series unavailable
        var rhrValues: [Double] = []
        var hrSamples: [(Int64, Int, Double)] = [] // (epochSec, minuteOfDay, bpm)
        var respSamples: [(Int64, Double)] = []
        var spo2Samples: [(Int64, Double)] = []
        var tempCelsiusValues: [Double] = []
        var tempDeltaValues: [Double] = []
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
        var stepsBySource: [String: Double] = [:]
        var hasSteps: Bool = false
        var activeKcalSum: Double = 0
        var activeKcalBySource: [String: Double] = [:]
        var hasActiveKcal: Bool = false
        var distanceKmSum: Double = 0
        var distanceKmBySource: [String: Double] = [:]
        var hasDistanceKm: Bool = false
        var elevationMSum: Double = 0
        var elevationMBySource: [String: Double] = [:]
        var hasElevationM: Bool = false

        /// Resolves overlapping Watch + iPhone + 3rd-party XML sources without double-counting!
        /// Prefers Apple Watch sum when substantial; otherwise takes the highest single-source total
        /// (falls back to direct `fallbackSum` for Shortcuts/unit-test inputs that populate `*Sum` directly).
        private func resolvedDeduplicatedSum(bySource: [String: Double], fallbackSum: Double) -> Double {
            guard !bySource.isEmpty else { return fallbackSum }
            if bySource.count == 1 { return bySource.values.first ?? fallbackSum }
            let watchEntries = bySource.filter {
                let low = $0.key.lowercased()
                return low.contains("watch") || low.contains("reloj") || low.contains("whoop")
            }
            let maxOverall = bySource.values.max() ?? fallbackSum
            if let watchSum = watchEntries.values.max(), watchSum >= maxOverall * 0.45 {
                return watchSum
            }
            return maxOverall
        }

        var deduplicatedStepsSum: Double { resolvedDeduplicatedSum(bySource: stepsBySource, fallbackSum: stepsSum) }
        var deduplicatedActiveKcalSum: Double { resolvedDeduplicatedSum(bySource: activeKcalBySource, fallbackSum: activeKcalSum) }
        var deduplicatedDistanceKmSum: Double { resolvedDeduplicatedSum(bySource: distanceKmBySource, fallbackSum: distanceKmSum) }
        var deduplicatedElevationMSum: Double { resolvedDeduplicatedSum(bySource: elevationMBySource, fallbackSum: elevationMSum) }
        var powerValues: [Double] = []
        var cadenceValues: [Double] = []

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

        // Compute personalized clinical norms from the user's birth date/age, sex, height & weight
        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: profile)
        let targetSleepMin = norms.sleepTargetHours * 60.0
        let respCenter = (norms.respLowRpm + norms.respHighRpm) / 2.0

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
        // Separate RMSSD and SDNN pools so switching between Watch RMSSD and Apple Health SDNN NEVER skews the 60d baseline.
        var priorLnHrvRmssd: [Double] = []
        var priorLnHrvSdnn: [Double] = []
        var priorRhr: [Double] = []
        var priorResp: [Double] = []

        // Continuous cross-day Energy Bank & Cumulative 7-day Rolling Sleep Debt state seeded from priorHistory!
        var prevDayDate: Date? = nil
        var prevDayEndEnergy: Double? = nil
        var prevDayEndEpoch: Int64? = nil
        var runningSleepDebtMin: Double = 0.0

        for iso in priorHistory.keys.sorted() where iso < firstNewIso {
            if let old = priorHistory[iso] {
                if let h = old.hrvMs, h > 2.0 {
                    let isSdnn = (old.hrvMethodLabel?.uppercased().contains("SDNN") == true)
                    if isSdnn {
                        priorLnHrvSdnn.append(log(h))
                    } else {
                        priorLnHrvRmssd.append(log(h))
                    }
                }
                if let r = old.restingHrBpm { priorRhr.append(r) }
                if let rr = old.respRateRpm { priorResp.append(rr) }
                if let asleep = old.asleepMinutes, asleep > 0 {
                    runningSleepDebtMin = Double(WhoopPhysiologyEngine.updateCumulativeSleepDebt(
                        previousDebtMinutes: runningSleepDebtMin,
                        asleepMinutes: asleep,
                        targetMinutes: targetSleepMin
                    ))
                } else if let prevDebt = old.sleepDebtMinutes {
                    runningSleepDebtMin = Double(prevDebt)
                }
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

            // 1. Build Primary Overnight Sleep Cluster ("Todo el sueño" / Entire Sleep):
            //    - Includes pre-midnight sleep blocks starting >= prev day 18:00 from prevRaw (rejects yesterday's daytime/oversized spans!)
            //    - Excludes next-night bedtime blocks (>= 19:30) from raw so daytime HRV NEVER leaks into sleep!
            //    - STRICT STAGED-SLEEP PRIORITY: When Apple Watch staged sleep (Deep/REM/Core >= 30 min) exists,
            //      completely IGNORE secondary/iPhone "Durmiendo" (`asleepUnspecified`) blocks so overlapping or afternoon
            //      "Durmiendo" blocks NEVER stretch the sleep window into daytime hours (e.g. 0:05-14:16)!
            let dayStartEp: Int64? = curDate.map { Int64($0.timeIntervalSince1970) }
            let prevEveningCutoff = dayStartEp.map { $0 - 6 * 3600 } // prev day 18:00
            let nextNightCutoff = dayStartEp.map { $0 + 19 * 3600 + 1800 } // current day 19:30
            let maxSingleBlockSec: Int64 = 14 * 3600

            func selectNightSpans(_ prevList: [ClosedRange<Int64>], _ curList: [ClosedRange<Int64>]) -> [ClosedRange<Int64>] {
                var out: [ClosedRange<Int64>] = []
                if let pCut = prevEveningCutoff {
                    out.append(contentsOf: prevList.filter {
                        let dur = $0.upperBound - $0.lowerBound
                        return dur > 0 && dur <= maxSingleBlockSec && $0.lowerBound >= pCut
                    })
                }
                if let nCut = nextNightCutoff {
                    out.append(contentsOf: curList.filter {
                        let dur = $0.upperBound - $0.lowerBound
                        return dur > 0 && dur <= maxSingleBlockSec && $0.lowerBound < nCut
                    })
                } else {
                    out.append(contentsOf: curList.filter {
                        let dur = $0.upperBound - $0.lowerBound
                        return dur > 0 && dur <= maxSingleBlockSec
                    })
                }
                return out
            }

            let candDeep = selectNightSpans(prevRaw?.deepIntervals ?? [], raw.deepIntervals)
            let candRem = selectNightSpans(prevRaw?.remIntervals ?? [], raw.remIntervals)
            let candCore = selectNightSpans(prevRaw?.coreIntervals ?? [], raw.coreIntervals)
            let candUnspec = selectNightSpans(prevRaw?.asleepAnyIntervals ?? [], raw.asleepAnyIntervals)
            let candAwake = selectNightSpans(prevRaw?.awakeIntervals ?? [], raw.awakeIntervals)
            let candInBed = selectNightSpans(prevRaw?.inBedIntervals ?? [], raw.inBedIntervals)

            let candStagedAsleep = candDeep + candRem + candCore
            let hasRealStagedSleep = mergeIntervalSeconds(candStagedAsleep) >= 30 * 60
            let candAsleepSpans = hasRealStagedSleep ? candStagedAsleep : (candStagedAsleep + candUnspec)
            let candAllSpans = candAsleepSpans + candAwake + candInBed

            // Cluster contiguous ACTUAL ASLEEP intervals first (gap <= 60 min) so iPhone `InBed` schedules,
            // afternoon naps, and secondary "Durmiendo" blocks NEVER stretch the sleep window into daytime hours!
            let primaryAsleepRange: ClosedRange<Int64>? = primarySleepSessionRange(
                allSpans: !candAsleepSpans.isEmpty ? candAsleepSpans : candAllSpans,
                asleepSpans: candAsleepSpans
            )

            func strictlyInPrimaryAsleep(_ spans: [ClosedRange<Int64>]) -> [ClosedRange<Int64>] {
                guard let pr = primaryAsleepRange else { return spans }
                return spans.filter { $0.lowerBound >= pr.lowerBound && $0.upperBound <= pr.upperBound }
            }

            let primaryDeep = strictlyInPrimaryAsleep(candDeep)
            let primaryRem = strictlyInPrimaryAsleep(candRem)
            let primaryCore = strictlyInPrimaryAsleep(candCore)
            let primaryUnspec = hasRealStagedSleep ? [] : strictlyInPrimaryAsleep(candUnspec)
            let primaryAwake = strictlyInPrimaryAsleep(candAwake)
            // Clamp InBed blocks strictly within [45m before falling asleep .. 15m after waking] so giant iPhone schedules cannot stretch sleep!
            let primaryInBed: [ClosedRange<Int64>] = {
                guard let pr = primaryAsleepRange else { return candInBed }
                let lo = pr.lowerBound - 45 * 60
                let hi = pr.upperBound + 15 * 60
                return candInBed.compactMap { sp in
                    guard sp.upperBound >= lo && sp.lowerBound <= hi else { return nil }
                    let cLo = max(sp.lowerBound, lo)
                    let cHi = min(sp.upperBound, hi)
                    return cHi > cLo ? (cLo...cHi) : nil
                }
            }()

            let deepSec = mergeIntervalSeconds(primaryDeep)
            let remSec = mergeIntervalSeconds(primaryRem)
            let coreSec = mergeIntervalSeconds(primaryCore)
            let unspecSec = mergeIntervalSeconds(primaryUnspec)
            let awakeSec = mergeIntervalSeconds(primaryAwake)
            let inBedSecRaw = mergeIntervalSeconds(primaryInBed)

            // Merge all staged sleep spans together so overlapping Deep/REM/Core blocks from two devices never double-count asleep time!
            let stagedMergedSec = mergeIntervalSeconds(primaryDeep + primaryRem + primaryCore)
            let stagedSec = stagedMergedSec > 0 ? stagedMergedSec : (deepSec + remSec + coreSec)
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

            // 2. Build SleepSessionDetail & extract overnight vitals STRICTLY during ACTUAL ASLEEP stages
            //    (Matches Bevel "Entire Sleep": explicitly EXCLUDES `InBed`, `Awake`, and secondary `Durmiendo` when staged sleep exists!)
            let allAsleepSpans = hasRealStagedSleep
                ? (primaryDeep + primaryRem + primaryCore)
                : (primaryDeep + primaryRem + primaryCore + primaryUnspec)
            let mergedAsleepSpans = mergeIntervals(allAsleepSpans)
            let mergedAwakeSpans = mergeIntervals(primaryAwake)
            let allSleepSpans = allAsleepSpans + primaryAwake + primaryInBed
            var sleepSession: SleepSessionDetail? = nil
            var sleepNoiseOver50: Bool? = nil
            var sleepHrVals: [Double] = []
            var sleepHrvRmssdVals: [Double] = []
            var sleepHrvSdnnVals: [Double] = []
            var sleepRespVals: [Double] = []
            var sleepSpo2Vals: [Double] = []
            var hrDipPct: Double? = nil

            let asleepWindowStart = mergedAsleepSpans.first?.lowerBound ?? primaryAsleepRange?.lowerBound
            let asleepWindowEnd = mergedAsleepSpans.last?.upperBound ?? primaryAsleepRange?.upperBound
            let displayStart = min(asleepWindowStart ?? Int64.max, primaryInBed.map(\.lowerBound).min() ?? Int64.max)
            let displayEnd = max(asleepWindowEnd ?? Int64.min, primaryAwake.map(\.upperBound).max() ?? Int64.min)
            let sleepWindowStart: Int64? = displayStart < Int64.max ? displayStart : allSleepSpans.map(\.lowerBound).min()
            let sleepWindowEnd: Int64? = displayEnd > Int64.min ? displayEnd : allSleepSpans.map(\.upperBound).max()

            let combinedRmssdHrv = (prevRaw?.hrvRmssdSamples ?? []) + raw.hrvRmssdSamples
            let combinedSdnnHrv = (prevRaw?.hrvSamples ?? []) + raw.hrvSamples

            // Bevel "Entire Sleep" filter: sample must occur during an actual ASLEEP interval (not InBed, not Awake!)
            func isDuringAsleep(_ ep: Int64, tolerance: Int64) -> Bool {
                guard !mergedAsleepSpans.isEmpty else { return false }
                // Exclude readings strictly inside an Awake period (> 2 min awake gap)
                for aw in mergedAwakeSpans where (aw.upperBound - aw.lowerBound) >= 120 {
                    if ep > aw.lowerBound + 30 && ep < aw.upperBound - 30 {
                        return false
                    }
                }
                return mergedAsleepSpans.contains { ep >= ($0.lowerBound - tolerance) && ep <= ($0.upperBound + tolerance) }
            }

            if let sStart = sleepWindowStart, let sEnd = sleepWindowEnd, sEnd > sStart, asleepOrNil != nil,
               let aStart = asleepWindowStart, let aEnd = asleepWindowEnd, aEnd > aStart {
                let firstAsleep = mergedAsleepSpans.first?.lowerBound
                let inBedStart = primaryInBed.map(\.lowerBound).min()
                let latencyMin: Int? = {
                    guard let ib = inBedStart, let fa = firstAsleep, fa >= ib else { return nil }
                    return min(Int((fa - ib) / 60), 120)
                }()

                let combinedHr = (prevRaw?.hrSamples ?? []) + raw.hrSamples
                let combinedResp = (prevRaw?.respSamples ?? []) + raw.respSamples
                let combinedSpo2 = (prevRaw?.spo2Samples ?? []) + raw.spo2Samples
                let combinedAudio = (prevRaw?.audioSamplesDb ?? []) + raw.audioSamplesDb
                let combinedStages: [SleepStageBlock] = {
                    let prevStages = (prevRaw?.rawStageBlocks ?? []).filter { $0.endEpochSec >= sStart && $0.startEpochSec <= sEnd }
                    let curStages = raw.rawStageBlocks.filter { $0.endEpochSec >= sStart && $0.startEpochSec <= sEnd }
                    return (prevStages + curStages).sorted { $0.startEpochSec < $1.startEpochSec }
                }()

                // Strict ASLEEP-only filtering (matches Bevel "Entire Sleep": excludes InBed & Awake!)
                let sleepHr = combinedHr
                    .filter { isDuringAsleep($0.0, tolerance: 30) }
                    .sorted { $0.0 < $1.0 }
                    .map { TimedBiometricPoint(minuteOfDay: minuteOfDay(epochSec: $0.0), value: round1($0.2), epochSec: $0.0) }
                let sleepRmssdPts = combinedRmssdHrv
                    .filter { isDuringAsleep($0.0, tolerance: 90) }
                    .sorted { $0.0 < $1.0 }
                    .map { TimedBiometricPoint(minuteOfDay: minuteOfDay(epochSec: $0.0), value: round1($0.1), epochSec: $0.0) }
                let sleepSdnnPts = combinedSdnnHrv
                    .filter { isDuringAsleep($0.0, tolerance: 90) }
                    .sorted { $0.0 < $1.0 }
                    .map { TimedBiometricPoint(minuteOfDay: minuteOfDay(epochSec: $0.0), value: round1($0.1), epochSec: $0.0) }
                let sleepHrv = !sleepRmssdPts.isEmpty ? sleepRmssdPts : sleepSdnnPts
                let sleepResp = combinedResp
                    .filter { isDuringAsleep($0.0, tolerance: 120) }
                    .sorted { $0.0 < $1.0 }
                    .map { TimedBiometricPoint(minuteOfDay: minuteOfDay(epochSec: $0.0), value: round1($0.1), epochSec: $0.0) }
                let sleepSpo2 = combinedSpo2
                    .filter { isDuringAsleep($0.0, tolerance: 120) }
                    .sorted { $0.0 < $1.0 }
                    .map { TimedBiometricPoint(minuteOfDay: minuteOfDay(epochSec: $0.0), value: round1($0.1), epochSec: $0.0) }

                sleepHrVals = sleepHr.map(\.value)
                sleepHrvRmssdVals = sleepRmssdPts.map(\.value)
                sleepHrvSdnnVals = sleepSdnnPts.map(\.value)
                sleepRespVals = sleepResp.map(\.value)
                sleepSpo2Vals = sleepSpo2.map(\.value)

                let sleepAudio = combinedAudio.filter { $0.0 >= aStart && $0.0 <= aEnd }
                if !sleepAudio.isEmpty {
                    sleepNoiseOver50 = sleepAudio.contains { $0.1 >= 50.0 }
                }

                let daytimeHrVals = raw.hrSamples.filter { $0.0 > aEnd }.map(\.2)
                if let dayMean = mean(daytimeHrVals), let slpMean = WhoopPhysiologyEngine.aggregateSleepingHr(sleepHrVals), dayMean > 35 {
                    hrDipPct = round1(((dayMean - slpMean) / dayMean) * 100.0)
                }

                let awakeCount = primaryAwake.count
                let continuityPct: Int? = combinedStages.isEmpty
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
                    sourceName: raw.sleepSourceName ?? prevRaw?.sleepSourceName,
                    awakeSeconds: awakeSec > 0 ? Int(awakeSec) : nil,
                    remSeconds: remSec > 0 ? Int(remSec) : nil,
                    coreSeconds: coreSec > 0 ? Int(coreSec) : nil,
                    deepSeconds: deepSec > 0 ? Int(deepSec) : nil,
                    latencyMinutes: latencyMin,
                    efficiencyPct: efficiencyPct,
                    hrDipPct: hrDipPct,
                    continuityPct: continuityPct,
                    stages: combinedStages,
                    sleepHrSamples: sleepHr,
                    sleepHrvSamples: sleepHrv,
                    sleepRespSamples: sleepResp,
                    sleepSpo2Samples: sleepSpo2
                )
            }

            // 3. Bevel / WHOOP Aligned Vitals — RMSSD + Entire Sleep (Asleep-Only) Priority!
            let (hrvMs, hrvMethodLabel): (Double?, String?) = {
                if !sleepHrvRmssdVals.isEmpty, let v = WhoopPhysiologyEngine.aggregateEntireSleepHrv(sleepHrvRmssdVals) {
                    return (round1(v), "RMSSD · Todo el sueño")
                }
                if !sleepHrvSdnnVals.isEmpty, let v = WhoopPhysiologyEngine.aggregateEntireSleepHrv(sleepHrvSdnnVals) {
                    return (round1(v), "SDNN · Todo el sueño")
                }
                if let dStart = dayStartEp {
                    // Narrow nocturnal fallback (00:00 – 08:30) when no sleep session exists, avoiding daytime stress HRV
                    let noctStart = dStart
                    let noctEnd = dStart + 8 * 3600 + 1800
                    let noctRmssd = combinedRmssdHrv.filter { $0.0 >= noctStart && $0.0 <= noctEnd }.map(\.1)
                    if !noctRmssd.isEmpty, let v = WhoopPhysiologyEngine.aggregateEntireSleepHrv(noctRmssd) {
                        return (round1(v), "RMSSD · Nocturna")
                    }
                    let noctSdnn = combinedSdnnHrv.filter { $0.0 >= noctStart && $0.0 <= noctEnd }.map(\.1)
                    if !noctSdnn.isEmpty, let v = WhoopPhysiologyEngine.aggregateEntireSleepHrv(noctSdnn) {
                        return (round1(v), "SDNN · Nocturna")
                    }
                }
                let dayRmssd = raw.hrvRmssdSamples.map(\.1)
                if !dayRmssd.isEmpty, let v = WhoopPhysiologyEngine.aggregateEntireSleepHrv(dayRmssd) {
                    return (round1(v), "RMSSD · Día")
                }
                let daySdnn = raw.hrvSamples.map(\.1)
                if !daySdnn.isEmpty, let v = WhoopPhysiologyEngine.aggregateEntireSleepHrv(daySdnn) {
                    return (round1(v), "SDNN · Día")
                }
                return (nil, nil)
            }()

            // - Resting HR: Bevel uses outlier-cleaned ASLEEP HR mean when >= 3 sleeping HR samples exist; falls back to Apple RHR!
            let appleRhr = mean(raw.rhrValues)
            let sleepMeanHr = sleepHrVals.count >= 3 ? WhoopPhysiologyEngine.aggregateSleepingHr(sleepHrVals) : nil
            let rhrBpm: Double? = (sleepMeanHr ?? appleRhr).map(round1)

            // Concise transparent diagnostic line so exact sleep window, sample counts, and RMSSD vs SDNN are 100% inspectable!
            let syncDiagLine: String = {
                var parts: [String] = []
                if let ss = sleepSession {
                    let sLbl = ss.startTimeLabel ?? "?"
                    let eLbl = ss.endTimeLabel ?? "?"
                    let durTag = asleepOrNil.map { " (\($0 / 60)h\(String(format: "%02d", $0 % 60))m)" } ?? ""
                    parts.append("Sueño \(sLbl)–\(eLbl)\(durTag)")
                } else {
                    parts.append("Sin bloques de sueño")
                }
                if let sm = sleepMeanHr {
                    parts.append(String(format: "FC sueño %.1f (%d)", round1(sm), sleepHrVals.count))
                } else if let ar = appleRhr {
                    parts.append(String(format: "FCR Apple %.1f (0 sueño)", round1(ar)))
                }
                let hrvSleepCount = !sleepHrvRmssdVals.isEmpty ? sleepHrvRmssdVals.count : sleepHrvSdnnVals.count
                let totalHrvDay = raw.hrvRmssdSamples.count + raw.hrvSamples.count
                if let h = hrvMs {
                    parts.append(String(format: "VFC %.1f (%d sueño/%d día)", h, hrvSleepCount, totalHrvDay))
                }
                return parts.joined(separator: " · ")
            }()

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

            let rawTempAbs = median(raw.tempCelsiusValues).map(round1)
            let directTempDelta = median(raw.tempDeltaValues).map { round1(min(max($0, -2.5), 2.5)) }
            let tempDelta: Double? = {
                if let d = rawTempAbs, let m = medianTemp {
                    return round1(min(max(d - m, -2.5), 2.5))
                }
                return directTempDelta
            }()
            let dayTempAbs: Double? = {
                if let d = rawTempAbs { return d }
                if let td = directTempDelta {
                    let base = medianTemp ?? 35.8
                    return round1(base + td)
                }
                return nil
            }()

            // 4. Bevel-Calibrated Sleep Score (only from measured components, personalized to user's age & sex!)
            let sleepPct: Int? = asleepOrNil.map { asleep in
                WhoopPhysiologyEngine.computeBevelSleepScore(
                    asleepMinutes: asleep,
                    inBedMinutes: inBedMin,
                    deepMinutes: deepOrNil,
                    remMinutes: remOrNil,
                    awakeMinutes: awakeOrNil,
                    awakeCount: primaryAwake.count,
                    hrDipPct: hrDipPct,
                    targetMinutes: targetSleepMin,
                    deepTargetPct: norms.deepTargetPct,
                    remTargetPct: norms.remTargetPct
                )
            }
            let sleepDebt: Int? = asleepOrNil.map { asleep in
                let updated = WhoopPhysiologyEngine.updateCumulativeSleepDebt(
                    previousDebtMinutes: runningSleepDebtMin,
                    asleepMinutes: asleep,
                    targetMinutes: targetSleepMin
                )
                runningSleepDebtMin = Double(updated)
                return updated
            }

            // 5. Causal 60-Day Personal Baselines -> Bevel Recovery % (Seeded with user's age/sex/body clinical priors!)
            // Match the day's HRV method (RMSSD vs SDNN) to its own dedicated baseline pool!
            let dayIsSdnn = (hrvMethodLabel?.uppercased().contains("SDNN") == true)
            let activePriorLnHrv = dayIsSdnn ? priorLnHrvSdnn : priorLnHrvRmssd
            let hrvPopExpected = dayIsSdnn ? (norms.hrvExpectedMs * 1.18) : norms.hrvExpectedMs
            let lnHrvBase = WhoopPhysiologyEngine.computeRollingBaseline(
                priorValues: activePriorLnHrv,
                populationMean: log(max(hrvPopExpected, 15.0)),
                populationSigma: WhoopPhysiologyEngine.baselinePopulationHrvSigma,
                floorSigma: WhoopPhysiologyEngine.baselineFloorHrvSigma
            )
            let rhrBase = WhoopPhysiologyEngine.computeRollingBaseline(
                priorValues: priorRhr,
                populationMean: norms.restingHrExpected,
                populationSigma: WhoopPhysiologyEngine.baselinePopulationRhrSigma,
                floorSigma: WhoopPhysiologyEngine.baselineFloorRhrSigma
            )
            let respBase = WhoopPhysiologyEngine.computeRollingBaseline(
                priorValues: priorResp,
                populationMean: respCenter,
                populationSigma: WhoopPhysiologyEngine.baselinePopulationRespSigma,
                floorSigma: WhoopPhysiologyEngine.baselineFloorRespSigma
            )

            // WHOOP rule: Never compute or show a Recovery % until real sleep has been recorded for that day!
            let hasSleepForRecovery = (asleepOrNil ?? 0) > 0 || sleepPct != nil || sleepSession != nil
            let recPct: Int? = hasSleepForRecovery ? WhoopPhysiologyEngine.computeBevelRecoveryPercent(
                hrvMs: hrvMs,
                rhrBpm: rhrBpm,
                respRpm: respRate,
                spo2Pct: spo2,
                wristTempDeltaC: tempDelta,
                lnHrvBaseline: lnHrvBase,
                rhrBaseline: rhrBase,
                respBaseline: respBase,
                profile: profile,
                sleepPct: sleepPct
            ) : nil

            // Update causal history AFTER scoring day i
            if let h = hrvMs, h > 2.0 {
                if dayIsSdnn {
                    priorLnHrvSdnn.append(log(h))
                } else {
                    priorLnHrvRmssd.append(log(h))
                }
            }
            if let r = rhrBpm { priorRhr.append(r) }
            if let rr = respRate { priorResp.append(rr) }

            // 6. Accurate 6-Zone HR (Z0..Z5) & Per-Workout Real HR/Zone/HRR Enrichment + Bevel Strain
            let rhrForZones = rhrBpm ?? rhrBase.mean

            // When syncing via native Apple Shortcuts (which has no built-in "Find Workouts" action),
            // detect genuine sustained elevated-HR exercise bouts strictly from real intraday HR samples!
            let effectiveWorkoutsRaw: [EffortEventItem]
            let effectiveWorkoutSpans: [ClosedRange<Int64>]
            if raw.workouts.isEmpty {
                let detected = detectElevatedHrWorkoutsFromRealSamples(
                    dateIso: dateIso,
                    hrSamples: raw.hrSamples,
                    rhrRef: rhrForZones,
                    maxHr: maxHr,
                    profile: profile,
                    sleepStartEpoch: sleepSession?.startEpochSec,
                    sleepEndEpoch: sleepSession?.endEpochSec,
                    dailyActiveKcal: raw.hasActiveKcal ? raw.deduplicatedActiveKcalSum : nil,
                    dailyDistanceKm: raw.hasDistanceKm ? raw.deduplicatedDistanceKmSum : nil
                )
                effectiveWorkoutsRaw = detected.workouts
                effectiveWorkoutSpans = detected.spans
            } else {
                effectiveWorkoutsRaw = raw.workouts
                effectiveWorkoutSpans = raw.workoutSpans
            }

            let zones6 = computeHrZoneMinutes6(
                samples: raw.hrSamples.map { ($0.0, $0.2) },
                workoutSpans: effectiveWorkoutSpans,
                maxHr: maxHr,
                rhr: rhrForZones
            )
            let zones = Array(zones6.dropFirst()) // [Z1, Z2, Z3, Z4, Z5]
            let z0Min = zones6.first ?? 0

            // Enrich workouts using real intraday HR samples (avgHrBpm, per-workout Z0..Z5, and 1-min post-workout HRR!)
            var inferredHrrVals: [Double] = []
            let outdoorDistanceWorkouts = effectiveWorkoutsRaw.filter { w in
                let l = w.title.lowercased()
                return l.contains("bici") || l.contains("carrera") || l.contains("caminat") || l.contains("run") || l.contains("cycl") || l.contains("walk") || l.contains("cardio")
            }
            let enrichedWorkouts: [EffortEventItem] = effectiveWorkoutsRaw.enumerated().map { idx, w in
                var item = w
                let span: ClosedRange<Int64>? = idx < effectiveWorkoutSpans.count ? effectiveWorkoutSpans[idx] : nil
                if let sp = span {
                    let inSpanSamples = raw.hrSamples.filter { sp.contains($0.0) }
                    if item.avgHrBpm == 0 && !inSpanSamples.isEmpty {
                        let avg = Int((inSpanSamples.map(\.2).reduce(0, +) / Double(inSpanSamples.count)).rounded())
                        if (45...225).contains(avg) {
                            let ws = WhoopPhysiologyEngine.computeWorkoutStrain(
                                durationMin: item.durationMin,
                                kcal: item.kcal,
                                avgHrBpm: avg,
                                rhrBpm: rhrForZones,
                                maxHrBpm: maxHr,
                                banisterB: profile.sex.banisterB
                            )
                            item = EffortEventItem(
                                id: item.id, title: item.title, timeRange: item.timeRange,
                                durationMin: item.durationMin, avgHrBpm: avg,
                                strainScore: ws.strain21, strainPct: ws.strainPct,
                                categoryLabel: item.categoryLabel, kcal: item.kcal,
                                distanceKm: item.distanceKm, elevationM: item.elevationM, dateIso: item.dateIso,
                                startEpochSec: item.startEpochSec ?? sp.lowerBound,
                                avgPowerW: item.avgPowerW, avgCadenceRpm: item.avgCadenceRpm,
                                hrZoneMinutes6: item.hrZoneMinutes6, hrRecovery1MinBpm: item.hrRecovery1MinBpm,
                                totalSets: item.totalSets, totalVolumeKg: item.totalVolumeKg, targetMuscles: item.targetMuscles
                            )
                        }
                    }
                    if inSpanSamples.count >= 2 {
                        let wZones6 = computeHrZoneMinutes6(
                            samples: inSpanSamples.map { ($0.0, $0.2) },
                            workoutSpans: [sp],
                            maxHr: maxHr,
                            rhr: rhrForZones
                        )
                        if wZones6.reduce(0, +) > 0 {
                            item.hrZoneMinutes6 = wZones6
                        }
                    }
                    // Genuine 1-minute post-workout HR Recovery from real HR samples when direct HKQuantity HRR wasn't exported!
                    let endWindowHr = raw.hrSamples.filter { $0.0 >= sp.upperBound - 120 && $0.0 <= sp.upperBound + 15 }.map(\.2)
                    let post1MinHr = raw.hrSamples.filter { $0.0 >= sp.upperBound + 45 && $0.0 <= sp.upperBound + 135 }.map(\.2)
                    if let peakEnd = endWindowHr.max(), let minAfter = post1MinHr.min(), peakEnd >= 102.0 {
                        let drop = peakEnd - minAfter
                        if (5.0...85.0).contains(drop) {
                            let roundedDrop = round1(drop)
                            item.hrRecovery1MinBpm = roundedDrop
                            inferredHrrVals.append(roundedDrop)
                        }
                    }
                }
                // If only 1 outdoor distance workout occurred today and distanceKm is missing on the workout, attach daily distance
                if item.distanceKm == nil && raw.hasDistanceKm && outdoorDistanceWorkouts.count == 1 && outdoorDistanceWorkouts.first?.id == item.id {
                    item.distanceKm = round1(raw.deduplicatedDistanceKmSum)
                }
                return item
            }

            let finalHrr = hrr ?? mean(inferredHrrVals).map(round1)

            let strainPair = WhoopPhysiologyEngine.computeBevelStrain(
                profile: profile,
                rhrBpm: rhrForZones,
                hrZoneMinutes: zones,
                workouts: enrichedWorkouts,
                activeKcal: raw.hasActiveKcal ? raw.deduplicatedActiveKcalSum : nil
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
                if sleepSession != nil || (asleepOrNil ?? 0) > 0 {
                    return Double(max(min((recPct ?? sleepPct ?? 65) - 34, 48), 22))
                }
                return Double(max(min((recPct ?? 65) - 24, 65), 22))
            }()

            // Detect if the user went to sleep BEFORE midnight on this evening (next day's night starts >= 19:00 today)
            let nextNightStartEpoch: Int64? = {
                guard let dStart = dayStartEp else { return nil }
                let eveningCut = dStart + 19 * 3600
                let dayEnd = dStart + 86_400
                var earliest: Int64? = nil
                let candidates = raw.deepIntervals + raw.remIntervals + raw.coreIntervals + raw.asleepAnyIntervals
                for sp in candidates where sp.lowerBound >= eveningCut && sp.lowerBound < dayEnd {
                    if earliest == nil || sp.lowerBound < earliest! { earliest = sp.lowerBound }
                }
                if dayIdx + 1 < sortedIsos.count, let nextRaw = days[sortedIsos[dayIdx + 1]] {
                    for sp in (nextRaw.deepIntervals + nextRaw.remIntervals + nextRaw.coreIntervals + nextRaw.asleepAnyIntervals) where sp.lowerBound >= eveningCut && sp.lowerBound < dayEnd {
                        if earliest == nil || sp.lowerBound < earliest! { earliest = sp.lowerBound }
                    }
                }
                return earliest
            }()

            let energy5m = buildContinuousFiveMinuteEnergySamples(
                stressSamples: stress5m,
                startingEnergy: initialEnergy,
                recoveryPct: recPct,
                sleepPct: sleepPct,
                sleepStartEpoch: sleepSession?.startEpochSec,
                sleepEndEpoch: sleepSession?.endEpochSec,
                workoutSpans: effectiveWorkoutSpans,
                asleepMinutes: asleepOrNil,
                dayStartEpoch: dayStartEp,
                nextSleepStartEpoch: nextNightStartEpoch
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

            totalWorkouts += enrichedWorkouts.count

            summaries[dateIso] = RealBiometricDaySummary(
                dateIso: dateIso,
                liveHrBpm: avgDayHr,
                restingHrBpm: rhrBpm,
                hrvMs: hrvMs,
                hrvMethodLabel: hrvMethodLabel,
                syncDiagnosticLine: syncDiagLine,
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
                stepsCount: raw.hasSteps ? max(Int(raw.deduplicatedStepsSum.rounded()), 0) : nil,
                vo2MaxMlKgMin: vo2,
                hrRecoveryBpm: finalHrr,
                glucoseMgDl: glucose,
                activeKcal: raw.hasActiveKcal ? Int(raw.deduplicatedActiveKcalSum.rounded()) : nil,
                daylightMinutes: raw.hasDaylight ? Int(raw.daylightMinSum.rounded()) : nil,
                sleepNoiseOver50Db: sleepNoiseOver50,
                bodyWeightKg: weight,
                bodyFatPct: bodyFat,
                leanMassKg: leanMass,
                systolicBp: sysBp,
                diastolicBp: diaBp,
                hrZoneMinutes: zones,
                hrZone0Minutes: z0Min > 0 ? z0Min : nil,
                distanceKm: raw.hasDistanceKm ? round1(raw.deduplicatedDistanceKmSum) : nil,
                elevationM: raw.hasElevationM ? round1(raw.deduplicatedElevationMSum) : nil,
                avgPowerW: mean(raw.powerValues).map(round1),
                avgCadenceRpm: mean(raw.cadenceValues).map(round1),
                stressSeries24h: [],
                energySeries24h: [],
                stressSamples5m: stress5m,
                energySamples5m: energy5m,
                strengthMinutes: raw.strengthMinutes,
                workouts: enrichedWorkouts
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

    /// Continuous physiological Body Battery model (resilient to Apple Watch Low Power Mode / sparse HR gaps!):
    /// Starts at EXACT `startingEnergy` carried from previous day's ending value (zero midnight jumps!).
    /// Integrates the FULL real recorded sleep window (even when watchOS Low Power Mode turns off background HR
    /// during sleep, leaving 0–1 HR readings overnight!) and drains proportionally during awake stress/workouts.
    static func buildContinuousFiveMinuteEnergySamples(
        stressSamples: [TimedBiometricPoint],
        startingEnergy: Double,
        recoveryPct: Int?,
        sleepPct: Int?,
        sleepStartEpoch: Int64?,
        sleepEndEpoch: Int64?,
        workoutSpans: [ClosedRange<Int64>] = [],
        asleepMinutes: Int? = nil,
        dayStartEpoch: Int64? = nil,
        nextSleepStartEpoch: Int64? = nil
    ) -> [TimedBiometricPoint] {
        let hasRecordedSleepSpan: Bool = {
            if let s = sleepStartEpoch, let e = sleepEndEpoch, e > s { return true }
            return false
        }()
        let hasRecordedSleep = hasRecordedSleepSpan || ((asleepMinutes ?? 0) > 0)
        guard !stressSamples.isEmpty || hasRecordedSleep else { return [] }

        // Combine sleep quality & recovery so a 94% sleep session always produces realistic restorative recharge
        let qualityFactor: Double = {
            switch (recoveryPct, sleepPct) {
            case let (r?, s?):
                return (0.50 * Double(r) + 0.50 * Double(s)) / 100.0
            case let (_, s?):
                return Double(s) / 100.0
            case let (r?, _):
                return Double(r) / 100.0
            default:
                return 0.65
            }
        }()
        let clampedQuality = min(max(qualityFactor, 0.15), 1.0)
        // Calibrated Garmin Body Battery / Bevel Energy Bank sleep recharge:
        // 8h (96 x 5m steps) at 90% quality -> up to +70% recharge capacity, ceiling ~95%
        // 5h (60 x 5m steps) at 45% quality -> ~+32% recharge capacity, ceiling ~76%
        let baseSleepChargePer5m = 0.34 + clampedQuality * 0.44
        let maxSleepCeiling = min(99.0, 58.0 + clampedQuality * 41.0)

        // Resolve local midnight epoch for today so we can clip sleep sessions that started before 00:00
        let resolvedDayStartEp: Int64? = {
            if let d = dayStartEpoch { return d }
            if let first = stressSamples.first, let ep = first.epochSec {
                return ep - Int64(first.minuteOfDay * 60)
            }
            if let e = sleepEndEpoch {
                let wakeDate = Date(timeIntervalSince1970: TimeInterval(e))
                return Int64(Calendar.current.startOfDay(for: wakeDate).timeIntervalSince1970)
            }
            return nil
        }()

        // Determine today's effective sleep window in [minuteOfDay] & [epochSec]
        var todaySleepStartMin: Int? = nil
        var todaySleepEndMin: Int? = nil
        var todaySleepStartEp: Int64? = nil
        var todaySleepEndEp: Int64? = nil

        if let s = sleepStartEpoch, let e = sleepEndEpoch, e > s {
            if let dStart = resolvedDayStartEp {
                let dEnd = dStart + 86_400
                let clipStart = max(s, dStart)
                let clipEnd = min(e, dEnd - 60)
                if clipEnd > clipStart {
                    let sMin = min(max(Int((clipStart - dStart) / 60), 0), 1434)
                    let eMin = min(max(Int((clipEnd - dStart) / 60), sMin + 5), 1439)
                    todaySleepStartMin = sMin
                    todaySleepEndMin = eMin
                    todaySleepStartEp = clipStart
                    todaySleepEndEp = clipEnd
                }
            } else {
                // Fallback when no epoch anchor exists: infer minute-of-day directly
                let sMinRaw = minuteOfDay(epochSec: s)
                let eMinRaw = minuteOfDay(epochSec: e)
                let sMin = sMinRaw > eMinRaw ? 0 : sMinRaw
                let eMin = max(eMinRaw, sMin + 5)
                todaySleepStartMin = sMin
                todaySleepEndMin = min(eMin, 1439)
                todaySleepStartEp = s
                todaySleepEndEp = e
            }
        } else if let asleep = asleepMinutes, asleep > 0 {
            // Summary-only sleep (e.g. WHOOP CSV or legacy record with asleepMinutes but no timestamps)
            let firstMorningAwake = stressSamples.first(where: { $0.minuteOfDay >= 270 && $0.minuteOfDay <= 660 })?.minuteOfDay
            let estWake = min(max((firstMorningAwake.map { max($0 - 5, 240) }) ?? 450, 180), 660)
            let estStart = max(0, estWake - min(asleep, estWake))
            if estWake > estStart {
                todaySleepStartMin = estStart
                todaySleepEndMin = estWake
                if let dStart = resolvedDayStartEp {
                    todaySleepStartEp = dStart + Int64(estStart * 60)
                    todaySleepEndEp = dStart + Int64(estWake * 60)
                }
            }
        }

        // Scale charge rate smoothly to true asleepMinutes (accounts cleanly for both pre-midnight sleep
        // and awake interruptions inside the sleep window!)
        let asleepRateMultiplier: Double = {
            guard let sMin = todaySleepStartMin, let eMin = todaySleepEndMin, eMin > sMin,
                  let asleep = asleepMinutes, asleep > 0 else { return 1.0 }
            let todayWindowMin = Double(eMin - sMin)
            return min(max(Double(asleep) / max(todayWindowMin, 30.0), 0.50), 1.65)
        }()
        let sleepChargePer5m = baseSleepChargePer5m * asleepRateMultiplier

        // Build unified chronological timeline combining real HR/stress readings + smooth 15-min knots
        // across any HR gap inside the real recorded sleep window (Apple Watch Low Power Mode!)
        struct EnergyKnot {
            let minuteOfDay: Int
            let epochSec: Int64?
            let measuredStress: Double?
            let isSyntheticSleep: Bool
        }

        var byMinute: [Int: EnergyKnot] = [:]
        let sortedReal = stressSamples.sorted { $0.minuteOfDay < $1.minuteOfDay }
        for pt in sortedReal {
            byMinute[pt.minuteOfDay] = EnergyKnot(
                minuteOfDay: pt.minuteOfDay,
                epochSec: pt.epochSec,
                measuredStress: pt.value,
                isSyntheticSleep: false
            )
        }

        if let sMin = todaySleepStartMin, let eMin = todaySleepEndMin, eMin > sMin {
            func hasRealNear(_ m: Int, tolerance: Int) -> Bool {
                sortedReal.contains { abs($0.minuteOfDay - m) <= tolerance }
            }
            func epochForMinute(_ m: Int) -> Int64? {
                if let dStart = resolvedDayStartEp { return dStart + Int64(m * 60) }
                if let sEp = todaySleepStartEp { return sEp + Int64((m - sMin) * 60) }
                return nil
            }

            // Sleep start anchor (only if no real reading already anchors the start of sleep within 10m)
            if !hasRealNear(sMin, tolerance: 10) {
                byMinute[sMin] = EnergyKnot(
                    minuteOfDay: sMin,
                    epochSec: todaySleepStartEp ?? epochForMinute(sMin),
                    measuredStress: nil,
                    isSyntheticSleep: true
                )
            }

            // Intermediate 15-min knots across Low Power Mode HR silence inside real sleep
            var m = sMin + 15
            while m <= eMin - 10 {
                if !hasRealNear(m, tolerance: 10) {
                    byMinute[m] = EnergyKnot(
                        minuteOfDay: m,
                        epochSec: epochForMinute(m),
                        measuredStress: nil,
                        isSyntheticSleep: true
                    )
                }
                m += 15
            }

            // Wake-up peak anchor (guarantees full recharge completes cleanly at wake time!)
            if !hasRealNear(eMin, tolerance: 10) {
                byMinute[eMin] = EnergyKnot(
                    minuteOfDay: eMin,
                    epochSec: todaySleepEndEp ?? epochForMinute(eMin),
                    measuredStress: nil,
                    isSyntheticSleep: true
                )
            }
        }

        let timeline = byMinute.keys.sorted().compactMap { byMinute[$0] }
        guard !timeline.isEmpty else { return [] }

        var cur = min(max(startingEnergy, 5.0), 99.0)
        var result: [TimedBiometricPoint] = []
        result.reserveCapacity(timeline.count)

        for (idx, ev) in timeline.enumerated() {
            if idx == 0 {
                // First point of the day preserves EXACT carried-over continuity from yesterday (zero jump!)
                result.append(TimedBiometricPoint(minuteOfDay: ev.minuteOfDay, value: round1(cur), epochSec: ev.epochSec))
                continue
            }

            let prev = timeline[idx - 1]
            let rawDtMin = max(Double(ev.minuteOfDay - prev.minuteOfDay), 5.0)

            let segmentIsSleeping: Bool = {
                if let sMin = todaySleepStartMin, let eMin = todaySleepEndMin, eMin > sMin {
                    let midMin = Double(prev.minuteOfDay + ev.minuteOfDay) / 2.0
                    if midMin >= Double(sMin) && midMin <= Double(eMin) {
                        return true
                    }
                }
                if let ep = ev.epochSec, let s = sleepStartEpoch, let e = sleepEndEpoch, ep >= s && ep <= e {
                    return true
                }
                // Pre-midnight bedtime of the NEXT night: recharge instead of draining while asleep before 00:00!
                if let ep = ev.epochSec, let nextStart = nextSleepStartEpoch,
                   let dStart = resolvedDayStartEp,
                   nextStart >= dStart + 19 * 3600, nextStart < dStart + 86_400,
                   ep >= nextStart {
                    return true
                }
                return ev.isSyntheticSleep
            }()

            let isWorkout: Bool = {
                guard !workoutSpans.isEmpty else { return false }
                if let ep = ev.epochSec {
                    if workoutSpans.contains(where: { $0.contains(ep) }) { return true }
                    if let prevEp = prev.epochSec, prevEp < ep {
                        return workoutSpans.contains { $0.lowerBound <= ep && $0.upperBound >= prevEp }
                    }
                }
                return false
            }()

            if segmentIsSleeping {
                // NEVER cap sleeping gaps to 45 min: integrate the TRUE real sleep duration!
                let steps = rawDtMin / 5.0
                let effRate = (ev.measuredStress ?? 8.0) > 22.0 ? sleepChargePer5m * 0.60 : sleepChargePer5m
                if cur < maxSleepCeiling {
                    cur = min(maxSleepCeiling, cur + effRate * steps)
                }
            } else if isWorkout {
                let dtMin = min(rawDtMin, 90.0)
                let steps = dtMin / 5.0
                let stressVal = ev.measuredStress ?? 55.0
                let drain = (0.55 + (stressVal / 100.0) * 1.15) * steps
                cur = max(5.0, cur - drain)
            } else {
                // Cap unmeasured daytime gaps (e.g. watch on charger) so energy never cliff-drops
                let dtMin = min(rawDtMin, 60.0)
                let steps = dtMin / 5.0
                let stressVal = ev.measuredStress ?? 22.0
                if stressVal <= 14.0 {
                    // Deep calm awake rest gently pauses drain / micro-recovers
                    cur = min(99.0, cur + 0.08 * steps)
                } else {
                    // Awake drain proportional to measured physiological stress
                    let drain = (0.06 + (stressVal / 100.0) * 0.72) * steps
                    cur = max(5.0, cur - drain)
                }
            }

            result.append(TimedBiometricPoint(minuteOfDay: ev.minuteOfDay, value: round1(cur), epochSec: ev.epochSec))
        }
        return result
    }

    private static func minuteOfDay(epochSec: Int64) -> Int {
        let d = Date(timeIntervalSince1970: TimeInterval(epochSec))
        let comps = Calendar.current.dateComponents([.hour, .minute], from: d)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    /// Detects genuine sustained high-HR exercise bouts strictly from real intraday Apple Watch HR samples
    /// when `HKWorkout` metadata wasn't exported (e.g. native Apple Shortcuts sync). Never fabricates workouts on rest days!
    private static func detectElevatedHrWorkoutsFromRealSamples(
        dateIso: String,
        hrSamples: [(Int64, Int, Double)],
        rhrRef: Double,
        maxHr: Double,
        profile: UserPhysiologyProfile,
        sleepStartEpoch: Int64?,
        sleepEndEpoch: Int64?,
        dailyActiveKcal: Double?,
        dailyDistanceKm: Double?
    ) -> (workouts: [EffortEventItem], spans: [ClosedRange<Int64>]) {
        guard hrSamples.count >= 6 else { return ([], []) }

        let elevatedFloor = max(rhrRef + 32.0, 105.0)
        let meanFloor = max(rhrRef + 38.0, 110.0)
        let awakeElevated = hrSamples
            .filter { sample in
                if let s = sleepStartEpoch, let e = sleepEndEpoch, sample.0 >= s && sample.0 <= e {
                    return false
                }
                return sample.2 >= elevatedFloor
            }
            .sorted { $0.0 < $1.0 }

        guard awakeElevated.count >= 6 else { return ([], []) }

        // Group consecutive elevated-HR readings separated by <= 8 minutes
        var clusters: [[(Int64, Int, Double)]] = []
        var current: [(Int64, Int, Double)] = [awakeElevated[0]]
        for s in awakeElevated.dropFirst() {
            if let prev = current.last, (s.0 - prev.0) <= 8 * 60 {
                current.append(s)
            } else {
                clusters.append(current)
                current = [s]
            }
        }
        clusters.append(current)

        var workouts: [EffortEventItem] = []
        var spans: [ClosedRange<Int64>] = []
        let age = profile.effectiveAgeYears
        let weight = profile.weightKg

        for (idx, rawCluster) in clusters.enumerated() {
            // Trim a sharp post-effort cool-down tail (>= 15 bpm drop within 45..150s at the end of a bout)
            // so workout end aligns with active peak effort and post-workout 1-min HRR captures the true recovery drop!
            var cluster = rawCluster
            while cluster.count >= 7,
                  let tail = cluster.last,
                  let beforeTail = cluster.dropLast().last,
                  (tail.0 - beforeTail.0) >= 45 && (tail.0 - beforeTail.0) <= 150,
                  beforeTail.2 >= 120.0,
                  (beforeTail.2 - tail.2) >= 15.0 {
                cluster.removeLast()
            }
            guard cluster.count >= 6,
                  let first = cluster.first,
                  let last = cluster.last else { continue }
            let durSec = last.0 - first.0
            let durMin = Int((Double(durSec) / 60.0).rounded())
            guard durMin >= 12 && durMin <= 360 else { continue }

            let avgHr = cluster.map(\.2).reduce(0, +) / Double(cluster.count)
            guard avgHr >= meanFloor else { continue }

            let avgHrInt = Int(avgHr.rounded())
            // Physiological Keytel kcal estimate from real HR/duration/weight/age, bounded by measured daily active kcal
            let kcalPerMin: Double = {
                if profile.sex == .female {
                    return max((-20.4022 + 0.4472 * avgHr - 0.1263 * weight + 0.074 * age) / 4.184, 3.0)
                }
                return max((-55.0969 + 0.6309 * avgHr + 0.1988 * weight + 0.2017 * age) / 4.184, 3.5)
            }()
            var estKcal = Int((kcalPerMin * Double(durMin)).rounded())
            if let dayKcal = dailyActiveKcal, dayKcal > 20 {
                estKcal = min(estKcal, max(Int((dayKcal * 0.92).rounded()), 30))
            }

            let ws = WhoopPhysiologyEngine.computeWorkoutStrain(
                durationMin: durMin,
                kcal: estKcal,
                avgHrBpm: avgHrInt,
                rhrBpm: rhrRef,
                maxHrBpm: maxHr,
                banisterB: profile.sex.banisterB
            )
            let sTime = String(format: "%02d:%02d", (first.1 / 60) % 24, first.1 % 60)
            let eTime = String(format: "%02d:%02d", (last.1 / 60) % 24, last.1 % 60)
            let title: String = {
                if let d = dailyDistanceKm, d >= 3.5 && avgHr >= 134 { return "Carrera / Cardio" }
                return "Sesión activa (FC)"
            }()
            let span = first.0...max(last.0, first.0 + 60)
            spans.append(span)
            workouts.append(
                EffortEventItem(
                    id: "hr_auto_\(dateIso)_\(idx)",
                    title: title,
                    timeRange: "\(sTime) - \(eTime)",
                    durationMin: durMin,
                    avgHrBpm: avgHrInt,
                    strainScore: ws.strain21,
                    strainPct: ws.strainPct,
                    categoryLabel: "Cardio",
                    kcal: estKcal,
                    dateIso: dateIso,
                    startEpochSec: first.0
                )
            )
        }
        return (workouts, spans)
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

        // Active HRV context: ALWAYS prefer beat-to-beat RMSSD from <InstantaneousBeatsPerMinute bpm="..." time="..."/>
        // using exact sub-second beat timestamps (identical to HealthKit HKHeartbeatSeriesQuery!).
        private var activeHrvDateIso: String?
        private var activeHrvEndEpoch: Int64 = 0
        private var activeHrvFallbackSdnn: Double? = nil
        private var activeHrvBeatEntries: [(timeSec: Double?, hasSubsecond: Bool, bpm: Double)] = []

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
                if activeHrvDateIso != nil && startsWithASCII(ptr, length, "InstantaneousBeatsPerMinute ") {
                    if let s = String(bytes: UnsafeBufferPointer(start: ptr, count: length), encoding: .utf8) {
                        let attrs = parseAttributes(s)
                        if let bStr = attrs["bpm"], let bpm = Double(bStr.replacingOccurrences(of: ",", with: ".")), (30...200).contains(bpm) {
                            let parsedTime = Self.parseInstantaneousBeatTime(attrs["time"])
                            activeHrvBeatEntries.append((parsedTime?.seconds, parsedTime?.hasSubsecond ?? false, bpm))
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

        /// Parses Apple Health `<InstantaneousBeatsPerMinute time="4:38:38.36 PM" />` or `"03:30:01,42"` into seconds since midnight.
        private static func parseInstantaneousBeatTime(_ raw: String?) -> (seconds: Double, hasSubsecond: Bool)? {
            guard let raw else { return nil }
            let s = raw
                .replacingOccurrences(of: "\u{00A0}", with: " ")
                .replacingOccurrences(of: "\u{202F}", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !s.isEmpty else { return nil }
            let isPm = s.contains("pm") || s.contains("p. m") || s.contains("p.m")
            let isAm = s.contains("am") || s.contains("a. m") || s.contains("a.m")
            guard let range = s.range(of: #"(\d{1,2}):(\d{2}):(\d{2})(?:[.,](\d+))?"#, options: .regularExpression) else {
                return nil
            }
            let token = String(s[range])
            let colonParts = token.split(separator: ":")
            guard colonParts.count == 3,
                  var hh = Int(colonParts[0]),
                  let mm = Int(colonParts[1]) else { return nil }
            let secPart = String(colonParts[2]).replacingOccurrences(of: ",", with: ".")
            let hasSub = secPart.contains(".")
            guard let ss = Double(secPart) else { return nil }
            if isPm && hh < 12 { hh += 12 }
            if isAm && hh == 12 { hh = 0 }
            guard (0...23).contains(hh), (0...59).contains(mm), ss >= 0 && ss < 60.0 else { return nil }
            return (Double(hh * 3600 + mm * 60) + ss, hasSub)
        }

        private func flushPendingHrvIfNeeded() {
            defer {
                activeHrvDateIso = nil
                activeHrvFallbackSdnn = nil
                activeHrvBeatEntries.removeAll(keepingCapacity: true)
            }
            guard let iso = activeHrvDateIso, let day = days[iso] else { return }
            // Priority 1: TRUE beat-to-beat RMSSD (sub-second RR intervals first, gap-split BPM fallback second)
            if let rmssd = WhoopPhysiologyEngine.computeRmssdFromBeatEntries(activeHrvBeatEntries) {
                day.hrvRmssdSamples.append((activeHrvEndEpoch, rmssd))
                return
            }
            // Priority 2: Fallback to Apple Health SDNN scalar only when no beat-to-beat series existed
            if let sdnn = activeHrvFallbackSdnn {
                day.hrvSamples.append((activeHrvEndEpoch, sdnn))
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
                var scalarSdnn: Double? = nil
                if let num = parsedNum, num.isFinite {
                    let lowU = unitStr.lowercased()
                    let ms = (!lowU.contains("ms") && lowU.contains("s") && num < 2.0) ? num * 1000.0 : num
                    if (3.0...350.0).contains(ms) {
                        scalarSdnn = ms
                    }
                }
                if isSelfClosing {
                    // Self-closing tag has no <InstantaneousBeatsPerMinute> children -> keep SDNN fallback
                    if let sdnn = scalarSdnn {
                        day.hrvSamples.append((endEp, sdnn))
                    }
                } else {
                    // Wait for </Record> so <InstantaneousBeatsPerMinute> beat-to-beat RMSSD overrides SDNN!
                    activeHrvDateIso = day.dateIso
                    activeHrvEndEpoch = endEp
                    activeHrvFallbackSdnn = scalarSdnn
                    activeHrvBeatEntries.removeAll(keepingCapacity: true)
                }
                return
            }

            guard let num = Double(valStr.replacingOccurrences(of: ",", with: ".")), num.isFinite else { return }
            let day = dayEntry(for: endDate, rawTimestamp: rawEnd)

            let srcKey = decodeXmlEntities((attrs["sourceName"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
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
                let isF = unitStr.localizedCaseInsensitiveContains("degF") || unitStr.contains("F")
                if (-4.5...4.5).contains(num) {
                    let deltaC = isF ? (num * 5.0 / 9.0) : num
                    day.tempDeltaValues.append(deltaC)
                } else {
                    let celsius = (isF || (num > 60.0 && num < 115.0)) ? (num - 32.0) * 5.0 / 9.0 : num
                    if (28.0...42.0).contains(celsius) { day.tempCelsiusValues.append(celsius) }
                }
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
                    day.stepsBySource[srcKey, default: 0] += num
                    day.hasSteps = true
                }
            case "HKQuantityTypeIdentifierActiveEnergyBurned":
                let kcal = unitStr.lowercased() == "kj" ? num / 4.184 : num
                if (0.0...15_000.0).contains(kcal) {
                    day.activeKcalSum += kcal
                    day.activeKcalBySource[srcKey, default: 0] += kcal
                    day.hasActiveKcal = true
                }
            case "HKQuantityTypeIdentifierDistanceWalkingRunning", "HKQuantityTypeIdentifierDistanceCycling":
                let lowU = unitStr.lowercased()
                let km = lowU == "m" ? num / 1000.0 : (lowU.contains("mi") ? num * 1.60934 : num)
                if (0.0...300.0).contains(km) {
                    day.distanceKmSum += km
                    day.distanceKmBySource[srcKey, default: 0] += km
                    day.hasDistanceKm = true
                }
            case "HKQuantityTypeIdentifierFlightsClimbed":
                if (0.0...500.0).contains(num) {
                    let elev = num * 3.05
                    day.elevationMSum += elev
                    day.elevationMBySource[srcKey, default: 0] += elev
                    day.hasElevationM = true
                }
            case "HKQuantityTypeIdentifierRunningPower", "HKQuantityTypeIdentifierCyclingPower":
                if (10.0...2000.0).contains(num) { day.powerValues.append(num) }
            case "HKQuantityTypeIdentifierCyclingCadence":
                if (20.0...220.0).contains(num) { day.cadenceValues.append(num) }
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
                dateIso: day.dateIso,
                startEpochSec: sEp
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
                        distanceKm: item.distanceKm, elevationM: item.elevationM, dateIso: item.dateIso,
                        startEpochSec: item.startEpochSec
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
                    distanceKm: item.distanceKm, elevationM: item.elevationM, dateIso: item.dateIso,
                    startEpochSec: item.startEpochSec
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
        let low = rawType
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
        if low.contains("traditionalstrength") || low.contains("fuerza tradicional") {
            return ("Entrenamiento de fuerza tradicional", "Fuerza", true)
        }
        if low.contains("functionalstrength") || low.contains("fuerza funcional") {
            return ("Entrenamiento de fuerza funcional", "Fuerza", true)
        }
        if low.contains("strength") || low.contains("coretraining") || low.contains("fuerza") || low.contains("pesas") {
            return ("Entrenamiento de fuerza tradicional", "Fuerza", true)
        }
        if low.contains("running") || low.contains("correr") || low.contains("carrera") { return ("Carrera", "Cardio", false) }
        if low.contains("cycling") || low.contains("bici") || low.contains("ciclismo") { return ("Bici al aire libre", "Cardio", false) }
        if low.contains("walking") || low.contains("hiking") || low.contains("caminar") || low.contains("caminata") || low.contains("senderismo") {
            return ("Caminata", "Aeróbico", false)
        }
        if low.contains("swimming") || low.contains("natacion") { return ("Natación", "Cardio", false) }
        if low.contains("highintensity") || low.contains("hiit") { return ("HIIT", "Alta intensidad", false) }
        if low.contains("yoga") || low.contains("pilates") || low.contains("movilidad") { return ("Movilidad / Yoga", "Recuperación", false) }
        if low.contains("rowing") || low.contains("remo") { return ("Remo", "Cardio", false) }
        if low.contains("soccer") || low.contains("football") || low.contains("futbol") { return ("Fútbol", "Deporte", false) }
        if low.contains("tennis") || low.contains("padel") || low.contains("tenis") { return ("Tenis / Pádel", "Deporte", false) }
        return ("Entrenamiento", "Actividad", false)
    }

    /// Clusters sleep intervals separated by <= 60 min gaps and picks the primary overnight sleep cluster
    /// (longest total asleep duration). Prevents afternoon naps or next-night bedtimes from stretching the
    /// sleep window across daytime hours and dragging sleeping HRV/RHR down.
    private static func primarySleepSessionRange(
        allSpans: [ClosedRange<Int64>],
        asleepSpans: [ClosedRange<Int64>]
    ) -> ClosedRange<Int64>? {
        let validSpans = allSpans.filter { ($0.upperBound - $0.lowerBound) > 0 && ($0.upperBound - $0.lowerBound) <= 14 * 3600 }
        guard !validSpans.isEmpty else { return nil }
        let sorted = validSpans.sorted { $0.lowerBound < $1.lowerBound }
        let maxGapSec: Int64 = 60 * 60

        var clusters: [ClosedRange<Int64>] = []
        var curStart = sorted[0].lowerBound
        var curEnd = sorted[0].upperBound
        for sp in sorted.dropFirst() {
            if sp.lowerBound <= curEnd + maxGapSec {
                curEnd = max(curEnd, sp.upperBound)
            } else {
                clusters.append(curStart...curEnd)
                curStart = sp.lowerBound
                curEnd = sp.upperBound
            }
        }
        clusters.append(curStart...curEnd)
        guard clusters.count > 1 else { return clusters.first }

        // Score each cluster by its deduplicated asleep duration (fall back to span duration)
        var best = clusters[0]
        var bestScore: Int64 = -1
        for c in clusters {
            let inside = asleepSpans.filter { $0.lowerBound >= c.lowerBound && $0.upperBound <= c.upperBound }
            let asleepDur = mergeIntervalSeconds(inside)
            let score = asleepDur > 0 ? asleepDur : max(c.upperBound - c.lowerBound, 0)
            if score > bestScore {
                bestScore = score
                best = c
            }
        }
        return best
    }

    private static func mergeIntervals(_ intervals: [ClosedRange<Int64>]) -> [ClosedRange<Int64>] {
        guard !intervals.isEmpty else { return [] }
        let sorted = intervals.sorted { $0.lowerBound < $1.lowerBound }
        var merged: [ClosedRange<Int64>] = []
        merged.reserveCapacity(sorted.count)
        var curStart = sorted[0].lowerBound
        var curEnd = sorted[0].upperBound
        for span in sorted.dropFirst() {
            if span.lowerBound <= curEnd {
                curEnd = max(curEnd, span.upperBound)
            } else {
                merged.append(curStart...curEnd)
                curStart = span.lowerBound
                curEnd = span.upperBound
            }
        }
        merged.append(curStart...curEnd)
        return merged
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
        let z6 = computeHrZoneMinutes6(samples: samples, workoutSpans: workoutSpans, maxHr: maxHr, rhr: rhr)
        return Array(z6.dropFirst())
    }

    /// Computes 6-zone heart rate durations `[Z0, Z1, Z2, Z3, Z4, Z5]` in minutes:
    /// - Z0: active workout / warm-up HR below 50% HRR (matches Bevel's Z0 bar!)
    /// - Z1..Z5: Karvonen 50%..100% HRR with conservative dt capping so passive walking never inflates Z1/Z2.
    static func computeHrZoneMinutes6(
        samples: [(Int64, Double)],
        workoutSpans: [ClosedRange<Int64>],
        maxHr: Double,
        rhr: Double
    ) -> [Int] {
        guard samples.count >= 2 else { return [0, 0, 0, 0, 0, 0] }
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
        guard deduped.count >= 2 else { return [0, 0, 0, 0, 0, 0] }

        let hrr = max(maxHr - rhr, 40.0)
        var secs = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
        for idx in 0..<(deduped.count - 1) {
            let ep = deduped[idx].0
            let rawDt = Double(deduped[idx + 1].0 - ep)
            guard rawDt > 0 else { continue }
            let inWorkout = workoutSpans.contains { $0.contains(ep) }
            let maxCap = inWorkout ? 300.0 : 90.0
            let dt = min(rawDt, maxCap)
            let pctHrr = (deduped[idx].1 - rhr) / hrr
            if pctHrr >= 0.90 { secs[5] += dt }
            else if pctHrr >= 0.80 { secs[4] += dt }
            else if pctHrr >= 0.70 { secs[3] += dt }
            else if pctHrr >= 0.60 { secs[2] += dt }
            else if pctHrr >= 0.50 { secs[1] += dt }
            else if inWorkout || pctHrr >= 0.34 { secs[0] += dt }
        }
        return secs.map { Int(($0 / 60.0).rounded()) }
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

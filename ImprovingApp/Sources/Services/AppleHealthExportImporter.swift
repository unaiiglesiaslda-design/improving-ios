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

/// Streaming Apple Health export importer (`exportar.zip` / `export.xml`).
/// Uses Foundation's streaming `XMLParser(contentsOf:)` so even gigabyte-scale `export.xml` files
/// parse cleanly without loading the DOM into memory.
enum AppleHealthExportImporter {

    private final class MutableAppleDay {
        let dateIso: String
        var hrvValues: [Double] = []
        var rhrValues: [Double] = []
        var hrValues: [Double] = []
        var hrTimedSamples: [(TimeInterval, Double)] = []
        var respValues: [Double] = []
        var spo2Values: [Double] = []
        var tempCelsiusValues: [Double] = []
        var vo2Values: [Double] = []
        var glucoseMgDlValues: [Double] = []
        var stepsSum: Double = 0
        var hasSteps: Bool = false
        var activeKcalSum: Double = 0
        var hasActiveKcal: Bool = false
        var deepIntervals: [ClosedRange<Int64>] = []
        var remIntervals: [ClosedRange<Int64>] = []
        var coreIntervals: [ClosedRange<Int64>] = []
        var asleepAnyIntervals: [ClosedRange<Int64>] = []
        var inBedIntervals: [ClosedRange<Int64>] = []
        var awakeIntervals: [ClosedRange<Int64>] = []
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
        guard let parser = Optional(XMLParser(data: data)) else {
            return .error("No se pudo inicializar el lector XML.")
        }
        return runParser(parser, sourceName: sourceName, profile: profile)
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

        let hrvSeries = days.values.compactMap { median($0.hrvValues) }
        let rhrSeries = days.values.compactMap { mean($0.rhrValues) }
        let respSeries = days.values.compactMap { mean($0.respValues) }
        let hrvCenter = hrvSeries.isEmpty ? 68.0 : hrvSeries.reduce(0, +) / Double(hrvSeries.count)
        let rhrCenter = rhrSeries.isEmpty ? 52.0 : rhrSeries.reduce(0, +) / Double(rhrSeries.count)
        let respCenter = respSeries.isEmpty ? 15.2 : respSeries.reduce(0, +) / Double(respSeries.count)

        let maxHr = Double(WhoopPhysiologyEngine.computeMaxHeartRate(profile: profile))
        var summaries: [String: RealBiometricDaySummary] = [:]
        var totalWorkouts = 0

        for dateIso in days.keys.sorted() {
            guard let raw = days[dateIso] else { continue }
            let hrvMs = median(raw.hrvValues).map(round1)
            let rhrBpm = mean(raw.rhrValues).map(round1)
            let avgHr = mean(raw.hrValues).map { Int($0.rounded()) } ?? rhrBpm.map { Int($0.rounded()) }
            let respRate = mean(raw.respValues).map(round1)
            let spo2 = mean(raw.spo2Values).map { min(max(Int($0.rounded()), 75), 100) }
            let vo2 = mean(raw.vo2Values).map(round1)
            let glucose = mean(raw.glucoseMgDlValues).map { Int($0.rounded()) }

            let dayTemp = median(raw.tempCelsiusValues)
            let tempDelta: Double? = if let d = dayTemp, let m = medianTemp {
                round1(min(max(d - m, -2.5), 2.5))
            } else {
                nil
            }

            let deepMin = mergeIntervalMinutes(raw.deepIntervals)
            let remMin = mergeIntervalMinutes(raw.remIntervals)
            let coreMin = mergeIntervalMinutes(raw.coreIntervals)
            let unspecMin = mergeIntervalMinutes(raw.asleepAnyIntervals)
            let awakeMin = mergeIntervalMinutes(raw.awakeIntervals)
            let inBedRaw = mergeIntervalMinutes(raw.inBedIntervals)

            let staged = deepMin + remMin + coreMin
            let asleepMin = staged > 0 ? staged : unspecMin
            let hasSleep = asleepMin > 0 || inBedRaw > 0
            let inBedMin = hasSleep ? max(inBedRaw, asleepMin + awakeMin) : nil
            let asleepOrNil = asleepMin > 0 ? asleepMin : nil
            let deepOrNil = deepMin > 0 ? deepMin : nil
            let remOrNil = remMin > 0 ? remMin : nil

            let sleepPct: Int? = if let asleep = asleepOrNil, asleep > 0 {
                {
                    let durRatio = min(max(Double(asleep) / 480.0, 0.25), 1.15)
                    let effRatio = (inBedMin ?? 0) > 0 ? min(max(Double(asleep) / Double(inBedMin!), 0.60), 1.0) : 0.90
                    return min(max(Int((durRatio * 75.0 + effRatio * 25.0).rounded()), 20), 100)
                }()
            } else {
                nil
            }
            let sleepDebt = asleepOrNil.map { max(480 - $0, 0) }

            let zones = computeHrZoneMinutes(samples: raw.hrTimedSamples, maxHr: maxHr, rhr: rhrBpm ?? 56.0)
            let hasZones = zones.reduce(0, +) > 0

            let strainPair: (Double, Int)? = if hasZones || !raw.workouts.isEmpty {
                WhoopPhysiologyEngine.computeStrainAndEffort(
                    profile: profile,
                    rhrBpm: rhrBpm ?? 56.0,
                    hrZoneMinutes: zones,
                    effortEvents: raw.workouts,
                    completedStrengthSets: raw.strengthMinutes > 0 ? max(raw.strengthMinutes / 6, 4) : 0,
                    totalStrengthVolumeKg: raw.strengthMinutes * 80
                )
            } else if raw.hasActiveKcal && raw.activeKcalSum >= 60 {
                {
                    let s21 = min(max(21.0 * log(1.0 + raw.activeKcalSum / 320.0) / log(1.0 + 4.5), 0.5), 20.5)
                    let pct = min(max(Int(((s21 / 21.0) * 100.0).rounded()), 2), 99)
                    return (round1(s21), pct)
                }()
            } else {
                nil
            }

            let recPct: Int? = if hrvMs != nil || rhrBpm != nil || asleepOrNil != nil {
                WhoopPhysiologyEngine.computeRecoveryPercent(
                    hrvMs: hrvMs ?? hrvCenter,
                    rhrBpm: rhrBpm ?? rhrCenter,
                    respRpm: respRate ?? respCenter,
                    spo2Pct: Double(spo2 ?? 98),
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

            let strainPct = strainPair?.1
            let energyPct = recPct.map { r -> Int in
                let drain = strainPct.map { Int((Double($0) * 0.45).rounded()) } ?? 12
                return min(max(r - drain + 15, 10), 99)
            }
            let stressScore: Int? = if let r = recPct, let s = strainPct {
                min(max(Int((Double(100 - r) * 0.42 + Double(s) * 0.36).rounded()), 8), 92)
            } else {
                nil
            }

            totalWorkouts += raw.workouts.count

            summaries[dateIso] = RealBiometricDaySummary(
                dateIso: dateIso,
                liveHrBpm: avgHr,
                restingHrBpm: rhrBpm,
                hrvMs: hrvMs,
                respRateRpm: respRate,
                wristTempDeltaC: tempDelta,
                spo2Percent: spo2,
                asleepMinutes: asleepOrNil,
                inBedMinutes: inBedMin,
                deepMinutes: deepOrNil,
                remMinutes: remOrNil,
                sleepPct: sleepPct,
                sleepDebtMinutes: sleepDebt,
                strain21: strainPair?.0,
                strainPct: strainPct,
                recoveryPct: recPct,
                stressScore: stressScore,
                energyBankPercent: energyPct,
                stepsCount: raw.hasSteps ? max(Int(raw.stepsSum.rounded()), 0) : nil,
                vo2MaxMlKgMin: vo2,
                glucoseMgDl: glucose,
                activeKcal: raw.hasActiveKcal ? Int(raw.activeKcalSum.rounded()) : nil,
                hrZoneMinutes: zones,
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

            if type == "HKCategoryTypeIdentifierSleepAnalysis" {
                let day = dayEntry(for: endDate)
                let s = Int64(startDate.timeIntervalSince1970)
                let e = Int64(endDate.timeIntervalSince1970)
                guard e > s else { return }
                let span = s...e
                let low = valStr.lowercased()
                if low.contains("asleepdeep") {
                    day.deepIntervals.append(span)
                } else if low.contains("asleeprem") {
                    day.remIntervals.append(span)
                } else if low.contains("asleepcore") {
                    day.coreIntervals.append(span)
                } else if low.contains("inbed") {
                    day.inBedIntervals.append(span)
                } else if low.contains("awake") {
                    day.awakeIntervals.append(span)
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
                if (5.0...280.0).contains(ms) { day.hrvValues.append(ms) }
            case "HKQuantityTypeIdentifierRestingHeartRate":
                if (28.0...130.0).contains(num) { day.rhrValues.append(num) }
            case "HKQuantityTypeIdentifierHeartRate":
                if (28.0...235.0).contains(num) {
                    day.hrValues.append(num)
                    day.hrTimedSamples.append((endDate.timeIntervalSince1970, num))
                }
            case "HKQuantityTypeIdentifierRespiratoryRate":
                if (5.0...45.0).contains(num) { day.respValues.append(num) }
            case "HKQuantityTypeIdentifierOxygenSaturation":
                let pct = num <= 1.05 ? num * 100.0 : num
                if (60.0...100.0).contains(pct) { day.spo2Values.append(pct) }
            case "HKQuantityTypeIdentifierAppleSleepingWristTemperature", "HKQuantityTypeIdentifierBodyTemperature":
                let celsius = (unitStr.localizedCaseInsensitiveContains("degF") || unitStr.contains("F")) ? (num - 32.0) * 5.0 / 9.0 : num
                if (28.0...42.0).contains(celsius) { day.tempCelsiusValues.append(celsius) }
            case "HKQuantityTypeIdentifierVO2Max":
                if (15.0...90.0).contains(num) { day.vo2Values.append(num) }
            case "HKQuantityTypeIdentifierBloodGlucose":
                let mgdl = unitStr.localizedCaseInsensitiveContains("mmol") ? num * 18.0182 : num
                if (35.0...400.0).contains(mgdl) { day.glucoseMgDlValues.append(mgdl) }
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
            let kcal = max(kcalRaw.map { Int((kcalUnit == "kj" ? $0 / 4.184 : $0).rounded()) } ?? Int((Double(durMin) * 7.5).rounded()), 10)
            let strain21 = min(max(21.0 * log(1.0 + Double(kcal) / 280.0) / log(1.0 + 4.5), 0.4), 20.5)
            let strainPct = min(max(Int(((strain21 / 21.0) * 100.0).rounded()), 2), 98)

            if isStrength { day.strengthMinutes += durMin }
            let item = EffortEventItem(
                id: "ah_wk_\(day.dateIso)_\(day.workouts.count)",
                title: title,
                timeRange: "\(timeFormatter.string(from: startDate)) - \(timeFormatter.string(from: endDate))",
                durationMin: durMin,
                avgHrBpm: 132,
                strainScore: AppleHealthExportImporter.round1(strain21),
                strainPct: strainPct,
                categoryLabel: category,
                kcal: kcal
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
                        strainPct: item.strainPct, categoryLabel: item.categoryLabel, kcal: item.kcal
                    )
                    day.workouts[activeWorkoutIdx] = item
                }
            } else if statType == "HKQuantityTypeIdentifierActiveEnergyBurned",
                      !activeWorkoutHasKcal,
                      let sumStr = attrs["sum"],
                      let sum = Double(sumStr.replacingOccurrences(of: ",", with: ".")) {
                let unit = (attrs["unit"] ?? "").lowercased()
                let kcal = max(Int((unit == "kj" ? sum / 4.184 : sum).rounded()), 10)
                let strain21 = min(max(21.0 * log(1.0 + Double(kcal) / 280.0) / log(1.0 + 4.5), 0.4), 20.5)
                let strainPct = min(max(Int(((strain21 / 21.0) * 100.0).rounded()), 2), 98)
                item = EffortEventItem(
                    id: item.id, title: item.title, timeRange: item.timeRange,
                    durationMin: item.durationMin, avgHrBpm: item.avgHrBpm,
                    strainScore: AppleHealthExportImporter.round1(strain21),
                    strainPct: strainPct, categoryLabel: item.categoryLabel, kcal: kcal
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
        if low.contains("strength") || low.contains("coretraining") { return ("Fuerza", "Fuerza", true) }
        if low.contains("running") { return ("Carrera", "Cardio", false) }
        if low.contains("cycling") { return ("Ciclismo", "Cardio", false) }
        if low.contains("walking") || low.contains("hiking") { return ("Caminata", "Aeróbico", false) }
        if low.contains("swimming") { return ("Natación", "Cardio", false) }
        if low.contains("highintensity") || low.contains("hiit") { return ("HIIT", "Alta intensidad", false) }
        if low.contains("yoga") || low.contains("pilates") { return ("Movilidad / Yoga", "Recuperación", false) }
        if low.contains("rowing") { return ("Remo", "Cardio", false) }
        if low.contains("soccer") || low.contains("football") { return ("Fútbol", "Deporte", false) }
        if low.contains("tennis") || low.contains("padel") { return ("Tenis / Pádel", "Deporte", false) }
        return ("Entrenamiento", "Actividad", false)
    }

    private static func mergeIntervalMinutes(_ intervals: [ClosedRange<Int64>]) -> Int {
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
        return max(Int(totalSec / 60), 0)
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

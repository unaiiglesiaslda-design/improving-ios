import Foundation

extension Notification.Name {
    static let improvingShortcutsSyncDidArrive = Notification.Name("com.improving.health.shortcutsSyncDidArrive")
}

/// Canonical payload written by Improving's native Apple Shortcuts AppIntent
/// (or dropped into `En mi iPhone / Improving /` as JSON, TXT, or CSV!).
struct ShortcutsSyncEnvelope: Codable {
    var source: String = "Atajos de Apple"
    var createdAtEpoch: Int64 = Int64(Date().timeIntervalSince1970)
    var hrValues: [String]? = nil
    var hrDates: [String]? = nil
    var hrvValues: [String]? = nil
    var hrvDates: [String]? = nil
    var rhrValues: [String]? = nil
    var rhrDates: [String]? = nil
    var respValues: [String]? = nil
    var respDates: [String]? = nil
    var spo2Values: [String]? = nil
    var spo2Dates: [String]? = nil
    var tempValues: [String]? = nil
    var tempDates: [String]? = nil
    var stepsValues: [String]? = nil
    var stepsDates: [String]? = nil
    var kcalValues: [String]? = nil
    var kcalDates: [String]? = nil
    var vo2Values: [String]? = nil
    var vo2Dates: [String]? = nil
    var hrrValues: [String]? = nil
    var hrrDates: [String]? = nil
    var distanceValues: [String]? = nil
    var distanceDates: [String]? = nil
    var cyclingDistanceValues: [String]? = nil
    var cyclingDistanceDates: [String]? = nil
    var flightsValues: [String]? = nil
    var flightsDates: [String]? = nil
    var weightValues: [String]? = nil
    var weightDates: [String]? = nil
    var sleepValues: [String]? = nil
    var sleepStarts: [String]? = nil
    var sleepEnds: [String]? = nil
    var workoutNames: [String]? = nil
    var workoutStarts: [String]? = nil
    var workoutEnds: [String]? = nil
    var workoutDurations: [String]? = nil
    var workoutKcals: [String]? = nil
    var workoutDistances: [String]? = nil
    var workoutLines: [String]? = nil
    var rawTextOrJson: String? = nil
}

/// Zero-entitlement automatic Apple Health sync bridge for Apple Shortcuts (`Atajos`),
/// `En mi iPhone / Improving` Files folder, `improving://sync` URL scheme, and Health Auto Export JSON.
/// Feeds directly into `AppleHealthExportImporter.buildSummaries` so every metric gets the EXACT same
/// Bevel 60-day causal rolling baselines, calibrated Strain/Recovery/Sleep, and continuous cross-day Energy Bank!
enum ShortcutsHealthSyncImporter {

    // MARK: - Public Documents & AutoSync Inbox Locations

    static var publicDocumentsURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var autoSyncInboxURL: URL {
        let dir = publicDocumentsURL.appendingPathComponent("AutoSync", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var latestShortcutsEnvelopeURL: URL {
        autoSyncInboxURL.appendingPathComponent("shortcuts_latest.json")
    }

    /// Writes an envelope produced by `SyncAppleHealthShortcutIntent` atomically and notifies the running app.
    @discardableResult
    static func saveEnvelopeToInbox(_ envelope: ShortcutsSyncEnvelope) -> URL? {
        let url = latestShortcutsEnvelopeURL
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted]
        guard let data = try? enc.encode(envelope) else { return nil }
        do {
            try data.write(to: url, options: .atomic)
            NotificationCenter.default.post(name: .improvingShortcutsSyncDidArrive, object: url)
            return url
        } catch {
            return nil
        }
    }

    /// Lists all supported sync files placed in `En mi iPhone/Improving/` (including 1-level subfolders like `AutoSync/`).
    static func discoverInboxFiles() -> [URL] {
        let fm = FileManager.default
        let exts: Set<String> = ["json", "txt", "csv", "xml", "zip"]
        var found: [URL] = []
        var seenPaths: Set<String> = []
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey, .isDirectoryKey]

        func scanDir(_ dir: URL, depth: Int) {
            guard let urls = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            ) else { return }
            for u in urls {
                let vals = try? u.resourceValues(forKeys: Set(keys))
                if vals?.isDirectory == true {
                    if depth < 1 {
                        scanDir(u, depth: depth + 1)
                    }
                    continue
                }
                guard vals?.isRegularFile == true else { continue }
                let ext = u.pathExtension.lowercased()
                let isNamedHealthFile = u.lastPathComponent.lowercased().contains("health") || u.lastPathComponent.lowercased().contains("sync")
                if exts.contains(ext) || (ext.isEmpty && isNamedHealthFile) {
                    let canon = u.standardizedFileURL.path
                    if seenPaths.insert(canon).inserted {
                        found.append(u)
                    }
                }
            }
        }

        scanDir(publicDocumentsURL, depth: 0)
        scanDir(autoSyncInboxURL, depth: 1)

        return found.sorted { a, b in
            let da = ((try? fm.attributesOfItem(atPath: a.path)[.modificationDate]) as? Date) ?? .distantPast
            let db = ((try? fm.attributesOfItem(atPath: b.path)[.modificationDate]) as? Date) ?? .distantPast
            return da < db
        }
    }

    /// Uncached kernel `stat()` signature with millisecond mtime + exact byte size so in-place
    /// Apple Shortcuts overwrites of `health_sync.json` are ALWAYS detected immediately!
    static func fileSignature(for url: URL) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let mtimeMs = Int64((((attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0) * 1000.0).rounded())
        let sz = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        // v8 prefix ensures instant re-parse with millisecond precision & live freshness tracking
        return "v8#\(url.lastPathComponent)#\(sz)#\(mtimeMs)"
    }

    static func fileModificationDate(for url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }

    static func isLightweightAutoSyncFile(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "json" || ext == "txt" || ext == "csv" || ext.isEmpty
    }

    // MARK: - Universal Entry Points (File URL, Raw Data, Raw String, or Envelope)

    static func isShortcutsOrJsonHealthFile(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "json" || ext == "txt"
    }

    static func parseFileURL(
        _ url: URL,
        profile: UserPhysiologyProfile = UserPhysiologyProfile(),
        priorHistory: [String: RealBiometricDaySummary] = [:]
    ) -> ExportParseResult {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            return .error("No se pudo leer el archivo \(url.lastPathComponent).")
        }
        return parseData(data, sourceName: url.lastPathComponent, profile: profile, priorHistory: priorHistory)
    }

    static func parseData(
        _ data: Data,
        sourceName: String = "Atajos de Apple",
        profile: UserPhysiologyProfile = UserPhysiologyProfile(),
        priorHistory: [String: RealBiometricDaySummary] = [:]
    ) -> ExportParseResult {
        // 1. Try canonical ShortcutsSyncEnvelope first
        if let env = try? JSONDecoder().decode(ShortcutsSyncEnvelope.self, from: data),
           envelopeHasAnyContent(env) {
            return parseEnvelope(env, sourceName: sourceName, profile: profile, priorHistory: priorHistory)
        }

        // 2. Try generic JSON (Health Auto Export, Shortcut Dictionary, array of samples, or daily scalar summary)
        if let obj = try? JSONSerialization.jsonObject(with: data) {
            var days: [String: AppleHealthExportImporter.MutableAppleDay] = [:]
            ingestGenericJsonObject(obj, into: &days)
            if !days.isEmpty {
                return AppleHealthExportImporter.buildSummaries(
                    from: days,
                    sourceName: sourceName,
                    profile: profile,
                    priorHistory: priorHistory
                )
            }
        }

        // 3. Try plain text / pipe / semicolon / tab lines from Shortcuts
        if let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
            return parseRawText(text, sourceName: sourceName, profile: profile, priorHistory: priorHistory)
        }

        return .error("No se reconocieron datos de Apple Salud en \(sourceName).")
    }

    static func parseRawText(
        _ rawText: String,
        sourceName: String = "Atajos de Apple",
        profile: UserPhysiologyProfile = UserPhysiologyProfile(),
        priorHistory: [String: RealBiometricDaySummary] = [:]
    ) -> ExportParseResult {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .error("El texto recibido desde Atajos está vacío.")
        }
        // If it looks like JSON, route through JSON parser
        if (trimmed.hasPrefix("{") || trimmed.hasPrefix("[")),
           let data = trimmed.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) {
            var days: [String: AppleHealthExportImporter.MutableAppleDay] = [:]
            ingestGenericJsonObject(obj, into: &days)
            if !days.isEmpty {
                return AppleHealthExportImporter.buildSummaries(
                    from: days,
                    sourceName: sourceName,
                    profile: profile,
                    priorHistory: priorHistory
                )
            }
        }
        // If it looks like Apple Health XML snippet
        if trimmed.contains("<Record ") || trimmed.contains("<HealthData"),
           let data = trimmed.data(using: .utf8) {
            return AppleHealthExportImporter.parseXmlData(data, sourceName: sourceName, profile: profile)
        }

        var days: [String: AppleHealthExportImporter.MutableAppleDay] = [:]
        ingestPipeLines(trimmed, into: &days)
        guard !days.isEmpty else {
            return .error("No se encontraron mediciones válidas en los datos de Atajos.")
        }
        return AppleHealthExportImporter.buildSummaries(
            from: days,
            sourceName: sourceName,
            profile: profile,
            priorHistory: priorHistory
        )
    }

    static func parseEnvelope(
        _ env: ShortcutsSyncEnvelope,
        sourceName: String = "Atajos de Apple",
        profile: UserPhysiologyProfile = UserPhysiologyProfile(),
        priorHistory: [String: RealBiometricDaySummary] = [:]
    ) -> ExportParseResult {
        var days: [String: AppleHealthExportImporter.MutableAppleDay] = [:]

        ingestParallelSeries(kind: .hr, values: env.hrValues, dates: env.hrDates, into: &days)
        ingestParallelSeries(kind: .hrv, values: env.hrvValues, dates: env.hrvDates, into: &days)
        ingestParallelSeries(kind: .rhr, values: env.rhrValues, dates: env.rhrDates, into: &days)
        ingestParallelSeries(kind: .resp, values: env.respValues, dates: env.respDates, into: &days)
        ingestParallelSeries(kind: .spo2, values: env.spo2Values, dates: env.spo2Dates, into: &days)
        ingestParallelSeries(kind: .temp, values: env.tempValues, dates: env.tempDates, into: &days)
        ingestParallelSeries(kind: .steps, values: env.stepsValues, dates: env.stepsDates, into: &days)
        ingestParallelSeries(kind: .kcal, values: env.kcalValues, dates: env.kcalDates, into: &days)
        ingestParallelSeries(kind: .vo2, values: env.vo2Values, dates: env.vo2Dates, into: &days)
        ingestParallelSeries(kind: .hrr, values: env.hrrValues, dates: env.hrrDates, into: &days)
        ingestParallelSeries(kind: .distanceKm, values: env.distanceValues, dates: env.distanceDates, into: &days)
        ingestParallelSeries(kind: .distanceKm, values: env.cyclingDistanceValues, dates: env.cyclingDistanceDates, into: &days)
        ingestParallelSeries(kind: .flights, values: env.flightsValues, dates: env.flightsDates, into: &days)
        ingestParallelSeries(kind: .weight, values: env.weightValues, dates: env.weightDates, into: &days)
        ingestParallelSleep(values: env.sleepValues, starts: env.sleepStarts, ends: env.sleepEnds, sourceName: env.source, into: &days)
        ingestParallelWorkouts(
            names: env.workoutNames,
            starts: env.workoutStarts,
            ends: env.workoutEnds,
            durations: env.workoutDurations,
            kcals: env.workoutKcals,
            distances: env.workoutDistances,
            into: &days
        )

        if let wkLines = env.workoutLines {
            for line in expandLines(wkLines) {
                ingestSinglePipeLine(line.hasPrefix("workout") ? line : "workout|\(line)", into: &days)
            }
        }
        if let raw = env.rawTextOrJson?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            if (raw.hasPrefix("{") || raw.hasPrefix("[")),
               let data = raw.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) {
                ingestGenericJsonObject(obj, into: &days)
            } else {
                ingestPipeLines(raw, into: &days)
            }
        }

        guard !days.isEmpty else {
            return .error("No se recibieron muestras de Salud válidas desde Atajos.")
        }

        return AppleHealthExportImporter.buildSummaries(
            from: days,
            sourceName: sourceName,
            profile: profile,
            priorHistory: priorHistory
        )
    }

    private static func envelopeHasAnyContent(_ e: ShortcutsSyncEnvelope) -> Bool {
        let lists: [[String]?] = [
            e.hrValues, e.hrvValues, e.rhrValues, e.respValues, e.spo2Values,
            e.tempValues, e.stepsValues, e.kcalValues, e.vo2Values, e.hrrValues,
            e.distanceValues, e.cyclingDistanceValues, e.flightsValues, e.weightValues,
            e.sleepValues, e.workoutNames, e.workoutStarts, e.workoutLines
        ]
        if lists.contains(where: { !($0?.isEmpty ?? true) }) { return true }
        return !(e.rawTextOrJson?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    // MARK: - Metric Kind Classification (Spanish & English)

    private enum SyncMetricKind {
        case hr, hrv, hrvRmssd, rhr, resp, spo2, temp, steps, kcal, vo2, hrr, weight, bodyFat, leanMass, daylight, audio
        case distanceKm, flights, elevationM, powerW, cadenceRpm
    }

    private static func classifyMetricKey(_ rawKey: String) -> SyncMetricKind? {
        let k = rawKey
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        if k.contains("rmssd") || k.contains("recovery hrv") { return .hrvRmssd }
        if k == "hrv" || k == "vfc" || k.contains("variabil") || k.contains("sdnn") { return .hrv }
        if k == "rhr" || k == "fcr" || k.contains("resting heart") || k.contains("en reposo") { return .rhr }
        if k == "hr" || k == "fc" || k.contains("heart rate") || k.contains("frecuencia cardiaca") || k.contains("ritmo cardiaco") || k.contains("pulso") {
            if k.contains("recovery") || k.contains("recuperacion") { return .hrr }
            return .hr
        }
        if k == "resp" || k == "fr" || k.contains("respirat") { return .resp }
        if k == "spo2" || k.contains("oxygen") || k.contains("oxigeno") || k.contains("saturacion") { return .spo2 }
        if k == "temp" || k.contains("temperat") || k.contains("wrist") || k.contains("muneca") { return .temp }
        if k == "steps" || k.contains("step") || k.contains("paso") { return .steps }
        if k == "kcal" || k == "calories" || k.contains("active energy") || k.contains("energia activa") || k.contains("calorias") { return .kcal }
        if k == "vo2" || k.contains("vo2") || k.contains("capacidad aerobica") { return .vo2 }
        if k == "hrr" || k.contains("heart rate recovery") || k.contains("recuperacion de fc") || k.contains("recuperacion cardiaca") { return .hrr }
        if k.contains("flight") || k.contains("pisos") || k.contains("escaleras") { return .flights }
        if k.contains("elevat") || k.contains("desnivel") || k.contains("altitud") { return .elevationM }
        if k.contains("distanc") || k == "km" { return .distanceKm }
        if k.contains("power") || k.contains("potencia") { return .powerW }
        if k.contains("cadenc") { return .cadenceRpm }
        if k == "weight" || k == "peso" || k.contains("body mass") || k.contains("masa corporal") { return .weight }
        if k.contains("body fat") || k.contains("grasa") { return .bodyFat }
        if k.contains("lean") || k.contains("masa magra") { return .leanMass }
        if k.contains("daylight") || k.contains("luz natural") || k.contains("luz solar") { return .daylight }
        if k.contains("audio") || k.contains("ruido") || k.contains("noise") { return .audio }
        return nil
    }

    // MARK: - Parallel Series Ingestion (Zero-Loop Apple Shortcuts Mode!)

    private static func expandLines(_ raw: [String]?) -> [String] {
        guard let raw else { return [] }
        return raw.flatMap { item in
            item.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
    }

    /// Splits a Shortcuts newline-joined parallel list while preserving internal empty lines so
    /// parallel indices (`values[i]`, `starts[i]`, `ends[i]`) NEVER shift out of alignment!
    private static func expandParallelLines(_ raw: [String]?) -> [String] {
        guard let raw, !raw.isEmpty else { return [] }
        if raw.count == 1 {
            var lines = raw[0]
                .replacingOccurrences(of: "\r\n", with: "\n")
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            while lines.last?.isEmpty == true { lines.removeLast() }
            while lines.first?.isEmpty == true { lines.removeFirst() }
            return lines
        }
        return expandLines(raw)
    }

    private static func ingestParallelSeries(
        kind: SyncMetricKind,
        values rawVals: [String]?,
        dates rawDates: [String]?,
        into days: inout [String: AppleHealthExportImporter.MutableAppleDay]
    ) {
        let vals = expandParallelLines(rawVals)
        guard !vals.isEmpty else { return }
        let dates = expandParallelLines(rawDates)
        let fallbackNow = Date()
        let allowDotThousands = (kind == .steps)

        // Deduplicate exact (day, minute, roundedValue) collisions caused by ungrouped Watch + iPhone Shortcuts samples
        var seenSamples: Set<String> = []
        seenSamples.reserveCapacity(vals.count)

        for idx in 0..<vals.count {
            guard let num = parseLocalizedNumber(vals[idx], allowDotThousands: allowDotThousands) else { continue }
            let parsed: (date: Date, wall: (iso: String, minuteOfDay: Int))
            if !dates.isEmpty {
                let rawDateStr = idx < dates.count ? dates[idx] : ""
                // Never collapse unparseable multi-day dates onto `today` (prevents summing 3 days of kcal onto today!)
                guard let ok = parseFlexibleDate(rawDateStr) else { continue }
                parsed = ok
            } else {
                parsed = (fallbackNow, wallClock(for: fallbackNow))
            }

            let dedupeKey = "\(parsed.wall.iso)#\(parsed.wall.minuteOfDay)#\(Int((num * 100.0).rounded()))"
            if !seenSamples.insert(dedupeKey).inserted {
                continue
            }

            recordSample(kind: kind, value: num, date: parsed.date, wall: parsed.wall, unitHint: vals[idx], into: &days)
        }
    }

    private static func ingestParallelSleep(
        values rawVals: [String]?,
        starts rawStarts: [String]?,
        ends rawEnds: [String]?,
        sourceName: String,
        into days: inout [String: AppleHealthExportImporter.MutableAppleDay]
    ) {
        let starts = expandParallelLines(rawStarts)
        let ends = expandParallelLines(rawEnds)
        let vals = expandParallelLines(rawVals)
        let count = min(starts.count, ends.count)
        guard count > 0 else { return }

        for i in 0..<count {
            guard let s = parseFlexibleDate(starts[i]),
                  let e = parseFlexibleDate(ends[i]) else { continue }
            let sEp = Int64(s.date.timeIntervalSince1970)
            let eEp = Int64(e.date.timeIntervalSince1970)
            let dur = eEp - sEp
            guard dur > 0 && dur <= 14 * 3600 else { continue }
            let stageRaw = (i < vals.count && !vals[i].isEmpty) ? vals[i] : "Asleep"
            addSleepInterval(startEpoch: sEp, endEpoch: eEp, endDayIso: e.wall.iso, stageRaw: stageRaw, sourceName: sourceName, into: &days)
        }
    }

    // MARK: - Generic JSON Ingestion (Shortcuts Dictionary + Health Auto Export + Array of Samples)

    private static func ingestGenericJsonObject(
        _ obj: Any,
        into days: inout [String: AppleHealthExportImporter.MutableAppleDay]
    ) {
        if let arr = obj as? [[String: Any]] {
            for item in arr { ingestSingleSampleDict(item, into: &days) }
            return
        }
        guard let dict = obj as? [String: Any] else { return }

        // 1. Health Auto Export format: { "data": { "metrics": [...], "workouts": [...] } }
        if let dataObj = dict["data"] as? [String: Any] {
            if let metrics = dataObj["metrics"] as? [[String: Any]] {
                for m in metrics {
                    ingestHealthAutoExportMetric(m, into: &days)
                }
            }
            if let workouts = dataObj["workouts"] as? [[String: Any]] {
                for w in workouts {
                    ingestWorkoutDict(w, into: &days)
                }
            }
            if !days.isEmpty { return }
        }

        // 2. Explicit samples / workouts arrays: { "samples": [...], "workouts": [...] }
        if let samples = dict["samples"] as? [[String: Any]] {
            for s in samples { ingestSingleSampleDict(s, into: &days) }
        }
        if let workouts = dict["workouts"] as? [[String: Any]] {
            for w in workouts { ingestWorkoutDict(w, into: &days) }
        }

        // 3. Parallel-list keys inside a Shortcut Dictionary (e.g. hr_values + hr_dates, sleep_values + sleep_starts + sleep_ends, workout_names + workout_starts...)
        let parallelPrefixes: [(prefix: String, kind: SyncMetricKind)] = [
            ("hr", .hr), ("fc", .hr),
            ("rmssd", .hrvRmssd), ("hrv_rmssd", .hrvRmssd), ("vfc_rmssd", .hrvRmssd),
            ("hrv", .hrv), ("vfc", .hrv),
            ("rhr", .rhr), ("fcr", .rhr),
            ("resp", .resp), ("fr", .resp),
            ("spo2", .spo2),
            ("temp", .temp),
            ("steps", .steps), ("pasos", .steps),
            ("kcal", .kcal), ("active_kcal", .kcal), ("calories", .kcal),
            ("vo2", .vo2),
            ("hrr", .hrr), ("hr_recovery", .hrr),
            ("distance", .distanceKm), ("walk_distance", .distanceKm), ("cycling_distance", .distanceKm), ("distancia", .distanceKm),
            ("flights", .flights), ("pisos", .flights),
            ("elevation", .elevationM), ("desnivel", .elevationM),
            ("power", .powerW), ("potencia", .powerW),
            ("cadence", .cadenceRpm), ("cadencia", .cadenceRpm),
            ("weight", .weight), ("peso", .weight)
        ]
        for (p, kind) in parallelPrefixes {
            let vList = extractStringList(dict["\(p)_values"] ?? dict["\(p)Values"])
            let dList = extractStringList(dict["\(p)_dates"] ?? dict["\(p)Dates"])
            if !vList.isEmpty {
                ingestParallelSeries(kind: kind, values: vList, dates: dList, into: &days)
            }
        }
        let slVals = extractStringList(dict["sleep_values"] ?? dict["sleepValues"])
        let slStarts = extractStringList(dict["sleep_starts"] ?? dict["sleepStarts"])
        let slEnds = extractStringList(dict["sleep_ends"] ?? dict["sleepEnds"])
        if !slStarts.isEmpty && !slEnds.isEmpty {
            ingestParallelSleep(values: slVals, starts: slStarts, ends: slEnds, sourceName: "Atajos de Apple", into: &days)
        }
        let wkNames = extractStringList(dict["workout_names"] ?? dict["workoutNames"] ?? dict["workout_types"] ?? dict["workouts_names"])
        let wkStarts = extractStringList(dict["workout_starts"] ?? dict["workoutStarts"] ?? dict["workouts_starts"] ?? dict["workout_dates"])
        let wkEnds = extractStringList(dict["workout_ends"] ?? dict["workoutEnds"] ?? dict["workouts_ends"])
        let wkDurs = extractStringList(dict["workout_durations"] ?? dict["workoutDurations"] ?? dict["workouts_durations"])
        let wkKcals = extractStringList(dict["workout_kcals"] ?? dict["workoutKcals"] ?? dict["workout_values"] ?? dict["workouts_values"])
        let wkDists = extractStringList(dict["workout_distances"] ?? dict["workoutDistances"])
        if !wkStarts.isEmpty {
            ingestParallelWorkouts(
                names: wkNames,
                starts: wkStarts,
                ends: wkEnds,
                durations: wkDurs,
                kcals: wkKcals,
                distances: wkDists,
                into: &days
            )
        }

        // 4. Shorthand dictionary keys: { "hr": ["2026-11-23 08:15|64"], "hrv": 72.0, "date": "2026-11-23", ... }
        let defaultDatePair: (date: Date, wall: (iso: String, minuteOfDay: Int)) = {
            if let ds = dict["date"] as? String ?? dict["fecha"] as? String, let parsed = parseFlexibleDate(ds) {
                return parsed
            }
            let now = Date()
            return (now, wallClock(for: now))
        }()

        // Optional scalar sleep_minutes / deep_minutes / rem_minutes
        if let slMin = anyToDouble(dict["sleep_minutes"] ?? dict["sueno_min"]), slMin > 10 {
            let endDt = defaultDatePair.date
            let startDt = endDt.addingTimeInterval(-slMin * 60.0)
            let sEp = Int64(startDt.timeIntervalSince1970)
            let eEp = Int64(endDt.timeIntervalSince1970)
            addSleepInterval(startEpoch: sEp, endEpoch: eEp, endDayIso: defaultDatePair.wall.iso, stageRaw: "Asleep", sourceName: "Atajos de Apple", into: &days)
        }

        for (rawKey, rawVal) in dict {
            let low = rawKey.lowercased()
            if low.hasSuffix("_values") || low.hasSuffix("_dates") || low.hasSuffix("_starts") || low.hasSuffix("_ends")
                || low == "date" || low == "fecha" || low == "samples" || low == "workouts" || low == "data" || low == "source" {
                continue
            }
            if low == "sleep" || low == "sueno" || low == "sueño" {
                for line in extractStringList(rawVal) {
                    ingestSinglePipeLine(line.lowercased().hasPrefix("sleep") ? line : "sleep|\(line)", into: &days)
                }
                continue
            }
            guard let kind = classifyMetricKey(rawKey) else { continue }
            if let num = anyToDouble(rawVal) {
                recordSample(kind: kind, value: num, date: defaultDatePair.date, wall: defaultDatePair.wall, unitHint: "", into: &days)
            } else {
                let items = extractStringList(rawVal)
                let allowStepsDot = (kind == .steps)
                for item in items {
                    let parts = splitDelimited(item)
                    if parts.count >= 2, let parsed = parseFlexibleDate(parts[0]), let num = parseLocalizedNumber(parts[1], allowDotThousands: allowStepsDot) {
                        recordSample(kind: kind, value: num, date: parsed.date, wall: parsed.wall, unitHint: parts[1], into: &days)
                    } else if let num = parseLocalizedNumber(item, allowDotThousands: allowStepsDot) {
                        recordSample(kind: kind, value: num, date: defaultDatePair.date, wall: defaultDatePair.wall, unitHint: item, into: &days)
                    }
                }
            }
        }
    }

    private static func ingestHealthAutoExportMetric(
        _ metric: [String: Any],
        into days: inout [String: AppleHealthExportImporter.MutableAppleDay]
    ) {
        let name = (metric["name"] as? String) ?? ""
        let units = (metric["units"] as? String) ?? ""
        guard let rows = metric["data"] as? [[String: Any]], !rows.isEmpty else { return }

        let lowName = name.lowercased()
        if lowName.contains("sleep") {
            for r in rows {
                let startStr = (r["sleepStart"] as? String) ?? (r["inBedStart"] as? String) ?? (r["startDate"] as? String) ?? (r["date"] as? String)
                let endStr = (r["sleepEnd"] as? String) ?? (r["inBedEnd"] as? String) ?? (r["endDate"] as? String)
                if let ss = startStr, let es = endStr,
                   let s = parseFlexibleDate(ss), let e = parseFlexibleDate(es) {
                    let sEp = Int64(s.date.timeIntervalSince1970)
                    let eEp = Int64(e.date.timeIntervalSince1970)
                    if eEp > sEp {
                        let day = mutableDay(iso: e.wall.iso, in: &days)
                        day.sleepSourceName = day.sleepSourceName ?? "Apple Health"
                        day.inBedIntervals.append(sEp...eEp)
                        if let deepHrs = anyToDouble(r["deep"]), deepHrs > 0 {
                            let dSec = Int64((deepHrs > 15 ? deepHrs * 60 : deepHrs * 3600).rounded())
                            day.deepIntervals.append(sEp...(sEp + dSec))
                        }
                        if let remHrs = anyToDouble(r["rem"]), remHrs > 0 {
                            let rSec = Int64((remHrs > 15 ? remHrs * 60 : remHrs * 3600).rounded())
                            let base = (day.deepIntervals.last?.upperBound ?? sEp)
                            day.remIntervals.append(base...(base + rSec))
                        }
                        if let coreHrs = anyToDouble(r["core"]), coreHrs > 0 {
                            let cSec = Int64((coreHrs > 15 ? coreHrs * 60 : coreHrs * 3600).rounded())
                            let base = (day.remIntervals.last?.upperBound ?? day.deepIntervals.last?.upperBound ?? sEp)
                            day.coreIntervals.append(base...(base + cSec))
                        }
                        if let awakeHrs = anyToDouble(r["awake"]), awakeHrs > 0 {
                            let aSec = Int64((awakeHrs > 15 ? awakeHrs * 60 : awakeHrs * 3600).rounded())
                            day.awakeIntervals.append(max(eEp - aSec, sEp)...eEp)
                        }
                        if let asleepHrs = anyToDouble(r["asleep"] ?? r["totalSleep"]), asleepHrs > 0 {
                            let aSec = Int64((asleepHrs > 15 ? asleepHrs * 60 : asleepHrs * 3600).rounded())
                            day.asleepAnyIntervals.append(sEp...(sEp + aSec))
                        }
                    }
                }
            }
            return
        }

        guard let kind = classifyMetricKey(name) else { return }
        for r in rows {
            guard let dateStr = (r["date"] as? String) ?? (r["startDate"] as? String),
                  let parsed = parseFlexibleDate(dateStr) else { continue }
            let val = anyToDouble(r["qty"] ?? r["Avg"] ?? r["avg"] ?? r["value"] ?? r["val"])
            if let v = val {
                recordSample(kind: kind, value: v, date: parsed.date, wall: parsed.wall, unitHint: units, into: &days)
            }
        }
    }

    private static func ingestSingleSampleDict(
        _ item: [String: Any],
        into days: inout [String: AppleHealthExportImporter.MutableAppleDay]
    ) {
        let typeStr = (item["type"] as? String) ?? (item["metric"] as? String) ?? (item["tipo"] as? String) ?? ""
        let lowType = typeStr.lowercased()

        if lowType.contains("sleep") || lowType.contains("sueño") || lowType.contains("sueno") {
            let sStr = (item["start"] as? String) ?? (item["startDate"] as? String) ?? (item["inicio"] as? String) ?? ""
            let eStr = (item["end"] as? String) ?? (item["endDate"] as? String) ?? (item["fin"] as? String) ?? ""
            let stage = (item["stage"] as? String) ?? (item["value"] as? String) ?? (item["valor"] as? String) ?? "Asleep"
            if let s = parseFlexibleDate(sStr), let e = parseFlexibleDate(eStr) {
                let sEp = Int64(s.date.timeIntervalSince1970)
                let eEp = Int64(e.date.timeIntervalSince1970)
                if eEp > sEp {
                    addSleepInterval(startEpoch: sEp, endEpoch: eEp, endDayIso: e.wall.iso, stageRaw: stage, sourceName: (item["source"] as? String) ?? "Atajos de Apple", into: &days)
                }
            }
            return
        }

        if lowType.contains("workout") || lowType.contains("entren") {
            ingestWorkoutDict(item, into: &days)
            return
        }

        guard let kind = classifyMetricKey(typeStr),
              let val = anyToDouble(item["value"] ?? item["valor"] ?? item["qty"]) else { return }
        let dateStr = (item["date"] as? String) ?? (item["endDate"] as? String) ?? (item["startDate"] as? String) ?? (item["fecha"] as? String) ?? ""
        let parsed = parseFlexibleDate(dateStr) ?? (Date(), wallClock(for: Date()))
        let unit = (item["unit"] as? String) ?? (item["unidad"] as? String) ?? ""
        recordSample(kind: kind, value: val, date: parsed.date, wall: parsed.wall, unitHint: unit, into: &days)
    }

    private static func ingestWorkoutDict(
        _ w: [String: Any],
        into days: inout [String: AppleHealthExportImporter.MutableAppleDay]
    ) {
        let sStr = (w["start"] as? String) ?? (w["startDate"] as? String) ?? (w["inicio"] as? String) ?? ""
        guard let s = parseFlexibleDate(sStr) else { return }
        let eStr = (w["end"] as? String) ?? (w["endDate"] as? String) ?? (w["fin"] as? String) ?? ""
        let e = parseFlexibleDate(eStr) ?? s

        let rawName = (w["name"] as? String) ?? (w["activityType"] as? String) ?? (w["title"] as? String) ?? (w["actividad"] as? String) ?? "Entrenamiento"
        let (title, category, isStrength) = AppleHealthExportImporter.mapWorkoutName(rawName)
        let durMin = Int((anyToDouble(w["duration"] ?? w["duracion"]) ?? max(e.date.timeIntervalSince(s.date) / 60.0, 1.0)).rounded())
        let kcalVal: Double = {
            if let activeObj = w["activeEnergyBurned"] as? [String: Any], let q = anyToDouble(activeObj["qty"]) { return q }
            return anyToDouble(w["kcal"] ?? w["activeEnergy"] ?? w["calories"] ?? w["calorias"]) ?? 0
        }()
        let avgHrVal: Double = {
            if let hrObj = w["heartRate"] as? [String: Any], let q = anyToDouble(hrObj["avg"] ?? hrObj["Avg"]) { return q }
            return anyToDouble(w["avgHr"] ?? w["avgHeartRate"] ?? w["fc_media"]) ?? 0
        }()
        let distKmVal: Double? = {
            if let distObj = w["distance"] as? [String: Any], let q = anyToDouble(distObj["qty"]) {
                let u = ((distObj["units"] as? String) ?? "").lowercased()
                return u == "m" ? q / 1000.0 : (u.contains("mi") ? q * 1.60934 : q)
            }
            return anyToDouble(w["distanceKm"] ?? w["distance"] ?? w["distancia"])
        }()
        let elevMVal: Double? = {
            if let elObj = w["elevationUp"] as? [String: Any], let q = anyToDouble(elObj["qty"]) { return q }
            return anyToDouble(w["elevationM"] ?? w["elevation"] ?? w["desnivel"])
        }()
        addWorkout(
            title: title == "Entrenamiento" && !rawName.isEmpty ? rawName : title,
            category: category,
            isStrength: isStrength,
            start: s,
            end: e,
            durationMin: max(durMin, 1),
            kcal: max(Int(kcalVal.rounded()), 0),
            avgHr: max(Int(avgHrVal.rounded()), 0),
            distanceKm: distKmVal,
            elevationM: elevMVal,
            into: &days
        )
    }

    private static func ingestParallelWorkouts(
        names rawNames: [String]?,
        starts rawStarts: [String]?,
        ends rawEnds: [String]?,
        durations rawDurations: [String]?,
        kcals rawKcals: [String]?,
        distances rawDistances: [String]?,
        into days: inout [String: AppleHealthExportImporter.MutableAppleDay]
    ) {
        let starts = expandParallelLines(rawStarts)
        guard !starts.isEmpty else { return }
        let names = expandParallelLines(rawNames)
        let ends = expandParallelLines(rawEnds)
        let durs = expandParallelLines(rawDurations)
        let kcals = expandParallelLines(rawKcals)
        let dists = expandParallelLines(rawDistances)

        for i in 0..<starts.count {
            guard let s = parseFlexibleDate(starts[i]) else { continue }
            let eOpt = i < ends.count ? parseFlexibleDate(ends[i]) : nil
            let durFromField: Int? = {
                guard i < durs.count, !durs[i].isEmpty else { return nil }
                let low = durs[i].lowercased()
                if let val = parseLocalizedNumber(durs[i]) {
                    if low.contains("seg") || low.contains("sec") || (val > 400 && !low.contains("min") && !low.contains("h")) {
                        return max(Int((val / 60.0).rounded()), 1)
                    }
                    if low.contains("h") && val <= 12 {
                        return max(Int((val * 60.0).rounded()), 1)
                    }
                    return max(Int(val.rounded()), 1)
                }
                return nil
            }()
            let spanMin: Int = {
                if let e = eOpt {
                    return max(Int((e.date.timeIntervalSince(s.date) / 60.0).rounded()), 1)
                }
                return durFromField ?? 30
            }()
            let finalDur = min(max(durFromField ?? spanMin, 1), 720)
            let endPair: (date: Date, wall: (iso: String, minuteOfDay: Int)) = eOpt ?? {
                let endDt = s.date.addingTimeInterval(Double(finalDur * 60))
                return (endDt, wallClock(for: endDt))
            }()

            let rawName = (i < names.count && !names[i].isEmpty) ? names[i] : "Entrenamiento"
            let (mapped, cat, isStr) = AppleHealthExportImporter.mapWorkoutName(rawName)
            let kcal: Int = {
                guard i < kcals.count, let v = parseLocalizedNumber(kcals[i]) else { return 0 }
                let low = kcals[i].lowercased()
                let k = low.contains("kj") ? v / 4.184 : v
                return (1.0...6_000.0).contains(k) ? Int(k.rounded()) : 0
            }()
            let distKm: Double? = {
                guard i < dists.count, let v = parseLocalizedNumber(dists[i]), v > 0 else { return nil }
                let low = dists[i].lowercased()
                let km = (low.contains(" m") || low.hasSuffix("m")) && !low.contains("km") && !low.contains("mi")
                    ? v / 1000.0
                    : (low.contains("mi") ? v * 1.60934 : v)
                return km > 0 && km < 300 ? AppleHealthExportImporter.round1(km) : nil
            }()

            addWorkout(
                title: mapped == "Entrenamiento" && rawName != "Entrenamiento" ? rawName : mapped,
                category: cat,
                isStrength: isStr,
                start: s,
                end: endPair,
                durationMin: finalDur,
                kcal: kcal,
                avgHr: 0,
                distanceKm: distKm,
                elevationM: nil,
                into: &days
            )
        }
    }

    // MARK: - Pipe / Delimited Plain Text Ingestion

    private static func ingestPipeLines(
        _ text: String,
        into days: inout [String: AppleHealthExportImporter.MutableAppleDay]
    ) {
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            ingestSinglePipeLine(line, into: &days)
        }
    }

    private static func ingestSinglePipeLine(
        _ line: String,
        into days: inout [String: AppleHealthExportImporter.MutableAppleDay]
    ) {
        let parts = splitDelimited(line)
        guard parts.count >= 2 else { return }
        let head = parts[0].lowercased()

        if head == "sleep" || head == "sueno" || head == "sueño" {
            guard parts.count >= 3,
                  let s = parseFlexibleDate(parts[1]),
                  let e = parseFlexibleDate(parts[2]) else { return }
            let stage = parts.count >= 4 ? parts[3] : "Asleep"
            let sEp = Int64(s.date.timeIntervalSince1970)
            let eEp = Int64(e.date.timeIntervalSince1970)
            if eEp > sEp {
                addSleepInterval(startEpoch: sEp, endEpoch: eEp, endDayIso: e.wall.iso, stageRaw: stage, sourceName: "Atajos de Apple", into: &days)
            }
            return
        }

        if head == "workout" || head == "entrenamiento" {
            guard parts.count >= 4, let s = parseFlexibleDate(parts[1]), let e = parseFlexibleDate(parts[2]) else { return }
            let rawType = parts[3]
            let (mapped, cat, isStr) = AppleHealthExportImporter.mapWorkoutName(rawType)
            let dur = parts.count >= 5 ? Int((parseLocalizedNumber(parts[4]) ?? max(e.date.timeIntervalSince(s.date) / 60.0, 1)).rounded()) : max(Int((e.date.timeIntervalSince(s.date) / 60.0).rounded()), 1)
            let kcal = parts.count >= 6 ? Int((parseLocalizedNumber(parts[5]) ?? 0).rounded()) : 0
            let avgHr = parts.count >= 7 ? Int((parseLocalizedNumber(parts[6]) ?? 0).rounded()) : 0
            addWorkout(title: mapped == "Entrenamiento" ? rawType : mapped, category: cat, isStrength: isStr, start: s, end: e, durationMin: max(dur, 1), kcal: max(kcal, 0), avgHr: max(avgHr, 0), into: &days)
            return
        }

        guard let kind = classifyMetricKey(parts[0]) else { return }
        let allowStepsDot = (kind == .steps)
        if parts.count >= 3, let parsed = parseFlexibleDate(parts[1]), let num = parseLocalizedNumber(parts[2], allowDotThousands: allowStepsDot) {
            recordSample(kind: kind, value: num, date: parsed.date, wall: parsed.wall, unitHint: parts[2], into: &days)
        } else if let num = parseLocalizedNumber(parts[1], allowDotThousands: allowStepsDot) {
            let now = Date()
            recordSample(kind: kind, value: num, date: now, wall: wallClock(for: now), unitHint: parts[1], into: &days)
        }
    }

    // MARK: - Core MutableAppleDay Recording Helpers

    private static func mutableDay(
        iso: String,
        in days: inout [String: AppleHealthExportImporter.MutableAppleDay]
    ) -> AppleHealthExportImporter.MutableAppleDay {
        if let existing = days[iso] { return existing }
        let created = AppleHealthExportImporter.MutableAppleDay(dateIso: iso)
        days[iso] = created
        return created
    }

    private static func recordSample(
        kind: SyncMetricKind,
        value num: Double,
        date: Date,
        wall: (iso: String, minuteOfDay: Int),
        unitHint: String,
        into days: inout [String: AppleHealthExportImporter.MutableAppleDay]
    ) {
        guard num.isFinite else { return }
        let day = mutableDay(iso: wall.iso, in: &days)
        let ep = Int64(date.timeIntervalSince1970)
        let lowUnit = unitHint.lowercased()

        switch kind {
        case .hr:
            if (28.0...235.0).contains(num) {
                day.hrSamples.append((ep, wall.minuteOfDay, num))
            }
        case .hrv:
            // Shortcuts may emit HRV in seconds (e.g. "0.068") without attaching the "s" unit label
            let ms = (num >= 0.003 && num < 2.0) ? num * 1000.0 : num
            if (3.0...350.0).contains(ms) {
                day.hrvSamples.append((ep, ms))
            }
        case .hrvRmssd:
            let ms = (num >= 0.003 && num < 2.0) ? num * 1000.0 : num
            if (3.0...350.0).contains(ms) {
                day.hrvRmssdSamples.append((ep, ms))
            }
        case .rhr:
            if (28.0...130.0).contains(num) {
                day.rhrValues.append(num)
            }
        case .resp:
            if (5.0...45.0).contains(num) {
                day.respSamples.append((ep, num))
            }
        case .spo2:
            let pct = num <= 1.05 ? num * 100.0 : num
            if (60.0...100.0).contains(pct) {
                day.spo2Samples.append((ep, pct))
            }
        case .temp:
            let celsius = (lowUnit.contains("f") && num > 60.0) ? (num - 32.0) * 5.0 / 9.0 : num
            if (28.0...42.0).contains(celsius) {
                day.tempCelsiusValues.append(celsius)
            }
        case .steps:
            if (0.0...120_000.0).contains(num) {
                day.stepsSum += num
                day.hasSteps = true
            }
        case .kcal:
            let kcal = lowUnit.contains("kj") ? num / 4.184 : num
            // Guard against corrupted/unitless spikes (> 4,500 kcal in a single Apple Health sample)
            if (0.0...4_500.0).contains(kcal) {
                day.activeKcalSum += kcal
                day.hasActiveKcal = true
            }
        case .vo2:
            if (15.0...90.0).contains(num) { day.vo2Values.append(num) }
        case .hrr:
            if (1.0...110.0).contains(num) { day.hrrValues.append(num) }
        case .weight:
            let kg = lowUnit.contains("lb") ? num * 0.453592 : num
            if (25.0...260.0).contains(kg) { day.weightValues.append(kg) }
        case .bodyFat:
            let pct = num <= 1.0 ? num * 100.0 : num
            if (3.0...65.0).contains(pct) { day.bodyFatValues.append(pct) }
        case .leanMass:
            let kg = lowUnit.contains("lb") ? num * 0.453592 : num
            if (20.0...180.0).contains(kg) { day.leanMassValues.append(kg) }
        case .daylight:
            if (0.0...1440.0).contains(num) {
                day.daylightMinSum += num
                day.hasDaylight = true
            }
        case .audio:
            if (20.0...130.0).contains(num) { day.audioSamplesDb.append((ep, num)) }
        case .distanceKm:
            let km = (lowUnit.contains("mi") ? num * 1.60934 : ((lowUnit.contains(" m") || lowUnit == "m") && !lowUnit.contains("km") ? num / 1000.0 : num))
            if (0.0...300.0).contains(km) {
                day.distanceKmSum += km
                day.hasDistanceKm = true
            }
        case .flights:
            if (0.0...500.0).contains(num) {
                day.elevationMSum += num * 3.05
                day.hasElevationM = true
            }
        case .elevationM:
            if (0.0...12_000.0).contains(num) {
                day.elevationMSum += num
                day.hasElevationM = true
            }
        case .powerW:
            if (10.0...2000.0).contains(num) { day.powerValues.append(num) }
        case .cadenceRpm:
            if (20.0...220.0).contains(num) { day.cadenceValues.append(num) }
        }
    }

    private static func addSleepInterval(
        startEpoch s: Int64,
        endEpoch e: Int64,
        endDayIso: String,
        stageRaw: String,
        sourceName: String,
        into days: inout [String: AppleHealthExportImporter.MutableAppleDay]
    ) {
        let dur = e - s
        guard dur > 0 && dur <= 14 * 3600 else { return }
        let day = mutableDay(iso: endDayIso, in: &days)
        if day.sleepSourceName == nil { day.sleepSourceName = sourceName }
        let span = s...e
        let low = stageRaw
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if low.contains("deep") || low.contains("profund") {
            day.deepIntervals.append(span)
            day.rawStageBlocks.append(SleepStageBlock(id: "sh_d_\(s)", stage: .deep, startEpochSec: s, endEpochSec: e))
        } else if low.contains("rem") || low.contains("mor") {
            day.remIntervals.append(span)
            day.rawStageBlocks.append(SleepStageBlock(id: "sh_r_\(s)", stage: .rem, startEpochSec: s, endEpochSec: e))
        } else if low.contains("core") || low.contains("esencial") || low.contains("central") || low.contains("liger") {
            day.coreIntervals.append(span)
            day.rawStageBlocks.append(SleepStageBlock(id: "sh_c_\(s)", stage: .core, startEpochSec: s, endEpochSec: e))
        } else if low.contains("inbed") || low.contains("in bed") || low.contains("en cama") || low.contains("en la cama") || low.contains("acostad") {
            day.inBedIntervals.append(span)
        } else if low.contains("awake") || low.contains("despiert") || low.contains("vigilia") {
            day.awakeIntervals.append(span)
            day.rawStageBlocks.append(SleepStageBlock(id: "sh_a_\(s)", stage: .awake, startEpochSec: s, endEpochSec: e))
        } else {
            day.asleepAnyIntervals.append(span)
        }
    }

    private static func addWorkout(
        title: String,
        category: String,
        isStrength: Bool,
        start: (date: Date, wall: (iso: String, minuteOfDay: Int)),
        end: (date: Date, wall: (iso: String, minuteOfDay: Int)),
        durationMin: Int,
        kcal: Int,
        avgHr: Int,
        distanceKm: Double? = nil,
        elevationM: Double? = nil,
        into days: inout [String: AppleHealthExportImporter.MutableAppleDay]
    ) {
        let day = mutableDay(iso: start.wall.iso, in: &days)
        let sEp = Int64(start.date.timeIntervalSince1970)
        let eEp = max(Int64(end.date.timeIntervalSince1970), sEp + Int64(durationMin * 60))
        let sTime = String(format: "%02d:%02d", start.wall.minuteOfDay / 60, start.wall.minuteOfDay % 60)
        let eTime = String(format: "%02d:%02d", end.wall.minuteOfDay / 60, end.wall.minuteOfDay % 60)
        let timeRange = "\(sTime) - \(eTime)"
        // Deduplicate exact same workout within the same sync payload
        if day.workouts.contains(where: { $0.title == title && $0.timeRange == timeRange }) {
            return
        }
        if isStrength { day.strengthMinutes += durationMin }
        day.workoutSpans.append(sEp...eEp)
        let ws = WhoopPhysiologyEngine.computeWorkoutStrain(durationMin: durationMin, kcal: kcal, avgHrBpm: avgHr)
        day.workouts.append(
            EffortEventItem(
                id: "sh_wk_\(day.dateIso)_\(day.workouts.count)",
                title: title,
                timeRange: timeRange,
                durationMin: durationMin,
                avgHrBpm: avgHr,
                strainScore: ws.strain21,
                strainPct: ws.strainPct,
                categoryLabel: category,
                kcal: kcal,
                distanceKm: distanceKm,
                elevationM: elevationM,
                dateIso: day.dateIso,
                startEpochSec: sEp
            )
        )
    }

    // MARK: - Flexible Multilingual Date, Number & Delimiter Parsing

    private static let isoWithFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()

    private static let cachedFormatters: [DateFormatter] = {
        let specs: [(String, String)] = [
            ("yyyy-MM-dd HH:mm:ss Z", "en_US_POSIX"),
            ("yyyy-MM-dd HH:mm:ss", "en_US_POSIX"),
            ("yyyy-MM-dd HH:mm", "en_US_POSIX"),
            ("yyyy-MM-dd'T'HH:mm:ss", "en_US_POSIX"),
            ("yyyy-MM-dd", "en_US_POSIX"),
            ("dd/MM/yyyy, H:mm:ss", "es_ES"),
            ("dd/MM/yyyy, H:mm", "es_ES"),
            ("d/M/yy, H:mm:ss", "es_ES"),
            ("d/M/yy, H:mm", "es_ES"),
            ("d/M/yy, h:mm a", "es_ES"),
            ("dd/MM/yyyy, h:mm a", "es_ES"),
            ("d/M/yy H:mm:ss", "es_ES"),
            ("d/M/yy H:mm", "es_ES"),
            ("d/M/yy 'a las' H:mm", "es_ES"),
            ("d/M/yy 'a la' H:mm", "es_ES"),
            ("d/M/yyyy H:mm:ss", "es_ES"),
            ("d/M/yyyy H:mm", "es_ES"),
            ("d/M/yyyy 'a las' H:mm", "es_ES"),
            ("d/M/yyyy 'a la' H:mm", "es_ES"),
            ("dd/MM/yyyy", "es_ES"),
            ("d MMM yyyy, H:mm:ss", "es_ES"),
            ("d MMM yyyy, H:mm", "es_ES"),
            ("d MMM yyyy H:mm:ss", "es_ES"),
            ("d MMM yyyy H:mm", "es_ES"),
            ("d MMM yyyy 'a las' H:mm:ss", "es_ES"),
            ("d MMM yyyy 'a las' H:mm", "es_ES"),
            ("d MMM yyyy 'a la' H:mm:ss", "es_ES"),
            ("d MMM yyyy 'a la' H:mm", "es_ES"),
            ("d MMM yyyy, h:mm a", "en_US_POSIX"),
            ("d MMM yyyy 'a las' h:mm a", "en_US_POSIX"),
            ("d MMM yyyy 'a la' h:mm a", "en_US_POSIX"),
            ("d MMM yyyy, h:mm a", "es_ES"),
            ("d MMM yyyy 'a las' h:mm a", "es_ES"),
            ("d MMM yyyy 'a la' h:mm a", "es_ES"),
            ("d 'de' MMMM 'de' yyyy, H:mm", "es_ES"),
            ("d 'de' MMMM 'de' yyyy 'a las' H:mm", "es_ES"),
            ("d 'de' MMMM 'de' yyyy 'a la' H:mm", "es_ES"),
            ("d 'de' MMM 'de' yyyy, H:mm", "es_ES"),
            ("d 'de' MMM 'de' yyyy 'a las' H:mm", "es_ES"),
            ("d 'de' MMM 'de' yyyy 'a la' H:mm", "es_ES"),
            ("MMM d, yyyy 'at' h:mm a", "en_US"),
            ("MMM d, yyyy, h:mm a", "en_US"),
            ("MMM d, yyyy 'at' H:mm", "en_US"),
            ("d MMM yyyy 'at' HH:mm", "en_GB")
        ]
        return specs.map { fmt, loc in
            let f = DateFormatter()
            f.locale = Locale(identifier: loc)
            f.dateFormat = fmt
            return f
        }
    }()

    private static let cachedDateDetector: NSDataDetector? = {
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
    }()

    private static let isoDayFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func wallClock(for date: Date) -> (iso: String, minuteOfDay: Int) {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (isoDayFmt.string(from: date), (comps.hour ?? 0) * 60 + (comps.minute ?? 0))
    }

    static func parseFlexibleDate(_ raw: String) -> (date: Date, wall: (iso: String, minuteOfDay: Int))? {
        let s = raw
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        // Extract explicit wall-clock prefix if ISO/Apple format ("2026-11-23 08:15:00 +0100" or "2026-11-23T08:15:00+01:00")
        let explicitWall: (iso: String, minuteOfDay: Int)? = {
            let b = Array(s.utf8)
            guard b.count >= 16, b[4] == 0x2D, b[7] == 0x2D, (b[10] == 0x20 || b[10] == 0x54), b[13] == 0x3A else { return nil }
            guard let iso = String(bytes: b[0..<10], encoding: .utf8),
                  let hStr = String(bytes: b[11..<13], encoding: .utf8),
                  let mStr = String(bytes: b[14..<16], encoding: .utf8),
                  let hh = Int(hStr), let mm = Int(mStr),
                  (0...23).contains(hh), (0...59).contains(mm) else { return nil }
            return (iso, hh * 60 + mm)
        }()

        if let d = isoWithFrac.date(from: s) ?? isoPlain.date(from: s) {
            return (d, explicitWall ?? wallClock(for: d))
        }

        // Handle Spanish/English relative words ("hoy, 8:15" / "ayer, 1:05 a. m." / "hoy, 1:15 p. m.")
        let low = s.lowercased()
        if low.hasPrefix("hoy") || low.hasPrefix("ayer") || low.hasPrefix("today") || low.hasPrefix("yesterday") {
            let isYesterday = low.hasPrefix("ayer") || low.hasPrefix("yesterday")
            let isPm = low.contains("p. m") || low.contains("p.m") || low.hasSuffix(" pm") || low.contains(" pm ")
            let isAm = low.contains("a. m") || low.contains("a.m") || low.hasSuffix(" am") || low.contains(" am ")
            let cal = Calendar.current
            let baseDay = cal.date(byAdding: .day, value: isYesterday ? -1 : 0, to: cal.startOfDay(for: Date())) ?? Date()
            if let timeMatch = s.range(of: #"\b([0-2]?\d):([0-5]\d)\b"#, options: .regularExpression) {
                let parts = String(s[timeMatch]).split(separator: ":")
                if parts.count == 2, var hh = Int(parts[0]), let mm = Int(parts[1]) {
                    if isPm && hh < 12 { hh += 12 }
                    if isAm && hh == 12 { hh = 0 }
                    let dt = cal.date(bySettingHour: hh % 24, minute: mm, second: 0, of: baseDay) ?? baseDay
                    return (dt, (isoDayFmt.string(from: dt), (hh % 24) * 60 + mm))
                }
            }
            return (baseDay, wallClock(for: baseDay))
        }

        // Preserve Spanish 12-hour AM/PM markers ("a. m." / "p. m.") BEFORE stripping month abbreviation dots ("nov.")
        let amPmNorm = s
            .replacingOccurrences(of: "a. m.", with: "AM", options: .caseInsensitive)
            .replacingOccurrences(of: "p. m.", with: "PM", options: .caseInsensitive)
            .replacingOccurrences(of: "a.m.", with: "AM", options: .caseInsensitive)
            .replacingOccurrences(of: "p.m.", with: "PM", options: .caseInsensitive)
        let normalizedWithSept = amPmNorm.replacingOccurrences(of: ".", with: "")
        let normalized = normalizedWithSept
            .replacingOccurrences(of: " sept ", with: " sep ", options: .caseInsensitive)
        for fmt in cachedFormatters {
            if let d = fmt.date(from: s) ?? fmt.date(from: amPmNorm) ?? fmt.date(from: normalizedWithSept) ?? fmt.date(from: normalized) {
                return (d, explicitWall ?? wallClock(for: d))
            }
        }

        // Cached NSDataDetector fallback (avoids allocating a detector per sample)
        if let detector = cachedDateDetector,
           let match = detector.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
           let d = match.date {
            return (d, explicitWall ?? wallClock(for: d))
        }
        return nil
    }

    static func parseLocalizedNumber(_ raw: String, allowDotThousands: Bool = false) -> Double? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        // Extract first numeric token (supports "68,4 ms", "1.245", "5.420 pasos", "97.5%", "-0,2 °C")
        guard let range = s.range(of: #"-?\d+(?:[.,]\d+)*"#, options: .regularExpression) else { return nil }
        var token = String(s[range])
        let low = s.lowercased()

        // Both '.' and ',' present -> whichever appears last is the decimal separator
        if token.contains(".") && token.contains(",") {
            if let lastDot = token.lastIndex(of: "."), let lastComma = token.lastIndex(of: ",") {
                if lastComma > lastDot {
                    token = token.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
                } else {
                    token = token.replacingOccurrences(of: ",", with: "")
                }
            }
            return Double(token)
        }

        // Multiple dots (e.g. "1.234.567") -> Spanish thousands separator
        let dotCount = token.filter { $0 == "." }.count
        if dotCount > 1 {
            return Double(token.replacingOccurrences(of: ".", with: ""))
        }

        // Multiple commas (e.g. "1,234,567") -> English thousands separator
        let commaCount = token.filter { $0 == "," }.count
        if commaCount > 1 {
            return Double(token.replacingOccurrences(of: ",", with: ""))
        }

        // Single dot: ONLY treat as thousands separator for whole-integer step counts (e.g. "5.420 pasos")!
        // NEVER multiply 3-decimal Apple Watch samples like "1.245" kcal or "68.412" ms HRV by 1,000!
        if dotCount == 1 {
            let isStepContext = allowDotThousands || low.contains("paso") || low.contains("step")
            if isStepContext && !low.contains("%") {
                let parts = token.split(separator: ".")
                if parts.count == 2 && parts[1].count == 3 && parts[0].count <= 3,
                   let asInt = Int(token.replacingOccurrences(of: ".", with: "")), asInt >= 1000 {
                    return Double(asInt)
                }
            }
            return Double(token)
        }

        // Single comma: always decimal separator in Spanish/European locales (e.g. "68,4", "1,245")
        if commaCount == 1 {
            return Double(token.replacingOccurrences(of: ",", with: "."))
        }

        return Double(token)
    }

    private static func anyToDouble(_ raw: Any?) -> Double? {
        if let d = raw as? Double { return d }
        if let i = raw as? Int { return Double(i) }
        if let n = raw as? NSNumber { return n.doubleValue }
        if let s = raw as? String { return parseLocalizedNumber(s) }
        return nil
    }

    private static func extractStringList(_ raw: Any?) -> [String] {
        if let arr = raw as? [String] { return expandParallelLines(arr) }
        if let arr = raw as? [Any] {
            return expandParallelLines(arr.map { "\($0)" })
        }
        if let s = raw as? String { return expandParallelLines([s]) }
        return []
    }

    private static func splitDelimited(_ line: String) -> [String] {
        let sep: Character = line.contains("|") ? "|" : (line.contains("\t") ? "\t" : (line.contains(";") ? ";" : ","))
        return line.split(separator: sep, omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

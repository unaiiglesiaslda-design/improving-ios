import Foundation

enum WhoopExportImporter {

    static func importURLs(
        _ urls: [URL],
        profile: UserPhysiologyProfile = UserPhysiologyProfile(),
        priorHistory: [String: RealBiometricDaySummary] = [:]
    ) -> ExportParseResult {
        guard !urls.isEmpty else { return .error("No se seleccionó ningún archivo.") }

        var appleUrls: [URL] = []
        var shortcutsUrls: [URL] = []
        var whoopUrls: [URL] = []
        for u in urls {
            let scoped = u.startAccessingSecurityScopedResource()
            defer { if scoped { u.stopAccessingSecurityScopedResource() } }
            if ShortcutsHealthSyncImporter.isShortcutsOrJsonHealthFile(url: u) {
                shortcutsUrls.append(u)
            } else if AppleHealthExportImporter.isAppleHealthFile(url: u) {
                appleUrls.append(u)
            } else {
                whoopUrls.append(u)
            }
        }

        let appleRes = appleUrls.isEmpty ? nil : AppleHealthExportImporter.importURLs(appleUrls, profile: profile)
        var namedCsvs: [(String, Data)] = []

        for url in whoopUrls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let name = url.lastPathComponent
            if name.lowercased().hasSuffix(".zip") {
                if let entries = try? ZipArchiveReader.listEntries(in: url) {
                    for entry in entries where entry.name.lowercased().hasSuffix(".csv") {
                        if let data = try? ZipArchiveReader.readEntryData(entry, from: url) {
                            namedCsvs.append((entry.name, data))
                        }
                    }
                }
            } else if let data = try? Data(contentsOf: url) {
                namedCsvs.append((name, data))
            }
        }

        let whoopRes = namedCsvs.isEmpty ? nil : parseNamedCsvs(namedCsvs)
        var merged: [String: RealBiometricDaySummary] = [:]
        var parsedFiles: [String] = []
        var totalWorkouts = 0
        var lastError: String? = nil

        if let a = appleRes {
            if !a.days.isEmpty {
                merged = mergeDays(existing: merged, imported: a.days)
                parsedFiles.append(contentsOf: a.filesParsed)
                totalWorkouts += a.workoutsCount
            } else if let e = a.errorMessage { lastError = e }
        }
        if let w = whoopRes {
            if !w.days.isEmpty {
                merged = mergeDays(existing: merged, imported: w.days)
                parsedFiles.append(contentsOf: w.filesParsed)
                totalWorkouts += w.workoutsCount
            } else if let e = w.errorMessage { lastError = e }
        }
        let seedPrior = mergeDays(existing: priorHistory, imported: merged)
        for sUrl in shortcutsUrls {
            let sRes = ShortcutsHealthSyncImporter.parseFileURL(sUrl, profile: profile, priorHistory: seedPrior)
            if !sRes.days.isEmpty {
                merged = mergeDays(existing: merged, imported: sRes.days)
                parsedFiles.append(contentsOf: sRes.filesParsed)
                totalWorkouts += sRes.workoutsCount
            } else if let e = sRes.errorMessage {
                lastError = e
            }
        }

        guard !merged.isEmpty else {
            return .error(lastError ?? "No se encontraron datos válidos de Apple Health, Atajos o WHOOP.")
        }

        let sortedKeys = merged.keys.sorted()
        return ExportParseResult(
            days: merged,
            journalByDate: whoopRes?.journalByDate ?? [:],
            filesParsed: Array(Set(parsedFiles)),
            workoutsCount: totalWorkouts,
            journalEntriesCount: whoopRes?.journalEntriesCount ?? 0,
            earliestDateIso: sortedKeys.first,
            latestDateIso: sortedKeys.last,
            errorMessage: nil
        )
    }

    static func parseNamedCsvs(_ csvs: [(String, Data)]) -> ExportParseResult {
        var mutableDays: [String: RealBiometricDaySummary] = [:]
        var journalByDate: [String: [String: JournalCheckState]] = [:]
        var parsedFiles: [String] = []
        var workoutsCount = 0
        var journalCount = 0

        for (rawName, data) in csvs {
            guard var text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { continue }
            if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
            let rows = parseCsv(text)
            guard rows.count >= 2 else { continue }
            let headers = rows[0].map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            let lowerName = rawName.lowercased()
            let joined = headers.joined(separator: "|")

            if lowerName.contains("physiological_cycles") || joined.contains("recovery score") || joined.contains("day strain") {
                ingestCycles(headers: headers, rows: Array(rows.dropFirst()), into: &mutableDays)
                parsedFiles.append((rawName as NSString).lastPathComponent)
            } else if lowerName.contains("sleep") || joined.contains("asleep duration") {
                ingestSleeps(headers: headers, rows: Array(rows.dropFirst()), into: &mutableDays)
                parsedFiles.append((rawName as NSString).lastPathComponent)
            } else if lowerName.contains("workout") || joined.contains("activity name") {
                workoutsCount += ingestWorkouts(headers: headers, rows: Array(rows.dropFirst()), into: &mutableDays)
                parsedFiles.append((rawName as NSString).lastPathComponent)
            } else if lowerName.contains("journal") || joined.contains("question text") {
                journalCount += ingestJournal(headers: headers, rows: Array(rows.dropFirst()), into: &journalByDate)
                parsedFiles.append((rawName as NSString).lastPathComponent)
            }
        }

        guard !mutableDays.isEmpty else {
            return .error("No se reconocieron columnas CSV de WHOOP.")
        }
        let keys = mutableDays.keys.sorted()
        return ExportParseResult(
            days: mutableDays,
            journalByDate: journalByDate,
            filesParsed: Array(Set(parsedFiles)),
            workoutsCount: workoutsCount,
            journalEntriesCount: journalCount,
            earliestDateIso: keys.first,
            latestDateIso: keys.last,
            errorMessage: nil
        )
    }

    static func mergeDays(existing: [String: RealBiometricDaySummary], imported: [String: RealBiometricDaySummary]) -> [String: RealBiometricDaySummary] {
        var merged = imported
        for (iso, cur) in existing {
            if let imp = merged[iso] {
                let impHasFreshActivity = imp.activeKcal != nil || !imp.stressSamples5m.isEmpty || !imp.workouts.isEmpty
                let zones = impHasFreshActivity
                    ? imp.hrZoneMinutes
                    : (cur.hrZoneMinutes.reduce(0, +) > imp.hrZoneMinutes.reduce(0, +) ? cur.hrZoneMinutes : imp.hrZoneMinutes)
                var combinedWorkouts = imp.workouts
                for w in cur.workouts where !combinedWorkouts.contains(where: { $0.title == w.title && $0.timeRange == w.timeRange }) {
                    combinedWorkouts.append(w)
                }
                // Never downgrade true beat-to-beat RMSSD (from exportar.zip / HealthKit live) to Apple Shortcuts SDNN!
                let preserveExistingRmssd: Bool = {
                    guard let curHrv = cur.hrvMs, curHrv > 2.0,
                          let curLbl = cur.hrvMethodLabel, curLbl.hasPrefix("RMSSD") else { return false }
                    guard let impLbl = imp.hrvMethodLabel else { return true }
                    return !impLbl.hasPrefix("RMSSD")
                }()
                merged[iso] = RealBiometricDaySummary(
                    dateIso: iso,
                    liveHrBpm: imp.liveHrBpm ?? cur.liveHrBpm,
                    restingHrBpm: imp.restingHrBpm ?? cur.restingHrBpm,
                    hrvMs: preserveExistingRmssd ? cur.hrvMs : (imp.hrvMs ?? cur.hrvMs),
                    hrvMethodLabel: preserveExistingRmssd ? cur.hrvMethodLabel : (imp.hrvMethodLabel ?? cur.hrvMethodLabel),
                    syncDiagnosticLine: imp.syncDiagnosticLine ?? cur.syncDiagnosticLine,
                    respRateRpm: imp.respRateRpm ?? cur.respRateRpm,
                    wristTempDeltaC: imp.wristTempDeltaC ?? cur.wristTempDeltaC,
                    wristTempAbsoluteC: imp.wristTempAbsoluteC ?? cur.wristTempAbsoluteC,
                    spo2Percent: imp.spo2Percent ?? cur.spo2Percent,
                    asleepMinutes: imp.asleepMinutes ?? cur.asleepMinutes,
                    inBedMinutes: imp.inBedMinutes ?? cur.inBedMinutes,
                    deepMinutes: imp.deepMinutes ?? cur.deepMinutes,
                    remMinutes: imp.remMinutes ?? cur.remMinutes,
                    coreMinutes: imp.coreMinutes ?? cur.coreMinutes,
                    awakeMinutes: imp.awakeMinutes ?? cur.awakeMinutes,
                    sleepPct: imp.sleepPct ?? cur.sleepPct,
                    sleepDebtMinutes: imp.sleepDebtMinutes ?? cur.sleepDebtMinutes,
                    sleepSession: imp.sleepSession ?? cur.sleepSession,
                    strain21: impHasFreshActivity ? imp.strain21 : (imp.strain21 ?? cur.strain21),
                    strainPct: impHasFreshActivity ? imp.strainPct : (imp.strainPct ?? cur.strainPct),
                    recoveryPct: imp.recoveryPct ?? cur.recoveryPct,
                    stressScore: imp.stressScore ?? cur.stressScore,
                    energyBankPercent: imp.energyBankPercent ?? cur.energyBankPercent,
                    stepsCount: imp.stepsCount ?? cur.stepsCount,
                    vo2MaxMlKgMin: imp.vo2MaxMlKgMin ?? cur.vo2MaxMlKgMin,
                    hrRecoveryBpm: imp.hrRecoveryBpm ?? cur.hrRecoveryBpm,
                    glucoseMgDl: imp.glucoseMgDl ?? cur.glucoseMgDl,
                    activeKcal: impHasFreshActivity ? imp.activeKcal : (imp.activeKcal ?? cur.activeKcal),
                    daylightMinutes: imp.daylightMinutes ?? cur.daylightMinutes,
                    sleepNoiseOver50Db: imp.sleepNoiseOver50Db ?? cur.sleepNoiseOver50Db,
                    bodyWeightKg: imp.bodyWeightKg ?? cur.bodyWeightKg,
                    bodyFatPct: imp.bodyFatPct ?? cur.bodyFatPct,
                    leanMassKg: imp.leanMassKg ?? cur.leanMassKg,
                    systolicBp: imp.systolicBp ?? cur.systolicBp,
                    diastolicBp: imp.diastolicBp ?? cur.diastolicBp,
                    hrZoneMinutes: zones,
                    stressSeries24h: !imp.stressSeries24h.isEmpty ? imp.stressSeries24h : cur.stressSeries24h,
                    energySeries24h: !imp.energySeries24h.isEmpty ? imp.energySeries24h : cur.energySeries24h,
                    stressSamples5m: !imp.stressSamples5m.isEmpty ? imp.stressSamples5m : cur.stressSamples5m,
                    energySamples5m: !imp.energySamples5m.isEmpty ? imp.energySamples5m : cur.energySamples5m,
                    strengthMinutes: max(cur.strengthMinutes, imp.strengthMinutes),
                    workouts: combinedWorkouts
                )
            } else {
                merged[iso] = cur
            }
        }
        return merged
    }

    // MARK: - CSV Helpers (Strictly Zero Fabricated Values)

    private static func ingestCycles(headers: [String], rows: [[String]], into days: inout [String: RealBiometricDaySummary]) {
        let dateCol = col(headers, "cycle start time", "fecha", "date")
        let recCol = col(headers, "recovery score", "recuperacion")
        let rhrCol = col(headers, "resting heart rate", "frecuencia cardiaca en reposo")
        let hrvCol = col(headers, "heart rate variability", "vfc", "hrv")
        let strainCol = col(headers, "day strain", "esfuerzo")
        let spo2Col = col(headers, "blood oxygen", "spo2")
        let respCol = col(headers, "respiratory rate", "frecuencia respiratoria")
        let sleepCol = col(headers, "sleep performance", "asleep duration")

        for r in rows {
            guard let iso = extractDateIso(cell(r, dateCol)) else { continue }
            var d = days[iso] ?? RealBiometricDaySummary(dateIso: iso)
            d.recoveryPct = parseNum(cell(r, recCol)).map { Int($0.rounded()) } ?? d.recoveryPct
            d.restingHrBpm = parseNum(cell(r, rhrCol)) ?? d.restingHrBpm
            d.hrvMs = parseNum(cell(r, hrvCol)) ?? d.hrvMs
            if let s = parseNum(cell(r, strainCol)) {
                d.strain21 = s
                d.strainPct = min(max(Int(((s / 21.0) * 100.0).rounded()), 1), 100)
            }
            d.spo2Percent = parseNum(cell(r, spo2Col)) ?? d.spo2Percent
            d.respRateRpm = parseNum(cell(r, respCol)) ?? d.respRateRpm
            if let sl = parseNum(cell(r, sleepCol)) {
                if sl > 100 { d.asleepMinutes = Int(sl.rounded()) } else { d.sleepPct = Int(sl.rounded()) }
            }
            days[iso] = d
        }
    }

    private static func ingestSleeps(headers: [String], rows: [[String]], into days: inout [String: RealBiometricDaySummary]) {
        let dateCol = col(headers, "wake onset", "cycle start time", "fecha")
        let asleepCol = col(headers, "asleep duration")
        let inBedCol = col(headers, "in bed duration")
        let deepCol = col(headers, "deep (sws) duration", "deep")
        let remCol = col(headers, "rem duration", "rem")
        let perfCol = col(headers, "sleep performance")

        for r in rows {
            guard let iso = extractDateIso(cell(r, dateCol)) else { continue }
            var d = days[iso] ?? RealBiometricDaySummary(dateIso: iso)
            d.asleepMinutes = parseNum(cell(r, asleepCol)).map { Int($0.rounded()) } ?? d.asleepMinutes
            d.inBedMinutes = parseNum(cell(r, inBedCol)).map { Int($0.rounded()) } ?? d.inBedMinutes
            d.deepMinutes = parseNum(cell(r, deepCol)).map { Int($0.rounded()) } ?? d.deepMinutes
            d.remMinutes = parseNum(cell(r, remCol)).map { Int($0.rounded()) } ?? d.remMinutes
            d.sleepPct = parseNum(cell(r, perfCol)).map { Int($0.rounded()) } ?? d.sleepPct
            days[iso] = d
        }
    }

    private static func ingestWorkouts(headers: [String], rows: [[String]], into days: inout [String: RealBiometricDaySummary]) -> Int {
        let dateCol = col(headers, "workout start time", "cycle start time", "fecha")
        let nameCol = col(headers, "activity name", "actividad")
        let durCol = col(headers, "duration", "duracion")
        let hrCol = col(headers, "average hr", "hr")
        let strainCol = col(headers, "activity strain", "strain")
        let kcalCol = col(headers, "energy burned", "calories", "kcal")
        var count = 0

        for r in rows {
            guard let iso = extractDateIso(cell(r, dateCol)) else { continue }
            var d = days[iso] ?? RealBiometricDaySummary(dateIso: iso)
            let title = cell(r, nameCol).isEmpty ? "Entrenamiento" : cell(r, nameCol)
            let dur = Int((parseNum(cell(r, durCol)) ?? 0).rounded())
            let avgHr = Int((parseNum(cell(r, hrCol)) ?? 0).rounded())
            let kcal = Int((parseNum(cell(r, kcalCol)) ?? 0).rounded())
            let s21 = parseNum(cell(r, strainCol)) ?? WhoopPhysiologyEngine.computeWorkoutStrain(durationMin: max(dur, 1), kcal: kcal, avgHrBpm: avgHr).strain21
            d.workouts.append(
                EffortEventItem(
                    id: "wh_wk_\(iso)_\(d.workouts.count)",
                    title: title,
                    timeRange: "Sesión",
                    durationMin: max(dur, 1),
                    avgHrBpm: avgHr,
                    strainScore: s21,
                    strainPct: min(max(Int(((s21 / 21.0) * 100.0).rounded()), 2), 99),
                    categoryLabel: "WHOOP",
                    kcal: kcal,
                    dateIso: iso
                )
            )
            days[iso] = d
            count += 1
        }
        return count
    }

    private static func ingestJournal(headers: [String], rows: [[String]], into journal: inout [String: [String: JournalCheckState]]) -> Int {
        let dateCol = col(headers, "cycle start time", "date", "fecha")
        let qCol = col(headers, "question text", "question")
        let ansCol = col(headers, "answered yes", "answer")
        var count = 0
        for r in rows {
            guard let iso = extractDateIso(cell(r, dateCol)) else { continue }
            let q = cell(r, qCol)
            guard !q.isEmpty else { continue }
            let a = cell(r, ansCol).lowercased()
            let state: JournalCheckState = (a == "true" || a == "yes" || a == "si" || a == "sí" || a == "1") ? .yes : .no
            var map = journal[iso] ?? [:]
            map[q] = state
            journal[iso] = map
            count += 1
        }
        return count
    }

    private static func col(_ headers: [String], _ patterns: String...) -> Int {
        for p in patterns {
            if let i = headers.firstIndex(where: { $0.contains(p) }) { return i }
        }
        return -1
    }

    private static func cell(_ r: [String], _ idx: Int) -> String {
        (idx >= 0 && idx < r.count) ? r[idx].trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }

    private static func parseNum(_ raw: String) -> Double? {
        Double(raw.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: ",", with: "."))
    }

    private static func extractDateIso(_ raw: String) -> String? {
        let prefix = String(raw.prefix(10))
        let parts = prefix.split(separator: "-")
        return (parts.count == 3 && parts[0].count == 4) ? prefix : nil
    }

    private static func parseCsv(_ text: String) -> [[String]] {
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let first = lines.first else { return [] }
        let sep: Character = first.filter { $0 == ";" }.count > first.filter { $0 == "," }.count ? ";" : ","
        return lines.map { line in
            var cols: [String] = []
            var cur = ""
            var inQuotes = false
            for ch in line {
                if ch == "\"" { inQuotes.toggle() }
                else if ch == sep && !inQuotes { cols.append(cur); cur = "" }
                else { cur.append(ch) }
            }
            cols.append(cur)
            return cols
        }
    }
}

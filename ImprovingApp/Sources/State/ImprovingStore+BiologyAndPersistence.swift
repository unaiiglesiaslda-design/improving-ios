import Foundation
import Combine
import SwiftUI
import UIKit
import AppleWatchReader
import WhoopBLE
import WhoopProtocol

extension ImprovingStore {
    // MARK: - Home Layout Customization (N2)

    func toggleHomeSection(_ kind: HomeSectionKind) {
        if homeLayout.hiddenSections.contains(kind) {
            homeLayout.hiddenSections.removeAll { $0 == kind }
        } else {
            // Keep at least 1 section visible
            let visibleCount = HomeSectionKind.allCases.filter { !homeLayout.hiddenSections.contains($0) }.count
            if visibleCount > 1 {
                homeLayout.hiddenSections.append(kind)
            }
        }
        persistState()
    }

    func moveHomeSection(_ kind: HomeSectionKind, direction: Int) {
        var order = homeLayout.normalizedOrder
        guard let idx = order.firstIndex(of: kind) else { return }
        let target = idx + direction
        guard order.indices.contains(target) else { return }
        order.swapAt(idx, target)
        homeLayout.sectionOrder = order
        persistState()
    }

    func toggleHealthMonitorMetric(_ kind: HealthMetricKind) {
        if homeLayout.hiddenHealthMetrics.contains(kind) {
            homeLayout.hiddenHealthMetrics.removeAll { $0 == kind }
        } else {
            let visibleCount = HealthMetricKind.allCases.filter { !homeLayout.hiddenHealthMetrics.contains($0) }.count
            if visibleCount > 1 {
                homeLayout.hiddenHealthMetrics.append(kind)
            }
        }
        persistState()
    }

    func resetHomeLayout() {
        homeLayout = HomeLayoutPreferences()
        persistState()
    }

    func toggleHomeCompactMode() {
        homeLayout.isCompactMode.toggle()
        persistState()
    }

    // MARK: - Manual Scale & Blood Pressure Logging + Lab Reports / Biomarkers (P2 & N6)

    func logManualScaleReading(
        date: Date = Date(),
        weightKg: Double?,
        bodyFatPct: Double?,
        leanMassKg: Double?,
        systolicBp: Int?,
        diastolicBp: Int?
    ) {
        let iso = isoFormatter.string(from: date)
        var d = activeHistory[iso] ?? RealBiometricDaySummary(dateIso: iso)
        if let w = weightKg, w > 20, w < 300 {
            d.bodyWeightKg = AppleHealthExportImporter.round1(w)
            userProfile.weightKg = AppleHealthExportImporter.round1(w)
        }
        if let f = bodyFatPct, f >= 2, f <= 70 {
            d.bodyFatPct = AppleHealthExportImporter.round1(f)
            userProfile.bodyFatPct = AppleHealthExportImporter.round1(f)
        }
        if let l = leanMassKg, l > 15, l < 220 {
            d.leanMassKg = AppleHealthExportImporter.round1(l)
        } else if let w = d.bodyWeightKg, let f = d.bodyFatPct {
            d.leanMassKg = AppleHealthExportImporter.round1(w * (1.0 - f / 100.0))
        }
        if let sys = systolicBp, let dia = diastolicBp, sys >= 70, sys <= 240, dia >= 40, dia <= 150 {
            d.systolicBp = sys
            d.diastolicBp = dia
        }

        realHistory[iso] = d
        if !hasImportedOrPairedRealData {
            simulatedHistory[iso] = d
        }
        dataRevision += 1
        persistState()
    }

    func bodyMetricSeries(for kind: BodyCompositionMetricKind, spanDays: Int, windowPageOffset: Int) -> MetricWindowSeries {
        customWindowSeries(spanDays: spanDays, windowPageOffset: windowPageOffset) { day in
            switch kind {
            case .weight: return day.bodyWeightKg
            case .bodyFat: return day.bodyFatPct
            case .leanMass: return day.leanMassKg
            case .bloodPressure: return day.systolicBp.map { Double($0) }
            }
        }
    }

    func bodyMetricHistoryEntries(for kind: BodyCompositionMetricKind, limit: Int = 40) -> [(dateIso: String, primary: String, secondary: String?)] {
        let sorted = activeHistory.keys.sorted(by: >)
        var out: [(String, String, String?)] = []
        for iso in sorted {
            guard let d = activeHistory[iso] else { continue }
            switch kind {
            case .weight:
                if let v = d.bodyWeightKg {
                    out.append((iso, String(format: "%.1f kg", locale: Locale(identifier: "es_ES"), v), d.bodyFatPct.map { String(format: "Grasa %.1f%%", locale: Locale(identifier: "es_ES"), $0) }))
                }
            case .bodyFat:
                if let v = d.bodyFatPct {
                    out.append((iso, String(format: "%.1f %%", locale: Locale(identifier: "es_ES"), v), d.bodyWeightKg.map { String(format: "Peso %.1f kg", locale: Locale(identifier: "es_ES"), $0) }))
                }
            case .leanMass:
                if let v = d.leanMassKg {
                    out.append((iso, String(format: "%.1f kg", locale: Locale(identifier: "es_ES"), v), d.bodyWeightKg.map { String(format: "Peso %.1f kg", locale: Locale(identifier: "es_ES"), $0) }))
                }
            case .bloodPressure:
                if let sys = d.systolicBp, let dia = d.diastolicBp {
                    let tone = (sys < 125 && dia < 82) ? "Óptima" : ((sys < 135 && dia < 88) ? "Normal" : "Elevada")
                    out.append((iso, "\(sys)/\(dia) mmHg", tone))
                }
            }
            if out.count >= limit { break }
        }
        return out
    }

    /// Unified 30-day Biological Age snapshot (Wearables + Body Composition + Blood Test Biomarkers).
    func biologicalAgeSnapshot() -> (
        eval: BiologicalAgeEvaluation,
        hasData: Bool,
        meanRhr: Double?,
        meanHrv: Double?,
        meanSleep: Double?,
        meanSteps: Int?,
        vo2Val: Double?
    ) {
        ensureDerivedCacheFresh()
        if let hit = cachedBioAge {
            return hit
        }
        let recent30 = trailingCalendarSummaries(days: 30)
        let rhrVals = recent30.compactMap { $0.summary?.restingHrBpm }
        let hrvVals = recent30.compactMap { $0.summary?.hrvMs }
        let sleepVals = recent30.compactMap { $0.summary?.asleepMinutes.map { Double($0) / 60.0 } }
        let stepsVals = recent30.compactMap { $0.summary?.stepsCount }
        let vo2Val = latestVo2Max
        let biomarkers = latestBiomarkersByName

        let meanRhr = rhrVals.isEmpty ? nil : (rhrVals.reduce(0, +) / Double(rhrVals.count))
        let meanHrv = hrvVals.isEmpty ? nil : (hrvVals.reduce(0, +) / Double(hrvVals.count))
        let meanSleep = sleepVals.isEmpty ? nil : (sleepVals.reduce(0, +) / Double(sleepVals.count))
        let meanSteps = stepsVals.isEmpty ? nil : (stepsVals.reduce(0, +) / stepsVals.count)

        let hasData = meanRhr != nil || meanHrv != nil || meanSleep != nil || meanSteps != nil || vo2Val != nil || !biomarkers.isEmpty
        let zoneProg = longevityZoneProgress
        let hasZoneData = (zoneProg.weeklyZone1To3Minutes + zoneProg.weeklyZone4To5Minutes) > 0
        let hasStrengthData = zoneProg.weeklyStrengthMinutes > 0
        let eval = WhoopPhysiologyEngine.computeBiologicalAge(
            profile: userProfile,
            meanRhr: meanRhr,
            meanHrv: meanHrv,
            meanSleepHours: meanSleep,
            meanSteps: meanSteps,
            vo2Max: vo2Val,
            latestWeightKg: latestBodyWeightKg,
            latestBodyFatPct: latestBodyFatPct,
            labBiomarkers: biomarkers,
            sleepConsistencyPct: sleepConsistencyPct,
            weeklyZone1To3Min: hasZoneData ? zoneProg.weeklyZone1To3Minutes : nil,
            weeklyZone4To5Min: hasZoneData ? zoneProg.weeklyZone4To5Minutes : nil,
            weeklyStrengthMin: hasStrengthData ? zoneProg.weeklyStrengthMinutes : nil
        )
        let res = (eval, hasData, meanRhr, meanHrv, meanSleep, meanSteps, vo2Val)
        cachedBioAge = res
        return res
    }

    var longevityZoneProgress: LongevityZoneProgressSnapshot {
        let recent7 = trailingCalendarSummaries(days: 7)
        var z13 = 0
        var z45 = 0
        var strengthSessions = 0
        var strengthMin = 0
        for item in recent7 {
            guard let d = item.summary else { continue }
            let zm = d.hrZoneMinutes
            z13 += (zm.count > 0 ? zm[0] : 0) + (zm.count > 1 ? zm[1] : 0) + (zm.count > 2 ? zm[2] : 0)
            z45 += (zm.count > 3 ? zm[3] : 0) + (zm.count > 4 ? zm[4] : 0)
            let sWorkouts = d.workouts.filter { $0.categoryLabel == "Fuerza" || ($0.totalSets ?? 0) > 0 }
            strengthSessions += sWorkouts.count
            strengthMin += d.strengthMinutes ?? sWorkouts.reduce(0) { $0 + $1.durationMin }
        }
        let p1 = min(Double(z13) / 150.0, 1.0)
        let p2 = min(Double(z45) / 25.0, 1.0)
        let p3 = min(Double(strengthSessions) / 3.0, 1.0)
        let overall = Int(((p1 * 0.45 + p2 * 0.25 + p3 * 0.30) * 100.0).rounded())
        return LongevityZoneProgressSnapshot(
            weeklyZone1To3Minutes: z13,
            targetZone1To3Minutes: 150,
            weeklyZone4To5Minutes: z45,
            targetZone4To5Minutes: 25,
            weeklyStrengthSessions: strengthSessions,
            targetStrengthSessions: 3,
            weeklyStrengthMinutes: strengthMin,
            overallCompliancePct: overall
        )
    }

    var circadianAndLatencySnapshot: CircadianAndLatencySnapshot {
        let recent14 = trailingCalendarSummaries(days: 14).compactMap { $0.summary?.sleepSession }
        return WhoopPhysiologyEngine.computeCircadianAndLatency(
            currentDay: currentDaySummary,
            recentSessions: recent14
        )
    }

    /// WHOOP Healthspan-style Pace of Aging (0.3x ... 2.5x) comparing recent 30d vs prior 30d (days 31...60).
    func paceOfAgingSnapshot() -> PaceOfAgingSnapshot? {
        let cur = biologicalAgeSnapshot()
        guard cur.hasData else { return nil }
        let last60 = trailingCalendarSummaries(days: 60)
        let prior30 = Array(last60.prefix(30))
        let pRhr = prior30.compactMap { $0.summary?.restingHrBpm }
        let pHrv = prior30.compactMap { $0.summary?.hrvMs }
        let pSleep = prior30.compactMap { $0.summary?.asleepMinutes.map { Double($0) / 60.0 } }
        let pSteps = prior30.compactMap { $0.summary?.stepsCount }
        let hasPrior = (pRhr.count + pHrv.count + pSleep.count + pSteps.count) >= 6

        let priorEval: BiologicalAgeEvaluation? = hasPrior
            ? WhoopPhysiologyEngine.computeBiologicalAge(
                profile: userProfile,
                meanRhr: pRhr.isEmpty ? nil : pRhr.reduce(0, +) / Double(pRhr.count),
                meanHrv: pHrv.isEmpty ? nil : pHrv.reduce(0, +) / Double(pHrv.count),
                meanSleepHours: pSleep.isEmpty ? nil : pSleep.reduce(0, +) / Double(pSleep.count),
                meanSteps: pSteps.isEmpty ? nil : pSteps.reduce(0, +) / pSteps.count,
                vo2Max: cur.vo2Val,
                latestWeightKg: latestBodyWeightKg,
                latestBodyFatPct: latestBodyFatPct,
                labBiomarkers: latestBiomarkersByName
            )
            : nil

        return WhoopPhysiologyEngine.computePaceOfAging(currentEval: cur.eval, priorEval: priorEval)
    }

    var latestBiomarkersByName: [LabBiomarkerItem] {
        let sortedReports = labReports.sorted { $0.dateIso > $1.dateIso }
        var seen = Set<String>()
        var result: [LabBiomarkerItem] = []
        for rep in sortedReports {
            for b in rep.biomarkers {
                let key = b.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
                if seen.insert(key).inserted {
                    result.append(b)
                }
            }
        }
        return result
    }

    func saveLabReport(_ report: LabReportRecord) {
        if let idx = labReports.firstIndex(where: { $0.id == report.id }) {
            labReports[idx] = report
        } else {
            labReports.insert(report, at: 0)
        }
        labReports.sort { $0.dateIso > $1.dateIso }
        dataRevision += 1
        persistState()
    }

    func deleteLabReport(id: String) {
        labReports.removeAll { $0.id == id }
        dataRevision += 1
        persistState()
    }

    func addManualBiomarker(_ item: LabBiomarkerItem, dateIso: String? = nil) {
        let iso = dateIso ?? isoFormatter.string(from: Date())
        if let idx = labReports.firstIndex(where: { $0.dateIso == iso && $0.title == "Biomarcadores manuales" }) {
            labReports[idx].biomarkers.insert(item, at: 0)
        } else {
            let rep = LabReportRecord(
                id: UUID().uuidString,
                dateIso: iso,
                title: "Biomarcadores manuales",
                sourceLabel: "Registro manual",
                summary: "Registro manual de biomarcadores clínicos.",
                biomarkers: [item]
            )
            labReports.insert(rep, at: 0)
        }
        labReports.sort { $0.dateIso > $1.dateIso }
        dataRevision += 1
        persistState()
    }

    // MARK: - Weekly Review Computation & AI Analysis (N5)

    func computeWeeklyReview(anchorDate: Date? = nil) -> WeeklyReviewReport {
        ensureDerivedCacheFresh()
        let cal = Calendar.current
        let anchor = cal.startOfDay(for: anchorDate ?? selectedDate)
        let anchorIso = isoFormatter.string(from: anchor)
        if let hit = cachedWeeklyReviews[anchorIso] {
            return hit
        }
        let curDates: [Date] = (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: anchor) }
        let prevDates: [Date] = (7..<14).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: anchor) }

        let curIsos = curDates.map { isoFormatter.string(from: $0) }
        let prevIsos = prevDates.map { isoFormatter.string(from: $0) }
        let curDays = curIsos.compactMap { activeHistory[$0] }
        let prevDays = prevIsos.compactMap { activeHistory[$0] }

        func avgInt(_ vals: [Int]) -> Int? {
            guard !vals.isEmpty else { return nil }
            return Int((Double(vals.reduce(0, +)) / Double(vals.count)).rounded())
        }
        func avgDbl(_ vals: [Double]) -> Double? {
            guard !vals.isEmpty else { return nil }
            return vals.reduce(0, +) / Double(vals.count)
        }

        let avgRec = avgInt(curDays.compactMap(\.recoveryPct))
        let prevRec = avgInt(prevDays.compactMap(\.recoveryPct))
        let avgHrv = avgDbl(curDays.compactMap(\.hrvMs))
        let prevHrv = avgDbl(prevDays.compactMap(\.hrvMs))
        let avgRhr = avgDbl(curDays.compactMap(\.restingHrBpm))
        let prevRhr = avgDbl(prevDays.compactMap(\.restingHrBpm))
        let avgSleepMin = avgInt(curDays.compactMap(\.asleepMinutes).filter { $0 > 0 })
        let prevSleepMin = avgInt(prevDays.compactMap(\.asleepMinutes).filter { $0 > 0 })
        let avgSleepPct = avgInt(curDays.compactMap(\.sleepPct))
        let sleepDebt = curDays.last?.sleepDebtMinutes ?? curDays.compactMap(\.sleepDebtMinutes).last ?? 0
        let avgStrain = avgInt(curDays.compactMap(\.strainPct))
        let prevStrain = avgInt(prevDays.compactMap(\.strainPct))

        let curWorkouts = curDays.flatMap(\.workouts)
        let prevWorkouts = prevDays.flatMap(\.workouts)
        let totalWkMin = curWorkouts.reduce(0) { $0 + $1.durationMin }

        let cardioAnalysis = trainingLoadAnalysis(tab: .cardio, spanDays: 14, windowPageOffset: 0)

        let curNutScores = curIsos.compactMap { nutritionScore(for: $0) }
        let prevNutScores = prevIsos.compactMap { nutritionScore(for: $0) }
        let avgNut = avgInt(curNutScores)
        let prevNut = avgInt(prevNutScores)

        let curNetVals = curIsos.compactMap { iso -> Int? in
            let meals = mealsByDate[iso] ?? []
            guard !meals.isEmpty else { return nil }
            return netEnergyKcal(for: iso).net
        }
        let avgNet = avgInt(curNetVals)
        let avgSteps = avgInt(curDays.compactMap(\.stepsCount).filter { $0 > 0 })

        // Top checked habits during this 7-day window
        var habitCounts: [String: Int] = [:]
        for iso in curIsos {
            for (hid, st) in (journalCheckinsByDate[iso] ?? [:]) where st == .yes {
                habitCounts[hid, default: 0] += 1
            }
        }
        let catalogMap = Dictionary(uniqueKeysWithValues: allCatalogAndCustomEntries.map { ($0.id, ($0.emoji, $0.title)) })
        let topHabits: [(emoji: String, title: String, count: Int)] = habitCounts
            .sorted { $0.value > $1.value }
            .prefix(4)
            .compactMap { k, v in
                guard let meta = catalogMap[k] else { return nil }
                return (meta.0, meta.1, v)
            }

        let startLbl = curDates.first.map { AppFormatters.dMMM.string(from: $0).replacingOccurrences(of: ".", with: "") } ?? ""
        let endLbl = curDates.last.map { AppFormatters.dMMM.string(from: $0).replacingOccurrences(of: ".", with: "") } ?? ""
        let weekKey = "\(curIsos.first ?? "")_\(curIsos.last ?? "")_r\(dataRevision)"

        let report = WeeklyReviewReport(
            weekKey: weekKey,
            dateRangeLabel: "\(startLbl) – \(endLbl)",
            daysWithData: curDays.count,
            avgRecovery: avgRec,
            recoveryDelta: (avgRec != nil && prevRec != nil) ? (avgRec! - prevRec!) : nil,
            avgHrv: avgHrv,
            hrvDelta: (avgHrv != nil && prevHrv != nil) ? (avgHrv! - prevHrv!) : nil,
            avgRhr: avgRhr,
            rhrDelta: (avgRhr != nil && prevRhr != nil) ? (avgRhr! - prevRhr!) : nil,
            avgSleepMinutes: avgSleepMin,
            sleepMinutesDelta: (avgSleepMin != nil && prevSleepMin != nil) ? (avgSleepMin! - prevSleepMin!) : nil,
            avgSleepPct: avgSleepPct,
            sleepDebtMinutes: sleepDebt,
            avgStrainPct: avgStrain,
            strainDelta: (avgStrain != nil && prevStrain != nil) ? (avgStrain! - prevStrain!) : nil,
            workoutsCount: curWorkouts.count,
            totalWorkoutMinutes: totalWkMin,
            workoutsDelta: curWorkouts.count - prevWorkouts.count,
            cardioLoadCurrent: cardioAnalysis.currentLoad,
            cardioLoadState: cardioAnalysis.currentState,
            avgNutritionScore: avgNut,
            nutritionScoreDelta: (avgNut != nil && prevNut != nil) ? (avgNut! - prevNut!) : nil,
            avgNetEnergyKcal: avgNet,
            avgSteps: avgSteps,
            topHabits: topHabits
        )
        cachedWeeklyReviews[anchorIso] = report
        return report
    }

    func generateWeeklyReviewAI(report: WeeklyReviewReport, force: Bool = false) {
        if !force, weeklyAiInsightsCache[report.weekKey] != nil { return }
        guard !isGeneratingWeeklyReviewAI else { return }
        isGeneratingWeeklyReviewAI = true
        let key = geminiApiKey
        let model = selectedGeminiModel
        let allowCloud = cloudAIEnabled
        let allowKeyless = allowKeylessAIFallback
        let uName = redactPIIFromAI ? "Usuario" : userProfile.displayFirstName

        Task { [weak self] in
            let insight = await GeminiCoachService.shared.generateWeeklyReviewInsight(
                report: report,
                userName: uName,
                apiKey: key,
                selectedModel: model,
                allowCloudAI: allowCloud,
                allowKeylessFallback: allowKeyless
            )
            await MainActor.run {
                guard let self else { return }
                self.isGeneratingWeeklyReviewAI = false
                self.weeklyAiInsightsCache[report.weekKey] = insight
                self.persistState()
            }
        }
    }

    // MARK: - WidgetKit Shared Snapshot Bridge (N7)

    func publishWidgetSnapshot(triggerReload: Bool = true, forceReload: Bool = false) {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let todayIso = isoFormatter.string(from: todayStart)
        let yesterdayIso = cal.date(byAdding: .day, value: -1, to: todayStart).map { isoFormatter.string(from: $0) } ?? ""
        let goals = effectiveNutritionGoals

        // Strict preview-mode isolation: NEVER push fabricated `simulatedHistory` numbers onto the user's Home/Lock Screen widgets!
        let hasReal = hasImportedOrPairedRealData || !realHistory.isEmpty
        let targetDay: RealBiometricDaySummary? = hasReal
            ? (realHistory[todayIso] ?? realHistory.keys.max().flatMap { realHistory[$0] })
            : nil
        let targetIso = targetDay?.dateIso ?? todayIso
        let dateLbl: String = {
            if !hasReal { return "Sin sincronizar" }
            if targetIso == todayIso { return "Hoy" }
            if targetIso == yesterdayIso { return "Ayer" }
            if let dt = AppFormatters.parseIsoDay(targetIso) {
                return AppFormatters.dMMM.string(from: dt).replacingOccurrences(of: ".", with: "")
            }
            return "Hoy"
        }()

        let nutTotals = hasReal ? nutritionDayTotals(for: todayIso) : (kcal: 0, fatG: 0.0, carbsG: 0.0, proteinG: 0.0, score: nil as Int?, mealCount: 0)
        let sleepDur: String = {
            if let m = targetDay?.asleepMinutes, m > 0 {
                return "\(m / 60)h \(String(format: "%02d", m % 60))m"
            }
            return "--"
        }()

        let optRange = personalizedEffortTarget(for: targetIso).range
        let optLo = Int((optRange.lowerBound * 100.0).rounded())
        let optHi = Int((optRange.upperBound * 100.0).rounded())

        let snap = ImprovingWidgetSnapshot(
            dateIso: targetIso,
            dateLabel: dateLbl,
            strainPct: targetDay?.strainPct ?? 0,
            recoveryPct: targetDay?.recoveryPct,
            sleepPct: targetDay?.sleepPct,
            energyPct: targetDay?.energyBankPercent,
            stressScore: targetDay?.stressSamples5m.last.map { Int($0.value.rounded()) } ?? targetDay?.stressScore,
            hrvMs: targetDay?.hrvMs,
            restingHrBpm: targetDay?.restingHrBpm,
            sleepDurationText: sleepDur,
            nutritionScore: nutTotals.score,
            caloriesToday: nutTotals.kcal,
            caloriesGoal: goals.kcal,
            proteinG: Int(nutTotals.proteinG.rounded()),
            carbsG: Int(nutTotals.carbsG.rounded()),
            fatG: Int(nutTotals.fatG.rounded()),
            stepsCount: targetDay?.stepsCount,
            optimalStrainLowPct: optLo,
            optimalStrainHighPct: optHi,
            updatedAt: Date()
        )
        WidgetSnapshotStore.save(snap, triggerReload: triggerReload, forceReload: forceReload)
    }

    func updateGeminiConfig(apiKey: String, model: String) {
        geminiApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        selectedGeminiModel = model
        // Store API key securely in Keychain (never in plaintext JSON!)
        if customPersistenceURL == nil {
            KeychainSecretStore.saveString(geminiApiKey, account: Self.geminiKeychainAccount)
        }
        dataRevision += 1
        persistState()
    }

    func updateAIPrivacySettings(cloudAIEnabled: Bool, allowKeylessFallback: Bool, redactPII: Bool) {
        self.cloudAIEnabled = cloudAIEnabled
        self.allowKeylessAIFallback = allowKeylessFallback
        self.redactPIIFromAI = redactPII
        sectionCoachingCache.removeAll()
        sectionCoachingTimestamps.removeAll()
        dataRevision += 1
        persistState()
    }

    func exportFullBackupURL() throws -> URL {
        let snap = buildPersistedSnapshot()
        let data = try JSONEncoder().encode(snap)
        return try AppBackupService.createBackupFile(snapshotData: data)
    }

    func restoreFullBackup(from url: URL) -> Result<String, Error> {
        do {
            let unpacked = try AppBackupService.unpackBackupFile(at: url)
            let snap = try JSONDecoder().decode(PersistedSnapshot.self, from: unpacked.snapshotData)
            applyPersistedSnapshot(snap)
            persistState(immediate: true)
            refreshSmartNotificationSchedules(promptPermission: false)
            publishWidgetSnapshot(triggerReload: true, forceReload: true)
            let photoCount = unpacked.restoredMealPhotos + unpacked.restoredAvatarPhotos
            let daysCount = realHistory.count
            return .success("Copia restaurada: \(daysCount) días, \(mealsByDate.values.reduce(0) { $0 + $1.count }) comidas, \(labReports.count) analíticas y \(photoCount) fotos.")
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Async Debounced Background Persistence (Schema-Versioned + .bak Anti-Corruption + File Protection!)

    func buildPersistedSnapshot() -> PersistedSnapshot {
        let orderedSigs = processedAutoSyncSignaturesOrder.isEmpty
            ? Array(processedAutoSyncSignatures.prefix(80))
            : Array(processedAutoSyncSignaturesOrder.suffix(80))
        return PersistedSnapshot(
            schemaVersion: Self.currentSchemaVersion,
            userProfile: userProfile,
            isDarkMode: BevelColors.isDarkMode,
            hasImportedOrPairedRealData: hasImportedOrPairedRealData,
            realHistory: realHistory,
            journalCheckins: journalCheckinsByDate,
            journalMoodByDate: journalMoodByDate,
            // Never write API key to plaintext JSON when Keychain is active (isolated custom URL tests keep round-trip intact)
            geminiApiKey: customPersistenceURL == nil ? "" : geminiApiKey,
            selectedGeminiModel: selectedGeminiModel,
            mealsByDate: mealsByDate,
            hydrationGlassesByDate: hydrationGlassesByDate,
            smartAlarmEnabled: smartAlarmEnabled,
            wakeOffsetMinutes: wakeOffsetMinutes,
            sleepGoalPct: sleepGoalPct,
            visibleTabs: Array(visibleTabs),
            sectionCoachingCache: sectionCoachingCache,
            processedAutoSyncSignatures: orderedSigs,
            lastAutoSyncStatus: autoSyncStatusText,
            shortcutSyncName: shortcutSyncName,
            autoRunShortcutOnOpen: autoRunShortcutOnOpen,
            workoutRoutines: workoutRoutines,
            strengthLogs: strengthLogs,
            manualNutrientsByDate: manualNutrientsByDate,
            hiddenJournalHabitIds: Array(hiddenJournalHabitIds),
            customJournalHabits: customJournalHabits,
            journalNotesByDate: journalNotesByDate,
            journalEventTimesByDate: journalEventTimesByDate,
            notificationSettings: notificationSettings,
            savedFoodsLibrary: savedFoodsLibrary,
            customNutritionGoals: customNutritionGoals,
            homeLayout: homeLayout,
            coachThreads: Array(coachThreads.prefix(30)),
            activeCoachThreadId: activeCoachThreadId,
            labReports: labReports,
            weeklyAiInsightsCache: weeklyAiInsightsCache,
            cloudAIEnabled: cloudAIEnabled,
            allowKeylessAIFallback: allowKeylessAIFallback,
            redactPIIFromAI: redactPIIFromAI,
            healthKitPreviouslyAuthorized: healthKitPreviouslyAuthorized,
            napMinutesByDate: napMinutesByDate,
            journalQuantitiesByDate: journalQuantitiesByDate,
            coachMemoryNotes: coachMemoryNotes,
            globalGoalMode: globalGoalMode,
            nutritionRecipes: nutritionRecipes,
            cycleTrackingSettings: cycleTrackingSettings,
            autoDeloadModeActive: autoDeloadModeActive,
            weatherCityName: weatherCityName,
            weatherSnapshot: weatherSnapshot,
            coachPersonalityTone: coachPersonalityTone,
            coachDetailLevel: coachDetailLevel,
            archivedAiInsights: Array(archivedAiInsights.prefix(120)),
            dynamicStrainNutritionEnabled: dynamicStrainNutritionEnabled
        )
    }

    // MARK: - Partitioned Domain Persistence (Core + Biometrics + Coach Threads + Rolling .bak + File Protection!)

    static func companionURL(for primaryURL: URL, suffix: String) -> URL {
        let baseName = primaryURL.deletingPathExtension().lastPathComponent
        return primaryURL.deletingLastPathComponent().appendingPathComponent("\(baseName)_\(suffix).json")
    }

    static func writeAtomicProtected(_ data: Data, to url: URL) {
        let fm = FileManager.default
        let bakURL = url.appendingPathExtension("bak")
        if fm.fileExists(atPath: url.path),
           let existing = try? Data(contentsOf: url),
           existing.count > 2 {
            try? existing.write(to: bakURL, options: [.atomic, .completeFileProtection])
        }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    static func loadProtectedOrBackup<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        if let d = try? Data(contentsOf: url), let v = try? JSONDecoder().decode(T.self, from: d) {
            return v
        }
        let bak = url.appendingPathExtension("bak")
        if let d = try? Data(contentsOf: bak), let v = try? JSONDecoder().decode(T.self, from: d) {
            return v
        }
        return nil
    }

    static func writeProtectedSnapshot(_ snap: PersistedSnapshot, to targetURL: URL) {
        let enc = JSONEncoder()
        // Partition heavy high-churn domains into dedicated sibling files while keeping core JSON small & fast!
        let bioURL = companionURL(for: targetURL, suffix: "biometrics")
        let coachURL = companionURL(for: targetURL, suffix: "coach")
        var coreSnap = snap
        if let bioData = try? enc.encode(snap.realHistory) {
            writeAtomicProtected(bioData, to: bioURL)
            coreSnap.realHistory = [:] // Stored in dedicated partitioned biometrics file
        }
        if let threads = snap.coachThreads, let coachData = try? enc.encode(threads) {
            writeAtomicProtected(coachData, to: coachURL)
            coreSnap.coachThreads = nil // Stored in dedicated partitioned coach file
        }
        guard let coreData = try? enc.encode(coreSnap) else { return }
        writeAtomicProtected(coreData, to: targetURL)
    }

    func persistState(immediate: Bool = false) {
        let snap = buildPersistedSnapshot()
        let targetURL = persistenceURL
        publishWidgetSnapshot(triggerReload: true)

        pendingPersistWorkItem?.cancel()
        if immediate {
            pendingPersistWorkItem = nil
            persistenceQueue.sync {
                Self.writeProtectedSnapshot(snap, to: targetURL)
            }
            return
        }

        let work = DispatchWorkItem {
            Self.writeProtectedSnapshot(snap, to: targetURL)
        }
        pendingPersistWorkItem = work
        persistenceQueue.asyncAfter(deadline: .now() + 0.28, execute: work)
    }

    func flushPersistenceNow() {
        persistState(immediate: true)
    }

    func loadPersistedState() {
        let fm = FileManager.default
        let primaryURL = persistenceURL
        let bakURL = primaryURL.appendingPathExtension("bak")

        // Load API key from Keychain first
        if customPersistenceURL == nil, let kcKey = KeychainSecretStore.loadString(account: Self.geminiKeychainAccount), !kcKey.isEmpty {
            geminiApiKey = kcKey
        }

        if fm.fileExists(atPath: primaryURL.path) {
            if let data = try? Data(contentsOf: primaryURL),
               var snap = try? JSONDecoder().decode(PersistedSnapshot.self, from: data) {
                hydratePartitionedDomains(into: &snap, primaryURL: primaryURL)
                applyPersistedSnapshot(snap)
                return
            }
            // Primary JSON is corrupted! Quarantine it instead of silently overwriting with empty state!
            let corruptURL = primaryURL.deletingLastPathComponent()
                .appendingPathComponent("improving_store_corrupt_\(Int(Date().timeIntervalSince1970)).json")
            try? fm.copyItem(at: primaryURL, to: corruptURL)

            if let bakData = try? Data(contentsOf: bakURL),
               var bakSnap = try? JSONDecoder().decode(PersistedSnapshot.self, from: bakData) {
                hydratePartitionedDomains(into: &bakSnap, primaryURL: primaryURL)
                applyPersistedSnapshot(bakSnap)
                persistenceRecoveryNotice = "Se detectó un archivo dañado y se restauró automáticamente tu última copia de seguridad local (.bak)."
                return
            }
            persistenceRecoveryNotice = "No se pudo leer el archivo de datos local; se guardó una copia en cuarentena para evitar pérdida definitiva."
        } else if let bakData = try? Data(contentsOf: bakURL),
                  var bakSnap = try? JSONDecoder().decode(PersistedSnapshot.self, from: bakData) {
            hydratePartitionedDomains(into: &bakSnap, primaryURL: primaryURL)
            applyPersistedSnapshot(bakSnap)
            persistenceRecoveryNotice = "Se restauró tu historial desde la copia de seguridad local (.bak)."
        }
    }

    func hydratePartitionedDomains(into snap: inout PersistedSnapshot, primaryURL: URL) {
        let bioURL = Self.companionURL(for: primaryURL, suffix: "biometrics")
        if let partBio = Self.loadProtectedOrBackup([String: RealBiometricDaySummary].self, from: bioURL), !partBio.isEmpty {
            // Merge partitioned biometrics on top of any legacy embedded entries
            for (k, v) in partBio { snap.realHistory[k] = v }
        }
        let coachURL = Self.companionURL(for: primaryURL, suffix: "coach")
        if let partCoach = Self.loadProtectedOrBackup([CoachChatThread].self, from: coachURL), !partCoach.isEmpty {
            snap.coachThreads = partCoach
        }
    }

    func applyPersistedSnapshot(_ snap: PersistedSnapshot) {
        userProfile = snap.userProfile
        // One-time migration: older builds bypassed onboarding (`profileSetupVersion == 0`), so present the
        // high-craft motion graphics onboarding & profile setup once while preserving 100% of stored realHistory!
        if userProfile.profileSetupVersion < 2 {
            userProfile.onboardingCompleted = false
        }
        BevelColors.isDarkMode = snap.isDarkMode
        hasImportedOrPairedRealData = snap.hasImportedOrPairedRealData
        realHistory = snap.realHistory
        journalCheckinsByDate = snap.journalCheckins
        journalMoodByDate = snap.journalMoodByDate

        // Migrate legacy plaintext API key from JSON -> Keychain cleanly once
        let legacyKey = snap.geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if customPersistenceURL == nil {
            if geminiApiKey.isEmpty && !legacyKey.isEmpty {
                geminiApiKey = legacyKey
                KeychainSecretStore.saveString(legacyKey, account: Self.geminiKeychainAccount)
            }
        } else if !legacyKey.isEmpty {
            geminiApiKey = legacyKey
        }
        if let cloudOn = snap.cloudAIEnabled { cloudAIEnabled = cloudOn }
        if let keylessOn = snap.allowKeylessAIFallback { allowKeylessAIFallback = keylessOn }
        if let redactOn = snap.redactPIIFromAI { redactPIIFromAI = redactOn }
        if let hkPrev = snap.healthKitPreviouslyAuthorized { healthKitPreviouslyAuthorized = hkPrev }
        if let naps = snap.napMinutesByDate { napMinutesByDate = naps }
        if let jQuants = snap.journalQuantitiesByDate { journalQuantitiesByDate = jQuants }
        if let cMem = snap.coachMemoryNotes { coachMemoryNotes = cMem }
        if let gMode = snap.globalGoalMode { globalGoalMode = gMode }
        if let nRecs = snap.nutritionRecipes { nutritionRecipes = nRecs }
        if let cSet = snap.cycleTrackingSettings { cycleTrackingSettings = cSet }
        if let dMode = snap.autoDeloadModeActive { autoDeloadModeActive = dMode }
        if let wCity = snap.weatherCityName { weatherCityName = wCity }
        if let wSnap = snap.weatherSnapshot { weatherSnapshot = wSnap }
        if let cTone = snap.coachPersonalityTone { coachPersonalityTone = cTone }
        if let cDet = snap.coachDetailLevel { coachDetailLevel = cDet }
        if let arch = snap.archivedAiInsights { archivedAiInsights = arch }
        if let dynNut = snap.dynamicStrainNutritionEnabled { dynamicStrainNutritionEnabled = dynNut }

        // Automatically migrate retired Gemini 2.0 / 2.5-flash-lite defaults to live Auto-Discovery ("auto")
        if snap.selectedGeminiModel == "gemini-2.5-flash-lite" || snap.selectedGeminiModel == "gemini-2.0-flash" || snap.selectedGeminiModel.isEmpty {
            selectedGeminiModel = "auto"
        } else {
            selectedGeminiModel = snap.selectedGeminiModel
        }
        mealsByDate = snap.mealsByDate
        hydrationGlassesByDate = snap.hydrationGlassesByDate
        smartAlarmEnabled = snap.smartAlarmEnabled
        wakeOffsetMinutes = snap.wakeOffsetMinutes
        sleepGoalPct = snap.sleepGoalPct
        if !snap.visibleTabs.isEmpty { visibleTabs = Set(snap.visibleTabs) }
        if let cached = snap.sectionCoachingCache { sectionCoachingCache = cached }
        if let sigs = snap.processedAutoSyncSignatures {
            processedAutoSyncSignaturesOrder = sigs
            processedAutoSyncSignatures = Set(sigs)
        }
        if let status = snap.lastAutoSyncStatus, !status.isEmpty { autoSyncStatusText = status }
        if let sName = snap.shortcutSyncName, !sName.isEmpty {
            // Migrate legacy two-shortcut names cleanly to the single unified `Sync Improving` master shortcut
            if sName == "Sync Improving (Automático)" || sName == "Sync Improving (1 Toque)" {
                shortcutSyncName = "Sync Improving"
            } else {
                shortcutSyncName = sName
            }
        }
        if let autoRun = snap.autoRunShortcutOnOpen { autoRunShortcutOnOpen = autoRun }
        if let routines = snap.workoutRoutines { workoutRoutines = routines }
        if let logs = snap.strengthLogs { strengthLogs = logs }
        if let manualNut = snap.manualNutrientsByDate { manualNutrientsByDate = manualNut }
        if let hiddenIds = snap.hiddenJournalHabitIds { hiddenJournalHabitIds = Set(hiddenIds) }
        if let customHabits = snap.customJournalHabits { customJournalHabits = customHabits }
        if let notes = snap.journalNotesByDate { journalNotesByDate = notes }
        if let evTimes = snap.journalEventTimesByDate { journalEventTimesByDate = evTimes }
        if let notifCfg = snap.notificationSettings { notificationSettings = notifCfg }
        if let library = snap.savedFoodsLibrary { savedFoodsLibrary = library }
        if let nutGoals = snap.customNutritionGoals { customNutritionGoals = nutGoals }
        if let layout = snap.homeLayout { homeLayout = layout }
        if let threads = snap.coachThreads {
            coachThreads = threads
            if let activeId = snap.activeCoachThreadId,
               let activeThread = threads.first(where: { $0.id == activeId }) {
                activeCoachThreadId = activeId
                coachMessages = activeThread.messages
            } else if let first = threads.first {
                activeCoachThreadId = first.id
                coachMessages = first.messages
            }
        }
        if let labs = snap.labReports { labReports = labs }
        if let wkCache = snap.weeklyAiInsightsCache { weeklyAiInsightsCache = wkCache }

        // One-time self-healing migration for days corrupted by the v1 3-decimal kcal multiplier (>6,000 kcal -> 100% strain)
        var sanitizedCorruptStrain = false
        for (iso, day) in realHistory {
            if let k = day.activeKcal, k > 6_000 {
                var clean = day
                clean.activeKcal = nil
                clean.strainPct = nil
                clean.strain21 = nil
                realHistory[iso] = clean
                sanitizedCorruptStrain = true
            }
        }
        if sanitizedCorruptStrain {
            processedAutoSyncSignatures.removeAll()
        }

        // Self-healing migration for nights affected by Apple Watch Low Power Mode (under-charged Body Battery
        // or missing Recovery % despite real recorded sleep): recompute immediately on launch!
        let needsLowPowerEnergyHeal = realHistory.values.contains { day in
            guard let asleep = day.asleepMinutes, asleep >= 180 else { return false }
            if day.recoveryPct == nil || day.energySamples5m.isEmpty { return true }
            if (day.sleepPct ?? 0) >= 65 && day.energySamples5m.count >= 2 {
                let gain = zip(day.energySamples5m, day.energySamples5m.dropFirst()).reduce(0.0) { acc, pair in
                    acc + max(pair.1.value - pair.0.value, 0.0)
                }
                if gain < 15.0 { return true }
            }
            return false
        }
        if needsLowPowerEnergyHeal {
            recomputeMetricsForCurrentProfile()
            persistState()
        }
    }
}

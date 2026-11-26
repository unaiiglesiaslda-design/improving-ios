import Foundation
import Combine
import SwiftUI
import UIKit
import AppleWatchReader
import WhoopBLE
import WhoopProtocol

extension ImprovingStore {
    // MARK: - Diario Completion (>= 20 Manual Items) & Strict 30-Day Real Insight Engine

    static let diarioRequiredManualCount: Int = 20
    static let diarioRequiredTrackingDays: Int = 30

    static let journalCatalog: [(id: String, emoji: String, title: String, isAuto: Bool)] = [
        // Manual daily & nightly habits (strictly ignoring .unset!)
        ("fish_oil", "💊", "Aceite de pescado", false),
        ("sexual_activity", "❣️", "Actividad sexual", false),
        ("alcohol", "🍷", "Alcohol", false),
        ("ashwagandha", "💊", "Ashwagandha", false),
        ("added_sugar", "🍬", "Azúcar añadido", false),
        ("caffeine", "☕", "Cafeína", false),
        ("creatine", "💊", "Creatina", false),
        ("turmeric", "🫚", "Cúrcuma", false),
        ("low_carb", "🥖", "Dieta baja en carbohidratos", false),
        ("keto", "🥑", "Dieta keto", false),
        ("illness", "😷", "Enfermedad", false),
        ("fever", "🤒", "Fiebre", false),
        ("physio", "🚶", "Fisioterapia", false),
        ("injury", "🩹", "Lesión", false),
        ("morning_sun", "☀️", "Luz del sol por la mañana", false),
        ("dairy", "🥛", "Lácteos", false),
        ("magnesium", "💊", "Magnesio", false),
        ("pain_meds", "℞", "Medicación para el dolor", false),
        ("probiotic", "🦠", "Probiótico", false),
        ("shared_bed", "🛏️", "Cama compartida", false),
        ("late_meal", "🍽️", "Comer tarde", false),
        ("device_bed", "📱", "Dispositivo en la cama", false),
        ("sleep_interrupt", "🥱", "Interrupción del sueño", false),
        ("reading_bed", "📖", "Lectura en la cama", false),
        // Automatic habits evaluated from real watch / Apple Health data
        ("a_noise", "🔊", "Ruido al dormir de 50+ dB", true),
        ("a_strength", "🏋️", "20+ minutos de fuerza", true),
        ("a_daylight", "☀️", "20+ minutos de luz natural", true),
        ("a_steps", "👟", "10.000+ pasos", true),
        ("a_cardio", "🏃", "20+ minutos de cardio", true),
        ("a_z2", "🟠", "30+ minutos en la zona 2", true),
        ("a_stress", "💢", "50+ puntuación del Estrés", true),
        ("a_strain", "😮‍💨", "Objetivo de Esfuerzo superado", true),
    ]

    static let manualHabitIds: [String] = journalCatalog.filter { !$0.isAuto }.map(\.id)

    var allCatalogAndCustomEntries: [(id: String, emoji: String, title: String, isAuto: Bool)] {
        let customTuples = customJournalHabits.map { (id: $0.id, emoji: $0.emoji, title: $0.title, isAuto: false) }
        return Self.journalCatalog + customTuples
    }

    var allTrackableManualHabitIds: [String] {
        Self.manualHabitIds + customJournalHabits.map(\.id)
    }

    var requiredManualCountForCompletion: Int {
        let visibleManualTriStates = allTrackableManualHabitIds.filter { !hiddenJournalHabitIds.contains($0) }.count
        let moodVisible = hiddenJournalHabitIds.contains("mood") ? 0 : 1
        let hydVisible = hiddenJournalHabitIds.contains("hydration") ? 0 : 1
        let totalVisibleSlots = max(visibleManualTriStates + moodVisible + hydVisible, 1)
        return min(Self.diarioRequiredManualCount, totalVisibleSlots)
    }

    /// Counts strictly MANUAL (non-automatic) Diario items completed on `dateIso` (tri-state ✓/✕ + mood + hydration).
    func manualCompletedCount(for dateIso: String) -> Int {
        let map = journalCheckinsByDate[dateIso] ?? [:]
        var count = 0
        for id in allTrackableManualHabitIds {
            if let st = map[id], st != .unset {
                count += 1
            }
        }
        if journalMoodByDate[dateIso] != nil { count += 1 }
        if (hydrationGlassesByDate[dateIso] ?? 0) > 0 || (manualNutrientsByDate[dateIso]?["hidratacion_extra_ml"] ?? 0) > 0 {
            count += 1
        }
        return count
    }

    /// A day receives the Diario checkmark badge when the user completes >= `requiredManualCountForCompletion` manual entries (20 by default, or all active habits if customized < 20).
    func isDiarioDayCompleted(for dateIso: String) -> Bool {
        manualCompletedCount(for: dateIso) >= requiredManualCountForCompletion
    }

    func hasAnyJournalActivity(for dateIso: String) -> Bool {
        if manualCompletedCount(for: dateIso) > 0 { return true }
        let note = (journalNotesByDate[dateIso] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return !note.isEmpty
    }

    /// Number of distinct dates on which the user has logged at least one manual Diario entry.
    var totalManualDiarioDaysLogged: Int {
        let validIds = allTrackableManualHabitIds
        var dates = Set<String>()
        for (iso, map) in journalCheckinsByDate {
            if validIds.contains(where: { (map[$0] ?? .unset) != .unset }) {
                dates.insert(iso)
            }
        }
        for iso in journalMoodByDate.keys { dates.insert(iso) }
        for (iso, g) in hydrationGlassesByDate where g > 0 { dates.insert(iso) }
        for (iso, n) in journalNotesByDate where !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { dates.insert(iso) }
        return dates.count
    }

    /// Calendar span (in days, inclusive) from the user's earliest manual Diario entry to `selectedDate`.
    var manualDiarioSpanDays: Int {
        let validIds = allTrackableManualHabitIds
        var earliestIso: String? = nil
        for (iso, map) in journalCheckinsByDate {
            if validIds.contains(where: { (map[$0] ?? .unset) != .unset }) {
                if earliestIso == nil || iso < earliestIso! { earliestIso = iso }
            }
        }
        for iso in journalMoodByDate.keys {
            if earliestIso == nil || iso < earliestIso! { earliestIso = iso }
        }
        guard let firstIso = earliestIso, let firstDate = isoFormatter.date(from: firstIso) else { return 0 }
        let cal = Calendar.current
        let diff = cal.dateComponents([.day], from: cal.startOfDay(for: firstDate), to: cal.startOfDay(for: selectedDate)).day ?? 0
        return max(diff + 1, 1)
    }

    func automaticHabitState(id: String, day: RealBiometricDaySummary?) -> JournalCheckState {
        guard let d = day else { return .unset }
        switch id {
        case "a_steps":
            guard let s = d.stepsCount else { return .unset }
            return s >= 10000 ? .yes : .no
        case "a_cardio":
            let cardioMin = d.workouts.filter { $0.categoryLabel != "Fuerza" }.reduce(0) { $0 + $1.durationMin }
            if d.workouts.isEmpty && d.activeKcal == nil && d.stepsCount == nil { return .unset }
            return cardioMin >= 20 ? .yes : .no
        case "a_strength":
            if d.workouts.isEmpty && d.strengthMinutes == 0 && d.activeKcal == nil && d.stepsCount == nil { return .unset }
            return d.strengthMinutes >= 20 ? .yes : .no
        case "a_daylight":
            guard let dl = d.daylightMinutes else { return .unset }
            return dl >= 20 ? .yes : .no
        case "a_z2":
            let totalZ = d.hrZoneMinutes.reduce(0, +)
            guard totalZ > 0 else { return .unset }
            return (d.hrZoneMinutes.count > 1 ? d.hrZoneMinutes[1] : 0) >= 30 ? .yes : .no
        case "a_stress":
            guard let st = d.stressScore else { return .unset }
            return st >= 50 ? .yes : .no
        case "a_strain":
            guard let st = d.strainPct, d.recoveryPct != nil else { return .unset }
            let upper = personalizedEffortTarget(for: d.dateIso, includeCardioLoad: false).range.upperBound * 100.0
            return Double(st) > upper ? .yes : .no
        case "a_noise":
            guard let n = d.sleepNoiseOver50Db else { return .unset }
            return n ? .yes : .no
        default:
            return .unset
        }
    }

    /// Strict 30-day real tracking engine for Diario ✨ Información:
    /// - If the user has NOT filled out the Diario form (0 manual entries logged), ZERO metrics are computed or unlocked!
    /// - Each habit requires at least 30 days of elapsed tracking (daysSpanCount >= 30 || loggedDaysCount >= 30) AND both ✓ and ✕ occurrences before computing impact %.
    func computeJournalImpacts(for target: JournalImpactTarget) -> [JournalHabitImpactItem] {
        ensureDerivedCacheFresh()
        if let hit = cachedJournalImpacts[target] {
            return hit
        }
        let hasUserFilledForm = totalManualDiarioDaysLogged > 0
        let cal = Calendar.current
        let anchor = cal.startOfDay(for: selectedDate)
        var last90Isos: [String] = []
        last90Isos.reserveCapacity(90)
        for back in (0..<90).reversed() {
            if let d = cal.date(byAdding: .day, value: -back, to: anchor) {
                last90Isos.append(isoFormatter.string(from: d))
            }
        }

        var items: [JournalHabitImpactItem] = []
        for entry in allCatalogAndCustomEntries {
            var yesVals: [Double] = []
            var noVals: [Double] = []
            var firstLoggedIso: String? = nil
            var totalExplicitDays = 0

            for idx in 0..<last90Isos.count {
                let iso = last90Isos[idx]
                let state: JournalCheckState
                if entry.isAuto {
                    guard hasUserFilledForm, let day = activeHistory[iso] else { continue }
                    state = automaticHabitState(id: entry.id, day: day)
                } else {
                    state = journalCheckinsByDate[iso]?[entry.id] ?? .unset
                }

                guard state != .unset else { continue }
                if firstLoggedIso == nil { firstLoggedIso = iso }
                totalExplicitDays += 1

                // WHOOP causal Next-Day Lag (D -> D+1): habits logged on day D impact tonight's sleep & tomorrow morning's recovery!
                guard idx + 1 < last90Isos.count else { continue }
                let nextIso = last90Isos[idx + 1]
                guard let nextDay = activeHistory[nextIso] else { continue }
                let outcomeOpt: Int? = (target == .recovery) ? nextDay.recoveryPct : nextDay.sleepPct
                guard let outcome = outcomeOpt else { continue }

                if state == .yes { yesVals.append(Double(outcome)) }
                else if state == .no { noVals.append(Double(outcome)) }
            }

            let spanDays: Int = {
                guard let fIso = firstLoggedIso, let fDate = isoFormatter.date(from: fIso) else { return 0 }
                let d = cal.dateComponents([.day], from: cal.startOfDay(for: fDate), to: anchor).day ?? 0
                return max(d + 1, 1)
            }()

            let yCount = yesVals.count
            let nCount = noVals.count
            let reached30Days = hasUserFilledForm && (spanDays >= Self.diarioRequiredTrackingDays || totalExplicitDays >= Self.diarioRequiredTrackingDays)

            let tier: JournalReliabilityTier
            let impact: Int
            if reached30Days && yCount >= 5 && nCount >= 5 {
                tier = .high
                let meanY = yesVals.reduce(0, +) / Double(yCount)
                let meanN = noVals.reduce(0, +) / Double(nCount)
                impact = Int((meanY - meanN).rounded())
            } else if reached30Days && yCount >= 1 && nCount >= 1 {
                tier = .low
                let meanY = yesVals.reduce(0, +) / Double(yCount)
                let meanN = noVals.reduce(0, +) / Double(nCount)
                impact = Int((meanY - meanN).rounded())
            } else {
                tier = .locked
                impact = 0
            }

            items.append(JournalHabitImpactItem(
                id: entry.id,
                emoji: entry.emoji,
                title: entry.title,
                impactPct: impact,
                yesCount: yCount,
                noCount: nCount,
                loggedDaysCount: totalExplicitDays,
                daysSpanCount: spanDays,
                reliability: tier,
                isAutomatic: entry.isAuto
            ))
        }

        let sortedItems = items.sorted { a, b in
            if a.reliability != b.reliability {
                let rank: (JournalReliabilityTier) -> Int = { $0 == .high ? 0 : ($0 == .low ? 1 : 2) }
                return rank(a.reliability) < rank(b.reliability)
            }
            if a.reliability != .locked && abs(a.impactPct) != abs(b.impactPct) {
                return abs(a.impactPct) > abs(b.impactPct)
            }
            if a.isAutomatic != b.isAutomatic {
                return !a.isAutomatic // Show manual habits first when locked
            }
            return (a.yesCount + a.noCount) > (b.yesCount + b.noCount)
        }
        cachedJournalImpacts[target] = sortedItems
        return sortedItems
    }

    // MARK: - User Actions & Date Selection

    func completeOnboarding(_ profile: UserPhysiologyProfile) {
        var p = profile
        p.onboardingCompleted = true
        p.profileSetupVersion = max(p.profileSetupVersion, 2)
        userProfile = p
        recomputeMetricsForCurrentProfile()
        persistState()
    }

    func replayOnboarding() {
        userProfile.onboardingCompleted = false
        persistState()
    }

    func updateProfile(_ profile: UserPhysiologyProfile) {
        var p = profile
        p.ageYears = p.effectiveAgeYears
        userProfile = p
        recomputeMetricsForCurrentProfile()
        persistState()
    }

    /// Recalculates Sleep Score, Sleep Debt, Recovery %, Strain % / Strain 21, Workout Strain,
    /// and Energy Bank across stored days immediately whenever age/birthDate, sex, height, or weight changes!
    func recomputeMetricsForCurrentProfile() {
        let profile = userProfile
        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: profile)
        let targetSleepMin = norms.sleepTargetHours * 60.0
        let maxHr = Double(norms.maxHrBpm)
        let respCenter = (norms.respLowRpm + norms.respHighRpm) / 2.0

        if !hasImportedOrPairedRealData {
            simulatedHistory = WhoopPhysiologyEngine.generateTwoYearSimulatedHistory(profile: profile)
        }

        if !realHistory.isEmpty {
            let sortedIsos = realHistory.keys.sorted()
            var priorLnHrvRmssd: [Double] = []
            var priorLnHrvSdnn: [Double] = []
            var priorRhr: [Double] = []
            var priorResp: [Double] = []
            var runningSleepDebtMin: Double = 0.0
            var updated: [String: RealBiometricDaySummary] = [:]
            updated.reserveCapacity(realHistory.count)

            for iso in sortedIsos {
                guard var day = realHistory[iso] else { continue }

                // 1. Age/Sex-calibrated Sleep Score & Cumulative Rolling Sleep Debt
                if let asleep = day.asleepMinutes, asleep > 0 {
                    let awakeCnt = day.sleepSession?.stages.filter { $0.stage == .awake }.count ?? 0
                    day.sleepPct = WhoopPhysiologyEngine.computeBevelSleepScore(
                        asleepMinutes: asleep,
                        inBedMinutes: day.inBedMinutes,
                        deepMinutes: day.deepMinutes,
                        remMinutes: day.remMinutes,
                        awakeMinutes: day.awakeMinutes,
                        awakeCount: awakeCnt,
                        hrDipPct: day.sleepSession?.hrDipPct,
                        targetMinutes: targetSleepMin,
                        deepTargetPct: norms.deepTargetPct,
                        remTargetPct: norms.remTargetPct
                    )
                    let debt = WhoopPhysiologyEngine.updateCumulativeSleepDebt(
                        previousDebtMinutes: runningSleepDebtMin,
                        asleepMinutes: asleep,
                        targetMinutes: targetSleepMin
                    )
                    runningSleepDebtMin = Double(debt)
                    day.sleepDebtMinutes = debt
                }

                // 2. Causal 60-day Recovery % with separate RMSSD vs SDNN personal baselines & unified sigmas
                let dayIsSdnn = (day.hrvMethodLabel?.uppercased().contains("SDNN") == true)
                let hrvExpected = dayIsSdnn ? (norms.hrvExpectedMs * 1.18) : norms.hrvExpectedMs
                let lnHrvBase = WhoopPhysiologyEngine.computeRollingBaseline(
                    priorValues: dayIsSdnn ? priorLnHrvSdnn : priorLnHrvRmssd,
                    populationMean: log(max(hrvExpected, 15.0)),
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

                if let newRec = WhoopPhysiologyEngine.computeBevelRecoveryPercent(
                    hrvMs: day.hrvMs,
                    rhrBpm: day.restingHrBpm,
                    respRpm: day.respRateRpm,
                    spo2Pct: day.spo2Percent,
                    wristTempDeltaC: day.wristTempDeltaC,
                    lnHrvBaseline: lnHrvBase,
                    rhrBaseline: rhrBase,
                    respBaseline: respBase,
                    profile: profile,
                    sleepPct: day.sleepPct
                ) {
                    day.recoveryPct = newRec
                }

                if let h = day.hrvMs, h > 2.0 {
                    if dayIsSdnn { priorLnHrvSdnn.append(log(h)) } else { priorLnHrvRmssd.append(log(h)) }
                }
                if let r = day.restingHrBpm { priorRhr.append(r) }
                if let rr = day.respRateRpm { priorResp.append(rr) }

                // 3. Age/Sex/Weight/Height-calibrated Workout & Daily Strain (Tanaka MaxHR + Banister B + Mifflin BMR)
                let rhrRef = day.restingHrBpm ?? rhrBase.mean
                if !day.workouts.isEmpty {
                    day.workouts = day.workouts.map { w in
                        let ws = WhoopPhysiologyEngine.computeWorkoutStrain(
                            durationMin: w.durationMin,
                            kcal: w.kcal,
                            avgHrBpm: w.avgHrBpm,
                            rhrBpm: rhrRef,
                            maxHrBpm: maxHr,
                            banisterB: profile.sex.banisterB
                        )
                        return EffortEventItem(
                            id: w.id,
                            title: w.title,
                            timeRange: w.timeRange,
                            durationMin: w.durationMin,
                            avgHrBpm: w.avgHrBpm,
                            strainScore: ws.strain21,
                            strainPct: ws.strainPct,
                            categoryLabel: w.categoryLabel,
                            kcal: w.kcal,
                            distanceKm: w.distanceKm,
                            elevationM: w.elevationM,
                            dateIso: w.dateIso,
                            startEpochSec: w.startEpochSec,
                            avgPowerW: w.avgPowerW,
                            avgCadenceRpm: w.avgCadenceRpm,
                            hrZoneMinutes6: w.hrZoneMinutes6,
                            hrRecovery1MinBpm: w.hrRecovery1MinBpm,
                            totalSets: w.totalSets,
                            totalVolumeKg: w.totalVolumeKg,
                            targetMuscles: w.targetMuscles
                        )
                    }
                }

                if let st = WhoopPhysiologyEngine.computeBevelStrain(
                    profile: profile,
                    rhrBpm: rhrRef,
                    hrZoneMinutes: day.hrZoneMinutes,
                    workouts: day.workouts,
                    activeKcal: day.activeKcal.map { Double($0) }
                ) {
                    day.strain21 = st.strain21
                    day.strainPct = st.strainPct
                }

                updated[iso] = day
            }
            recomputeContinuousEnergy(in: &updated)
            realHistory = updated
        }

        sectionCoachingCache.removeAll()
        dataRevision += 1
    }

    /// Re-integrates the continuous cross-day Body Battery timeline across all stored days
    /// (preserves exact midnight handoff, handles Apple Watch Low Power Mode sleep gaps, and eliminates stale curve seams).
    func recomputeContinuousEnergy(in history: inout [String: RealBiometricDaySummary]) {
        let sortedIsos = history.keys.sorted()
        var prevDayDate: Date? = nil
        var prevDayEndEnergy: Double? = nil
        var prevDayEndEpoch: Int64? = nil
        let cal = Calendar.current

        for (dayIdx, iso) in sortedIsos.enumerated() {
            guard var day = history[iso] else { continue }
            let curDate = isoFormatter.date(from: iso)
            let dayStartEp: Int64? = curDate.map { Int64(cal.startOfDay(for: $0).timeIntervalSince1970) }
            let hasRealSleep = (day.sleepSession != nil) || ((day.asleepMinutes ?? 0) > 0)
            let nextSleepStartEp: Int64? = {
                guard dayIdx + 1 < sortedIsos.count else { return nil }
                return history[sortedIsos[dayIdx + 1]]?.sleepSession?.startEpochSec
            }()

            guard !day.stressSamples5m.isEmpty || hasRealSleep else {
                if let lastE = day.energySamples5m.last?.value ?? day.energyBankPercent.map({ Double($0) }) {
                    prevDayEndEnergy = lastE
                    prevDayEndEpoch = day.energySamples5m.last?.epochSec
                    prevDayDate = curDate
                }
                continue
            }

            let isContinuous: Bool = {
                guard let prevE = prevDayEndEnergy, let pDate = prevDayDate, let cDate = curDate, prevE.isFinite else { return false }
                let gapDays = cal.dateComponents([.day], from: pDate, to: cDate).day ?? 99
                guard gapDays == 1 else { return false }
                if let pEp = prevDayEndEpoch, let firstEp = day.stressSamples5m.first?.epochSec {
                    return (firstEp - pEp) <= 24 * 3600
                }
                return true
            }()

            let initialEnergy: Double = {
                if isContinuous, let carried = prevDayEndEnergy {
                    return carried
                }
                if hasRealSleep {
                    return Double(max(min((day.recoveryPct ?? day.sleepPct ?? 65) - 34, 48), 22))
                }
                return Double(max(min((day.recoveryPct ?? 65) - 24, 65), 22))
            }()

            let workoutSpans: [ClosedRange<Int64>] = day.workouts.compactMap { w in
                guard let s = w.startEpochSec, w.durationMin > 0 else { return nil }
                return s...(s + Int64(w.durationMin * 60))
            }

            let energy5m = AppleHealthExportImporter.buildContinuousFiveMinuteEnergySamples(
                stressSamples: day.stressSamples5m,
                startingEnergy: initialEnergy,
                recoveryPct: day.recoveryPct,
                sleepPct: day.sleepPct,
                sleepStartEpoch: day.sleepSession?.startEpochSec,
                sleepEndEpoch: day.sleepSession?.endEpochSec,
                workoutSpans: workoutSpans,
                asleepMinutes: day.asleepMinutes,
                dayStartEpoch: dayStartEp,
                nextSleepStartEpoch: nextSleepStartEp
            )

            if let lastE = energy5m.last {
                day.energySamples5m = energy5m
                day.energyBankPercent = Int(lastE.value.rounded())
                prevDayEndEnergy = lastE.value
                prevDayEndEpoch = lastE.epochSec
                prevDayDate = curDate
                history[iso] = day
            }
        }
    }

    func shiftDay(_ delta: Int) {
        dayOffset = max(dayOffset + delta, 0)
    }

    func selectDayOffset(_ offset: Int) {
        dayOffset = max(offset, 0)
    }

    func selectDate(_ date: Date) {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let targetStart = cal.startOfDay(for: date)
        let diff = cal.dateComponents([.day], from: targetStart, to: todayStart).day ?? 0
        dayOffset = max(diff, 0)
    }

    func setDarkMode(_ dark: Bool) {
        BevelColors.isDarkMode = dark
        objectWillChange.send()
        persistState()
    }

    func toggleTabVisibility(_ tab: MainTab) {
        if visibleTabs.contains(tab) && visibleTabs.count > 1 {
            visibleTabs.remove(tab)
        } else {
            visibleTabs.insert(tab)
        }
        persistState()
    }

    func setJournalCheck(habitId: String, state: JournalCheckState, for dateIso: String? = nil, eventTime: String? = nil) {
        let iso = dateIso ?? selectedDateIso
        var map = journalCheckinsByDate[iso] ?? [:]
        map[habitId] = state
        journalCheckinsByDate[iso] = map

        if state != .yes {
            // Clearing or marking No removes any optional event timestamp and dosage for this habit on this day
            journalEventTimesByDate[iso]?.removeValue(forKey: habitId)
            if journalEventTimesByDate[iso]?.isEmpty == true {
                journalEventTimesByDate.removeValue(forKey: iso)
            }
            journalQuantitiesByDate[iso]?.removeValue(forKey: habitId)
            if journalQuantitiesByDate[iso]?.isEmpty == true {
                journalQuantitiesByDate.removeValue(forKey: iso)
            }
        } else {
            if let spec = JournalHabitDosageSpec.spec(for: habitId),
               journalQuantitiesByDate[iso]?[habitId] == nil {
                var qMap = journalQuantitiesByDate[iso] ?? [:]
                qMap[habitId] = spec.defaultYesValue
                journalQuantitiesByDate[iso] = qMap
            }
            if let rawTime = eventTime {
                let clean = rawTime.trimmingCharacters(in: .whitespacesAndNewlines)
                if clean.isEmpty {
                    journalEventTimesByDate[iso]?.removeValue(forKey: habitId)
                } else {
                    var tMap = journalEventTimesByDate[iso] ?? [:]
                    tMap[habitId] = clean
                    journalEventTimesByDate[iso] = tMap
                }
            }
        }
        invalidateSectionCoachingCache(sections: [.hoy, .recuperacion, .sueno])
        dataRevision += 1
        persistState()
        if iso == isoFormatter.string(from: Date()) {
            refreshSmartNotificationSchedules(promptPermission: false)
        }
    }

    func journalEventTime(habitId: String, for dateIso: String? = nil) -> String? {
        let iso = dateIso ?? selectedDateIso
        let t = journalEventTimesByDate[iso]?[habitId]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (t?.isEmpty == false) ? t : nil
    }

    func setJournalEventTime(habitId: String, timeLabel: String?, for dateIso: String? = nil) {
        let iso = dateIso ?? selectedDateIso
        let clean = timeLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if clean.isEmpty {
            journalEventTimesByDate[iso]?.removeValue(forKey: habitId)
            if journalEventTimesByDate[iso]?.isEmpty == true {
                journalEventTimesByDate.removeValue(forKey: iso)
            }
        } else {
            var tMap = journalEventTimesByDate[iso] ?? [:]
            tMap[habitId] = clean
            journalEventTimesByDate[iso] = tMap
        }
        dataRevision += 1
        persistState()
    }

    func setJournalMood(_ mood: Int, for dateIso: String? = nil) {
        let iso = dateIso ?? selectedDateIso
        journalMoodByDate[iso] = min(max(mood, 1), 5)
        invalidateSectionCoachingCache(sections: [.hoy, .recuperacion, .sueno])
        dataRevision += 1
        persistState()
        if iso == isoFormatter.string(from: Date()) {
            refreshSmartNotificationSchedules(promptPermission: false)
        }
    }

    func isHabitHidden(_ id: String) -> Bool {
        hiddenJournalHabitIds.contains(id)
    }

    func toggleHabitHidden(_ id: String) {
        if hiddenJournalHabitIds.contains(id) {
            hiddenJournalHabitIds.remove(id)
        } else {
            hiddenJournalHabitIds.insert(id)
        }
        persistState()
    }

    func resetHiddenHabits() {
        hiddenJournalHabitIds.removeAll()
        persistState()
    }

    func addCustomJournalHabit(emoji: String, title: String, isNightHabit: Bool) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        let cleanEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "✨" : String(emoji.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2))
        let item = CustomJournalHabit(
            id: "custom_\(UUID().uuidString.prefix(8))",
            emoji: cleanEmoji,
            title: cleanTitle,
            isNightHabit: isNightHabit
        )
        customJournalHabits.append(item)
        persistState()
    }

    func deleteCustomJournalHabit(id: String) {
        customJournalHabits.removeAll { $0.id == id }
        hiddenJournalHabitIds.remove(id)
        persistState()
    }

    func journalNote(for dateIso: String? = nil) -> String {
        journalNotesByDate[dateIso ?? selectedDateIso] ?? ""
    }

    func setJournalNote(_ note: String, for dateIso: String? = nil) {
        let iso = dateIso ?? selectedDateIso
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            journalNotesByDate.removeValue(forKey: iso)
        } else {
            journalNotesByDate[iso] = trimmed
        }
        invalidateSectionCoachingCache(sections: [.hoy, .recuperacion, .sueno, .estres])
        dataRevision += 1
        persistState()
        if iso == isoFormatter.string(from: Date()) {
            refreshSmartNotificationSchedules(promptPermission: false)
        }
    }

    // MARK: - Persisted Nutrition & Nutrient Tracking

    static func normalizedNutrientBucketKey(_ raw: String) -> String {
        let low = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
        if low.contains("carb") { return "carbohidratos" }
        if low.contains("prote") { return "proteina" }
        if low.contains("gras") { return "grasas" }
        if low.contains("hidra") || low.contains("agua") { return "hidratacion" }
        if low.contains("cafe") { return "cafeina" }
        if low.contains("alco") { return "alcohol" }
        return "calcio"
    }

    func manualNutrientAmount(for key: String, dateIso: String? = nil) -> Double {
        let iso = dateIso ?? selectedDateIso
        let bucket = Self.normalizedNutrientBucketKey(key)
        if bucket == "hidratacion" {
            let glassesMl = Double(hydrationGlassesByDate[iso] ?? 0) * 250.0
            let extraMl = manualNutrientsByDate[iso]?["hidratacion_extra_ml"] ?? 0.0
            return max(0, glassesMl + extraMl)
        }
        return max(0, manualNutrientsByDate[iso]?[bucket] ?? 0.0)
    }

    func addNutrientAmount(key: String, amount: Double, dateIso: String? = nil) {
        guard amount > 0 else { return }
        let iso = dateIso ?? selectedDateIso
        let bucket = Self.normalizedNutrientBucketKey(key)
        if bucket == "hidratacion" {
            if abs(amount - 250.0) < 0.1 {
                hydrationGlassesByDate[iso] = (hydrationGlassesByDate[iso] ?? 0) + 1
            } else {
                var dayMap = manualNutrientsByDate[iso] ?? [:]
                dayMap["hidratacion_extra_ml"] = (dayMap["hidratacion_extra_ml"] ?? 0.0) + amount
                manualNutrientsByDate[iso] = dayMap
            }
        } else {
            var dayMap = manualNutrientsByDate[iso] ?? [:]
            dayMap[bucket] = (dayMap[bucket] ?? 0.0) + amount
            manualNutrientsByDate[iso] = dayMap
        }
        dataRevision += 1
        persistState()
    }

    func resetNutrientAmount(key: String, dateIso: String? = nil) {
        let iso = dateIso ?? selectedDateIso
        let bucket = Self.normalizedNutrientBucketKey(key)
        if bucket == "hidratacion" {
            hydrationGlassesByDate.removeValue(forKey: iso)
            manualNutrientsByDate[iso]?.removeValue(forKey: "hidratacion_extra_ml")
        } else {
            manualNutrientsByDate[iso]?.removeValue(forKey: bucket)
        }
        dataRevision += 1
        persistState()
    }

    func addHydrationGlass() {
        hydrationGlassesByDate[selectedDateIso] = (hydrationGlassesByDate[selectedDateIso] ?? 0) + 1
        invalidateSectionCoachingCache(sections: [.hoy, .energia])
        dataRevision += 1
        persistState()
    }

    func saveMeal(_ meal: NutritionMealItem, for dateIso: String? = nil) {
        let iso = dateIso ?? selectedDateIso
        var list = mealsByDate[iso] ?? []
        if let idx = list.firstIndex(where: { $0.id == meal.id }) {
            list[idx] = meal
        } else {
            list.insert(meal, at: 0)
        }
        mealsByDate[iso] = list
        syncAutoJournalHabits(for: iso)
        invalidateSectionCoachingCache(sections: [.hoy, .energia])
        dataRevision += 1
        persistState()
    }

    func invalidateSectionCoachingCache(sections: [CoachingSection]) {
        let prefixes = sections.map { "\($0.rawValue)_" }
        for k in Array(sectionCoachingCache.keys) {
            if prefixes.contains(where: { k.hasPrefix($0) }) {
                sectionCoachingCache.removeValue(forKey: k)
                sectionCoachingTimestamps.removeValue(forKey: k)
            }
        }
    }

    func deleteMeal(id: String, for dateIso: String? = nil, deletePhotoFromDisk: Bool = true) {
        let iso = dateIso ?? selectedDateIso
        guard var list = mealsByDate[iso] else { return }
        if deletePhotoFromDisk {
            for m in list where m.id == id {
                if let fname = m.photoFilename, !fname.isEmpty {
                    MealPhotoStorage.deletePhoto(filename: fname)
                }
            }
        }
        list.removeAll { $0.id == id }
        if list.isEmpty {
            mealsByDate.removeValue(forKey: iso)
        } else {
            mealsByDate[iso] = list
        }
        invalidateSectionCoachingCache(sections: [.hoy, .energia])
        dataRevision += 1
        persistState()
    }

    func addQuickMeal(title: String, kcal: Int, protein: Int, carbs: Int, fat: Int) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        saveMeal(
            NutritionMealItem(
                id: UUID().uuidString,
                title: title,
                timeLabel: f.string(from: Date()),
                kcal: kcal,
                proteinG: protein,
                carbsG: carbs,
                fatG: fat,
                qualityScore: 85
            )
        )
    }

    // MARK: - Smart Local Notifications, Nap Credit & WHOOP Sleep Coach Planner

    var napMinutesToday: Int {
        napMinutesByDate[selectedDateIso] ?? 0
    }

    func napMinutes(for dateIso: String) -> Int {
        napMinutesByDate[dateIso] ?? 0
    }

    func napCreditMinutes(for dateIso: String) -> Int {
        let mins = napMinutes(for: dateIso)
        guard mins > 0 else { return 0 }
        // WHOOP-style nap credit: ~85% restorative credit, capped at 90 min so main circadian sleep stays protected
        return min(Int((Double(mins) * 0.85).rounded()), 90)
    }

    func logNap(minutes: Int, for dateIso: String? = nil) {
        let iso = dateIso ?? selectedDateIso
        let clamped = min(max(minutes, 0), 180)
        if clamped == 0 {
            napMinutesByDate.removeValue(forKey: iso)
        } else {
            napMinutesByDate[iso] = clamped
        }
        invalidateSectionCoachingCache(sections: [.hoy, .sueno, .energia])
        dataRevision += 1
        persistState()
        refreshSmartNotificationSchedules(promptPermission: false)
    }

    func clearNap(for dateIso: String? = nil) {
        logNap(minutes: 0, for: dateIso)
    }

    func setSleepGoalPct(_ pct: Int) {
        let allowed = [70, 85, 100]
        sleepGoalPct = allowed.contains(pct) ? pct : min(max(pct, 70), 100)
        dataRevision += 1
        persistState()
        refreshSmartNotificationSchedules(promptPermission: false)
    }

    var tonightSleepNeedBreakdown: (baseMin: Int, debtMin: Int, strainExtraMin: Int, napCreditMin: Int, goalPct: Int, totalMin: Int) {
        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: userProfile)
        let baseMin = Int((norms.sleepTargetHours * 60.0).rounded())
        let todayIso = isoFormatter.string(from: Date())
        let refDay = activeHistory[todayIso] ?? currentDaySummary
        let debt = refDay?.sleepDebtMinutes ?? 0
        let stPct = refDay?.strainPct ?? 0
        let extra = stPct > 70 ? 25 : (stPct > 45 ? 10 : 0)
        let napCredit = napCreditMinutes(for: todayIso)
        let fullNeed = max(baseMin + debt + extra - napCredit, 300)
        let pct = min(max(sleepGoalPct, 70), 100)
        let scaledNeed = max(Int((Double(fullNeed) * Double(pct) / 100.0).rounded()), 300)
        return (baseMin, debt, extra, napCredit, pct, scaledNeed)
    }

    var computedSleepPlan: ComputedSleepNotificationPlan {
        LocalNotificationManager.computeSleepNotificationPlan(
            wakeHour: notificationSettings.smartAlarmHour,
            wakeMinute: notificationSettings.smartAlarmMinute,
            sleepNeedMinutes: tonightSleepNeedBreakdown.totalMin,
            leadMinutes: notificationSettings.bedtimeLeadMinutes
        )
    }

    func setSmartAlarmEnabled(_ enabled: Bool, promptPermission: Bool = true) {
        smartAlarmEnabled = enabled
        persistState()
        refreshSmartNotificationSchedules(promptPermission: promptPermission && enabled)
    }

    func updateNotificationSettings(_ updated: SmartNotificationSettings, promptPermission: Bool = true) {
        notificationSettings = updated
        persistState()
        refreshSmartNotificationSchedules(promptPermission: promptPermission)
    }

    func refreshSmartNotificationSchedules(promptPermission: Bool = false) {
        let todayIso = isoFormatter.string(from: Date())
        let alreadyLogged = hasAnyJournalActivity(for: todayIso)
        let need = tonightSleepNeedBreakdown
        let todaySummary = activeHistory[todayIso] ?? currentDaySummary
        let stPct = todaySummary?.strainPct ?? 0
        let hasSt = todaySummary?.strainPct != nil
        let cfg = notificationSettings
        let alarmOn = smartAlarmEnabled
        let uName = userProfile.displayFirstName

        Task { @MainActor [weak self] in
            let status = await LocalNotificationManager.shared.syncAllSchedules(
                settings: cfg,
                smartAlarmEnabled: alarmOn,
                todayJournalAlreadyLogged: alreadyLogged,
                sleepNeedMinutes: need.totalMin,
                sleepDebtMinutes: need.debtMin,
                strainPercent: stPct,
                hasStrainData: hasSt,
                userName: uName,
                promptPermissionIfNeeded: promptPermission
            )
            self?.notificationStatusText = status
        }
    }

    func triggerTestLocalNotification() {
        let uName = userProfile.displayFirstName
        Task { @MainActor [weak self] in
            let status = await LocalNotificationManager.shared.sendTestNotification(userName: uName)
            self?.notificationStatusText = status
        }
    }

    // MARK: - Individual Workout Selection, Editing & Deletion

    func selectWorkout(_ workout: EffortEventItem) {
        var enriched = workout
        if enriched.dateIso == nil {
            enriched.dateIso = selectedDateIso
        }
        selectedWorkoutItem = enriched
    }

    func updateWorkout(_ updated: EffortEventItem, originalDateIso: String? = nil) {
        let targetIso = updated.dateIso ?? originalDateIso ?? selectedDateIso
        var d = activeHistory[targetIso] ?? RealBiometricDaySummary(dateIso: targetIso)
        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: userProfile)
        let rhrRef = d.restingHrBpm ?? norms.restingHrExpected
        let ws = WhoopPhysiologyEngine.computeWorkoutStrain(
            durationMin: max(updated.durationMin, 1),
            kcal: max(updated.kcal, 0),
            avgHrBpm: max(updated.avgHrBpm, 0),
            rhrBpm: rhrRef,
            maxHrBpm: Double(norms.maxHrBpm),
            banisterB: userProfile.sex.banisterB
        )

        var recalc = updated
        recalc.dateIso = targetIso
        recalc.strainScore = ws.strain21
        recalc.strainPct = ws.strainPct

        if let idx = d.workouts.firstIndex(where: { $0.id == recalc.id }) {
            d.workouts[idx] = recalc
        } else {
            d.workouts.insert(recalc, at: 0)
        }
        d.strengthMinutes = d.workouts.filter { $0.categoryLabel == "Fuerza" }.reduce(0) { $0 + $1.durationMin }
        if let st = WhoopPhysiologyEngine.computeBevelStrain(
            profile: userProfile,
            rhrBpm: rhrRef,
            hrZoneMinutes: d.hrZoneMinutes,
            workouts: d.workouts,
            activeKcal: d.activeKcal.map { Double($0) }
        ) {
            d.strain21 = st.strain21
            d.strainPct = st.strainPct
        }

        realHistory[targetIso] = d
        if !hasImportedOrPairedRealData {
            simulatedHistory[targetIso] = d
        }
        selectedWorkoutItem = recalc
        invalidateSectionCoachingCache(sections: [.hoy, .esfuerzo, .fitness, .energia])
        dataRevision += 1
        persistState()
    }

    func deleteWorkout(id: String, dateIso: String? = nil) {
        let targetIso = dateIso ?? selectedWorkoutItem?.dateIso ?? selectedDateIso
        guard var d = activeHistory[targetIso] else { return }
        d.workouts.removeAll { $0.id == id }
        d.strengthMinutes = d.workouts.filter { $0.categoryLabel == "Fuerza" }.reduce(0) { $0 + $1.durationMin }

        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: userProfile)
        let rhrRef = d.restingHrBpm ?? norms.restingHrExpected
        if let st = WhoopPhysiologyEngine.computeBevelStrain(
            profile: userProfile,
            rhrBpm: rhrRef,
            hrZoneMinutes: d.hrZoneMinutes,
            workouts: d.workouts,
            activeKcal: d.activeKcal.map { Double($0) }
        ) {
            d.strain21 = st.strain21
            d.strainPct = st.strainPct
        } else if d.workouts.isEmpty && (d.activeKcal ?? 0) == 0 {
            d.strain21 = nil
            d.strainPct = nil
        }

        realHistory[targetIso] = d
        if !hasImportedOrPairedRealData {
            simulatedHistory[targetIso] = d
        }
        if selectedWorkoutItem?.id == id {
            selectedWorkoutItem = nil
        }
        invalidateSectionCoachingCache(sections: [.hoy, .esfuerzo, .fitness, .energia])
        dataRevision += 1
        persistState()
    }

    func workoutIntradaySamples(for workout: EffortEventItem) -> [TimedBiometricPoint] {
        let iso = workout.dateIso ?? selectedDateIso
        guard let day = activeHistory[iso], !day.stressSamples5m.isEmpty else { return [] }
        // Parse `HH:mm - HH:mm` from `timeRange` when available
        let parts = workout.timeRange.components(separatedBy: "-")
        if parts.count == 2 {
            let parseHHMM: (String) -> Int? = { raw in
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                let tokens = trimmed.split(separator: ":")
                guard tokens.count == 2, let h = Int(tokens[0]), let m = Int(tokens[1]) else { return nil }
                return h * 60 + m
            }
            if let sMin = parseHHMM(parts[0]), let eMin = parseHHMM(parts[1]), eMin >= sMin {
                let window = max(0, sMin - 5)...min(1439, eMin + 5)
                let slice = day.stressSamples5m.filter { window.contains($0.minuteOfDay) }
                if slice.count >= 2 { return slice }
            }
        }
        if let sEp = workout.startEpochSec, workout.durationMin > 0 {
            let eEp = sEp + Int64(workout.durationMin * 60)
            let slice = day.stressSamples5m.filter { pt in
                guard let ep = pt.epochSec else { return false }
                return ep >= (sEp - 300) && ep <= (eEp + 300)
            }
            if slice.count >= 2 { return slice }
        }
        return []
    }

    func addEffortEvent(title: String, durationMin: Int, kcal: Int) {
        var d = realHistory[selectedDateIso] ?? currentDaySummary ?? RealBiometricDaySummary(dateIso: selectedDateIso)
        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: userProfile)
        let rhrRef = d.restingHrBpm ?? norms.restingHrExpected
        let ws = WhoopPhysiologyEngine.computeWorkoutStrain(
            durationMin: max(durationMin, 1),
            kcal: max(kcal, 0),
            avgHrBpm: 0,
            rhrBpm: rhrRef,
            maxHrBpm: Double(norms.maxHrBpm),
            banisterB: userProfile.sex.banisterB
        )
        let startEp = Int64(selectedDate.timeIntervalSince1970) - Int64(max(durationMin, 1) * 60)
        let ev = EffortEventItem(
            id: UUID().uuidString,
            title: title,
            timeRange: "Hoy",
            durationMin: max(durationMin, 1),
            avgHrBpm: 0,
            strainScore: ws.strain21,
            strainPct: ws.strainPct,
            categoryLabel: "Actividad",
            kcal: max(kcal, 0),
            dateIso: selectedDateIso,
            startEpochSec: startEp
        )
        d.workouts.insert(ev, at: 0)
        if let st = WhoopPhysiologyEngine.computeBevelStrain(
            profile: userProfile,
            rhrBpm: rhrRef,
            hrZoneMinutes: d.hrZoneMinutes,
            workouts: d.workouts,
            activeKcal: d.activeKcal.map { Double($0) }
        ) {
            d.strain21 = st.strain21
            d.strainPct = st.strainPct
        }
        realHistory[selectedDateIso] = d
        if !hasImportedOrPairedRealData {
            simulatedHistory[selectedDateIso] = d
        }
        invalidateSectionCoachingCache(sections: [.hoy, .esfuerzo, .fitness])
        dataRevision += 1
        persistState()
    }

    func toggleSetCompleted(_ id: String) {
        if let idx = strengthSets.firstIndex(where: { $0.id == id }) {
            strengthSets[idx].completed.toggle()
        }
    }

    func addStrengthSet(exercise: String = "Press militar", reps: Int = 10, weightKg: Double = 45) {
        strengthSets.append((UUID().uuidString, exercise, reps, weightKg, false))
    }

    func toggleRestTimer() {
        restTimerRunning.toggle()
        timerTask?.cancel()
        if restTimerRunning {
            let startSec = restTimerSeconds > 0 ? restTimerSeconds : 90
            restTimerSeconds = startSec
            let endDate = Date().addingTimeInterval(TimeInterval(startSec))
            restTimerEndDate = endDate
            timerTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    guard let self, self.restTimerRunning, let end = self.restTimerEndDate else { break }
                    let rem = max(Int(ceil(end.timeIntervalSinceNow)), 0)
                    if self.restTimerSeconds != rem {
                        self.restTimerSeconds = rem
                    }
                    if rem == 0 {
                        self.restTimerRunning = false
                        self.restTimerEndDate = nil
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        break
                    }
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
        } else {
            restTimerEndDate = nil
            restTimerSeconds = 90
        }
    }

    func refreshBackgroundRestTimer() {
        guard restTimerRunning, let end = restTimerEndDate else { return }
        let rem = max(Int(ceil(end.timeIntervalSinceNow)), 0)
        restTimerSeconds = rem
        if rem == 0 {
            restTimerRunning = false
            restTimerEndDate = nil
            timerTask?.cancel()
        }
    }

    // MARK: - Quantified Journal Dosages, Auto-Fill & Caffeine Half-Life (Apartado 1.2)

    func journalQuantity(habitId: String, for dateIso: String? = nil) -> Double? {
        let iso = dateIso ?? selectedDateIso
        return journalQuantitiesByDate[iso]?[habitId]
    }

    func setJournalQuantity(habitId: String, quantity: Double?, for dateIso: String? = nil) {
        let iso = dateIso ?? selectedDateIso
        if let q = quantity, q > 0 {
            var qMap = journalQuantitiesByDate[iso] ?? [:]
            qMap[habitId] = q
            journalQuantitiesByDate[iso] = qMap
            var cMap = journalCheckinsByDate[iso] ?? [:]
            cMap[habitId] = .yes
            journalCheckinsByDate[iso] = cMap
        } else {
            journalQuantitiesByDate[iso]?.removeValue(forKey: habitId)
            if journalQuantitiesByDate[iso]?.isEmpty == true {
                journalQuantitiesByDate.removeValue(forKey: iso)
            }
        }
        dataRevision += 1
        persistState()
    }

    /// Automatically populates Diario habits (`caffeine`, `alcohol`, `late_meal`, `added_sugar`, `dairy`) from logged meals without double entry.
    func syncAutoJournalHabits(for dateIso: String? = nil) {
        let iso = dateIso ?? selectedDateIso
        let meals = mealsByDate[iso] ?? []
        guard !meals.isEmpty else { return }

        var checkMap = journalCheckinsByDate[iso] ?? [:]
        var quantMap = journalQuantitiesByDate[iso] ?? [:]
        var timeMap = journalEventTimesByDate[iso] ?? [:]

        let timing = WhoopPhysiologyEngine.computeCaffeineAndMealTiming(
            meals: meals,
            bedtimeMinutesOfDay: computedSleepPlan.bedtimeHour * 60 + computedSleepPlan.bedtimeMinute
        )

        // 1. Caffeine auto-sync
        if timing.totalCaffeineTodayMg >= 25 {
            checkMap["caffeine"] = .yes
            quantMap["caffeine"] = timing.totalCaffeineTodayMg
            if let t = timing.lastCaffeineTimeLabel {
                timeMap["caffeine"] = t
            }
        }

        // 2. Alcohol auto-sync
        let totalAlc = meals.reduce(0.0) { $0 + ($1.alcoholDrinks ?? 0) }
        if totalAlc >= 0.5 {
            checkMap["alcohol"] = .yes
            quantMap["alcohol"] = totalAlc
            if let lastAlcMeal = meals.first(where: { ($0.alcoholDrinks ?? 0) > 0 }) {
                timeMap["alcohol"] = lastAlcMeal.timeLabel
            }
        }

        // 3. Late meal auto-sync (meal < 2.8h before bedtime or >= 20:45)
        if let gap = timing.hoursFromLastMealToBedtime, gap < 2.8, let lastT = timing.lastMealTimeLabel {
            checkMap["late_meal"] = .yes
            quantMap["late_meal"] = max(0.5, gap)
            timeMap["late_meal"] = lastT
        } else if let lastT = timing.lastMealTimeLabel,
                  let minDay = WhoopPhysiologyEngine.parseTimeLabelToMinutes(lastT),
                  minDay >= (20 * 60 + 45) {
            checkMap["late_meal"] = .yes
            quantMap["late_meal"] = timing.hoursFromLastMealToBedtime ?? 1.5
            timeMap["late_meal"] = lastT
        }

        // 4. Added sugar auto-sync
        let totalSugar = meals.reduce(0.0) { $0 + $1.effectiveSugarG }
        let hasExcessSugarFactor = meals.contains { ($0.qualityFactors?.excessSugar ?? 0) > 0 }
        if hasExcessSugarFactor || totalSugar >= 40 {
            checkMap["added_sugar"] = .yes
        }

        journalCheckinsByDate[iso] = checkMap
        if !quantMap.isEmpty { journalQuantitiesByDate[iso] = quantMap }
        if !timeMap.isEmpty { journalEventTimesByDate[iso] = timeMap }
    }

    var caffeineAndMealTimingToday: CaffeineAndMealTimingSnapshot {
        let iso = selectedDateIso
        let meals = mealsByDate[iso] ?? []
        let plan = computedSleepPlan
        let bedMin = plan.bedtimeHour * 60 + plan.bedtimeMinute
        let manCaff = journalQuantitiesByDate[iso]?["caffeine"] ?? (journalCheckinsByDate[iso]?["caffeine"] == .yes ? 120.0 : nil)
        let manTime = journalEventTimesByDate[iso]?["caffeine"]
        return WhoopPhysiologyEngine.computeCaffeineAndMealTiming(
            meals: meals,
            bedtimeMinutesOfDay: bedMin,
            manualCaffeineMg: manCaff,
            manualCaffeineTime: manTime
        )
    }

    // MARK: - Zero-Friction Nutrition: Repeat Yesterday, Recipes & Micronutrients (Apartado 1.5)

    var yesterdayMealsForSelectedDate: [NutritionMealItem] {
        let cal = Calendar.current
        guard let prevDate = cal.date(byAdding: .day, value: -1, to: selectedDate) else { return [] }
        let prevIso = isoFormatter.string(from: prevDate)
        return mealsByDate[prevIso] ?? []
    }

    @discardableResult
    func repeatYesterdayMeals(for targetDateIso: String? = nil) -> Int {
        let iso = targetDateIso ?? selectedDateIso
        let cal = Calendar.current
        let baseDate = isoFormatter.date(from: iso) ?? selectedDate
        guard let prevDate = cal.date(byAdding: .day, value: -1, to: baseDate) else { return 0 }
        let prevIso = isoFormatter.string(from: prevDate)
        let prevMeals = mealsByDate[prevIso] ?? []
        guard !prevMeals.isEmpty else { return 0 }

        var curList = mealsByDate[iso] ?? []
        for pm in prevMeals {
            var copy = pm
            copy = NutritionMealItem(
                id: UUID().uuidString,
                title: pm.title,
                timeLabel: pm.timeLabel,
                kcal: pm.kcal,
                proteinG: pm.proteinG,
                carbsG: pm.carbsG,
                fatG: pm.fatG,
                qualityScore: pm.qualityScore,
                caffeineMg: pm.caffeineMg,
                alcoholDrinks: pm.alcoholDrinks,
                calciumMg: pm.calciumMg,
                fiberG: pm.fiberG,
                sugarG: pm.sugarG,
                sodiumMg: pm.sodiumMg,
                potassiumMg: pm.potassiumMg,
                magnesiumMg: pm.magnesiumMg,
                ironMg: pm.ironMg,
                vitaminDMcg: pm.vitaminDMcg,
                omega3G: pm.omega3G,
                aiNotes: pm.aiNotes,
                photoFilename: nil,
                emoji: pm.emoji,
                qualityFactors: pm.qualityFactors,
                isFavorite: pm.isFavorite
            )
            curList.append(copy)
        }
        mealsByDate[iso] = curList
        syncAutoJournalHabits(for: iso)
        invalidateSectionCoachingCache(sections: [.hoy, .energia])
        dataRevision += 1
        persistState()
        return prevMeals.count
    }

    func saveNutritionRecipe(_ recipe: NutritionRecipeTemplate) {
        if let idx = nutritionRecipes.firstIndex(where: { $0.id == recipe.id }) {
            nutritionRecipes[idx] = recipe
        } else {
            nutritionRecipes.insert(recipe, at: 0)
        }
        // Mirror into savedFoodsLibrary so it appears in Favorites / Library tabs too
        let libItem = SavedFoodLibraryItem(
            id: "recipe_\(recipe.id)",
            kind: .recipe,
            emoji: recipe.emoji.isEmpty ? "🍲" : recipe.emoji,
            title: "\(recipe.title) (1/\(recipe.safeServings) ración)",
            kcal: recipe.kcalPerServing,
            proteinG: recipe.proteinPerServing,
            carbsG: recipe.carbsPerServing,
            fatG: recipe.fatPerServing,
            qualityScore: 88
        )
        savedFoodsLibrary.removeAll { $0.id == libItem.id }
        savedFoodsLibrary.insert(libItem, at: 0)
        persistState()
    }

    func deleteNutritionRecipe(id: String) {
        nutritionRecipes.removeAll { $0.id == id }
        savedFoodsLibrary.removeAll { $0.id == "recipe_\(id)" }
        persistState()
    }

    func logRecipeServing(_ recipe: NutritionRecipeTemplate, servingsCount: Double = 1.0, for dateIso: String? = nil) {
        let mult = max(servingsCount, 0.25)
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        let meal = NutritionMealItem(
            id: UUID().uuidString,
            title: "\(recipe.title) (\(String(format: "%.1f", locale: Locale(identifier: "es_ES"), mult)) rac.)",
            timeLabel: f.string(from: Date()),
            kcal: Int((Double(recipe.kcalPerServing) * mult).rounded()),
            proteinG: Int((Double(recipe.proteinPerServing) * mult).rounded()),
            carbsG: Int((Double(recipe.carbsPerServing) * mult).rounded()),
            fatG: Int((Double(recipe.fatPerServing) * mult).rounded()),
            qualityScore: 88,
            fiberG: AppleHealthExportImporter.round1(recipe.fiberPerServing * mult),
            emoji: recipe.emoji
        )
        saveMeal(meal, for: dateIso)
    }

    var dailyMicronutrientsSnapshot: [MicronutrientDailySnapshot] {
        let meals = mealsToday
        let fiber = meals.reduce(0.0) { $0 + $1.effectiveFiberG }
        let sugar = meals.reduce(0.0) { $0 + $1.effectiveSugarG }
        let sodium = meals.reduce(0.0) { $0 + $1.effectiveSodiumMg }
        let potassium = meals.reduce(0.0) { $0 + $1.effectivePotassiumMg }
        let magnesium = meals.reduce(0.0) { $0 + $1.effectiveMagnesiumMg }
        let iron = meals.reduce(0.0) { $0 + $1.effectiveIronMg }
        let vitD = meals.reduce(0.0) { $0 + $1.effectiveVitaminDMcg }
        let omega3 = meals.reduce(0.0) { $0 + $1.effectiveOmega3G }
        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: userProfile)

        return [
            MicronutrientDailySnapshot(id: "micro_fiber", name: "Fibra dietética", unit: "g", currentValue: AppleHealthExportImporter.round1(fiber), targetValue: Double(norms.fiberGoalG), isUpperLimit: false, icon: "leaf.fill", accentHex: 0x34D399),
            MicronutrientDailySnapshot(id: "micro_sugar", name: "Azúcar", unit: "g", currentValue: AppleHealthExportImporter.round1(sugar), targetValue: 36.0, isUpperLimit: true, icon: "cube.fill", accentHex: 0xF97316),
            MicronutrientDailySnapshot(id: "micro_sodium", name: "Sodio", unit: "mg", currentValue: sodium.rounded(), targetValue: 2300.0, isUpperLimit: true, icon: "drop.triangle.fill", accentHex: 0xF59E0B),
            MicronutrientDailySnapshot(id: "micro_potassium", name: "Potasio", unit: "mg", currentValue: potassium.rounded(), targetValue: 3500.0, isUpperLimit: false, icon: "bolt.fill", accentHex: 0x38BDF8),
            MicronutrientDailySnapshot(id: "micro_magnesium", name: "Magnesio", unit: "mg", currentValue: magnesium.rounded(), targetValue: userProfile.sex == .female ? 320.0 : 400.0, isUpperLimit: false, icon: "sparkles", accentHex: 0x818CF8),
            MicronutrientDailySnapshot(id: "micro_iron", name: "Hierro", unit: "mg", currentValue: AppleHealthExportImporter.round1(iron), targetValue: userProfile.sex == .female ? 18.0 : 10.0, isUpperLimit: false, icon: "cross.vial.fill", accentHex: 0xFB7185),
            MicronutrientDailySnapshot(id: "micro_vitd", name: "Vitamina D", unit: "mcg", currentValue: AppleHealthExportImporter.round1(vitD), targetValue: 15.0, isUpperLimit: false, icon: "sun.max.fill", accentHex: 0xFBBF24),
            MicronutrientDailySnapshot(id: "micro_omega3", name: "Omega-3 (EPA/DHA)", unit: "g", currentValue: AppleHealthExportImporter.round1(omega3), targetValue: 1.6, isUpperLimit: false, icon: "fish.fill", accentHex: 0x2DD4BF)
        ]
    }

    var unifiedCausalInsights: [UnifiedCausalInsight] {
        WhoopPhysiologyEngine.computeUnifiedCausalInsights(
            history: activeHistory,
            mealsByDate: mealsByDate,
            strengthLogs: strengthLogs,
            labReports: labReports,
            profile: userProfile
        )
    }

    // MARK: - Pharmacokinetic Caffeine Window & Quick Beverage Logging

    var caffeineWindowSnapshot: CaffeineWindowTimelineSnapshot {
        let iso = selectedDateIso
        let meals = mealsByDate[iso] ?? []
        let plan = computedSleepPlan

        // Derive real wake time from last sleep session end time or smart alarm hour/minute
        let wakeMin: Int = {
            if let endLbl = currentDaySummary?.sleepSession?.endTimeLabel,
               let parsed = WhoopPhysiologyEngine.parseTimeLabelToMinutes(endLbl) {
                return parsed
            }
            return notificationSettings.smartAlarmHour * 60 + notificationSettings.smartAlarmMinute
        }()
        let bedMin = plan.bedtimeHour * 60 + plan.bedtimeMinute
        let cal = Calendar.current
        let nowComps = cal.dateComponents([.hour, .minute], from: Date())
        let nowMin = (nowComps.hour ?? 12) * 60 + (nowComps.minute ?? 0)
        let manCaff = journalQuantitiesByDate[iso]?["caffeine"] ?? (journalCheckinsByDate[iso]?["caffeine"] == .yes ? 95.0 : nil)
        let manTime = journalEventTimesByDate[iso]?["caffeine"]

        return WhoopPhysiologyEngine.computeCaffeineWindowTimeline(
            meals: meals,
            wakeMinuteOfDay: wakeMin,
            bedtimeMinuteOfDay: bedMin,
            nowMinuteOfDay: nowMin,
            manualCaffeineMg: manCaff,
            manualCaffeineTime: manTime
        )
    }

    func logQuickCaffeineDrink(title: String, mg: Double, emoji: String = "☕", timeLabel: String? = nil, for dateIso: String? = nil) {
        guard mg > 0 else { return }
        let iso = dateIso ?? selectedDateIso
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        let stamp = (timeLabel?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? timeLabel! : f.string(from: Date())
        let meal = NutritionMealItem(
            id: UUID().uuidString,
            title: title,
            timeLabel: stamp,
            kcal: 0,
            proteinG: 0,
            carbsG: 0,
            fatG: 0,
            qualityScore: 80,
            caffeineMg: mg,
            emoji: emoji
        )
        saveMeal(meal, for: iso)
    }

    func deleteCaffeineIntake(id: String, for dateIso: String? = nil) {
        let iso = dateIso ?? selectedDateIso
        if id == "manual_caffeine" {
            setJournalCheck(habitId: "caffeine", state: .unset, for: iso)
        } else {
            deleteMeal(id: id, for: iso, deletePhotoFromDisk: false)
        }
    }

}

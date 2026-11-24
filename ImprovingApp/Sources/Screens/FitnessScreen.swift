import SwiftUI

struct FitnessScreen: View {
    @ObservedObject var store: ImprovingStore
    let onNavigate: (OverlayRoute) -> Void
    let onOpenTrainingLoad: (TrainingLoadTab) -> Void
    let onOpenCardioMetric: (CardioMetricRoute) -> Void
    var onOpenWorkout: ((EffortEventItem) -> Void)? = nil

    @State private var showWorkoutLoggerSheet: Bool = false
    @State private var showCalendarSheet: Bool = false
    @State private var showRoutinesLibrarySheet: Bool = false
    @State private var showPinEditorSheet: Bool = false
    @State private var activeRoutineToRun: WorkoutRoutineTemplate? = nil

    private func formatHMS(_ totalMinutes: Int) -> String {
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        return String(format: "%d:%02d:00", h, m)
    }

    private func formatZoneDuration(_ mins: Int) -> String {
        if mins >= 60 {
            return "\(mins / 60) h \(mins % 60) min"
        }
        return "\(mins) min"
    }

    var body: some View {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let stripOffsets = [-3, -2, -1, 0, 1, 2, 3]
        let wdFmt: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "es_ES")
            f.dateFormat = "EEEEE"
            return f
        }()

        // 1. Real 30-day current & previous period cumulative series (Zero Fabricated Numbers!)
        let last60 = store.trailingCalendarSummaries(days: 62)
        let prev31 = Array(last60.prefix(31))
        let cur31 = Array(last60.suffix(31))

        let dailyDurCur = cur31.map { Double(($0.summary?.workouts ?? []).reduce(0) { $0 + $1.durationMin }) }
        let dailyDurPrev = prev31.map { Double(($0.summary?.workouts ?? []).reduce(0) { $0 + $1.durationMin }) }
        var runDurCur = 0.0
        let cumDurCur = dailyDurCur.map { runDurCur += $0; return runDurCur }
        var runDurPrev = 0.0
        let cumDurPrev = dailyDurPrev.map { runDurPrev += $0; return runDurPrev }
        let totalDurMin30 = Int(runDurCur.rounded())

        let dailyKcalCur = cur31.map { Double(($0.summary?.workouts ?? []).reduce(0) { $0 + $1.kcal }) }
        let dailyKcalPrev = prev31.map { Double(($0.summary?.workouts ?? []).reduce(0) { $0 + $1.kcal }) }
        var runKcalCur = 0.0
        let cumKcalCur = dailyKcalCur.map { runKcalCur += $0; return runKcalCur }
        var runKcalPrev = 0.0
        let cumKcalPrev = dailyKcalPrev.map { runKcalPrev += $0; return runKcalPrev }
        let totalKcal30 = Int(runKcalCur.rounded())

        // 2. Real EWMA Cardio & Muscular Training Load
        let cardioLoad = store.trainingLoadAnalysis(tab: .cardio, spanDays: 31, windowPageOffset: 0)
        let muscularLoad = store.trainingLoadAnalysis(tab: .muscular, spanDays: 31, windowPageOffset: 0)

        // 3. VO₂ máx. & HRR with age/sex standardized evaluations & real 30-day sparklines
        let vo2Record = store.latestVo2MaxRecord
        let vo2Eval = vo2Record.map { WhoopPhysiologyEngine.standardizeVo2Max($0.value, profile: store.userProfile) }
        let vo2Points30 = cur31.map { $0.summary?.vo2MaxMlKgMin }

        let hrrRecord = store.latestHrRecoveryRecord
        let hrrEval = hrrRecord.map { WhoopPhysiologyEngine.standardizeHrRecovery($0.value, profile: store.userProfile) }
        let hrrPoints30 = cur31.map { $0.summary?.hrRecoveryBpm }

        // 4. 30-day Cardio Focus & 6-Zone HR Totals (Z0..Z5)
        let z0Sum = cur31.reduce(0) { $0 + ($1.summary?.hrZone0Minutes ?? 0) }
        let z15Sums: [Int] = (0..<5).map { zIdx in
            cur31.reduce(0) { acc, item in
                let arr = item.summary?.hrZoneMinutes ?? []
                return acc + (zIdx < arr.count ? arr[zIdx] : 0)
            }
        }
        let zones6 = [z0Sum] + z15Sums
        let totalZoneMin30 = zones6.reduce(0, +)
        let topZoneIdx = zones6.enumerated().max(by: { $0.element < $1.element })?.offset ?? 1
        let lowAeroMin = zones6[0] + zones6[1] + zones6[2]
        let highAeroMin = zones6[3] + zones6[4]
        let anaeroMin = zones6[5]
        let lowAeroPct = totalZoneMin30 > 0 ? Int((Double(lowAeroMin) / Double(totalZoneMin30) * 100.0).rounded()) : 0
        let highAeroPct = totalZoneMin30 > 0 ? Int((Double(highAeroMin) / Double(totalZoneMin30) * 100.0).rounded()) : 0
        let anaeroPct = totalZoneMin30 > 0 ? max(0, 100 - lowAeroPct - highAeroPct) : 0
        let dominantFocusTitle: String = {
            if totalZoneMin30 == 0 { return "Sin datos" }
            if lowAeroPct >= highAeroPct && lowAeroPct >= anaeroPct { return "Aeróbico bajo" }
            if highAeroPct >= anaeroPct { return "Aeróbico alto" }
            return "Anaeróbico"
        }()
        let dominantFocusPct = max(lowAeroPct, max(highAeroPct, anaeroPct))

        // 5. Real 30-day Strength Totals (logged sets + HealthKit strength sessions!)
        let cur31Isos = Set(cur31.map(\.iso))
        let setsByDay = Dictionary(grouping: store.strengthLogs.filter { $0.completed && cur31Isos.contains($0.dateIso) }, by: \.dateIso)
        let dailySetsCur: [Double] = cur31.map { item in
            let logged = setsByDay[item.iso]?.count ?? 0
            let wkSets = (item.summary?.workouts ?? []).compactMap(\.totalSets).reduce(0, +)
            return Double(max(logged, wkSets))
        }
        let dailyVolCur: [Double] = cur31.map { item in
            let logged = (setsByDay[item.iso] ?? []).reduce(0.0) { $0 + Double($1.reps) * $1.weightKg }
            let wkVol = (item.summary?.workouts ?? []).compactMap(\.totalVolumeKg).reduce(0, +)
            return max(logged, wkVol)
        }
        var runSets = 0.0
        let cumSetsCur = dailySetsCur.map { runSets += $0; return runSets }
        var runVol = 0.0
        let cumVolCur = dailyVolCur.map { runVol += $0; return runVol }
        let totalSets30 = Int(runSets.rounded())
        let totalVolKg30 = Int(runVol.rounded())

        let muscleSnaps = store.muscleGroupSnapshots()
        let recoveredMusclesCount = muscleSnaps.filter { $0.state == .recovered }.count
        let fatiguedMusclesCount = muscleSnaps.filter { $0.state == .fatigued || $0.state == .exhausted }.count

        let pinnedRoutines = store.workoutRoutines.filter(\.isPinned)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 1. Warm Bronze Atmospheric Top Bar + 7-Day Workout Strip
                ZStack(alignment: .top) {
                    LinearGradient(
                        colors: BevelColors.isDarkMode ? [Color(hex: 0x38271B), Color(hex: 0x1E1B1A), BevelColors.canvas] : [BevelColors.canvas, BevelColors.canvas],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 198)
                    .ignoresSafeArea(edges: .top)

                    VStack(spacing: 16) {
                        HStack {
                            Button { showCalendarSheet = true } label: {
                                Image(systemName: "calendar.badge.clock")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .frame(width: 40, height: 40)
                                    .background(Circle().fill(BevelColors.glassChromeFill))
                                    .overlay(Circle().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.8))
                            }
                            Spacer()
                            Text("Fitness")
                                .font(ImprovingFont.sectionTitle(18.5))
                                .foregroundColor(BevelColors.textPrimary)
                            Spacer()
                            Menu {
                                Button("Registrar entrenamiento", systemImage: "plus.circle") { showWorkoutLoggerSheet = true }
                                Button("Gestionar rutinas", systemImage: "list.bullet.rectangle") { showRoutinesLibrarySheet = true }
                                Button("Grupos musculares", systemImage: "figure.strengthtraining.traditional") { onOpenCardioMetric(.muscleGroups) }
                                Button("Sincronizar Atajos / Salud", systemImage: "arrow.triangle.2.circlepath") {
                                    store.scanAutoSyncInboxIfNeeded(force: true, showBanner: true)
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .frame(width: 40, height: 40)
                                    .background(Circle().fill(BevelColors.glassChromeFill))
                                    .overlay(Circle().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.8))
                            }
                        }

                        HStack(spacing: 6) {
                            ForEach(stripOffsets, id: \.self) { offset in
                                let dt = cal.date(byAdding: .day, value: offset, to: todayStart) ?? todayStart
                                let pastOffset = max(0, -offset)
                                let isFuture = offset > 0
                                let isToday = offset == 0
                                let isSelected = !isFuture && (pastOffset == store.dayOffset)
                                let dayNum = cal.component(.day, from: dt)
                                let letter = wdFmt.string(from: dt).uppercased()
                                let iso = store.isoFormatter.string(from: dt)
                                let dayWorkouts = store.activeHistory[iso]?.workouts ?? []
                                let primaryWorkout = dayWorkouts.max(by: { $0.durationMin < $1.durationMin })
                                let hasWorkout = primaryWorkout != nil
                                let sportStyle = primaryWorkout.map { WorkoutSportStyle.resolve(title: $0.title, category: $0.categoryLabel) }

                                Button {
                                    if !isFuture { store.selectDayOffset(pastOffset) }
                                } label: {
                                    VStack(spacing: 4) {
                                        if isToday {
                                            Image(systemName: "arrowtriangle.down.fill")
                                                .font(.system(size: 7))
                                                .foregroundColor(BevelColors.orangeEnd)
                                        } else {
                                            Spacer().frame(height: 7)
                                        }

                                        VStack(spacing: 6) {
                                            Text(letter)
                                                .font(ImprovingFont.caption(11))
                                                .foregroundColor(BevelColors.textMuted)
                                            Text("\(dayNum)")
                                                .font(ImprovingFont.cardTitle(14.5))
                                                .foregroundColor(isToday ? BevelColors.skyBlue : (isFuture ? BevelColors.textMuted : BevelColors.textPrimary))

                                            ZStack {
                                                Circle()
                                                    .fill(sportStyle?.bg ?? Color.white.opacity(0.05))
                                                    .frame(width: 30, height: 30)
                                                if let st = sportStyle, hasWorkout {
                                                    Image(systemName: st.icon)
                                                        .font(.system(size: 13, weight: .bold))
                                                        .foregroundColor(st.fg)
                                                } else {
                                                    Image(systemName: "zzz")
                                                        .font(.system(size: 12, weight: .semibold))
                                                        .foregroundColor(BevelColors.textMuted)
                                                }
                                            }
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(
                                            Capsule(style: .continuous)
                                                .fill(isSelected ? BevelColors.card : BevelColors.card.opacity(0.55))
                                        )
                                        .overlay(
                                            Capsule(style: .continuous)
                                                .strokeBorder(isSelected ? Color.white.opacity(0.18) : BevelColors.cardBorder, lineWidth: 0.8)
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }

                VStack(alignment: .leading, spacing: 22) {
                    // 2. 4-Hour Time-Aware Fitness-Focused Live AI Coaching Card
                    LiveAiCoachingCard(
                        section: .fitness,
                        store: store,
                        onAskMore: { onNavigate(.askBevel) }
                    )

                    // 3. Actividad de hoy (Exact match to Screenshot 1!)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Text(store.dayOffset == 0 ? "Actividad de hoy" : "Actividad · \(store.dateLabel)")
                                .font(ImprovingFont.sectionTitle(18))
                                .foregroundColor(BevelColors.textPrimary)
                            Spacer()
                            if let kcal = store.currentDaySummary?.activeKcal, kcal > 0 {
                                HStack(spacing: 5) {
                                    Image(systemName: "flame.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(BevelColors.orangeEnd)
                                    Text("\(kcal) kcal")
                                        .font(ImprovingFont.caption(12))
                                        .fontWeight(.semibold)
                                        .monospacedDigit()
                                        .foregroundColor(BevelColors.textPrimary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(BevelColors.card))
                                .overlay(Capsule().strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
                            }
                            Button { showWorkoutLoggerSheet = true } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(BevelColors.card))
                                    .overlay(Circle().strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
                            }
                        }

                        if !store.workoutsToday.isEmpty {
                            ForEach(store.workoutsToday) { w in
                                Button {
                                    if let onOpenWorkout {
                                        onOpenWorkout(w)
                                    } else {
                                        onOpenCardioMetric(.activitiesDuration)
                                    }
                                } label: {
                                    FitnessActivityHistoryRow(workout: w, dateLabelOverride: w.timeRange)
                                }
                                .buttonStyle(.plain)
                            }
                        } else {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.06))
                                        .frame(width: 42, height: 42)
                                    Image(systemName: "zzz")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(BevelColors.textSecondary)
                                }
                                Text("Día de descanso")
                                    .font(ImprovingFont.cardTitle(15))
                                    .foregroundColor(BevelColors.textSecondary)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 20)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(BevelColors.card.opacity(0.45)))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                                    .foregroundColor(Color.white.opacity(0.12))
                            )
                        }
                    }

                    // 4. Rutinas (Exact match to Screenshot 1: Editar anclas + Ver todo > + Pinned Routines!)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Text("Rutinas")
                                .font(ImprovingFont.sectionTitle(18))
                                .foregroundColor(BevelColors.textPrimary)
                            Spacer()
                            Button { showPinEditorSheet = true } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(BevelColors.card))
                                    .overlay(Circle().strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
                            }
                            Button { showRoutinesLibrarySheet = true } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(BevelColors.card))
                                    .overlay(Circle().strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
                            }
                        }

                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(pinnedRoutines.prefix(4)) { r in
                                Button {
                                    activeRoutineToRun = r
                                } label: {
                                    BevelCard(cornerRadius: 20) {
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                Image(systemName: r.iconName)
                                                    .font(.system(size: 16, weight: .semibold))
                                                    .foregroundColor(BevelColors.amberStart)
                                                    .frame(width: 34, height: 34)
                                                    .background(Circle().fill(BevelColors.amberSoftBg))
                                                Spacer()
                                                Image(systemName: "play.fill")
                                                    .font(.system(size: 11))
                                                    .foregroundColor(BevelColors.textMuted)
                                            }
                                            Spacer(minLength: 8)
                                            Text(r.name)
                                                .font(ImprovingFont.cardTitle(14.5))
                                                .foregroundColor(BevelColors.textPrimary)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                            Text("\(r.exercises.count) ejercicios · \(r.category)")
                                                .font(ImprovingFont.caption(11.5))
                                                .foregroundColor(BevelColors.textSecondary)
                                        }
                                        .padding(14)
                                        .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
                                    }
                                }
                            }

                            Button { showPinEditorSheet = true } label: {
                                VStack(spacing: 10) {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(BevelColors.textSecondary)
                                        .frame(width: 36, height: 36)
                                        .background(Circle().fill(Color.white.opacity(0.07)))
                                    Text("Editar anclas")
                                        .font(ImprovingFont.cardTitle(14.5))
                                        .foregroundColor(BevelColors.textPrimary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 136)
                                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(BevelColors.card.opacity(0.45)))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                                        .foregroundColor(Color.white.opacity(0.14))
                                )
                            }

                            Button { showRoutinesLibrarySheet = true } label: {
                                BevelCard(cornerRadius: 20) {
                                    HStack(spacing: 6) {
                                        Text("Ver todo")
                                            .font(ImprovingFont.cardTitle(15))
                                            .foregroundColor(BevelColors.textPrimary)
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(BevelColors.textPrimary)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 136)
                                }
                            }
                        }
                    }

                    // 5. Carga de entrenamiento (Exact match to Screenshot 1!)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Carga de entrenamiento")
                            .font(ImprovingFont.sectionTitle(18))
                            .foregroundColor(BevelColors.textPrimary)

                        HStack(spacing: 12) {
                            trainingLoadTile(analysis: cardioLoad, title: "Cardio") {
                                onOpenTrainingLoad(.cardio)
                            }
                            trainingLoadTile(analysis: muscularLoad, title: "Muscular") {
                                onOpenTrainingLoad(.muscular)
                            }
                        }
                    }

                    // 6. Cardio 2x3 Visual Sparkline & Bar Grid (Exact match to Screenshot 2!)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Cardio")
                                .font(ImprovingFont.sectionTitle(18))
                                .foregroundColor(BevelColors.textPrimary)
                            Spacer()
                            Button("Editar") { onOpenCardioMetric(.activitiesDuration) }
                                .font(ImprovingFont.caption(13.5))
                                .underline()
                                .foregroundColor(BevelColors.textSecondary)
                        }

                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            // Tile 1: Todas las actividades (Duración)
                            Button { onOpenCardioMetric(.activitiesDuration) } label: {
                                BevelCard(cornerRadius: 20) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        tileHeader("Todas las actividades")
                                        Text(totalDurMin30 > 0 ? formatHMS(totalDurMin30) : "--")
                                            .font(ImprovingFont.metricTile(20))
                                            .monospacedDigit()
                                            .foregroundColor(totalDurMin30 > 0 ? BevelColors.textPrimary : BevelColors.textMuted)
                                            .lineLimit(1)
                                        Text("Duración de la actividad")
                                            .font(ImprovingFont.caption(11.5))
                                            .foregroundColor(BevelColors.textSecondary)
                                            .lineLimit(1)
                                        Spacer(minLength: 4)
                                        MiniFitnessStepSparkline(
                                            currentSeries: cumDurCur,
                                            previousSeries: cumDurPrev,
                                            accentStart: Color(hex: 0x3CC8E8),
                                            accentEnd: BevelColors.cyanBright
                                        )
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 138, alignment: .leading)
                                    .padding(14)
                                }
                            }

                            // Tile 2: Todas las actividades (Energía)
                            Button { onOpenCardioMetric(.activitiesEnergy) } label: {
                                BevelCard(cornerRadius: 20) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        tileHeader("Todas las actividades")
                                        Text(totalKcal30 > 0 ? "\(totalKcal30) kcal" : "--")
                                            .font(ImprovingFont.metricTile(20))
                                            .monospacedDigit()
                                            .foregroundColor(totalKcal30 > 0 ? BevelColors.textPrimary : BevelColors.textMuted)
                                            .lineLimit(1)
                                        Text("Energía en actividad")
                                            .font(ImprovingFont.caption(11.5))
                                            .foregroundColor(BevelColors.textSecondary)
                                            .lineLimit(1)
                                        Spacer(minLength: 4)
                                        MiniFitnessStepSparkline(
                                            currentSeries: cumKcalCur,
                                            previousSeries: cumKcalPrev,
                                            accentStart: Color(hex: 0x3CC8E8),
                                            accentEnd: BevelColors.cyanBright
                                        )
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 138, alignment: .leading)
                                    .padding(14)
                                }
                            }

                            // Tile 3: VO₂ máx.
                            Button { onOpenCardioMetric(.vo2Max) } label: {
                                BevelCard(cornerRadius: 20) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        tileHeader("VO₂ máx.")
                                        Text(vo2Record.map { String(format: "%.1f", locale: Locale(identifier: "es_ES"), $0.value) } ?? "--")
                                            .font(ImprovingFont.metricTile(21))
                                            .monospacedDigit()
                                            .foregroundColor(vo2Record != nil ? BevelColors.textPrimary : BevelColors.textMuted)
                                        Text(vo2Eval?.categoryTitle ?? "Sin datos")
                                            .font(ImprovingFont.caption(12))
                                            .fontWeight(.semibold)
                                            .foregroundColor(vo2Eval?.activeColor ?? BevelColors.textMuted)
                                        Spacer(minLength: 4)
                                        TrendSparklineWithBand(
                                            optionalPoints: vo2Points30,
                                            lineColor: vo2Eval?.activeColor ?? BevelColors.amberStart,
                                            fillUnder: true,
                                            showBand: false,
                                            showGlowDot: true
                                        )
                                        .frame(height: 44)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 138, alignment: .leading)
                                    .padding(14)
                                }
                            }

                            // Tile 4: Recuperación de FC
                            Button { onOpenCardioMetric(.hrRecovery) } label: {
                                BevelCard(cornerRadius: 20) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        tileHeader("Recuperación de FC")
                                        Text(hrrRecord.map { "\(Int($0.value.rounded())) ppm" } ?? "--")
                                            .font(ImprovingFont.metricTile(21))
                                            .monospacedDigit()
                                            .foregroundColor(hrrRecord != nil ? BevelColors.textPrimary : BevelColors.textMuted)
                                        Text(hrrEval?.categoryTitle ?? "Sin datos")
                                            .font(ImprovingFont.caption(12))
                                            .fontWeight(.semibold)
                                            .foregroundColor(hrrEval?.activeColor ?? BevelColors.textMuted)
                                        Spacer(minLength: 4)
                                        TrendSparklineWithBand(
                                            optionalPoints: hrrPoints30,
                                            lineColor: hrrEval?.activeColor ?? BevelColors.amberStart,
                                            fillUnder: true,
                                            showBand: false,
                                            showGlowDot: true
                                        )
                                        .frame(height: 44)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 138, alignment: .leading)
                                    .padding(14)
                                }
                            }

                            // Tile 5: Foco cardiovascular
                            Button { onOpenCardioMetric(.cardioFocus) } label: {
                                BevelCard(cornerRadius: 20) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        tileHeader("Foco cardiovascular")
                                        Text(totalZoneMin30 > 0 ? "\(dominantFocusPct) %" : "--")
                                            .font(ImprovingFont.metricTile(21))
                                            .monospacedDigit()
                                            .foregroundColor(totalZoneMin30 > 0 ? BevelColors.textPrimary : BevelColors.textMuted)
                                        Text(dominantFocusTitle)
                                            .font(ImprovingFont.caption(12))
                                            .fontWeight(.semibold)
                                            .foregroundColor(totalZoneMin30 > 0 ? Color(hex: 0x7CECE2) : BevelColors.textMuted)
                                            .lineLimit(1)
                                        Spacer(minLength: 4)
                                        MiniCardioFocusBars(lowPct: lowAeroPct, highPct: highAeroPct, anaeroPct: anaeroPct)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 138, alignment: .leading)
                                    .padding(14)
                                }
                            }

                            // Tile 6: Zonas de frecuencia cardíaca
                            Button { onOpenCardioMetric(.hrZones) } label: {
                                BevelCard(cornerRadius: 20) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        tileHeader("Zonas de frecuencia")
                                        Text(totalZoneMin30 > 0 ? "Zona \(topZoneIdx)" : "--")
                                            .font(ImprovingFont.metricTile(20))
                                            .foregroundColor(totalZoneMin30 > 0 ? BevelColors.textPrimary : BevelColors.textMuted)
                                        Text(totalZoneMin30 > 0 ? formatZoneDuration(zones6[topZoneIdx]) : "Sin datos")
                                            .font(ImprovingFont.caption(12))
                                            .fontWeight(.semibold)
                                            .foregroundColor(totalZoneMin30 > 0 ? HrZonesSixBarChart.zoneColors[topZoneIdx] : BevelColors.textMuted)
                                        Spacer(minLength: 4)
                                        MiniHrZonesHistogram(minutes6: zones6)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 138, alignment: .leading)
                                    .padding(14)
                                }
                            }
                        }
                    }

                    // 7. Fuerza (Exact match to Screenshot 2 + Anatomical Muscle Groups entry!)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Fuerza")
                                .font(ImprovingFont.sectionTitle(18))
                                .foregroundColor(BevelColors.textPrimary)
                            Spacer()
                            Button("Editar") { showWorkoutLoggerSheet = true }
                                .font(ImprovingFont.caption(13.5))
                                .underline()
                                .foregroundColor(BevelColors.textSecondary)
                        }

                        HStack(spacing: 12) {
                            Button { onOpenCardioMetric(.strengthSets) } label: {
                                BevelCard(cornerRadius: 20) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        tileHeader("Todos los músculos")
                                        Text(totalSets30 > 0 ? "\(totalSets30)" : "0")
                                            .font(ImprovingFont.metricTile(21))
                                            .monospacedDigit()
                                            .foregroundColor(BevelColors.textPrimary)
                                        Text("Total series")
                                            .font(ImprovingFont.caption(11.5))
                                            .foregroundColor(BevelColors.textSecondary)
                                        Spacer(minLength: 4)
                                        MiniFitnessStepSparkline(
                                            currentSeries: cumSetsCur,
                                            previousSeries: Array(repeating: 0, count: cumSetsCur.count),
                                            accentStart: Color(hex: 0xF07A5B),
                                            accentEnd: BevelColors.strengthPink
                                        )
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 138, alignment: .leading)
                                    .padding(14)
                                }
                            }

                            Button { onOpenCardioMetric(.strengthVolume) } label: {
                                BevelCard(cornerRadius: 20) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        tileHeader("Todos los músculos")
                                        Text("\(totalVolKg30) kg")
                                            .font(ImprovingFont.metricTile(20))
                                            .monospacedDigit()
                                            .foregroundColor(BevelColors.textPrimary)
                                        Text("Volumen total")
                                            .font(ImprovingFont.caption(11.5))
                                            .foregroundColor(BevelColors.textSecondary)
                                        Spacer(minLength: 4)
                                        MiniFitnessStepSparkline(
                                            currentSeries: cumVolCur,
                                            previousSeries: Array(repeating: 0, count: cumVolCur.count),
                                            accentStart: Color(hex: 0xF07A5B),
                                            accentEnd: BevelColors.strengthPink
                                        )
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 138, alignment: .leading)
                                    .padding(14)
                                }
                            }
                        }

                        // Grupos musculares anatomical freshness card (Screenshots 29-33!)
                        Button { onOpenCardioMetric(.muscleGroups) } label: {
                            BevelCard(cornerRadius: 20) {
                                HStack(spacing: 14) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text("Grupos musculares")
                                                .font(ImprovingFont.cardTitle(15))
                                                .foregroundColor(BevelColors.textPrimary)
                                            Spacer()
                                            Image(systemName: "arrow.right")
                                                .font(.system(size: 12))
                                                .foregroundColor(BevelColors.textMuted)
                                        }
                                        Text("Frescura y carga muscular")
                                            .font(ImprovingFont.caption(12))
                                            .foregroundColor(BevelColors.textSecondary)
                                        HStack(spacing: 8) {
                                            StatusDotPill(text: "\(recoveredMusclesCount) listos", dotColor: BevelColors.greenPrimary)
                                            if fatiguedMusclesCount > 0 {
                                                StatusDotPill(text: "\(fatiguedMusclesCount) fatigados", dotColor: BevelColors.amberStart)
                                            }
                                        }
                                        .padding(.top, 2)
                                    }

                                    AnatomicalMuscleMapCanvas(
                                        snapshots: muscleSnaps,
                                        filterState: nil,
                                        compact: true
                                    )
                                    .frame(width: 96, height: 92)
                                }
                                .padding(14)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 155)
        }
        .background(BevelColors.canvas)
        .sheet(isPresented: $showCalendarSheet) {
            DatePickerSheetView(
                selectedDate: Binding(
                    get: { store.selectedDate },
                    set: { d in store.selectDate(d); showCalendarSheet = false }
                ),
                onJumpToday: { store.selectDayOffset(0); showCalendarSheet = false },
                onClose: { showCalendarSheet = false }
            )
        }
        .sheet(isPresented: $showWorkoutLoggerSheet) {
            StrengthSessionLoggerSheet(store: store, routine: nil) {
                showWorkoutLoggerSheet = false
            }
        }
        .sheet(item: $activeRoutineToRun) { r in
            StrengthSessionLoggerSheet(store: store, routine: r) {
                activeRoutineToRun = nil
            }
        }
        .sheet(isPresented: $showRoutinesLibrarySheet) {
            RoutinesLibrarySheet(store: store, onStartRoutine: { r in
                showRoutinesLibrarySheet = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    activeRoutineToRun = r
                }
            }, onClose: { showRoutinesLibrarySheet = false })
        }
        .sheet(isPresented: $showPinEditorSheet) {
            RoutinePinsEditorSheet(store: store) { showPinEditorSheet = false }
        }
    }

    private func trainingLoadTile(analysis: TrainingLoadAnalysis, title: String, action: @escaping () -> Void) -> some View {
        let maxG = max(Double(analysis.gaugeMax), 1.0)
        return Button(action: action) {
            BevelCard(cornerRadius: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(title).font(ImprovingFont.cardTitle(14.5)).foregroundColor(BevelColors.textPrimary)
                        Spacer()
                        Image(systemName: "arrow.right").font(.system(size: 12)).foregroundColor(BevelColors.textMuted)
                    }
                    Text(analysis.hasAnyData ? analysis.currentState.rawValue : "Calibrando")
                        .font(ImprovingFont.sectionTitle(16))
                        .foregroundColor(analysis.hasAnyData ? analysis.currentState.accentColor : BevelColors.textSecondary)
                        .lineLimit(1)
                    TrainingLoadTickGauge(
                        value: analysis.currentLoad,
                        minVal: 0,
                        maxVal: analysis.gaugeMax,
                        optimalStartFrac: Double(analysis.optimalLow) / maxG,
                        optimalEndFrac: Double(analysis.optimalHigh) / maxG,
                        currentFrac: Double(analysis.currentLoad) / maxG,
                        optimalRangeLabel: analysis.hasAnyData ? "Óptimo: \(analysis.optimalLow)-\(analysis.optimalHigh)" : "Calibrando base",
                        hasData: analysis.hasAnyData
                    )
                }
                .padding(14)
            }
        }
    }

    private func tileHeader(_ title: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(ImprovingFont.cardTitle(13.5))
                .foregroundColor(BevelColors.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 2)
            Image(systemName: "arrow.right")
                .font(.system(size: 11))
                .foregroundColor(BevelColors.textMuted)
        }
    }
}

// MARK: - Shared Activity History Row (Exact Match to Screenshots 10, 11, 26, 27!)

struct FitnessActivityHistoryRow: View {
    let workout: EffortEventItem
    var dateLabelOverride: String? = nil

    private var sportStyle: (icon: String, fg: Color, bg: Color) {
        let s = WorkoutSportStyle.resolve(title: workout.title, category: workout.categoryLabel)
        return (s.icon, s.fg, s.bg)
    }

    private var formattedTimestamp: String {
        if let override = dateLabelOverride { return override }
        let startTime = workout.timeRange.split(separator: "-").first?.trimmingCharacters(in: .whitespaces) ?? workout.timeRange
        if let iso = workout.dateIso {
            let inFmt = DateFormatter()
            inFmt.locale = Locale(identifier: "en_US_POSIX")
            inFmt.dateFormat = "yyyy-MM-dd"
            if let dt = inFmt.date(from: iso) {
                let outFmt = DateFormatter()
                outFmt.locale = Locale(identifier: "es_ES")
                outFmt.dateFormat = "d MMM"
                let dStr = outFmt.string(from: dt).replacingOccurrences(of: ".", with: "")
                return "\(dStr), \(startTime)"
            }
        }
        return startTime
    }

    var body: some View {
        let st = sportStyle
        BevelCard(cornerRadius: 18) {
            HStack(spacing: 13) {
                ZStack {
                    Circle().fill(st.bg).frame(width: 44, height: 44)
                    Image(systemName: st.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(st.fg)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(formattedTimestamp)
                        .font(ImprovingFont.caption(12))
                        .foregroundColor(BevelColors.textMuted)
                    Text(workout.title)
                        .font(ImprovingFont.cardTitle(15))
                        .foregroundColor(BevelColors.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Image(systemName: "circle.dashed")
                                .font(.system(size: 11))
                            Text("\(workout.strainPct)%")
                                .monospacedDigit()
                        }
                        if let km = workout.distanceKm, km > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                                    .font(.system(size: 11))
                                Text(String(format: "%.2f km", locale: Locale(identifier: "es_ES"), km))
                                    .monospacedDigit()
                            }
                        }
                        if workout.kcal > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 10.5))
                                Text("\(workout.kcal) kcal")
                                    .monospacedDigit()
                            }
                        }
                    }
                    .font(ImprovingFont.caption(12.5))
                    .foregroundColor(BevelColors.textSecondary)
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
        }
    }
}

// MARK: - Interactive Strength & Routine Logger Sheet

struct StrengthSessionLoggerSheet: View {
    @ObservedObject var store: ImprovingStore
    let routine: WorkoutRoutineTemplate?
    let onClose: () -> Void

    @State private var sessionTitle: String = "Entrenamiento de fuerza tradicional"
    @State private var durationMin: Int = 45
    @State private var kcalEstimate: Int = 260
    @State private var setsDraft: [StrengthLoggedSet] = []
    @State private var newExerciseName: String = "Press banca"
    @State private var newReps: Int = 10
    @State private var newWeight: Double = 60
    @State private var newMuscle: MuscleGroupKind = .pectorales

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    BevelCard(cornerRadius: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("SESIÓN ACTUAL")
                                .font(ImprovingFont.microLabel(10.5))
                                .foregroundColor(BevelColors.textMuted)
                            TextField("Nombre de la sesión", text: $sessionTitle)
                                .font(ImprovingFont.cardTitle(15))
                                .foregroundColor(BevelColors.textPrimary)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.cardSubtle))

                            HStack(spacing: 10) {
                                Stepper("Duración: \(durationMin) min", value: $durationMin, in: 5...240, step: 5)
                                    .font(ImprovingFont.caption(12.5))
                                    .foregroundColor(BevelColors.textPrimary)
                            }
                            Stepper("Energía est.: \(kcalEstimate) kcal", value: $kcalEstimate, in: 20...2000, step: 20)
                                .font(ImprovingFont.caption(12.5))
                                .foregroundColor(BevelColors.textPrimary)
                        }
                        .padding(14)
                    }

                    // Rest timer card
                    BevelCard(cornerRadius: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Temporizador de descanso")
                                    .font(ImprovingFont.cardTitle(14))
                                    .foregroundColor(BevelColors.textPrimary)
                                Text(String(format: "%02d:%02d", store.restTimerSeconds / 60, store.restTimerSeconds % 60))
                                    .font(ImprovingFont.displayLarge(26))
                                    .monospacedDigit()
                                    .foregroundColor(store.restTimerRunning ? BevelColors.greenPrimary : BevelColors.textPrimary)
                            }
                            Spacer()
                            Button(store.restTimerRunning ? "Pausar" : "Iniciar 90s") {
                                store.toggleRestTimer()
                            }
                            .font(ImprovingFont.caption(12.5))
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(store.restTimerRunning ? BevelColors.coralHigh : BevelColors.floatingDarkButton))
                        }
                        .padding(14)
                    }

                    // Add exercise set builder
                    BevelCard(cornerRadius: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("AÑADIR SERIE")
                                .font(ImprovingFont.microLabel(10.5))
                                .foregroundColor(BevelColors.textMuted)
                            TextField("Ejercicio (ej. Press inclinado, Dominadas…)", text: $newExerciseName)
                                .font(ImprovingFont.body(14))
                                .foregroundColor(BevelColors.textPrimary)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.cardSubtle))

                            HStack(spacing: 10) {
                                Picker("Músculo", selection: $newMuscle) {
                                    ForEach(MuscleGroupKind.allCases) { m in
                                        Text(m.rawValue).tag(m)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(BevelColors.skyBlue)
                                Spacer()
                                Stepper("\(newReps) reps", value: $newReps, in: 1...50)
                                    .labelsHidden()
                                Text("\(newReps) reps · \(Int(newWeight)) kg")
                                    .font(ImprovingFont.caption(12))
                                    .monospacedDigit()
                                    .foregroundColor(BevelColors.textPrimary)
                            }

                            HStack(spacing: 8) {
                                Button("-5 kg") { newWeight = max(0, newWeight - 5) }
                                    .font(ImprovingFont.caption(12)).foregroundColor(BevelColors.textPrimary)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Capsule().fill(BevelColors.cardSubtle))
                                Button("+5 kg") { newWeight = min(400, newWeight + 5) }
                                    .font(ImprovingFont.caption(12)).foregroundColor(BevelColors.textPrimary)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Capsule().fill(BevelColors.cardSubtle))
                                Spacer()
                                Button {
                                    let trimmed = newExerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
                                    setsDraft.append(
                                        StrengthLoggedSet(
                                            id: UUID().uuidString,
                                            dateIso: store.selectedDateIso,
                                            exercise: trimmed.isEmpty ? "Ejercicio de fuerza" : trimmed,
                                            reps: newReps,
                                            weightKg: newWeight,
                                            primaryMuscles: [newMuscle],
                                            secondaryMuscles: [],
                                            completed: true
                                        )
                                    )
                                } label: {
                                    Text("+ Añadir serie")
                                        .font(ImprovingFont.caption(12.5))
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(Capsule().fill(BevelColors.indigoEnd))
                                }
                            }
                        }
                        .padding(14)
                    }

                    ForEach($setsDraft) { $s in
                        BevelCard(cornerRadius: 16) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.exercise)
                                        .font(ImprovingFont.cardTitle(14.5))
                                        .foregroundColor(BevelColors.textPrimary)
                                    Text("\(s.reps) reps · \(Int(s.weightKg)) kg · \(s.primaryMuscles.map(\.rawValue).joined(separator: ", "))")
                                        .font(ImprovingFont.caption(12))
                                        .foregroundColor(BevelColors.textSecondary)
                                }
                                Spacer()
                                Button(s.completed ? "✓ Hecho" : "Marcar") {
                                    s.completed.toggle()
                                }
                                .font(ImprovingFont.caption(12))
                                .fontWeight(.bold)
                                .foregroundColor(s.completed ? BevelColors.greenPrimary : BevelColors.textSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(RoundedRectangle(cornerRadius: 10).fill(s.completed ? BevelColors.greenSoftBg : BevelColors.trackGroove))
                            }
                            .padding(14)
                        }
                    }

                    Button {
                        store.logCompletedStrengthSession(
                            title: sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Entrenamiento de fuerza tradicional" : sessionTitle,
                            durationMin: durationMin,
                            kcal: kcalEstimate,
                            sets: setsDraft
                        )
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        onClose()
                    } label: {
                        let doneCount = setsDraft.filter(\.completed).count
                        let volKg = Int(setsDraft.filter(\.completed).reduce(0.0) { $0 + Double($1.reps) * $1.weightKg })
                        Text("Guardar sesión (\(doneCount) series · \(volKg) kg)")
                            .font(ImprovingFont.cardTitle(14.5))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 16).fill(BevelColors.emeraldEnd))
                    }
                }
                .padding(16)
            }
            .background(BevelColors.canvas)
            .navigationTitle("Registrar entrenamiento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar", action: onClose)
                }
            }
            .onAppear {
                if let r = routine {
                    sessionTitle = r.name
                    setsDraft = r.exercises.flatMap { ex in
                        (0..<max(ex.targetSets, 1)).map { _ in
                            StrengthLoggedSet(
                                id: UUID().uuidString,
                                dateIso: store.selectedDateIso,
                                exercise: ex.name,
                                reps: ex.targetReps,
                                weightKg: ex.defaultWeightKg,
                                primaryMuscles: ex.primaryMuscles,
                                secondaryMuscles: ex.secondaryMuscles,
                                completed: true
                            )
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Routines Library, Multi-Exercise Routine Builder & Pin Manager Sheets (P5!)

private struct RoutinesLibrarySheet: View {
    @ObservedObject var store: ImprovingStore
    let onStartRoutine: (WorkoutRoutineTemplate) -> Void
    let onClose: () -> Void

    @State private var routineBeingEdited: WorkoutRoutineTemplate? = nil
    @State private var showCreateBuilder: Bool = false

    private static let starterTemplates: [WorkoutRoutineTemplate] = [
        WorkoutRoutineTemplate(
            id: "tpl_push",
            name: "Empuje (Pecho, Hombro, Tríceps)",
            category: "Fuerza",
            iconName: "figure.strengthtraining.traditional",
            isPinned: true,
            exercises: [
                WorkoutRoutineExercise(id: "e1", name: "Press banca inclinado", targetSets: 4, targetReps: 8, defaultWeightKg: 65, primaryMuscles: [.pectorales], secondaryMuscles: [.hombros, .triceps]),
                WorkoutRoutineExercise(id: "e2", name: "Press militar mancuernas", targetSets: 3, targetReps: 10, defaultWeightKg: 32, primaryMuscles: [.hombros], secondaryMuscles: [.triceps]),
                WorkoutRoutineExercise(id: "e3", name: "Fondos / Extensión tríceps", targetSets: 3, targetReps: 12, defaultWeightKg: 35, primaryMuscles: [.triceps], secondaryMuscles: [.pectorales])
            ]
        ),
        WorkoutRoutineTemplate(
            id: "tpl_pull",
            name: "Tirón (Espalda y Bíceps)",
            category: "Fuerza",
            iconName: "figure.strengthtraining.functional",
            isPinned: false,
            exercises: [
                WorkoutRoutineExercise(id: "e4", name: "Dominadas / Jalón al pecho", targetSets: 4, targetReps: 10, defaultWeightKg: 60, primaryMuscles: [.dorsales], secondaryMuscles: [.biceps, .espaldaAlta]),
                WorkoutRoutineExercise(id: "e5", name: "Remo con barra", targetSets: 4, targetReps: 10, defaultWeightKg: 60, primaryMuscles: [.espaldaAlta, .dorsales], secondaryMuscles: [.lumbares, .biceps]),
                WorkoutRoutineExercise(id: "e6", name: "Curl de bíceps barra Z", targetSets: 3, targetReps: 12, defaultWeightKg: 30, primaryMuscles: [.biceps], secondaryMuscles: [.antebrazo])
            ]
        ),
        WorkoutRoutineTemplate(
            id: "tpl_legs",
            name: "Pierna completa",
            category: "Fuerza",
            iconName: "figure.run",
            isPinned: false,
            exercises: [
                WorkoutRoutineExercise(id: "e7", name: "Sentadilla libre", targetSets: 4, targetReps: 8, defaultWeightKg: 80, primaryMuscles: [.cuadriceps, .gluteos], secondaryMuscles: [.abdominales, .lumbares]),
                WorkoutRoutineExercise(id: "e8", name: "Peso muerto rumano", targetSets: 3, targetReps: 10, defaultWeightKg: 70, primaryMuscles: [.isquiotibiales, .gluteos], secondaryMuscles: [.lumbares]),
                WorkoutRoutineExercise(id: "e9", name: "Elevación de talones", targetSets: 3, targetReps: 15, defaultWeightKg: 50, primaryMuscles: [.pantorrillas], secondaryMuscles: [])
            ]
        )
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Button {
                        showCreateBuilder = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 18, weight: .bold))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Crear nueva rutina multi-ejercicio")
                                    .font(ImprovingFont.cardTitle(15))
                                Text("Añade varios ejercicios, series, repeticiones, peso y músculos")
                                    .font(ImprovingFont.caption(12))
                                    .opacity(0.85)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(BevelColors.emeraldEnd))
                    }
                    .buttonStyle(.plain)

                    if !store.workoutRoutines.isEmpty {
                        Text("Tus rutinas")
                            .font(ImprovingFont.sectionTitle(17))
                            .foregroundColor(BevelColors.textPrimary)
                        ForEach(store.workoutRoutines) { r in
                            routineCard(r, isSaved: true)
                        }
                    }

                    Text("Plantillas sugeridas")
                        .font(ImprovingFont.sectionTitle(17))
                        .foregroundColor(BevelColors.textPrimary)
                        .padding(.top, 4)

                    ForEach(Self.starterTemplates) { tpl in
                        routineCard(tpl, isSaved: false)
                    }
                }
                .padding(16)
            }
            .background(BevelColors.canvas)
            .navigationTitle("Rutinas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar", action: onClose)
                }
            }
            .sheet(isPresented: $showCreateBuilder) {
                RoutineEditorSheet(
                    store: store,
                    existingRoutine: nil,
                    onClose: { showCreateBuilder = false }
                )
            }
            .sheet(item: $routineBeingEdited) { r in
                RoutineEditorSheet(
                    store: store,
                    existingRoutine: r,
                    onClose: { routineBeingEdited = nil }
                )
            }
        }
    }

    private func routineCard(_ r: WorkoutRoutineTemplate, isSaved: Bool) -> some View {
        let previewExercises = r.exercises.prefix(3).map(\.name).joined(separator: " · ")
        return BevelCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: r.iconName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(BevelColors.amberStart)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(BevelColors.amberSoftBg))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(r.name)
                            .font(ImprovingFont.cardTitle(14.5))
                            .foregroundColor(BevelColors.textPrimary)
                        Text("\(r.exercises.count) ejercicio\(r.exercises.count == 1 ? "" : "s") · \(r.category)")
                            .font(ImprovingFont.caption(12))
                            .foregroundColor(BevelColors.textSecondary)
                    }
                    Spacer()
                    if isSaved {
                        Button {
                            routineBeingEdited = r
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(BevelColors.textSecondary)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(BevelColors.cardSubtle))
                        }
                        Button {
                            store.toggleRoutinePin(r.id)
                        } label: {
                            Image(systemName: r.isPinned ? "pin.fill" : "pin")
                                .font(.system(size: 13))
                                .foregroundColor(r.isPinned ? BevelColors.amberStart : BevelColors.textMuted)
                                .frame(width: 30, height: 30)
                        }
                    } else {
                        Button {
                            var copy = r
                            copy = WorkoutRoutineTemplate(
                                id: UUID().uuidString,
                                name: r.name,
                                category: r.category,
                                iconName: r.iconName,
                                isPinned: true,
                                exercises: r.exercises
                            )
                            store.saveRoutine(copy)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(BevelColors.skyBlue)
                        }
                    }
                    Button("Iniciar") {
                        onStartRoutine(r)
                    }
                    .font(ImprovingFont.caption(12))
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(BevelColors.indigoEnd))
                }

                if !previewExercises.isEmpty {
                    Text(previewExercises)
                        .font(ImprovingFont.caption(11.5))
                        .foregroundColor(BevelColors.textMuted)
                        .lineLimit(1)
                }
            }
            .padding(14)
        }
    }
}

private struct RoutineEditorSheet: View {
    @ObservedObject var store: ImprovingStore
    let existingRoutine: WorkoutRoutineTemplate?
    let onClose: () -> Void

    @State private var nameDraft: String = ""
    @State private var categoryDraft: String = "Fuerza"
    @State private var isPinnedDraft: Bool = true
    @State private var exercisesDraft: [WorkoutRoutineExercise] = []

    @State private var exName: String = ""
    @State private var exSets: Int = 3
    @State private var exReps: Int = 10
    @State private var exWeight: Double = 40
    @State private var exMuscle: MuscleGroupKind = .pectorales

    private let categories = ["Fuerza", "Cardio", "Movilidad", "HIIT"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    BevelCard(cornerRadius: 18) {
                        VStack(alignment: .leading, spacing: 11) {
                            Text("DATOS DE LA RUTINA")
                                .font(ImprovingFont.microLabel(10.5))
                                .foregroundColor(BevelColors.textMuted)

                            TextField("Nombre (ej. Torso Fuerza A)", text: $nameDraft)
                                .font(ImprovingFont.cardTitle(15))
                                .foregroundColor(BevelColors.textPrimary)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.cardSubtle))

                            Picker("Categoría", selection: $categoryDraft) {
                                ForEach(categories, id: \.self) { c in Text(c).tag(c) }
                            }
                            .pickerStyle(.segmented)

                            Toggle("Fijar en acceso rápido de Fitness", isOn: $isPinnedDraft)
                                .font(ImprovingFont.body(13.5))
                                .foregroundColor(BevelColors.textPrimary)
                                .tint(BevelColors.emeraldEnd)
                        }
                        .padding(14)
                    }

                    // Add exercise to routine
                    BevelCard(cornerRadius: 18) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("AÑADIR EJERCICIO A LA RUTINA")
                                .font(ImprovingFont.microLabel(10.5))
                                .foregroundColor(BevelColors.skyBlue)

                            TextField("Ej: Press inclinado, Dominadas, Sentadilla…", text: $exName)
                                .font(ImprovingFont.body(14))
                                .foregroundColor(BevelColors.textPrimary)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.cardSubtle))

                            HStack {
                                Picker("Músculo", selection: $exMuscle) {
                                    ForEach(MuscleGroupKind.allCases) { m in Text(m.rawValue).tag(m) }
                                }
                                .pickerStyle(.menu)
                                .tint(BevelColors.skyBlue)
                                Spacer()
                                Stepper("\(exSets) ser · \(exReps) rep", value: $exSets, in: 1...10)
                                    .labelsHidden()
                                Text("\(exSets) × \(exReps) · \(Int(exWeight)) kg")
                                    .font(ImprovingFont.caption(12.5))
                                    .fontWeight(.semibold)
                                    .monospacedDigit()
                                    .foregroundColor(BevelColors.textPrimary)
                            }

                            HStack(spacing: 8) {
                                Button("-2 reps") { exReps = max(1, exReps - 2) }
                                    .font(ImprovingFont.caption(11.5)).foregroundColor(BevelColors.textPrimary)
                                    .padding(.horizontal, 9).padding(.vertical, 6)
                                    .background(Capsule().fill(BevelColors.cardSubtle))
                                Button("+2 reps") { exReps = min(50, exReps + 2) }
                                    .font(ImprovingFont.caption(11.5)).foregroundColor(BevelColors.textPrimary)
                                    .padding(.horizontal, 9).padding(.vertical, 6)
                                    .background(Capsule().fill(BevelColors.cardSubtle))
                                Button("-5 kg") { exWeight = max(0, exWeight - 5) }
                                    .font(ImprovingFont.caption(11.5)).foregroundColor(BevelColors.textPrimary)
                                    .padding(.horizontal, 9).padding(.vertical, 6)
                                    .background(Capsule().fill(BevelColors.cardSubtle))
                                Button("+5 kg") { exWeight = min(350, exWeight + 5) }
                                    .font(ImprovingFont.caption(11.5)).foregroundColor(BevelColors.textPrimary)
                                    .padding(.horizontal, 9).padding(.vertical, 6)
                                    .background(Capsule().fill(BevelColors.cardSubtle))
                                Spacer()
                            }

                            Button {
                                let clean = exName.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !clean.isEmpty else { return }
                                exercisesDraft.append(
                                    WorkoutRoutineExercise(
                                        id: UUID().uuidString,
                                        name: clean,
                                        targetSets: exSets,
                                        targetReps: exReps,
                                        defaultWeightKg: exWeight,
                                        primaryMuscles: [exMuscle],
                                        secondaryMuscles: []
                                    )
                                )
                                exName = ""
                            } label: {
                                Label("Añadir ejercicio", systemImage: "plus")
                                    .font(ImprovingFont.cardTitle(13.5))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Capsule().fill(BevelColors.indigoEnd))
                            }
                            .disabled(exName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .opacity(exName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
                        }
                        .padding(14)
                    }

                    // Exercises list inside routine
                    Text("Ejercicios en esta rutina (\(exercisesDraft.count))")
                        .font(ImprovingFont.sectionTitle(16.5))
                        .foregroundColor(BevelColors.textPrimary)

                    if exercisesDraft.isEmpty {
                        BevelCard(cornerRadius: 16) {
                            Text("Añade al menos un ejercicio arriba para guardar la rutina.")
                                .font(ImprovingFont.body(13))
                                .foregroundColor(BevelColors.textSecondary)
                                .padding(14)
                        }
                    } else {
                        ForEach(Array(exercisesDraft.enumerated()), id: \.element.id) { idx, ex in
                            BevelCard(cornerRadius: 16) {
                                HStack(spacing: 10) {
                                    VStack(spacing: 4) {
                                        Button {
                                            if idx > 0 { exercisesDraft.swapAt(idx, idx - 1) }
                                        } label: {
                                            Image(systemName: "chevron.up")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(idx > 0 ? BevelColors.textSecondary : BevelColors.textMuted.opacity(0.3))
                                        }
                                        .disabled(idx == 0)
                                        Button {
                                            if idx < exercisesDraft.count - 1 { exercisesDraft.swapAt(idx, idx + 1) }
                                        } label: {
                                            Image(systemName: "chevron.down")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(idx < exercisesDraft.count - 1 ? BevelColors.textSecondary : BevelColors.textMuted.opacity(0.3))
                                        }
                                        .disabled(idx == exercisesDraft.count - 1)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ex.name)
                                            .font(ImprovingFont.cardTitle(14.5))
                                            .foregroundColor(BevelColors.textPrimary)
                                        Text("\(ex.targetSets) × \(ex.targetReps) reps · \(Int(ex.defaultWeightKg)) kg · \(ex.primaryMuscles.map(\.rawValue).joined(separator: ", "))")
                                            .font(ImprovingFont.caption(12))
                                            .foregroundColor(BevelColors.textSecondary)
                                    }
                                    Spacer()
                                    Button {
                                        exercisesDraft.removeAll { $0.id == ex.id }
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 13))
                                            .foregroundColor(BevelColors.coralHigh)
                                            .frame(width: 30, height: 30)
                                    }
                                }
                                .padding(13)
                            }
                        }
                    }

                    Button {
                        let cleanName = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !cleanName.isEmpty else { return }
                        let finalExercises: [WorkoutRoutineExercise] = exercisesDraft.isEmpty
                            ? [WorkoutRoutineExercise(id: UUID().uuidString, name: cleanName, targetSets: 3, targetReps: 10, defaultWeightKg: 40, primaryMuscles: [exMuscle], secondaryMuscles: [])]
                            : exercisesDraft
                        let icon = WorkoutSportStyle.resolve(title: cleanName, category: categoryDraft).icon
                        let model = WorkoutRoutineTemplate(
                            id: existingRoutine?.id ?? UUID().uuidString,
                            name: cleanName,
                            category: categoryDraft,
                            iconName: icon,
                            isPinned: isPinnedDraft,
                            exercises: finalExercises
                        )
                        store.saveRoutine(model)
                        onClose()
                    } label: {
                        Text(existingRoutine == nil ? "Guardar rutina" : "Guardar cambios")
                            .font(ImprovingFont.cardTitle(15))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(BevelColors.emeraldEnd))
                    }
                    .disabled(nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)

                    if let existing = existingRoutine {
                        Button {
                            store.deleteRoutine(existing.id)
                            onClose()
                        } label: {
                            Label("Eliminar rutina", systemImage: "trash")
                                .font(ImprovingFont.cardTitle(14))
                                .foregroundColor(BevelColors.coralHigh)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Capsule().fill(BevelColors.coralHigh.opacity(0.12)))
                        }
                    }
                }
                .padding(16)
            }
            .background(BevelColors.canvas)
            .navigationTitle(existingRoutine == nil ? "Nueva rutina" : "Editar rutina")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Cerrar", action: onClose) }
            }
            .onAppear {
                if let r = existingRoutine {
                    nameDraft = r.name
                    categoryDraft = r.category
                    isPinnedDraft = r.isPinned
                    exercisesDraft = r.exercises
                }
            }
        }
    }
}

private struct RoutinePinsEditorSheet: View {
    @ObservedObject var store: ImprovingStore
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Selecciona qué rutinas quieres fijar en el acceso rápido de Fitness.")
                        .font(ImprovingFont.body(13.5))
                        .foregroundColor(BevelColors.textSecondary)

                    if store.workoutRoutines.isEmpty {
                        BevelCard(cornerRadius: 18) {
                            Text("Aún no has creado ninguna rutina. Pulsa «Ver todo» o «+» en Rutinas para crear o añadir tu primera plantilla.")
                                .font(ImprovingFont.body(13.5))
                                .foregroundColor(BevelColors.textSecondary)
                                .padding(16)
                        }
                    } else {
                        ForEach(store.workoutRoutines) { r in
                            BevelCard(cornerRadius: 16) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(r.name).font(ImprovingFont.cardTitle(14.5)).foregroundColor(BevelColors.textPrimary)
                                        Text("\(r.exercises.count) ejercicios").font(ImprovingFont.caption(12)).foregroundColor(BevelColors.textSecondary)
                                    }
                                    Spacer()
                                    Button(r.isPinned ? "Anclada" : "Anclar") {
                                        store.toggleRoutinePin(r.id)
                                    }
                                    .font(ImprovingFont.caption(12))
                                    .fontWeight(.bold)
                                    .foregroundColor(r.isPinned ? BevelColors.greenPrimary : BevelColors.textSecondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(r.isPinned ? BevelColors.greenSoftBg : BevelColors.trackGroove))
                                }
                                .padding(14)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(BevelColors.canvas)
            .navigationTitle("Editar anclas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Listo", action: onClose) }
            }
        }
    }
}

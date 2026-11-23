import SwiftUI

struct FitnessScreen: View {
    @ObservedObject var store: ImprovingStore
    let onNavigate: (OverlayRoute) -> Void
    let onOpenTrainingLoad: (TrainingLoadTab) -> Void
    let onOpenCardioMetric: (CardioMetricRoute) -> Void

    @State private var showStrengthSheet: Bool = false
    @State private var showCalendarSheet: Bool = false

    var body: some View {
        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: store.userProfile)
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let stripOffsets = [-3, -2, -1, 0, 1, 2, 3]
        let wdFmt: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "es_ES")
            f.dateFormat = "EEEEE"
            return f
        }()

        // Real 30-day workout totals (strictly zero invented numbers!)
        let last30 = store.trailingCalendarSummaries(days: 30)
        let all30Workouts = last30.flatMap { $0.summary?.workouts ?? [] }
        let totalDurMin30 = all30Workouts.reduce(0) { $0 + $1.durationMin }
        let totalKcal30 = all30Workouts.reduce(0) { $0 + $1.kcal }

        // Real Cardio & Muscular load from last 7 days
        let last7 = store.trailingCalendarSummaries(days: 7)
        let strainVals7 = last7.compactMap { $0.summary?.strainPct }
        let cardioLoadVal: Int? = strainVals7.isEmpty ? nil : Int((Double(strainVals7.reduce(0, +)) / Double(strainVals7.count) * 0.45).rounded())
        let strengthMin7 = last7.compactMap { $0.summary?.strengthMinutes }.reduce(0, +)
        let hasStrength7 = strengthMin7 > 0

        let zones = store.currentDaySummary?.hrZoneMinutes ?? [0, 0, 0, 0, 0]
        let totalZoneMin = zones.reduce(0, +)
        let topZoneIdx = zones.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
        let lowAero = (zones.count > 0 ? zones[0] : 0) + (zones.count > 1 ? zones[1] : 0)
        let lowAeroPct = totalZoneMin > 0 ? Int((Double(lowAero) / Double(totalZoneMin) * 100.0).rounded()) : 0

        let completedSets = store.strengthSets.filter(\.completed)
        let loggedVolumeKg = Int(completedSets.reduce(0.0) { $0 + Double($1.reps) * $1.weightKg })

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 1. Warm Bronze Atmospheric Top Bar + Real 7-Day Strip
                ZStack(alignment: .top) {
                    LinearGradient(
                        colors: BevelColors.isDarkMode ? [Color(hex: 0x38271B), Color(hex: 0x1E1B1A), BevelColors.canvas] : [BevelColors.canvas, BevelColors.canvas],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 195)
                    .ignoresSafeArea(edges: .top)

                    VStack(spacing: 16) {
                        HStack {
                            Button { showCalendarSheet = true } label: {
                                Image(systemName: "calendar")
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
                            Button { showStrengthSheet = true } label: {
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
                                let hasWorkout = !(store.activeHistory[iso]?.workouts.isEmpty ?? true)

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
                                                    .fill(hasWorkout ? Color(hex: 0x45341E) : Color.white.opacity(0.05))
                                                    .frame(width: 30, height: 30)
                                                if hasWorkout {
                                                    Image(systemName: "figure.strengthtraining.traditional")
                                                        .font(.system(size: 13, weight: .bold))
                                                        .foregroundColor(BevelColors.amberStart)
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

                VStack(alignment: .leading, spacing: 18) {
                    // 2. 4-Hour Time-Aware Fitness-Focused Live AI Coaching Card
                    LiveAiCoachingCard(
                        section: .fitness,
                        store: store,
                        onAskMore: { onNavigate(.askBevel) }
                    )

                    // 3. Actividad de hoy
                    HStack {
                        Text("Actividad · \(store.dateLabel)")
                            .font(ImprovingFont.sectionTitle(18))
                            .foregroundColor(BevelColors.textPrimary)
                        Spacer()
                        Button { showStrengthSheet = true } label: {
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
                            Button { onNavigate(.esfuerzo) } label: {
                                BevelCard(cornerRadius: 18) {
                                    HStack(spacing: 12) {
                                        Image(systemName: w.categoryLabel == "Fuerza" ? "figure.strengthtraining.traditional" : "figure.run")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundColor(BevelColors.amberStart)
                                            .frame(width: 40, height: 40)
                                            .background(Circle().fill(BevelColors.amberSoftBg))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(w.title)
                                                .font(ImprovingFont.cardTitle(14.5))
                                                .foregroundColor(BevelColors.textPrimary)
                                            let meta = [
                                                w.timeRange,
                                                "\(w.durationMin) min",
                                                w.kcal > 0 ? "\(w.kcal) kcal" : nil
                                            ].compactMap { $0 }.joined(separator: " · ")
                                            Text(meta)
                                                .font(ImprovingFont.caption(12))
                                                .foregroundColor(BevelColors.textSecondary)
                                        }
                                        Spacer()
                                        Text("\(w.strainPct)%")
                                            .font(ImprovingFont.caption(12.5))
                                            .fontWeight(.bold)
                                            .foregroundColor(BevelColors.orangeEnd)
                                    }
                                    .padding(14)
                                }
                            }
                        }
                    } else {
                        HStack(spacing: 12) {
                            Image(systemName: "zzz")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(BevelColors.textMuted)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(BevelColors.card))
                            Text("Sin entrenamientos registrados")
                                .font(ImprovingFont.body(14.5))
                                .foregroundColor(BevelColors.textSecondary)
                            Spacer()
                        }
                        .padding(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                                .foregroundColor(BevelColors.cardBorder)
                        )
                    }

                    // 4. Carga de entrenamiento (Real computed values only)
                    Text("Carga de entrenamiento")
                        .font(ImprovingFont.sectionTitle(18))
                        .foregroundColor(BevelColors.textPrimary)

                    HStack(spacing: 12) {
                        Button { onOpenTrainingLoad(.cardio) } label: {
                            BevelCard(cornerRadius: 20) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Cardio").font(ImprovingFont.cardTitle(14.5)).foregroundColor(BevelColors.textPrimary)
                                        Spacer()
                                        Image(systemName: "arrow.right").font(.system(size: 12)).foregroundColor(BevelColors.textMuted)
                                    }
                                    Text(cardioLoadVal != nil ? "Activo" : "Sin datos")
                                        .font(ImprovingFont.sectionTitle(16))
                                        .foregroundColor(cardioLoadVal != nil ? BevelColors.greenPrimary : BevelColors.textMuted)
                                    TrainingLoadTickGauge(
                                        value: cardioLoadVal ?? 0,
                                        minVal: 0,
                                        maxVal: 60,
                                        optimalStartFrac: 0.42,
                                        optimalEndFrac: 0.72,
                                        currentFrac: Double(cardioLoadVal ?? 0) / 60.0,
                                        hasData: cardioLoadVal != nil
                                    )
                                }
                                .padding(14)
                            }
                        }

                        Button { onOpenTrainingLoad(.muscular) } label: {
                            BevelCard(cornerRadius: 20) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Muscular").font(ImprovingFont.cardTitle(14.5)).foregroundColor(BevelColors.textPrimary)
                                        Spacer()
                                        Image(systemName: "arrow.right").font(.system(size: 12)).foregroundColor(BevelColors.textMuted)
                                    }
                                    Text(hasStrength7 ? "\(strengthMin7) min/7d" : "Sin datos")
                                        .font(ImprovingFont.sectionTitle(16))
                                        .foregroundColor(hasStrength7 ? BevelColors.skyBlue : BevelColors.textMuted)
                                    TrainingLoadTickGauge(
                                        value: strengthMin7,
                                        minVal: 0,
                                        maxVal: 240,
                                        optimalStartFrac: min(max(Double(norms.weeklyStrengthGoalMin) / 240.0, 0.20), 0.55),
                                        optimalEndFrac: min(max(Double(norms.weeklyStrengthGoalMin + 90) / 240.0, 0.55), 0.85),
                                        currentFrac: min(Double(strengthMin7) / 240.0, 1.0),
                                        hasData: hasStrength7
                                    )
                                }
                                .padding(14)
                            }
                        }
                    }

                    // 5. Cardio 2x3 Grid (Strictly Real Imported Data!)
                    Text("Cardio (últimos 30 días)")
                        .font(ImprovingFont.sectionTitle(18))
                        .foregroundColor(BevelColors.textPrimary)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        Button { onOpenCardioMetric(.activitiesDuration) } label: {
                            BevelCard(cornerRadius: 20) {
                                VStack(alignment: .leading, spacing: 6) {
                                    tileHeader("Duración 30 d")
                                    Text(totalDurMin30 > 0 ? "\(totalDurMin30 / 60) h \(String(format: "%02d", totalDurMin30 % 60)) m" : "--")
                                        .font(ImprovingFont.metricTile(19))
                                        .monospacedDigit()
                                        .foregroundColor(totalDurMin30 > 0 ? BevelColors.textPrimary : BevelColors.textMuted)
                                    Text("\(all30Workouts.count) sesiones").font(ImprovingFont.caption(11.5)).foregroundColor(BevelColors.textSecondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                            }
                        }

                        Button { onOpenCardioMetric(.activitiesEnergy) } label: {
                            BevelCard(cornerRadius: 20) {
                                VStack(alignment: .leading, spacing: 6) {
                                    tileHeader("Energía 30 d")
                                    Text(totalKcal30 > 0 ? "\(totalKcal30) kcal" : "--")
                                        .font(ImprovingFont.metricTile(19))
                                        .monospacedDigit()
                                        .foregroundColor(totalKcal30 > 0 ? BevelColors.textPrimary : BevelColors.textMuted)
                                    Text("En entrenamientos").font(ImprovingFont.caption(11.5)).foregroundColor(BevelColors.textSecondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                            }
                        }

                        Button { onOpenCardioMetric(.vo2Max) } label: {
                            BevelCard(cornerRadius: 20) {
                                VStack(alignment: .leading, spacing: 6) {
                                    tileHeader("VO₂ máx.")
                                    Text(store.latestVo2Max.map { String(format: "%.1f", locale: Locale(identifier: "es_ES"), $0) } ?? "--")
                                        .font(ImprovingFont.metricTile(21))
                                        .monospacedDigit()
                                        .foregroundColor(store.latestVo2Max != nil ? BevelColors.textPrimary : BevelColors.textMuted)
                                    Text(store.latestVo2Max != nil ? "mL/kg·min" : "Sin datos")
                                        .font(ImprovingFont.caption(12))
                                        .foregroundColor(store.latestVo2Max != nil ? BevelColors.amberStart : BevelColors.textMuted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                            }
                        }

                        Button { onOpenCardioMetric(.hrRecovery) } label: {
                            BevelCard(cornerRadius: 20) {
                                VStack(alignment: .leading, spacing: 6) {
                                    tileHeader("Recup. de FC")
                                    Text(store.latestHrRecoveryBpm.map { "\(Int($0.rounded())) ppm" } ?? "--")
                                        .font(ImprovingFont.metricTile(21))
                                        .monospacedDigit()
                                        .foregroundColor(store.latestHrRecoveryBpm != nil ? BevelColors.textPrimary : BevelColors.textMuted)
                                    Text(store.latestHrRecoveryBpm != nil ? "1 min post-ej." : "Sin datos")
                                        .font(ImprovingFont.caption(12))
                                        .foregroundColor(store.latestHrRecoveryBpm != nil ? BevelColors.amberStart : BevelColors.textMuted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                            }
                        }

                        Button { onOpenCardioMetric(.cardioFocus) } label: {
                            BevelCard(cornerRadius: 20) {
                                VStack(alignment: .leading, spacing: 6) {
                                    tileHeader("Foco cardio")
                                    Text(totalZoneMin > 0 ? "\(lowAeroPct) %" : "--")
                                        .font(ImprovingFont.metricTile(21))
                                        .monospacedDigit()
                                        .foregroundColor(totalZoneMin > 0 ? BevelColors.textPrimary : BevelColors.textMuted)
                                    Text(totalZoneMin > 0 ? "Aeróbico bajo" : "Sin zonas hoy")
                                        .font(ImprovingFont.caption(12))
                                        .foregroundColor(totalZoneMin > 0 ? BevelColors.tealLow : BevelColors.textMuted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                            }
                        }

                        Button { onOpenCardioMetric(.hrZones) } label: {
                            BevelCard(cornerRadius: 20) {
                                VStack(alignment: .leading, spacing: 6) {
                                    tileHeader("Zonas de FC")
                                    Text(totalZoneMin > 0 ? "Zona \(topZoneIdx + 1)" : "--")
                                        .font(ImprovingFont.metricTile(20))
                                        .foregroundColor(totalZoneMin > 0 ? BevelColors.textPrimary : BevelColors.textMuted)
                                    Text(totalZoneMin > 0 ? "\(zones[topZoneIdx]) min" : "Sin datos")
                                        .font(ImprovingFont.caption(12))
                                        .foregroundColor(totalZoneMin > 0 ? BevelColors.skyBlue : BevelColors.textMuted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                            }
                        }
                    }

                    // 6. Fuerza (Manual Workout Logger)
                    HStack {
                        Text("Fuerza").font(ImprovingFont.sectionTitle(18)).foregroundColor(BevelColors.textPrimary)
                        Spacer()
                        Button("Registrar") { showStrengthSheet = true }
                            .font(ImprovingFont.caption(13))
                            .foregroundColor(BevelColors.skyBlue)
                    }

                    HStack(spacing: 12) {
                        Button { showStrengthSheet = true } label: {
                            BevelCard(cornerRadius: 20) {
                                VStack(alignment: .leading, spacing: 4) {
                                    tileHeader("Series hoy")
                                    Text("\(completedSets.count)").font(ImprovingFont.metricTile(22)).monospacedDigit().foregroundColor(BevelColors.textPrimary)
                                    Text("Completadas").font(ImprovingFont.caption(12)).foregroundColor(BevelColors.textSecondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                            }
                        }

                        Button { showStrengthSheet = true } label: {
                            BevelCard(cornerRadius: 20) {
                                VStack(alignment: .leading, spacing: 4) {
                                    tileHeader("Volumen")
                                    Text("\(loggedVolumeKg) kg").font(ImprovingFont.metricTile(21)).monospacedDigit().foregroundColor(BevelColors.textPrimary)
                                    Text("Total levantado").font(ImprovingFont.caption(12)).foregroundColor(BevelColors.textSecondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
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
        .sheet(isPresented: $showStrengthSheet) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
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

                        ForEach(store.strengthSets, id: \.id) { s in
                            BevelCard(cornerRadius: 16) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(s.exercise)
                                            .font(ImprovingFont.cardTitle(14.5))
                                            .foregroundColor(BevelColors.textPrimary)
                                        Text("\(s.reps) reps · \(Int(s.weightKg)) kg")
                                            .font(ImprovingFont.caption(12))
                                            .foregroundColor(BevelColors.textSecondary)
                                    }
                                    Spacer()
                                    Button(s.completed ? "✓ Hecho" : "Marcar") {
                                        store.toggleSetCompleted(s.id)
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

                        Button { store.addStrengthSet() } label: {
                            Text("+ Añadir serie")
                                .font(ImprovingFont.cardTitle(14))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(RoundedRectangle(cornerRadius: 14).fill(BevelColors.floatingDarkButton))
                        }
                    }
                    .padding(16)
                }
                .background(BevelColors.canvas)
                .navigationTitle("Entrenamiento de Fuerza")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private func tileHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(ImprovingFont.cardTitle(13.5))
                .foregroundColor(BevelColors.textPrimary)
                .lineLimit(1)
            Spacer()
            Image(systemName: "arrow.right")
                .font(.system(size: 11))
                .foregroundColor(BevelColors.textMuted)
        }
    }
}

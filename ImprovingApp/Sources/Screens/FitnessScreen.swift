import SwiftUI

struct FitnessScreen: View {
    @ObservedObject var store: ImprovingStore
    let onNavigate: (OverlayRoute) -> Void
    let onOpenTrainingLoad: (TrainingLoadTab) -> Void
    let onOpenCardioMetric: (CardioMetricRoute) -> Void

    @State private var showStrengthSheet: Bool = false

    private let dayLetters = ["M", "X", "J", "V", "S", "D", "L"]
    private let dayOffsets = [-3, -2, -1, 0, 1, 2, 3]

    var body: some View {
        let completedSets = store.strengthSets.filter(\.completed)
        let totalVolumeKg = max(Int(completedSets.reduce(0.0) { $0 + Double($1.reps) * $1.weightKg }), 1240)

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 1. Warm Bronze Atmospheric Top Bar + 7 Vertical Pill Day Capsules (Screenshot 46)
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
                            Button { store.shiftDay(1) } label: {
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
                            Button { showStrengthSheet = true } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .frame(width: 40, height: 40)
                                    .background(Circle().fill(BevelColors.glassChromeFill))
                                    .overlay(Circle().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.8))
                            }
                        }

                        // 7 Vertical Pill Capsules (M 17..L 23) with top orange triangle on today (Screenshot 46)
                        HStack(spacing: 6) {
                            ForEach(0..<7, id: \.self) { idx in
                                let offset = dayOffsets[idx]
                                let pastOffset = max(0, -offset)
                                let isFuture = offset > 0
                                let isToday = offset == 0
                                let isSelected = !isFuture && (pastOffset == store.dayOffset)
                                let dayNum = 20 + offset
                                let hasWorkout = idx == 1 || (isToday && !store.workoutsToday.isEmpty)

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
                                            Text(dayLetters[idx])
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
                    // 2. Coaching Card (Screenshot 46)
                    BevelCard(cornerRadius: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("🏋️ Retoma fuerza con calma")
                                    .font(ImprovingFont.cardTitle(15))
                                    .foregroundColor(BevelColors.textPrimary)
                                Spacer()
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 12))
                                    .foregroundColor(BevelColors.textMuted)
                            }
                            Text("Tienes margen para entrenar hoy: la Recuperación subió al \(store.recoveryPercent)% y el Sueño al \(store.sleepPercent)%. Haz una sesión cómoda de cuerpo completo controlando técnica y esfuerzo objetivo \(store.effortTargetRangeText).")
                                .font(ImprovingFont.body(13.5))
                                .foregroundColor(BevelColors.textSecondary)
                                .lineLimit(4)
                        }
                        .padding(16)
                    }

                    // 3. Actividad de hoy (Screenshot 46)
                    HStack {
                        Text("Actividad de hoy")
                            .font(ImprovingFont.sectionTitle(18))
                            .foregroundColor(BevelColors.textPrimary)
                        Spacer()
                        HStack(spacing: 8) {
                            HStack(spacing: 5) {
                                Image(systemName: "cloud.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(BevelColors.textSecondary)
                                Text("12°C")
                                    .font(ImprovingFont.caption(12.5))
                                    .foregroundColor(BevelColors.textPrimary)
                            }
                            .padding(.horizontal, 11)
                            .frame(height: 32)
                            .background(Capsule().fill(BevelColors.card))
                            .overlay(Capsule().strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))

                            Button { showStrengthSheet = true } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(BevelColors.card))
                                    .overlay(Circle().strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
                            }
                        }
                    }

                    if let w = store.workoutsToday.first {
                        Button { onNavigate(.esfuerzo) } label: {
                            BevelCard(cornerRadius: 18) {
                                HStack(spacing: 12) {
                                    Image(systemName: "figure.run")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(BevelColors.amberStart)
                                        .frame(width: 40, height: 40)
                                        .background(Circle().fill(BevelColors.amberSoftBg))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(w.title)
                                            .font(ImprovingFont.cardTitle(14.5))
                                            .foregroundColor(BevelColors.textPrimary)
                                        Text("\(w.timeRange) · \(w.durationMin) min · \(w.kcal) kcal")
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
                    } else {
                        HStack(spacing: 12) {
                            Image(systemName: "zzz")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(BevelColors.textMuted)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(BevelColors.card))
                            Text("Día de descanso")
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

                    // 4. Rutinas (Screenshot 46)
                    HStack {
                        Text("Rutinas")
                            .font(ImprovingFont.sectionTitle(18))
                            .foregroundColor(BevelColors.textPrimary)
                        Spacer()
                        HStack(spacing: 8) {
                            Button { showStrengthSheet = true } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(BevelColors.textSecondary)
                                    .frame(width: 30, height: 30)
                                    .background(Circle().fill(BevelColors.card))
                            }
                            Button { showStrengthSheet = true } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .frame(width: 30, height: 30)
                                    .background(Circle().fill(BevelColors.card))
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        Button { showStrengthSheet = true } label: {
                            VStack(spacing: 10) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(BevelColors.card))
                                Text("Editar anclas")
                                    .font(ImprovingFont.cardTitle(14))
                                    .foregroundColor(BevelColors.textPrimary)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 136)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                                    .foregroundColor(Color.white.opacity(0.18))
                            )
                        }

                        Button { showStrengthSheet = true } label: {
                            BevelCard(cornerRadius: 20) {
                                HStack(spacing: 6) {
                                    Text("Ver todo")
                                        .font(ImprovingFont.cardTitle(15))
                                        .foregroundColor(BevelColors.textPrimary)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(BevelColors.textPrimary)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 136)
                            }
                        }
                    }

                    // 5. Carga de entrenamiento (Exact 270° Tick Gauges from Screenshot 47)
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
                                    Text("Manteniéndose")
                                        .font(ImprovingFont.sectionTitle(16.5))
                                        .foregroundColor(BevelColors.greenPrimary)
                                    TrainingLoadTickGauge(value: 37, minVal: 0, maxVal: 60, optimalStartFrac: 0.42, optimalEndFrac: 0.72, currentFrac: 0.60)
                                    HStack(spacing: 5) {
                                        Image(systemName: "line.3.horizontal").font(.system(size: 10)).foregroundColor(BevelColors.greenPrimary)
                                        Text("Óptimo: 32-42").font(ImprovingFont.caption(11.5)).foregroundColor(BevelColors.textSecondary)
                                    }
                                    .frame(maxWidth: .infinity)
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
                                    Text("Productivo")
                                        .font(ImprovingFont.sectionTitle(16.5))
                                        .foregroundColor(BevelColors.skyBlue)
                                    TrainingLoadTickGauge(value: 26, minVal: 0, maxVal: 32, optimalStartFrac: 0.25, optimalEndFrac: 0.65, currentFrac: 0.78)
                                    HStack(spacing: 5) {
                                        Image(systemName: "line.3.horizontal").font(.system(size: 10)).foregroundColor(BevelColors.greenPrimary)
                                        Text("Óptimo: 8-19").font(ImprovingFont.caption(11.5)).foregroundColor(BevelColors.textSecondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .padding(14)
                            }
                        }
                    }

                    // 6. Cardio 2x3 Grid (Literal Match to Screenshots 47 & 48)
                    HStack {
                        Text("Cardio").font(ImprovingFont.sectionTitle(18)).foregroundColor(BevelColors.textPrimary)
                        Spacer()
                        Text("Editar").font(ImprovingFont.caption(13)).underline().foregroundColor(BevelColors.textSecondary)
                    }

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        // Tile 1: Duración de la actividad (stepped cyan comparison)
                        Button { onOpenCardioMetric(.activitiesDuration) } label: {
                            BevelCard(cornerRadius: 20) {
                                VStack(alignment: .leading, spacing: 4) {
                                    tileHeader("Todas las activi...")
                                    Text("2:22:27").font(ImprovingFont.metricTile(21)).monospacedDigit().foregroundColor(BevelColors.textPrimary)
                                    Text("Duración de la activid...").font(ImprovingFont.caption(11.5)).foregroundColor(BevelColors.textSecondary).lineLimit(1)
                                    SteppedCumulativeComparisonChart(
                                        currentPoints: [0, 0, 0.5, 0.5, 0.5, 0.8, 0.8, 1.3, 1.3],
                                        previousPoints: [0, 0.9, 1.1, 1.1, 1.1, 1.1, 1.1, 1.1, 1.1],
                                        accentColor: BevelColors.cyanBright,
                                        height: 46
                                    )
                                }
                                .padding(13)
                            }
                        }

                        // Tile 2: Energía en actividad
                        Button { onOpenCardioMetric(.activitiesEnergy) } label: {
                            BevelCard(cornerRadius: 20) {
                                VStack(alignment: .leading, spacing: 4) {
                                    tileHeader("Todas las activi...")
                                    Text("715 kcal").font(ImprovingFont.metricTile(21)).monospacedDigit().foregroundColor(BevelColors.textPrimary)
                                    Text("Energía en actividad").font(ImprovingFont.caption(11.5)).foregroundColor(BevelColors.textSecondary).lineLimit(1)
                                    SteppedCumulativeComparisonChart(
                                        currentPoints: [0, 0, 210, 210, 210, 420, 420, 715, 715],
                                        previousPoints: [0, 320, 510, 510, 510, 510, 510, 510, 510],
                                        accentColor: BevelColors.cyanBright,
                                        height: 46
                                    )
                                }
                                .padding(13)
                            }
                        }

                        // Tile 3: VO2 máx.
                        Button { onOpenCardioMetric(.vo2Max) } label: {
                            BevelCard(cornerRadius: 20) {
                                VStack(alignment: .leading, spacing: 4) {
                                    tileHeader("VO₂ máx.")
                                    Text(String(format: "%.1f", locale: Locale(identifier: "es_ES"), store.vo2Max)).font(ImprovingFont.metricTile(21)).monospacedDigit().foregroundColor(BevelColors.textPrimary)
                                    Text("Aceptable").font(ImprovingFont.caption(12)).fontWeight(.semibold).foregroundColor(BevelColors.amberStart)
                                    TrendSparklineWithBand(points: [43.2, 43.4, 43.7, 43.9, 44.1, 44.3], bandLow: 42.5, bandHigh: 45, lineColor: BevelColors.amberStart, fillUnder: true, showGlowDot: true)
                                        .frame(height: 44)
                                }
                                .padding(13)
                            }
                        }

                        // Tile 4: Recuperación de FC
                        Button { onOpenCardioMetric(.hrRecovery) } label: {
                            BevelCard(cornerRadius: 20) {
                                VStack(alignment: .leading, spacing: 4) {
                                    tileHeader("Recuperación d...")
                                    Text("27 ppm").font(ImprovingFont.metricTile(21)).monospacedDigit().foregroundColor(BevelColors.textPrimary)
                                    Text("Aceptable").font(ImprovingFont.caption(12)).fontWeight(.semibold).foregroundColor(BevelColors.amberStart)
                                    TrendSparklineWithBand(points: [38, 36, 33, 31, 29, 27], bandLow: 24, bandHigh: 42, lineColor: BevelColors.amberStart, fillUnder: true, showGlowDot: true)
                                        .frame(height: 44)
                                }
                                .padding(13)
                            }
                        }

                        // Tile 5: Foco cardiovascular (3 horizontal bars — Screenshot 48)
                        Button { onOpenCardioMetric(.cardioFocus) } label: {
                            BevelCard(cornerRadius: 20) {
                                VStack(alignment: .leading, spacing: 5) {
                                    tileHeader("Foco cardiovasc...")
                                    Text("95 %").font(ImprovingFont.metricTile(21)).monospacedDigit().foregroundColor(BevelColors.textPrimary)
                                    Text("Aeróbico bajo").font(ImprovingFont.caption(12)).fontWeight(.semibold).foregroundColor(BevelColors.tealLow)
                                    VStack(spacing: 5) {
                                        focusMiniBar(frac: 0.95, color: BevelColors.tealLow)
                                        focusMiniBar(frac: 0.08, color: BevelColors.skyBlue)
                                        focusMiniBar(frac: 0.0, color: BevelColors.periwinkleStart)
                                    }
                                    .padding(.top, 4)
                                }
                                .padding(13)
                            }
                        }

                        // Tile 6: Zonas de FC (5 colored vertical bars — Screenshot 48)
                        Button { onOpenCardioMetric(.hrZones) } label: {
                            BevelCard(cornerRadius: 20) {
                                VStack(alignment: .leading, spacing: 4) {
                                    tileHeader("Zonas de frecue...")
                                    Text("Zona 1").font(ImprovingFont.metricTile(20)).foregroundColor(BevelColors.textPrimary)
                                    Text("45 min").font(ImprovingFont.caption(12)).fontWeight(.semibold).foregroundColor(BevelColors.skyBlue)
                                    HStack(alignment: .bottom, spacing: 5) {
                                        zoneMiniCol(h: 4, color: BevelColors.periwinkleStart.opacity(0.6))
                                        zoneMiniCol(h: 40, color: Color(hex: 0x5A84F8))
                                        zoneMiniCol(h: 22, color: BevelColors.greenPrimary)
                                        zoneMiniCol(h: 10, color: BevelColors.amberStart)
                                        zoneMiniCol(h: 3, color: BevelColors.redAlert)
                                    }
                                    .frame(height: 42, alignment: .bottom)
                                }
                                .padding(13)
                            }
                        }
                    }

                    // 7. Fuerza + Frescura Muscular (Literal Match to Screenshots 48 & 49)
                    HStack {
                        Text("Fuerza").font(ImprovingFont.sectionTitle(18)).foregroundColor(BevelColors.textPrimary)
                        Spacer()
                        Text("Editar").font(ImprovingFont.caption(13)).underline().foregroundColor(BevelColors.textSecondary)
                    }

                    HStack(spacing: 12) {
                        Button { showStrengthSheet = true } label: {
                            BevelCard(cornerRadius: 20) {
                                VStack(alignment: .leading, spacing: 4) {
                                    tileHeader("Todos los músc...")
                                    Text("16").font(ImprovingFont.metricTile(22)).monospacedDigit().foregroundColor(BevelColors.textPrimary)
                                    Text("Total series").font(ImprovingFont.caption(12)).foregroundColor(BevelColors.textSecondary)
                                    SteppedCumulativeComparisonChart(currentPoints: [0, 0, 0, 0, 0, 0, 16, 16], previousPoints: [0, 0, 0, 0, 0, 0, 0, 0], accentColor: BevelColors.strengthPink, height: 48)
                                }
                                .padding(13)
                            }
                        }

                        Button { showStrengthSheet = true } label: {
                            BevelCard(cornerRadius: 20) {
                                VStack(alignment: .leading, spacing: 4) {
                                    tileHeader("Todos los músc...")
                                    Text("\(totalVolumeKg) kg").font(ImprovingFont.metricTile(21)).monospacedDigit().foregroundColor(BevelColors.textPrimary)
                                    Text("Volumen total").font(ImprovingFont.caption(12)).foregroundColor(BevelColors.textSecondary)
                                    SteppedCumulativeComparisonChart(currentPoints: [0, 0, 0, 0, 0, 0, Double(totalVolumeKg), Double(totalVolumeKg)], previousPoints: [0, 0, 0, 0, 0, 0, 0, 0], accentColor: BevelColors.strengthPink, height: 48)
                                }
                                .padding(13)
                            }
                        }
                    }

                    // Frescura muscular (Single Card with 2x3 Muscle Icons & 10-Dot Meters — Screenshot 49)
                    BevelCard(cornerRadius: 22) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("Frescura muscular")
                                    .font(ImprovingFont.cardTitle(15.5))
                                    .foregroundColor(BevelColors.textPrimary)
                                Spacer()
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 12))
                                    .foregroundColor(BevelColors.textMuted)
                            }

                            let muscles: [(String, Int, String)] = [
                                ("Pectorales", 4, "figure.arms.open"),
                                ("Dorsales", 100, "figure.stand"),
                                ("Bíceps", 100, "figure.strengthtraining.traditional"),
                                ("Tríceps", 12, "figure.strengthtraining.functional"),
                                ("Cuádriceps", 98, "figure.walk"),
                                ("Glúteos", 98, "figure.run")
                            ]

                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 16) {
                                ForEach(muscles, id: \.0) { name, pct, icon in
                                    let activeColor: Color = pct < 35 ? BevelColors.orangeEnd : (pct == 100 ? BevelColors.textSecondary : BevelColors.greenPrimary)
                                    let litDots = max(1, Int((Double(pct) / 100.0 * 10.0).rounded()))
                                    HStack(spacing: 9) {
                                        Image(systemName: icon)
                                            .font(.system(size: 19))
                                            .foregroundColor(activeColor)
                                            .frame(width: 30, height: 34)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(name)
                                                .font(ImprovingFont.cardTitle(13.5))
                                                .foregroundColor(BevelColors.textPrimary)
                                            Text("\(pct)% recuperado")
                                                .font(ImprovingFont.caption(11))
                                                .foregroundColor(BevelColors.textSecondary)
                                            HStack(spacing: 2.5) {
                                                ForEach(0..<10, id: \.self) { i in
                                                    let isTip = i == litDots - 1
                                                    Capsule()
                                                        .fill(i < litDots ? (isTip ? activeColor : activeColor.opacity(0.45)) : Color.white.opacity(0.08))
                                                        .frame(width: 6, height: 9)
                                                }
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .padding(16)
                    }

                    // Bottom "Editar fitness" pill button (Screenshot 49)
                    Button { showStrengthSheet = true } label: {
                        Text("Editar fitness")
                            .font(ImprovingFont.cardTitle(15))
                            .foregroundColor(BevelColors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(BevelColors.card))
                            .overlay(Capsule().strokeBorder(BevelColors.cardBorder, lineWidth: 0.9))
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 155)
        }
        .background(BevelColors.canvas)
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

    private func focusMiniBar(frac: Double, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                if frac > 0 {
                    Capsule().fill(color).frame(width: max(8, geo.size.width * CGFloat(frac)))
                }
            }
        }
        .frame(height: 8)
    }

    private func zoneMiniCol(h: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(color)
            .frame(maxWidth: .infinity)
            .frame(height: h)
    }
}

import SwiftUI

struct FitnessScreen: View {
    @ObservedObject var store: ImprovingStore
    let onNavigate: (OverlayRoute) -> Void
    let onOpenTrainingLoad: (TrainingLoadTab) -> Void
    let onOpenCardioMetric: (CardioMetricRoute) -> Void

    @State private var showStrengthSheet: Bool = false

    private let dayNames = ["lun", "mar", "mié", "jue", "vie", "sáb", "dom"]
    private let dayOffsets = [-5, -4, -3, -2, -1, 0, 1]

    var body: some View {
        let avail = store.dataAvailability
        let completedSets = store.strengthSets.filter(\.completed)
        let totalVolumeKg = Int(completedSets.reduce(0.0) { $0 + Double($1.reps) * $1.weightKg })

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 1. Top Bar: Date + Orb + •••
                HStack {
                    HStack(spacing: 4) {
                        Button { store.shiftDay(-1) } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(BevelColors.textSecondary)
                                .frame(width: 28, height: 28)
                        }
                        Text(store.dateLabel)
                            .font(ImprovingFont.sectionTitle(18))
                            .foregroundColor(BevelColors.textPrimary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(BevelColors.textSecondary)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        Button {
                            store.startNewCleanChat()
                            onNavigate(.askBevel)
                        } label: {
                            IridescentPearlOrb(size: 34)
                        }
                        Button { showStrengthSheet = true } label: {
                            Text("•••")
                                .font(ImprovingFont.caption(12))
                                .fontWeight(.bold)
                                .foregroundColor(BevelColors.textPrimary)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(BevelColors.card))
                                .overlay(Circle().strokeBorder(BevelColors.cardBorder, lineWidth: 1))
                        }
                    }
                }

                Text("Fitness")
                    .font(ImprovingFont.displayLarge(28))
                    .foregroundColor(BevelColors.textPrimary)

                // 2. 7-Day Week Strip with Colored Activity Dots
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { idx in
                        let offset = dayOffsets[idx]
                        let isSelected = offset == store.selectedDayOffset
                        let dayNum = 21 + offset
                        let isFuture = offset > 0

                        Button {
                            if !isFuture {
                                store.shiftDay(offset - store.selectedDayOffset)
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Text(dayNames[idx])
                                    .font(ImprovingFont.caption(11))
                                    .foregroundColor(isSelected ? .white.opacity(0.85) : BevelColors.textSecondary)
                                Text("\(dayNum)")
                                    .font(ImprovingFont.cardTitle(14.5))
                                    .foregroundColor(isSelected ? .white : (isFuture ? BevelColors.textMuted : BevelColors.textPrimary))

                                HStack(spacing: 3) {
                                    if !isFuture {
                                        Circle()
                                            .fill(idx % 2 == 0 ? BevelColors.orangeEnd : BevelColors.emeraldEnd)
                                            .frame(width: 5, height: 5)
                                        if idx == 3 || idx == 5 {
                                            Circle()
                                                .fill(BevelColors.skyBlue)
                                                .frame(width: 5, height: 5)
                                        }
                                    } else {
                                        Spacer().frame(height: 5)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(isSelected ? BevelColors.floatingDarkButton : .clear)
                            )
                        }
                    }
                }

                // 3. Coaching Banner Card with Mini Strain Ring
                Button { onNavigate(.esfuerzo) } label: {
                    BevelCard {
                        HStack(spacing: 16) {
                            BevelRecessedRingGauge(
                                progress: Double(store.strainPercent) / 100.0,
                                centerText: "\(store.strainPercent)%",
                                label: "",
                                kind: .strain,
                                size: 56,
                                strokeWidth: 6.5,
                                targetRange: store.optimalEffortRange,
                                hasData: avail.hasStrainData
                            )

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Entrenamiento recomendado · Esfuerzo objetivo \(store.effortTargetRangeText)")
                                    .font(ImprovingFont.caption(11.5))
                                    .fontWeight(.semibold)
                                    .foregroundColor(BevelColors.orangeEnd)
                                Text(store.activeCoachingSummary)
                                    .font(ImprovingFont.body(12.5))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(3)
                            }
                        }
                        .padding(16)
                    }
                }

                // 4. Actividad de hoy
                HStack {
                    Text("Actividad de hoy")
                        .font(ImprovingFont.sectionTitle(18))
                        .foregroundColor(BevelColors.textPrimary)
                    Spacer()
                    HStack(spacing: 8) {
                        Text("☁️ 12°C")
                            .font(ImprovingFont.caption(12))
                            .foregroundColor(BevelColors.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(BevelColors.card))
                            .overlay(Capsule().strokeBorder(BevelColors.cardBorder, lineWidth: 1))

                        Button { showStrengthSheet = true } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(BevelColors.textPrimary)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(BevelColors.card))
                                .overlay(Circle().strokeBorder(BevelColors.cardBorder, lineWidth: 1))
                        }
                    }
                }

                ForEach(store.workoutsToday) { w in
                    Button { onNavigate(.esfuerzo) } label: {
                        BevelCard(cornerRadius: 20) {
                            HStack(spacing: 12) {
                                Text("🏃")
                                    .font(.system(size: 18))
                                    .frame(width: 44, height: 44)
                                    .background(RoundedRectangle(cornerRadius: 14).fill(BevelColors.amberSoftBg))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(w.title)
                                        .font(ImprovingFont.cardTitle(14.5))
                                        .foregroundColor(BevelColors.textPrimary)
                                    Text("\(w.timeRange) · \(w.durationMin) min · \(w.kcal) kcal · \(w.avgHrBpm) bpm")
                                        .font(ImprovingFont.caption(11.5))
                                        .foregroundColor(BevelColors.textSecondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("48%")
                                        .font(ImprovingFont.caption(11.5))
                                        .fontWeight(.bold)
                                        .foregroundColor(BevelColors.orangeEnd)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill(BevelColors.amberSoftBg))
                                    Text(String(format: "%.1f", locale: Locale(identifier: "es_ES"), store.strain21))
                                        .font(ImprovingFont.caption(11.5))
                                        .fontWeight(.semibold)
                                        .foregroundColor(BevelColors.textSecondary)
                                }
                            }
                            .padding(14)
                        }
                    }
                }

                // 5. Rutinas
                HStack {
                    Text("Rutinas")
                        .font(ImprovingFont.sectionTitle(18))
                        .foregroundColor(BevelColors.textPrimary)
                    Spacer()
                    Button("Ver todo · \(store.strengthSets.count) series activas") {
                        showStrengthSheet = true
                    }
                    .font(ImprovingFont.caption(12.5))
                    .foregroundColor(BevelColors.textSecondary)
                }

                HStack(spacing: 12) {
                    Button { showStrengthSheet = true } label: {
                        VStack(spacing: 6) {
                            Text("⚙️").font(.system(size: 16))
                            Text("Editar anclas")
                                .font(ImprovingFont.caption(12))
                                .foregroundColor(BevelColors.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 82)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.4, dash: [6, 5]))
                                .foregroundColor(BevelColors.textMuted)
                        )
                    }

                    Button { showStrengthSheet = true } label: {
                        BevelCard(cornerRadius: 18) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("🏋️").font(.system(size: 16))
                                    Spacer()
                                    Text(store.restTimerRunning ? "⏱ \(store.restTimerSeconds)s" : "Interactivo")
                                        .font(ImprovingFont.caption(11))
                                        .fontWeight(.bold)
                                        .foregroundColor(BevelColors.emeraldEnd)
                                }
                                Spacer()
                                Text("Entrenamiento de Fuerza")
                                    .font(ImprovingFont.cardTitle(13))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .lineLimit(1)
                                Text("\(completedSets.count)/\(store.strengthSets.count) series · \(totalVolumeKg) kg")
                                    .font(ImprovingFont.caption(11))
                                    .foregroundColor(BevelColors.textSecondary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 82)
                        }
                    }
                }

                // 6. Carga de entrenamiento (Side-by-Side Semi-Circular Gauge Cards)
                Text("Carga de entrenamiento")
                    .font(ImprovingFont.sectionTitle(18))
                    .foregroundColor(BevelColors.textPrimary)

                HStack(spacing: 12) {
                    trainingLoadCard(
                        title: "Cardio",
                        value: "37",
                        status: "Manteniendo",
                        color: BevelColors.emeraldEnd,
                        fillFraction: 0.56,
                        onClick: { onOpenTrainingLoad(.cardio) }
                    )
                    trainingLoadCard(
                        title: "Muscular",
                        value: "45",
                        status: "Subiendo",
                        color: BevelColors.orangeEnd,
                        fillFraction: 0.68,
                        onClick: { onOpenTrainingLoad(.muscular) }
                    )
                }

                // 7. Cardio 2x3 Grid
                Text("Cardio")
                    .font(ImprovingFont.sectionTitle(18))
                    .foregroundColor(BevelColors.textPrimary)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    cardioSparkCard(title: "Duración de actividades", value: "2:22:27", unit: "", status: "Esta semana", color: BevelColors.skyBlue, points: [0.4, 0.55, 0.5, 0.72, 0.68, 0.85, 0.9]) {
                        onOpenCardioMetric(.activitiesDuration)
                    }
                    cardioSparkCard(title: "Energía en actividades", value: "715", unit: "kcal", status: "Normal", color: BevelColors.orangeEnd, points: [0.5, 0.45, 0.62, 0.58, 0.75, 0.7, 0.82]) {
                        onOpenCardioMetric(.cardioLoad)
                    }
                    cardioSparkCard(title: "VO₂ máx.", value: "44,3", unit: "", status: "Normal", color: BevelColors.emeraldEnd, points: [0.6, 0.61, 0.62, 0.64, 0.63, 0.66, 0.68]) {
                        onOpenCardioMetric(.vo2Max)
                    }
                    cardioSparkCard(title: "Recuperación de FC", value: "27", unit: "ppm", status: "Excelente", color: BevelColors.emeraldEnd, points: [0.45, 0.5, 0.52, 0.58, 0.6, 0.62, 0.67]) {
                        onOpenCardioMetric(.hrRecovery)
                    }
                    cardioSparkCard(title: "Foco cardiovascular", value: "95", unit: "%", status: "Aeróbico bajo", color: BevelColors.skyBlue, points: [0.7, 0.75, 0.8, 0.85, 0.9, 0.92, 0.95]) {
                        onOpenCardioMetric(.cardioLoad)
                    }
                    cardioSparkCard(title: "Zonas de FC", value: "Zona 1 · 45 min", unit: "", status: "Aeróbico ligero", color: BevelColors.emeraldEnd, points: [0.3, 0.5, 0.65, 0.6, 0.75, 0.8, 0.85]) {
                        onOpenCardioMetric(.activitiesDuration)
                    }
                }

                // 8. Fuerza + Frescura Muscular Grid
                Text("Fuerza")
                    .font(ImprovingFont.sectionTitle(18))
                    .foregroundColor(BevelColors.textPrimary)

                HStack(spacing: 12) {
                    Button { showStrengthSheet = true } label: {
                        BevelCard(cornerRadius: 18) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("16")
                                    .font(ImprovingFont.metricHero(22))
                                    .foregroundColor(BevelColors.textPrimary)
                                Text("Total series (7d)")
                                    .font(ImprovingFont.caption(12))
                                    .foregroundColor(BevelColors.textSecondary)
                                Text("↑ +2 vs sem. ant.")
                                    .font(ImprovingFont.caption(11.5))
                                    .fontWeight(.semibold)
                                    .foregroundColor(BevelColors.emeraldEnd)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                        }
                    }

                    Button { showStrengthSheet = true } label: {
                        BevelCard(cornerRadius: 18) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(totalVolumeKg) kg")
                                    .font(ImprovingFont.metricHero(22))
                                    .foregroundColor(BevelColors.textPrimary)
                                Text("Volumen total")
                                    .font(ImprovingFont.caption(12))
                                    .foregroundColor(BevelColors.textSecondary)
                                Text("Toca para registrar")
                                    .font(ImprovingFont.caption(11.5))
                                    .fontWeight(.semibold)
                                    .foregroundColor(BevelColors.skyBlue)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                        }
                    }
                }

                BevelCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Frescura muscular")
                                .font(ImprovingFont.cardTitle(16))
                                .foregroundColor(BevelColors.textPrimary)
                            Spacer()
                            Text("Recuperación local")
                                .font(ImprovingFont.caption(12))
                                .foregroundColor(BevelColors.textSecondary)
                        }

                        let muscles: [(String, Int)] = [
                            ("Pectorales", 4), ("Dorsales", 100),
                            ("Bíceps", 100), ("Tríceps", 12),
                            ("Cuádriceps", 98), ("Glúteos", 98)
                        ]

                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                            ForEach(muscles, id: \.0) { name, pct in
                                let c = pct < 35 ? BevelColors.coralHigh : (pct < 70 ? BevelColors.amberStart : BevelColors.emeraldEnd)
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(name)
                                            .font(ImprovingFont.cardTitle(13))
                                            .foregroundColor(BevelColors.textPrimary)
                                        Spacer()
                                        Text("\(pct)%")
                                            .font(ImprovingFont.caption(12))
                                            .fontWeight(.bold)
                                            .foregroundColor(c)
                                    }
                                    HStack(spacing: 3) {
                                        ForEach(0..<10, id: \.self) { seg in
                                            let filled = seg < (pct / 10)
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(filled ? c : BevelColors.trackGroove)
                                                .frame(height: 6)
                                        }
                                    }
                                }
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 14).fill(BevelColors.surfaceOverlay))
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 120)
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
                                        .foregroundColor(store.restTimerRunning ? BevelColors.emeraldEnd : BevelColors.textPrimary)
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

                        ForEach(store.strengthSets) { s in
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
                                    .foregroundColor(s.completed ? BevelColors.emeraldEnd : BevelColors.textSecondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(s.completed ? BevelColors.greenSoftBg : BevelColors.trackGroove))
                                }
                                .padding(14)
                            }
                        }

                        Button {
                            store.addStrengthSet()
                        } label: {
                            Text("+ Añadir serie de prensa / sentadilla")
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

    private func trainingLoadCard(title: String, value: String, status: String, color: Color, fillFraction: Double, onClick: @escaping () -> Void) -> some View {
        Button(action: onClick) {
            BevelCard(cornerRadius: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(title)
                            .font(ImprovingFont.cardTitle(14.5))
                            .foregroundColor(BevelColors.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(BevelColors.textMuted)
                    }

                    ZStack {
                        Canvas { ctx, sz in
                            let strokeW: CGFloat = 8
                            let radius = min(sz.width * 0.44, sz.height - strokeW)
                            let center = CGPoint(x: sz.width / 2, y: sz.height - 4)
                            var track = Path()
                            track.addArc(center: center, radius: radius, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
                            ctx.stroke(track, with: .color(BevelColors.trackGroove), style: StrokeStyle(lineWidth: strokeW, lineCap: .round))

                            var prog = Path()
                            prog.addArc(center: center, radius: radius, startAngle: .degrees(180), endAngle: .degrees(180 + 180 * fillFraction), clockwise: false)
                            ctx.stroke(prog, with: .color(color), style: StrokeStyle(lineWidth: strokeW, lineCap: .round))
                        }
                        .frame(height: 52)

                        Text(value)
                            .font(ImprovingFont.metricHero(22))
                            .monospacedDigit()
                            .foregroundColor(BevelColors.textPrimary)
                            .offset(y: 12)
                    }

                    HStack(spacing: 5) {
                        Circle().fill(color).frame(width: 6, height: 6)
                        Text(status)
                            .font(ImprovingFont.caption(12))
                            .fontWeight(.medium)
                            .foregroundColor(color)
                    }
                }
                .padding(14)
            }
        }
    }

    private func cardioSparkCard(title: String, value: String, unit: String, status: String, color: Color, points: [Double], onClick: @escaping () -> Void) -> some View {
        Button(action: onClick) {
            BevelCard(cornerRadius: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(ImprovingFont.caption(11.5))
                        .foregroundColor(BevelColors.textSecondary)
                        .lineLimit(1)

                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(value)
                            .font(ImprovingFont.metricTile(17))
                            .monospacedDigit()
                            .foregroundColor(BevelColors.textPrimary)
                            .lineLimit(1)
                        if !unit.isEmpty {
                            Text(unit)
                                .font(ImprovingFont.caption(11.5))
                                .foregroundColor(BevelColors.textSecondary)
                        }
                    }

                    HStack {
                        Text(status)
                            .font(ImprovingFont.caption(11))
                            .fontWeight(.semibold)
                            .foregroundColor(color)
                        Spacer()
                        TrendSparklineWithBand(points: points, lineColor: color)
                            .frame(width: 48, height: 18)
                    }
                }
                .padding(14)
            }
        }
    }
}

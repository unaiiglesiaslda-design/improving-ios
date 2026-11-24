import SwiftUI

struct WorkoutDetailScreen: View {
    @ObservedObject var store: ImprovingStore
    let workout: EffortEventItem
    let onBack: () -> Void

    @State private var showShareSheet: Bool = false
    @State private var showEditSheet: Bool = false
    @State private var showDeleteConfirm: Bool = false

    private var liveWorkout: EffortEventItem {
        let iso = workout.dateIso ?? store.selectedDateIso
        if let match = store.activeHistory[iso]?.workouts.first(where: { $0.id == workout.id }) {
            return match
        }
        return store.selectedWorkoutItem?.id == workout.id ? (store.selectedWorkoutItem ?? workout) : workout
    }

    private func formatDuration(_ mins: Int) -> String {
        if mins >= 60 {
            return "\(mins / 60) h \(String(format: "%02d", mins % 60)) min"
        }
        return "\(mins) min"
    }

    var body: some View {
        let w = liveWorkout
        let iso = w.dateIso ?? store.selectedDateIso
        let daySummary = store.activeHistory[iso]
        let sessionSamples = store.workoutIntradaySamples(for: w)
        let hrrVal = w.hrRecovery1MinBpm ?? ((daySummary?.workouts.count == 1) ? daySummary?.hrRecoveryBpm : nil)

        // Resolve Z0..Z5 minutes for this workout (strictly real: workout's own 6-zone array, or day's zones when single workout)
        let zone6Minutes: [Int]? = {
            if let z6 = w.hrZoneMinutes6, z6.count == 6, z6.reduce(0, +) > 0 {
                return z6
            }
            if let day = daySummary, day.workouts.count == 1 {
                let z15 = day.hrZoneMinutes
                if z15.count == 5 && z15.reduce(0, +) > 0 {
                    return [day.hrZone0Minutes ?? 0] + z15
                }
            }
            return nil
        }()

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AtmosphericHeroHeader(
                    title: w.title,
                    subtitle: "\(w.categoryLabel) · \(w.timeRange)",
                    style: .fitness,
                    onBack: onBack,
                    rightPrimaryIcon: "square.and.arrow.up",
                    onRightPrimary: { showShareSheet = true },
                    rightSecondaryIcon: "pencil",
                    onRightSecondary: { showEditSheet = true }
                ) {
                    BevelRecessedRingGauge(
                        progress: min(max(Double(w.strainPct) / 100.0, 0.03), 1.0),
                        centerText: "\(w.strainPct)%",
                        label: "",
                        kind: .strain,
                        size: 168,
                        strokeWidth: 16,
                        subLabel: iso,
                        centerSubtitle: String(format: "Strain %.1f / 21", locale: Locale(identifier: "es_ES"), w.strainScore),
                        hasData: true
                    )
                }

                VStack(alignment: .leading, spacing: 14) {
                    // 1. Core Workout Metrics Grid
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        HeaderedMetricCard(
                            icon: "timer",
                            title: "Duración",
                            value: formatDuration(w.durationMin)
                        )
                        HeaderedMetricCard(
                            icon: "flame.fill",
                            title: "Energía activa",
                            value: w.kcal > 0 ? "\(w.kcal)" : "--",
                            unit: w.kcal > 0 ? "kcal" : ""
                        )
                        HeaderedMetricCard(
                            icon: "heart.fill",
                            title: "FC media",
                            value: w.avgHrBpm > 0 ? "\(w.avgHrBpm)" : "--",
                            unit: w.avgHrBpm > 0 ? "ppm" : ""
                        )
                        HeaderedMetricCard(
                            icon: "heart.text.square.fill",
                            title: "Recup. FC (1 min)",
                            value: hrrVal.map { "-\(Int($0.rounded()))" } ?? "--",
                            unit: hrrVal != nil ? "ppm" : ""
                        )

                        if let dist = w.distanceKm, dist > 0.05 {
                            HeaderedMetricCard(
                                icon: "figure.run",
                                title: "Distancia",
                                value: String(format: "%.2f", locale: Locale(identifier: "es_ES"), dist),
                                unit: "km"
                            )
                        }
                        if let elev = w.elevationM, elev > 1 {
                            HeaderedMetricCard(
                                icon: "mountain.2.fill",
                                title: "Desnivel positivo",
                                value: "\(Int(elev.rounded()))",
                                unit: "m"
                            )
                        }
                        if let sets = w.totalSets, sets > 0 {
                            HeaderedMetricCard(
                                icon: "number.square.fill",
                                title: "Series completadas",
                                value: "\(sets)"
                            )
                        }
                        if let vol = w.totalVolumeKg, vol > 0 {
                            HeaderedMetricCard(
                                icon: "dumbbell.fill",
                                title: "Volumen muscular",
                                value: "\(Int(vol.rounded()))",
                                unit: "kg"
                            )
                        }
                    }

                    // 2. Heart Rate Zones Breakdown (Z0 - Z5)
                    BevelCard(cornerRadius: 20) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Zonas de frecuencia cardíaca")
                                    .font(ImprovingFont.sectionTitle(17))
                                    .foregroundColor(BevelColors.textPrimary)
                                Spacer()
                                if w.avgHrBpm > 0 {
                                    Text("Media \(w.avgHrBpm) ppm")
                                        .font(ImprovingFont.caption(12))
                                        .foregroundColor(BevelColors.amberStart)
                                }
                            }

                            if let z6 = zone6Minutes {
                                let totalZ = max(z6.reduce(0, +), 1)
                                let specs: [(label: String, name: String, color: Color)] = [
                                    ("Z5", "Máxima (90–100%)", BevelColors.coralHigh),
                                    ("Z4", "Umbral (80–90%)", BevelColors.orangeEnd),
                                    ("Z3", "Aeróbica (70–80%)", BevelColors.amberStart),
                                    ("Z2", "Quema grasa (60–70%)", BevelColors.greenPrimary),
                                    ("Z1", "Calentamiento (50–60%)", BevelColors.skyBlue),
                                    ("Z0", "Ligera (<50%)", BevelColors.textMuted)
                                ]
                                ForEach(0..<6, id: \.self) { revIdx in
                                    let zIdx = 5 - revIdx
                                    let mins = z6[zIdx]
                                    let pct = Int((Double(mins) / Double(totalZ) * 100.0).rounded())
                                    let spec = specs[revIdx]
                                    VStack(spacing: 5) {
                                        HStack {
                                            Text(spec.label)
                                                .font(ImprovingFont.caption(12))
                                                .fontWeight(.bold)
                                                .foregroundColor(spec.color)
                                                .frame(width: 26, alignment: .leading)
                                            Text(spec.name)
                                                .font(ImprovingFont.caption(12.5))
                                                .foregroundColor(BevelColors.textSecondary)
                                            Spacer()
                                            Text("\(mins) min · \(pct)%")
                                                .font(ImprovingFont.caption(12.5))
                                                .fontWeight(.semibold)
                                                .monospacedDigit()
                                                .foregroundColor(BevelColors.textPrimary)
                                        }
                                        GeometryReader { geo in
                                            ZStack(alignment: .leading) {
                                                Capsule().fill(Color.white.opacity(0.07)).frame(height: 7)
                                                if mins > 0 {
                                                    Capsule()
                                                        .fill(spec.color)
                                                        .frame(width: max(8, geo.size.width * CGFloat(Double(mins) / Double(totalZ))), height: 7)
                                                }
                                            }
                                        }
                                        .frame(height: 7)
                                    }
                                }
                            } else {
                                Text("No hay desglose minuto a minuto por zonas Z0–Z5 registrado para esta sesión concreta.")
                                    .font(ImprovingFont.body(13.5))
                                    .foregroundColor(BevelColors.textSecondary)
                            }
                        }
                        .padding(16)
                    }

                    // 3. Session Physiological Intensity Timeline (when overlapping 5-min samples exist)
                    if sessionSamples.count >= 2 {
                        BevelCard(cornerRadius: 20) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Curva de activación en la sesión")
                                        .font(ImprovingFont.sectionTitle(17))
                                        .foregroundColor(BevelColors.textPrimary)
                                    Spacer()
                                    if let pk = sessionSamples.map(\.value).max() {
                                        Text("Pico \(Int(pk.rounded()))/100")
                                            .font(ImprovingFont.caption(12))
                                            .foregroundColor(BevelColors.orangeEnd)
                                    }
                                }

                                Canvas { ctx, sz in
                                    let vals = sessionSamples.map(\.value)
                                    let minV = max(0, (vals.min() ?? 0) - 8)
                                    let maxV = min(100, max((vals.max() ?? 100) + 8, minV + 20))
                                    let stepX = sz.width / CGFloat(max(vals.count - 1, 1))

                                    var line = Path()
                                    var area = Path()
                                    for (i, v) in vals.enumerated() {
                                        let x = CGFloat(i) * stepX
                                        let y = sz.height - CGFloat((v - minV) / (maxV - minV)) * (sz.height - 12) - 6
                                        if i == 0 {
                                            line.move(to: CGPoint(x: x, y: y))
                                            area.move(to: CGPoint(x: x, y: sz.height))
                                            area.addLine(to: CGPoint(x: x, y: y))
                                        } else {
                                            line.addLine(to: CGPoint(x: x, y: y))
                                            area.addLine(to: CGPoint(x: x, y: y))
                                        }
                                    }
                                    area.addLine(to: CGPoint(x: sz.width, y: sz.height))
                                    area.closeSubpath()

                                    ctx.fill(
                                        area,
                                        with: .linearGradient(
                                            Gradient(colors: [BevelColors.orangeEnd.opacity(0.32), .clear]),
                                            startPoint: .zero,
                                            endPoint: CGPoint(x: 0, y: sz.height)
                                        )
                                    )
                                    ctx.stroke(line, with: .color(BevelColors.amberStart), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                                }
                                .frame(height: 110)
                            }
                            .padding(16)
                        }
                    }

                    // 4. Target Muscles (Strength Sessions)
                    if let muscles = w.targetMuscles, !muscles.isEmpty {
                        BevelCard(cornerRadius: 20) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Músculos trabajados")
                                    .font(ImprovingFont.sectionTitle(17))
                                    .foregroundColor(BevelColors.textPrimary)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(muscles, id: \.self) { m in
                                            Text(m)
                                                .font(ImprovingFont.caption(12.5))
                                                .fontWeight(.semibold)
                                                .foregroundColor(BevelColors.strengthPink)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(Capsule().fill(BevelColors.strengthPink.opacity(0.14)))
                                        }
                                    }
                                }
                            }
                            .padding(16)
                        }
                    }

                    // 5. Action Buttons: Share, Edit & Delete
                    HStack(spacing: 10) {
                        Button {
                            showShareSheet = true
                        } label: {
                            Label("Compartir tarjeta", systemImage: "square.and.arrow.up")
                                .font(ImprovingFont.cardTitle(14))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(Capsule().fill(BevelColors.indigoEnd))
                        }

                        Button {
                            showEditSheet = true
                        } label: {
                            Label("Editar", systemImage: "pencil")
                                .font(ImprovingFont.cardTitle(14))
                                .foregroundColor(BevelColors.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(Capsule().fill(BevelColors.card))
                                .overlay(Capsule().strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
                        }
                    }

                    Button {
                        showDeleteConfirm = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                            Text("Eliminar entrenamiento")
                        }
                        .font(ImprovingFont.cardTitle(14))
                        .foregroundColor(BevelColors.coralHigh)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Capsule().fill(BevelColors.coralHigh.opacity(0.12)))
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 150)
        }
        .background(BevelColors.canvas)
        .confirmationDialog("¿Eliminar «\(w.title)» de tu historial?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Eliminar entrenamiento", role: .destructive) {
                store.deleteWorkout(id: w.id, dateIso: w.dateIso)
                onBack()
            }
            Button("Cancelar", role: .cancel) {}
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSummaryCardSheet(
                store: store,
                kind: .workout(w),
                onClose: { showShareSheet = false }
            )
        }
        .sheet(isPresented: $showEditSheet) {
            WorkoutEditSheet(
                store: store,
                workout: w,
                onClose: { showEditSheet = false }
            )
        }
    }
}

private struct WorkoutEditSheet: View {
    @ObservedObject var store: ImprovingStore
    let workout: EffortEventItem
    let onClose: () -> Void

    @State private var titleDraft: String = ""
    @State private var categoryDraft: String = "Cardio"
    @State private var timeRangeDraft: String = ""
    @State private var durationDraft: String = ""
    @State private var kcalDraft: String = ""
    @State private var avgHrDraft: String = ""
    @State private var distanceDraft: String = ""

    private let categories = ["Cardio", "Fuerza", "Carrera", "Ciclismo", "Movilidad", "Actividad"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    BevelCard(cornerRadius: 18) {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Nombre de la sesión").font(ImprovingFont.caption(12)).foregroundColor(BevelColors.textSecondary)
                                TextField("Ej: Carrera Zona 2", text: $titleDraft)
                                    .font(ImprovingFont.body(14.5))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .padding(11)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.cardSubtle))
                            }

                            HStack {
                                Text("Categoría").font(ImprovingFont.caption(12)).foregroundColor(BevelColors.textSecondary)
                                Spacer()
                                Picker("Categoría", selection: $categoryDraft) {
                                    ForEach(categories, id: \.self) { c in Text(c).tag(c) }
                                }
                                .pickerStyle(.menu)
                                .tint(BevelColors.skyBlue)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Horario (ej. 18:00 - 18:45)").font(ImprovingFont.caption(12)).foregroundColor(BevelColors.textSecondary)
                                TextField("18:00 - 18:45", text: $timeRangeDraft)
                                    .font(ImprovingFont.body(14))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .padding(11)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.cardSubtle))
                            }

                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                                fieldBox("Duración (min)", text: $durationDraft)
                                fieldBox("Calorías (kcal)", text: $kcalDraft)
                                fieldBox("FC media (ppm)", text: $avgHrDraft)
                                fieldBox("Distancia (km)", text: $distanceDraft, decimal: true)
                            }
                        }
                        .padding(15)
                    }

                    Button {
                        saveEdits()
                    } label: {
                        Text("Guardar cambios y recalcular esfuerzo")
                            .font(ImprovingFont.cardTitle(15))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(BevelColors.emeraldEnd))
                    }
                }
                .padding(16)
            }
            .background(BevelColors.canvas)
            .navigationTitle("Editar entrenamiento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar", action: onClose)
                }
            }
            .onAppear {
                titleDraft = workout.title
                categoryDraft = categories.contains(workout.categoryLabel) ? workout.categoryLabel : "Cardio"
                timeRangeDraft = workout.timeRange
                durationDraft = "\(workout.durationMin)"
                kcalDraft = "\(workout.kcal)"
                avgHrDraft = workout.avgHrBpm > 0 ? "\(workout.avgHrBpm)" : ""
                distanceDraft = workout.distanceKm.map { String(format: "%.2f", $0) } ?? ""
            }
        }
    }

    private func fieldBox(_ title: String, text: Binding<String>, decimal: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(ImprovingFont.caption(11.5)).foregroundColor(BevelColors.textSecondary)
            TextField("0", text: text)
                .keyboardType(decimal ? .decimalPad : .numberPad)
                .font(ImprovingFont.cardTitle(15))
                .monospacedDigit()
                .foregroundColor(BevelColors.textPrimary)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.cardSubtle))
        }
    }

    private func saveEdits() {
        let cleanTitle = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? workout.title : titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanRange = timeRangeDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? workout.timeRange : timeRangeDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let dur = max(1, Int(durationDraft) ?? workout.durationMin)
        let kcal = max(0, Int(kcalDraft) ?? workout.kcal)
        let hr = max(0, Int(avgHrDraft) ?? 0)
        let dist = Double(distanceDraft.replacingOccurrences(of: ",", with: "."))

        var updated = workout
        updated = EffortEventItem(
            id: workout.id,
            title: cleanTitle,
            timeRange: cleanRange,
            durationMin: dur,
            avgHrBpm: hr,
            strainScore: workout.strainScore,
            strainPct: workout.strainPct,
            categoryLabel: categoryDraft,
            kcal: kcal,
            distanceKm: (dist ?? 0) > 0 ? dist : nil,
            elevationM: workout.elevationM,
            dateIso: workout.dateIso ?? store.selectedDateIso,
            startEpochSec: workout.startEpochSec,
            avgPowerW: workout.avgPowerW,
            avgCadenceRpm: workout.avgCadenceRpm,
            hrZoneMinutes6: workout.hrZoneMinutes6,
            hrRecovery1MinBpm: workout.hrRecovery1MinBpm,
            totalSets: workout.totalSets,
            totalVolumeKg: workout.totalVolumeKg,
            targetMuscles: workout.targetMuscles
        )
        store.updateWorkout(updated, originalDateIso: workout.dateIso)
        onClose()
    }
}

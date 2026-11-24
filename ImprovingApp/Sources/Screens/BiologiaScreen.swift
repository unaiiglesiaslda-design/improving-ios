import SwiftUI

struct BiologiaScreen: View {
    @ObservedObject var store: ImprovingStore
    let onSelectHealthMetric: (HealthMetricKind) -> Void
    let onOpenBodyMetric: (BodyCompositionMetricKind) -> Void
    let onOpenVo2Max: () -> Void
    let onNavigate: (OverlayRoute) -> Void

    @State private var expandedCategoryId: String? = "sleep"
    @State private var showBioInfoSheet: Bool = false
    @State private var showShareBioSheet: Bool = false
    @State private var showScaleSheet: Bool = false
    @State private var showLabScannerSheet: Bool = false

    var body: some View {
        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: store.userProfile)
        let recent30 = store.trailingCalendarSummaries(days: 30)
        let rhrVals = recent30.compactMap { $0.summary?.restingHrBpm }
        let hrvVals = recent30.compactMap { $0.summary?.hrvMs }
        let sleepVals = recent30.compactMap { $0.summary?.asleepMinutes.map { Double($0) / 60.0 } }
        let stepsVals = recent30.compactMap { $0.summary?.stepsCount }
        let vo2Val = store.latestVo2Max

        let hasBioBase = !rhrVals.isEmpty || !hrvVals.isEmpty || !sleepVals.isEmpty || vo2Val != nil
        let meanRhr = rhrVals.isEmpty ? nil : (rhrVals.reduce(0, +) / Double(rhrVals.count))
        let meanHrv = hrvVals.isEmpty ? nil : (hrvVals.reduce(0, +) / Double(hrvVals.count))
        let meanSleep = sleepVals.isEmpty ? nil : (sleepVals.reduce(0, +) / Double(sleepVals.count))
        let meanSteps = stepsVals.isEmpty ? nil : (stepsVals.reduce(0, +) / stepsVals.count)

        let bioEval = WhoopPhysiologyEngine.computeBiologicalAge(
            profile: store.userProfile,
            meanRhr: meanRhr,
            meanHrv: meanHrv,
            meanSleepHours: meanSleep,
            meanSteps: meanSteps,
            vo2Max: vo2Val,
            latestWeightKg: store.latestBodyWeightKg
        )
        let chronologicalAge = bioEval.chronoAgeYears
        let bioDelta = hasBioBase ? bioEval.deltaYears : 0.0
        let bioAge = hasBioBase ? bioEval.bioAgeYears : chronologicalAge

        let hrvSeries = recent30.map { $0.summary?.hrvMs }
        let rhrSeries = recent30.map { $0.summary?.restingHrBpm }
        let weightSeries = recent30.map { $0.summary?.bodyWeightKg }
        let fatSeries = recent30.map { $0.summary?.bodyFatPct }
        let leanSeries = recent30.map { $0.summary?.leanMassKg }
        let vo2Series = recent30.map { $0.summary?.vo2MaxMlKgMin }
        let latestBiomarkers = store.latestBiomarkersByName

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 1. Atmospheric Biological Age Hero (P2: Real Action Menu on ···)
                ZStack(alignment: .top) {
                    LinearGradient(
                        colors: BevelColors.isDarkMode ? [Color(hex: 0x1A2E2A), Color(hex: 0x172022), BevelColors.canvas] : [BevelColors.canvas, BevelColors.canvas],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 330)
                    .ignoresSafeArea(edges: .top)

                    VStack(spacing: 8) {
                        HStack {
                            Spacer()
                            Menu {
                                Button { showShareBioSheet = true } label: {
                                    Label("Compartir Edad Biológica", systemImage: "square.and.arrow.up")
                                }
                                Button { showBioInfoSheet = true } label: {
                                    Label("Cómo se calcula", systemImage: "info.circle")
                                }
                                Divider()
                                Button { showScaleSheet = true } label: {
                                    Label("Registrar peso / báscula", systemImage: "scalemass.fill")
                                }
                                Button { showLabScannerSheet = true } label: {
                                    Label("Subir analítica de sangre (IA)", systemImage: "doc.text.viewfinder")
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

                        Text("Edad biológica")
                            .font(ImprovingFont.displayLarge(23))
                            .foregroundColor(BevelColors.textPrimary)
                        Text("A fecha \(store.fullDateLabel)")
                            .font(ImprovingFont.caption(13.5))
                            .foregroundColor(BevelColors.textSecondary)

                        BioAgeCurvedDial(
                            bioAgeYears: bioAge,
                            chronoAgeYears: chronologicalAge,
                            diffYears: bioDelta,
                            sampledDays: store.activeHistory.count,
                            hasData: hasBioBase
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }

                VStack(alignment: .leading, spacing: 16) {
                    // Quick Biology Actions: Scale + Blood Test AI (N6!)
                    HStack(spacing: 10) {
                        Button { showScaleSheet = true } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "scalemass.fill")
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundColor(BevelColors.skyBlue)
                                Text("+ Báscula / TA")
                                    .font(ImprovingFont.cardTitle(13.5))
                                    .foregroundColor(BevelColors.textPrimary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BevelColors.card))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
                        }

                        Button { showLabScannerSheet = true } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "doc.text.viewfinder")
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundColor(BevelColors.bioTeal)
                                Text("+ Analítica IA")
                                    .font(ImprovingFont.cardTitle(13.5))
                                    .foregroundColor(BevelColors.textPrimary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BevelColors.card))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(BevelColors.bioTeal.opacity(0.35), lineWidth: 0.8))
                        }
                    }

                    Text("Biomarcadores de edad")
                        .font(ImprovingFont.sectionTitle(18.5))
                        .foregroundColor(BevelColors.textPrimary)

                    if let avgS = meanSleep {
                        let hrs = Int(avgS)
                        let mins = Int(((avgS - Double(hrs)) * 60).rounded())
                        bioCategoryCard(
                            id: "sleep",
                            icon: "moon.fill",
                            ringPrimary: BevelColors.bioTeal,
                            ringSecondary: BevelColors.trackGroove,
                            title: "Sueño",
                            subtitle: "\(hrs) h \(String(format: "%02d", mins)) min promedio",
                            subtitleColor: BevelColors.bioTeal
                        ) {
                            BioDotRangeSlider(
                                title: "Duración media (30 d)",
                                valueLabel: "\(hrs) h \(String(format: "%02d", mins)) min",
                                minLabel: "5 h",
                                maxLabel: "10 h",
                                deltaText: "",
                                deltaUnit: "",
                                positionFrac: min(max((avgS - 5.0) / 5.0, 0.05), 0.95),
                                fillStartFrac: min(max((norms.sleepLowHours - 5.0) / 5.0, 0.10), 0.70),
                                fillEndFrac: min(max((norms.sleepHighHours - 5.0) / 5.0, 0.45), 0.96),
                                accentColor: BevelColors.bioTeal
                            )
                        }
                    }

                    if let avgSt = meanSteps {
                        bioCategoryCard(
                            id: "activity",
                            icon: "figure.run",
                            ringPrimary: BevelColors.bioTeal,
                            ringSecondary: BevelColors.amberStart,
                            title: "Actividad",
                            subtitle: "\(avgSt) pasos/día (30 d)",
                            subtitleColor: BevelColors.bioTeal
                        ) {
                            BioDotRangeSlider(
                                title: "Número de pasos medio",
                                valueLabel: String(format: "%.1fk", Double(avgSt) / 1000.0),
                                minLabel: "0",
                                maxLabel: "16k",
                                deltaText: "",
                                deltaUnit: "",
                                positionFrac: min(max(Double(avgSt) / 16000.0, 0.04), 0.96),
                                fillStartFrac: min(max(Double(norms.dailyStepsGoal) / 16000.0, 0.25), 0.75),
                                fillEndFrac: 0.90,
                                accentColor: BevelColors.bioTeal
                            )
                        }
                    }

                    if meanRhr != nil || vo2Val != nil {
                        bioCategoryCard(
                            id: "fitness",
                            icon: "heart.fill",
                            ringPrimary: BevelColors.bioTeal,
                            ringSecondary: BevelColors.amberStart,
                            title: "Fitness",
                            subtitle: meanRhr.map { String(format: "FCR media %.1f ppm", locale: Locale(identifier: "es_ES"), $0) } ?? "VO₂ máx. registrado",
                            subtitleColor: BevelColors.textSecondary
                        ) {
                            if let v = vo2Val {
                                BioDotRangeSlider(
                                    title: "VO₂ máx.",
                                    valueLabel: String(format: "%.1f", locale: Locale(identifier: "es_ES"), v),
                                    minLabel: "20",
                                    maxLabel: "65",
                                    deltaText: "",
                                    deltaUnit: "",
                                    positionFrac: min(max((v - 20.0) / 45.0, 0.05), 0.95),
                                    fillStartFrac: min(max((norms.vo2GoodThreshold - 20.0) / 45.0, 0.10), 0.75),
                                    fillEndFrac: min(max((norms.vo2ExcellentThreshold - 20.0) / 45.0, 0.35), 0.95),
                                    accentColor: BevelColors.amberStart
                                )
                            }
                            if let r = meanRhr {
                                if vo2Val != nil { Divider().background(BevelColors.divider) }
                                BioDotRangeSlider(
                                    title: "FC en reposo (30 d)",
                                    valueLabel: String(format: "%.1f ppm", locale: Locale(identifier: "es_ES"), r),
                                    minLabel: "40",
                                    maxLabel: "90",
                                    deltaText: "",
                                    deltaUnit: "",
                                    positionFrac: min(max((r - 40.0) / 50.0, 0.05), 0.95),
                                    fillStartFrac: min(max((norms.rhrLowBpm - 40.0) / 50.0, 0.04), 0.50),
                                    fillEndFrac: min(max((norms.rhrHighBpm - 40.0) / 50.0, 0.20), 0.80),
                                    accentColor: BevelColors.bioTeal
                                )
                            }
                        }
                    }

                    // N6: Analíticas de Sangre y Biomarcadores Clínicos
                    HStack {
                        Text("Analíticas de sangre")
                            .font(ImprovingFont.sectionTitle(18.5))
                            .foregroundColor(BevelColors.textPrimary)
                        Spacer()
                        Button("+ Subir") { showLabScannerSheet = true }
                            .font(ImprovingFont.caption(13))
                            .fontWeight(.semibold)
                            .foregroundColor(BevelColors.bioTeal)
                    }
                    .padding(.top, 4)

                    if latestBiomarkers.isEmpty {
                        Button { showLabScannerSheet = true } label: {
                            BevelCard(cornerRadius: 20) {
                                HStack(spacing: 12) {
                                    Image(systemName: "cross.case.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(BevelColors.bioTeal)
                                        .frame(width: 42, height: 42)
                                        .background(Circle().fill(BevelColors.bioTeal.opacity(0.15)))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Añade tu última analítica con Gemini IA")
                                            .font(ImprovingFont.cardTitle(14.5))
                                            .foregroundColor(BevelColors.textPrimary)
                                        Text("Foto o PDF · Extrae Vitamina D, Ferritina, Glucosa, Lípidos, TSH…")
                                            .font(ImprovingFont.caption(12))
                                            .foregroundColor(BevelColors.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(BevelColors.textMuted)
                                }
                                .padding(15)
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        BevelCard(cornerRadius: 20) {
                            VStack(alignment: .leading, spacing: 10) {
                                if let latestRep = store.labReports.first {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(latestRep.title)
                                                .font(ImprovingFont.cardTitle(14.5))
                                                .foregroundColor(BevelColors.textPrimary)
                                            Text("\(latestRep.dateIso) · \(latestBiomarkers.count) biomarcadores activos")
                                                .font(ImprovingFont.caption(11.5))
                                                .foregroundColor(BevelColors.textSecondary)
                                        }
                                        Spacer()
                                        Menu {
                                            Button("Añadir nueva analítica / marcador", systemImage: "plus") {
                                                showLabScannerSheet = true
                                            }
                                            Button("Eliminar último informe", systemImage: "trash", role: .destructive) {
                                                store.deleteLabReport(id: latestRep.id)
                                            }
                                        } label: {
                                            Image(systemName: "ellipsis.circle")
                                                .font(.system(size: 16))
                                                .foregroundColor(BevelColors.textMuted)
                                        }
                                    }
                                    Divider().background(BevelColors.divider)
                                }

                                ForEach(Array(latestBiomarkers.prefix(10).enumerated()), id: \.element.id) { idx, b in
                                    LabBiomarkerBarRow(item: b)
                                    if idx < min(latestBiomarkers.count, 10) - 1 {
                                        Divider().background(BevelColors.divider)
                                    }
                                }
                            }
                            .padding(16)
                        }
                    }

                    // 4. Otros biomarcadores (P2: All wired to dedicated charts & VO₂ max bug FIXED!)
                    Text("Otros biomarcadores")
                        .font(ImprovingFont.sectionTitle(18.5))
                        .foregroundColor(BevelColors.textPrimary)
                        .padding(.top, 4)

                    if let w = store.latestBodyWeightKg {
                        otherBioCard(title: "Peso", statusText: "Registrado", statusColor: BevelColors.skyBlue, value: String(format: "%.1f kg", locale: Locale(identifier: "es_ES"), w), lineColor: BevelColors.skyBlue, points: weightSeries) {
                            onOpenBodyMetric(.weight)
                        }
                    }
                    if store.dataAvailability.hasHrvData || meanHrv != nil {
                        let val = store.dataAvailability.hasHrvData ? store.hrvMs : (meanHrv ?? 0)
                        otherBioCard(title: "VFC histórico", statusText: "Real", statusColor: BevelColors.greenPrimary, value: String(format: "%.1f ms", locale: Locale(identifier: "es_ES"), val), lineColor: BevelColors.greenPrimary, points: hrvSeries) {
                            onSelectHealthMetric(.hrv)
                        }
                    }
                    if store.dataAvailability.hasRestingHrData || meanRhr != nil {
                        let val = store.dataAvailability.hasRestingHrData ? store.restingHrBpm : (meanRhr ?? 0)
                        otherBioCard(title: "Históricos FCR", statusText: "Real", statusColor: BevelColors.skyBlue, value: String(format: "%.1f ppm", locale: Locale(identifier: "es_ES"), val), lineColor: BevelColors.skyBlue, points: rhrSeries) {
                            onSelectHealthMetric(.restingHeartRate)
                        }
                    }
                    if let fat = store.latestBodyFatPct {
                        otherBioCard(title: "Grasa corporal", statusText: "Registrado", statusColor: BevelColors.amberStart, value: String(format: "%.1f %%", locale: Locale(identifier: "es_ES"), fat), lineColor: BevelColors.amberStart, points: fatSeries) {
                            onOpenBodyMetric(.bodyFat)
                        }
                    }
                    if let lean = store.latestLeanMassKg {
                        otherBioCard(title: "Masa magra", statusText: "Registrado", statusColor: BevelColors.bioTeal, value: String(format: "%.1f kg", locale: Locale(identifier: "es_ES"), lean), lineColor: BevelColors.bioTeal, points: leanSeries) {
                            onOpenBodyMetric(.leanMass)
                        }
                    }
                    if let v = vo2Val {
                        otherBioCard(title: "VO₂ máx.", statusText: "Registrado", statusColor: BevelColors.amberStart, value: String(format: "%.1f", locale: Locale(identifier: "es_ES"), v), lineColor: BevelColors.amberStart, points: vo2Series) {
                            onOpenVo2Max()
                        }
                    }
                    if let bp = store.latestBloodPressure {
                        Button { onOpenBodyMetric(.bloodPressure) } label: {
                            BevelCard(cornerRadius: 20) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("Presión arterial").font(ImprovingFont.cardTitle(15)).foregroundColor(BevelColors.textPrimary)
                                        Text("\(bp.sys)/\(bp.dia) mmHg")
                                            .font(ImprovingFont.caption(13.5))
                                            .fontWeight(.semibold)
                                            .foregroundColor(BevelColors.greenPrimary)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(BevelColors.textMuted)
                                }
                                .padding(16)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    if !hasBioBase {
                        BevelCard(cornerRadius: 20) {
                            Text("Importa tus datos de Apple Health o conecta tu dispositivo en Ajustes para calcular tu biología real sin valores inventados.")
                                .font(ImprovingFont.body(13.5))
                                .foregroundColor(BevelColors.textSecondary)
                                .padding(16)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 155)
        }
        .background(BevelColors.canvas)
        .sheet(isPresented: $showBioInfoSheet) {
            MetricMethodologyInfoSheet(kind: .biologicalAge, onClose: { showBioInfoSheet = false })
        }
        .sheet(isPresented: $showShareBioSheet) {
            ShareSummaryCardSheet(store: store, kind: .biologicalAge, onClose: { showShareBioSheet = false })
        }
        .sheet(isPresented: $showScaleSheet) {
            ManualScaleLoggerSheet(store: store, onClose: { showScaleSheet = false })
        }
        .sheet(isPresented: $showLabScannerSheet) {
            LabReportScannerSheet(store: store, onClose: { showLabScannerSheet = false })
        }
    }

    private func bioCategoryCard<Content: View>(
        id: String,
        icon: String,
        ringPrimary: Color,
        ringSecondary: Color,
        title: String,
        subtitle: String,
        subtitleColor: Color,
        @ViewBuilder details: @escaping () -> Content
    ) -> some View {
        let isExpanded = expandedCategoryId == id
        return BevelCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        expandedCategoryId = isExpanded ? nil : id
                    }
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            Canvas { ctx, sz in
                                let center = CGPoint(x: sz.width / 2, y: sz.height / 2)
                                let r = min(sz.width, sz.height) / 2 - 4
                                var p1 = Path()
                                p1.addArc(center: center, radius: r, startAngle: .degrees(-80), endAngle: .degrees(80), clockwise: false)
                                ctx.stroke(p1, with: .color(ringPrimary), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                                var p2 = Path()
                                p2.addArc(center: center, radius: r, startAngle: .degrees(100), endAngle: .degrees(260), clockwise: false)
                                ctx.stroke(p2, with: .color(ringSecondary), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                            }
                            .frame(width: 48, height: 48)
                            Image(systemName: icon)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(ringPrimary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(ImprovingFont.cardTitle(16))
                                .foregroundColor(BevelColors.textPrimary)
                            Text(subtitle)
                                .font(ImprovingFont.cardTitle(14))
                                .foregroundColor(subtitleColor)
                        }
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(BevelColors.textMuted)
                    }
                }

                if isExpanded {
                    Divider().background(BevelColors.divider)
                    details()
                }
            }
            .padding(16)
        }
    }

    private func otherBioCard(title: String, statusText: String, statusColor: Color, value: String, lineColor: Color, points: [Double?], onClick: @escaping () -> Void) -> some View {
        Button(action: onClick) {
            BevelCard(cornerRadius: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title).font(ImprovingFont.cardTitle(15)).foregroundColor(BevelColors.textPrimary)
                        HStack(spacing: 5) {
                            Text(statusText).font(ImprovingFont.caption(13)).fontWeight(.semibold).foregroundColor(statusColor)
                            Text("·").foregroundColor(BevelColors.textMuted)
                            Text(value).font(ImprovingFont.caption(13)).fontWeight(.semibold).monospacedDigit().foregroundColor(BevelColors.textPrimary)
                        }
                    }
                    Spacer()
                    if points.compactMap({ $0 }).count >= 2 {
                        TrendSparklineWithBand(optionalPoints: points, lineColor: lineColor, fillUnder: true, showGlowDot: true)
                            .frame(width: 82, height: 34)
                    }
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(BevelColors.textMuted)
                }
                .padding(16)
            }
        }
        .buttonStyle(.plain)
    }
}

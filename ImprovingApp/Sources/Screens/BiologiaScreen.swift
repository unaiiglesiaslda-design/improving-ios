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
        let bioSnap = store.biologicalAgeSnapshot()
        let bioEval = bioSnap.eval
        let hasBioBase = bioSnap.hasData
        let meanRhr = bioSnap.meanRhr
        let meanHrv = bioSnap.meanHrv
        let meanSleep = bioSnap.meanSleep
        let meanSteps = bioSnap.meanSteps
        let vo2Val = bioSnap.vo2Val

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

                    HStack(alignment: .firstTextBaseline) {
                        Text("Biomarcadores de edad")
                            .font(ImprovingFont.sectionTitle(18.5))
                            .foregroundColor(BevelColors.textPrimary)
                        Spacer()
                        if hasBioBase {
                            Text(impactPillText(bioDelta))
                                .font(ImprovingFont.caption(12))
                                .fontWeight(.bold)
                                .monospacedDigit()
                                .foregroundColor(impactColor(bioDelta))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(impactColor(bioDelta).opacity(0.14)))
                        }
                    }

                    if let avgS = meanSleep {
                        let hrs = Int(avgS)
                        let mins = Int(((avgS - Double(hrs)) * 60).rounded())
                        bioCategoryCard(
                            id: "sleep",
                            icon: "moon.fill",
                            ringPrimary: impactColor(bioEval.sleepDelta),
                            ringSecondary: BevelColors.trackGroove,
                            title: "Sueño",
                            subtitle: "\(hrs) h \(String(format: "%02d", mins)) min promedio",
                            subtitleColor: BevelColors.textSecondary,
                            deltaYears: bioEval.sleepDelta
                        ) {
                            BioDotRangeSlider(
                                title: "Duración media (30 d)",
                                valueLabel: "\(hrs) h \(String(format: "%02d", mins)) min",
                                minLabel: "5 h",
                                maxLabel: "10 h",
                                deltaText: sliderDeltaNumber(bioEval.sleepDelta),
                                deltaUnit: "años",
                                positionFrac: min(max((avgS - 5.0) / 5.0, 0.05), 0.95),
                                fillStartFrac: min(max((norms.sleepLowHours - 5.0) / 5.0, 0.10), 0.70),
                                fillEndFrac: min(max((norms.sleepHighHours - 5.0) / 5.0, 0.45), 0.96),
                                accentColor: BevelColors.bioTeal,
                                deltaColor: impactColor(bioEval.sleepDelta)
                            )
                        }
                    }

                    if let avgSt = meanSteps {
                        bioCategoryCard(
                            id: "activity",
                            icon: "figure.run",
                            ringPrimary: impactColor(bioEval.activityDelta),
                            ringSecondary: BevelColors.trackGroove,
                            title: "Actividad",
                            subtitle: "\(avgSt) pasos/día (30 d)",
                            subtitleColor: BevelColors.textSecondary,
                            deltaYears: bioEval.activityDelta
                        ) {
                            BioDotRangeSlider(
                                title: "Número de pasos medio",
                                valueLabel: String(format: "%.1fk", Double(avgSt) / 1000.0),
                                minLabel: "0",
                                maxLabel: "16k",
                                deltaText: sliderDeltaNumber(bioEval.activityDelta),
                                deltaUnit: "años",
                                positionFrac: min(max(Double(avgSt) / 16000.0, 0.04), 0.96),
                                fillStartFrac: min(max(Double(norms.dailyStepsGoal) / 16000.0, 0.25), 0.75),
                                fillEndFrac: 0.90,
                                accentColor: BevelColors.bioTeal,
                                deltaColor: impactColor(bioEval.activityDelta)
                            )
                        }
                    }

                    if meanRhr != nil || vo2Val != nil {
                        bioCategoryCard(
                            id: "fitness",
                            icon: "heart.fill",
                            ringPrimary: impactColor(bioEval.fitnessDelta),
                            ringSecondary: BevelColors.trackGroove,
                            title: "Fitness cardiovascular",
                            subtitle: meanRhr.map { String(format: "FCR media %.1f ppm", locale: Locale(identifier: "es_ES"), $0) } ?? "VO₂ máx. registrado",
                            subtitleColor: BevelColors.textSecondary,
                            deltaYears: bioEval.fitnessDelta
                        ) {
                            if let v = vo2Val {
                                BioDotRangeSlider(
                                    title: "VO₂ máx.",
                                    valueLabel: String(format: "%.1f", locale: Locale(identifier: "es_ES"), v),
                                    minLabel: "20",
                                    maxLabel: "65",
                                    deltaText: sliderDeltaNumber(bioEval.vo2Delta),
                                    deltaUnit: "años",
                                    positionFrac: min(max((v - 20.0) / 45.0, 0.05), 0.95),
                                    fillStartFrac: min(max((norms.vo2GoodThreshold - 20.0) / 45.0, 0.10), 0.75),
                                    fillEndFrac: min(max((norms.vo2ExcellentThreshold - 20.0) / 45.0, 0.35), 0.95),
                                    accentColor: BevelColors.amberStart,
                                    deltaColor: impactColor(bioEval.vo2Delta)
                                )
                            }
                            if let r = meanRhr {
                                if vo2Val != nil { Divider().background(BevelColors.divider) }
                                BioDotRangeSlider(
                                    title: "FC en reposo (30 d)",
                                    valueLabel: String(format: "%.1f ppm", locale: Locale(identifier: "es_ES"), r),
                                    minLabel: "40",
                                    maxLabel: "90",
                                    deltaText: sliderDeltaNumber(bioEval.rhrDelta),
                                    deltaUnit: "años",
                                    positionFrac: min(max((r - 40.0) / 50.0, 0.05), 0.95),
                                    fillStartFrac: min(max((norms.rhrLowBpm - 40.0) / 50.0, 0.04), 0.50),
                                    fillEndFrac: min(max((norms.rhrHighBpm - 40.0) / 50.0, 0.20), 0.80),
                                    accentColor: BevelColors.bioTeal,
                                    deltaColor: impactColor(bioEval.rhrDelta)
                                )
                            }
                        }
                    }

                    if let avgH = meanHrv, avgH > 2.0 {
                        bioCategoryCard(
                            id: "autonomic",
                            icon: "waveform.path.ecg",
                            ringPrimary: impactColor(bioEval.autonomicDelta),
                            ringSecondary: BevelColors.trackGroove,
                            title: "Sistema autónomo (VFC)",
                            subtitle: String(format: "%.1f ms promedio (30 d)", locale: Locale(identifier: "es_ES"), avgH),
                            subtitleColor: BevelColors.textSecondary,
                            deltaYears: bioEval.autonomicDelta
                        ) {
                            BioDotRangeSlider(
                                title: "VFC media (30 d)",
                                valueLabel: String(format: "%.1f ms", locale: Locale(identifier: "es_ES"), avgH),
                                minLabel: "20 ms",
                                maxLabel: "130 ms",
                                deltaText: sliderDeltaNumber(bioEval.autonomicDelta),
                                deltaUnit: "años",
                                positionFrac: min(max((avgH - 20.0) / 110.0, 0.04), 0.96),
                                fillStartFrac: min(max((norms.hrvLowMs - 20.0) / 110.0, 0.12), 0.72),
                                fillEndFrac: min(max((norms.hrvHighMs - 20.0) / 110.0, 0.35), 0.94),
                                accentColor: BevelColors.greenPrimary,
                                deltaColor: impactColor(bioEval.autonomicDelta)
                            )
                        }
                    }

                    if bioEval.hasBody {
                        let wNow = store.latestBodyWeightKg ?? store.userProfile.weightKg
                        let hm = max(store.userProfile.heightCm / 100.0, 1.2)
                        let bmiNow = wNow / (hm * hm)
                        let bfOpt = store.latestBodyFatPct
                        bioCategoryCard(
                            id: "body",
                            icon: "figure.stand",
                            ringPrimary: impactColor(bioEval.bodyDelta),
                            ringSecondary: BevelColors.trackGroove,
                            title: "Composición corporal",
                            subtitle: bfOpt.map { String(format: "Grasa %.1f%% · IMC %.1f", locale: Locale(identifier: "es_ES"), $0, bmiNow) }
                                ?? String(format: "IMC %.1f · %.1f kg", locale: Locale(identifier: "es_ES"), bmiNow, wNow),
                            subtitleColor: BevelColors.textSecondary,
                            deltaYears: bioEval.bodyDelta
                        ) {
                            if let bf = bfOpt {
                                BioDotRangeSlider(
                                    title: "Grasa corporal",
                                    valueLabel: String(format: "%.1f%%", locale: Locale(identifier: "es_ES"), bf),
                                    minLabel: "6%",
                                    maxLabel: "38%",
                                    deltaText: sliderDeltaNumber(bioEval.bodyDelta),
                                    deltaUnit: "años",
                                    positionFrac: min(max((bf - 6.0) / 32.0, 0.04), 0.96),
                                    fillStartFrac: min(max((norms.optimalBodyFatLowPct - 6.0) / 32.0, 0.08), 0.65),
                                    fillEndFrac: min(max((norms.optimalBodyFatHighPct - 6.0) / 32.0, 0.25), 0.85),
                                    accentColor: BevelColors.skyBlue,
                                    deltaColor: impactColor(bioEval.bodyDelta)
                                )
                            } else {
                                BioDotRangeSlider(
                                    title: "Índice de masa corporal (IMC)",
                                    valueLabel: String(format: "%.1f", locale: Locale(identifier: "es_ES"), bmiNow),
                                    minLabel: "16",
                                    maxLabel: "34",
                                    deltaText: sliderDeltaNumber(bioEval.bodyDelta),
                                    deltaUnit: "años",
                                    positionFrac: min(max((bmiNow - 16.0) / 18.0, 0.04), 0.96),
                                    fillStartFrac: min(max((norms.bmiOptimalLow - 16.0) / 18.0, 0.10), 0.55),
                                    fillEndFrac: min(max((norms.bmiOptimalHigh - 16.0) / 18.0, 0.30), 0.75),
                                    accentColor: BevelColors.skyBlue,
                                    deltaColor: impactColor(bioEval.bodyDelta)
                                )
                            }
                        }
                    }

                    // Analíticas de Sangre (integradas directamente en la Edad Biológica con impacto por biomarcador!)
                    if latestBiomarkers.isEmpty {
                        Button { showLabScannerSheet = true } label: {
                            BevelCard(cornerRadius: 24) {
                                HStack(spacing: 14) {
                                    Image(systemName: "cross.case.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(BevelColors.bioTeal)
                                        .frame(width: 48, height: 48)
                                        .background(Circle().fill(BevelColors.bioTeal.opacity(0.15)))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Analíticas de sangre")
                                            .font(ImprovingFont.cardTitle(16))
                                            .foregroundColor(BevelColors.textPrimary)
                                        Text("Sube tu PDF o foto para que ajusten tu Edad Biológica")
                                            .font(ImprovingFont.caption(12))
                                            .foregroundColor(BevelColors.textSecondary)
                                    }
                                    Spacer()
                                    Text("+ Subir")
                                        .font(ImprovingFont.caption(12))
                                        .fontWeight(.bold)
                                        .foregroundColor(BevelColors.bioTeal)
                                }
                                .padding(16)
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        let latestRep = store.labReports.first
                        bioCategoryCard(
                            id: "labs",
                            icon: "cross.case.fill",
                            ringPrimary: impactColor(bioEval.bloodLabsDelta),
                            ringSecondary: BevelColors.trackGroove,
                            title: "Analíticas de sangre",
                            subtitle: "\(latestBiomarkers.count) biomarcadores\(latestRep.map { " · \($0.dateIso)" } ?? "")",
                            subtitleColor: BevelColors.textSecondary,
                            deltaYears: bioEval.bloodLabsDelta
                        ) {
                            if let rep = latestRep {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(rep.title)
                                            .font(ImprovingFont.cardTitle(14))
                                            .foregroundColor(BevelColors.textPrimary)
                                        Text("Impacto clínico acumulado: \(impactDescription(bioEval.bloodLabsDelta))")
                                            .font(ImprovingFont.caption(11.5))
                                            .foregroundColor(impactColor(bioEval.bloodLabsDelta))
                                    }
                                    Spacer()
                                    Menu {
                                        Button("Añadir nueva analítica / marcador", systemImage: "plus") {
                                            showLabScannerSheet = true
                                        }
                                        Button("Eliminar último informe", systemImage: "trash", role: .destructive) {
                                            store.deleteLabReport(id: rep.id)
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                            .font(.system(size: 16))
                                            .foregroundColor(BevelColors.textMuted)
                                    }
                                }
                                Divider().background(BevelColors.divider)
                            }

                            ForEach(Array(bioEval.labImpacts.enumerated()), id: \.element.id) { idx, impact in
                                LabBiomarkerBarRow(item: impact.biomarker, ageDeltaYears: impact.deltaYears)
                                if idx < bioEval.labImpacts.count - 1 {
                                    Divider().background(BevelColors.divider)
                                }
                            }
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

    private func impactColor(_ deltaYears: Double) -> Color {
        if deltaYears <= -0.05 { return BevelColors.bioTeal }
        if deltaYears >= 0.05 { return BevelColors.coralHigh }
        return BevelColors.textSecondary
    }

    private func impactPillText(_ deltaYears: Double) -> String {
        if abs(deltaYears) < 0.05 { return "0,0 años" }
        return String(format: "%+.1f años", locale: Locale(identifier: "es_ES"), deltaYears)
    }

    private func sliderDeltaNumber(_ deltaYears: Double) -> String {
        if abs(deltaYears) < 0.05 { return "0,0" }
        return String(format: "%+.1f", locale: Locale(identifier: "es_ES"), deltaYears)
    }

    private func impactDescription(_ deltaYears: Double) -> String {
        if deltaYears <= -0.05 {
            return String(format: "resta %.1f años", locale: Locale(identifier: "es_ES"), abs(deltaYears))
        }
        if deltaYears >= 0.05 {
            return String(format: "suma %.1f años", locale: Locale(identifier: "es_ES"), deltaYears)
        }
        return "efecto neutro (0,0 años)"
    }

    private func bioCategoryCard<Content: View>(
        id: String,
        icon: String,
        ringPrimary: Color,
        ringSecondary: Color,
        title: String,
        subtitle: String,
        subtitleColor: Color,
        deltaYears: Double,
        @ViewBuilder details: @escaping () -> Content
    ) -> some View {
        let isExpanded = expandedCategoryId == id
        let deltaCol = impactColor(deltaYears)
        return BevelCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        expandedCategoryId = isExpanded ? nil : id
                    }
                } label: {
                    HStack(spacing: 12) {
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
                                .font(ImprovingFont.cardTitle(15.5))
                                .foregroundColor(BevelColors.textPrimary)
                                .lineLimit(1)
                            Text(subtitle)
                                .font(ImprovingFont.caption(12.5))
                                .foregroundColor(subtitleColor)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        Text(impactPillText(deltaYears))
                            .font(ImprovingFont.caption(12))
                            .fontWeight(.bold)
                            .monospacedDigit()
                            .foregroundColor(deltaCol)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(deltaCol.opacity(0.14)))
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 12.5, weight: .semibold))
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

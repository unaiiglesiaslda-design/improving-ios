import SwiftUI

struct BiologiaScreen: View {
    @ObservedObject var store: ImprovingStore
    let onSelectHealthMetric: (HealthMetricKind) -> Void
    let onNavigate: (OverlayRoute) -> Void

    @State private var expandedCategoryId: String? = "sleep"

    var body: some View {
        let chronologicalAge = store.userProfile.ageYears
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

        let bioDelta: Double = {
            guard hasBioBase else { return 0 }
            var delta = 0.0
            if let r = meanRhr { delta += (r - 58.0) * 0.12 }
            if let h = meanHrv { delta += (65.0 - h) * 0.04 }
            if let s = meanSleep { delta += (7.5 - s) * 0.45 }
            if let v = vo2Val { delta += (42.0 - v) * 0.14 }
            return AppleHealthExportImporter.round1(min(max(delta, -6.0), 6.0))
        }()
        let bioAge = max(16.0, chronologicalAge + bioDelta)

        let hrvSeries = recent30.map { $0.summary?.hrvMs }
        let rhrSeries = recent30.map { $0.summary?.restingHrBpm }
        let weightSeries = recent30.map { $0.summary?.bodyWeightKg }
        let fatSeries = recent30.map { $0.summary?.bodyFatPct }
        let leanSeries = recent30.map { $0.summary?.leanMassKg }
        let vo2Series = recent30.map { $0.summary?.vo2MaxMlKgMin }

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 1. Atmospheric Biological Age Hero (Strictly derived from real imported data!)
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
                            Button { onNavigate(.dispositivos) } label: {
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
                    Text("Biomarcadores de edad")
                        .font(ImprovingFont.sectionTitle(18.5))
                        .foregroundColor(BevelColors.textPrimary)

                    // Category 1: Sueño (only if real sleep data exists)
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
                                fillStartFrac: 0.40,
                                fillEndFrac: 0.80,
                                accentColor: BevelColors.bioTeal
                            )
                        }
                    }

                    // Category 2: Actividad (only if steps or zones exist)
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
                                fillStartFrac: 0.48,
                                fillEndFrac: 0.85,
                                accentColor: BevelColors.bioTeal
                            )
                        }
                    }

                    // Category 3: Fitness (only showing recorded sub-biomarkers)
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
                                    fillStartFrac: 0.45,
                                    fillEndFrac: 0.90,
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
                                    fillStartFrac: 0.05,
                                    fillEndFrac: 0.35,
                                    accentColor: BevelColors.bioTeal
                                )
                            }
                        }
                    }

                    // 4. Otros biomarcadores (Strictly real readings — omit unrecorded body/blood metrics!)
                    Text("Otros biomarcadores")
                        .font(ImprovingFont.sectionTitle(18.5))
                        .foregroundColor(BevelColors.textPrimary)
                        .padding(.top, 4)

                    if let w = store.latestBodyWeightKg {
                        otherBioCard(title: "Peso", statusText: "Registrado", statusColor: BevelColors.textSecondary, value: String(format: "%.1f kg", locale: Locale(identifier: "es_ES"), w), lineColor: BevelColors.textSecondary, points: weightSeries) { onNavigate(.dispositivos) }
                    }
                    if store.dataAvailability.hasHrvData || meanHrv != nil {
                        let val = store.dataAvailability.hasHrvData ? store.hrvMs : (meanHrv ?? 0)
                        otherBioCard(title: "VFC histórico", statusText: "Real", statusColor: BevelColors.greenPrimary, value: String(format: "%.1f ms", locale: Locale(identifier: "es_ES"), val), lineColor: BevelColors.greenPrimary, points: hrvSeries) { onSelectHealthMetric(.hrv) }
                    }
                    if store.dataAvailability.hasRestingHrData || meanRhr != nil {
                        let val = store.dataAvailability.hasRestingHrData ? store.restingHrBpm : (meanRhr ?? 0)
                        otherBioCard(title: "Históricos FCR", statusText: "Real", statusColor: BevelColors.skyBlue, value: String(format: "%.1f ppm", locale: Locale(identifier: "es_ES"), val), lineColor: BevelColors.skyBlue, points: rhrSeries) { onSelectHealthMetric(.restingHeartRate) }
                    }
                    if let fat = store.latestBodyFatPct {
                        otherBioCard(title: "Grasa corporal", statusText: "Registrado", statusColor: BevelColors.textSecondary, value: String(format: "%.1f %%", locale: Locale(identifier: "es_ES"), fat), lineColor: BevelColors.textMuted, points: fatSeries) { onNavigate(.dispositivos) }
                    }
                    if let lean = store.latestLeanMassKg {
                        otherBioCard(title: "Masa magra", statusText: "Registrado", statusColor: BevelColors.textSecondary, value: String(format: "%.1f kg", locale: Locale(identifier: "es_ES"), lean), lineColor: BevelColors.textMuted, points: leanSeries) { onNavigate(.dispositivos) }
                    }
                    if let v = vo2Val {
                        otherBioCard(title: "VO₂ máx.", statusText: "Registrado", statusColor: BevelColors.amberStart, value: String(format: "%.1f", locale: Locale(identifier: "es_ES"), v), lineColor: BevelColors.amberStart, points: vo2Series) { onNavigate(.cardioMetricDetail) }
                    }
                    if let bp = store.latestBloodPressure {
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
                            }
                            .padding(16)
                        }
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
                }
                .padding(16)
            }
        }
    }
}

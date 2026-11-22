import SwiftUI

struct BiologiaScreen: View {
    @ObservedObject var store: ImprovingStore
    let onSelectHealthMetric: (HealthMetricKind) -> Void
    let onNavigate: (OverlayRoute) -> Void

    @State private var expandedCategoryId: String? = "sleep"

    var body: some View {
        let chronologicalAge = store.userProfile.ageYears
        let bioDelta = -2.4
        let bioAge = max(16.0, chronologicalAge + bioDelta)

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 1. Atmospheric Emerald-Teal Biological Age Hero (Screenshot 69)
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
                            HStack(spacing: 14) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(BevelColors.textPrimary)
                                Button { onNavigate(.dispositivos) } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(BevelColors.textPrimary)
                                }
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 40)
                            .background(Capsule().fill(BevelColors.glassChromeFill))
                            .overlay(Capsule().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.8))
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
                            sampledDays: max(store.realHistory.count, 730)
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }

                VStack(alignment: .leading, spacing: 16) {
                    // 2. Confianza Card (Screenshot 69)
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 20))
                            .foregroundColor(BevelColors.greenPrimary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Confianza del 88 %")
                                .font(ImprovingFont.cardTitle(15))
                                .foregroundColor(BevelColors.greenPrimary)
                            Text("Estimación de edad de alta calidad con lagunas menores")
                                .font(ImprovingFont.caption(12.5))
                                .foregroundColor(BevelColors.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12))
                            .foregroundColor(BevelColors.textMuted)
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(BevelColors.greenSoftBg))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(BevelColors.greenSoftBorder.opacity(0.6), lineWidth: 0.9))

                    // 3. Biomarcadores de edad — 5 Exact Expandable Categories with Dot Range Sliders (Screenshots 70, 72–74)
                    Text("Biomarcadores de edad")
                        .font(ImprovingFont.sectionTitle(18.5))
                        .foregroundColor(BevelColors.textPrimary)

                    // Category 1: Sueño
                    bioCategoryCard(
                        id: "sleep",
                        icon: "moon.fill",
                        ringPrimary: BevelColors.bioTeal,
                        ringSecondary: BevelColors.trackGroove,
                        title: "Sueño",
                        subtitle: "1,2 años menos",
                        subtitleColor: BevelColors.bioTeal
                    ) {
                        BioDotRangeSlider(title: "Duración del sueño", valueLabel: store.sleepDurationText, minLabel: "5 h", maxLabel: "11 h", deltaText: "-0,0", deltaUnit: "años", positionFrac: 0.44, fillStartFrac: 0.44, fillEndFrac: 0.44, accentColor: BevelColors.textPrimary)
                        Divider().background(BevelColors.divider)
                        BioDotRangeSlider(title: "Regularidad del sueño", valueLabel: "88%", minLabel: "30%", maxLabel: "100%", deltaText: "-1,2", deltaUnit: "años", positionFrac: 0.80, fillStartFrac: 0.56, fillEndFrac: 0.96, accentColor: BevelColors.bioTeal)
                    }

                    // Category 2: Actividad
                    bioCategoryCard(
                        id: "activity",
                        icon: "figure.run",
                        ringPrimary: BevelColors.amberStart,
                        ringSecondary: BevelColors.bioTeal,
                        title: "Actividad",
                        subtitle: "0,7 años menos",
                        subtitleColor: BevelColors.bioTeal
                    ) {
                        BioDotRangeSlider(title: "Número de pasos", valueLabel: String(format: "%.2fk", Double(store.stepsCount) / 1000.0), minLabel: "0", maxLabel: "16k", deltaText: "-0,4", deltaUnit: "años", positionFrac: 0.72, fillStartFrac: 0.50, fillEndFrac: 0.75, accentColor: BevelColors.bioTeal)
                        Divider().background(BevelColors.divider)
                        BioDotRangeSlider(title: "Zonas 2-3", valueLabel: "185m", minLabel: "0m", maxLabel: "300m", deltaText: "-0,3", deltaUnit: "años", positionFrac: 0.62, fillStartFrac: 0.45, fillEndFrac: 0.68, accentColor: BevelColors.bioTeal)
                        Divider().background(BevelColors.divider)
                        BioDotRangeSlider(title: "Zonas 4-5", valueLabel: "22m", minLabel: "0m", maxLabel: "60m", deltaText: "+0,2", deltaUnit: "años", positionFrac: 0.35, fillStartFrac: 0.15, fillEndFrac: 0.42, accentColor: BevelColors.amberStart)
                        Divider().background(BevelColors.divider)
                        BioDotRangeSlider(title: "Entrenamiento de Fuerza", valueLabel: "42m", minLabel: "0m", maxLabel: "120m", deltaText: "-0,2", deltaUnit: "años", positionFrac: 0.36, fillStartFrac: 0.20, fillEndFrac: 0.90, accentColor: BevelColors.bioTeal)
                    }

                    // Category 3: Fitness
                    bioCategoryCard(
                        id: "fitness",
                        icon: "heart.fill",
                        ringPrimary: BevelColors.bioTeal,
                        ringSecondary: BevelColors.amberStart,
                        title: "Fitness",
                        subtitle: "0,1 años menos",
                        subtitleColor: BevelColors.textSecondary
                    ) {
                        BioDotRangeSlider(title: "VO₂ máx.", valueLabel: String(format: "%.1f", locale: Locale(identifier: "es_ES"), store.vo2Max), minLabel: "15", maxLabel: "65", deltaText: "+1,4", deltaUnit: "años", positionFrac: 0.60, fillStartFrac: 0.0, fillEndFrac: 0.65, accentColor: BevelColors.amberStart)
                        Divider().background(BevelColors.divider)
                        BioDotRangeSlider(title: "FC en reposo", valueLabel: String(format: "%.1f", locale: Locale(identifier: "es_ES"), store.restingHrBpm), minLabel: "40", maxLabel: "100", deltaText: "-1,5", deltaUnit: "años", positionFrac: 0.16, fillStartFrac: 0.0, fillEndFrac: 0.34, accentColor: BevelColors.bioTeal)
                        Divider().background(BevelColors.divider)
                        BioDotRangeSlider(title: "Porcentaje de masa magra del cuerpo", valueLabel: "83,8%", minLabel: "50%", maxLabel: "95%", deltaText: "—", deltaUnit: "años", positionFrac: 0.75, fillStartFrac: 0.55, fillEndFrac: 0.80, accentColor: BevelColors.textMuted)
                    }

                    // Category 4: Estilo de vida
                    bioCategoryCard(
                        id: "lifestyle",
                        icon: "figure.stand",
                        ringPrimary: BevelColors.textMuted,
                        ringSecondary: BevelColors.trackGroove,
                        title: "Estilo de vida",
                        subtitle: "0,0 años menos",
                        subtitleColor: BevelColors.textSecondary
                    ) {
                        BioDotRangeSlider(title: "Nutrición", valueLabel: "\(store.foodQualityScore)", minLabel: "0", maxLabel: "100", deltaText: "-0,2", deltaUnit: "años", positionFrac: 0.86, fillStartFrac: 0.65, fillEndFrac: 0.90, accentColor: BevelColors.bioTeal)
                        Divider().background(BevelColors.divider)
                        BioDotRangeSlider(title: "Efectos del tabaco", valueLabel: "No fumador", minLabel: "No fumador", maxLabel: "Fuerte", deltaText: "+0,0", deltaUnit: "años", positionFrac: 0.02, fillStartFrac: 0.0, fillEndFrac: 0.02, accentColor: BevelColors.textSecondary)
                        Divider().background(BevelColors.divider)
                        BioDotRangeSlider(title: "Alcohol", valueLabel: "0", minLabel: "0", maxLabel: "20", deltaText: "+0,0", deltaUnit: "años", positionFrac: 0.02, fillStartFrac: 0.0, fillEndFrac: 0.04, accentColor: BevelColors.textSecondary)
                    }

                    // Category 5: Sangre (PhenoAge 8 Markers — Screenshot 74)
                    bioCategoryCard(
                        id: "blood",
                        icon: "flask.fill",
                        ringPrimary: BevelColors.bioTeal,
                        ringSecondary: BevelColors.bioTeal,
                        title: "Sangre",
                        subtitle: "7,1 años menos",
                        subtitleColor: BevelColors.bioTeal
                    ) {
                        let markers: [(String, String, Double)] = [
                            ("Albúmina", "4,4 g/dL", 0.56),
                            ("Creatina", "1,1 mg/dL", 0.64),
                            ("Glucosa", "76 mg/dL", 0.30),
                            ("Fosfatasa alcalina (ALP)", "68 U/L", 0.42),
                            ("% de linfocitos", "33,6%", 0.50),
                            ("Volumen corpuscular medio (MCV)", "90,6 fL", 0.58),
                            ("Índice de distribución eritrocitaria (RDW)", "11,6%", 0.38),
                            ("Recuento de glóbulos blancos (WBC)", "5,4 K/μL", 0.45),
                        ]
                        ForEach(Array(markers.enumerated()), id: \.offset) { idx, m in
                            BioDotRangeSlider(title: m.0, valueLabel: m.1, minLabel: "", maxLabel: "", deltaText: "", deltaUnit: "", positionFrac: m.2, fillStartFrac: 0.25, fillEndFrac: 0.75, accentColor: BevelColors.bioTeal, showMinMax: false, statusBadgeText: "En el rango")
                            if idx < markers.count - 1 {
                                Divider().background(BevelColors.divider)
                            }
                        }
                    }

                    // 4. Otros biomarcadores (Exact 7 Cards from Screenshot 71)
                    HStack {
                        Text("Otros biomarcadores")
                            .font(ImprovingFont.sectionTitle(18.5))
                            .foregroundColor(BevelColors.textPrimary)
                        Spacer()
                        Text("Editar").font(ImprovingFont.caption(13)).underline().foregroundColor(BevelColors.textSecondary)
                    }
                    .padding(.top, 4)

                    otherBioCard(title: "Peso", statusIcon: "arrow.down.circle.fill", statusText: "Ha bajado", statusColor: BevelColors.textSecondary, value: String(format: "%.1f kg", locale: Locale(identifier: "es_ES"), store.userProfile.weightKg), lineColor: BevelColors.textSecondary, points: [81.4, 81.1, 80.9, 80.7, store.userProfile.weightKg]) { onNavigate(.dispositivos) }
                    otherBioCard(title: "VFC histórico", statusIcon: "arrow.right.circle.fill", statusText: "Estable", statusColor: BevelColors.textSecondary, value: String(format: "%.1f ms", locale: Locale(identifier: "es_ES"), store.hrvMs), lineColor: BevelColors.textSecondary, points: [70, 72, 71, 79, 80, 77, store.hrvMs]) { onSelectHealthMetric(.hrv) }
                    otherBioCard(title: "Históricos FCR", statusIcon: nil, statusText: "Excelente", statusColor: BevelColors.skyBlue, value: String(format: "%.1f ppm", locale: Locale(identifier: "es_ES"), store.restingHrBpm), lineColor: BevelColors.skyBlue, points: [53, 51, 51, 48, 48, 49, store.restingHrBpm]) { onSelectHealthMetric(.restingHeartRate) }
                    otherBioCard(title: "Grasa corporal", statusIcon: nil, statusText: "Normal", statusColor: BevelColors.textSecondary, value: "16,2 %", lineColor: BevelColors.textMuted, points: [16.5, 16.4, 16.3, 16.2]) { onNavigate(.dispositivos) }
                    otherBioCard(title: "Masa magra", statusIcon: nil, statusText: "Normal", statusColor: BevelColors.textSecondary, value: "67,5 kg", lineColor: BevelColors.textMuted, points: [67.2, 67.3, 67.4, 67.5]) { onNavigate(.dispositivos) }
                    otherBioCard(title: "VO₂ máx.", statusIcon: nil, statusText: "Aceptable", statusColor: BevelColors.amberStart, value: String(format: "%.1f", locale: Locale(identifier: "es_ES"), store.vo2Max), lineColor: BevelColors.amberStart, points: [42.2, 43.4, 43.9, store.vo2Max]) { onNavigate(.cardioMetricDetail) }

                    // Presión arterial with green layered zone widget (Screenshot 71)
                    BevelCard(cornerRadius: 20) {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Presión arterial").font(ImprovingFont.cardTitle(15)).foregroundColor(BevelColors.textPrimary)
                                HStack(spacing: 5) {
                                    Text("No elevada").font(ImprovingFont.caption(13)).fontWeight(.semibold).foregroundColor(BevelColors.greenPrimary)
                                    Text("·").foregroundColor(BevelColors.textMuted)
                                    Text("99/51 mmHg").font(ImprovingFont.caption(13)).fontWeight(.semibold).foregroundColor(BevelColors.textPrimary)
                                }
                            }
                            Spacer()
                            VStack(spacing: 2) {
                                Capsule().fill(Color.white.opacity(0.1)).frame(width: 72, height: 3)
                                Capsule().fill(Color.white.opacity(0.14)).frame(width: 72, height: 3)
                                ZStack {
                                    RoundedRectangle(cornerRadius: 5).fill(BevelColors.greenPrimary.opacity(0.65)).frame(width: 72, height: 22)
                                    Circle().fill(BevelColors.card).frame(width: 9, height: 9).overlay(Circle().strokeBorder(BevelColors.greenPrimary, lineWidth: 2))
                                }
                            }
                        }
                        .padding(16)
                    }

                    Button { onNavigate(.dispositivos) } label: {
                        HStack(spacing: 4) {
                            Text("Ver todo").font(ImprovingFont.caption(13.5)).foregroundColor(BevelColors.textSecondary)
                            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundColor(BevelColors.textMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
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
        @ViewBuilder details: () -> Content
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
                                .font(ImprovingFont.cardTitle(14.5))
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

    private func otherBioCard(title: String, statusIcon: String?, statusText: String, statusColor: Color, value: String, lineColor: Color, points: [Double], onClick: @escaping () -> Void) -> some View {
        Button(action: onClick) {
            BevelCard(cornerRadius: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title).font(ImprovingFont.cardTitle(15)).foregroundColor(BevelColors.textPrimary)
                        HStack(spacing: 5) {
                            if let ic = statusIcon {
                                Image(systemName: ic).font(.system(size: 12)).foregroundColor(statusColor)
                            }
                            Text(statusText).font(ImprovingFont.caption(13)).fontWeight(.semibold).foregroundColor(statusColor)
                            Text("·").foregroundColor(BevelColors.textMuted)
                            Text(value).font(ImprovingFont.caption(13)).fontWeight(.semibold).monospacedDigit().foregroundColor(BevelColors.textPrimary)
                        }
                    }
                    Spacer()
                    TrendSparklineWithBand(points: points, lineColor: lineColor, fillUnder: true, showGlowDot: true)
                        .frame(width: 82, height: 34)
                }
                .padding(16)
            }
        }
    }
}

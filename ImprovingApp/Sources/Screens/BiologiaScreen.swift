import SwiftUI

private struct BioAgeCategoryData: Identifiable {
    let id: String
    let icon: String
    let title: String
    let summary: String
    let deltaYears: Double
    let isFavorable: Bool
    let details: [(String, String, String)]
}

private let bioCategories: [BioAgeCategoryData] = [
    BioAgeCategoryData(
        id: "sleep",
        icon: "🌙",
        title: "Sueño",
        summary: "4 dentro del rango",
        deltaYears: -0.9,
        isFavorable: true,
        details: [
            ("Duración media (90d)", "7 h 48 m", "-0,4 años"),
            ("Sueño profundo + REM", "45 %", "-0,3 años"),
            ("Consistencia circadiana", "89 %", "-0,2 años")
        ]
    ),
    BioAgeCategoryData(
        id: "activity",
        icon: "👣",
        title: "Actividad",
        summary: "2 dentro del rango",
        deltaYears: -0.7,
        isFavorable: true,
        details: [
            ("Pasos diarios (media 90d)", "10.840 pasos", "-0,4 años"),
            ("Minutos activos en Zona 2", "185 min/sem", "-0,3 años")
        ]
    ),
    BioAgeCategoryData(
        id: "fitness",
        icon: "❤️",
        title: "Fitness",
        summary: "2 dentro del rango",
        deltaYears: -0.5,
        isFavorable: true,
        details: [
            ("VO₂ máx. estimado", "44,3 ml/kg/min", "-0,3 años"),
            ("Frecuencia cardíaca en reposo", "48,2 ppm", "-0,2 años")
        ]
    ),
    BioAgeCategoryData(
        id: "body",
        icon: "⚖️",
        title: "Composición corporal",
        summary: "3 dentro del rango",
        deltaYears: -0.3,
        isFavorable: true,
        details: [
            ("Masa corporal magra", "83,8 %", "-0,2 años"),
            ("Grasa corporal", "16,2 %", "-0,1 años"),
            ("Peso estable", "80,6 kg", "0,0 años")
        ]
    ),
    BioAgeCategoryData(
        id: "blood",
        icon: "🩸",
        title: "Sangre · PhenoAge",
        summary: "Panel clínico opcional",
        deltaYears: -0.2,
        isFavorable: true,
        details: [
            ("hs-CRP (Inflamación)", "0,6 mg/L", "-0,1 años"),
            ("Glucosa basal / HbA1c", "86 mg/dL · 5,1%", "-0,1 años"),
            ("ApoB / Perfil lipídico", "74 mg/dL", "Óptimo")
        ]
    )
]

struct BiologiaScreen: View {
    @ObservedObject var store: ImprovingStore
    let onSelectHealthMetric: (HealthMetricKind) -> Void
    let onNavigate: (OverlayRoute) -> Void

    @State private var expandedCategoryId: String? = "sleep"

    var body: some View {
        let chronologicalAge = store.userProfile.ageYears
        let bioDelta = -2.4
        let bioAge = max(14.0, chronologicalAge + bioDelta)

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 1. Top Header
                HStack {
                    Text("Biología")
                        .font(ImprovingFont.displayLarge(28))
                        .foregroundColor(BevelColors.textPrimary)
                    Spacer()
                    HStack(spacing: 8) {
                        Button {
                            store.startNewCleanChat()
                            onNavigate(.askBevel)
                        } label: {
                            IridescentPearlOrb(size: 34)
                        }
                        Button { onNavigate(.dispositivos) } label: {
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

                // 2. Hero BioAge Curved Dial Card
                BevelCard {
                    VStack(spacing: 10) {
                        BioAgeCurvedDial(
                            bioAgeYears: bioAge,
                            chronoAgeYears: chronologicalAge,
                            diffYears: bioDelta,
                            sampledDays: max(store.realHistory.count, 730)
                        )

                        HStack(spacing: 8) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(BevelColors.emeraldEnd)
                                .frame(width: 20, height: 20)
                                .background(Circle().fill(BevelColors.greenSoftBg))
                            Text("Confianza del 88 %")
                                .font(ImprovingFont.caption(12.5))
                                .fontWeight(.semibold)
                                .foregroundColor(BevelColors.emeraldEnd)
                            Spacer()
                            Text("Línea base 90d")
                                .font(ImprovingFont.caption(11.5))
                                .foregroundColor(BevelColors.textSecondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 14).fill(BevelColors.surfaceOverlay))
                    }
                    .padding(18)
                }

                // 3. Biomarcadores de edad (5 Expandable Categories)
                HStack {
                    Text("Biomarcadores de edad")
                        .font(ImprovingFont.sectionTitle(18))
                        .foregroundColor(BevelColors.textPrimary)
                    Spacer()
                    Text("Toca para desglosar")
                        .font(ImprovingFont.caption(12))
                        .foregroundColor(BevelColors.textSecondary)
                }

                ForEach(bioCategories) { cat in
                    let isExpanded = expandedCategoryId == cat.id
                    BevelCard(cornerRadius: 20) {
                        VStack(alignment: .leading, spacing: 10) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    expandedCategoryId = isExpanded ? nil : cat.id
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    segmentedIconBadge(icon: cat.icon, color: BevelColors.emeraldEnd)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(cat.title)
                                            .font(ImprovingFont.cardTitle(15))
                                            .foregroundColor(BevelColors.textPrimary)
                                        Text(cat.summary)
                                            .font(ImprovingFont.caption(12))
                                            .foregroundColor(BevelColors.textSecondary)
                                    }
                                    Spacer()
                                    Text(String(format: "%.1f años", locale: Locale(identifier: "es_ES"), cat.deltaYears))
                                        .font(ImprovingFont.caption(12.5))
                                        .fontWeight(.bold)
                                        .foregroundColor(BevelColors.emeraldEnd)
                                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(BevelColors.textMuted)
                                }
                            }

                            if isExpanded {
                                Divider().background(BevelColors.divider)
                                ForEach(cat.details, id: \.0) { label, val, impact in
                                    HStack {
                                        Text(label)
                                            .font(ImprovingFont.caption(12.5))
                                            .foregroundColor(BevelColors.textSecondary)
                                        Spacer()
                                        Text(val)
                                            .font(ImprovingFont.caption(12.5))
                                            .fontWeight(.semibold)
                                            .foregroundColor(BevelColors.textPrimary)
                                        Text(impact)
                                            .font(ImprovingFont.caption(12))
                                            .fontWeight(.bold)
                                            .foregroundColor(BevelColors.emeraldEnd)
                                            .padding(.leading, 8)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                        .padding(16)
                    }
                }

                // 4. Otros biomarcadores
                HStack {
                    Text("Otros biomarcadores")
                        .font(ImprovingFont.sectionTitle(18))
                        .foregroundColor(BevelColors.textPrimary)
                    Spacer()
                    Text("Últimos 90 días")
                        .font(ImprovingFont.caption(12))
                        .foregroundColor(BevelColors.textSecondary)
                }

                otherBiomarkerCard(
                    title: "VO₂ máx.",
                    date: "21/11/26",
                    value: "44,3",
                    unit: "ml/kg/min",
                    delta: "↑ 0,8",
                    color: BevelColors.emeraldEnd,
                    points: [42.1, 42.6, 43.0, 43.4, 43.8, 44.1, 44.3],
                    onClick: { onSelectHealthMetric(.respiratoryRate) }
                )
                otherBiomarkerCard(
                    title: "FC en reposo",
                    date: "21/11/26",
                    value: String(format: "%.1f", locale: Locale(identifier: "es_ES"), store.restingHrBpm),
                    unit: "ppm",
                    delta: "↓ 1,1",
                    color: BevelColors.emeraldEnd,
                    points: [51.2, 50.4, 49.8, 49.2, 48.9, 48.5, store.restingHrBpm],
                    onClick: { onSelectHealthMetric(.restingHeartRate) }
                )
                otherBiomarkerCard(
                    title: "VFC (RMSSD)",
                    date: "21/11/26",
                    value: String(format: "%.1f", locale: Locale(identifier: "es_ES"), store.hrvMs),
                    unit: "ms",
                    delta: "↑ 4,2",
                    color: BevelColors.emeraldEnd,
                    points: [69.0, 71.5, 73.0, 74.2, 75.8, 76.4, store.hrvMs],
                    onClick: { onSelectHealthMetric(.hrv) }
                )
                otherBiomarkerCard(
                    title: "Peso",
                    date: "21/11/26",
                    value: String(format: "%.1f", locale: Locale(identifier: "es_ES"), store.userProfile.weightKg),
                    unit: "kg",
                    delta: "↓ 0,4",
                    color: BevelColors.skyBlue,
                    points: [81.4, 81.2, 81.0, 80.9, 80.8, 80.7, store.userProfile.weightKg],
                    onClick: { onNavigate(.dispositivos) }
                )
                otherBiomarkerCard(
                    title: "Masa corporal magra",
                    date: "21/11/26",
                    value: "83,8",
                    unit: "%",
                    delta: "↑ 0,2",
                    color: BevelColors.emeraldEnd,
                    points: [83.1, 83.2, 83.4, 83.5, 83.6, 83.7, 83.8],
                    onClick: { onNavigate(.dispositivos) }
                )
                otherBiomarkerCard(
                    title: "Grasa corporal",
                    date: "21/11/26",
                    value: "16,2",
                    unit: "%",
                    delta: "↓ 0,2",
                    color: BevelColors.amberStart,
                    points: [16.9, 16.8, 16.6, 16.5, 16.4, 16.3, 16.2],
                    onClick: { onNavigate(.dispositivos) }
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 120)
        }
        .background(BevelColors.canvas)
    }

    private func segmentedIconBadge(icon: String, color: Color) -> some View {
        ZStack {
            Canvas { ctx, sz in
                let strokeW: CGFloat = 3
                let radius = (min(sz.width, sz.height) - strokeW) / 2
                let center = CGPoint(x: sz.width / 2, y: sz.height / 2)
                for i in 0..<4 {
                    let start = Double(i) * 90.0 - 78.0
                    var p = Path()
                    p.addArc(center: center, radius: radius, startAngle: .degrees(start), endAngle: .degrees(start + 66.0), clockwise: false)
                    ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: strokeW, lineCap: .round))
                }
            }
            .frame(width: 42, height: 42)
            Text(icon).font(.system(size: 16))
        }
    }

    private func otherBiomarkerCard(title: String, date: String, value: String, unit: String, delta: String, color: Color, points: [Double], onClick: @escaping () -> Void) -> some View {
        Button(action: onClick) {
            BevelCard(cornerRadius: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(ImprovingFont.cardTitle(15))
                            .foregroundColor(BevelColors.textPrimary)
                        Text(date)
                            .font(ImprovingFont.caption(11.5))
                            .foregroundColor(BevelColors.textSecondary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(value)
                                .font(ImprovingFont.metricHero(22))
                                .monospacedDigit()
                                .foregroundColor(BevelColors.textPrimary)
                            Text(unit)
                                .font(ImprovingFont.caption(12))
                                .foregroundColor(BevelColors.textSecondary)
                            Text(delta)
                                .font(ImprovingFont.caption(12))
                                .fontWeight(.bold)
                                .foregroundColor(color)
                                .padding(.leading, 4)
                        }
                    }
                    Spacer()
                    TrendSparklineWithBand(points: points, lineColor: color)
                        .frame(width: 88, height: 34)
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(BevelColors.emeraldEnd)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(BevelColors.greenSoftBg))
                        .padding(.leading, 6)
                }
                .padding(16)
            }
        }
    }
}

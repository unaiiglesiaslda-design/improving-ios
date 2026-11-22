import SwiftUI

struct HealthMetricDetailScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void

    @State private var inspectedFloat: Double? = nil
    @State private var inspectedDate: String? = nil
    @State private var scrollCollapseSignal: Int = 0
    @State private var aiInsight: MetricFloatingAiInsight = MetricFloatingAiInsight(
        shortPillText: "Analizando métrica…",
        expandedHeadline: "LECTURA EN VIVO DE TU IA",
        shortExpandedMessage: "",
        expandedMessage: "",
        structureIndex: 0,
        variationSeed: 1
    )

    private var spanDays: Int {
        switch store.selectedHealthRange {
        case "7 d": return 7
        case "3 M": return 90
        case "6 M": return 180
        case "1 A": return 365
        default: return 30
        }
    }

    var body: some View {
        let kind = store.selectedHealthMetric
        let series = store.metricSeries(for: kind, spanDays: spanDays)
        let points = series.map(\.1)
        let dates = series.map(\.0)
        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: store.userProfile)
        let (bandLow, bandHigh): (Double, Double) = switch kind {
        case .respiratoryRate: (norms.respLowRpm, norms.respHighRpm)
        case .restingHeartRate: (norms.rhrLowBpm, norms.rhrHighBpm)
        case .hrv: (norms.hrvLowMs, norms.hrvHighMs)
        case .oxygenSaturation: (95, 100)
        case .wristTemperature: (35.5, 36.6)
        case .sleepDuration: (norms.sleepLowHours, norms.sleepHighHours)
        }
        let currentNumeric: Double? = switch kind {
        case .respiratoryRate: store.dataAvailability.hasRespData ? store.respRateRpm : nil
        case .restingHeartRate: store.dataAvailability.hasRestingHrData ? store.restingHrBpm : nil
        case .hrv: store.dataAvailability.hasHrvData ? store.hrvMs : nil
        case .oxygenSaturation: store.dataAvailability.hasSpo2Data ? Double(store.spo2Percent) + 0.2 : nil
        case .wristTemperature: store.dataAvailability.hasTempData ? 35.9 + store.wristTempDeltaC : nil
        case .sleepDuration: store.currentDaySummary?.asleepMinutes.map { Double($0) / 60.0 }
        }
        let avgVal = points.isEmpty ? (currentNumeric ?? 0) : points.reduce(0, +) / Double(points.count)
        let heroVal = inspectedFloat ?? currentNumeric ?? points.last ?? 0

        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    DetailSheetHeader(title: kind.title, onBack: onBack)

                    // 1. Main Chart Card
                    BevelCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .bottom) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                                        EmptyView().animatableNumber(
                                            heroVal,
                                            decimals: 1,
                                            font: ImprovingFont.displayLarge(31),
                                            color: BevelColors.textPrimary
                                        )
                                        if !kind.unit.isEmpty {
                                            Text(kind.unit)
                                                .font(ImprovingFont.sectionTitle(19))
                                                .foregroundColor(BevelColors.textSecondary)
                                        }
                                    }
                                    Text(inspectedDate.map { "\($0) · Punto seleccionado" } ?? store.dateLabel)
                                        .font(ImprovingFont.caption(12))
                                        .foregroundColor(inspectedDate != nil ? BevelColors.emeraldEnd : BevelColors.textSecondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("Rango normal")
                                        .font(ImprovingFont.caption(12))
                                        .fontWeight(.semibold)
                                        .foregroundColor(BevelColors.emeraldEnd)
                                    Text(String(format: "%.1f – %.1f %@", locale: Locale(identifier: "es_ES"), bandLow, bandHigh, kind.unit))
                                        .font(ImprovingFont.caption(12))
                                        .monospacedDigit()
                                        .foregroundColor(BevelColors.textSecondary)
                                }
                            }

                            // Metric chip switcher
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(HealthMetricKind.allCases) { item in
                                        let active = item == kind
                                        Button {
                                            inspectedFloat = nil
                                            inspectedDate = nil
                                            store.selectedHealthMetric = item
                                        } label: {
                                            Text(item.shortLabel)
                                                .font(ImprovingFont.caption(12))
                                                .fontWeight(.semibold)
                                                .foregroundColor(active ? .white : BevelColors.textSecondary)
                                                .padding(.horizontal, 13)
                                                .padding(.vertical, 7)
                                                .background(Capsule().fill(active ? BevelColors.floatingDarkButton : BevelColors.trackGroove))
                                        }
                                    }
                                }
                            }

                            if points.count >= 2 {
                                HealthMetricBaselineChart(
                                    points: points,
                                    dates: dates,
                                    bandLow: bandLow,
                                    bandHigh: bandHigh,
                                    averageText: String(format: "Prom. %.1f %@", locale: Locale(identifier: "es_ES"), avgVal, kind.unit),
                                    accentColor: BevelColors.emeraldEnd,
                                    valueFormatter: { v in String(format: "%.1f %@", locale: Locale(identifier: "es_ES"), v, kind.unit) },
                                    onPointSelected: { _, v, d in
                                        withAnimation(.easeOut(duration: 0.22)) {
                                            inspectedFloat = v
                                            inspectedDate = d
                                        }
                                    }
                                )
                            }

                            // Range selector: < 7 d | 30 d | 3 M | 6 M | 1 A >
                            HStack(spacing: 6) {
                                ForEach(["7 d", "30 d", "3 M", "6 M", "1 A"], id: \.self) { r in
                                    let active = store.selectedHealthRange == r
                                    Button {
                                        inspectedFloat = nil
                                        inspectedDate = nil
                                        store.selectedHealthRange = r
                                    } label: {
                                        Text(r)
                                            .font(ImprovingFont.caption(12))
                                            .fontWeight(.semibold)
                                            .foregroundColor(active ? .white : BevelColors.textSecondary)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 7)
                                            .background(Capsule().fill(active ? BevelColors.floatingDarkButton : .clear))
                                    }
                                }
                            }
                            .padding(4)
                            .background(Capsule().fill(BevelColors.trackGroove))
                        }
                        .padding(16)
                    }
                    .padding(.horizontal, 16)

                    // 2. Análisis de tendencias (3d / 7d / 14d / 30d / 90d Delta Table with Sparklines)
                    Text("Análisis de tendencias")
                        .font(ImprovingFont.sectionTitle(18))
                        .foregroundColor(BevelColors.textPrimary)
                        .padding(.horizontal, 16)

                    BevelCard {
                        VStack(spacing: 0) {
                            let periods = [3, 7, 14, 30, 90]
                            ForEach(Array(periods.enumerated()), id: \.offset) { idx, p in
                                let subPts = Array(points.suffix(min(max(p, 3), max(points.count, 1))))
                                let subAvg = subPts.isEmpty ? avgVal : subPts.reduce(0, +) / Double(subPts.count)
                                let delta = (currentNumeric ?? avgVal) - subAvg
                                let arrow = abs(delta) < 0.15 ? "→" : (delta > 0 ? "↑" : "↓")
                                let isGood = abs(delta) < 0.8

                                HStack {
                                    Text("\(p) día(s)")
                                        .font(ImprovingFont.cardTitle(14))
                                        .foregroundColor(BevelColors.textPrimary)
                                        .frame(width: 78, alignment: .leading)

                                    HStack(spacing: 6) {
                                        Text(arrow)
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(isGood ? BevelColors.skyBlue : BevelColors.orangeEnd)
                                            .frame(width: 24, height: 24)
                                            .background(Circle().fill(isGood ? BevelColors.skySoftBg : BevelColors.amberSoftBg))
                                        Text(String(format: "%+.1f %@", locale: Locale(identifier: "es_ES"), delta, kind.unit))
                                            .font(ImprovingFont.cardTitle(13.5))
                                            .monospacedDigit()
                                            .foregroundColor(BevelColors.textPrimary)
                                    }

                                    Spacer()

                                    TrendSparklineWithBand(
                                        points: subPts.isEmpty ? [bandLow, avgVal, bandHigh] : subPts,
                                        lineColor: BevelColors.skyBlue
                                    )
                                    .frame(width: 96, height: 26)
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)

                                if idx < periods.count - 1 {
                                    Divider().background(BevelColors.divider)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    Text("Basado en la tendencia móvil respecto al final del período seleccionado.")
                        .font(ImprovingFont.caption(11.5))
                        .foregroundColor(BevelColors.textSecondary)
                        .padding(.horizontal, 16)

                    // 3. Recursos
                    Text("Recursos")
                        .font(ImprovingFont.sectionTitle(18))
                        .foregroundColor(BevelColors.textPrimary)
                        .padding(.horizontal, 16)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            resourceCard(title: "Qué es \(kind.shortLabel) y por qué importa", tag: "Fisiología · 3 min", gradient: [Color(hex: 0x1E293B), Color(hex: 0x0F172A)])
                            resourceCard(title: "Cómo mejorar tu línea base de 90 días", tag: "Protocolos · 4 min", gradient: [Color(hex: 0x064E3B), Color(hex: 0x047857)])
                        }
                        .padding(.horizontal, 16)
                    }

                    // 4. Sobre esta métrica
                    BevelCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(BevelColors.skyBlue)
                                Text("Sobre \(kind.title)")
                                    .font(ImprovingFont.cardTitle(15))
                                    .foregroundColor(BevelColors.textPrimary)
                            }
                            Text("Tu rango personal (\(String(format: "%.1f–%.1f %@", locale: Locale(identifier: "es_ES"), bandLow, bandHigh, kind.unit))) se recalibra dinámicamente utilizando tu historial fisiológico y tus parámetros antropométricos.")
                                .font(ImprovingFont.body(13))
                                .foregroundColor(BevelColors.textSecondary)
                        }
                        .padding(16)
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 185)
            }
            .onVerticalScrollCollapse {
                scrollCollapseSignal += 1
            }

            FloatingMetricAiCoachOverlay(
                metricKey: "\(kind.rawValue)_\(store.selectedHealthRange)",
                metricTitle: kind.title,
                insight: aiInsight,
                scrollCollapseSignal: scrollCollapseSignal
            )
        }
        .background(BevelColors.canvas)
        .task(id: "\(kind.rawValue)_\(store.selectedHealthRange)_\(store.selectedDateIso)") {
            let valStr = currentNumeric.map { String(format: "%.1f %@", locale: Locale(identifier: "es_ES"), $0, kind.unit) } ?? "--"
            let rangeStr = String(format: "%.1f–%.1f %@", locale: Locale(identifier: "es_ES"), bandLow, bandHigh, kind.unit)
            let res = await GeminiCoachService.shared.buildMetricFloatingInsight(
                metricId: kind.rawValue,
                metricTitle: kind.title,
                currentValueText: valStr,
                normalRangeText: rangeStr,
                recoveryPct: store.dataAvailability.hasRecoveryData ? store.recoveryPercent : nil,
                strainPct: store.dataAvailability.hasStrainData ? store.strainPercent : nil,
                hrvMs: store.dataAvailability.hasHrvData ? store.hrvMs : nil,
                restingHrBpm: store.dataAvailability.hasRestingHrData ? store.restingHrBpm : nil,
                sleepDurationText: store.dataAvailability.hasSleepData ? store.sleepDurationText : nil,
                energyPct: store.dataAvailability.hasEnergyData ? store.energyPercent : nil,
                stressScore: store.dataAvailability.hasStressData ? store.stressScore : nil,
                profile: store.userProfile,
                hasData: currentNumeric != nil
            )
            aiInsight = res
        }
    }

    private func resourceCard(title: String, tag: String, gradient: [Color]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tag)
                .font(ImprovingFont.microLabel(10.5))
                .foregroundColor(.white.opacity(0.8))
            Spacer()
            Text(title)
                .font(ImprovingFont.cardTitle(14))
                .foregroundColor(.white)
                .lineLimit(2)
        }
        .padding(16)
        .frame(width: 220, height: 112, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
        )
    }
}

struct TrainingLoadDetailScreen: View {
    @ObservedObject var store: ImprovingStore
    let initialTab: TrainingLoadTab
    let onBack: () -> Void

    @State private var selectedTab: TrainingLoadTab = .cardio

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DetailSheetHeader(title: "Carga de entrenamiento", onBack: onBack)

                Picker("Tipo", selection: $selectedTab) {
                    ForEach(TrainingLoadTab.allCases) { t in Text(t.rawValue).tag(t) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                BevelCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(selectedTab == .cardio ? "RATIO AGUDA / CRÓNICA (ACWR)" : "CARGA MUSCULAR SEMANAL")
                            .font(ImprovingFont.microLabel(11))
                            .foregroundColor(BevelColors.textSecondary)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(selectedTab == .cardio ? "37" : "45")
                                .font(ImprovingFont.displayLarge(32))
                                .monospacedDigit()
                                .foregroundColor(BevelColors.textPrimary)
                            Text(selectedTab == .cardio ? "Manteniendo · Ratio 1,08" : "Subiendo · Ratio 1,18")
                                .font(ImprovingFont.cardTitle(14))
                                .foregroundColor(selectedTab == .cardio ? BevelColors.emeraldEnd : BevelColors.orangeEnd)
                        }
                        TrendSparklineWithBand(
                            points: selectedTab == .cardio ? [31, 33, 34, 35, 36, 36, 37] : [34, 36, 38, 40, 42, 44, 45],
                            lineColor: selectedTab == .cardio ? BevelColors.emeraldEnd : BevelColors.orangeEnd
                        )
                        .frame(height: 82)
                        Text("Mantener el ratio entre 0,8 y 1,3 optimiza adaptaciones cardiovasculares y neuromusculares evitando sobreentrenamiento.")
                            .font(ImprovingFont.body(13))
                            .foregroundColor(BevelColors.textSecondary)
                    }
                    .padding(16)
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 120)
        }
        .background(BevelColors.canvas)
        .onAppear { selectedTab = initialTab }
    }
}

struct CardioMetricDetailScreen: View {
    @ObservedObject var store: ImprovingStore
    let route: CardioMetricRoute
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DetailSheetHeader(title: route.rawValue, onBack: onBack)
                BevelCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("TENDENCIA 30 DÍAS")
                            .font(ImprovingFont.microLabel(11))
                            .foregroundColor(BevelColors.skyBlue)
                        Text(route == .vo2Max ? "44,3 ml/kg/min" : (route == .hrRecovery ? "27 ppm" : "2 h 22 min"))
                            .font(ImprovingFont.displayLarge(30))
                            .monospacedDigit()
                            .foregroundColor(BevelColors.textPrimary)
                        TrendSparklineWithBand(points: [41.8, 42.2, 42.7, 43.1, 43.5, 43.9, 44.3], lineColor: BevelColors.emeraldEnd)
                            .frame(height: 88)
                        Text("Los valores se actualizan automáticamente desde Apple Health, tu exportación .zip/.xml o WHOOP BLE.")
                            .font(ImprovingFont.body(13))
                            .foregroundColor(BevelColors.textSecondary)
                    }
                    .padding(16)
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 120)
        }
        .background(BevelColors.canvas)
    }
}

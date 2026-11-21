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
        case .wristTemperature: (-0.5, 0.5)
        case .sleepDuration: (norms.sleepLowHours, norms.sleepHighHours)
        }
        let currentNumeric: Double? = switch kind {
        case .respiratoryRate: store.dataAvailability.hasRespData ? store.respRateRpm : nil
        case .restingHeartRate: store.dataAvailability.hasRestingHrData ? store.restingHrBpm : nil
        case .hrv: store.dataAvailability.hasHrvData ? store.hrvMs : nil
        case .oxygenSaturation: store.dataAvailability.hasSpo2Data ? Double(store.spo2Percent) : nil
        case .wristTemperature: store.dataAvailability.hasTempData ? store.wristTempDeltaC : nil
        case .sleepDuration: store.currentDaySummary?.asleepMinutes.map { Double($0) / 60.0 }
        }
        let avgVal = points.isEmpty ? (currentNumeric ?? 0) : points.reduce(0, +) / Double(points.count)
        let heroVal = inspectedFloat ?? currentNumeric ?? points.last ?? 0

        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DetailSheetHeader(title: kind.title, onBack: onBack)

                    BevelCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .bottom) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                                        if inspectedFloat != nil || currentNumeric != nil || !points.isEmpty {
                                            EmptyView().animatableNumber(
                                                heroVal,
                                                decimals: kind == .oxygenSaturation ? 0 : 1,
                                                font: ImprovingFont.displayLarge(31),
                                                color: BevelColors.textPrimary
                                            )
                                        } else {
                                            Text("--")
                                                .font(ImprovingFont.displayLarge(31))
                                                .foregroundColor(BevelColors.textMuted)
                                        }
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
                                        .foregroundColor(BevelColors.emeraldEnd)
                                    Text(String(format: "%.1f – %.1f %@", bandLow, bandHigh, kind.unit))
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
                                                .padding(.horizontal, 12)
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
                                    averageText: String(format: "Prom. %.1f %@", avgVal, kind.unit),
                                    accentColor: BevelColors.emeraldEnd,
                                    valueFormatter: { v in String(format: "%.1f %@", locale: Locale(identifier: "es_ES"), v, kind.unit) },
                                    onPointSelected: { _, v, d in
                                        withAnimation(.easeOut(duration: 0.22)) {
                                            inspectedFloat = v
                                            inspectedDate = d
                                        }
                                    }
                                )
                            } else {
                                Text("Se necesitan al menos 2 días reales (Apple Health, WHOOP o importación) para graficar esta tendencia.")
                                    .font(ImprovingFont.caption(12.5))
                                    .foregroundColor(BevelColors.textMuted)
                                    .frame(maxWidth: .infinity, minHeight: 130)
                                    .background(RoundedRectangle(cornerRadius: 16).fill(BevelColors.cardSubtle))
                            }

                            // Range selector
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
                }
                .padding(.bottom, 170)
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
            let valStr = currentNumeric.map { String(format: "%.1f %@", $0, kind.unit) } ?? "--"
            let rangeStr = String(format: "%.1f–%.1f %@", bandLow, bandHigh, kind.unit)
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
}

struct TrainingLoadDetailScreen: View {
    @ObservedObject var store: ImprovingStore
    let initialTab: TrainingLoadTab
    let onBack: () -> Void

    @State private var selectedTab: TrainingLoadTab = .cardio

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                DetailSheetHeader(title: "Carga de entrenamiento", onBack: onBack)
                Picker("Tipo", selection: $selectedTab) {
                    ForEach(TrainingLoadTab.allCases) { t in Text(t.rawValue).tag(t) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                BevelCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(selectedTab == .cardio ? "RATIO AGUDA / CRÓNICA (ACWR)" : "CARGA MUSCULAR SEMANAL")
                            .font(ImprovingFont.microLabel(11))
                            .foregroundColor(BevelColors.textSecondary)
                        Text(store.dataAvailability.hasStrainData ? "1,08 · Óptimo" : "Pendiente de historial")
                            .font(ImprovingFont.displayLarge(26))
                            .foregroundColor(BevelColors.emeraldEnd)
                        Text("Mantener el ratio entre 0,8 y 1,3 optimiza adaptaciones cardiovasculares evitando sobreentrenamiento.")
                            .font(ImprovingFont.body(13.5))
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
            VStack(spacing: 16) {
                DetailSheetHeader(title: route.rawValue, onBack: onBack)
                BevelCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("HISTORIAL REAL")
                            .font(ImprovingFont.microLabel(11))
                            .foregroundColor(BevelColors.skyBlue)
                        Text(store.realHistory.isEmpty ? "Sin registros aún" : "\(store.realHistory.count) días registrados")
                            .font(ImprovingFont.cardTitle(16))
                            .foregroundColor(BevelColors.textPrimary)
                        Text("Los valores se actualizan automáticamente desde Apple Health, tu exportación .zip/.xml o WHOOP BLE.")
                            .font(ImprovingFont.body(13.5))
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

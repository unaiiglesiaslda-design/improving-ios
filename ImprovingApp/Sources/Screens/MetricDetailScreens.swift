import SwiftUI

// MARK: - 0. Specific Trend Metric Detail Screen (Esfuerzo / Recuperación / Sueño / Estrés Trends — Never Forces HRV!)

struct TrendMetricDetailScreen: View {
    @ObservedObject var store: ImprovingStore
    let trend: EffortTrendItem
    let onBack: () -> Void

    @State private var selectedRange: String = "30 d"
    @State private var windowPageOffset: Int = 0
    @State private var inspectedFloat: Double? = nil
    @State private var inspectedDate: String? = nil

    private var spanDays: Int {
        switch selectedRange {
        case "7 d": return 7
        case "30 d": return 30
        case "3 M": return 90
        case "6 M": return 180
        case "1 A": return 365
        default: return 30
        }
    }

    private var isDurationMinutesTrend: Bool {
        trend.id == "s_dur" || trend.id == "s_rem" || trend.id == "s_deep"
    }

    private static let integerTrendIds: Set<String> = [
        "t_steps", "t_kcal", "t_strain", "r_rec", "s_score", "s_eff",
        "t_dur", "t_day_hr", "st_score", "st_sleep", "s_lat", "s_dip"
    ]

    private func formatValue(_ val: Double) -> String {
        if isDurationMinutesTrend {
            let m = Int(val.rounded())
            return "\(m / 60) h \(String(format: "%02d", m % 60)) min"
        }
        if trend.id == "t_perf" {
            return String(format: "%+.0f %@", val, trend.unitText).trimmingCharacters(in: .whitespaces)
        }
        if Self.integerTrendIds.contains(trend.id) {
            let core = "\(Int(val.rounded()))"
            return trend.unitText.isEmpty ? core : "\(core) \(trend.unitText)"
        }
        let core = String(format: "%.1f", locale: Locale(identifier: "es_ES"), val)
        return trend.unitText.isEmpty ? core : "\(core) \(trend.unitText)"
    }

    var body: some View {
        let extractor = store.trendExtractor(for: trend.id)
        let window = store.customWindowSeries(spanDays: spanDays, windowPageOffset: windowPageOffset, extractor: extractor)
        let realPoints = window.realPoints
        let avgVal: Double? = realPoints.isEmpty ? nil : (realPoints.reduce(0, +) / Double(realPoints.count))
        let maxVal: Double? = realPoints.max()
        let minVal: Double? = realPoints.min()
        let currentNumeric: Double? = store.currentDaySummary.flatMap(extractor)
        let displayVal: Double? = inspectedFloat ?? (windowPageOffset == 0 ? currentNumeric : nil) ?? realPoints.last
        let accent = Color(hex: trend.lineColorHex)
        let multiTrends = WhoopPhysiologyEngine.computeMultiPeriodTrendRows(
            history: store.activeHistory,
            anchorDate: store.selectedDate,
            extractor: extractor
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerChartSection(window: window, displayVal: displayVal, avgVal: avgVal, accent: accent)
                detailsSection(avgVal: avgVal, maxVal: maxVal, minVal: minVal, accent: accent, multiTrends: multiTrends)
            }
            .padding(.bottom, 150)
        }
        .background(BevelColors.canvas)
    }

    @ViewBuilder
    private func headerChartSection(
        window: MetricWindowSeries,
        displayVal: Double?,
        avgVal: Double?,
        accent: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            DetailSheetHeader(title: trend.title, onBack: onBack)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    if let val = displayVal {
                        Text(formatValue(val))
                            .font(ImprovingFont.displayLarge(31))
                            .monospacedDigit()
                            .foregroundColor(BevelColors.textPrimary)
                    } else {
                        Text("Sin datos")
                            .font(ImprovingFont.displayLarge(28))
                            .foregroundColor(BevelColors.textMuted)
                    }
                    Text(inspectedDate ?? window.windowRangeLabel)
                        .font(ImprovingFont.caption(13))
                        .foregroundColor(BevelColors.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("Rango habitual")
                        .font(ImprovingFont.cardTitle(13))
                        .foregroundColor(accent)
                    Text("\(formatValue(trend.bandLow)) – \(formatValue(trend.bandHigh))")
                        .font(ImprovingFont.caption(12))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundColor(BevelColors.textPrimary)
                }
            }
            .padding(.horizontal, 16)

            HealthMetricBaselineChart(
                optionalPoints: window.values,
                dates: window.dates,
                bandLow: trend.bandLow,
                bandHigh: trend.bandHigh,
                averageText: avgVal.map { "Prom. \(formatValue($0))" } ?? "",
                accentColor: accent,
                valueFormatter: { formatValue($0) },
                onPointSelected: { _, v, d in
                    withAnimation(.easeOut(duration: 0.18)) {
                        inspectedFloat = v
                        inspectedDate = d
                    }
                }
            )
            .padding(.horizontal, 14)

            rangeSelectorBar(window: window)
                .padding(.horizontal, 14)
                .padding(.bottom, 16)
        }
        .background(BevelColors.sheetHeaderBg)
    }

    @ViewBuilder
    private func rangeSelectorBar(window: MetricWindowSeries) -> some View {
        HStack(spacing: 6) {
            Button {
                if window.canStepBackward {
                    inspectedFloat = nil
                    inspectedDate = nil
                    windowPageOffset += 1
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(window.canStepBackward ? BevelColors.textPrimary : BevelColors.textMuted.opacity(0.35))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(window.canStepBackward ? 0.08 : 0.03)))
            }
            .disabled(!window.canStepBackward)

            HStack(spacing: 2) {
                ForEach(["7 d", "30 d", "3 M", "6 M", "1 A"], id: \.self) { r in
                    let active = selectedRange == r
                    Button {
                        inspectedFloat = nil
                        inspectedDate = nil
                        windowPageOffset = 0
                        selectedRange = r
                    } label: {
                        Text(r)
                            .font(ImprovingFont.caption(11.5))
                            .fontWeight(.semibold)
                            .foregroundColor(active ? .white : BevelColors.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(active ? Color(hex: 0x6A6E7A) : .clear))
                    }
                }
            }
            .padding(3)
            .background(Capsule().fill(Color.white.opacity(0.06)))

            Button {
                if window.canStepForward {
                    inspectedFloat = nil
                    inspectedDate = nil
                    windowPageOffset = max(0, windowPageOffset - 1)
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(window.canStepForward ? BevelColors.textPrimary : BevelColors.textMuted.opacity(0.35))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(window.canStepForward ? 0.08 : 0.03)))
            }
            .disabled(!window.canStepForward)
        }
    }

    @ViewBuilder
    private func detailsSection(
        avgVal: Double?,
        maxVal: Double?,
        minVal: Double?,
        accent: Color,
        multiTrends: [MetricTrendPeriodRow]
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                summaryPill(label: "Promedio", value: avgVal.map(formatValue) ?? "--", color: accent)
                summaryPill(label: "Máximo", value: maxVal.map(formatValue) ?? "--", color: BevelColors.textPrimary)
                summaryPill(label: "Mínimo", value: minVal.map(formatValue) ?? "--", color: BevelColors.textSecondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Tendencias por período")
                    .font(ImprovingFont.sectionTitle(17.5))
                    .foregroundColor(BevelColors.textPrimary)

                BevelCard(cornerRadius: 18) {
                    VStack(spacing: 0) {
                        ForEach(Array(multiTrends.enumerated()), id: \.element.id) { idx, row in
                            multiPeriodRowView(row: row, accent: accent)
                            if idx < multiTrends.count - 1 {
                                Divider().background(BevelColors.divider).padding(.horizontal, 14)
                            }
                        }
                    }
                }
            }

            if !trend.detailNote.isEmpty {
                BevelCard(cornerRadius: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sobre esta tendencia")
                            .font(ImprovingFont.cardTitle(14.5))
                            .foregroundColor(BevelColors.textPrimary)
                        Text(trend.detailNote)
                            .font(ImprovingFont.body(13.5))
                            .foregroundColor(BevelColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    @ViewBuilder
    private func multiPeriodRowView(row: MetricTrendPeriodRow, accent: Color) -> some View {
        let latestVal = row.sparklinePoints.last
        HStack {
            Text(row.label)
                .font(ImprovingFont.body(13.5))
                .foregroundColor(BevelColors.textSecondary)
            Spacer()
            Text(latestVal.map(formatValue) ?? "--")
                .font(ImprovingFont.cardTitle(14))
                .monospacedDigit()
                .foregroundColor(BevelColors.textPrimary)
            if let delta = row.delta {
                let sign = delta >= 0 ? "+" : ""
                let dTxt = isDurationMinutesTrend
                    ? "\(sign)\(Int(delta.rounded()))m"
                    : String(format: "%@%.1f", locale: Locale(identifier: "es_ES"), sign, delta)
                Text(dTxt)
                    .font(ImprovingFont.caption(12))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundColor(abs(delta) < 0.05 ? BevelColors.textMuted : (delta >= 0 ? accent : BevelColors.coralHigh))
                    .frame(width: 64, alignment: .trailing)
            } else {
                Text("--")
                    .font(ImprovingFont.caption(12))
                    .foregroundColor(BevelColors.textMuted)
                    .frame(width: 64, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func summaryPill(label: String, value: String, color: Color) -> some View {
        BevelCard(cornerRadius: 14) {
            VStack(spacing: 4) {
                Text(label)
                    .font(ImprovingFont.caption(11))
                    .foregroundColor(BevelColors.textMuted)
                Text(value)
                    .font(ImprovingFont.cardTitle(13.5))
                    .monospacedDigit()
                    .foregroundColor(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
        }
    }
}

// MARK: - 1. Health Monitor Metric Detail Sheet (7 d | 30 d | 3 M | 6 M | 1 A + Working < > Time Navigation + Zero Fake Data)

struct HealthMetricDetailScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void

    @State private var inspectedFloat: Double? = nil
    @State private var inspectedDate: String? = nil
    @State private var windowPageOffset: Int = 0
    @State private var showDateSheet: Bool = false
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
        case "30 d": return 30
        case "3 M": return 90
        case "6 M": return 180
        case "1 A": return 365
        default: return 30
        }
    }

    private func leadingEmoji(for kind: HealthMetricKind) -> String {
        switch kind {
        case .respiratoryRate: return "🌬️"
        case .restingHeartRate: return "📉"
        case .hrv: return "📈"
        case .oxygenSaturation: return "🫁"
        case .wristTemperature: return "🌡️"
        case .sleepDuration: return "🌙"
        }
    }

    private func educationalText(for kind: HealthMetricKind) -> [String] {
        switch kind {
        case .respiratoryRate:
            return [
                "La FR registra tus respiraciones por minuto durante el sueño.",
                "La FR suele tener un nivel similar todas las noches, por lo que, en caso de observar un gran cambio, puede deberse a cansancio, infección, alergias o cambios de altitud."
            ]
        case .restingHeartRate:
            return [
                "La FCR mide el promedio de los latidos del corazón por minuto mientras estás completamente en reposo.",
                "Una FCR más baja suele reflejar mejor eficiencia cardiovascular, mientras que subidas temporales pueden señalar fatiga o falta de recuperación."
            ]
        case .hrv:
            return [
                "La VFC en reposo es la variación temporal entre latidos mientras duermes y refleja el equilibrio de tu sistema nervioso autónomo.",
                "Si sube indica buena adaptación; si baja varios días seguidos puede señalar sobrecarga, estrés o descanso insuficiente."
            ]
        case .oxygenSaturation:
            return [
                "La SpO₂ mide el porcentaje de sangre saturada con oxígeno durante el sueño y en segundo plano.",
                "Se ve influida por la altitud, la calidad respiratoria nocturna y la hidratación."
            ]
        case .wristTemperature:
            return [
                "La temperatura refleja la temperatura media de la piel de tu muñeca durante la noche.",
                "Por regla general, es aproximadamente 1–2 °C inferior a la temperatura corporal central y ayuda a detectar desviaciones tempranas."
            ]
        case .sleepDuration:
            return [
                "La duración del sueño registra el tiempo total que has pasado dormido excluyendo períodos de vigilia.",
                "La mayoría de adultos rinden mejor entre 7 y 9 horas diarias con horarios regulares."
            ]
        }
    }

    var body: some View {
        let kind = store.selectedHealthMetric
        let personalBand = store.personalVitalNormalBand(for: kind)
        let window = store.metricWindowSeries(for: kind, spanDays: spanDays, windowPageOffset: windowPageOffset)
        let realPoints = window.realPoints
        let bandLow = personalBand.low
        let bandHigh = personalBand.high
        let currentNumeric: Double? = switch kind {
        case .respiratoryRate: store.dataAvailability.hasRespData ? store.respRateRpm : nil
        case .restingHeartRate: store.dataAvailability.hasRestingHrData ? store.restingHrBpm : nil
        case .hrv: store.dataAvailability.hasHrvData ? store.hrvMs : nil
        case .oxygenSaturation: store.spo2Value
        case .wristTemperature: store.wristTempAbsoluteC
        case .sleepDuration: store.currentDaySummary?.asleepMinutes.map { Double($0) / 60.0 }
        }
        let avgVal: Double? = realPoints.isEmpty ? nil : (realPoints.reduce(0, +) / Double(realPoints.count))
        let displayVal: Double? = inspectedFloat ?? (windowPageOffset == 0 ? currentNumeric : nil) ?? realPoints.last

        // Real weekday sleep distribution (only computed from real recorded sleep days!)
        let weekdaySleepAvgs: [(String, Double)] = {
            guard kind == .sleepDuration else { return [] }
            let cal = Calendar.current
            var buckets: [Int: [Double]] = [:]
            for (iso, summary) in store.activeHistory {
                guard let mins = summary.asleepMinutes, mins > 0, let dt = store.isoFormatter.date(from: iso) else { continue }
                let wd = cal.component(.weekday, from: dt) // 1=Sun .. 7=Sat
                buckets[wd, default: []].append(Double(mins) / 60.0)
            }
            guard !buckets.isEmpty else { return [] }
            let order: [(Int, String)] = [(2, "lun"), (3, "mar"), (4, "mié"), (5, "jue"), (6, "vie"), (7, "sáb"), (1, "dom")]
            return order.map { wd, name in
                let arr = buckets[wd] ?? []
                let mean = arr.isEmpty ? 0.0 : arr.reduce(0, +) / Double(arr.count)
                return (name, mean)
            }
        }()

        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 14) {
                        DetailSheetHeader(title: kind.title, onBack: onBack)

                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 2) {
                                if let val = displayVal {
                                    if kind == .sleepDuration {
                                        let totalM = Int((val * 60.0).rounded())
                                        Text("\(totalM / 60) h \(String(format: "%02d", totalM % 60)) min")
                                            .font(ImprovingFont.displayLarge(31))
                                            .monospacedDigit()
                                            .foregroundColor(BevelColors.textPrimary)
                                    } else {
                                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                                            EmptyView().animatableNumber(
                                                val,
                                                decimals: 1,
                                                font: ImprovingFont.displayLarge(33),
                                                color: BevelColors.textPrimary
                                            )
                                            if !kind.unit.isEmpty {
                                                Text(kind.unit)
                                                    .font(ImprovingFont.sectionTitle(19))
                                                    .foregroundColor(BevelColors.textPrimary)
                                            }
                                        }
                                    }
                                } else {
                                    Text("Sin datos")
                                        .font(ImprovingFont.displayLarge(28))
                                        .foregroundColor(BevelColors.textMuted)
                                }
                                Text(inspectedDate ?? window.windowRangeLabel)
                                    .font(ImprovingFont.caption(13))
                                    .foregroundColor(BevelColors.textSecondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("Rango referencia")
                                    .font(ImprovingFont.cardTitle(13.5))
                                    .foregroundColor(BevelColors.greenPrimary)
                                Text(kind == .sleepDuration
                                     ? "7 h 00 min – 9 h 00 min"
                                     : String(format: "%.1f – %.1f %@", locale: Locale(identifier: "es_ES"), bandLow, bandHigh, kind.unit))
                                    .font(ImprovingFont.caption(12.5))
                                    .fontWeight(.semibold)
                                    .monospacedDigit()
                                    .foregroundColor(BevelColors.textPrimary)
                            }
                        }
                        .padding(.horizontal, 16)

                        // Metric Switcher Pills
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(HealthMetricKind.allCases) { item in
                                    let active = item == kind
                                    Button {
                                        inspectedFloat = nil
                                        inspectedDate = nil
                                        windowPageOffset = 0
                                        store.selectedHealthMetric = item
                                    } label: {
                                        Text(item.title)
                                            .font(ImprovingFont.caption(12.5))
                                            .fontWeight(.semibold)
                                            .foregroundColor(active ? .white : BevelColors.textSecondary)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                            .background(Capsule().fill(active ? Color(hex: 0x6A6E7A) : Color.white.opacity(0.06)))
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }

                        // Sparse Interactive Baseline Chart
                        HealthMetricBaselineChart(
                            optionalPoints: window.values,
                            dates: window.dates,
                            bandLow: bandLow,
                            bandHigh: bandHigh,
                            averageText: avgVal.map { a in
                                kind == .sleepDuration
                                    ? "Prom. \(Int(a)) h \(Int((a - floor(a)) * 60)) min"
                                    : String(format: "Prom. %.1f %@", locale: Locale(identifier: "es_ES"), a, kind.unit)
                            } ?? "",
                            accentColor: BevelColors.greenPrimary,
                            valueFormatter: { v in
                                kind == .sleepDuration
                                    ? "\(Int(v)) h \(Int((v - floor(v)) * 60)) min"
                                    : String(format: "%.1f %@", locale: Locale(identifier: "es_ES"), v, kind.unit)
                            },
                            onPointSelected: { _, v, d in
                                withAnimation(.easeOut(duration: 0.18)) {
                                    inspectedFloat = v
                                    inspectedDate = d
                                }
                            }
                        )
                        .padding(.horizontal, 14)

                        // Interactive Range Selector: < [ 7 d | 30 d | 3 M | 6 M | 1 A ] 📅 >
                        HStack(spacing: 6) {
                            Button {
                                if window.canStepBackward {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    inspectedFloat = nil
                                    inspectedDate = nil
                                    windowPageOffset += 1
                                }
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(window.canStepBackward ? BevelColors.textPrimary : BevelColors.textMuted.opacity(0.35))
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(Color.white.opacity(window.canStepBackward ? 0.08 : 0.03)))
                            }
                            .disabled(!window.canStepBackward)

                            HStack(spacing: 2) {
                                ForEach(["7 d", "30 d", "3 M", "6 M", "1 A"], id: \.self) { r in
                                    let active = store.selectedHealthRange == r
                                    Button {
                                        UISelectionFeedbackGenerator().selectionChanged()
                                        inspectedFloat = nil
                                        inspectedDate = nil
                                        windowPageOffset = 0
                                        store.selectedHealthRange = r
                                    } label: {
                                        Text(r)
                                            .font(ImprovingFont.caption(11.5))
                                            .fontWeight(.semibold)
                                            .foregroundColor(active ? .white : BevelColors.textSecondary)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 6)
                                            .background(Capsule().fill(active ? Color(hex: 0x6A6E7A) : .clear))
                                    }
                                }
                            }
                            .padding(3)
                            .background(Capsule().fill(Color.white.opacity(0.06)))

                            Button { showDateSheet = true } label: {
                                Image(systemName: "calendar")
                                    .font(.system(size: 13))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(Color.white.opacity(0.08)))
                            }

                            Button {
                                if window.canStepForward {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    inspectedFloat = nil
                                    inspectedDate = nil
                                    windowPageOffset = max(0, windowPageOffset - 1)
                                }
                            } label: {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(window.canStepForward ? BevelColors.textPrimary : BevelColors.textMuted.opacity(0.35))
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(Color.white.opacity(window.canStepForward ? 0.08 : 0.03)))
                            }
                            .disabled(!window.canStepForward)
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 16)
                    }
                    .background(BevelColors.sheetHeaderBg)

                    VStack(alignment: .leading, spacing: 18) {
                        // Real Weekly Sleep Distribution (only if real sleep days exist!)
                        if kind == .sleepDuration && !weekdaySleepAvgs.isEmpty {
                            let maxHrs = max(weekdaySleepAvgs.map(\.1).max() ?? 9.0, 1.0)
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Distribución semanal del sueño")
                                    .font(ImprovingFont.sectionTitle(17.5))
                                    .foregroundColor(BevelColors.textPrimary)

                                HStack(spacing: 4) {
                                    ForEach(weekdaySleepAvgs, id: \.0) { name, hrs in
                                        let intensity = hrs > 0 ? min(max(hrs / maxHrs, 0.22), 1.0) : 0.08
                                        VStack(spacing: 6) {
                                            RoundedRectangle(cornerRadius: 5)
                                                .fill(hrs > 0 ? BevelColors.greenPrimary.opacity(intensity) : BevelColors.trackGroove)
                                                .frame(height: 16)
                                            Text(name)
                                                .font(ImprovingFont.caption(12))
                                                .foregroundColor(BevelColors.textPrimary)
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                }
                            }
                        }

                        // Análisis de tendencias (Strict Zero Fabrication!)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Análisis de tendencias")
                                .font(ImprovingFont.sectionTitle(18))
                                .foregroundColor(BevelColors.textPrimary)
                            Text("Comparando el período actual frente a tus medias históricas reales")
                                .font(ImprovingFont.caption(12.5))
                                .foregroundColor(BevelColors.textSecondary)
                        }

                        BevelCard(cornerRadius: 20) {
                            VStack(spacing: 0) {
                                HStack {
                                    Text("Período").frame(width: 82, alignment: .leading)
                                    Text("Variación")
                                    Spacer()
                                    Text("Tendencia").frame(width: 96, alignment: .trailing)
                                }
                                .font(ImprovingFont.caption(12))
                                .foregroundColor(BevelColors.textMuted)
                                .padding(.horizontal, 16)
                                .padding(.top, 14)
                                .padding(.bottom, 8)

                                let periods = [7, 14, 30, 90, 365]
                                ForEach(Array(periods.enumerated()), id: \.offset) { idx, p in
                                    let pSeries = store.metricWindowSeries(for: kind, spanDays: p, windowPageOffset: 0)
                                    let pReal = pSeries.realPoints

                                    HStack {
                                        Text(p == 365 ? "1 año" : "\(p) días")
                                            .font(ImprovingFont.body(14))
                                            .foregroundColor(BevelColors.textSecondary)
                                            .frame(width: 82, alignment: .leading)

                                        if pReal.count >= 2, let latest = pReal.last {
                                            let pAvg = pReal.reduce(0, +) / Double(pReal.count)
                                            let delta = latest - pAvg
                                            let isSignificant = abs(delta) >= (kind == .hrv ? 3.5 : (kind == .sleepDuration ? 0.35 : 0.7))
                                            let icon = !isSignificant ? "arrow.right.circle.fill" : (delta > 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                            let color = isSignificant ? BevelColors.skyBlue : BevelColors.textMuted

                                            HStack(spacing: 7) {
                                                Image(systemName: icon)
                                                    .font(.system(size: 16))
                                                    .foregroundColor(color)
                                                Text(kind == .sleepDuration
                                                     ? String(format: "%+d min", Int((delta * 60).rounded()))
                                                     : String(format: "%+.1f %@", locale: Locale(identifier: "es_ES"), delta, kind.unit))
                                                    .font(ImprovingFont.cardTitle(14))
                                                    .monospacedDigit()
                                                    .foregroundColor(BevelColors.textPrimary)
                                            }
                                            Spacer()
                                            TrendSparklineWithBand(
                                                optionalPoints: pSeries.values,
                                                lineColor: isSignificant ? BevelColors.skyBlue : BevelColors.textMuted,
                                                fillUnder: true
                                            )
                                            .frame(width: 96, height: 24)
                                        } else {
                                            Text("Sin datos suficientes")
                                                .font(ImprovingFont.caption(12.5))
                                                .foregroundColor(BevelColors.textMuted)
                                            Spacer()
                                        }
                                    }
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 16)

                                    if idx < periods.count - 1 {
                                        Divider().background(BevelColors.divider).padding(.horizontal, 16)
                                    }
                                }
                            }
                        }

                        // Educational Block
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle").font(.system(size: 14)).foregroundColor(BevelColors.textSecondary)
                                Text(kind.title).font(ImprovingFont.cardTitle(14.5)).foregroundColor(BevelColors.textSecondary)
                            }
                            ForEach(educationalText(for: kind), id: \.self) { para in
                                Text(para)
                                    .font(ImprovingFont.body(14))
                                    .foregroundColor(BevelColors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 20).fill(BevelColors.card.opacity(0.7)))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                }
                .padding(.bottom, 185)
            }
            .onVerticalScrollCollapse { scrollCollapseSignal += 1 }

            FloatingMetricAiCoachOverlay(
                metricKey: "\(kind.rawValue)_\(store.selectedHealthRange)_\(windowPageOffset)",
                metricTitle: kind.title,
                insight: aiInsight,
                scrollCollapseSignal: scrollCollapseSignal,
                leadingEmoji: leadingEmoji(for: kind)
            )
        }
        .background(BevelColors.canvas)
        .sheet(isPresented: $showDateSheet) {
            DatePickerSheetView(
                selectedDate: Binding(
                    get: { store.selectedDate },
                    set: { d in
                        store.selectDate(d)
                        windowPageOffset = 0
                        inspectedFloat = nil
                        inspectedDate = nil
                        showDateSheet = false
                    }
                ),
                onJumpToday: {
                    store.selectDayOffset(0)
                    windowPageOffset = 0
                    showDateSheet = false
                },
                onClose: { showDateSheet = false }
            )
        }
        .task(id: "\(kind.rawValue)_\(store.selectedHealthRange)_\(store.selectedDateIso)_\(windowPageOffset)") {
            let valStr = displayVal.map {
                kind == .sleepDuration
                    ? "\(Int($0)) h \(Int(($0 - floor($0)) * 60)) min"
                    : String(format: "%.1f %@", locale: Locale(identifier: "es_ES"), $0, kind.unit)
            } ?? "--"
            let rangeStr = kind == .sleepDuration
                ? String(format: "%.1f h – %.1f h", locale: Locale(identifier: "es_ES"), bandLow, bandHigh)
                : String(format: "%.1f–%.1f %@", locale: Locale(identifier: "es_ES"), bandLow, bandHigh, kind.unit)
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
                hasData: displayVal != nil
            )
            aiInsight = res
        }
    }
}

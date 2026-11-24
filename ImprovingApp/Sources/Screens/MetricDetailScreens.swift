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

    private func formatValue(_ val: Double) -> String {
        if isDurationMinutesTrend {
            let m = Int(val.rounded())
            return "\(m / 60) h \(String(format: "%02d", m % 60)) min"
        }
        if trend.id == "t_perf" {
            return String(format: "%+.0f %@", val, trend.unitText).trimmingCharacters(in: .whitespaces)
        }
        if trend.id == "t_steps" || trend.id == "t_kcal" || trend.id == "t_strain" || trend.id == "r_rec" || trend.id == "s_score" || trend.id == "s_eff" || trend.id == "t_dur" || trend.id == "t_day_hr" || trend.id == "st_score" || trend.id == "st_sleep" || trend.id == "s_lat" || trend.id == "s_dip" {
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

                    // Range selector: < [ 7 d | 30 d | 3 M | 6 M | 1 A ] >
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
                    .padding(.horizontal, 14)
                    .padding(.bottom, 16)
                }
                .background(BevelColors.sheetHeaderBg)

                VStack(alignment: .leading, spacing: 16) {
                    // Period Summary Cards
                    HStack(spacing: 10) {
                        summaryPill(label: "Promedio", value: avgVal.map(formatValue) ?? "--", color: accent)
                        summaryPill(label: "Máximo", value: maxVal.map(formatValue) ?? "--", color: BevelColors.textPrimary)
                        summaryPill(label: "Mínimo", value: minVal.map(formatValue) ?? "--", color: BevelColors.textSecondary)
                    }

                    // Multi-period Trend Table (3d / 7d / 14d / 30d / 90d)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Tendencias por período")
                            .font(ImprovingFont.sectionTitle(17.5))
                            .foregroundColor(BevelColors.textPrimary)

                        BevelCard(cornerRadius: 18) {
                            VStack(spacing: 0) {
                                ForEach(Array(multiTrends.enumerated()), id: \.element.id) { idx, row in
                                    HStack {
                                        Text(row.label)
                                            .font(ImprovingFont.body(13.5))
                                            .foregroundColor(BevelColors.textSecondary)
                                        Spacer()
                                        Text(row.currentAvg.map(formatValue) ?? "--")
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
                                                .foregroundColor(abs(delta) < 0.05 ? BevelColors.textMuted : (delta >= 0 ? BevelColors.greenPrimary : BevelColors.coralHigh))
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
                                    if idx < multiTrends.count - 1 {
                                        Divider().background(BevelColors.divider).padding(.horizontal, 14)
                                    }
                                }
                            }
                        }
                    }

                    // Educational note
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
            .padding(.bottom, 150)
        }
        .background(BevelColors.canvas)
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

// MARK: - 2. Training Load Detail Sheet (Exact Match to Screenshots 3-6 & 12: EWMA Ribbon + 7-State Breakdown + Resources + AI Pill)

struct TrainingLoadDetailScreen: View {
    @ObservedObject var store: ImprovingStore
    let initialTab: TrainingLoadTab
    let onBack: () -> Void

    @State private var selectedTab: TrainingLoadTab = .cardio
    @State private var selectedRange: String = "30 d"
    @State private var windowPageOffset: Int = 0
    @State private var scrubbedPoint: TrainingLoadDayPoint? = nil
    @State private var showInfoSheet: Bool = false

    private var spanDays: Int {
        FitnessRangeControlBar.spanDays(for: selectedRange, anchorDate: store.selectedDate)
    }

    private var resourcesForTab: [FitnessResourceItem] {
        if selectedTab == .cardio {
            return [
                FitnessResourceItem(
                    id: "res_cardio_basics",
                    badgeIcon: "shoeprints.fill",
                    heroTitle: "Cardio Load",
                    heroSubtitle: "The Basics",
                    cardTitle: "The Basics: Cardio Load",
                    cardDescription: "Entrena con inteligencia optimizando tu carga cardiovascular.",
                    gradientHexA: 0x385468,
                    gradientHexB: 0x5B4B3F,
                    fullGuideBody: "La Carga Cardíaca compara tu esfuerzo cardiovascular agudo de los últimos 7 días frente a tu base crónica de los últimos 28 días. Mantenerte dentro de la banda verde óptima te permite mejorar tu capacidad aeróbica y tu VO₂ máx. sin acumular fatiga innecesaria."
                ),
                FitnessResourceItem(
                    id: "res_cardio_status",
                    badgeIcon: "bicycle",
                    heroTitle: "Cardio Status",
                    heroSubtitle: "Training Zones",
                    cardTitle: "Cardio Status",
                    cardDescription: "Entiende el impacto entre tu carga de entrenamiento y recuperación.",
                    gradientHexA: 0x263B32,
                    gradientHexB: 0x1D252C,
                    fullGuideBody: "Tus 7 estados (Calibrando, Desentrenamiento, Pico de forma, Manteniéndose, Productivo, Fatigado y Entrenamiento excesivo) reflejan la relación entre carga aguda y crónica. Durante las primeras 3 semanas el sistema muestra Calibrando mientras consolida tu historial real."
                )
            ]
        } else {
            return [
                FitnessResourceItem(
                    id: "res_musc_basics",
                    badgeIcon: "scope",
                    heroTitle: "Muscular Load",
                    heroSubtitle: "The Basics",
                    cardTitle: "The Basics: Muscular Load",
                    cardDescription: "Entrena fuerza con propósito controlando tu volumen y fatiga.",
                    gradientHexA: 0x4A3D36,
                    gradientHexB: 0x23262E,
                    fullGuideBody: "La Carga Muscular integra tus sesiones de fuerza registradas en Apple Salud junto con las series y el volumen (kg) que anotes en Improving. Al respetar la franja óptima verde favoreces la hipertrofia y la fuerza reduciendo el riesgo de sobrecarga articular."
                ),
                FitnessResourceItem(
                    id: "res_musc_fresh",
                    badgeIcon: "battery.75percent",
                    heroTitle: "Muscle Freshness",
                    heroSubtitle: "The Basics",
                    cardTitle: "The Basics: Muscle Freshness",
                    cardDescription: "Descubre qué grupos musculares están recuperados y cuáles necesitan descanso.",
                    gradientHexA: 0x2C3F36,
                    gradientHexB: 0x1B2228,
                    fullGuideBody: "Cada grupo muscular sigue una curva fisiológica de recuperación de 48 a 72 horas según la intensidad, series y volumen del estímulo recibido. Alternar grupos recuperados en verde con descanso en los fatigados maximiza la progresión semanal."
                )
            ]
        }
    }

    var body: some View {
        let isCardio = selectedTab == .cardio
        let analysis = store.trainingLoadAnalysis(tab: selectedTab, spanDays: spanDays, windowPageOffset: windowPageOffset)
        let activeLoadVal = scrubbedPoint.map { Int($0.load.rounded()) } ?? analysis.currentLoad
        let activeState = scrubbedPoint?.state ?? analysis.currentState
        let activeOptLow = scrubbedPoint.map { Int($0.optLow.rounded()) } ?? analysis.optimalLow
        let activeOptHigh = scrubbedPoint.map { Int($0.optHigh.rounded()) } ?? analysis.optimalHigh
        let dateSubtitle: String = {
            if let sp = scrubbedPoint { return sp.shortDateLabel }
            let f = DateFormatter()
            f.locale = Locale(identifier: "es_ES")
            f.dateFormat = "d MMM yyyy"
            return f.string(from: store.selectedDate).replacingOccurrences(of: ".", with: "")
        }()

        let aiInsight: MetricFloatingAiInsight = {
            let kindWord = isCardio ? "Carga cardíaca" : "Carga muscular"
            let pill: String
            let shortMsg: String
            if !analysis.hasAnyData {
                pill = isCardio ? "Sin sesiones en el período" : "Sin fuerza registrada"
                shortMsg = "Todavía no hay entrenamientos suficientes en Apple Health o Improving para calcular tu \(kindWord.lowercased()). Sincroniza tu Atajo de Salud o registra tu próxima sesión."
            } else if activeState == .calibrating {
                pill = isCardio ? "Carga cardíaca provisional" : "Carga muscular en calibración"
                shortMsg = "Tu \(kindWord) actual es \(activeLoadVal) (rango óptimo \(activeOptLow)–\(activeOptHigh)), pero sigue en calibración mientras reúne 21 días de base real."
            } else {
                pill = "\(kindWord): \(activeState.rawValue)"
                shortMsg = "Tu \(kindWord) está en \(activeLoadVal) frente a un rango óptimo de \(activeOptLow)–\(activeOptHigh) (\(activeState.rawValue))."
            }
            return MetricFloatingAiInsight(
                shortPillText: pill,
                expandedHeadline: pill,
                shortExpandedMessage: shortMsg,
                expandedMessage: shortMsg + " Mantener la curva dentro de la franja verde óptima favorece adaptaciones sostenibles semana tras semana.",
                structureIndex: 0,
                variationSeed: 1
            )
        }()

        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Button(action: onBack) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .frame(width: 40, height: 40)
                                    .background(Circle().fill(BevelColors.glassChromeFill))
                                    .overlay(Circle().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.8))
                            }
                            Spacer()
                            Text(isCardio ? "Carga cardíaca" : "Carga muscular")
                                .font(ImprovingFont.cardTitle(16.5))
                                .foregroundColor(BevelColors.textPrimary)
                            Spacer()
                            Button { showInfoSheet = true } label: {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .frame(width: 40, height: 40)
                                    .background(Circle().fill(BevelColors.glassChromeFill))
                                    .overlay(Circle().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.8))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 10)

                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(analysis.hasAnyData ? "\(activeLoadVal)" : "--")
                                    .font(ImprovingFont.displayLarge(36))
                                    .monospacedDigit()
                                    .foregroundColor(analysis.hasAnyData ? BevelColors.textPrimary : BevelColors.textMuted)
                                Text(dateSubtitle)
                                    .font(ImprovingFont.caption(13.5))
                                    .foregroundColor(BevelColors.textSecondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(activeState.rawValue)
                                    .font(ImprovingFont.cardTitle(16))
                                    .foregroundColor(activeState.accentColor)
                                HStack(spacing: 5) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 2).fill(BevelColors.greenPrimary.opacity(0.28)).frame(width: 11, height: 11)
                                        VStack(spacing: 5) {
                                            Rectangle().fill(BevelColors.greenPrimary).frame(width: 11, height: 1.5)
                                            Rectangle().fill(BevelColors.greenPrimary).frame(width: 11, height: 1.5)
                                        }
                                    }
                                    Text("Óptimo: \(activeOptLow)-\(activeOptHigh)")
                                        .font(ImprovingFont.cardTitle(13.5))
                                        .monospacedDigit()
                                        .foregroundColor(BevelColors.textPrimary)
                                }
                            }
                        }
                        .padding(.horizontal, 16)

                        HStack(spacing: 10) {
                            tabPill("Carga cardíaca", active: isCardio) {
                                selectedTab = .cardio
                                windowPageOffset = 0
                                scrubbedPoint = nil
                            }
                            tabPill("Carga muscular", active: !isCardio) {
                                selectedTab = .muscular
                                windowPageOffset = 0
                                scrubbedPoint = nil
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)

                        TrainingLoadOptimalBandChart(
                            points: analysis.points,
                            currentOptLow: activeOptLow,
                            currentOptHigh: activeOptHigh,
                            onPointSelected: { scrubbedPoint = $0 }
                        )
                        .padding(.horizontal, 14)

                        FitnessRangeControlBar(
                            selectedRange: $selectedRange,
                            canStepBackward: true,
                            canStepForward: windowPageOffset > 0,
                            onStepBackward: { windowPageOffset += 1; scrubbedPoint = nil },
                            onStepForward: { windowPageOffset = max(0, windowPageOffset - 1); scrubbedPoint = nil },
                            onRangeChanged: { windowPageOffset = 0; scrubbedPoint = nil }
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                    .background(BevelColors.sheetHeaderBg)

                    // Breakdown Table (Exact Match to Screenshots 3-6!)
                    VStack(alignment: .leading, spacing: 18) {
                        Text(isCardio ? "Desglose de la carga cardíaca" : "Desglose de la carga muscular")
                            .font(ImprovingFont.sectionTitle(18))
                            .foregroundColor(BevelColors.textPrimary)

                        BevelCard(cornerRadius: 20) {
                            VStack(spacing: 0) {
                                HStack {
                                    Text("Estado").frame(width: 116, alignment: .leading)
                                    Text("Duración").frame(width: 52, alignment: .leading)
                                    Spacer()
                                    Text("%").frame(width: 44, alignment: .trailing)
                                }
                                .font(ImprovingFont.caption(12))
                                .foregroundColor(BevelColors.textMuted)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)

                                ForEach(Array(analysis.breakdown.enumerated()), id: \.element.id) { idx, row in
                                    if idx > 0 {
                                        Divider().background(BevelColors.divider).padding(.horizontal, 14)
                                    }
                                    HStack(spacing: 10) {
                                        Text(row.state.rawValue)
                                            .font(ImprovingFont.body(14))
                                            .foregroundColor(row.days > 0 ? BevelColors.textPrimary : BevelColors.textSecondary)
                                            .frame(width: 116, alignment: .leading)
                                            .fixedSize(horizontal: false, vertical: true)

                                        Text("\(row.days)d")
                                            .font(ImprovingFont.cardTitle(14))
                                            .monospacedDigit()
                                            .foregroundColor(BevelColors.textPrimary)
                                            .frame(width: 42, alignment: .leading)

                                        GeometryReader { geo in
                                            ZStack(alignment: .leading) {
                                                Capsule().fill(Color.white.opacity(0.08)).frame(height: 8)
                                                if row.percent > 0 {
                                                    Capsule()
                                                        .fill(row.state == .calibrating ? Color(hex: 0x9CA3AF) : row.state.accentColor)
                                                        .frame(width: max(8, geo.size.width * CGFloat(row.percent) / 100.0), height: 8)
                                                }
                                            }
                                            .frame(maxHeight: .infinity)
                                        }
                                        .frame(height: 18)

                                        Text("\(row.percent)%")
                                            .font(ImprovingFont.cardTitle(14))
                                            .monospacedDigit()
                                            .foregroundColor(row.percent > 0 ? BevelColors.textPrimary : BevelColors.textMuted)
                                            .frame(width: 44, alignment: .trailing)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 13)
                                }
                            }
                        }

                        FitnessResourceCarousel(items: resourcesForTab)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                }
                .padding(.bottom, 165)
            }
            .background(BevelColors.canvas)

            FloatingMetricAiCoachOverlay(
                metricKey: "tl_\(selectedTab.rawValue)_\(selectedRange)_\(windowPageOffset)",
                metricTitle: isCardio ? "Carga cardíaca" : "Carga muscular",
                insight: aiInsight,
                scrollCollapseSignal: 0,
                leadingEmoji: isCardio ? "🚴" : "🏋️"
            )
        }
        .onAppear { selectedTab = initialTab }
        .sheet(isPresented: $showInfoSheet) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(isCardio ? "¿Cómo se calcula la Carga cardíaca?" : "¿Cómo se calcula la Carga muscular?")
                            .font(ImprovingFont.sectionTitle(19))
                            .foregroundColor(BevelColors.textPrimary)
                        Text(isCardio
                             ? "Improving calcula una media móvil exponencial aguda (7 días) y una base crónica (28 días) a partir de tus entrenamientos reales, zonas de FC y esfuerzo diario de Apple Health. La franja verde representa la ventana óptima (80%–132% de tu carga crónica)."
                             : "Improving combina tus sesiones de entrenamiento de fuerza importadas desde Apple Health (duración, esfuerzo y calorías) con las series y kilogramos registrados en tu diario de fuerza para calcular tu carga aguda vs. crónica y tu frescura muscular.")
                            .font(ImprovingFont.body(14.5))
                            .foregroundColor(BevelColors.textSecondary)
                            .lineSpacing(4)
                    }
                    .padding(18)
                }
                .background(BevelColors.canvas)
                .navigationTitle("Información")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { Button("Cerrar") { showInfoSheet = false } }
                }
            }
        }
    }

    private func tabPill(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(ImprovingFont.cardTitle(13.5))
                .foregroundColor(active ? .white : BevelColors.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 9.5)
                .background(Capsule().fill(active ? Color(hex: 0x6A6E7A) : Color.white.opacity(0.06)))
        }
    }
}

// MARK: - 3. Cardio & Strength Metric Detail Sheet (All 9 Fitness Subscreens Matching Screenshots 7-33!)

struct CardioMetricDetailScreen: View {
    @ObservedObject var store: ImprovingStore
    let route: CardioMetricRoute
    let onBack: () -> Void

    @State private var currentRoute: CardioMetricRoute = .activitiesDuration
    @State private var selectedRange: String = "30 d"
    @State private var windowPageOffset: Int = 0
    @State private var isBarMode: Bool = false
    @State private var selectedActivityFilter: String = "Todas"
    @State private var selectedActivityKpi: Int = 0 // 0=Dur, 1=Dist, 2=Elev, 3=Kcal, 4=Pace, 5=Speed, 6=HR, 7=Power, 8=Cadence
    @State private var selectedStrengthKpi: Int = 0 // 0=Series, 1=Volumen, 2=Carga
    @State private var sortNewestFirst: Bool = true
    @State private var selectedZoneIdx: Int = 1
    @State private var muscleModeTab: Int = 2 // 0=Volumen total, 1=Carga muscular, 2=Frescura muscular
    @State private var muscleStateFilter: MuscleFreshnessState? = nil
    @State private var muscleDateOffset: Int = 0
    @State private var selectedMuscleDropdown: String = "Todos los músculos"

    private var spanDays: Int {
        FitnessRangeControlBar.spanDays(for: selectedRange, anchorDate: store.selectedDate)
    }

    private var windowDates: (start: Date, end: Date, prevStart: Date, prevEnd: Date, isos: [String], prevIsos: [String], shortLabels: [String], rangeTitle: String) {
        let cal = Calendar.current
        let anchor = cal.startOfDay(for: store.selectedDate)
        let end = cal.date(byAdding: .day, value: -(windowPageOffset * spanDays), to: anchor) ?? anchor
        let start = cal.date(byAdding: .day, value: -(spanDays - 1), to: end) ?? end
        let prevEnd = cal.date(byAdding: .day, value: -1, to: start) ?? start
        let prevStart = cal.date(byAdding: .day, value: -(spanDays - 1), to: prevEnd) ?? prevEnd

        let shortFmt = DateFormatter()
        shortFmt.locale = Locale(identifier: "es_ES")
        shortFmt.dateFormat = spanDays >= 180 ? "MMM yy" : "d MMM"
        let headerFmt = DateFormatter()
        headerFmt.locale = Locale(identifier: "es_ES")
        headerFmt.dateFormat = "d MMM"
        let yearFmt = DateFormatter()
        yearFmt.locale = Locale(identifier: "es_ES")
        yearFmt.dateFormat = "d MMM yyyy"

        var isos: [String] = []
        var prevIsos: [String] = []
        var labels: [String] = []
        for i in 0..<spanDays {
            if let d = cal.date(byAdding: .day, value: i, to: start) {
                isos.append(store.isoFormatter.string(from: d))
                labels.append(shortFmt.string(from: d).replacingOccurrences(of: ".", with: ""))
            }
            if let pd = cal.date(byAdding: .day, value: i, to: prevStart) {
                prevIsos.append(store.isoFormatter.string(from: pd))
            }
        }
        let rTitle = "\(headerFmt.string(from: start).replacingOccurrences(of: ".", with: "")) – \(yearFmt.string(from: end).replacingOccurrences(of: ".", with: ""))"
        return (start, end, prevStart, prevEnd, isos, prevIsos, labels, rTitle)
    }

    private var availableActivityNames: [String] {
        let names = Set(store.activeHistory.values.flatMap { $0.workouts.map(\.title) })
        return ["Todas"] + names.sorted()
    }

    private func filterWorkouts(_ list: [EffortEventItem]) -> [EffortEventItem] {
        if selectedActivityFilter == "Todas" { return list }
        return list.filter { $0.title == selectedActivityFilter }
    }

    private func formatHMS(_ mins: Int) -> String {
        String(format: "%d:%02d:00", mins / 60, mins % 60)
    }

    private func formatShortDate(_ iso: String) -> String {
        guard let d = store.isoFormatter.date(from: iso) else { return iso }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "d MMM yyyy"
        return f.string(from: d).replacingOccurrences(of: ".", with: "")
    }

    private func groupWorkoutsByMonth(_ items: [(iso: String, workout: EffortEventItem)]) -> [(monthTitle: String, items: [EffortEventItem])] {
        let mFmt = DateFormatter()
        mFmt.locale = Locale(identifier: "es_ES")
        mFmt.dateFormat = "MMMM 'de' yyyy"

        let ordered = sortNewestFirst
            ? items.sorted { ($0.iso, $0.workout.timeRange) > ($1.iso, $1.workout.timeRange) }
            : items.sorted { ($0.iso, $0.workout.timeRange) < ($1.iso, $1.workout.timeRange) }

        var groups: [(String, [EffortEventItem])] = []
        for entry in ordered {
            let key: String = {
                if let d = store.isoFormatter.date(from: entry.iso) {
                    return mFmt.string(from: d).lowercased()
                }
                return entry.iso
            }()
            if let last = groups.last, last.0 == key {
                groups[groups.count - 1].1.append(entry.workout)
            } else {
                groups.append((key, [entry.workout]))
            }
        }
        return groups
    }

    var body: some View {
        Group {
            switch currentRoute {
            case .activitiesDuration, .activitiesEnergy:
                activitiesOverviewView
            case .vo2Max:
                vo2MaxDetailView
            case .hrRecovery:
                hrRecoveryDetailView
            case .cardioFocus:
                cardioFocusDetailView
            case .hrZones:
                hrZonesDetailView
            case .strengthSets, .strengthVolume:
                strengthOverviewView
            case .muscleGroups:
                muscleGroupsDetailView
            }
        }
        .onAppear {
            currentRoute = route
            if route == .activitiesEnergy { selectedActivityKpi = 3 }
            else if route == .activitiesDuration { selectedActivityKpi = 0 }
            else if route == .strengthVolume { selectedStrengthKpi = 1 }
            else if route == .strengthSets { selectedStrengthKpi = 0 }
        }
    }

    // MARK: - 3A. Todas las actividades (Screenshots 7-11!)

    private var activitiesOverviewView: some View {
        let win = windowDates
        let curWorkoutsDated: [(iso: String, workout: EffortEventItem)] = win.isos.flatMap { iso in
            filterWorkouts(store.activeHistory[iso]?.workouts ?? []).map { (iso, $0) }
        }
        let prevWorkoutsDated: [(iso: String, workout: EffortEventItem)] = win.prevIsos.flatMap { iso in
            filterWorkouts(store.activeHistory[iso]?.workouts ?? []).map { (iso, $0) }
        }

        let curDur = curWorkoutsDated.reduce(0) { $0 + $1.workout.durationMin }
        let prevDur = prevWorkoutsDated.reduce(0) { $0 + $1.workout.durationMin }
        let curDist = curWorkoutsDated.compactMap(\.workout.distanceKm).reduce(0, +)
        let prevDist = prevWorkoutsDated.compactMap(\.workout.distanceKm).reduce(0, +)
        let curElev = win.isos.compactMap { store.activeHistory[$0]?.elevationM }.reduce(0, +)
            + curWorkoutsDated.compactMap(\.workout.elevationM).reduce(0, +)
        let prevElev = win.prevIsos.compactMap { store.activeHistory[$0]?.elevationM }.reduce(0, +)
            + prevWorkoutsDated.compactMap(\.workout.elevationM).reduce(0, +)
        let curKcal = curWorkoutsDated.reduce(0) { $0 + $1.workout.kcal }
        let prevKcal = prevWorkoutsDated.reduce(0) { $0 + $1.workout.kcal }

        // Pace & Speed from workouts with real distanceKm > 0
        let distWorkouts = curWorkoutsDated.filter { ($0.workout.distanceKm ?? 0) > 0.05 }
        let distKmSum = distWorkouts.compactMap(\.workout.distanceKm).reduce(0, +)
        let distMinSum = Double(distWorkouts.reduce(0) { $0 + $1.workout.durationMin })
        let paceMinPerKm: Double? = distKmSum > 0.1 ? (distMinSum / distKmSum) : nil
        let speedKmh: Double? = distMinSum > 0.5 && distKmSum > 0.1 ? (distKmSum / (distMinSum / 60.0)) : nil

        let hrVals = curWorkoutsDated.map(\.workout.avgHrBpm).filter { $0 > 0 }
        let avgWorkoutHr: Int? = hrVals.isEmpty ? nil : Int((Double(hrVals.reduce(0, +)) / Double(hrVals.count)).rounded())
        let powerVals = curWorkoutsDated.compactMap(\.workout.avgPowerW) + win.isos.compactMap { store.activeHistory[$0]?.avgPowerW }
        let avgPower: Double? = powerVals.isEmpty ? nil : (powerVals.reduce(0, +) / Double(powerVals.count))
        let cadVals = curWorkoutsDated.compactMap(\.workout.avgCadenceRpm) + win.isos.compactMap { store.activeHistory[$0]?.avgCadenceRpm }
        let avgCadence: Double? = cadVals.isEmpty ? nil : (cadVals.reduce(0, +) / Double(cadVals.count))

        // Daily series for the selected KPI card
        let dailyCur: [Double] = win.isos.map { iso in
            let ws = filterWorkouts(store.activeHistory[iso]?.workouts ?? [])
            switch selectedActivityKpi {
            case 0: return Double(ws.reduce(0) { $0 + $1.durationMin }) / 60.0 // hours
            case 1: return ws.compactMap(\.distanceKm).reduce(0, +)
            case 2: return (store.activeHistory[iso]?.elevationM ?? 0) + ws.compactMap(\.elevationM).reduce(0, +)
            case 3: return Double(ws.reduce(0) { $0 + $1.kcal })
            case 6:
                let hs = ws.map(\.avgHrBpm).filter { $0 > 0 }
                return hs.isEmpty ? 0 : Double(hs.reduce(0, +)) / Double(hs.count)
            default: return Double(ws.reduce(0) { $0 + $1.durationMin }) / 60.0
            }
        }
        let dailyPrev: [Double] = win.prevIsos.map { iso in
            let ws = filterWorkouts(store.activeHistory[iso]?.workouts ?? [])
            switch selectedActivityKpi {
            case 0: return Double(ws.reduce(0) { $0 + $1.durationMin }) / 60.0
            case 1: return ws.compactMap(\.distanceKm).reduce(0, +)
            case 2: return (store.activeHistory[iso]?.elevationM ?? 0) + ws.compactMap(\.elevationM).reduce(0, +)
            case 3: return Double(ws.reduce(0) { $0 + $1.kcal })
            case 6:
                let hs = ws.map(\.avgHrBpm).filter { $0 > 0 }
                return hs.isEmpty ? 0 : Double(hs.reduce(0, +)) / Double(hs.count)
            default: return Double(ws.reduce(0) { $0 + $1.durationMin }) / 60.0
            }
        }

        let chartFormatter: (Double) -> String = { v in
            switch selectedActivityKpi {
            case 0: return String(format: "%.1fh", locale: Locale(identifier: "es_ES"), v)
            case 1: return String(format: "%.1f km", locale: Locale(identifier: "es_ES"), v)
            case 2: return "\(Int(v.rounded())) m"
            case 3: return "\(Int(v.rounded()))"
            case 6: return "\(Int(v.rounded()))"
            default: return String(format: "%.1fh", locale: Locale(identifier: "es_ES"), v)
            }
        }

        let durDelta = curDur - prevDur
        let distDelta = curDist - prevDist
        let elevDelta = curElev - prevElev
        let kcalDelta = curKcal - prevKcal

        let groupedHistory = groupWorkoutsByMonth(curWorkoutsDated)

        let aiInsight: MetricFloatingAiInsight = {
            if curWorkoutsDated.isEmpty {
                return MetricFloatingAiInsight(
                    shortPillText: "Sin actividades en este período",
                    expandedHeadline: "Sin actividades registradas",
                    shortExpandedMessage: "No constan entrenamientos en estos \(spanDays) días. Sincroniza tu Atajo de Apple Health para importar tus sesiones.",
                    expandedMessage: "No constan entrenamientos en estos \(spanDays) días. Sincroniza tu Atajo de Apple Health para importar tus sesiones.",
                    structureIndex: 0, variationSeed: 1
                )
            }
            let moreActive = durDelta >= 0
            let head = moreActive ? "Un periodo más activo" : "Menor volumen de actividad"
            let dAbs = abs(durDelta)
            let msg = "En tus actividades, el cambio más destacado fue \(moreActive ? "sumar" : "reducir") \(dAbs / 60) h \(dAbs % 60) min frente al periodo anterior. El total acumulado llegó a \(curDur / 60) h \(curDur % 60) min y \(curKcal) kcal en estos \(spanDays) días."
            return MetricFloatingAiInsight(
                shortPillText: head,
                expandedHeadline: head,
                shortExpandedMessage: msg,
                expandedMessage: msg,
                structureIndex: 0, variationSeed: 2
            )
        }()

        return ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Button(action: onBack) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .frame(width: 40, height: 40)
                                    .background(Circle().fill(BevelColors.glassChromeFill))
                                    .overlay(Circle().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.8))
                            }
                            Spacer()
                            Menu {
                                Button("Ordenar más recientes") { sortNewestFirst = true }
                                Button("Ordenar más antiguos") { sortNewestFirst = false }
                                Button(isBarMode ? "Ver línea acumulada" : "Ver barras diarias") { isBarMode.toggle() }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .frame(width: 40, height: 40)
                                    .background(Circle().fill(BevelColors.glassChromeFill))
                                    .overlay(Circle().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.8))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 10)

                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 3) {
                                Menu {
                                    ForEach(availableActivityNames, id: \.self) { name in
                                        Button(name == "Todas" ? "Todas las actividades" : name) {
                                            selectedActivityFilter = name
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(selectedActivityFilter == "Todas" ? "Todas las actividades" : selectedActivityFilter)
                                            .font(ImprovingFont.displayLarge(23))
                                            .foregroundColor(BevelColors.textPrimary)
                                            .lineLimit(1)
                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(BevelColors.textSecondary)
                                    }
                                }

                                Text(win.rangeTitle)
                                    .font(ImprovingFont.caption(13.5))
                                    .foregroundColor(BevelColors.textSecondary)
                                Text("Período actual vs. anterior")
                                    .font(ImprovingFont.caption(12))
                                    .foregroundColor(BevelColors.textMuted)
                            }
                            Spacer()

                            // Bar vs Cumulative Line Toggle (Exact Match to Screenshot 7!)
                            HStack(spacing: 2) {
                                Button { isBarMode = true } label: {
                                    Image(systemName: "chart.bar.fill")
                                        .font(.system(size: 13))
                                        .foregroundColor(isBarMode ? .white : BevelColors.textMuted)
                                        .frame(width: 40, height: 32)
                                        .background(Capsule().fill(isBarMode ? Color.white.opacity(0.14) : .clear))
                                }
                                Button { isBarMode = false } label: {
                                    Image(systemName: "chart.xyaxis.line")
                                        .font(.system(size: 13))
                                        .foregroundColor(!isBarMode ? .white : BevelColors.textMuted)
                                        .frame(width: 40, height: 32)
                                        .background(Capsule().fill(!isBarMode ? Color.white.opacity(0.14) : .clear))
                                }
                            }
                            .padding(3)
                            .background(Capsule().fill(Color.white.opacity(0.06)))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.7))
                        }
                        .padding(.horizontal, 16)

                        // Horizontally Scrollable Selectable 9 KPI Cards (Exact Match to Screenshots 7, 8, 9!)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                activityKpiCard(
                                    idx: 0, title: "Duración de la act.",
                                    value: curDur > 0 ? formatHMS(curDur) : "No hay datos",
                                    deltaText: curDur > 0 ? formatHMS(abs(durDelta)) : nil,
                                    isUp: durDelta >= 0
                                )
                                activityKpiCard(
                                    idx: 1, title: "Distancia",
                                    value: curDist > 0 ? String(format: "%.2f km", locale: Locale(identifier: "es_ES"), curDist) : "No hay datos",
                                    deltaText: curDist > 0 ? String(format: "%.2f km", locale: Locale(identifier: "es_ES"), abs(distDelta)) : nil,
                                    isUp: distDelta >= 0
                                )
                                activityKpiCard(
                                    idx: 2, title: "Desnivel",
                                    value: curElev > 0 ? "\(Int(curElev.rounded())) m" : "No hay datos",
                                    deltaText: curElev > 0 ? "\(Int(abs(elevDelta).rounded())) m" : nil,
                                    isUp: elevDelta >= 0
                                )
                                activityKpiCard(
                                    idx: 3, title: "Energía en actividad",
                                    value: curKcal > 0 ? "\(curKcal) kcal" : "No hay datos",
                                    deltaText: curKcal > 0 ? "\(abs(kcalDelta)) kcal" : nil,
                                    isUp: kcalDelta >= 0
                                )
                                activityKpiCard(
                                    idx: 4, title: "Ritmo",
                                    value: paceMinPerKm.map { p in
                                        let m = Int(p)
                                        let s = Int(((p - Double(m)) * 60.0).rounded())
                                        return String(format: "%d:%02d /km", m, min(s, 59))
                                    } ?? "No hay datos",
                                    deltaText: nil, isUp: true
                                )
                                activityKpiCard(
                                    idx: 5, title: "Velocidad",
                                    value: speedKmh.map { String(format: "%.1f km/h", locale: Locale(identifier: "es_ES"), $0) } ?? "No hay datos",
                                    deltaText: nil, isUp: true
                                )
                                activityKpiCard(
                                    idx: 6, title: "Frecuencia cardíaca",
                                    value: avgWorkoutHr.map { "\($0) ppm" } ?? "No hay datos",
                                    deltaText: nil, isUp: true
                                )
                                activityKpiCard(
                                    idx: 7, title: "Potencia",
                                    value: avgPower.map { "\(Int($0.rounded())) W" } ?? "No hay datos",
                                    deltaText: nil, isUp: true
                                )
                                activityKpiCard(
                                    idx: 8, title: "Cadencia",
                                    value: avgCadence.map { "\(Int($0.rounded())) rpm" } ?? "No hay datos",
                                    deltaText: nil, isUp: true
                                )
                            }
                            .padding(.horizontal, 16)
                        }

                        ActivityComparisonBarOrLineChart(
                            dailyCurrent: dailyCur,
                            dailyPrevious: dailyPrev,
                            dateLabels: win.shortLabels,
                            isBarMode: isBarMode,
                            accentStart: Color(hex: 0x3AC4E8),
                            accentEnd: BevelColors.cyanBright,
                            valueFormatter: chartFormatter
                        )
                        .padding(.horizontal, 14)

                        FitnessRangeControlBar(
                            selectedRange: $selectedRange,
                            canStepBackward: true,
                            canStepForward: windowPageOffset > 0,
                            onStepBackward: { windowPageOffset += 1 },
                            onStepForward: { windowPageOffset = max(0, windowPageOffset - 1) },
                            onRangeChanged: { windowPageOffset = 0 }
                        )
                        .padding(.horizontal, 16)

                        Text(isBarMode ? "Total diario en el período seleccionado." : "Total acumulado en el período seleccionado, por días.")
                            .font(ImprovingFont.caption(12))
                            .foregroundColor(BevelColors.textMuted)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.bottom, 14)
                    }
                    .background(BevelColors.sheetHeaderBg)

                    // Monthly Grouped Sortable Activity History (Screenshots 10-11!)
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Historial de actividad")
                                .font(ImprovingFont.sectionTitle(18))
                                .foregroundColor(BevelColors.textPrimary)
                            Spacer()
                            Button {
                                UISelectionFeedbackGenerator().selectionChanged()
                                sortNewestFirst.toggle()
                            } label: {
                                Image(systemName: "arrow.up.arrow.down")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(BevelColors.card))
                                    .overlay(Circle().strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
                            }
                        }

                        if groupedHistory.isEmpty {
                            BevelCard(cornerRadius: 18) {
                                Text("No hay entrenamientos registrados en este período. Sincroniza Apple Health con el Atajo o registra tu próxima sesión.")
                                    .font(ImprovingFont.body(13.5))
                                    .foregroundColor(BevelColors.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(16)
                            }
                        } else {
                            ForEach(groupedHistory, id: \.monthTitle) { group in
                                Text(group.monthTitle)
                                    .font(ImprovingFont.cardTitle(14.5))
                                    .foregroundColor(BevelColors.textSecondary)
                                    .padding(.top, 4)

                                ForEach(group.items) { w in
                                    FitnessActivityHistoryRow(workout: w)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                }
                .padding(.bottom, 165)
            }
            .background(BevelColors.canvas)

            FloatingMetricAiCoachOverlay(
                metricKey: "act_\(selectedActivityFilter)_\(selectedRange)_\(selectedActivityKpi)",
                metricTitle: "Actividades",
                insight: aiInsight,
                scrollCollapseSignal: 0,
                leadingEmoji: "🚴"
            )
        }
    }

    private func activityKpiCard(idx: Int, title: String, value: String, deltaText: String?, isUp: Bool) -> some View {
        let active = selectedActivityKpi == idx
        let isNoData = value == "No hay datos"
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            selectedActivityKpi = idx
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(ImprovingFont.caption(12))
                    .foregroundColor(BevelColors.textSecondary)
                    .lineLimit(1)
                Text(value)
                    .font(ImprovingFont.metricTile(isNoData ? 17 : 20))
                    .monospacedDigit()
                    .foregroundColor(isNoData ? BevelColors.textMuted : BevelColors.textPrimary)
                    .lineLimit(1)
                if let d = deltaText {
                    HStack(spacing: 4) {
                        Image(systemName: isUp ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(BevelColors.skyBlue)
                        Text(d)
                            .font(ImprovingFont.caption(12))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .foregroundColor(BevelColors.skyBlue)
                    }
                } else {
                    Text("—")
                        .font(ImprovingFont.caption(12))
                        .foregroundColor(BevelColors.textMuted)
                }
            }
            .frame(width: 146, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(BevelColors.card))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(active ? Color.white.opacity(0.42) : BevelColors.cardBorder, lineWidth: active ? 1.3 : 0.8)
            )
        }
    }

    // MARK: - 3B. VO₂ máx. Detail Sheet (Exact Match to Screenshots 13-15!)

    private var vo2MaxDetailView: some View {
        let win = windowDates
        let values: [Double?] = win.isos.map { store.activeHistory[$0]?.vo2MaxMlKgMin }
        let rec = store.latestVo2MaxRecord
        let eval = rec.map { WhoopPhysiologyEngine.standardizeVo2Max($0.value, profile: store.userProfile) }
        let trendRows = WhoopPhysiologyEngine.computeMultiPeriodTrendRows(
            history: store.activeHistory,
            anchorDate: store.selectedDate
        ) { $0.vo2MaxMlKgMin }

        let d90 = trendRows.last?.delta
        let aiInsight: MetricFloatingAiInsight = {
            guard let r = rec, let e = eval else {
                return MetricFloatingAiInsight(
                    shortPillText: "Sin lecturas de VO₂ máx.",
                    expandedHeadline: "VO₂ máx. pendiente",
                    shortExpandedMessage: "Realiza caminatas o carreras al aire libre con Apple Watch y sincroniza con el Atajo para registrar tu VO₂ máx.",
                    expandedMessage: "Realiza caminatas o carreras al aire libre con Apple Watch y sincroniza con el Atajo para registrar tu VO₂ máx.",
                    structureIndex: 0, variationSeed: 1
                )
            }
            let head = (d90 ?? 0) > 0.3 ? "VO₂ máx: mejora gradual" : "VO₂ máx: banda \(e.categoryTitle)"
            let deltaSentence = d90.map { String(format: "Varió %+.1f mL/kg·min en los últimos 90 días.", locale: Locale(identifier: "es_ES"), $0) } ?? ""
            let msg = "Tu VO₂ máx. está en \(String(format: "%.1f", locale: Locale(identifier: "es_ES"), r.value)) dentro de la banda \(e.categoryTitle) (\(e.cohortSubtitle)). \(deltaSentence)"
            return MetricFloatingAiInsight(shortPillText: head, expandedHeadline: head, shortExpandedMessage: msg, expandedMessage: msg, structureIndex: 0, variationSeed: 3)
        }()

        return ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 14) {
                        DetailSheetHeader(title: "VO₂ máx.", onBack: onBack)
                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rec.map { String(format: "%.1f", locale: Locale(identifier: "es_ES"), $0.value) } ?? "Sin datos")
                                    .font(ImprovingFont.displayLarge(rec != nil ? 36 : 26))
                                    .monospacedDigit()
                                    .foregroundColor(rec != nil ? BevelColors.textPrimary : BevelColors.textMuted)
                                Text(formatShortDate(store.selectedDateIso))
                                    .font(ImprovingFont.caption(13.5))
                                    .foregroundColor(BevelColors.textSecondary)
                            }
                            Spacer()
                            if let e = eval {
                                Text(e.categoryTitle)
                                    .font(ImprovingFont.sectionTitle(18))
                                    .foregroundColor(e.activeColor)
                            }
                        }
                        .padding(.horizontal, 16)

                        Vo2AmberAreaChart(
                            optionalPoints: values,
                            dates: win.shortLabels,
                            lineStartColor: BevelColors.amberStart,
                            lineEndColor: BevelColors.orangeEnd,
                            valueFormatter: { String(format: "%.1f", locale: Locale(identifier: "es_ES"), $0) }
                        )
                        .padding(.horizontal, 14)

                        FitnessRangeControlBar(
                            selectedRange: $selectedRange,
                            canStepBackward: true,
                            canStepForward: windowPageOffset > 0,
                            onStepBackward: { windowPageOffset += 1 },
                            onStepForward: { windowPageOffset = max(0, windowPageOffset - 1) },
                            onRangeChanged: { windowPageOffset = 0 }
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                    .background(BevelColors.sheetHeaderBg)

                    VStack(alignment: .leading, spacing: 18) {
                        if let e = eval, let r = rec {
                            FiveSegmentRangeBar(
                                labels: e.labels,
                                activeSegmentIndex: e.activeSegmentIndex,
                                activeColor: e.activeColor,
                                pointerFraction: e.pointerFraction,
                                rangeTitle: e.categoryTitle,
                                subtitle: e.cohortSubtitle,
                                footerDate: "Último dato el \(formatShortDate(r.dateIso))"
                            )
                        }

                        // Análisis de tendencias (3d / 7d / 14d / 30d / 90d — Exact Match to Screenshot 14!)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Análisis de tendencias")
                                .font(ImprovingFont.sectionTitle(18))
                                .foregroundColor(BevelColors.textPrimary)
                            if let r = rec {
                                Text("Último dato el \(formatShortDate(r.dateIso))")
                                    .font(ImprovingFont.caption(12.5))
                                    .foregroundColor(BevelColors.textSecondary)
                            }
                        }

                        BevelCard(cornerRadius: 20) {
                            VStack(spacing: 0) {
                                HStack {
                                    Text("Período").frame(width: 90, alignment: .leading)
                                    Text("Variación").frame(maxWidth: .infinity, alignment: .leading)
                                    Text("Tendencia").frame(width: 78, alignment: .trailing)
                                }
                                .font(ImprovingFont.caption(12))
                                .foregroundColor(BevelColors.textMuted)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)

                                ForEach(Array(trendRows.enumerated()), id: \.element.id) { idx, row in
                                    if idx > 0 { Divider().background(BevelColors.divider).padding(.horizontal, 14) }
                                    let isStrong = abs(row.delta ?? 0) >= 1.5
                                    let arrowIcon: String = {
                                        guard let d = row.delta else { return "minus.circle.fill" }
                                        if d >= 1.0 { return "arrow.up.circle.fill" }
                                        if d <= -1.0 { return "arrow.down.circle.fill" }
                                        return "arrow.right.circle.fill"
                                    }()
                                    let badgeColor: Color = {
                                        guard let d = row.delta else { return BevelColors.textMuted }
                                        if d >= 1.0 { return BevelColors.skyBlue }
                                        if d <= -1.0 { return BevelColors.coralHigh }
                                        return BevelColors.textMuted
                                    }()
                                    HStack {
                                        Text(row.label)
                                            .font(ImprovingFont.body(14.5))
                                            .foregroundColor(BevelColors.textSecondary)
                                            .frame(width: 90, alignment: .leading)

                                        HStack(spacing: 6) {
                                            Image(systemName: arrowIcon)
                                                .font(.system(size: 14))
                                                .foregroundColor(badgeColor)
                                            Text(row.delta.map { String(format: "%+.1f", locale: Locale(identifier: "es_ES"), $0) } ?? "—")
                                                .font(ImprovingFont.cardTitle(14.5))
                                                .monospacedDigit()
                                                .foregroundColor(BevelColors.textPrimary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                        if row.sparklinePoints.count >= 2 {
                                            TrendSparklineWithBand(
                                                points: row.sparklinePoints,
                                                lineColor: isStrong ? BevelColors.skyBlue : Color(hex: 0x8E939E),
                                                fillUnder: true,
                                                showBand: false,
                                                showGlowDot: false
                                            )
                                            .frame(width: 78, height: 24)
                                        } else {
                                            Text("—").font(ImprovingFont.caption(12)).foregroundColor(BevelColors.textMuted).frame(width: 78, alignment: .trailing)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 13)
                                }
                            }
                        }

                        Text("Basado en las medias móviles de 7 días durante el período seleccionado.")
                            .font(ImprovingFont.caption(12))
                            .foregroundColor(BevelColors.textMuted)

                        // Educational card (Screenshot 15!)
                        Text("¿Qué es el VO₂ máx.?")
                            .font(ImprovingFont.sectionTitle(18))
                            .foregroundColor(BevelColors.textPrimary)

                        BevelCard(cornerRadius: 20) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("El VO₂ máx. mide el volumen máximo de oxígeno que tu cuerpo puede usar durante un ejercicio intenso. Es un indicador clave de la forma física cardiovascular y la resistencia.")
                                Text("Mejorar tu VO₂ máx. puede potenciar tu rendimiento deportivo, aumentar tus niveles de energía y favorecer la salud cardíaca. Unos niveles más altos de VO₂ máx. están relacionados con una mejor forma física general y una mayor longevidad.")
                            }
                            .font(ImprovingFont.body(14))
                            .foregroundColor(BevelColors.textSecondary)
                            .lineSpacing(3.5)
                            .padding(16)
                        }

                        FitnessResourceCarousel(items: [
                            FitnessResourceItem(
                                id: "res_vo2",
                                badgeIcon: "lungs.fill",
                                heroTitle: "VO₂ Max",
                                heroSubtitle: "The Basics",
                                cardTitle: "The Basics: VO₂ Max",
                                cardDescription: "Entiende cómo refleja tu VO₂ máx. tu forma física y longevidad.",
                                gradientHexA: 0x3D495C,
                                gradientHexB: 0x57483D,
                                fullGuideBody: "Combinar un 80% de sesiones aeróbicas suaves en Zona 2 con un 20% de intervalos de alta intensidad en Zonas 4–5 es la estrategia con mayor respaldo científico para elevar tu VO₂ máx. de forma constante."
                            )
                        ])
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                }
                .padding(.bottom, 165)
            }
            .background(BevelColors.canvas)

            FloatingMetricAiCoachOverlay(
                metricKey: "vo2_\(selectedRange)_\(windowPageOffset)",
                metricTitle: "VO₂ máx.",
                insight: aiInsight,
                scrollCollapseSignal: 0,
                leadingEmoji: "📈"
            )
        }
    }

    // MARK: - 3C. Recuperación de FC (HRR) Detail Sheet (Exact Match to Screenshots 16-18!)

    private var hrRecoveryDetailView: some View {
        let win = windowDates
        let values: [Double?] = win.isos.map { iso in
            guard let day = store.activeHistory[iso] else { return nil }
            if selectedActivityFilter == "Todas" {
                return day.hrRecoveryBpm
            }
            let matching = day.workouts.filter { $0.title == selectedActivityFilter }.compactMap(\.hrRecovery1MinBpm)
            if !matching.isEmpty {
                return matching.reduce(0, +) / Double(matching.count)
            }
            return day.workouts.contains(where: { $0.title == selectedActivityFilter }) ? day.hrRecoveryBpm : nil
        }
        let realVals = values.compactMap { $0 }
        let avgHrr = realVals.isEmpty ? nil : Int((realVals.reduce(0, +) / Double(realVals.count)).rounded())
        let rec = store.latestHrRecoveryRecord
        let eval = rec.map { WhoopPhysiologyEngine.standardizeHrRecovery($0.value, profile: store.userProfile) }

        let aiInsight: MetricFloatingAiInsight = {
            guard let r = rec, let e = eval else {
                return MetricFloatingAiInsight(
                    shortPillText: "Sin lecturas de HRR",
                    expandedHeadline: "Recuperación de FC",
                    shortExpandedMessage: "Tras tus sesiones con Apple Watch, Improving lee o calcula automáticamente cuántos ppm baja tu pulso en el primer minuto.",
                    expandedMessage: "Tras tus sesiones con Apple Watch, Improving lee o calcula automáticamente cuántos ppm baja tu pulso en el primer minuto.",
                    structureIndex: 0, variationSeed: 1
                )
            }
            let pill = (avgHrr ?? Int(r.value)) >= 30 ? "Buen promedio del periodo" : "HRR en rango \(e.categoryTitle)"
            let msg = "Tu última recuperación de frecuencia cardíaca fue de \(Int(r.value.rounded())) ppm (\(e.categoryTitle))." + (avgHrr.map { " El promedio del periodo seleccionado se sitúa en \($0) ppm." } ?? "")
            return MetricFloatingAiInsight(shortPillText: pill, expandedHeadline: pill, shortExpandedMessage: msg, expandedMessage: msg, structureIndex: 0, variationSeed: 4)
        }()

        return ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 14) {
                        DetailSheetHeader(title: "Recuperación de frecuencia cardíaca", onBack: onBack)
                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rec.map { "\(Int($0.value.rounded())) ppm" } ?? "Sin datos")
                                    .font(ImprovingFont.displayLarge(rec != nil ? 36 : 26))
                                    .monospacedDigit()
                                    .foregroundColor(rec != nil ? BevelColors.textPrimary : BevelColors.textMuted)
                                Text(formatShortDate(store.selectedDateIso))
                                    .font(ImprovingFont.caption(13.5))
                                    .foregroundColor(BevelColors.textSecondary)
                            }
                            Spacer()
                            if let e = eval {
                                Text(e.categoryTitle)
                                    .font(ImprovingFont.sectionTitle(18))
                                    .foregroundColor(e.activeColor)
                            }
                        }
                        .padding(.horizontal, 16)

                        activityFilterChipsBar

                        Vo2AmberAreaChart(
                            optionalPoints: values,
                            dates: win.shortLabels,
                            lineStartColor: BevelColors.strengthPink,
                            lineEndColor: BevelColors.amberStart,
                            averageBadgeText: avgHrr.map { "Prom. \($0) ppm" },
                            valueFormatter: { "\(Int($0.rounded())) ppm" }
                        )
                        .padding(.horizontal, 14)

                        FitnessRangeControlBar(
                            selectedRange: $selectedRange,
                            canStepBackward: true,
                            canStepForward: windowPageOffset > 0,
                            onStepBackward: { windowPageOffset += 1 },
                            onStepForward: { windowPageOffset = max(0, windowPageOffset - 1) },
                            onRangeChanged: { windowPageOffset = 0 }
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                    .background(BevelColors.sheetHeaderBg)

                    VStack(alignment: .leading, spacing: 18) {
                        if let e = eval, let r = rec {
                            FiveSegmentRangeBar(
                                labels: e.labels,
                                activeSegmentIndex: e.activeSegmentIndex,
                                activeColor: e.activeColor,
                                pointerFraction: e.pointerFraction,
                                rangeTitle: e.categoryTitle,
                                subtitle: e.cohortSubtitle,
                                footerDate: "Último dato el \(formatShortDate(r.dateIso))"
                            )
                        }

                        Text("¿Qué es la recuperación de la frecuencia cardíaca?")
                            .font(ImprovingFont.sectionTitle(18))
                            .foregroundColor(BevelColors.textPrimary)

                        BevelCard(cornerRadius: 20) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("La recuperación de la frecuencia cardíaca (HRR) mide la rapidez con la que tu frecuencia cardíaca vuelve a los valores normales después de hacer ejercicio, lo que indica tu estado cardiovascular y tu capacidad de recuperación.")
                                Text("Una HRR más rápida es señal de buena salud cardíaca, mientras que una recuperación más lenta puede indicar fatiga o la necesidad de mejorar tu capacidad aeróbica. Puedes mejorar la HRR con entrenamiento aeróbico, hidratación, sueño y control del estrés.")
                            }
                            .font(ImprovingFont.body(14))
                            .foregroundColor(BevelColors.textSecondary)
                            .lineSpacing(3.5)
                            .padding(16)
                        }

                        FitnessResourceCarousel(items: [
                            FitnessResourceItem(
                                id: "res_hrr",
                                badgeIcon: "heart.circle.fill",
                                heroTitle: "Heart Rate Recovery",
                                heroSubtitle: "The Basics",
                                cardTitle: "The Basics: Heart Rate Recovery",
                                cardDescription: "Entiende cómo se recupera tu corazón tras esfuerzos exigentes.",
                                gradientHexA: 0x3D4C3E,
                                gradientHexB: 0x5A483A,
                                fullGuideBody: "La caída de pulsaciones en el primer minuto tras detener un entrenamiento refleja la reactivación parasimpática del nervio vago. Valores por encima de 30–35 ppm indican una excelente respuesta autónoma."
                            )
                        ])
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                }
                .padding(.bottom, 165)
            }
            .background(BevelColors.canvas)

            FloatingMetricAiCoachOverlay(
                metricKey: "hrr_\(selectedActivityFilter)_\(selectedRange)",
                metricTitle: "HRR",
                insight: aiInsight,
                scrollCollapseSignal: 0,
                leadingEmoji: "📈"
            )
        }
    }

    // MARK: - 3D. Foco cardiovascular Detail Sheet (Exact Match to Screenshots 19-21!)

    private var cardioFocusDetailView: some View {
        let win = windowDates
        let dailyTriples: [(low: Int, high: Int, anaero: Int)] = win.isos.map { iso in
            guard let day = store.activeHistory[iso] else { return (0, 0, 0) }
            if selectedActivityFilter != "Todas" {
                let ws = day.workouts.filter { $0.title == selectedActivityFilter }
                let z6 = ws.reduce([0, 0, 0, 0, 0, 0]) { acc, w in
                    let arr = w.hrZoneMinutes6 ?? [0, 0, 0, 0, 0, 0]
                    return (0..<6).map { acc[$0] + ($0 < arr.count ? arr[$0] : 0) }
                }
                return (z6[0] + z6[1] + z6[2], z6[3] + z6[4], z6[5])
            }
            let z0 = day.hrZone0Minutes ?? 0
            let z = day.hrZoneMinutes
            let low = z0 + (z.count > 0 ? z[0] : 0) + (z.count > 1 ? z[1] : 0)
            let high = (z.count > 2 ? z[2] : 0) + (z.count > 3 ? z[3] : 0)
            let an = z.count > 4 ? z[4] : 0
            return (low, high, an)
        }
        let totLow = dailyTriples.reduce(0) { $0 + $1.low }
        let totHigh = dailyTriples.reduce(0) { $0 + $1.high }
        let totAn = dailyTriples.reduce(0) { $0 + $1.anaero }
        let grandTotal = totLow + totHigh + totAn
        let pLow = grandTotal > 0 ? Int((Double(totLow) / Double(grandTotal) * 100.0).rounded()) : 0
        let pHigh = grandTotal > 0 ? Int((Double(totHigh) / Double(grandTotal) * 100.0).rounded()) : 0
        let pAn = grandTotal > 0 ? max(0, 100 - pLow - pHigh) : 0

        let domTitle = grandTotal == 0 ? "Sin datos" : (pLow >= pHigh && pLow >= pAn ? "Aeróbico bajo" : (pHigh >= pAn ? "Aeróbico alto" : "Anaeróbico"))
        let domPct = max(pLow, max(pHigh, pAn))

        let aiInsight = MetricFloatingAiInsight(
            shortPillText: grandTotal == 0 ? "Sin zonas registradas" : (pLow >= 70 ? "Predomina el trabajo suave" : "Buen estímulo intenso"),
            expandedHeadline: grandTotal == 0 ? "Foco cardiovascular" : (pLow >= 70 ? "Predomina el trabajo suave" : "Foco equilibrado"),
            shortExpandedMessage: grandTotal == 0
                ? "Todavía no hay minutos en zonas cardíacas en este período."
                : "Un \(pLow)% de tu volumen fue aeróbico bajo (\(totLow) min), \(pHigh)% aeróbico alto (\(totHigh) min) y \(pAn)% anaeróbico (\(totAn) min).",
            expandedMessage: grandTotal == 0
                ? "Todavía no hay minutos en zonas cardíacas en este período."
                : "Un \(pLow)% de tu volumen fue aeróbico bajo (\(totLow) min), \(pHigh)% aeróbico alto (\(totHigh) min) y \(pAn)% anaeróbico (\(totAn) min). Añadir 1 bloque semanal en Zona 4 ayuda a impulsar tu VO₂ máx.",
            structureIndex: 0, variationSeed: 5
        )

        return ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 14) {
                        DetailSheetHeader(title: "Foco cardiovascular", onBack: onBack)
                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(domTitle)
                                    .font(ImprovingFont.displayLarge(26))
                                    .foregroundColor(grandTotal > 0 ? BevelColors.textPrimary : BevelColors.textMuted)
                                Text(formatShortDate(store.selectedDateIso))
                                    .font(ImprovingFont.caption(13.5))
                                    .foregroundColor(BevelColors.textSecondary)
                            }
                            Spacer()
                            if grandTotal > 0 {
                                Text("\(domPct) %")
                                    .font(ImprovingFont.sectionTitle(18))
                                    .monospacedDigit()
                                    .foregroundColor(Color(hex: 0x62E2E8))
                            }
                        }
                        .padding(.horizontal, 16)

                        activityFilterChipsBar

                        CardioFocusStackedBarChart(dailyTriples: dailyTriples, dateLabels: win.shortLabels)
                            .padding(.horizontal, 14)

                        FitnessRangeControlBar(
                            selectedRange: $selectedRange,
                            canStepBackward: true,
                            canStepForward: windowPageOffset > 0,
                            onStepBackward: { windowPageOffset += 1 },
                            onStepForward: { windowPageOffset = max(0, windowPageOffset - 1) },
                            onRangeChanged: { windowPageOffset = 0 }
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                    .background(BevelColors.sheetHeaderBg)

                    VStack(alignment: .leading, spacing: 18) {
                        Text("Desglose del foco cardiovascular")
                            .font(ImprovingFont.sectionTitle(18))
                            .foregroundColor(BevelColors.textPrimary)

                        BevelCard(cornerRadius: 20) {
                            VStack(spacing: 0) {
                                HStack {
                                    Text("Estado").frame(width: 96, alignment: .leading)
                                    Text("Valor").frame(width: 44, alignment: .leading)
                                    Spacer()
                                    Text("%").frame(width: 44, alignment: .trailing)
                                }
                                .font(ImprovingFont.caption(12))
                                .foregroundColor(BevelColors.textMuted)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)

                                focusRow("Aeró. bajo", val: "\(totLow)", pct: pLow, color: Color(hex: 0x62E2E8))
                                Divider().background(BevelColors.divider).padding(.horizontal, 14)
                                focusRow("Aeró. alto", val: "\(totHigh)", pct: pHigh, color: Color(hex: 0x5682FF))
                                Divider().background(BevelColors.divider).padding(.horizontal, 14)
                                focusRow("Anaeróbico", val: "\(totAn)", pct: pAn, color: Color(hex: 0xA855F7))
                            }
                        }

                        Text("¿Qué es el foco cardiovascular?")
                            .font(ImprovingFont.sectionTitle(18))
                            .foregroundColor(BevelColors.textPrimary)

                        BevelCard(cornerRadius: 20) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("El foco cardiovascular muestra la división en zonas aeróbicas durante tus ejercicios. Improving utiliza tu VO₂ máx. e intensidad de entrenamiento para estimar tus umbrales que se acumulan con el tiempo:")
                                    .font(ImprovingFont.body(14))
                                    .foregroundColor(BevelColors.textSecondary)

                                zoneExplainBullet(color: Color(hex: 0x62E2E8), title: "Aeróbico bajo:", body: "esfuerzos de baja intensidad pero prolongados que se suelen realizar a un ritmo de conversación.")
                                zoneExplainBullet(color: Color(hex: 0x5682FF), title: "Aeróbico alto:", body: "esfuerzos con una intensidad de moderadamente alta a alta, donde tu frecuencia cardíaca se mantiene muy elevada durante un periodo prolongado.")
                                zoneExplainBullet(color: Color(hex: 0xA855F7), title: "Anaeróbico:", body: "esfuerzos de corta duración y alta intensidad que elevan rápidamente tu frecuencia cardíaca, como entrenamiento por intervalos o HIIT.")
                            }
                            .padding(16)
                        }

                        FitnessResourceCarousel(items: [
                            FitnessResourceItem(
                                id: "res_cf",
                                badgeIcon: "square.stack.3d.up.fill",
                                heroTitle: "Cardio Focus",
                                heroSubtitle: "The Basics",
                                cardTitle: "The Basics: Cardio Focus",
                                cardDescription: "Optimiza tu intensidad de entrenamiento con un esfuerzo aeróbico equilibrado.",
                                gradientHexA: 0x4C5968,
                                gradientHexB: 0x665850,
                                fullGuideBody: "La regla 80/20 en entrenamiento de resistencia consiste en acumular alrededor de un 80% del tiempo en aeróbico bajo para construir mitocondrias y capilares, reservando el 20% para bloques intensos."
                            ),
                            FitnessResourceItem(
                                id: "res_hrz_cf",
                                badgeIcon: "waveform.path.ecg",
                                heroTitle: "Heart Rate Zones",
                                heroSubtitle: "Z0 – Z5",
                                cardTitle: "Heart Rate Zones",
                                cardDescription: "Entiende cada zona cardíaca y cuándo entrenar en cada umbral.",
                                gradientHexA: 0x5C3E2E,
                                gradientHexB: 0x262832,
                                fullGuideBody: "Tus 6 zonas se calculan automáticamente con la fórmula de Tanaka y Karvonen a partir de tu edad y tu FC en reposo real."
                            )
                        ])
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                }
                .padding(.bottom, 165)
            }
            .background(BevelColors.canvas)

            FloatingMetricAiCoachOverlay(
                metricKey: "cf_\(selectedActivityFilter)_\(selectedRange)",
                metricTitle: "Foco cardio",
                insight: aiInsight,
                scrollCollapseSignal: 0,
                leadingEmoji: "🚴"
            )
        }
    }

    // MARK: - 3E. Zonas de frecuencia cardíaca Detail Sheet (Exact Match to Screenshots 22-24!)

    private var hrZonesDetailView: some View {
        let win = windowDates
        let minutes6: [Int] = {
            var sums = [0, 0, 0, 0, 0, 0]
            for iso in win.isos {
                guard let day = store.activeHistory[iso] else { continue }
                if selectedActivityFilter != "Todas" {
                    for w in day.workouts where w.title == selectedActivityFilter {
                        if let z6 = w.hrZoneMinutes6 {
                            for i in 0..<min(6, z6.count) { sums[i] += z6[i] }
                        }
                    }
                } else {
                    sums[0] += day.hrZone0Minutes ?? 0
                    for i in 0..<min(5, day.hrZoneMinutes.count) {
                        sums[i + 1] += day.hrZoneMinutes[i]
                    }
                }
            }
            return sums
        }()
        let totalM = minutes6.reduce(0, +)
        let dominantIdx = minutes6.enumerated().max(by: { $0.element < $1.element })?.offset ?? 1
        let activeIdx = (selectedZoneIdx >= 0 && selectedZoneIdx < 6 && minutes6[selectedZoneIdx] > 0) ? selectedZoneIdx : dominantIdx
        let bpmRanges = WhoopPhysiologyEngine.hrZoneRangesBpm(profile: store.userProfile, restingHrBpm: store.restingHrBpm > 30 ? store.restingHrBpm : nil)
        let activeRange = bpmRanges[min(activeIdx, bpmRanges.count - 1)]
        let activeMins = minutes6[activeIdx]
        let activeDurText = activeMins >= 60 ? "\(activeMins / 60) h \(activeMins % 60) min" : "\(activeMins) min"

        let aiInsight = MetricFloatingAiInsight(
            shortPillText: totalM == 0 ? "Sin zonas registradas" : (dominantIdx <= 2 ? "Mucho movimiento suave" : "Buena carga cardiovascular"),
            expandedHeadline: "Zonas de frecuencia cardíaca",
            shortExpandedMessage: totalM == 0
                ? "Todavía no se acumularon minutos por zonas en este período."
                : "Tu zona predominante es Zona \(dominantIdx) con \(minutes6[dominantIdx]) min (\(bpmRanges[dominantIdx].low)–\(bpmRanges[dominantIdx].high) ppm).",
            expandedMessage: totalM == 0
                ? "Todavía no se acumularon minutos por zonas en este período."
                : "Tu zona predominante es Zona \(dominantIdx) con \(minutes6[dominantIdx]) min (\(bpmRanges[dominantIdx].low)–\(bpmRanges[dominantIdx].high) ppm). Total acumulado: \(totalM / 60) h \(totalM % 60) min.",
            structureIndex: 0, variationSeed: 6
        )

        return ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 14) {
                        DetailSheetHeader(title: "Zonas de frecuencia cardíaca", onBack: onBack)
                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(totalM > 0 ? "Zona \(activeIdx)" : "Sin datos")
                                    .font(ImprovingFont.displayLarge(28))
                                    .foregroundColor(totalM > 0 ? BevelColors.textPrimary : BevelColors.textMuted)
                                Text(formatShortDate(store.selectedDateIso))
                                    .font(ImprovingFont.caption(13.5))
                                    .foregroundColor(BevelColors.textSecondary)
                            }
                            Spacer()
                            if totalM > 0 {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(activeDurText)
                                        .font(ImprovingFont.sectionTitle(17))
                                        .monospacedDigit()
                                        .foregroundColor(HrZonesSixBarChart.zoneColors[activeIdx])
                                    Text("\(activeRange.low)–\(activeRange.high) ppm")
                                        .font(ImprovingFont.caption(13))
                                        .monospacedDigit()
                                        .foregroundColor(BevelColors.textSecondary)
                                }
                            }
                        }
                        .padding(.horizontal, 16)

                        activityFilterChipsBar

                        HrZonesSixBarChart(minutes6: minutes6, selectedZone: $selectedZoneIdx)
                            .padding(.horizontal, 14)

                        FitnessRangeControlBar(
                            selectedRange: $selectedRange,
                            canStepBackward: true,
                            canStepForward: windowPageOffset > 0,
                            onStepBackward: { windowPageOffset += 1 },
                            onStepForward: { windowPageOffset = max(0, windowPageOffset - 1) },
                            onRangeChanged: { windowPageOffset = 0 }
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                    .background(BevelColors.sheetHeaderBg)

                    VStack(alignment: .leading, spacing: 18) {
                        Text("¿Qué son las zonas de frecuencia cardíaca?")
                            .font(ImprovingFont.sectionTitle(18))
                            .foregroundColor(BevelColors.textPrimary)

                        BevelCard(cornerRadius: 20) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Las zonas de frecuencia cardíaca son rangos que representan diferentes niveles de intensidad de ejercicio. Cada zona tiene una finalidad distinta, desde el descanso y la recuperación hasta el esfuerzo máximo.")
                                    .font(ImprovingFont.body(14))
                                    .foregroundColor(BevelColors.textSecondary)

                                zoneExplainBullet(color: HrZonesSixBarChart.zoneColors[0], title: "Zona 0 (\(bpmRanges[0].low)–\(bpmRanges[0].high) ppm):", body: "el histórico de tu frecuencia cardíaca, que representa el nivel más bajo de intensidad.")
                                zoneExplainBullet(color: HrZonesSixBarChart.zoneColors[1], title: "Zona 1 (\(bpmRanges[1].low)–\(bpmRanges[1].high) ppm):", body: "recuperación activa para el calentamiento y el enfriamiento. El esfuerzo se nota ligero y cómodo.")
                                zoneExplainBullet(color: HrZonesSixBarChart.zoneColors[2], title: "Zona 2 (\(bpmRanges[2].low)–\(bpmRanges[2].high) ppm):", body: "esfuerzo sostenido para entrenamientos más largos que desarrolla la resistencia y usa una mayor proporción de grasa como fuente de energía.")
                                zoneExplainBullet(color: HrZonesSixBarChart.zoneColors[3], title: "Zona 3 (\(bpmRanges[3].low)–\(bpmRanges[3].high) ppm):", body: "esfuerzo moderado que mejora la capacidad cardiovascular. La respiración es más profunda, pero controlada.")
                                zoneExplainBullet(color: HrZonesSixBarChart.zoneColors[4], title: "Zona 4 (\(bpmRanges[4].low)–\(bpmRanges[4].high) ppm):", body: "esfuerzo de alta intensidad para sprints e intervalos. La respiración es agitada y el esfuerzo solo se puede mantener durante poco tiempo.")
                                zoneExplainBullet(color: HrZonesSixBarChart.zoneColors[5], title: "Zona 5 (\(bpmRanges[5].low)–\(bpmRanges[5].high) ppm):", body: "esfuerzo máximo para ráfagas cortas e intensas. Este esfuerzo solo se puede mantener durante muy poco tiempo.")
                            }
                            .padding(16)
                        }

                        FitnessResourceCarousel(items: [
                            FitnessResourceItem(
                                id: "res_hrz",
                                badgeIcon: "heart.text.square.fill",
                                heroTitle: "Heart Rate Zones",
                                heroSubtitle: "Z0 – Z5",
                                cardTitle: "Heart Rate Zones",
                                cardDescription: "Aprende a utilizar tus zonas de pulso para planificar cada sesión.",
                                gradientHexA: 0x5B3F30,
                                gradientHexB: 0x262832,
                                fullGuideBody: "Tus zonas se calibran automáticamente con tu FC máxima de Tanaka (208 − 0,7 × edad) y tu FC en reposo medida por el Apple Watch."
                            )
                        ])
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                }
                .padding(.bottom, 165)
            }
            .background(BevelColors.canvas)

            FloatingMetricAiCoachOverlay(
                metricKey: "hrz_\(selectedActivityFilter)_\(selectedRange)",
                metricTitle: "Zonas de FC",
                insight: aiInsight,
                scrollCollapseSignal: 0,
                leadingEmoji: "🚴"
            )
        }
    }

    // MARK: - 3F. Todos los músculos (Fuerza Overview — Exact Match to Screenshots 25-28!)

    private var strengthOverviewView: some View {
        let win = windowDates
        let setsCurByDay = Dictionary(grouping: store.strengthLogs.filter { s in
            guard s.completed else { return false }
            if selectedMuscleDropdown == "Todos los músculos" { return true }
            return s.primaryMuscles.contains(where: { $0.rawValue == selectedMuscleDropdown })
                || s.secondaryMuscles.contains(where: { $0.rawValue == selectedMuscleDropdown })
        }, by: \.dateIso)

        let dailySetsCur: [Double] = win.isos.map { iso in
            let logged = setsCurByDay[iso]?.count ?? 0
            let wkSets = (store.activeHistory[iso]?.workouts ?? []).compactMap(\.totalSets).reduce(0, +)
            return Double(max(logged, wkSets))
        }
        let dailySetsPrev: [Double] = win.prevIsos.map { iso in
            let logged = setsCurByDay[iso]?.count ?? 0
            let wkSets = (store.activeHistory[iso]?.workouts ?? []).compactMap(\.totalSets).reduce(0, +)
            return Double(max(logged, wkSets))
        }
        let dailyVolCur: [Double] = win.isos.map { iso in
            let logged = (setsCurByDay[iso] ?? []).reduce(0.0) { $0 + Double($1.reps) * $1.weightKg }
            let wkVol = (store.activeHistory[iso]?.workouts ?? []).compactMap(\.totalVolumeKg).reduce(0, +)
            return max(logged, wkVol)
        }
        let dailyVolPrev: [Double] = win.prevIsos.map { iso in
            let logged = (setsCurByDay[iso] ?? []).reduce(0.0) { $0 + Double($1.reps) * $1.weightKg }
            let wkVol = (store.activeHistory[iso]?.workouts ?? []).compactMap(\.totalVolumeKg).reduce(0, +)
            return max(logged, wkVol)
        }

        let totSetsCur = Int(dailySetsCur.reduce(0, +).rounded())
        let totSetsPrev = Int(dailySetsPrev.reduce(0, +).rounded())
        let totVolCur = Int(dailyVolCur.reduce(0, +).rounded())
        let totVolPrev = Int(dailyVolPrev.reduce(0, +).rounded())
        let muscAnalysis = store.trainingLoadAnalysis(tab: .muscular, spanDays: spanDays, windowPageOffset: windowPageOffset)

        let curWorkoutsDated: [(iso: String, workout: EffortEventItem)] = win.isos.flatMap { iso in
            (store.activeHistory[iso]?.workouts ?? []).map { (iso, $0) }
        }
        let groupedHistory = groupWorkoutsByMonth(curWorkoutsDated)

        let chartCur = selectedStrengthKpi == 1 ? dailyVolCur : (selectedStrengthKpi == 2 ? muscAnalysis.points.map(\.load) : dailySetsCur)
        let chartPrev = selectedStrengthKpi == 1 ? dailyVolPrev : (selectedStrengthKpi == 2 ? Array(repeating: 0.0, count: chartCur.count) : dailySetsPrev)
        let fmt: (Double) -> String = { v in
            if selectedStrengthKpi == 1 {
                return v >= 1000 ? String(format: "%.2fk", locale: Locale(identifier: "es_ES"), v / 1000.0) : "\(Int(v.rounded()))"
            }
            return "\(Int(v.rounded()))"
        }

        let aiInsight = MetricFloatingAiInsight(
            shortPillText: totSetsCur > 0 ? "Fuerza retomada" : "Sin series registradas",
            expandedHeadline: totSetsCur > 0 ? "Fuerza retomada" : "Registra tu fuerza",
            shortExpandedMessage: totSetsCur > 0
                ? "Has completado \(totSetsCur) series y \(totVolCur) kg acumulados en estos \(spanDays) días (carga muscular \(muscAnalysis.currentLoad))."
                : "Registra tus series en Fitness o inicia una rutina anclada para ver aquí el volumen total y la frescura por músculo.",
            expandedMessage: totSetsCur > 0
                ? "Has completado \(totSetsCur) series y \(totVolCur) kg acumulados en estos \(spanDays) días (carga muscular \(muscAnalysis.currentLoad), estado \(muscAnalysis.currentState.rawValue))."
                : "Registra tus series en Fitness o inicia una rutina anclada para ver aquí el volumen total y la frescura por músculo.",
            structureIndex: 0, variationSeed: 7
        )

        return ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Button(action: onBack) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .frame(width: 40, height: 40)
                                    .background(Circle().fill(BevelColors.glassChromeFill))
                                    .overlay(Circle().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.8))
                            }
                            Spacer()
                            Button {
                                currentRoute = .muscleGroups
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "figure.strengthtraining.traditional").font(.system(size: 12))
                                    Text("Mapa muscular").font(ImprovingFont.caption(12)).fontWeight(.semibold)
                                }
                                .foregroundColor(BevelColors.textPrimary)
                                .padding(.horizontal, 12)
                                .frame(height: 36)
                                .background(Capsule().fill(BevelColors.glassChromeFill))
                                .overlay(Capsule().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.8))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 10)

                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 3) {
                                Menu {
                                    Button("Todos los músculos") { selectedMuscleDropdown = "Todos los músculos" }
                                    ForEach(MuscleGroupKind.allCases) { m in
                                        Button(m.rawValue) { selectedMuscleDropdown = m.rawValue }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(selectedMuscleDropdown)
                                            .font(ImprovingFont.displayLarge(23))
                                            .foregroundColor(BevelColors.textPrimary)
                                            .lineLimit(1)
                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(BevelColors.textSecondary)
                                    }
                                }
                                Text(win.rangeTitle)
                                    .font(ImprovingFont.caption(13.5))
                                    .foregroundColor(BevelColors.textSecondary)
                                Text("Período actual vs. anterior")
                                    .font(ImprovingFont.caption(12))
                                    .foregroundColor(BevelColors.textMuted)
                            }
                            Spacer()
                            HStack(spacing: 2) {
                                Button { isBarMode = true } label: {
                                    Image(systemName: "chart.bar.fill")
                                        .font(.system(size: 13))
                                        .foregroundColor(isBarMode ? .white : BevelColors.textMuted)
                                        .frame(width: 40, height: 32)
                                        .background(Capsule().fill(isBarMode ? Color.white.opacity(0.14) : .clear))
                                }
                                Button { isBarMode = false } label: {
                                    Image(systemName: "chart.xyaxis.line")
                                        .font(.system(size: 13))
                                        .foregroundColor(!isBarMode ? .white : BevelColors.textMuted)
                                        .frame(width: 40, height: 32)
                                        .background(Capsule().fill(!isBarMode ? Color.white.opacity(0.14) : .clear))
                                }
                            }
                            .padding(3)
                            .background(Capsule().fill(Color.white.opacity(0.06)))
                        }
                        .padding(.horizontal, 16)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                strengthKpiCard(idx: 0, title: "Total series", value: "\(totSetsCur)", sub: "\(abs(totSetsCur - totSetsPrev))", isDelta: true, isUp: totSetsCur >= totSetsPrev)
                                strengthKpiCard(idx: 1, title: "Volumen total", value: "\(totVolCur) kg", sub: "\(abs(totVolCur - totVolPrev)) kg", isDelta: true, isUp: totVolCur >= totVolPrev)
                                strengthKpiCard(idx: 2, title: "Carga", value: "\(muscAnalysis.currentLoad)", sub: muscAnalysis.currentState.rawValue, isDelta: false, isUp: true)
                            }
                            .padding(.horizontal, 16)
                        }

                        ActivityComparisonBarOrLineChart(
                            dailyCurrent: chartCur,
                            dailyPrevious: chartPrev,
                            dateLabels: win.shortLabels,
                            isBarMode: isBarMode,
                            accentStart: Color(hex: 0xEE7A5A),
                            accentEnd: BevelColors.strengthPink,
                            valueFormatter: fmt
                        )
                        .padding(.horizontal, 14)

                        FitnessRangeControlBar(
                            selectedRange: $selectedRange,
                            canStepBackward: true,
                            canStepForward: windowPageOffset > 0,
                            onStepBackward: { windowPageOffset += 1 },
                            onStepForward: { windowPageOffset = max(0, windowPageOffset - 1) },
                            onRangeChanged: { windowPageOffset = 0 }
                        )
                        .padding(.horizontal, 16)

                        Text("Total acumulado en el período seleccionado, por días.")
                            .font(ImprovingFont.caption(12))
                            .foregroundColor(BevelColors.textMuted)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.bottom, 14)
                    }
                    .background(BevelColors.sheetHeaderBg)

                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Historial de actividad")
                                .font(ImprovingFont.sectionTitle(18))
                                .foregroundColor(BevelColors.textPrimary)
                            Spacer()
                            Button { sortNewestFirst.toggle() } label: {
                                Image(systemName: "arrow.up.arrow.down")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(BevelColors.card))
                                    .overlay(Circle().strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
                            }
                        }

                        if groupedHistory.isEmpty {
                            BevelCard(cornerRadius: 18) {
                                Text("No hay actividades registradas en este período.")
                                    .font(ImprovingFont.body(13.5))
                                    .foregroundColor(BevelColors.textSecondary)
                                    .padding(16)
                            }
                        } else {
                            ForEach(groupedHistory, id: \.monthTitle) { g in
                                Text(g.monthTitle)
                                    .font(ImprovingFont.cardTitle(14.5))
                                    .foregroundColor(BevelColors.textSecondary)
                                    .padding(.top, 4)
                                ForEach(g.items) { w in FitnessActivityHistoryRow(workout: w) }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                }
                .padding(.bottom, 165)
            }
            .background(BevelColors.canvas)

            FloatingMetricAiCoachOverlay(
                metricKey: "str_\(selectedStrengthKpi)_\(selectedRange)",
                metricTitle: "Fuerza",
                insight: aiInsight,
                scrollCollapseSignal: 0,
                leadingEmoji: "💪"
            )
        }
    }

    private func strengthKpiCard(idx: Int, title: String, value: String, sub: String, isDelta: Bool, isUp: Bool) -> some View {
        let active = selectedStrengthKpi == idx
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            selectedStrengthKpi = idx
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(ImprovingFont.caption(12)).foregroundColor(BevelColors.textSecondary).lineLimit(1)
                Text(value).font(ImprovingFont.metricTile(21)).monospacedDigit().foregroundColor(BevelColors.textPrimary).lineLimit(1)
                if isDelta {
                    HStack(spacing: 4) {
                        Image(systemName: isUp ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(BevelColors.skyBlue)
                        Text(sub).font(ImprovingFont.caption(12)).fontWeight(.semibold).monospacedDigit().foregroundColor(BevelColors.skyBlue)
                    }
                } else {
                    Text(sub).font(ImprovingFont.caption(12)).foregroundColor(BevelColors.textSecondary)
                }
            }
            .frame(width: 146, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(BevelColors.card))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(active ? Color.white.opacity(0.42) : BevelColors.cardBorder, lineWidth: active ? 1.3 : 0.8)
            )
        }
    }

    // MARK: - 3G. Grupos musculares (Exact Match to Screenshots 29-33!)

    private var muscleGroupsDetailView: some View {
        let cal = Calendar.current
        let targetDate = cal.date(byAdding: .day, value: -muscleDateOffset, to: store.selectedDate) ?? store.selectedDate
        let snapshots = store.muscleGroupSnapshots(for: targetDate)

        let dateBarText: String = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "es_ES")
            if muscleDateOffset == 0 && store.dayOffset == 0 {
                f.dateFormat = "'Hoy,' d 'de' MMMM"
            } else {
                f.dateFormat = "EEE, d 'de' MMMM"
            }
            return f.string(from: targetDate).capitalized
        }()

        let filtered: [MuscleGroupSnapshot] = {
            var list = snapshots
            if let f = muscleStateFilter {
                list = list.filter { $0.state == f }
            }
            if selectedMuscleDropdown != "Todos los músculos" {
                list = list.filter { $0.muscle.rawValue == selectedMuscleDropdown }
            }
            let rank: (MuscleFreshnessState) -> Int = { st in
                switch st {
                case .recovered: return 0
                case .fatigued: return 1
                case .exhausted: return 2
                case .calibrating: return 3
                }
            }
            return list.sorted { a, b in
                if sortNewestFirst {
                    if rank(a.state) != rank(b.state) { return rank(a.state) < rank(b.state) }
                    return a.freshnessPct > b.freshnessPct
                } else {
                    return a.freshnessPct < b.freshnessPct
                }
            }
        }()

        let recCnt = snapshots.filter { $0.state == .recovered }.count
        let fatCnt = snapshots.filter { $0.state == .fatigued || $0.state == .exhausted }.count
        let aiInsight = MetricFloatingAiInsight(
            shortPillText: fatCnt > 0 ? "Músculos listos y otros aún fatigados" : (recCnt > 0 ? "Grupos musculares recuperados" : "Calibrando grupos musculares"),
            expandedHeadline: fatCnt > 0 ? "Músculos listos y otros aún fatigados" : "Estado muscular actual",
            shortExpandedMessage: fatCnt > 0
                ? "Tienes \(recCnt) grupos recuperados en verde y \(fatCnt) aún fatigados tras tus sesiones recientes. Prioriza los grupos frescos si entrenas hoy."
                : "Registra sesiones de fuerza o sincroniza tus entrenamientos de Apple Health para seguir la recuperación individual de los 20 grupos musculares.",
            expandedMessage: fatCnt > 0
                ? "Tienes \(recCnt) grupos recuperados en verde y \(fatCnt) aún fatigados tras tus sesiones recientes. Prioriza los grupos frescos si entrenas hoy y deja 48h a los fatigados."
                : "Registra sesiones de fuerza o sincroniza tus entrenamientos de Apple Health para seguir la recuperación individual de los 20 grupos musculares.",
            structureIndex: 0, variationSeed: 8
        )

        return ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 14) {
                        DetailSheetHeader(title: "Grupos musculares", onBack: onBack)

                        // Mode Tabs (Volumen total | Carga muscular | Frescura muscular)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                muscleModePill("Volumen total", idx: 0)
                                muscleModePill("Carga muscular", idx: 1)
                                muscleModePill("Frescura muscular", idx: 2)
                            }
                            .padding(.horizontal, 16)
                        }

                        // Dual Front & Back Anatomical Muscle Map (Screenshot 29!)
                        AnatomicalMuscleMapCanvas(
                            snapshots: snapshots,
                            filterState: muscleStateFilter,
                            compact: false
                        )
                        .padding(.horizontal, 20)
                        .padding(.vertical, 6)

                        // Filter Chips (Todo | • Recuperado | • Fatigado | • Agotado)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                muscleFilterChip(title: "Todo", dotColor: nil, active: muscleStateFilter == nil) {
                                    muscleStateFilter = nil
                                }
                                muscleFilterChip(title: "Recuperado", dotColor: BevelColors.greenPrimary, active: muscleStateFilter == .recovered) {
                                    muscleStateFilter = .recovered
                                }
                                muscleFilterChip(title: "Fatigado", dotColor: BevelColors.amberStart, active: muscleStateFilter == .fatigued) {
                                    muscleStateFilter = .fatigued
                                }
                                muscleFilterChip(title: "Agotado", dotColor: BevelColors.coralHigh, active: muscleStateFilter == .exhausted) {
                                    muscleStateFilter = .exhausted
                                }
                            }
                            .padding(.horizontal, 16)
                        }

                        // Date Stepper Bar (<  Hoy, 23 de noviembre  📅  >)
                        HStack(spacing: 8) {
                            Button { muscleDateOffset += 1 } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(Color.white.opacity(0.06)))
                            }
                            Text(dateBarText)
                                .font(ImprovingFont.cardTitle(14))
                                .foregroundColor(BevelColors.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(Capsule().fill(Color.white.opacity(0.06)))
                            Button { muscleDateOffset = 0 } label: {
                                Image(systemName: "calendar")
                                    .font(.system(size: 13))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(Color.white.opacity(0.06)))
                            }
                            Button { muscleDateOffset = max(0, muscleDateOffset - 1) } label: {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(muscleDateOffset > 0 ? BevelColors.textPrimary : BevelColors.textMuted.opacity(0.35))
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(Color.white.opacity(0.06)))
                            }
                            .disabled(muscleDateOffset == 0)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                    .background(BevelColors.sheetHeaderBg)

                    // 20-Muscle List (Screenshots 30-33!)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Menu {
                                Button("Todos los músculos") { selectedMuscleDropdown = "Todos los músculos" }
                                ForEach(MuscleGroupKind.allCases) { m in
                                    Button(m.rawValue) { selectedMuscleDropdown = m.rawValue }
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Text(selectedMuscleDropdown)
                                        .font(ImprovingFont.cardTitle(15.5))
                                        .foregroundColor(BevelColors.textPrimary)
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(BevelColors.textSecondary)
                                }
                            }
                            Spacer()
                            Button { sortNewestFirst.toggle() } label: {
                                Image(systemName: "arrow.up.arrow.down")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(BevelColors.card))
                                    .overlay(Circle().strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
                            }
                        }

                        ForEach(filtered) { snap in
                            BevelCard(cornerRadius: 18) {
                                HStack(spacing: 13) {
                                    MuscleMiniThumbnailView(muscle: snap.muscle, color: snap.state.color)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(snap.muscle.rawValue)
                                            .font(ImprovingFont.cardTitle(15))
                                            .foregroundColor(BevelColors.textPrimary)
                                        if muscleModeTab == 0 {
                                            Text("\(snap.recentSets) series · \(Int(snap.recentVolumeKg.rounded())) kg")
                                                .font(ImprovingFont.caption(13))
                                                .foregroundColor(BevelColors.textSecondary)
                                        } else if muscleModeTab == 1 {
                                            Text("Carga \(snap.loadScore) · \(snap.state.rawValue)")
                                                .font(ImprovingFont.caption(13))
                                                .foregroundColor(snap.state.color)
                                        } else {
                                            HStack(spacing: 5) {
                                                Text(snap.state.rawValue)
                                                    .foregroundColor(snap.state.color)
                                                Text("•")
                                                    .foregroundColor(BevelColors.textMuted)
                                                Text("\(snap.freshnessPct) %")
                                                    .monospacedDigit()
                                                    .foregroundColor(BevelColors.textPrimary)
                                            }
                                            .font(ImprovingFont.caption(13.5))
                                            .fontWeight(.semibold)
                                        }
                                    }
                                    Spacer()
                                    MuscleBatteryBarsView(
                                        filledBars: snap.filledBars,
                                        color: snap.state.color,
                                        isCalibrating: snap.state == .calibrating
                                    )
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                            }
                        }

                        FitnessResourceCarousel(items: [
                            FitnessResourceItem(
                                id: "res_mg_load",
                                badgeIcon: "scope",
                                heroTitle: "Muscular Load",
                                heroSubtitle: "The Basics",
                                cardTitle: "The Basics: Muscular Load",
                                cardDescription: "Entrena con propósito comprendiendo tu carga muscular.",
                                gradientHexA: 0x4E3F37,
                                gradientHexB: 0x242730,
                                fullGuideBody: "Tu carga muscular refleja el estrés mecánico acumulado en los últimos 7 y 28 días por grupo muscular."
                            ),
                            FitnessResourceItem(
                                id: "res_mg_fresh",
                                badgeIcon: "bolt.batteryblock.fill",
                                heroTitle: "Muscle Freshness",
                                heroSubtitle: "The Basics",
                                cardTitle: "The Basics: Muscle Freshness",
                                cardDescription: "Sabe cuándo apretar y cuándo dar descanso a cada músculo.",
                                gradientHexA: 0x4A4035,
                                gradientHexB: 0x22262E,
                                fullGuideBody: "Cada grupo muscular se recupera en 48–72 horas según la intensidad. Entrenar músculos recuperados en verde reduce el riesgo de lesión."
                            )
                        ])
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                }
                .padding(.bottom, 165)
            }
            .background(BevelColors.canvas)

            FloatingMetricAiCoachOverlay(
                metricKey: "mg_\(muscleModeTab)_\(muscleDateOffset)",
                metricTitle: "Grupos musculares",
                insight: aiInsight,
                scrollCollapseSignal: 0,
                leadingEmoji: "🌿"
            )
        }
    }

    // MARK: - Shared Helpers

    private var activityFilterChipsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(BevelColors.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.08)))

                ForEach(availableActivityNames, id: \.self) { name in
                    let active = selectedActivityFilter == name
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        selectedActivityFilter = name
                    } label: {
                        Text(name)
                            .font(ImprovingFont.cardTitle(13))
                            .foregroundColor(active ? .white : BevelColors.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(active ? Color(hex: 0x6A6E7A) : Color.white.opacity(0.06)))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.7))
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func muscleModePill(_ title: String, idx: Int) -> some View {
        let active = muscleModeTab == idx
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            muscleModeTab = idx
        } label: {
            Text(title)
                .font(ImprovingFont.cardTitle(13.5))
                .foregroundColor(active ? .white : BevelColors.textSecondary)
                .padding(.horizontal, 15)
                .padding(.vertical, 9)
                .background(Capsule().fill(active ? Color(hex: 0x6A6E7A) : Color.white.opacity(0.06)))
        }
    }

    private func muscleFilterChip(title: String, dotColor: Color?, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            HStack(spacing: 6) {
                if let c = dotColor {
                    Circle().fill(c).frame(width: 7, height: 7)
                }
                Text(title)
                    .font(ImprovingFont.caption(13))
                    .fontWeight(.semibold)
                    .foregroundColor(active ? .white : BevelColors.textSecondary)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(Capsule().fill(active ? Color(hex: 0x6A6E7A) : Color.white.opacity(0.06)))
        }
    }

    private func focusRow(_ label: String, val: String, pct: Int, color: Color) -> some View {
        HStack(spacing: 10) {
            Text(label).font(ImprovingFont.body(14)).foregroundColor(BevelColors.textPrimary).frame(width: 96, alignment: .leading)
            Text(val).font(ImprovingFont.cardTitle(14)).monospacedDigit().foregroundColor(BevelColors.textPrimary).frame(width: 44, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08)).frame(height: 8)
                    if pct > 0 {
                        Capsule().fill(color).frame(width: max(8, geo.size.width * CGFloat(pct) / 100.0), height: 8)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 18)
            Text("\(pct)%").font(ImprovingFont.cardTitle(14)).monospacedDigit().foregroundColor(BevelColors.textPrimary).frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private func zoneExplainBullet(color: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(color).frame(width: 7, height: 7).padding(.top, 6)
            (Text(title).fontWeight(.semibold).foregroundColor(BevelColors.textPrimary) + Text(" \(body)").foregroundColor(BevelColors.textSecondary))
                .font(ImprovingFont.body(13.5))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

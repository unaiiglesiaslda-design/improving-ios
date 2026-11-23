import SwiftUI

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

// MARK: - 2. Training Load Detail Sheet (7 d – 1 A + Working < > + Zero Fake Data)

struct TrainingLoadDetailScreen: View {
    @ObservedObject var store: ImprovingStore
    let initialTab: TrainingLoadTab
    let onBack: () -> Void

    @State private var selectedTab: TrainingLoadTab = .cardio
    @State private var selectedRange: String = "30 d"
    @State private var windowPageOffset: Int = 0

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

    var body: some View {
        let isCardio = selectedTab == .cardio
        let window = store.customWindowSeries(spanDays: spanDays, windowPageOffset: windowPageOffset) { day in
            if isCardio {
                return day.strainPct.map { AppleHealthExportImporter.round1(Double($0) * 0.45) }
            } else {
                return day.strengthMinutes > 0 ? Double(day.strengthMinutes) : nil
            }
        }
        let latestVal = window.realPoints.last

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    DetailSheetHeader(title: isCardio ? "Carga cardíaca" : "Carga muscular", onBack: onBack)

                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(latestVal.map { "\(Int($0.rounded()))" } ?? "Sin datos")
                                .font(ImprovingFont.displayLarge(latestVal != nil ? 34 : 26))
                                .monospacedDigit()
                                .foregroundColor(latestVal != nil ? BevelColors.textPrimary : BevelColors.textMuted)
                            Text(window.windowRangeLabel)
                                .font(ImprovingFont.caption(13))
                                .foregroundColor(BevelColors.textSecondary)
                        }
                        Spacer()
                        if let v = latestVal {
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(v >= 20 ? "Productivo" : "Moderado")
                                    .font(ImprovingFont.cardTitle(15))
                                    .foregroundColor(v >= 20 ? BevelColors.greenPrimary : BevelColors.skyBlue)
                                Text(isCardio ? "Ref. 24–42" : "Min. fuerza")
                                    .font(ImprovingFont.caption(12.5))
                                    .foregroundColor(BevelColors.textSecondary)
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    HStack(spacing: 10) {
                        tabPill("Carga cardíaca", active: isCardio) { selectedTab = .cardio; windowPageOffset = 0 }
                        tabPill("Carga muscular", active: !isCardio) { selectedTab = .muscular; windowPageOffset = 0 }
                        Spacer()
                    }
                    .padding(.horizontal, 16)

                    HealthMetricBaselineChart(
                        optionalPoints: window.values,
                        dates: window.dates,
                        bandLow: isCardio ? 24 : 20,
                        bandHigh: isCardio ? 42 : 60,
                        averageText: "",
                        accentColor: isCardio ? BevelColors.greenPrimary : BevelColors.strengthPink,
                        valueFormatter: { isCardio ? "\(Int($0.rounded()))" : "\(Int($0.rounded())) min" }
                    )
                    .padding(.horizontal, 14)

                    // Range Selector < [ 7 d | 30 d | 3 M | 6 M | 1 A ] >
                    HStack(spacing: 6) {
                        Button {
                            if window.canStepBackward { windowPageOffset += 1 }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13))
                                .foregroundColor(window.canStepBackward ? BevelColors.textPrimary : BevelColors.textMuted.opacity(0.35))
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(Color.white.opacity(0.06)))
                        }
                        .disabled(!window.canStepBackward)

                        HStack(spacing: 2) {
                            ForEach(["7 d", "30 d", "3 M", "6 M", "1 A"], id: \.self) { r in
                                Button { selectedRange = r; windowPageOffset = 0 } label: {
                                    Text(r)
                                        .font(ImprovingFont.caption(11.5))
                                        .fontWeight(.semibold)
                                        .foregroundColor(selectedRange == r ? .white : BevelColors.textSecondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                        .background(Capsule().fill(selectedRange == r ? Color(hex: 0x6A6E7A) : .clear))
                                }
                            }
                        }
                        .padding(3)
                        .background(Capsule().fill(Color.white.opacity(0.06)))

                        Button {
                            if window.canStepForward { windowPageOffset = max(0, windowPageOffset - 1) }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13))
                                .foregroundColor(window.canStepForward ? BevelColors.textPrimary : BevelColors.textMuted.opacity(0.35))
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(Color.white.opacity(0.06)))
                        }
                        .disabled(!window.canStepForward)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                .background(BevelColors.sheetHeaderBg)
            }
            .padding(.bottom, 150)
        }
        .background(BevelColors.canvas)
        .onAppear { selectedTab = initialTab }
    }

    private func tabPill(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(ImprovingFont.cardTitle(13))
                .foregroundColor(active ? .white : BevelColors.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Capsule().fill(active ? Color(hex: 0x6A6E7A) : Color.white.opacity(0.06)))
        }
    }
}

// MARK: - 3. Cardio Metric Detail Sheet (Strictly Real Imported Metrics, 7 d – 1 A + Working < >)

struct CardioMetricDetailScreen: View {
    @ObservedObject var store: ImprovingStore
    let route: CardioMetricRoute
    let onBack: () -> Void

    @State private var selectedRange: String = "30 d"
    @State private var windowPageOffset: Int = 0

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch route {
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
                }
            }
            .padding(.bottom, 155)
        }
        .background(BevelColors.canvas)
    }

    private func rangeBar(window: MetricWindowSeries) -> some View {
        HStack(spacing: 6) {
            Button {
                if window.canStepBackward { windowPageOffset += 1 }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13))
                    .foregroundColor(window.canStepBackward ? BevelColors.textPrimary : BevelColors.textMuted.opacity(0.35))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.06)))
            }
            .disabled(!window.canStepBackward)

            HStack(spacing: 2) {
                ForEach(["7 d", "30 d", "3 M", "6 M", "1 A"], id: \.self) { r in
                    Button { selectedRange = r; windowPageOffset = 0 } label: {
                        Text(r)
                            .font(ImprovingFont.caption(11.5))
                            .fontWeight(.semibold)
                            .foregroundColor(selectedRange == r ? .white : BevelColors.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(selectedRange == r ? Color(hex: 0x6A6E7A) : .clear))
                    }
                }
            }
            .padding(3)
            .background(Capsule().fill(Color.white.opacity(0.06)))

            Button {
                if window.canStepForward { windowPageOffset = max(0, windowPageOffset - 1) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundColor(window.canStepForward ? BevelColors.textPrimary : BevelColors.textMuted.opacity(0.35))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.06)))
            }
            .disabled(!window.canStepForward)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    private var activitiesOverviewView: some View {
        let last30 = store.trailingCalendarSummaries(days: 30)
        let allWorkouts: [(String, EffortEventItem)] = last30.reversed().flatMap { item in
            (item.summary?.workouts ?? []).map { (item.iso, $0) }
        }
        let totalDurMin = allWorkouts.reduce(0) { $0 + $1.1.durationMin }
        let totalKcal = allWorkouts.reduce(0) { $0 + $1.1.kcal }

        return VStack(alignment: .leading, spacing: 14) {
            DetailSheetHeader(title: "Todas las actividades", onBack: onBack)

            HStack(spacing: 12) {
                HeaderedMetricCard(
                    icon: "clock.fill",
                    title: "Duración (30 d)",
                    value: totalDurMin > 0 ? "\(totalDurMin / 60) h \(String(format: "%02d", totalDurMin % 60)) m" : "--"
                )
                HeaderedMetricCard(
                    icon: "flame.fill",
                    title: "Energía (30 d)",
                    value: totalKcal > 0 ? "\(totalKcal)" : "--",
                    unit: "kcal"
                )
            }
            .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 12) {
                Text("Historial de actividad (\(allWorkouts.count))")
                    .font(ImprovingFont.sectionTitle(18))
                    .foregroundColor(BevelColors.textPrimary)

                if allWorkouts.isEmpty {
                    BevelCard(cornerRadius: 18) {
                        Text("No hay entrenamientos registrados en los últimos 30 días.")
                            .font(ImprovingFont.body(13.5))
                            .foregroundColor(BevelColors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    }
                } else {
                    ForEach(allWorkouts, id: \.1.id) { iso, w in
                        BevelCard(cornerRadius: 18) {
                            HStack(spacing: 12) {
                                Image(systemName: w.categoryLabel == "Fuerza" ? "figure.strengthtraining.traditional" : "figure.run")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(BevelColors.amberStart)
                                    .frame(width: 42, height: 42)
                                    .background(Circle().fill(BevelColors.amberSoftBg))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(iso) · \(w.timeRange)").font(ImprovingFont.caption(12)).foregroundColor(BevelColors.textMuted)
                                    Text(w.title).font(ImprovingFont.cardTitle(15)).foregroundColor(BevelColors.textPrimary)
                                    let bits = [
                                        "\(w.durationMin) min",
                                        w.kcal > 0 ? "🔥 \(w.kcal) kcal" : nil,
                                        w.avgHrBpm > 0 ? "♡ \(w.avgHrBpm) ppm" : nil
                                    ].compactMap { $0 }.joined(separator: "   ")
                                    Text(bits).font(ImprovingFont.caption(12.5)).foregroundColor(BevelColors.textSecondary)
                                }
                                Spacer()
                            }
                            .padding(14)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var vo2MaxDetailView: some View {
        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: store.userProfile)
        let window = store.customWindowSeries(spanDays: spanDays, windowPageOffset: windowPageOffset) { $0.vo2MaxMlKgMin }
        let cur = window.realPoints.last ?? store.latestVo2Max

        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                DetailSheetHeader(title: "VO₂ máx.", onBack: onBack)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cur.map { String(format: "%.1f", locale: Locale(identifier: "es_ES"), $0) } ?? "Sin datos")
                            .font(ImprovingFont.displayLarge(cur != nil ? 34 : 26))
                            .foregroundColor(cur != nil ? BevelColors.textPrimary : BevelColors.textMuted)
                        Text("\(window.windowRangeLabel) · \(norms.vo2CohortSubtitle)").font(ImprovingFont.caption(12.5)).foregroundColor(BevelColors.textSecondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)

                HealthMetricBaselineChart(
                    optionalPoints: window.values,
                    dates: window.dates,
                    bandLow: norms.vo2GoodThreshold,
                    bandHigh: norms.vo2ExcellentThreshold,
                    averageText: "",
                    accentColor: BevelColors.amberStart,
                    valueFormatter: { String(format: "%.1f", locale: Locale(identifier: "es_ES"), $0) }
                )
                .padding(.horizontal, 14)

                rangeBar(window: window)
            }
            .background(BevelColors.sheetHeaderBg)
        }
    }

    private var hrRecoveryDetailView: some View {
        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: store.userProfile)
        let window = store.customWindowSeries(spanDays: spanDays, windowPageOffset: windowPageOffset) { $0.hrRecoveryBpm }
        let cur = window.realPoints.last ?? store.latestHrRecoveryBpm

        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                DetailSheetHeader(title: "Recuperación de FC", onBack: onBack)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cur.map { "\(Int($0.rounded())) ppm" } ?? "Sin datos")
                            .font(ImprovingFont.displayLarge(cur != nil ? 34 : 26))
                            .foregroundColor(cur != nil ? BevelColors.textPrimary : BevelColors.textMuted)
                        Text(window.windowRangeLabel).font(ImprovingFont.caption(13)).foregroundColor(BevelColors.textSecondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)

                HealthMetricBaselineChart(
                    optionalPoints: window.values,
                    dates: window.dates,
                    bandLow: Double(norms.hrrGoodThresholdBpm),
                    bandHigh: Double(norms.hrrGoodThresholdBpm + 20),
                    averageText: "",
                    accentColor: BevelColors.coralHigh,
                    valueFormatter: { "\(Int($0.rounded())) ppm" }
                )
                .padding(.horizontal, 14)

                rangeBar(window: window)
            }
            .background(BevelColors.sheetHeaderBg)
        }
    }

    private var cardioFocusDetailView: some View {
        let zones = store.currentDaySummary?.hrZoneMinutes ?? [0, 0, 0, 0, 0]
        let lowAero = (zones.count > 0 ? zones[0] : 0) + (zones.count > 1 ? zones[1] : 0)
        let highAero = (zones.count > 2 ? zones[2] : 0) + (zones.count > 3 ? zones[3] : 0)
        let anaero = zones.count > 4 ? zones[4] : 0
        let total = lowAero + highAero + anaero

        return VStack(alignment: .leading, spacing: 16) {
            DetailSheetHeader(title: "Foco cardiovascular", onBack: onBack)
            if total == 0 {
                BevelCard(cornerRadius: 20) {
                    Text("No hay minutos por zonas cardíacas registrados en esta fecha.")
                        .font(ImprovingFont.body(14))
                        .foregroundColor(BevelColors.textSecondary)
                        .padding(16)
                }
                .padding(.horizontal, 16)
            } else {
                let pLow = Int((Double(lowAero) / Double(total) * 100).rounded())
                let pHigh = Int((Double(highAero) / Double(total) * 100).rounded())
                let pAn = max(0, 100 - pLow - pHigh)
                BevelCard(cornerRadius: 20) {
                    VStack(spacing: 14) {
                        focusRow("Aeró. bajo", val: "\(lowAero)m", pct: pLow, color: BevelColors.tealLow)
                        Divider().background(BevelColors.divider)
                        focusRow("Aeró. alto", val: "\(highAero)m", pct: pHigh, color: BevelColors.skyBlue)
                        Divider().background(BevelColors.divider)
                        focusRow("Anaeróbico", val: "\(anaero)m", pct: pAn, color: BevelColors.periwinkleStart)
                    }
                    .padding(16)
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var hrZonesDetailView: some View {
        let z = store.currentDaySummary?.hrZoneMinutes ?? [0, 0, 0, 0, 0]
        let maxZ = max(z.max() ?? 0, 1)
        let totalZ = z.reduce(0, +)
        let specs: [(String, Int, Color)] = [
            ("Z1", z.count > 0 ? z[0] : 0, Color(hex: 0x5A84F8)),
            ("Z2", z.count > 1 ? z[1] : 0, BevelColors.greenPrimary),
            ("Z3", z.count > 2 ? z[2] : 0, BevelColors.amberStart),
            ("Z4", z.count > 3 ? z[3] : 0, BevelColors.redAlert),
            ("Z5", z.count > 4 ? z[4] : 0, Color(hex: 0xA855F7)),
        ]

        return VStack(alignment: .leading, spacing: 16) {
            DetailSheetHeader(title: "Zonas de frecuencia cardíaca", onBack: onBack)
            if totalZ == 0 {
                BevelCard(cornerRadius: 20) {
                    Text("No se registraron zonas de frecuencia cardíaca en esta fecha.")
                        .font(ImprovingFont.body(14))
                        .foregroundColor(BevelColors.textSecondary)
                        .padding(16)
                }
                .padding(.horizontal, 16)
            } else {
                HStack(alignment: .bottom, spacing: 14) {
                    ForEach(specs, id: \.0) { label, mins, color in
                        let h = max(6, CGFloat(mins) / CGFloat(maxZ) * 145)
                        VStack(spacing: 6) {
                            Text("\(mins)m").font(ImprovingFont.caption(11)).foregroundColor(BevelColors.textSecondary)
                            RoundedRectangle(cornerRadius: 6)
                                .fill(LinearGradient(colors: [color, color.opacity(0.65)], startPoint: .top, endPoint: .bottom))
                                .frame(height: h)
                            Text(label).font(ImprovingFont.caption(12)).fontWeight(.semibold).foregroundColor(BevelColors.textPrimary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 185, alignment: .bottom)
                .padding(.horizontal, 16)
            }
        }
    }

    private func focusRow(_ label: String, val: String, pct: Int, color: Color) -> some View {
        HStack(spacing: 10) {
            Text(label).font(ImprovingFont.body(14)).foregroundColor(BevelColors.textPrimary).frame(width: 82, alignment: .leading)
            Text(val).font(ImprovingFont.cardTitle(14)).foregroundColor(BevelColors.textPrimary).frame(width: 42, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08)).frame(height: 7)
                    if pct > 0 {
                        Capsule().fill(color).frame(width: max(8, geo.size.width * CGFloat(pct) / 100.0), height: 7)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 16)
            Text("\(pct)%").font(ImprovingFont.cardTitle(14)).foregroundColor(BevelColors.textPrimary).frame(width: 38, alignment: .trailing)
        }
    }
}

import SwiftUI

// MARK: - 1. Health Monitor Metric Detail Sheet (Literal Match to Screenshots 16–33)

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
                "La FR (frecuencia respiratoria) registra tus respiraciones por minuto durante el sueño.",
                "Se calcula la tasa media durante toda la noche a partir del patrón rítmico de las pulsaciones de tu corazón mientras inhalas y exhalas.",
                "La FR suele tener un nivel similar todas las noches, por lo que, en caso de observar un gran cambio, debe de estar provocado por una enfermedad, cansancio, alergias o cambios de altitud."
            ]
        case .restingHeartRate:
            return [
                "La FCR (frecuencia cardíaca en reposo) mide el promedio de los latidos del corazón por minuto mientras estás completamente en reposo.",
                "En general, una FCR más baja apunta a una mejor aptitud cardiovascular. Significa que el músculo cardíaco puede bombear más sangre con cada pulsación.",
                "Los picos temporales de FCR pueden indicar fatiga o enfermedad, mientras que niveles más bajos sostenidos apuntan a una mejor salud del corazón."
            ]
        case .hrv:
            return [
                "La VFC (variabilidad de la frecuencia cardíaca) en reposo es la variación entre los latidos del corazón mientras duermes que muestra la capacidad de adaptación del cuerpo.",
                "La VFC alta suele equivaler a una mejor condición física. Es única para cada persona en función de edad, género y estilo de vida, por lo que conviene observar tendencias relativas.",
                "Si aumenta, indica buena adaptación. Si se reduce, puede señalar entrenamiento excesivo, sueño deficiente o altos niveles de estrés."
            ]
        case .oxygenSaturation:
            return [
                "La SpO₂ (saturación capilar periférica de oxígeno) mide el porcentaje de sangre saturada con oxígeno durante el sueño y en segundo plano.",
                "La saturación de oxígeno puede verse afectada por cambios de altitud, actividad física, deshidratación y ciertas condiciones cardiovasculares o respiratorias."
            ]
        case .wristTemperature:
            return [
                "La temperatura refleja la temperatura media de la piel durante la noche anterior. Las mediciones nocturnas minimizan la interferencia de factores externos como el movimiento o la temperatura ambiente.",
                "Por regla general, la temperatura de la piel de la muñeca es aproximadamente 1–2 °C más baja que la temperatura corporal central."
            ]
        case .sleepDuration:
            return [
                "La Duración del sueño registra la cantidad total del tiempo que has pasado en los ciclos de sueño central, MOR (movimiento ocular rápido) y sueño profundo. Por lo general, los adultos necesitan entre 7 y 9 horas de sueño al día.",
                "Para mejorarla, intenta acostarte antes y evita cafeína, alcohol y comidas pesadas antes de dormir. Mantener la habitación fresca y oscura ayuda a reducir el tiempo de vigilia."
            ]
        }
    }

    private func resourceCards(for kind: HealthMetricKind) -> [(String, String, String, String, [Color])] {
        switch kind {
        case .respiratoryRate:
            return [
                ("lungs.fill", "Respiratory Rate", "The Basics: Respiratory Rate", "Gauge the performance of your respiratory system...", [Color(hex: 0x2B5866), Color(hex: 0x1A3540)]),
                ("wind", "Improving Your RR", "Improving Your Respiratory Rate", "Consider making these changes to strengthen your RR...", [Color(hex: 0x354B34), Color(hex: 0x1D291E)])
            ]
        case .restingHeartRate:
            return [
                ("heart.fill", "Resting Heart Rate", "The Basics: Resting Heart Rate", "A vital metric for assessing your cardiovascular health...", [Color(hex: 0x5B645E), Color(hex: 0x2B302E)]),
                ("chart.bar.fill", "Athletes Table", "What Makes a Good RHR?", "Put your resting heart rate into perspective...", [Color(hex: 0x4E4A42), Color(hex: 0x292622)])
            ]
        case .hrv:
            return [
                ("waveform.path.ecg", "Heart Rate Variability", "The Basics: Heart Rate Variability", "Offers valuable insights into your autonomic health...", [Color(hex: 0x255B82), Color(hex: 0x14334C)]),
                ("chart.xyaxis.line", "HRV by Age", "HRV by Age", "Understanding the correlation between HRV and age...", [Color(hex: 0x3B4046), Color(hex: 0x1F2227)])
            ]
        case .oxygenSaturation:
            return [
                ("drop.fill", "SpO2", "The Basics: SpO2", "Advanced health monitoring features can transform...", [Color(hex: 0x575443), Color(hex: 0x2B2A22)]),
                ("applewatch", "SpO2 on Watch", "How Your Wearable Tracks SpO2", "With its optical sensors and nightly sampling...", [Color(hex: 0x5E262B), Color(hex: 0x2C1417)])
            ]
        case .wristTemperature:
            return [
                ("thermometer.medium", "Temperature", "The Basics: Wrist Temperature", "Learn how to leverage overnight skin temperature...", [Color(hex: 0x584236), Color(hex: 0x28201C)]),
                ("flame.fill", "Skin Temp & Fevers", "Can Wrist Temp Detect Illness?", "The most common methods to spot early deviations...", [Color(hex: 0x6B4837), Color(hex: 0x302119)])
            ]
        case .sleepDuration:
            return [
                ("waveform", "Time Asleep", "The Basics: Time Asleep", "Time asleep affects much more than just energy...", [Color(hex: 0x364E6B), Color(hex: 0x1A283A)]),
                ("bed.double.fill", "Sleep Hygiene", "Prioritizing Sleep Hygiene", "How to improve your sleep routine and consistency...", [Color(hex: 0x434852), Color(hex: 0x22252B)])
            ]
        }
    }

    var body: some View {
        let kind = store.selectedHealthMetric
        let series = store.metricSeries(for: kind, spanDays: spanDays)
        let points = series.map(\.1)
        let dates = series.map(\.0)
        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: store.userProfile)
        let (bandLow, bandHigh): (Double, Double) = switch kind {
        case .respiratoryRate: (14.9, 15.6)
        case .restingHeartRate: (45.8, 51.2)
        case .hrv: (62.0, 83.5)
        case .oxygenSaturation: (95.8, 96.6)
        case .wristTemperature: (35.6, 35.9)
        case .sleepDuration: (6.55, 8.9)
        }
        let currentNumeric: Double? = switch kind {
        case .respiratoryRate: store.dataAvailability.hasRespData ? store.respRateRpm : nil
        case .restingHeartRate: store.dataAvailability.hasRestingHrData ? store.restingHrBpm : nil
        case .hrv: store.dataAvailability.hasHrvData ? store.hrvMs : nil
        case .oxygenSaturation: store.dataAvailability.hasSpo2Data ? store.spo2DisplayDouble : nil
        case .wristTemperature: store.dataAvailability.hasTempData ? store.wristTempAbsoluteC : nil
        case .sleepDuration: store.currentDaySummary?.asleepMinutes.map { Double($0) / 60.0 }
        }
        let avgVal = points.isEmpty ? (currentNumeric ?? 0) : points.reduce(0, +) / Double(points.count)
        let heroVal = inspectedFloat ?? currentNumeric ?? points.last ?? 0

        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Seamless Dark Sheet Header Pane (Screenshots 16, 19, 22, 25, 28, 31)
                    VStack(alignment: .leading, spacing: 14) {
                        DetailSheetHeader(title: kind.title, onBack: onBack)

                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 2) {
                                if kind == .sleepDuration && inspectedFloat == nil {
                                    Text(store.sleepDurationText)
                                        .font(ImprovingFont.displayLarge(31))
                                        .foregroundColor(BevelColors.textPrimary)
                                } else {
                                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                                        EmptyView().animatableNumber(
                                            heroVal,
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
                                Text(inspectedDate ?? store.fullDateLabel)
                                    .font(ImprovingFont.caption(13))
                                    .foregroundColor(BevelColors.textSecondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("Rango normal")
                                    .font(ImprovingFont.cardTitle(14.5))
                                    .foregroundColor(BevelColors.greenPrimary)
                                HStack(spacing: 4) {
                                    Image(systemName: "line.3.horizontal").font(.system(size: 10)).foregroundColor(BevelColors.textMuted)
                                    Text(kind == .sleepDuration
                                        ? "6 h 33 min - 8 h 54 min"
                                        : String(format: "%.1f - %.1f %@", locale: Locale(identifier: "es_ES"), bandLow, bandHigh, kind.unit))
                                        .font(ImprovingFont.caption(12.5))
                                        .fontWeight(.semibold)
                                        .monospacedDigit()
                                        .foregroundColor(BevelColors.textPrimary)
                                }
                            }
                        }
                        .padding(.horizontal, 16)

                        // Full-title Metric Switcher Pills (Screenshot 16)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(HealthMetricKind.allCases) { item in
                                    let active = item == kind
                                    Button {
                                        inspectedFloat = nil
                                        inspectedDate = nil
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

                        // Full-Width Baseline Chart
                        HealthMetricBaselineChart(
                            points: points,
                            dates: dates,
                            bandLow: bandLow,
                            bandHigh: bandHigh,
                            averageText: kind == .sleepDuration
                                ? "Prom. \(Int(avgVal)) h \(Int((avgVal - floor(avgVal)) * 60)) min"
                                : String(format: "Prom. %.1f %@", locale: Locale(identifier: "es_ES"), avgVal, kind.unit),
                            accentColor: BevelColors.greenPrimary,
                            valueFormatter: { v in
                                kind == .sleepDuration
                                    ? "\(Int(v)) h \(Int((v - floor(v)) * 60)) min"
                                    : String(format: "%.1f %@", locale: Locale(identifier: "es_ES"), v, kind.unit)
                            },
                            onPointSelected: { _, v, d in
                                withAnimation(.easeOut(duration: 0.22)) {
                                    inspectedFloat = v
                                    inspectedDate = d
                                }
                            }
                        )
                        .padding(.horizontal, 14)

                        // Exact Range Selector Bar: < [ 30 d | 3 M | 6 M | 1 A ] 📅 >
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(BevelColors.textPrimary)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Color.white.opacity(0.06)))

                            HStack(spacing: 4) {
                                ForEach(["30 d", "3 M", "6 M", "1 A"], id: \.self) { r in
                                    let active = store.selectedHealthRange == r
                                    Button {
                                        inspectedFloat = nil
                                        inspectedDate = nil
                                        store.selectedHealthRange = r
                                    } label: {
                                        Text(r)
                                            .font(ImprovingFont.caption(12.5))
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

                            Image(systemName: "calendar")
                                .font(.system(size: 13))
                                .foregroundColor(BevelColors.textPrimary)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Color.white.opacity(0.06)))

                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(BevelColors.textPrimary)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Color.white.opacity(0.06)))
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                    .background(BevelColors.sheetHeaderBg)

                    VStack(alignment: .leading, spacing: 18) {
                        // Weekly Sleep Distribution ONLY for Sleep Duration (Screenshots 31 & 32)
                        if kind == .sleepDuration {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Distribución semanal del sueño")
                                    .font(ImprovingFont.sectionTitle(17.5))
                                    .foregroundColor(BevelColors.textPrimary)

                                HStack(spacing: 4) {
                                    let days = [("lun", 0.35), ("mar", 0.72), ("mié", 0.68), ("jue", 0.30), ("vie", 0.78), ("sáb", 0.92), ("dom", 0.64)]
                                    ForEach(days, id: \.0) { name, intensity in
                                        VStack(spacing: 6) {
                                            RoundedRectangle(cornerRadius: 5)
                                                .fill(BevelColors.greenPrimary.opacity(intensity))
                                                .frame(height: 16)
                                            Text(name)
                                                .font(ImprovingFont.caption(12))
                                                .foregroundColor(BevelColors.textPrimary)
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                }

                                HStack(spacing: 14) {
                                    HStack(spacing: 5) {
                                        Circle().fill(BevelColors.greenPrimary).frame(width: 7, height: 7)
                                        Text("Más sueño").font(ImprovingFont.caption(12)).foregroundColor(BevelColors.textSecondary)
                                    }
                                    HStack(spacing: 5) {
                                        Circle().fill(BevelColors.greenPrimary.opacity(0.32)).frame(width: 7, height: 7)
                                        Text("Menos sueño").font(ImprovingFont.caption(12)).foregroundColor(BevelColors.textSecondary)
                                    }
                                }
                            }
                        }

                        // Análisis de tendencias (Exact Table from Screenshots 17, 20, 23, 26, 29, 32)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Análisis de tendencias")
                                .font(ImprovingFont.sectionTitle(18))
                                .foregroundColor(BevelColors.textPrimary)
                            Text("Último dato el \(store.fullDateLabel)")
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

                                let periods = [3, 7, 14, 30, 90]
                                ForEach(Array(periods.enumerated()), id: \.offset) { idx, p in
                                    let subPts = Array(points.suffix(min(max(p, 3), max(points.count, 1))))
                                    let subAvg = subPts.isEmpty ? avgVal : subPts.reduce(0, +) / Double(subPts.count)
                                    let delta = (currentNumeric ?? avgVal) - subAvg
                                    let isSignificant = abs(delta) >= (kind == .hrv ? 3.5 : (kind == .sleepDuration ? 0.35 : 0.7))
                                    let icon = !isSignificant ? "arrow.right.circle.fill" : (delta > 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                    let color = isSignificant ? BevelColors.skyBlue : BevelColors.textMuted

                                    HStack {
                                        Text("\(p) día(s)")
                                            .font(ImprovingFont.body(14.5))
                                            .foregroundColor(BevelColors.textSecondary)
                                            .frame(width: 82, alignment: .leading)

                                        HStack(spacing: 7) {
                                            Image(systemName: icon)
                                                .font(.system(size: 16))
                                                .foregroundColor(color)
                                            Text(kind == .sleepDuration
                                                ? String(format: "%+d min", Int((delta * 60).rounded()))
                                                : String(format: "%+.1f %@", locale: Locale(identifier: "es_ES"), delta, kind.unit))
                                                .font(ImprovingFont.cardTitle(14.5))
                                                .monospacedDigit()
                                                .foregroundColor(BevelColors.textPrimary)
                                        }

                                        Spacer()

                                        TrendSparklineWithBand(
                                            points: subPts.isEmpty ? [bandLow, avgVal, bandHigh] : subPts,
                                            lineColor: isSignificant ? BevelColors.skyBlue : BevelColors.textMuted,
                                            fillUnder: true
                                        )
                                        .frame(width: 96, height: 24)
                                    }
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 16)

                                    if idx < periods.count - 1 {
                                        Divider().background(BevelColors.divider).padding(.horizontal, 16)
                                    }
                                }
                            }
                        }

                        Text("Basado en las medias móviles de 7 días durante el período seleccionado.")
                            .font(ImprovingFont.caption(12))
                            .foregroundColor(BevelColors.textMuted)

                        // Recursos Editorial Cards (Screenshots 17, 18, 20, 23, 26, 29, 33)
                        Text("Recursos")
                            .font(ImprovingFont.sectionTitle(18))
                            .foregroundColor(BevelColors.textPrimary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(resourceCards(for: kind), id: \.2) { icon, overlayTitle, cardTitle, desc, colors in
                                    VStack(alignment: .leading, spacing: 8) {
                                        ZStack {
                                            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                                            VStack(spacing: 5) {
                                                Image(systemName: icon)
                                                    .font(.system(size: 22))
                                                    .foregroundColor(.white.opacity(0.9))
                                                Text(overlayTitle)
                                                    .font(ImprovingFont.sectionTitle(17))
                                                    .foregroundColor(.white)
                                                    .multilineTextAlignment(.center)
                                                Text("The Basics")
                                                    .font(ImprovingFont.caption(11.5))
                                                    .foregroundColor(.white.opacity(0.75))
                                            }
                                            .padding(12)
                                        }
                                        .frame(width: 235, height: 128)
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                                        Text(cardTitle)
                                            .font(ImprovingFont.cardTitle(14.5))
                                            .foregroundColor(BevelColors.textPrimary)
                                            .lineLimit(1)
                                        Text(desc)
                                            .font(ImprovingFont.caption(12))
                                            .foregroundColor(BevelColors.textSecondary)
                                            .lineLimit(2)
                                    }
                                    .frame(width: 235)
                                }
                            }
                        }

                        // Exact Educational Explanation Block (Screenshots 18, 21, 24, 27, 30, 33)
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 14))
                                    .foregroundColor(BevelColors.textSecondary)
                                Text(kind.title)
                                    .font(ImprovingFont.cardTitle(14.5))
                                    .foregroundColor(BevelColors.textSecondary)
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
            .onVerticalScrollCollapse {
                scrollCollapseSignal += 1
            }

            FloatingMetricAiCoachOverlay(
                metricKey: "\(kind.rawValue)_\(store.selectedHealthRange)",
                metricTitle: kind.title,
                insight: aiInsight,
                scrollCollapseSignal: scrollCollapseSignal,
                leadingEmoji: leadingEmoji(for: kind)
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
}

// MARK: - 2. Training Load Detail Sheet (Literal Match to Screenshots 50, 51, 52, 53)

struct TrainingLoadDetailScreen: View {
    @ObservedObject var store: ImprovingStore
    let initialTab: TrainingLoadTab
    let onBack: () -> Void

    @State private var selectedTab: TrainingLoadTab = .cardio
    @State private var selectedRange: String = "30 d"

    var body: some View {
        let isCardio = selectedTab == .cardio
        let pts: [Double] = isCardio
            ? [18, 22, 26, 31, 34, 33, 35, 36, 37, 36, 38, 37]
            : [10, 12, 14, 18, 22, 20, 17, 19, 28, 24, 26, 26]
        let dates = ["21 oct", "29 oct", "5 nov", "12 nov", "20 nov"]

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Dark Header Sheet Pane
                VStack(alignment: .leading, spacing: 14) {
                    DetailSheetHeader(title: isCardio ? "Carga cardíaca" : "Carga muscular", onBack: onBack, rightSystemIcon: "info.circle")

                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isCardio ? "37" : "26")
                                .font(ImprovingFont.displayLarge(34))
                                .monospacedDigit()
                                .foregroundColor(BevelColors.textPrimary)
                            Text(store.fullDateLabel)
                                .font(ImprovingFont.caption(13))
                                .foregroundColor(BevelColors.textSecondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(isCardio ? "Manteniéndose" : "Productivo")
                                .font(ImprovingFont.cardTitle(15))
                                .foregroundColor(isCardio ? BevelColors.greenPrimary : BevelColors.skyBlue)
                            HStack(spacing: 4) {
                                Image(systemName: "line.3.horizontal").font(.system(size: 10)).foregroundColor(BevelColors.greenPrimary)
                                Text(isCardio ? "Óptimo: 32-42" : "Óptimo: 8-19")
                                    .font(ImprovingFont.caption(13))
                                    .fontWeight(.semibold)
                                    .foregroundColor(BevelColors.textPrimary)
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    // Two Pill Tabs: [ Carga cardíaca ] [ Carga muscular ] (Screenshots 50 & 52)
                    HStack(spacing: 10) {
                        tabPill("Carga cardíaca", active: isCardio) { selectedTab = .cardio }
                        tabPill("Carga muscular", active: !isCardio) { selectedTab = .muscular }
                        Spacer()
                    }
                    .padding(.horizontal, 16)

                    HealthMetricBaselineChart(
                        points: pts,
                        dates: dates,
                        bandLow: isCardio ? 32 : 8,
                        bandHigh: isCardio ? 42 : 19,
                        averageText: "",
                        accentColor: BevelColors.textSecondary,
                        valueFormatter: { "\(Int($0))" }
                    )
                    .padding(.horizontal, 14)

                    // Range Selector: < [ 7 D | 30 d | 3 M | 1 A | YTD ] 🎚️ >
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left").font(.system(size: 13)).foregroundColor(BevelColors.textPrimary).frame(width: 30, height: 30).background(Circle().fill(Color.white.opacity(0.06)))
                        HStack(spacing: 2) {
                            ForEach(["7 D", "30 d", "3 M", "1 A", "YTD"], id: \.self) { r in
                                Button { selectedRange = r } label: {
                                    Text(r)
                                        .font(ImprovingFont.caption(12))
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
                        Image(systemName: "slider.horizontal.3").font(.system(size: 13)).foregroundColor(BevelColors.textPrimary).frame(width: 30, height: 30).background(Circle().fill(Color.white.opacity(0.06)))
                        Image(systemName: "chevron.right").font(.system(size: 13)).foregroundColor(BevelColors.textPrimary).frame(width: 30, height: 30).background(Circle().fill(Color.white.opacity(0.06)))
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                .background(BevelColors.sheetHeaderBg)

                // Exact 7-Row Desglose Table (Screenshots 50–53)
                VStack(alignment: .leading, spacing: 16) {
                    Text(isCardio ? "Desglose de la carga cardíaca" : "Desglose de la carga muscular")
                        .font(ImprovingFont.sectionTitle(18))
                        .foregroundColor(BevelColors.textPrimary)

                    BevelCard(cornerRadius: 20) {
                        VStack(spacing: 0) {
                            HStack {
                                Text("Estado").frame(width: 112, alignment: .leading)
                                Text("Duración").frame(width: 50, alignment: .leading)
                                Spacer()
                                Text("%")
                            }
                            .font(ImprovingFont.caption(12))
                            .foregroundColor(BevelColors.textMuted)
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                            .padding(.bottom, 8)

                            let rows: [(String, String, Int, Color)] = isCardio ? [
                                ("Calibrando", "0d", 0, BevelColors.textSecondary),
                                ("Desentrenamiento", "2d", 6, BevelColors.textMuted),
                                ("Pico de forma", "4d", 13, BevelColors.cyanBright),
                                ("Manteniéndose", "14d", 46, BevelColors.greenPrimary),
                                ("Productivo", "9d", 29, BevelColors.skyBlue),
                                ("Fatigado", "2d", 6, BevelColors.amberStart),
                                ("Entrenamiento excesivo", "0d", 0, BevelColors.coralHigh),
                            ] : [
                                ("Calibrando", "0d", 0, BevelColors.textSecondary),
                                ("Desentrenamiento", "3d", 10, BevelColors.textMuted),
                                ("Pico de forma", "5d", 16, BevelColors.cyanBright),
                                ("Manteniéndose", "10d", 32, BevelColors.greenPrimary),
                                ("Productivo", "11d", 36, BevelColors.skyBlue),
                                ("Entrenamiento excesivo", "2d", 6, BevelColors.coralHigh),
                            ]

                            ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                                HStack(spacing: 8) {
                                    Text(row.0)
                                        .font(ImprovingFont.body(13.5))
                                        .foregroundColor(BevelColors.textPrimary)
                                        .frame(width: 112, alignment: .leading)
                                    Text(row.1)
                                        .font(ImprovingFont.cardTitle(13.5))
                                        .monospacedDigit()
                                        .foregroundColor(BevelColors.textPrimary)
                                        .frame(width: 36, alignment: .leading)
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(Color.white.opacity(0.07)).frame(height: 6)
                                            if row.2 > 0 {
                                                Capsule().fill(row.3).frame(width: max(8, geo.size.width * CGFloat(row.2) / 100.0), height: 6)
                                            }
                                        }
                                        .frame(maxHeight: .infinity)
                                    }
                                    .frame(height: 16)
                                    Text("\(row.2)%")
                                        .font(ImprovingFont.caption(13))
                                        .monospacedDigit()
                                        .foregroundColor(BevelColors.textSecondary)
                                        .frame(width: 38, alignment: .trailing)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)

                                if idx < rows.count - 1 {
                                    Divider().background(BevelColors.divider).padding(.horizontal, 16)
                                }
                            }
                        }
                    }

                    // Recursos
                    Text("Recursos")
                        .font(ImprovingFont.sectionTitle(18))
                        .foregroundColor(BevelColors.textPrimary)

                    VStack(alignment: .leading, spacing: 8) {
                        ZStack {
                            LinearGradient(colors: isCardio ? [Color(hex: 0x3D4C5C), Color(hex: 0x1E252D)] : [Color(hex: 0x573E34), Color(hex: 0x241B18)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            VStack(spacing: 4) {
                                Image(systemName: isCardio ? "figure.run" : "safari.fill").font(.system(size: 22)).foregroundColor(.white)
                                Text(isCardio ? "Cardio Load" : "Muscular Load").font(ImprovingFont.sectionTitle(18)).foregroundColor(.white)
                                Text("The Basics").font(ImprovingFont.caption(11.5)).foregroundColor(.white.opacity(0.75))
                            }
                        }
                        .frame(width: 235, height: 124)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        Text(isCardio ? "The Basics: Cardio Load" : "The Basics: Muscular Load")
                            .font(ImprovingFont.cardTitle(14.5))
                            .foregroundColor(BevelColors.textPrimary)
                        Text(isCardio ? "Train smarter, not harder, by optimizing your cardio load." : "Train with purpose by understanding your muscular load.")
                            .font(ImprovingFont.caption(12))
                            .foregroundColor(BevelColors.textSecondary)
                    }
                    .frame(width: 235)
                }
                .padding(16)
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

// MARK: - 3. Cardio Metric Detail Sheet (Literal Match to Screenshots 54–68)

struct CardioMetricDetailScreen: View {
    @ObservedObject var store: ImprovingStore
    let route: CardioMetricRoute
    let onBack: () -> Void

    @State private var selectedActivityTab: Int = 0 // 0=Duración, 1=Distancia, 2=Desnivel, 3=Energía, 4=Ritmo

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
        .onAppear {
            selectedActivityTab = (route == .activitiesEnergy) ? 3 : 0
        }
    }

    // Screenshots 54–57: Todas las actividades
    private var activitiesOverviewView: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                DetailSheetHeader(title: "", onBack: onBack, rightSystemIcon: "ellipsis")

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("Todas las actividades")
                                .font(ImprovingFont.displayLarge(22))
                                .foregroundColor(BevelColors.textPrimary)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(BevelColors.textSecondary)
                        }
                        Text("22 oct – 20 nov 2026")
                            .font(ImprovingFont.caption(13))
                            .foregroundColor(BevelColors.textSecondary)
                        Text("Período actual vs. anterior")
                            .font(ImprovingFont.caption(12))
                            .foregroundColor(BevelColors.textMuted)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "chart.bar.fill").font(.system(size: 13)).foregroundColor(BevelColors.textMuted).frame(width: 32, height: 28)
                        Image(systemName: "chart.xyaxis.line").font(.system(size: 13)).foregroundColor(.white).frame(width: 32, height: 28).background(Capsule().fill(Color.white.opacity(0.14)))
                    }
                    .padding(3)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                }
                .padding(.horizontal, 16)

                // Horizontal Metric Selector Cards (Screenshots 54 & 56)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        let cards: [(String, String, String, Color)] = [
                            ("Duración de la ac...", "2:22:27", "↑ 20:05", BevelColors.skyBlue),
                            ("Distancia", "7,79 km", "↑ 7,79 km", BevelColors.skyBlue),
                            ("Desnivel", "80 m", "↑ 80 m", BevelColors.skyBlue),
                            ("Energía en activi...", "715 kcal", "↑ 198 kcal", BevelColors.skyBlue),
                            ("Ritmo", "4:29 /km", "↑ 0:24 /km", BevelColors.orangeEnd),
                        ]
                        ForEach(Array(cards.enumerated()), id: \.offset) { idx, c in
                            let active = selectedActivityTab == idx
                            Button { selectedActivityTab = idx } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(c.0).font(ImprovingFont.caption(12)).foregroundColor(BevelColors.textSecondary).lineLimit(1)
                                    Text(c.1).font(ImprovingFont.metricTile(19)).monospacedDigit().foregroundColor(BevelColors.textPrimary)
                                    Text(c.2).font(ImprovingFont.caption(12)).fontWeight(.semibold).foregroundColor(c.3)
                                }
                                .padding(13)
                                .frame(width: 138, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 16).fill(BevelColors.card))
                                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(active ? Color.white.opacity(0.45) : BevelColors.cardBorder, lineWidth: active ? 1.3 : 0.8))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                SteppedCumulativeComparisonChart(
                    currentPoints: selectedActivityTab == 3 ? [0, 0, 210, 210, 210, 380, 420, 715, 715] : [0, 0, 0.7, 0.7, 0.7, 1.1, 1.3, 2.3, 2.3],
                    previousPoints: selectedActivityTab == 3 ? [0, 240, 490, 490, 490, 490, 490, 490, 490] : [0, 0.9, 1.9, 1.9, 1.9, 1.9, 1.9, 1.9, 1.9],
                    accentColor: BevelColors.cyanBright,
                    rightLabels: selectedActivityTab == 3 ? ["789", "526", "263", "0"] : ["3,0h", "2,0h", "1,0h", "0"],
                    bottomDates: ["21 oct", "29 oct", "5 nov", "12 nov", "20 nov"],
                    height: 164
                )
                .padding(.horizontal, 16)

                Text("Total acumulado en el periodo seleccionado, por días.")
                    .font(ImprovingFont.caption(12))
                    .foregroundColor(BevelColors.textMuted)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
            .background(BevelColors.sheetHeaderBg)

            // Historial de actividad grouped by month (Screenshots 55 & 57)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Historial de actividad").font(ImprovingFont.sectionTitle(18)).foregroundColor(BevelColors.textPrimary)
                    Spacer()
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 13))
                        .foregroundColor(BevelColors.textPrimary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(BevelColors.card))
                }

                Text("noviembre de 2026").font(ImprovingFont.caption(13.5)).foregroundColor(BevelColors.textSecondary)

                activityHistoryRow(icon: "figure.strengthtraining.traditional", iconColor: BevelColors.amberStart, date: "18 nov, 15:08", title: "Entrenamiento de fuerza tradicional", meta: "○ 25%   🔥 300 kcal")
                activityHistoryRow(icon: "bicycle", iconColor: BevelColors.periwinkleStart, date: "12 nov, 13:21", title: "Bici al aire libre", meta: "○ 20%   1,61 km   🔥 38 kcal")
                activityHistoryRow(icon: "bicycle", iconColor: BevelColors.periwinkleStart, date: "12 nov, 10:58", title: "Bici al aire libre", meta: "○ 19%   1,79 km   🔥 48 kcal")
                activityHistoryRow(icon: "bicycle", iconColor: BevelColors.periwinkleStart, date: "11 nov, 19:56", title: "Bici al aire libre", meta: "○ 18%   2,10 km   🔥 52 kcal")

                Text("octubre de 2026").font(ImprovingFont.caption(13.5)).foregroundColor(BevelColors.textSecondary).padding(.top, 6)
                activityHistoryRow(icon: "figure.strengthtraining.traditional", iconColor: BevelColors.amberStart, date: "30 oct, 20:16", title: "Entrenamiento de fuerza tradicional", meta: "○ 35%   🔥 217 kcal")
            }
            .padding(16)
        }
    }

    private func activityHistoryRow(icon: String, iconColor: Color, date: String, title: String, meta: String) -> some View {
        BevelCard(cornerRadius: 18) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(iconColor)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(iconColor.opacity(0.16)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(date).font(ImprovingFont.caption(12)).foregroundColor(BevelColors.textMuted)
                    Text(title).font(ImprovingFont.cardTitle(15)).foregroundColor(BevelColors.textPrimary)
                    Text(meta).font(ImprovingFont.caption(12.5)).foregroundColor(BevelColors.textSecondary)
                }
                Spacer()
            }
            .padding(14)
        }
    }

    // Screenshots 58–60: VO2 máx.
    private var vo2MaxDetailView: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                DetailSheetHeader(title: "VO₂ máx.", onBack: onBack, rightSystemIcon: "ellipsis")
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "%.1f", locale: Locale(identifier: "es_ES"), store.vo2Max))
                            .font(ImprovingFont.displayLarge(34))
                            .foregroundColor(BevelColors.textPrimary)
                        Text(store.fullDateLabel).font(ImprovingFont.caption(13)).foregroundColor(BevelColors.textSecondary)
                    }
                    Spacer()
                    Text("Aceptable").font(ImprovingFont.cardTitle(16)).foregroundColor(BevelColors.amberStart)
                }
                .padding(.horizontal, 16)

                HealthMetricBaselineChart(
                    points: [43.2, 43.4, 43.6, 43.8, 44.0, 44.2, store.vo2Max],
                    dates: ["21 oct", "29 oct", "5 nov", "12 nov", "20 nov"],
                    bandLow: 40.1,
                    bandHigh: 48.0,
                    averageText: "",
                    accentColor: BevelColors.amberStart,
                    valueFormatter: { String(format: "%.1f", locale: Locale(identifier: "es_ES"), $0) }
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
            .background(BevelColors.sheetHeaderBg)

            VStack(alignment: .leading, spacing: 16) {
                FiveSegmentRangeBar(
                    labels: ["<40,1", "40,1", "48,0", "55,2", ">61,8"],
                    activeSegmentIndex: 1,
                    activeColor: BevelColors.amberStart,
                    pointerFraction: 0.31,
                    rangeTitle: "Aceptable",
                    subtitle: "Estandarizado para 20 - 29 hombres",
                    footerDate: "Último dato el \(store.fullDateLabel)"
                )

                Text("¿Qué es el VO₂ máx.?").font(ImprovingFont.sectionTitle(18)).foregroundColor(BevelColors.textPrimary)
                BevelCard(cornerRadius: 18) {
                    Text("El VO₂ máx. mide el volumen máximo de oxígeno que tu cuerpo puede usar durante un ejercicio intenso. Es un indicador clave de la forma física cardiovascular y la longevidad.")
                        .font(ImprovingFont.body(14))
                        .foregroundColor(BevelColors.textSecondary)
                        .padding(16)
                }
            }
            .padding(16)
        }
    }

    // Screenshots 61–62: Recuperación de FC (HRR)
    private var hrRecoveryDetailView: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                DetailSheetHeader(title: "Recuperación de FC", onBack: onBack, rightSystemIcon: "ellipsis")
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("27 ppm").font(ImprovingFont.displayLarge(34)).foregroundColor(BevelColors.textPrimary)
                        Text(store.fullDateLabel).font(ImprovingFont.caption(13)).foregroundColor(BevelColors.textSecondary)
                    }
                    Spacer()
                    Text("Aceptable").font(ImprovingFont.cardTitle(16)).foregroundColor(BevelColors.amberStart)
                }
                .padding(.horizontal, 16)

                HealthMetricBaselineChart(
                    points: [38, 35, 34, 31, 29, 27],
                    dates: ["21 oct", "29 oct", "5 nov", "12 nov", "20 nov"],
                    bandLow: 15,
                    bandHigh: 40,
                    averageText: "Prom. 34 ppm",
                    accentColor: BevelColors.coralHigh,
                    valueFormatter: { "\(Int($0)) ppm" }
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
            .background(BevelColors.sheetHeaderBg)

            VStack(alignment: .leading, spacing: 16) {
                FiveSegmentRangeBar(
                    labels: ["<15,0", "15,0", "32,0", "40,0", ">49,0"],
                    activeSegmentIndex: 1,
                    activeColor: BevelColors.amberStart,
                    pointerFraction: 0.34,
                    rangeTitle: "Aceptable",
                    subtitle: "Estandarizado para 0 - 29",
                    footerDate: "Último dato el \(store.fullDateLabel)"
                )

                Text("¿Qué es la recuperación de la frecuencia cardíaca?").font(ImprovingFont.sectionTitle(18)).foregroundColor(BevelColors.textPrimary)
                BevelCard(cornerRadius: 18) {
                    Text("La recuperación de la frecuencia cardíaca (HRR) mide la rapidez con la que tu frecuencia cardíaca vuelve a los valores normales después de hacer ejercicio. Una HRR más rápida es señal de buena salud cardíaca.")
                        .font(ImprovingFont.body(14))
                        .foregroundColor(BevelColors.textSecondary)
                        .padding(16)
                }
            }
            .padding(16)
        }
    }

    // Screenshots 63–65: Foco cardiovascular
    private var cardioFocusDetailView: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                DetailSheetHeader(title: "Foco cardiovascular", onBack: onBack, rightSystemIcon: "ellipsis")
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Aeróbico bajo").font(ImprovingFont.displayLarge(28)).foregroundColor(BevelColors.textPrimary)
                        Text(store.fullDateLabel).font(ImprovingFont.caption(13)).foregroundColor(BevelColors.textSecondary)
                    }
                    Spacer()
                    Text("95 %").font(ImprovingFont.sectionTitle(18)).foregroundColor(BevelColors.tealLow)
                }
                .padding(.horizontal, 16)

                // Vertical Stacked Cyan/Blue Bars (Screenshot 63)
                HStack(alignment: .bottom, spacing: 22) {
                    Spacer()
                    RoundedRectangle(cornerRadius: 4).fill(BevelColors.cyanBright).frame(width: 10, height: 142)
                    Spacer()
                    HStack(alignment: .bottom, spacing: 6) {
                        VStack(spacing: 0) {
                            RoundedRectangle(cornerRadius: 3).fill(BevelColors.skyBlue).frame(width: 10, height: 14)
                            RoundedRectangle(cornerRadius: 3).fill(BevelColors.cyanBright).frame(width: 10, height: 64)
                        }
                        RoundedRectangle(cornerRadius: 4).fill(BevelColors.cyanBright).frame(width: 10, height: 56)
                    }
                    Spacer()
                }
                .frame(height: 158, alignment: .bottom)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .background(BevelColors.sheetHeaderBg)

            VStack(alignment: .leading, spacing: 16) {
                Text("Desglose del foco cardiovascular").font(ImprovingFont.sectionTitle(18)).foregroundColor(BevelColors.textPrimary)
                BevelCard(cornerRadius: 20) {
                    VStack(spacing: 14) {
                        focusRow("Aeró. bajo", val: "33", pct: 95, color: BevelColors.tealLow)
                        Divider().background(BevelColors.divider)
                        focusRow("Aeró. alto", val: "2", pct: 5, color: BevelColors.skyBlue)
                        Divider().background(BevelColors.divider)
                        focusRow("Anaeróbico", val: "0", pct: 0, color: BevelColors.periwinkleStart)
                    }
                    .padding(16)
                }

                Text("¿Qué es el foco cardiovascular?").font(ImprovingFont.sectionTitle(18)).foregroundColor(BevelColors.textPrimary)
                BevelCard(cornerRadius: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("El foco cardiovascular muestra la división en zonas aeróbicas durante tus ejercicios utilizando tu VO₂ máx. e intensidad.")
                            .font(ImprovingFont.body(13.5))
                            .foregroundColor(BevelColors.textSecondary)
                        bulletInfo(color: BevelColors.tealLow, title: "Aeróbico bajo:", body: "esfuerzos de baja intensidad pero prolongados a ritmo de conversación.")
                        bulletInfo(color: BevelColors.skyBlue, title: "Aeróbico alto:", body: "esfuerzos de intensidad moderadamente alta a alta donde tu FC se mantiene elevada.")
                        bulletInfo(color: BevelColors.periwinkleStart, title: "Anaeróbico:", body: "esfuerzos cortos de alta intensidad como intervalos o series HIIT.")
                    }
                    .padding(16)
                }
            }
            .padding(16)
        }
    }

    // Screenshots 66–68: Zonas de frecuencia cardíaca
    private var hrZonesDetailView: some View {
        let zones: [(String, CGFloat, Color, String)] = [
            ("Z0", 6, BevelColors.periwinkleStart, "Histórico basal de menor intensidad."),
            ("Z1", 150, Color(hex: 0x5A84F8), "Recuperación activa para calentamiento y enfriamiento."),
            ("Z2", 78, BevelColors.greenPrimary, "Esfuerzo sostenido que desarrolla resistencia y oxidación de grasas."),
            ("Z3", 36, BevelColors.amberStart, "Esfuerzo moderado que mejora la capacidad cardiovascular."),
            ("Z4", 6, BevelColors.redAlert, "Alta intensidad para sprints e intervalos."),
            ("Z5", 4, Color(hex: 0xA855F7), "Esfuerzo máximo para ráfagas cortas e intensas."),
        ]

        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                DetailSheetHeader(title: "Zonas de frecuencia cardíaca", onBack: onBack, rightSystemIcon: "ellipsis")
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Zona 1").font(ImprovingFont.displayLarge(28)).foregroundColor(BevelColors.textPrimary)
                        Text(store.fullDateLabel).font(ImprovingFont.caption(13)).foregroundColor(BevelColors.textSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("45 min").font(ImprovingFont.sectionTitle(16.5)).foregroundColor(BevelColors.skyBlue)
                        Text("101–121 ppm").font(ImprovingFont.caption(13)).foregroundColor(BevelColors.textSecondary)
                    }
                }
                .padding(.horizontal, 16)

                // 6 Vertical Gradient Zone Bars (Screenshot 66)
                HStack(alignment: .bottom, spacing: 14) {
                    ForEach(zones, id: \.0) { label, h, color, _ in
                        VStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(LinearGradient(colors: [color, color.opacity(0.65)], startPoint: .top, endPoint: .bottom))
                                .frame(height: h)
                            HStack(spacing: 4) {
                                Circle().fill(color).frame(width: 6, height: 6)
                                Text(label).font(ImprovingFont.caption(11.5)).foregroundColor(BevelColors.textPrimary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 178, alignment: .bottom)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .background(BevelColors.sheetHeaderBg)

            VStack(alignment: .leading, spacing: 14) {
                Text("¿Qué son las zonas de frecuencia cardíaca?").font(ImprovingFont.sectionTitle(18)).foregroundColor(BevelColors.textPrimary)
                BevelCard(cornerRadius: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Las zonas de frecuencia cardíaca representan diferentes niveles de intensidad de ejercicio, desde el descanso hasta el esfuerzo máximo.")
                            .font(ImprovingFont.body(13.5))
                            .foregroundColor(BevelColors.textSecondary)
                        ForEach(zones, id: \.0) { label, _, color, desc in
                            bulletInfo(color: color, title: "Zona \(label.dropFirst()):", body: desc)
                        }
                    }
                    .padding(16)
                }
            }
            .padding(16)
        }
    }

    private func focusRow(_ label: String, val: String, pct: Int, color: Color) -> some View {
        HStack(spacing: 10) {
            Text(label).font(ImprovingFont.body(14)).foregroundColor(BevelColors.textPrimary).frame(width: 82, alignment: .leading)
            Text(val).font(ImprovingFont.cardTitle(14)).foregroundColor(BevelColors.textPrimary).frame(width: 30, alignment: .leading)
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

    private func bulletInfo(color: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(color).frame(width: 7, height: 7).padding(.top, 6)
            Text("\(title) \(body)")
                .font(ImprovingFont.body(13.5))
                .foregroundColor(BevelColors.textSecondary)
        }
    }
}

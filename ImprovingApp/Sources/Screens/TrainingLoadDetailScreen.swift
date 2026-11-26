import SwiftUI

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
    @State private var scrollCollapseSignal: Int = 0

    private var spanDays: Int {
        FitnessRangeControlBar.spanDays(for: selectedRange, anchorDate: store.selectedDate)
    }

    private var resourcesForTab: [FitnessResourceItem] {
        if selectedTab == .cardio {
            return [
                FitnessResourceItem(
                    id: "res_cardio_basics",
                    badgeIcon: "shoeprints.fill",
                    heroTitle: "Carga cardíaca",
                    heroSubtitle: "Fundamentos",
                    cardTitle: "Fundamentos: Carga cardiovascular",
                    cardDescription: "Entrena con inteligencia optimizando tu carga cardiovascular.",
                    gradientHexA: 0x385468,
                    gradientHexB: 0x5B4B3F,
                    fullGuideBody: "La Carga Cardíaca compara tu esfuerzo cardiovascular agudo de los últimos 7 días frente a tu base crónica de los últimos 28 días. Mantenerte dentro de la banda verde óptima te permite mejorar tu capacidad aeróbica y tu VO₂ máx. sin acumular fatiga innecesaria."
                ),
                FitnessResourceItem(
                    id: "res_cardio_status",
                    badgeIcon: "bicycle",
                    heroTitle: "Estado cardíaco",
                    heroSubtitle: "Zonas de entreno",
                    cardTitle: "Estado cardiovascular",
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
                    heroTitle: "Carga muscular",
                    heroSubtitle: "Fundamentos",
                    cardTitle: "Fundamentos: Carga muscular",
                    cardDescription: "Entrena fuerza con propósito controlando tu volumen y fatiga.",
                    gradientHexA: 0x4A3D36,
                    gradientHexB: 0x23262E,
                    fullGuideBody: "La Carga Muscular integra tus sesiones de fuerza registradas en Apple Salud junto con las series y el volumen (kg) que anotes en Improving. Al respetar la franja óptima verde favoreces la hipertrofia y la fuerza reduciendo el riesgo de sobrecarga articular."
                ),
                FitnessResourceItem(
                    id: "res_musc_fresh",
                    badgeIcon: "battery.75percent",
                    heroTitle: "Frescura muscular",
                    heroSubtitle: "Fundamentos",
                    cardTitle: "Fundamentos: Frescura muscular",
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
            .onVerticalScrollCollapse { scrollCollapseSignal += 1 }

            FloatingMetricAiCoachOverlay(
                metricKey: "tl_\(selectedTab.rawValue)_\(selectedRange)_\(windowPageOffset)",
                metricTitle: isCardio ? "Carga cardíaca" : "Carga muscular",
                insight: aiInsight,
                scrollCollapseSignal: scrollCollapseSignal,
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

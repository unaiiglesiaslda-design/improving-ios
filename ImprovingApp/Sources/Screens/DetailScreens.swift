import SwiftUI

// MARK: - Top Detail Modal Sheet Header

struct DetailSheetHeader: View {
    let title: String
    let onBack: () -> Void
    var rightSystemIcon: String? = nil
    var onRightAction: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(BevelColors.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(BevelColors.glassChromeFill))
                    .overlay(Circle().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.8))
            }
            Spacer()
            Text(title)
                .font(ImprovingFont.sectionTitle(16.5))
                .foregroundColor(BevelColors.textPrimary)
                .lineLimit(1)
            Spacer()
            if let icon = rightSystemIcon {
                Button {
                    onRightAction?()
                } label: {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(BevelColors.textPrimary)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(BevelColors.glassChromeFill))
                        .overlay(Circle().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.8))
                }
            } else {
                Spacer().frame(width: 38)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Metric Methodology Guide Sheet (P1 — Real info.circle Explanation per Pillar)

enum PillarInfoKind: String, Identifiable {
    case strain
    case recovery
    case sleep
    case stress
    case energy
    case biologicalAge

    var id: String { rawValue }

    var navTitle: String {
        switch self {
        case .strain: return "Guía de Esfuerzo"
        case .recovery: return "Guía de Recuperación"
        case .sleep: return "Guía de Sueño"
        case .stress: return "Guía de Estrés"
        case .energy: return "Guía de Energía"
        case .biologicalAge: return "Edad Biológica"
        }
    }

    var headline: String {
        switch self {
        case .strain: return "Cómo se calcula tu Esfuerzo (0–100% y Strain 0–21)"
        case .recovery: return "Cómo se calcula tu Recuperación autonómica"
        case .sleep: return "Cómo se calcula tu Puntuación del Sueño"
        case .stress: return "Cómo medimos tu Estrés fisiológico"
        case .energy: return "Cómo funciona tu Batería Corporal"
        case .biologicalAge: return "Cómo estimamos tu Edad Biológica"
        }
    }

    var accent: Color {
        switch self {
        case .strain: return BevelColors.amberStart
        case .recovery: return BevelColors.greenPrimary
        case .sleep: return BevelColors.periwinkleStart
        case .stress: return BevelColors.tealLow
        case .energy: return BevelColors.limeStart
        case .biologicalAge: return BevelColors.bioTeal
        }
    }

    var summary: String {
        switch self {
        case .strain:
            return "Evalúa la carga cardiovascular y muscular acumulada en el día usando un modelo logarítmico tipo Banister TRIMP calibrado a tu FC máxima (fórmula de Tanaka), zonas cardíacas, calorías activas y sesiones registradas."
        case .recovery:
            return "Mide cuán preparado está tu sistema nervioso para asimilar carga comparando tu VFC nocturna (RMSSD/SDNN) y FC en reposo frente a tu propia línea base móvil de 60 días, ajustado por frecuencia respiratoria, SpO₂ y temperatura."
        case .sleep:
            return "Combina tu duración neta frente a tu meta fisiológica personalizada, la proporción de fases reparadoras (Sueño profundo y REM), la eficiencia en cama, la continuidad y el descenso nocturno de la frecuencia cardíaca."
        case .stress:
            return "Analiza tus muestras intradía de pulso y VFC en bloques de 5 minutos para estimar la activación del sistema nervioso simpático (0–34 bajo, 35–64 moderado, 65–100 alto), diferenciando descanso y carga."
        case .energy:
            return "Integra una curva continua de 24 horas entre días: se recarga durante el sueño reparador (incluso si el Apple Watch está en modo ahorro) y se descarga en función del estrés sostenido, el esfuerzo y los entrenamientos."
        case .biologicalAge:
            return "Integra tus promedios reales de 30 días (sueño, actividad, VO₂ máx., FC en reposo, VFC y composición corporal) junto con tus analíticas de sangre frente a referencias clínicas ajustadas a tu edad cronológica y sexo."
        }
    }

    var bullets: [(icon: String, title: String, detail: String)] {
        switch self {
        case .strain:
            return [
                ("target", "Zona óptima personalizada y continua", "Combina de forma continua tu Recuperación de hoy con tu media real de Esfuerzo de 28 días, tu Carga Cardíaca (EWMA) y tu deuda de sueño."),
                ("heart.fill", "Zonas Z1–Z5", "Los minutos en zonas altas (Z4–Z5) suman exponencialmente más carga que actividad ligera."),
                ("dumbbell.fill", "Fuerza + Cardio", "Combina sesiones de gimnasio, volumen en kg y carga cardiovascular.")
            ]
        case .recovery:
            return [
                ("waveform.path.ecg", "Línea base personal (60 d)", "No te compara con promedios genéricos sino contra tus propias noches recientes."),
                ("checkmark.seal.fill", "Escala semafórica", "Verde (67–100%) listo para exigirte · Ámbar (34–66%) entreno moderado · Rojo (<34%) prioriza descanso."),
                ("applewatch", "Resiliencia en modo ahorro", "Si faltan sensores puntuales, recalcula con las señales reales disponibles sin inventar datos.")
            ]
        case .sleep:
            return [
                ("bed.double.fill", "Sueño neto vs en cama", "Solo cuenta el tiempo realmente dormido; los despertares reducen la eficiencia."),
                ("moon.stars.fill", "Fases reparadoras", "Profundo repara tejido muscular y sistema inmune; REM consolida memoria y foco."),
                ("alarm.fill", "Deuda de sueño", "Suma las horas faltantes para recomendarte tu hora óptima de acostarte hoy.")
            ]
        case .stress:
            return [
                ("waveform.path", "Resolución cada 5 min", "Detecta picos de activación por reuniones, cafeína, digestiones pesadas o entrenos."),
                ("moon.zzz.fill", "Estrés nocturno", "Un estrés bajo durante el sueño (<18) acelera la recarga de tu Batería Corporal."),
                ("lungs.fill", "Nota fisiológica", "El estrés fisiológico también sube al entrenar o comer copiosamente; no siempre es estrés mental.")
            ]
        case .energy:
            return [
                ("battery.100percent.bolt", "Continuidad entre días", "Tu batería a las 00:00 parte exactamente del nivel con el que cerraste ayer."),
                ("arrow.up.circle.fill", "Recarga nocturna", "Un sueño eficiente con buena recuperación puede sumar entre +35% y +65% de carga."),
                ("flame.fill", "Descarga activa", "Entrenamientos intensos y picos prolongados de estrés consumen reservas más rápido.")
            ]
        case .biologicalAge:
            return [
                ("heart.circle.fill", "Impacto transparente por apartado", "Cada sección muestra exactamente cuántos años resta (−) o suma (+) a tu edad cronológica."),
                ("cross.case.fill", "Analíticas de sangre (tipo PhenoAge)", "Marcadores como HbA1c, glucosa, PCR, lípidos (HDL/LDL/ApoB), ferritina, vitamina D o función renal/hepática ajustan hasta −3,5 / +4,5 años."),
                ("scalemass.fill", "Actualización viva", "Mejora progresivamente al sostener 30+ días de buen sueño, pasos, VFC, VO₂ máx. y biomarcadores óptimos.")
            ]
        }
    }
}

struct MetricMethodologyInfoSheet: View {
    let kind: PillarInfoKind
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    BevelCard(cornerRadius: 20) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(kind.headline)
                                .font(ImprovingFont.sectionTitle(18))
                                .foregroundColor(BevelColors.textPrimary)
                            Text(kind.summary)
                                .font(ImprovingFont.body(14))
                                .foregroundColor(BevelColors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)
                    }

                    ForEach(Array(kind.bullets.enumerated()), id: \.offset) { _, b in
                        BevelCard(cornerRadius: 18) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: b.icon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(kind.accent)
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(kind.accent.opacity(0.15)))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(b.title)
                                        .font(ImprovingFont.cardTitle(14.5))
                                        .foregroundColor(BevelColors.textPrimary)
                                    Text(b.detail)
                                        .font(ImprovingFont.body(13))
                                        .foregroundColor(BevelColors.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(14)
                        }
                    }
                }
                .padding(16)
            }
            .background(BevelColors.canvas)
            .navigationTitle(kind.navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar", action: onClose)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - 1. Esfuerzo Detail Screen

struct EsfuerzoScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void
    let onOpenTrend: (EffortTrendItem) -> Void
    var onOpenWorkout: ((EffortEventItem) -> Void)? = nil

    @State private var showShareSheet: Bool = false
    @State private var showInfoSheet: Bool = false

    var body: some View {
        let avail = store.dataAvailability
        let totalActiveMin = store.workoutsToday.reduce(0) { $0 + $1.durationMin }
        let activeTimeText: String = {
            if totalActiveMin > 0 {
                return "\(totalActiveMin / 60) h \(String(format: "%02d", totalActiveMin % 60)) min"
            }
            return "--"
        }()

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AtmosphericHeroHeader(
                    title: "Esfuerzo",
                    subtitle: store.dateLabel,
                    style: .strain,
                    onBack: onBack,
                    onPrevDay: { store.shiftDay(1) },
                    onNextDay: { if store.dayOffset > 0 { store.shiftDay(-1) } },
                    canGoNextDay: store.dayOffset > 0,
                    onRightPrimary: { showShareSheet = true },
                    onRightSecondary: { showInfoSheet = true }
                ) {
                    BevelRecessedRingGauge(
                        progress: avail.hasStrainData ? Double(store.strainPercent) / 100.0 : 0.0,
                        centerText: "\(avail.hasStrainData ? store.strainPercent : 0)%",
                        label: "",
                        kind: .strain,
                        size: 170,
                        strokeWidth: 16,
                        subLabel: "Objetivo: \(store.effortTargetRangeText)",
                        centerSubtitle: store.strainStatusText,
                        targetRange: store.optimalEffortRange,
                        hasData: avail.hasStrainData,
                        showZeroBaselineArc: true
                    )
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        HeaderedMetricCard(
                            icon: "flame.fill",
                            title: "Strain (0–21)",
                            value: String(format: "%.1f", locale: Locale(identifier: "es_ES"), avail.hasStrainData ? store.strain21 : 0.0)
                        )
                        HeaderedMetricCard(icon: "clock.fill", title: "Tiempo activo", value: totalActiveMin > 0 ? activeTimeText : "0 min")
                    }

                    HStack(spacing: 7) {
                        Image(systemName: "scope")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(BevelColors.amberStart)
                        Text(store.effortTargetCalibrationCaption)
                            .font(ImprovingFont.caption(12))
                            .foregroundColor(BevelColors.textSecondary)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(BevelColors.card))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(BevelColors.cardBorder, lineWidth: 0.7))

                    LiveAiCoachingCard(section: .esfuerzo, store: store)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Cronología del esfuerzo")
                            .font(ImprovingFont.sectionTitle(18))
                            .foregroundColor(BevelColors.textPrimary)
                        Text("\(store.workoutsToday.count) evento(s)")
                            .font(ImprovingFont.caption(12.5))
                            .foregroundColor(BevelColors.textMuted)
                    }

                    BevelCard(cornerRadius: 20) {
                        VStack(spacing: 14) {
                            if store.workoutsToday.isEmpty {
                                Text("Sin esfuerzo registrado todavía · Tu rango óptimo hoy es \(store.effortTargetRangeText).")
                                    .font(ImprovingFont.body(13.5))
                                    .foregroundColor(BevelColors.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                ForEach(store.workoutsToday) { w in
                                    Button {
                                        onOpenWorkout?(w)
                                    } label: {
                                        let st = WorkoutSportStyle.resolve(title: w.title, category: w.categoryLabel)
                                        HStack(spacing: 12) {
                                            Image(systemName: st.icon)
                                                .font(.system(size: 16, weight: .bold))
                                                .foregroundColor(st.fg)
                                                .frame(width: 40, height: 40)
                                                .background(Circle().fill(st.bg))
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(w.timeRange).font(ImprovingFont.caption(11.5)).foregroundColor(BevelColors.textMuted)
                                                Text(w.title).font(ImprovingFont.cardTitle(15)).foregroundColor(BevelColors.textPrimary)
                                                let parts = [
                                                    "○ \(w.strainPct)%",
                                                    w.kcal > 0 ? "🔥 \(w.kcal) kcal" : nil,
                                                    w.avgHrBpm > 0 ? "♡ \(w.avgHrBpm) ppm" : nil
                                                ].compactMap { $0 }.joined(separator: "   ")
                                                Text(parts)
                                                    .font(ImprovingFont.caption(12))
                                                    .foregroundColor(BevelColors.textSecondary)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundColor(BevelColors.textMuted)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(16)
                    }

                    Text("Tendencias")
                        .font(ImprovingFont.sectionTitle(18))
                        .foregroundColor(BevelColors.textPrimary)
                        .padding(.top, 4)

                    let effortIcons = ["gauge.with.dots.needle.67percent", "timer", "heart.fill", "flame.fill", "shoeprints.fill", "target"]
                    ForEach(Array(store.effortTrends.enumerated()), id: \.element.id) { idx, item in
                        BevelTrendLightCard(
                            trend: item,
                            systemIcon: effortIcons[idx % effortIcons.count],
                            onClick: { onOpenTrend(item) }
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 150)
        }
        .background(BevelColors.canvas)
        .sheet(isPresented: $showShareSheet) {
            ShareSummaryCardSheet(store: store, kind: .strain, onClose: { showShareSheet = false })
        }
        .sheet(isPresented: $showInfoSheet) {
            MetricMethodologyInfoSheet(kind: .strain, onClose: { showInfoSheet = false })
        }
    }
}

// MARK: - 2. Recuperación Detail Screen

struct RecuperacionScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void
    let onSelectHealthMetric: (HealthMetricKind) -> Void
    let onOpenSleepSession: () -> Void
    var onOpenTrend: ((EffortTrendItem) -> Void)? = nil

    @State private var showShareSheet: Bool = false
    @State private var showInfoSheet: Bool = false

    var body: some View {
        let avail = store.dataAvailability
        let sess = store.currentDaySummary?.sleepSession

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AtmosphericHeroHeader(
                    title: "Recuperación",
                    subtitle: store.dateLabel,
                    style: .recovery,
                    onBack: onBack,
                    onPrevDay: { store.shiftDay(1) },
                    onNextDay: { if store.dayOffset > 0 { store.shiftDay(-1) } },
                    canGoNextDay: store.dayOffset > 0,
                    onRightPrimary: { showShareSheet = true },
                    onRightSecondary: { showInfoSheet = true }
                ) {
                    BevelRecessedRingGauge(
                        progress: Double(store.recoveryPercent) / 100.0,
                        centerText: "\(store.recoveryPercent)%",
                        label: "",
                        kind: .recovery,
                        size: 170,
                        strokeWidth: 16,
                        centerSubtitle: avail.hasRecoveryData ? store.recoveryStatusText : "Sin datos",
                        hasData: avail.hasRecoveryData
                    )
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        HeaderedMetricCard(
                            icon: "waveform.path.ecg",
                            title: "VFC en reposo",
                            value: avail.hasHrvData ? String(format: "%.1f", locale: Locale(identifier: "es_ES"), store.hrvMs) : "--",
                            unit: "ms",
                            onClick: { onSelectHealthMetric(.hrv) }
                        )
                        HeaderedMetricCard(
                            icon: "heart.fill",
                            title: "FC en reposo",
                            value: avail.hasRestingHrData ? String(format: "%.1f", locale: Locale(identifier: "es_ES"), store.restingHrBpm) : "--",
                            unit: "ppm",
                            onClick: { onSelectHealthMetric(.restingHeartRate) }
                        )
                    }

                    LiveAiCoachingCard(section: .recuperacion, store: store)

                    // Cronología de la recuperación (only when sleep exists)
                    if avail.hasSleepData {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Cronología de la recuperación")
                                .font(ImprovingFont.sectionTitle(18))
                                .foregroundColor(BevelColors.textPrimary)
                            Text("1 evento")
                                .font(ImprovingFont.caption(12.5))
                                .foregroundColor(BevelColors.textMuted)
                        }

                        Button(action: onOpenSleepSession) {
                            BevelCard(cornerRadius: 20) {
                                HStack(spacing: 12) {
                                    Image(systemName: "moon.stars.fill")
                                        .font(.system(size: 17))
                                        .foregroundColor(BevelColors.periwinkleStart)
                                        .frame(width: 42, height: 42)
                                        .background(Circle().fill(BevelColors.indigoSoftBg))
                                    VStack(alignment: .leading, spacing: 2) {
                                        if let t = sess?.endTimeLabel ?? sess?.startTimeLabel {
                                            Text(t).font(ImprovingFont.caption(12)).foregroundColor(BevelColors.textMuted)
                                        }
                                        Text("Sueño principal").font(ImprovingFont.cardTitle(15)).foregroundColor(BevelColors.textPrimary)
                                        Text("○ \(store.sleepPercent)%   🛏 \(store.sleepDurationText)")
                                            .font(ImprovingFont.caption(12.5))
                                            .foregroundColor(BevelColors.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.right").font(.system(size: 12)).foregroundColor(BevelColors.textMuted)
                                }
                                .padding(16)
                            }
                        }
                    }

                    Text("Tendencias")
                        .font(ImprovingFont.sectionTitle(18))
                        .foregroundColor(BevelColors.textPrimary)
                        .padding(.top, 4)

                    let recIcons = ["leaf.fill", "waveform.path.ecg", "heart.fill", "lungs.fill", "drop.fill", "thermometer.medium"]
                    ForEach(Array(store.recoveryTrends.enumerated()), id: \.element.id) { idx, item in
                        BevelTrendLightCard(
                            trend: item,
                            systemIcon: recIcons[idx % recIcons.count],
                            onClick: {
                                switch item.id {
                                case "r_hrv": onSelectHealthMetric(.hrv)
                                case "r_rhr": onSelectHealthMetric(.restingHeartRate)
                                case "r_resp": onSelectHealthMetric(.respiratoryRate)
                                case "r_spo2": onSelectHealthMetric(.oxygenSaturation)
                                case "r_temp": onSelectHealthMetric(.wristTemperature)
                                default: onOpenTrend?(item)
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 150)
        }
        .background(BevelColors.canvas)
        .sheet(isPresented: $showShareSheet) {
            ShareSummaryCardSheet(store: store, kind: .recovery, onClose: { showShareSheet = false })
        }
        .sheet(isPresented: $showInfoSheet) {
            MetricMethodologyInfoSheet(kind: .recovery, onClose: { showInfoSheet = false })
        }
    }
}

// MARK: - 3. Sueño Detail Screen

struct SuenoDetailScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void
    let onOpenSleepNeed: () -> Void
    let onOpenSleepSession: () -> Void
    var onOpenTrend: ((EffortTrendItem) -> Void)? = nil

    @State private var showShareSheet: Bool = false

    var body: some View {
        let avail = store.dataAvailability
        let sess = store.currentDaySummary?.sleepSession
        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: store.userProfile)
        let baseNeedMin = Int((norms.sleepTargetHours * 60.0).rounded())
        let debt = store.currentDaySummary?.sleepDebtMinutes ?? 0
        let needMin = baseNeedMin + debt + (store.strainPercent > 75 ? 25 : 0)
        let needText = "\(needMin / 60) h \(String(format: "%02d", needMin % 60)) min"

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AtmosphericHeroHeader(
                    title: "Sueño",
                    subtitle: store.dateLabel,
                    style: .sleep,
                    onBack: onBack,
                    onPrevDay: { store.shiftDay(1) },
                    onNextDay: { if store.dayOffset > 0 { store.shiftDay(-1) } },
                    canGoNextDay: store.dayOffset > 0,
                    rightPrimaryIcon: "square.and.arrow.up",
                    onRightPrimary: { showShareSheet = true },
                    rightSecondaryIcon: "alarm.fill",
                    onRightSecondary: onOpenSleepNeed
                ) {
                    BevelRecessedRingGauge(
                        progress: Double(store.sleepPercent) / 100.0,
                        centerText: "\(store.sleepPercent)%",
                        label: "",
                        kind: .sleep,
                        size: 170,
                        strokeWidth: 16,
                        centerSubtitle: avail.hasSleepData ? store.sleepStatusText : "Sin datos",
                        hasData: avail.hasSleepData
                    )
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        HeaderedMetricCard(icon: "bed.double.fill", title: "Tiempo en la cama", value: store.sleepInBedText)
                        HeaderedMetricCard(icon: "clock.fill", title: "Duración del sueño", value: store.sleepDurationText)
                    }

                    // 4-Hour Time-Aware Sleep-Focused AI Coaching Card
                    LiveAiCoachingCard(
                        section: .sueno,
                        store: store,
                        backgroundColor: BevelColors.isDarkMode ? Color(hex: 0x202741) : BevelColors.card
                    )

                    // Cronología del sueño -> Taps directly into Sueño principal!
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cronología del sueño").font(ImprovingFont.sectionTitle(18)).foregroundColor(BevelColors.textPrimary)
                        Text(avail.hasSleepData ? "1 evento · Toca para ver detalle completo" : "0 eventos").font(ImprovingFont.caption(12.5)).foregroundColor(BevelColors.textMuted)
                    }

                    if avail.hasSleepData {
                        Button(action: onOpenSleepSession) {
                            BevelCard(cornerRadius: 20, backgroundColor: BevelColors.isDarkMode ? Color(hex: 0x202741) : BevelColors.card) {
                                VStack(spacing: 14) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "moon.stars.fill")
                                            .font(.system(size: 17))
                                            .foregroundColor(BevelColors.periwinkleStart)
                                            .frame(width: 42, height: 42)
                                            .background(Circle().fill(Color(hex: 0x2F3962)))
                                        VStack(alignment: .leading, spacing: 2) {
                                            if let s = sess?.startTimeLabel, let e = sess?.endTimeLabel {
                                                Text("\(s) - \(e)").font(ImprovingFont.caption(12)).foregroundColor(BevelColors.textMuted)
                                            }
                                            Text("Sueño principal").font(ImprovingFont.cardTitle(15)).foregroundColor(BevelColors.textPrimary)
                                            Text("○ \(store.sleepPercent)%   🛏 \(store.sleepDurationText)")
                                                .font(ImprovingFont.caption(12.5))
                                                .foregroundColor(BevelColors.textSecondary)
                                        }
                                        Spacer()
                                        Image(systemName: "arrow.right").font(.system(size: 12)).foregroundColor(BevelColors.textMuted)
                                    }

                                    Text("Abrir fases y constantes nocturnas")
                                        .font(ImprovingFont.cardTitle(13.5))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(Capsule().fill(Color(hex: 0x2E375C)))
                                }
                                .padding(16)
                            }
                        }
                    } else {
                        BevelCard(cornerRadius: 20) {
                            Text("No se registró ningún bloque de sueño en esta fecha.")
                                .font(ImprovingFont.body(13.5))
                                .foregroundColor(BevelColors.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                        }
                    }

                    // 24h Sleep Schedule (ONLY shown from user's real recorded sleep schedule — zero hardcoded times!)
                    if let realSched = store.realSleepScheduleLabels {
                        SleepSchedule24hDial(
                            windDownText: realSched.windDown,
                            bedtimeText: realSched.bedtime,
                            wakeTimeText: realSched.wakeTime,
                            sleepNeedText: needText,
                            onOpenSleepNeed: onOpenSleepNeed
                        )
                    }

                    Text("Tendencias")
                        .font(ImprovingFont.sectionTitle(18))
                        .foregroundColor(BevelColors.textPrimary)
                        .padding(.top, 4)

                    let sleepIcons = ["zzz", "clock.fill", "moon.fill", "moon.stars.fill", "heart.fill", "checkmark.seal.fill", "hourglass"]
                    ForEach(Array(store.sleepTrends.enumerated()), id: \.element.id) { idx, item in
                        BevelTrendLightCard(
                            trend: item,
                            systemIcon: sleepIcons[idx % sleepIcons.count],
                            onClick: { onOpenTrend?(item) }
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 150)
        }
        .background(BevelColors.canvas)
        .sheet(isPresented: $showShareSheet) {
            ShareSummaryCardSheet(store: store, kind: .sleep, onClose: { showShareSheet = false })
        }
    }
}

// MARK: - 3B. Sueño Principal Detail Screen (Literal Match to Screenshots 3–8, ZERO Fabricated Variables!)

struct SleepSessionDetailScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void
    let onOpenSleepNeed: () -> Void

    @State private var selectedVital: OvernightVitalTab = .fc
    @State private var scrollCollapseSignal: Int = 0
    @State private var aiInsight: MetricFloatingAiInsight = MetricFloatingAiInsight(
        shortPillText: "Analizando sueño…",
        expandedHeadline: "LECTURA DE TU SUEÑO",
        shortExpandedMessage: "",
        expandedMessage: "",
        structureIndex: 0,
        variationSeed: 1
    )

    private struct SubRatingItem: Identifiable {
        let id: String
        let icon: String
        let ratingText: String
        let label: String
        let fillFrac: Double
        let color: Color
    }

    private func formatHMS(_ sec: Int) -> String {
        let h = sec / 3600
        let m = (sec % 3600) / 60
        let s = sec % 60
        return String(format: "%d:%02d:%02d", h, m, s)
    }

    private func ratingFor(score: Double, good: Double, ok: Double) -> (String, Color, Double) {
        if score >= good { return ("Excelente", Color(hex: 0x7A9BF8), 0.90) }
        if score >= ok { return ("Aceptable", BevelColors.amberStart, 0.56) }
        return ("Deficiente", BevelColors.coralHigh, 0.24)
    }

    var body: some View {
        let d = store.currentDaySummary
        let sess = d?.sleepSession
        let asleepMin = d?.asleepMinutes ?? 0
        let inBedMin = d?.inBedMinutes ?? 0
        let sleepPct = d?.sleepPct

        // Build quality sub-ratings ONLY for variables that actually exist!
        let subRatings: [SubRatingItem] = {
            var list: [SubRatingItem] = []
            if asleepMin > 0 {
                let r = ratingFor(score: Double(asleepMin), good: 420, ok: 360)
                list.append(SubRatingItem(id: "dur", icon: "clock.fill", ratingText: r.0, label: "Duración del sueño", fillFrac: r.2, color: r.1))
            }
            if let dip = sess?.hrDipPct {
                let r = ratingFor(score: dip, good: 12, ok: 6)
                list.append(SubRatingItem(id: "dip", icon: "heart.circle.fill", ratingText: r.0, label: "Disminución de la FC", fillFrac: r.2, color: r.1))
            }
            let remSec = sess?.remSeconds ?? (d?.remMinutes.flatMap { $0 > 0 ? $0 * 60 : nil })
            if let rs = remSec, rs > 0, asleepMin > 0 {
                let pct = Double(rs) / Double(asleepMin * 60) * 100.0
                let r = ratingFor(score: pct, good: 18, ok: 12)
                list.append(SubRatingItem(id: "rem", icon: "sparkles", ratingText: r.0, label: "Sueño REM", fillFrac: r.2, color: r.1))
            }
            let deepSec = sess?.deepSeconds ?? (d?.deepMinutes.flatMap { $0 > 0 ? $0 * 60 : nil })
            if let ds = deepSec, ds > 0, asleepMin > 0 {
                let pct = Double(ds) / Double(asleepMin * 60) * 100.0
                let r = ratingFor(score: pct, good: 14, ok: 8)
                list.append(SubRatingItem(id: "deep", icon: "zzz", ratingText: r.0, label: "Sueño profundo", fillFrac: r.2, color: r.1))
            }
            if let eff = sess?.efficiencyPct {
                let r = ratingFor(score: Double(eff), good: 90, ok: 80)
                list.append(SubRatingItem(id: "eff", icon: "gearshape.2.fill", ratingText: r.0, label: "Eficiencia", fillFrac: r.2, color: r.1))
            }
            if let cont = sess?.continuityPct {
                let r = ratingFor(score: Double(cont), good: 88, ok: 72)
                list.append(SubRatingItem(id: "cont", icon: "moon.zzz.fill", ratingText: r.0, label: "Continuidad", fillFrac: r.2, color: r.1))
            }
            return list
        }()

        // Stage seconds (ONLY real measured stages — zero force unwraps!)
        let awakeSec = sess?.awakeSeconds ?? (d?.awakeMinutes.flatMap { $0 > 0 ? $0 * 60 : nil })
        let remSec = sess?.remSeconds ?? (d?.remMinutes.flatMap { $0 > 0 ? $0 * 60 : nil })
        let coreSec = sess?.coreSeconds ?? (d?.coreMinutes.flatMap { $0 > 0 ? $0 * 60 : nil })
        let deepSec = sess?.deepSeconds ?? (d?.deepMinutes.flatMap { $0 > 0 ? $0 * 60 : nil })
        let totalStageSec = (awakeSec ?? 0) + (remSec ?? 0) + (coreSec ?? 0) + (deepSec ?? 0)

        let stageCards: [(String, Int, Color)] = [
            awakeSec.flatMap { $0 > 0 ? ("Vigilia", $0, Color(hex: 0xF2845C)) : nil },
            remSec.flatMap { $0 > 0 ? ("REM", $0, Color(hex: 0xA8BCFF)) : nil },
            coreSec.flatMap { $0 > 0 ? ("Esencial", $0, Color(hex: 0x6285FA)) : nil },
            deepSec.flatMap { $0 > 0 ? ("Profundo", $0, Color(hex: 0x4E5CC8)) : nil },
        ].compactMap { $0 }

        // Overnight vitals arrays (strictly real samples)
        let hrSamples = sess?.sleepHrSamples ?? []
        let hrvSamples = sess?.sleepHrvSamples ?? []
        let respSamples = sess?.sleepRespSamples ?? []
        let spo2Samples = sess?.sleepSpo2Samples ?? []
        let hasAnyOvernightVital = !hrSamples.isEmpty || !hrvSamples.isEmpty || !respSamples.isEmpty || !spo2Samples.isEmpty

        let activeSamples: [TimedBiometricPoint] = switch selectedVital {
        case .fc: hrSamples
        case .vfc: hrvSamples
        case .fr: respSamples
        case .spo2: spo2Samples
        }
        let activeAvg: Double? = activeSamples.isEmpty ? nil : (activeSamples.map(\.value).reduce(0, +) / Double(activeSamples.count))

        let bgNavy = BevelColors.isDarkMode ? Color(hex: 0x101426) : BevelColors.canvas
        let cardNavy = BevelColors.isDarkMode ? Color(hex: 0x1D233D) : BevelColors.card

        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Header: [ ✕ ] + Sueño principal + real timestamp
                    VStack(alignment: .leading, spacing: 12) {
                        Button(action: onBack) {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(BevelColors.textPrimary)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(BevelColors.glassChromeFill))
                                .overlay(Circle().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.8))
                        }
                        .accessibilityLabel("Cerrar")
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Sueño principal")
                                .font(ImprovingFont.displayLarge(26))
                                .foregroundColor(BevelColors.textPrimary)
                            Text(sess?.startDateTimeLabel ?? store.fullDateLabel)
                                .font(ImprovingFont.body(14))
                                .foregroundColor(BevelColors.textSecondary)
                        }
                    }
                    .padding(.top, 8)

                    // 1. Puntuación del Sueño Pill (Screenshot 3)
                    if let pct = sleepPct {
                        HStack {
                            Text("Puntuación del Sueño")
                                .font(ImprovingFont.cardTitle(15.5))
                                .foregroundColor(.white)
                            Spacer()
                            Text("\(pct)%")
                                .font(ImprovingFont.cardTitle(16))
                                .monospacedDigit()
                                .foregroundColor(.white)
                            ZStack {
                                Circle().stroke(Color.white.opacity(0.12), lineWidth: 3.6).frame(width: 28, height: 28)
                                Circle()
                                    .trim(from: 0, to: CGFloat(min(max(Double(pct) / 100.0, 0.02), 1)))
                                    .stroke(
                                        LinearGradient(colors: [Color(hex: 0xC4D6FF), Color(hex: 0x7A90EE)], startPoint: .top, endPoint: .bottom),
                                        style: StrokeStyle(lineWidth: 3.6, lineCap: .round)
                                    )
                                    .rotationEffect(.degrees(-90))
                                    .frame(width: 28, height: 28)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(cardNavy))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.9))
                    }

                    // 2. Período de sueño + Tiempo en la cama | Duración del sueño + Quality 2xN Grid (Screenshot 3)
                    if sess?.startTimeLabel != nil || inBedMin > 0 || asleepMin > 0 || !subRatings.isEmpty {
                        VStack(spacing: 10) {
                            if let sLbl = sess?.startTimeLabel, let eLbl = sess?.endTimeLabel {
                                HStack {
                                    Image(systemName: "bed.double.fill")
                                        .font(.system(size: 13))
                                        .foregroundColor(BevelColors.textSecondary)
                                    Text("Período de sueño")
                                        .font(ImprovingFont.cardTitle(14.5))
                                        .foregroundColor(.white)
                                    Spacer()
                                    Text("\(sLbl) - \(eLbl)")
                                        .font(ImprovingFont.cardTitle(14.5))
                                        .monospacedDigit()
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 13)
                                .background(RoundedRectangle(cornerRadius: 16).fill(cardNavy))
                            }

                            if inBedMin > 0 || asleepMin > 0 {
                                HStack(spacing: 0) {
                                    if inBedMin > 0 {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Tiempo en la cama").font(ImprovingFont.caption(12.5)).foregroundColor(BevelColors.textSecondary)
                                            Text("\(inBedMin / 60) h \(String(format: "%02d", inBedMin % 60)) min")
                                                .font(ImprovingFont.metricHero(22))
                                                .monospacedDigit()
                                                .foregroundColor(.white)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    if inBedMin > 0 && asleepMin > 0 {
                                        Rectangle().fill(Color.white.opacity(0.10)).frame(width: 1, height: 42).padding(.horizontal, 12)
                                    }
                                    if asleepMin > 0 {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Duración del sueño").font(ImprovingFont.caption(12.5)).foregroundColor(BevelColors.textSecondary)
                                            Text("\(asleepMin / 60) h \(String(format: "%02d", asleepMin % 60)) min")
                                                .font(ImprovingFont.metricHero(22))
                                                .monospacedDigit()
                                                .foregroundColor(.white)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .padding(16)
                                .background(RoundedRectangle(cornerRadius: 16).fill(cardNavy))
                            }

                            if !subRatings.isEmpty {
                                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 12) {
                                    ForEach(subRatings) { item in
                                        VStack(spacing: 6) {
                                            Image(systemName: item.icon)
                                                .font(.system(size: 14))
                                                .foregroundColor(BevelColors.textSecondary)
                                            Text(item.ratingText)
                                                .font(ImprovingFont.cardTitle(16))
                                                .foregroundColor(.white)
                                            Text(item.label)
                                                .font(ImprovingFont.caption(12))
                                                .foregroundColor(BevelColors.textSecondary)
                                                .lineLimit(1)
                                            GeometryReader { geo in
                                                ZStack(alignment: .leading) {
                                                    Capsule().fill(Color.white.opacity(0.10)).frame(height: 5)
                                                    Capsule().fill(item.color).frame(width: geo.size.width * CGFloat(item.fillFrac), height: 5)
                                                }
                                            }
                                            .frame(height: 6)
                                            .padding(.horizontal, 14)
                                            .padding(.top, 2)
                                        }
                                        .padding(.vertical, 14)
                                        .frame(maxWidth: .infinity)
                                        .background(RoundedRectangle(cornerRadius: 16).fill(cardNavy))
                                    }
                                }
                            }
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 22).fill(Color(hex: 0x151A30)))
                        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8))
                    }

                    // 3. Registrado con [Real Device] (ONLY if sourceName exists!)
                    if let source = sess?.sourceName, !source.isEmpty {
                        HStack(spacing: 8) {
                            Spacer()
                            Image(systemName: "applewatch")
                                .font(.system(size: 14))
                                .foregroundColor(BevelColors.textSecondary)
                            Text("Registrado con \(source)")
                                .font(ImprovingFont.body(13.5))
                                .foregroundColor(BevelColors.textSecondary)
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 16).fill(cardNavy.opacity(0.75)))
                    }

                    // 4. Fases de sueño (Hypnogram + 2x2 Stage Cards — ONLY if real stages/durations exist!)
                    if !(sess?.stages.isEmpty ?? true) || !stageCards.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Fases de sueño")
                                .font(ImprovingFont.sectionTitle(18.5))
                                .foregroundColor(.white)

                            if let stages = sess?.stages, !stages.isEmpty,
                               let stEp = sess?.startEpochSec, let enEp = sess?.endEpochSec, enEp > stEp {
                                SleepHypnogramStepChart(stages: stages, startEpoch: stEp, endEpoch: enEp)

                                HStack {
                                    if let sLbl = sess?.startTimeLabel {
                                        HStack(spacing: 4) {
                                            Image(systemName: "moon.fill").font(.system(size: 10))
                                            Text(sLbl)
                                        }
                                        .font(ImprovingFont.caption(11.5))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(Capsule().fill(Color.white.opacity(0.10)))
                                    }
                                    Spacer()
                                    if let eLbl = sess?.endTimeLabel {
                                        HStack(spacing: 4) {
                                            Image(systemName: "sun.max.fill").font(.system(size: 10))
                                            Text(eLbl)
                                        }
                                        .font(ImprovingFont.caption(11.5))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(Capsule().fill(Color.white.opacity(0.10)))
                                    }
                                }
                            }

                            if totalStageSec > 0 {
                                HStack {
                                    Text("Fases registradas")
                                        .font(ImprovingFont.caption(12.5))
                                        .foregroundColor(BevelColors.textSecondary)
                                    Spacer()
                                    Text("Duración: \(formatHMS(totalStageSec))")
                                        .font(ImprovingFont.caption(13))
                                        .monospacedDigit()
                                        .foregroundColor(.white)
                                }
                            }

                            if !stageCards.isEmpty {
                                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                                    ForEach(stageCards, id: \.0) { title, sec, color in
                                        let pct = totalStageSec > 0 ? Int((Double(sec) / Double(totalStageSec) * 100.0).rounded()) : 0
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(title).font(ImprovingFont.caption(12.5)).foregroundColor(BevelColors.textSecondary)
                                                Text(formatHMS(sec))
                                                    .font(ImprovingFont.metricTile(19))
                                                    .monospacedDigit()
                                                    .foregroundColor(.white)
                                                Text("\(pct)%")
                                                    .font(ImprovingFont.caption(12.5))
                                                    .fontWeight(.semibold)
                                                    .foregroundColor(color)
                                            }
                                            Spacer()
                                            ZStack {
                                                Circle().stroke(Color.white.opacity(0.10), lineWidth: 4.5).frame(width: 44, height: 44)
                                                Circle()
                                                    .trim(from: 0, to: CGFloat(min(max(Double(pct) / 100.0, 0.02), 1.0)))
                                                    .stroke(color, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                                                    .rotationEffect(.degrees(-90))
                                                    .frame(width: 44, height: 44)
                                            }
                                        }
                                        .padding(14)
                                        .background(RoundedRectangle(cornerRadius: 16).fill(cardNavy))
                                    }
                                }
                            }
                        }
                        .padding(.top, 6)
                    }

                    // 5. Necesidad sueño (noche ant.) — ONLY if sleep data exists
                    if asleepMin > 0 {
                        let debt = d?.sleepDebtMinutes ?? 0
                        let needM = max(420, 480 + debt)
                        Button(action: onOpenSleepNeed) {
                            HStack {
                                Text("Necesidad sueño (noche ant.)")
                                    .font(ImprovingFont.cardTitle(14.5))
                                    .foregroundColor(.white)
                                Spacer()
                                Text("\(needM / 60)h \(String(format: "%02d", needM % 60))m")
                                    .font(ImprovingFont.cardTitle(14.5))
                                    .monospacedDigit()
                                    .foregroundColor(.white)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 12))
                                    .foregroundColor(BevelColors.textMuted)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 16).fill(cardNavy))
                        }
                    }

                    // 6. Tiempo que tardaste en dormirte (ONLY if latencyMinutes != nil!)
                    if let lat = sess?.latencyMinutes {
                        let clampedFrac = min(max(Double(lat) / 45.0, 0.04), 0.96)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Tiempo que tardaste en dormirte")
                                .font(ImprovingFont.sectionTitle(17.5))
                                .foregroundColor(.white)

                            VStack(spacing: 12) {
                                Text("\(lat) minutos")
                                    .font(ImprovingFont.metricTile(19))
                                    .foregroundColor(.white)

                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(
                                                LinearGradient(
                                                    colors: [Color(hex: 0x3D497A), Color(hex: 0x7A90EE), Color(hex: 0x3D497A)],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                            .frame(height: 8)
                                        Circle()
                                            .fill(Color.white.opacity(0.28))
                                            .frame(width: 24, height: 24)
                                            .offset(x: geo.size.width * CGFloat(clampedFrac) - 12)
                                        Circle()
                                            .fill(.white)
                                            .frame(width: 11, height: 11)
                                            .offset(x: geo.size.width * CGFloat(clampedFrac) - 5.5)
                                    }
                                    .frame(maxHeight: .infinity)
                                }
                                .frame(height: 24)

                                HStack {
                                    Text("Rápido")
                                        .font(ImprovingFont.caption(12.5))
                                        .fontWeight(lat <= 15 ? .bold : .regular)
                                        .foregroundColor(lat <= 15 ? .white : BevelColors.textSecondary)
                                    Spacer()
                                    Text("Normal")
                                        .font(ImprovingFont.caption(12.5))
                                        .fontWeight((16...30).contains(lat) ? .bold : .regular)
                                        .foregroundColor((16...30).contains(lat) ? .white : BevelColors.textSecondary)
                                    Spacer()
                                    Text("Tarde")
                                        .font(ImprovingFont.caption(12.5))
                                        .fontWeight(lat > 30 ? .bold : .regular)
                                        .foregroundColor(lat > 30 ? .white : BevelColors.textSecondary)
                                }
                            }
                            .padding(16)
                            .background(RoundedRectangle(cornerRadius: 18).fill(cardNavy))
                        }
                        .padding(.top, 4)
                    }

                    // 7. Overnight Vitals Section (FC / VFC / FR / SpO₂ — ONLY if at least one sensor has real overnight samples!)
                    if hasAnyOvernightVital {
                        VStack(alignment: .leading, spacing: 10) {
                            let titleStr: String = switch selectedVital {
                            case .fc: "Frecuencia cardíaca durmiendo"
                            case .vfc: "VFC durmiendo"
                            case .fr: "Frecuencia respiratoria durmiendo"
                            case .spo2: "SpO₂ durmiendo"
                            }
                            let subLabelStr: String = switch selectedVital {
                            case .fc: "PROMEDIO DE FC"
                            case .vfc: "PROMEDIO DE VFC"
                            case .fr: "PROMEDIO DE FR"
                            case .spo2: "PROMEDIO DE SPO₂"
                            }
                            let unitStr: String = switch selectedVital {
                            case .fc: "ppm"
                            case .vfc: "ms"
                            case .fr: "rpm"
                            case .spo2: "%"
                            }

                            Text(titleStr)
                                .font(ImprovingFont.sectionTitle(17.5))
                                .foregroundColor(.white)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(alignment: .firstTextBaseline, spacing: 5) {
                                    Text(activeAvg.map { String(format: "%.1f", locale: Locale(identifier: "es_ES"), $0) } ?? "--")
                                        .font(ImprovingFont.displayLarge(31))
                                        .monospacedDigit()
                                        .foregroundColor(activeAvg != nil ? .white : BevelColors.textMuted)
                                    if activeAvg != nil {
                                        Text(unitStr)
                                            .font(ImprovingFont.sectionTitle(18))
                                            .foregroundColor(BevelColors.textSecondary)
                                    }
                                }
                                Text(subLabelStr)
                                    .font(ImprovingFont.microLabel(11))
                                    .foregroundColor(BevelColors.textSecondary)
                            }

                            OvernightVitalChart(tab: selectedVital, samples: activeSamples)

                            // 4 Selector Buttons: [ FC | VFC | FR | SpO₂ ]
                            HStack(spacing: 8) {
                                vitalTabCard(.fc, icon: "heart.fill", color: Color(hex: 0xF06498), hasData: !hrSamples.isEmpty)
                                vitalTabCard(.vfc, icon: "waveform.path.ecg", color: Color(hex: 0x5CE1E6), hasData: !hrvSamples.isEmpty)
                                vitalTabCard(.fr, icon: "lungs.fill", color: Color(hex: 0xA884FF), hasData: !respSamples.isEmpty)
                                vitalTabCard(.spo2, icon: "drop.fill", color: Color(hex: 0x26B4F6), hasData: !spo2Samples.isEmpty)
                            }
                            .padding(.top, 4)
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 185)
            }
            .onVerticalScrollCollapse { scrollCollapseSignal += 1 }

            FloatingMetricAiCoachOverlay(
                metricKey: "sleep_session_\(store.selectedDateIso)",
                metricTitle: "Sueño principal",
                insight: aiInsight,
                scrollCollapseSignal: scrollCollapseSignal,
                leadingEmoji: "🌙"
            )
        }
        .background(bgNavy.ignoresSafeArea())
        .onAppear {
            // Auto-select first vital tab that actually has real data
            if !hrSamples.isEmpty { selectedVital = .fc }
            else if !hrvSamples.isEmpty { selectedVital = .vfc }
            else if !respSamples.isEmpty { selectedVital = .fr }
            else if !spo2Samples.isEmpty { selectedVital = .spo2 }
        }
        .task(id: store.selectedDateIso) {
            let slNorms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: store.userProfile)
            let rangeTxt = String(format: "%.1f h – %.1f h", locale: Locale(identifier: "es_ES"), slNorms.sleepLowHours, slNorms.sleepHighHours)
            let res = await GeminiCoachService.shared.buildMetricFloatingInsight(
                metricId: "sleep_session",
                metricTitle: "Sueño principal",
                currentValueText: store.sleepDurationText,
                normalRangeText: rangeTxt,
                recoveryPct: store.dataAvailability.hasRecoveryData ? store.recoveryPercent : nil,
                strainPct: store.dataAvailability.hasStrainData ? store.strainPercent : nil,
                hrvMs: store.dataAvailability.hasHrvData ? store.hrvMs : nil,
                restingHrBpm: store.dataAvailability.hasRestingHrData ? store.restingHrBpm : nil,
                sleepDurationText: store.dataAvailability.hasSleepData ? store.sleepDurationText : nil,
                energyPct: store.dataAvailability.hasEnergyData ? store.energyPercent : nil,
                stressScore: store.dataAvailability.hasStressData ? store.stressScore : nil,
                profile: store.userProfile,
                hasData: store.dataAvailability.hasSleepData
            )
            aiInsight = res
        }
    }

    private func vitalTabCard(_ tab: OvernightVitalTab, icon: String, color: Color, hasData: Bool) -> some View {
        let active = selectedVital == tab
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            selectedVital = tab
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(active ? color : color.opacity(hasData ? 0.55 : 0.25))
                Text(tab.rawValue)
                    .font(ImprovingFont.caption(12))
                    .fontWeight(.semibold)
                    .foregroundColor(active ? .white : (hasData ? BevelColors.textSecondary : BevelColors.textMuted.opacity(0.5)))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 14).fill(active ? color.opacity(0.14) : Color(hex: 0x171C32)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(active ? color : color.opacity(0.28), lineWidth: active ? 1.6 : 0.9))
        }
    }
}

struct SleepNeedDetailScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void

    private var wakeTimeBinding: Binding<Date> {
        Binding(
            get: {
                var comps = DateComponents()
                comps.hour = store.notificationSettings.smartAlarmHour
                comps.minute = store.notificationSettings.smartAlarmMinute
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { newDate in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                var cfg = store.notificationSettings
                cfg.smartAlarmHour = c.hour ?? 7
                cfg.smartAlarmMinute = c.minute ?? 30
                store.updateNotificationSettings(cfg, promptPermission: store.smartAlarmEnabled || cfg.bedtimeReminderEnabled)
            }
        )
    }

    var body: some View {
        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: store.userProfile)
        let baseNeedMin = Int((norms.sleepTargetHours * 60.0).rounded())
        let debt = store.currentDaySummary?.sleepDebtMinutes ?? 0
        let strainExtra = store.dataAvailability.hasStrainData ? (store.strainPercent > 70 ? 25 : (store.strainPercent > 45 ? 10 : 0)) : 0
        let totalNeed = baseNeedMin + debt + strainExtra
        let plan = LocalNotificationManager.computeSleepNotificationPlan(
            wakeHour: store.notificationSettings.smartAlarmHour,
            wakeMinute: store.notificationSettings.smartAlarmMinute,
            sleepNeedMinutes: totalNeed,
            leadMinutes: store.notificationSettings.bedtimeLeadMinutes
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                DetailSheetHeader(title: "Necesidad de sueño y Alarma", onBack: onBack)

                BevelCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("NECESIDAD DE SUEÑO ESTA NOCHE")
                            .font(ImprovingFont.microLabel(11))
                            .foregroundColor(BevelColors.periwinkleStart)
                        Text("\(totalNeed / 60) h \(String(format: "%02d", totalNeed % 60)) min")
                            .font(ImprovingFont.displayLarge(32))
                            .monospacedDigit()
                            .foregroundColor(BevelColors.textPrimary)
                        Text("Para despertar a las \(plan.wakeLabel), tu hora óptima de acostarte hoy es las \(plan.bedtimeLabel).")
                            .font(ImprovingFont.caption(12.5))
                            .foregroundColor(BevelColors.greenPrimary)

                        Divider().background(BevelColors.divider)

                        planRow("Necesidad basal fisiológica", "\(baseNeedMin / 60) h \(String(format: "%02d", baseNeedMin % 60)) m", BevelColors.textPrimary)
                        if store.dataAvailability.hasStrainData && strainExtra > 0 {
                            planRow("+ Esfuerzo físico (\(store.strainPercent)%)", "+ 0 h \(String(format: "%02d", strainExtra)) m", BevelColors.orangeEnd)
                        }
                        if debt > 0 {
                            planRow("+ Deuda de sueño acumulada", "+ \(debt / 60) h \(String(format: "%02d", debt % 60)) m", BevelColors.periwinkleStart)
                        }
                        planRow("Hora recomendada de dormir", plan.bedtimeLabel, BevelColors.skyBlue)
                    }
                    .padding(18)
                }
                .padding(.horizontal, 16)

                // Real Wake-Up Alarm Card
                BevelCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: Binding(
                            get: { store.smartAlarmEnabled },
                            set: { store.setSmartAlarmEnabled($0, promptPermission: true) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Alarma de Despertar Inteligente")
                                    .font(ImprovingFont.cardTitle(15))
                                    .foregroundColor(BevelColors.textPrimary)
                                Text("Programa aviso real en iOS a tu hora objetivo")
                                    .font(ImprovingFont.caption(12))
                                    .foregroundColor(BevelColors.textSecondary)
                            }
                        }

                        Divider().background(BevelColors.divider)

                        HStack {
                            Text("Hora objetivo de despertar")
                                .font(ImprovingFont.body(13.5))
                                .foregroundColor(BevelColors.textSecondary)
                            Spacer()
                            DatePicker("", selection: wakeTimeBinding, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }

                        HStack {
                            Text("Ventana de sueño ligero")
                                .font(ImprovingFont.body(13.5))
                                .foregroundColor(BevelColors.textSecondary)
                            Spacer()
                            Picker("Ventana", selection: Binding(
                                get: { store.notificationSettings.smartAlarmWindowMinutes },
                                set: { val in
                                    var cfg = store.notificationSettings
                                    cfg.smartAlarmWindowMinutes = val
                                    store.updateNotificationSettings(cfg, promptPermission: store.smartAlarmEnabled)
                                }
                            )) {
                                Text("Exacta").tag(0)
                                Text("15 min").tag(15)
                                Text("20 min").tag(20)
                                Text("30 min").tag(30)
                            }
                            .pickerStyle(.menu)
                            .tint(BevelColors.skyBlue)
                        }
                    }
                    .padding(16)
                }
                .padding(.horizontal, 16)

                // Bedtime Wind-Down Notification Card
                BevelCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: Binding(
                            get: { store.notificationSettings.bedtimeReminderEnabled },
                            set: { val in
                                var cfg = store.notificationSettings
                                cfg.bedtimeReminderEnabled = val
                                store.updateNotificationSettings(cfg, promptPermission: val)
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Aviso de hora recomendada para dormir")
                                    .font(ImprovingFont.cardTitle(15))
                                    .foregroundColor(BevelColors.textPrimary)
                                Text("Te avisa a las \(plan.notifyLabel) según tu deuda y esfuerzo de hoy")
                                    .font(ImprovingFont.caption(12))
                                    .foregroundColor(BevelColors.textSecondary)
                            }
                        }

                        if store.notificationSettings.bedtimeReminderEnabled {
                            Divider().background(BevelColors.divider)
                            HStack {
                                Text("Avisarme antes de acostarme")
                                    .font(ImprovingFont.body(13.5))
                                    .foregroundColor(BevelColors.textSecondary)
                                Spacer()
                                Picker("Antelación", selection: Binding(
                                    get: { store.notificationSettings.bedtimeLeadMinutes },
                                    set: { val in
                                        var cfg = store.notificationSettings
                                        cfg.bedtimeLeadMinutes = val
                                        store.updateNotificationSettings(cfg, promptPermission: true)
                                    }
                                )) {
                                    Text("15 min antes").tag(15)
                                    Text("30 min antes").tag(30)
                                    Text("45 min antes").tag(45)
                                }
                                .pickerStyle(.menu)
                                .tint(BevelColors.skyBlue)
                            }
                        }

                        Text(store.notificationStatusText)
                            .font(ImprovingFont.caption(11.5))
                            .foregroundColor(BevelColors.greenPrimary)
                    }
                    .padding(16)
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 140)
        }
        .background(BevelColors.canvas)
    }

    private func planRow(_ label: String, _ val: String, _ color: Color) -> some View {
        HStack {
            Text(label).font(ImprovingFont.body(13)).foregroundColor(BevelColors.textSecondary)
            Spacer()
            Text(val).font(ImprovingFont.cardTitle(13.5)).monospacedDigit().foregroundColor(color)
        }
    }
}

// MARK: - 4. Estrés Detail Screen (5-Minute High-Res + Real Computed Zone Durations)

struct EstresScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void
    var onOpenTrend: ((EffortTrendItem) -> Void)? = nil

    @State private var showShareSheet: Bool = false
    @State private var showInfoSheet: Bool = false

    private func formatHM(_ mins: Int) -> String {
        String(format: "%d:%02d:00", mins / 60, mins % 60)
    }

    var body: some View {
        let samples = store.stressSamplesToday
        let avail = store.dataAvailability
        let stepMin = samples.count > 40 ? 5 : (samples.isEmpty ? 0 : 60)
        let highBins = samples.filter { $0.value >= 65 }.count
        let medBins = samples.filter { $0.value >= 35 && $0.value < 65 }.count
        let lowBins = samples.filter { $0.value < 35 }.count
        let totalBins = max(samples.count, 1)
        let highMin = highBins * stepMin
        let medMin = medBins * stepMin
        let lowMin = lowBins * stepMin
        let totalMin = samples.count * stepMin
        let highPct = samples.isEmpty ? 0 : Int((Double(highBins) / Double(totalBins) * 100.0).rounded())
        let medPct = samples.isEmpty ? 0 : Int((Double(medBins) / Double(totalBins) * 100.0).rounded())
        let lowPct = samples.isEmpty ? 0 : max(0, 100 - highPct - medPct)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AtmosphericHeroHeader(
                    title: "Estrés",
                    subtitle: store.fullDateLabel,
                    style: .stress,
                    onBack: onBack,
                    onPrevDay: { store.shiftDay(1) },
                    onNextDay: { if store.dayOffset > 0 { store.shiftDay(-1) } },
                    canGoNextDay: store.dayOffset > 0,
                    onRightPrimary: { showShareSheet = true },
                    onRightSecondary: { showInfoSheet = true }
                ) {
                    VStack(spacing: 10) {
                        StressRadialDial(score: store.displayStressScore, statusLabel: store.stressStatusLabel, size: 176, isHeroGauge: true, hasData: avail.hasStressData)
                        if avail.hasStressData {
                            let labelPrefix = store.dayOffset == 0
                                ? (store.lastStressSampleTimeLabel.map { "Actual \($0)" } ?? "Actual")
                                : "Media del día"
                            Text("\(labelPrefix) · Media \(store.stressAvg ?? store.stressScore) · Máx \(store.stressMax ?? 0) · Mín \(store.stressMin ?? 0)")
                                .font(ImprovingFont.caption(12))
                                .monospacedDigit()
                                .foregroundColor(BevelColors.textSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.white.opacity(0.06)))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        HeaderedMetricCard(
                            icon: "waveform.path.ecg",
                            title: "VFC media",
                            value: avail.hasHrvData ? String(format: "%.1f", locale: Locale(identifier: "es_ES"), store.hrvMs) : "--",
                            unit: "ms"
                        )
                        HeaderedMetricCard(
                            icon: "heart.fill",
                            title: "FC media",
                            value: store.liveHrBpm.map { "\($0)" } ?? "--",
                            unit: "ppm"
                        )
                    }

                    LiveAiCoachingCard(section: .estres, store: store)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.fullDateLabel)
                            .font(ImprovingFont.cardTitle(16))
                            .foregroundColor(BevelColors.textPrimary)
                        Text("ESTRÉS DE HOY (DETALLE CADA 5 MIN)")
                            .font(ImprovingFont.microLabel(11))
                            .foregroundColor(BevelColors.textMuted)
                    }
                    .padding(.top, 4)

                    Timeline24hChart(samples: samples, isEnergy: false, sleepWindowMinutes: store.sleepWindowMinutes)

                    if !samples.isEmpty {
                        HStack {
                            Text("\(samples.count) mediciones reales")
                                .font(ImprovingFont.caption(12))
                                .foregroundColor(BevelColors.textMuted)
                            Spacer()
                            Text("Cobertura: ")
                                .font(ImprovingFont.caption(12.5))
                                .foregroundColor(BevelColors.textMuted)
                            Text(formatHM(totalMin))
                                .font(ImprovingFont.cardTitle(13.5))
                                .monospacedDigit()
                                .foregroundColor(BevelColors.textPrimary)
                        }

                        stressZonePill(label: "Alto", pct: highPct, duration: formatHM(highMin), color: BevelColors.redAlert)
                        stressZonePill(label: "Med.", pct: medPct, duration: formatHM(medMin), color: BevelColors.amberStart)
                        stressZonePill(label: "Nivel bajo", pct: lowPct, duration: formatHM(lowMin), color: BevelColors.tealLow)
                    }

                    Text("Tendencias")
                        .font(ImprovingFont.sectionTitle(18))
                        .foregroundColor(BevelColors.textPrimary)
                        .padding(.top, 6)

                    let stressIcons = ["speedometer", "moon.zzz.fill"]
                    ForEach(Array(store.stressTrends.enumerated()), id: \.element.id) { idx, item in
                        BevelTrendLightCard(
                            trend: item,
                            systemIcon: stressIcons[idx % stressIcons.count],
                            onClick: { onOpenTrend?(item) }
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 150)
        }
        .background(BevelColors.canvas)
        .sheet(isPresented: $showShareSheet) {
            ShareSummaryCardSheet(store: store, kind: .stress, onClose: { showShareSheet = false })
        }
        .sheet(isPresented: $showInfoSheet) {
            MetricMethodologyInfoSheet(kind: .stress, onClose: { showInfoSheet = false })
        }
    }

    private func stressZonePill(label: String, pct: Int, duration: String, color: Color) -> some View {
        BevelCard(cornerRadius: 16) {
            HStack(spacing: 10) {
                Text(label)
                    .font(ImprovingFont.cardTitle(14))
                    .foregroundColor(BevelColors.textPrimary)
                    .frame(width: 68, alignment: .leading)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(color.opacity(0.18)).frame(height: 8)
                        if pct > 0 {
                            Capsule().fill(color).frame(width: max(6, geo.size.width * CGFloat(pct) / 100.0), height: 8)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(height: 16)

                Text("\(pct)%")
                    .font(ImprovingFont.cardTitle(14))
                    .monospacedDigit()
                    .foregroundColor(BevelColors.textPrimary)
                    .frame(width: 38, alignment: .trailing)

                Text(duration)
                    .font(ImprovingFont.caption(13.5))
                    .monospacedDigit()
                    .foregroundColor(BevelColors.textSecondary)
                    .frame(width: 62, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
    }
}

// MARK: - 5. Reservas de Energía Detail Screen (5-Minute High-Res + Real Charge/Drain)

struct EnergiaScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void
    let onOpenSleepSession: () -> Void

    @State private var showShareSheet: Bool = false
    @State private var showInfoSheet: Bool = false

    var body: some View {
        let avail = store.dataAvailability
        let energySamples = store.energySamplesToday
        let stressSamples = store.stressSamplesToday
        let batteryFillColor: Color = !avail.hasEnergyData ? BevelColors.textMuted : (store.energyPercent >= 55 ? BevelColors.greenPrimary : BevelColors.amberStart)

        // Latest point achieving the daily peak (accurately marks wake-up peak when plateaued at ceiling)
        let peakSample: TimedBiometricPoint? = energySamples.reduce(nil) { best, pt in
            guard let b = best else { return pt }
            return pt.value >= b.value ? pt : b
        }
        // Conservation-of-energy totals across the 24h timeline:
        // captures full overnight sleep recharge (+ naps) even if energy dipped slightly before bedtime!
        let chargedPct: Int? = {
            guard energySamples.count >= 2 else { return nil }
            let gain = zip(energySamples, energySamples.dropFirst()).reduce(0.0) { acc, pair in
                acc + max(pair.1.value - pair.0.value, 0.0)
            }
            return max(Int(gain.rounded()), 0)
        }()
        let drainedPct: Int? = {
            guard energySamples.count >= 2 else { return nil }
            let loss = zip(energySamples, energySamples.dropFirst()).reduce(0.0) { acc, pair in
                acc + max(pair.0.value - pair.1.value, 0.0)
            }
            return max(Int(loss.rounded()), 0)
        }()
        let peakTimeLabel: String? = peakSample.map {
            String(format: "%02d:%02d", ($0.minuteOfDay / 60) % 24, $0.minuteOfDay % 60)
        }

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AtmosphericHeroHeader(
                    title: "Reservas de energía",
                    subtitle: store.fullDateLabel,
                    style: .energy,
                    onBack: onBack,
                    onPrevDay: { store.shiftDay(1) },
                    onNextDay: { if store.dayOffset > 0 { store.shiftDay(-1) } },
                    canGoNextDay: store.dayOffset > 0,
                    rightPrimaryIcon: "square.and.arrow.up",
                    onRightPrimary: { showShareSheet = true },
                    rightSecondaryIcon: "info.circle",
                    onRightSecondary: { showInfoSheet = true }
                ) {
                    VStack(spacing: 14) {
                        HStack(spacing: 4) {
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(batteryFillColor.opacity(0.22))
                                    .frame(width: 196, height: 88)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                                            .strokeBorder(batteryFillColor.opacity(0.45), lineWidth: 1.8)
                                    )
                                    .shadow(color: batteryFillColor.opacity(0.28), radius: 18)

                                if avail.hasEnergyData {
                                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [batteryFillColor, batteryFillColor.opacity(0.85)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: max(22, 188 * CGFloat(store.energyPercent) / 100.0), height: 80)
                                        .padding(.leading, 4)
                                }

                                VStack(spacing: 2) {
                                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                                        Text(avail.hasEnergyData ? "\(store.energyPercent)" : "--")
                                            .font(ImprovingFont.displayLarge(34))
                                            .monospacedDigit()
                                            .foregroundColor(.white)
                                        if avail.hasEnergyData {
                                            Text("%")
                                                .font(ImprovingFont.sectionTitle(18))
                                                .foregroundColor(.white.opacity(0.9))
                                        }
                                    }
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 13))
                                        .foregroundColor(.white.opacity(0.9))
                                }
                                .frame(width: 196)
                            }

                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 7, height: 30)
                        }

                        if let pk = peakSample, let tStr = peakTimeLabel {
                            HStack(spacing: 4) {
                                Text("Pico de carga hasta")
                                    .font(ImprovingFont.caption(13))
                                    .foregroundColor(BevelColors.textSecondary)
                                Text("\(Int(pk.value.rounded())) % a las \(tStr)")
                                    .font(ImprovingFont.caption(13))
                                    .fontWeight(.semibold)
                                    .foregroundColor(BevelColors.textPrimary)
                            }
                        } else {
                            Text("Sin mediciones de energía registradas hoy")
                                .font(ImprovingFont.caption(13))
                                .foregroundColor(BevelColors.textMuted)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        BevelCard(cornerRadius: 18) {
                            VStack(spacing: 4) {
                                Text(chargedPct.map { "+\($0)%" } ?? "--")
                                    .font(ImprovingFont.metricHero(22))
                                    .foregroundColor(chargedPct != nil ? BevelColors.greenPrimary : BevelColors.textMuted)
                                Text("Total cargado")
                                    .font(ImprovingFont.caption(13))
                                    .foregroundColor(BevelColors.textPrimary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                        }

                        BevelCard(cornerRadius: 18) {
                            VStack(spacing: 4) {
                                Text(drainedPct.map { "-\($0)%" } ?? "--")
                                    .font(ImprovingFont.metricHero(22))
                                    .foregroundColor(drainedPct != nil ? BevelColors.coralHigh : BevelColors.textMuted)
                                Text("Total gastado")
                                    .font(ImprovingFont.caption(13))
                                    .foregroundColor(BevelColors.textPrimary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                        }
                    }

                    LiveAiCoachingCard(section: .energia, store: store)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.fullDateLabel)
                            .font(ImprovingFont.cardTitle(16))
                            .foregroundColor(BevelColors.textPrimary)
                        Text("NIVEL DE ENERGÍA (DETALLE CADA 5 MIN)")
                            .font(ImprovingFont.microLabel(11))
                            .foregroundColor(BevelColors.textMuted)
                    }

                    Timeline24hChart(samples: energySamples, isEnergy: true, sleepWindowMinutes: store.sleepWindowMinutes, fillArea: true)

                    if !stressSamples.isEmpty {
                        Text("ESTRÉS SINCRONIZADO")
                            .font(ImprovingFont.microLabel(11))
                            .foregroundColor(BevelColors.textMuted)
                            .padding(.top, 4)

                        Timeline24hChart(samples: stressSamples, isEnergy: false, sleepWindowMinutes: nil)
                    }

                    // Uso de energía (only if sleep was recorded!)
                    if avail.hasSleepData {
                        Text("Uso de energía")
                            .font(ImprovingFont.sectionTitle(18))
                            .foregroundColor(BevelColors.textPrimary)
                            .padding(.top, 4)

                        Button(action: onOpenSleepSession) {
                            BevelCard(cornerRadius: 20) {
                                HStack(spacing: 12) {
                                    Image(systemName: "moon.stars.fill")
                                        .font(.system(size: 17))
                                        .foregroundColor(BevelColors.periwinkleStart)
                                        .frame(width: 42, height: 42)
                                        .background(Circle().fill(BevelColors.indigoSoftBg))
                                    VStack(alignment: .leading, spacing: 2) {
                                        if let s = store.currentDaySummary?.sleepSession?.startTimeLabel,
                                           let e = store.currentDaySummary?.sleepSession?.endTimeLabel {
                                            Text("\(s) - \(e)").font(ImprovingFont.caption(12)).foregroundColor(BevelColors.textMuted)
                                        }
                                        Text("Sueño principal").font(ImprovingFont.cardTitle(15)).foregroundColor(BevelColors.textPrimary)
                                        Text("○ \(store.sleepPercent)%   🛏 \(store.sleepDurationText)")
                                            .font(ImprovingFont.caption(12.5))
                                            .foregroundColor(BevelColors.textSecondary)
                                    }
                                    Spacer()
                                    if let c = chargedPct {
                                        Text("+\(c)%")
                                            .font(ImprovingFont.cardTitle(16))
                                            .monospacedDigit()
                                            .foregroundColor(BevelColors.greenPrimary)
                                    }
                                }
                                .padding(16)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 150)
        }
        .background(BevelColors.canvas)
        .sheet(isPresented: $showShareSheet) {
            ShareSummaryCardSheet(store: store, kind: .energy, onClose: { showShareSheet = false })
        }
        .sheet(isPresented: $showInfoSheet) {
            MetricMethodologyInfoSheet(kind: .energy, onClose: { showInfoSheet = false })
        }
    }
}

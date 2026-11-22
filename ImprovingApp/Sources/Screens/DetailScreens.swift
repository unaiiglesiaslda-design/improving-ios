import SwiftUI

// MARK: - Top Detail Modal Sheet Header (Screenshots 16–33, 50–68)

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

// MARK: - 1. Esfuerzo Detail Screen (Literal Match to Screenshot 02)

struct EsfuerzoScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void
    let onOpenTrend: (EffortTrendItem) -> Void

    var body: some View {
        let avail = store.dataAvailability
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AtmosphericHeroHeader(
                    title: "Esfuerzo",
                    subtitle: store.dateLabel,
                    style: .strain,
                    onBack: onBack
                ) {
                    BevelRecessedRingGauge(
                        progress: Double(store.strainPercent) / 100.0,
                        centerText: "\(store.strainPercent)%",
                        label: "",
                        kind: .strain,
                        size: 170,
                        strokeWidth: 16,
                        subLabel: "Objetivo: \(store.effortTargetRangeText)",
                        centerSubtitle: store.strainStatusText,
                        targetRange: store.optimalEffortRange,
                        hasData: avail.hasStrainData
                    )
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        HeaderedMetricCard(icon: "flame.fill", title: "Strain (0–21)", value: String(format: "%.1f", locale: Locale(identifier: "es_ES"), store.strain21))
                        HeaderedMetricCard(icon: "clock.fill", title: "Tiempo activo", value: "1 h 26 min")
                    }

                    // Coaching Card with expand icon (⤢)
                    BevelCard(cornerRadius: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("🔥 Ritmo cardiovascular óptimo")
                                    .font(ImprovingFont.cardTitle(15))
                                    .foregroundColor(BevelColors.textPrimary)
                                Spacer()
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 12))
                                    .foregroundColor(BevelColors.textMuted)
                            }
                            Text(store.activeCoachingSummary)
                                .font(ImprovingFont.body(13.5))
                                .foregroundColor(BevelColors.textSecondary)
                        }
                        .padding(16)
                    }

                    // Cronología del esfuerzo
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
                            ForEach(store.workoutsToday) { w in
                                HStack(spacing: 12) {
                                    Image(systemName: "figure.run")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(BevelColors.amberStart)
                                        .frame(width: 40, height: 40)
                                        .background(Circle().fill(BevelColors.amberSoftBg))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(w.timeRange).font(ImprovingFont.caption(11.5)).foregroundColor(BevelColors.textMuted)
                                        Text(w.title).font(ImprovingFont.cardTitle(15)).foregroundColor(BevelColors.textPrimary)
                                        Text("○ \(w.strainPct)%   🔥 \(w.kcal) kcal   ♡ \(w.avgHrBpm) ppm")
                                            .font(ImprovingFont.caption(12))
                                            .foregroundColor(BevelColors.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.right").font(.system(size: 12)).foregroundColor(BevelColors.textMuted)
                                }
                            }
                            Text("Ver cronología")
                                .font(ImprovingFont.cardTitle(14))
                                .foregroundColor(BevelColors.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(Capsule().fill(BevelColors.cardHeaderStrip))
                        }
                        .padding(16)
                    }

                    // All 6 Exact Tendencias Cards from Screenshot 02
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
    }
}

// MARK: - 2. Recuperación Detail Screen (Literal Match to Screenshots 03, 04, 05)

struct RecuperacionScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void
    let onSelectHealthMetric: (HealthMetricKind) -> Void
    var onOpenTrend: ((EffortTrendItem) -> Void)? = nil

    var body: some View {
        let avail = store.dataAvailability
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AtmosphericHeroHeader(
                    title: "Recuperación",
                    subtitle: store.dateLabel,
                    style: .recovery,
                    onBack: onBack
                ) {
                    BevelRecessedRingGauge(
                        progress: Double(store.recoveryPercent) / 100.0,
                        centerText: "\(store.recoveryPercent)%",
                        label: "",
                        kind: .recovery,
                        size: 170,
                        strokeWidth: 16,
                        centerSubtitle: "Recuperado",
                        hasData: avail.hasRecoveryData
                    )
                }

                VStack(alignment: .leading, spacing: 14) {
                    // Two-tone Headered Stat Boxes (Screenshot 03)
                    HStack(spacing: 12) {
                        HeaderedMetricCard(
                            icon: "waveform.path.ecg",
                            title: "VFC en reposo",
                            value: avail.hasHrvData ? String(format: "%.1f", locale: Locale(identifier: "es_ES"), store.hrvMs) : "—",
                            unit: "ms",
                            onClick: { onSelectHealthMetric(.hrv) }
                        )
                        HeaderedMetricCard(
                            icon: "heart.fill",
                            title: "FC en reposo",
                            value: avail.hasRestingHrData ? String(format: "%.1f", locale: Locale(identifier: "es_ES"), store.restingHrBpm) : "—",
                            unit: "ppm",
                            onClick: { onSelectHealthMetric(.restingHeartRate) }
                        )
                    }

                    // Coaching Card (Screenshot 03)
                    BevelCard(cornerRadius: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("🌙 Sueño muy eficiente")
                                    .font(ImprovingFont.cardTitle(15))
                                    .foregroundColor(BevelColors.textPrimary)
                                Spacer()
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 12))
                                    .foregroundColor(BevelColors.textMuted)
                            }
                            Text("La señal más clara de tu noche es la eficiencia del 98%: dormiste \(store.sleepDurationText) y la puntuación de Sueño quedó en \(store.sleepPercent)%. Tu VFC en \(String(format: "%.1f", locale: Locale(identifier: "es_ES"), store.hrvMs)) ms respalda una recuperación sólida.")
                                .font(ImprovingFont.body(13.5))
                                .foregroundColor(BevelColors.textSecondary)
                        }
                        .padding(16)
                    }

                    // Cronología de la recuperación (Screenshot 04)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Cronología de la recuperación")
                            .font(ImprovingFont.sectionTitle(18))
                            .foregroundColor(BevelColors.textPrimary)
                        Text("1 evento")
                            .font(ImprovingFont.caption(12.5))
                            .foregroundColor(BevelColors.textMuted)
                    }

                    BevelCard(cornerRadius: 20) {
                        VStack(spacing: 14) {
                            HStack(spacing: 12) {
                                Image(systemName: "moon.stars.fill")
                                    .font(.system(size: 17))
                                    .foregroundColor(BevelColors.periwinkleStart)
                                    .frame(width: 42, height: 42)
                                    .background(Circle().fill(BevelColors.indigoSoftBg))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("7:46").font(ImprovingFont.caption(12)).foregroundColor(BevelColors.textMuted)
                                    Text("Sueño principal").font(ImprovingFont.cardTitle(15)).foregroundColor(BevelColors.textPrimary)
                                    Text("○ \(store.sleepPercent)%   🛏 \(store.sleepDurationText)")
                                        .font(ImprovingFont.caption(12.5))
                                        .foregroundColor(BevelColors.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.right").font(.system(size: 12)).foregroundColor(BevelColors.textMuted)
                            }
                            Text("Ver cronología")
                                .font(ImprovingFont.cardTitle(14))
                                .foregroundColor(BevelColors.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(Capsule().fill(BevelColors.cardHeaderStrip))
                        }
                        .padding(16)
                    }

                    // All 6 Exact Tendencias Cards from Screenshots 04–05
                    Text("Tendencias")
                        .font(ImprovingFont.sectionTitle(18))
                        .foregroundColor(BevelColors.textPrimary)
                        .padding(.top, 4)

                    let recIcons = ["leaf.fill", "waveform.path.ecg", "heart.fill", "lungs.fill", "drop.fill", "thermometer.medium"]
                    let recKinds: [HealthMetricKind] = [.hrv, .hrv, .restingHeartRate, .respiratoryRate, .oxygenSaturation, .wristTemperature]
                    ForEach(Array(store.recoveryTrends.enumerated()), id: \.element.id) { idx, item in
                        BevelTrendLightCard(
                            trend: item,
                            systemIcon: recIcons[idx % recIcons.count],
                            onClick: { onSelectHealthMetric(recKinds[idx % recKinds.count]) }
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 150)
        }
        .background(BevelColors.canvas)
    }
}

// MARK: - 3. Sueño Detail Screen (Literal Match to Screenshots 06, 07, 08, 09)

struct SuenoDetailScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void
    let onOpenSleepNeed: () -> Void
    var onOpenTrend: ((EffortTrendItem) -> Void)? = nil

    var body: some View {
        let avail = store.dataAvailability

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AtmosphericHeroHeader(
                    title: "Sueño",
                    subtitle: store.dateLabel,
                    style: .sleep,
                    onBack: onBack,
                    rightPrimaryIcon: "square.and.arrow.up",
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
                        centerSubtitle: "Calidad",
                        hasData: avail.hasSleepData
                    )
                }

                VStack(alignment: .leading, spacing: 14) {
                    // Headered Cards: Tiempo en la cama | Duración del sueño (Screenshot 06)
                    HStack(spacing: 12) {
                        HeaderedMetricCard(icon: "bed.double.fill", title: "Tiempo en la cama", value: store.sleepInBedText)
                        HeaderedMetricCard(icon: "clock.fill", title: "Duración del sueño", value: store.sleepDurationText)
                    }

                    // Coaching Card (Screenshot 06)
                    BevelCard(cornerRadius: 20, backgroundColor: BevelColors.isDarkMode ? Color(hex: 0x202741) : BevelColors.card) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("✨ Una noche muy eficiente")
                                    .font(ImprovingFont.cardTitle(15))
                                    .foregroundColor(BevelColors.textPrimary)
                                Spacer()
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 12))
                                    .foregroundColor(BevelColors.textMuted)
                            }
                            Text("La eficiencia del Sueño fue del 98%, y el sueño profundo subió a 1 hora y 42 minutos: tu noche fue compacta y muy reparadora. Para esta noche, prueba a repetir este ciclo constante.")
                                .font(ImprovingFont.body(13.5))
                                .foregroundColor(BevelColors.textSecondary)
                        }
                        .padding(16)
                    }

                    // "✨ Ver información →" pill card (Screenshot 06)
                    Button(action: onOpenSleepNeed) {
                        BevelCard(cornerRadius: 18, backgroundColor: BevelColors.isDarkMode ? Color(hex: 0x202741) : BevelColors.card) {
                            HStack {
                                Image(systemName: "sparkles").foregroundColor(BevelColors.periwinkleStart)
                                Text("Ver información").font(ImprovingFont.cardTitle(14.5)).foregroundColor(BevelColors.textPrimary)
                                Spacer()
                                Image(systemName: "arrow.right").font(.system(size: 12)).foregroundColor(BevelColors.textMuted)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                    }

                    // 24-Hour Circular Sleep Schedule Clock Dial (Screenshot 07)
                    SleepSchedule24hDial(
                        windDownText: "23:47",
                        bedtimeText: "0:17",
                        wakeTimeText: "7:40",
                        sleepNeedText: "7 h 22 min",
                        onOpenSleepNeed: onOpenSleepNeed
                    )

                    // Cronología del sueño (Screenshot 07)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cronología del sueño").font(ImprovingFont.sectionTitle(18)).foregroundColor(BevelColors.textPrimary)
                            Text("1 evento").font(ImprovingFont.caption(12.5)).foregroundColor(BevelColors.textMuted)
                        }
                        Spacer()
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(BevelColors.textPrimary)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(BevelColors.card))
                    }

                    BevelCard(cornerRadius: 20, backgroundColor: BevelColors.isDarkMode ? Color(hex: 0x202741) : BevelColors.card) {
                        VStack(spacing: 14) {
                            HStack(spacing: 12) {
                                Image(systemName: "moon.stars.fill")
                                    .font(.system(size: 17))
                                    .foregroundColor(BevelColors.periwinkleStart)
                                    .frame(width: 42, height: 42)
                                    .background(Circle().fill(Color(hex: 0x2F3962)))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("7:46").font(ImprovingFont.caption(12)).foregroundColor(BevelColors.textMuted)
                                    Text("Sueño principal").font(ImprovingFont.cardTitle(15)).foregroundColor(BevelColors.textPrimary)
                                    Text("○ \(store.sleepPercent)%   🛏 \(store.sleepDurationText)")
                                        .font(ImprovingFont.caption(12.5))
                                        .foregroundColor(BevelColors.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.right").font(.system(size: 12)).foregroundColor(BevelColors.textMuted)
                            }
                            Text("Ver cronología")
                                .font(ImprovingFont.cardTitle(14))
                                .foregroundColor(BevelColors.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(Capsule().fill(Color(hex: 0x2E375C)))
                        }
                        .padding(16)
                    }

                    // All 9 Exact Tendencias Cards from Screenshots 08–09
                    Text("Tendencias")
                        .font(ImprovingFont.sectionTitle(18))
                        .foregroundColor(BevelColors.textPrimary)
                        .padding(.top, 4)

                    let sleepIcons = ["zzz", "clock.fill", "moon.fill", "moon.stars.fill", "heart.fill", "building.columns.fill", "clock", "sunrise.fill", "hourglass"]
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
    }
}

struct SleepNeedDetailScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                DetailSheetHeader(title: "Necesidad de sueño", onBack: onBack)

                BevelCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("NECESIDAD DE SUEÑO ESTA NOCHE")
                            .font(ImprovingFont.microLabel(11))
                            .foregroundColor(BevelColors.periwinkleStart)
                        Text("7 h 22 min")
                            .font(ImprovingFont.displayLarge(32))
                            .monospacedDigit()
                            .foregroundColor(BevelColors.textPrimary)
                        Text("Recalculado automáticamente con tu esfuerzo de hoy (\(store.strainPercent)%) y balance acumulado.")
                            .font(ImprovingFont.caption(12.5))
                            .foregroundColor(BevelColors.textSecondary)

                        Divider().background(BevelColors.divider)

                        planRow("Necesidad basal fisiológica", "7 h 45 m", BevelColors.textPrimary)
                        planRow("+ Esfuerzo físico de hoy (\(store.strainPercent)%)", "+ 0 h 29 m", BevelColors.orangeEnd)
                        planRow("− Superávit reciente", "− 0 h 52 m", BevelColors.greenPrimary)
                    }
                    .padding(18)
                }
                .padding(.horizontal, 16)

                BevelCard {
                    Toggle(isOn: $store.smartAlarmEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Alarma Háptica Inteligente")
                                .font(ImprovingFont.cardTitle(15))
                                .foregroundColor(BevelColors.textPrimary)
                            Text("Despertar óptimo a las 7:40 en fase de sueño ligero")
                                .font(ImprovingFont.caption(12))
                                .foregroundColor(BevelColors.textSecondary)
                        }
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

// MARK: - 4. Estrés Detail Screen (Literal Match to Screenshots 10, 11, 12)

struct EstresScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void
    var onOpenTrend: ((EffortTrendItem) -> Void)? = nil

    var body: some View {
        let pts = store.currentDaySummary?.stressSeries24h ?? []

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AtmosphericHeroHeader(
                    title: "Estrés",
                    subtitle: store.fullDateLabel,
                    style: .stress,
                    onBack: onBack
                ) {
                    StressRadialDial(score: store.stressScore, statusLabel: store.stressStatusLabel, size: 176, isHeroGauge: true, hasData: store.dataAvailability.hasStressData)
                }

                VStack(alignment: .leading, spacing: 14) {
                    // Headered Cards: VFC media | FC media (Screenshot 10)
                    HStack(spacing: 12) {
                        HeaderedMetricCard(icon: "waveform.path.ecg", title: "VFC media", value: "\(Int(store.hrvMs))", unit: "ms")
                        HeaderedMetricCard(icon: "heart.fill", title: "FC media", value: "\(store.liveHrBpm > 0 ? store.liveHrBpm : 63)", unit: "ppm")
                    }

                    // Coaching Card (Screenshot 10)
                    BevelCard(cornerRadius: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("🧠 Estrés contenido")
                                    .font(ImprovingFont.cardTitle(15))
                                    .foregroundColor(BevelColors.textPrimary)
                                Spacer()
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 12))
                                    .foregroundColor(BevelColors.textMuted)
                            }
                            Text("El Estrés estuvo en \(store.stressScore) de media hoy, con 30 minutos en nivel alto dentro de la ventana diaria; el resto se repartió entre 7 horas y 24 minutos en nivel medio y 13 horas y 54 minutos en nivel bajo.")
                                .font(ImprovingFont.body(13.5))
                                .foregroundColor(BevelColors.textSecondary)
                        }
                        .padding(16)
                    }

                    // Full-width 24h Stress Graph (Screenshot 11)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.fullDateLabel)
                            .font(ImprovingFont.cardTitle(16))
                            .foregroundColor(BevelColors.textPrimary)
                        Text("ESTRÉS DE HOY")
                            .font(ImprovingFont.microLabel(11))
                            .foregroundColor(BevelColors.textMuted)
                    }
                    .padding(.top, 4)

                    Timeline24hChart(points: pts, isEnergy: false, showSleepTopBar: true)

                    HStack {
                        Spacer()
                        Text("Duración:  ")
                            .font(ImprovingFont.caption(12.5))
                            .foregroundColor(BevelColors.textMuted)
                        Text("21:48:00")
                            .font(ImprovingFont.cardTitle(13.5))
                            .monospacedDigit()
                            .foregroundColor(BevelColors.textPrimary)
                    }

                    // 3 Individual Zone Pill Cards (Screenshots 11 & 12)
                    stressZonePill(label: "Alto", pct: 2, duration: "0:30:00", color: BevelColors.redAlert)
                    stressZonePill(label: "Med.", pct: 34, duration: "7:24:00", color: BevelColors.amberStart)
                    stressZonePill(label: "Nivel bajo", pct: 64, duration: "13:54:00", color: BevelColors.tealLow)

                    // All 3 Exact Tendencias Cards (Screenshot 12)
                    Text("Tendencias")
                        .font(ImprovingFont.sectionTitle(18))
                        .foregroundColor(BevelColors.textPrimary)
                        .padding(.top, 6)

                    let stressIcons = ["speedometer", "brain.head.profile", "moon.zzz.fill"]
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
    }

    private func stressZonePill(label: String, pct: Int, duration: String, color: Color) -> some View {
        BevelCard(cornerRadius: 16) {
            HStack(spacing: 10) {
                Text(label)
                    .font(ImprovingFont.cardTitle(14))
                    .foregroundColor(BevelColors.textPrimary)
                    .frame(width: 58, alignment: .leading)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(color.opacity(0.18)).frame(height: 8)
                        Capsule().fill(color).frame(width: max(6, geo.size.width * CGFloat(pct) / 100.0), height: 8)
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

// MARK: - 5. Reservas de Energía Detail Screen (Literal Match to Screenshots 13 & 14)

struct EnergiaScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void

    var body: some View {
        let energyPts = store.currentDaySummary?.energySeries24h ?? []
        let stressPts = store.currentDaySummary?.stressSeries24h ?? []
        let chargedPct = min(98, max(20, store.sleepPercent - 16))
        let drainedPct = max(12, chargedPct - store.energyPercent + 24)
        let batteryFillColor: Color = store.energyPercent >= 55 ? BevelColors.greenPrimary : BevelColors.amberStart

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AtmosphericHeroHeader(
                    title: "Reservas de energía",
                    subtitle: store.fullDateLabel,
                    style: .energy,
                    onBack: onBack,
                    rightPrimaryIcon: "ellipsis",
                    rightSecondaryIcon: "info.circle"
                ) {
                    VStack(spacing: 14) {
                        // 3D Translucent Hatched Battery Widget (Screenshot 13)
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

                                VStack(spacing: 2) {
                                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                                        Text("\(store.energyPercent)")
                                            .font(ImprovingFont.displayLarge(34))
                                            .monospacedDigit()
                                            .foregroundColor(.white)
                                        Text("%")
                                            .font(ImprovingFont.sectionTitle(18))
                                            .foregroundColor(.white.opacity(0.9))
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

                        HStack(spacing: 4) {
                            Text("Última carga hasta")
                                .font(ImprovingFont.caption(13))
                                .foregroundColor(BevelColors.textSecondary)
                            Text("\(min(store.energyPercent + 24, 96)) % a las 07:38")
                                .font(ImprovingFont.caption(13))
                                .fontWeight(.semibold)
                                .foregroundColor(BevelColors.textPrimary)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    // +Total cargado / -Total gastado (Screenshot 13)
                    HStack(spacing: 12) {
                        BevelCard(cornerRadius: 18) {
                            VStack(spacing: 4) {
                                Text("+\(chargedPct)%")
                                    .font(ImprovingFont.metricHero(22))
                                    .foregroundColor(BevelColors.greenPrimary)
                                Text("Total cargado")
                                    .font(ImprovingFont.caption(13))
                                    .foregroundColor(BevelColors.textPrimary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                        }

                        BevelCard(cornerRadius: 18) {
                            VStack(spacing: 4) {
                                Text("-\(drainedPct)%")
                                    .font(ImprovingFont.metricHero(22))
                                    .foregroundColor(BevelColors.coralHigh)
                                Text("Total gastado")
                                    .font(ImprovingFont.caption(13))
                                    .foregroundColor(BevelColors.textPrimary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                        }
                    }

                    // Coaching Summary Card
                    BevelCard(cornerRadius: 20) {
                        Text("El Sueño recargó tus reservas de energía aportando +\(chargedPct) puntos; tras la carga diaria actual mantienes un \(store.energyPercent)% de reserva disponible.")
                            .font(ImprovingFont.body(13.5))
                            .foregroundColor(BevelColors.textSecondary)
                            .padding(16)
                    }

                    // Synchronized Dual Energy + Charging Bolt Bar + Stress Chart (Screenshot 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.fullDateLabel)
                            .font(ImprovingFont.cardTitle(16))
                            .foregroundColor(BevelColors.textPrimary)
                        Text("NIVEL DE ENERGÍA")
                            .font(ImprovingFont.microLabel(11))
                            .foregroundColor(BevelColors.textMuted)
                    }

                    Timeline24hChart(points: energyPts, isEnergy: true, showSleepTopBar: true, fillArea: true)

                    // Middle Green Charging Strip with Lightning Icon (Exact Match to Screenshot 14!)
                    HStack(spacing: 4) {
                        Capsule().fill(BevelColors.greenPrimary).frame(height: 6)
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(BevelColors.greenPrimary)
                        Capsule().fill(BevelColors.greenPrimary).frame(width: 72, height: 6)
                        ForEach(0..<8, id: \.self) { i in
                            Capsule()
                                .fill(i % 2 == 0 ? BevelColors.greenPrimary.opacity(0.85) : BevelColors.greenSoftBg)
                                .frame(width: i % 2 == 0 ? 4 : 10, height: 6)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 4)

                    Timeline24hChart(points: stressPts, isEnergy: false, showSleepTopBar: false)

                    // Uso de energía (Screenshot 14)
                    HStack {
                        Text("Uso de energía")
                            .font(ImprovingFont.sectionTitle(18))
                            .foregroundColor(BevelColors.textPrimary)
                        Spacer()
                        Text("El día anterior")
                            .font(ImprovingFont.caption(12.5))
                            .foregroundColor(BevelColors.textMuted)
                    }
                    .padding(.top, 4)

                    BevelCard(cornerRadius: 20) {
                        HStack(spacing: 12) {
                            Image(systemName: "moon.stars.fill")
                                .font(.system(size: 17))
                                .foregroundColor(BevelColors.periwinkleStart)
                                .frame(width: 42, height: 42)
                                .background(Circle().fill(BevelColors.indigoSoftBg))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("23:12 - 07:38").font(ImprovingFont.caption(12)).foregroundColor(BevelColors.textMuted)
                                Text("Sueño principal").font(ImprovingFont.cardTitle(15)).foregroundColor(BevelColors.textPrimary)
                                Text("○ \(store.sleepPercent)%   🛏 \(store.sleepDurationText)")
                                    .font(ImprovingFont.caption(12.5))
                                    .foregroundColor(BevelColors.textSecondary)
                            }
                            Spacer()
                            Text("+\(chargedPct)%")
                                .font(ImprovingFont.cardTitle(16))
                                .monospacedDigit()
                                .foregroundColor(BevelColors.greenPrimary)
                        }
                        .padding(16)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 150)
        }
        .background(BevelColors.canvas)
    }
}

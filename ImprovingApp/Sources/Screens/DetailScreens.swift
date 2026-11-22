import SwiftUI

// MARK: - Top Detail Modal Bar Helper

struct DetailSheetHeader: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(BevelColors.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(BevelColors.trackGroove))
            }
            Text(title)
                .font(ImprovingFont.sectionTitle(18))
                .foregroundColor(BevelColors.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - 1. Esfuerzo Detail Screen (1:1 Android Port)

struct EsfuerzoScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void
    let onOpenTrend: (EffortTrendItem) -> Void

    var body: some View {
        let avail = store.dataAvailability
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                AtmosphericHeroHeader(
                    title: "Esfuerzo",
                    subtitle: store.dateLabel,
                    onBack: onBack
                ) {
                    BevelRecessedRingGauge(
                        progress: Double(store.strainPercent) / 100.0,
                        centerText: "\(store.strainPercent)%",
                        label: "",
                        kind: .strain,
                        size: 162,
                        strokeWidth: 15,
                        subLabel: "Rango de esfuerzo óptimo \(store.effortTargetRangeText)",
                        centerSubtitle: store.strainStatusText,
                        targetRange: store.optimalEffortRange,
                        hasData: avail.hasStrainData
                    )
                }

                VStack(alignment: .leading, spacing: 14) {
                    // Sub-scorecards: Strain 0-21 | Tiempo activo | Energía total
                    BevelCard {
                        HStack {
                            statCol(value: String(format: "%.1f", locale: Locale(identifier: "es_ES"), store.strain21), label: "Strain (0-21)")
                            Rectangle().fill(BevelColors.divider).frame(width: 1, height: 34)
                            statCol(value: "01:26:00", label: "Tiempo activo")
                            Rectangle().fill(BevelColors.divider).frame(width: 1, height: 34)
                            statCol(value: "2.890 cal", label: "Energía total")
                        }
                        .padding(16)
                    }

                    // Coaching Insight Card
                    BevelCard {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Text("✨").font(.system(size: 13))
                                Text("Superando tus límites hoy")
                                    .font(ImprovingFont.cardTitle(14.5))
                                    .foregroundColor(BevelColors.textPrimary)
                            }
                            Text(store.activeCoachingSummary)
                                .font(ImprovingFont.body(13))
                                .foregroundColor(BevelColors.textSecondary)
                        }
                        .padding(16)
                    }

                    // Línea de tiempo
                    HStack {
                        Text("Línea de tiempo")
                            .font(ImprovingFont.sectionTitle(17))
                            .foregroundColor(BevelColors.textPrimary)
                        Spacer()
                        Text("Hoy").font(ImprovingFont.caption(12)).foregroundColor(BevelColors.textSecondary)
                    }

                    ForEach(store.workoutsToday) { w in
                        BevelCard(cornerRadius: 20) {
                            HStack(spacing: 12) {
                                Text("🏃")
                                    .font(.system(size: 18))
                                    .frame(width: 44, height: 44)
                                    .background(RoundedRectangle(cornerRadius: 14).fill(BevelColors.amberSoftBg))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(w.title)
                                        .font(ImprovingFont.cardTitle(14.5))
                                        .foregroundColor(BevelColors.textPrimary)
                                    Text("\(w.timeRange) · \(w.durationMin) min · \(w.kcal) kcal · \(w.avgHrBpm) bpm")
                                        .font(ImprovingFont.caption(11.5))
                                        .foregroundColor(BevelColors.textSecondary)
                                }
                                Spacer()
                                Text("\(w.strainPct)%")
                                    .font(ImprovingFont.caption(12))
                                    .fontWeight(.bold)
                                    .foregroundColor(BevelColors.orangeEnd)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(BevelColors.amberSoftBg))
                            }
                            .padding(14)
                        }
                    }

                    // Tendencias
                    Text("Tendencias")
                        .font(ImprovingFont.sectionTitle(17))
                        .foregroundColor(BevelColors.textPrimary)
                        .padding(.top, 4)

                    ForEach(store.effortTrends) { item in
                        BevelTrendLightCard(
                            trend: item,
                            systemIcon: "flame.fill",
                            onClick: { onOpenTrend(item) }
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 120)
        }
        .background(BevelColors.canvas)
    }

    private func statCol(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(ImprovingFont.cardTitle(16))
                .monospacedDigit()
                .foregroundColor(BevelColors.textPrimary)
            Text(label)
                .font(ImprovingFont.caption(11.5))
                .foregroundColor(BevelColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 2. Recuperación Detail Screen (1:1 Android Port)

struct RecuperacionScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void
    let onSelectHealthMetric: (HealthMetricKind) -> Void
    var onOpenTrend: ((EffortTrendItem) -> Void)? = nil

    var body: some View {
        let avail = store.dataAvailability
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                AtmosphericHeroHeader(
                    title: "Recuperación",
                    subtitle: store.dateLabel,
                    onBack: onBack
                ) {
                    BevelRecessedRingGauge(
                        progress: Double(store.recoveryPercent) / 100.0,
                        centerText: "\(store.recoveryPercent)%",
                        label: "",
                        kind: .recovery,
                        size: 162,
                        strokeWidth: 15,
                        subLabel: "Línea base calibrada (90 días)",
                        centerSubtitle: store.recoveryStatusText,
                        hasData: avail.hasRecoveryData
                    )
                }

                VStack(alignment: .leading, spacing: 14) {
                    // 2x2 Grid: VFC | FCR | Resp | SpO2
                    HStack(spacing: 12) {
                        recMiniCard(title: "VFC (RMSSD)", value: String(format: "%.1f", locale: Locale(identifier: "es_ES"), store.hrvMs), unit: "ms", status: "↑ +9% vs base 30d", color: BevelColors.emeraldEnd) {
                            onSelectHealthMetric(.hrv)
                        }
                        recMiniCard(title: "FC en reposo", value: String(format: "%.1f", locale: Locale(identifier: "es_ES"), store.restingHrBpm), unit: "ppm", status: "↓ -1.4 ppm óptimo", color: BevelColors.emeraldEnd) {
                            onSelectHealthMetric(.restingHeartRate)
                        }
                    }

                    HStack(spacing: 12) {
                        recMiniCard(title: "Frec. Respiratoria", value: String(format: "%.1f", locale: Locale(identifier: "es_ES"), store.respRateRpm), unit: "rpm", status: "Rango normal", color: BevelColors.skyBlue) {
                            onSelectHealthMetric(.respiratoryRate)
                        }
                        recMiniCard(title: "Oxígeno (SpO₂)", value: "\(store.spo2Percent),2", unit: "%", status: "Rango normal", color: BevelColors.emeraldEnd) {
                            onSelectHealthMetric(.oxygenSaturation)
                        }
                    }

                    BevelCard {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Text("✨").font(.system(size: 13))
                                Text("Sistema nervioso parasimpático")
                                    .font(ImprovingFont.cardTitle(14.5))
                                    .foregroundColor(BevelColors.textPrimary)
                            }
                            Text(store.activeCoachingSummary)
                                .font(ImprovingFont.body(13))
                                .foregroundColor(BevelColors.textSecondary)
                        }
                        .padding(16)
                    }

                    Text("Tendencias")
                        .font(ImprovingFont.sectionTitle(17))
                        .foregroundColor(BevelColors.textPrimary)
                        .padding(.top, 4)

                    ForEach(store.recoveryTrends) { item in
                        BevelTrendLightCard(
                            trend: item,
                            systemIcon: "heart.fill",
                            onClick: { onOpenTrend?(item) }
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 120)
        }
        .background(BevelColors.canvas)
    }

    private func recMiniCard(title: String, value: String, unit: String, status: String, color: Color, onClick: @escaping () -> Void) -> some View {
        Button(action: onClick) {
            BevelCard(cornerRadius: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(ImprovingFont.caption(12))
                        .foregroundColor(BevelColors.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(value)
                            .font(ImprovingFont.metricHero(22))
                            .monospacedDigit()
                            .foregroundColor(BevelColors.textPrimary)
                        Text(unit)
                            .font(ImprovingFont.caption(12))
                            .foregroundColor(BevelColors.textSecondary)
                    }
                    Text(status)
                        .font(ImprovingFont.caption(11.5))
                        .fontWeight(.medium)
                        .foregroundColor(color)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
        }
    }
}

// MARK: - 3. Sueño & Necesidad de Sueño Detail Screens (1:1 Android Port)

struct SuenoDetailScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void
    let onOpenSleepNeed: () -> Void
    var onOpenTrend: ((EffortTrendItem) -> Void)? = nil

    var body: some View {
        let avail = store.dataAvailability
        let d = store.currentDaySummary
        let deep = d?.deepMinutes ?? 108
        let rem = d?.remMinutes ?? 116
        let total = d?.asleepMinutes ?? 478
        let light = max(total - deep - rem, 226)
        let awake = max((d?.inBedMinutes ?? 512) - total, 28)

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                AtmosphericHeroHeader(
                    title: "Sueño",
                    subtitle: store.dateLabel,
                    onBack: onBack
                ) {
                    BevelRecessedRingGauge(
                        progress: Double(store.sleepPercent) / 100.0,
                        centerText: "\(store.sleepPercent)%",
                        label: "",
                        kind: .sleep,
                        size: 162,
                        strokeWidth: 15,
                        subLabel: "\(store.sleepDurationText) dormido de 8 h 15 m objetivo",
                        centerSubtitle: store.sleepStatusText,
                        hasData: avail.hasSleepData
                    )
                }

                VStack(alignment: .leading, spacing: 14) {
                    // Sleep Need Interactive Banner
                    Button(action: onOpenSleepNeed) {
                        BevelCard(cornerRadius: 20) {
                            HStack(spacing: 12) {
                                Text("🛏️")
                                    .font(.system(size: 18))
                                    .frame(width: 42, height: 42)
                                    .background(Circle().fill(BevelColors.indigoSoftBg))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Necesidad de sueño y Alarma")
                                        .font(ImprovingFont.cardTitle(14.5))
                                        .foregroundColor(BevelColors.textPrimary)
                                    Text("Objetivo esta noche: 8h 26m · Hora ideal 23:05")
                                        .font(ImprovingFont.caption(12))
                                        .foregroundColor(BevelColors.textSecondary)
                                }
                                Spacer()
                                Text("Plan →")
                                    .font(ImprovingFont.caption(12.5))
                                    .fontWeight(.bold)
                                    .foregroundColor(BevelColors.indigoEnd)
                            }
                            .padding(14)
                        }
                    }

                    // Sleep Stages Breakdown Card
                    BevelCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Fases del sueño")
                                    .font(ImprovingFont.cardTitle(16))
                                    .foregroundColor(BevelColors.textPrimary)
                                Spacer()
                                Text("23:12 — 07:38")
                                    .font(ImprovingFont.caption(12))
                                    .foregroundColor(BevelColors.textSecondary)
                            }

                            SleepStagesHypnogramBar(deepMin: deep, remMin: rem, lightMin: light, awakeMin: awake)

                            stageRow(label: "Despierto", pct: "6%", duration: "0 h \(awake) m", color: BevelColors.coralHigh)
                            stageRow(label: "Sueño REM", pct: "23%", duration: "\(rem / 60) h \(rem % 60) m", color: Color(hex: 0x818CF8))
                            stageRow(label: "Sueño Ligero", pct: "49%", duration: "\(light / 60) h \(light % 60) m", color: BevelColors.periwinkleStart)
                            stageRow(label: "Sueño Profundo (SWS)", pct: "22%", duration: "\(deep / 60) h \(deep % 60) m", color: BevelColors.indigoEnd)
                        }
                        .padding(16)
                    }

                    //Tendencias
                    Text("Tendencias")
                        .font(ImprovingFont.sectionTitle(17))
                        .foregroundColor(BevelColors.textPrimary)
                        .padding(.top, 4)

                    ForEach(store.sleepTrends) { item in
                        BevelTrendLightCard(
                            trend: item,
                            systemIcon: "moon.fill",
                            onClick: { onOpenTrend?(item) }
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 120)
        }
        .background(BevelColors.canvas)
    }

    private func stageRow(label: String, pct: String, duration: String, color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(label)
                .font(ImprovingFont.body(13.5))
                .foregroundColor(BevelColors.textPrimary)
            Spacer()
            Text(pct)
                .font(ImprovingFont.caption(12.5))
                .foregroundColor(BevelColors.textSecondary)
                .padding(.trailing, 8)
            Text(duration)
                .font(ImprovingFont.cardTitle(13.5))
                .monospacedDigit()
                .foregroundColor(BevelColors.textPrimary)
        }
    }
}

struct SleepNeedDetailScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                DetailSheetHeader(title: "Planificador de Sueño", onBack: onBack)

                BevelCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("NECESIDAD DE SUEÑO ESTA NOCHE")
                            .font(ImprovingFont.microLabel(11))
                            .foregroundColor(BevelColors.indigoEnd)
                        Text("8 h 26 min")
                            .font(ImprovingFont.displayLarge(32))
                            .monospacedDigit()
                            .foregroundColor(BevelColors.textPrimary)
                        Text("Calculado por WHOOP 5.0 según tu esfuerzo de hoy (\(store.strainPercent)%) y deuda acumulada.")
                            .font(ImprovingFont.caption(12.5))
                            .foregroundColor(BevelColors.textSecondary)

                        Divider().background(BevelColors.divider)

                        planRow("Necesidad basal fisiológica", "7 h 45 m", BevelColors.textPrimary)
                        planRow("+ Esfuerzo físico de hoy (\(store.strainPercent)%)", "+ 0 h 29 m", BevelColors.orangeEnd)
                        planRow("+ Deuda de sueño reciente", "+ 0 h 12 m", BevelColors.coralHigh)
                        planRow("− Siestas registradas hoy", "− 0 h 00 m", BevelColors.emeraldEnd)
                    }
                    .padding(18)
                }
                .padding(.horizontal, 16)

                HStack(spacing: 12) {
                    BevelCard(cornerRadius: 18) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Hora ideal dormir").font(ImprovingFont.caption(12)).foregroundColor(BevelColors.textSecondary)
                            Text("23:05").font(ImprovingFont.displayLarge(24)).monospacedDigit().foregroundColor(BevelColors.indigoEnd)
                            Text("Ventana 22:50 – 23:20").font(ImprovingFont.caption(11.5)).foregroundColor(BevelColors.emeraldEnd)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                    }
                    BevelCard(cornerRadius: 18) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Despertar óptimo").font(ImprovingFont.caption(12)).foregroundColor(BevelColors.textSecondary)
                            Text("07:31").font(ImprovingFont.displayLarge(24)).monospacedDigit().foregroundColor(BevelColors.textPrimary)
                            Text("100% meta cumplida").font(ImprovingFont.caption(11.5)).foregroundColor(BevelColors.emeraldEnd)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                    }
                }
                .padding(.horizontal, 16)

                BevelCard {
                    Toggle(isOn: $store.smartAlarmEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Alarma Háptica Inteligente")
                                .font(ImprovingFont.cardTitle(15))
                                .foregroundColor(BevelColors.textPrimary)
                            Text("Vibra en fase de sueño ligero o al alcanzar el 100% de tu objetivo")
                                .font(ImprovingFont.caption(12))
                                .foregroundColor(BevelColors.textSecondary)
                        }
                    }
                    .padding(16)
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 120)
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

// MARK: - 4. Estrés Detail Screen (1:1 Android Port)

struct EstresScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void

    var body: some View {
        let pts = store.currentDaySummary?.stressSeries24h ?? []
        let stressMax = pts.map { Int($0.rounded()) }.max() ?? 77
        let stressMin = pts.map { Int($0.rounded()) }.min() ?? 2
        let stressAvg = pts.isEmpty ? 35 : Int((pts.reduce(0, +) / Double(pts.count)).rounded())

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                AtmosphericHeroHeader(
                    title: "Puntuación de estrés",
                    subtitle: store.dateLabel,
                    onBack: onBack
                ) {
                    StressRadialDial(score: store.stressScore, statusLabel: store.stressStatusLabel, size: 162, isHeroGauge: true, hasData: store.dataAvailability.hasStressData)
                }

                VStack(alignment: .leading, spacing: 14) {
                    // Instant / Avg VFC & FC cards
                    HStack(spacing: 12) {
                        BevelCard(cornerRadius: 18) {
                            HStack(spacing: 10) {
                                Text("📈")
                                    .font(.system(size: 16))
                                    .frame(width: 36, height: 36)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.trackGroove))
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                                        Text("\(Int(store.hrvMs))")
                                            .font(ImprovingFont.metricHero(20))
                                            .foregroundColor(BevelColors.textPrimary)
                                        Text(" / 51 ms")
                                            .font(ImprovingFont.caption(11.5))
                                            .foregroundColor(BevelColors.textSecondary)
                                    }
                                    Text("VFC (inst. / prom.)")
                                        .font(ImprovingFont.caption(11))
                                        .foregroundColor(BevelColors.textSecondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                        }

                        BevelCard(cornerRadius: 18) {
                            HStack(spacing: 10) {
                                Text("❤️")
                                    .font(.system(size: 16))
                                    .frame(width: 36, height: 36)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.trackGroove))
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                                        Text("\(store.liveHrBpm > 0 ? store.liveHrBpm : 68)")
                                            .font(ImprovingFont.metricHero(20))
                                            .foregroundColor(BevelColors.textPrimary)
                                        Text(" / 70 ppm")
                                            .font(ImprovingFont.caption(11.5))
                                            .foregroundColor(BevelColors.textSecondary)
                                    }
                                    Text("FC (inst. / prom.)")
                                        .font(ImprovingFont.caption(11))
                                        .foregroundColor(BevelColors.textSecondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                        }
                    }

                    // Coaching Card
                    BevelCard {
                        Text(store.activeCoachingSummary)
                            .font(ImprovingFont.body(13))
                            .foregroundColor(BevelColors.textPrimary)
                            .padding(16)
                    }

                    // 24h Stress Timeline Card
                    Text("Línea de tiempo")
                        .font(ImprovingFont.sectionTitle(17))
                        .foregroundColor(BevelColors.textPrimary)

                    BevelCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 18) {
                                statSmall("\(stressMax)", "Máximo", BevelColors.amberStart)
                                statSmall("\(stressMin)", "Mínimo", BevelColors.emeraldEnd)
                                statSmall("\(stressAvg)", "Promedio", BevelColors.emeraldEnd)
                            }

                            Timeline24hChart(points: pts, isEnergy: false, showSleepTopBar: true)

                            Divider().background(BevelColors.divider)

                            stressZoneBar(label: "Alto", pct: 4, duration: "1h 1m", color: BevelColors.coralHigh)
                            stressZoneBar(label: "Med.", pct: 18, duration: "4h 12m", color: BevelColors.amberStart)
                            stressZoneBar(label: "Bajo", pct: 78, duration: "18h 10m", color: BevelColors.emeraldEnd)
                        }
                        .padding(16)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 120)
        }
        .background(BevelColors.canvas)
    }

    private func statSmall(_ val: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(val).font(ImprovingFont.metricHero(22)).monospacedDigit().foregroundColor(color)
            Text(label).font(ImprovingFont.caption(11.5)).foregroundColor(BevelColors.textSecondary)
        }
    }

    private func stressZoneBar(label: String, pct: Int, duration: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(ImprovingFont.caption(12))
                .foregroundColor(BevelColors.textSecondary)
                .frame(width: 36, alignment: .leading)
            Text("\(pct) %")
                .font(ImprovingFont.caption(12))
                .fontWeight(.bold)
                .foregroundColor(BevelColors.textPrimary)
                .frame(width: 36, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(BevelColors.trackGroove).frame(height: 6)
                    Capsule().fill(color).frame(width: geo.size.width * CGFloat(pct) / 100.0, height: 6)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 16)
            Text(duration)
                .font(ImprovingFont.caption(12))
                .foregroundColor(BevelColors.textSecondary)
                .frame(width: 52, alignment: .trailing)
        }
    }
}

// MARK: - 5. Energía Detail Screen (1:1 Android Port)

struct EnergiaScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void

    var body: some View {
        let energyPts = store.currentDaySummary?.energySeries24h ?? []
        let stressPts = store.currentDaySummary?.stressSeries24h ?? []
        let chargedPct = min(98, max(20, store.sleepPercent - 16))
        let drainedPct = max(12, chargedPct - store.energyPercent + 24)

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                AtmosphericHeroHeader(
                    title: "Banco de energía",
                    subtitle: store.dateLabel,
                    onBack: onBack
                ) {
                    VStack(spacing: 12) {
                        HStack(spacing: 3) {
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .fill(BevelColors.card)
                                    .frame(width: 194, height: 84)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                                            .strokeBorder(BevelColors.cardBorder, lineWidth: 1.5)
                                    )

                                RoundedRectangle(cornerRadius: 19, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [BevelColors.emeraldStart, BevelColors.emeraldEnd],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(20, 182 * CGFloat(store.energyPercent) / 100.0), height: 72)
                                    .padding(.leading, 6)
                            }
                            RoundedRectangle(cornerRadius: 4)
                                .fill(BevelColors.textMuted.opacity(0.45))
                                .frame(width: 7, height: 28)
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(store.energyPercent)")
                                .font(ImprovingFont.displayLarge(38))
                                .monospacedDigit()
                                .foregroundColor(BevelColors.textPrimary)
                            Text("%")
                                .font(ImprovingFont.sectionTitle(20))
                                .foregroundColor(BevelColors.textSecondary)
                        }
                        Text("Nivel de energía adecuado")
                            .font(ImprovingFont.cardTitle(14.5))
                            .foregroundColor(BevelColors.emeraldEnd)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    // +Charged / -Drained cards
                    HStack(spacing: 12) {
                        BevelCard(cornerRadius: 18) {
                            HStack(spacing: 10) {
                                Text("⚡")
                                    .font(.system(size: 16))
                                    .frame(width: 36, height: 36)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.greenSoftBg))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("+\(chargedPct) %")
                                        .font(ImprovingFont.metricHero(20))
                                        .foregroundColor(BevelColors.emeraldEnd)
                                    Text("Total cargado")
                                        .font(ImprovingFont.caption(11.5))
                                        .foregroundColor(BevelColors.textSecondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                        }

                        BevelCard(cornerRadius: 18) {
                            HStack(spacing: 10) {
                                Text("📉")
                                    .font(.system(size: 16))
                                    .frame(width: 36, height: 36)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.coralSoftBg))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("-\(drainedPct) %")
                                        .font(ImprovingFont.metricHero(20))
                                        .foregroundColor(BevelColors.coralHigh)
                                    Text("Total gastado")
                                        .font(ImprovingFont.caption(11.5))
                                        .foregroundColor(BevelColors.textSecondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                        }
                    }

                    // Coaching Card
                    BevelCard {
                        Text(store.activeCoachingSummary)
                            .font(ImprovingFont.body(13))
                            .foregroundColor(BevelColors.textPrimary)
                            .padding(16)
                    }

                    // Dual Synchronized 24h Charts (Energy + Stress)
                    Text("Línea de tiempo")
                        .font(ImprovingFont.sectionTitle(17))
                        .foregroundColor(BevelColors.textPrimary)

                    BevelCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Banco de energía")
                                .font(ImprovingFont.cardTitle(14.5))
                                .foregroundColor(BevelColors.textPrimary)
                            Timeline24hChart(points: energyPts, isEnergy: true, showSleepTopBar: true)

                            Divider().background(BevelColors.divider)

                            Text("Puntuación de estrés")
                                .font(ImprovingFont.cardTitle(14.5))
                                .foregroundColor(BevelColors.textPrimary)
                            Timeline24hChart(points: stressPts, isEnergy: false, showSleepTopBar: false)
                        }
                        .padding(16)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 120)
        }
        .background(BevelColors.canvas)
    }
}

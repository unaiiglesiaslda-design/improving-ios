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

// MARK: - Esfuerzo Detail Screen

struct EsfuerzoScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void
    let onOpenTrend: (EffortTrendItem) -> Void

    var body: some View {
        let avail = store.dataAvailability
        ScrollView {
            VStack(spacing: 16) {
                DetailSheetHeader(title: "Esfuerzo", onBack: onBack)

                BevelCard {
                    VStack(spacing: 14) {
                        BevelRecessedRingGauge(
                            progress: Double(store.strainPercent) / 100.0,
                            centerText: "\(store.strainPercent)%",
                            label: "Esfuerzo de hoy",
                            kind: .strain,
                            size: 138,
                            strokeWidth: 14,
                            subLabel: "Óptimo: \(store.effortTargetRangeText)",
                            targetRange: store.optimalEffortRange,
                            hasData: avail.hasStrainData
                        )
                        Text(store.activeCoachingSummary)
                            .font(ImprovingFont.body(13.5))
                            .foregroundColor(BevelColors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(18)
                }
                .padding(.horizontal, 16)

                if !store.workoutsToday.isEmpty {
                    BevelCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("ACTIVIDADES DE HOY")
                                .font(ImprovingFont.microLabel(11))
                                .foregroundColor(BevelColors.textSecondary)
                            ForEach(store.workoutsToday) { w in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(w.title).font(ImprovingFont.cardTitle(14.5)).foregroundColor(BevelColors.textPrimary)
                                        Text("\(w.timeRange) · \(w.durationMin) min · \(w.avgHrBpm) ppm").font(ImprovingFont.caption(11.5)).foregroundColor(BevelColors.textSecondary)
                                    }
                                    Spacer()
                                    Text("\(w.strainPct)%").font(ImprovingFont.cardTitle(14.5)).monospacedDigit().foregroundColor(BevelColors.orangeEnd)
                                }
                            }
                        }
                        .padding(16)
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 120)
        }
        .background(BevelColors.canvas)
    }
}

// MARK: - Recuperación Detail Screen

struct RecuperacionScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void
    let onSelectHealthMetric: (HealthMetricKind) -> Void

    var body: some View {
        let avail = store.dataAvailability
        ScrollView {
            VStack(spacing: 16) {
                DetailSheetHeader(title: "Recuperación", onBack: onBack)

                BevelCard {
                    VStack(spacing: 14) {
                        BevelRecessedRingGauge(
                            progress: Double(store.recoveryPercent) / 100.0,
                            centerText: "\(store.recoveryPercent)%",
                            label: store.recoveryStatusText,
                            kind: .recovery,
                            size: 138,
                            strokeWidth: 14,
                            hasData: avail.hasRecoveryData
                        )
                        HStack(spacing: 12) {
                            Button { onSelectHealthMetric(.hrv) } label: {
                                metricChip("VFC", avail.hasHrvData ? String(format: "%.1f ms", store.hrvMs) : "--")
                            }
                            Button { onSelectHealthMetric(.restingHeartRate) } label: {
                                metricChip("FCR", avail.hasRestingHrData ? String(format: "%.1f ppm", store.restingHrBpm) : "--")
                            }
                            Button { onSelectHealthMetric(.sleepDuration) } label: {
                                metricChip("Sueño", store.sleepDurationText)
                            }
                        }
                    }
                    .padding(18)
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 120)
        }
        .background(BevelColors.canvas)
    }

    private func metricChip(_ title: String, _ val: String) -> some View {
        VStack(spacing: 3) {
            Text(title).font(ImprovingFont.caption(11)).foregroundColor(BevelColors.textSecondary)
            Text(val).font(ImprovingFont.cardTitle(13.5)).monospacedDigit().foregroundColor(BevelColors.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(BevelColors.cardSubtle))
    }
}

// MARK: - Sueño & Necesidad de Sueño Detail Screens

struct SuenoDetailScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void
    let onOpenSleepNeed: () -> Void

    var body: some View {
        let avail = store.dataAvailability
        let d = store.currentDaySummary
        let deep = d?.deepMinutes ?? 0
        let rem = d?.remMinutes ?? 0
        let total = d?.asleepMinutes ?? 0
        let light = max(total - deep - rem, 0)

        ScrollView {
            VStack(spacing: 16) {
                DetailSheetHeader(title: "Sueño", onBack: onBack)

                BevelCard {
                    VStack(spacing: 14) {
                        BevelRecessedRingGauge(
                            progress: Double(store.sleepPercent) / 100.0,
                            centerText: "\(store.sleepPercent)%",
                            label: "Calidad de sueño",
                            kind: .sleep,
                            size: 136,
                            strokeWidth: 14,
                            subLabel: store.sleepDurationText,
                            hasData: avail.hasSleepData
                        )

                        if avail.hasSleepData {
                            SleepStagesHypnogramBar(deepMin: deep, remMin: rem, lightMin: light, awakeMin: max((d?.inBedMinutes ?? total) - total, 0))
                            HStack {
                                stageDot("Profundo", "\(deep)m", BevelColors.indigoEnd)
                                Spacer()
                                stageDot("REM", "\(rem)m", BevelColors.periwinkleStart)
                                Spacer()
                                stageDot("Ligero", "\(light)m", BevelColors.skyBlue)
                            }
                        }

                        Button(action: onOpenSleepNeed) {
                            Text("Ver plan y necesidad de sueño →")
                                .font(ImprovingFont.caption(12.5))
                                .fontWeight(.semibold)
                                .foregroundColor(BevelColors.periwinkleStart)
                        }
                    }
                    .padding(18)
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 120)
        }
        .background(BevelColors.canvas)
    }

    private func stageDot(_ name: String, _ val: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(name) \(val)").font(ImprovingFont.caption(11.5)).monospacedDigit().foregroundColor(BevelColors.textPrimary)
        }
    }
}

struct SleepNeedDetailScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void

    var body: some View {
        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: store.userProfile)
        ScrollView {
            VStack(spacing: 16) {
                DetailSheetHeader(title: "Necesidad de sueño", onBack: onBack)
                BevelCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("META RECOMENDADA PARA HOY")
                            .font(ImprovingFont.microLabel(11))
                            .foregroundColor(BevelColors.periwinkleStart)
                        Text(String(format: "%.1f horas", norms.sleepTargetHours))
                            .font(ImprovingFont.displayLarge(30))
                            .monospacedDigit()
                            .foregroundColor(BevelColors.textPrimary)
                        Toggle("Alarma inteligente de ciclo ligero", isOn: $store.smartAlarmEnabled)
                            .font(ImprovingFont.body(14))
                            .foregroundColor(BevelColors.textPrimary)
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

// MARK: - Estrés & Energía Detail Screens

struct EstresScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void

    var body: some View {
        let pts = store.currentDaySummary?.stressSeries24h ?? []
        ScrollView {
            VStack(spacing: 16) {
                DetailSheetHeader(title: "Monitor de estrés", onBack: onBack)
                BevelCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ESTRÉS ACTUAL").font(ImprovingFont.microLabel(11)).foregroundColor(BevelColors.textSecondary)
                        Text(store.dataAvailability.hasStressData ? "\(store.stressScore) / 100" : "--")
                            .font(ImprovingFont.displayLarge(30))
                            .monospacedDigit()
                            .foregroundColor(BevelColors.textPrimary)
                        Timeline24hChart(points: pts, isEnergy: false)
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

struct EnergiaScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void

    var body: some View {
        let pts = store.currentDaySummary?.energySeries24h ?? []
        ScrollView {
            VStack(spacing: 16) {
                DetailSheetHeader(title: "Batería de energía", onBack: onBack)
                BevelCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("RESERVA CORPORAL").font(ImprovingFont.microLabel(11)).foregroundColor(BevelColors.textSecondary)
                        Text(store.dataAvailability.hasEnergyData ? "\(store.energyPercent)%" : "--")
                            .font(ImprovingFont.displayLarge(30))
                            .monospacedDigit()
                            .foregroundColor(BevelColors.greenPrimary)
                        SegmentedEnergyMeter(percent: store.dataAvailability.hasEnergyData ? store.energyPercent : 0)
                        Timeline24hChart(points: pts, isEnergy: true)
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

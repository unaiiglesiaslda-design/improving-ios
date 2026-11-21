import SwiftUI

struct HoyScreen: View {
    @ObservedObject var store: ImprovingStore
    let onNavigate: (OverlayRoute) -> Void
    let onSelectHealthMetric: (HealthMetricKind) -> Void

    var body: some View {
        let avail = store.dataAvailability
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Header
                HStack {
                    HStack(spacing: 8) {
                        Button { store.shiftDay(-1) } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(BevelColors.textSecondary)
                        }
                        Text(store.dateLabel)
                            .font(ImprovingFont.displayLarge(26))
                            .foregroundColor(BevelColors.textPrimary)
                    }
                    Spacer()
                    HStack(spacing: 10) {
                        Button {
                            store.startNewCleanChat()
                            onNavigate(.askBevel)
                        } label: {
                            IridescentPearlOrb(size: 36)
                        }
                        Button { onNavigate(.dispositivos) } label: {
                            Image(systemName: "person.fill")
                                .font(.system(size: 15))
                                .foregroundColor(BevelColors.avatarTextColor)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(BevelColors.cardSubtle))
                        }
                    }
                }

                // Device / HR Status Pills
                HStack(spacing: 8) {
                    Button { onNavigate(.dispositivos) } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(store.whoopConnected || store.healthKitAuthorized || avail.hasAnyRecordedData ? BevelColors.greenPrimary : BevelColors.textMuted)
                                .frame(width: 8, height: 8)
                            Text(
                                store.whoopConnected
                                    ? "WHOOP · \(store.whoopBatteryPct ?? 0)%"
                                    : (store.healthKitAuthorized || avail.hasAnyRecordedData ? "Apple Health · Activo" : "Conectar sensor / Salud")
                            )
                            .font(ImprovingFont.caption(12))
                            .foregroundColor(BevelColors.textPrimary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(BevelColors.card))
                        .overlay(Capsule().strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
                    }

                    HStack(spacing: 5) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 11))
                            .foregroundColor(avail.hasRestingHrData || store.liveHrBpm > 0 ? BevelColors.coralHigh : BevelColors.textMuted)
                        Text(store.liveHrBpm > 0 ? "\(store.liveHrBpm) ppm" : "-- ppm")
                            .font(ImprovingFont.caption(12))
                            .monospacedDigit()
                            .foregroundColor(BevelColors.textPrimary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(BevelColors.card))
                    .overlay(Capsule().strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
                }

                // Setup Banner ONLY when zero recorded data exists anywhere
                if !avail.hasAnyRecordedData && store.realHistory.isEmpty {
                    Button { onNavigate(.dispositivos) } label: {
                        BevelCard {
                            HStack(spacing: 12) {
                                Image(systemName: "person.badge.plus")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 40, height: 40)
                                    .background(Circle().fill(BevelColors.indigoEnd))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Configura tu perfil y dispositivo")
                                        .font(ImprovingFont.cardTitle(14.5))
                                        .foregroundColor(BevelColors.textPrimary)
                                    Text("Conecta Apple Health, importa exportar.zip o vincula WHOOP")
                                        .font(ImprovingFont.caption(12))
                                        .foregroundColor(BevelColors.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(BevelColors.indigoEnd)
                            }
                            .padding(14)
                        }
                    }
                }

                // Hero 3 Rings Card + Coaching
                BevelCard {
                    VStack(spacing: 16) {
                        HStack(spacing: 12) {
                            Button { onNavigate(.esfuerzo) } label: {
                                BevelRecessedRingGauge(
                                    progress: Double(store.strainPercent) / 100.0,
                                    centerText: "\(store.strainPercent)%",
                                    label: "Esfuerzo",
                                    kind: .strain,
                                    size: 86,
                                    subLabel: store.strainStatusText,
                                    targetRange: store.optimalEffortRange,
                                    hasData: avail.hasStrainData
                                )
                            }
                            .frame(maxWidth: .infinity)

                            Button { onNavigate(.recuperacion) } label: {
                                BevelRecessedRingGauge(
                                    progress: Double(store.recoveryPercent) / 100.0,
                                    centerText: "\(store.recoveryPercent)%",
                                    label: "Recuperación",
                                    kind: .recovery,
                                    size: 86,
                                    subLabel: store.recoveryStatusText,
                                    hasData: avail.hasRecoveryData
                                )
                            }
                            .frame(maxWidth: .infinity)

                            Button { onNavigate(.suenoDetail) } label: {
                                BevelRecessedRingGauge(
                                    progress: Double(store.sleepPercent) / 100.0,
                                    centerText: "\(store.sleepPercent)%",
                                    label: "Sueño",
                                    kind: .sleep,
                                    size: 86,
                                    subLabel: store.sleepDurationText,
                                    hasData: avail.hasSleepData
                                )
                            }
                            .frame(maxWidth: .infinity)
                        }

                        Divider().background(BevelColors.divider)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 12))
                                    .foregroundColor(BevelColors.amberStart)
                                Text("COACHING")
                                    .font(ImprovingFont.microLabel(11))
                                    .foregroundColor(BevelColors.textSecondary)
                            }
                            Text(store.activeCoachingSummary)
                                .font(ImprovingFont.body(13.5))
                                .foregroundColor(BevelColors.textPrimary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(16)
                }

                // Stress & Energy Section
                HStack {
                    Text("Estrés y Energía")
                        .font(ImprovingFont.sectionTitle(18))
                        .foregroundColor(BevelColors.textPrimary)
                    Spacer()
                    Text("En vivo")
                        .font(ImprovingFont.caption(12))
                        .foregroundColor(BevelColors.textSecondary)
                }

                Button { onNavigate(.estres) } label: {
                    BevelCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Circle().fill(avail.hasStressData ? BevelColors.greenPrimary : BevelColors.textMuted).frame(width: 8, height: 8)
                                    Text("Estrés de hoy")
                                        .font(ImprovingFont.cardTitle(15))
                                        .foregroundColor(BevelColors.textPrimary)
                                }
                                Text(avail.hasStressData ? "Nivel \(store.stressScore) / 100" : "Sin muestras registradas")
                                    .font(ImprovingFont.caption(12))
                                    .foregroundColor(BevelColors.textSecondary)
                            }
                            Spacer()
                            Text(avail.hasStressData ? "\(store.stressScore)" : "--")
                                .font(ImprovingFont.metricHero(28))
                                .monospacedDigit()
                                .foregroundColor(BevelColors.textPrimary)
                        }
                        .padding(16)
                    }
                }

                Button { onNavigate(.energia) } label: {
                    BevelCard {
                        HStack(spacing: 12) {
                            Image(systemName: "bolt.fill")
                                .foregroundColor(BevelColors.amberStart)
                            SegmentedEnergyMeter(percent: avail.hasEnergyData ? store.energyPercent : 0)
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(avail.hasEnergyData ? "\(store.energyPercent)%" : "--")
                                    .font(ImprovingFont.cardTitle(16))
                                    .monospacedDigit()
                                    .foregroundColor(BevelColors.textPrimary)
                                Text("Energía")
                                    .font(ImprovingFont.caption(11))
                                    .foregroundColor(BevelColors.textSecondary)
                            }
                        }
                        .padding(16)
                    }
                }

                // Monitor de Salud 2x3 Grid
                Text("Monitor de salud")
                    .font(ImprovingFont.sectionTitle(18))
                    .foregroundColor(BevelColors.textPrimary)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    healthTile(.respiratoryRate, value: avail.hasRespData ? String(format: "%.1f", store.respRateRpm) : "--", unit: "rpm", ok: avail.hasRespData)
                    healthTile(.restingHeartRate, value: avail.hasRestingHrData ? String(format: "%.1f", store.restingHrBpm) : "--", unit: "ppm", ok: avail.hasRestingHrData)
                    healthTile(.hrv, value: avail.hasHrvData ? String(format: "%.1f", store.hrvMs) : "--", unit: "ms", ok: avail.hasHrvData)
                    healthTile(.oxygenSaturation, value: avail.hasSpo2Data ? "\(store.spo2Percent)" : "--", unit: "%", ok: avail.hasSpo2Data)
                    healthTile(.wristTemperature, value: avail.hasTempData ? String(format: "%+.1f", store.wristTempDeltaC) : "--", unit: "°C", ok: avail.hasTempData)
                    healthTile(.sleepDuration, value: store.sleepDurationText, unit: "", ok: avail.hasSleepData)
                }

                // Actividad y Nutrición
                HStack {
                    Text("Actividad y Nutrición")
                        .font(ImprovingFont.sectionTitle(18))
                        .foregroundColor(BevelColors.textPrimary)
                    Spacer()
                    Button("Abrir Nutrición →") { onNavigate(.nutricion) }
                        .font(ImprovingFont.caption(12.5))
                        .foregroundColor(BevelColors.emeraldEnd)
                }

                BevelCard {
                    VStack(spacing: 12) {
                        if let w = store.workoutsToday.first {
                            Button { onNavigate(.esfuerzo) } label: {
                                HStack {
                                    Image(systemName: "figure.run")
                                        .foregroundColor(BevelColors.orangeEnd)
                                    VStack(alignment: .leading) {
                                        Text(w.title).font(ImprovingFont.cardTitle(14.5)).foregroundColor(BevelColors.textPrimary)
                                        Text("\(w.durationMin) min · \(w.kcal) kcal").font(ImprovingFont.caption(12)).foregroundColor(BevelColors.textSecondary)
                                    }
                                    Spacer()
                                    Text("\(w.strainPct)%").font(ImprovingFont.cardTitle(14)).monospacedDigit().foregroundColor(BevelColors.orangeEnd)
                                }
                            }
                        } else {
                            HStack {
                                Image(systemName: "figure.walk")
                                    .foregroundColor(BevelColors.textMuted)
                                Text(store.stepsCount > 0 ? "\(store.stepsCount) pasos registrados hoy" : "Sin entrenamientos hoy")
                                    .font(ImprovingFont.body(13.5))
                                    .foregroundColor(BevelColors.textSecondary)
                                Spacer()
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 118)
        }
        .background(BevelColors.canvas)
    }

    private func healthTile(_ kind: HealthMetricKind, value: String, unit: String, ok: Bool) -> some View {
        Button { onSelectHealthMetric(kind) } label: {
            BevelCard(cornerRadius: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(kind.shortLabel)
                        .font(ImprovingFont.caption(12))
                        .foregroundColor(BevelColors.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(value)
                            .font(ImprovingFont.metricTile(20))
                            .monospacedDigit()
                            .foregroundColor(ok ? BevelColors.textPrimary : BevelColors.textMuted)
                        if !unit.isEmpty {
                            Text(unit)
                                .font(ImprovingFont.caption(12))
                                .foregroundColor(BevelColors.textSecondary)
                        }
                    }
                    HStack(spacing: 5) {
                        Circle().fill(ok ? BevelColors.greenPrimary : BevelColors.textMuted).frame(width: 6, height: 6)
                        Text(ok ? "Normal" : "Sin datos")
                            .font(ImprovingFont.caption(11))
                            .foregroundColor(ok ? BevelColors.emeraldEnd : BevelColors.textMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
        }
    }
}

private extension BevelColors {
    static var avatarTextColor: Color { isDarkMode ? Color(hex: 0x93C5FD) : Color(hex: 0x1E3A8A) }
}

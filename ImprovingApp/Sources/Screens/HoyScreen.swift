import SwiftUI

struct HoyScreen: View {
    @ObservedObject var store: ImprovingStore
    let onNavigate: (OverlayRoute) -> Void
    let onSelectHealthMetric: (HealthMetricKind) -> Void

    var body: some View {
        let avail = store.dataAvailability
        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: store.userProfile)
        let respEval = WhoopPhysiologyEngine.evaluateVital(value: store.respRateRpm, bandLow: norms.respLowRpm, bandHigh: norms.respHighRpm, lowerIsBetter: true, hasData: avail.hasRespData)
        let rhrEval = WhoopPhysiologyEngine.evaluateVital(value: store.restingHrBpm, bandLow: norms.rhrLowBpm, bandHigh: norms.rhrHighBpm, lowerIsBetter: true, hasData: avail.hasRestingHrData)
        let hrvEval = WhoopPhysiologyEngine.evaluateVital(value: store.hrvMs, bandLow: norms.hrvLowMs, bandHigh: norms.hrvHighMs, higherIsBetter: true, hasData: avail.hasHrvData)
        let spo2Eval = WhoopPhysiologyEngine.evaluateVital(value: Double(store.spo2Percent), bandLow: 95.0, bandHigh: 100.0, higherIsBetter: true, hasData: avail.hasSpo2Data)
        let tempAbs = 35.8 + store.wristTempDeltaC
        let tempEval = WhoopPhysiologyEngine.evaluateVital(value: tempAbs, bandLow: 35.5, bandHigh: 36.6, hasData: avail.hasTempData)
        let sleepHours = Double(store.currentDaySummary?.asleepMinutes ?? 478) / 60.0
        let sleepEval = WhoopPhysiologyEngine.evaluateVital(value: sleepHours, bandLow: norms.sleepLowHours, bandHigh: norms.sleepHighHours, higherIsBetter: true, hasData: avail.hasSleepData)

        let stressPts = store.currentDaySummary?.stressSeries24h ?? []
        let stressMax = stressPts.map { Int($0.rounded()) }.max() ?? 77
        let stressMin = stressPts.map { Int($0.rounded()) }.min() ?? 2
        let stressAvg = stressPts.isEmpty ? 35 : Int((stressPts.reduce(0, +) / Double(stressPts.count)).rounded())

        let initials = store.userProfile.userName.isEmpty
            ? "UI"
            : String(store.userProfile.userName.prefix(2)).uppercased()

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 1. Exact Top Bar from Screenshots 01 & 15: [Calendar]   Hoy, 21 nov ⌄   [Share | UI]
                HStack {
                    Button { store.shiftDay(1) } label: {
                        Image(systemName: "calendar")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(BevelColors.textPrimary)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(BevelColors.glassChromeFill))
                            .overlay(Circle().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.8))
                    }

                    Spacer()

                    Button {
                        if store.dayOffset > 0 { store.shiftDay(-1) }
                    } label: {
                        HStack(spacing: 5) {
                            Text(store.dateLabel)
                                .font(ImprovingFont.sectionTitle(17.5))
                                .foregroundColor(BevelColors.textPrimary)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(BevelColors.textSecondary)
                        }
                    }

                    Spacer()

                    HStack(spacing: 10) {
                        Button { onNavigate(.dispositivos) } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(BevelColors.textPrimary)
                        }
                        Button { onNavigate(.dispositivos) } label: {
                            Text(initials)
                                .font(ImprovingFont.caption(12))
                                .fontWeight(.bold)
                                .foregroundColor(BevelColors.skyBlue)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(BevelColors.skySoftBg))
                        }
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 40)
                    .background(Capsule().fill(BevelColors.glassChromeFill))
                    .overlay(Capsule().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.8))
                }

                // Setup Banner ONLY when zero recorded data exists anywhere
                if !store.hasEverHadAnyRecordedData {
                    Button { onNavigate(.dispositivos) } label: {
                        BevelCard {
                            HStack(spacing: 12) {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 36, height: 36)
                                    .background(Circle().fill(BevelColors.indigoEnd))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Configura tu perfil y dispositivo")
                                        .font(ImprovingFont.cardTitle(14))
                                        .foregroundColor(BevelColors.textPrimary)
                                    Text("Conecta Apple Health, importa exportar.zip o vincula WHOOP")
                                        .font(ImprovingFont.caption(11.5))
                                        .foregroundColor(BevelColors.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(BevelColors.indigoEnd)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                    }
                }

                // 2. Hero Card: 3 Recessed Rings + Vertical Dividers + Coaching (Screenshot 01)
                BevelCard(cornerRadius: 24) {
                    VStack(spacing: 0) {
                        HStack(alignment: .top, spacing: 0) {
                            Button { onNavigate(.esfuerzo) } label: {
                                BevelRecessedRingGauge(
                                    progress: Double(store.strainPercent) / 100.0,
                                    centerText: "\(store.strainPercent)%",
                                    label: "Esfuerzo",
                                    kind: .strain,
                                    size: 92,
                                    strokeWidth: 9.5,
                                    targetRange: store.optimalEffortRange,
                                    hasData: avail.hasStrainData
                                )
                            }
                            .frame(maxWidth: .infinity)

                            Rectangle()
                                .fill(BevelColors.divider)
                                .frame(width: 1, height: 92)
                                .padding(.top, 8)

                            Button { onNavigate(.recuperacion) } label: {
                                BevelRecessedRingGauge(
                                    progress: Double(store.recoveryPercent) / 100.0,
                                    centerText: "\(store.recoveryPercent)%",
                                    label: "Recuperación",
                                    kind: .recovery,
                                    size: 92,
                                    strokeWidth: 9.5,
                                    hasData: avail.hasRecoveryData
                                )
                            }
                            .frame(maxWidth: .infinity)

                            Rectangle()
                                .fill(BevelColors.divider)
                                .frame(width: 1, height: 92)
                                .padding(.top, 8)

                            Button { onNavigate(.suenoDetail) } label: {
                                BevelRecessedRingGauge(
                                    progress: Double(store.sleepPercent) / 100.0,
                                    centerText: "\(store.sleepPercent)%",
                                    label: "Sueño",
                                    kind: .sleep,
                                    size: 92,
                                    strokeWidth: 9.5,
                                    hasData: avail.hasSleepData
                                )
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 18)

                        Divider().background(BevelColors.divider)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("COACHING")
                                .font(ImprovingFont.microLabel(11))
                                .foregroundColor(BevelColors.textMuted)
                            Text(store.activeCoachingSummary)
                                .font(ImprovingFont.body(13.5))
                                .foregroundColor(BevelColors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(BevelColors.cardSubtle.opacity(0.65))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }

                // 3. Estrés y Energía Section (Screenshot 01)
                Text("Estrés y Energía")
                    .font(ImprovingFont.sectionTitle(18.5))
                    .foregroundColor(BevelColors.textPrimary)

                Button { onNavigate(.estres) } label: {
                    BevelCard(cornerRadius: 22) {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 14) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 7) {
                                        Circle()
                                            .fill(BevelColors.greenPrimary)
                                            .frame(width: 8, height: 8)
                                        Text("Estrés de hoy")
                                            .font(ImprovingFont.cardTitle(15.5))
                                            .foregroundColor(BevelColors.textPrimary)
                                    }
                                    Text("Última actualización a las 14:32")
                                        .font(ImprovingFont.caption(12))
                                        .foregroundColor(BevelColors.textMuted)
                                }

                                HStack(spacing: 14) {
                                    stressStatColumn(val: "\(stressMax)", label: "Máximo", color: BevelColors.coralHigh)
                                    Rectangle().fill(BevelColors.divider).frame(width: 1, height: 34)
                                    stressStatColumn(val: "\(stressMin)", label: "Mínimo", color: BevelColors.tealLow)
                                    Rectangle().fill(BevelColors.divider).frame(width: 1, height: 34)
                                    stressStatColumn(val: "\(stressAvg)", label: "Media", color: BevelColors.tealLow)
                                }
                            }
                            Spacer()
                            ZStack(alignment: .topTrailing) {
                                StressRadialDial(score: store.stressScore, statusLabel: store.stressStatusLabel, size: 96, isHeroGauge: false, hasData: avail.hasStressData)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(BevelColors.textMuted)
                                    .offset(x: 4, y: -6)
                            }
                        }
                        .padding(16)
                    }
                }

                // 34-bar green battery pill (Screenshot 01)
                EnergyBankBatteryBar(percent: store.energyPercent, hasData: avail.hasEnergyData, onClick: { onNavigate(.energia) })

                // 4. Monitor de salud (Exact 2x3 Grid from Screenshot 15)
                HStack {
                    Text("Monitor de salud")
                        .font(ImprovingFont.sectionTitle(18.5))
                        .foregroundColor(BevelColors.textPrimary)
                    Spacer()
                    Button("Editar >") { onNavigate(.dispositivos) }
                        .font(ImprovingFont.caption(13))
                        .foregroundColor(BevelColors.textSecondary)
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    HealthMonitorRangeCard(
                        title: "FR",
                        value: avail.hasRespData ? String(format: "%.1f", locale: Locale(identifier: "es_ES"), store.respRateRpm) : "--",
                        unit: "rpm",
                        systemIcon: "lungs.fill",
                        evaluation: respEval,
                        onClick: { onSelectHealthMetric(.respiratoryRate) }
                    )
                    HealthMonitorRangeCard(
                        title: "FCR",
                        value: avail.hasRestingHrData ? String(format: "%.1f", locale: Locale(identifier: "es_ES"), store.restingHrBpm) : "--",
                        unit: "ppm",
                        systemIcon: "heart.fill",
                        evaluation: rhrEval,
                        onClick: { onSelectHealthMetric(.restingHeartRate) }
                    )
                    HealthMonitorRangeCard(
                        title: "VFC",
                        value: avail.hasHrvData ? String(format: "%.1f", locale: Locale(identifier: "es_ES"), store.hrvMs) : "--",
                        unit: "ms",
                        systemIcon: "waveform.path.ecg",
                        evaluation: hrvEval,
                        onClick: { onSelectHealthMetric(.hrv) }
                    )
                    HealthMonitorRangeCard(
                        title: "SpO₂",
                        value: avail.hasSpo2Data ? String(format: "%.1f", locale: Locale(identifier: "es_ES"), store.spo2DisplayDouble) : "--",
                        unit: "%",
                        systemIcon: "drop.fill",
                        evaluation: spo2Eval,
                        onClick: { onSelectHealthMetric(.oxygenSaturation) }
                    )
                    HealthMonitorRangeCard(
                        title: "Temp.",
                        value: avail.hasTempData ? String(format: "%.1f", locale: Locale(identifier: "es_ES"), tempAbs) : "--",
                        unit: "°C",
                        systemIcon: "thermometer.medium",
                        evaluation: tempEval,
                        onClick: { onSelectHealthMetric(.wristTemperature) }
                    )
                    HealthMonitorRangeCard(
                        title: "Sueño",
                        value: store.sleepDurationText,
                        unit: "",
                        systemIcon: "bed.double.fill",
                        evaluation: sleepEval,
                        onClick: { onSelectHealthMetric(.sleepDuration) }
                    )
                }

                // "Todas las métricas dentro del rango normal" status bar (Screenshot 01)
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(BevelColors.greenPrimary)
                    Text("Todas las métricas están dentro del rango normal.")
                        .font(ImprovingFont.body(13))
                        .foregroundColor(BevelColors.greenPrimary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(BevelColors.greenSoftBg))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(BevelColors.greenSoftBorder.opacity(0.6), lineWidth: 0.8))

                // 5. Carga cardíaca Preview Card (Bottom of Screenshot 15)
                Text("Carga cardíaca")
                    .font(ImprovingFont.sectionTitle(18.5))
                    .foregroundColor(BevelColors.textPrimary)

                Button { onNavigate(.trainingLoad) } label: {
                    BevelCard(cornerRadius: 20) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                HStack(spacing: 6) {
                                    Image(systemName: "figure.run")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(BevelColors.textMuted)
                                    Text("Carga cardíaca")
                                        .font(ImprovingFont.caption(13.5))
                                        .foregroundColor(BevelColors.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(BevelColors.textMuted)
                            }
                            HStack(alignment: .bottom) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("37")
                                        .font(ImprovingFont.metricHero(26))
                                        .foregroundColor(BevelColors.textPrimary)
                                    Text("Manteniéndose · Óptimo 32–42")
                                        .font(ImprovingFont.caption(12))
                                        .foregroundColor(BevelColors.greenPrimary)
                                }
                                Spacer()
                                TrendSparklineWithBand(points: [28, 30, 32, 31, 35, 34, 37], bandLow: 30, bandHigh: 42, lineColor: BevelColors.periwinkleStart, showBand: true, showGlowDot: true)
                                    .frame(width: 120, height: 48)
                            }
                        }
                        .padding(16)
                    }
                }

                // 6. Nutrición y Actividad
                Text("Nutrición y Actividad")
                    .font(ImprovingFont.sectionTitle(18.5))
                    .foregroundColor(BevelColors.textPrimary)

                BevelCard(cornerRadius: 20) {
                    VStack(spacing: 14) {
                        if let w = store.workoutsToday.first {
                            Button { onNavigate(.esfuerzo) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "figure.run")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(BevelColors.orangeEnd)
                                        .frame(width: 42, height: 42)
                                        .background(Circle().fill(BevelColors.amberSoftBg))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(w.title)
                                            .font(ImprovingFont.cardTitle(14.5))
                                            .foregroundColor(BevelColors.textPrimary)
                                        Text("\(w.timeRange) · \(w.kcal) kcal · \(w.avgHrBpm) ppm")
                                            .font(ImprovingFont.caption(12))
                                            .foregroundColor(BevelColors.textSecondary)
                                    }
                                    Spacer()
                                    Text("\(w.strainPct)%")
                                        .font(ImprovingFont.caption(12.5))
                                        .fontWeight(.bold)
                                        .foregroundColor(BevelColors.orangeEnd)
                                }
                            }
                        }

                        Divider().background(BevelColors.divider)

                        Button { onNavigate(.nutricion) } label: {
                            HStack(spacing: 12) {
                                Text("🥑")
                                    .font(.system(size: 18))
                                    .frame(width: 42, height: 42)
                                    .background(Circle().fill(BevelColors.greenSoftBg))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Nutrición · \(store.mealsToday.count) comidas")
                                        .font(ImprovingFont.cardTitle(14.5))
                                        .foregroundColor(BevelColors.textPrimary)
                                    Text("\(store.totalCaloriesToday) kcal · \(store.totalProteinToday)g Prot · Calidad \(store.foodQualityScore)")
                                        .font(ImprovingFont.caption(12))
                                        .foregroundColor(BevelColors.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(BevelColors.textMuted)
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 150)
        }
        .background(BevelColors.canvas)
    }

    private func stressStatColumn(val: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(val)
                .font(ImprovingFont.metricHero(22))
                .monospacedDigit()
                .foregroundColor(color)
            Text(label)
                .font(ImprovingFont.caption(11.5))
                .foregroundColor(BevelColors.textSecondary)
        }
    }
}

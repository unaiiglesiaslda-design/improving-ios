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
        let tempAbs = 35.9 + store.wristTempDeltaC
        let tempEval = WhoopPhysiologyEngine.evaluateVital(value: tempAbs, bandLow: 35.5, bandHigh: 36.6, hasData: avail.hasTempData)
        let sleepHours = Double(store.currentDaySummary?.asleepMinutes ?? 478) / 60.0
        let sleepEval = WhoopPhysiologyEngine.evaluateVital(value: sleepHours, bandLow: norms.sleepLowHours, bandHigh: norms.sleepHighHours, higherIsBetter: true, hasData: avail.hasSleepData)

        let stressPts = store.currentDaySummary?.stressSeries24h ?? []
        let stressMax = stressPts.map { Int($0.rounded()) }.max() ?? 77
        let stressMin = stressPts.map { Int($0.rounded()) }.min() ?? 2
        let stressAvg = stressPts.isEmpty ? 35 : Int((stressPts.reduce(0, +) / Double(stressPts.count)).rounded())

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 1. Top Bar: Date Navigation + Pearl Orb + Profile Avatar
                HStack {
                    HStack(spacing: 4) {
                        Button { store.shiftDay(1) } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(BevelColors.textSecondary)
                                .frame(width: 28, height: 28)
                        }
                        Button {
                            if store.dayOffset > 0 { store.shiftDay(-1) }
                        } label: {
                            HStack(spacing: 4) {
                                Text(store.dateLabel)
                                    .font(ImprovingFont.sectionTitle(19))
                                    .foregroundColor(BevelColors.textPrimary)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(BevelColors.textSecondary)
                            }
                        }
                        if store.dayOffset > 0 {
                            Button { store.shiftDay(-1) } label: {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(BevelColors.textSecondary)
                                    .frame(width: 28, height: 28)
                            }
                        }
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
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(BevelColors.isDarkMode ? Color(hex: 0x93C5FD) : Color(hex: 0x1E3A8A))
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(BevelColors.isDarkMode ? Color(hex: 0x1E293B) : Color(hex: 0xDBEAFE)))
                                .overlay(Circle().strokeBorder(BevelColors.cardBorder, lineWidth: 1))
                        }
                    }
                }

                // 2. Status Pills Row
                HStack(spacing: 10) {
                    Button { onNavigate(.dispositivos) } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(BevelColors.greenPrimary)
                                .frame(width: 7, height: 7)
                            Text(
                                store.whoopConnected
                                    ? "Activo · WHOOP 5.0 · \(store.whoopBatteryPct ?? 86)%"
                                    : (store.healthKitAuthorized ? "Activo · Apple Health" : "Activo · WHOOP 5.0 · 86%")
                            )
                            .font(ImprovingFont.caption(12))
                            .fontWeight(.medium)
                            .foregroundColor(BevelColors.textPrimary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(BevelColors.textSecondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(BevelColors.card))
                        .overlay(Capsule().strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
                    }

                    Button { onSelectHealthMetric(.restingHeartRate) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 11))
                                .foregroundColor(BevelColors.coralHigh)
                            Text("\(store.liveHrBpm > 0 ? store.liveHrBpm : 68) bpm")
                                .font(ImprovingFont.caption(12))
                                .fontWeight(.semibold)
                                .monospacedDigit()
                                .foregroundColor(BevelColors.textPrimary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(BevelColors.card))
                        .overlay(Capsule().strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
                    }
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
                                    Text("Añade tu nombre, edad, peso, altura y vincula tu reloj")
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

                // 3. Hero Card: 3 Rings with Vertical Dividers + Coaching Block
                BevelCard {
                    VStack(spacing: 16) {
                        HStack(alignment: .top, spacing: 0) {
                            Button { onNavigate(.esfuerzo) } label: {
                                BevelRecessedRingGauge(
                                    progress: Double(store.strainPercent) / 100.0,
                                    centerText: "\(store.strainPercent)%",
                                    label: "Esfuerzo",
                                    kind: .strain,
                                    size: 88,
                                    strokeWidth: 9.5,
                                    subLabel: "Óptimo: \(store.effortTargetRangeText)",
                                    centerSubtitle: store.strainStatusText,
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
                                    size: 88,
                                    strokeWidth: 9.5,
                                    centerSubtitle: store.recoveryStatusText,
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
                                    size: 88,
                                    strokeWidth: 9.5,
                                    subLabel: store.sleepDurationText,
                                    centerSubtitle: store.sleepStatusText,
                                    hasData: avail.hasSleepData
                                )
                            }
                            .frame(maxWidth: .infinity)
                        }

                        Divider().background(BevelColors.divider)

                        Button {
                            store.startNewCleanChat()
                            onNavigate(.askBevel)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Text("✨")
                                        .font(.system(size: 12))
                                    Text("COACHING")
                                        .font(ImprovingFont.microLabel(11))
                                        .foregroundColor(BevelColors.textSecondary)
                                }
                                Text(store.activeCoachingSummary)
                                    .font(ImprovingFont.body(13))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(18)
                }

                // 4. Estrés y Energía Section
                Text("Estrés y Energía")
                    .font(ImprovingFont.sectionTitle(18))
                    .foregroundColor(BevelColors.textPrimary)

                // Stress Card with Max/Min/Avg + Radial Dial
                Button { onNavigate(.estres) } label: {
                    BevelCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Estrés de hoy")
                                        .font(ImprovingFont.cardTitle(16))
                                        .foregroundColor(BevelColors.textPrimary)
                                    Text("Última actualización a las 14:32")
                                        .font(ImprovingFont.caption(12))
                                        .foregroundColor(BevelColors.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(BevelColors.textMuted)
                            }

                            HStack(alignment: .center) {
                                HStack(spacing: 14) {
                                    stressStatColumn(val: "\(stressMax)", label: "Máximo", color: BevelColors.amberStart)
                                    Rectangle().fill(BevelColors.divider).frame(width: 1, height: 34)
                                    stressStatColumn(val: "\(stressMin)", label: "Mínimo", color: BevelColors.emeraldEnd)
                                    Rectangle().fill(BevelColors.divider).frame(width: 1, height: 34)
                                    stressStatColumn(val: "\(stressAvg)", label: "Media", color: BevelColors.emeraldEnd)
                                }
                                Spacer()
                                StressRadialDial(score: store.stressScore, statusLabel: store.stressStatusLabel, size: 108, isHeroGauge: false, hasData: avail.hasStressData)
                            }
                        }
                        .padding(18)
                    }
                }

                // Energy Bank Card with 34 Vertical Capsules
                EnergyBankBatteryBar(percent: store.energyPercent, hasData: avail.hasEnergyData, onClick: { onNavigate(.energia) })

                // 5. Monitor de Salud (2x3 Grid with Vertical Thermometer Pills)
                HStack {
                    Text("Monitor de salud")
                        .font(ImprovingFont.sectionTitle(18))
                        .foregroundColor(BevelColors.textPrimary)
                    Spacer()
                    Text("Base 90 días")
                        .font(ImprovingFont.caption(12))
                        .foregroundColor(BevelColors.textSecondary)
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    HealthMonitorRangeCard(
                        title: "Frecuencia respiratoria",
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
                        value: avail.hasSpo2Data ? String(format: "%.1f", locale: Locale(identifier: "es_ES"), Double(store.spo2Percent) + 0.2) : "--",
                        unit: "%",
                        systemIcon: "drop.fill",
                        evaluation: spo2Eval,
                        onClick: { onSelectHealthMetric(.oxygenSaturation) }
                    )
                    HealthMonitorRangeCard(
                        title: "Temp. muñeca",
                        value: avail.hasTempData ? String(format: "%.1f", locale: Locale(identifier: "es_ES"), tempAbs) : "--",
                        unit: "°C",
                        systemIcon: "thermometer.medium",
                        evaluation: tempEval,
                        onClick: { onSelectHealthMetric(.wristTemperature) }
                    )
                    HealthMonitorRangeCard(
                        title: "Sueño",
                        value: store.sleepDurationText.replacingOccurrences(of: " min", with: "m").replacingOccurrences(of: " h ", with: "h "),
                        unit: "",
                        systemIcon: "moon.fill",
                        evaluation: sleepEval,
                        onClick: { onSelectHealthMetric(.sleepDuration) }
                    )
                }

                // Monitor de Salud Summary Banner
                BevelCard(cornerRadius: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(BevelColors.emeraldEnd)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(BevelColors.greenSoftBg))
                        Text("Nivel óptimo hoy: FCR mejoran tu línea base.")
                            .font(ImprovingFont.body(13))
                            .fontWeight(.medium)
                            .foregroundColor(BevelColors.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }

                // 6. Actividad y Nutrición
                Text("Actividad y Nutrición")
                    .font(ImprovingFont.sectionTitle(18))
                    .foregroundColor(BevelColors.textPrimary)

                BevelCard {
                    VStack(spacing: 14) {
                        if let w = store.workoutsToday.first {
                            Button { onNavigate(.esfuerzo) } label: {
                                HStack(spacing: 12) {
                                    Text("🏃")
                                        .font(.system(size: 20))
                                        .frame(width: 44, height: 44)
                                        .background(RoundedRectangle(cornerRadius: 14).fill(BevelColors.amberSoftBg))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(w.title)
                                            .font(ImprovingFont.cardTitle(14.5))
                                            .foregroundColor(BevelColors.textPrimary)
                                        Text("\(w.timeRange) · \(w.kcal) kcal · \(w.avgHrBpm) bpm media")
                                            .font(ImprovingFont.caption(11.5))
                                            .foregroundColor(BevelColors.textSecondary)
                                    }
                                    Spacer()
                                    Text("\(w.strainPct)%")
                                        .font(ImprovingFont.caption(12))
                                        .fontWeight(.bold)
                                        .monospacedDigit()
                                        .foregroundColor(BevelColors.orangeEnd)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Capsule().fill(BevelColors.amberSoftBg))
                                }
                            }
                        }

                        Divider().background(BevelColors.divider)

                        let meals = store.mealsByDate[store.selectedDateIso] ?? []
                        let totalKcal = meals.reduce(0) { $0 + $1.kcal }
                        let totalProt = meals.reduce(0) { $0 + $1.proteinG }
                        let avgScore = meals.isEmpty ? 86 : meals.reduce(0) { $0 + $1.qualityScore } / meals.count

                        Button { onNavigate(.nutricion) } label: {
                            HStack(spacing: 12) {
                                Text("🥑")
                                    .font(.system(size: 20))
                                    .frame(width: 44, height: 44)
                                    .background(RoundedRectangle(cornerRadius: 14).fill(BevelColors.greenSoftBg))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Nutrición · \(meals.count) Comidas")
                                        .font(ImprovingFont.cardTitle(14.5))
                                        .foregroundColor(BevelColors.textPrimary)
                                    Text("\(totalKcal) kcal · \(totalProt)g Prot · CGM 94 mg/dL")
                                        .font(ImprovingFont.caption(11.5))
                                        .foregroundColor(BevelColors.textSecondary)
                                }
                                Spacer()
                                Text("Calidad \(avgScore)")
                                    .font(ImprovingFont.caption(12))
                                    .fontWeight(.bold)
                                    .foregroundColor(BevelColors.emeraldEnd)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(BevelColors.greenSoftBg))
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 120)
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

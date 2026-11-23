import SwiftUI

struct HoyScreen: View {
    @ObservedObject var store: ImprovingStore
    let onNavigate: (OverlayRoute) -> Void
    let onSelectHealthMetric: (HealthMetricKind) -> Void

    @State private var showCalendarSheet: Bool = false

    var body: some View {
        let avail = store.dataAvailability
        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: store.userProfile)
        let respEval = WhoopPhysiologyEngine.evaluateVital(value: store.respRateRpm, bandLow: norms.respLowRpm, bandHigh: norms.respHighRpm, lowerIsBetter: true, hasData: avail.hasRespData)
        let rhrEval = WhoopPhysiologyEngine.evaluateVital(value: store.restingHrBpm, bandLow: norms.rhrLowBpm, bandHigh: norms.rhrHighBpm, lowerIsBetter: true, hasData: avail.hasRestingHrData)
        let hrvEval = WhoopPhysiologyEngine.evaluateVital(value: store.hrvMs, bandLow: norms.hrvLowMs, bandHigh: norms.hrvHighMs, higherIsBetter: true, hasData: avail.hasHrvData)
        let spo2Eval = WhoopPhysiologyEngine.evaluateVital(value: store.spo2DisplayDouble, bandLow: 95.0, bandHigh: 100.0, higherIsBetter: true, hasData: avail.hasSpo2Data)
        let tempAbs = store.wristTempAbsoluteC ?? 0
        let tempEval = WhoopPhysiologyEngine.evaluateVital(value: tempAbs, bandLow: 35.5, bandHigh: 36.6, hasData: avail.hasTempData)
        let sleepHours = Double(store.currentDaySummary?.asleepMinutes ?? 0) / 60.0
        let sleepEval = WhoopPhysiologyEngine.evaluateVital(value: sleepHours, bandLow: norms.sleepLowHours, bandHigh: norms.sleepHighHours, higherIsBetter: true, hasData: avail.hasSleepData)

        let vitalsList = [respEval, rhrEval, hrvEval, spo2Eval, tempEval, sleepEval]
        let recordedVitals = vitalsList.filter { $0.severity != .noData }
        let outOfRangeCount = recordedVitals.filter { $0.severity == .borderlineWarning || $0.severity == .alertOutOfRange }.count

        let cardioWindow = store.trailingCalendarSummaries(days: 7)
        let cardioSeries: [Double?] = cardioWindow.map { item in
            guard let s = item.summary?.strainPct else { return nil }
            return AppleHealthExportImporter.round1(Double(s) * 0.45)
        }
        let realCardioVals = cardioSeries.compactMap { $0 }
        let latestCardioVal = realCardioVals.last

        let initials = store.userProfile.userName.isEmpty
            ? "UI"
            : String(store.userProfile.userName.prefix(2)).uppercased()

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 1. Top Bar with Dropdown Calendar Picker + < Date > Navigation Arrows
                HStack(spacing: 8) {
                    Button { showCalendarSheet = true } label: {
                        Image(systemName: "calendar")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(BevelColors.textPrimary)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(BevelColors.glassChromeFill))
                            .overlay(Circle().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.8))
                    }

                    Spacer(minLength: 4)

                    HStack(spacing: 8) {
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            store.shiftDay(1)
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(BevelColors.textPrimary)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(BevelColors.glassChromeFill))
                                .overlay(Circle().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.7))
                        }

                        Button { showCalendarSheet = true } label: {
                            HStack(spacing: 4) {
                                Text(store.dateLabel)
                                    .font(ImprovingFont.sectionTitle(16.5))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(BevelColors.textSecondary)
                            }
                        }

                        Button {
                            if store.dayOffset > 0 {
                                UISelectionFeedbackGenerator().selectionChanged()
                                store.shiftDay(-1)
                            }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(store.dayOffset > 0 ? BevelColors.textPrimary : BevelColors.textMuted.opacity(0.35))
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(BevelColors.glassChromeFill.opacity(store.dayOffset > 0 ? 1 : 0.45)))
                                .overlay(Circle().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.7))
                        }
                        .disabled(store.dayOffset == 0)
                    }

                    Spacer(minLength: 4)

                    HStack(spacing: 8) {
                        Button { onNavigate(.dispositivos) } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14, weight: .medium))
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
                    .padding(.horizontal, 10)
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

                // 2. Hero Card: 3 Recessed Rings + Vertical Dividers + Coaching
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
                                    targetRange: avail.hasRecoveryData ? store.optimalEffortRange : nil,
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

                        LiveAiCoachingCard(
                            section: .hoy,
                            store: store,
                            embedded: true,
                            onAskMore: { onNavigate(.askBevel) }
                        )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }

                // 3. Estrés y Energía Section (Zero Fabricated Defaults)
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
                                            .fill(avail.hasStressData ? BevelColors.greenPrimary : BevelColors.textMuted)
                                            .frame(width: 8, height: 8)
                                        Text("Estrés de hoy")
                                            .font(ImprovingFont.cardTitle(15.5))
                                            .foregroundColor(BevelColors.textPrimary)
                                    }
                                    Text(store.lastStressSampleTimeLabel.map { "Última lectura a las \($0)" } ?? "Sin mediciones este día")
                                        .font(ImprovingFont.caption(12))
                                        .foregroundColor(BevelColors.textMuted)
                                }

                                HStack(spacing: 14) {
                                    stressStatColumn(
                                        val: store.stressMax.map { "\($0)" } ?? "--",
                                        label: "Máximo",
                                        color: store.stressMax != nil ? BevelColors.coralHigh : BevelColors.textMuted
                                    )
                                    Rectangle().fill(BevelColors.divider).frame(width: 1, height: 34)
                                    stressStatColumn(
                                        val: store.stressMin.map { "\($0)" } ?? "--",
                                        label: "Mínimo",
                                        color: store.stressMin != nil ? BevelColors.tealLow : BevelColors.textMuted
                                    )
                                    Rectangle().fill(BevelColors.divider).frame(width: 1, height: 34)
                                    stressStatColumn(
                                        val: store.stressAvg.map { "\($0)" } ?? "--",
                                        label: "Media",
                                        color: store.stressAvg != nil ? BevelColors.tealLow : BevelColors.textMuted
                                    )
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

                EnergyBankBatteryBar(percent: store.energyPercent, hasData: avail.hasEnergyData, onClick: { onNavigate(.energia) })

                // 4. Monitor de salud (2x3 Grid)
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

                // Honest Health Monitor status bar
                if recordedVitals.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 15))
                            .foregroundColor(BevelColors.textMuted)
                        Text("No se recopilaron métricas de salud en esta fecha.")
                            .font(ImprovingFont.body(13))
                            .foregroundColor(BevelColors.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(BevelColors.card))
                } else {
                    let allNormal = outOfRangeCount == 0
                    let bannerColor = allNormal ? BevelColors.greenPrimary : BevelColors.amberStart
                    let bannerBg = allNormal ? BevelColors.greenSoftBg : BevelColors.amberSoftBg
                    HStack(spacing: 10) {
                        Image(systemName: allNormal ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 15))
                            .foregroundColor(bannerColor)
                        Text(allNormal
                            ? (recordedVitals.count == 6 ? "Todas las métricas están dentro del rango normal." : "\(recordedVitals.count) de 6 métricas registradas, todas en rango normal.")
                            : "\(outOfRangeCount) métrica(s) fuera de tu rango habitual hoy.")
                            .font(ImprovingFont.body(13))
                            .foregroundColor(bannerColor)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(bannerBg))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(bannerColor.opacity(0.3), lineWidth: 0.8))
                }

                // 5. Carga cardíaca Preview Card (Real data only)
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
                                    Text(latestCardioVal.map { "\(Int($0.rounded()))" } ?? "Sin datos")
                                        .font(ImprovingFont.metricHero(latestCardioVal != nil ? 26 : 20))
                                        .foregroundColor(latestCardioVal != nil ? BevelColors.textPrimary : BevelColors.textMuted)
                                    Text(latestCardioVal != nil ? "Basado en tus últimos 7 días" : "Sin registros de esfuerzo")
                                        .font(ImprovingFont.caption(12))
                                        .foregroundColor(latestCardioVal != nil ? BevelColors.greenPrimary : BevelColors.textMuted)
                                }
                                Spacer()
                                if realCardioVals.count >= 2 {
                                    TrendSparklineWithBand(optionalPoints: cardioSeries, bandLow: 24, bandHigh: 44, lineColor: BevelColors.periwinkleStart, showBand: true, showGlowDot: true)
                                        .frame(width: 120, height: 48)
                                }
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
                                        let meta = [
                                            w.timeRange,
                                            w.kcal > 0 ? "\(w.kcal) kcal" : nil,
                                            w.avgHrBpm > 0 ? "\(w.avgHrBpm) ppm" : nil
                                        ].compactMap { $0 }.joined(separator: " · ")
                                        Text(meta)
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
                            Divider().background(BevelColors.divider)
                        }

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
                                    if let fq = store.foodQualityScore {
                                        Text("\(store.totalCaloriesToday) kcal · \(store.totalProteinToday)g Prot · Calidad \(fq)")
                                            .font(ImprovingFont.caption(12))
                                            .foregroundColor(BevelColors.textSecondary)
                                    } else {
                                        Text("Sin comidas registradas este día")
                                            .font(ImprovingFont.caption(12))
                                            .foregroundColor(BevelColors.textSecondary)
                                    }
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
        .sheet(isPresented: $showCalendarSheet) {
            DatePickerSheetView(
                selectedDate: Binding(
                    get: { store.selectedDate },
                    set: { newDate in
                        store.selectDate(newDate)
                        showCalendarSheet = false
                    }
                ),
                onJumpToday: {
                    store.selectDayOffset(0)
                    showCalendarSheet = false
                },
                onClose: { showCalendarSheet = false }
            )
        }
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

// MARK: - Dropdown Graphical Calendar Picker Sheet

struct DatePickerSheetView: View {
    @Binding var selectedDate: Date
    let onJumpToday: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Capsule().fill(BevelColors.trackGroove).frame(width: 40, height: 4).padding(.top, 10)
            HStack {
                Text("Elegir fecha")
                    .font(ImprovingFont.sectionTitle(18))
                    .foregroundColor(BevelColors.textPrimary)
                Spacer()
                Button("Hoy", action: onJumpToday)
                    .font(ImprovingFont.caption(13))
                    .fontWeight(.bold)
                    .foregroundColor(BevelColors.greenPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(BevelColors.greenSoftBg))
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(BevelColors.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(BevelColors.card))
                }
            }
            .padding(.horizontal, 20)

            DatePicker(
                "Fecha",
                selection: $selectedDate,
                in: ...Date(),
                displayedComponents: [.date]
            )
            .datePickerStyle(.graphical)
            .tint(BevelColors.greenPrimary)
            .environment(\.locale, Locale(identifier: "es_ES"))
            .padding(.horizontal, 12)

            Spacer(minLength: 8)
        }
        .background(BevelColors.sheetHeaderBg.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }
}

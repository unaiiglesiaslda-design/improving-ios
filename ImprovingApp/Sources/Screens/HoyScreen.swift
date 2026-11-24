import SwiftUI

struct HoyScreen: View {
    @ObservedObject var store: ImprovingStore
    let onNavigate: (OverlayRoute) -> Void
    let onSelectHealthMetric: (HealthMetricKind) -> Void
    var onOpenWorkout: ((EffortEventItem) -> Void)? = nil

    @State private var showCalendarSheet: Bool = false
    @State private var showShareDailySheet: Bool = false
    @State private var showEditHomeSheet: Bool = false
    @State private var editHomeFocusHealth: Bool = false
    @State private var deepPullOffset: CGFloat = 0
    @State private var deepPullTriggered: Bool = false
    @State private var lastDeepPullAt: Date = .distantPast
    private let deepPullThreshold: CGFloat = 135.0

    var body: some View {
        let avail = store.dataAvailability
        let respBand = store.personalVitalNormalBand(for: .respiratoryRate)
        let rhrBand = store.personalVitalNormalBand(for: .restingHeartRate)
        let hrvBand = store.personalVitalNormalBand(for: .hrv)
        let spo2Band = store.personalVitalNormalBand(for: .oxygenSaturation)
        let tempBand = store.personalVitalNormalBand(for: .wristTemperature)
        let sleepBand = store.personalVitalNormalBand(for: .sleepDuration)

        let respEval = WhoopPhysiologyEngine.evaluateVital(value: store.respRateRpm, bandLow: respBand.low, bandHigh: respBand.high, lowerIsBetter: true, hasData: avail.hasRespData)
        let rhrEval = WhoopPhysiologyEngine.evaluateVital(value: store.restingHrBpm, bandLow: rhrBand.low, bandHigh: rhrBand.high, lowerIsBetter: true, hasData: avail.hasRestingHrData)
        let hrvEval = WhoopPhysiologyEngine.evaluateVital(value: store.hrvMs, bandLow: hrvBand.low, bandHigh: hrvBand.high, higherIsBetter: true, hasData: avail.hasHrvData)
        let spo2Eval = WhoopPhysiologyEngine.evaluateVital(value: store.spo2DisplayDouble, bandLow: spo2Band.low, bandHigh: spo2Band.high, higherIsBetter: true, hasData: avail.hasSpo2Data)
        let tempAbs = store.wristTempAbsoluteC ?? 0
        let tempEval = WhoopPhysiologyEngine.evaluateVital(value: tempAbs, bandLow: tempBand.low, bandHigh: tempBand.high, hasData: avail.hasTempData)
        let sleepHours = Double(store.currentDaySummary?.asleepMinutes ?? 0) / 60.0
        let sleepEval = WhoopPhysiologyEngine.evaluateVital(value: sleepHours, bandLow: sleepBand.low, bandHigh: sleepBand.high, higherIsBetter: true, hasData: avail.hasSleepData)

        let evalMap: [HealthMetricKind: VitalEvaluation] = [
            .respiratoryRate: respEval,
            .restingHeartRate: rhrEval,
            .hrv: hrvEval,
            .oxygenSaturation: spo2Eval,
            .wristTemperature: tempEval,
            .sleepDuration: sleepEval
        ]
        let visibleHealthKinds = HealthMetricKind.allCases.filter { store.homeLayout.isHealthMetricVisible($0) }
        let recordedVitals = visibleHealthKinds.compactMap { evalMap[$0] }.filter { $0.severity != .noData }
        let outOfRangeCount = recordedVitals.filter { $0.severity == .borderlineWarning || $0.severity == .alertOutOfRange }.count

        // P4: Exact EWMA Cardio Training Load unified 100% with FitnessScreen!
        let cardioAnalysis = store.trainingLoadAnalysis(tab: .cardio, spanDays: 14, windowPageOffset: 0)
        let cardioSeries: [Double?] = cardioAnalysis.points.map { $0.load }
        let weeklySummary = store.computeWeeklyReview()
        let initials = store.userProfile.initials

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Deep deliberate pull-down overscroll sensor (>= 135 pt required — zero accidental reloads or vibration!)
                GeometryReader { geo in
                    let minY = geo.frame(in: .named("hoyScrollSpace")).minY
                    Color.clear
                        .onChange(of: minY) { _, newY in
                            let clamped = max(newY, 0)
                            deepPullOffset = clamped
                            if clamped >= deepPullThreshold && !deepPullTriggered && Date().timeIntervalSince(lastDeepPullAt) > 6.0 {
                                deepPullTriggered = true
                                lastDeepPullAt = Date()
                                Task {
                                    await store.handlePullToRefresh()
                                }
                            } else if clamped < 12 {
                                deepPullTriggered = false
                            }
                        }
                }
                .frame(height: 0)

                if deepPullOffset > 45 && store.syncBannerState == .hidden {
                    let progress = min(max((deepPullOffset - 45) / (deepPullThreshold - 45), 0), 1)
                    HStack(spacing: 8) {
                        Image(systemName: progress >= 1 ? "checkmark.circle.fill" : "arrow.down.circle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(progress >= 1 ? BevelColors.emeraldEnd : BevelColors.textSecondary)
                        Text(progress >= 1 ? "Sincronizando…" : "Desliza más para sincronizar")
                            .font(ImprovingFont.caption(12))
                            .foregroundColor(BevelColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .opacity(Double(min(progress * 1.4, 1.0)))
                }

                // 1. Top Bar with Dropdown Calendar Picker + < Date > + Real Daily Share Card & Profile Avatar (P1!)
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
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            showShareDailySheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(BevelColors.textPrimary)
                        }
                        Button { onNavigate(.dispositivos) } label: {
                            UserProfileAvatarView(
                                photoPath: store.userProfile.profilePhotoPath,
                                initials: initials,
                                size: 28,
                                showGradientRing: store.userProfile.profilePhotoPath != nil,
                                ringWidth: 1.5
                            )
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

                // Customizable Ordered Home Sections (N2!)
                ForEach(store.homeLayout.normalizedOrder) { section in
                    if store.homeLayout.isSectionVisible(section) {
                        homeSectionView(
                            section,
                            avail: avail,
                            visibleHealthKinds: visibleHealthKinds,
                            evalMap: evalMap,
                            tempAbs: tempAbs,
                            recordedVitals: recordedVitals,
                            outOfRangeCount: outOfRangeCount,
                            cardioAnalysis: cardioAnalysis,
                            cardioSeries: cardioSeries,
                            weeklySummary: weeklySummary
                        )
                    }
                }

                // Signature Bevel Bottom Action Pills: "Editar Inicio" + "Ver todas las categorías" (Screenshot 1 & N2!)
                VStack(spacing: 12) {
                    Divider()
                        .background(BevelColors.divider)
                        .padding(.vertical, 4)

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        editHomeFocusHealth = false
                        showEditHomeSheet = true
                    } label: {
                        Text("Editar Inicio")
                            .font(ImprovingFont.cardTitle(15.5))
                            .foregroundColor(BevelColors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Capsule().fill(BevelColors.card))
                            .overlay(Capsule().strokeBorder(BevelColors.cardBorder, lineWidth: 0.9))
                    }
                    .buttonStyle(.plain)

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onNavigate(.allCategories)
                    } label: {
                        Text("Ver todas las categorías")
                            .font(ImprovingFont.cardTitle(15.5))
                            .foregroundColor(BevelColors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Capsule().fill(BevelColors.card))
                            .overlay(Capsule().strokeBorder(BevelColors.cardBorder, lineWidth: 0.9))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 155)
        }
        .coordinateSpace(name: "hoyScrollSpace")
        .background(BevelColors.canvas)
        .overlay(alignment: .top) {
            SyncStatusBubbleOverlay(state: store.syncBannerState)
                .padding(.top, 10)
        }
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
        .sheet(isPresented: $showShareDailySheet) {
            ShareSummaryCardSheet(store: store, kind: .dailyOverview, onClose: { showShareDailySheet = false })
        }
        .sheet(isPresented: $showEditHomeSheet) {
            HomeLayoutEditorSheet(
                store: store,
                initialFocusHealthMonitor: editHomeFocusHealth,
                onClose: { showEditHomeSheet = false }
            )
        }
    }

    @ViewBuilder
    private func homeSectionView(
        _ section: HomeSectionKind,
        avail: DataAvailabilitySnapshot,
        visibleHealthKinds: [HealthMetricKind],
        evalMap: [HealthMetricKind: VitalEvaluation],
        tempAbs: Double,
        recordedVitals: [VitalEvaluation],
        outOfRangeCount: Int,
        cardioAnalysis: TrainingLoadAnalysis,
        cardioSeries: [Double?],
        weeklySummary: WeeklyReviewReport
    ) -> some View {
        switch section {
        case .heroRings:
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

        case .stressEnergy:
            VStack(alignment: .leading, spacing: 14) {
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
                                    Text(
                                        store.dayOffset == 0
                                            ? (store.lastStressSampleTimeLabel.map { "Última lectura a las \($0)" } ?? "Sin mediciones este día")
                                            : (avail.hasStressData ? "Media diaria · \(store.stressSamplesToday.count) lecturas" : "Sin mediciones este día")
                                    )
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
                                StressRadialDial(score: store.displayStressScore, statusLabel: store.stressStatusLabel, size: 96, isHeroGauge: false, hasData: avail.hasStressData)
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
            }

        case .healthMonitor:
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Monitor de salud")
                        .font(ImprovingFont.sectionTitle(18.5))
                        .foregroundColor(BevelColors.textPrimary)
                    Spacer()
                    Button("Editar >") {
                        editHomeFocusHealth = true
                        showEditHomeSheet = true
                    }
                    .font(ImprovingFont.caption(13))
                    .foregroundColor(BevelColors.textSecondary)
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(visibleHealthKinds) { kind in
                        healthMonitorTile(kind: kind, avail: avail, eval: evalMap[kind] ?? WhoopPhysiologyEngine.evaluateVital(value: 0, bandLow: 0, bandHigh: 1, hasData: false), tempAbs: tempAbs)
                    }
                }

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
                            ? (recordedVitals.count == visibleHealthKinds.count ? "Todas las métricas están dentro del rango normal." : "\(recordedVitals.count) de \(visibleHealthKinds.count) métricas registradas, todas en rango normal.")
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
            }

        case .cardioLoad:
            VStack(alignment: .leading, spacing: 12) {
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
                                    Text(cardioAnalysis.hasAnyData ? "\(cardioAnalysis.currentLoad)" : "Sin datos")
                                        .font(ImprovingFont.metricHero(cardioAnalysis.hasAnyData ? 26 : 20))
                                        .monospacedDigit()
                                        .foregroundColor(cardioAnalysis.hasAnyData ? BevelColors.textPrimary : BevelColors.textMuted)
                                    Text(cardioAnalysis.hasAnyData ? cardioAnalysis.currentState.rawValue : "Sin registros de esfuerzo")
                                        .font(ImprovingFont.caption(12.5))
                                        .fontWeight(.semibold)
                                        .foregroundColor(cardioAnalysis.hasAnyData ? cardioAnalysis.currentState.accentColor : BevelColors.textMuted)
                                }
                                Spacer()
                                if cardioAnalysis.hasAnyData && cardioSeries.compactMap({ $0 }).count >= 2 {
                                    TrendSparklineWithBand(
                                        optionalPoints: cardioSeries,
                                        bandLow: Double(cardioAnalysis.optimalLow),
                                        bandHigh: Double(cardioAnalysis.optimalHigh),
                                        lineColor: BevelColors.periwinkleStart,
                                        showBand: true,
                                        showGlowDot: true
                                    )
                                    .frame(width: 132, height: 50)
                                }
                            }
                        }
                        .padding(16)
                    }
                }
                .buttonStyle(.plain)
            }

        case .nutrition:
            VStack(alignment: .leading, spacing: 12) {
                Text("Nutrición")
                    .font(ImprovingFont.sectionTitle(18.5))
                    .foregroundColor(BevelColors.textPrimary)

                NutritionHomeSummaryCard(store: store) {
                    onNavigate(.nutricion)
                }
            }

        case .weeklyReview:
            VStack(alignment: .leading, spacing: 12) {
                Text("Resumen semanal")
                    .font(ImprovingFont.sectionTitle(18.5))
                    .foregroundColor(BevelColors.textPrimary)

                Button { onNavigate(.weeklyReview) } label: {
                    BevelCard(cornerRadius: 20) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                HStack(spacing: 7) {
                                    Image(systemName: "calendar.badge.checkmark")
                                        .font(.system(size: 13.5, weight: .semibold))
                                        .foregroundColor(BevelColors.periwinkleStart)
                                    Text("Últimos 7 días · \(weeklySummary.dateRangeLabel)")
                                        .font(ImprovingFont.caption(13))
                                        .foregroundColor(BevelColors.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(BevelColors.textMuted)
                            }

                            HStack(spacing: 10) {
                                weeklyMiniStat(
                                    label: "Recup.",
                                    value: weeklySummary.avgRecovery.map { "\($0)%" } ?? "--",
                                    delta: weeklySummary.recoveryDelta.map { ($0 >= 0 ? "+\($0)" : "\($0)") },
                                    positive: (weeklySummary.recoveryDelta ?? 0) >= 0
                                )
                                weeklyMiniStat(
                                    label: "Entrenos",
                                    value: "\(weeklySummary.workoutsCount)",
                                    delta: "\(weeklySummary.totalWorkoutMinutes)m",
                                    positive: true
                                )
                                weeklyMiniStat(
                                    label: "Nutrición",
                                    value: weeklySummary.avgNutritionScore.map { "\($0)" } ?? "--",
                                    delta: weeklySummary.avgHrv.map { String(format: "%.0fms", $0) } ?? "--",
                                    positive: true
                                )
                            }
                        }
                        .padding(16)
                    }
                }
                .buttonStyle(.plain)
            }

        case .recentActivity:
            if let w = store.workoutsToday.first {
                let st = WorkoutSportStyle.resolve(title: w.title, category: w.categoryLabel)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Actividad reciente")
                        .font(ImprovingFont.sectionTitle(18.5))
                        .foregroundColor(BevelColors.textPrimary)

                    Button {
                        if let onOpenWorkout {
                            onOpenWorkout(w)
                        } else {
                            onNavigate(.esfuerzo)
                        }
                    } label: {
                        BevelCard(cornerRadius: 20) {
                            HStack(spacing: 12) {
                                Image(systemName: st.icon)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(st.fg)
                                    .frame(width: 42, height: 42)
                                    .background(Circle().fill(st.bg))
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
                            .padding(16)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func healthMonitorTile(
        kind: HealthMetricKind,
        avail: DataAvailabilitySnapshot,
        eval: VitalEvaluation,
        tempAbs: Double
    ) -> some View {
        switch kind {
        case .respiratoryRate:
            HealthMonitorRangeCard(
                title: "FR",
                value: avail.hasRespData ? String(format: "%.1f", locale: Locale(identifier: "es_ES"), store.respRateRpm) : "--",
                unit: "rpm",
                systemIcon: "lungs.fill",
                evaluation: eval,
                onClick: { onSelectHealthMetric(.respiratoryRate) }
            )
        case .restingHeartRate:
            HealthMonitorRangeCard(
                title: "FCR",
                value: avail.hasRestingHrData ? String(format: "%.1f", locale: Locale(identifier: "es_ES"), store.restingHrBpm) : "--",
                unit: "ppm",
                systemIcon: "heart.fill",
                evaluation: eval,
                onClick: { onSelectHealthMetric(.restingHeartRate) }
            )
        case .hrv:
            HealthMonitorRangeCard(
                title: "VFC",
                value: avail.hasHrvData ? String(format: "%.1f", locale: Locale(identifier: "es_ES"), store.hrvMs) : "--",
                unit: "ms",
                systemIcon: "waveform.path.ecg",
                evaluation: eval,
                onClick: { onSelectHealthMetric(.hrv) }
            )
        case .oxygenSaturation:
            HealthMonitorRangeCard(
                title: "SpO₂",
                value: avail.hasSpo2Data ? String(format: "%.1f", locale: Locale(identifier: "es_ES"), store.spo2DisplayDouble) : "--",
                unit: "%",
                systemIcon: "drop.fill",
                evaluation: eval,
                onClick: { onSelectHealthMetric(.oxygenSaturation) }
            )
        case .wristTemperature:
            HealthMonitorRangeCard(
                title: "Temp.",
                value: avail.hasTempData ? String(format: "%.1f", locale: Locale(identifier: "es_ES"), tempAbs) : "--",
                unit: "°C",
                systemIcon: "thermometer.medium",
                evaluation: eval,
                onClick: { onSelectHealthMetric(.wristTemperature) }
            )
        case .sleepDuration:
            HealthMonitorRangeCard(
                title: "Sueño",
                value: store.sleepDurationText,
                unit: "",
                systemIcon: "bed.double.fill",
                evaluation: eval,
                onClick: { onSelectHealthMetric(.sleepDuration) }
            )
        }
    }

    private func weeklyMiniStat(label: String, value: String, delta: String?, positive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(ImprovingFont.caption(11))
                .foregroundColor(BevelColors.textMuted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(ImprovingFont.metricTile(17))
                    .monospacedDigit()
                    .foregroundColor(BevelColors.textPrimary)
                if let d = delta {
                    Text(d)
                        .font(ImprovingFont.caption(10.5))
                        .fontWeight(.semibold)
                        .foregroundColor(positive ? BevelColors.greenPrimary : BevelColors.amberStart)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(BevelColors.cardSubtle))
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

// MARK: - Top Floating Sync Status Bubble (Slides from Top Edge Over the Date & Vanishes Cleanly)

private struct SyncStatusBubbleOverlay: View {
    let state: SyncBannerState
    @State private var spinRotation: Double = 0

    var body: some View {
        ZStack {
            if state != .hidden {
                pillContent
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.86, anchor: .top)),
                            removal: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.86, anchor: .top))
                        )
                    )
            }
        }
        .animation(.spring(response: 0.44, dampingFraction: 0.80), value: state)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var pillContent: some View {
        let isSynced: Bool = {
            if case .synced = state { return true }
            return false
        }()
        let isNotice: Bool = {
            if case .notice = state { return true }
            return false
        }()
        let labelText: String = {
            switch state {
            case .hidden: return ""
            case .syncing(let t), .synced(let t), .notice(let t): return t
            }
        }()

        HStack(spacing: 7) {
            if isSynced {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundColor(BevelColors.emeraldEnd)
                    .transition(.scale.combined(with: .opacity))
            } else if isNotice {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundColor(BevelColors.amberStart)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(BevelColors.skyBlue)
                    .rotationEffect(.degrees(spinRotation))
                    .onAppear {
                        spinRotation = 0
                        withAnimation(.linear(duration: 1.05).repeatForever(autoreverses: false)) {
                            spinRotation = 360
                        }
                    }
                    .onDisappear {
                        spinRotation = 0
                    }
            }

            Text(labelText)
                .font(ImprovingFont.caption(12.5))
                .fontWeight(.bold)
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(BevelColors.isDarkMode ? Color(hex: 0x1E2332).opacity(0.96) : Color(hex: 0x171A22).opacity(0.94))
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    isSynced
                        ? BevelColors.emeraldEnd.opacity(0.55)
                        : (isNotice ? BevelColors.amberStart.opacity(0.50) : BevelColors.skyBlue.opacity(0.45)),
                    lineWidth: 0.9
                )
        )
        .shadow(color: Color.black.opacity(0.24), radius: 12, x: 0, y: 5)
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

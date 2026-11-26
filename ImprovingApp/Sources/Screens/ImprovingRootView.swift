import SwiftUI

struct ImprovingRootView: View {
    @EnvironmentObject var store: ImprovingStore
    @ObservedObject private var themeSettings = ThemeSettings.shared

    @State private var selectedTab: MainTab = .hoy
    @State private var overlayStack: [OverlayRoute] = []
    @State private var quickMenuOpen: Bool = false
    @State private var isBottomBarCollapsed: Bool = false
    @State private var trainingLoadTab: TrainingLoadTab = .cardio
    @State private var cardioRoute: CardioMetricRoute = .activitiesDuration
    @State private var showLaunchSplash: Bool = true

    // Quick Action 1-tap sheets (P7!)
    @State private var showQuickNoteSheet: Bool = false
    @State private var quickNoteDraft: String = ""
    @State private var showQuickScaleSheet: Bool = false
    @State private var showQuickWorkoutSheet: Bool = false

    private var currentOverlay: OverlayRoute { overlayStack.last ?? .none }

    var body: some View {
        ZStack(alignment: .bottom) {
            BevelColors.canvas.ignoresSafeArea()

            if !store.userProfile.onboardingCompleted {
                OnboardingExperienceView(
                    initialProfile: store.userProfile,
                    healthAuthorized: store.healthKitAuthorized,
                    healthStatusText: store.healthKitLastSyncText,
                    onConnectAppleHealth: { store.connectAndSyncAppleHealth() },
                    onFinish: { completedProfile in
                        withAnimation(.easeInOut(duration: 0.35)) {
                            store.completeOnboarding(completedProfile)
                        }
                    }
                )
                .transition(.opacity)
            } else {
                ZStack(alignment: .bottom) {
                    Group {
                        switch selectedTab {
                        case .hoy:
                            HoyScreen(
                                store: store,
                                onNavigate: { push($0) },
                                onSelectHealthMetric: { kind in
                                    store.selectedHealthMetric = kind
                                    push(.healthMetricDetail)
                                },
                                onOpenWorkout: { w in
                                    store.selectWorkout(w)
                                    push(.workoutDetail)
                                }
                            )
                        case .diario:
                            DiarioScreen(store: store, onNavigate: { push($0) })
                        case .fitness:
                            FitnessScreen(
                                store: store,
                                onNavigate: { push($0) },
                                onOpenTrainingLoad: { t in
                                    trainingLoadTab = t
                                    push(.trainingLoad)
                                },
                                onOpenCardioMetric: { c in
                                    cardioRoute = c
                                    push(.cardioMetricDetail)
                                },
                                onOpenWorkout: { w in
                                    store.selectWorkout(w)
                                    push(.workoutDetail)
                                }
                            )
                        case .biologia:
                            BiologiaScreen(
                                store: store,
                                onSelectHealthMetric: { kind in
                                    store.selectedHealthMetric = kind
                                    push(.healthMetricDetail)
                                },
                                onOpenBodyMetric: { bodyKind in
                                    store.selectedBodyMetric = bodyKind
                                    push(.bodyCompositionDetail)
                                },
                                onOpenVo2Max: {
                                    cardioRoute = .vo2Max
                                    push(.cardioMetricDetail)
                                },
                                onNavigate: { push($0) }
                            )
                        }
                    }

                    if currentOverlay != .none {
                        overlayView(for: currentOverlay)
                            .transition(.move(edge: currentOverlay == .askBevel ? .bottom : .trailing).combined(with: .opacity))
                            .zIndex(5)
                    }

                    if quickMenuOpen && currentOverlay != .askBevel {
                        QuickActionsOverlaySheet(
                            hydrationTodayMl: Int(store.totalHydrationTodayMl.rounded()),
                            onDismiss: { quickMenuOpen = false },
                            onCaptureFoodAI: {
                                store.pendingNutritionLaunchMode = .camera
                                push(.nutricion)
                            },
                            onScanBarcode: {
                                store.pendingNutritionLaunchMode = .barcode
                                push(.nutricion)
                            },
                            onDescribeFoodAI: {
                                store.pendingNutritionLaunchMode = .standard
                                push(.nutricion)
                            },
                            onAddWater250ml: {
                                store.addNutrientAmount(key: "Hidratación", amount: 250)
                            },
                            onOpenAskBevel: {
                                push(.askBevel)
                            },
                            onQuickJournalNote: {
                                quickMenuOpen = false
                                quickNoteDraft = store.journalNote()
                                showQuickNoteSheet = true
                            },
                            onLogScale: {
                                quickMenuOpen = false
                                showQuickScaleSheet = true
                            },
                            onLogWorkout: {
                                quickMenuOpen = false
                                showQuickWorkoutSheet = true
                            },
                            onOpenWeeklyReview: {
                                push(.weeklyReview)
                            },
                            onOpenDevices: {
                                push(.dispositivos)
                            }
                        )
                        .zIndex(15)
                    }

                    if currentOverlay == .none {
                        FloatingPillBottomBar(
                            selectedTab: selectedTab,
                            visibleTabs: store.visibleTabs,
                            isQuickMenuOpen: quickMenuOpen,
                            isCollapsed: isBottomBarCollapsed,
                            onSelectTab: { tab in
                                isBottomBarCollapsed = false
                                selectTab(tab)
                            },
                            onToggleQuickMenu: {
                                isBottomBarCollapsed = false
                                withAnimation { quickMenuOpen.toggle() }
                            },
                            onOpenAskBevel: {
                                push(.askBevel)
                            },
                            onExpand: {
                                isBottomBarCollapsed = false
                            }
                        )
                        .zIndex(20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .onVerticalScrollCollapse {
                    if !quickMenuOpen && currentOverlay != .askBevel && !isBottomBarCollapsed {
                        isBottomBarCollapsed = true
                    }
                }
            }

            if showLaunchSplash {
                LaunchMotionGraphicOverlay(isOnboardingNext: !store.userProfile.onboardingCompleted) {
                    withAnimation(.easeOut(duration: 0.35)) {
                        showLaunchSplash = false
                    }
                }
                .zIndex(50)
            }
        }
        .preferredColorScheme(themeSettings.isDarkMode ? .dark : .light)
        .animation(.easeInOut(duration: 0.25), value: currentOverlay)
        .onChange(of: store.pendingDeepLinkRoute) { _, req in
            guard let req else { return }
            showLaunchSplash = false
            quickMenuOpen = false
            switch req.destination {
            case .hoy:
                selectedTab = .hoy
                overlayStack = []
            case .diario:
                selectedTab = .diario
                overlayStack = []
            case .fitness:
                selectedTab = .fitness
                overlayStack = []
            case .biologia:
                selectedTab = .biologia
                overlayStack = []
            case .nutricion:
                selectedTab = .hoy
                overlayStack = [.nutricion]
            case .sueno:
                selectedTab = .hoy
                overlayStack = [.suenoDetail]
            case .esfuerzo:
                selectedTab = .hoy
                overlayStack = [.esfuerzo]
            case .dispositivos:
                overlayStack = [.dispositivos]
            case .askBevel:
                overlayStack = [.askBevel]
            }
            store.pendingDeepLinkRoute = nil
        }
        .sheet(isPresented: $showQuickNoteSheet) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Nota rápida para \(store.dateLabel) (visible para tu Coach IA)")
                        .font(ImprovingFont.caption(13))
                        .foregroundColor(BevelColors.textSecondary)
                    TextEditor(text: $quickNoteDraft)
                        .font(ImprovingFont.body(15))
                        .foregroundColor(BevelColors.textPrimary)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .frame(minHeight: 130)
                        .background(RoundedRectangle(cornerRadius: 16).fill(BevelColors.card))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
                    Button {
                        store.setJournalNote(quickNoteDraft)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        showQuickNoteSheet = false
                    } label: {
                        Text("Guardar nota del día")
                            .font(ImprovingFont.cardTitle(15))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(BevelColors.emeraldEnd))
                    }
                    Spacer()
                }
                .padding(16)
                .background(BevelColors.canvas.ignoresSafeArea())
                .navigationTitle("Nota del Diario")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Cerrar") { showQuickNoteSheet = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showQuickScaleSheet) {
            ManualScaleLoggerSheet(store: store, onClose: { showQuickScaleSheet = false })
        }
        .sheet(isPresented: $showQuickWorkoutSheet) {
            StrengthSessionLoggerSheet(store: store, routine: nil, onClose: { showQuickWorkoutSheet = false })
        }
    }

    @ViewBuilder
    private func overlayView(for route: OverlayRoute) -> some View {
        switch route {
        case .none:
            EmptyView()
        case .esfuerzo:
            EsfuerzoScreen(
                store: store,
                onBack: { pop() },
                onOpenTrend: { item in
                    store.selectedTrendItem = item
                    push(.trendMetricDetail)
                },
                onOpenWorkout: { w in
                    store.selectWorkout(w)
                    push(.workoutDetail)
                }
            )
        case .recuperacion:
            RecuperacionScreen(
                store: store,
                onBack: { pop() },
                onSelectHealthMetric: { kind in
                    store.selectedHealthMetric = kind
                    push(.healthMetricDetail)
                },
                onOpenSleepSession: { push(.sleepSessionDetail) },
                onOpenTrend: { item in
                    store.selectedTrendItem = item
                    push(.trendMetricDetail)
                }
            )
        case .suenoDetail:
            SuenoDetailScreen(
                store: store,
                onBack: { pop() },
                onOpenSleepNeed: { push(.sleepNeedDetail) },
                onOpenSleepSession: { push(.sleepSessionDetail) },
                onOpenTrend: { item in
                    if item.id == "s_dur" {
                        store.selectedHealthMetric = .sleepDuration
                        push(.healthMetricDetail)
                    } else {
                        store.selectedTrendItem = item
                        push(.trendMetricDetail)
                    }
                }
            )
        case .sleepSessionDetail:
            SleepSessionDetailScreen(
                store: store,
                onBack: { pop() },
                onOpenSleepNeed: { push(.sleepNeedDetail) }
            )
        case .sleepNeedDetail:
            SleepNeedDetailScreen(store: store, onBack: { pop() })
        case .estres:
            EstresScreen(
                store: store,
                onBack: { pop() },
                onOpenTrend: { item in
                    store.selectedTrendItem = item
                    push(.trendMetricDetail)
                }
            )
        case .energia:
            EnergiaScreen(
                store: store,
                onBack: { pop() },
                onOpenSleepSession: { push(.sleepSessionDetail) }
            )
        case .nutricion:
            NutricionScreen(
                store: store,
                onBack: { pop() },
                onOpenNutrient: { key in
                    store.selectedNutrientKey = key
                    push(.nutrientDetail)
                },
                onOpenTrends: { tab in
                    store.selectedNutritionTrendTab = tab
                    push(.nutritionTrends)
                }
            )
        case .nutrientDetail:
            NutrientDetailScreen(store: store, onBack: { pop() })
        case .nutritionTrends:
            NutritionTrendsDetailScreen(
                store: store,
                initialTab: store.selectedNutritionTrendTab,
                onBack: { pop() }
            )
        case .journalInsights:
            JournalInsightsScreen(store: store, onBack: { pop() })
        case .healthMetricDetail:
            HealthMetricDetailScreen(store: store, onBack: { pop() })
        case .trendMetricDetail:
            if let trend = store.selectedTrendItem {
                TrendMetricDetailScreen(store: store, trend: trend, onBack: { pop() })
            } else {
                HealthMetricDetailScreen(store: store, onBack: { pop() })
            }
        case .trainingLoad:
            TrainingLoadDetailScreen(store: store, initialTab: trainingLoadTab, onBack: { pop() })
        case .cardioMetricDetail:
            CardioMetricDetailScreen(
                store: store,
                route: cardioRoute,
                onBack: { pop() },
                onOpenWorkout: { w in
                    store.selectWorkout(w)
                    push(.workoutDetail)
                }
            )
        case .workoutDetail:
            if let workout = store.selectedWorkoutItem {
                WorkoutDetailScreen(store: store, workout: workout, onBack: { pop() })
            } else {
                CardioMetricDetailScreen(store: store, route: cardioRoute, onBack: { pop() })
            }
        case .bodyCompositionDetail:
            BodyCompositionDetailScreen(
                store: store,
                kind: store.selectedBodyMetric,
                onBack: { pop() }
            )
        case .weeklyReview:
            WeeklyReviewScreen(
                store: store,
                onBack: { pop() },
                onAskCoach: { push(.askBevel) }
            )
        case .allCategories:
            AllCategoriesDirectoryScreen(
                store: store,
                onBack: { pop() },
                onNavigate: { push($0) },
                onSelectHealthMetric: { kind in
                    store.selectedHealthMetric = kind
                    push(.healthMetricDetail)
                },
                onOpenCardioMetric: { c in
                    cardioRoute = c
                    push(.cardioMetricDetail)
                },
                onOpenBodyMetric: { b in
                    store.selectedBodyMetric = b
                    push(.bodyCompositionDetail)
                },
                onOpenNutrient: { key in
                    store.selectedNutrientKey = key
                    push(.nutrientDetail)
                },
                onSelectMainTab: { tab in
                    selectTab(tab)
                }
            )
        case .askBevel:
            AskBevelScreen(store: store, onClose: { pop() }, onOpenSettings: { push(.dispositivos) })
        case .dispositivos:
            DispositivosScreen(store: store, onBack: { pop() })
        }
    }

    private func selectTab(_ tab: MainTab) {
        selectedTab = tab
        overlayStack.removeAll()
        quickMenuOpen = false
        isBottomBarCollapsed = false
    }

    private func push(_ route: OverlayRoute) {
        quickMenuOpen = false
        isBottomBarCollapsed = false
        if overlayStack.last != route {
            overlayStack.append(route)
        }
    }

    private func pop() {
        isBottomBarCollapsed = false
        if !overlayStack.isEmpty {
            overlayStack.removeLast()
        }
    }
}

// MARK: - Choreographed App Icon Motion Graphic Intro (1:1 Android Motion Fidelity)

private struct LaunchMotionGraphicOverlay: View {
    let isOnboardingNext: Bool
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dotScale: CGFloat = 0.0
    @State private var rippleProgress: CGFloat = 0.0
    @State private var trackProgress: CGFloat = 0.0
    @State private var arcSweep: CGFloat = 0.0
    @State private var tileElevation: CGFloat = 0.0
    @State private var sheenProgress: CGFloat = -0.6
    @State private var wordmarkProgress: CGFloat = 0.0
    @State private var exitAlpha: Double = 1.0
    @State private var finished: Bool = false

    private func triggerFinish() {
        guard !finished else { return }
        finished = true
        onFinished()
    }

    var body: some View {
        let isDark = BevelColors.isDarkMode
        ZStack {
            RadialGradient(
                colors: isDark
                    ? [Color(hex: 0x162420), Color(hex: 0x11151B), BevelColors.canvas]
                    : [Color.white, Color(hex: 0xF3F8F5), BevelColors.canvas],
                center: .center,
                startRadius: 10,
                endRadius: 520
            )
            .ignoresSafeArea()

            // Ambient emerald halo + dual concentric biometric sonar ripples
            Canvas { ctx, sz in
                let center = CGPoint(x: sz.width / 2, y: sz.height / 2)
                let maxR = min(sz.width, sz.height) / 2

                let glowAlpha = min(max(0.16 * Double(tileElevation), 0), 0.16)
                if glowAlpha > 0.005 {
                    let grad = Gradient(colors: [BevelColors.greenPrimary.opacity(glowAlpha), .clear])
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: center.x - maxR * 0.95, y: center.y - maxR * 0.95, width: maxR * 1.9, height: maxR * 1.9)),
                        with: .radialGradient(grad, center: center, startRadius: 0, endRadius: maxR * 0.95)
                    )
                }

                let r1 = rippleProgress
                if r1 > 0.01 && r1 < 0.99 {
                    let rad = maxR * (0.16 + 0.80 * r1)
                    var p = Path()
                    p.addEllipse(in: CGRect(x: center.x - rad, y: center.y - rad, width: rad * 2, height: rad * 2))
                    ctx.stroke(p, with: .color(BevelColors.greenPrimary.opacity(Double(1 - r1) * 0.34)), lineWidth: max(3.5 * (1 - r1 * 0.55), 1))
                }

                let r2 = min(max((rippleProgress - 0.18) / 0.82, 0), 1)
                if r2 > 0.01 && r2 < 0.99 {
                    let rad = maxR * (0.14 + 0.72 * r2)
                    var p = Path()
                    p.addEllipse(in: CGRect(x: center.x - rad, y: center.y - rad, width: rad * 2, height: rad * 2))
                    ctx.stroke(p, with: .color(Color(hex: 0x38D9B5).opacity(Double(1 - r2) * 0.24)), lineWidth: max(2.4 * (1 - r2 * 0.5), 1))
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 26) {
                ZStack {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: 0x161E24), Color(hex: 0x0F151A)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 132, height: 132)
                        .overlay(
                            RoundedRectangle(cornerRadius: 34, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.11), lineWidth: 1)
                        )
                        .shadow(color: BevelColors.greenPrimary.opacity(0.28 * Double(tileElevation)), radius: 26, y: 12)
                        .scaleEffect(0.84 + 0.16 * tileElevation)
                        .opacity(Double(tileElevation))

                    Canvas { ctx, sz in
                        let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
                        let r: CGFloat = 38

                        if trackProgress > 0.01 {
                            var track = Path()
                            track.addArc(center: c, radius: r, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * Double(trackProgress)), clockwise: false)
                            ctx.stroke(track, with: .color(Color.white.opacity(0.11)), style: StrokeStyle(lineWidth: 10.5, lineCap: .round))
                        }

                        if arcSweep > 0.01 {
                            var arc = Path()
                            arc.addArc(center: c, radius: r, startAngle: .degrees(-90), endAngle: .degrees(-90 + 275 * Double(arcSweep)), clockwise: false)
                            ctx.stroke(
                                arc,
                                with: .linearGradient(
                                    Gradient(colors: [Color(hex: 0x4ADE80), Color(hex: 0x10B981), Color(hex: 0x38D9B5)]),
                                    startPoint: CGPoint(x: 0, y: 0),
                                    endPoint: CGPoint(x: sz.width, y: sz.height)
                                ),
                                style: StrokeStyle(lineWidth: 10.5, lineCap: .round)
                            )
                        }
                    }
                    .frame(width: 132, height: 132)

                    Circle()
                        .fill(BevelColors.greenPrimary)
                        .frame(width: 14, height: 14)
                        .scaleEffect(dotScale)
                        .shadow(color: BevelColors.greenPrimary.opacity(0.7), radius: 8)

                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.22), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: 60, height: 180)
                    .rotationEffect(.degrees(24))
                    .offset(x: sheenProgress * 160)
                    .mask(RoundedRectangle(cornerRadius: 34, style: .continuous).frame(width: 132, height: 132))
                }

                VStack(spacing: 6) {
                    Text("Improving")
                        .font(ImprovingFont.displayLarge(30))
                        .foregroundColor(BevelColors.textPrimary)
                        .tracking(0.6)
                    Text("BIOMETRÍA REAL · RENDIMIENTO INTELIGENTE")
                        .font(ImprovingFont.microLabel(10))
                        .foregroundColor(BevelColors.greenPrimary.opacity(0.9))
                }
                .opacity(Double(wordmarkProgress))
                .offset(y: (1 - wordmarkProgress) * 10)
            }
        }
        .opacity(exitAlpha)
        .onAppear {
            if reduceMotion {
                dotScale = 1; trackProgress = 1; arcSweep = 1; tileElevation = 1; wordmarkProgress = 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    withAnimation(.easeOut(duration: 0.25)) { exitAlpha = 0 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { triggerFinish() }
                }
                return
            }

            withAnimation(.spring(response: 0.42, dampingFraction: 0.68)) {
                dotScale = 1.0
                tileElevation = 1.0
            }
            withAnimation(.easeOut(duration: 1.05)) {
                rippleProgress = 1.0
            }
            withAnimation(.easeOut(duration: 0.42).delay(0.14)) {
                trackProgress = 1.0
            }
            withAnimation(.spring(response: 0.62, dampingFraction: 0.80).delay(0.24)) {
                arcSweep = 1.0
            }
            withAnimation(.easeInOut(duration: 0.68).delay(0.55)) {
                sheenProgress = 1.15
            }
            withAnimation(.easeOut(duration: 0.42).delay(0.40)) {
                wordmarkProgress = 1.0
            }

            let hold: Double = isOnboardingNext ? 1.10 : 1.18
            DispatchQueue.main.asyncAfter(deadline: .now() + hold) {
                withAnimation(.easeOut(duration: 0.32)) {
                    exitAlpha = 0.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
                    triggerFinish()
                }
            }
        }
    }
}

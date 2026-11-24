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

    private var currentOverlay: OverlayRoute { overlayStack.last ?? .none }

    var body: some View {
        ZStack(alignment: .bottom) {
            BevelColors.canvas.ignoresSafeArea()

            if !store.userProfile.onboardingCompleted {
                OnboardingExperienceView(
                    initialProfile: store.userProfile,
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
                                }
                            )
                        case .biologia:
                            BiologiaScreen(
                                store: store,
                                onSelectHealthMetric: { kind in
                                    store.selectedHealthMetric = kind
                                    push(.healthMetricDetail)
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
                            onDismiss: { quickMenuOpen = false },
                            onOpenNutrition: { push(.nutricion) },
                            onOpenAskBevel: {
                                push(.askBevel)
                            },
                            onOpenFitness: { selectTab(.fitness) },
                            onOpenJournal: { selectTab(.diario) },
                            onOpenSleep: { push(.suenoDetail) },
                            onOpenDevices: { push(.dispositivos) }
                        )
                        .zIndex(15)
                    }

                    if currentOverlay != .askBevel {
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
            NutricionScreen(store: store, onBack: { pop() }) { key in
                store.selectedNutrientKey = key
                push(.nutrientDetail)
            }
        case .nutrientDetail:
            NutrientDetailScreen(store: store, onBack: { pop() })
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
            CardioMetricDetailScreen(store: store, route: cardioRoute, onBack: { pop() })
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
                    let rad = maxR * (0.14 + 0.66 * r2)
                    var p = Path()
                    p.addEllipse(in: CGRect(x: center.x - rad, y: center.y - rad, width: rad * 2, height: rad * 2))
                    ctx.stroke(p, with: .color(BevelColors.textPrimary.opacity(Double(1 - r2) * 0.16)), lineWidth: max(2.2 * (1 - r2 * 0.5), 1))
                }
            }
            .frame(width: 310, height: 310)

            VStack(spacing: 24) {
                // Choreographed Improving App Icon Squircle
                ZStack {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: isDark
                                    ? [Color(hex: 0x202733), Color(hex: 0x161B24), Color(hex: 0x12161E)]
                                    : [Color.white, Color(hex: 0xF1F5F9), Color(hex: 0xE2E8F0)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 30, style: .continuous)
                                .strokeBorder(Color.white.opacity((isDark ? 0.16 : 0.85) * Double(tileElevation)), lineWidth: 1)
                        )
                        .shadow(color: BevelColors.greenPrimary.opacity(0.24 * Double(tileElevation)), radius: 22, y: 10)

                    Canvas { ctx, sz in
                        let w = sz.width
                        let h = sz.height
                        let cx = w / 2
                        let cy = h / 2
                        let radius = (30.0 / 108.0) * w * (0.76 + 0.24 * trackProgress)
                        let strokePx = (10.2 / 108.0) * w

                        // 1. Recessed circular track
                        if trackProgress > 0.01 {
                            var track = Path()
                            track.addEllipse(in: CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2))
                            ctx.stroke(track, with: .color(Color(hex: isDark ? 0x2E3848 : 0xCBD5E1).opacity(Double(trackProgress))), lineWidth: strokePx)
                        }

                        // 2. Signature Emerald-Lime Recovery Arc + Specular Comet Highlight
                        if arcSweep > 0.5 {
                            var arc = Path()
                            arc.addArc(
                                center: CGPoint(x: cx, y: cy),
                                radius: radius,
                                startAngle: .degrees(-90),
                                endAngle: .degrees(-90 + Double(arcSweep)),
                                clockwise: false
                            )
                            let grad = Gradient(colors: [Color(hex: 0x4ADE80), Color(hex: 0x22C55E), Color(hex: 0x10B981)])
                            ctx.stroke(
                                arc,
                                with: .linearGradient(grad, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: w, y: h)),
                                style: StrokeStyle(lineWidth: strokePx, lineCap: .round)
                            )

                            let tipFade = min(max(1.0 - Double(tileElevation) * 0.72, 0), 1)
                            if tipFade > 0.05 {
                                let rad = (-90.0 + Double(arcSweep)) * .pi / 180.0
                                let tip = CGPoint(x: cx + radius * CGFloat(cos(rad)), y: cy + radius * CGFloat(sin(rad)))
                                let glowR = strokePx * 1.45
                                let tipGrad = Gradient(colors: [.white.opacity(0.85 * tipFade), Color(hex: 0x22C55E).opacity(0.45 * tipFade), .clear])
                                ctx.fill(
                                    Path(ellipseIn: CGRect(x: tip.x - glowR, y: tip.y - glowR, width: glowR * 2, height: glowR * 2)),
                                    with: .radialGradient(tipGrad, center: tip, startRadius: 0, endRadius: glowR)
                                )
                            }
                        }

                        // 3. Center pulse spark dot
                        let dotR = (6.4 / 108.0) * w * dotScale
                        if dotR > 0.5 {
                            ctx.fill(
                                Path(ellipseIn: CGRect(x: cx - dotR, y: cy - dotR, width: dotR * 2, height: dotR * 2)),
                                with: .color(isDark ? .white : Color(hex: 0x111827))
                            )
                        }

                        // 4. Diagonal specular glass sheen sweep
                        if sheenProgress > -0.5 && sheenProgress < 1.5 {
                            let bandStart = CGPoint(x: w * (sheenProgress - 0.35), y: 0)
                            let bandEnd = CGPoint(x: w * (sheenProgress + 0.35), y: h)
                            let sheenGrad = Gradient(colors: [.clear, Color.white.opacity(isDark ? 0.18 : 0.42), .clear])
                            ctx.fill(
                                Path(CGRect(x: 0, y: 0, width: w, height: h)),
                                with: .linearGradient(sheenGrad, startPoint: bandStart, endPoint: bandEnd)
                            )
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                }
                .frame(width: 116, height: 116)
                .scaleEffect(0.86 + 0.14 * tileElevation)

                // Masked kinetic wordmark reveal
                VStack(spacing: 6) {
                    Text("Improving")
                        .font(.system(size: 31, weight: .heavy, design: .rounded))
                        .tracking(-0.6 + (1 - wordmarkProgress) * 2.4)
                        .foregroundColor(BevelColors.textPrimary)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(BevelColors.greenPrimary)
                            .frame(width: 6, height: 6)
                        Text("TU FISIOLOGÍA, A MEDIDA")
                            .font(ImprovingFont.microLabel(10.5))
                            .tracking(1.5)
                            .foregroundColor(BevelColors.textSecondary)
                    }
                }
                .opacity(Double(wordmarkProgress))
                .offset(y: (1 - wordmarkProgress) * 28)
            }
        }
        .opacity(exitAlpha)
        .contentShape(Rectangle())
        .onTapGesture { triggerFinish() }
        .task {
            if reduceMotion {
                dotScale = 1
                trackProgress = 1
                arcSweep = 248
                tileElevation = 1
                wordmarkProgress = 1
                try? await Task.sleep(nanoseconds: 420_000_000)
                withAnimation(.easeIn(duration: 0.22)) { exitAlpha = 0 }
                try? await Task.sleep(nanoseconds: 240_000_000)
                triggerFinish()
                return
            }

            // Beat 1: Center pulse dot + dual biometric sonar ripples
            withAnimation(.spring(response: 0.42, dampingFraction: 0.56)) { dotScale = 1.0 }
            withAnimation(.timingCurve(0.16, 1.0, 0.3, 1.0, duration: 1.05)) { rippleProgress = 1.0 }

            // Beat 2: Ring track + emerald recovery arc with overshoot settle
            try? await Task.sleep(nanoseconds: 160_000_000)
            withAnimation(.easeOut(duration: 0.46)) { trackProgress = 1.0 }
            try? await Task.sleep(nanoseconds: 75_000_000)
            withAnimation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.66)) { arcSweep = 258 }

            // Beat 3: Squircle elevation + specular sheen + kinetic wordmark rise
            try? await Task.sleep(nanoseconds: 380_000_000)
            withAnimation(.spring(response: 0.42, dampingFraction: 0.66)) { arcSweep = 248 }
            withAnimation(.easeOut(duration: 0.42)) { tileElevation = 1.0 }
            withAnimation(.easeInOut(duration: 0.65)) { sheenProgress = 1.6 }
            withAnimation(.easeOut(duration: 0.52)) { wordmarkProgress = 1.0 }

            let holdNs: UInt64 = isOnboardingNext ? 820_000_000 : 480_000_000
            try? await Task.sleep(nanoseconds: holdNs)
            withAnimation(.easeIn(duration: 0.30)) { exitAlpha = 0.0 }
            try? await Task.sleep(nanoseconds: 320_000_000)
            triggerFinish()
        }
    }
}

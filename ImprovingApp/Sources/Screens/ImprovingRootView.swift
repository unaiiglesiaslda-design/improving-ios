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

    private var currentOverlay: OverlayRoute { overlayStack.last ?? .none }

    var body: some View {
        ZStack(alignment: .bottom) {
            BevelColors.canvas.ignoresSafeArea()

            if !store.userProfile.onboardingCompleted {
                OnboardingExperienceView { completedProfile in
                    store.completeOnboarding(completedProfile)
                }
                .transition(.opacity)
            } else {
                ZStack(alignment: .bottom) {
                    // Main 4 Tabs
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

                    // Active Overlay Screen
                    if currentOverlay != .none {
                        overlayView(for: currentOverlay)
                            .transition(.move(edge: currentOverlay == .askBevel ? .bottom : .trailing).combined(with: .opacity))
                            .zIndex(5)
                    }

                    // Quick Actions (+) Sheet
                    if quickMenuOpen && currentOverlay != .askBevel {
                        QuickActionsOverlaySheet(
                            onDismiss: { quickMenuOpen = false },
                            onOpenNutrition: { push(.nutricion) },
                            onOpenAskBevel: {
                                store.startNewCleanChat()
                                push(.askBevel)
                            },
                            onOpenFitness: { selectTab(.fitness) },
                            onOpenJournal: { selectTab(.diario) },
                            onOpenSleep: { push(.suenoDetail) },
                            onOpenDevices: { push(.dispositivos) }
                        )
                        .zIndex(15)
                    }

                    // Persistent Bottom Bar (always visible EXCEPT when talking to AI in AskBevelScreen)
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
            EsfuerzoScreen(store: store, onBack: { pop() }, onOpenTrend: { _ in push(.healthMetricDetail) })
        case .recuperacion:
            RecuperacionScreen(store: store, onBack: { pop() }) { kind in
                store.selectedHealthMetric = kind
                push(.healthMetricDetail)
            }
        case .suenoDetail:
            SuenoDetailScreen(store: store, onBack: { pop() }, onOpenSleepNeed: { push(.sleepNeedDetail) })
        case .sleepNeedDetail:
            SleepNeedDetailScreen(store: store, onBack: { pop() })
        case .estres:
            EstresScreen(store: store, onBack: { pop() })
        case .energia:
            EnergiaScreen(store: store, onBack: { pop() })
        case .nutricion:
            NutricionScreen(store: store, onBack: { pop() }) { key in
                store.selectedNutrientKey = key
                push(.nutrientDetail)
            }
        case .nutrientDetail:
            NutrientDetailScreen(store: store, onBack: { pop() })
        case .healthMetricDetail, .trendMetricDetail:
            HealthMetricDetailScreen(store: store, onBack: { pop() })
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

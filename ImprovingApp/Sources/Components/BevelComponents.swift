import SwiftUI

enum GaugeKind {
    case strain, recovery, sleep
}

// MARK: - Animated Step-by-Step Numeric Text (1:1 Parity with Android Chart Scrubbing)

struct AnimatableNumberText: AnimatableModifier {
    var value: Double
    var decimals: Int = 1
    var suffix: String = ""
    var font: Font
    var color: Color

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    func body(content: Content) -> some View {
        let formatted: String = {
            if decimals == 0 {
                return "\(Int(value.rounded()))\(suffix)"
            }
            return String(format: "%.\(decimals)f", locale: Locale(identifier: "es_ES"), value) + suffix
        }()
        return Text(formatted)
            .font(font)
            .foregroundColor(color)
            .monospacedDigit()
    }
}

extension View {
    func animatableNumber(
        _ value: Double,
        decimals: Int = 1,
        suffix: String = "",
        font: Font = ImprovingFont.displayLarge(31),
        color: Color = BevelColors.textPrimary
    ) -> some View {
        modifier(AnimatableNumberText(value: value, decimals: decimals, suffix: suffix, font: font, color: color))
    }
}

// MARK: - Recessed Ring Gauge (Always-Visible Optimal Range + Progressive Red Overreach)

struct BevelRecessedRingGauge: View {
    let progress: Double // 0.0 ... 1.0
    let centerText: String
    let label: String
    let kind: GaugeKind
    var size: CGFloat = 86
    var strokeWidth: CGFloat = 10
    var subLabel: String? = nil
    var targetRange: ClosedRange<Double>? = nil
    var hasData: Bool = true

    @State private var animatedProgress: Double = 0

    private var overreachFraction: Double {
        guard kind == .strain, hasData, let tr = targetRange, animatedProgress > tr.upperBound else { return 0 }
        let headroom = max(1.0 - tr.upperBound, 0.08)
        return min(max((animatedProgress - tr.upperBound) / headroom, 0), 1)
    }

    private var gradientColors: [Color] {
        switch kind {
        case .strain:
            if overreachFraction > 0 {
                let s = Color.lerp(BevelColors.amberStart, BevelColors.orangeEnd, t: min(overreachFraction * 0.75, 1))
                let m = Color.lerp(BevelColors.orangeEnd, BevelColors.coralHigh, t: min(overreachFraction * 1.15, 1))
                let e = Color.lerp(BevelColors.coralHigh, BevelColors.redAlert, t: overreachFraction)
                return [s, m, e]
            }
            return [BevelColors.amberStart, BevelColors.orangeEnd]
        case .recovery:
            return [BevelColors.limeStart, BevelColors.emeraldEnd]
        case .sleep:
            return [BevelColors.periwinkleStart, BevelColors.indigoEnd]
        }
    }

    private var subColor: Color {
        guard hasData else { return BevelColors.textMuted }
        switch kind {
        case .strain:
            return overreachFraction > 0
                ? Color.lerp(BevelColors.orangeEnd, BevelColors.redAlert, t: min(overreachFraction * 1.15, 1))
                : BevelColors.orangeEnd
        case .recovery: return BevelColors.emeraldEnd
        case .sleep: return BevelColors.indigoEnd
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Canvas { context, canvasSize in
                    let pad = strokeWidth / 2 + 3
                    let arcRect = CGRect(x: pad, y: pad, width: canvasSize.width - pad * 2, height: canvasSize.height - pad * 2)
                    let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                    let radius = arcRect.width / 2

                    // Subtle outer recessed shadow
                    let outerPath = Path(ellipseIn: arcRect.insetBy(dx: -strokeWidth * 0.52, dy: -strokeWidth * 0.52))
                    context.stroke(outerPath, with: .color(BevelColors.trackInnerShadow.opacity(0.45)), lineWidth: 1.5)

                    // Base track groove
                    let groovePath = Path(ellipseIn: arcRect)
                    context.stroke(groovePath, with: .color(BevelColors.trackGroove), lineWidth: strokeWidth)

                    // Target range under-band
                    if hasData, let tr = targetRange {
                        let startDeg = -90.0 + tr.lowerBound * 360.0
                        let endDeg = -90.0 + tr.upperBound * 360.0
                        var bandPath = Path()
                        bandPath.addArc(center: center, radius: radius, startAngle: .degrees(startDeg), endAngle: .degrees(endDeg), clockwise: false)
                        context.stroke(bandPath, with: .color(BevelColors.strainHatchBg), style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))

                        let steps = max(Int((endDeg - startDeg) / 5.0), 4)
                        for i in 0...steps {
                            let deg = startDeg + (endDeg - startDeg) * Double(i) / Double(steps)
                            let rad = deg * .pi / 180.0
                            let rIn = radius - strokeWidth * 0.34
                            let rOut = radius + strokeWidth * 0.34
                            var tick = Path()
                            tick.move(to: CGPoint(x: center.x + rIn * cos(rad), y: center.y + rIn * sin(rad)))
                            tick.addLine(to: CGPoint(x: center.x + rOut * cos(rad + 0.045), y: center.y + rOut * sin(rad + 0.045)))
                            context.stroke(tick, with: .color(BevelColors.strainHatchLine.opacity(0.65)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                        }
                    }

                    // Active sweep arc
                    if hasData {
                        let sweepDeg = max(animatedProgress * 360.0, progress > 0 ? 4.0 : 0.0)
                        if sweepDeg > 0 {
                            var sweepPath = Path()
                            sweepPath.addArc(center: center, radius: radius, startAngle: .degrees(-90), endAngle: .degrees(-90 + sweepDeg), clockwise: false)
                            let grad = Gradient(colors: gradientColors)
                            context.stroke(
                                sweepPath,
                                with: .conicGradient(grad, center: center, angle: .degrees(-90)),
                                style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                            )

                            let tipRad = (-90.0 + sweepDeg) * .pi / 180.0
                            let tipCenter = CGPoint(x: center.x + radius * cos(tipRad), y: center.y + radius * sin(tipRad))
                            let dotRect = CGRect(x: tipCenter.x - strokeWidth * 0.24, y: tipCenter.y - strokeWidth * 0.24, width: strokeWidth * 0.48, height: strokeWidth * 0.48)
                            context.fill(Path(ellipseIn: dotRect), with: .color(.white.opacity(0.9)))
                        }

                        // Always-visible optimal effort boundary markers & translucent guide arc on top
                        if let tr = targetRange {
                            let startDeg = -90.0 + tr.lowerBound * 360.0
                            let endDeg = -90.0 + tr.upperBound * 360.0
                            let covered = min(max((animatedProgress - tr.lowerBound) / max(tr.upperBound - tr.lowerBound, 0.01), 0), 1)
                            if covered > 0.05 {
                                var outerGuide = Path()
                                outerGuide.addArc(center: center, radius: radius + strokeWidth * 0.62, startAngle: .degrees(startDeg), endAngle: .degrees(endDeg), clockwise: false)
                                context.stroke(outerGuide, with: .color(.white.opacity(0.45)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))

                                let steps = max(Int((endDeg - startDeg) / 7.0), 4)
                                for i in 0...steps {
                                    let frac = Double(i) / Double(steps)
                                    if frac <= covered {
                                        let deg = startDeg + (endDeg - startDeg) * frac
                                        let rad = deg * .pi / 180.0
                                        let rIn = radius - strokeWidth * 0.28
                                        let rOut = radius + strokeWidth * 0.28
                                        var tick = Path()
                                        tick.move(to: CGPoint(x: center.x + rIn * cos(rad), y: center.y + rIn * sin(rad)))
                                        tick.addLine(to: CGPoint(x: center.x + rOut * cos(rad + 0.04), y: center.y + rOut * sin(rad + 0.04)))
                                        context.stroke(tick, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
                                    }
                                }
                            }
                            for boundDeg in [startDeg, endDeg] {
                                let rad = boundDeg * .pi / 180.0
                                let rIn = radius - strokeWidth * 0.48
                                let rOut = radius + strokeWidth * 0.48
                                var bTick = Path()
                                bTick.move(to: CGPoint(x: center.x + rIn * cos(rad), y: center.y + rIn * sin(rad)))
                                bTick.addLine(to: CGPoint(x: center.x + rOut * cos(rad), y: center.y + rOut * sin(rad)))
                                context.stroke(bTick, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                            }
                        }
                    }
                }
                .frame(width: size, height: size)

                Text(hasData ? centerText : "--")
                    .font(ImprovingFont.metricHero(size >= 120 ? 32 : 20))
                    .foregroundColor(hasData ? BevelColors.textPrimary : BevelColors.textMuted)
                    .monospacedDigit()
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.7)) {
                    animatedProgress = hasData ? min(max(progress, 0), 1) : 0
                }
            }
            .onChange(of: progress) { _, newVal in
                withAnimation(.easeOut(duration: 0.45)) {
                    animatedProgress = hasData ? min(max(newVal, 0), 1) : 0
                }
            }

            if !label.isEmpty {
                Text(label)
                    .font(ImprovingFont.caption(12))
                    .fontWeight(.semibold)
                    .foregroundColor(BevelColors.textPrimary)
            }
            if let sub = subLabel {
                Text(sub)
                    .font(ImprovingFont.caption(11))
                    .fontWeight(.semibold)
                    .foregroundColor(subColor)
            }
        }
    }
}

// MARK: - Iridescent Pearl Orb

struct IridescentPearlOrb: View {
    var size: CGFloat = 34
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: 0xFFFFFF), Color(hex: 0xD8F8EC), Color(hex: 0xC7D2FE)],
                        center: .topLeading,
                        startRadius: 1,
                        endRadius: size * 0.9
                    )
                )
            Circle()
                .strokeBorder(.white.opacity(0.65), lineWidth: 1)
        }
        .frame(width: size, height: size)
        .shadow(color: Color(hex: 0x22C55E).opacity(0.22), radius: 6, y: 2)
    }
}

// MARK: - Scroll-Collapsing Persistent Bottom Navigation Bar (Glides Left on Scroll)

struct FloatingPillBottomBar: View {
    let selectedTab: MainTab
    let visibleTabs: Set<MainTab>
    let isQuickMenuOpen: Bool
    let isCollapsed: Bool
    let onSelectTab: (MainTab) -> Unit
    let onToggleQuickMenu: () -> Unit
    let onExpand: () -> Unit

    private var effectiveCollapsed: Bool { isCollapsed && !isQuickMenuOpen }

    var body: some View {
        HStack {
            if !effectiveCollapsed {
                Spacer(minLength: 0)
            }

            Group {
                if effectiveCollapsed {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onExpand()
                    } label: {
                        Image(systemName: selectedTab.systemIcon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(BevelColors.textPrimary)
                            .frame(width: 52, height: 52)
                    }
                    .accessibilityLabel("Mostrar barra (\(selectedTab.label))")
                    .transition(.scale(scale: 0.86).combined(with: .opacity))
                } else {
                    HStack(spacing: 6) {
                        if visibleTabs.contains(.hoy) {
                            pillTabButton(.hoy)
                        }
                        if visibleTabs.contains(.diario) {
                            pillTabButton(.diario)
                        }

                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onToggleQuickMenu()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundColor(isQuickMenuOpen ? .white : BevelColors.textPrimary)
                                .rotationEffect(.degrees(isQuickMenuOpen ? 45 : 0))
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle().fill(isQuickMenuOpen ? BevelColors.floatingDarkButton : BevelColors.trackGroove)
                                )
                        }
                        .padding(.horizontal, 4)

                        if visibleTabs.contains(.fitness) {
                            pillTabButton(.fitness)
                        }
                        if visibleTabs.contains(.biologia) {
                            pillTabButton(.biologia)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
            .background(
                Capsule(style: .continuous)
                    .fill(BevelColors.card.opacity(0.96))
                    .shadow(color: .black.opacity(0.32), radius: 14, y: 6)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(BevelColors.cardBorder, lineWidth: 0.9)
            )

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: effectiveCollapsed)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: isQuickMenuOpen)
    }

    private func pillTabButton(_ tab: MainTab) -> some View {
        let isSelected = selectedTab == tab && !isQuickMenuOpen
        return Button {
            if !isSelected {
                UISelectionFeedbackGenerator().selectionChanged()
            }
            onSelectTab(tab)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.systemIcon)
                    .font(.system(size: 17, weight: isSelected ? .bold : .medium))
                    .scaleEffect(isSelected ? 1.08 : 1.0)
                Text(tab.label)
                    .font(ImprovingFont.caption(10))
                    .fontWeight(isSelected ? .bold : .medium)
            }
            .foregroundColor(isSelected ? BevelColors.textPrimary : BevelColors.textMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(isSelected ? BevelColors.trackGroove : .clear)
            )
        }
    }
}

// MARK: - Short Click-to-Expand Floating Metric AI Overlay (Above Bottom Bar)

struct FloatingMetricAiCoachOverlay: View {
    let metricKey: String
    let metricTitle: String
    let insight: MetricFloatingAiInsight
    let scrollCollapseSignal: Int

    @State private var isLoading = true
    @State private var isExpanded = false
    @State private var isFullyExpanded = false
    @State private var collapsedByScroll = false

    var body: some View {
        VStack(spacing: 10) {
            if isExpanded && !isLoading {
                let shortText = insight.shortExpandedMessage.isEmpty ? insight.expandedMessage : insight.shortExpandedMessage
                let hasMore = !insight.expandedMessage.isEmpty && insight.expandedMessage != shortText

                BevelCard(cornerRadius: 22, backgroundColor: BevelColors.card.opacity(0.97)) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            HStack(spacing: 7) {
                                IridescentPearlOrb(size: 18)
                                Text(insight.expandedHeadline)
                                    .font(ImprovingFont.microLabel(10.5))
                                    .foregroundColor(BevelColors.emeraldEnd)
                            }
                            Spacer()
                            Text(metricTitle)
                                .font(ImprovingFont.caption(10.5))
                                .foregroundColor(BevelColors.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(BevelColors.cardSubtle))
                                .overlay(Capsule().strokeBorder(BevelColors.cardBorder, lineWidth: 0.6))
                        }

                        Text(isFullyExpanded ? insight.expandedMessage : shortText)
                            .font(ImprovingFont.body(13.5))
                            .foregroundColor(BevelColors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        if hasMore {
                            HStack(spacing: 4) {
                                Text(isFullyExpanded ? "Toca para resumir" : "Toca para leer completo")
                                    .font(ImprovingFont.caption(11))
                                    .fontWeight(.semibold)
                                    .foregroundColor(BevelColors.emeraldEnd)
                                Image(systemName: isFullyExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(BevelColors.emeraldEnd)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                }
                .onTapGesture {
                    if hasMore {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.easeInOut(duration: 0.24)) {
                            isFullyExpanded.toggle()
                        }
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Button {
                if !isLoading {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        isExpanded.toggle()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    IridescentPearlOrb(size: 20)
                    if isLoading {
                        Text("Analizando con tus datos…")
                            .font(ImprovingFont.body(13))
                            .foregroundColor(BevelColors.textSecondary)
                    } else {
                        Text(insight.shortPillText)
                            .font(ImprovingFont.cardTitle(13.5))
                            .foregroundColor(BevelColors.textPrimary)
                            .lineLimit(1)
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(BevelColors.textMuted)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Capsule().fill(BevelColors.card.opacity(0.96)))
                .overlay(Capsule().strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 86) // Sits cleanly above persistent bottom navigation bar
        .onAppear {
            triggerReveal()
        }
        .onChange(of: metricKey) { _, _ in
            triggerReveal()
        }
        .onChange(of: scrollCollapseSignal) { _, _ in
            if isExpanded {
                withAnimation(.easeOut(duration: 0.22)) {
                    collapsedByScroll = true
                    isExpanded = false
                    isFullyExpanded = false
                }
            }
        }
    }

    private func triggerReveal() {
        isLoading = true
        isExpanded = false
        isFullyExpanded = false
        collapsedByScroll = false
        Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            await MainActor.run {
                isLoading = false
                if !collapsedByScroll {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        isExpanded = true
                    }
                }
            }
        }
    }
}

// MARK: - Quick Actions Sheet (+)

struct QuickActionsOverlaySheet: View {
    let onDismiss: () -> Void
    let onOpenNutrition: () -> Void
    let onOpenAskBevel: () -> Void
    let onOpenFitness: () -> Void
    let onOpenJournal: () -> Void
    let onOpenSleep: () -> Void
    let onOpenDevices: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            BevelCard(cornerRadius: 26, backgroundColor: BevelColors.card.opacity(0.98)) {
                VStack(spacing: 14) {
                    Button(action: onOpenAskBevel) {
                        HStack(spacing: 12) {
                            IridescentPearlOrb(size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Preguntar a Improving IA")
                                    .font(ImprovingFont.cardTitle(15))
                                    .foregroundColor(BevelColors.textPrimary)
                                Text("Analiza sueño, recuperación, VFC y entreno")
                                    .font(ImprovingFont.caption(11.5))
                                    .foregroundColor(BevelColors.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(BevelColors.textMuted)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 16).fill(BevelColors.cardSubtle))
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        quickTile("Nutrición", icon: "fork.knife", color: BevelColors.emeraldEnd, action: onOpenNutrition)
                        quickTile("Fitness", icon: "figure.run", color: BevelColors.orangeEnd, action: onOpenFitness)
                        quickTile("Diario", icon: "book.fill", color: BevelColors.skyBlue, action: onOpenJournal)
                        quickTile("Sueño", icon: "moon.stars.fill", color: BevelColors.periwinkleStart, action: onOpenSleep)
                        quickTile("Salud / Apple", icon: "heart.text.square.fill", color: BevelColors.redAlert, action: onOpenDevices)
                        quickTile("Ajustes", icon: "slider.horizontal.3", color: BevelColors.textSecondary, action: onOpenDevices)
                    }
                }
                .padding(16)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 88)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func quickTile(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(color.opacity(0.14)))
                Text(title)
                    .font(ImprovingFont.caption(11.5))
                    .foregroundColor(BevelColors.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14).fill(BevelColors.cardSubtle))
        }
    }
}

// MARK: - Segmented Bar Meter & Pills

struct SegmentedEnergyMeter: View {
    let percent: Int
    var totalSegments: Int = 26

    var body: some View {
        let filled = Int((Double(min(max(percent, 0), 100)) / 100.0 * Double(totalSegments)).rounded())
        HStack(spacing: 3.5) {
            ForEach(0..<totalSegments, id: \.self) { idx in
                RoundedRectangle(cornerRadius: 3)
                    .fill(idx < filled ? BevelColors.greenPrimary : BevelColors.trackGroove)
                    .frame(height: 22)
            }
        }
    }
}

struct StatusDotPill: View {
    let text: String
    let dotColor: Color
    var bgColor: Color = BevelColors.cardSubtle

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(dotColor).frame(width: 7, height: 7)
            Text(text)
                .font(ImprovingFont.caption(11.5))
                .fontWeight(.semibold)
                .foregroundColor(BevelColors.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(bgColor))
    }
}

// MARK: - Passive Scroll Detector Modifier

struct VerticalScrollDetector: ViewModifier {
    let onVerticalScroll: () -> Void
    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 14)
                .onChanged { value in
                    if abs(value.translation.height) > abs(value.translation.width) * 1.15 && abs(value.translation.height) > 16 {
                        onVerticalScroll()
                    }
                }
        )
    }
}

extension View {
    func onVerticalScrollCollapse(_ action: @escaping () -> Void) -> some View {
        modifier(VerticalScrollDetector(onVerticalScroll: action))
    }
}

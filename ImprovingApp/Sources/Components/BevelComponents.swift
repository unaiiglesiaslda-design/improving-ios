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
    var size: CGFloat = 82
    var strokeWidth: CGFloat = 9
    var subLabel: String? = nil
    var centerSubtitle: String? = nil
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
        VStack(spacing: 5) {
            ZStack {
                Canvas { context, canvasSize in
                    let pad = strokeWidth / 2 + 3
                    let arcRect = CGRect(x: pad, y: pad, width: canvasSize.width - pad * 2, height: canvasSize.height - pad * 2)
                    let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                    let radius = arcRect.width / 2

                    let outerPath = Path(ellipseIn: arcRect.insetBy(dx: -strokeWidth * 0.52, dy: -strokeWidth * 0.52))
                    context.stroke(outerPath, with: .color(BevelColors.trackInnerShadow.opacity(0.45)), lineWidth: 1.5)

                    let groovePath = Path(ellipseIn: arcRect)
                    context.stroke(groovePath, with: .color(BevelColors.trackGroove), lineWidth: strokeWidth)

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

                VStack(spacing: 1) {
                    Text(hasData ? centerText : "--")
                        .font(ImprovingFont.metricHero(size >= 120 ? 32 : 20))
                        .foregroundColor(hasData ? BevelColors.textPrimary : BevelColors.textMuted)
                        .monospacedDigit()
                    if let cSub = centerSubtitle {
                        Text(hasData ? cSub : "Sin datos")
                            .font(ImprovingFont.caption(11))
                            .foregroundColor(hasData ? BevelColors.textSecondary : BevelColors.textMuted)
                    }
                }
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.65)) {
                    animatedProgress = hasData ? min(max(progress, 0), 1) : 0
                }
            }
            .onChange(of: progress) { _, newVal in
                withAnimation(.easeOut(duration: 0.4)) {
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
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Signature Radial Tick-Mark Stress Dial (Compact 36-tick & Hero 54-tick)

struct StressRadialDial: View {
    let score: Int
    let statusLabel: String
    var size: CGFloat = 86
    var isHeroGauge: Bool = false
    var hasData: Bool = true

    var body: some View {
        let frac = hasData ? min(max(Double(score) / 100.0, 0), 1) : 0
        let statusColor: Color = !hasData ? BevelColors.textMuted : (score < 35 ? BevelColors.tealLow : (score < 65 ? BevelColors.amberStart : BevelColors.coralHigh))

        ZStack {
            Canvas { ctx, canvasSize in
                let totalTicks = isHeroGauge ? 54 : 36
                let startDeg = isHeroGauge ? 135.0 : -90.0
                let sweepTotal = isHeroGauge ? 270.0 : 360.0
                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let outerR = min(canvasSize.width, canvasSize.height) / 2 - 4
                let innerR = outerR - (isHeroGauge ? 11 : 8)
                let litTicks = hasData ? max(Int(frac * Double(totalTicks)), score > 0 ? 1 : 0) : -1
                let maxIdx = isHeroGauge ? totalTicks : (totalTicks - 1)

                for i in 0...maxIdx {
                    let angleDeg = startDeg + (Double(i) * sweepTotal / Double(totalTicks))
                    let rad = angleDeg * .pi / 180.0
                    let ratio = Double(i) / Double(totalTicks)
                    let tickColor: Color
                    if hasData && i <= litTicks {
                        tickColor = ratio < 0.35 ? BevelColors.greenPrimary : (ratio < 0.65 ? BevelColors.amberStart : BevelColors.coralHigh)
                    } else {
                        tickColor = BevelColors.trackGroove
                    }
                    var line = Path()
                    line.move(to: CGPoint(x: center.x + innerR * cos(rad), y: center.y + innerR * sin(rad)))
                    line.addLine(to: CGPoint(x: center.x + outerR * cos(rad), y: center.y + outerR * sin(rad)))
                    ctx.stroke(line, with: .color(tickColor), style: StrokeStyle(lineWidth: isHeroGauge ? 2.4 : 2.1, lineCap: .round))
                }
            }

            VStack(spacing: 1) {
                Text(hasData ? "\(score)" : "--")
                    .font(ImprovingFont.metricTile(isHeroGauge ? 34 : 22))
                    .monospacedDigit()
                    .foregroundColor(hasData ? BevelColors.textPrimary : BevelColors.textMuted)
                Text(!hasData ? "Sin datos" : (isHeroGauge ? statusLabel : "\(statusLabel) →"))
                    .font(ImprovingFont.caption(isHeroGauge ? 12.5 : 10.5))
                    .fontWeight(.semibold)
                    .foregroundColor(statusColor)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Energy Bank 34-Bar Segmented Battery Bar (1:1 Android EnergyBankBatteryBar)

struct EnergyBankBatteryBar: View {
    let percent: Int
    var hasData: Bool = true
    let onClick: () -> Void

    var body: some View {
        let clamped = hasData ? min(max(percent, 0), 100) : 0
        let barColor = clamped >= 50 ? BevelColors.greenPrimary : BevelColors.amberStart

        Button(action: onClick) {
            BevelCard(cornerRadius: 18) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(hasData ? BevelColors.greenSoftBg : BevelColors.trackGroove)
                            .frame(width: 28, height: 28)
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(BevelColors.amberStart)
                    }

                    GeometryReader { geo in
                        let barCount = 34
                        let gap: CGFloat = 2.5
                        let totalGap = gap * CGFloat(barCount - 1)
                        let barW = max((geo.size.width - totalGap) / CGFloat(barCount), 2)
                        let litBars = hasData ? Int((Double(clamped) / 100.0) * Double(barCount)) : 0

                        HStack(spacing: gap) {
                            ForEach(0..<barCount, id: \.self) { idx in
                                Capsule()
                                    .fill(hasData && idx < litBars ? barColor : BevelColors.trackGroove)
                                    .frame(width: barW, height: 18)
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .center)
                    }
                    .frame(height: 22)

                    VStack(alignment: .trailing, spacing: 1) {
                        Text(hasData ? "\(clamped)%" : "--")
                            .font(ImprovingFont.cardTitle(15))
                            .fontWeight(.bold)
                            .monospacedDigit()
                            .foregroundColor(hasData ? BevelColors.textPrimary : BevelColors.textMuted)
                        Text(hasData ? "Energía" : "Sin datos")
                            .font(ImprovingFont.caption(10))
                            .foregroundColor(hasData ? BevelColors.textSecondary : BevelColors.textMuted)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
            }
        }
    }
}

// MARK: - 2-Column Health Monitor Card with Vertical Thermometer Range Gauge (1:1 Android HealthMonitorRangeCard)

struct HealthMonitorRangeCard: View {
    let title: String
    let value: String
    let unit: String
    let systemIcon: String
    let evaluation: VitalEvaluation
    let onClick: () -> Void

    var body: some View {
        let hasData = evaluation.severity != .noData
        let accent: Color = switch evaluation.severity {
        case .optimalExcellent: BevelColors.skyBlue
        case .normal: BevelColors.emeraldEnd
        case .borderlineWarning: BevelColors.orangeEnd
        case .alertOutOfRange: BevelColors.redAlert
        case .noData: BevelColors.textMuted
        }
        let statusIcon: String = {
            if !hasData { return "info.circle.fill" }
            if evaluation.severity == .normal { return "checkmark.circle.fill" }
            if evaluation.isAboveBand { return "arrow.up" }
            if evaluation.isBelowBand { return "arrow.down" }
            return "checkmark.circle.fill"
        }()

        Button(action: onClick) {
            BevelCard(cornerRadius: 18) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: systemIcon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(BevelColors.textMuted)
                            Text(title)
                                .font(ImprovingFont.caption(13))
                                .foregroundColor(BevelColors.textSecondary)
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(hasData ? value : "--")
                                .font(ImprovingFont.metricTile(value.count > 6 ? 17 : 21))
                                .monospacedDigit()
                                .foregroundColor(hasData ? BevelColors.textPrimary : BevelColors.textMuted)
                                .lineLimit(1)
                            if hasData && !unit.isEmpty {
                                Text(unit)
                                    .font(ImprovingFont.caption(12))
                                    .foregroundColor(BevelColors.textSecondary)
                            }
                        }

                        HStack(spacing: 4) {
                            Image(systemName: statusIcon)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(accent)
                            Text(hasData ? evaluation.statusLabel : "Sin datos")
                                .font(ImprovingFont.caption(12))
                                .fontWeight(.semibold)
                                .foregroundColor(accent)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)

                    // 14x66pt Vertical Recessed Thermometer Range Pill
                    Canvas { ctx, size in
                        let trackRadius = size.width / 2
                        let inset: CGFloat = 1.8
                        let innerW = size.width - inset * 2
                        let innerR = innerW / 2

                        let outerRect = CGRect(origin: .zero, size: size)
                        ctx.fill(Path(roundedRect: outerRect, cornerRadius: trackRadius), with: .color(BevelColors.trackGroove))

                        let bandTop = size.height * 0.26
                        let bandBottom = size.height * 0.74
                        let bandRect = CGRect(x: inset, y: bandTop, width: innerW, height: bandBottom - bandTop)

                        if !hasData {
                            ctx.fill(Path(roundedRect: bandRect, cornerRadius: innerR), with: .color(BevelColors.trackInnerShadow.opacity(0.45)))
                            return
                        }

                        let clampedPos = min(max(evaluation.normalizedPosition, 0.08), 0.92)
                        let dotY = size.height * (1.0 - clampedPos)
                        let dotCenter = CGPoint(x: size.width / 2, y: dotY)

                        if evaluation.severity == .normal {
                            ctx.fill(Path(roundedRect: bandRect, cornerRadius: innerR), with: .color(BevelColors.greenPrimary.opacity(0.88)))
                        } else {
                            ctx.fill(Path(roundedRect: bandRect, cornerRadius: innerR), with: .color(BevelColors.greenPrimary.opacity(0.24)))
                            if dotY < bandTop {
                                let tTop = max(dotY - innerR * 0.4, inset)
                                let tH = max(bandTop - tTop + innerR * 0.8, innerW)
                                ctx.fill(Path(roundedRect: CGRect(x: inset, y: tTop, width: innerW, height: tH), cornerRadius: innerR), with: .color(accent.opacity(0.88)))
                            } else if dotY > bandBottom {
                                let tStart = max(bandBottom - innerR * 0.8, bandTop)
                                let tEnd = min(dotY + innerR * 0.4, size.height - inset)
                                let tH = max(tEnd - tStart, innerW)
                                ctx.fill(Path(roundedRect: CGRect(x: inset, y: tStart, width: innerW, height: tH), cornerRadius: innerR), with: .color(accent.opacity(0.88)))
                            }
                        }

                        ctx.fill(Path(ellipseIn: CGRect(x: dotCenter.x - 6.8, y: dotCenter.y - 6.8, width: 13.6, height: 13.6)), with: .color(accent.opacity(0.22)))
                        ctx.fill(Path(ellipseIn: CGRect(x: dotCenter.x - 5.4, y: dotCenter.y - 5.4, width: 10.8, height: 10.8)), with: .color(.white))
                        ctx.fill(Path(ellipseIn: CGRect(x: dotCenter.x - 3.2, y: dotCenter.y - 3.2, width: 6.4, height: 6.4)), with: .color(accent))
                    }
                    .frame(width: 14, height: 66)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 12)
            }
        }
    }
}

// MARK: - Atmospheric Hero Header for Detail Screens (1:1 Android AtmosphericHeroHeader)

struct AtmosphericHeroHeader<Content: View>: View {
    let title: String
    let subtitle: String
    let onBack: () -> Void
    var rightSystemIcon: String = "info.circle"
    var onRightAction: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(BevelColors.textPrimary)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(BevelColors.card))
                }
                Spacer()
                VStack(spacing: 2) {
                    Text(title)
                        .font(ImprovingFont.sectionTitle(17))
                        .foregroundColor(BevelColors.textPrimary)
                    Text(subtitle)
                        .font(ImprovingFont.caption(12))
                        .foregroundColor(BevelColors.textSecondary)
                }
                Spacer()
                Button {
                    onRightAction?()
                } label: {
                    Image(systemName: rightSystemIcon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(BevelColors.textSecondary)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(BevelColors.card))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            content()
        }
        .padding(.bottom, 10)
    }
}

// MARK: - Shared Bevel Trend Card with Sparkline (Esfuerzo, Recuperación, Sueño)

struct BevelTrendLightCard: View {
    let trend: EffortTrendItem
    let systemIcon: String
    let onClick: () -> Void

    var body: some View {
        let lineColor = Color(hex: trend.lineColorHex)
        let statusColor: Color = switch trend.statusTone {
        case .normal: BevelColors.emeraldEnd
        case .above: BevelColors.skyBlue
        case .below: BevelColors.orangeEnd
        }

        Button(action: onClick) {
            BevelCard(cornerRadius: 18) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            Image(systemName: systemIcon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(BevelColors.textSecondary)
                            Text(trend.title)
                                .font(ImprovingFont.caption(12.5))
                                .foregroundColor(BevelColors.textSecondary)
                                .lineLimit(1)
                        }
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(statusColor)
                            Text(trend.statusText)
                                .font(ImprovingFont.caption(11.5))
                                .fontWeight(.semibold)
                                .foregroundColor(statusColor)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(trend.valueText)
                                .font(ImprovingFont.metricTile(21))
                                .monospacedDigit()
                                .foregroundColor(BevelColors.textPrimary)
                            if !trend.unitText.isEmpty {
                                Text(trend.unitText)
                                    .font(ImprovingFont.caption(12))
                                    .foregroundColor(BevelColors.textSecondary)
                            }
                        }
                    }
                    Spacer()
                    TrendSparklineWithBand(points: trend.points, bandLow: trend.bandLow, bandHigh: trend.bandHigh, lineColor: lineColor)
                        .frame(width: 118, height: 52)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(BevelColors.textMuted)
                }
                .padding(14)
            }
        }
    }
}

// MARK: - Iridescent Pearl Orb (1:1 Android Multi-Stop Radial Glass Orb)

struct IridescentPearlOrb: View {
    var size: CGFloat = 36
    var body: some View {
        ZStack(alignment: .topLeading) {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: 0xFFFFFF),
                            Color(hex: 0xE0F2FE),
                            Color(hex: 0xFCE7F3),
                            Color(hex: 0xDDD6FE),
                            Color(hex: 0xCCFBF1),
                        ],
                        center: .topLeading,
                        startRadius: 1,
                        endRadius: size * 0.95
                    )
                )
            Circle()
                .strokeBorder(.white.opacity(0.9), lineWidth: 1.4)
            Circle()
                .fill(.white.opacity(0.65))
                .frame(width: size * 0.34, height: size * 0.34)
                .offset(x: size * 0.16, y: size * 0.14)
        }
        .frame(width: size, height: size)
        .shadow(color: Color(hex: 0x818CF8).opacity(0.32), radius: 7, y: 2)
    }
}

// MARK: - Scroll-Collapsing Persistent Bottom Navigation Bar (Glides Left on Scroll)

struct FloatingPillBottomBar: View {
    let selectedTab: MainTab
    let visibleTabs: Set<MainTab>
    let isQuickMenuOpen: Bool
    let isCollapsed: Bool
    let onSelectTab: (MainTab) -> Void
    let onToggleQuickMenu: () -> Void
    let onExpand: () -> Void

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
                                .frame(width: 46, height: 46)
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
        .padding(.bottom, 86)
        .onAppear { triggerReveal() }
        .onChange(of: metricKey) { _, _ in triggerReveal() }
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
            try? await Task.sleep(nanoseconds: 420_000_000)
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

// MARK: - 3x3 Quick Actions Sheet with Centered 60pt Iridescent Pearl Orb (1:1 Android QuickActionsOverlaySheet)

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
            Color.black.opacity(0.48)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            BevelCard(cornerRadius: 28, backgroundColor: BevelColors.card.opacity(0.98)) {
                VStack(spacing: 16) {
                    Capsule()
                        .fill(BevelColors.trackGroove)
                        .frame(width: 38, height: 4)

                    VStack(spacing: 3) {
                        Text("ACCIONES RÁPIDAS")
                            .font(ImprovingFont.microLabel(10.5))
                            .foregroundColor(BevelColors.textMuted)
                        Text("Registrar o Consultar")
                            .font(ImprovingFont.sectionTitle(18))
                            .foregroundColor(BevelColors.textPrimary)
                    }

                    // Row 1
                    HStack {
                        quickActionTile("Describir comida", icon: "square.and.pencil", action: onOpenNutrition)
                        Spacer()
                        quickActionTile("Importar foto", icon: "photo.on.rectangle", action: onOpenNutrition)
                        Spacer()
                        quickActionTile("Capturar comida", icon: "camera.fill", badge: true, action: onOpenNutrition)
                    }

                    // Row 2 with 60pt Iridescent Pearl Orb in center
                    HStack(alignment: .center) {
                        quickActionTile("Escanear código", icon: "qrcode.viewfinder", action: onOpenNutrition)
                        Spacer()
                        Button(action: onOpenAskBevel) {
                            VStack(spacing: 8) {
                                IridescentPearlOrb(size: 60)
                                Text("Ask Improving")
                                    .font(ImprovingFont.caption(12))
                                    .fontWeight(.bold)
                                    .foregroundColor(BevelColors.textPrimary)
                            }
                            .frame(width: 96)
                        }
                        Spacer()
                        quickActionTile("Buscar alimento", icon: "magnifyingglass", action: onOpenNutrition)
                    }

                    // Row 3
                    HStack {
                        quickActionTile("Generar rutinas", icon: "sparkles", action: onOpenFitness)
                        Spacer()
                        quickActionTile("Ver plantillas", icon: "dumbbell.fill", action: onOpenFitness)
                        Spacer()
                        quickActionTile("Sueño & Alarma", icon: "bed.double.fill", action: onOpenSleep)
                    }

                    Button(action: onOpenDevices) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(BevelColors.emeraldEnd)
                            Text("WHOOP BLE + Apple Health · Configurar")
                                .font(ImprovingFont.caption(12))
                                .fontWeight(.semibold)
                                .foregroundColor(BevelColors.emeraldEnd)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(BevelColors.greenSoftBg))
                        .overlay(Capsule().strokeBorder(BevelColors.greenSoftBorder, lineWidth: 0.8))
                    }
                }
                .padding(20)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 88)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func quickActionTile(_ title: String, icon: String, badge: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack(alignment: .topTrailing) {
                    Circle()
                        .fill(BevelColors.cardSubtle)
                        .frame(width: 50, height: 50)
                        .overlay(Circle().strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
                    Image(systemName: icon)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(BevelColors.textPrimary)
                        .frame(width: 50, height: 50)
                    if badge {
                        Circle()
                            .fill(BevelColors.greenPrimary)
                            .frame(width: 9, height: 9)
                            .offset(x: -2, y: 2)
                    }
                }
                Text(title)
                    .font(ImprovingFont.caption(11))
                    .foregroundColor(BevelColors.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: 92)
        }
    }
}

struct SegmentedEnergyMeter: View {
    let percent: Int
    var totalSegments: Int = 28

    var body: some View {
        let filled = Int((Double(min(max(percent, 0), 100)) / 100.0 * Double(totalSegments)).rounded())
        HStack(spacing: 3) {
            ForEach(0..<totalSegments, id: \.self) { idx in
                RoundedRectangle(cornerRadius: 3)
                    .fill(idx < filled ? BevelColors.greenPrimary : BevelColors.trackGroove)
                    .frame(height: 20)
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

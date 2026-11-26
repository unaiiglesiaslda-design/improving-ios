import SwiftUI
import UIKit

extension View {
    /// Adds a native Spanish `"Listo"` toolbar button above `.numberPad` / `.decimalPad` keyboards
    /// so users can always dismiss numeric keypads with 1 tap without leaving the sheet.
    func keyboardDoneToolbar() -> some View {
        self.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Listo") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .fontWeight(.semibold)
            }
        }
    }
}

enum GaugeKind {
    case strain, recovery, sleep
}

enum AtmosphereStyle {
    case strain, recovery, sleep, stress, energy, biology, fitness
}

// MARK: - Animated Step-by-Step Numeric Text (1:1 Scrub Animation)

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

// MARK: - Signature Glowing Two-Eyed Mascot Orb (Literal Match to Screenshots 02–75)

struct BevelMascotOrb: View {
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: 0xC7D2FE),
                            Color(hex: 0x818CF8),
                            Color(hex: 0x5B63B7),
                            Color(hex: 0x3D437D)
                        ],
                        center: UnitPoint(x: 0.42, y: 0.25),
                        startRadius: size * 0.05,
                        endRadius: size * 0.65
                    )
                )
                .shadow(color: Color(hex: 0x818CF8).opacity(0.45), radius: size * 0.24, y: 0)

            HStack(spacing: size * 0.14) {
                Capsule()
                    .fill(Color.white.opacity(0.94))
                    .frame(width: size * 0.16, height: size * 0.27)
                Capsule()
                    .fill(Color.white.opacity(0.94))
                    .frame(width: size * 0.16, height: size * 0.27)
            }
            .offset(y: -size * 0.03)
        }
        .frame(width: size, height: size)
    }
}

struct IridescentPearlOrb: View {
    var size: CGFloat = 34
    var body: some View {
        BevelMascotOrb(size: size)
    }
}

// MARK: - Recessed 3D Ring Gauge (Bulletproof Animatable Trim — NEVER Sticks at 0%!)

struct BevelRecessedRingGauge: View {
    let progress: Double
    let centerText: String
    let label: String
    let kind: GaugeKind
    var size: CGFloat = 92
    var strokeWidth: CGFloat = 9.5
    var subLabel: String? = nil
    var centerSubtitle: String? = nil
    var targetRange: ClosedRange<Double>? = nil
    var hasData: Bool = true
    /// When true (used for Esfuerzo), 0% / no-activity still renders the ring with `0%`,
    /// a tiny starting progress nub at 12 o'clock, and the hatched optimal target zone.
    var showZeroBaselineArc: Bool = false

    private var effectiveHasVisualValue: Bool {
        hasData || showZeroBaselineArc
    }

    private var targetProgress: Double {
        let clamped = min(max(progress, 0), 1)
        if hasData && clamped > 0 {
            return max(clamped, 0.02)
        }
        return showZeroBaselineArc ? 0.018 : 0
    }

    private var overreachFraction: Double {
        guard kind == .strain, hasData, let tr = targetRange, targetProgress > tr.upperBound else { return 0 }
        let headroom = max(1.0 - tr.upperBound, 0.08)
        return min(max((targetProgress - tr.upperBound) / headroom, 0), 1)
    }

    private var gradientColors: [Color] {
        switch kind {
        case .strain:
            if overreachFraction > 0 {
                let s = Color.lerp(BevelColors.amberStart, BevelColors.orangeEnd, t: min(overreachFraction * 0.75, 1))
                let m = Color.lerp(BevelColors.orangeEnd, BevelColors.coralHigh, t: min(overreachFraction * 1.15, 1))
                let e = Color.lerp(BevelColors.coralHigh, BevelColors.redAlert, t: overreachFraction)
                return [s, m, e, s]
            }
            return [BevelColors.amberStart, BevelColors.orangeEnd, BevelColors.amberStart]
        case .recovery:
            return [BevelColors.limeStart, BevelColors.greenPrimary, BevelColors.emeraldEnd, BevelColors.limeStart]
        case .sleep:
            return [Color(hex: 0xC4D6FF), BevelColors.periwinkleStart, BevelColors.indigoEnd, Color(hex: 0xC4D6FF)]
        }
    }

    var body: some View {
        let pad = strokeWidth / 2 + 4
        let ringDiameter = max(size - pad * 2, 16)

        VStack(spacing: 6) {
            ZStack {
                // Static recessed bevel + groove + center dish + optimal effort hatch band
                Canvas { context, canvasSize in
                    let arcRect = CGRect(x: pad, y: pad, width: canvasSize.width - pad * 2, height: canvasSize.height - pad * 2)
                    let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                    let radius = arcRect.width / 2

                    let bezelOuter = Path(ellipseIn: arcRect.insetBy(dx: -strokeWidth * 0.65, dy: -strokeWidth * 0.65))
                    context.fill(bezelOuter, with: .color(BevelColors.isDarkMode ? Color(hex: 0x333640, alpha: 0.7) : Color(hex: 0xE5E9F0)))
                    context.stroke(bezelOuter, with: .color(Color.white.opacity(BevelColors.isDarkMode ? 0.14 : 0.7)), lineWidth: 1)

                    let groovePath = Path(ellipseIn: arcRect)
                    context.stroke(groovePath, with: .color(BevelColors.isDarkMode ? Color(hex: 0x1D1F25) : BevelColors.trackGroove), lineWidth: strokeWidth)

                    let innerDish = Path(ellipseIn: arcRect.insetBy(dx: strokeWidth * 0.56, dy: strokeWidth * 0.56))
                    context.fill(innerDish, with: .color(BevelColors.isDarkMode ? Color(hex: 0x2C2F38, alpha: 0.85) : Color.white))
                    context.stroke(innerDish, with: .color(Color.white.opacity(BevelColors.isDarkMode ? 0.08 : 0.4)), lineWidth: 0.9)

                    if effectiveHasVisualValue, let tr = targetRange {
                        let startDeg = -90.0 + tr.lowerBound * 360.0
                        let endDeg = -90.0 + tr.upperBound * 360.0
                        var bandPath = Path()
                        bandPath.addArc(center: center, radius: radius, startAngle: .degrees(startDeg), endAngle: .degrees(endDeg), clockwise: false)
                        context.stroke(bandPath, with: .color(BevelColors.strainHatchBg), style: StrokeStyle(lineWidth: strokeWidth, lineCap: .butt))

                        let steps = max(Int((endDeg - startDeg) / 4.5), 5)
                        for i in 0...steps {
                            let deg = startDeg + (endDeg - startDeg) * Double(i) / Double(steps)
                            let rad = deg * .pi / 180.0
                            let rIn = radius - strokeWidth * 0.36
                            let rOut = radius + strokeWidth * 0.36
                            var tick = Path()
                            tick.move(to: CGPoint(x: center.x + rIn * cos(rad), y: center.y + rIn * sin(rad)))
                            tick.addLine(to: CGPoint(x: center.x + rOut * cos(rad + 0.05), y: center.y + rOut * sin(rad + 0.05)))
                            context.stroke(tick, with: .color(BevelColors.strainHatchLine.opacity(0.75)), style: StrokeStyle(lineWidth: 1.25, lineCap: .round))
                        }
                    }
                }
                .frame(width: size, height: size)

                // Native GPU-animated SwiftUI trim ring — directly bound to targetProgress, NEVER gets stuck at 0%
                if targetProgress > 0 {
                    Circle()
                        .trim(from: 0, to: CGFloat(targetProgress))
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: gradientColors),
                                center: .center,
                                startAngle: .degrees(0),
                                endAngle: .degrees(360)
                            ),
                            style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: ringDiameter, height: ringDiameter)
                        .animation(.easeOut(duration: 0.45), value: targetProgress)
                }

                // Always-visible white boundary ticks for optimal effort range
                if effectiveHasVisualValue, let tr = targetRange {
                    Canvas { context, canvasSize in
                        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                        let radius = ringDiameter / 2
                        let startDeg = -90.0 + tr.lowerBound * 360.0
                        let endDeg = -90.0 + tr.upperBound * 360.0
                        let covered = min(max((targetProgress - tr.lowerBound) / max(tr.upperBound - tr.lowerBound, 0.01), 0), 1)
                        if covered > 0.05 {
                            var outerGuide = Path()
                            outerGuide.addArc(center: center, radius: radius + strokeWidth * 0.62, startAngle: .degrees(startDeg), endAngle: .degrees(endDeg), clockwise: false)
                            context.stroke(outerGuide, with: .color(Color.white.opacity(0.45)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                        }
                        for boundDeg in [startDeg, endDeg] {
                            let rad = boundDeg * .pi / 180.0
                            let rIn = radius - strokeWidth * 0.48
                            let rOut = radius + strokeWidth * 0.48
                            var bTick = Path()
                            bTick.move(to: CGPoint(x: center.x + rIn * cos(rad), y: center.y + rIn * sin(rad)))
                            bTick.addLine(to: CGPoint(x: center.x + rOut * cos(rad), y: center.y + rOut * sin(rad)))
                            context.stroke(bTick, with: .color(Color.white.opacity(0.88)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                        }
                    }
                    .frame(width: size, height: size)
                    .allowsHitTesting(false)
                }

                VStack(spacing: 1) {
                    Text(effectiveHasVisualValue ? centerText : "--%")
                        .font(ImprovingFont.metricHero(size >= 140 ? 38 : (size >= 100 ? 26 : 19)))
                        .foregroundColor(effectiveHasVisualValue ? BevelColors.textPrimary : BevelColors.textMuted)
                        .monospacedDigit()
                    if let cSub = centerSubtitle {
                        Text(effectiveHasVisualValue ? cSub : "Sin datos")
                            .font(ImprovingFont.caption(size >= 140 ? 13.5 : 10.5))
                            .foregroundColor(BevelColors.textSecondary)
                    }
                }
            }

            if !label.isEmpty {
                Text(label)
                    .font(ImprovingFont.caption(12.5))
                    .fontWeight(.semibold)
                    .foregroundColor(BevelColors.textPrimary)
            }
            if let sub = subLabel {
                Text(sub)
                    .font(ImprovingFont.caption(11))
                    .foregroundColor(BevelColors.textSecondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Radial Tick-Mark Stress Dial (Literal Match to Screenshots 01 & 10)

struct StressRadialDial: View {
    let score: Int
    let statusLabel: String
    var size: CGFloat = 92
    var isHeroGauge: Bool = false
    var hasData: Bool = true

    var body: some View {
        let frac = hasData ? min(max(Double(score) / 100.0, 0), 1) : 0
        let statusColor: Color = !hasData ? BevelColors.textMuted : (score < 30 ? BevelColors.greenPrimary : (score < 60 ? BevelColors.amberStart : BevelColors.coralHigh))

        ZStack {
            Circle()
                .fill(BevelColors.isDarkMode ? Color(hex: 0x2F323C, alpha: 0.72) : Color(hex: 0xF1F5F9))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))

            Canvas { ctx, canvasSize in
                let totalTicks = isHeroGauge ? 56 : 36
                let startDeg = 132.0
                let sweepTotal = 276.0
                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let outerR = min(canvasSize.width, canvasSize.height) / 2 - 6
                let innerR = outerR - (isHeroGauge ? 13 : 8)
                let litTicks = hasData ? max(Int(frac * Double(totalTicks)), score > 0 ? 1 : 0) : -1

                if isHeroGauge {
                    let innerCircleR = innerR - 6
                    ctx.stroke(
                        Path(ellipseIn: CGRect(x: center.x - innerCircleR, y: center.y - innerCircleR, width: innerCircleR * 2, height: innerCircleR * 2)),
                        with: .color(Color.white.opacity(0.14)),
                        lineWidth: 1
                    )
                }

                for i in 0...totalTicks {
                    let angleDeg = startDeg + (Double(i) * sweepTotal / Double(totalTicks))
                    let rad = angleDeg * .pi / 180.0
                    let ratio = Double(i) / Double(totalTicks)
                    let baseColor: Color = ratio < 0.35 ? BevelColors.greenPrimary : (ratio < 0.65 ? BevelColors.amberStart : BevelColors.coralHigh)
                    let tickColor = (hasData && i <= litTicks) ? baseColor : baseColor.opacity(0.22)

                    var line = Path()
                    line.move(to: CGPoint(x: center.x + innerR * cos(rad), y: center.y + innerR * sin(rad)))
                    line.addLine(to: CGPoint(x: center.x + outerR * cos(rad), y: center.y + outerR * sin(rad)))
                    ctx.stroke(line, with: .color(tickColor), style: StrokeStyle(lineWidth: isHeroGauge ? 2.4 : 2.0, lineCap: .round))
                }

                if isHeroGauge && hasData {
                    let ptrDeg = startDeg + frac * sweepTotal
                    let rad = ptrDeg * .pi / 180.0
                    let tip = CGPoint(x: center.x + (innerR - 14) * cos(rad), y: center.y + (innerR - 14) * sin(rad))
                    let left = CGPoint(x: center.x + (innerR - 2) * cos(rad - 0.05), y: center.y + (innerR - 2) * sin(rad - 0.05))
                    let right = CGPoint(x: center.x + (innerR - 2) * cos(rad + 0.05), y: center.y + (innerR - 2) * sin(rad + 0.05))
                    var tri = Path()
                    tri.move(to: tip); tri.addLine(to: left); tri.addLine(to: right); tri.closeSubpath()
                    ctx.fill(tri, with: .color(BevelColors.tealLow))
                }
            }

            VStack(spacing: 1) {
                Text(hasData ? "\(score)" : "--")
                    .font(ImprovingFont.metricHero(isHeroGauge ? 38 : 22))
                    .monospacedDigit()
                    .foregroundColor(hasData ? BevelColors.textPrimary : BevelColors.textMuted)
                Text(!hasData ? "Sin datos" : statusLabel)
                    .font(ImprovingFont.caption(isHeroGauge ? 13 : 10.5))
                    .fontWeight(.semibold)
                    .foregroundColor(statusColor)
            }

            if isHeroGauge {
                VStack {
                    Spacer()
                    HStack {
                        Text("0").font(ImprovingFont.caption(11)).foregroundColor(BevelColors.textMuted)
                        Spacer()
                        Text("100").font(ImprovingFont.caption(11)).foregroundColor(BevelColors.textMuted)
                    }
                    .padding(.horizontal, size * 0.22)
                    .padding(.bottom, size * 0.07)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 270° Training Load Tick Gauge (Literal Match to Screenshot 47: Cardio / Muscular)

struct TrainingLoadTickGauge: View {
    let value: Int
    let minVal: Int
    let maxVal: Int
    let optimalStartFrac: Double
    let optimalEndFrac: Double
    let currentFrac: Double
    var optimalRangeLabel: String? = nil
    var hasData: Bool = true

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Canvas { ctx, sz in
                    let center = CGPoint(x: sz.width / 2, y: sz.height * 0.58)
                    let outerR = min(sz.width, sz.height) * 0.45
                    let innerR = outerR - 11
                    let startDeg = 140.0
                    let sweepDeg = 260.0
                    let totalTicks = 44

                    // Subtle outer halo track
                    var trackArc = Path()
                    trackArc.addArc(center: center, radius: outerR + 6, startAngle: .degrees(startDeg), endAngle: .degrees(startDeg + sweepDeg), clockwise: false)
                    ctx.stroke(trackArc, with: .color(BevelColors.chartTrackSubtle), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

                    if hasData {
                        let oStart = min(max(optimalStartFrac, 0.02), 0.94)
                        let oEnd = min(max(optimalEndFrac, oStart + 0.06), 0.98)
                        var optArc = Path()
                        optArc.addArc(
                            center: center,
                            radius: outerR + 6,
                            startAngle: .degrees(startDeg + sweepDeg * oStart),
                            endAngle: .degrees(startDeg + sweepDeg * oEnd),
                            clockwise: false
                        )
                        ctx.stroke(optArc, with: .color(BevelColors.greenPrimary), style: StrokeStyle(lineWidth: 3.4, lineCap: .round))
                    }

                    let clamped = min(max(currentFrac, 0.03), 0.97)
                    let litCount = hasData ? Int(clamped * Double(totalTicks)) : -1
                    for i in 0...totalTicks {
                        let deg = startDeg + Double(i) / Double(totalTicks) * sweepDeg
                        let rad = deg * .pi / 180.0
                        var tick = Path()
                        tick.move(to: CGPoint(x: center.x + innerR * cos(rad), y: center.y + innerR * sin(rad)))
                        tick.addLine(to: CGPoint(x: center.x + outerR * cos(rad), y: center.y + outerR * sin(rad)))
                        ctx.stroke(tick, with: .color(i <= litCount ? BevelColors.chartPointerFill.opacity(0.65) : BevelColors.chartTickInactive), style: StrokeStyle(lineWidth: 1.9, lineCap: .round))
                    }

                    if hasData {
                        let knobDeg = startDeg + clamped * sweepDeg
                        let kRad = knobDeg * .pi / 180.0
                        let kPt = CGPoint(x: center.x + (outerR - 4) * cos(kRad), y: center.y + (outerR - 4) * sin(kRad))
                        ctx.fill(Path(ellipseIn: CGRect(x: kPt.x - 11, y: kPt.y - 11, width: 22, height: 22)), with: .color(BevelColors.chartTrackSubtle))
                        ctx.fill(Path(ellipseIn: CGRect(x: kPt.x - 6, y: kPt.y - 6, width: 12, height: 12)), with: .color(BevelColors.card))
                        ctx.stroke(Path(ellipseIn: CGRect(x: kPt.x - 6, y: kPt.y - 6, width: 12, height: 12)), with: .color(BevelColors.chartPointerFill), lineWidth: 2.2)
                    }
                }

                Text(hasData ? "\(value)" : "--")
                    .font(ImprovingFont.metricHero(28))
                    .monospacedDigit()
                    .foregroundColor(hasData ? BevelColors.textPrimary : BevelColors.textMuted)
                    .offset(y: 6)

                VStack {
                    Spacer()
                    HStack {
                        Text("\(minVal)").font(ImprovingFont.caption(10.5)).monospacedDigit().foregroundColor(BevelColors.textMuted)
                        Spacer()
                        Text("\(maxVal)").font(ImprovingFont.caption(10.5)).monospacedDigit().foregroundColor(BevelColors.textMuted)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 0)
                }
            }
            .frame(height: 120)

            if let optLbl = optimalRangeLabel {
                HStack(spacing: 5) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 2).fill(BevelColors.greenPrimary.opacity(0.28)).frame(width: 10, height: 10)
                        VStack(spacing: 4) {
                            Rectangle().fill(BevelColors.greenPrimary).frame(width: 10, height: 1.4)
                            Rectangle().fill(BevelColors.greenPrimary).frame(width: 10, height: 1.4)
                        }
                    }
                    Text(optLbl)
                        .font(ImprovingFont.caption(11.5))
                        .foregroundColor(BevelColors.textSecondary)
                        .lineLimit(1)
                }
                .padding(.top, 2)
            }
        }
    }
}

// MARK: - Energy Bank 34-Bar Battery Bar (Literal Match to Screenshot 01)

struct EnergyBankBatteryBar: View {
    let percent: Int
    var hasData: Bool = true
    let onClick: () -> Void

    var body: some View {
        let clamped = hasData ? min(max(percent, 0), 100) : 0

        Button(action: onClick) {
            BevelCard(cornerRadius: 18) {
                HStack(spacing: 10) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(hasData ? BevelColors.greenPrimary : BevelColors.textMuted)

                    GeometryReader { geo in
                        let barCount = 34
                        let gap: CGFloat = 2.6
                        let totalGap = gap * CGFloat(barCount - 1)
                        let barW = max((geo.size.width - totalGap) / CGFloat(barCount), 2.2)
                        let litBars = hasData ? Int((Double(clamped) / 100.0) * Double(barCount)) : 0

                        HStack(spacing: gap) {
                            ForEach(0..<barCount, id: \.self) { idx in
                                let t = Double(idx) / Double(barCount - 1)
                                let segColor = Color.lerp(BevelColors.limeStart, BevelColors.emeraldEnd, t: t)
                                Capsule()
                                    .fill(hasData && idx < litBars ? segColor : BevelColors.trackGroove)
                                    .frame(width: barW, height: 18)
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .center)
                    }
                    .frame(height: 22)

                    Text(hasData ? "\(clamped)%" : "--")
                        .font(ImprovingFont.cardTitle(15))
                        .monospacedDigit()
                        .foregroundColor(hasData ? BevelColors.textPrimary : BevelColors.textMuted)
                        .frame(minWidth: 38, alignment: .trailing)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
            }
        }
    }
}

// MARK: - Health Monitor Card with Vertical Recessed Glowing Thermometer Pill (Literal Match to Screenshot 15)

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
        case .normal: BevelColors.greenPrimary
        case .borderlineWarning: BevelColors.orangeEnd
        case .alertOutOfRange: BevelColors.redAlert
        case .noData: BevelColors.textMuted
        }
        let statusIcon: String = {
            if !hasData { return "info.circle.fill" }
            if evaluation.severity == .normal { return "checkmark.circle.fill" }
            if evaluation.isAboveBand { return "arrow.up.circle.fill" }
            if evaluation.isBelowBand { return "arrow.down.circle.fill" }
            return "checkmark.circle.fill"
        }()

        Button(action: onClick) {
            BevelCard(cornerRadius: 20) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 5) {
                            Image(systemName: systemIcon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(BevelColors.textMuted)
                            Text(title)
                                .font(ImprovingFont.caption(13.5))
                                .foregroundColor(BevelColors.textSecondary)
                                .lineLimit(1)
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(hasData ? value : "--")
                                .font(ImprovingFont.metricTile(value.count > 7 ? 17.5 : 22))
                                .monospacedDigit()
                                .foregroundColor(hasData ? BevelColors.textPrimary : BevelColors.textMuted)
                                .lineLimit(1)
                            if hasData && !unit.isEmpty {
                                Text(unit)
                                    .font(ImprovingFont.caption(12.5))
                                    .foregroundColor(BevelColors.textSecondary)
                            }
                        }

                        HStack(spacing: 5) {
                            Image(systemName: statusIcon)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(accent)
                            Text(hasData ? evaluation.statusLabel : "Sin datos")
                                .font(ImprovingFont.caption(12.5))
                                .fontWeight(.semibold)
                                .foregroundColor(accent)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)

                    Canvas { ctx, size in
                        let trackRadius = size.width / 2
                        let inset: CGFloat = 1.6
                        let innerW = size.width - inset * 2
                        let innerR = innerW / 2

                        let outerRect = CGRect(origin: .zero, size: size)
                        ctx.fill(Path(roundedRect: outerRect, cornerRadius: trackRadius), with: .color(BevelColors.trackGroove))

                        let bandTop = size.height * 0.22
                        let bandBottom = size.height * 0.78
                        let bandRect = CGRect(x: inset, y: bandTop, width: innerW, height: bandBottom - bandTop)

                        if !hasData {
                            ctx.fill(Path(roundedRect: bandRect, cornerRadius: innerR), with: .color(BevelColors.trackInnerShadow))
                            return
                        }

                        let clampedPos = min(max(evaluation.normalizedPosition, 0.10), 0.90)
                        let dotY = size.height * (1.0 - clampedPos)
                        let dotCenter = CGPoint(x: size.width / 2, y: dotY)

                        ctx.fill(Path(roundedRect: bandRect, cornerRadius: innerR), with: .color(accent.opacity(evaluation.severity == .normal ? 0.82 : 0.28)))

                        ctx.fill(Path(ellipseIn: CGRect(x: dotCenter.x - 6.5, y: dotCenter.y - 6.5, width: 13, height: 13)), with: .color(accent.opacity(0.28)))
                        ctx.fill(Path(ellipseIn: CGRect(x: dotCenter.x - 4.6, y: dotCenter.y - 4.6, width: 9.2, height: 9.2)), with: .color(BevelColors.card))
                        ctx.stroke(Path(ellipseIn: CGRect(x: dotCenter.x - 4.6, y: dotCenter.y - 4.6, width: 9.2, height: 9.2)), with: .color(accent), lineWidth: 2.0)
                    }
                    .frame(width: 12, height: 68)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
            }
        }
    }
}

// MARK: - Two-Tone Headered Stat Card (Literal Match to Screenshots 03, 06, 10)

struct HeaderedMetricCard: View {
    let icon: String
    let title: String
    let value: String
    var unit: String = ""
    var onClick: (() -> Void)? = nil

    var body: some View {
        let cardContent = VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(BevelColors.textMuted)
                Text(title)
                    .font(ImprovingFont.caption(12.5))
                    .foregroundColor(BevelColors.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(BevelColors.cardHeaderStrip)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(ImprovingFont.metricTile(22))
                    .monospacedDigit()
                    .foregroundColor(value == "--" || value == "—" ? BevelColors.textMuted : BevelColors.textPrimary)
                    .lineLimit(1)
                if !unit.isEmpty && value != "--" && value != "—" {
                    Text(unit)
                        .font(ImprovingFont.caption(13.5))
                        .foregroundColor(BevelColors.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 13)
            .background(BevelColors.card)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(BevelColors.cardBorder, lineWidth: 0.9)
        )

        if let action = onClick {
            Button(action: action) { cardContent }
        } else {
            cardContent
        }
    }
}

// MARK: - Atmospheric Hero Header with Optional < Date > Stepper Controls

struct AtmosphericHeroHeader<Content: View>: View {
    let title: String
    let subtitle: String
    var style: AtmosphereStyle = .recovery
    let onBack: () -> Void
    var onPrevDay: (() -> Void)? = nil
    var onNextDay: (() -> Void)? = nil
    var canGoNextDay: Bool = false
    var rightPrimaryIcon: String = "square.and.arrow.up"
    var onRightPrimary: (() -> Void)? = nil
    var rightSecondaryIcon: String = "info.circle"
    var onRightSecondary: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    private var atmosphereColors: [Color] {
        switch style {
        case .strain:
            return [Color(hex: 0x3D2618), Color(hex: 0x261B17), BevelColors.canvas]
        case .recovery:
            return [Color(hex: 0x2F233F), Color(hex: 0x222D28), BevelColors.canvas]
        case .sleep:
            return [Color(hex: 0x16224A), Color(hex: 0x171F3A), BevelColors.canvas]
        case .stress:
            return [Color(hex: 0x3C2C3C), Color(hex: 0x2D242E), BevelColors.canvas]
        case .energy:
            return [Color(hex: 0x3D2E1E), Color(hex: 0x28211B), BevelColors.canvas]
        case .biology:
            return [Color(hex: 0x1A2E2B), Color(hex: 0x172022), BevelColors.canvas]
        case .fitness:
            return [Color(hex: 0x36271C), Color(hex: 0x201D1B), BevelColors.canvas]
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: BevelColors.isDarkMode ? atmosphereColors : [BevelColors.canvas, BevelColors.canvas],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)

            VStack(spacing: 14) {
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(BevelColors.textPrimary)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(BevelColors.glassChromeFill))
                            .overlay(Circle().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.8))
                    }
                    Spacer()

                    HStack(spacing: 14) {
                        Button {
                            onRightPrimary?()
                        } label: {
                            Image(systemName: rightPrimaryIcon)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(BevelColors.textPrimary)
                        }
                        Button {
                            onRightSecondary?()
                        } label: {
                            Image(systemName: rightSecondaryIcon)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(BevelColors.textPrimary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .background(Capsule().fill(BevelColors.glassChromeFill))
                    .overlay(Capsule().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.8))
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                VStack(spacing: 4) {
                    Text(title)
                        .font(ImprovingFont.displayLarge(23))
                        .foregroundColor(BevelColors.textPrimary)
                    HStack(spacing: 10) {
                        if let prev = onPrevDay {
                            Button(action: prev) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(BevelColors.textSecondary)
                                    .frame(width: 26, height: 26)
                                    .background(Circle().fill(Color.white.opacity(0.08)))
                            }
                        }
                        Text(subtitle)
                            .font(ImprovingFont.caption(13.5))
                            .foregroundColor(BevelColors.textSecondary)
                        if let next = onNextDay {
                            Button(action: next) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(canGoNextDay ? BevelColors.textSecondary : BevelColors.textMuted.opacity(0.35))
                                    .frame(width: 26, height: 26)
                                    .background(Circle().fill(Color.white.opacity(canGoNextDay ? 0.08 : 0.03)))
                            }
                            .disabled(!canGoNextDay)
                        }
                    }
                }

                content()
                    .padding(.top, 4)
            }
            .padding(.bottom, 16)
        }
    }
}

// MARK: - Shared Bevel Trend Card with Honest No-Data State & Sparse Sparkline

struct BevelTrendLightCard: View {
    let trend: EffortTrendItem
    let systemIcon: String
    let onClick: () -> Void

    var body: some View {
        let lineColor = Color(hex: trend.lineColorHex)
        let statusColor: Color = switch trend.statusTone {
        case .normal: BevelColors.greenPrimary
        case .above: BevelColors.skyBlue
        case .below: BevelColors.orangeEnd
        case .noData: BevelColors.textMuted
        }
        let statusIcon: String = switch trend.statusTone {
        case .normal: "checkmark.circle.fill"
        case .above: "arrow.up.circle.fill"
        case .below: "arrow.down.circle.fill"
        case .noData: "info.circle.fill"
        }
        let realCount = trend.points.compactMap { $0 }.count

        Button(action: onClick) {
            BevelCard(cornerRadius: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: systemIcon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(BevelColors.textMuted)
                            Text(trend.title)
                                .font(ImprovingFont.caption(13.5))
                                .foregroundColor(BevelColors.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(BevelColors.textMuted)
                    }

                    HStack(alignment: .bottom, spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(trend.hasData ? trend.valueText : "No hay datos")
                                    .font(ImprovingFont.metricHero(trend.hasData ? 25 : 21))
                                    .monospacedDigit()
                                    .foregroundColor(trend.hasData ? BevelColors.textPrimary : BevelColors.textMuted)
                                    .lineLimit(1)
                                if trend.hasData && !trend.unitText.isEmpty {
                                    Text(trend.unitText)
                                        .font(ImprovingFont.sectionTitle(15))
                                        .foregroundColor(BevelColors.textSecondary)
                                }
                            }
                            HStack(spacing: 5) {
                                Image(systemName: statusIcon)
                                    .font(.system(size: 12))
                                    .foregroundColor(statusColor)
                                Text(trend.statusText)
                                    .font(ImprovingFont.caption(12.5))
                                    .fontWeight(.semibold)
                                    .foregroundColor(statusColor)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        if trend.hasData && realCount >= 2 {
                            TrendSparklineWithBand(
                                optionalPoints: trend.points,
                                bandLow: trend.bandLow,
                                bandHigh: trend.bandHigh,
                                lineColor: lineColor,
                                showBand: true,
                                showGlowDot: true
                            )
                            .frame(width: 124, height: 52)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
    }
}

// MARK: - Scroll-Collapsing Floating Liquid-Glass Bottom Bar

struct FloatingPillBottomBar: View {
    let selectedTab: MainTab
    let visibleTabs: Set<MainTab>
    let isQuickMenuOpen: Bool
    let isCollapsed: Bool
    let onSelectTab: (MainTab) -> Void
    let onToggleQuickMenu: () -> Void
    let onOpenAskBevel: () -> Void
    let onExpand: () -> Void

    private var effectiveCollapsed: Bool { isCollapsed && !isQuickMenuOpen }

    var body: some View {
        VStack(spacing: 8) {
            if !effectiveCollapsed && !isQuickMenuOpen {
                Button(action: onOpenAskBevel) {
                    HStack(spacing: 10) {
                        BevelMascotOrb(size: 26)
                        Text("Pregunta a Improving lo que sea")
                            .font(ImprovingFont.body(14))
                            .foregroundColor(BevelColors.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        Capsule(style: .continuous)
                            .fill(BevelColors.glassChromeFill)
                            .shadow(color: .black.opacity(0.32), radius: 12, y: 5)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.9)
                    )
                }
                .padding(.horizontal, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 10) {
                if effectiveCollapsed {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onExpand()
                    } label: {
                        Image(systemName: selectedTab.systemIcon)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundColor(BevelColors.textPrimary)
                            .frame(width: 50, height: 50)
                            .background(
                                Circle()
                                    .fill(BevelColors.glassChromeFill)
                                    .shadow(color: .black.opacity(0.35), radius: 12, y: 5)
                            )
                            .overlay(Circle().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.9))
                    }
                    .accessibilityLabel("Mostrar barra (\(selectedTab.label))")

                    Button(action: onOpenAskBevel) {
                        HStack(spacing: 9) {
                            BevelMascotOrb(size: 26)
                            Text("Preguntar a Improving")
                                .font(ImprovingFont.body(14))
                                .foregroundColor(BevelColors.textSecondary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 50)
                        .background(
                            Capsule(style: .continuous)
                                .fill(BevelColors.glassChromeFill)
                                .shadow(color: .black.opacity(0.35), radius: 12, y: 5)
                        )
                        .overlay(Capsule().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.9))
                    }

                    plusCircleButton
                } else {
                    HStack(spacing: 4) {
                        ForEach([MainTab.hoy, .diario, .fitness, .biologia]) { tab in
                            if visibleTabs.contains(tab) {
                                pillTabButton(tab)
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(BevelColors.glassChromeFill)
                            .shadow(color: .black.opacity(0.38), radius: 16, y: 6)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.9)
                    )

                    plusCircleButton
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: effectiveCollapsed)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: isQuickMenuOpen)
    }

    private var plusCircleButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onToggleQuickMenu()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(BevelColors.textPrimary)
                .rotationEffect(.degrees(isQuickMenuOpen ? 45 : 0))
                .frame(width: 54, height: 54)
                .background(
                    Circle()
                        .fill(BevelColors.glassChromeFill)
                        .shadow(color: .black.opacity(0.38), radius: 14, y: 6)
                )
                .overlay(Circle().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.9))
        }
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
                    .font(.system(size: 16.5, weight: isSelected ? .bold : .medium))
                Text(tab.label)
                    .font(ImprovingFont.caption(10))
                    .fontWeight(isSelected ? .bold : .medium)
            }
            .foregroundColor(isSelected ? .white : BevelColors.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? BevelColors.floatingDarkButton : .clear)
            )
        }
    }
}

// MARK: - Peeking Mascot Orb Floating AI Pill

struct FloatingMetricAiCoachOverlay: View {
    let metricKey: String
    let metricTitle: String
    let insight: MetricFloatingAiInsight
    let scrollCollapseSignal: Int
    var leadingEmoji: String = "✨"

    @State private var isLoading = true
    @State private var isExpanded = false
    @State private var isFullyExpanded = false
    @State private var collapsedByScroll = false

    var body: some View {
        VStack(spacing: 8) {
            if isExpanded && !isLoading {
                let shortText = insight.shortExpandedMessage.isEmpty ? insight.expandedMessage : insight.shortExpandedMessage
                let hasMore = !insight.expandedMessage.isEmpty && insight.expandedMessage != shortText

                BevelCard(cornerRadius: 22, backgroundColor: BevelColors.card.opacity(0.97)) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            HStack(spacing: 7) {
                                BevelMascotOrb(size: 18)
                                Text(insight.expandedHeadline)
                                    .font(ImprovingFont.microLabel(10.5))
                                    .foregroundColor(BevelColors.greenPrimary)
                            }
                            Spacer()
                            Text(metricTitle)
                                .font(ImprovingFont.caption(10.5))
                                .foregroundColor(BevelColors.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(BevelColors.cardSubtle))
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
                                    .foregroundColor(BevelColors.greenPrimary)
                                Image(systemName: isFullyExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(BevelColors.greenPrimary)
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
                ZStack(alignment: .top) {
                    BevelMascotOrb(size: 32)
                        .offset(y: -18)

                    HStack(spacing: 8) {
                        if isLoading {
                            HStack(spacing: 4) {
                                Circle().fill(BevelColors.textSecondary).frame(width: 5, height: 5)
                                Circle().fill(BevelColors.textMuted).frame(width: 5, height: 5)
                                Circle().fill(BevelColors.textMuted.opacity(0.5)).frame(width: 5, height: 5)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                        } else {
                            Text(leadingEmoji)
                                .font(.system(size: 13))
                            Text(insight.shortPillText)
                                .font(ImprovingFont.cardTitle(13.5))
                                .foregroundColor(BevelColors.textPrimary)
                                .lineLimit(1)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(BevelColors.textMuted)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(BevelColors.glassChromeFill))
                    .overlay(Capsule().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.9))
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
                }
                .padding(.top, 18)
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
            try? await Task.sleep(nanoseconds: 340_000_000)
            await MainActor.run {
                isLoading = false
            }
        }
    }
}

// MARK: - Unified Workout Sport Icon & Color Resolver (P5)

enum WorkoutSportStyle {
    struct Style {
        let icon: String
        let fg: Color
        let bg: Color
    }

    static func resolve(title: String, category: String = "") -> Style {
        let low = "\(title) \(category)".folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
        if low.contains("bici") || low.contains("ciclism") || low.contains("cycl") || low.contains("spin") || low.contains("rodillo") {
            return Style(icon: "bicycle", fg: Color(hex: 0x9B7BF8), bg: Color(hex: 0x2E2748))
        }
        if low.contains("fuerza") || low.contains("strength") || low.contains("pesas") || low.contains("gimnasio") || low.contains("gym") || low.contains("crossfit") || low.contains("funcional") || low.contains("hipertrofia") {
            return Style(icon: "figure.strengthtraining.traditional", fg: BevelColors.amberStart, bg: Color(hex: 0x3D321E))
        }
        if low.contains("carrera") || low.contains("correr") || low.contains("run") || low.contains("trail") || low.contains("maraton") || low.contains("pista") || low.contains("trote") {
            return Style(icon: "figure.run", fg: BevelColors.greenPrimary, bg: Color(hex: 0x1D3528))
        }
        if low.contains("nataci") || low.contains("nadar") || low.contains("swim") || low.contains("piscina") || low.contains("aguas abiertas") {
            return Style(icon: "figure.pool.swim", fg: BevelColors.cyanBright, bg: Color(hex: 0x1A323D))
        }
        if low.contains("futbol") || low.contains("soccer") || low.contains("futsal") {
            return Style(icon: "figure.soccer", fg: BevelColors.emeraldEnd, bg: Color(hex: 0x1C3629))
        }
        if low.contains("padel") || low.contains("tenis") || low.contains("tennis") || low.contains("squash") || low.contains("badminton") || low.contains("raqueta") {
            return Style(icon: "figure.tennis", fg: BevelColors.limeStart, bg: Color(hex: 0x2F381E))
        }
        if low.contains("baloncesto") || low.contains("basket") {
            return Style(icon: "figure.basketball", fg: BevelColors.orangeEnd, bg: Color(hex: 0x3D281D))
        }
        if low.contains("hiit") || low.contains("interval") || low.contains("circuito") || low.contains("metcon") {
            return Style(icon: "figure.highintensity.intervaltraining", fg: BevelColors.coralHigh, bg: Color(hex: 0x3C2224))
        }
        if low.contains("yoga") || low.contains("pilates") || low.contains("estir") || low.contains("movilidad") || low.contains("flexibil") {
            return Style(icon: "figure.yoga", fg: Color(hex: 0xC084FC), bg: Color(hex: 0x312340))
        }
        if low.contains("sender") || low.contains("hik") || low.contains("montan") || low.contains("trek") {
            return Style(icon: "figure.hiking", fg: BevelColors.bioTeal, bg: Color(hex: 0x1B3532))
        }
        if low.contains("camin") || low.contains("walk") || low.contains("paseo") {
            return Style(icon: "figure.walk", fg: BevelColors.tealLow, bg: Color(hex: 0x1B3434))
        }
        if low.contains("remo") || low.contains("row") || low.contains("kayak") || low.contains("piragua") {
            return Style(icon: "figure.rower", fg: BevelColors.skyBlue, bg: Color(hex: 0x1E2E45))
        }
        if low.contains("boxeo") || low.contains("boxing") || low.contains("kick") || low.contains("mma") || low.contains("artes marciales") {
            return Style(icon: "figure.boxing", fg: BevelColors.coralHigh, bg: Color(hex: 0x3A2125))
        }
        if low.contains("escalada") || low.contains("climb") || low.contains("boulder") {
            return Style(icon: "figure.climbing", fg: BevelColors.amberStart, bg: Color(hex: 0x3A2F1E))
        }
        if low.contains("esqui") || low.contains("ski") || low.contains("snow") {
            return Style(icon: "figure.skiing.downhill", fg: BevelColors.cyanBright, bg: Color(hex: 0x1C303D))
        }
        if low.contains("core") || low.contains("abdom") {
            return Style(icon: "figure.core.training", fg: BevelColors.amberStart, bg: Color(hex: 0x392E1E))
        }
        return Style(icon: "figure.mixed.cardio", fg: BevelColors.skyBlue, bg: Color(hex: 0x1F2D46))
    }
}

// MARK: - 3x3 Functional Quick Actions Sheet (P7 — Real 1-Tap Actions!)

struct QuickActionsOverlaySheet: View {
    let hydrationTodayMl: Int
    let onDismiss: () -> Void
    let onCaptureFoodAI: () -> Void
    let onScanBarcode: () -> Void
    let onDescribeFoodAI: () -> Void
    let onAddWater250ml: () -> Void
    let onOpenAskBevel: () -> Void
    let onQuickJournalNote: () -> Void
    let onLogScale: () -> Void
    let onLogWorkout: () -> Void
    let onOpenWeeklyReview: () -> Void
    let onOpenDevices: () -> Void

    @State private var waterAddedFlash: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.55)
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
                        Text("Registrar en 1 toque")
                            .font(ImprovingFont.sectionTitle(18))
                            .foregroundColor(BevelColors.textPrimary)
                    }

                    HStack {
                        quickActionTile("Foto comida IA", icon: "camera.fill", badge: true, action: onCaptureFoodAI)
                        Spacer()
                        quickActionTile("Código barras", icon: "barcode.viewfinder", action: onScanBarcode)
                        Spacer()
                        quickActionTile("Describir comida", icon: "square.and.pencil", action: onDescribeFoodAI)
                    }

                    HStack(alignment: .center) {
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onAddWater250ml()
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                                waterAddedFlash = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                                withAnimation(.easeOut(duration: 0.25)) {
                                    waterAddedFlash = false
                                }
                            }
                        } label: {
                            VStack(spacing: 7) {
                                ZStack(alignment: .topTrailing) {
                                    Circle()
                                        .fill(waterAddedFlash ? BevelColors.skyBlue.opacity(0.28) : BevelColors.cardSubtle)
                                        .frame(width: 50, height: 50)
                                        .overlay(Circle().strokeBorder(waterAddedFlash ? BevelColors.skyBlue : BevelColors.cardBorder, lineWidth: 1.0))
                                    Image(systemName: waterAddedFlash ? "checkmark" : "drop.fill")
                                        .font(.system(size: 19, weight: .semibold))
                                        .foregroundColor(BevelColors.skyBlue)
                                        .frame(width: 50, height: 50)
                                    if hydrationTodayMl > 0 {
                                        Text("\(hydrationTodayMl / 1000).\(String(format: "%01d", (hydrationTodayMl % 1000) / 100))L")
                                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(BevelColors.skyBlue))
                                            .offset(x: 6, y: -2)
                                    }
                                }
                                Text(waterAddedFlash ? "+250 ml ✓" : "+250 ml agua")
                                    .font(ImprovingFont.caption(11))
                                    .fontWeight(waterAddedFlash ? .bold : .regular)
                                    .foregroundColor(waterAddedFlash ? BevelColors.skyBlue : BevelColors.textSecondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 92)
                        }

                        Spacer()
                        Button(action: onOpenAskBevel) {
                            VStack(spacing: 8) {
                                BevelMascotOrb(size: 58)
                                Text("Ask Improving")
                                    .font(ImprovingFont.caption(12))
                                    .fontWeight(.bold)
                                    .foregroundColor(BevelColors.textPrimary)
                            }
                            .frame(width: 96)
                        }
                        Spacer()
                        quickActionTile("Nota Diario", icon: "note.text.badge.plus", action: onQuickJournalNote)
                    }

                    HStack {
                        quickActionTile("Báscula / Peso", icon: "scalemass.fill", action: onLogScale)
                        Spacer()
                        quickActionTile("Registrar entreno", icon: "dumbbell.fill", action: onLogWorkout)
                        Spacer()
                        quickActionTile("Resumen 7 días", icon: "calendar.badge.checkmark", action: onOpenWeeklyReview)
                    }

                    Button(action: onOpenDevices) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(BevelColors.greenPrimary)
                            Text("WHOOP BLE + Apple Health · Configurar")
                                .font(ImprovingFont.caption(12))
                                .fontWeight(.semibold)
                                .foregroundColor(BevelColors.greenPrimary)
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
            .padding(.bottom, 92)
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

// MARK: - 4-Hour Time-Aware, Section-Specific Live AI Coaching Card

struct LiveAiCoachingCard: View {
    let section: CoachingSection
    @ObservedObject var store: ImprovingStore
    var backgroundColor: Color? = nil
    var embedded: Bool = false
    var onAskMore: (() -> Void)? = nil

    @State private var clockTick: Int = 0

    var body: some View {
        let card = store.coachingCard(for: section)
        let loading = store.isLoadingCoaching(for: section)
        let taskKey = "\(store.coachingSlotKey(for: section))_\(clockTick)"

        let innerContent = VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                BevelMascotOrb(size: 20)
                if let c = card {
                    Text("\(c.emoji) \(c.headline)")
                        .font(ImprovingFont.cardTitle(14.5))
                        .foregroundColor(BevelColors.textPrimary)
                        .lineLimit(2)
                } else {
                    Text("COACHING · \(section.displayName.uppercased())")
                        .font(ImprovingFont.microLabel(11))
                        .foregroundColor(BevelColors.textMuted)
                }
                Spacer(minLength: 4)
                if loading {
                    ProgressView()
                        .scaleEffect(0.72)
                        .tint(BevelColors.periwinkleStart)
                } else {
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        store.refreshCoachingIfNeeded(for: section, force: true)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(BevelColors.textMuted)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color.white.opacity(0.06)))
                    }
                    .accessibilityLabel("Actualizar mensaje de coaching")
                }
            }

            if let c = card {
                Text(c.body)
                    .font(ImprovingFont.body(13.5))
                    .foregroundColor(BevelColors.textPrimary.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Image(systemName: c.isLiveAI ? "sparkles" : "clock")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(c.isLiveAI ? BevelColors.greenPrimary : BevelColors.textMuted)
                    Text("Act. \(c.generatedAtLabel) · Próx. \(c.nextUpdateLabel) (cada 4h)")
                        .font(ImprovingFont.caption(11))
                        .foregroundColor(BevelColors.textMuted)
                    Spacer()
                    if let ask = onAskMore {
                        Button(action: ask) {
                            HStack(spacing: 3) {
                                Text("Hablar con IA")
                                    .font(ImprovingFont.caption(11.5))
                                    .fontWeight(.semibold)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9.5, weight: .bold))
                            }
                            .foregroundColor(BevelColors.skyBlue)
                        }
                    }
                }
                .padding(.top, 2)
            } else {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("Preparando tu análisis personalizado de \(section.displayName.lowercased()) para esta hora...")
                        .font(ImprovingFont.caption(12.5))
                        .foregroundColor(BevelColors.textSecondary)
                }
                .padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .task(id: taskKey) {
            store.refreshCoachingIfNeeded(for: section)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            clockTick += 1
        }

        if embedded {
            innerContent
                .background((backgroundColor ?? BevelColors.cardSubtle).opacity(0.65))
        } else {
            BevelCard(cornerRadius: 20, backgroundColor: backgroundColor ?? BevelColors.card) {
                innerContent
            }
        }
    }
}

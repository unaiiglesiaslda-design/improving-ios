import SwiftUI

// MARK: - Interactive Baseline Chart with Rolling Band, Hollow Nodes & Glowing End Dot (Screenshots 16–33)

struct HealthMetricBaselineChart: View {
    let points: [Double]
    let dates: [String]
    let bandLow: Double
    let bandHigh: Double
    let averageText: String
    let accentColor: Color
    let valueFormatter: (Double) -> String
    var onPointSelected: (Int?, Double?, String?) -> Void = { _, _, _ in }

    @State private var selectedIdx: Int? = nil
    @State private var animatedDisplayVal: Double = 0

    var body: some View {
        let safePoints = points.count >= 2 ? points : [bandLow, bandHigh]
        let minVal = min(safePoints.min() ?? bandLow, bandLow)
        let maxVal = max(safePoints.max() ?? bandHigh, bandHigh)
        let span = max(maxVal - minVal, 0.5)
        let pad = max(span * 0.25, 0.3)
        let chartMin = minVal - pad
        let chartMax = maxVal + pad
        let chartSpan = max(chartMax - chartMin, 0.5)
        let avgVal = safePoints.reduce(0, +) / Double(safePoints.count)

        VStack(spacing: 6) {
            HStack(spacing: 6) {
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    let stepX = w / CGFloat(max(safePoints.count - 1, 1))
                    let yFor: (Double) -> CGFloat = { v in
                        h * (1.0 - CGFloat(min(max((v - chartMin) / chartSpan, 0), 1)))
                    }

                    ZStack(alignment: .topLeading) {
                        Canvas { ctx, size in
                            for frac in [0.1, 0.37, 0.64, 0.9] {
                                let y = size.height * frac
                                var gPath = Path()
                                gPath.move(to: CGPoint(x: 0, y: y))
                                gPath.addLine(to: CGPoint(x: size.width, y: y))
                                ctx.stroke(gPath, with: .color(Color.white.opacity(0.06)), lineWidth: 1)
                            }

                            // Shaded rolling envelope band
                            let halfBand = max((bandHigh - bandLow) * 0.48, chartSpan * 0.14)
                            var bandPath = Path()
                            for (idx, v) in safePoints.enumerated() {
                                let smoothed = (v + avgVal * 2.0) / 3.0
                                let pt = CGPoint(x: CGFloat(idx) * stepX, y: yFor(smoothed + halfBand))
                                if idx == 0 { bandPath.move(to: pt) } else { bandPath.addLine(to: pt) }
                            }
                            for (idx, v) in safePoints.enumerated().reversed() {
                                let smoothed = (v + avgVal * 2.0) / 3.0
                                bandPath.addLine(to: CGPoint(x: CGFloat(idx) * stepX, y: yFor(smoothed - halfBand)))
                            }
                            bandPath.closeSubpath()
                            ctx.fill(bandPath, with: .color(accentColor.opacity(0.18)))

                            // Dotted average line
                            let avgY = yFor(avgVal)
                            var avgPath = Path()
                            avgPath.move(to: CGPoint(x: 0, y: avgY))
                            avgPath.addLine(to: CGPoint(x: size.width, y: avgY))
                            ctx.stroke(avgPath, with: .color(accentColor.opacity(selectedIdx == nil ? 0.65 : 0.22)), style: StrokeStyle(lineWidth: 1.4, dash: [3, 4]))

                            if let sel = selectedIdx {
                                let sx = CGFloat(sel) * stepX
                                var vPath = Path()
                                vPath.move(to: CGPoint(x: sx, y: 0))
                                vPath.addLine(to: CGPoint(x: sx, y: size.height))
                                ctx.stroke(vPath, with: .color(BevelColors.textPrimary.opacity(0.28)), style: StrokeStyle(lineWidth: 1.4, dash: [5, 4]))
                            }

                            // Main curve
                            var linePath = Path()
                            for (idx, v) in safePoints.enumerated() {
                                let pt = CGPoint(x: CGFloat(idx) * stepX, y: yFor(v))
                                if idx == 0 { linePath.move(to: pt) } else { linePath.addLine(to: pt) }
                            }
                            ctx.stroke(linePath, with: .color(accentColor), style: StrokeStyle(lineWidth: 2.1, lineCap: .round, lineJoin: .round))

                            // Hollow dark-centered nodes + glowing terminal node (exact match to Screenshots 16–31)
                            for (idx, v) in safePoints.enumerated() {
                                let pt = CGPoint(x: CGFloat(idx) * stepX, y: yFor(v))
                                if idx == selectedIdx {
                                    ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 12, y: pt.y - 12, width: 24, height: 24)), with: .color(accentColor.opacity(0.28)))
                                    ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 5.5, y: pt.y - 5.5, width: 11, height: 11)), with: .color(BevelColors.sheetHeaderBg))
                                    ctx.stroke(Path(ellipseIn: CGRect(x: pt.x - 5.5, y: pt.y - 5.5, width: 11, height: 11)), with: .color(accentColor), lineWidth: 2.5)
                                } else if selectedIdx == nil && idx == safePoints.count - 1 {
                                    ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 11, y: pt.y - 11, width: 22, height: 22)), with: .color(accentColor.opacity(0.26)))
                                    ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10)), with: .color(BevelColors.sheetHeaderBg))
                                    ctx.stroke(Path(ellipseIn: CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10)), with: .color(accentColor), lineWidth: 2.4)
                                } else {
                                    let rect = CGRect(x: pt.x - 3.3, y: pt.y - 3.3, width: 6.6, height: 6.6)
                                    ctx.fill(Path(ellipseIn: rect), with: .color(BevelColors.sheetHeaderBg))
                                    ctx.stroke(Path(ellipseIn: rect), with: .color(accentColor), lineWidth: 1.7)
                                }
                            }
                        }

                        if selectedIdx == nil && !averageText.isEmpty {
                            Text(averageText)
                                .font(ImprovingFont.caption(11.5))
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(accentColor))
                                .position(x: w * 0.48, y: min(max(yFor(avgVal), 16), h - 16))
                        } else if let sel = selectedIdx {
                            let dateStr = (sel < dates.count) ? "\(dates[sel]) · " : ""
                            let pillX = min(max(CGFloat(sel) * stepX, 68), w - 68)
                            let ptY = yFor(safePoints[sel])
                            let pillY = ptY > 40 ? ptY - 24 : ptY + 24
                            HStack(spacing: 0) {
                                Text(dateStr)
                                    .font(ImprovingFont.caption(11.5))
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                Text(valueFormatter(animatedDisplayVal))
                                    .font(ImprovingFont.caption(11.5))
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(BevelColors.floatingDarkButton))
                            .position(x: pillX, y: pillY)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { val in
                                let rawIdx = Int((val.location.x / max(stepX, 1)).rounded())
                                let clamped = min(max(rawIdx, 0), safePoints.count - 1)
                                if selectedIdx != clamped {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    selectedIdx = clamped
                                    let targetVal = safePoints[clamped]
                                    withAnimation(.easeOut(duration: 0.22)) {
                                        animatedDisplayVal = targetVal
                                    }
                                    let d = clamped < dates.count ? dates[clamped] : nil
                                    onPointSelected(clamped, targetVal, d)
                                }
                            }
                    )
                    .onTapGesture {
                        if selectedIdx != nil {
                            selectedIdx = nil
                            onPointSelected(nil, nil, nil)
                        }
                    }
                }
                .frame(height: 178)

                VStack(alignment: .trailing) {
                    Text(String(format: "%.1f", locale: Locale(identifier: "es_ES"), chartMax - chartSpan * 0.1))
                    Spacer()
                    Text(String(format: "%.1f", locale: Locale(identifier: "es_ES"), chartMax - chartSpan * 0.37))
                    Spacer()
                    Text(String(format: "%.1f", locale: Locale(identifier: "es_ES"), chartMax - chartSpan * 0.64))
                    Spacer()
                    Text(String(format: "%.1f", locale: Locale(identifier: "es_ES"), chartMax - chartSpan * 0.9))
                }
                .font(ImprovingFont.caption(10.5))
                .monospacedDigit()
                .foregroundColor(BevelColors.textMuted)
                .frame(height: 168)
            }

            if !dates.isEmpty {
                HStack {
                    Text(dates.first ?? "")
                    Spacer()
                    if dates.count > 3 {
                        Text(dates[dates.count / 3])
                        Spacer()
                        Text(dates[(dates.count * 2) / 3])
                        Spacer()
                    }
                    Text(dates.last ?? "")
                }
                .font(ImprovingFont.caption(10.5))
                .foregroundColor(BevelColors.textMuted)
                .padding(.trailing, 34)
            }
        }
        .onAppear {
            animatedDisplayVal = safePoints.last ?? 0
        }
    }
}

// MARK: - Trend Sparkline with Shaded Rolling Band & Glowing End Dot (Screenshots 02, 04, 05, 08, 09, 12, 71)

struct TrendSparklineWithBand: View {
    let points: [Double]
    var bandLow: Double = 40
    var bandHigh: Double = 80
    let lineColor: Color
    var fillUnder: Bool = true
    var showBand: Bool = false
    var showGlowDot: Bool = false

    var body: some View {
        let safe = points.count >= 2 ? points : [bandLow, bandHigh]
        let minV = min(safe.min() ?? 0, bandLow)
        let maxV = max(safe.max() ?? 1, bandHigh)
        let span = max(maxV - minV, 1)

        Canvas { ctx, size in
            let rightPad: CGFloat = showGlowDot ? 8 : 2
            let drawW = max(size.width - rightPad, 10)
            let stepX = drawW / CGFloat(max(safe.count - 1, 1))
            let yFor: (Double) -> CGFloat = { v in
                size.height - 6 - CGFloat((v - minV) / span) * (size.height - 12)
            }

            if showBand {
                let topY = yFor(bandHigh)
                let botY = yFor(bandLow)
                let bandRect = CGRect(x: 0, y: min(topY, botY), width: drawW, height: max(abs(botY - topY), 10))
                ctx.fill(Path(roundedRect: bandRect, cornerRadius: 3), with: .color(lineColor.opacity(0.18)))
            }

            var line = Path()
            var fill = Path()
            for (idx, v) in safe.enumerated() {
                let pt = CGPoint(x: CGFloat(idx) * stepX, y: yFor(v))
                if idx == 0 {
                    line.move(to: pt)
                    fill.move(to: CGPoint(x: 0, y: size.height))
                    fill.addLine(to: pt)
                } else {
                    line.addLine(to: pt)
                    fill.addLine(to: pt)
                }
            }
            fill.addLine(to: CGPoint(x: drawW, y: size.height))
            fill.closeSubpath()

            if fillUnder && !showBand {
                ctx.fill(fill, with: .linearGradient(Gradient(colors: [lineColor.opacity(0.22), .clear]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            }
            ctx.stroke(line, with: .color(lineColor), style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))

            if showGlowDot, let last = safe.last {
                let pt = CGPoint(x: drawW, y: yFor(last))
                ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 8, y: pt.y - 8, width: 16, height: 16)), with: .color(lineColor.opacity(0.28)))
                ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 4, y: pt.y - 4, width: 8, height: 8)), with: .color(BevelColors.card))
                ctx.stroke(Path(ellipseIn: CGRect(x: pt.x - 4, y: pt.y - 4, width: 8, height: 8)), with: .color(lineColor), lineWidth: 2.0)
            }
        }
    }
}

// MARK: - Stepped Cumulative Comparison Chart (Literal Match to Screenshots 47, 54, 56)

struct SteppedCumulativeComparisonChart: View {
    let currentPoints: [Double]
    let previousPoints: [Double]
    let accentColor: Color
    var rightLabels: [String] = []
    var bottomDates: [String] = []
    var height: CGFloat = 158

    var body: some View {
        let safeCur = currentPoints.count >= 2 ? currentPoints : [0, 1]
        let safePrev = previousPoints.count >= 2 ? previousPoints : safeCur
        let maxV = max(max(safeCur.max() ?? 1, safePrev.max() ?? 1), 1)

        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Canvas { ctx, sz in
                    let drawW = sz.width - 10
                    let yFor: (Double) -> CGFloat = { v in sz.height - 6 - CGFloat(v / maxV) * (sz.height - 16) }

                    for f in [0.15, 0.45, 0.75, 0.96] {
                        var gp = Path()
                        gp.move(to: CGPoint(x: 0, y: sz.height * f))
                        gp.addLine(to: CGPoint(x: drawW, y: sz.height * f))
                        ctx.stroke(gp, with: .color(Color.white.opacity(0.06)), lineWidth: 1)
                    }

                    // Previous period subtle gray stepped line
                    let prevStep = drawW / CGFloat(max(safePrev.count - 1, 1))
                    var prevPath = Path()
                    for (i, v) in safePrev.enumerated() {
                        let p = CGPoint(x: CGFloat(i) * prevStep, y: yFor(v))
                        if i == 0 { prevPath.move(to: p) } else { prevPath.addLine(to: p) }
                    }
                    ctx.stroke(prevPath, with: .color(Color.white.opacity(0.22)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))

                    // Current period stepped cyan/pink area + glowing dot
                    let curStep = drawW / CGFloat(max(safeCur.count - 1, 1))
                    var curLine = Path()
                    var curFill = Path()
                    for (i, v) in safeCur.enumerated() {
                        let p = CGPoint(x: CGFloat(i) * curStep, y: yFor(v))
                        if i == 0 {
                            curLine.move(to: p)
                            curFill.move(to: CGPoint(x: 0, y: sz.height))
                            curFill.addLine(to: p)
                        } else {
                            curLine.addLine(to: p)
                            curFill.addLine(to: p)
                        }
                    }
                    curFill.addLine(to: CGPoint(x: drawW, y: sz.height))
                    curFill.closeSubpath()

                    ctx.fill(curFill, with: .linearGradient(Gradient(colors: [accentColor.opacity(0.24), .clear]), startPoint: .zero, endPoint: CGPoint(x: 0, y: sz.height)))
                    ctx.stroke(curLine, with: .color(accentColor), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

                    if let last = safeCur.last {
                        let pt = CGPoint(x: drawW, y: yFor(last))
                        ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 10, y: pt.y - 10, width: 20, height: 20)), with: .color(accentColor.opacity(0.28)))
                        ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 4.5, y: pt.y - 4.5, width: 9, height: 9)), with: .color(accentColor))
                    }
                }
                .frame(height: height)

                if !rightLabels.isEmpty {
                    VStack(alignment: .trailing) {
                        ForEach(Array(rightLabels.enumerated()), id: \.offset) { idx, lbl in
                            Text(lbl)
                            if idx < rightLabels.count - 1 { Spacer() }
                        }
                    }
                    .font(ImprovingFont.caption(10.5))
                    .foregroundColor(BevelColors.textMuted)
                    .frame(height: height - 8)
                }
            }

            if !bottomDates.isEmpty {
                HStack {
                    ForEach(Array(bottomDates.enumerated()), id: \.offset) { idx, d in
                        Text(d)
                        if idx < bottomDates.count - 1 { Spacer() }
                    }
                }
                .font(ImprovingFont.caption(10.5))
                .foregroundColor(BevelColors.textMuted)
            }
        }
    }
}

// MARK: - 5-Segment Horizontal Range Bar (Literal Match to Screenshots 58 & 61: VO2 max & HRR)

struct FiveSegmentRangeBar: View {
    let labels: [String] // 5 boundary labels
    let activeSegmentIndex: Int // 0..4
    let activeColor: Color
    let pointerFraction: Double // 0..1
    let rangeTitle: String
    let subtitle: String
    let footerDate: String

    var body: some View {
        BevelCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 10) {
                GeometryReader { geo in
                    let segGap: CGFloat = 3
                    let segW = (geo.size.width - segGap * 4) / 5.0
                    ZStack(alignment: .topLeading) {
                        HStack(spacing: segGap) {
                            ForEach(0..<5, id: \.self) { i in
                                RoundedRectangle(cornerRadius: i == 0 || i == 4 ? 6 : 3)
                                    .fill(i == activeSegmentIndex ? activeColor : activeColor.opacity(0.22))
                                    .frame(width: segW, height: 14)
                            }
                        }
                        .padding(.top, 5)

                        // White downward pointer triangle
                        Image(systemName: "arrowtriangle.down.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                            .offset(x: max(4, min(geo.size.width - 14, geo.size.width * CGFloat(pointerFraction) - 5)), y: 0)
                    }
                }
                .frame(height: 22)

                HStack {
                    ForEach(Array(labels.enumerated()), id: \.offset) { idx, lbl in
                        Text(lbl)
                            .font(ImprovingFont.caption(11))
                            .foregroundColor(BevelColors.textMuted)
                        if idx < labels.count - 1 { Spacer() }
                    }
                }

                HStack(spacing: 4) {
                    Text("Tu rango es")
                        .font(ImprovingFont.cardTitle(14.5))
                        .foregroundColor(BevelColors.textPrimary)
                    Text(rangeTitle)
                        .font(ImprovingFont.cardTitle(14.5))
                        .foregroundColor(activeColor)
                }

                Text(subtitle)
                    .font(ImprovingFont.caption(12))
                    .foregroundColor(BevelColors.textSecondary)

                Text(footerDate)
                    .font(ImprovingFont.caption(11.5))
                    .foregroundColor(BevelColors.textMuted)
            }
            .padding(16)
        }
    }
}

// MARK: - 24-Hour Circular Sleep Schedule Dial (Literal Match to Screenshot 07)

struct SleepSchedule24hDial: View {
    let windDownText: String
    let bedtimeText: String
    let wakeTimeText: String
    let sleepNeedText: String
    let onOpenSleepNeed: () -> Void

    var body: some View {
        BevelCard(cornerRadius: 22, backgroundColor: BevelColors.isDarkMode ? Color(hex: 0x202741) : BevelColors.card) {
            VStack(spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Relajación")
                            .font(ImprovingFont.caption(12.5))
                            .foregroundColor(BevelColors.textSecondary)
                        Text(windDownText)
                            .font(ImprovingFont.metricHero(22))
                            .monospacedDigit()
                            .foregroundColor(BevelColors.textPrimary)
                    }
                    .frame(maxWidth: .infinity)

                    Rectangle().fill(BevelColors.divider).frame(width: 1, height: 38)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Hora de dormir\nobjetivo")
                            .font(ImprovingFont.caption(12))
                            .foregroundColor(BevelColors.textSecondary)
                        Text(bedtimeText)
                            .font(ImprovingFont.metricHero(22))
                            .monospacedDigit()
                            .foregroundColor(BevelColors.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.top, 4)

                // 24h Circular Clock Dial (Screenshot 07)
                ZStack {
                    Canvas { ctx, sz in
                        let center = CGPoint(x: sz.width / 2, y: sz.height / 2)
                        let outerR = min(sz.width, sz.height) / 2 - 14
                        let ringW: CGFloat = 24

                        // Outer recessed track
                        ctx.stroke(
                            Path(ellipseIn: CGRect(x: center.x - outerR, y: center.y - outerR, width: outerR * 2, height: outerR * 2)),
                            with: .color(Color(hex: 0x3A436B, alpha: 0.65)),
                            lineWidth: ringW
                        )

                        // Periwinkle sleep window arc (0:17 -> 7:40 ≈ -85° to +25°)
                        var sleepArc = Path()
                        sleepArc.addArc(center: center, radius: outerR, startAngle: .degrees(-86), endAngle: .degrees(24), clockwise: false)
                        ctx.stroke(sleepArc, with: .color(Color(hex: 0x8294EA)), style: StrokeStyle(lineWidth: ringW, lineCap: .round))

                        // Subtle tick marks inside clock face
                        let tickOuter = outerR - ringW / 2 - 6
                        for i in 0..<48 {
                            let deg = Double(i) * 7.5 - 90
                            let rad = deg * .pi / 180.0
                            let isMajor = i % 4 == 0
                            let rIn = tickOuter - (isMajor ? 7 : 3.5)
                            var t = Path()
                            t.move(to: CGPoint(x: center.x + rIn * cos(rad), y: center.y + rIn * sin(rad)))
                            t.addLine(to: CGPoint(x: center.x + tickOuter * cos(rad), y: center.y + tickOuter * sin(rad)))
                            ctx.stroke(t, with: .color(Color.white.opacity(isMajor ? 0.35 : 0.16)), lineWidth: 1.2)
                        }
                    }

                    // Bedtime & Alarm circular badges positioned on the arc
                    Image(systemName: "bed.double.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color(hex: 0x8294EA)))
                        .offset(x: 4, y: -96)

                    Image(systemName: "alarm.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color(hex: 0x9AA9F4)))
                        .offset(x: 88, y: 39)

                    // Clock Face Cardinal Labels
                    VStack {
                        VStack(spacing: 3) {
                            Text("12AM").font(ImprovingFont.caption(12)).fontWeight(.bold).foregroundColor(BevelColors.textPrimary)
                            Image(systemName: "moon.fill").font(.system(size: 11)).foregroundColor(BevelColors.periwinkleStart)
                        }
                        Spacer()
                        VStack(spacing: 3) {
                            Image(systemName: "sun.max.fill").font(.system(size: 12)).foregroundColor(BevelColors.amberStart)
                            Text("12PM").font(ImprovingFont.caption(12)).fontWeight(.bold).foregroundColor(BevelColors.textPrimary)
                        }
                    }
                    .frame(height: 126)

                    HStack {
                        Text("6PM").font(ImprovingFont.caption(12)).fontWeight(.bold).foregroundColor(BevelColors.textPrimary)
                        Spacer()
                        Text("6AM").font(ImprovingFont.caption(12)).fontWeight(.bold).foregroundColor(BevelColors.textPrimary)
                    }
                    .frame(width: 136)
                }
                .frame(width: 222, height: 222)

                HStack(spacing: 6) {
                    Text("Despertar a las")
                        .font(ImprovingFont.body(14))
                        .foregroundColor(BevelColors.textSecondary)
                    Text(wakeTimeText)
                        .font(ImprovingFont.cardTitle(15))
                        .monospacedDigit()
                        .foregroundColor(BevelColors.textPrimary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(BevelColors.textMuted)
                }

                Divider().background(BevelColors.divider)

                Button(action: onOpenSleepNeed) {
                    HStack {
                        Text("Necesidad de sueño esta noche")
                            .font(ImprovingFont.body(13.5))
                            .foregroundColor(BevelColors.textPrimary)
                        Spacer()
                        Text(sleepNeedText)
                            .font(ImprovingFont.cardTitle(14))
                            .monospacedDigit()
                            .foregroundColor(BevelColors.textPrimary)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(BevelColors.textMuted)
                    }
                }
            }
            .padding(16)
        }
    }
}

// MARK: - Biological Age Sweeping Curved Arc Dial (Literal Match to Screenshot 69)

struct BioAgeCurvedDial: View {
    let bioAgeYears: Double
    let chronoAgeYears: Double
    let diffYears: Double
    let sampledDays: Int

    var body: some View {
        let lowerBound = chronoAgeYears - 6.0
        let upperBound = chronoAgeYears + 6.0
        let span = max(upperBound - lowerBound, 1.0)
        let isYounger = bioAgeYears <= chronoAgeYears
        let accent = isYounger ? BevelColors.bioTeal : BevelColors.amberStart

        VStack(spacing: 4) {
            ZStack {
                Canvas { ctx, size in
                    let center = CGPoint(x: size.width / 2, y: size.height * 0.24)
                    let radius = min(size.width * 0.48, size.height * 0.72)
                    let startAngle = 22.0
                    let sweep = 136.0
                    let tickCount = 60

                    for i in 0...tickCount {
                        let t = Double(i) / Double(tickCount)
                        let deg = startAngle + t * sweep
                        let rad = deg * .pi / 180.0
                        let rIn = radius * 0.90
                        let rOut = radius * 0.96
                        var line = Path()
                        line.move(to: CGPoint(x: center.x + cos(rad) * rIn, y: center.y + sin(rad) * rIn))
                        line.addLine(to: CGPoint(x: center.x + cos(rad) * rOut, y: center.y + sin(rad) * rOut))
                        ctx.stroke(line, with: .color(Color.white.opacity(0.14)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    }

                    let chronoFrac = min(max((chronoAgeYears - lowerBound) / span, 0.12), 0.88)
                    let bioFrac = min(max((bioAgeYears - lowerBound) / span, 0.12), 0.88)
                    let chronoDeg = (startAngle + sweep) - chronoFrac * sweep
                    let bioDeg = (startAngle + sweep) - bioFrac * sweep

                    // Glowing teal connecting bridge bar
                    var bridge = Path()
                    bridge.addArc(center: center, radius: radius * 0.93, startAngle: .degrees(min(chronoDeg, bioDeg)), endAngle: .degrees(max(chronoDeg, bioDeg)), clockwise: false)
                    ctx.stroke(bridge, with: .color(accent.opacity(0.52)), style: StrokeStyle(lineWidth: 12, lineCap: .round))

                    // Chronological dot
                    let cRad = chronoDeg * .pi / 180.0
                    let cPt = CGPoint(x: center.x + cos(cRad) * radius * 0.93, y: center.y + sin(cRad) * radius * 0.93)
                    ctx.fill(Path(ellipseIn: CGRect(x: cPt.x - 3.5, y: cPt.y - 3.5, width: 7, height: 7)), with: .color(.white.opacity(0.85)))

                    // Biological glowing ring handle
                    let bRad = bioDeg * .pi / 180.0
                    let bPt = CGPoint(x: center.x + cos(bRad) * radius * 0.93, y: center.y + sin(bRad) * radius * 0.93)
                    let bRect = CGRect(x: bPt.x - 7, y: bPt.y - 7, width: 14, height: 14)
                    ctx.fill(Path(ellipseIn: bRect), with: .color(accent))
                    ctx.stroke(Path(ellipseIn: bRect), with: .color(.white), lineWidth: 3)
                }
                .frame(height: 215)

                VStack(spacing: 4) {
                    Text(String(format: "%.1f", locale: Locale(identifier: "es_ES"), bioAgeYears))
                        .font(ImprovingFont.displayLarge(48))
                        .monospacedDigit()
                        .foregroundColor(BevelColors.textPrimary)
                    Text(String(format: "%.1f años menos", locale: Locale(identifier: "es_ES"), abs(diffYears)))
                        .font(ImprovingFont.cardTitle(15))
                        .foregroundColor(BevelColors.bioTeal)
                    HStack(spacing: 5) {
                        Text("▲").font(.system(size: 9)).foregroundColor(BevelColors.amberStart)
                        Text("−0,2 desde la semana pasada")
                            .font(ImprovingFont.caption(12))
                            .foregroundColor(BevelColors.textPrimary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(BevelColors.textMuted)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                    .padding(.top, 4)
                }
                .offset(y: -26)
            }

            Text(String(format: "%.1f", locale: Locale(identifier: "es_ES"), chronoAgeYears))
                .font(ImprovingFont.caption(12.5))
                .fontWeight(.semibold)
                .foregroundColor(BevelColors.textPrimary)
                .offset(y: -8)

            HStack(spacing: 4) {
                Text("Próxima actualización en")
                    .font(ImprovingFont.caption(13))
                    .foregroundColor(BevelColors.textSecondary)
                Text("3 días")
                    .font(ImprovingFont.caption(13))
                    .fontWeight(.bold)
                    .foregroundColor(BevelColors.textPrimary)
            }
        }
    }
}

// MARK: - Segmented Biomarker Dot Slider (Literal Match to Screenshots 72, 73, 74)

struct BioDotRangeSlider: View {
    let title: String
    let valueLabel: String
    let minLabel: String
    let maxLabel: String
    let deltaText: String
    let deltaUnit: String
    let positionFrac: Double // 0.0..1.0
    let fillStartFrac: Double
    let fillEndFrac: Double
    let accentColor: Color
    var showMinMax: Bool = true
    var statusBadgeText: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(ImprovingFont.cardTitle(14.5))
                    .foregroundColor(BevelColors.textPrimary)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(BevelColors.textMuted)
            }

            if let badge = statusBadgeText {
                HStack(spacing: 5) {
                    Text(badge)
                        .font(ImprovingFont.caption(13))
                        .fontWeight(.semibold)
                        .foregroundColor(accentColor)
                    Text("·")
                        .foregroundColor(BevelColors.textMuted)
                    Text(valueLabel)
                        .font(ImprovingFont.caption(13))
                        .fontWeight(.semibold)
                        .foregroundColor(BevelColors.textPrimary)
                }
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    if showMinMax {
                        HStack {
                            Text(minLabel).font(ImprovingFont.caption(11.5)).foregroundColor(BevelColors.textMuted)
                            Spacer()
                            Text(valueLabel).font(ImprovingFont.caption(12.5)).fontWeight(.semibold).foregroundColor(BevelColors.textPrimary)
                            Spacer()
                            Text(maxLabel).font(ImprovingFont.caption(11.5)).foregroundColor(BevelColors.textMuted)
                        }
                    }

                    // 34 vertical capsules with tall glowing cursor bar
                    GeometryReader { geo in
                        let count = 34
                        let gap: CGFloat = 2.6
                        let barW = max((geo.size.width - gap * CGFloat(count - 1)) / CGFloat(count), 2)
                        let cursorIdx = min(max(Int((positionFrac * Double(count - 1)).rounded()), 0), count - 1)
                        let startIdx = Int((fillStartFrac * Double(count - 1)).rounded())
                        let endIdx = Int((fillEndFrac * Double(count - 1)).rounded())

                        HStack(spacing: gap) {
                            ForEach(0..<count, id: \.self) { i in
                                let isCursor = i == cursorIdx
                                let inBand = i >= startIdx && i <= endIdx
                                Capsule()
                                    .fill(isCursor ? accentColor : (inBand ? accentColor.opacity(0.62) : Color.white.opacity(0.08)))
                                    .frame(width: isCursor ? barW + 1.5 : barW, height: isCursor ? 18 : 9)
                                    .shadow(color: isCursor ? accentColor.opacity(0.75) : .clear, radius: 4)
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .center)
                    }
                    .frame(height: 20)
                }

                if !deltaText.isEmpty {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(deltaText)
                            .font(ImprovingFont.cardTitle(16))
                            .monospacedDigit()
                            .foregroundColor(accentColor)
                        if !deltaUnit.isEmpty {
                            Text(deltaUnit)
                                .font(ImprovingFont.caption(11.5))
                                .foregroundColor(BevelColors.textSecondary)
                        }
                    }
                    .frame(minWidth: 44, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Stress & Energy 24h Timelines (Literal Match to Screenshots 11 & 14)

struct Timeline24hChart: View {
    let points: [Double]
    let isEnergy: Bool
    var showSleepTopBar: Bool = true
    var fillArea: Bool = false

    @State private var selectedIdx: Int? = nil
    @State private var animatedVal: Double = 0

    var body: some View {
        let safePts = points.count >= 2 ? points : [20, 28, 34, 42, 31, 25]
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    let stepX = w / CGFloat(max(safePts.count - 1, 1))
                    let yFor: (Double) -> CGFloat = { v in h * (1.0 - CGFloat(min(max(v / 100.0, 0), 1))) }

                    ZStack(alignment: .topLeading) {
                        Canvas { ctx, size in
                            for lvl in [0.0, 25.0, 50.0, 75.0, 100.0] {
                                let y = yFor(lvl)
                                var gp = Path()
                                gp.move(to: CGPoint(x: 0, y: y))
                                gp.addLine(to: CGPoint(x: size.width, y: y))
                                ctx.stroke(gp, with: .color(Color.white.opacity(0.06)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                            }

                            if showSleepTopBar {
                                let sRect = CGRect(x: size.width * 0.12, y: 0, width: size.width * 0.30, height: size.height)
                                ctx.fill(Path(sRect), with: .color(Color(hex: 0x3D4C7A, alpha: 0.34)))

                                var topBar = Path()
                                topBar.move(to: CGPoint(x: size.width * 0.12, y: 1.5))
                                topBar.addLine(to: CGPoint(x: size.width * 0.42, y: 1.5))
                                ctx.stroke(topBar, with: .color(Color(hex: 0x7A90EE)), style: StrokeStyle(lineWidth: 2.8, lineCap: .round))
                            }

                            if fillArea {
                                var area = Path()
                                for (i, v) in safePts.enumerated() {
                                    let p = CGPoint(x: CGFloat(i) * stepX, y: yFor(v))
                                    if i == 0 {
                                        area.move(to: CGPoint(x: 0, y: size.height))
                                        area.addLine(to: p)
                                    } else {
                                        area.addLine(to: p)
                                    }
                                }
                                area.addLine(to: CGPoint(x: size.width, y: size.height))
                                area.closeSubpath()
                                ctx.fill(area, with: .linearGradient(Gradient(colors: [BevelColors.greenPrimary.opacity(0.32), BevelColors.amberStart.opacity(0.08)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                            }

                            for i in 0..<(safePts.count - 1) {
                                let avg = (safePts[i] + safePts[i + 1]) / 2.0
                                let segColor: Color
                                if isEnergy {
                                    segColor = avg >= 55 ? BevelColors.greenPrimary : (avg >= 32 ? BevelColors.amberStart : BevelColors.orangeEnd)
                                } else {
                                    segColor = avg < 25 ? BevelColors.tealLow : (avg < 45 ? BevelColors.greenPrimary : (avg < 68 ? BevelColors.amberStart : BevelColors.coralHigh))
                                }
                                var seg = Path()
                                seg.move(to: CGPoint(x: CGFloat(i) * stepX, y: yFor(safePts[i])))
                                seg.addLine(to: CGPoint(x: CGFloat(i + 1) * stepX, y: yFor(safePts[i + 1])))
                                ctx.stroke(seg, with: .color(segColor), style: StrokeStyle(lineWidth: 2.1, lineCap: .round))
                            }

                            if let sel = selectedIdx {
                                let sx = CGFloat(sel) * stepX
                                let sy = yFor(safePts[sel])
                                var vp = Path()
                                vp.move(to: CGPoint(x: sx, y: 0))
                                vp.addLine(to: CGPoint(x: sx, y: size.height))
                                ctx.stroke(vp, with: .color(BevelColors.textPrimary.opacity(0.3)), style: StrokeStyle(lineWidth: 1.3, dash: [5, 4]))
                                ctx.fill(Path(ellipseIn: CGRect(x: sx - 5.5, y: sy - 5.5, width: 11, height: 11)), with: .color(.white))
                            }
                        }

                        if showSleepTopBar {
                            Image(systemName: "moon.stars.fill")
                                .font(.system(size: 13))
                                .foregroundColor(Color(hex: 0x8EA0F8))
                                .position(x: w * 0.27, y: -12)
                        }

                        if let sel = selectedIdx {
                            let hour = Int((Double(sel) / Double(max(safePts.count - 1, 1)) * 23.0).rounded())
                            let px = min(max(CGFloat(sel) * stepX, 46), w - 46)
                            let py = max(yFor(safePts[sel]) - 22, 16)
                            Text(String(format: "%02d:00 · %d%@", hour, Int(animatedVal.rounded()), isEnergy ? "%" : ""))
                                .font(ImprovingFont.caption(11))
                                .fontWeight(.bold)
                                .monospacedDigit()
                                .foregroundColor(.white)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(BevelColors.floatingDarkButton))
                                .position(x: px, y: py)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { val in
                                let raw = Int((val.location.x / max(stepX, 1)).rounded())
                                let idx = min(max(raw, 0), safePts.count - 1)
                                if selectedIdx != idx {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    selectedIdx = idx
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        animatedVal = safePts[idx]
                                    }
                                }
                            }
                    )
                }
                .frame(height: 152)

                VStack(alignment: .trailing) {
                    Text("100"); Spacer(); Text("75"); Spacer(); Text("50"); Spacer(); Text("25"); Spacer(); Text("0")
                }
                .font(ImprovingFont.caption(10.5))
                .foregroundColor(BevelColors.textMuted)
                .frame(height: 148)
            }
            .padding(.top, showSleepTopBar ? 18 : 2)

            HStack {
                Text("0:00"); Spacer(); Text("6:00"); Spacer(); Text("12:00"); Spacer(); Text("18:00")
            }
            .font(ImprovingFont.caption(10.5))
            .foregroundColor(BevelColors.textMuted)
            .padding(.trailing, 26)
        }
    }
}

struct SleepStagesHypnogramBar: View {
    let deepMin: Int
    let remMin: Int
    let lightMin: Int
    let awakeMin: Int

    var body: some View {
        let total = max(deepMin + remMin + lightMin + awakeMin, 1)
        GeometryReader { geo in
            HStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(BevelColors.indigoEnd)
                    .frame(width: geo.size.width * CGFloat(deepMin) / CGFloat(total))
                RoundedRectangle(cornerRadius: 5)
                    .fill(BevelColors.periwinkleStart)
                    .frame(width: geo.size.width * CGFloat(remMin) / CGFloat(total))
                RoundedRectangle(cornerRadius: 5)
                    .fill(BevelColors.skyBlue)
                    .frame(width: geo.size.width * CGFloat(lightMin) / CGFloat(total))
                if awakeMin > 0 {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(BevelColors.coralHigh)
                        .frame(width: geo.size.width * CGFloat(awakeMin) / CGFloat(total))
                }
            }
        }
        .frame(height: 16)
    }
}

struct ConsistencyHeatmapGrid: View {
    let levels: [Int]

    var body: some View {
        VStack(spacing: 5) {
            ForEach(0..<6, id: \.self) { row in
                HStack(spacing: 5) {
                    ForEach(0..<7, id: \.self) { col in
                        let idx = row * 7 + col
                        let lvl = idx < levels.count ? levels[idx] : 0
                        let bg: Color = switch lvl {
                        case 0: BevelColors.trackGroove
                        case 1: Color(hex: 0x264D3B)
                        case 2: Color(hex: 0x2F855A)
                        default: BevelColors.greenPrimary
                        }
                        RoundedRectangle(cornerRadius: 6)
                            .fill(bg)
                            .frame(height: 22)
                    }
                }
            }
        }
    }
}

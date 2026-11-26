import SwiftUI

// MARK: - Interactive Sparse Baseline Chart (Zero Fabricated Points, Reset-Safe on Window Switch)

struct HealthMetricBaselineChart: View {
    let optionalPoints: [Double?]
    let dates: [String]
    let bandLow: Double
    let bandHigh: Double
    let averageText: String
    let accentColor: Color
    let valueFormatter: (Double) -> String
    var onPointSelected: (Int?, Double?, String?) -> Void = { _, _, _ in }

    init(
        optionalPoints: [Double?],
        dates: [String],
        bandLow: Double,
        bandHigh: Double,
        averageText: String,
        accentColor: Color,
        valueFormatter: @escaping (Double) -> String,
        onPointSelected: @escaping (Int?, Double?, String?) -> Void = { _, _, _ in }
    ) {
        self.optionalPoints = optionalPoints
        self.dates = dates
        self.bandLow = bandLow
        self.bandHigh = bandHigh
        self.averageText = averageText
        self.accentColor = accentColor
        self.valueFormatter = valueFormatter
        self.onPointSelected = onPointSelected
    }

    init(
        points: [Double],
        dates: [String],
        bandLow: Double,
        bandHigh: Double,
        averageText: String,
        accentColor: Color,
        valueFormatter: @escaping (Double) -> String,
        onPointSelected: @escaping (Int?, Double?, String?) -> Void = { _, _, _ in }
    ) {
        self.optionalPoints = points.map { Optional($0) }
        self.dates = dates
        self.bandLow = bandLow
        self.bandHigh = bandHigh
        self.averageText = averageText
        self.accentColor = accentColor
        self.valueFormatter = valueFormatter
        self.onPointSelected = onPointSelected
    }

    @State private var selectedIdx: Int? = nil
    @State private var animatedDisplayVal: Double = 0

    var body: some View {
        let validPairs: [(idx: Int, val: Double)] = optionalPoints.enumerated().compactMap { idx, opt in
            guard let v = opt else { return nil }
            return (idx, v)
        }
        let realVals = validPairs.map(\.val)

        if realVals.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 26))
                    .foregroundColor(BevelColors.textMuted.opacity(0.6))
                Text("No hay mediciones en este período")
                    .font(ImprovingFont.caption(13))
                    .foregroundColor(BevelColors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 186)
            .background(RoundedRectangle(cornerRadius: 16).fill(BevelColors.chartTrackSubtle.opacity(0.45)))
        } else {
            let minVal = min(realVals.min() ?? bandLow, bandLow)
            let maxVal = max(realVals.max() ?? bandHigh, bandHigh)
            let span = max(maxVal - minVal, 0.5)
            let pad = max(span * 0.24, 0.3)
            let chartMin = minVal - pad
            let chartMax = maxVal + pad
            let chartSpan = max(chartMax - chartMin, 0.5)
            let avgVal = realVals.reduce(0, +) / Double(realVals.count)
            let totalSlots = max(optionalPoints.count, 1)
            let showIndividualNodes = validPairs.count <= 45

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    GeometryReader { geo in
                        let w = geo.size.width
                        let h = geo.size.height
                        let xFor: (Int) -> CGFloat = { idx in
                            totalSlots <= 1 ? w / 2 : CGFloat(idx) / CGFloat(totalSlots - 1) * w
                        }
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
                                    ctx.stroke(gPath, with: .color(BevelColors.chartGridLine), lineWidth: 1)
                                }

                                // Normal target range band
                                let topBandY = yFor(bandHigh)
                                let botBandY = yFor(bandLow)
                                let bandRect = CGRect(x: 0, y: min(topBandY, botBandY), width: size.width, height: max(abs(botBandY - topBandY), 8))
                                ctx.fill(Path(roundedRect: bandRect, cornerRadius: 4), with: .color(accentColor.opacity(0.14)))

                                // Dotted average line
                                let avgY = yFor(avgVal)
                                var avgPath = Path()
                                avgPath.move(to: CGPoint(x: 0, y: avgY))
                                avgPath.addLine(to: CGPoint(x: size.width, y: avgY))
                                ctx.stroke(avgPath, with: .color(accentColor.opacity(selectedIdx == nil ? 0.65 : 0.22)), style: StrokeStyle(lineWidth: 1.4, dash: [3, 4]))

                                if let sel = selectedIdx, sel < optionalPoints.count, optionalPoints[sel] != nil {
                                    let sx = xFor(sel)
                                    var vPath = Path()
                                    vPath.move(to: CGPoint(x: sx, y: 0))
                                    vPath.addLine(to: CGPoint(x: sx, y: size.height))
                                    ctx.stroke(vPath, with: .color(BevelColors.textPrimary.opacity(0.28)), style: StrokeStyle(lineWidth: 1.4, dash: [5, 4]))
                                }

                                // Connect real points, breaking gap if > maxGap days missing
                                let maxGap = totalSlots > 120 ? 18 : (totalSlots > 40 ? 7 : 3)
                                if validPairs.count >= 2 {
                                    var seg = Path()
                                    var prevIdx: Int? = nil
                                    for pair in validPairs {
                                        let pt = CGPoint(x: xFor(pair.idx), y: yFor(pair.val))
                                        if let pIdx = prevIdx, (pair.idx - pIdx) <= maxGap {
                                            seg.addLine(to: pt)
                                        } else {
                                            seg.move(to: pt)
                                        }
                                        prevIdx = pair.idx
                                    }
                                    ctx.stroke(seg, with: .color(accentColor), style: StrokeStyle(lineWidth: 2.1, lineCap: .round, lineJoin: .round))
                                }

                                let lastValidIdx = validPairs.last?.idx
                                for pair in validPairs {
                                    let pt = CGPoint(x: xFor(pair.idx), y: yFor(pair.val))
                                    if pair.idx == selectedIdx {
                                        ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 12, y: pt.y - 12, width: 24, height: 24)), with: .color(accentColor.opacity(0.28)))
                                        ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 5.5, y: pt.y - 5.5, width: 11, height: 11)), with: .color(BevelColors.sheetHeaderBg))
                                        ctx.stroke(Path(ellipseIn: CGRect(x: pt.x - 5.5, y: pt.y - 5.5, width: 11, height: 11)), with: .color(accentColor), lineWidth: 2.5)
                                    } else if selectedIdx == nil && pair.idx == lastValidIdx {
                                        ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 11, y: pt.y - 11, width: 22, height: 22)), with: .color(accentColor.opacity(0.26)))
                                        ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10)), with: .color(BevelColors.sheetHeaderBg))
                                        ctx.stroke(Path(ellipseIn: CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10)), with: .color(accentColor), lineWidth: 2.4)
                                    } else if showIndividualNodes {
                                        let rect = CGRect(x: pt.x - 3.2, y: pt.y - 3.2, width: 6.4, height: 6.4)
                                        ctx.fill(Path(ellipseIn: rect), with: .color(BevelColors.sheetHeaderBg))
                                        ctx.stroke(Path(ellipseIn: rect), with: .color(accentColor), lineWidth: 1.6)
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
                            } else if let sel = selectedIdx, sel < optionalPoints.count, let v = optionalPoints[sel] {
                                let dateStr = (sel < dates.count) ? "\(dates[sel]) · " : ""
                                let pillX = min(max(xFor(sel), 68), w - 68)
                                let ptY = yFor(v)
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
                                    let touchX = min(max(val.location.x, 0), w)
                                    // Snap cleanly to the nearest REAL data point
                                    if let nearest = validPairs.min(by: { abs(xFor($0.idx) - touchX) < abs(xFor($1.idx) - touchX) }) {
                                        if selectedIdx != nearest.idx {
                                            UISelectionFeedbackGenerator().selectionChanged()
                                            selectedIdx = nearest.idx
                                            withAnimation(.easeOut(duration: 0.18)) {
                                                animatedDisplayVal = nearest.val
                                            }
                                            let d = nearest.idx < dates.count ? dates[nearest.idx] : nil
                                            onPointSelected(nearest.idx, nearest.val, d)
                                        }
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
                selectedIdx = nil
                animatedDisplayVal = realVals.last ?? 0
            }
            .onChange(of: dates) { _, _ in
                selectedIdx = nil
                animatedDisplayVal = realVals.last ?? 0
                onPointSelected(nil, nil, nil)
            }
        }
    }
}

// MARK: - Trend Sparkline with Sparse Optional Support

struct TrendSparklineWithBand: View {
    let optionalPoints: [Double?]
    var bandLow: Double = 40
    var bandHigh: Double = 80
    let lineColor: Color
    var fillUnder: Bool = true
    var showBand: Bool = false
    var showGlowDot: Bool = false

    init(
        optionalPoints: [Double?],
        bandLow: Double = 40,
        bandHigh: Double = 80,
        lineColor: Color,
        fillUnder: Bool = true,
        showBand: Bool = false,
        showGlowDot: Bool = false
    ) {
        self.optionalPoints = optionalPoints
        self.bandLow = bandLow
        self.bandHigh = bandHigh
        self.lineColor = lineColor
        self.fillUnder = fillUnder
        self.showBand = showBand
        self.showGlowDot = showGlowDot
    }

    init(
        points: [Double],
        bandLow: Double = 40,
        bandHigh: Double = 80,
        lineColor: Color,
        fillUnder: Bool = true,
        showBand: Bool = false,
        showGlowDot: Bool = false
    ) {
        self.optionalPoints = points.map { Optional($0) }
        self.bandLow = bandLow
        self.bandHigh = bandHigh
        self.lineColor = lineColor
        self.fillUnder = fillUnder
        self.showBand = showBand
        self.showGlowDot = showGlowDot
    }

    var body: some View {
        let validPairs: [(idx: Int, val: Double)] = optionalPoints.enumerated().compactMap { idx, opt in
            guard let v = opt else { return nil }
            return (idx, v)
        }
        let realVals = validPairs.map(\.val)

        if realVals.count >= 2 {
            let minV = min(realVals.min() ?? 0, bandLow)
            let maxV = max(realVals.max() ?? 1, bandHigh)
            let span = max(maxV - minV, 1)
            let count = max(optionalPoints.count, 2)

            Canvas { ctx, size in
                let rightPad: CGFloat = showGlowDot ? 8 : 2
                let drawW = max(size.width - rightPad, 10)
                let xFor: (Int) -> CGFloat = { idx in CGFloat(idx) / CGFloat(count - 1) * drawW }
                let yFor: (Double) -> CGFloat = { v in
                    size.height - 6 - CGFloat((v - minV) / span) * (size.height - 12)
                }

                if showBand {
                    let topY = yFor(bandHigh)
                    let botY = yFor(bandLow)
                    let bandRect = CGRect(x: 0, y: min(topY, botY), width: drawW, height: max(abs(botY - topY), 10))
                    ctx.fill(Path(roundedRect: bandRect, cornerRadius: 3), with: .color(lineColor.opacity(0.18)))
                }

                let maxGap = count > 90 ? 12 : (count > 25 ? 5 : 3)
                var line = Path()
                var fill = Path()
                var prevPair: (idx: Int, val: Double)? = nil
                for pair in validPairs {
                    let pt = CGPoint(x: xFor(pair.idx), y: yFor(pair.val))
                    if let prev = prevPair, (pair.idx - prev.idx) <= maxGap {
                        line.addLine(to: pt)
                        fill.addLine(to: pt)
                    } else {
                        if let prev = prevPair {
                            fill.addLine(to: CGPoint(x: xFor(prev.idx), y: size.height))
                            fill.closeSubpath()
                        }
                        line.move(to: pt)
                        fill.move(to: CGPoint(x: pt.x, y: size.height))
                        fill.addLine(to: pt)
                    }
                    prevPair = pair
                }
                if let last = prevPair {
                    fill.addLine(to: CGPoint(x: xFor(last.idx), y: size.height))
                    fill.closeSubpath()
                }

                if fillUnder && !showBand {
                    ctx.fill(fill, with: .linearGradient(Gradient(colors: [lineColor.opacity(0.22), .clear]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                }
                ctx.stroke(line, with: .color(lineColor), style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))

                if showGlowDot, let last = validPairs.last {
                    let pt = CGPoint(x: xFor(last.idx), y: yFor(last.val))
                    ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 8, y: pt.y - 8, width: 16, height: 16)), with: .color(lineColor.opacity(0.28)))
                    ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 4, y: pt.y - 4, width: 8, height: 8)), with: .color(BevelColors.card))
                    ctx.stroke(Path(ellipseIn: CGRect(x: pt.x - 4, y: pt.y - 4, width: 8, height: 8)), with: .color(lineColor), lineWidth: 2.0)
                }
            }
        } else {
            Color.clear
        }
    }
}

// MARK: - Stepped Cumulative Comparison Chart

struct SteppedCumulativeComparisonChart: View {
    let currentPoints: [Double]
    let previousPoints: [Double]
    let accentColor: Color
    var rightLabels: [String] = []
    var bottomDates: [String] = []
    var height: CGFloat = 158

    var body: some View {
        let safeCur = currentPoints.count >= 2 ? currentPoints : [0, 0]
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
                        ctx.stroke(gp, with: .color(BevelColors.chartGridLine), lineWidth: 1)
                    }

                    let prevStep = drawW / CGFloat(max(safePrev.count - 1, 1))
                    var prevPath = Path()
                    for (i, v) in safePrev.enumerated() {
                        let p = CGPoint(x: CGFloat(i) * prevStep, y: yFor(v))
                        if i == 0 { prevPath.move(to: p) } else { prevPath.addLine(to: p) }
                    }
                    ctx.stroke(prevPath, with: .color(BevelColors.chartGhostCurve), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))

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

                    if let last = safeCur.last, last > 0 {
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

// MARK: - 5-Segment Horizontal Range Bar

struct FiveSegmentRangeBar: View {
    let labels: [String]
    let activeSegmentIndex: Int
    let activeColor: Color
    let pointerFraction: Double
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

// MARK: - 24-Hour Circular Sleep Schedule Dial

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

                ZStack {
                    Canvas { ctx, sz in
                        let center = CGPoint(x: sz.width / 2, y: sz.height / 2)
                        let outerR = min(sz.width, sz.height) / 2 - 14
                        let ringW: CGFloat = 24

                        ctx.stroke(
                            Path(ellipseIn: CGRect(x: center.x - outerR, y: center.y - outerR, width: outerR * 2, height: outerR * 2)),
                            with: .color(Color(hex: 0x3A436B, alpha: 0.65)),
                            lineWidth: ringW
                        )

                        var sleepArc = Path()
                        sleepArc.addArc(center: center, radius: outerR, startAngle: .degrees(-86), endAngle: .degrees(24), clockwise: false)
                        ctx.stroke(sleepArc, with: .color(Color(hex: 0x8294EA)), style: StrokeStyle(lineWidth: ringW, lineCap: .round))

                        let tickOuter = outerR - ringW / 2 - 6
                        for i in 0..<48 {
                            let deg = Double(i) * 7.5 - 90
                            let rad = deg * .pi / 180.0
                            let isMajor = i % 4 == 0
                            let rIn = tickOuter - (isMajor ? 7 : 3.5)
                            var t = Path()
                            t.move(to: CGPoint(x: center.x + rIn * cos(rad), y: center.y + rIn * sin(rad)))
                            t.addLine(to: CGPoint(x: center.x + tickOuter * cos(rad), y: center.y + tickOuter * sin(rad)))
                            ctx.stroke(t, with: .color(isMajor ? BevelColors.chartAxisStroke : BevelColors.chartTickInactive), lineWidth: 1.2)
                        }
                    }

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

                    VStack {
                        VStack(spacing: 3) {
                            Text("00:00").font(ImprovingFont.caption(12)).fontWeight(.bold).foregroundColor(BevelColors.textPrimary)
                            Image(systemName: "moon.fill").font(.system(size: 11)).foregroundColor(BevelColors.periwinkleStart)
                        }
                        Spacer()
                        VStack(spacing: 3) {
                            Image(systemName: "sun.max.fill").font(.system(size: 12)).foregroundColor(BevelColors.amberStart)
                            Text("12:00").font(ImprovingFont.caption(12)).fontWeight(.bold).foregroundColor(BevelColors.textPrimary)
                        }
                    }
                    .frame(height: 126)

                    HStack {
                        Text("18:00").font(ImprovingFont.caption(12)).fontWeight(.bold).foregroundColor(BevelColors.textPrimary)
                        Spacer()
                        Text("06:00").font(ImprovingFont.caption(12)).fontWeight(.bold).foregroundColor(BevelColors.textPrimary)
                    }
                    .frame(width: 136)
                }
                .frame(width: 222, height: 222)

                Button(action: onOpenSleepNeed) {
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
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

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

// MARK: - Biological Age Sweeping Curved Arc Dial

struct BioAgeCurvedDial: View {
    let bioAgeYears: Double
    let chronoAgeYears: Double
    let diffYears: Double
    let sampledDays: Int
    var hasData: Bool = true

    var body: some View {
        let lowerBound = chronoAgeYears - 6.0
        let upperBound = chronoAgeYears + 6.0
        let span = max(upperBound - lowerBound, 1.0)
        let isYounger = bioAgeYears <= chronoAgeYears
        let accent = !hasData ? BevelColors.textMuted : (isYounger ? BevelColors.bioTeal : BevelColors.amberStart)

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
                        ctx.stroke(line, with: .color(BevelColors.chartAxisStroke), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    }

                    guard hasData else { return }
                    let chronoFrac = min(max((chronoAgeYears - lowerBound) / span, 0.12), 0.88)
                    let bioFrac = min(max((bioAgeYears - lowerBound) / span, 0.12), 0.88)
                    let chronoDeg = (startAngle + sweep) - chronoFrac * sweep
                    let bioDeg = (startAngle + sweep) - bioFrac * sweep

                    var bridge = Path()
                    bridge.addArc(center: center, radius: radius * 0.93, startAngle: .degrees(min(chronoDeg, bioDeg)), endAngle: .degrees(max(chronoDeg, bioDeg)), clockwise: false)
                    ctx.stroke(bridge, with: .color(accent.opacity(0.52)), style: StrokeStyle(lineWidth: 12, lineCap: .round))

                    let cRad = chronoDeg * .pi / 180.0
                    let cPt = CGPoint(x: center.x + cos(cRad) * radius * 0.93, y: center.y + sin(cRad) * radius * 0.93)
                    ctx.fill(Path(ellipseIn: CGRect(x: cPt.x - 3.5, y: cPt.y - 3.5, width: 7, height: 7)), with: .color(.white.opacity(0.85)))

                    let bRad = bioDeg * .pi / 180.0
                    let bPt = CGPoint(x: center.x + cos(bRad) * radius * 0.93, y: center.y + sin(bRad) * radius * 0.93)
                    let bRect = CGRect(x: bPt.x - 7, y: bPt.y - 7, width: 14, height: 14)
                    ctx.fill(Path(ellipseIn: bRect), with: .color(accent))
                    ctx.stroke(Path(ellipseIn: bRect), with: .color(.white), lineWidth: 3)
                }
                .frame(height: 215)

                VStack(spacing: 4) {
                    Text(hasData ? String(format: "%.1f", locale: Locale(identifier: "es_ES"), bioAgeYears) : "--")
                        .font(ImprovingFont.displayLarge(48))
                        .monospacedDigit()
                        .foregroundColor(hasData ? BevelColors.textPrimary : BevelColors.textMuted)
                    if hasData {
                        Text(String(format: "%.1f años %@", locale: Locale(identifier: "es_ES"), abs(diffYears), diffYears <= 0 ? "menos" : "más"))
                            .font(ImprovingFont.cardTitle(15))
                            .foregroundColor(accent)
                    } else {
                        Text("Faltan datos biométricos")
                            .font(ImprovingFont.caption(13))
                            .foregroundColor(BevelColors.textSecondary)
                    }
                }
                .offset(y: -26)
            }

            Text(String(format: "%.1f", locale: Locale(identifier: "es_ES"), chronoAgeYears))
                .font(ImprovingFont.caption(12.5))
                .fontWeight(.semibold)
                .foregroundColor(BevelColors.textPrimary)
                .offset(y: -8)

            Text("\(sampledDays) días con lecturas analizados")
                .font(ImprovingFont.caption(12.5))
                .foregroundColor(BevelColors.textSecondary)
        }
    }
}

// MARK: - Segmented Biomarker Dot Slider

struct BioDotRangeSlider: View {
    let title: String
    let valueLabel: String
    let minLabel: String
    let maxLabel: String
    let deltaText: String
    let deltaUnit: String
    let positionFrac: Double
    let fillStartFrac: Double
    let fillEndFrac: Double
    let accentColor: Color
    var showMinMax: Bool = true
    var statusBadgeText: String? = nil
    var deltaColor: Color? = nil

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
                                    .fill(isCursor ? accentColor : (inBand ? accentColor.opacity(0.62) : BevelColors.chartTrackSubtle))
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
                            .foregroundColor(deltaColor ?? accentColor)
                        if !deltaUnit.isEmpty {
                            Text(deltaUnit)
                                .font(ImprovingFont.caption(11.5))
                                .foregroundColor(BevelColors.textSecondary)
                        }
                    }
                    .frame(minWidth: 48, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

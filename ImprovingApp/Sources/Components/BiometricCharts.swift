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
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.03)))
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
                                    ctx.stroke(gPath, with: .color(Color.white.opacity(0.06)), lineWidth: 1)
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

                var line = Path()
                var fill = Path()
                for (n, pair) in validPairs.enumerated() {
                    let pt = CGPoint(x: xFor(pair.idx), y: yFor(pair.val))
                    if n == 0 {
                        line.move(to: pt)
                        fill.move(to: CGPoint(x: pt.x, y: size.height))
                        fill.addLine(to: pt)
                    } else {
                        line.addLine(to: pt)
                        fill.addLine(to: pt)
                    }
                }
                if let last = validPairs.last {
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
                        ctx.stroke(gp, with: .color(Color.white.opacity(0.06)), lineWidth: 1)
                    }

                    let prevStep = drawW / CGFloat(max(safePrev.count - 1, 1))
                    var prevPath = Path()
                    for (i, v) in safePrev.enumerated() {
                        let p = CGPoint(x: CGFloat(i) * prevStep, y: yFor(v))
                        if i == 0 { prevPath.move(to: p) } else { prevPath.addLine(to: p) }
                    }
                    ctx.stroke(prevPath, with: .color(Color.white.opacity(0.22)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))

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
                            ctx.stroke(t, with: .color(Color.white.opacity(isMajor ? 0.35 : 0.16)), lineWidth: 1.2)
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
                        ctx.stroke(line, with: .color(Color.white.opacity(0.14)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
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

// MARK: - High-Resolution 5-Minute Stress & Energy 24h Timelines (Zero Fabricated Points!)

struct Timeline24hChart: View {
    let samples: [TimedBiometricPoint]
    let isEnergy: Bool
    var sleepWindowMinutes: ClosedRange<Int>? = nil
    var fillArea: Bool = false

    @State private var selectedIdx: Int? = nil

    var body: some View {
        if samples.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: isEnergy ? "bolt.slash.fill" : "waveform.path.ecg")
                    .font(.system(size: 24))
                    .foregroundColor(BevelColors.textMuted.opacity(0.6))
                Text(isEnergy ? "No hay datos de energía registrados este día" : "No hay mediciones de estrés registradas este día")
                    .font(ImprovingFont.caption(12.5))
                    .foregroundColor(BevelColors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 156)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.03)))
        } else {
            let showSleepBar = sleepWindowMinutes != nil
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    GeometryReader { geo in
                        let w = geo.size.width
                        let h = geo.size.height
                        let xForMinute: (Int) -> CGFloat = { m in
                            CGFloat(min(max(m, 0), 1439)) / 1440.0 * w
                        }
                        let yFor: (Double) -> CGFloat = { v in
                            h * (1.0 - CGFloat(min(max(v / 100.0, 0), 1)))
                        }

                        ZStack(alignment: .topLeading) {
                            Canvas { ctx, size in
                                for lvl in [0.0, 25.0, 50.0, 75.0, 100.0] {
                                    let y = yFor(lvl)
                                    var gp = Path()
                                    gp.move(to: CGPoint(x: 0, y: y))
                                    gp.addLine(to: CGPoint(x: size.width, y: y))
                                    ctx.stroke(gp, with: .color(Color.white.opacity(0.06)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                                }

                                if let sw = sleepWindowMinutes {
                                    let sx1 = xForMinute(sw.lowerBound)
                                    let sx2 = xForMinute(sw.upperBound)
                                    if sx2 > sx1 {
                                        ctx.fill(Path(CGRect(x: sx1, y: 0, width: sx2 - sx1, height: size.height)), with: .color(Color(hex: 0x3D4C7A, alpha: 0.34)))
                                        var topBar = Path()
                                        topBar.move(to: CGPoint(x: sx1, y: 1.5))
                                        topBar.addLine(to: CGPoint(x: sx2, y: 1.5))
                                        ctx.stroke(topBar, with: .color(Color(hex: 0x7A90EE)), style: StrokeStyle(lineWidth: 2.8, lineCap: .round))
                                    }
                                }

                                // Draw contiguous segments broken cleanly if gap > 45 minutes
                                if fillArea && samples.count >= 2 {
                                    var runStart = 0
                                    while runStart < samples.count {
                                        var runEnd = runStart
                                        while runEnd + 1 < samples.count && (samples[runEnd + 1].minuteOfDay - samples[runEnd].minuteOfDay) <= 45 {
                                            runEnd += 1
                                        }
                                        if runEnd > runStart {
                                            var area = Path()
                                            let firstPt = CGPoint(x: xForMinute(samples[runStart].minuteOfDay), y: yFor(samples[runStart].value))
                                            area.move(to: CGPoint(x: firstPt.x, y: size.height))
                                            area.addLine(to: firstPt)
                                            for k in (runStart + 1)...runEnd {
                                                area.addLine(to: CGPoint(x: xForMinute(samples[k].minuteOfDay), y: yFor(samples[k].value)))
                                            }
                                            let lastX = xForMinute(samples[runEnd].minuteOfDay)
                                            area.addLine(to: CGPoint(x: lastX, y: size.height))
                                            area.closeSubpath()
                                            ctx.fill(area, with: .linearGradient(Gradient(colors: [BevelColors.greenPrimary.opacity(0.30), BevelColors.amberStart.opacity(0.06)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                                        }
                                        runStart = runEnd + 1
                                    }
                                }

                                if samples.count >= 2 {
                                    for i in 0..<(samples.count - 1) {
                                        let a = samples[i]
                                        let b = samples[i + 1]
                                        // Leave genuine gaps when watch wasn't measuring
                                        if (b.minuteOfDay - a.minuteOfDay) > 45 { continue }
                                        let avg = (a.value + b.value) / 2.0
                                        let segColor: Color
                                        if isEnergy {
                                            segColor = avg >= 55 ? BevelColors.greenPrimary : (avg >= 32 ? BevelColors.amberStart : BevelColors.orangeEnd)
                                        } else {
                                            segColor = avg < 25 ? BevelColors.tealLow : (avg < 45 ? BevelColors.greenPrimary : (avg < 68 ? BevelColors.amberStart : BevelColors.coralHigh))
                                        }
                                        var seg = Path()
                                        seg.move(to: CGPoint(x: xForMinute(a.minuteOfDay), y: yFor(a.value)))
                                        seg.addLine(to: CGPoint(x: xForMinute(b.minuteOfDay), y: yFor(b.value)))
                                        ctx.stroke(seg, with: .color(segColor), style: StrokeStyle(lineWidth: 2.0, lineCap: .round))
                                    }
                                } else if let only = samples.first {
                                    let pt = CGPoint(x: xForMinute(only.minuteOfDay), y: yFor(only.value))
                                    ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 4, y: pt.y - 4, width: 8, height: 8)), with: .color(isEnergy ? BevelColors.greenPrimary : BevelColors.tealLow))
                                }

                                if let sel = selectedIdx, sel < samples.count {
                                    let pt = samples[sel]
                                    let sx = xForMinute(pt.minuteOfDay)
                                    let sy = yFor(pt.value)
                                    var vp = Path()
                                    vp.move(to: CGPoint(x: sx, y: 0))
                                    vp.addLine(to: CGPoint(x: sx, y: size.height))
                                    ctx.stroke(vp, with: .color(BevelColors.textPrimary.opacity(0.32)), style: StrokeStyle(lineWidth: 1.3, dash: [5, 4]))
                                    ctx.fill(Path(ellipseIn: CGRect(x: sx - 5.5, y: sy - 5.5, width: 11, height: 11)), with: .color(.white))
                                }
                            }

                            if let sw = sleepWindowMinutes {
                                let midX = (xForMinute(sw.lowerBound) + xForMinute(sw.upperBound)) / 2
                                Image(systemName: "moon.stars.fill")
                                    .font(.system(size: 13))
                                    .foregroundColor(Color(hex: 0x8EA0F8))
                                    .position(x: min(max(midX, 16), w - 16), y: -12)
                            }

                            if let sel = selectedIdx, sel < samples.count {
                                let pt = samples[sel]
                                let hh = (pt.minuteOfDay / 60) % 24
                                let mm = pt.minuteOfDay % 60
                                let px = min(max(xForMinute(pt.minuteOfDay), 52), w - 52)
                                let py = max(yFor(pt.value) - 22, 16)
                                Text(String(format: "%02d:%02d · %d%@", hh, mm, Int(pt.value.rounded()), isEnergy ? "%" : ""))
                                    .font(ImprovingFont.caption(11.5))
                                    .fontWeight(.bold)
                                    .monospacedDigit()
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4.5)
                                    .background(Capsule().fill(BevelColors.floatingDarkButton))
                                    .position(x: px, y: py)
                            }
                        }
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { val in
                                    let frac = min(max(val.location.x / max(w, 1), 0), 1)
                                    let targetMin = Double(frac) * 1440.0
                                    if let nearest = samples.enumerated().min(by: { abs(Double($0.element.minuteOfDay) - targetMin) < abs(Double($1.element.minuteOfDay) - targetMin) }) {
                                        if selectedIdx != nearest.offset {
                                            UISelectionFeedbackGenerator().selectionChanged()
                                            selectedIdx = nearest.offset
                                        }
                                    }
                                }
                        )
                        .onTapGesture {
                            if selectedIdx != nil { selectedIdx = nil }
                        }
                    }
                    .frame(height: 152)

                    VStack(alignment: .trailing) {
                        Text("100"); Spacer(); Text("75"); Spacer(); Text("50"); Spacer(); Text("25"); Spacer(); Text("0")
                    }
                    .font(ImprovingFont.caption(10.5))
                    .foregroundColor(BevelColors.textMuted)
                    .frame(height: 148)
                }
                .padding(.top, showSleepBar ? 18 : 2)

                HStack {
                    Text("0:00"); Spacer(); Text("6:00"); Spacer(); Text("12:00"); Spacer(); Text("18:00"); Spacer(); Text("24:00")
                }
                .font(ImprovingFont.caption(10.5))
                .foregroundColor(BevelColors.textMuted)
                .padding(.trailing, 26)
            }
            .onChange(of: samples.count) { _, _ in selectedIdx = nil }
        }
    }
}

// MARK: - 4-Row Step Sleep Hypnogram Chart (Literal Match to Screenshot 4: Vigilia / MOR / Central / Profundo)

struct SleepHypnogramStepChart: View {
    let stages: [SleepStageBlock]
    let startEpoch: Int64
    let endEpoch: Int64

    private func stageColor(_ s: SleepStageKind) -> Color {
        switch s {
        case .awake: return Color(hex: 0xF2845C)
        case .rem: return Color(hex: 0xA8BCFF)
        case .core: return Color(hex: 0x6285FA)
        case .deep: return Color(hex: 0x4E5CC8)
        }
    }

    private func rowIndex(_ s: SleepStageKind) -> Int {
        switch s {
        case .awake: return 0
        case .rem: return 1
        case .core: return 2
        case .deep: return 3
        }
    }

    var body: some View {
        let span = max(Double(endEpoch - startEpoch), 60.0)
        Canvas { ctx, size in
            let padTop: CGFloat = 10
            let padBot: CGFloat = 10
            let usableH = size.height - padTop - padBot
            let rowH = usableH / 4.0
            let barH = rowH * 0.56

            // Horizontal row dividers
            for r in 0...4 {
                let y = padTop + CGFloat(r) * rowH
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(line, with: .color(Color.white.opacity(0.08)), lineWidth: 1)
            }
            // Subtle outer frame
            ctx.stroke(Path(CGRect(origin: .zero, size: size)), with: .color(Color.white.opacity(0.06)), lineWidth: 1)

            // Draw connecting vertical transitions first
            for i in 0..<(stages.count - 1) {
                let a = stages[i]
                let b = stages[i + 1]
                if b.startEpochSec - a.endEpochSec <= 180 {
                    let x = CGFloat(Double(a.endEpochSec - startEpoch) / span) * size.width
                    let yA = padTop + (CGFloat(rowIndex(a.stage)) + 0.5) * rowH
                    let yB = padTop + (CGFloat(rowIndex(b.stage)) + 0.5) * rowH
                    var v = Path()
                    v.move(to: CGPoint(x: x, y: yA))
                    v.addLine(to: CGPoint(x: x, y: yB))
                    ctx.stroke(v, with: .color(stageColor(a.stage).opacity(0.55)), lineWidth: 1.6)
                }
            }

            // Draw horizontal stage bars
            for blk in stages {
                let x1 = max(0, CGFloat(Double(blk.startEpochSec - startEpoch) / span) * size.width)
                let x2 = min(size.width, CGFloat(Double(blk.endEpochSec - startEpoch) / span) * size.width)
                let w = max(x2 - x1, 2.2)
                let yCenter = padTop + (CGFloat(rowIndex(blk.stage)) + 0.5) * rowH
                let rect = CGRect(x: x1, y: yCenter - barH / 2, width: w, height: barH)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 2.5), with: .color(stageColor(blk.stage)))
            }
        }
        .frame(height: 186)
    }
}

// MARK: - Interactive Overnight Vitals Chart (Literal Match to Screenshots 5, 6, 7, 8: FC / VFC / FR / SpO₂)

enum OvernightVitalTab: String, CaseIterable, Identifiable {
    case fc = "FC"
    case vfc = "VFC"
    case fr = "FR"
    case spo2 = "SpO₂"

    var id: String { rawValue }
}

struct OvernightVitalChart: View {
    let tab: OvernightVitalTab
    let samples: [TimedBiometricPoint]

    @State private var selectedIdx: Int? = nil

    private var accent: Color {
        switch tab {
        case .fc: return Color(hex: 0xF06498)
        case .vfc: return Color(hex: 0x5CE1E6)
        case .fr: return Color(hex: 0xA884FF)
        case .spo2: return Color(hex: 0x26B4F6)
        }
    }

    private var unit: String {
        switch tab {
        case .fc: return "ppm"
        case .vfc: return "ms"
        case .fr: return "rpm"
        case .spo2: return "%"
        }
    }

    private func timeLabel(_ pt: TimedBiometricPoint) -> String {
        String(format: "%d:%02d", (pt.minuteOfDay / 60) % 24, pt.minuteOfDay % 60)
    }

    var body: some View {
        if samples.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 22))
                    .foregroundColor(BevelColors.textMuted)
                Text("No hay mediciones de \(tab.rawValue) durante este sueño")
                    .font(ImprovingFont.caption(12.5))
                    .foregroundColor(BevelColors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.03)))
        } else {
            let vals = samples.map(\.value)
            let rawMin = vals.min() ?? 0
            let rawMax = vals.max() ?? 100
            let span = max(rawMax - rawMin, tab == .spo2 ? 3.0 : (tab == .fr ? 3.0 : 12.0))
            let yMin = floor(rawMin - span * 0.12)
            let yMax = ceil(rawMax + span * 0.14)
            let ySpan = max(yMax - yMin, 1.0)

            let startEp = samples.first?.epochSec ?? 0
            let endEp = samples.last?.epochSec ?? Int64(max(samples.count - 1, 1))
            let hasEpochs = startEp > 0 && endEp > startEp

            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    GeometryReader { geo in
                        let w = geo.size.width
                        let h = geo.size.height
                        let xFor: (Int) -> CGFloat = { idx in
                            if hasEpochs, let ep = samples[idx].epochSec {
                                return CGFloat(Double(ep - startEp) / Double(endEp - startEp)) * w
                            }
                            return samples.count <= 1 ? w / 2 : CGFloat(idx) / CGFloat(samples.count - 1) * w
                        }
                        let yFor: (Double) -> CGFloat = { v in
                            h * (1.0 - CGFloat(min(max((v - yMin) / ySpan, 0), 1)))
                        }

                        ZStack(alignment: .topLeading) {
                            Canvas { ctx, size in
                                for frac in [0.0, 0.33, 0.66, 1.0] {
                                    let y = size.height * frac
                                    var gp = Path()
                                    gp.move(to: CGPoint(x: 0, y: y))
                                    gp.addLine(to: CGPoint(x: size.width, y: y))
                                    ctx.stroke(gp, with: .color(Color.white.opacity(0.07)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                                }

                                if tab == .fc {
                                    // Screenshot 5: pink scatter dots + smooth purple moving-average curve!
                                    for (idx, pt) in samples.enumerated() {
                                        let p = CGPoint(x: xFor(idx), y: yFor(pt.value))
                                        ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2.6, y: p.y - 2.6, width: 5.2, height: 5.2)), with: .color(accent))
                                    }
                                    if samples.count >= 2 {
                                        let window = max(3, samples.count / 12)
                                        var smooth = Path()
                                        for i in 0..<samples.count {
                                            let lo = max(0, i - window)
                                            let hi = min(samples.count - 1, i + window)
                                            let slice = samples[lo...hi].map(\.value)
                                            let ma = slice.reduce(0, +) / Double(slice.count)
                                            let p = CGPoint(x: xFor(i), y: yFor(ma))
                                            if i == 0 { smooth.move(to: p) } else { smooth.addLine(to: p) }
                                        }
                                        ctx.stroke(smooth, with: .color(Color(hex: 0xB388FF)), style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                                    }
                                } else {
                                    // Screenshots 6, 7, 8: colored polyline + soft gradient fill + hollow dark-centered nodes!
                                    if samples.count >= 2 {
                                        var line = Path()
                                        var fill = Path()
                                        for (idx, pt) in samples.enumerated() {
                                            let p = CGPoint(x: xFor(idx), y: yFor(pt.value))
                                            if idx == 0 {
                                                line.move(to: p)
                                                fill.move(to: CGPoint(x: p.x, y: size.height))
                                                fill.addLine(to: p)
                                            } else {
                                                line.addLine(to: p)
                                                fill.addLine(to: p)
                                            }
                                        }
                                        fill.addLine(to: CGPoint(x: xFor(samples.count - 1), y: size.height))
                                        fill.closeSubpath()
                                        ctx.fill(fill, with: .linearGradient(Gradient(colors: [accent.opacity(0.24), .clear]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                                        ctx.stroke(line, with: .color(accent), style: StrokeStyle(lineWidth: 2.3, lineCap: .round, lineJoin: .round))
                                    }
                                    let drawNodes = samples.count <= 65
                                    if drawNodes {
                                        for (idx, pt) in samples.enumerated() {
                                            let p = CGPoint(x: xFor(idx), y: yFor(pt.value))
                                            let r = CGRect(x: p.x - 3.6, y: p.y - 3.6, width: 7.2, height: 7.2)
                                            ctx.fill(Path(ellipseIn: r), with: .color(Color(hex: 0x111526)))
                                            ctx.stroke(Path(ellipseIn: r), with: .color(accent), lineWidth: 1.9)
                                        }
                                    }
                                }

                                if let sel = selectedIdx, sel < samples.count {
                                    let sx = xFor(sel)
                                    let sy = yFor(samples[sel].value)
                                    var v = Path()
                                    v.move(to: CGPoint(x: sx, y: 0))
                                    v.addLine(to: CGPoint(x: sx, y: size.height))
                                    ctx.stroke(v, with: .color(Color.white.opacity(0.35)), style: StrokeStyle(lineWidth: 1.3, dash: [4, 4]))
                                    ctx.fill(Path(ellipseIn: CGRect(x: sx - 5.5, y: sy - 5.5, width: 11, height: 11)), with: .color(.white))
                                }
                            }

                            if let sel = selectedIdx, sel < samples.count {
                                let pt = samples[sel]
                                let px = min(max(xFor(sel), 56), w - 56)
                                let py = max(yFor(pt.value) - 22, 16)
                                Text("\(timeLabel(pt)) · \(String(format: "%.1f", locale: Locale(identifier: "es_ES"), pt.value)) \(unit)")
                                    .font(ImprovingFont.caption(11))
                                    .fontWeight(.bold)
                                    .monospacedDigit()
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(BevelColors.floatingDarkButton))
                                    .position(x: px, y: py)
                            }
                        }
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { val in
                                    let tx = min(max(val.location.x, 0), w)
                                    if let nearest = samples.indices.min(by: { abs(xFor($0) - tx) < abs(xFor($1) - tx) }) {
                                        if selectedIdx != nearest {
                                            UISelectionFeedbackGenerator().selectionChanged()
                                            selectedIdx = nearest
                                        }
                                    }
                                }
                        )
                        .onTapGesture { selectedIdx = nil }
                    }
                    .frame(height: 176)

                    VStack(alignment: .trailing) {
                        Text("\(Int(yMax.rounded()))")
                        Spacer()
                        Text("\(Int((yMin + ySpan * 0.66).rounded()))")
                        Spacer()
                        Text("\(Int((yMin + ySpan * 0.33).rounded()))")
                        Spacer()
                        Text("\(Int(yMin.rounded()))")
                    }
                    .font(ImprovingFont.caption(10.5))
                    .monospacedDigit()
                    .foregroundColor(BevelColors.textMuted)
                    .frame(height: 172)
                }

                HStack {
                    if let first = samples.first {
                        HStack(spacing: 4) {
                            Image(systemName: "moon.fill").font(.system(size: 10))
                            Text(timeLabel(first))
                        }
                        .font(ImprovingFont.caption(11.5))
                        .foregroundColor(BevelColors.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                    Spacer()
                    if let last = samples.last {
                        HStack(spacing: 4) {
                            Image(systemName: "sun.max.fill").font(.system(size: 10))
                            Text(timeLabel(last))
                        }
                        .font(ImprovingFont.caption(11.5))
                        .foregroundColor(BevelColors.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                }
                .padding(.trailing, 28)
            }
            .onChange(of: tab) { _, _ in selectedIdx = nil }
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

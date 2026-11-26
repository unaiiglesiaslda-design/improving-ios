import SwiftUI

// MARK: - Fitness Range Control Bar (<  [ 7 D | 30 d | 3 M | 1 A | YTD ]  sliders  >)

struct FitnessRangeControlBar: View {
    @Binding var selectedRange: String
    let canStepBackward: Bool
    let canStepForward: Bool
    let onStepBackward: () -> Void
    let onStepForward: () -> Void
    var onRangeChanged: () -> Void = {}

    static let options = ["7 d", "30 d", "3 M", "1 A", "Año"]

    static func spanDays(for range: String, anchorDate: Date = Date()) -> Int {
        switch range {
        case "7 d", "7 D": return 7
        case "30 d": return 31
        case "3 M": return 90
        case "1 A": return 365
        case "Año", "YTD":
            let cal = Calendar.current
            let y = cal.component(.year, from: anchorDate)
            let jan1 = cal.date(from: DateComponents(year: y, month: 1, day: 1)) ?? anchorDate
            let days = (cal.dateComponents([.day], from: jan1, to: cal.startOfDay(for: anchorDate)).day ?? 30) + 1
            return max(days, 7)
        default: return 31
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            Button(action: onStepBackward) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(canStepBackward ? BevelColors.textPrimary : BevelColors.textMuted.opacity(0.35))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(BevelColors.cardSubtle))
            }
            .disabled(!canStepBackward)

            HStack(spacing: 2) {
                ForEach(Self.options, id: \.self) { opt in
                    let active = selectedRange == opt
                    Button {
                        if selectedRange != opt {
                            UISelectionFeedbackGenerator().selectionChanged()
                            selectedRange = opt
                            onRangeChanged()
                        }
                    } label: {
                        Text(opt)
                            .font(ImprovingFont.caption(11.5))
                            .fontWeight(.semibold)
                            .foregroundColor(active ? .white : BevelColors.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6.5)
                            .background(Capsule().fill(active ? Color(hex: 0x6A6E7A) : .clear))
                    }
                }
            }
            .padding(3)
            .background(Capsule().fill(BevelColors.cardSubtle))

            Button(action: onStepForward) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(canStepForward ? BevelColors.textPrimary : BevelColors.textMuted.opacity(0.35))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(BevelColors.cardSubtle))
            }
            .disabled(!canStepForward)
        }
    }
}

// MARK: - Training Load Dynamic Green Optimal Ribbon Chart (Exact Match to Screenshots 3 & 5)

struct TrainingLoadOptimalBandChart: View {
    let points: [TrainingLoadDayPoint]
    let currentOptLow: Int
    let currentOptHigh: Int
    var onPointSelected: (TrainingLoadDayPoint?) -> Void = { _ in }

    @State private var selectedIdx: Int? = nil

    var body: some View {
        if points.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 24))
                    .foregroundColor(BevelColors.textMuted)
                Text("Sin carga registrada en este período")
                    .font(ImprovingFont.caption(12.5))
                    .foregroundColor(BevelColors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 196)
        } else {
            let maxLoad = max(points.map(\.load).max() ?? 1, points.map(\.optHigh).max() ?? 1)
            let yMax = max(maxLoad * 1.24, 6.0)
            let showNodes = points.count <= 40

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    GeometryReader { geo in
                        let w = geo.size.width
                        let h = geo.size.height
                        let xFor: (Int) -> CGFloat = { idx in
                            points.count <= 1 ? w / 2 : 6 + CGFloat(idx) / CGFloat(points.count - 1) * (w - 14)
                        }
                        let yFor: (Double) -> CGFloat = { v in
                            h - 10 - CGFloat(min(max(v / yMax, 0), 1)) * (h - 20)
                        }

                        ZStack(alignment: .topLeading) {
                            Canvas { ctx, sz in
                                // Subtle baseline grid
                                for frac in [0.18, 0.50, 0.82, 0.96] {
                                    let y = sz.height * frac
                                    var g = Path()
                                    g.move(to: CGPoint(x: 0, y: y))
                                    g.addLine(to: CGPoint(x: sz.width, y: y))
                                    ctx.stroke(g, with: .color(BevelColors.chartGridLine), lineWidth: 1)
                                }

                                // Dynamic green optimal zone ribbon polygon tracking daily (optLow, optHigh)
                                if points.count >= 2 {
                                    var ribbon = Path()
                                    for (i, p) in points.enumerated() {
                                        let pt = CGPoint(x: xFor(i), y: yFor(p.optHigh))
                                        if i == 0 { ribbon.move(to: pt) } else { ribbon.addLine(to: pt) }
                                    }
                                    for i in stride(from: points.count - 1, through: 0, by: -1) {
                                        ribbon.addLine(to: CGPoint(x: xFor(i), y: yFor(points[i].optLow)))
                                    }
                                    ribbon.closeSubpath()
                                    ctx.fill(ribbon, with: .color(BevelColors.greenPrimary.opacity(0.24)))

                                    var topEdge = Path()
                                    var botEdge = Path()
                                    for (i, p) in points.enumerated() {
                                        let tPt = CGPoint(x: xFor(i), y: yFor(p.optHigh))
                                        let bPt = CGPoint(x: xFor(i), y: yFor(p.optLow))
                                        if i == 0 { topEdge.move(to: tPt); botEdge.move(to: bPt) }
                                        else { topEdge.addLine(to: tPt); botEdge.addLine(to: bPt) }
                                    }
                                    ctx.stroke(topEdge, with: .color(BevelColors.greenPrimary.opacity(0.55)), lineWidth: 1.2)
                                    ctx.stroke(botEdge, with: .color(BevelColors.greenPrimary.opacity(0.45)), lineWidth: 1.1)
                                }

                                // Load polyline
                                if points.count >= 2 {
                                    var line = Path()
                                    for (i, p) in points.enumerated() {
                                        let pt = CGPoint(x: xFor(i), y: yFor(p.load))
                                        if i == 0 { line.move(to: pt) } else { line.addLine(to: pt) }
                                    }
                                    ctx.stroke(line, with: .color(Color(hex: 0x9A9FA8)), style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round))
                                }

                                // Scrub vertical guide
                                if let sel = selectedIdx, points.indices.contains(sel) {
                                    let sx = xFor(sel)
                                    var v = Path()
                                    v.move(to: CGPoint(x: sx, y: 0))
                                    v.addLine(to: CGPoint(x: sx, y: sz.height))
                                    ctx.stroke(v, with: .color(BevelColors.chartAxisStroke), style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                                }

                                // Hollow circular nodes + glowing active/last circle
                                let activeIdx = selectedIdx ?? (points.count - 1)
                                for (i, p) in points.enumerated() {
                                    let pt = CGPoint(x: xFor(i), y: yFor(p.load))
                                    if i == activeIdx {
                                        ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 11, y: pt.y - 11, width: 22, height: 22)), with: .color(BevelColors.chartTrackSubtle))
                                        ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 5.5, y: pt.y - 5.5, width: 11, height: 11)), with: .color(BevelColors.sheetHeaderBg))
                                        ctx.stroke(Path(ellipseIn: CGRect(x: pt.x - 5.5, y: pt.y - 5.5, width: 11, height: 11)), with: .color(BevelColors.chartPointerFill), lineWidth: 2.4)
                                    } else if showNodes {
                                        let r = CGRect(x: pt.x - 3.3, y: pt.y - 3.3, width: 6.6, height: 6.6)
                                        ctx.fill(Path(ellipseIn: r), with: .color(BevelColors.sheetHeaderBg))
                                        ctx.stroke(Path(ellipseIn: r), with: .color(Color(hex: 0xA1A6B0)), lineWidth: 1.6)
                                    }
                                }
                            }

                            if let sel = selectedIdx, points.indices.contains(sel) {
                                let p = points[sel]
                                let px = min(max(xFor(sel), 62), w - 62)
                                let py = max(yFor(p.load) - 24, 16)
                                Text("\(p.shortDateLabel) · \(Int(p.load.rounded())) (\(p.state.rawValue))")
                                    .font(ImprovingFont.caption(11))
                                    .fontWeight(.bold)
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
                                    let tx = min(max(val.location.x, 0), w)
                                    if let nearest = points.indices.min(by: { abs(xFor($0) - tx) < abs(xFor($1) - tx) }) {
                                        if selectedIdx != nearest {
                                            UISelectionFeedbackGenerator().selectionChanged()
                                            selectedIdx = nearest
                                            onPointSelected(points[nearest])
                                        }
                                    }
                                }
                        )
                        .onTapGesture {
                            selectedIdx = nil
                            onPointSelected(nil)
                        }
                    }
                    .frame(height: 196)

                    // Right-side vertical green optimal zone indicator bar (exact match to Screenshots 3 & 5)
                    GeometryReader { rGeo in
                        let h = rGeo.size.height
                        let yFor: (Double) -> CGFloat = { v in
                            h - 10 - CGFloat(min(max(v / yMax, 0), 1)) * (h - 20)
                        }
                        let yHigh = yFor(Double(currentOptHigh))
                        let yLow = yFor(Double(currentOptLow))
                        let segH = max(abs(yLow - yHigh), 10)

                        HStack(spacing: 4) {
                            ZStack(alignment: .topTrailing) {
                                Color.clear
                                Text("\(currentOptHigh)")
                                    .font(ImprovingFont.caption(10.5))
                                    .monospacedDigit()
                                    .foregroundColor(BevelColors.greenPrimary)
                                    .position(x: 11, y: max(min(yHigh, h - 22), 10))
                                Text("\(currentOptLow)")
                                    .font(ImprovingFont.caption(10.5))
                                    .monospacedDigit()
                                    .foregroundColor(BevelColors.greenPrimary)
                                    .position(x: 11, y: max(min(yLow, h - 8), yHigh + 15))
                            }
                            .frame(width: 22)

                            ZStack(alignment: .top) {
                                Capsule().fill(Color.white.opacity(0.12)).frame(width: 4.5, height: h - 14).offset(y: 7)
                                Capsule().fill(BevelColors.greenPrimary).frame(width: 4.5, height: segH).offset(y: min(yHigh, yLow))
                            }
                            .frame(width: 6)
                        }
                    }
                    .frame(width: 34, height: 196)
                }

                // Bottom X-Axis Dates
                HStack {
                    Text(points.first?.shortDateLabel ?? "")
                    Spacer()
                    if points.count > 4 {
                        Text(points[points.count / 4].shortDateLabel)
                        Spacer()
                        Text(points[points.count / 2].shortDateLabel)
                        Spacer()
                        Text(points[(points.count * 3) / 4].shortDateLabel)
                        Spacer()
                    }
                    Text(points.last?.shortDateLabel ?? "")
                        .foregroundColor(BevelColors.textPrimary)
                }
                .font(ImprovingFont.caption(10.5))
                .foregroundColor(BevelColors.textMuted)
                .padding(.trailing, 38)
            }
            .onChange(of: points.count) { _, _ in selectedIdx = nil }
        }
    }
}

// MARK: - Activity Comparison Bar / Cumulative Stepped Line Chart (Screenshots 7-9 & 25-28)

struct ActivityComparisonBarOrLineChart: View {
    let dailyCurrent: [Double]
    let dailyPrevious: [Double]
    let dateLabels: [String]
    let isBarMode: Bool
    let accentStart: Color
    let accentEnd: Color
    let valueFormatter: (Double) -> String
    var height: CGFloat = 176

    @State private var selectedIdx: Int? = nil

    private var cumulativeCurrent: [Double] {
        var run = 0.0
        return dailyCurrent.map { run += $0; return run }
    }

    private var cumulativePrevious: [Double] {
        var run = 0.0
        return dailyPrevious.map { run += $0; return run }
    }

    var body: some View {
        let curSeries = isBarMode ? dailyCurrent : cumulativeCurrent
        let prevSeries = isBarMode ? dailyPrevious : cumulativePrevious
        let maxVal = max(max(curSeries.max() ?? 0, prevSeries.max() ?? 0), 1.0)
        let yMax = maxVal * 1.15
        let count = max(curSeries.count, 2)

        VStack(spacing: 8) {
            HStack(spacing: 6) {
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    let xFor: (Int) -> CGFloat = { idx in
                        6 + CGFloat(idx) / CGFloat(max(count - 1, 1)) * max(w - 16, 10)
                    }
                    let yFor: (Double) -> CGFloat = { v in
                        h - 8 - CGFloat(min(max(v / yMax, 0), 1)) * (h - 18)
                    }

                    ZStack(alignment: .topLeading) {
                        Canvas { ctx, sz in
                            for frac in [0.12, 0.42, 0.72, 0.96] {
                                let y = sz.height * frac
                                var g = Path()
                                g.move(to: CGPoint(x: 0, y: y))
                                g.addLine(to: CGPoint(x: sz.width, y: y))
                                ctx.stroke(g, with: .color(BevelColors.chartGridLine), lineWidth: 1)
                            }

                            if isBarMode {
                                let slotW = max((sz.width - 8) / CGFloat(count), 3)
                                let barW = max(slotW * 0.62, 2.5)
                                for i in 0..<curSeries.count {
                                    let cx = xFor(i)
                                    if i < prevSeries.count && prevSeries[i] > 0 {
                                        let py = yFor(prevSeries[i])
                                        let pRect = CGRect(x: cx - barW * 0.55, y: py, width: barW * 0.5, height: max(sz.height - 8 - py, 2))
                                        ctx.fill(Path(roundedRect: pRect, cornerRadius: 2.5), with: .color(Color.white.opacity(0.16)))
                                    }
                                    if curSeries[i] > 0 {
                                        let cy = yFor(curSeries[i])
                                        let cRect = CGRect(x: cx - barW / 2, y: cy, width: barW, height: max(sz.height - 8 - cy, 3))
                                        ctx.fill(
                                            Path(roundedRect: cRect, cornerRadius: 3),
                                            with: .linearGradient(Gradient(colors: [accentEnd, accentStart.opacity(0.75)]), startPoint: CGPoint(x: cx, y: cy), endPoint: CGPoint(x: cx, y: sz.height))
                                        )
                                    }
                                }
                            } else {
                                // Previous period muted gray comparison curve
                                if prevSeries.count >= 2 {
                                    var pPath = Path()
                                    for (i, v) in prevSeries.enumerated() {
                                        let pt = CGPoint(x: xFor(i), y: yFor(v))
                                        if i == 0 { pPath.move(to: pt) } else { pPath.addLine(to: pt) }
                                    }
                                    ctx.stroke(pPath, with: .color(Color.white.opacity(0.24)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                                }

                                // Current period stepped cumulative line + vertical area gradient
                                if curSeries.count >= 2 {
                                    var line = Path()
                                    var fill = Path()
                                    for (i, v) in curSeries.enumerated() {
                                        let pt = CGPoint(x: xFor(i), y: yFor(v))
                                        if i == 0 {
                                            line.move(to: pt)
                                            fill.move(to: CGPoint(x: pt.x, y: sz.height - 8))
                                            fill.addLine(to: pt)
                                        } else {
                                            line.addLine(to: pt)
                                            fill.addLine(to: pt)
                                        }
                                    }
                                    fill.addLine(to: CGPoint(x: xFor(curSeries.count - 1), y: sz.height - 8))
                                    fill.closeSubpath()
                                    ctx.fill(
                                        fill,
                                        with: .linearGradient(Gradient(colors: [accentEnd.opacity(0.24), .clear]), startPoint: .zero, endPoint: CGPoint(x: 0, y: sz.height))
                                    )
                                    ctx.stroke(
                                        line,
                                        with: .linearGradient(Gradient(colors: [accentStart, accentEnd]), startPoint: .zero, endPoint: CGPoint(x: sz.width, y: 0)),
                                        style: StrokeStyle(lineWidth: 2.3, lineCap: .round, lineJoin: .round)
                                    )

                                    // Hollow circles on step-up days + glowing endpoint (Screenshots 7 & 25!)
                                    for i in 0..<curSeries.count {
                                        let steppedUp = (i == 0) || (i < dailyCurrent.count && dailyCurrent[i] > 0)
                                        if i == curSeries.count - 1 {
                                            let pt = CGPoint(x: xFor(i), y: yFor(curSeries[i]))
                                            ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 11, y: pt.y - 11, width: 22, height: 22)), with: .color(accentEnd.opacity(0.32)))
                                            ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 4.8, y: pt.y - 4.8, width: 9.6, height: 9.6)), with: .color(accentEnd))
                                            ctx.stroke(Path(ellipseIn: CGRect(x: pt.x - 4.8, y: pt.y - 4.8, width: 9.6, height: 9.6)), with: .color(.white.opacity(0.45)), lineWidth: 1.2)
                                        } else if steppedUp && curSeries.count <= 45 {
                                            let pt = CGPoint(x: xFor(i), y: yFor(curSeries[i]))
                                            let r = CGRect(x: pt.x - 3.6, y: pt.y - 3.6, width: 7.2, height: 7.2)
                                            ctx.fill(Path(ellipseIn: r), with: .color(BevelColors.sheetHeaderBg))
                                            ctx.stroke(Path(ellipseIn: r), with: .color(accentEnd), lineWidth: 1.9)
                                        }
                                    }
                                }
                            }

                            if let sel = selectedIdx, sel < curSeries.count {
                                let sx = xFor(sel)
                                let sy = yFor(curSeries[sel])
                                var vp = Path()
                                vp.move(to: CGPoint(x: sx, y: 0))
                                vp.addLine(to: CGPoint(x: sx, y: sz.height))
                                ctx.stroke(vp, with: .color(Color.white.opacity(0.30)), style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                                ctx.fill(Path(ellipseIn: CGRect(x: sx - 5, y: sy - 5, width: 10, height: 10)), with: .color(.white))
                            }
                        }

                        if let sel = selectedIdx, sel < curSeries.count {
                            let lbl = sel < dateLabels.count ? "\(dateLabels[sel]) · " : ""
                            let px = min(max(xFor(sel), 58), w - 58)
                            let py = max(yFor(curSeries[sel]) - 22, 16)
                            Text("\(lbl)\(valueFormatter(curSeries[sel]))")
                                .font(ImprovingFont.caption(11))
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
                                let tx = min(max(val.location.x, 0), w)
                                if let nearest = curSeries.indices.min(by: { abs(xFor($0) - tx) < abs(xFor($1) - tx) }) {
                                    if selectedIdx != nearest {
                                        UISelectionFeedbackGenerator().selectionChanged()
                                        selectedIdx = nearest
                                    }
                                }
                            }
                    )
                    .onTapGesture { selectedIdx = nil }
                }
                .frame(height: height)

                // Right Y-Axis ticks
                VStack(alignment: .trailing) {
                    Text(valueFormatter(yMax))
                    Spacer()
                    Text(valueFormatter(yMax * 0.66))
                    Spacer()
                    Text(valueFormatter(yMax * 0.33))
                    Spacer()
                    Text("0")
                }
                .font(ImprovingFont.caption(10.5))
                .monospacedDigit()
                .foregroundColor(BevelColors.textMuted)
                .frame(height: height - 8)
            }

            if !dateLabels.isEmpty {
                HStack {
                    Text(dateLabels.first ?? "")
                    Spacer()
                    if dateLabels.count > 4 {
                        Text(dateLabels[dateLabels.count / 4])
                        Spacer()
                        Text(dateLabels[dateLabels.count / 2])
                        Spacer()
                        Text(dateLabels[(dateLabels.count * 3) / 4])
                        Spacer()
                    }
                    Text(dateLabels.last ?? "")
                        .foregroundColor(BevelColors.textPrimary)
                }
                .font(ImprovingFont.caption(10.5))
                .foregroundColor(BevelColors.textMuted)
                .padding(.trailing, 34)
            }
        }
        .onChange(of: dateLabels) { _, _ in selectedIdx = nil }
    }
}

// MARK: - VO₂ máx. & HRR Gradient Area Chart with Dashed Day Ticks (Screenshots 13 & 16)

struct Vo2AmberAreaChart: View {
    let optionalPoints: [Double?]
    let dates: [String]
    let lineStartColor: Color
    let lineEndColor: Color
    var averageBadgeText: String? = nil
    let valueFormatter: (Double) -> String

    @State private var selectedIdx: Int? = nil

    var body: some View {
        let validPairs: [(idx: Int, val: Double)] = optionalPoints.enumerated().compactMap { idx, opt in
            guard let v = opt else { return nil }
            return (idx, v)
        }
        let realVals = validPairs.map(\.val)

        if realVals.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 24))
                    .foregroundColor(BevelColors.textMuted)
                Text("Sin mediciones registradas en este período")
                    .font(ImprovingFont.caption(12.5))
                    .foregroundColor(BevelColors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 186)
        } else {
            let minV = realVals.min() ?? 0
            let maxV = realVals.max() ?? 100
            let span = max(maxV - minV, 1.4)
            let yMin = minV - span * 0.22
            let yMax = maxV + span * 0.24
            let ySpan = max(yMax - yMin, 1.0)
            let avgVal = realVals.reduce(0, +) / Double(realVals.count)
            let slots = max(optionalPoints.count, 2)

            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    GeometryReader { geo in
                        let w = geo.size.width
                        let h = geo.size.height
                        let xFor: (Int) -> CGFloat = { idx in
                            6 + CGFloat(idx) / CGFloat(slots - 1) * max(w - 14, 10)
                        }
                        let yFor: (Double) -> CGFloat = { v in
                            h - 10 - CGFloat(min(max((v - yMin) / ySpan, 0), 1)) * (h - 20)
                        }

                        ZStack(alignment: .topLeading) {
                            Canvas { ctx, sz in
                                for frac in [0.12, 0.42, 0.72, 0.96] {
                                    let y = sz.height * frac
                                    var g = Path()
                                    g.move(to: CGPoint(x: 0, y: y))
                                    g.addLine(to: CGPoint(x: sz.width, y: y))
                                    ctx.stroke(g, with: .color(BevelColors.chartGridLine), lineWidth: 1)
                                }

                                if averageBadgeText != nil {
                                    let ay = yFor(avgVal)
                                    var ap = Path()
                                    ap.move(to: CGPoint(x: 0, y: ay))
                                    ap.addLine(to: CGPoint(x: sz.width, y: ay))
                                    ctx.stroke(ap, with: .color(Color(hex: 0xF4A478).opacity(0.70)), style: StrokeStyle(lineWidth: 1.6, dash: [2.5, 4]))
                                }

                                if validPairs.count >= 2 {
                                    var line = Path()
                                    var fill = Path()
                                    for (n, pair) in validPairs.enumerated() {
                                        let pt = CGPoint(x: xFor(pair.idx), y: yFor(pair.val))
                                        if n == 0 {
                                            line.move(to: pt)
                                            fill.move(to: CGPoint(x: pt.x, y: sz.height - 6))
                                            fill.addLine(to: pt)
                                        } else {
                                            line.addLine(to: pt)
                                            fill.addLine(to: pt)
                                        }
                                    }
                                    if let last = validPairs.last {
                                        fill.addLine(to: CGPoint(x: xFor(last.idx), y: sz.height - 6))
                                        fill.closeSubpath()
                                    }
                                    ctx.fill(
                                        fill,
                                        with: .linearGradient(Gradient(colors: [lineEndColor.opacity(0.24), .clear]), startPoint: .zero, endPoint: CGPoint(x: 0, y: sz.height))
                                    )
                                    ctx.stroke(
                                        line,
                                        with: .linearGradient(Gradient(colors: [lineStartColor, lineEndColor]), startPoint: .zero, endPoint: CGPoint(x: sz.width, y: sz.height)),
                                        style: StrokeStyle(lineWidth: 2.3, lineCap: .round, lineJoin: .round)
                                    )
                                }

                                for (n, pair) in validPairs.enumerated() {
                                    let pt = CGPoint(x: xFor(pair.idx), y: yFor(pair.val))
                                    let isLast = n == validPairs.count - 1
                                    if isLast || pair.idx == selectedIdx {
                                        ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 11, y: pt.y - 11, width: 22, height: 22)), with: .color(lineEndColor.opacity(0.32)))
                                        ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10)), with: .color(BevelColors.sheetHeaderBg))
                                        ctx.stroke(Path(ellipseIn: CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10)), with: .color(lineEndColor), lineWidth: 2.5)
                                    } else if validPairs.count <= 20 {
                                        let r = CGRect(x: pt.x - 3.6, y: pt.y - 3.6, width: 7.2, height: 7.2)
                                        ctx.fill(Path(ellipseIn: r), with: .color(BevelColors.sheetHeaderBg))
                                        ctx.stroke(Path(ellipseIn: r), with: .color(lineStartColor), lineWidth: 1.9)
                                    }
                                }
                            }

                            if selectedIdx == nil, let badge = averageBadgeText {
                                Text(badge)
                                    .font(ImprovingFont.caption(11.5))
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 3.5)
                                    .background(Capsule().fill(Color(hex: 0xF3A678)))
                                    .position(x: w * 0.52, y: min(max(yFor(avgVal), 16), h - 16))
                            } else if let sel = selectedIdx, sel < optionalPoints.count, let v = optionalPoints[sel] {
                                let dStr = sel < dates.count ? "\(dates[sel]) · " : ""
                                let px = min(max(xFor(sel), 56), w - 56)
                                let py = max(yFor(v) - 22, 16)
                                Text("\(dStr)\(valueFormatter(v))")
                                    .font(ImprovingFont.caption(11))
                                    .fontWeight(.bold)
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
                                    if let nearest = validPairs.min(by: { abs(xFor($0.idx) - tx) < abs(xFor($1.idx) - tx) }) {
                                        if selectedIdx != nearest.idx {
                                            UISelectionFeedbackGenerator().selectionChanged()
                                            selectedIdx = nearest.idx
                                        }
                                    }
                                }
                        )
                        .onTapGesture { selectedIdx = nil }
                    }
                    .frame(height: 176)

                    VStack(alignment: .trailing) {
                        Text(String(format: "%.1f", locale: Locale(identifier: "es_ES"), yMax))
                        Spacer()
                        Text(String(format: "%.1f", locale: Locale(identifier: "es_ES"), yMin + ySpan * 0.66))
                        Spacer()
                        Text(String(format: "%.1f", locale: Locale(identifier: "es_ES"), yMin + ySpan * 0.33))
                        Spacer()
                        Text(String(format: "%.1f", locale: Locale(identifier: "es_ES"), yMin))
                    }
                    .font(ImprovingFont.caption(10.5))
                    .monospacedDigit()
                    .foregroundColor(BevelColors.textMuted)
                    .frame(height: 168)
                }

                // Signature dashed day-slot ticks bar (Screenshots 13 & 16!)
                HStack(spacing: 3) {
                    ForEach(0..<min(slots, 31), id: \.self) { _ in
                        Capsule()
                            .fill(Color.white.opacity(0.24))
                            .frame(height: 3)
                    }
                }
                .padding(.trailing, 34)

                if !dates.isEmpty {
                    HStack {
                        Text(dates.first ?? "")
                        Spacer()
                        if dates.count > 4 {
                            Text(dates[dates.count / 4])
                            Spacer()
                            Text(dates[dates.count / 2])
                            Spacer()
                            Text(dates[(dates.count * 3) / 4])
                            Spacer()
                        }
                        Text(dates.last ?? "")
                            .foregroundColor(BevelColors.textPrimary)
                    }
                    .font(ImprovingFont.caption(10.5))
                    .foregroundColor(BevelColors.textMuted)
                    .padding(.trailing, 34)
                }
            }
            .onChange(of: dates) { _, _ in selectedIdx = nil }
        }
    }
}

// MARK: - Cardio Focus Stacked Daily Bar Chart (Exact Match to Screenshot 19)

struct CardioFocusStackedBarChart: View {
    let dailyTriples: [(low: Int, high: Int, anaero: Int)]
    let dateLabels: [String]

    var body: some View {
        let totals = dailyTriples.map { $0.low + $0.high + $0.anaero }
        let maxVal = max(totals.max() ?? 0, 1)
        let yMax = max(Int(ceil(Double(maxVal) * 1.15)), 4)

        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Canvas { ctx, sz in
                    for frac in [0.06, 0.38, 0.70, 0.98] {
                        let y = sz.height * frac
                        var g = Path()
                        g.move(to: CGPoint(x: 0, y: y))
                        g.addLine(to: CGPoint(x: sz.width, y: y))
                        ctx.stroke(g, with: .color(BevelColors.chartGridLine), lineWidth: 1)
                    }

                    let count = max(dailyTriples.count, 1)
                    let slotW = sz.width / CGFloat(count)
                    let barW = min(max(slotW * 0.56, 3.5), 10)

                    for (i, t) in dailyTriples.enumerated() {
                        let tot = t.low + t.high + t.anaero
                        guard tot > 0 else { continue }
                        let cx = (CGFloat(i) + 0.5) * slotW
                        let usableH = sz.height - 10
                        let lowH = CGFloat(t.low) / CGFloat(yMax) * usableH
                        let highH = CGFloat(t.high) / CGFloat(yMax) * usableH
                        let anH = CGFloat(t.anaero) / CGFloat(yMax) * usableH

                        var cursorY = sz.height - 4
                        if lowH > 0.5 {
                            let r = CGRect(x: cx - barW / 2, y: cursorY - lowH, width: barW, height: lowH)
                            ctx.fill(Path(roundedRect: r, cornerRadius: barW / 2), with: .color(Color(hex: 0x62E2E8)))
                            cursorY -= lowH
                        }
                        if highH > 0.5 {
                            let r = CGRect(x: cx - barW / 2, y: cursorY - highH, width: barW, height: highH)
                            ctx.fill(Path(roundedRect: r, cornerRadius: barW / 2), with: .color(Color(hex: 0x5682FF)))
                            cursorY -= highH
                        }
                        if anH > 0.5 {
                            let r = CGRect(x: cx - barW / 2, y: cursorY - anH, width: barW, height: anH)
                            ctx.fill(Path(roundedRect: r, cornerRadius: barW / 2), with: .color(Color(hex: 0xA855F7)))
                        }
                    }
                }
                .frame(height: 174)

                VStack(alignment: .trailing) {
                    Text("\(yMax)")
                    Spacer()
                    Text("\(Int((Double(yMax) * 0.66).rounded()))")
                    Spacer()
                    Text("\(Int((Double(yMax) * 0.33).rounded()))")
                    Spacer()
                    Text("0")
                }
                .font(ImprovingFont.caption(10.5))
                .monospacedDigit()
                .foregroundColor(BevelColors.textMuted)
                .frame(height: 168)
            }

            if !dateLabels.isEmpty {
                HStack {
                    Text(dateLabels.first ?? "")
                    Spacer()
                    if dateLabels.count > 4 {
                        Text(dateLabels[dateLabels.count / 4])
                        Spacer()
                        Text(dateLabels[dateLabels.count / 2])
                        Spacer()
                        Text(dateLabels[(dateLabels.count * 3) / 4])
                        Spacer()
                    }
                    Text(dateLabels.last ?? "")
                        .foregroundColor(BevelColors.textPrimary)
                }
                .font(ImprovingFont.caption(10.5))
                .foregroundColor(BevelColors.textMuted)
                .padding(.trailing, 26)
            }
        }
    }
}

// MARK: - 6-Bar HR Zones Chart Z0..Z5 (Exact Match to Screenshot 22)

struct HrZonesSixBarChart: View {
    let minutes6: [Int] // [Z0, Z1, Z2, Z3, Z4, Z5]
    @Binding var selectedZone: Int

    static let zoneColors: [Color] = [
        Color(hex: 0xA9C1F8), // Z0
        Color(hex: 0x5882FA), // Z1
        Color(hex: 0x4ED485), // Z2
        Color(hex: 0xF5A623), // Z3
        Color(hex: 0xEF4444), // Z4
        Color(hex: 0xA855F7), // Z5
    ]

    var body: some View {
        let safe = (0..<6).map { $0 < minutes6.count ? minutes6[$0] : 0 }
        let maxM = max(safe.max() ?? 0, 1)
        let yMax = max(Int(ceil(Double(maxM) * 1.12)), 12)

        VStack(spacing: 10) {
            HStack(alignment: .bottom, spacing: 8) {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(0..<6, id: \.self) { idx in
                        let mins = safe[idx]
                        let frac = CGFloat(mins) / CGFloat(yMax)
                        let c = Self.zoneColors[idx]
                        let isSel = selectedZone == idx

                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            selectedZone = idx
                        } label: {
                            VStack(spacing: 8) {
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [c, c.opacity(mins > 0 ? 0.45 : 0.14)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(height: mins > 0 ? max(frac * 158, 8) : 5)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .strokeBorder(isSel ? Color.white.opacity(0.6) : .clear, lineWidth: 1.4)
                                    )

                                HStack(spacing: 4) {
                                    Circle().fill(c).frame(width: 6.5, height: 6.5)
                                    Text("Z\(idx)")
                                        .font(ImprovingFont.caption(11.5))
                                        .fontWeight(isSel ? .bold : .semibold)
                                        .foregroundColor(isSel ? BevelColors.textPrimary : BevelColors.textSecondary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(height: 192)

                VStack(alignment: .trailing) {
                    Text("\(yMax)m")
                    Spacer()
                    Text("\(Int((Double(yMax) * 0.66).rounded()))m")
                    Spacer()
                    Text("\(Int((Double(yMax) * 0.33).rounded()))m")
                    Spacer()
                    Text("0")
                }
                .font(ImprovingFont.caption(10.5))
                .monospacedDigit()
                .foregroundColor(BevelColors.textMuted)
                .frame(height: 164)
                .padding(.bottom, 22)
            }
        }
    }
}

// MARK: - Mini Fitness Tile Sparklines & Bars (Exact Match to Screenshot 2!)

struct MiniFitnessStepSparkline: View {
    let currentSeries: [Double]
    let previousSeries: [Double]
    let accentStart: Color
    let accentEnd: Color

    var body: some View {
        let cur = currentSeries.count >= 2 ? currentSeries : [0, 0]
        let prev = previousSeries.count >= 2 ? previousSeries : cur
        let maxV = max(max(cur.max() ?? 0, prev.max() ?? 0), 1.0)

        Canvas { ctx, sz in
            let w = sz.width - 8
            let h = sz.height
            let yFor: (Double) -> CGFloat = { v in h - 5 - CGFloat(min(max(v / maxV, 0), 1)) * (h - 12) }

            var prevPath = Path()
            for (i, v) in prev.enumerated() {
                let pt = CGPoint(x: CGFloat(i) / CGFloat(max(prev.count - 1, 1)) * w, y: yFor(v))
                if i == 0 { prevPath.move(to: pt) } else { prevPath.addLine(to: pt) }
            }
            ctx.stroke(prevPath, with: .color(BevelColors.chartTrackSubtle), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))

            var line = Path()
            var fill = Path()
            for (i, v) in cur.enumerated() {
                let pt = CGPoint(x: CGFloat(i) / CGFloat(max(cur.count - 1, 1)) * w, y: yFor(v))
                if i == 0 {
                    line.move(to: pt)
                    fill.move(to: CGPoint(x: 0, y: h))
                    fill.addLine(to: pt)
                } else {
                    line.addLine(to: pt)
                    fill.addLine(to: pt)
                }
            }
            fill.addLine(to: CGPoint(x: w, y: h))
            fill.closeSubpath()
            ctx.fill(fill, with: .linearGradient(Gradient(colors: [accentEnd.opacity(0.22), .clear]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
            ctx.stroke(line, with: .linearGradient(Gradient(colors: [accentStart, accentEnd]), startPoint: .zero, endPoint: CGPoint(x: w, y: 0)), style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round))

            if let last = cur.last {
                let pt = CGPoint(x: w, y: yFor(last))
                ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 7, y: pt.y - 7, width: 14, height: 14)), with: .color(accentEnd.opacity(0.32)))
                ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 3.6, y: pt.y - 3.6, width: 7.2, height: 7.2)), with: .color(accentEnd))
            }
        }
        .frame(height: 44)
    }
}

struct MiniCardioFocusBars: View {
    let lowPct: Int
    let highPct: Int
    let anaeroPct: Int

    var body: some View {
        VStack(spacing: 6) {
            barRow(pct: lowPct, color: Color(hex: 0x7CECE2))
            barRow(pct: highPct, color: Color(hex: 0x5682FF))
            barRow(pct: anaeroPct, color: Color(hex: 0xA855F7))
        }
        .frame(height: 44)
    }

    private func barRow(pct: Int, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(BevelColors.cardSubtle)
                if pct > 0 {
                    Capsule().fill(color).frame(width: max(6, geo.size.width * CGFloat(min(pct, 100)) / 100.0))
                }
            }
        }
        .frame(height: 10)
    }
}

struct MiniHrZonesHistogram: View {
    let minutes6: [Int]

    var body: some View {
        let safe = (0..<6).map { $0 < minutes6.count ? minutes6[$0] : 0 }
        let maxM = max(safe.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(0..<6, id: \.self) { i in
                let v = safe[i]
                RoundedRectangle(cornerRadius: 3.5)
                    .fill(v > 0 ? HrZonesSixBarChart.zoneColors[i] : Color.white.opacity(0.08))
                    .frame(height: v > 0 ? max(CGFloat(v) / CGFloat(maxM) * 40, 5) : 3)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 44, alignment: .bottom)
    }
}

// MARK: - Anatomical Front & Back Muscle Map + Battery Freshness Meter (Screenshots 29-33)

struct AnatomicalMuscleMapCanvas: View {
    let snapshots: [MuscleGroupSnapshot]
    let filterState: MuscleFreshnessState?
    var compact: Bool = false

    private func fillColor(for muscle: MuscleGroupKind) -> Color {
        guard let snap = snapshots.first(where: { $0.muscle == muscle }) else {
            return Color(hex: 0x424650)
        }
        if let f = filterState, snap.state != f {
            return Color(hex: 0x353841)
        }
        switch snap.state {
        case .recovered: return Color(hex: 0x22C55E)
        case .fatigued: return Color(hex: 0xE89B1C)
        case .exhausted: return Color(hex: 0xEF4444)
        case .calibrating: return Color(hex: 0x484C57)
        }
    }

    var body: some View {
        HStack(spacing: compact ? 8 : 16) {
            frontSilhouette
            backSilhouette
        }
        .frame(height: compact ? 92 : 272)
    }

    private var frontSilhouette: some View {
        Canvas { ctx, sz in
            let w = sz.width
            let h = sz.height
            let cx = w * 0.5
            let base = Color(hex: 0x373A43)

            // Head & Neck
            ctx.fill(Path(ellipseIn: CGRect(x: cx - w * 0.11, y: h * 0.02, width: w * 0.22, height: h * 0.12)), with: .color(base))
            ctx.fill(Path(roundedRect: CGRect(x: cx - w * 0.055, y: h * 0.13, width: w * 0.11, height: h * 0.05), cornerRadius: 4), with: .color(fillColor(for: .cuello)))

            // Torso base silhouette
            ctx.fill(Path(roundedRect: CGRect(x: cx - w * 0.22, y: h * 0.18, width: w * 0.44, height: h * 0.34), cornerRadius: w * 0.10), with: .color(base))

            // Shoulders (Deltoids L/R)
            ctx.fill(Path(ellipseIn: CGRect(x: cx - w * 0.31, y: h * 0.18, width: w * 0.13, height: h * 0.10)), with: .color(fillColor(for: .hombros)))
            ctx.fill(Path(ellipseIn: CGRect(x: cx + w * 0.18, y: h * 0.18, width: w * 0.13, height: h * 0.10)), with: .color(fillColor(for: .hombros)))

            // Pectorals (L/R)
            ctx.fill(Path(roundedRect: CGRect(x: cx - w * 0.20, y: h * 0.20, width: w * 0.185, height: h * 0.10), cornerRadius: 8), with: .color(fillColor(for: .pectorales)))
            ctx.fill(Path(roundedRect: CGRect(x: cx + w * 0.015, y: h * 0.20, width: w * 0.185, height: h * 0.10), cornerRadius: 8), with: .color(fillColor(for: .pectorales)))

            // Biceps + Forearms (L/R)
            ctx.fill(Path(roundedRect: CGRect(x: cx - w * 0.33, y: h * 0.28, width: w * 0.09, height: h * 0.12), cornerRadius: 6), with: .color(fillColor(for: .biceps)))
            ctx.fill(Path(roundedRect: CGRect(x: cx + w * 0.24, y: h * 0.28, width: w * 0.09, height: h * 0.12), cornerRadius: 6), with: .color(fillColor(for: .biceps)))
            ctx.fill(Path(roundedRect: CGRect(x: cx - w * 0.36, y: h * 0.41, width: w * 0.08, height: h * 0.13), cornerRadius: 5), with: .color(fillColor(for: .antebrazo)))
            ctx.fill(Path(roundedRect: CGRect(x: cx + w * 0.28, y: h * 0.41, width: w * 0.08, height: h * 0.13), cornerRadius: 5), with: .color(fillColor(for: .antebrazo)))

            // Abs (3x2 grid) & Obliques
            let absCol = fillColor(for: .abdominales)
            for row in 0..<3 {
                let y = h * (0.31 + CGFloat(row) * 0.056)
                ctx.fill(Path(roundedRect: CGRect(x: cx - w * 0.095, y: y, width: w * 0.085, height: h * 0.046), cornerRadius: 4), with: .color(absCol))
                ctx.fill(Path(roundedRect: CGRect(x: cx + w * 0.010, y: y, width: w * 0.085, height: h * 0.046), cornerRadius: 4), with: .color(absCol))
            }
            ctx.fill(Path(roundedRect: CGRect(x: cx - w * 0.18, y: h * 0.32, width: w * 0.07, height: h * 0.14), cornerRadius: 5), with: .color(fillColor(for: .oblicuos)))
            ctx.fill(Path(roundedRect: CGRect(x: cx + w * 0.11, y: h * 0.32, width: w * 0.07, height: h * 0.14), cornerRadius: 5), with: .color(fillColor(for: .oblicuos)))

            // Hip flexors / pelvis
            ctx.fill(Path(roundedRect: CGRect(x: cx - w * 0.14, y: h * 0.48, width: w * 0.28, height: h * 0.07), cornerRadius: 6), with: .color(fillColor(for: .flexoresCadera)))

            // Quads + Adductors + Abductors (L/R)
            ctx.fill(Path(roundedRect: CGRect(x: cx - w * 0.21, y: h * 0.55, width: w * 0.16, height: h * 0.21), cornerRadius: 9), with: .color(fillColor(for: .cuadriceps)))
            ctx.fill(Path(roundedRect: CGRect(x: cx + w * 0.05, y: h * 0.55, width: w * 0.16, height: h * 0.21), cornerRadius: 9), with: .color(fillColor(for: .cuadriceps)))

            // Calves / Shins (L/R)
            ctx.fill(Path(roundedRect: CGRect(x: cx - w * 0.19, y: h * 0.78, width: w * 0.12, height: h * 0.18), cornerRadius: 7), with: .color(fillColor(for: .pantorrillas)))
            ctx.fill(Path(roundedRect: CGRect(x: cx + w * 0.07, y: h * 0.78, width: w * 0.12, height: h * 0.18), cornerRadius: 7), with: .color(fillColor(for: .pantorrillas)))
        }
        .frame(maxWidth: .infinity)
    }

    private var backSilhouette: some View {
        Canvas { ctx, sz in
            let w = sz.width
            let h = sz.height
            let cx = w * 0.5
            let base = Color(hex: 0x373A43)

            // Head & Neck
            ctx.fill(Path(ellipseIn: CGRect(x: cx - w * 0.11, y: h * 0.02, width: w * 0.22, height: h * 0.12)), with: .color(base))
            ctx.fill(Path(roundedRect: CGRect(x: cx - w * 0.06, y: h * 0.13, width: w * 0.12, height: h * 0.05), cornerRadius: 4), with: .color(fillColor(for: .cuello)))

            // Torso base
            ctx.fill(Path(roundedRect: CGRect(x: cx - w * 0.22, y: h * 0.18, width: w * 0.44, height: h * 0.34), cornerRadius: w * 0.10), with: .color(base))

            // Traps & Upper Back
            ctx.fill(Path(roundedRect: CGRect(x: cx - w * 0.14, y: h * 0.18, width: w * 0.28, height: h * 0.08), cornerRadius: 7), with: .color(fillColor(for: .trapecio)))
            ctx.fill(Path(roundedRect: CGRect(x: cx - w * 0.16, y: h * 0.25, width: w * 0.32, height: h * 0.07), cornerRadius: 6), with: .color(fillColor(for: .espaldaAlta)))

            // Rear Shoulders & Triceps
            ctx.fill(Path(ellipseIn: CGRect(x: cx - w * 0.31, y: h * 0.18, width: w * 0.13, height: h * 0.10)), with: .color(fillColor(for: .hombros)))
            ctx.fill(Path(ellipseIn: CGRect(x: cx + w * 0.18, y: h * 0.18, width: w * 0.13, height: h * 0.10)), with: .color(fillColor(for: .hombros)))
            ctx.fill(Path(roundedRect: CGRect(x: cx - w * 0.33, y: h * 0.28, width: w * 0.09, height: h * 0.13), cornerRadius: 6), with: .color(fillColor(for: .triceps)))
            ctx.fill(Path(roundedRect: CGRect(x: cx + w * 0.24, y: h * 0.28, width: w * 0.09, height: h * 0.13), cornerRadius: 6), with: .color(fillColor(for: .triceps)))
            ctx.fill(Path(roundedRect: CGRect(x: cx - w * 0.36, y: h * 0.42, width: w * 0.08, height: h * 0.12), cornerRadius: 5), with: .color(fillColor(for: .antebrazo)))
            ctx.fill(Path(roundedRect: CGRect(x: cx + w * 0.28, y: h * 0.42, width: w * 0.08, height: h * 0.12), cornerRadius: 5), with: .color(fillColor(for: .antebrazo)))

            // Lats (Dorsales) + Lower back (Lumbares)
            ctx.fill(Path(roundedRect: CGRect(x: cx - w * 0.21, y: h * 0.30, width: w * 0.18, height: h * 0.13), cornerRadius: 8), with: .color(fillColor(for: .dorsales)))
            ctx.fill(Path(roundedRect: CGRect(x: cx + w * 0.03, y: h * 0.30, width: w * 0.18, height: h * 0.13), cornerRadius: 8), with: .color(fillColor(for: .dorsales)))
            ctx.fill(Path(roundedRect: CGRect(x: cx - w * 0.10, y: h * 0.41, width: w * 0.20, height: h * 0.08), cornerRadius: 5), with: .color(fillColor(for: .lumbares)))

            // Glutes (L/R)
            ctx.fill(Path(ellipseIn: CGRect(x: cx - w * 0.20, y: h * 0.49, width: w * 0.19, height: h * 0.11)), with: .color(fillColor(for: .gluteos)))
            ctx.fill(Path(ellipseIn: CGRect(x: cx + w * 0.01, y: h * 0.49, width: w * 0.19, height: h * 0.11)), with: .color(fillColor(for: .gluteos)))

            // Hamstrings (L/R)
            ctx.fill(Path(roundedRect: CGRect(x: cx - w * 0.20, y: h * 0.60, width: w * 0.15, height: h * 0.17), cornerRadius: 8), with: .color(fillColor(for: .isquiotibiales)))
            ctx.fill(Path(roundedRect: CGRect(x: cx + w * 0.05, y: h * 0.60, width: w * 0.15, height: h * 0.17), cornerRadius: 8), with: .color(fillColor(for: .isquiotibiales)))

            // Calves (L/R)
            ctx.fill(Path(roundedRect: CGRect(x: cx - w * 0.19, y: h * 0.78, width: w * 0.12, height: h * 0.18), cornerRadius: 7), with: .color(fillColor(for: .pantorrillas)))
            ctx.fill(Path(roundedRect: CGRect(x: cx + w * 0.07, y: h * 0.78, width: w * 0.12, height: h * 0.18), cornerRadius: 7), with: .color(fillColor(for: .pantorrillas)))
        }
        .frame(maxWidth: .infinity)
    }
}

struct MuscleMiniThumbnailView: View {
    let muscle: MuscleGroupKind
    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .frame(width: 44, height: 44)
            Canvas { ctx, sz in
                let cx = sz.width / 2
                let cy = sz.height / 2
                let base = Color(hex: 0x4A4E59)
                switch muscle {
                case .abdominales, .oblicuos:
                    ctx.fill(Path(roundedRect: CGRect(x: cx - 10, y: cy - 13, width: 20, height: 26), cornerRadius: 6), with: .color(base))
                    ctx.fill(Path(roundedRect: CGRect(x: cx - 5, y: cy - 8, width: 10, height: 16), cornerRadius: 3), with: .color(color))
                case .pectorales:
                    ctx.fill(Path(roundedRect: CGRect(x: cx - 13, y: cy - 12, width: 26, height: 24), cornerRadius: 7), with: .color(base))
                    ctx.fill(Path(roundedRect: CGRect(x: cx - 10, y: cy - 8, width: 9, height: 9), cornerRadius: 3), with: .color(color))
                    ctx.fill(Path(roundedRect: CGRect(x: cx + 1, y: cy - 8, width: 9, height: 9), cornerRadius: 3), with: .color(color))
                case .dorsales, .espaldaAlta, .trapecio, .manguitoRotador, .lumbares:
                    ctx.fill(Path(roundedRect: CGRect(x: cx - 12, y: cy - 13, width: 24, height: 26), cornerRadius: 7), with: .color(base))
                    ctx.fill(Path(roundedRect: CGRect(x: cx - 9, y: cy - 6, width: 8, height: 12), cornerRadius: 3), with: .color(color))
                    ctx.fill(Path(roundedRect: CGRect(x: cx + 1, y: cy - 6, width: 8, height: 12), cornerRadius: 3), with: .color(color))
                case .hombros, .cuello:
                    ctx.fill(Path(roundedRect: CGRect(x: cx - 11, y: cy - 10, width: 22, height: 22), cornerRadius: 6), with: .color(base))
                    ctx.fill(Path(ellipseIn: CGRect(x: cx - 15, y: cy - 9, width: 8, height: 10)), with: .color(color))
                    ctx.fill(Path(ellipseIn: CGRect(x: cx + 7, y: cy - 9, width: 8, height: 10)), with: .color(color))
                case .triceps, .biceps, .antebrazo:
                    ctx.fill(Path(roundedRect: CGRect(x: cx - 6, y: cy - 14, width: 12, height: 28), cornerRadius: 6), with: .color(base))
                    ctx.fill(Path(roundedRect: CGRect(x: cx - 5, y: cy - 7, width: 10, height: 13), cornerRadius: 4), with: .color(color))
                case .gluteos, .flexoresCadera, .abductores, .aductores:
                    ctx.fill(Path(roundedRect: CGRect(x: cx - 12, y: cy - 11, width: 24, height: 22), cornerRadius: 7), with: .color(base))
                    ctx.fill(Path(ellipseIn: CGRect(x: cx - 10, y: cy - 6, width: 9, height: 12)), with: .color(color))
                    ctx.fill(Path(ellipseIn: CGRect(x: cx + 1, y: cy - 6, width: 9, height: 12)), with: .color(color))
                case .cuadriceps, .isquiotibiales, .pantorrillas:
                    ctx.fill(Path(roundedRect: CGRect(x: cx - 11, y: cy - 14, width: 9, height: 28), cornerRadius: 4), with: .color(base))
                    ctx.fill(Path(roundedRect: CGRect(x: cx + 2, y: cy - 14, width: 9, height: 28), cornerRadius: 4), with: .color(base))
                    ctx.fill(Path(roundedRect: CGRect(x: cx - 10, y: cy - 9, width: 7, height: 16), cornerRadius: 3), with: .color(color))
                    ctx.fill(Path(roundedRect: CGRect(x: cx + 3, y: cy - 9, width: 7, height: 16), cornerRadius: 3), with: .color(color))
                }
            }
            .frame(width: 40, height: 40)
        }
    }
}

struct MuscleBatteryBarsView: View {
    let filledBars: Int
    let color: Color
    let isCalibrating: Bool

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { idx in
                let lit = idx < filledBars
                let isTip = lit && idx == filledBars - 1
                Capsule()
                    .fill(
                        isCalibrating
                            ? (idx == 4 ? Color.white.opacity(0.45) : Color.white.opacity(0.18))
                            : (isTip ? color : (lit ? color.opacity(0.48) : Color.white.opacity(0.10)))
                    )
                    .frame(width: 8, height: 22)
            }
        }
    }
}

// MARK: - Editorial Resources Carousel (Screenshots 4, 6, 15, 18, 21, 24, 33)

struct FitnessResourceItem: Identifiable {
    let id: String
    let badgeIcon: String
    let heroTitle: String
    let heroSubtitle: String
    let cardTitle: String
    let cardDescription: String
    let gradientHexA: UInt64
    let gradientHexB: UInt64
    let fullGuideBody: String
}

struct FitnessResourceCarousel: View {
    let items: [FitnessResourceItem]
    @State private var activeGuide: FitnessResourceItem? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recursos")
                .font(ImprovingFont.sectionTitle(18))
                .foregroundColor(BevelColors.textPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items) { item in
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            activeGuide = item
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ZStack {
                                    LinearGradient(
                                        colors: [Color(hex: item.gradientHexA), Color(hex: item.gradientHexB)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                    RadialGradient(
                                        colors: [Color.white.opacity(0.18), .clear],
                                        center: .topTrailing,
                                        startRadius: 8,
                                        endRadius: 110
                                    )
                                    VStack(spacing: 5) {
                                        Image(systemName: item.badgeIcon)
                                            .font(.system(size: 20, weight: .semibold))
                                            .foregroundColor(.white.opacity(0.85))
                                        Text(item.heroTitle)
                                            .font(ImprovingFont.displayLarge(20))
                                            .foregroundColor(.white)
                                            .multilineTextAlignment(.center)
                                            .lineLimit(2)
                                        if !item.heroSubtitle.isEmpty {
                                            Text(item.heroSubtitle)
                                                .font(ImprovingFont.caption(12))
                                                .foregroundColor(.white.opacity(0.75))
                                        }
                                    }
                                    .padding(12)
                                }
                                .frame(width: 215, height: 122)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8)
                                )

                                Text(item.cardTitle)
                                    .font(ImprovingFont.cardTitle(14.5))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .lineLimit(1)

                                Text(item.cardDescription)
                                    .font(ImprovingFont.caption(12))
                                    .foregroundColor(BevelColors.textSecondary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(width: 215, alignment: .leading)
                        }
                    }
                }
            }
        }
        .sheet(item: $activeGuide) { g in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ZStack {
                            LinearGradient(
                                colors: [Color(hex: g.gradientHexA), Color(hex: g.gradientHexB)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            VStack(spacing: 6) {
                                Image(systemName: g.badgeIcon).font(.system(size: 28)).foregroundColor(.white)
                                Text(g.heroTitle).font(ImprovingFont.displayLarge(24)).foregroundColor(.white)
                                Text(g.heroSubtitle).font(ImprovingFont.caption(13)).foregroundColor(.white.opacity(0.8))
                            }
                        }
                        .frame(height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                        Text(g.cardTitle)
                            .font(ImprovingFont.sectionTitle(19))
                            .foregroundColor(BevelColors.textPrimary)

                        Text(g.fullGuideBody)
                            .font(ImprovingFont.body(14.5))
                            .foregroundColor(BevelColors.textSecondary)
                            .lineSpacing(4)
                    }
                    .padding(18)
                }
                .background(BevelColors.canvas)
                .navigationTitle("Guía de rendimiento")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Cerrar") { activeGuide = nil }
                    }
                }
            }
        }
    }
}

import SwiftUI

// MARK: - Interactive Baseline Chart with Scrubbing & Animated Step-by-Step Readout

struct HealthMetricBaselineChart: View {
    let points: [Double]
    let dates: [String]
    let bandLow: Double
    let bandHigh: Double
    let averageText: String
    let accentColor: Color
    let valueFormatter: (Double) -> String
    let onPointSelected: (Int?, Double?, String?) -> Void

    @State private var selectedIdx: Int? = nil
    @State private var animatedDisplayVal: Double = 0

    var body: some View {
        let safePoints = points.count >= 2 ? points : [bandLow, bandHigh]
        let minVal = min(safePoints.min() ?? bandLow, bandLow)
        let maxVal = max(safePoints.max() ?? bandHigh, bandHigh)
        let span = max(maxVal - minVal, 1.0)
        let chartMin = minVal - span * 0.2
        let chartMax = maxVal + span * 0.2
        let chartSpan = max(chartMax - chartMin, 1.0)
        let avgVal = safePoints.reduce(0, +) / Double(safePoints.count)

        VStack(spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let stepX = w / CGFloat(max(safePoints.count - 1, 1))
                let yFor: (Double) -> CGFloat = { v in
                    h * (1.0 - CGFloat(min(max((v - chartMin) / chartSpan, 0), 1)))
                }

                ZStack(alignment: .topLeading) {
                    Canvas { ctx, size in
                        // Subtle horizontal grid
                        for frac in [0.15, 0.4, 0.65, 0.9] {
                            let y = size.height * frac
                            var gPath = Path()
                            gPath.move(to: CGPoint(x: 0, y: y))
                            gPath.addLine(to: CGPoint(x: size.width, y: y))
                            ctx.stroke(gPath, with: .color(BevelColors.trackGroove), lineWidth: 1)
                        }

                        // Normal range envelope band
                        let bandTop = yFor(bandHigh)
                        let bandBot = yFor(bandLow)
                        let bandRect = CGRect(x: 0, y: bandTop, width: size.width, height: max(bandBot - bandTop, 4))
                        ctx.fill(Path(bandRect), with: .color(accentColor.opacity(0.14)))

                        // Dotted average line
                        let avgY = yFor(avgVal)
                        var avgPath = Path()
                        avgPath.move(to: CGPoint(x: 0, y: avgY))
                        avgPath.addLine(to: CGPoint(x: size.width, y: avgY))
                        ctx.stroke(avgPath, with: .color(accentColor.opacity(selectedIdx == nil ? 0.7 : 0.25)), style: StrokeStyle(lineWidth: 1.4, dash: [5, 5]))

                        // Main line
                        var linePath = Path()
                        for (idx, v) in safePoints.enumerated() {
                            let pt = CGPoint(x: CGFloat(idx) * stepX, y: yFor(v))
                            if idx == 0 { linePath.move(to: pt) } else { linePath.addLine(to: pt) }
                        }
                        ctx.stroke(linePath, with: .color(accentColor), style: StrokeStyle(lineWidth: 2.3, lineCap: .round, lineJoin: .round))

                        // Nodes
                        for (idx, v) in safePoints.enumerated() {
                            let pt = CGPoint(x: CGFloat(idx) * stepX, y: yFor(v))
                            let r: CGFloat = (idx == selectedIdx) ? 6 : 3.5
                            let rect = CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)
                            ctx.fill(Path(ellipseIn: rect), with: .color(.white))
                            ctx.stroke(Path(ellipseIn: rect), with: .color(accentColor), lineWidth: idx == selectedIdx ? 2.6 : 1.7)
                        }

                        // Scrub guideline
                        if let sel = selectedIdx {
                            let sx = CGFloat(sel) * stepX
                            var vPath = Path()
                            vPath.move(to: CGPoint(x: sx, y: 0))
                            vPath.addLine(to: CGPoint(x: sx, y: size.height))
                            ctx.stroke(vPath, with: .color(BevelColors.textPrimary.opacity(0.3)), style: StrokeStyle(lineWidth: 1.3, dash: [5, 4]))
                        }
                    }

                    // Average pill or animated scrub tooltip pill
                    if selectedIdx == nil {
                        Text(averageText)
                            .font(ImprovingFont.caption(11.5))
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(accentColor))
                            .position(x: w / 2, y: min(max(yFor(avgVal), 16), h - 16))
                    } else if let sel = selectedIdx {
                        let dateStr = (sel < dates.count) ? "\(dates[sel]) · " : ""
                        let pillX = min(max(CGFloat(sel) * stepX, 62), w - 62)
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
            .frame(height: 168)

            if !dates.isEmpty {
                HStack {
                    Text(dates.first ?? "")
                    Spacer()
                    if dates.count > 2 {
                        Text(dates[dates.count / 2])
                        Spacer()
                    }
                    Text(dates.last ?? "")
                }
                .font(ImprovingFont.caption(10.5))
                .foregroundColor(BevelColors.textMuted)
            }
        }
        .onAppear {
            animatedDisplayVal = safePoints.last ?? 0
        }
    }
}

// MARK: - Stress & Energy 24h Timelines (Animated Scrub Value)

struct Timeline24hChart: View {
    let points: [Double]
    let isEnergy: Bool

    @State private var selectedIdx: Int? = nil
    @State private var animatedVal: Double = 0

    var body: some View {
        let safePts = points.count >= 2 ? points : [20, 28, 34, 42, 31, 25]
        VStack(spacing: 4) {
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
                            ctx.stroke(gp, with: .color(BevelColors.trackGroove), lineWidth: 1)
                        }

                        // Sleep zone highlight (0:45 .. 08:30)
                        let sRect = CGRect(x: size.width * 0.04, y: 0, width: size.width * 0.32, height: size.height)
                        ctx.fill(Path(sRect), with: .color(BevelColors.indigoSoftBg.opacity(0.72)))

                        for i in 0..<(safePts.count - 1) {
                            let avg = (safePts[i] + safePts[i + 1]) / 2.0
                            let segColor: Color
                            if isEnergy {
                                segColor = avg >= 55 ? BevelColors.greenPrimary : (avg >= 32 ? BevelColors.amberStart : BevelColors.orangeEnd)
                            } else {
                                segColor = avg < 25 ? BevelColors.tealLow : (avg < 45 ? BevelColors.greenPrimary : (avg < 70 ? BevelColors.amberStart : BevelColors.coralHigh))
                            }
                            var seg = Path()
                            seg.move(to: CGPoint(x: CGFloat(i) * stepX, y: yFor(safePts[i])))
                            seg.addLine(to: CGPoint(x: CGFloat(i + 1) * stepX, y: yFor(safePts[i + 1])))
                            ctx.stroke(seg, with: .color(segColor), style: StrokeStyle(lineWidth: 2.3, lineCap: .round))
                        }

                        if let sel = selectedIdx {
                            let sx = CGFloat(sel) * stepX
                            let sy = yFor(safePts[sel])
                            var vp = Path()
                            vp.move(to: CGPoint(x: sx, y: 0))
                            vp.addLine(to: CGPoint(x: sx, y: size.height))
                            ctx.stroke(vp, with: .color(BevelColors.textPrimary.opacity(0.3)), style: StrokeStyle(lineWidth: 1.3, dash: [5, 4]))
                            let r: CGFloat = 5.5
                            ctx.fill(Path(ellipseIn: CGRect(x: sx - r, y: sy - r, width: r * 2, height: r * 2)), with: .color(.white))
                        }
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
            .frame(height: 146)

            HStack {
                Text("0:00"); Spacer(); Text("6:00"); Spacer(); Text("12:00"); Spacer(); Text("18:00")
            }
            .font(ImprovingFont.caption(10.5))
            .foregroundColor(BevelColors.textMuted)
        }
    }
}

// MARK: - Sleep Hypnogram & 42-Day Consistency Heatmap

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
                        case 1: Color(hex: 0xBBF7D0)
                        case 2: Color(hex: 0x4ADE80)
                        default: BevelColors.emeraldEnd
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

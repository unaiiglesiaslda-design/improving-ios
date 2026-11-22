import SwiftUI

// MARK: - Interactive Baseline Chart with Rolling Band, Hollow Nodes & Animated Scrub Readout

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
                                ctx.stroke(gPath, with: .color(BevelColors.trackGroove), lineWidth: 1)
                            }

                            // Shaded rolling envelope band
                            let halfBand = max((bandHigh - bandLow) * 0.48, chartSpan * 0.14)
                            var bandPath = Path()
                            for (idx, v) in safePoints.enumerated() {
                                let pt = CGPoint(x: CGFloat(idx) * stepX, y: yFor(v + halfBand))
                                if idx == 0 { bandPath.move(to: pt) } else { bandPath.addLine(to: pt) }
                            }
                            for (idx, v) in safePoints.enumerated().reversed() {
                                bandPath.addLine(to: CGPoint(x: CGFloat(idx) * stepX, y: yFor(v - halfBand)))
                            }
                            bandPath.closeSubpath()
                            ctx.fill(bandPath, with: .color(BevelColors.greenPrimary.opacity(0.16)))

                            // Dotted average line
                            let avgY = yFor(avgVal)
                            var avgPath = Path()
                            avgPath.move(to: CGPoint(x: 0, y: avgY))
                            avgPath.addLine(to: CGPoint(x: size.width, y: avgY))
                            ctx.stroke(avgPath, with: .color(accentColor.opacity(selectedIdx == nil ? 0.7 : 0.22)), style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))

                            if let sel = selectedIdx {
                                let sx = CGFloat(sel) * stepX
                                var vPath = Path()
                                vPath.move(to: CGPoint(x: sx, y: 0))
                                vPath.addLine(to: CGPoint(x: sx, y: size.height))
                                ctx.stroke(vPath, with: .color(BevelColors.textPrimary.opacity(0.28)), style: StrokeStyle(lineWidth: 1.4, dash: [6, 5]))
                            }

                            // Main curve
                            var linePath = Path()
                            for (idx, v) in safePoints.enumerated() {
                                let pt = CGPoint(x: CGFloat(idx) * stepX, y: yFor(v))
                                if idx == 0 { linePath.move(to: pt) } else { linePath.addLine(to: pt) }
                            }
                            ctx.stroke(linePath, with: .color(accentColor), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

                            // Hollow nodes + highlighted last/selected node
                            for (idx, v) in safePoints.enumerated() {
                                let pt = CGPoint(x: CGFloat(idx) * stepX, y: yFor(v))
                                if idx == selectedIdx {
                                    ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 11, y: pt.y - 11, width: 22, height: 22)), with: .color(accentColor.opacity(0.25)))
                                    ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 6, y: pt.y - 6, width: 12, height: 12)), with: .color(.white))
                                    ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 4, y: pt.y - 4, width: 8, height: 8)), with: .color(accentColor))
                                } else if selectedIdx == nil && idx == safePoints.count - 1 {
                                    ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 8, y: pt.y - 8, width: 16, height: 16)), with: .color(BevelColors.greenPrimary.opacity(0.28)))
                                    ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 4.5, y: pt.y - 4.5, width: 9, height: 9)), with: .color(accentColor))
                                    ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 2, y: pt.y - 2, width: 4, height: 4)), with: .color(.white))
                                } else {
                                    let rect = CGRect(x: pt.x - 3.8, y: pt.y - 3.8, width: 7.6, height: 7.6)
                                    ctx.fill(Path(ellipseIn: rect), with: .color(.white))
                                    ctx.stroke(Path(ellipseIn: rect), with: .color(accentColor), lineWidth: 1.8)
                                }
                            }
                        }

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
                .frame(height: 168)

                // Right Y-axis ticks matching Android screenshot
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
                .foregroundColor(BevelColors.textSecondary)
                .frame(height: 158)
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
                .foregroundColor(BevelColors.textSecondary)
                .padding(.trailing, 34)
            }
        }
        .onAppear {
            animatedDisplayVal = safePoints.last ?? 0
        }
    }
}

// MARK: - Trend Sparkline with Normal Band (Esfuerzo, Recuperación, Sueño & Análisis de tendencias)

struct TrendSparklineWithBand: View {
    let points: [Double]
    var bandLow: Double = 40
    var bandHigh: Double = 80
    let lineColor: Color
    var fillUnder: Bool = true

    var body: some View {
        let safe = points.count >= 2 ? points : [bandLow, bandHigh]
        let minV = min(safe.min() ?? 0, bandLow)
        let maxV = max(safe.max() ?? 1, bandHigh)
        let span = max(maxV - minV, 1)

        Canvas { ctx, size in
            let stepX = size.width / CGFloat(max(safe.count - 1, 1))
            let yFor: (Double) -> CGFloat = { v in
                size.height - 3 - CGFloat((v - minV) / span) * (size.height - 6)
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
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.closeSubpath()
            if fillUnder {
                ctx.fill(fill, with: .linearGradient(Gradient(colors: [lineColor.opacity(0.24), .clear]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            }
            ctx.stroke(line, with: .color(lineColor), style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Biological Age 54-Tick Curved Arc Dial (1:1 Android BioAgeCurvedDial)

struct BioAgeCurvedDial: View {
    let bioAgeYears: Double
    let chronoAgeYears: Double
    let diffYears: Double
    let sampledDays: Int

    var body: some View {
        let lowerBound = chronoAgeYears - 8.0
        let upperBound = chronoAgeYears + 8.0
        let span = max(upperBound - lowerBound, 1.0)
        let isYounger = bioAgeYears <= chronoAgeYears
        let accent = isYounger ? Color(hex: 0x0D9488) : Color(hex: 0xD97706)

        VStack(spacing: 4) {
            ZStack {
                Canvas { ctx, size in
                    let center = CGPoint(x: size.width / 2, y: size.height * 0.42)
                    let radius = min(size.width * 0.41, size.height * 0.48)
                    let startAngle = 15.0
                    let sweep = 150.0
                    let tickCount = 54

                    for i in 0...tickCount {
                        let t = Double(i) / Double(tickCount)
                        let deg = startAngle + t * sweep
                        let rad = deg * .pi / 180.0
                        let rIn = radius * 0.88
                        let rOut = radius * 0.96
                        var line = Path()
                        line.move(to: CGPoint(x: center.x + cos(rad) * rIn, y: center.y + sin(rad) * rIn))
                        line.addLine(to: CGPoint(x: center.x + cos(rad) * rOut, y: center.y + sin(rad) * rOut))
                        ctx.stroke(line, with: .color(BevelColors.trackInnerShadow), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    }

                    let chronoFrac = min(max((chronoAgeYears - lowerBound) / span, 0.05), 0.95)
                    let bioFrac = min(max((bioAgeYears - lowerBound) / span, 0.05), 0.95)
                    let chronoDeg = (startAngle + sweep) - chronoFrac * sweep
                    let bioDeg = (startAngle + sweep) - bioFrac * sweep

                    var bridge = Path()
                    bridge.addArc(center: center, radius: radius * 0.92, startAngle: .degrees(min(chronoDeg, bioDeg)), endAngle: .degrees(max(chronoDeg, bioDeg)), clockwise: false)
                    ctx.stroke(bridge, with: .color(accent.opacity(0.32)), style: StrokeStyle(lineWidth: 10, lineCap: .round))

                    let cRad = chronoDeg * .pi / 180.0
                    let cPt = CGPoint(x: center.x + cos(cRad) * radius * 0.92, y: center.y + sin(cRad) * radius * 0.92)
                    ctx.fill(Path(ellipseIn: CGRect(x: cPt.x - 3.5, y: cPt.y - 3.5, width: 7, height: 7)), with: .color(BevelColors.textSecondary))

                    let bRad = bioDeg * .pi / 180.0
                    let bPt = CGPoint(x: center.x + cos(bRad) * radius * 0.92, y: center.y + sin(bRad) * radius * 0.92)
                    let bRect = CGRect(x: bPt.x - 7, y: bPt.y - 7, width: 14, height: 14)
                    ctx.fill(Path(ellipseIn: bRect), with: .color(.white))
                    ctx.stroke(Path(ellipseIn: bRect), with: .color(accent), lineWidth: 3)
                }
                .frame(height: 204)

                VStack(spacing: 4) {
                    Text(String(format: "%.1f", locale: Locale(identifier: "es_ES"), bioAgeYears))
                        .font(ImprovingFont.displayLarge(42))
                        .monospacedDigit()
                        .foregroundColor(BevelColors.textPrimary)
                    Text(String(format: "%.1f años más joven", locale: Locale(identifier: "es_ES"), abs(diffYears)))
                        .font(ImprovingFont.cardTitle(14))
                        .foregroundColor(BevelColors.emeraldEnd)
                    Text("−0,2 desde la semana pasada")
                        .font(ImprovingFont.caption(11.5))
                        .foregroundColor(BevelColors.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(BevelColors.card))
                        .overlay(Capsule().strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
                        .padding(.top, 2)
                }
                .offset(y: -14)
            }
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
                                ctx.stroke(gp, with: .color(BevelColors.trackGroove), lineWidth: 1)
                            }

                            let sRect = CGRect(x: size.width * 0.04, y: 0, width: size.width * 0.32, height: size.height)
                            ctx.fill(Path(sRect), with: .color(BevelColors.indigoSoftBg.opacity(0.72)))

                            var topBar = Path()
                            topBar.move(to: CGPoint(x: size.width * 0.04, y: 1.5))
                            topBar.addLine(to: CGPoint(x: size.width * 0.36, y: 1.5))
                            ctx.stroke(topBar, with: .color(BevelColors.periwinkleStart), style: StrokeStyle(lineWidth: 3, lineCap: .round))

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

                VStack(alignment: .trailing) {
                    Text("100"); Spacer(); Text("75"); Spacer(); Text("50"); Spacer(); Text("25"); Spacer(); Text("0")
                }
                .font(ImprovingFont.caption(10))
                .foregroundColor(BevelColors.textSecondary)
                .frame(height: 140)
            }

            HStack {
                Text("0:00"); Spacer(); Text("6:00"); Spacer(); Text("12:00"); Spacer(); Text("18:00")
            }
            .font(ImprovingFont.caption(10.5))
            .foregroundColor(BevelColors.textSecondary)
            .padding(.trailing, 24)
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

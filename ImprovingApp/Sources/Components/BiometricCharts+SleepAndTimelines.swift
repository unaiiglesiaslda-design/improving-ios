import SwiftUI

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
            .background(RoundedRectangle(cornerRadius: 16).fill(BevelColors.chartTrackSubtle.opacity(0.45)))
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
                                    ctx.stroke(gp, with: .color(BevelColors.chartGridLine), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
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

// MARK: - 4-Row Step Sleep Hypnogram Chart (Literal Match to Screenshot 4: Vigilia / REM / Central / Profundo)

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
                ctx.stroke(line, with: .color(BevelColors.chartGridLine), lineWidth: 1)
            }
            // Subtle outer frame
            ctx.stroke(Path(CGRect(origin: .zero, size: size)), with: .color(BevelColors.chartGridLine), lineWidth: 1)

            // Draw connecting vertical transitions first (guarded against empty/single-element stages!)
            if stages.count >= 2 {
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
            .background(RoundedRectangle(cornerRadius: 14).fill(BevelColors.chartTrackSubtle.opacity(0.45)))
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
                                    ctx.stroke(gp, with: .color(BevelColors.chartGridLine), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
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
                                    ctx.stroke(v, with: .color(BevelColors.chartAxisStroke), style: StrokeStyle(lineWidth: 1.3, dash: [4, 4]))
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
                        .background(Capsule().fill(BevelColors.cardSubtle))
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
                        .background(Capsule().fill(BevelColors.cardSubtle))
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

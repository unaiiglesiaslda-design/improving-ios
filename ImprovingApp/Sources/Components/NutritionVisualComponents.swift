import SwiftUI

// MARK: - Bevel Exact Nutrition Palette Constants

enum NutritionPalette {
    static let fatBlue = Color(hex: 0x7A9BF8)
    static let carbsAmber = Color(hex: 0xF5A623)
    static let proteinPink = Color(hex: 0xE85D8A)
    static let scoreLavender = Color(hex: 0x8BA0FF)
    static let scoreViolet = Color(hex: 0xB88CFF)
    static let positiveMint = Color(hex: 0x4CE2A7)
    static let negativeOrange = Color(hex: 0xF58A2A)
    static let burnedOrange = Color(hex: 0xF26D3D)
    static let consumedBlue = Color(hex: 0x7C93F8)
}

// MARK: - 1. Radial Tick-Mark Ceramic Plate Gauge (Matches Screenshots 1 & 2)

struct NutritionPlateTickGauge: View {
    let score: Int?
    let statusLabel: String
    let statusColor: Color
    var diameter: CGFloat = 178
    var showZeroHundredLabels: Bool = true
    var tickCount: Int = 46

    var body: some View {
        let clampedFrac: Double = score.map { min(max(Double($0) / 100.0, 0.0), 1.0) } ?? 0.0
        let activeTicks = score != nil ? max(1, Int((clampedFrac * Double(tickCount)).rounded())) : 0
        let startAngleDeg = 132.0
        let sweepDeg = 276.0

        ZStack {
            // Subtle outer bevel dish shadow & rim
            Circle()
                .fill(
                    RadialGradient(
                        colors: BevelColors.isDarkMode
                            ? [Color(hex: 0x262936), Color(hex: 0x1D202A), Color(hex: 0x272A35)]
                            : [Color(hex: 0xFFFFFF), Color(hex: 0xEEF1F6), Color(hex: 0xE4E9F2)],
                        center: .center,
                        startRadius: diameter * 0.10,
                        endRadius: diameter * 0.50
                    )
                )
                .frame(width: diameter, height: diameter)
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(BevelColors.isDarkMode ? 0.14 : 0.7), Color.black.opacity(0.28)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.1
                        )
                )
                .shadow(color: Color.black.opacity(BevelColors.isDarkMode ? 0.42 : 0.10), radius: 14, y: 7)

            // Recessed inner circular plate center
            Circle()
                .fill(
                    RadialGradient(
                        colors: BevelColors.isDarkMode
                            ? [Color(hex: 0x2C303D), Color(hex: 0x1E212B)]
                            : [Color.white, Color(hex: 0xF3F5F9)],
                        center: .top,
                        startRadius: 2,
                        endRadius: diameter * 0.36
                    )
                )
                .frame(width: diameter * 0.68, height: diameter * 0.68)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(BevelColors.isDarkMode ? 0.06 : 0.7), lineWidth: 0.8)
                )

            // 46 Radial Tick Marks around the ceramic rim
            Canvas { ctx, sz in
                let center = CGPoint(x: sz.width / 2, y: sz.height / 2)
                let outerR = diameter * 0.445
                let innerR = diameter * 0.368
                let tickW = max(diameter * 0.013, 1.5)

                for i in 0..<tickCount {
                    let frac = Double(i) / Double(max(tickCount - 1, 1))
                    let deg = startAngleDeg + sweepDeg * frac
                    let rad = deg * .pi / 180.0
                    let p1 = CGPoint(x: center.x + innerR * CGFloat(cos(rad)), y: center.y + innerR * CGFloat(sin(rad)))
                    let p2 = CGPoint(x: center.x + outerR * CGFloat(cos(rad)), y: center.y + outerR * CGFloat(sin(rad)))

                    var path = Path()
                    path.move(to: p1)
                    path.addLine(to: p2)

                    let isActive = i < activeTicks
                    let color: Color
                    if isActive {
                        if let s = score, s >= 78 {
                            color = frac < 0.5 ? NutritionPalette.scoreLavender : NutritionPalette.positiveMint
                        } else if let s = score, s >= 55 {
                            color = frac < 0.4 ? NutritionPalette.scoreViolet : NutritionPalette.fatBlue
                        } else {
                            color = frac < 0.45 ? Color(hex: 0xD28EF7) : NutritionPalette.scoreLavender
                        }
                        // Soft bloom behind illuminated tick
                        ctx.stroke(path, with: .color(color.opacity(0.32)), style: StrokeStyle(lineWidth: tickW * 2.6, lineCap: .round))
                        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: tickW, lineCap: .round))
                    } else {
                        ctx.stroke(
                            path,
                            with: .color(BevelColors.isDarkMode ? Color.white.opacity(0.14) : Color.black.opacity(0.12)),
                            style: StrokeStyle(lineWidth: tickW, lineCap: .round)
                        )
                    }
                }
            }
            .frame(width: diameter, height: diameter)

            // Center Score + Status
            VStack(spacing: diameter > 130 ? 3 : 1) {
                Text(score.map { "\($0)" } ?? "--")
                    .font(.system(size: diameter * 0.255, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(BevelColors.textPrimary)
                Text(statusLabel)
                    .font(.system(size: diameter * 0.088, weight: .semibold, design: .rounded))
                    .foregroundColor(statusColor)
                    .lineLimit(1)
            }

            // 0 and 100 Bottom Arc Labels (Screenshot 2)
            if showZeroHundredLabels {
                HStack {
                    Text("0")
                        .font(ImprovingFont.caption(11.5))
                        .monospacedDigit()
                        .foregroundColor(BevelColors.textMuted)
                    Spacer()
                    Text("100")
                        .font(ImprovingFont.caption(11.5))
                        .monospacedDigit()
                        .foregroundColor(BevelColors.textMuted)
                }
                .frame(width: diameter * 0.52)
                .offset(y: diameter * 0.355)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

// MARK: - 2. Hero Plate Flanked by Sleek Fork & Knife (Matches Screenshot 2)

struct NutritionHeroPlateWithCutlery: View {
    let score: Int?
    let statusLabel: String
    let statusColor: Color

    var body: some View {
        HStack(spacing: 24) {
            ForkCutlerySilhouette()
                .frame(width: 22, height: 118)

            NutritionPlateTickGauge(
                score: score,
                statusLabel: statusLabel,
                statusColor: statusColor,
                diameter: 184,
                showZeroHundredLabels: true,
                tickCount: 48
            )

            KnifeCutlerySilhouette()
                .frame(width: 18, height: 118)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

private struct ForkCutlerySilhouette: View {
    var body: some View {
        Canvas { ctx, sz in
            let grad = Gradient(colors: [
                Color.white.opacity(BevelColors.isDarkMode ? 0.30 : 0.24),
                Color.white.opacity(BevelColors.isDarkMode ? 0.18 : 0.14),
                Color.white.opacity(BevelColors.isDarkMode ? 0.24 : 0.18)
            ])
            let fill = GraphicsContext.Shading.linearGradient(grad, startPoint: .zero, endPoint: CGPoint(x: 0, y: sz.height))

            // 4 fork tines
            let tineW: CGFloat = 2.1
            let tineH: CGFloat = sz.height * 0.28
            let xs: [CGFloat] = [2, 7.2, 12.4, 17.6]
            for x in xs {
                let r = CGRect(x: x, y: 2, width: tineW, height: tineH)
                ctx.fill(Path(roundedRect: r, cornerRadius: 1.1), with: fill)
            }

            // Fork neck bowl
            var neck = Path()
            neck.move(to: CGPoint(x: 2, y: tineH))
            neck.addLine(to: CGPoint(x: 19.7, y: tineH))
            neck.addQuadCurve(to: CGPoint(x: 13.6, y: tineH + 14), control: CGPoint(x: 19.7, y: tineH + 11))
            neck.addLine(to: CGPoint(x: 8.1, y: tineH + 14))
            neck.addQuadCurve(to: CGPoint(x: 2, y: tineH), control: CGPoint(x: 2, y: tineH + 11))
            neck.closeSubpath()
            ctx.fill(neck, with: fill)

            // Slim tapered handle
            let handleRect = CGRect(x: 8.4, y: tineH + 11, width: 5.0, height: sz.height - tineH - 13)
            ctx.fill(Path(roundedRect: handleRect, cornerRadius: 2.5), with: fill)
        }
    }
}

private struct KnifeCutlerySilhouette: View {
    var body: some View {
        Canvas { ctx, sz in
            let grad = Gradient(colors: [
                Color.white.opacity(BevelColors.isDarkMode ? 0.30 : 0.24),
                Color.white.opacity(BevelColors.isDarkMode ? 0.18 : 0.14),
                Color.white.opacity(BevelColors.isDarkMode ? 0.24 : 0.18)
            ])
            let fill = GraphicsContext.Shading.linearGradient(grad, startPoint: .zero, endPoint: CGPoint(x: 0, y: sz.height))

            // Knife blade curving gently to top tip
            var blade = Path()
            blade.move(to: CGPoint(x: 12.5, y: 3))
            blade.addQuadCurve(to: CGPoint(x: 4.5, y: sz.height * 0.26), control: CGPoint(x: 4.5, y: 12))
            blade.addLine(to: CGPoint(x: 4.5, y: sz.height * 0.52))
            blade.addQuadCurve(to: CGPoint(x: 8.5, y: sz.height * 0.56), control: CGPoint(x: 4.8, y: sz.height * 0.55))
            blade.addLine(to: CGPoint(x: 12.8, y: sz.height * 0.56))
            blade.addLine(to: CGPoint(x: 12.8, y: 3))
            blade.closeSubpath()
            ctx.fill(blade, with: fill)

            // Handle
            let handle = CGRect(x: 7.4, y: sz.height * 0.53, width: 5.4, height: sz.height * 0.45)
            ctx.fill(Path(roundedRect: handle, cornerRadius: 2.7), with: fill)
        }
    }
}

// MARK: - 3. Glowing Dot-Matrix Macro Grid (Matches Screenshots 1 & 3!)

struct MacroDotMatrixGrid: View {
    let fraction: Double // 0...1
    let color: Color
    var columns: Int = 8
    var rows: Int = 7
    var dotSize: CGFloat = 6.2
    var spacing: CGFloat = 4.2

    var body: some View {
        let totalDots = columns * rows
        let filledCount = fraction > 0.005 ? max(1, min(totalDots, Int((min(max(fraction, 0), 1) * Double(totalDots)).rounded()))) : 0

        VStack(spacing: spacing) {
            ForEach(0..<rows, id: \.self) { visualRow in
                // Fill bottom-up! Bottom row = index 0, top row = rows - 1
                let bottomUpRow = (rows - 1) - visualRow
                HStack(spacing: spacing) {
                    ForEach(0..<columns, id: \.self) { col in
                        let idx = bottomUpRow * columns + col
                        let isLit = idx < filledCount
                        Circle()
                            .fill(isLit ? color : color.opacity(BevelColors.isDarkMode ? 0.14 : 0.18))
                            .frame(width: dotSize, height: dotSize)
                            .shadow(color: isLit ? color.opacity(0.65) : .clear, radius: isLit ? 2.6 : 0)
                    }
                }
            }
        }
    }
}

// MARK: - 4. Bipolar Luminous Net Energy Bar (Matches Screenshot 3!)

struct NetEnergyBipolarBar: View {
    let netKcal: Int

    private func formatAxisVal(_ v: Int) -> String {
        let absV = abs(v)
        let sign = v < 0 ? "-" : ""
        if absV == 0 { return "0" }
        if absV >= 1000 {
            let k = Double(absV) / 1000.0
            let s = String(format: "%.1fK", locale: Locale(identifier: "es_ES"), k)
                .replacingOccurrences(of: ",0K", with: "K")
            return "\(sign)\(s)"
        }
        return "\(sign)\(absV)"
    }

    var body: some View {
        let cap = max(1300, Int((Double(max(abs(netKcal), 650)) / 500.0).rounded(.up) * 500.0))
        let halfCap = cap / 2
        let normPos = min(max((Double(netKcal) + Double(cap)) / Double(cap * 2), 0.03), 0.97)
        let labels = [-cap, -halfCap, 0, halfCap, cap]

        VStack(spacing: 8) {
            GeometryReader { geo in
                let w = geo.size.width
                let markerX = w * CGFloat(normPos)

                ZStack(alignment: .leading) {
                    // Subtle glow under bar
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: 0xEF4444).opacity(0.35),
                                    Color(hex: 0xF59E0B).opacity(0.28),
                                    Color.white.opacity(0.28),
                                    Color(hex: 0x7C93F8).opacity(0.32),
                                    Color(hex: 0x6366F1).opacity(0.38)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 14)
                        .blur(radius: 5)

                    // Crisp main gradient track
                    Capsule()
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: Color(hex: 0xEF4444), location: 0.00),
                                    .init(color: Color(hex: 0xF97316), location: 0.18),
                                    .init(color: Color(hex: 0xF5B942), location: 0.36),
                                    .init(color: Color(hex: 0xF3F6FF), location: 0.50),
                                    .init(color: Color(hex: 0xA8B8FF), location: 0.66),
                                    .init(color: Color(hex: 0x7083FA), location: 0.85),
                                    .init(color: Color(hex: 0x616AF2), location: 1.00)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 11)

                    // Dark hollow indicator ring positioned at exact Net Energy value
                    Circle()
                        .strokeBorder(Color(hex: 0x161820), lineWidth: 3.0)
                        .background(Circle().fill(Color.clear))
                        .frame(width: 15, height: 15)
                        .shadow(color: Color.black.opacity(0.35), radius: 2)
                        .offset(x: min(max(markerX - 7.5, 2), w - 17))
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 22)

            // Axis Ticks + Labels (-1,3K  -650  0  650  1,3K)
            HStack {
                ForEach(Array(labels.enumerated()), id: \.offset) { idx, val in
                    VStack(spacing: 4) {
                        Rectangle()
                            .fill(Color.white.opacity(0.14))
                            .frame(width: 1, height: 5)
                        Text(formatAxisVal(val))
                            .font(ImprovingFont.caption(11))
                            .monospacedDigit()
                            .foregroundColor(BevelColors.textMuted)
                    }
                    if idx < labels.count - 1 { Spacer() }
                }
            }
        }
    }
}

// MARK: - 5. Food Quality Contributor Row (Matches Screenshots 4 & 5!)

struct FoodQualityFactorRow: View {
    let kind: FoodQualityFactorKind
    let value: Double
    let onTap: () -> Void

    private var formattedValue: String {
        let absVal = abs(value)
        if absVal < 0.05 {
            return kind.isPositive ? "+0" : "-0"
        }
        let isWhole = abs(absVal - absVal.rounded()) < 0.05
        let numStr = isWhole
            ? "\(Int(absVal.rounded()))"
            : String(format: "%.1f", locale: Locale(identifier: "es_ES"), absVal)
        return kind.isPositive ? "+\(numStr)" : "-\(numStr)"
    }

    var body: some View {
        let absVal = abs(value)
        let frac = min(max(absVal / kind.maxTrackMagnitude, 0.0), 1.0)
        let isActive = absVal >= 0.05
        let thresholdFrac = kind.safeThresholdFraction
        let pastThreshold = !kind.isPositive && isActive && (frac > (thresholdFrac ?? 0.45))

        let accentColor: Color = {
            if !isActive { return Color.white.opacity(0.35) }
            if kind.isPositive { return NutritionPalette.positiveMint }
            return pastThreshold ? NutritionPalette.negativeOrange : Color(hex: 0x9BA1B2)
        }()

        Button(action: onTap) {
            BevelCard(cornerRadius: 16) {
                HStack(spacing: 10) {
                    Text(kind.emoji)
                        .font(.system(size: 18))
                        .frame(width: 24)

                    Text(kind.title)
                        .font(ImprovingFont.cardTitle(14.5))
                        .foregroundColor(BevelColors.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    // Proportional Track + Safe Threshold Vertical Tick + Glowing Indicator Dot
                    GeometryReader { geo in
                        let w = geo.size.width
                        let cy = geo.size.height / 2
                        let thumbX = max(6, min(w - 6, 6 + (w - 12) * CGFloat(frac)))

                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                                .frame(height: 6)

                            if isActive {
                                if !kind.isPositive, let tf = thresholdFrac {
                                    let threshX = w * CGFloat(tf)
                                    // Neutral gray up to safe threshold
                                    Capsule()
                                        .fill(Color.white.opacity(0.28))
                                        .frame(width: min(thumbX, threshX), height: 6)
                                    // Glowing orange beyond safe threshold
                                    if thumbX > threshX {
                                        Capsule()
                                            .fill(NutritionPalette.negativeOrange)
                                            .frame(width: thumbX - threshX, height: 6)
                                            .offset(x: threshX)
                                            .shadow(color: NutritionPalette.negativeOrange.opacity(0.65), radius: 5)
                                    }
                                } else {
                                    Capsule()
                                        .fill(accentColor)
                                        .frame(width: thumbX, height: 6)
                                        .shadow(color: accentColor.opacity(0.65), radius: 5)
                                }
                            }

                            // Safe Threshold vertical hairline marker (Screenshot 4 & 5: Exceso de azúcar, Exceso de sodio)
                            if let tf = thresholdFrac {
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.white.opacity(0.28))
                                    .frame(width: 1.8, height: 14)
                                    .position(x: w * CGFloat(tf), y: cy)
                            }

                            // Glowing Thumb Dot
                            Circle()
                                .fill(isActive ? accentColor.opacity(0.32) : Color.white.opacity(0.14))
                                .frame(width: 14, height: 14)
                                .position(x: thumbX, y: cy)
                            Circle()
                                .fill(.white)
                                .frame(width: 7, height: 7)
                                .position(x: thumbX, y: cy)
                        }
                    }
                    .frame(width: 78, height: 20)

                    Text(formattedValue)
                        .font(ImprovingFont.cardTitle(14))
                        .monospacedDigit()
                        .foregroundColor(isActive ? accentColor : BevelColors.textMuted)
                        .frame(width: 38, alignment: .trailing)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(BevelColors.textMuted)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 6. HoyScreen (Inicio) "Alimentos de hoy" Card (Exact Match to Screenshot 1!)

struct NutritionHomeSummaryCard: View {
    @ObservedObject var store: ImprovingStore
    let onTap: () -> Void

    var body: some View {
        let goals = store.effectiveNutritionGoals
        let scoreOpt = store.foodQualityScore
        let status = store.nutritionScoreStatus(for: scoreOpt)
        let fatG = store.totalFatToday
        let carbsG = store.totalCarbsToday
        let protG = store.totalProteinToday

        let fatFrac = Double(fatG) / Double(max(goals.fatG, 1))
        let carbsFrac = Double(carbsG) / Double(max(goals.carbsG, 1))
        let protFrac = Double(protG) / Double(max(goals.proteinG, 1))

        Button(action: onTap) {
            BevelCard(cornerRadius: 22) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Alimentos de hoy")
                            .font(ImprovingFont.cardTitle(16))
                            .foregroundColor(BevelColors.textPrimary)
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(BevelColors.textMuted)
                    }

                    HStack(spacing: 12) {
                        NutritionPlateTickGauge(
                            score: scoreOpt,
                            statusLabel: status.label,
                            statusColor: status.color,
                            diameter: 96,
                            showZeroHundredLabels: false,
                            tickCount: 36
                        )

                        Spacer(minLength: 2)

                        HStack(spacing: 12) {
                            homeMacroColumn(
                                icon: "drop.fill",
                                value: "\(fatG) g",
                                color: NutritionPalette.fatBlue,
                                fraction: fatFrac
                            )
                            homeMacroColumn(
                                icon: "leaf.fill",
                                value: "\(carbsG) g",
                                color: NutritionPalette.carbsAmber,
                                fraction: carbsFrac
                            )
                            homeMacroColumn(
                                icon: "flame.fill",
                                value: "\(protG) g",
                                color: NutritionPalette.proteinPink,
                                fraction: protFrac
                            )
                        }
                    }
                }
                .padding(16)
            }
        }
        .buttonStyle(.plain)
    }

    private func homeMacroColumn(icon: String, value: String, color: Color, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(color)
                Text(value)
                    .font(ImprovingFont.caption(12.5))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundColor(color)
                    .lineLimit(1)
            }

            MacroDotMatrixGrid(
                fraction: fraction,
                color: color,
                columns: 6,
                rows: 5,
                dotSize: 5.2,
                spacing: 3.4
            )
        }
    }
}

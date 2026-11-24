import SwiftUI

// MARK: - Nutrition Trends Detail Screen (Exact Match to Screenshots 8–14!)
// Supports all 3 tabs: Puntuación de nutrición | Equilibrio macro | Energía neta

struct NutritionTrendsDetailScreen: View {
    @ObservedObject var store: ImprovingStore
    let initialTab: NutritionTrendTab
    let onBack: () -> Void

    @State private var activeTab: NutritionTrendTab = .score
    @State private var selectedRange: String = "30 d"
    @State private var windowPageOffset: Int = 0
    @State private var macroPercentMode: Bool = false
    @State private var showTotalInsteadOfAvg: Bool = false
    @State private var showCalendarSheet: Bool = false
    @State private var activeResourceGuide: NutritionResourceGuide? = nil
    @State private var scrollCollapseSignal: Int = 0

    private struct NutritionResourceGuide: Identifiable {
        let id: String
        let icon: String
        let heroTitle: String
        let heroSubtitle: String
        let cardTitle: String
        let cardDescription: String
        let gradientA: Color
        let gradientB: Color
        let bodyText: String
    }

    private let resourceGuides: [NutritionResourceGuide] = [
        NutritionResourceGuide(
            id: "nut_basics",
            icon: "fork.knife",
            heroTitle: "Nutrition Score",
            heroSubtitle: "The Basics",
            cardTitle: "The Basics: Nutrition Score",
            cardDescription: "Una forma sencilla y científica de entender cómo impactan tus comidas diarias.",
            gradientA: Color(hex: 0x2A3D3F),
            gradientB: Color(hex: 0x574834),
            bodyText: "La Puntuación de nutrición evalúa del 1 al 100 la calidad global de tus comidas del día ponderada por su aporte calórico. Combina la densidad de alimentos enteros (verduras, fruta, cereales integrales, legumbres, grasas saludables y omega-3) y penaliza excesos de azúcar añadido, sodio, carnes procesadas y alcohol por encima del umbral seguro."
        ),
        NutritionResourceGuide(
            id: "nut_factors",
            icon: "leaf.fill",
            heroTitle: "Food Quality\nContributors",
            heroSubtitle: "11 Factores",
            cardTitle: "Food Quality Contributors",
            cardDescription: "Entiende los pilares que suben o bajan tu puntuación diaria de nutrición.",
            gradientA: Color(hex: 0x2A472F),
            gradientB: Color(hex: 0x4E2B2A),
            bodyText: "Cada comida registrada con Gemini IA o de forma manual aporta puntos positivos en 6 factores protectores (cereales integrales, verdura, grasas saludables, fruta, frutos secos/legumbres y omega-3) y evalúa 5 factores límite (azúcar añadido, sodio, carne roja, carne procesada y alcohol). Mantener los factores negativos por debajo del umbral seguro maximiza tu VFC y recuperación nocturna."
        )
    ]

    private var rangeOptions: [String] {
        switch activeTab {
        case .score: return ["7 D", "30 d", "3 M", "6 M", "1 A"]
        case .macroBalance: return ["30 d", "3 M", "6 M", "1 A"]
        case .netEnergy: return ["7 D", "30 d", "3 M", "6 M"]
        }
    }

    private var spanDays: Int {
        switch selectedRange {
        case "7 D": return 7
        case "30 d": return 30
        case "3 M": return 90
        case "6 M": return 180
        case "1 A": return 365
        default: return 30
        }
    }

    private struct DayNutritionPoint: Identifiable {
        var id: String { iso }
        let iso: String
        let date: Date
        let shortLabel: String
        let weekdayInitial: String
        let score: Int?
        let fatG: Double
        let carbsG: Double
        let proteinG: Double
        let consumedKcal: Int
        let burnedKcal: Int
        var netKcal: Int { consumedKcal - burnedKcal }
        var totalMacroG: Double { fatG + carbsG + proteinG }
    }

    private func buildWindowPoints() -> [DayNutritionPoint] {
        let cal = Calendar.current
        let anchor = cal.startOfDay(for: store.selectedDate)
        let end = cal.date(byAdding: .day, value: -(windowPageOffset * spanDays), to: anchor) ?? anchor
        let start = cal.date(byAdding: .day, value: -(spanDays - 1), to: end) ?? end

        let shortFmt = DateFormatter()
        shortFmt.locale = Locale(identifier: "es_ES")
        shortFmt.dateFormat = spanDays >= 180 ? "MMM yy" : "d MMM"

        let wdFmt = DateFormatter()
        wdFmt.locale = Locale(identifier: "es_ES")
        wdFmt.dateFormat = "EEEEE"

        var list: [DayNutritionPoint] = []
        list.reserveCapacity(spanDays)
        for i in 0..<spanDays {
            guard let d = cal.date(byAdding: .day, value: i, to: start) else { continue }
            let iso = store.isoFormatter.string(from: d)
            let t = store.nutritionDayTotals(for: iso)
            let burned = store.burnedCalories(for: iso)
            list.append(DayNutritionPoint(
                iso: iso,
                date: d,
                shortLabel: shortFmt.string(from: d).replacingOccurrences(of: ".", with: ""),
                weekdayInitial: wdFmt.string(from: d).uppercased(),
                score: t.score,
                fatG: t.fatG,
                carbsG: t.carbsG,
                proteinG: t.proteinG,
                consumedKcal: t.kcal,
                burnedKcal: burned
            ))
        }
        return list
    }

    private var shortSelectedDateLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "d MMM yyyy"
        return f.string(from: store.selectedDate).replacingOccurrences(of: ".", with: "")
    }

    var body: some View {
        let points = buildWindowPoints()
        let todayTotals = store.nutritionDayTotals(for: store.selectedDateIso)
        let todayNet = store.netEnergyKcal(for: store.selectedDateIso)
        let totalMacroG = Int((todayTotals.fatG + todayTotals.carbsG + todayTotals.proteinG).rounded())

        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Top Modal Header (X + Title)
                    DetailSheetHeader(title: activeTab.rawValue, onBack: onBack)

                    VStack(alignment: .leading, spacing: 14) {
                        // Hero Metric Block per Active Tab
                        heroHeader(todayTotals: todayTotals, todayNet: todayNet, totalMacroG: totalMacroG)

                        // 3-Tab Horizontal Switcher (Exact Screenshots 10 & 13!)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(NutritionTrendTab.allCases) { tab in
                                    let isSelected = activeTab == tab
                                    Button {
                                        UISelectionFeedbackGenerator().selectionChanged()
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            activeTab = tab
                                            if !rangeOptions.contains(selectedRange) {
                                                selectedRange = tab == .netEnergy ? "7 D" : "30 d"
                                            }
                                            windowPageOffset = 0
                                        }
                                    } label: {
                                        Text(tab.rawValue)
                                            .font(ImprovingFont.cardTitle(13.5))
                                            .foregroundColor(isSelected ? .white : BevelColors.textSecondary)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 9.5)
                                            .background(Capsule().fill(isSelected ? Color(hex: 0x6A6E7A) : BevelColors.card))
                                    }
                                }
                            }
                        }

                        // Primary Chart per Tab
                        switch activeTab {
                        case .score:
                            scoreLineChart(points: points)
                        case .macroBalance:
                            macroStackedBarChart(points: points)
                        case .netEnergy:
                            netEnergyDualBarChart(points: points)
                        }

                        // Range Pagination Bar (< [7 D | 30 d | 3 M | 6 M] 📅 >)
                        rangeControlBar

                        // Tab-Specific Lower Analytics & History Tables
                        switch activeTab {
                        case .score:
                            scoreTrendAnalysisSection
                            resourcesCarouselSection
                            educationalCard(
                                title: "Puntuación de nutrición",
                                paragraphs: [
                                    "La puntuación de nutrición evalúa la calidad de tus elecciones de alimentos y su impacto en el cuerpo, en una escala de 1–100. Una puntuación más alta refleja una mayor calidad y un efecto más saludable en tu bienestar general.",
                                    "Esta puntuación combina tus métricas de calidad de alimentos e impacto metabólico (si están disponibles). Para optimizar tu puntuación de nutrición, céntrate en comer alimentos no procesados, alimentos enteros con mínimo sodio o azúcar añadidos y comidas equilibradas que incluyan una gran variedad de nutrientes."
                                ]
                            )

                        case .macroBalance:
                            macroWeeklyHistorySection
                            educationalCard(
                                title: "Equilibrio macro",
                                paragraphs: [
                                    "El equilibrio macro mide la proporción de macronutrientes (proteínas, grasas y carbohidratos) en tu dieta.",
                                    "Hacer un seguimiento de tu equilibrio macro te asegura saber que estás consumiendo la combinación adecuada de nutrientes para alcanzar tus objetivos de salud y forma física, como desarrollar la musculatura, perder peso o mantener el bienestar. Una ingesta bien equilibrada ayuda a conservar la energía, optimizar el rendimiento y promover una buena salud en general."
                                ]
                            )

                        case .netEnergy:
                            netEnergyTrendAnalysisSection
                            educationalCard(
                                title: "Energía neta",
                                paragraphs: [
                                    "La energía neta es el equilibrio entre la energía que quemas y la energía que consumes, y muestra si tienes superávit, déficit o equilibrio de calorías.",
                                    "Monitorizar la energía neta te ayuda a alinear tu ingesta y actividad con tus objetivos, ya sea gestionar el peso, desarrollar la musculatura o mantener una buena salud en general."
                                ]
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 185)
            }
            .onVerticalScrollCollapse { scrollCollapseSignal += 1 }

            FloatingMetricAiCoachOverlay(
                metricKey: "nut_trend_\(activeTab.rawValue)_\(store.selectedDateIso)",
                metricTitle: activeTab.rawValue,
                insight: buildAiInsight(todayTotals: todayTotals, todayNet: todayNet),
                scrollCollapseSignal: scrollCollapseSignal,
                leadingEmoji: activeTab == .score ? "📉" : (activeTab == .macroBalance ? "🍪" : "🔥")
            )
        }
        .background(BevelColors.canvas)
        .onAppear {
            activeTab = initialTab
            selectedRange = initialTab == .netEnergy ? "7 D" : "30 d"
        }
        .sheet(isPresented: $showCalendarSheet) {
            DatePickerSheetView(
                selectedDate: Binding(
                    get: { store.selectedDate },
                    set: { d in
                        store.selectDate(d)
                        windowPageOffset = 0
                        showCalendarSheet = false
                    }
                ),
                onJumpToday: {
                    store.selectDayOffset(0)
                    windowPageOffset = 0
                    showCalendarSheet = false
                },
                onClose: { showCalendarSheet = false }
            )
        }
        .sheet(item: $activeResourceGuide) { guide in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ZStack(alignment: .bottomLeading) {
                            LinearGradient(colors: [guide.gradientA, guide.gradientB], startPoint: .topLeading, endPoint: .bottomTrailing)
                                .frame(height: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            VStack(alignment: .leading, spacing: 6) {
                                Image(systemName: guide.icon)
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundColor(.white)
                                Text(guide.heroTitle)
                                    .font(ImprovingFont.displayLarge(26))
                                    .foregroundColor(.white)
                                Text(guide.heroSubtitle)
                                    .font(ImprovingFont.caption(13))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .padding(20)
                        }

                        Text(guide.bodyText)
                            .font(ImprovingFont.body(15))
                            .foregroundColor(BevelColors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                }
                .background(BevelColors.canvas)
                .navigationTitle(guide.cardTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Cerrar") { activeResourceGuide = nil }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Hero Metric Header per Tab

    @ViewBuilder
    private func heroHeader(
        todayTotals: (kcal: Int, fatG: Double, carbsG: Double, proteinG: Double, score: Int?, mealCount: Int),
        todayNet: (net: Int, consumed: Int, burned: Int),
        totalMacroG: Int
    ) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                switch activeTab {
                case .score:
                    Text(todayTotals.score.map { "\($0)" } ?? "--")
                        .font(ImprovingFont.displayLarge(34))
                        .monospacedDigit()
                        .foregroundColor(BevelColors.textPrimary)
                case .macroBalance:
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(macroPercentMode ? (totalMacroG > 0 ? "100" : "0") : "\(totalMacroG)")
                            .font(ImprovingFont.displayLarge(34))
                            .monospacedDigit()
                            .foregroundColor(BevelColors.textPrimary)
                        Text(macroPercentMode ? "%" : "g")
                            .font(ImprovingFont.sectionTitle(21))
                            .foregroundColor(BevelColors.textSecondary)
                    }
                case .netEnergy:
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(todayNet.net > 0 ? "+\(todayNet.net)" : "\(todayNet.net)")
                            .font(ImprovingFont.displayLarge(34))
                            .monospacedDigit()
                            .foregroundColor(BevelColors.textPrimary)
                        Text("kcal")
                            .font(ImprovingFont.sectionTitle(21))
                            .foregroundColor(BevelColors.textSecondary)
                    }
                }
                Text(shortSelectedDateLabel)
                    .font(ImprovingFont.body(14))
                    .foregroundColor(BevelColors.textSecondary)
            }

            Spacer()

            switch activeTab {
            case .score:
                let st = store.nutritionScoreStatus(for: todayTotals.score)
                Text(st.label.capitalized)
                    .font(ImprovingFont.cardTitle(14.5))
                    .foregroundColor(st.color)
            case .macroBalance:
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    macroPercentMode.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Text(macroPercentMode ? "Porcentaje" : "Gramos")
                            .font(ImprovingFont.cardTitle(13.5))
                            .foregroundColor(BevelColors.textPrimary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(BevelColors.textSecondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 12).fill(BevelColors.card))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
                }
            case .netEnergy:
                let eq = netEnergyBalanceLabel(todayNet.net)
                Text(eq.label)
                    .font(ImprovingFont.cardTitle(15))
                    .foregroundColor(eq.color)
            }
        }
    }

    // MARK: - Chart 1: Nutrition Score Line Chart

    private func scoreLineChart(points: [DayNutritionPoint]) -> some View {
        let scoreVals = points.map { $0.score.map { Double($0) } }
        let xTicks = xAxisLabels(from: points)

        return VStack(spacing: 8) {
            ZStack {
                HStack(spacing: 6) {
                    Canvas { ctx, sz in
                        let w = sz.width
                        let h = sz.height
                        let gridYs: [CGFloat] = [0.1, 0.4, 0.7, 0.96]
                        for gy in gridYs {
                            var line = Path()
                            line.move(to: CGPoint(x: 0, y: h * gy))
                            line.addLine(to: CGPoint(x: w, y: h * gy))
                            ctx.stroke(line, with: .color(Color.white.opacity(0.06)), lineWidth: 0.8)
                        }

                        var path = Path()
                        var started = false
                        var lastPt: CGPoint? = nil
                        let stepX = w / CGFloat(max(scoreVals.count - 1, 1))
                        for (i, optV) in scoreVals.enumerated() {
                            guard let v = optV else { continue }
                            let x = CGFloat(i) * stepX
                            let norm = min(max(v / 100.0, 0.0), 1.0)
                            let y = h * 0.96 - CGFloat(norm) * (h * 0.86)
                            let pt = CGPoint(x: x, y: y)
                            if !started {
                                path.move(to: pt)
                                started = true
                            } else {
                                path.addLine(to: pt)
                            }
                            lastPt = pt
                        }
                        if started {
                            ctx.stroke(path, with: .color(NutritionPalette.scoreLavender), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        }
                        if let lp = lastPt {
                            ctx.fill(Path(ellipseIn: CGRect(x: lp.x - 9, y: lp.y - 9, width: 18, height: 18)), with: .color(NutritionPalette.scoreLavender.opacity(0.28)))
                            ctx.fill(Path(ellipseIn: CGRect(x: lp.x - 4.5, y: lp.y - 4.5, width: 9, height: 9)), with: .color(.white))
                            ctx.stroke(Path(ellipseIn: CGRect(x: lp.x - 4.5, y: lp.y - 4.5, width: 9, height: 9)), with: .color(NutritionPalette.scoreLavender), lineWidth: 2.2)
                        }
                    }

                    VStack {
                        Text("100").font(ImprovingFont.caption(11)).foregroundColor(BevelColors.textMuted)
                        Spacer()
                        Text("67").font(ImprovingFont.caption(11)).foregroundColor(BevelColors.textMuted)
                        Spacer()
                        Text("33").font(ImprovingFont.caption(11)).foregroundColor(BevelColors.textMuted)
                        Spacer()
                        Text("0").font(ImprovingFont.caption(11)).foregroundColor(BevelColors.textMuted)
                    }
                    .frame(width: 28)
                }
                .frame(height: 195)

                if scoreVals.compactMap({ $0 }).isEmpty {
                    Text("Registra comidas para ver tu curva de puntuación")
                        .font(ImprovingFont.caption(13))
                        .foregroundColor(BevelColors.textMuted)
                }
            }

            HStack {
                ForEach(Array(xTicks.enumerated()), id: \.offset) { idx, lbl in
                    Text(lbl).font(ImprovingFont.caption(11.5)).foregroundColor(BevelColors.textMuted)
                    if idx < xTicks.count - 1 { Spacer() }
                }
            }
            .padding(.trailing, 32)
        }
        .padding(.top, 6)
    }

    // MARK: - Chart 2: Stacked Vertical Capsule Macro Bars (Exact Screenshot 10!)

    private func macroStackedBarChart(points: [DayNutritionPoint]) -> some View {
        let maxG = max(450.0, ceil((points.map(\.totalMacroG).max() ?? 0) / 150.0) * 150.0)
        let yTop = macroPercentMode ? 100.0 : maxG
        let yLabels: [String] = macroPercentMode
            ? ["100%", "67%", "33%", "0%"]
            : ["\(Int(yTop))", "\(Int(yTop * 2 / 3))", "\(Int(yTop / 3))", "0"]
        let xTicks = xAxisLabels(from: points)

        return VStack(spacing: 8) {
            HStack(spacing: 6) {
                Canvas { ctx, sz in
                    let w = sz.width
                    let h = sz.height
                    for frac in [0.06, 0.37, 0.68, 0.98] as [CGFloat] {
                        var line = Path()
                        line.move(to: CGPoint(x: 0, y: h * frac))
                        line.addLine(to: CGPoint(x: w, y: h * frac))
                        ctx.stroke(line, with: .color(Color.white.opacity(0.06)), lineWidth: 0.8)
                    }

                    let count = max(points.count, 1)
                    let slotW = w / CGFloat(count)
                    let barW = min(max(slotW * 0.56, 3.0), 10.0)
                    let chartH = h * 0.92

                    for (i, pt) in points.enumerated() {
                        let tot = pt.totalMacroG
                        guard tot > 0.5 else { continue }
                        let cx = (CGFloat(i) + 0.5) * slotW

                        let fH: CGFloat
                        let cH: CGFloat
                        let pH: CGFloat
                        if macroPercentMode {
                            fH = chartH * CGFloat(pt.fatG / tot)
                            cH = chartH * CGFloat(pt.carbsG / tot)
                            pH = chartH * CGFloat(pt.proteinG / tot)
                        } else {
                            let scale = chartH / CGFloat(max(yTop, 1))
                            fH = CGFloat(pt.fatG) * scale
                            cH = CGFloat(pt.carbsG) * scale
                            pH = CGFloat(pt.proteinG) * scale
                        }

                        var curBottom = h * 0.98
                        let segments: [(CGFloat, Color)] = [
                            (fH, NutritionPalette.fatBlue),
                            (cH, NutritionPalette.carbsAmber),
                            (pH, NutritionPalette.proteinPink)
                        ]
                        for (segH, col) in segments where segH > 0.8 {
                            let rect = CGRect(x: cx - barW / 2, y: curBottom - segH, width: barW, height: max(segH - 1.0, 1.5))
                            ctx.fill(Path(roundedRect: rect, cornerRadius: barW / 2), with: .color(col))
                            curBottom -= segH
                        }
                    }
                }

                VStack {
                    ForEach(Array(yLabels.enumerated()), id: \.offset) { idx, lbl in
                        Text(lbl).font(ImprovingFont.caption(11)).monospacedDigit().foregroundColor(BevelColors.textMuted)
                        if idx < yLabels.count - 1 { Spacer() }
                    }
                }
                .frame(width: 34)
            }
            .frame(height: 205)

            HStack {
                ForEach(Array(xTicks.enumerated()), id: \.offset) { idx, lbl in
                    Text(lbl).font(ImprovingFont.caption(11.5)).foregroundColor(BevelColors.textMuted)
                    if idx < xTicks.count - 1 { Spacer() }
                }
            }
            .padding(.trailing, 38)
        }
        .padding(.top, 6)
    }

    // MARK: - Chart 3: Grouped Dual-Bar Net Energy Chart (Exact Screenshot 13!)

    private func netEnergyDualBarChart(points: [DayNutritionPoint]) -> some View {
        let maxK = max(2540.0, ceil(Double(points.map { max($0.consumedKcal, $0.burnedKcal) }.max() ?? 2000) / 300.0) * 300.0)
        let formatK: (Double) -> String = { v in
            if v <= 0 { return "0" }
            if v >= 1000 {
                return String(format: "%.2fK", locale: Locale(identifier: "es_ES"), v / 1000.0)
            }
            return "\(Int(v.rounded()))"
        }
        let yLabels = [formatK(maxK), formatK(maxK * 2 / 3), formatK(maxK / 3), "0"]

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Canvas { ctx, sz in
                    let w = sz.width
                    let h = sz.height
                    for frac in [0.06, 0.37, 0.68, 0.98] as [CGFloat] {
                        var line = Path()
                        line.move(to: CGPoint(x: 0, y: h * frac))
                        line.addLine(to: CGPoint(x: w, y: h * frac))
                        ctx.stroke(line, with: .color(Color.white.opacity(0.06)), lineWidth: 0.8)
                    }

                    let count = max(points.count, 1)
                    let slotW = w / CGFloat(count)
                    let singleBarW = min(max(slotW * 0.24, 2.2), 9.0)
                    let gap: CGFloat = singleBarW >= 5 ? 2.5 : 1.0
                    let chartH = h * 0.92
                    let baseY = h * 0.98

                    for (i, pt) in points.enumerated() {
                        let cx = (CGFloat(i) + 0.5) * slotW
                        if pt.consumedKcal > 0 {
                            let ch = min(chartH, CGFloat(Double(pt.consumedKcal) / maxK) * chartH)
                            let r = CGRect(x: cx - singleBarW - gap / 2, y: baseY - ch, width: singleBarW, height: max(ch, 3))
                            ctx.fill(Path(roundedRect: r, cornerRadius: singleBarW / 2), with: .color(NutritionPalette.consumedBlue))
                        }
                        if pt.burnedKcal > 0 {
                            let bh = min(chartH, CGFloat(Double(pt.burnedKcal) / maxK) * chartH)
                            let r = CGRect(x: cx + gap / 2, y: baseY - bh, width: singleBarW, height: max(bh, 3))
                            ctx.fill(Path(roundedRect: r, cornerRadius: singleBarW / 2), with: .color(NutritionPalette.burnedOrange))
                        }
                    }
                }

                VStack {
                    ForEach(Array(yLabels.enumerated()), id: \.offset) { idx, lbl in
                        Text(lbl).font(ImprovingFont.caption(11)).monospacedDigit().foregroundColor(BevelColors.textMuted)
                        if idx < yLabels.count - 1 { Spacer() }
                    }
                }
                .frame(width: 40)
            }
            .frame(height: 205)

            if spanDays == 7 {
                HStack {
                    ForEach(points) { pt in
                        Text(pt.weekdayInitial)
                            .font(ImprovingFont.caption(11.5))
                            .foregroundColor(BevelColors.textMuted)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.trailing, 44)
            } else {
                let xTicks = xAxisLabels(from: points)
                HStack {
                    ForEach(Array(xTicks.enumerated()), id: \.offset) { idx, lbl in
                        Text(lbl).font(ImprovingFont.caption(11.5)).foregroundColor(BevelColors.textMuted)
                        if idx < xTicks.count - 1 { Spacer() }
                    }
                }
                .padding(.trailing, 44)
            }

            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Circle().fill(NutritionPalette.consumedBlue).frame(width: 8, height: 8)
                    Text("Consumidas").font(ImprovingFont.caption(12.5)).foregroundColor(BevelColors.textSecondary)
                }
                HStack(spacing: 6) {
                    Circle().fill(NutritionPalette.burnedOrange).frame(width: 8, height: 8)
                    Text("Quemadas").font(ImprovingFont.caption(12.5)).foregroundColor(BevelColors.textSecondary)
                }
            }
        }
        .padding(.top, 6)
    }

    // MARK: - Range Control Bar (< [7 D | 30 d | 3 M | 6 M] 📅 >)

    private var rangeControlBar: some View {
        HStack(spacing: 8) {
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                windowPageOffset += 1
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(BevelColors.textPrimary)
                    .frame(width: 32, height: 32)
            }

            HStack(spacing: 2) {
                ForEach(rangeOptions, id: \.self) { opt in
                    let active = selectedRange == opt
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        selectedRange = opt
                        windowPageOffset = 0
                    } label: {
                        Text(opt)
                            .font(ImprovingFont.caption(12.5))
                            .fontWeight(active ? .bold : .medium)
                            .foregroundColor(active ? .white : BevelColors.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(active ? Color(hex: 0x6A6E7A) : .clear))
                    }
                }
            }
            .padding(3)
            .background(Capsule().fill(BevelColors.card))

            Button { showCalendarSheet = true } label: {
                Image(systemName: "calendar")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(BevelColors.textPrimary)
                    .frame(width: 32, height: 32)
            }

            Button {
                if windowPageOffset > 0 {
                    UISelectionFeedbackGenerator().selectionChanged()
                    windowPageOffset -= 1
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(windowPageOffset > 0 ? BevelColors.textPrimary : BevelColors.textMuted.opacity(0.35))
                    .frame(width: 32, height: 32)
            }
            .disabled(windowPageOffset == 0)
        }
    }

    // MARK: - Lower Section 1: Score Trend Analysis Table + Recursos (Screenshots 8 & 9)

    private var scoreTrendAnalysisSection: some View {
        let periods = [3, 7, 14, 30, 90]
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Análisis de tendencias")
                    .font(ImprovingFont.sectionTitle(18))
                    .foregroundColor(BevelColors.textPrimary)
                Text("Último dato el \(shortSelectedDateLabel)")
                    .font(ImprovingFont.caption(13))
                    .foregroundColor(BevelColors.textMuted)
            }
            .padding(.top, 4)

            BevelCard(cornerRadius: 20) {
                VStack(spacing: 0) {
                    HStack {
                        Text("Período").font(ImprovingFont.caption(12.5)).foregroundColor(BevelColors.textMuted).frame(width: 82, alignment: .leading)
                        Text("Variación").font(ImprovingFont.caption(12.5)).foregroundColor(BevelColors.textMuted)
                        Spacer()
                        Text("Tendencia").font(ImprovingFont.caption(12.5)).foregroundColor(BevelColors.textMuted).frame(width: 90, alignment: .trailing)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 8)

                    ForEach(Array(periods.enumerated()), id: \.offset) { idx, pDays in
                        let series = trailingScores(days: pDays)
                        let valid = series.compactMap { $0 }
                        let delta: Int? = valid.count >= 2 ? Int((valid.last! - valid.first!).rounded()) : nil

                        HStack {
                            Text("\(pDays) día(s)")
                                .font(ImprovingFont.body(14.5))
                                .foregroundColor(BevelColors.textSecondary)
                                .frame(width: 82, alignment: .leading)

                            if let d = delta {
                                let isPos = d >= 0
                                let col = d == 0 ? BevelColors.textMuted : (isPos ? BevelColors.greenPrimary : NutritionPalette.burnedOrange)
                                HStack(spacing: 6) {
                                    Image(systemName: isPos ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(col)
                                    Text(d > 0 ? "+\(d)" : "\(d)")
                                        .font(ImprovingFont.cardTitle(15))
                                        .monospacedDigit()
                                        .foregroundColor(BevelColors.textPrimary)
                                }
                            } else {
                                Text("—")
                                    .font(ImprovingFont.body(15))
                                    .foregroundColor(BevelColors.textMuted)
                            }

                            Spacer()

                            if valid.count >= 2 {
                                let isPos = (delta ?? 0) >= 0
                                TrendSparklineWithBand(
                                    optionalPoints: series,
                                    lineColor: isPos ? BevelColors.greenPrimary : NutritionPalette.burnedOrange,
                                    fillUnder: true
                                )
                                .frame(width: 90, height: 22)
                            } else {
                                Capsule()
                                    .fill(Color.white.opacity(0.16))
                                    .frame(width: 86, height: 2)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)

                        if idx < periods.count - 1 {
                            Divider().background(BevelColors.divider).padding(.horizontal, 16)
                        }
                    }
                }
            }

            Text("Basado en las medias móviles de 7 días durante el período seleccionado.")
                .font(ImprovingFont.caption(12))
                .foregroundColor(BevelColors.textMuted)
        }
    }

    private var resourcesCarouselSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recursos")
                .font(ImprovingFont.sectionTitle(18))
                .foregroundColor(BevelColors.textPrimary)
                .padding(.top, 6)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(resourceGuides) { g in
                        Button { activeResourceGuide = g } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ZStack {
                                    LinearGradient(colors: [g.gradientA, g.gradientB], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    VStack(spacing: 5) {
                                        Image(systemName: g.icon)
                                            .font(.system(size: 20, weight: .semibold))
                                            .foregroundColor(.white.opacity(0.88))
                                        Text(g.heroTitle)
                                            .font(.system(size: 19, weight: .bold, design: .rounded))
                                            .foregroundColor(.white)
                                            .multilineTextAlignment(.center)
                                        Text(g.heroSubtitle)
                                            .font(ImprovingFont.caption(12))
                                            .foregroundColor(.white.opacity(0.75))
                                    }
                                    .padding(12)
                                }
                                .frame(width: 220, height: 118)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                                Text(g.cardTitle)
                                    .font(ImprovingFont.cardTitle(14.5))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .lineLimit(1)

                                Text(g.cardDescription)
                                    .font(ImprovingFont.caption(12))
                                    .foregroundColor(BevelColors.textSecondary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(width: 220, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Lower Section 2: Weekly Macro History Grouped by Month (Exact Screenshots 10–12!)

    private struct MacroWeekRow: Identifiable {
        let id: String
        let weekLabel: String
        let fat: Double
        let carbs: Double
        let protein: Double
    }

    private struct MacroMonthGroup: Identifiable {
        let id: String
        let monthTitle: String
        let weeks: [MacroWeekRow]
    }

    private var macroWeeklyHistorySection: some View {
        let groups = buildMonthlyWeeklyMacros(monthsBack: 3)
        let rangeSubtitle: String = {
            if let first = groups.last?.monthTitle, let last = groups.first?.monthTitle {
                return "\(first.split(separator: " ").first ?? "") – \(last)"
            }
            return shortSelectedDateLabel
        }()

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Historial de equilibrio macro")
                        .font(ImprovingFont.sectionTitle(18))
                        .foregroundColor(BevelColors.textPrimary)
                    Text(rangeSubtitle)
                        .font(ImprovingFont.caption(13))
                        .foregroundColor(BevelColors.textSecondary)
                }
                Spacer()
                avgTotalTogglePill
            }
            .padding(.top, 6)

            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.monthTitle)
                        .font(ImprovingFont.cardTitle(15))
                        .foregroundColor(BevelColors.textPrimary)

                    BevelCard(cornerRadius: 18) {
                        VStack(spacing: 0) {
                            HStack {
                                Text("Semana").font(ImprovingFont.caption(12.5)).foregroundColor(BevelColors.textMuted).frame(width: 78, alignment: .leading)
                                Text("Grasas").font(ImprovingFont.caption(12.5)).fontWeight(.semibold).foregroundColor(NutritionPalette.fatBlue).frame(maxWidth: .infinity, alignment: .leading)
                                Text("Carbos").font(ImprovingFont.caption(12.5)).fontWeight(.semibold).foregroundColor(NutritionPalette.carbsAmber).frame(maxWidth: .infinity, alignment: .leading)
                                Text("Proteína").font(ImprovingFont.caption(12.5)).fontWeight(.semibold).foregroundColor(NutritionPalette.proteinPink).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 14)
                            .padding(.top, 13)
                            .padding(.bottom, 8)

                            ForEach(Array(group.weeks.enumerated()), id: \.element.id) { idx, row in
                                HStack {
                                    Text(row.weekLabel)
                                        .font(ImprovingFont.body(14))
                                        .foregroundColor(BevelColors.textSecondary)
                                        .frame(width: 78, alignment: .leading)
                                    Text(String(format: "%.1f", locale: Locale(identifier: "es_ES"), row.fat))
                                        .font(ImprovingFont.cardTitle(14.5))
                                        .monospacedDigit()
                                        .foregroundColor(BevelColors.textPrimary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(String(format: "%.1f", locale: Locale(identifier: "es_ES"), row.carbs))
                                        .font(ImprovingFont.cardTitle(14.5))
                                        .monospacedDigit()
                                        .foregroundColor(BevelColors.textPrimary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(String(format: "%.1f", locale: Locale(identifier: "es_ES"), row.protein))
                                        .font(ImprovingFont.cardTitle(14.5))
                                        .monospacedDigit()
                                        .foregroundColor(BevelColors.textPrimary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)

                                if idx < group.weeks.count - 1 {
                                    Divider().background(BevelColors.divider).padding(.horizontal, 14)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Lower Section 3: Net Energy Trend Analysis Table (Exact Screenshots 13 & 14!)

    private var netEnergyTrendAnalysisSection: some View {
        let periods = [3, 7, 14, 30, 90]
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Análisis de tendencias")
                        .font(ImprovingFont.sectionTitle(18))
                        .foregroundColor(BevelColors.textPrimary)
                    Text("Último dato el \(shortSelectedDateLabel)")
                        .font(ImprovingFont.caption(13))
                        .foregroundColor(BevelColors.textMuted)
                }
                Spacer()
                avgTotalTogglePill
            }
            .padding(.top, 6)

            BevelCard(cornerRadius: 20) {
                VStack(spacing: 0) {
                    HStack {
                        Text("Período").font(ImprovingFont.caption(12.5)).foregroundColor(BevelColors.textMuted).frame(width: 82, alignment: .leading)
                        Text("Energía neta").font(ImprovingFont.caption(12.5)).foregroundColor(BevelColors.textMuted)
                        Spacer()
                        Text("Equilibrio").font(ImprovingFont.caption(12.5)).foregroundColor(BevelColors.textMuted)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 8)

                    ForEach(Array(periods.enumerated()), id: \.offset) { idx, pDays in
                        let val = aggregateNetEnergy(days: pDays, total: showTotalInsteadOfAvg)
                        let eq = netEnergyBalanceLabel(val)

                        HStack {
                            Text("\(pDays) día(s)")
                                .font(ImprovingFont.body(14.5))
                                .foregroundColor(BevelColors.textSecondary)
                                .frame(width: 82, alignment: .leading)

                            Text(val > 0 ? "+\(val) kcal" : "\(val) kcal")
                                .font(ImprovingFont.cardTitle(15))
                                .monospacedDigit()
                                .foregroundColor(BevelColors.textPrimary)

                            Spacer()

                            HStack(spacing: 6) {
                                Image(systemName: eq.icon)
                                    .font(.system(size: 15))
                                    .foregroundColor(eq.color)
                                Text(eq.label)
                                    .font(ImprovingFont.cardTitle(14))
                                    .foregroundColor(BevelColors.textPrimary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)

                        if idx < periods.count - 1 {
                            Divider().background(BevelColors.divider).padding(.horizontal, 16)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var avgTotalTogglePill: some View {
        HStack(spacing: 2) {
            Button { showTotalInsteadOfAvg = false } label: {
                Text("Prom.")
                    .font(ImprovingFont.caption(12))
                    .fontWeight(.semibold)
                    .foregroundColor(!showTotalInsteadOfAvg ? .white : BevelColors.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(!showTotalInsteadOfAvg ? Color(hex: 0x6A6E7A) : .clear))
            }
            Button { showTotalInsteadOfAvg = true } label: {
                Text("Total")
                    .font(ImprovingFont.caption(12))
                    .fontWeight(.semibold)
                    .foregroundColor(showTotalInsteadOfAvg ? .white : BevelColors.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(showTotalInsteadOfAvg ? Color(hex: 0x6A6E7A) : .clear))
            }
        }
        .padding(3)
        .background(Capsule().fill(BevelColors.card))
    }

    private func educationalCard(title: String, paragraphs: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle").font(.system(size: 14)).foregroundColor(BevelColors.textSecondary)
                Text(title).font(ImprovingFont.cardTitle(14.5)).foregroundColor(BevelColors.textSecondary)
            }
            ForEach(paragraphs, id: \.self) { p in
                Text(p)
                    .font(ImprovingFont.body(13.5))
                    .foregroundColor(BevelColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20).fill(BevelColors.card.opacity(0.65)))
        .padding(.top, 4)
    }

    private func xAxisLabels(from points: [DayNutritionPoint]) -> [String] {
        guard points.count >= 4 else { return points.map(\.shortLabel) }
        let idxs = [0, points.count / 3, (points.count * 2) / 3, points.count - 1]
        return idxs.map { points[$0].shortLabel }
    }

    private func trailingScores(days: Int) -> [Double?] {
        let cal = Calendar.current
        let anchor = cal.startOfDay(for: store.selectedDate)
        return (0..<days).reversed().compactMap { back -> Double? in
            guard let d = cal.date(byAdding: .day, value: -back, to: anchor) else { return nil }
            let iso = store.isoFormatter.string(from: d)
            return store.nutritionScore(for: iso).map { Double($0) }
        }
    }

    private func aggregateNetEnergy(days: Int, total: Bool) -> Int {
        let cal = Calendar.current
        let anchor = cal.startOfDay(for: store.selectedDate)
        var sum = 0
        var count = 0
        for back in 0..<days {
            guard let d = cal.date(byAdding: .day, value: -back, to: anchor) else { continue }
            let iso = store.isoFormatter.string(from: d)
            sum += store.netEnergyKcal(for: iso).net
            count += 1
        }
        guard count > 0 else { return 0 }
        return total ? sum : Int((Double(sum) / Double(count)).rounded())
    }

    private func netEnergyBalanceLabel(_ net: Int) -> (label: String, icon: String, color: Color) {
        if net < -150 { return ("Déficit", "arrow.down.circle.fill", NutritionPalette.burnedOrange) }
        if net > 150 { return ("Superávit", "arrow.up.circle.fill", NutritionPalette.consumedBlue) }
        return ("Equilibrio", "equal.circle.fill", BevelColors.greenPrimary)
    }

    private func buildMonthlyWeeklyMacros(monthsBack: Int) -> [MacroMonthGroup] {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // Monday
        let anchor = cal.startOfDay(for: store.selectedDate)

        let monthFmt = DateFormatter()
        monthFmt.locale = Locale(identifier: "es_ES")
        monthFmt.dateFormat = "MMM yyyy"

        let weekFmt = DateFormatter()
        weekFmt.locale = Locale(identifier: "es_ES")
        weekFmt.dateFormat = "d MMM"

        // Collect last 12 Mondays up to current week
        let weekday = cal.component(.weekday, from: anchor)
        let daysFromMonday = (weekday + 5) % 7
        let currentMonday = cal.date(byAdding: .day, value: -daysFromMonday, to: anchor) ?? anchor

        var grouped: [String: (title: String, orderDate: Date, rows: [MacroWeekRow])] = [:]
        for wBack in 0..<(monthsBack * 4) {
            guard let monday = cal.date(byAdding: .day, value: -(wBack * 7), to: currentMonday) else { continue }
            var fatSum = 0.0
            var carbsSum = 0.0
            var protSum = 0.0
            var activeDays = 0
            for dOff in 0..<7 {
                guard let day = cal.date(byAdding: .day, value: dOff, to: monday), day <= anchor else { continue }
                let iso = store.isoFormatter.string(from: day)
                let t = store.nutritionDayTotals(for: iso)
                fatSum += t.fatG
                carbsSum += t.carbsG
                protSum += t.proteinG
                activeDays += 1
            }
            let divisor = showTotalInsteadOfAvg ? 1.0 : Double(max(activeDays, 1))
            let row = MacroWeekRow(
                id: store.isoFormatter.string(from: monday),
                weekLabel: weekFmt.string(from: monday).replacingOccurrences(of: ".", with: ""),
                fat: fatSum / divisor,
                carbs: carbsSum / divisor,
                protein: protSum / divisor
            )
            let mKey = monthFmt.string(from: monday).replacingOccurrences(of: ".", with: "")
            if var existing = grouped[mKey] {
                existing.rows.append(row)
                grouped[mKey] = existing
            } else {
                grouped[mKey] = (mKey, monday, [row])
            }
        }

        return grouped.values
            .sorted { $0.orderDate > $1.orderDate }
            .map { MacroMonthGroup(id: $0.title, monthTitle: $0.title, weeks: $0.rows) }
    }

    private func buildAiInsight(
        todayTotals: (kcal: Int, fatG: Double, carbsG: Double, proteinG: Double, score: Int?, mealCount: Int),
        todayNet: (net: Int, consumed: Int, burned: Int)
    ) -> MetricFloatingAiInsight {
        let goals = store.effectiveNutritionGoals
        switch activeTab {
        case .score:
            if let s = todayTotals.score {
                let pill = s >= 78 ? "Calidad nutricional sólida" : (s >= 55 ? "Puntuación aceptable" : "La puntuación bajó")
                let msg = "Tu puntuación de nutrición hoy es \(s)/100 con \(todayTotals.mealCount) evento(s). Prioriza proteína magra, verduras y cereales integrales para impulsarla hacia 80+."
                return MetricFloatingAiInsight(shortPillText: pill, expandedHeadline: "PUNTUACIÓN DE NUTRICIÓN", shortExpandedMessage: msg, expandedMessage: msg, structureIndex: 0, variationSeed: 1)
            }
            let msg = "Todavía no has registrado comidas en esta fecha. Haz una foto o descríbela con Gemini IA para calcular tu puntuación real."
            return MetricFloatingAiInsight(shortPillText: "Sin comidas hoy", expandedHeadline: "PUNTUACIÓN DE NUTRICIÓN", shortExpandedMessage: msg, expandedMessage: msg, structureIndex: 0, variationSeed: 1)

        case .macroBalance:
            let pPct = Double(goals.proteinG) > 0 ? todayTotals.proteinG / Double(goals.proteinG) : 0
            let pill = todayTotals.mealCount == 0 ? "Sin macros registrados" : (pPct < 0.45 ? "Proteína muy baja" : (pPct >= 0.85 ? "Objetivo proteico en ruta" : "Equilibrio en progreso"))
            let msg = String(format: "Hoy llevas %.1f g de grasas, %.1f g de carbos y %.1f g de proteína frente a tu meta de %d g de proteína.", locale: Locale(identifier: "es_ES"), todayTotals.fatG, todayTotals.carbsG, todayTotals.proteinG, goals.proteinG)
            return MetricFloatingAiInsight(shortPillText: pill, expandedHeadline: "EQUILIBRIO MACRO", shortExpandedMessage: msg, expandedMessage: msg, structureIndex: 1, variationSeed: 2)

        case .netEnergy:
            let eq = netEnergyBalanceLabel(todayNet.net)
            let pill = "\(eq.label): \(todayNet.net) kcal"
            let msg = "Has consumido \(todayNet.consumed) kcal frente a \(todayNet.burned) kcal quemadas estimadas (metabolismo basal + energía activa), dejando un balance neto de \(todayNet.net) kcal."
            return MetricFloatingAiInsight(shortPillText: pill, expandedHeadline: "ENERGÍA NETA", shortExpandedMessage: msg, expandedMessage: msg, structureIndex: 2, variationSeed: 3)
        }
    }
}

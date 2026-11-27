import SwiftUI
import UIKit

// MARK: - Persisted Nutrient Detail Screen (Proteína, Carbos, Grasas, Cafeína, Hidratación, Alcohol, Calcio)

struct NutrientDetailScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void
    var onAskCoach: (() -> Void)? = nil

    @State private var showCustomInputSheet: Bool = false
    @State private var customAmountText: String = ""
    @State private var showResetConfirmation: Bool = false

    var body: some View {
        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: store.userProfile)
        let goals = store.effectiveNutritionGoals
        let key = store.selectedNutrientKey.isEmpty ? "Proteína" : store.selectedNutrientKey
        let low = key.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))

        let spec = nutrientSpec(for: low, norms: norms, goals: goals)
        let mealsVal = spec.mealsContribution
        let manualVal = store.manualNutrientAmount(for: key)
        let totalVal = mealsVal + manualVal
        let frac = spec.goal > 0 ? min(max(totalVal / spec.goal, 0.0), 1.0) : 0.0

        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DetailSheetHeader(
                        title: spec.displayTitle,
                        onBack: onBack,
                        rightSystemIcon: manualVal > 0 ? "arrow.counterclockwise" : "plus.circle",
                        onRightAction: {
                            if manualVal > 0 {
                                showResetConfirmation = true
                            } else {
                                customAmountText = ""
                                showCustomInputSheet = true
                            }
                        }
                    )

                    nutrientGaugeCard(spec: spec, totalVal: totalVal, frac: frac)
                    if low.contains("cafe") {
                        CaffeineWindowCard(store: store, onAskCoach: onAskCoach)
                            .padding(.horizontal, 16)
                    }
                    nutrientEntriesSection(spec: spec, manualVal: manualVal)
                }
                .padding(.bottom, 185)
            }

            nutrientBottomActionBar(spec: spec, key: key)
        }
        .background(BevelColors.sheetHeaderBg)
        .confirmationDialog(
            "¿Restablecer el registro manual de \(spec.displayTitle.lowercased()) de este día?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restablecer a 0", role: .destructive) { store.resetNutrientAmount(key: key) }
            Button("Cancelar", role: .cancel) {}
        }
        .sheet(isPresented: $showCustomInputSheet) {
            customNutrientInputSheet(spec: spec, key: key)
        }
    }

    private func nutrientGaugeCard(spec: NutrientSpec, totalVal: Double, frac: Double) -> some View {
        BevelCard(cornerRadius: 22) {
            VStack(spacing: 6) {
                HStack {
                    Text("\(spec.formatValue(totalVal)) / \(spec.formatValue(spec.goal)) \(spec.unit)")
                        .font(ImprovingFont.caption(13))
                        .monospacedDigit()
                        .foregroundColor(BevelColors.textSecondary)
                    Spacer()
                    Text("\(Int((frac * 100).rounded()))%")
                        .font(ImprovingFont.caption(13))
                        .monospacedDigit()
                        .foregroundColor(spec.accentColor)
                }

                ZStack {
                    Canvas { ctx, sz in
                        let center = CGPoint(x: sz.width / 2, y: sz.height * 0.78)
                        let r = min(sz.width * 0.36, sz.height * 0.72)
                        var track = Path()
                        track.addArc(center: center, radius: r, startAngle: .degrees(165), endAngle: .degrees(375), clockwise: false)
                        ctx.stroke(track, with: .color(Color.white.opacity(0.08)), style: StrokeStyle(lineWidth: 14, lineCap: .round))

                        if totalVal > 0 {
                            let arcFrac = max(frac, 0.02)
                            let endDeg = 165.0 + 210.0 * arcFrac
                            var prog = Path()
                            prog.addArc(center: center, radius: r, startAngle: .degrees(165), endAngle: .degrees(endDeg), clockwise: false)
                            ctx.stroke(prog, with: .color(spec.accentColor), style: StrokeStyle(lineWidth: 14, lineCap: .round))

                            let rad = endDeg * .pi / 180.0
                            let pt = CGPoint(x: center.x + r * cos(rad), y: center.y + r * sin(rad))
                            ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 8, y: pt.y - 8, width: 16, height: 16)), with: .color(.white))
                            ctx.stroke(Path(ellipseIn: CGRect(x: pt.x - 8, y: pt.y - 8, width: 16, height: 16)), with: .color(spec.accentColor), lineWidth: 3)
                        }
                    }
                    .frame(height: 150)

                    VStack(spacing: 2) {
                        Text("\(spec.formatValue(totalVal)) \(spec.unit)")
                            .font(ImprovingFont.displayLarge(28))
                            .monospacedDigit()
                            .foregroundColor(BevelColors.textPrimary)
                        Text(spec.isUpperLimit
                             ? "límite orientativo \(spec.formatValue(spec.goal)) \(spec.unit)"
                             : "faltan \(spec.formatValue(max(spec.goal - totalVal, 0))) \(spec.unit)")
                            .font(ImprovingFont.caption(12.5))
                            .foregroundColor(BevelColors.textSecondary)
                    }
                    .offset(y: 12)
                }

                HStack {
                    Text("0").font(ImprovingFont.caption(12)).foregroundColor(BevelColors.textMuted)
                    Spacer()
                    Text("\(spec.formatValue(spec.goal)) \(spec.unit)").font(ImprovingFont.caption(12)).foregroundColor(BevelColors.textMuted)
                }
                .padding(.horizontal, 40)
            }
            .padding(16)
        }
        .padding(.horizontal, 16)
    }

    private func nutrientEntriesSection(spec: NutrientSpec, manualVal: Double) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Entradas registradas · \(store.dateLabel)")
                    .font(ImprovingFont.sectionTitle(17))
                    .foregroundColor(BevelColors.textPrimary)
                Spacer()
                if manualVal > 0 {
                    Button("Borrar manual") { showResetConfirmation = true }
                        .font(ImprovingFont.caption(12))
                        .foregroundColor(BevelColors.coralHigh)
                }
            }
            .padding(.horizontal, 16)

            VStack(spacing: 10) {
                if manualVal > 0 {
                    nutrientEntryRow(
                        emoji: spec.emoji,
                        time: store.dateLabel,
                        title: spec.isHydration
                            ? "Agua registrada (\(Int((manualVal / 250.0).rounded())) vasos)"
                            : "Registro directo de \(spec.displayTitle.lowercased())",
                        meta: "Guardado permanentemente en este día",
                        amount: "+\(spec.formatValue(manualVal)) \(spec.unit)"
                    )
                }

                if !spec.isHydration {
                    let matchingMeals = store.mealsToday.filter { spec.mealExtractor($0) > 0 }
                    ForEach(matchingMeals) { meal in
                        let val = spec.mealExtractor(meal)
                        nutrientEntryRow(
                            emoji: meal.emoji ?? "🍽️",
                            time: meal.timeLabel,
                            title: meal.title,
                            meta: "🔥 \(meal.kcal) kcal · Calidad \(meal.qualityScore)",
                            amount: "\(spec.formatValue(val)) \(spec.unit)"
                        )
                    }

                    if manualVal <= 0 && matchingMeals.isEmpty {
                        BevelCard(cornerRadius: 16) {
                            Text("No hay registros de \(spec.displayTitle.lowercased()) en esta fecha. Usa los botones inferiores o registra una comida con IA.")
                                .font(ImprovingFont.body(13.5))
                                .foregroundColor(BevelColors.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                        }
                    }
                } else if manualVal <= 0 {
                    BevelCard(cornerRadius: 16) {
                        Text("No has registrado hidratación este día. Pulsa abajo para añadir un vaso de 250 ml o una cantidad personalizada.")
                            .font(ImprovingFont.body(13.5))
                            .foregroundColor(BevelColors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func nutrientBottomActionBar(spec: NutrientSpec, key: String) -> some View {
        HStack(spacing: 12) {
            Button {
                AppHaptics.selection()
                store.addNutrientAmount(key: key, amount: spec.quickIncrement)
            } label: {
                Text(spec.quickButtonLabel)
                    .font(ImprovingFont.cardTitle(14.5))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(spec.accentColor.opacity(0.85)))
            }

            Button {
                customAmountText = ""
                showCustomInputSheet = true
            } label: {
                Text("+ Añadir cantidad")
                    .font(ImprovingFont.cardTitle(14.5))
                    .foregroundColor(BevelColors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(BevelColors.cardHeaderStrip))
                    .overlay(Capsule().strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 98)
    }

    private func customNutrientInputSheet(spec: NutrientSpec, key: String) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Introduce la cantidad exacta de \(spec.displayTitle.lowercased()) (\(spec.unit)) para añadir al día \(store.dateLabel).")
                    .font(ImprovingFont.body(14))
                    .foregroundColor(BevelColors.textSecondary)

                TextField("Ej: \(spec.formatValue(spec.quickIncrement * 1.5))", text: $customAmountText)
                    .keyboardType(.decimalPad)
                    .keyboardDoneToolbar()
                    .font(ImprovingFont.displayLarge(28))
                    .monospacedDigit()
                    .foregroundColor(BevelColors.textPrimary)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(BevelColors.card))

                Button {
                    let val = Double(customAmountText.replacingOccurrences(of: ",", with: ".")) ?? 0
                    if val > 0 { store.addNutrientAmount(key: key, amount: val) }
                    showCustomInputSheet = false
                } label: {
                    Text("Guardar \(spec.unit)")
                        .font(ImprovingFont.cardTitle(15))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(BevelColors.emeraldEnd))
                }
                Spacer()
            }
            .padding(20)
            .background(BevelColors.canvas)
            .navigationTitle("Añadir \(spec.displayTitle)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cerrar") { showCustomInputSheet = false } } }
        }
        .presentationDetents([.height(290)])
    }

    private struct NutrientSpec {
        let displayTitle: String
        let emoji: String
        let unit: String
        let goal: Double
        let quickIncrement: Double
        let quickButtonLabel: String
        let accentColor: Color
        let isHydration: Bool
        let isUpperLimit: Bool
        let mealsContribution: Double
        let mealExtractor: (NutritionMealItem) -> Double
        let formatValue: (Double) -> String
    }

    private func nutrientSpec(
        for lowKey: String,
        norms: PersonalizedPhysiologyNorms,
        goals: (kcal: Int, fatG: Int, carbsG: Int, proteinG: Int)
    ) -> NutrientSpec {
        let intFmt: (Double) -> String = { "\(Int($0.rounded()))" }
        let decFmt: (Double) -> String = { String(format: "%.1f", locale: Locale(identifier: "es_ES"), $0) }

        if lowKey.contains("prote") {
            return NutrientSpec(
                displayTitle: "Proteína", emoji: "🍗", unit: "g", goal: Double(max(goals.proteinG, 60)),
                quickIncrement: 25, quickButtonLabel: "+ 25 g proteína",
                accentColor: NutritionPalette.proteinPink, isHydration: false, isUpperLimit: false,
                mealsContribution: Double(store.mealsToday.reduce(0) { $0 + $1.proteinG }),
                mealExtractor: { Double($0.proteinG) }, formatValue: intFmt
            )
        } else if lowKey.contains("carb") {
            return NutrientSpec(
                displayTitle: "Carbohidratos", emoji: "🌾", unit: "g", goal: Double(max(goals.carbsG, 80)),
                quickIncrement: 30, quickButtonLabel: "+ 30 g carbos",
                accentColor: NutritionPalette.carbsAmber, isHydration: false, isUpperLimit: false,
                mealsContribution: Double(store.mealsToday.reduce(0) { $0 + $1.carbsG }),
                mealExtractor: { Double($0.carbsG) }, formatValue: intFmt
            )
        } else if lowKey.contains("gras") {
            return NutrientSpec(
                displayTitle: "Grasas", emoji: "🥑", unit: "g", goal: Double(max(goals.fatG, 40)),
                quickIncrement: 10, quickButtonLabel: "+ 10 g grasas",
                accentColor: NutritionPalette.fatBlue, isHydration: false, isUpperLimit: false,
                mealsContribution: Double(store.mealsToday.reduce(0) { $0 + $1.fatG }),
                mealExtractor: { Double($0.fatG) }, formatValue: intFmt
            )
        } else if lowKey.contains("hidra") || lowKey.contains("agua") {
            let goalMl = store.effectiveHydrationGoalMl
            return NutrientSpec(
                displayTitle: "Hidratación", emoji: "💧", unit: "ml", goal: goalMl,
                quickIncrement: 250, quickButtonLabel: "+ Añadir 250 ml",
                accentColor: BevelColors.skyBlue, isHydration: true, isUpperLimit: false,
                mealsContribution: 0, mealExtractor: { _ in 0 }, formatValue: intFmt
            )
        } else if lowKey.contains("cafe") {
            let cap = max(norms.caffeineLimitMg, 100.0)
            return NutrientSpec(
                displayTitle: "Cafeína", emoji: "☕", unit: "mg", goal: cap,
                quickIncrement: 80, quickButtonLabel: "+ Café (80 mg)",
                accentColor: BevelColors.limeStart, isHydration: false, isUpperLimit: true,
                mealsContribution: store.mealsToday.compactMap(\.caffeineMg).reduce(0, +),
                mealExtractor: { $0.caffeineMg ?? 0 }, formatValue: intFmt
            )
        } else if lowKey.contains("alco") {
            return NutrientSpec(
                displayTitle: "Alcohol", emoji: "🍷", unit: "bebidas", goal: 2.0,
                quickIncrement: 1.0, quickButtonLabel: "+ 1 bebida",
                accentColor: BevelColors.coralHigh, isHydration: false, isUpperLimit: true,
                mealsContribution: store.mealsToday.compactMap(\.alcoholDrinks).reduce(0, +),
                mealExtractor: { $0.alcoholDrinks ?? 0 }, formatValue: decFmt
            )
        } else {
            return NutrientSpec(
                displayTitle: "Calcio", emoji: "🦴", unit: "mg", goal: 1000.0,
                quickIncrement: 200, quickButtonLabel: "+ 200 mg calcio",
                accentColor: BevelColors.periwinkleStart, isHydration: false, isUpperLimit: false,
                mealsContribution: store.mealsToday.compactMap(\.calciumMg).reduce(0, +),
                mealExtractor: { $0.calciumMg ?? 0 }, formatValue: intFmt
            )
        }
    }

    private func nutrientEntryRow(emoji: String, time: String, title: String, meta: String?, amount: String) -> some View {
        BevelCard(cornerRadius: 18) {
            HStack(spacing: 12) {
                Text(emoji)
                    .font(.system(size: 20))
                    .frame(width: 42, height: 42)
                    .background(RoundedRectangle(cornerRadius: 12).fill(BevelColors.cardSubtle))

                VStack(alignment: .leading, spacing: 3) {
                    Text(time).font(ImprovingFont.caption(11.5)).foregroundColor(BevelColors.textMuted)
                    Text(title).font(ImprovingFont.cardTitle(14.5)).foregroundColor(BevelColors.textPrimary).lineLimit(1)
                    if let meta {
                        Text(meta).font(ImprovingFont.caption(11.5)).foregroundColor(BevelColors.textSecondary).lineLimit(1)
                    }
                }
                Spacer()
                Text(amount).font(ImprovingFont.cardTitle(14)).monospacedDigit().foregroundColor(BevelColors.textPrimary)
            }
            .padding(14)
        }
    }
}

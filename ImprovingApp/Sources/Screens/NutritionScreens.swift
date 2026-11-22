import SwiftUI

struct NutricionScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void
    let onOpenNutrient: (String) -> Void

    var body: some View {
        let meals = store.mealsByDate[store.selectedDateIso] ?? []
        let totalKcal = meals.reduce(0) { $0 + $1.kcal }
        let totalProt = meals.reduce(0) { $0 + $1.proteinG }
        let totalCarbs = meals.reduce(0) { $0 + $1.carbsG }
        let totalFat = meals.reduce(0) { $0 + $1.fatG }
        let glasses = store.hydrationGlassesByDate[store.selectedDateIso] ?? 8
        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: store.userProfile)
        let avgQuality = meals.isEmpty ? 86 : meals.reduce(0) { $0 + $1.qualityScore } / meals.count

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DetailSheetHeader(title: "Nutrición", onBack: onBack)

                // 1. Hero Nutrition Quality & Macros Card
                BevelCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("ENERGÍA INGERIDA HOY")
                                    .font(ImprovingFont.microLabel(11))
                                    .foregroundColor(BevelColors.textSecondary)
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text("\(totalKcal)")
                                        .font(ImprovingFont.displayLarge(32))
                                        .monospacedDigit()
                                        .foregroundColor(BevelColors.textPrimary)
                                    Text("/ \(norms.bmrKcal + 550) kcal")
                                        .font(ImprovingFont.caption(13))
                                        .foregroundColor(BevelColors.textSecondary)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Calidad \(avgQuality)")
                                    .font(ImprovingFont.cardTitle(14))
                                    .foregroundColor(BevelColors.emeraldEnd)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(BevelColors.greenSoftBg))
                                Text("CGM 94 mg/dL")
                                    .font(ImprovingFont.caption(11.5))
                                    .foregroundColor(BevelColors.textSecondary)
                            }
                        }

                        HStack(spacing: 10) {
                            Button { onOpenNutrient("Proteína") } label: {
                                macroPill("Proteína", "\(totalProt)g", target: "\(norms.proteinGoalG)g", color: BevelColors.emeraldEnd)
                            }
                            Button { onOpenNutrient("Carbohidratos") } label: {
                                macroPill("Carbos", "\(totalCarbs)g", target: "210g", color: BevelColors.skyBlue)
                            }
                            Button { onOpenNutrient("Grasas") } label: {
                                macroPill("Grasas", "\(totalFat)g", target: "70g", color: BevelColors.amberStart)
                            }
                        }

                        HStack(spacing: 10) {
                            Button {
                                store.addQuickMeal(title: "Snack proteico + fruta", kcal: 320, protein: 28, carbs: 34, fat: 8)
                            } label: {
                                Text("+ Registrar comida")
                                    .font(ImprovingFont.caption(12.5))
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(BevelColors.emeraldEnd))
                            }

                            Button { store.addHydrationGlass() } label: {
                                Label(String(format: "%.2f / %.1f L", Double(glasses) * 0.25, norms.hydrationGoalLiters), systemImage: "drop.fill")
                                    .font(ImprovingFont.caption(12.5))
                                    .fontWeight(.bold)
                                    .foregroundColor(BevelColors.skyBlue)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(BevelColors.skySoftBg))
                            }
                        }
                    }
                    .padding(16)
                }
                .padding(.horizontal, 16)

                // 2. Registro de comidas de hoy
                Text("Comidas de hoy (\(meals.count))")
                    .font(ImprovingFont.sectionTitle(18))
                    .foregroundColor(BevelColors.textPrimary)
                    .padding(.horizontal, 16)

                ForEach(meals) { meal in
                    Button { onOpenNutrient("Proteína") } label: {
                        BevelCard(cornerRadius: 18) {
                            HStack(spacing: 12) {
                                Text(meal.emoji)
                                    .font(.system(size: 20))
                                    .frame(width: 44, height: 44)
                                    .background(RoundedRectangle(cornerRadius: 14).fill(BevelColors.greenSoftBg))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(meal.name)
                                        .font(ImprovingFont.cardTitle(14.5))
                                        .foregroundColor(BevelColors.textPrimary)
                                        .lineLimit(1)
                                    Text("\(meal.time) · \(meal.kcal) kcal · \(meal.proteinG)g P · \(meal.carbsG)g C · \(meal.fatG)g G")
                                        .font(ImprovingFont.caption(11.5))
                                        .foregroundColor(BevelColors.textSecondary)
                                }
                                Spacer()
                                Text("\(meal.qualityScore)")
                                    .font(ImprovingFont.caption(12))
                                    .fontWeight(.bold)
                                    .foregroundColor(BevelColors.emeraldEnd)
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(BevelColors.greenSoftBg))
                            }
                            .padding(14)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 120)
        }
        .background(BevelColors.canvas)
    }

    private func macroPill(_ title: String, _ val: String, target: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(ImprovingFont.caption(11.5)).foregroundColor(BevelColors.textSecondary)
            Text(val).font(ImprovingFont.metricHero(18)).monospacedDigit().foregroundColor(BevelColors.textPrimary)
            Text("Meta \(target)").font(ImprovingFont.caption(11)).foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(BevelColors.surfaceOverlay))
    }
}

struct NutrientDetailScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void

    var body: some View {
        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: store.userProfile)
        let title = store.selectedNutrientKey.isEmpty ? "Proteína" : store.selectedNutrientKey
        let pts: [Double] = [118, 124, 132, 128, 140, 136, 126]

        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DetailSheetHeader(title: title, onBack: onBack)

                    BevelCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .bottom) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("126 g")
                                        .font(ImprovingFont.displayLarge(31))
                                        .monospacedDigit()
                                        .foregroundColor(BevelColors.textPrimary)
                                    Text(store.dateLabel)
                                        .font(ImprovingFont.caption(12))
                                        .foregroundColor(BevelColors.textSecondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("Objetivo óptimo")
                                        .font(ImprovingFont.caption(12))
                                        .fontWeight(.semibold)
                                        .foregroundColor(BevelColors.emeraldEnd)
                                    Text("\(norms.proteinGoalG - 15) – \(norms.proteinGoalG + 15) g")
                                        .font(ImprovingFont.caption(12))
                                        .foregroundColor(BevelColors.textSecondary)
                                }
                            }

                            HealthMetricBaselineChart(
                                points: pts,
                                dates: ["15 nov", "16 nov", "17 nov", "18 nov", "19 nov", "20 nov", "Hoy"],
                                bandLow: Double(norms.proteinGoalG - 15),
                                bandHigh: Double(norms.proteinGoalG + 15),
                                averageText: "Prom. 129 g",
                                accentColor: BevelColors.emeraldEnd,
                                valueFormatter: { v in "\(Int(v)) g" }
                            )
                        }
                        .padding(16)
                    }
                    .padding(.horizontal, 16)

                    BevelCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("OBJETIVO DIARIO PERSONALIZADO")
                                .font(ImprovingFont.microLabel(11))
                                .foregroundColor(BevelColors.emeraldEnd)
                            Text("Seguimiento directo vinculado a tu masa corporal (\(Int(store.userProfile.weightKg)) kg) y síntesis proteica post-esfuerzo.")
                                .font(ImprovingFont.body(13.5))
                                .foregroundColor(BevelColors.textPrimary)
                        }
                        .padding(16)
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 180)
            }

            HStack(spacing: 10) {
                Button {
                    store.addQuickMeal(title: "Batido Whey Isolate", kcal: 160, protein: 32, carbs: 4, fat: 2)
                } label: {
                    Text("+ Añadir registro")
                        .font(ImprovingFont.cardTitle(13.5))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(BevelColors.emeraldEnd))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 92)
        }
        .background(BevelColors.canvas)
    }
}

import SwiftUI

struct NutricionScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void
    let onOpenNutrient: (String) -> Void

    var body: some View {
        let meals = store.mealsByDate[store.selectedDateIso] ?? []
        let totalKcal = meals.reduce(0) { $0 + $1.kcal }
        let totalProt = meals.reduce(0) { $0 + $1.proteinG }
        let glasses = store.hydrationGlassesByDate[store.selectedDateIso] ?? 0
        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: store.userProfile)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DetailSheetHeader(title: "Nutrición", onBack: onBack)

                BevelCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("ENERGÍA INGERIDA").font(ImprovingFont.microLabel(11)).foregroundColor(BevelColors.textSecondary)
                                Text("\(totalKcal) kcal").font(ImprovingFont.displayLarge(28)).monospacedDigit().foregroundColor(BevelColors.textPrimary)
                            }
                            Spacer()
                            Button {
                                store.addQuickMeal(title: "Comida equilibrada", kcal: 540, protein: 38, carbs: 54, fat: 18)
                            } label: {
                                Text("+ Comida rápida")
                                    .font(ImprovingFont.caption(12))
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Capsule().fill(BevelColors.emeraldEnd))
                            }
                        }

                        HStack(spacing: 10) {
                            Button { onOpenNutrient("proteina") } label: {
                                macroPill("Proteína", "\(totalProt)g")
                            }
                            Button { onOpenNutrient("hidratacion") } label: {
                                macroPill("Agua", String(format: "%.2f / %.1f L", Double(glasses) * 0.25, norms.hydrationGoalLiters))
                            }
                        }

                        Button { store.addHydrationGlass() } label: {
                            Label("Añadir vaso de agua (250 ml)", systemImage: "drop.fill")
                                .font(ImprovingFont.cardTitle(13.5))
                                .foregroundColor(BevelColors.skyBlue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 12).fill(BevelColors.skySoftBg))
                        }
                    }
                    .padding(16)
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 120)
        }
        .background(BevelColors.canvas)
    }

    private func macroPill(_ title: String, _ val: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(ImprovingFont.caption(11)).foregroundColor(BevelColors.textSecondary)
            Text(val).font(ImprovingFont.cardTitle(14)).monospacedDigit().foregroundColor(BevelColors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(BevelColors.cardSubtle))
    }
}

struct NutrientDetailScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DetailSheetHeader(title: store.selectedNutrientKey.capitalized, onBack: onBack)
                    BevelCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("OBJETIVO DIARIO PERSONALIZADO")
                                .font(ImprovingFont.microLabel(11))
                                .foregroundColor(BevelColors.emeraldEnd)
                            Text("Seguimiento directo vinculado a tu masa corporal (\(Int(store.userProfile.weightKg)) kg) y recuperación.")
                                .font(ImprovingFont.body(14))
                                .foregroundColor(BevelColors.textPrimary)
                        }
                        .padding(16)
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 176)
            }

            HStack(spacing: 10) {
                Button {
                    store.addQuickMeal(title: "Refuerzo nutricional", kcal: 240, protein: 26, carbs: 18, fat: 6)
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

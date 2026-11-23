import SwiftUI

struct NutricionScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void
    let onOpenNutrient: (String) -> Void

    var body: some View {
        let meals = store.mealsToday
        let glasses = store.hydrationGlassesByDate[store.selectedDateIso] ?? 0
        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: store.userProfile)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DetailSheetHeader(title: "Nutrición", onBack: onBack, rightSystemIcon: "gearshape.fill")

                BevelCard(cornerRadius: 22) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("ENERGÍA INGERIDA HOY")
                                    .font(ImprovingFont.microLabel(11))
                                    .foregroundColor(BevelColors.textMuted)
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text("\(store.totalCaloriesToday)")
                                        .font(ImprovingFont.displayLarge(32))
                                        .monospacedDigit()
                                        .foregroundColor(BevelColors.textPrimary)
                                    Text("/ \(norms.maintenanceCaloriesKcal) kcal")
                                        .font(ImprovingFont.caption(13))
                                        .foregroundColor(BevelColors.textSecondary)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                if let fq = store.foodQualityScore {
                                    Text("Calidad \(fq)")
                                        .font(ImprovingFont.cardTitle(13.5))
                                        .foregroundColor(BevelColors.greenPrimary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Capsule().fill(BevelColors.greenSoftBg))
                                }
                                if let cgm = store.cgmMgDl {
                                    Text("CGM \(cgm) mg/dL")
                                        .font(ImprovingFont.caption(11.5))
                                        .foregroundColor(BevelColors.textSecondary)
                                }
                            }
                        }

                        HStack(spacing: 10) {
                            Button { onOpenNutrient("Calcio") } label: {
                                macroPill("Proteína", "\(store.totalProteinToday)g", target: "\(norms.proteinGoalG)g", color: BevelColors.strengthPink)
                            }
                            Button { onOpenNutrient("Cafeína") } label: {
                                macroPill("Carbos", "\(store.totalCarbsToday)g", target: "\(norms.carbsGoalG)g", color: BevelColors.amberStart)
                            }
                            Button { onOpenNutrient("Hidratación") } label: {
                                macroPill("Grasas", "\(store.totalFatToday)g", target: "\(norms.fatGoalG)g", color: BevelColors.skyBlue)
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
                                    .background(Capsule().fill(BevelColors.emeraldEnd))
                            }

                            Button { store.addHydrationGlass() } label: {
                                Label(String(format: "%.2f / %.1f L", Double(glasses) * 0.25, norms.hydrationGoalLiters), systemImage: "drop.fill")
                                    .font(ImprovingFont.caption(12.5))
                                    .fontWeight(.bold)
                                    .foregroundColor(BevelColors.skyBlue)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                                    .background(Capsule().fill(BevelColors.skySoftBg))
                            }
                        }
                    }
                    .padding(16)
                }
                .padding(.horizontal, 16)

                Text("Entradas de hoy (\(meals.count))")
                    .font(ImprovingFont.sectionTitle(18))
                    .foregroundColor(BevelColors.textPrimary)
                    .padding(.horizontal, 16)

                ForEach(Array(meals.enumerated()), id: \.element.id) { idx, meal in
                    Button { onOpenNutrient("Calcio") } label: {
                        BevelCard(cornerRadius: 18) {
                            HStack(spacing: 12) {
                                Text(["🥣", "🐟", "🥗", "🍪"][idx % 4])
                                    .font(.system(size: 20))
                                    .frame(width: 44, height: 44)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(BevelColors.cardSubtle))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(meal.timeLabel).font(ImprovingFont.caption(11.5)).foregroundColor(BevelColors.textMuted)
                                    Text(meal.title)
                                        .font(ImprovingFont.cardTitle(14.5))
                                        .foregroundColor(BevelColors.textPrimary)
                                        .lineLimit(1)
                                    Text("🍎 \(meal.kcal) kcal   🧪 \(meal.fatG)   🌾 \(meal.carbsG)   🍗 \(meal.proteinG)")
                                        .font(ImprovingFont.caption(11.5))
                                        .foregroundColor(BevelColors.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 12))
                                    .foregroundColor(BevelColors.textMuted)
                            }
                            .padding(14)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 150)
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
        .background(RoundedRectangle(cornerRadius: 14).fill(BevelColors.cardSubtle))
    }
}

// MARK: - Exact Nutrient Detail Sheet (Literal Match to Screenshots 41, 43, 44, 45)

struct NutrientDetailScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void

    @State private var extraAmount: Double = 0

    var body: some View {
        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: store.userProfile)
        let caffeineCap = max(norms.caffeineLimitMg, 100.0)
        let hydrationGoalMl = max(norms.hydrationGoalLiters * 1000.0, 1800.0)

        let key = store.selectedNutrientKey.isEmpty ? "Cafeína" : store.selectedNutrientKey
        let isCaffeine = key.localizedCaseInsensitiveContains("cafe")
        let isHydration = key.localizedCaseInsensitiveContains("hidra")
        let isAlcohol = key.localizedCaseInsensitiveContains("alco")

        let quickIncrement: Double = isHydration ? 250.0 : (isAlcohol ? 1.0 : (isCaffeine ? 50.0 : 100.0))
        let quickButtonTitle: String = isHydration
            ? "Añadir 250,0 ml"
            : (isAlcohol ? "+ Añadir 1 bebidas" : (isCaffeine ? "+ Añadir 50mg" : "+ Añadir 100mg"))

        let glassesToday = store.hydrationGlassesByDate[store.selectedDateIso] ?? 0
        let baseVal: Double = isHydration ? Double(glassesToday) * 250.0 : 0.0
        let totalVal = baseVal + extraAmount

        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DetailSheetHeader(title: key, onBack: onBack, rightSystemIcon: "gearshape.fill")

                    // Cafeína Semi-Circle Arc Gauge Card (Personalized by age & weight!)
                    if isCaffeine {
                        BevelCard(cornerRadius: 22) {
                            VStack(spacing: 6) {
                                HStack {
                                    Text(String(format: "%.1f/%.0fmg", locale: Locale(identifier: "es_ES"), totalVal, caffeineCap))
                                        .font(ImprovingFont.caption(13))
                                        .foregroundColor(BevelColors.textSecondary)
                                    Spacer()
                                    Text("\(min(Int((totalVal / caffeineCap * 100).rounded()), 100))%")
                                        .font(ImprovingFont.caption(13))
                                        .foregroundColor(BevelColors.textSecondary)
                                }

                                ZStack {
                                    Canvas { ctx, sz in
                                        let center = CGPoint(x: sz.width / 2, y: sz.height * 0.78)
                                        let r = min(sz.width * 0.36, sz.height * 0.72)
                                        var track = Path()
                                        track.addArc(center: center, radius: r, startAngle: .degrees(165), endAngle: .degrees(375), clockwise: false)
                                        ctx.stroke(track, with: .color(Color.white.opacity(0.08)), style: StrokeStyle(lineWidth: 14, lineCap: .round))

                                        let frac = min(max(totalVal / caffeineCap, 0.02), 1.0)
                                        let endDeg = 165.0 + 210.0 * frac
                                        var prog = Path()
                                        prog.addArc(center: center, radius: r, startAngle: .degrees(165), endAngle: .degrees(endDeg), clockwise: false)
                                        ctx.stroke(prog, with: .color(BevelColors.limeStart), style: StrokeStyle(lineWidth: 14, lineCap: .round))

                                        let rad = endDeg * .pi / 180.0
                                        let pt = CGPoint(x: center.x + r * cos(rad), y: center.y + r * sin(rad))
                                        ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 8, y: pt.y - 8, width: 16, height: 16)), with: .color(.white))
                                        ctx.stroke(Path(ellipseIn: CGRect(x: pt.x - 8, y: pt.y - 8, width: 16, height: 16)), with: .color(BevelColors.greenPrimary), lineWidth: 3)
                                    }
                                    .frame(height: 150)

                                    VStack(spacing: 2) {
                                        Text(String(format: "%.1fmg", locale: Locale(identifier: "es_ES"), max(caffeineCap - totalVal, 0)))
                                            .font(ImprovingFont.displayLarge(28))
                                            .monospacedDigit()
                                            .foregroundColor(BevelColors.textPrimary)
                                        Text("faltan")
                                            .font(ImprovingFont.caption(13))
                                            .foregroundColor(BevelColors.textSecondary)
                                    }
                                    .offset(y: 12)
                                }

                                HStack {
                                    Text("0").font(ImprovingFont.caption(12)).foregroundColor(BevelColors.textMuted)
                                    Spacer()
                                    Text("\(Int(caffeineCap))").font(ImprovingFont.caption(12)).foregroundColor(BevelColors.textMuted)
                                }
                                .padding(.horizontal, 44)
                            }
                            .padding(16)
                        }
                        .padding(.horizontal, 16)
                    }

                    // Entradas de hoy Header (Screenshots 41, 43, 44, 45)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Entradas de hoy")
                                .font(ImprovingFont.sectionTitle(17))
                                .foregroundColor(BevelColors.textPrimary)
                            Spacer()
                            if isHydration {
                                HStack(spacing: 8) {
                                    Text(String(format: "%.0f/%.0f ml", locale: Locale(identifier: "es_ES"), totalVal, hydrationGoalMl))
                                        .font(ImprovingFont.caption(13.5))
                                        .monospacedDigit()
                                        .foregroundColor(BevelColors.textSecondary)
                                    ZStack {
                                        Circle().stroke(Color.white.opacity(0.1), lineWidth: 3).frame(width: 20, height: 20)
                                        Circle()
                                            .trim(from: 0, to: min(totalVal / hydrationGoalMl, 1.0))
                                            .stroke(BevelColors.skyBlue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                            .rotationEffect(.degrees(-90))
                                            .frame(width: 20, height: 20)
                                    }
                                }
                            } else if isAlcohol {
                                Text("\(Int(totalVal)) bebidas (\(Int(totalVal * 14))g)")
                                    .font(ImprovingFont.caption(13.5))
                                    .foregroundColor(BevelColors.textSecondary)
                            } else {
                                Text(String(format: "%.1fmg", locale: Locale(identifier: "es_ES"), totalVal))
                                    .font(ImprovingFont.caption(13.5))
                                    .foregroundColor(BevelColors.textSecondary)
                            }
                        }

                        if !isHydration {
                            Text("Detectado por nutrición y registro manual.")
                                .font(ImprovingFont.caption(13))
                                .foregroundColor(BevelColors.textSecondary)
                        }
                    }
                    .padding(.horizontal, 16)

                    // Linked Food / Hydration Rows (Strictly real user-logged entries — ZERO invented foods!)
                    VStack(spacing: 10) {
                        if isHydration {
                            if glassesToday > 0 {
                                nutrientEntryRow(
                                    emoji: "💧",
                                    time: store.dateLabel,
                                    title: "Hidratación registrada (\(glassesToday) vasos)",
                                    meta: nil,
                                    amount: String(format: "%.0f ml", Double(glassesToday) * 250.0)
                                )
                            } else {
                                BevelCard(cornerRadius: 16) {
                                    Text("No has registrado hidratación este día. Pulsa abajo para añadir un vaso de 250 ml.")
                                        .font(ImprovingFont.body(13.5))
                                        .foregroundColor(BevelColors.textSecondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(14)
                                }
                            }
                        } else if !store.mealsToday.isEmpty {
                            ForEach(store.mealsToday) { meal in
                                nutrientEntryRow(
                                    emoji: "🍽️",
                                    time: meal.timeLabel,
                                    title: meal.title,
                                    meta: "🍎 \(meal.kcal) kcal  🍗 \(meal.proteinG)g  🌾 \(meal.carbsG)g  🧪 \(meal.fatG)g",
                                    amount: "\(meal.kcal) kcal"
                                )
                            }
                        } else if extraAmount > 0 {
                            nutrientEntryRow(
                                emoji: isCaffeine ? "☕" : (isAlcohol ? "🍷" : "✨"),
                                time: "Hoy",
                                title: "Registro manual de \(key.lowercased())",
                                meta: nil,
                                amount: isAlcohol ? "+\(Int(extraAmount)) bebidas" : String(format: "+%.0fmg", extraAmount)
                            )
                        } else {
                            BevelCard(cornerRadius: 16) {
                                Text("No hay registros de \(key.lowercased()) en esta fecha.")
                                    .font(ImprovingFont.body(13.5))
                                    .foregroundColor(BevelColors.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(14)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 185)
            }

            // Dual Bottom Action Pills (Screenshots 41, 43, 44, 45)
            HStack(spacing: 12) {
                Button {
                    if isHydration { store.addHydrationGlass() } else { extraAmount += quickIncrement }
                } label: {
                    Text(quickButtonTitle)
                        .font(ImprovingFont.cardTitle(14.5))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Color(hex: 0x6A6E7A)))
                }

                Button {
                    if isHydration { store.addHydrationGlass() } else { extraAmount += quickIncrement / 2.0 }
                } label: {
                    Text(isHydration ? "Añadir personal" : "+ Añadir personal")
                        .font(ImprovingFont.cardTitle(14.5))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(BevelColors.cardHeaderStrip))
                        .overlay(Capsule().strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 98)
        }
        .background(BevelColors.sheetHeaderBg)
    }

    private func nutrientEntryRow(emoji: String, time: String, title: String, meta: String?, amount: String) -> some View {
        BevelCard(cornerRadius: 18) {
            HStack(spacing: 12) {
                Text(emoji)
                    .font(.system(size: 20))
                    .frame(width: 42, height: 42)
                    .background(RoundedRectangle(cornerRadius: 12).fill(BevelColors.cardSubtle))
                VStack(alignment: .leading, spacing: 2) {
                    Text(time).font(ImprovingFont.caption(11.5)).foregroundColor(BevelColors.textMuted)
                    Text(title).font(ImprovingFont.cardTitle(14.5)).foregroundColor(BevelColors.textPrimary).lineLimit(1)
                    if let m = meta {
                        Text(m).font(ImprovingFont.caption(12)).foregroundColor(BevelColors.textSecondary)
                    }
                }
                Spacer()
                Text(amount)
                    .font(ImprovingFont.cardTitle(14))
                    .monospacedDigit()
                    .foregroundColor(BevelColors.textPrimary)
                Image(systemName: "arrow.right")
                    .font(.system(size: 12))
                    .foregroundColor(BevelColors.textMuted)
            }
            .padding(14)
        }
    }
}

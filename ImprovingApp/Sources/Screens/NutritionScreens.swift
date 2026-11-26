import SwiftUI
import UIKit
import PhotosUI

// MARK: - Meal Photo Storage Helper (Downscaled JPEG in Application Support)

enum MealPhotoStorage {
    private static let imageCache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 48
        c.totalCostLimit = 32 * 1024 * 1024
        return c
    }()

    private static var folderURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("MealPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func prepareJpegData(from image: UIImage, maxDimension: CGFloat = 1024, quality: CGFloat = 0.78) -> Data? {
        let sz = image.size
        guard sz.width > 1, sz.height > 1 else { return image.jpegData(compressionQuality: quality) }
        let maxSide = max(sz.width, sz.height)
        let targetImage: UIImage
        if maxSide > maxDimension {
            let ratio = maxDimension / maxSide
            let newSize = CGSize(width: floor(sz.width * ratio), height: floor(sz.height * ratio))
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1.0
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
            targetImage = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        } else {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1.0
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(size: sz, format: format)
            targetImage = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: sz))
            }
        }
        return targetImage.jpegData(compressionQuality: quality)
    }

    static func savePhotoData(_ data: Data, existingFilename: String? = nil) -> String? {
        let name = existingFilename ?? "meal_\(UUID().uuidString).jpg"
        let url = folderURL.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            if let img = UIImage(data: data) {
                imageCache.setObject(img, forKey: name as NSString, cost: data.count)
            } else {
                imageCache.removeObject(forKey: name as NSString)
            }
            return name
        } catch {
            return nil
        }
    }

    static func loadImage(filename: String?) -> UIImage? {
        guard let filename, !filename.isEmpty else { return nil }
        let key = filename as NSString
        if let cached = imageCache.object(forKey: key) {
            return cached
        }
        let url = folderURL.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url), let img = UIImage(data: data) else { return nil }
        imageCache.setObject(img, forKey: key, cost: data.count)
        return img
    }

    static func deletePhoto(filename: String?) {
        guard let filename, !filename.isEmpty else { return }
        imageCache.removeObject(forKey: filename as NSString)
        let url = folderURL.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Main Nutrition Screen (Exact Match to Screenshots 2–7 + Multimodal Gemini AI Scanner!)

private enum NutritionActiveSheet: Identifiable {
    case datePicker
    case share
    case info
    case goals
    case myFoods
    case recipeBuilder
    case fullTimeline
    case mealComposer(existing: NutritionMealItem?, mode: NutritionComposerInitialMode)
    case factorInfo(FoodQualityFactorKind)

    var id: String {
        switch self {
        case .datePicker: return "datePicker"
        case .share: return "share"
        case .info: return "info"
        case .goals: return "goals"
        case .myFoods: return "myFoods"
        case .recipeBuilder: return "recipeBuilder"
        case .fullTimeline: return "fullTimeline"
        case .mealComposer(let m, let mode): return "composer_\(m?.id ?? "new")_\(mode)"
        case .factorInfo(let f): return "factor_\(f.id)"
        }
    }
}

struct NutricionScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void
    let onOpenNutrient: (String) -> Void
    var onOpenTrends: ((NutritionTrendTab) -> Void)? = nil

    @State private var activeSheet: NutritionActiveSheet? = nil
    @State private var macroDetailsInPercent: Bool = false
    @State private var factorsExpanded: Bool = false

    var body: some View {
        let goals = store.effectiveNutritionGoals
        let todayTotals = store.nutritionDayTotals(for: store.selectedDateIso)
        let netInfo = store.netEnergyKcal(for: store.selectedDateIso)
        let scoreOpt = todayTotals.score
        let scoreStatus = store.nutritionScoreStatus(for: scoreOpt)
        let meals = store.mealsToday
        let libCounts = store.savedFoodsCounts
        let dailyFactors = store.dailyFoodQualityFactors(for: store.selectedDateIso)

        let remainingKcal = goals.kcal - todayTotals.kcal
        let remainingFat = goals.fatG - Int(todayTotals.fatG.rounded())
        let remainingCarbs = goals.carbsG - Int(todayTotals.carbsG.rounded())
        let remainingProt = goals.proteinG - Int(todayTotals.proteinG.rounded())

        let totalMacroG = max(todayTotals.fatG + todayTotals.carbsG + todayTotals.proteinG, 0.001)
        let fatPct = todayTotals.kcal > 0 || todayTotals.fatG > 0 ? Int((todayTotals.fatG / totalMacroG * 100.0).rounded()) : 0
        let carbsPct = todayTotals.kcal > 0 || todayTotals.carbsG > 0 ? Int((todayTotals.carbsG / totalMacroG * 100.0).rounded()) : 0
        let protPct = todayTotals.kcal > 0 || todayTotals.proteinG > 0 ? max(0, 100 - fatPct - carbsPct) : 0

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 1. Atmospheric Top Bar + Title + Date Selector + Ceramic Plate & Cutlery (Screenshot 2)
                ZStack(alignment: .top) {
                    LinearGradient(
                        colors: BevelColors.isDarkMode
                            ? [Color(hex: 0x262835), Color(hex: 0x1A1C24), BevelColors.canvas]
                            : [Color(hex: 0xEEF1F7), BevelColors.canvas],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea(edges: .top)

                    VStack(spacing: 14) {
                        // Top Navigation Pill Bar (<   |   [ Share  Info  ... ])
                        HStack {
                            Button(action: onBack) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .frame(width: 40, height: 40)
                                    .background(Circle().fill(BevelColors.glassChromeFill))
                                    .overlay(Circle().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.8))
                            }

                            Spacer()

                            HStack(spacing: 16) {
                                Button { activeSheet = .share } label: {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(BevelColors.textPrimary)
                                }
                                Button { activeSheet = .info } label: {
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(BevelColors.textPrimary)
                                }
                                Menu {
                                    Button {
                                        activeSheet = .mealComposer(existing: nil, mode: .standard)
                                    } label: {
                                        Label("Registrar comida con IA (foto/texto)", systemImage: "camera.viewfinder")
                                    }
                                    Button {
                                        activeSheet = .mealComposer(existing: nil, mode: .barcode)
                                    } label: {
                                        Label("Escanear código de barras (OpenFoodFacts)", systemImage: "barcode.viewfinder")
                                    }
                                    Button { activeSheet = .goals } label: {
                                        Label("Editar objetivos diarios", systemImage: "target")
                                    }
                                    Divider()
                                    Button { onOpenNutrient("Hidratación") } label: {
                                        Label("Hidratación (\(Int(store.totalHydrationTodayMl.rounded())) ml)", systemImage: "drop.fill")
                                    }
                                    Button { onOpenNutrient("Cafeína") } label: {
                                        Label("Cafeína (\(Int(store.totalCaffeineTodayMg.rounded())) mg)", systemImage: "cup.and.saucer.fill")
                                    }
                                    Button { onOpenNutrient("Alcohol") } label: {
                                        Label("Alcohol", systemImage: "wineglass.fill")
                                    }
                                    Button { onOpenNutrient("Calcio") } label: {
                                        Label("Calcio (\(Int(store.totalCalciumTodayMg.rounded())) mg)", systemImage: "sparkles")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(BevelColors.textPrimary)
                                }
                            }
                            .padding(.horizontal, 15)
                            .frame(height: 40)
                            .background(Capsule().fill(BevelColors.glassChromeFill))
                            .overlay(Capsule().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.8))
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                        // Title + Date Dropdown
                        VStack(spacing: 4) {
                            Text("Nutrición")
                                .font(ImprovingFont.displayLarge(25))
                                .foregroundColor(BevelColors.textPrimary)

                            Button { activeSheet = .datePicker } label: {
                                HStack(spacing: 5) {
                                    Text(store.fullDateLabel)
                                        .font(ImprovingFont.body(14.5))
                                        .foregroundColor(BevelColors.textSecondary)
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(BevelColors.textMuted)
                                }
                            }
                        }

                        // Plate + Fork + Knife Hero Gauge
                        NutritionHeroPlateWithCutlery(
                            score: scoreOpt,
                            statusLabel: scoreStatus.label,
                            statusColor: scoreStatus.color
                        )
                        .padding(.bottom, 4)
                    }
                }

                VStack(alignment: .leading, spacing: 16) {
                    // 2. "Mis alimentos" Notebook-Bound Card (Exact Screenshot 2!)
                    Button { activeSheet = .myFoods } label: {
                        ZStack(alignment: .leading) {
                            BevelCard(cornerRadius: 20) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Mis alimentos")
                                            .font(ImprovingFont.cardTitle(16))
                                            .foregroundColor(BevelColors.textPrimary)
                                        Text("\(libCounts.favorites) favoritos • \(libCounts.recipes) recetas • \(libCounts.meals) comidas")
                                            .font(ImprovingFont.caption(13))
                                            .foregroundColor(BevelColors.textSecondary)
                                    }
                                    .padding(.leading, 12)
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(BevelColors.textMuted)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 16)
                            }

                            // 3 Signature Spiral Notebook Loops on Left Edge
                            VStack(spacing: 11) {
                                ForEach(0..<3, id: \.self) { _ in
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color(hex: 0x6A6F7D), Color(hex: 0x3D414D)],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        .frame(width: 17, height: 5.5)
                                        .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                                }
                            }
                            .offset(x: -5)
                        }
                    }
                    .buttonStyle(.plain)

                    // 3. "Objetivos" Card (Calories 7-Day Mini Bars + 3 Macro Ring Cards — Exact Screenshot 2!)
                    BevelCard(cornerRadius: 22) {
                        VStack(alignment: .leading, spacing: 12) {
                            Button { activeSheet = .goals } label: {
                                HStack {
                                    Text("Objetivos")
                                        .font(ImprovingFont.sectionTitle(17))
                                        .foregroundColor(BevelColors.textPrimary)
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(BevelColors.textMuted)
                                }
                            }
                            .buttonStyle(.plain)

                            // Calorías Inner Card with 7-day mini bars + dotted goal line
                            Button { activeSheet = .goals } label: {
                                HStack(alignment: .center, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Calorías")
                                            .font(ImprovingFont.cardTitle(15))
                                            .foregroundColor(BevelColors.textPrimary)
                                        Text(remainingKcal >= 0 ? "Faltan \(remainingKcal)kcal" : "Superado +\(abs(remainingKcal))kcal")
                                            .font(ImprovingFont.caption(13))
                                            .monospacedDigit()
                                            .foregroundColor(BevelColors.textSecondary)
                                    }
                                    Spacer()
                                    caloriesSevenDayMiniBars(goalKcal: goals.kcal)
                                        .frame(width: 142, height: 38)
                                }
                                .padding(14)
                                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BevelColors.cardSubtle))
                            }
                            .buttonStyle(.plain)

                            // 3 Bottom Macro Ring Tiles (Grasa, Carbohidratos, Proteína)
                            HStack(spacing: 8) {
                                goalMacroRingTile(
                                    title: "Grasa",
                                    remainingG: remainingFat,
                                    progress: todayTotals.fatG / Double(max(goals.fatG, 1)),
                                    color: NutritionPalette.fatBlue
                                ) { onOpenNutrient("Grasas") }

                                goalMacroRingTile(
                                    title: "Carbohidratos",
                                    remainingG: remainingCarbs,
                                    progress: todayTotals.carbsG / Double(max(goals.carbsG, 1)),
                                    color: NutritionPalette.carbsAmber
                                ) { onOpenNutrient("Carbohidratos") }

                                goalMacroRingTile(
                                    title: "Proteína",
                                    remainingG: remainingProt,
                                    progress: todayTotals.proteinG / Double(max(goals.proteinG, 1)),
                                    color: NutritionPalette.proteinPink
                                ) { onOpenNutrient("Proteína") }
                            }
                        }
                        .padding(14)
                    }

                    // 4. "Detalles de nutrición" Dot-Matrix Card with [g | %] Toggle (Exact Screenshot 3!)
                    BevelCard(cornerRadius: 22) {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(spacing: 10) {
                                Text("Detalles de nutrición")
                                    .font(ImprovingFont.sectionTitle(17))
                                    .foregroundColor(BevelColors.textPrimary)
                                Spacer()
                                HStack(spacing: 2) {
                                    Button {
                                        UISelectionFeedbackGenerator().selectionChanged()
                                        macroDetailsInPercent = false
                                    } label: {
                                        Text("g")
                                            .font(ImprovingFont.caption(12.5))
                                            .fontWeight(.bold)
                                            .foregroundColor(!macroDetailsInPercent ? .white : BevelColors.textSecondary)
                                            .frame(width: 30, height: 26)
                                            .background(Capsule().fill(!macroDetailsInPercent ? Color(hex: 0x6A6E7A) : .clear))
                                    }
                                    Button {
                                        UISelectionFeedbackGenerator().selectionChanged()
                                        macroDetailsInPercent = true
                                    } label: {
                                        Text("%")
                                            .font(ImprovingFont.caption(12.5))
                                            .fontWeight(.bold)
                                            .foregroundColor(macroDetailsInPercent ? .white : BevelColors.textSecondary)
                                            .frame(width: 30, height: 26)
                                            .background(Capsule().fill(macroDetailsInPercent ? Color(hex: 0x6A6E7A) : .clear))
                                    }
                                }
                                .padding(3)
                                .background(Capsule().fill(BevelColors.cardSubtle))

                                Button { onOpenTrends?(.macroBalance) } label: {
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(BevelColors.textMuted)
                                }
                            }

                            HStack(spacing: 12) {
                                macroDetailColumn(
                                    label: "Grasas",
                                    valueText: macroDetailsInPercent ? "\(fatPct)%" : String(format: "%.1fg", locale: Locale(identifier: "es_ES"), todayTotals.fatG),
                                    fraction: macroDetailsInPercent ? Double(fatPct) / 100.0 : todayTotals.fatG / Double(max(goals.fatG, 1)),
                                    color: NutritionPalette.fatBlue
                                ) { onOpenNutrient("Grasas") }

                                macroDetailColumn(
                                    label: "Carbos",
                                    valueText: macroDetailsInPercent ? "\(carbsPct)%" : String(format: "%.1fg", locale: Locale(identifier: "es_ES"), todayTotals.carbsG),
                                    fraction: macroDetailsInPercent ? Double(carbsPct) / 100.0 : todayTotals.carbsG / Double(max(goals.carbsG, 1)),
                                    color: NutritionPalette.carbsAmber
                                ) { onOpenNutrient("Carbohidratos") }

                                macroDetailColumn(
                                    label: "Proteína",
                                    valueText: macroDetailsInPercent ? "\(protPct)%" : String(format: "%.1fg", locale: Locale(identifier: "es_ES"), todayTotals.proteinG),
                                    fraction: macroDetailsInPercent ? Double(protPct) / 100.0 : todayTotals.proteinG / Double(max(goals.proteinG, 1)),
                                    color: NutritionPalette.proteinPink
                                ) { onOpenNutrient("Proteína") }
                            }
                        }
                        .padding(16)
                    }

                    // 5. "Energía neta" Bipolar Bar Card (Exact Screenshot 3!)
                    Button { onOpenTrends?(.netEnergy) } label: {
                        BevelCard(cornerRadius: 22) {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(netInfo.net > 0 ? "+\(netInfo.net) kcal" : "\(netInfo.net) kcal")
                                            .font(ImprovingFont.metricHero(22))
                                            .monospacedDigit()
                                            .foregroundColor(BevelColors.textPrimary)
                                        Text("Energía neta")
                                            .font(ImprovingFont.caption(13))
                                            .foregroundColor(BevelColors.textSecondary)
                                    }
                                    Spacer()
                                    HStack(spacing: 12) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "flame.fill")
                                                .font(.system(size: 13))
                                                .foregroundColor(NutritionPalette.burnedOrange)
                                            Text("\(netInfo.burned)")
                                                .font(ImprovingFont.cardTitle(14.5))
                                                .monospacedDigit()
                                                .foregroundColor(NutritionPalette.burnedOrange)
                                        }
                                        HStack(spacing: 4) {
                                            Image(systemName: "apple.logo")
                                                .font(.system(size: 12.5))
                                                .foregroundColor(NutritionPalette.consumedBlue)
                                            Text("\(netInfo.consumed)")
                                                .font(ImprovingFont.cardTitle(14.5))
                                                .monospacedDigit()
                                                .foregroundColor(NutritionPalette.consumedBlue)
                                        }
                                    }
                                }

                                NetEnergyBipolarBar(netKcal: netInfo.net)
                            }
                            .padding(16)
                        }
                    }
                    .buttonStyle(.plain)

                    // 6. "Factores que contribuyen a la calidad de los alimentos" (Exact Screenshots 4 & 5!)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            Text("Factores que contribuyen a la calidad de los alimentos")
                                .font(ImprovingFont.sectionTitle(18))
                                .foregroundColor(BevelColors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button { activeSheet = .info } label: {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 15))
                                    .foregroundColor(BevelColors.textMuted)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                        }
                        .padding(.top, 6)

                        let visibleFactors = factorsExpanded
                            ? FoodQualityFactorKind.allCases
                            : Array(FoodQualityFactorKind.allCases.prefix(6))

                        ForEach(visibleFactors) { factor in
                            FoodQualityFactorRow(
                                kind: factor,
                                value: dailyFactors.value(for: factor),
                                onTap: { activeSheet = .factorInfo(factor) }
                            )
                        }

                        // Expand / Collapse Full-Width Chevron Pill (Screenshots 4 & 5!)
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.easeInOut(duration: 0.22)) {
                                factorsExpanded.toggle()
                            }
                        } label: {
                            BevelCard(cornerRadius: 15) {
                                Image(systemName: factorsExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                            }
                        }
                        .buttonStyle(.plain)

                        // "Umbral seguro" Legend
                        HStack(spacing: 8) {
                            HStack(spacing: 0) {
                                Capsule()
                                    .fill(Color.white.opacity(0.28))
                                    .frame(width: 14, height: 4)
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.white.opacity(0.45))
                                    .frame(width: 2, height: 11)
                            }
                            Text("Umbral seguro")
                                .font(ImprovingFont.caption(12.5))
                                .foregroundColor(BevelColors.textMuted)
                        }
                        .padding(.top, 2)
                    }

                    // 7. "Cronología nutricional" Card + "+" Multimodal Gemini AI Logger (Exact Screenshot 6!)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Cronología nutricional")
                                    .font(ImprovingFont.sectionTitle(18))
                                    .foregroundColor(BevelColors.textPrimary)
                                Text("\(meals.count) evento\(meals.count == 1 ? "" : "s")")
                                    .font(ImprovingFont.caption(13))
                                    .foregroundColor(BevelColors.textMuted)
                            }
                            Spacer()
                            HStack(spacing: 8) {
                                let yestCount = store.yesterdayMealsForSelectedDate.count
                                if yestCount > 0 {
                                    Button {
                                        AppHaptics.selection()
                                        _ = store.repeatYesterdayMeals()
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.counterclockwise")
                                                .font(.system(size: 11, weight: .bold))
                                            Text("Repetir ayer (\(yestCount))")
                                                .font(ImprovingFont.caption(11.5))
                                                .fontWeight(.bold)
                                        }
                                        .foregroundColor(BevelColors.skyBlue)
                                        .padding(.horizontal, 10)
                                        .frame(height: 36)
                                        .background(Capsule().fill(BevelColors.card))
                                        .overlay(Capsule().strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
                                    }
                                }
                                Button {
                                    activeSheet = .recipeBuilder
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "frying.pan.fill")
                                            .font(.system(size: 11.5, weight: .semibold))
                                        Text("Recetas")
                                            .font(ImprovingFont.caption(11.5))
                                            .fontWeight(.bold)
                                    }
                                    .foregroundColor(BevelColors.amberStart)
                                    .padding(.horizontal, 10)
                                    .frame(height: 36)
                                    .background(Capsule().fill(BevelColors.card))
                                    .overlay(Capsule().strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
                                }
                                Button {
                                    activeSheet = .mealComposer(existing: nil, mode: .barcode)
                                } label: {
                                    Image(systemName: "barcode.viewfinder")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(BevelColors.textPrimary)
                                        .frame(width: 44, height: 44)
                                        .background(Circle().fill(BevelColors.card))
                                        .overlay(Circle().strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
                                }
                                Button {
                                    activeSheet = .mealComposer(existing: nil, mode: .standard)
                                } label: {
                                    Image(systemName: "plus")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(BevelColors.textPrimary)
                                        .frame(width: 44, height: 44)
                                        .background(Circle().fill(BevelColors.card))
                                        .overlay(Circle().strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
                                }
                            }
                        }
                        .padding(.top, 8)

                        BevelCard(cornerRadius: 22) {
                            LazyVStack(spacing: 0) {
                                if meals.isEmpty {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("Sin eventos nutricionales registrados este día.")
                                            .font(ImprovingFont.body(14))
                                            .foregroundColor(BevelColors.textSecondary)
                                        Button {
                                            activeSheet = .mealComposer(existing: nil, mode: .standard)
                                        } label: {
                                            Label("Escanear plato con IA o registrar manual", systemImage: "camera.viewfinder")
                                                .font(ImprovingFont.cardTitle(13.5))
                                                .foregroundColor(.white)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 12)
                                                .background(Capsule().fill(BevelColors.emeraldEnd))
                                        }
                                    }
                                    .padding(16)
                                } else {
                                    ForEach(Array(meals.enumerated()), id: \.element.id) { idx, meal in
                                        Button {
                                            activeSheet = .mealComposer(existing: meal, mode: .standard)
                                        } label: {
                                            timelineMealRow(meal: meal)
                                        }
                                        .buttonStyle(.plain)

                                        if idx < meals.count - 1 {
                                            Divider()
                                                .background(BevelColors.divider)
                                                .padding(.horizontal, 16)
                                        }
                                    }

                                    Button { activeSheet = .fullTimeline } label: {
                                        Text("Ver cronología")
                                            .font(ImprovingFont.cardTitle(14.5))
                                            .foregroundColor(BevelColors.textPrimary)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(Capsule().fill(BevelColors.cardSubtle))
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.top, 8)
                                    .padding(.bottom, 14)
                                }
                            }
                        }
                    }

                    // 7B. Ventana de Ayuno Intermitente + Panel de 8 Micronutrientes Cuantificados (Apartado 1.5)
                    FastingAndMicronutrientsSection(store: store)

                    // 8. "Tendencias" — 3 Exact Cards (Screenshots 6 & 7!)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Tendencias")
                            .font(ImprovingFont.sectionTitle(18))
                            .foregroundColor(BevelColors.textPrimary)
                            .padding(.top, 8)

                        // Card 1: Puntuación de nutrición
                        nutritionScoreTrendCard(scoreOpt: scoreOpt)

                        // Card 2: Equilibrio macro
                        macroBalanceTrendCard(totalMacroG: Int((todayTotals.fatG + todayTotals.carbsG + todayTotals.proteinG).rounded()))

                        // Card 3: Energía neta
                        netEnergyTrendCard(netKcal: netInfo.net)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 150)
        }
        .background(BevelColors.canvas)
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            if let pending = store.pendingNutritionLaunchMode {
                store.pendingNutritionLaunchMode = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    activeSheet = .mealComposer(existing: nil, mode: pending)
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .datePicker:
                DatePickerSheetView(
                    selectedDate: Binding(
                        get: { store.selectedDate },
                        set: { d in store.selectDate(d); activeSheet = nil }
                    ),
                    onJumpToday: { store.selectDayOffset(0); activeSheet = nil },
                    onClose: { activeSheet = nil }
                )
            case .share:
                ShareSummaryCardSheet(store: store, kind: .nutrition, onClose: { activeSheet = nil })
            case .info:
                NutritionInfoSheet(onClose: { activeSheet = nil })
            case .goals:
                NutritionGoalsSheet(store: store, onClose: { activeSheet = nil })
            case .myFoods:
                MisAlimentosSheet(store: store, onClose: { activeSheet = nil })
            case .recipeBuilder:
                MultiIngredientRecipeBuilderSheet(store: store, onClose: { activeSheet = nil })
            case .fullTimeline:
                FullNutritionTimelineSheet(
                    store: store,
                    onEditMeal: { m in
                        activeSheet = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                            activeSheet = .mealComposer(existing: m, mode: .standard)
                        }
                    },
                    onAddMeal: {
                        activeSheet = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                            activeSheet = .mealComposer(existing: nil, mode: .standard)
                        }
                    },
                    onClose: { activeSheet = nil }
                )
            case .mealComposer(let existing, let mode):
                MealComposerSheet(
                    store: store,
                    existingMeal: existing,
                    initialMode: mode,
                    onClose: { activeSheet = nil }
                )
            case .factorInfo(let factor):
                FactorBreakdownSheet(
                    store: store,
                    factor: factor,
                    dailyValue: dailyFactors.value(for: factor),
                    onClose: { activeSheet = nil }
                )
            }
        }
    }

    // MARK: - Helper Subviews for NutricionScreen

    private func caloriesSevenDayMiniBars(goalKcal: Int) -> some View {
        let cal = Calendar.current
        let anchor = cal.startOfDay(for: store.selectedDate)
        let values: [Int] = (0..<7).reversed().map { back in
            guard let d = cal.date(byAdding: .day, value: -back, to: anchor) else { return 0 }
            return store.nutritionDayTotals(for: store.isoFormatter.string(from: d)).kcal
        }
        let maxVal = max(Double(goalKcal) * 1.25, Double(values.max() ?? 0), 1000.0)
        let goalFrac = min(max(Double(goalKcal) / maxVal, 0.25), 0.88)
        let goalLabel: String = {
            let k = Double(goalKcal) / 1000.0
            let s = String(format: "%.1fk", locale: Locale(identifier: "es_ES"), k)
                .replacingOccurrences(of: ",0k", with: "k")
            return s
        }()

        return ZStack(alignment: .trailing) {
            Canvas { ctx, sz in
                let w = sz.width - 22
                let h = sz.height
                let goalY = h * (1.0 - CGFloat(goalFrac))

                // Dotted horizontal goal line
                var dash = Path()
                dash.move(to: CGPoint(x: 0, y: goalY))
                dash.addLine(to: CGPoint(x: w, y: goalY))
                ctx.stroke(
                    dash,
                    with: .color(Color.white.opacity(0.42)),
                    style: StrokeStyle(lineWidth: 1.2, dash: [2.2, 3.0])
                )

                // 7 rounded translucent bars
                let slot = w / 7.0
                let barW = max(slot * 0.56, 5.0)
                for (i, v) in values.enumerated() {
                    let frac = min(Double(v) / maxVal, 1.0)
                    let bh = v > 0 ? max(4, h * CGFloat(frac)) : 2
                    let x = CGFloat(i) * slot + (slot - barW) / 2
                    let rect = CGRect(x: x, y: h - bh, width: barW, height: bh)
                    let col = v > 0 ? NutritionPalette.scoreLavender.opacity(0.45) : Color.white.opacity(0.08)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(col))
                }
            }

            Text(goalLabel)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(BevelColors.textPrimary)
                .offset(y: -CGFloat(goalFrac - 0.5) * 34)
        }
    }

    private func goalMacroRingTile(
        title: String,
        remainingG: Int,
        progress: Double,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        let clamped = min(max(progress, 0.0), 1.0)
        return Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 4) {
                    Text(title)
                        .font(ImprovingFont.cardTitle(13))
                        .foregroundColor(BevelColors.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 2)
                    ZStack {
                        Circle()
                            .stroke(color.opacity(0.22), lineWidth: 3)
                            .frame(width: 17, height: 17)
                        if clamped > 0.01 {
                            Circle()
                                .trim(from: 0, to: CGFloat(clamped))
                                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .frame(width: 17, height: 17)
                        }
                    }
                }
                Spacer(minLength: 0)
                Text(remainingG >= 0 ? "Faltan \(remainingG)g" : "+\(abs(remainingG))g")
                    .font(ImprovingFont.caption(12))
                    .monospacedDigit()
                    .foregroundColor(BevelColors.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .padding(11)
            .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(BevelColors.cardSubtle))
        }
        .buttonStyle(.plain)
    }

    private func macroDetailColumn(
        label: String,
        valueText: String,
        fraction: Double,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                MacroDotMatrixGrid(
                    fraction: fraction,
                    color: color,
                    columns: 8,
                    rows: 7,
                    dotSize: 5.8,
                    spacing: 3.6
                )
                VStack(alignment: .leading, spacing: 1) {
                    Text(valueText)
                        .font(ImprovingFont.metricTile(17))
                        .monospacedDigit()
                        .foregroundColor(BevelColors.textPrimary)
                    Text(label)
                        .font(ImprovingFont.caption(13))
                        .fontWeight(.semibold)
                        .foregroundColor(color)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private func timelineMealRow(meal: NutritionMealItem) -> some View {
        let impactBadge: (icon: String, bg: Color) = {
            if meal.qualityScore >= 75 { return ("arrow.up", NutritionPalette.scoreViolet) }
            if meal.qualityScore >= 50 { return ("minus", Color(hex: 0x4A4E5C)) }
            return ("arrow.down", NutritionPalette.scoreViolet)
        }()

        return HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                if let img = MealPhotoStorage.loadImage(filename: meal.photoFilename) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 42, height: 42)
                        .clipShape(Circle())
                } else {
                    Text(meal.emoji ?? GeminiCoachService.inferEmoji(forTitle: meal.title))
                        .font(.system(size: 24))
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(BevelColors.cardSubtle))
                }

                Image(systemName: impactBadge.icon)
                    .font(.system(size: 8.5, weight: .black))
                    .foregroundColor(.white)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(impactBadge.bg))
                    .overlay(Circle().strokeBorder(BevelColors.card, lineWidth: 1.5))
                    .offset(x: 3, y: 2)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(meal.timeLabel)
                    .font(ImprovingFont.caption(12))
                    .foregroundColor(BevelColors.textMuted)
                Text(meal.title)
                    .font(ImprovingFont.cardTitle(15))
                    .foregroundColor(BevelColors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 10) {
                    HStack(spacing: 3) {
                        Image(systemName: "apple.logo").font(.system(size: 10.5)).foregroundColor(BevelColors.textMuted)
                        Text("\(meal.kcal) kcal").font(ImprovingFont.caption(12)).monospacedDigit().foregroundColor(BevelColors.textSecondary)
                    }
                    HStack(spacing: 3) {
                        Image(systemName: "drop.fill").font(.system(size: 10)).foregroundColor(NutritionPalette.fatBlue)
                        Text("\(meal.fatG)").font(ImprovingFont.caption(12)).monospacedDigit().foregroundColor(BevelColors.textSecondary)
                    }
                    HStack(spacing: 3) {
                        Image(systemName: "leaf.fill").font(.system(size: 10)).foregroundColor(NutritionPalette.carbsAmber)
                        Text("\(meal.carbsG)").font(ImprovingFont.caption(12)).monospacedDigit().foregroundColor(BevelColors.textSecondary)
                    }
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill").font(.system(size: 10)).foregroundColor(NutritionPalette.proteinPink)
                        Text("\(meal.proteinG)").font(ImprovingFont.caption(12)).monospacedDigit().foregroundColor(BevelColors.textSecondary)
                    }
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "arrow.right")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(BevelColors.textMuted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func nutritionScoreTrendCard(scoreOpt: Int?) -> some View {
        let cal = Calendar.current
        let anchor = cal.startOfDay(for: store.selectedDate)
        let pts: [Double?] = (0..<10).reversed().map { back in
            guard let d = cal.date(byAdding: .day, value: -back, to: anchor) else { return nil }
            return store.nutritionScore(for: store.isoFormatter.string(from: d)).map { Double($0) }
        }
        let statusPair: (String, Color, String) = {
            guard let s = scoreOpt else { return ("Sin datos suficientes", BevelColors.textMuted, "minus.circle") }
            if s < 55 { return ("Debajo de lo normal", NutritionPalette.burnedOrange, "arrow.down.circle.fill") }
            if s >= 78 { return ("Encima de lo normal", BevelColors.greenPrimary, "arrow.up.circle.fill") }
            return ("Rango normal", NutritionPalette.scoreLavender, "checkmark.circle.fill")
        }()

        return Button { onOpenTrends?(.score) } label: {
            BevelCard(cornerRadius: 20) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "fork.knife").font(.system(size: 13)).foregroundColor(BevelColors.textMuted)
                            Text("Puntuación de nutrición").font(ImprovingFont.cardTitle(14.5)).foregroundColor(BevelColors.textSecondary)
                        }
                        Text(scoreOpt.map { "\($0)" } ?? "--")
                            .font(ImprovingFont.displayLarge(28))
                            .monospacedDigit()
                            .foregroundColor(BevelColors.textPrimary)
                        HStack(spacing: 5) {
                            Image(systemName: statusPair.2).font(.system(size: 13)).foregroundColor(statusPair.1)
                            Text(statusPair.0).font(ImprovingFont.caption(13)).fontWeight(.semibold).foregroundColor(statusPair.1)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 10) {
                        Image(systemName: "arrow.right").font(.system(size: 12.5, weight: .semibold)).foregroundColor(BevelColors.textMuted)
                        TrendSparklineWithBand(
                            optionalPoints: pts,
                            lineColor: NutritionPalette.scoreLavender,
                            fillUnder: true,
                            showGlowDot: true
                        )
                        .frame(width: 76, height: 42)
                    }
                }
                .padding(16)
            }
        }
        .buttonStyle(.plain)
    }

    private func macroBalanceTrendCard(totalMacroG: Int) -> some View {
        let cal = Calendar.current
        let anchor = cal.startOfDay(for: store.selectedDate)
        let recentDays: [(f: Double, c: Double, p: Double)] = (0..<6).reversed().map { back in
            guard let d = cal.date(byAdding: .day, value: -back, to: anchor) else { return (0, 0, 0) }
            let t = store.nutritionDayTotals(for: store.isoFormatter.string(from: d))
            return (t.fatG, t.carbsG, t.proteinG)
        }
        let maxSum = max(recentDays.map { $0.f + $0.c + $0.p }.max() ?? 1, 100)

        return Button { onOpenTrends?(.macroBalance) } label: {
            BevelCard(cornerRadius: 20) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "chart.pie.fill").font(.system(size: 13)).foregroundColor(BevelColors.textMuted)
                            Text("Equilibrio macro").font(ImprovingFont.cardTitle(14.5)).foregroundColor(BevelColors.textSecondary)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(totalMacroG)")
                                .font(ImprovingFont.displayLarge(28))
                                .monospacedDigit()
                                .foregroundColor(BevelColors.textPrimary)
                            Text("g")
                                .font(ImprovingFont.cardTitle(18))
                                .foregroundColor(BevelColors.textSecondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 10) {
                        Image(systemName: "arrow.right").font(.system(size: 12.5, weight: .semibold)).foregroundColor(BevelColors.textMuted)
                        Canvas { ctx, sz in
                            let slot = sz.width / 6.0
                            let bw: CGFloat = 4.2
                            for (i, d) in recentDays.enumerated() {
                                let sum = d.f + d.c + d.p
                                guard sum > 0.5 else { continue }
                                let cx = (CGFloat(i) + 0.5) * slot
                                var bottom = sz.height
                                for (val, col) in [(d.f, NutritionPalette.fatBlue), (d.c, NutritionPalette.carbsAmber), (d.p, NutritionPalette.proteinPink)] {
                                    let segH = CGFloat(val / maxSum) * sz.height
                                    if segH > 0.8 {
                                        let r = CGRect(x: cx - bw / 2, y: bottom - segH, width: bw, height: max(segH - 0.8, 1.5))
                                        ctx.fill(Path(roundedRect: r, cornerRadius: bw / 2), with: .color(col))
                                        bottom -= segH
                                    }
                                }
                            }
                        }
                        .frame(width: 56, height: 42)
                    }
                }
                .padding(16)
            }
        }
        .buttonStyle(.plain)
    }

    private func netEnergyTrendCard(netKcal: Int) -> some View {
        let cal = Calendar.current
        let anchor = cal.startOfDay(for: store.selectedDate)
        let recent: [(cons: Int, burn: Int)] = (0..<8).reversed().map { back in
            guard let d = cal.date(byAdding: .day, value: -back, to: anchor) else { return (0, 0) }
            let n = store.netEnergyKcal(for: store.isoFormatter.string(from: d))
            return (n.consumed, n.burned)
        }
        let maxK = Double(max(recent.map { max($0.cons, $0.burn) }.max() ?? 2000, 1200))
        let statusLabel = netKcal < -150 ? "Déficit" : (netKcal > 150 ? "Superávit" : "Equilibrio")
        let statusColor = netKcal < -150 ? NutritionPalette.burnedOrange : (netKcal > 150 ? NutritionPalette.consumedBlue : BevelColors.greenPrimary)

        return Button { onOpenTrends?(.netEnergy) } label: {
            BevelCard(cornerRadius: 20) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.forwardslash.minus").font(.system(size: 13)).foregroundColor(BevelColors.textMuted)
                            Text("Energía neta").font(ImprovingFont.cardTitle(14.5)).foregroundColor(BevelColors.textSecondary)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(netKcal > 0 ? "+\(netKcal)" : "\(netKcal)")
                                .font(ImprovingFont.displayLarge(26))
                                .monospacedDigit()
                                .foregroundColor(BevelColors.textPrimary)
                            Text("kcal")
                                .font(ImprovingFont.cardTitle(16))
                                .foregroundColor(BevelColors.textSecondary)
                        }
                        Text(statusLabel)
                            .font(ImprovingFont.caption(13))
                            .fontWeight(.semibold)
                            .foregroundColor(statusColor)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 10) {
                        Image(systemName: "arrow.right").font(.system(size: 12.5, weight: .semibold)).foregroundColor(BevelColors.textMuted)
                        Canvas { ctx, sz in
                            let slot = sz.width / 8.0
                            let bw: CGFloat = 3.2
                            for (i, item) in recent.enumerated() {
                                let cx = (CGFloat(i) + 0.5) * slot
                                if item.cons > 0 {
                                    let ch = CGFloat(Double(item.cons) / maxK) * sz.height
                                    let r = CGRect(x: cx - bw - 0.8, y: sz.height - ch, width: bw, height: max(ch, 3))
                                    ctx.fill(Path(roundedRect: r, cornerRadius: bw / 2), with: .color(NutritionPalette.consumedBlue))
                                }
                                if item.burn > 0 {
                                    let bh = CGFloat(Double(item.burn) / maxK) * sz.height
                                    let r = CGRect(x: cx + 0.8, y: sz.height - bh, width: bw, height: max(bh, 3))
                                    ctx.fill(Path(roundedRect: r, cornerRadius: bw / 2), with: .color(NutritionPalette.burnedOrange))
                                }
                            }
                        }
                        .frame(width: 112, height: 42)
                    }
                }
                .padding(16)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Fasting Window, Meal-to-Bedtime Gap, Quantified Micronutrients & Multi-Ingredient Recipe Builder (Apartado 1.5)

struct FastingAndMicronutrientsSection: View {
    @ObservedObject var store: ImprovingStore
    @State private var showAllMicros: Bool = false

    var body: some View {
        let timing = store.caffeineAndMealTimingToday
        let micros = store.dailyMicronutrientsSnapshot
        let visibleMicros = showAllMicros ? micros : Array(micros.prefix(4))

        VStack(alignment: .leading, spacing: 12) {
            // 1. Ventana de Alimentación / Ayuno Intermitente & Digestión Nocturna
            BevelCard(cornerRadius: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "clock.badge.checkmark.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(BevelColors.bioTeal)
                        Text("VENTANA DE ALIMENTACIÓN Y AYUNO")
                            .font(ImprovingFont.microLabel(10))
                            .foregroundColor(BevelColors.textMuted)
                        Spacer()
                        if let fast = timing.fastingHours, let win = timing.eatingWindowHours {
                            Text("Ayuno \(Int(fast.rounded())):\(Int(win.rounded()))")
                                .font(ImprovingFont.caption(11.5))
                                .fontWeight(.bold)
                                .monospacedDigit()
                                .foregroundColor(fast >= 13.5 ? BevelColors.greenPrimary : BevelColors.skyBlue)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(BevelColors.cardSubtle))
                        }
                    }

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Primera comida")
                                .font(ImprovingFont.caption(11))
                                .foregroundColor(BevelColors.textMuted)
                            Text(timing.firstMealTimeLabel ?? "--:--")
                                .font(ImprovingFont.cardTitle(15))
                                .monospacedDigit()
                                .foregroundColor(BevelColors.textPrimary)
                        }
                        Spacer()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Última comida")
                                .font(ImprovingFont.caption(11))
                                .foregroundColor(BevelColors.textMuted)
                            Text(timing.lastMealTimeLabel ?? "--:--")
                                .font(ImprovingFont.cardTitle(15))
                                .monospacedDigit()
                                .foregroundColor(BevelColors.textPrimary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Margen al sueño")
                                .font(ImprovingFont.caption(11))
                                .foregroundColor(BevelColors.textMuted)
                            Text(timing.hoursFromLastMealToBedtime.map { String(format: "%.1f h", locale: Locale(identifier: "es_ES"), $0) } ?? "--")
                                .font(ImprovingFont.cardTitle(15))
                                .monospacedDigit()
                                .foregroundColor((timing.hoursFromLastMealToBedtime ?? 3.0) >= 2.8 ? BevelColors.greenPrimary : BevelColors.coralHigh)
                        }
                    }

                    Text(timing.statusSummary)
                        .font(ImprovingFont.caption(11.5))
                        .foregroundColor(BevelColors.textSecondary)
                }
                .padding(16)
            }

            // 2. Panel de 8 Micronutrientes Cuantificados con Objetivos Diarios
            HStack {
                Text("Micronutrientes cuantificados")
                    .font(ImprovingFont.sectionTitle(18))
                    .foregroundColor(BevelColors.textPrimary)
                Spacer()
                Button(showAllMicros ? "Ver menos" : "Ver los 8") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAllMicros.toggle()
                    }
                }
                .font(ImprovingFont.caption(12))
                .fontWeight(.semibold)
                .foregroundColor(BevelColors.skyBlue)
            }
            .padding(.top, 4)

            BevelCard(cornerRadius: 20) {
                VStack(spacing: 12) {
                    ForEach(visibleMicros) { item in
                        let col = Color(hex: item.accentHex)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Image(systemName: item.icon)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(col)
                                Text(item.name)
                                    .font(ImprovingFont.cardTitle(13.5))
                                    .foregroundColor(BevelColors.textPrimary)
                                Spacer()
                                Text("\(String(format: item.currentValue >= 100 ? "%.0f" : "%.1f", locale: Locale(identifier: "es_ES"), item.currentValue)) / \(String(format: item.targetValue >= 100 ? "%.0f" : "%.1f", locale: Locale(identifier: "es_ES"), item.targetValue)) \(item.unit)")
                                    .font(ImprovingFont.caption(12))
                                    .fontWeight(.bold)
                                    .monospacedDigit()
                                    .foregroundColor(item.isUpperLimit && item.currentValue > item.targetValue ? BevelColors.coralHigh : BevelColors.textPrimary)
                            }
                            GeometryReader { geo in
                                let w = max(geo.size.width, 1)
                                let frac = min(item.progressFraction, 1.0)
                                ZStack(alignment: .leading) {
                                    Capsule().fill(BevelColors.chartTrackSubtle).frame(height: 6)
                                    Capsule()
                                        .fill(item.isUpperLimit && item.currentValue > item.targetValue ? BevelColors.coralHigh : col)
                                        .frame(width: max(6, w * CGFloat(frac)), height: 6)
                                }
                            }
                            .frame(height: 6)
                        }
                    }
                }
                .padding(16)
            }
        }
    }
}

struct MultiIngredientRecipeBuilderSheet: View {
    @ObservedObject var store: ImprovingStore
    let onClose: () -> Void

    @State private var recipeTitle: String = "Bowl proteico post-entreno"
    @State private var recipeEmoji: String = "🍲"
    @State private var servings: Int = 2
    @State private var ingredients: [NutritionRecipeIngredient] = [
        NutritionRecipeIngredient(id: "i1", name: "Pechuga de pollo / Tofu", grams: 300, kcal: 495, proteinG: 93, carbsG: 0, fatG: 11, fiberG: 0),
        NutritionRecipeIngredient(id: "i2", name: "Arroz integral cocido", grams: 250, kcal: 280, proteinG: 6, carbsG: 58, fatG: 2, fiberG: 4.5),
        NutritionRecipeIngredient(id: "i3", name: "Aguacate y verduras", grams: 150, kcal: 190, proteinG: 3, carbsG: 10, fatG: 16, fiberG: 6.5)
    ]
    @State private var ingName: String = ""
    @State private var ingGrams: Int = 100
    @State private var ingKcal: Int = 150
    @State private var ingProt: Int = 12
    @State private var ingCarbs: Int = 15
    @State private var ingFat: Int = 5

    var body: some View {
        let draftTemplate = NutritionRecipeTemplate(
            id: UUID().uuidString,
            title: recipeTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Receta casera" : recipeTitle,
            emoji: recipeEmoji,
            servings: max(servings, 1),
            ingredients: ingredients
        )

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    BevelCard(cornerRadius: 18) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("CREAR RECETA MULTI-INGREDIENTE")
                                .font(ImprovingFont.microLabel(10))
                                .foregroundColor(BevelColors.textMuted)
                            HStack(spacing: 8) {
                                TextField("🍲", text: $recipeEmoji)
                                    .frame(width: 44)
                                    .multilineTextAlignment(.center)
                                    .padding(8)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.cardSubtle))
                                TextField("Nombre de la receta", text: $recipeTitle)
                                    .font(ImprovingFont.cardTitle(14.5))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .padding(10)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.cardSubtle))
                            }
                            Stepper("Raciones totales: \(servings)", value: $servings, in: 1...12)
                                .font(ImprovingFont.caption(13))
                                .foregroundColor(BevelColors.textPrimary)

                            HStack {
                                Text("Por ración (1/\(servings)):")
                                    .font(ImprovingFont.caption(12))
                                    .foregroundColor(BevelColors.textSecondary)
                                Spacer()
                                Text("\(draftTemplate.kcalPerServing) kcal · \(draftTemplate.proteinPerServing)g P · \(draftTemplate.carbsPerServing)g C · \(draftTemplate.fatPerServing)g G")
                                    .font(ImprovingFont.caption(12))
                                    .fontWeight(.bold)
                                    .monospacedDigit()
                                    .foregroundColor(BevelColors.greenPrimary)
                            }
                        }
                        .padding(14)
                    }

                    // Add Ingredient Card
                    BevelCard(cornerRadius: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("AÑADIR INGREDIENTE")
                                .font(ImprovingFont.microLabel(10))
                                .foregroundColor(BevelColors.textMuted)
                            TextField("Ingrediente (ej. Avena, Huevos, Salmón…)", text: $ingName)
                                .font(ImprovingFont.body(13.5))
                                .foregroundColor(BevelColors.textPrimary)
                                .padding(9)
                                .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.cardSubtle))
                            Stepper("Peso: \(ingGrams) g · \(ingKcal) kcal", value: $ingKcal, in: 10...1500, step: 25)
                                .font(ImprovingFont.caption(12))
                            HStack {
                                Stepper("P: \(ingProt)g", value: $ingProt, in: 0...150, step: 2)
                                Stepper("C: \(ingCarbs)g", value: $ingCarbs, in: 0...200, step: 5)
                                Stepper("G: \(ingFat)g", value: $ingFat, in: 0...100, step: 2)
                            }
                            .font(ImprovingFont.caption(11.5))

                            Button {
                                let clean = ingName.trimmingCharacters(in: .whitespacesAndNewlines)
                                ingredients.append(NutritionRecipeIngredient(
                                    id: UUID().uuidString,
                                    name: clean.isEmpty ? "Ingrediente" : clean,
                                    grams: ingGrams,
                                    kcal: ingKcal,
                                    proteinG: ingProt,
                                    carbsG: ingCarbs,
                                    fatG: ingFat,
                                    fiberG: Double(ingCarbs) * 0.12
                                ))
                                ingName = ""
                                AppHaptics.selection()
                            } label: {
                                Text("+ Añadir ingrediente a la receta")
                                    .font(ImprovingFont.caption(12))
                                    .fontWeight(.bold)
                                    .foregroundColor(BevelColors.skyBlue)
                            }
                        }
                        .padding(14)
                    }

                    ForEach(ingredients) { ing in
                        BevelCard(cornerRadius: 14) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ing.name).font(ImprovingFont.cardTitle(13.5)).foregroundColor(BevelColors.textPrimary)
                                    Text("\(ing.kcal) kcal · \(ing.proteinG)g P · \(ing.carbsG)g C · \(ing.fatG)g G")
                                        .font(ImprovingFont.caption(11.5))
                                        .foregroundColor(BevelColors.textSecondary)
                                }
                                Spacer()
                                Button {
                                    ingredients.removeAll { $0.id == ing.id }
                                } label: {
                                    Image(systemName: "trash").font(.system(size: 12.5)).foregroundColor(BevelColors.coralHigh)
                                }
                            }
                            .padding(12)
                        }
                    }

                    HStack(spacing: 10) {
                        Button {
                            store.saveNutritionRecipe(draftTemplate)
                            AppHaptics.success()
                        } label: {
                            Text("Guardar en Recetas")
                                .font(ImprovingFont.cardTitle(13.5))
                                .foregroundColor(BevelColors.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(RoundedRectangle(cornerRadius: 14).fill(BevelColors.card))
                        }
                        Button {
                            store.saveNutritionRecipe(draftTemplate)
                            store.logRecipeServing(draftTemplate, servingsCount: 1.0)
                            AppHaptics.success()
                            onClose()
                        } label: {
                            Text("Registrar 1 ración hoy")
                                .font(ImprovingFont.cardTitle(13.5))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(RoundedRectangle(cornerRadius: 14).fill(BevelColors.emeraldEnd))
                        }
                    }

                    if !store.nutritionRecipes.isEmpty {
                        Text("Mis recetas guardadas (\(store.nutritionRecipes.count))")
                            .font(ImprovingFont.sectionTitle(16))
                            .foregroundColor(BevelColors.textPrimary)
                            .padding(.top, 6)

                        ForEach(store.nutritionRecipes) { rec in
                            BevelCard(cornerRadius: 16) {
                                HStack {
                                    Text(rec.emoji).font(.system(size: 20))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(rec.title).font(ImprovingFont.cardTitle(14)).foregroundColor(BevelColors.textPrimary)
                                        Text("1/\(rec.safeServings) rac: \(rec.kcalPerServing) kcal · \(rec.proteinPerServing)g P · \(rec.carbsPerServing)g C · \(rec.fatPerServing)g G")
                                            .font(ImprovingFont.caption(11.5))
                                            .foregroundColor(BevelColors.textSecondary)
                                    }
                                    Spacer()
                                    Button("+ 1 rac.") {
                                        store.logRecipeServing(rec, servingsCount: 1.0)
                                        AppHaptics.success()
                                        onClose()
                                    }
                                    .font(ImprovingFont.caption(11.5))
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(BevelColors.indigoEnd))
                                }
                                .padding(12)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(BevelColors.canvas)
            .navigationTitle("Constructor de Recetas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar", action: onClose)
                }
            }
        }
    }
}

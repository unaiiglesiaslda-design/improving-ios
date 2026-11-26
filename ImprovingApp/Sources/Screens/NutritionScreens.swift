import SwiftUI
import UIKit
import PhotosUI

// MARK: - Meal Photo Storage Helper (Downscaled JPEG in Application Support)

enum MealPhotoStorage {
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
            return name
        } catch {
            return nil
        }
    }

    static func loadImage(filename: String?) -> UIImage? {
        guard let filename, !filename.isEmpty else { return nil }
        let url = folderURL.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func deletePhoto(filename: String?) {
        guard let filename, !filename.isEmpty else { return }
        let url = folderURL.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Native Camera Capture Wrapper (Fallback-Safe on Simulator)

private struct CameraCaptureSheet: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraCaptureSheet
        init(parent: CameraCaptureSheet) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage {
                parent.onCapture(img)
            } else {
                parent.onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }
    }
}

// MARK: - Main Nutrition Screen (Exact Match to Screenshots 2–7 + Multimodal Gemini AI Scanner!)

struct NutricionScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void
    let onOpenNutrient: (String) -> Void
    var onOpenTrends: ((NutritionTrendTab) -> Void)? = nil

    @State private var showDatePicker: Bool = false
    @State private var showShareSheet: Bool = false
    @State private var showInfoSheet: Bool = false
    @State private var showGoalsSheet: Bool = false
    @State private var showMyFoodsSheet: Bool = false
    @State private var showFullTimelineSheet: Bool = false
    @State private var showMealComposer: Bool = false
    @State private var composerInitialMode: NutritionComposerInitialMode = .standard
    @State private var mealToEdit: NutritionMealItem? = nil
    @State private var macroDetailsInPercent: Bool = false
    @State private var factorsExpanded: Bool = false
    @State private var selectedFactorForInfo: FoodQualityFactorKind? = nil

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
                                Button { showShareSheet = true } label: {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(BevelColors.textPrimary)
                                }
                                Button { showInfoSheet = true } label: {
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(BevelColors.textPrimary)
                                }
                                Menu {
                                    Button {
                                        mealToEdit = nil
                                        composerInitialMode = .standard
                                        showMealComposer = true
                                    } label: {
                                        Label("Registrar comida con IA (foto/texto)", systemImage: "camera.viewfinder")
                                    }
                                    Button {
                                        mealToEdit = nil
                                        composerInitialMode = .barcode
                                        showMealComposer = true
                                    } label: {
                                        Label("Escanear código de barras (OpenFoodFacts)", systemImage: "barcode.viewfinder")
                                    }
                                    Button { showGoalsSheet = true } label: {
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

                            Button { showDatePicker = true } label: {
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
                    Button { showMyFoodsSheet = true } label: {
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
                            Button { showGoalsSheet = true } label: {
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
                            Button { showGoalsSheet = true } label: {
                                HStack(alignment: .center, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Calorías")
                                            .font(ImprovingFont.cardTitle(15))
                                            .foregroundColor(BevelColors.textPrimary)
                                        Text(remainingKcal >= 0 ? "Faltan \(remainingKcal)kCal" : "Superado +\(abs(remainingKcal))kCal")
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
                            Button { showInfoSheet = true } label: {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 15))
                                    .foregroundColor(BevelColors.textMuted)
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
                                onTap: { selectedFactorForInfo = factor }
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
                                Button {
                                    mealToEdit = nil
                                    composerInitialMode = .barcode
                                    showMealComposer = true
                                } label: {
                                    Image(systemName: "barcode.viewfinder")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(BevelColors.textPrimary)
                                        .frame(width: 36, height: 36)
                                        .background(Circle().fill(BevelColors.card))
                                        .overlay(Circle().strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
                                }
                                Button {
                                    mealToEdit = nil
                                    composerInitialMode = .standard
                                    showMealComposer = true
                                } label: {
                                    Image(systemName: "plus")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(BevelColors.textPrimary)
                                        .frame(width: 36, height: 36)
                                        .background(Circle().fill(BevelColors.card))
                                        .overlay(Circle().strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
                                }
                            }
                        }
                        .padding(.top, 8)

                        BevelCard(cornerRadius: 22) {
                            VStack(spacing: 0) {
                                if meals.isEmpty {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("Sin eventos nutricionales registrados este día.")
                                            .font(ImprovingFont.body(14))
                                            .foregroundColor(BevelColors.textSecondary)
                                        Button {
                                            mealToEdit = nil
                                            showMealComposer = true
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
                                            mealToEdit = meal
                                            showMealComposer = true
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

                                    Button { showFullTimelineSheet = true } label: {
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
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheetView(
                selectedDate: Binding(
                    get: { store.selectedDate },
                    set: { d in store.selectDate(d); showDatePicker = false }
                ),
                onJumpToday: { store.selectDayOffset(0); showDatePicker = false },
                onClose: { showDatePicker = false }
            )
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSummaryCardSheet(store: store, kind: .nutrition, onClose: { showShareSheet = false })
        }
        .sheet(isPresented: $showMealComposer) {
            MealComposerSheet(
                store: store,
                existingMeal: mealToEdit,
                initialMode: composerInitialMode,
                onClose: {
                    showMealComposer = false
                    mealToEdit = nil
                    composerInitialMode = .standard
                }
            )
        }
        .onAppear {
            if let pending = store.pendingNutritionLaunchMode {
                store.pendingNutritionLaunchMode = nil
                mealToEdit = nil
                composerInitialMode = pending
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    showMealComposer = true
                }
            }
        }
        .sheet(isPresented: $showGoalsSheet) {
            NutritionGoalsSheet(store: store, onClose: { showGoalsSheet = false })
        }
        .sheet(isPresented: $showMyFoodsSheet) {
            MisAlimentosSheet(store: store, onClose: { showMyFoodsSheet = false })
        }
        .sheet(isPresented: $showFullTimelineSheet) {
            FullNutritionTimelineSheet(
                store: store,
                onEditMeal: { m in
                    showFullTimelineSheet = false
                    mealToEdit = m
                    showMealComposer = true
                },
                onAddMeal: {
                    showFullTimelineSheet = false
                    mealToEdit = nil
                    showMealComposer = true
                },
                onClose: { showFullTimelineSheet = false }
            )
        }
        .sheet(isPresented: $showInfoSheet) {
            NutritionInfoSheet(onClose: { showInfoSheet = false })
        }
        .sheet(item: $selectedFactorForInfo) { factor in
            FactorBreakdownSheet(
                store: store,
                factor: factor,
                dailyValue: dailyFactors.value(for: factor),
                onClose: { selectedFactorForInfo = nil }
            )
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

// MARK: - Supporting Sheets (Mis Alimentos, Objetivos, Factor Breakdown, Full Timeline, Info)

private struct MisAlimentosSheet: View {
    @ObservedObject var store: ImprovingStore
    let onClose: () -> Void

    @State private var selectedKind: SavedFoodLibraryItem.Kind = .favorite
    @State private var newTitle: String = ""
    @State private var newKcal: String = ""
    @State private var newFat: String = ""
    @State private var newCarbs: String = ""
    @State private var pendingDeleteFood: SavedFoodLibraryItem? = nil
    @State private var newProtein: String = ""

    var body: some View {
        let filtered = store.savedFoodsLibrary.filter { $0.kind == selectedKind }

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Tipo", selection: $selectedKind) {
                        ForEach(SavedFoodLibraryItem.Kind.allCases) { k in
                            Text(k.rawValue).tag(k)
                        }
                    }
                    .pickerStyle(.segmented)

                    // Quick Add to Library Card
                    BevelCard(cornerRadius: 18) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("GUARDAR EN \(selectedKind.rawValue.uppercased())")
                                .font(ImprovingFont.microLabel(11))
                                .foregroundColor(BevelColors.greenPrimary)

                            TextField("Ej: Bowl avena + proteína, Tortilla 3 huevos…", text: $newTitle)
                                .font(ImprovingFont.body(14))
                                .foregroundColor(BevelColors.textPrimary)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.cardSubtle))

                            HStack(spacing: 8) {
                                miniField("kcal", text: $newKcal)
                                miniField("Grasas", text: $newFat)
                                miniField("Carbos", text: $newCarbs)
                                miniField("Prot", text: $newProtein)
                            }

                            Button {
                                let clean = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !clean.isEmpty else { return }
                                let f = max(0, Int(newFat) ?? 0)
                                let c = max(0, Int(newCarbs) ?? 0)
                                let p = max(0, Int(newProtein) ?? 0)
                                let k = max(0, Int(newKcal) ?? (p * 4 + c * 4 + f * 9))
                                let item = SavedFoodLibraryItem(
                                    id: UUID().uuidString,
                                    kind: selectedKind,
                                    emoji: GeminiCoachService.inferEmoji(forTitle: clean),
                                    title: clean,
                                    kcal: k,
                                    proteinG: p,
                                    carbsG: c,
                                    fatG: f,
                                    qualityScore: 84,
                                    qualityFactors: GeminiCoachService.inferQualityFactors(title: clean, qualityScore: 84)
                                )
                                store.saveFoodToLibrary(item)
                                newTitle = ""; newKcal = ""; newFat = ""; newCarbs = ""; newProtein = ""
                            } label: {
                                Text("Guardar en Mis alimentos")
                                    .font(ImprovingFont.cardTitle(13.5))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                                    .background(Capsule().fill(BevelColors.emeraldEnd))
                            }
                        }
                        .padding(14)
                    }

                    if filtered.isEmpty {
                        BevelCard(cornerRadius: 18) {
                            Text("Todavía no tienes elementos en \(selectedKind.rawValue.lowercased()). Marca cualquier comida como favorita o créala arriba para registrarla en 1 toque.")
                                .font(ImprovingFont.body(13.5))
                                .foregroundColor(BevelColors.textSecondary)
                                .padding(16)
                        }
                    } else {
                        ForEach(filtered) { item in
                            BevelCard(cornerRadius: 18) {
                                HStack(spacing: 12) {
                                    Text(item.emoji)
                                        .font(.system(size: 22))
                                        .frame(width: 40, height: 40)
                                        .background(Circle().fill(BevelColors.cardSubtle))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(ImprovingFont.cardTitle(14.5))
                                            .foregroundColor(BevelColors.textPrimary)
                                            .lineLimit(1)
                                        Text("\(item.kcal) kcal · G \(item.fatG)g · C \(item.carbsG)g · P \(item.proteinG)g")
                                            .font(ImprovingFont.caption(12))
                                            .foregroundColor(BevelColors.textSecondary)
                                    }
                                    Spacer()

                                    Button {
                                        UISelectionFeedbackGenerator().selectionChanged()
                                        store.logLibraryFoodToday(item)
                                        onClose()
                                    } label: {
                                        Text("+ Hoy")
                                            .font(ImprovingFont.caption(12))
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 11)
                                            .padding(.vertical, 7)
                                            .background(Capsule().fill(BevelColors.indigoEnd))
                                    }

                                    Button {
                                        pendingDeleteFood = item
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 13.5))
                                            .foregroundColor(BevelColors.textMuted)
                                            .frame(width: 44, height: 44)
                                    }
                                    .accessibilityLabel("Eliminar alimento guardado")
                                }
                                .padding(13)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(BevelColors.canvas)
        .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Mis alimentos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar", action: onClose)
                }
            }
            .confirmationDialog(
                "¿Eliminar de Mis alimentos?",
                isPresented: Binding(
                    get: { pendingDeleteFood != nil },
                    set: { if !$0 { pendingDeleteFood = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Eliminar alimento", role: .destructive) {
                    if let f = pendingDeleteFood {
                        store.removeFoodFromLibrary(id: f.id)
                    }
                    pendingDeleteFood = nil
                }
                Button("Cancelar", role: .cancel) { pendingDeleteFood = nil }
            } message: {
                Text("Se quitará «\(pendingDeleteFood?.title ?? "")» de tu biblioteca.")
            }
        }
    }

    private func miniField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(.numberPad)
            .keyboardDoneToolbar()
            .font(ImprovingFont.caption(13))
            .monospacedDigit()
            .foregroundColor(BevelColors.textPrimary)
            .padding(9)
            .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.cardSubtle))
    }
}

private struct NutritionGoalsSheet: View {
    @ObservedObject var store: ImprovingStore
    let onClose: () -> Void

    @State private var kcalText: String = ""
    @State private var fatText: String = ""
    @State private var carbsText: String = ""
    @State private var protText: String = ""

    var body: some View {
        let autoNorms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: store.userProfile)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    BevelCard(cornerRadius: 20) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("OBJETIVOS DIARIOS DE NUTRICIÓN")
                                .font(ImprovingFont.microLabel(11))
                                .foregroundColor(BevelColors.skyBlue)

                            Text("Por defecto se calculan según tu perfil fisiológico (\(autoNorms.maintenanceCaloriesKcal) kcal). Puedes ajustarlos manualmente aquí.")
                                .font(ImprovingFont.caption(12.5))
                                .foregroundColor(BevelColors.textSecondary)

                            goalField("Calorías objetivo (kcal)", text: $kcalText, color: NutritionPalette.scoreLavender)
                            goalField("Grasas (g)", text: $fatText, color: NutritionPalette.fatBlue)
                            goalField("Carbohidratos (g)", text: $carbsText, color: NutritionPalette.carbsAmber)
                            goalField("Proteína (g)", text: $protText, color: NutritionPalette.proteinPink)
                        }
                        .padding(16)
                    }

                    Button {
                        let g = CustomNutritionGoals(
                            caloriesKcal: Int(kcalText),
                            fatG: Int(fatText),
                            carbsG: Int(carbsText),
                            proteinG: Int(protText)
                        )
                        store.updateNutritionGoals(g)
                        onClose()
                    } label: {
                        Text("Guardar objetivos")
                            .font(ImprovingFont.cardTitle(15))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(BevelColors.emeraldEnd))
                    }

                    Button {
                        store.updateNutritionGoals(CustomNutritionGoals())
                        onClose()
                    } label: {
                        Text("Restaurar cálculo automático por perfil")
                            .font(ImprovingFont.caption(13))
                            .fontWeight(.semibold)
                            .foregroundColor(BevelColors.skyBlue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                }
                .padding(16)
            }
            .background(BevelColors.canvas)
        .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Objetivos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Cerrar", action: onClose) }
            }
            .onAppear {
                let g = store.effectiveNutritionGoals
                kcalText = "\(g.kcal)"
                fatText = "\(g.fatG)"
                carbsText = "\(g.carbsG)"
                protText = "\(g.proteinG)"
            }
        }
    }

    private func goalField(_ title: String, text: Binding<String>, color: Color) -> some View {
        HStack {
            Text(title)
                .font(ImprovingFont.body(14))
                .foregroundColor(color)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.numberPad)
                .keyboardDoneToolbar()
                .multilineTextAlignment(.trailing)
                .font(ImprovingFont.cardTitle(16))
                .monospacedDigit()
                .foregroundColor(BevelColors.textPrimary)
                .frame(width: 96)
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.cardSubtle))
        }
    }
}

private struct FactorBreakdownSheet: View {
    @ObservedObject var store: ImprovingStore
    let factor: FoodQualityFactorKind
    let dailyValue: Double
    let onClose: () -> Void

    var body: some View {
        let contributingMeals = store.mealsToday.filter { m in
            let f = m.qualityFactors ?? GeminiCoachService.inferQualityFactors(title: m.title, qualityScore: m.qualityScore, alcoholDrinks: m.alcoholDrinks ?? 0)
            return abs(f.value(for: factor)) > 0.05
        }

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    BevelCard(cornerRadius: 20) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Text(factor.emoji).font(.system(size: 30))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(factor.title)
                                        .font(ImprovingFont.sectionTitle(18))
                                        .foregroundColor(BevelColors.textPrimary)
                                    Text(factor.isPositive ? "Factor positivo de calidad" : "Factor límite · Umbral seguro")
                                        .font(ImprovingFont.caption(12.5))
                                        .foregroundColor(factor.isPositive ? NutritionPalette.positiveMint : NutritionPalette.negativeOrange)
                                }
                                Spacer()
                                Text(String(format: "%+.1f", locale: Locale(identifier: "es_ES"), dailyValue))
                                    .font(ImprovingFont.metricHero(22))
                                    .monospacedDigit()
                                    .foregroundColor(abs(dailyValue) < 0.05 ? BevelColors.textMuted : (factor.isPositive ? NutritionPalette.positiveMint : NutritionPalette.negativeOrange))
                            }
                            Text(factor.explanation)
                                .font(ImprovingFont.body(14))
                                .foregroundColor(BevelColors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)
                    }

                    Text("Alimentos de hoy que contribuyeron")
                        .font(ImprovingFont.sectionTitle(16.5))
                        .foregroundColor(BevelColors.textPrimary)

                    if contributingMeals.isEmpty {
                        BevelCard(cornerRadius: 16) {
                            Text("Ninguna comida registrada hoy tuvo impacto relevante en \(factor.title.lowercased()).")
                                .font(ImprovingFont.body(13.5))
                                .foregroundColor(BevelColors.textSecondary)
                                .padding(14)
                        }
                    } else {
                        ForEach(contributingMeals) { m in
                            let f = m.qualityFactors ?? GeminiCoachService.inferQualityFactors(title: m.title, qualityScore: m.qualityScore, alcoholDrinks: m.alcoholDrinks ?? 0)
                            let v = f.value(for: factor)
                            BevelCard(cornerRadius: 16) {
                                HStack {
                                    Text(m.emoji ?? GeminiCoachService.inferEmoji(forTitle: m.title)).font(.system(size: 20))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(m.title).font(ImprovingFont.cardTitle(14.5)).foregroundColor(BevelColors.textPrimary)
                                        Text("\(m.timeLabel) · \(m.kcal) kcal").font(ImprovingFont.caption(12)).foregroundColor(BevelColors.textMuted)
                                    }
                                    Spacer()
                                    Text(String(format: "%+.1f", locale: Locale(identifier: "es_ES"), v))
                                        .font(ImprovingFont.cardTitle(15))
                                        .monospacedDigit()
                                        .foregroundColor(factor.isPositive ? NutritionPalette.positiveMint : NutritionPalette.negativeOrange)
                                }
                                .padding(14)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(BevelColors.canvas)
        .scrollDismissesKeyboard(.interactively)
            .navigationTitle(factor.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cerrar", action: onClose) } }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct FullNutritionTimelineSheet: View {
    @ObservedObject var store: ImprovingStore
    let onEditMeal: (NutritionMealItem) -> Void
    let onAddMeal: () -> Void
    let onClose: () -> Void

    var body: some View {
        let sortedDates = store.mealsByDate.keys.sorted(by: >)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if sortedDates.isEmpty {
                        BevelCard(cornerRadius: 18) {
                            Text("Todavía no tienes comidas registradas en tu historial.")
                                .font(ImprovingFont.body(14))
                                .foregroundColor(BevelColors.textSecondary)
                                .padding(16)
                        }
                    } else {
                        ForEach(sortedDates, id: \.self) { iso in
                            let dayMeals = store.mealsByDate[iso] ?? []
                            if !dayMeals.isEmpty {
                                let totals = store.nutritionDayTotals(for: iso)
                                HStack {
                                    Text(iso)
                                        .font(ImprovingFont.cardTitle(15))
                                        .foregroundColor(BevelColors.textPrimary)
                                    Spacer()
                                    Text("\(totals.kcal) kcal · Calidad \(totals.score ?? 0)")
                                        .font(ImprovingFont.caption(12.5))
                                        .foregroundColor(BevelColors.textSecondary)
                                }
                                .padding(.top, 4)

                                ForEach(dayMeals) { meal in
                                    Button {
                                        if let dt = store.isoFormatter.date(from: iso) {
                                            store.selectDate(dt)
                                        }
                                        onEditMeal(meal)
                                    } label: {
                                        BevelCard(cornerRadius: 16) {
                                            HStack(spacing: 12) {
                                                Text(meal.emoji ?? GeminiCoachService.inferEmoji(forTitle: meal.title)).font(.system(size: 20))
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text("\(meal.timeLabel) · \(meal.title)")
                                                        .font(ImprovingFont.cardTitle(14.5))
                                                        .foregroundColor(BevelColors.textPrimary)
                                                        .lineLimit(1)
                                                    Text("\(meal.kcal) kcal · G \(meal.fatG)g · C \(meal.carbsG)g · P \(meal.proteinG)g")
                                                        .font(ImprovingFont.caption(12))
                                                        .foregroundColor(BevelColors.textSecondary)
                                                }
                                                Spacer()
                                                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(BevelColors.textMuted)
                                            }
                                            .padding(13)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(BevelColors.canvas)
        .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Cronología nutricional")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onAddMeal) {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar", action: onClose)
                }
            }
        }
    }
}

private struct NutritionInfoSheet: View {
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    BevelCard(cornerRadius: 20) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Cómo funciona tu Puntuación de nutrición")
                                .font(ImprovingFont.sectionTitle(18))
                                .foregroundColor(BevelColors.textPrimary)
                            Text("La puntuación del 1 al 100 resume la calidad global de los alimentos que registras cada día mediante foto o texto con Gemini IA, ponderando cada plato según su energía y los 11 factores de calidad alimentaria.")
                                .font(ImprovingFont.body(14))
                                .foregroundColor(BevelColors.textSecondary)
                            Text("Las matrices de puntos muestran el llenado de tus metas diarias de Grasas, Carbohidratos y Proteína, y Energía neta compara lo ingerido frente a tu gasto total real (metabolismo basal + calorías activas de Apple Salud).")
                                .font(ImprovingFont.body(14))
                                .foregroundColor(BevelColors.textSecondary)
                        }
                        .padding(16)
                    }
                }
                .padding(16)
            }
            .background(BevelColors.canvas)
        .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Guía de Nutrición")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cerrar", action: onClose) } }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Multimodal AI & Barcode Meal Composer Sheet (Camera + Gallery + OpenFoodFacts Barcode + Natural Text!)

private struct MealComposerSheet: View {
    @ObservedObject var store: ImprovingStore
    let existingMeal: NutritionMealItem?
    var initialMode: NutritionComposerInitialMode = .standard
    let onClose: () -> Void

    @State private var naturalDescription: String = ""
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var showCameraSheet: Bool = false
    @State private var showBarcodeScannerSheet: Bool = false
    @State private var didApplyInitialMode: Bool = false
    @State private var capturedImage: UIImage? = nil
    @State private var capturedJpegData: Data? = nil
    @State private var removedExistingPhoto: Bool = false
    @State private var showDeleteMealConfirm: Bool = false

    @State private var isAnalyzingAI: Bool = false
    @State private var aiFeedbackText: String? = nil
    @State private var aiModelBadge: String? = nil

    @State private var titleDraft: String = ""
    @State private var emojiDraft: String = "🍽️"
    @State private var timeDraft: String = ""
    @State private var kcalDraft: String = ""
    @State private var proteinDraft: String = ""
    @State private var carbsDraft: String = ""
    @State private var fatDraft: String = ""
    @State private var qualityDraft: Double = 85
    @State private var caffeineDraft: String = "0"
    @State private var alcoholDraft: String = "0"
    @State private var calciumDraft: String = "0"
    @State private var isFavoriteDraft: Bool = false
    @State private var computedFactors: NutritionQualityFactors? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // 1. Multimodal AI Analyzer Card
                    BevelCard(cornerRadius: 20) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 7) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(BevelColors.greenPrimary)
                                Text("ESCÁNER NUTRICIONAL IA (FOTO O TEXTO)")
                                    .font(ImprovingFont.microLabel(11))
                                    .foregroundColor(BevelColors.greenPrimary)
                                Spacer()
                                if let badge = aiModelBadge {
                                    Text(badge)
                                        .font(ImprovingFont.caption(10.5))
                                        .foregroundColor(BevelColors.skyBlue)
                                }
                            }

                            HStack(spacing: 8) {
                                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                    Button { showCameraSheet = true } label: {
                                        Label("Cámara", systemImage: "camera.fill")
                                            .font(ImprovingFont.caption(12))
                                            .fontWeight(.semibold)
                                            .foregroundColor(BevelColors.textPrimary)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(RoundedRectangle(cornerRadius: 12).fill(BevelColors.cardSubtle))
                                    }
                                }

                                PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                                    Label(capturedImage != nil ? "Foto" : "Fototeca", systemImage: "photo.on.rectangle")
                                        .font(ImprovingFont.caption(12))
                                        .fontWeight(.semibold)
                                        .foregroundColor(BevelColors.textPrimary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(RoundedRectangle(cornerRadius: 12).fill(BevelColors.cardSubtle))
                                }

                                Button { showBarcodeScannerSheet = true } label: {
                                    Label("Código", systemImage: "barcode.viewfinder")
                                        .font(ImprovingFont.caption(12))
                                        .fontWeight(.semibold)
                                        .foregroundColor(BevelColors.greenPrimary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(RoundedRectangle(cornerRadius: 12).fill(BevelColors.greenSoftBg))
                                }
                            }

                            if let img = capturedImage {
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 170)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                                    Button {
                                        capturedImage = nil
                                        capturedJpegData = nil
                                        selectedPhotoItem = nil
                                        removedExistingPhoto = true
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 22))
                                            .foregroundColor(.white)
                                            .shadow(radius: 4)
                                            .padding(8)
                                    }
                                }
                            }

                            TextField(
                                "Ej: 2 huevos revueltos con tostada integral, medio aguacate y un café solo",
                                text: $naturalDescription,
                                axis: .vertical
                            )
                            .lineLimit(2...4)
                            .font(ImprovingFont.body(13.5))
                            .foregroundColor(BevelColors.textPrimary)
                            .padding(11)
                            .background(RoundedRectangle(cornerRadius: 12).fill(BevelColors.cardSubtle))

                            Button { runMultimodalAnalysis() } label: {
                                HStack(spacing: 8) {
                                    if isAnalyzingAI {
                                        ProgressView().tint(.white)
                                        Text("Analizando plato y calidad con Gemini…")
                                    } else {
                                        Image(systemName: "wand.and.stars")
                                        Text("Calcular macros y factores con IA")
                                    }
                                }
                                .font(ImprovingFont.cardTitle(14))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    Capsule().fill(
                                        (naturalDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && capturedJpegData == nil)
                                            ? Color.gray.opacity(0.45)
                                            : BevelColors.indigoEnd
                                    )
                                )
                            }
                            .disabled(isAnalyzingAI || (naturalDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && capturedJpegData == nil))

                            if let note = aiFeedbackText, !note.isEmpty {
                                Text(note)
                                    .font(ImprovingFont.caption(12))
                                    .foregroundColor(BevelColors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(15)
                    }

                    // 2. Editable Macros & Micronutrients Card
                    BevelCard(cornerRadius: 20) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("DETALLES Y MACROS EDITABLES")
                                    .font(ImprovingFont.microLabel(11))
                                    .foregroundColor(BevelColors.textMuted)
                                Spacer()
                                Button {
                                    isFavoriteDraft.toggle()
                                } label: {
                                    Label(isFavoriteDraft ? "Favorito" : "Guardar fav.", systemImage: isFavoriteDraft ? "star.fill" : "star")
                                        .font(ImprovingFont.caption(11.5))
                                        .fontWeight(.semibold)
                                        .foregroundColor(isFavoriteDraft ? BevelColors.amberStart : BevelColors.textSecondary)
                                }
                            }

                            HStack(spacing: 8) {
                                TextField("🍽️", text: $emojiDraft)
                                    .font(.system(size: 20))
                                    .multilineTextAlignment(.center)
                                    .frame(width: 44)
                                    .padding(.vertical, 9)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.cardSubtle))

                                TextField("Nombre del plato", text: $titleDraft)
                                    .font(ImprovingFont.body(14))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .padding(10)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.cardSubtle))

                                TextField("14:30", text: $timeDraft)
                                    .font(ImprovingFont.body(14))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .frame(width: 68)
                                    .padding(10)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.cardSubtle))
                            }

                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                                numericField("Calorías (kcal)", text: $kcalDraft, accent: BevelColors.emeraldEnd)
                                numericField("Grasas (g)", text: $fatDraft, accent: NutritionPalette.fatBlue)
                                numericField("Carbohidratos (g)", text: $carbsDraft, accent: NutritionPalette.carbsAmber)
                                numericField("Proteína (g)", text: $proteinDraft, accent: NutritionPalette.proteinPink)
                                numericField("Cafeína (mg)", text: $caffeineDraft, accent: BevelColors.limeStart)
                                numericField("Alcohol (bebidas)", text: $alcoholDraft, accent: BevelColors.coralHigh, decimal: true)
                                numericField("Calcio (mg)", text: $calciumDraft, accent: BevelColors.periwinkleStart)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Puntuación de calidad nutricional")
                                        .font(ImprovingFont.caption(12))
                                        .foregroundColor(BevelColors.textSecondary)
                                    Spacer()
                                    Text("\(Int(qualityDraft.rounded())) / 100")
                                        .font(ImprovingFont.cardTitle(13.5))
                                        .monospacedDigit()
                                        .foregroundColor(qualityDraft >= 80 ? BevelColors.greenPrimary : BevelColors.amberStart)
                                }
                                Slider(value: $qualityDraft, in: 10...100, step: 1)
                                    .tint(NutritionPalette.scoreLavender)
                            }
                        }
                        .padding(15)
                    }

                    // 3. Save & Delete Buttons
                    Button { saveCurrentMeal() } label: {
                        Text(existingMeal == nil ? "Guardar comida" : "Guardar cambios")
                            .font(ImprovingFont.cardTitle(15))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(BevelColors.emeraldEnd))
                    }

                    if existingMeal != nil {
                        Button {
                            showDeleteMealConfirm = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                Text("Eliminar esta comida")
                            }
                            .font(ImprovingFont.cardTitle(14))
                            .foregroundColor(BevelColors.coralHigh)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(BevelColors.coralHigh.opacity(0.12)))
                        }
                    }
                }
                .padding(16)
            }
            .background(BevelColors.canvas)
        .scrollDismissesKeyboard(.interactively)
            .navigationTitle(existingMeal == nil ? "Registrar comida" : "Editar comida")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cerrar", action: onClose) } }
            .confirmationDialog(
                "¿Eliminar esta comida?",
                isPresented: $showDeleteMealConfirm,
                titleVisibility: .visible
            ) {
                Button("Eliminar comida permanentemente", role: .destructive) {
                    if let existing = existingMeal {
                        store.deleteMeal(id: existing.id)
                    }
                    onClose()
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Se borrarán «\(existingMeal?.title ?? "esta comida")» y su foto asociada.")
            }
            .onAppear {
                populateInitialFields()
                if !didApplyInitialMode && existingMeal == nil {
                    didApplyInitialMode = true
                    if initialMode == .barcode {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            showBarcodeScannerSheet = true
                        }
                    } else if initialMode == .camera && UIImagePickerController.isSourceTypeAvailable(.camera) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            showCameraSheet = true
                        }
                    }
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let rawData = try? await newItem.loadTransferable(type: Data.self),
                       let uiImg = UIImage(data: rawData),
                       let jpg = MealPhotoStorage.prepareJpegData(from: uiImg) {
                        await MainActor.run {
                            capturedImage = uiImg
                            capturedJpegData = jpg
                            removedExistingPhoto = false
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showCameraSheet) {
                CameraCaptureSheet(
                    onCapture: { img in
                        capturedImage = img
                        capturedJpegData = MealPhotoStorage.prepareJpegData(from: img)
                        removedExistingPhoto = false
                        showCameraSheet = false
                    },
                    onCancel: { showCameraSheet = false }
                )
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showBarcodeScannerSheet) {
                BarcodeScannerSheet(
                    onApplyEstimate: { est in
                        applyAnalyzedEstimate(est)
                        showBarcodeScannerSheet = false
                    },
                    onClose: { showBarcodeScannerSheet = false }
                )
            }
        }
    }

    private func applyAnalyzedEstimate(_ est: AnalyzedMealEstimate) {
        titleDraft = est.title
        emojiDraft = est.emoji
        kcalDraft = "\(est.kcal)"
        proteinDraft = "\(est.proteinG)"
        carbsDraft = "\(est.carbsG)"
        fatDraft = "\(est.fatG)"
        qualityDraft = Double(est.qualityScore)
        caffeineDraft = "\(Int(est.caffeineMg.rounded()))"
        alcoholDraft = est.alcoholDrinks > 0 ? String(format: "%.1f", est.alcoholDrinks) : "0"
        calciumDraft = "\(Int(est.calciumMg.rounded()))"
        computedFactors = est.qualityFactors
        aiFeedbackText = est.aiSummary
        aiModelBadge = est.usedLiveAI ? "✓ \(est.modelUsed)" : "Modo local"
    }

    private func numericField(_ label: String, text: Binding<String>, accent: Color, decimal: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(ImprovingFont.caption(11)).foregroundColor(accent)
            TextField("0", text: text)
                .keyboardType(decimal ? .decimalPad : .numberPad)
                .keyboardDoneToolbar()
                .font(ImprovingFont.cardTitle(15))
                .monospacedDigit()
                .foregroundColor(BevelColors.textPrimary)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.cardSubtle))
        }
    }

    private func populateInitialFields() {
        let nowFmt = DateFormatter()
        nowFmt.dateFormat = "HH:mm"
        if let m = existingMeal {
            titleDraft = m.title
            emojiDraft = m.emoji ?? GeminiCoachService.inferEmoji(forTitle: m.title)
            timeDraft = m.timeLabel
            kcalDraft = "\(m.kcal)"
            proteinDraft = "\(m.proteinG)"
            carbsDraft = "\(m.carbsG)"
            fatDraft = "\(m.fatG)"
            qualityDraft = Double(m.qualityScore)
            caffeineDraft = m.caffeineMg.map { "\(Int($0.rounded()))" } ?? "0"
            alcoholDraft = m.alcoholDrinks.map { String(format: "%.1f", $0) } ?? "0"
            calciumDraft = m.calciumMg.map { "\(Int($0.rounded()))" } ?? "0"
            aiFeedbackText = m.aiNotes
            isFavoriteDraft = m.isFavorite
            computedFactors = m.qualityFactors
            if let img = MealPhotoStorage.loadImage(filename: m.photoFilename) {
                capturedImage = img
                capturedJpegData = MealPhotoStorage.prepareJpegData(from: img)
            }
        } else {
            timeDraft = nowFmt.string(from: Date())
        }
    }

    private func runMultimodalAnalysis() {
        isAnalyzingAI = true
        let desc = naturalDescription
        let jpg = capturedJpegData
        let key = store.geminiApiKey
        let model = store.selectedGeminiModel
        let allowCloud = store.cloudAIEnabled
        let allowKeyless = store.allowKeylessAIFallback

        Task {
            let est = await GeminiCoachService.shared.analyzeMealWithAI(
                descriptionText: desc,
                jpegImageData: jpg,
                apiKey: key,
                selectedModel: model,
                allowCloudAI: allowCloud,
                allowKeylessFallback: allowKeyless
            )
            await MainActor.run {
                isAnalyzingAI = false
                titleDraft = est.title
                emojiDraft = est.emoji
                kcalDraft = "\(est.kcal)"
                proteinDraft = "\(est.proteinG)"
                carbsDraft = "\(est.carbsG)"
                fatDraft = "\(est.fatG)"
                qualityDraft = Double(est.qualityScore)
                caffeineDraft = "\(Int(est.caffeineMg.rounded()))"
                alcoholDraft = est.alcoholDrinks > 0 ? String(format: "%.1f", est.alcoholDrinks) : "0"
                calciumDraft = "\(Int(est.calciumMg.rounded()))"
                computedFactors = est.qualityFactors
                aiFeedbackText = est.aiSummary
                aiModelBadge = est.usedLiveAI ? "✓ \(est.modelUsed)" : "Modo local"
            }
        }
    }

    private func saveCurrentMeal() {
        let cleanTitle: String = {
            let t = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
            let d = naturalDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            return d.isEmpty ? "Comida registrada" : String(d.prefix(54))
        }()
        let cleanTime = timeDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Hoy" : timeDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = max(0, Int(proteinDraft) ?? 0)
        let c = max(0, Int(carbsDraft) ?? 0)
        let f = max(0, Int(fatDraft) ?? 0)
        var kcal = max(0, Int(kcalDraft) ?? 0)
        if kcal == 0 && (p + c + f) > 0 {
            kcal = p * 4 + c * 4 + f * 9
        }
        let caff = max(0, Double(caffeineDraft.replacingOccurrences(of: ",", with: ".")) ?? 0)
        let alc = max(0, Double(alcoholDraft.replacingOccurrences(of: ",", with: ".")) ?? 0)
        let calc = max(0, Double(calciumDraft.replacingOccurrences(of: ",", with: ".")) ?? 0)
        let qScore = Int(qualityDraft.rounded())

        var savedFilename: String? = existingMeal?.photoFilename
        if removedExistingPhoto {
            MealPhotoStorage.deletePhoto(filename: existingMeal?.photoFilename)
            savedFilename = nil
        } else if let jpg = capturedJpegData {
            savedFilename = MealPhotoStorage.savePhotoData(jpg, existingFilename: existingMeal?.photoFilename)
        }

        let finalEmoji = emojiDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? GeminiCoachService.inferEmoji(forTitle: cleanTitle)
            : String(emojiDraft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2))

        let finalFactors = computedFactors ?? GeminiCoachService.inferQualityFactors(
            title: cleanTitle,
            qualityScore: qScore,
            alcoholDrinks: alc
        )

        let item = NutritionMealItem(
            id: existingMeal?.id ?? UUID().uuidString,
            title: cleanTitle,
            timeLabel: cleanTime,
            kcal: kcal,
            proteinG: p,
            carbsG: c,
            fatG: f,
            qualityScore: qScore,
            caffeineMg: caff > 0 ? caff : nil,
            alcoholDrinks: alc > 0 ? alc : nil,
            calciumMg: calc > 0 ? calc : nil,
            aiNotes: aiFeedbackText,
            photoFilename: savedFilename,
            emoji: finalEmoji,
            qualityFactors: finalFactors,
            isFavorite: isFavoriteDraft
        )
        store.saveMeal(item)
        if isFavoriteDraft {
            store.saveFoodToLibrary(SavedFoodLibraryItem(
                id: "fav_\(item.id)",
                kind: .favorite,
                emoji: finalEmoji,
                title: cleanTitle,
                kcal: kcal,
                proteinG: p,
                carbsG: c,
                fatG: f,
                qualityScore: qScore,
                caffeineMg: item.caffeineMg,
                alcoholDrinks: item.alcoholDrinks,
                calciumMg: item.calciumMg,
                qualityFactors: finalFactors
            ))
        }
        onClose()
    }
}

// MARK: - N3. OpenFoodFacts Barcode Scanner Sheet (Native AVFoundation + Gram Scaler + Zero API Key!)

private struct BarcodeScannerSheet: View {
    let onApplyEstimate: (AnalyzedMealEstimate) -> Void
    let onClose: () -> Void

    @State private var isTorchOn: Bool = false
    @State private var manualCode: String = ""
    @State private var isLookingUp: Bool = false
    @State private var cameraNotice: String? = nil
    @State private var errorText: String? = nil
    @State private var foundProduct: BarcodeProductResult? = nil
    @State private var gramsAmount: Double = 100.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Live Camera Viewfinder with Laser Guide
                    ZStack(alignment: .bottomTrailing) {
                        BarcodeScannerCameraView(
                            isTorchOn: isTorchOn,
                            isPaused: foundProduct != nil || isLookingUp,
                            onCodeDetected: { code in
                                manualCode = code
                                lookupBarcode(code)
                            },
                            onCameraUnavailable: { notice in
                                cameraNotice = notice
                            }
                        )
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(BevelColors.cardBorder, lineWidth: 1)
                        )
                        .overlay {
                            if let notice = cameraNotice {
                                VStack(spacing: 8) {
                                    Image(systemName: "barcode.viewfinder")
                                        .font(.system(size: 32))
                                        .foregroundColor(BevelColors.textSecondary)
                                    Text(notice)
                                        .font(ImprovingFont.caption(12.5))
                                        .foregroundColor(BevelColors.textSecondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 24)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(BevelColors.card)
                                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            } else {
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(BevelColors.greenPrimary.opacity(0.9), lineWidth: 2)
                                    .frame(width: 220, height: 100)
                                    .overlay(
                                        Rectangle()
                                            .fill(BevelColors.greenPrimary.opacity(0.65))
                                            .frame(height: 1.5)
                                    )
                            }
                        }

                        if cameraNotice == nil {
                            Button {
                                isTorchOn.toggle()
                            } label: {
                                Image(systemName: isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(isTorchOn ? .black : .white)
                                    .frame(width: 38, height: 38)
                                    .background(Circle().fill(isTorchOn ? BevelColors.amberStart : Color.black.opacity(0.65)))
                            }
                            .padding(12)
                        }
                    }

                    // Manual EAN Input Fallback
                    BevelCard(cornerRadius: 18) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("CÓDIGO DE BARRAS (OPENFOODFACTS GRATIS)")
                                .font(ImprovingFont.microLabel(10.5))
                                .foregroundColor(BevelColors.textMuted)
                            HStack(spacing: 8) {
                TextField("Ej: 8410076472106", text: $manualCode)
                    .keyboardType(.numberPad)
                    .keyboardDoneToolbar()
                                    .font(ImprovingFont.cardTitle(15))
                                    .monospacedDigit()
                                    .foregroundColor(BevelColors.textPrimary)
                                    .padding(10)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.cardSubtle))

                                Button {
                                    lookupBarcode(manualCode)
                                } label: {
                                    if isLookingUp {
                                        ProgressView().tint(.white)
                                            .frame(width: 78, height: 40)
                                            .background(Capsule().fill(BevelColors.indigoEnd))
                                    } else {
                                        Text("Buscar")
                                            .font(ImprovingFont.cardTitle(13.5))
                                            .foregroundColor(.white)
                                            .frame(width: 78, height: 40)
                                            .background(Capsule().fill(BevelColors.indigoEnd))
                                    }
                                }
                                .disabled(isLookingUp || manualCode.trimmingCharacters(in: .whitespaces).isEmpty)
                            }

                            if let err = errorText {
                                Text(err)
                                    .font(ImprovingFont.caption(12))
                                    .foregroundColor(BevelColors.amberStart)
                            }
                        }
                        .padding(14)
                    }

                    // Found Product Preview & Portion Adjuster
                    if let prod = foundProduct {
                        let est = prod.toMealEstimate(grams: gramsAmount)
                        BevelCard(cornerRadius: 20) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(alignment: .top, spacing: 10) {
                                    Text(est.emoji)
                                        .font(.system(size: 28))
                                        .frame(width: 44, height: 44)
                                        .background(Circle().fill(BevelColors.cardSubtle))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(prod.displayTitle)
                                            .font(ImprovingFont.cardTitle(15.5))
                                            .foregroundColor(BevelColors.textPrimary)
                                        HStack(spacing: 8) {
                                            Text("Calidad \(est.qualityScore)/100")
                                                .font(ImprovingFont.caption(12))
                                                .fontWeight(.bold)
                                                .foregroundColor(est.qualityScore >= 70 ? BevelColors.greenPrimary : BevelColors.amberStart)
                                            if let ns = prod.nutriscoreGrade?.uppercased(), !ns.isEmpty {
                                                Text("Nutri-Score \(ns)")
                                                    .font(ImprovingFont.caption(11.5))
                                                    .fontWeight(.semibold)
                                                    .foregroundColor(BevelColors.skyBlue)
                                            }
                                            if let sz = prod.servingSizeLabel, !sz.isEmpty {
                                                Text("Porción: \(sz)")
                                                    .font(ImprovingFont.caption(11.5))
                                                    .foregroundColor(BevelColors.textMuted)
                                            }
                                        }
                                    }
                                    Spacer()
                                }

                                // Portion Gram Control
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Cantidad consumida")
                                            .font(ImprovingFont.caption(12.5))
                                            .foregroundColor(BevelColors.textSecondary)
                                        Spacer()
                                        Text("\(Int(gramsAmount.rounded())) g")
                                            .font(ImprovingFont.cardTitle(16))
                                            .monospacedDigit()
                                            .foregroundColor(BevelColors.textPrimary)
                                    }
                                    HStack(spacing: 8) {
                                        ForEach([30.0, 50.0, 100.0, 150.0, 200.0], id: \.self) { preset in
                                            Button("\(Int(preset))g") {
                                                UISelectionFeedbackGenerator().selectionChanged()
                                                gramsAmount = preset
                                            }
                                            .font(ImprovingFont.caption(12))
                                            .fontWeight(.bold)
                                            .foregroundColor(abs(gramsAmount - preset) < 1 ? .white : BevelColors.textSecondary)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 7)
                                            .background(Capsule().fill(abs(gramsAmount - preset) < 1 ? BevelColors.indigoEnd : BevelColors.cardSubtle))
                                        }
                                    }
                                    Slider(value: $gramsAmount, in: 10...500, step: 5)
                                        .tint(BevelColors.greenPrimary)
                                }

                                // Scaled Macros Grid
                                HStack(spacing: 8) {
                                    macroPill("kcal", val: "\(est.kcal)", color: BevelColors.textPrimary)
                                    macroPill("Grasa", val: "\(est.fatG)g", color: NutritionPalette.fatBlue)
                                    macroPill("Carbos", val: "\(est.carbsG)g", color: NutritionPalette.carbsAmber)
                                    macroPill("Prot", val: "\(est.proteinG)g", color: NutritionPalette.proteinPink)
                                }

                                Button {
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                    onApplyEstimate(est)
                                } label: {
                                    Text("Usar este producto (\(est.kcal) kcal)")
                                        .font(ImprovingFont.cardTitle(15))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 13)
                                        .background(Capsule().fill(BevelColors.emeraldEnd))
                                }
                            }
                            .padding(16)
                        }
                    }
                }
                .padding(16)
            }
            .background(BevelColors.canvas)
        .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Escanear código de barras")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar", action: onClose)
                }
            }
        }
    }

    private func lookupBarcode(_ raw: String) {
        guard !isLookingUp else { return }
        isLookingUp = true
        errorText = nil
        Task {
            let res = await OpenFoodFactsService.lookupProduct(barcode: raw)
            await MainActor.run {
                isLookingUp = false
                if let p = res.product {
                    foundProduct = p
                    gramsAmount = p.defaultGrams
                    errorText = nil
                } else {
                    foundProduct = nil
                    errorText = res.errorMessage
                }
            }
        }
    }

    private func macroPill(_ label: String, val: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(val).font(ImprovingFont.cardTitle(15)).monospacedDigit().foregroundColor(color)
            Text(label).font(ImprovingFont.caption(10.5)).foregroundColor(BevelColors.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 11).fill(BevelColors.cardSubtle))
    }
}

// MARK: - Persisted Nutrient Detail Screen (Proteína, Carbos, Grasas, Cafeína, Hidratación, Alcohol, Calcio)

struct NutrientDetailScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void

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
                .padding(.bottom, 185)
            }

            HStack(spacing: 12) {
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
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
        .background(BevelColors.sheetHeaderBg)
        .scrollDismissesKeyboard(.interactively)
        .confirmationDialog("¿Restablecer el registro manual de \(spec.displayTitle.lowercased()) de este día?", isPresented: $showResetConfirmation, titleVisibility: .visible) {
            Button("Restablecer a 0", role: .destructive) { store.resetNutrientAmount(key: key) }
            Button("Cancelar", role: .cancel) {}
        }
        .sheet(isPresented: $showCustomInputSheet) {
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
        .scrollDismissesKeyboard(.interactively)
                .navigationTitle("Añadir \(spec.displayTitle)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cerrar") { showCustomInputSheet = false } } }
            }
            .presentationDetents([.height(290)])
        }
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
            let goalMl = max(norms.hydrationGoalLiters * 1000.0, 1800.0)
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

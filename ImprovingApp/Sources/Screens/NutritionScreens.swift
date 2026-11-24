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
            let renderer = UIGraphicsImageRenderer(size: newSize)
            targetImage = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        } else {
            targetImage = image
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

// MARK: - Main Nutrition Screen (Multimodal Gemini AI + Real Macro Routing + Edit/Delete)

struct NutricionScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void
    let onOpenNutrient: (String) -> Void

    @State private var showMealComposer: Bool = false
    @State private var mealToEdit: NutritionMealItem? = nil

    var body: some View {
        let meals = store.mealsToday
        let hydrationMl = store.totalHydrationTodayMl
        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: store.userProfile)
        let calFrac = min(Double(store.totalCaloriesToday) / Double(max(norms.maintenanceCaloriesKcal, 1200)), 1.0)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DetailSheetHeader(
                    title: "Nutrición",
                    onBack: onBack,
                    rightSystemIcon: "sparkles",
                    onRightAction: {
                        mealToEdit = nil
                        showMealComposer = true
                    }
                )

                BevelCard(cornerRadius: 22) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("ENERGÍA INGERIDA · \(store.dateLabel.uppercased())")
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
                            VStack(alignment: .trailing, spacing: 4) {
                                if let fq = store.foodQualityScore {
                                    let qColor = fq >= 80 ? BevelColors.greenPrimary : (fq >= 60 ? BevelColors.amberStart : BevelColors.coralHigh)
                                    Text("Calidad \(fq)/100")
                                        .font(ImprovingFont.cardTitle(13))
                                        .foregroundColor(qColor)
                                        .padding(.horizontal, 11)
                                        .padding(.vertical, 5)
                                        .background(Capsule().fill(qColor.opacity(0.14)))
                                }
                                if let cgm = store.cgmMgDl {
                                    Text("CGM \(cgm) mg/dL")
                                        .font(ImprovingFont.caption(11.5))
                                        .foregroundColor(BevelColors.textSecondary)
                                }
                            }
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.08)).frame(height: 7)
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [BevelColors.emeraldEnd, BevelColors.greenPrimary],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(calFrac > 0 ? 10 : 0, geo.size.width * CGFloat(calFrac)), height: 7)
                            }
                        }
                        .frame(height: 7)

                        // Properly wired Macro Pills -> Proteína, Carbohidratos, Grasas!
                        HStack(spacing: 10) {
                            Button { onOpenNutrient("Proteína") } label: {
                                macroPill("Proteína", "\(store.totalProteinToday)g", target: "\(norms.proteinGoalG)g", frac: Double(store.totalProteinToday) / Double(max(norms.proteinGoalG, 1)), color: BevelColors.strengthPink)
                            }
                            Button { onOpenNutrient("Carbohidratos") } label: {
                                macroPill("Carbos", "\(store.totalCarbsToday)g", target: "\(norms.carbsGoalG)g", frac: Double(store.totalCarbsToday) / Double(max(norms.carbsGoalG, 1)), color: BevelColors.amberStart)
                            }
                            Button { onOpenNutrient("Grasas") } label: {
                                macroPill("Grasas", "\(store.totalFatToday)g", target: "\(norms.fatGoalG)g", frac: Double(store.totalFatToday) / Double(max(norms.fatGoalG, 1)), color: BevelColors.skyBlue)
                            }
                        }

                        // Persisted Micro & Beverage Chips (Hidratación, Cafeína, Alcohol, Calcio)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                microChip(
                                    emoji: "💧",
                                    label: "Agua",
                                    value: String(format: "%.2f L", locale: Locale(identifier: "es_ES"), hydrationMl / 1000.0),
                                    color: BevelColors.skyBlue
                                ) { onOpenNutrient("Hidratación") }

                                microChip(
                                    emoji: "☕",
                                    label: "Cafeína",
                                    value: "\(Int(store.totalCaffeineTodayMg.rounded())) mg",
                                    color: BevelColors.limeStart
                                ) { onOpenNutrient("Cafeína") }

                                microChip(
                                    emoji: "🍷",
                                    label: "Alcohol",
                                    value: store.totalAlcoholTodayDrinks > 0 ? String(format: "%.1f beb.", locale: Locale(identifier: "es_ES"), store.totalAlcoholTodayDrinks) : "0 beb.",
                                    color: BevelColors.coralHigh
                                ) { onOpenNutrient("Alcohol") }

                                microChip(
                                    emoji: "🦴",
                                    label: "Calcio",
                                    value: "\(Int(store.totalCalciumTodayMg.rounded())) mg",
                                    color: BevelColors.periwinkleStart
                                ) { onOpenNutrient("Calcio") }
                            }
                        }

                        HStack(spacing: 10) {
                            Button {
                                mealToEdit = nil
                                showMealComposer = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "camera.viewfinder")
                                        .font(.system(size: 13, weight: .bold))
                                    Text("Comida con IA / Manual")
                                        .font(ImprovingFont.caption(12.5))
                                        .fontWeight(.bold)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Capsule().fill(BevelColors.emeraldEnd))
                            }

                            Button {
                                UISelectionFeedbackGenerator().selectionChanged()
                                store.addHydrationGlass()
                            } label: {
                                Label(
                                    String(format: "%.2f / %.1f L", locale: Locale(identifier: "es_ES"), hydrationMl / 1000.0, norms.hydrationGoalLiters),
                                    systemImage: "drop.fill"
                                )
                                .font(ImprovingFont.caption(12.5))
                                .fontWeight(.bold)
                                .foregroundColor(BevelColors.skyBlue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Capsule().fill(BevelColors.skySoftBg))
                            }
                        }
                    }
                    .padding(16)
                }
                .padding(.horizontal, 16)

                HStack {
                    Text("Entradas de hoy (\(meals.count))")
                        .font(ImprovingFont.sectionTitle(18))
                        .foregroundColor(BevelColors.textPrimary)
                    Spacer()
                    if !meals.isEmpty {
                        Text("Toca para editar")
                            .font(ImprovingFont.caption(12))
                            .foregroundColor(BevelColors.textMuted)
                    }
                }
                .padding(.horizontal, 16)

                if meals.isEmpty {
                    BevelCard(cornerRadius: 20) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(BevelColors.greenPrimary)
                                    .frame(width: 40, height: 40)
                                    .background(Circle().fill(BevelColors.greenSoftBg))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Sin comidas registradas este día")
                                        .font(ImprovingFont.cardTitle(15))
                                        .foregroundColor(BevelColors.textPrimary)
                                    Text("Haz una foto al plato o descríbelo en una frase")
                                        .font(ImprovingFont.caption(12))
                                        .foregroundColor(BevelColors.textSecondary)
                                }
                            }
                            Text("Con Gemini multimodal puedes fotografiar tu plato o escribir por ejemplo «2 huevos revueltos con tostada y aguacate» para calcular al instante calorías, macros y calidad nutricional.")
                                .font(ImprovingFont.body(13))
                                .foregroundColor(BevelColors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)
                    }
                    .padding(.horizontal, 16)
                } else {
                    ForEach(Array(meals.enumerated()), id: \.element.id) { idx, meal in
                        BevelCard(cornerRadius: 18) {
                            HStack(spacing: 12) {
                                Button {
                                    mealToEdit = meal
                                    showMealComposer = true
                                } label: {
                                    HStack(spacing: 12) {
                                        if let img = MealPhotoStorage.loadImage(filename: meal.photoFilename) {
                                            Image(uiImage: img)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 48, height: 48)
                                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        } else {
                                            Text(["🍳", "🥗", "🐟", "🍲"][idx % 4])
                                                .font(.system(size: 20))
                                                .frame(width: 48, height: 48)
                                                .background(RoundedRectangle(cornerRadius: 12).fill(BevelColors.cardSubtle))
                                        }

                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack(spacing: 6) {
                                                Text(meal.timeLabel)
                                                    .font(ImprovingFont.caption(11.5))
                                                    .foregroundColor(BevelColors.textMuted)
                                                Text("Calidad \(meal.qualityScore)")
                                                    .font(ImprovingFont.caption(10.5))
                                                    .fontWeight(.semibold)
                                                    .foregroundColor(meal.qualityScore >= 80 ? BevelColors.greenPrimary : BevelColors.amberStart)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Capsule().fill(Color.white.opacity(0.06)))
                                            }
                                            Text(meal.title)
                                                .font(ImprovingFont.cardTitle(14.5))
                                                .foregroundColor(BevelColors.textPrimary)
                                                .lineLimit(1)

                                            let extras: String = {
                                                var parts: [String] = []
                                                if let c = meal.caffeineMg, c > 0 { parts.append("☕ \(Int(c.rounded()))mg") }
                                                if let a = meal.alcoholDrinks, a > 0 { parts.append(String(format: "🍷 %.1f", locale: Locale(identifier: "es_ES"), a)) }
                                                return parts.isEmpty ? "" : "  " + parts.joined(separator: "  ")
                                            }()
                                            Text("🔥 \(meal.kcal) kcal  🍗 \(meal.proteinG)g  🌾 \(meal.carbsG)g  🥑 \(meal.fatG)g\(extras)")
                                                .font(ImprovingFont.caption(11.5))
                                                .foregroundColor(BevelColors.textSecondary)
                                                .lineLimit(1)
                                        }
                                        Spacer(minLength: 4)
                                    }
                                }
                                .buttonStyle(.plain)

                                Button {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    MealPhotoStorage.deletePhoto(filename: meal.photoFilename)
                                    store.deleteMeal(id: meal.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(BevelColors.textMuted)
                                        .frame(width: 34, height: 34)
                                        .background(Circle().fill(BevelColors.cardSubtle))
                                }
                            }
                            .padding(13)
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.bottom, 150)
        }
        .background(BevelColors.canvas)
        .sheet(isPresented: $showMealComposer) {
            MealComposerSheet(
                store: store,
                existingMeal: mealToEdit,
                onClose: {
                    showMealComposer = false
                    mealToEdit = nil
                }
            )
        }
    }

    private func macroPill(_ title: String, _ val: String, target: String, frac: Double, color: Color) -> some View {
        let clamped = min(max(frac, 0.0), 1.0)
        return VStack(alignment: .leading, spacing: 5) {
            Text(title).font(ImprovingFont.caption(11.5)).foregroundColor(BevelColors.textSecondary)
            Text(val).font(ImprovingFont.metricHero(18)).monospacedDigit().foregroundColor(BevelColors.textPrimary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08)).frame(height: 4)
                    Capsule().fill(color).frame(width: max(clamped > 0 ? 6 : 0, geo.size.width * CGFloat(clamped)), height: 4)
                }
            }
            .frame(height: 4)
            Text("Meta \(target)").font(ImprovingFont.caption(10.5)).foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 14).fill(BevelColors.cardSubtle))
    }

    private func microChip(emoji: String, label: String, value: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(emoji).font(.system(size: 13))
                Text(label)
                    .font(ImprovingFont.caption(12))
                    .foregroundColor(BevelColors.textSecondary)
                Text(value)
                    .font(ImprovingFont.caption(12))
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundColor(color)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(Capsule().fill(BevelColors.cardSubtle))
            .overlay(Capsule().strokeBorder(BevelColors.cardBorder, lineWidth: 0.7))
        }
    }
}

// MARK: - Multimodal AI Meal Composer & Editor Sheet (Camera + Gallery + Natural Text + Manual Override)

private struct MealComposerSheet: View {
    @ObservedObject var store: ImprovingStore
    let existingMeal: NutritionMealItem?
    let onClose: () -> Void

    @State private var naturalDescription: String = ""
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var showCameraSheet: Bool = false
    @State private var capturedImage: UIImage? = nil
    @State private var capturedJpegData: Data? = nil
    @State private var removedExistingPhoto: Bool = false

    @State private var isAnalyzingAI: Bool = false
    @State private var aiFeedbackText: String? = nil
    @State private var aiModelBadge: String? = nil

    @State private var titleDraft: String = ""
    @State private var timeDraft: String = ""
    @State private var kcalDraft: String = ""
    @State private var proteinDraft: String = ""
    @State private var carbsDraft: String = ""
    @State private var fatDraft: String = ""
    @State private var qualityDraft: Double = 85
    @State private var caffeineDraft: String = "0"
    @State private var alcoholDraft: String = "0"
    @State private var calciumDraft: String = "0"

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

                            HStack(spacing: 10) {
                                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                    Button {
                                        showCameraSheet = true
                                    } label: {
                                        Label("Cámara", systemImage: "camera.fill")
                                            .font(ImprovingFont.caption(12.5))
                                            .fontWeight(.semibold)
                                            .foregroundColor(BevelColors.textPrimary)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(RoundedRectangle(cornerRadius: 12).fill(BevelColors.cardSubtle))
                                    }
                                }

                                PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                                    Label(capturedImage != nil ? "Cambiar foto" : "Fototeca", systemImage: "photo.on.rectangle")
                                        .font(ImprovingFont.caption(12.5))
                                        .fontWeight(.semibold)
                                        .foregroundColor(BevelColors.textPrimary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(RoundedRectangle(cornerRadius: 12).fill(BevelColors.cardSubtle))
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

                            Button {
                                runMultimodalAnalysis()
                            } label: {
                                HStack(spacing: 8) {
                                    if isAnalyzingAI {
                                        ProgressView().tint(.white)
                                        Text("Analizando plato con Gemini…")
                                    } else {
                                        Image(systemName: "wand.and.stars")
                                        Text("Calcular calorías y macros con IA")
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
                                Button("4P+4C+9G → kcal") {
                                    let p = Int(proteinDraft) ?? 0
                                    let c = Int(carbsDraft) ?? 0
                                    let f = Int(fatDraft) ?? 0
                                    kcalDraft = "\(p * 4 + c * 4 + f * 9)"
                                }
                                .font(ImprovingFont.caption(11))
                                .foregroundColor(BevelColors.skyBlue)
                            }

                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Plato / Comida").font(ImprovingFont.caption(11.5)).foregroundColor(BevelColors.textSecondary)
                                    TextField("Nombre del plato", text: $titleDraft)
                                        .font(ImprovingFont.body(14))
                                        .foregroundColor(BevelColors.textPrimary)
                                        .padding(10)
                                        .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.cardSubtle))
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Hora").font(ImprovingFont.caption(11.5)).foregroundColor(BevelColors.textSecondary)
                                    TextField("14:30", text: $timeDraft)
                                        .font(ImprovingFont.body(14))
                                        .foregroundColor(BevelColors.textPrimary)
                                        .frame(width: 78)
                                        .padding(10)
                                        .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.cardSubtle))
                                }
                            }

                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                                numericField("Calorías (kcal)", text: $kcalDraft, accent: BevelColors.emeraldEnd)
                                numericField("Proteína (g)", text: $proteinDraft, accent: BevelColors.strengthPink)
                                numericField("Carbohidratos (g)", text: $carbsDraft, accent: BevelColors.amberStart)
                                numericField("Grasas (g)", text: $fatDraft, accent: BevelColors.skyBlue)
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
                                    .tint(BevelColors.greenPrimary)
                            }
                        }
                        .padding(15)
                    }

                    // 3. Save & Delete Buttons
                    Button {
                        saveCurrentMeal()
                    } label: {
                        Text(existingMeal == nil ? "Guardar comida" : "Guardar cambios")
                            .font(ImprovingFont.cardTitle(15))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(BevelColors.emeraldEnd))
                    }

                    if let existing = existingMeal {
                        Button {
                            MealPhotoStorage.deletePhoto(filename: existing.photoFilename)
                            store.deleteMeal(id: existing.id)
                            onClose()
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
            .navigationTitle(existingMeal == nil ? "Registrar comida" : "Editar comida")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar", action: onClose)
                }
            }
            .onAppear {
                populateInitialFields()
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
        }
    }

    private func numericField(_ label: String, text: Binding<String>, accent: Color, decimal: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(ImprovingFont.caption(11))
                .foregroundColor(accent)
            TextField("0", text: text)
                .keyboardType(decimal ? .decimalPad : .numberPad)
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

        Task {
            let est = await GeminiCoachService.shared.analyzeMealWithAI(
                descriptionText: desc,
                jpegImageData: jpg,
                apiKey: key,
                selectedModel: model
            )
            await MainActor.run {
                isAnalyzingAI = false
                titleDraft = est.title
                kcalDraft = "\(est.kcal)"
                proteinDraft = "\(est.proteinG)"
                carbsDraft = "\(est.carbsG)"
                fatDraft = "\(est.fatG)"
                qualityDraft = Double(est.qualityScore)
                caffeineDraft = "\(Int(est.caffeineMg.rounded()))"
                alcoholDraft = est.alcoholDrinks > 0 ? String(format: "%.1f", est.alcoholDrinks) : "0"
                calciumDraft = "\(Int(est.calciumMg.rounded()))"
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

        var savedFilename: String? = existingMeal?.photoFilename
        if removedExistingPhoto {
            MealPhotoStorage.deletePhoto(filename: existingMeal?.photoFilename)
            savedFilename = nil
        } else if let jpg = capturedJpegData {
            savedFilename = MealPhotoStorage.savePhotoData(jpg, existingFilename: existingMeal?.photoFilename)
        }

        let item = NutritionMealItem(
            id: existingMeal?.id ?? UUID().uuidString,
            title: cleanTitle,
            timeLabel: cleanTime,
            kcal: kcal,
            proteinG: p,
            carbsG: c,
            fatG: f,
            qualityScore: Int(qualityDraft.rounded()),
            caffeineMg: caff > 0 ? caff : nil,
            alcoholDrinks: alc > 0 ? alc : nil,
            calciumMg: calc > 0 ? calc : nil,
            aiNotes: aiFeedbackText,
            photoFilename: savedFilename
        )
        store.saveMeal(item)
        onClose()
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
        let key = store.selectedNutrientKey.isEmpty ? "Proteína" : store.selectedNutrientKey
        let low = key.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))

        let spec = nutrientSpec(for: low, norms: norms)
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

                    // Semi-Circle Arc Gauge Card for ALL Nutrients!
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

                    // Breakdown Header
                    HStack {
                        Text("Entradas registradas · \(store.dateLabel)")
                            .font(ImprovingFont.sectionTitle(17))
                            .foregroundColor(BevelColors.textPrimary)
                        Spacer()
                        if manualVal > 0 {
                            Button("Borrar manual") {
                                store.resetNutrientAmount(key: key)
                            }
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
                                    emoji: "🍽️",
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

            // Dual Persisted Action Pills
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
        .confirmationDialog("¿Restablecer el registro manual de \(spec.displayTitle.lowercased()) de este día?", isPresented: $showResetConfirmation, titleVisibility: .visible) {
            Button("Restablecer a 0", role: .destructive) {
                store.resetNutrientAmount(key: key)
            }
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
                        .font(ImprovingFont.displayLarge(28))
                        .monospacedDigit()
                        .foregroundColor(BevelColors.textPrimary)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(BevelColors.card))

                    Button {
                        let val = Double(customAmountText.replacingOccurrences(of: ",", with: ".")) ?? 0
                        if val > 0 {
                            store.addNutrientAmount(key: key, amount: val)
                        }
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
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Cerrar") { showCustomInputSheet = false }
                    }
                }
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

    private func nutrientSpec(for lowKey: String, norms: PersonalizedPhysiologyNorms) -> NutrientSpec {
        let intFmt: (Double) -> String = { "\(Int($0.rounded()))" }
        let decFmt: (Double) -> String = { String(format: "%.1f", locale: Locale(identifier: "es_ES"), $0) }

        if lowKey.contains("hidra") || lowKey.contains("agua") {
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
        } else if lowKey.contains("prote") {
            return NutrientSpec(
                displayTitle: "Proteína", emoji: "🍗", unit: "g", goal: Double(max(norms.proteinGoalG, 60)),
                quickIncrement: 25, quickButtonLabel: "+ 25 g proteína",
                accentColor: BevelColors.strengthPink, isHydration: false, isUpperLimit: false,
                mealsContribution: Double(store.mealsToday.reduce(0) { $0 + $1.proteinG }),
                mealExtractor: { Double($0.proteinG) }, formatValue: intFmt
            )
        } else if lowKey.contains("carb") {
            return NutrientSpec(
                displayTitle: "Carbohidratos", emoji: "🌾", unit: "g", goal: Double(max(norms.carbsGoalG, 80)),
                quickIncrement: 30, quickButtonLabel: "+ 30 g carbos",
                accentColor: BevelColors.amberStart, isHydration: false, isUpperLimit: false,
                mealsContribution: Double(store.mealsToday.reduce(0) { $0 + $1.carbsG }),
                mealExtractor: { Double($0.carbsG) }, formatValue: intFmt
            )
        } else if lowKey.contains("gras") {
            return NutrientSpec(
                displayTitle: "Grasas", emoji: "🥑", unit: "g", goal: Double(max(norms.fatGoalG, 40)),
                quickIncrement: 10, quickButtonLabel: "+ 10 g grasas",
                accentColor: BevelColors.skyBlue, isHydration: false, isUpperLimit: false,
                mealsContribution: Double(store.mealsToday.reduce(0) { $0 + $1.fatG }),
                mealExtractor: { Double($0.fatG) }, formatValue: intFmt
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
                    Text(time)
                        .font(ImprovingFont.caption(11.5))
                        .foregroundColor(BevelColors.textMuted)
                    Text(title)
                        .font(ImprovingFont.cardTitle(14.5))
                        .foregroundColor(BevelColors.textPrimary)
                        .lineLimit(1)
                    if let meta {
                        Text(meta)
                            .font(ImprovingFont.caption(11.5))
                            .foregroundColor(BevelColors.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text(amount)
                    .font(ImprovingFont.cardTitle(14))
                    .monospacedDigit()
                    .foregroundColor(BevelColors.textPrimary)
            }
            .padding(14)
        }
    }
}

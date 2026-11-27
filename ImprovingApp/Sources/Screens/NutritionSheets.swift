import SwiftUI
import UIKit
import PhotosUI

// MARK: - Native Camera Capture Wrapper (Fallback-Safe on Simulator)

struct CameraCaptureSheet: UIViewControllerRepresentable {
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

// MARK: - Supporting Sheets (Mis Alimentos, Objetivos, Factor Breakdown, Full Timeline, Info)

struct MisAlimentosSheet: View {
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

struct NutritionGoalsSheet: View {
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

                            Divider().background(BevelColors.divider)

                            Toggle(isOn: Binding(
                                get: { store.dynamicStrainNutritionEnabled },
                                set: { store.setDynamicStrainNutrition(enabled: $0) }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Carb Cycling dinámico por Strain")
                                        .font(ImprovingFont.cardTitle(13.5))
                                        .foregroundColor(BevelColors.textPrimary)
                                    Text("Sube carbohidratos y electrolitos en días duros (Strain ≥ 14) y recorta suave en descanso (< 7) protegiendo la proteína.")
                                        .font(ImprovingFont.caption(11))
                                        .foregroundColor(BevelColors.textSecondary)
                                }
                            }
                            .tint(BevelColors.emeraldEnd)
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

struct FactorBreakdownSheet: View {
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
            .navigationTitle(factor.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cerrar", action: onClose) } }
        }
        .presentationDetents([.medium, .large])
    }
}

struct FullNutritionTimelineSheet: View {
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

struct NutritionInfoSheet: View {
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
            .navigationTitle("Guía de Nutrición")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cerrar", action: onClose) } }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Multimodal AI & Barcode Meal Composer Sheet (Camera + Gallery + OpenFoodFacts Barcode + Natural Text!)

struct MealComposerSheet: View {
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
    @State private var fiberDraft: Double? = nil
    @State private var sugarDraft: Double? = nil
    @State private var sodiumDraft: Double? = nil
    @State private var potassiumDraft: Double? = nil
    @State private var magnesiumDraft: Double? = nil
    @State private var ironDraft: Double? = nil
    @State private var vitaminDDraft: Double? = nil
    @State private var omega3Draft: Double? = nil

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
        fiberDraft = est.fiberG > 0 ? est.fiberG : nil
        sugarDraft = est.sugarG > 0 ? est.sugarG : nil
        sodiumDraft = est.sodiumMg > 0 ? est.sodiumMg : nil
        potassiumDraft = est.potassiumMg > 0 ? est.potassiumMg : nil
        magnesiumDraft = est.magnesiumMg > 0 ? est.magnesiumMg : nil
        ironDraft = est.ironMg > 0 ? est.ironMg : nil
        vitaminDDraft = est.vitaminDMcg > 0 ? est.vitaminDMcg : nil
        omega3Draft = est.omega3G > 0 ? est.omega3G : nil
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
            fiberDraft = m.fiberG
            sugarDraft = m.sugarG
            sodiumDraft = m.sodiumMg
            potassiumDraft = m.potassiumMg
            magnesiumDraft = m.magnesiumMg
            ironDraft = m.ironMg
            vitaminDDraft = m.vitaminDMcg
            omega3Draft = m.omega3G
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
                applyAnalyzedEstimate(est)
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
            fiberG: fiberDraft,
            sugarG: sugarDraft,
            sodiumMg: sodiumDraft,
            potassiumMg: potassiumDraft,
            magnesiumMg: magnesiumDraft,
            ironMg: ironDraft,
            vitaminDMcg: vitaminDDraft,
            omega3G: omega3Draft,
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

struct BarcodeScannerSheet: View {
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

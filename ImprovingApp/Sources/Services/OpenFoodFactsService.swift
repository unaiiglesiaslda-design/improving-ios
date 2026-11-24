import Foundation
import SwiftUI
import AVFoundation

/// Free, zero-API-key product lookup via OpenFoodFacts API v2 for barcode scanning in Nutrition.
struct BarcodeProductResult: Equatable, Identifiable {
    var id: String { barcode }
    let barcode: String
    let productName: String
    let brand: String
    let imageUrl: String?
    let servingSizeLabel: String?
    let defaultGrams: Double
    let kcalPer100g: Double
    let proteinPer100g: Double
    let carbsPer100g: Double
    let fatPer100g: Double
    let sugarsPer100g: Double
    let saltPer100g: Double
    let fiberPer100g: Double
    let satFatPer100g: Double
    let calciumMgPer100g: Double
    let nutriscoreGrade: String?
    let novaGroup: Int?
    let ingredientsText: String?

    var displayTitle: String {
        let cleanBrand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = productName.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanBrand.isEmpty || cleanName.localizedCaseInsensitiveContains(cleanBrand) {
            return cleanName.isEmpty ? "Producto \(barcode)" : cleanName
        }
        return "\(cleanName) · \(cleanBrand)"
    }

    func toMealEstimate(grams: Double) -> AnalyzedMealEstimate {
        let factor = max(grams, 1.0) / 100.0
        let kcal = Int((kcalPer100g * factor).rounded())
        let p = Int((proteinPer100g * factor).rounded())
        let c = Int((carbsPer100g * factor).rounded())
        let f = Int((fatPer100g * factor).rounded())
        let sugar = sugarsPer100g * factor
        let salt = saltPer100g * factor
        let fiber = fiberPer100g * factor
        let calcium = calciumMgPer100g * factor

        var quality = 74
        switch nutriscoreGrade?.lowercased() {
        case "a": quality = 90
        case "b": quality = 79
        case "c": quality = 64
        case "d": quality = 46
        case "e": quality = 28
        default:
            if sugar > 14 { quality -= 18 }
            else if sugar > 8 { quality -= 8 }
            if salt > 1.5 { quality -= 10 }
            if fiber >= 4 { quality += 10 }
            if p >= 12 { quality += 6 }
            if satFatPer100g * factor > 6 { quality -= 8 }
        }
        if let nova = novaGroup {
            if nova == 4 { quality -= 12 }
            else if nova == 1 { quality += 6 }
        }
        quality = min(max(quality, 12), 98)

        var qFactors = GeminiCoachService.inferQualityFactors(title: displayTitle, qualityScore: quality)
        if sugar > 6.0 {
            let penalty = -min(14.0, ((sugar - 5.0) / 3.2))
            qFactors.excessSugar = min(qFactors.excessSugar, penalty)
        }
        if salt > 0.9 {
            let penalty = -min(14.0, ((salt - 0.8) * 3.5))
            qFactors.excessSodium = min(qFactors.excessSodium, penalty)
        }
        if fiber >= 3.0 && qFactors.wholeGrains == 0 {
            let low = "\(displayTitle) \(ingredientsText ?? "")".lowercased()
            if low.contains("integral") || low.contains("avena") || low.contains("cereal") || low.contains("trigo") {
                qFactors.wholeGrains = min(8.0, fiber * 0.8)
            }
        }

        let gramsLabel = "\(Int(grams.rounded())) g"
        var summaryParts = ["Escaneado vía OpenFoodFacts (\(gramsLabel))."]
        if let ns = nutriscoreGrade?.uppercased(), !ns.isEmpty {
            summaryParts.append("Nutri-Score \(ns).")
        }
        if sugar >= 1.0 {
            summaryParts.append(String(format: "Azúcares %.1fg.", locale: Locale(identifier: "es_ES"), sugar))
        }
        if fiber >= 1.0 {
            summaryParts.append(String(format: "Fibra %.1fg.", locale: Locale(identifier: "es_ES"), fiber))
        }

        return AnalyzedMealEstimate(
            title: String(displayTitle.prefix(64)),
            emoji: GeminiCoachService.inferEmoji(forTitle: displayTitle),
            kcal: max(kcal, p * 4 + c * 4 + f * 9 > 0 && kcal == 0 ? p * 4 + c * 4 + f * 9 : kcal),
            proteinG: p,
            carbsG: c,
            fatG: f,
            caffeineMg: 0,
            alcoholDrinks: 0,
            calciumMg: calcium,
            qualityScore: quality,
            qualityFactors: qFactors,
            aiSummary: summaryParts.joined(separator: " "),
            usedLiveAI: true,
            modelUsed: "OpenFoodFacts"
        )
    }
}

enum OpenFoodFactsService {
    static func sanitizeBarcode(_ raw: String) -> String {
        raw.filter { $0.isNumber }
    }

    static func lookupProduct(barcode rawBarcode: String) async -> (product: BarcodeProductResult?, errorMessage: String?) {
        let code = sanitizeBarcode(rawBarcode)
        guard code.count >= 8, code.count <= 14 else {
            return (nil, "Código de barras no válido (introduce entre 8 y 14 dígitos).")
        }
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json?fields=code,product_name,product_name_es,brands,image_front_small_url,serving_size,serving_quantity,nutriments,nutriscore_grade,nova_group,ingredients_text_es,ingredients_text") else {
            return (nil, "URL de consulta inválida.")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 14
        req.setValue("Improving-iOS/1.0 (health-app)", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                return (nil, "Sin respuesta del servidor.")
            }
            if http.statusCode == 404 {
                return (nil, "Producto \(code) no encontrado en OpenFoodFacts. Puedes fotografiarlo o describirlo con Gemini IA.")
            }
            guard (200...299).contains(http.statusCode) else {
                return (nil, "Error de consulta (HTTP \(http.statusCode)).")
            }
            guard let parsed = parseOpenFoodFactsResponse(data, fallbackBarcode: code) else {
                return (nil, "No encontramos datos nutricionales para el código \(code). Usa la cámara IA para analizar la etiqueta.")
            }
            return (parsed, nil)
        } catch {
            return (nil, "Error de red al consultar OpenFoodFacts: \(error.localizedDescription)")
        }
    }

    static func parseOpenFoodFactsResponse(_ data: Data, fallbackBarcode: String) -> BarcodeProductResult? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let status = root["status"] as? Int, status == 0 { return nil }
        guard let prod = root["product"] as? [String: Any] else { return nil }

        let code = (prod["code"] as? String) ?? fallbackBarcode
        let nameEs = (prod["product_name_es"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let nameDefault = (prod["product_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let productName = !nameEs.isEmpty ? nameEs : nameDefault
        guard !productName.isEmpty else { return nil }

        let brand = (prod["brands"] as? String)?
            .split(separator: ",")
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        let imageUrl = prod["image_front_small_url"] as? String
        let servingSizeLabel = (prod["serving_size"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let nutriments = prod["nutriments"] as? [String: Any] ?? [:]

        func num(_ keys: [String]) -> Double {
            for k in keys {
                if let n = nutriments[k] as? NSNumber { return max(0, n.doubleValue) }
                if let s = nutriments[k] as? String, let d = Double(s.replacingOccurrences(of: ",", with: ".")) {
                    return max(0, d)
                }
            }
            return 0
        }

        var kcal100 = num(["energy-kcal_100g", "energy-kcal"])
        if kcal100 <= 0 {
            let kj = num(["energy-kj_100g", "energy_100g", "energy"])
            if kj > 0 { kcal100 = kj / 4.184 }
        }
        let protein100 = num(["proteins_100g", "proteins"])
        let carbs100 = num(["carbohydrates_100g", "carbohydrates"])
        let fat100 = num(["fat_100g", "fat"])
        if kcal100 <= 0 && (protein100 + carbs100 + fat100) > 0 {
            kcal100 = protein100 * 4.0 + carbs100 * 4.0 + fat100 * 9.0
        }
        let sugars100 = num(["sugars_100g", "sugars"])
        var salt100 = num(["salt_100g", "salt"])
        if salt100 <= 0 {
            let sodiumG = num(["sodium_100g", "sodium"])
            if sodiumG > 0 { salt100 = sodiumG * 2.5 }
        }
        let fiber100 = num(["fiber_100g", "fiber"])
        let satFat100 = num(["saturated-fat_100g", "saturated-fat"])
        // OpenFoodFacts stores calcium in grams per 100g -> mg
        let calciumRaw = num(["calcium_100g", "calcium"])
        let calciumMg100 = calciumRaw > 5.0 ? calciumRaw : (calciumRaw * 1000.0)

        let defaultGrams: Double = {
            if let q = prod["serving_quantity"] as? NSNumber, q.doubleValue >= 5, q.doubleValue <= 1000 {
                return q.doubleValue
            }
            if let s = prod["serving_quantity"] as? String,
               let d = Double(s.replacingOccurrences(of: ",", with: ".")),
               d >= 5, d <= 1000 {
                return d
            }
            return 100.0
        }()

        let nutriscore = (prod["nutriscore_grade"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let novaGroup: Int? = {
            if let n = prod["nova_group"] as? Int { return n }
            if let n = prod["nova_group"] as? NSNumber { return n.intValue }
            if let s = prod["nova_group"] as? String { return Int(s) }
            return nil
        }()
        let ingredients = (prod["ingredients_text_es"] as? String) ?? (prod["ingredients_text"] as? String)

        return BarcodeProductResult(
            barcode: code,
            productName: productName,
            brand: brand,
            imageUrl: imageUrl,
            servingSizeLabel: servingSizeLabel,
            defaultGrams: defaultGrams,
            kcalPer100g: kcal100,
            proteinPer100g: protein100,
            carbsPer100g: carbs100,
            fatPer100g: fat100,
            sugarsPer100g: sugars100,
            saltPer100g: salt100,
            fiberPer100g: fiber100,
            satFatPer100g: satFat100,
            calciumMgPer100g: calciumMg100,
            nutriscoreGrade: nutriscore,
            novaGroup: novaGroup,
            ingredientsText: ingredients
        )
    }
}

// MARK: - Native AVFoundation Barcode Scanner Camera View

struct BarcodeScannerCameraView: UIViewControllerRepresentable {
    let isTorchOn: Bool
    let onCodeDetected: (String) -> Void
    let onCameraUnavailable: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCodeDetected: onCodeDetected)
    }

    func makeUIViewController(context: Context) -> BarcodeScannerController {
        let vc = BarcodeScannerController()
        vc.delegate = context.coordinator
        vc.onUnavailable = onCameraUnavailable
        return vc
    }

    func updateUIViewController(_ uiViewController: BarcodeScannerController, context: Context) {
        uiViewController.setTorch(enabled: isTorchOn)
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onCodeDetected: (String) -> Void
        private var lastCode: String?
        private var lastDetectedAt: Date = .distantPast

        init(onCodeDetected: @escaping (String) -> Void) {
            self.onCodeDetected = onCodeDetected
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard let readable = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let raw = readable.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else { return }
            let now = Date()
            if raw == lastCode && now.timeIntervalSince(lastDetectedAt) < 2.2 { return }
            lastCode = raw
            lastDetectedAt = now
            DispatchQueue.main.async {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                self.onCodeDetected(raw)
            }
        }
    }
}

final class BarcodeScannerController: UIViewController {
    weak var delegate: AVCaptureMetadataOutputObjectsDelegate?
    var onUnavailable: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let sessionQueue = DispatchQueue(label: "com.improving.barcode.camera")
    private var configured = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        checkAndConfigureCamera()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sessionQueue.async { [weak self] in
            guard let self, self.configured, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        setTorch(enabled: false)
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func setTorch(enabled: Bool) {
        sessionQueue.async {
            guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
            do {
                try device.lockForConfiguration()
                device.torchMode = enabled ? .on : .off
                device.unlockForConfiguration()
            } catch {}
        }
    }

    private func checkAndConfigureCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.configureSession()
                    } else {
                        self?.onUnavailable?("Activa el permiso de Cámara en Ajustes para escanear códigos de barras.")
                    }
                }
            }
        default:
            DispatchQueue.main.async { [weak self] in
                self?.onUnavailable?("Permiso de cámara denegado. Puedes escribir el código EAN manualmente abajo.")
            }
        }
    }

    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                DispatchQueue.main.async {
                    self.onUnavailable?("Cámara no disponible en este dispositivo. Escribe el código de barras manualmente abajo.")
                }
                return
            }

            self.session.beginConfiguration()
            if self.session.canAddInput(input) {
                self.session.addInput(input)
            }
            let output = AVCaptureMetadataOutput()
            if self.session.canAddOutput(output) {
                self.session.addOutput(output)
                output.setMetadataObjectsDelegate(self.delegate, queue: DispatchQueue.main)
                let wanted: [AVMetadataObject.ObjectType] = [.ean13, .ean8, .upce, .code128, .code39, .qr]
                output.metadataObjectTypes = wanted.filter { output.availableMetadataObjectTypes.contains($0) }
            }
            self.session.commitConfiguration()
            self.configured = true

            DispatchQueue.main.async {
                let layer = AVCaptureVideoPreviewLayer(session: self.session)
                layer.videoGravity = .resizeAspectFill
                layer.frame = self.view.bounds
                self.view.layer.insertSublayer(layer, at: 0)
                self.previewLayer = layer
            }

            self.session.startRunning()
        }
    }
}

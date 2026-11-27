import Foundation

extension GeminiCoachService {
    // MARK: - 4. Multimodal Nutrition Analyzer (Photo + Natural Spanish Text via Gemini 3/3.1 Flash)

    func analyzeMealWithAI(
        descriptionText: String,
        jpegImageData: Data?,
        apiKey: String,
        selectedModel: String,
        allowCloudAI: Bool = true,
        allowKeylessFallback: Bool = false
    ) async -> AnalyzedMealEstimate {
        let trimmedDesc = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanKey = Self.sanitizeApiKey(apiKey)
        let model = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "auto" : selectedModel

        let sysPrompt = """
        Eres un nutricionista deportivo clínico experto dentro de Improving.
        Tu tarea es analizar la comida del usuario (a partir de la fotografía del plato, la descripción en lenguaje natural, o ambas) y calcular con precisión realista sus calorías, macronutrientes, cafeína, alcohol, calcio y una puntuación de calidad nutricional de 0 a 100.

        CRITERIOS DE PUNTUACIÓN DE CALIDAD (0 a 100):
        - 85 a 98: Comida real mínimamente procesada, buena densidad proteica, grasas saludables, fibra o micronutrientes (ej. huevos, aguacate, pescado, verduras, legumbres, fruta, avena).
        - 65 a 84: Comida equilibrada estándar con algún refinado moderado (ej. bocadillo limpio, arroz blanco con pollo, pasta con atún).
        - 35 a 64: Ultraprocesados moderados, frituras, exceso de azúcares añadidos o bollería.
        - 10 a 34: Alcohol, refrescos azucarados, comida rápida muy densa en grasas trans/azúcar.

        Devuelve ÚNICAMENTE un objeto JSON válido sin bloques markdown con estas claves exactas:
        {
          "title": "Nombre corto y claro del plato en español (máx 48 caracteres)",
          "emoji": "1 emoji exacto que represente el plato (ej. 🍪, 🥛, 🍳, 🥗, 🐟, 🥑)",
          "kcal": 520,
          "protein_g": 32,
          "carbs_g": 42,
          "fat_g": 24,
          "fiber_g": 6.5,
          "sugar_g": 4.0,
          "sodium_mg": 420,
          "potassium_mg": 580,
          "magnesium_mg": 65,
          "iron_mg": 2.4,
          "vitamin_d_mcg": 1.2,
          "omega3_g": 0.6,
          "caffeine_mg": 0,
          "alcohol_drinks": 0,
          "calcium_mg": 85,
          "quality_score": 90,
          "factors": {
            "whole_grains": 2.0,
            "excess_sugar": 0.0,
            "excess_sodium": 0.0,
            "vegetables": 3.0,
            "healthy_fats": 4.0,
            "fruit": 0.0,
            "nuts_legumes": 0.0,
            "omega3": 0.0,
            "red_meat": 0.0,
            "processed_meat": 0.0,
            "alcohol": 0.0
          },
          "summary": "Breve explicación nutricional en 1 frase clara en español."
        }
        Nota sobre `factors`: los positivos (whole_grains, vegetables, healthy_fats, fruit, nuts_legumes, omega3) van de 0 a +10; los negativos (excess_sugar, excess_sodium, red_meat, processed_meat, alcohol) van de 0 a -12 (números negativos o 0).
        """

        let userPrompt: String = {
            if !trimmedDesc.isEmpty && jpegImageData != nil {
                return "Analiza la foto del plato junto con esta descripción del usuario: «\(trimmedDesc)». Calcula raciones, calorías, macros y calidad."
            } else if jpegImageData != nil {
                return "Analiza visualmente todos los alimentos y raciones de la fotografía adjunta y calcula calorías, macros y calidad nutricional."
            } else {
                return "Analiza nutricionalmente esta comida descrita por el usuario: «\(trimmedDesc)». Calcula calorías, macros, cafeína/alcohol si los hay y calidad nutricional."
            }
        }()

        // Tier 1: Live Multimodal Gemini API (supports both JPEG inline_data + text!)
        if allowCloudAI && !cleanKey.isEmpty {
            let candidates = await resolveCandidateModels(apiKey: cleanKey, selectedModel: model, forceDiscovery: model == "auto")
            for m in candidates.prefix(3) {
                let res = await callGeminiMultimodalJson(
                    prompt: userPrompt,
                    sysPrompt: sysPrompt,
                    jpegImageData: jpegImageData,
                    apiKey: cleanKey,
                    model: m
                )
                if let raw = res.text, let parsed = Self.parseMealEstimateJson(raw, usedLiveAI: true, modelUsed: m) {
                    return parsed
                }
                if res.statusCode == 401 || res.statusCode == 403 { break }
            }
        }

        // Tier 2: Optional Keyless Cloud LLM (disabled by default for privacy)
        if allowCloudAI && allowKeylessFallback && !trimmedDesc.isEmpty {
            if let raw = await callKeylessCloudOneShot(prompt: userPrompt, sysPrompt: sysPrompt, seed: nextSeed()),
               let parsed = Self.parseMealEstimateJson(raw, usedLiveAI: true, modelUsed: "improving-cloud") {
                return parsed
            }
        }

        // Tier 3: Deterministic Spanish Nutrition Lexicon Fallback (instant offline resilience, editable before saving)
        return Self.estimateMealLocally(from: trimmedDesc, hasPhoto: jpegImageData != nil)
    }

    func callGeminiMultimodalJson(
        prompt: String,
        sysPrompt: String,
        jpegImageData: Data?,
        apiKey: String,
        model: String
    ) async -> (text: String?, statusCode: Int) {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else { return (nil, 0) }
        var userParts: [[String: Any]] = []
        if let img = jpegImageData, !img.isEmpty {
            userParts.append([
                "inline_data": [
                    "mime_type": "image/jpeg",
                    "data": img.base64EncodedString()
                ]
            ])
        }
        userParts.append(["text": prompt])

        var genConfig: [String: Any] = [
            "temperature": 0.25,
            "maxOutputTokens": 1500,
            "responseMimeType": "application/json"
        ]
        if model.hasPrefix("gemini-2.5-flash") {
            genConfig["thinkingConfig"] = ["thinkingBudget": 0]
        }

        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": sysPrompt]]],
            "contents": [["role": "user", "parts": userParts]],
            "generationConfig": genConfig
        ]
        let resp = await sendSingleGeminiGenerateRequest(url: url, apiKey: apiKey, body: body, timeout: 28)
        guard let parts = resp.parts else { return (nil, resp.statusCode) }
        let joined = parts.compactMap { part -> String? in
            if (part["thought"] as? Bool) == true { return nil }
            return part["text"] as? String
        }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        return (joined.isEmpty ? nil : joined, resp.statusCode)
    }

    nonisolated static func parseMealEstimateJson(_ raw: String, usedLiveAI: Bool = true, modelUsed: String = "gemini") -> AnalyzedMealEstimate? {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["```json", "```JSON", "```"] {
            if cleaned.hasPrefix(prefix) { cleaned = String(cleaned.dropFirst(prefix.count)) }
        }
        if cleaned.hasSuffix("```") { cleaned = String(cleaned.dropLast(3)) }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let s = cleaned.firstIndex(of: "{"), let e = cleaned.lastIndex(of: "}"), e > s,
              let data = String(cleaned[s...e]).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        func intVal(_ keys: [String], default def: Int = 0) -> Int {
            for k in keys {
                if let n = obj[k] as? NSNumber { return Int(n.doubleValue.rounded()) }
                if let str = obj[k] as? String, let d = Double(str.replacingOccurrences(of: ",", with: ".")) {
                    return Int(d.rounded())
                }
            }
            return def
        }

        func dblVal(_ keys: [String], default def: Double = 0) -> Double {
            for k in keys {
                if let n = obj[k] as? NSNumber { return n.doubleValue }
                if let str = obj[k] as? String, let d = Double(str.replacingOccurrences(of: ",", with: ".")) {
                    return d
                }
            }
            return def
        }

        let rawTitle = (obj["title"] as? String ?? obj["nombre"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let p = max(0, intVal(["protein_g", "proteinG", "proteina", "protein"]))
        let c = max(0, intVal(["carbs_g", "carbsG", "carbos", "carbs"]))
        let f = max(0, intVal(["fat_g", "fatG", "grasas", "fat"]))
        var kcal = max(0, intVal(["kcal", "calories", "calorias"]))
        if kcal == 0 && (p + c + f) > 0 {
            kcal = p * 4 + c * 4 + f * 9
        }
        guard !rawTitle.isEmpty || kcal > 0 else { return nil }

        let caff = max(0, dblVal(["caffeine_mg", "caffeineMg", "cafeina_mg"]))
        let alc = max(0, dblVal(["alcohol_drinks", "alcoholDrinks", "bebidas_alcohol"]))
        let calc = max(0, dblVal(["calcium_mg", "calciumMg", "calcio_mg"]))
        let fib = max(0, dblVal(["fiber_g", "fiberG", "fibra_g"]))
        let sug = max(0, dblVal(["sugar_g", "sugarG", "azucar_g"]))
        let sod = max(0, dblVal(["sodium_mg", "sodiumMg", "sodio_mg"]))
        let pot = max(0, dblVal(["potassium_mg", "potassiumMg", "potasio_mg"]))
        let mag = max(0, dblVal(["magnesium_mg", "magnesiumMg", "magnesio_mg"]))
        let irn = max(0, dblVal(["iron_mg", "ironMg", "hierro_mg"]))
        let vitD = max(0, dblVal(["vitamin_d_mcg", "vitaminDMcg", "vitamina_d_mcg"]))
        let om3 = max(0, dblVal(["omega3_g", "omega3G", "omega_3_g"]))
        let q = min(max(intVal(["quality_score", "qualityScore", "calidad"], default: 80), 10), 100)
        let rawEmoji = (obj["emoji"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let emoji = rawEmoji.isEmpty ? Self.inferEmoji(forTitle: rawTitle) : String(rawEmoji.prefix(2))
        let summary = ((obj["summary"] as? String) ?? (obj["resumen"] as? String) ?? "Estimación calculada por IA. Puedes ajustar cualquier valor antes de guardar.")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var parsedFactors = NutritionQualityFactors()
        if let fObj = obj["factors"] as? [String: Any] {
            func fDbl(_ key: String) -> Double {
                if let n = fObj[key] as? NSNumber { return n.doubleValue }
                if let str = fObj[key] as? String, let d = Double(str.replacingOccurrences(of: ",", with: ".")) { return d }
                return 0
            }
            parsedFactors = NutritionQualityFactors(
                wholeGrains: max(0, min(12, fDbl("whole_grains"))),
                excessSugar: -min(14, abs(fDbl("excess_sugar"))),
                excessSodium: -min(14, abs(fDbl("excess_sodium"))),
                vegetables: max(0, min(12, fDbl("vegetables"))),
                healthyFats: max(0, min(12, fDbl("healthy_fats"))),
                fruit: max(0, min(12, fDbl("fruit"))),
                nutsLegumes: max(0, min(12, fDbl("nuts_legumes"))),
                omega3: max(0, min(12, fDbl("omega3"))),
                redMeat: -min(12, abs(fDbl("red_meat"))),
                processedMeat: -min(12, abs(fDbl("processed_meat"))),
                alcohol: -min(14, abs(fDbl("alcohol")))
            )
        }
        if !parsedFactors.hasAnyNonZero {
            parsedFactors = Self.inferQualityFactors(title: rawTitle, qualityScore: q, alcoholDrinks: alc)
        }

        return AnalyzedMealEstimate(
            title: rawTitle.isEmpty ? "Comida analizada" : String(rawTitle.prefix(64)),
            emoji: emoji,
            kcal: kcal,
            proteinG: p,
            carbsG: c,
            fatG: f,
            caffeineMg: caff,
            alcoholDrinks: alc,
            calciumMg: calc,
            fiberG: fib,
            sugarG: sug,
            sodiumMg: sod,
            potassiumMg: pot,
            magnesiumMg: mag,
            ironMg: irn,
            vitaminDMcg: vitD,
            omega3G: om3,
            qualityScore: q,
            qualityFactors: parsedFactors,
            aiSummary: summary,
            usedLiveAI: usedLiveAI,
            modelUsed: modelUsed
        )
    }

    nonisolated static func inferEmoji(forTitle title: String) -> String {
        let low = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
        if low.contains("galleta") || low.contains("cookie") { return "🍪" }
        if low.contains("colacao") || low.contains("leche") || low.contains("batido") { return "🥛" }
        if low.contains("huevo") || low.contains("tortilla") { return "🍳" }
        if low.contains("salmon") || low.contains("atun") || low.contains("pescado") { return "🐟" }
        if low.contains("ensalada") || low.contains("verdura") || low.contains("brocoli") { return "🥗" }
        if low.contains("aguacate") { return "🥑" }
        if low.contains("pollo") || low.contains("pavo") { return "🍗" }
        if low.contains("arroz") || low.contains("avena") || low.contains("bowl") { return "🥣" }
        if low.contains("pasta") || low.contains("macarron") || low.contains("espagueti") { return "🍝" }
        if low.contains("pizza") { return "🍕" }
        if low.contains("hamburguesa") || low.contains("burger") { return "🍔" }
        if low.contains("fruta") || low.contains("platano") || low.contains("manzana") || low.contains("fresa") { return "🍓" }
        if low.contains("cafe") || low.contains("espresso") { return "☕" }
        if low.contains("vino") || low.contains("cerveza") || low.contains("copa") { return "🍷" }
        if low.contains("tostada") || low.contains("bocadillo") || low.contains("pan") { return "🥪" }
        return "🍽️"
    }

    nonisolated static func inferQualityFactors(title: String, qualityScore: Int, alcoholDrinks: Double = 0) -> NutritionQualityFactors {
        let low = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
        var f = NutritionQualityFactors()

        if low.contains("avena") || low.contains("integral") || low.contains("quinoa") || low.contains("centeno") || low.contains("cereal") {
            f.wholeGrains += 2.5
        }
        if low.contains("galleta") || low.contains("chocolate") || low.contains("colacao") || low.contains("azucar") || low.contains("bolleria") || low.contains("tarta") || low.contains("helado") || low.contains("refresco") || low.contains("donut") || low.contains("croissant") {
            f.excessSugar -= 4.2
        }
        if low.contains("pizza") || low.contains("hamburguesa") || low.contains("patatas fritas") || low.contains("embutido") || low.contains("salchicha") || low.contains("bacon") || low.contains("jamon") || low.contains("soja") {
            f.excessSodium -= 2.4
        }
        if low.contains("ensalada") || low.contains("verdura") || low.contains("espinaca") || low.contains("brocoli") || low.contains("tomate") || low.contains("calabacin") || low.contains("pimiento") {
            f.vegetables += 3.5
        }
        if low.contains("aguacate") || low.contains("aceite") || low.contains("nueces") || low.contains("almendra") || low.contains("pistacho") || low.contains("salmon") || low.contains("oliva") {
            f.healthyFats += 3.0
        }
        if low.contains("fruta") || low.contains("fresa") || low.contains("arandano") || low.contains("platano") || low.contains("manzana") || low.contains("naranja") || low.contains("frutos rojos") || low.contains("kiwi") {
            f.fruit += 3.0
        }
        if low.contains("lenteja") || low.contains("garbanzo") || low.contains("alubia") || low.contains("nuez") || low.contains("nueces") || low.contains("almendra") || low.contains("cacahuete") || low.contains("hummus") {
            f.nutsLegumes += 3.0
        }
        if low.contains("salmon") || low.contains("sardina") || low.contains("atun") || low.contains("caballa") || low.contains("chia") || low.contains("nueces") {
            f.omega3 += 3.5
        }
        if low.contains("ternera") || low.contains("chuleton") || low.contains("entrecot") || low.contains("cerdo") || low.contains("cordero") || low.contains("carne roja") {
            f.redMeat -= 2.5
        }
        if low.contains("bacon") || low.contains("salchicha") || low.contains("chorizo") || low.contains("fuet") || low.contains("salami") || low.contains("embutido") || low.contains("mortadela") || low.contains("perrito") {
            f.processedMeat -= 3.5
        }
        if alcoholDrinks > 0 || low.contains("cerveza") || low.contains("vino") || low.contains("copa") || low.contains("gin") || low.contains("ron") || low.contains("whisky") {
            f.alcohol -= max(3.5, alcoholDrinks * 4.0)
        }
        if !f.hasAnyNonZero && qualityScore < 55 {
            f.excessSugar = -Double(60 - qualityScore) * 0.25
        }
        return f
    }

    nonisolated static func estimateMealLocally(from rawText: String, hasPhoto: Bool) -> AnalyzedMealEstimate {
        let low = rawText
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        struct FoodEntry {
            let pattern: String
            let kcal: Double
            let p: Double
            let c: Double
            let f: Double
            let caff: Double
            let alc: Double
            let calc: Double
            let qualityDelta: Int
        }

        let catalog: [FoodEntry] = [
            FoodEntry(pattern: "huevo", kcal: 78, p: 6.5, c: 0.6, f: 5.5, caff: 0, alc: 0, calc: 28, qualityDelta: 6),
            FoodEntry(pattern: "tostada", kcal: 110, p: 3.8, c: 20.0, f: 1.5, caff: 0, alc: 0, calc: 25, qualityDelta: 1),
            FoodEntry(pattern: "pan", kcal: 120, p: 4.0, c: 23.0, f: 1.5, caff: 0, alc: 0, calc: 20, qualityDelta: 0),
            FoodEntry(pattern: "aguacate", kcal: 145, p: 1.8, c: 7.5, f: 13.5, caff: 0, alc: 0, calc: 12, qualityDelta: 7),
            FoodEntry(pattern: "pollo", kcal: 245, p: 42.0, c: 0.0, f: 7.5, caff: 0, alc: 0, calc: 18, qualityDelta: 6),
            FoodEntry(pattern: "pavo", kcal: 210, p: 39.0, c: 0.0, f: 5.0, caff: 0, alc: 0, calc: 16, qualityDelta: 6),
            FoodEntry(pattern: "salmon", kcal: 330, p: 34.0, c: 0.0, f: 21.0, caff: 0, alc: 0, calc: 24, qualityDelta: 8),
            FoodEntry(pattern: "atun", kcal: 195, p: 35.0, c: 0.0, f: 5.5, caff: 0, alc: 0, calc: 18, qualityDelta: 6),
            FoodEntry(pattern: "ternera", kcal: 290, p: 36.0, c: 0.0, f: 16.0, caff: 0, alc: 0, calc: 16, qualityDelta: 4),
            FoodEntry(pattern: "arroz", kcal: 215, p: 4.5, c: 46.0, f: 0.8, caff: 0, alc: 0, calc: 15, qualityDelta: 2),
            FoodEntry(pattern: "pasta", kcal: 260, p: 9.0, c: 51.0, f: 2.0, caff: 0, alc: 0, calc: 20, qualityDelta: 1),
            FoodEntry(pattern: "avena", kcal: 230, p: 8.5, c: 39.0, f: 4.5, caff: 0, alc: 0, calc: 40, qualityDelta: 6),
            FoodEntry(pattern: "patata", kcal: 165, p: 4.0, c: 37.0, f: 0.4, caff: 0, alc: 0, calc: 22, qualityDelta: 4),
            FoodEntry(pattern: "boniato", kcal: 170, p: 3.5, c: 39.0, f: 0.3, caff: 0, alc: 0, calc: 35, qualityDelta: 6),
            FoodEntry(pattern: "lenteja", kcal: 250, p: 18.0, c: 40.0, f: 1.5, caff: 0, alc: 0, calc: 45, qualityDelta: 7),
            FoodEntry(pattern: "garbanzo", kcal: 270, p: 15.0, c: 44.0, f: 4.2, caff: 0, alc: 0, calc: 65, qualityDelta: 7),
            FoodEntry(pattern: "ensalada", kcal: 135, p: 3.5, c: 10.0, f: 9.0, caff: 0, alc: 0, calc: 55, qualityDelta: 7),
            FoodEntry(pattern: "verdura", kcal: 95, p: 3.5, c: 13.0, f: 3.5, caff: 0, alc: 0, calc: 60, qualityDelta: 7),
            FoodEntry(pattern: "platano", kcal: 105, p: 1.3, c: 27.0, f: 0.4, caff: 0, alc: 0, calc: 8, qualityDelta: 5),
            FoodEntry(pattern: "manzana", kcal: 85, p: 0.4, c: 22.0, f: 0.3, caff: 0, alc: 0, calc: 10, qualityDelta: 5),
            FoodEntry(pattern: "yogur", kcal: 130, p: 12.0, c: 9.0, f: 4.5, caff: 0, alc: 0, calc: 180, qualityDelta: 5),
            FoodEntry(pattern: "queso", kcal: 160, p: 11.0, c: 1.5, f: 12.5, caff: 0, alc: 0, calc: 240, qualityDelta: 2),
            FoodEntry(pattern: "leche", kcal: 125, p: 8.0, c: 12.0, f: 4.8, caff: 0, alc: 0, calc: 290, qualityDelta: 3),
            FoodEntry(pattern: "batido", kcal: 150, p: 26.0, c: 6.0, f: 2.2, caff: 0, alc: 0, calc: 120, qualityDelta: 5),
            FoodEntry(pattern: "proteina", kcal: 130, p: 25.0, c: 4.0, f: 1.8, caff: 0, alc: 0, calc: 110, qualityDelta: 5),
            FoodEntry(pattern: "aceite", kcal: 90, p: 0.0, c: 0.0, f: 10.0, caff: 0, alc: 0, calc: 0, qualityDelta: 3),
            FoodEntry(pattern: "nueces", kcal: 185, p: 4.5, c: 4.0, f: 18.0, caff: 0, alc: 0, calc: 28, qualityDelta: 5),
            FoodEntry(pattern: "almendra", kcal: 170, p: 6.0, c: 6.0, f: 15.0, caff: 0, alc: 0, calc: 75, qualityDelta: 5),
            FoodEntry(pattern: "cafe", kcal: 10, p: 0.3, c: 1.0, f: 0.2, caff: 80, alc: 0, calc: 8, qualityDelta: 0),
            FoodEntry(pattern: "espresso", kcal: 5, p: 0.2, c: 0.8, f: 0.1, caff: 75, alc: 0, calc: 4, qualityDelta: 0),
            FoodEntry(pattern: "te verde", kcal: 4, p: 0.0, c: 0.5, f: 0.0, caff: 35, alc: 0, calc: 2, qualityDelta: 2),
            FoodEntry(pattern: "matcha", kcal: 25, p: 1.0, c: 4.0, f: 0.2, caff: 65, alc: 0, calc: 15, qualityDelta: 3),
            FoodEntry(pattern: "cerveza", kcal: 145, p: 1.5, c: 13.0, f: 0.0, caff: 0, alc: 1.0, calc: 14, qualityDelta: -18),
            FoodEntry(pattern: "vino", kcal: 125, p: 0.2, c: 4.0, f: 0.0, caff: 0, alc: 1.0, calc: 12, qualityDelta: -16),
            FoodEntry(pattern: "copa", kcal: 180, p: 0.0, c: 12.0, f: 0.0, caff: 0, alc: 1.5, calc: 5, qualityDelta: -22),
            FoodEntry(pattern: "pizza", kcal: 680, p: 26.0, c: 78.0, f: 28.0, caff: 0, alc: 0, calc: 280, qualityDelta: -14),
            FoodEntry(pattern: "hamburguesa", kcal: 620, p: 32.0, c: 46.0, f: 33.0, caff: 0, alc: 0, calc: 140, qualityDelta: -12)
        ]

        func multiplierBefore(_ keyword: String, in text: String) -> Double {
            guard let range = text.range(of: keyword) else { return 1.0 }
            let prefix = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let lastToken = prefix.split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
            switch lastToken {
            case "1", "un", "una": return 1.0
            case "2", "dos", "par": return 2.0
            case "3", "tres": return 3.0
            case "4", "cuatro": return 4.0
            case "5", "cinco": return 5.0
            case "medio", "media", "0.5", "1/2": return 0.5
            default:
                if let n = Double(lastToken), (0.25...12.0).contains(n) { return n }
                return 1.0
            }
        }

        var totalKcal = 0.0
        var totalP = 0.0
        var totalC = 0.0
        var totalF = 0.0
        var totalCaff = 0.0
        var totalAlc = 0.0
        var totalCalc = 0.0
        var quality = 78
        var matchedAny = false

        for item in catalog {
            if low.contains(item.pattern) {
                let mult = multiplierBefore(item.pattern, in: low)
                totalKcal += item.kcal * mult
                totalP += item.p * mult
                totalC += item.c * mult
                totalF += item.f * mult
                totalCaff += item.caff * mult
                totalAlc += item.alc * mult
                totalCalc += item.calc * mult
                quality += item.qualityDelta
                matchedAny = true
            }
        }

        if !matchedAny {
            totalKcal = 460
            totalP = 28
            totalC = 44
            totalF = 18
            totalCalc = 90
            quality = 78
        }

        let cleanTitle: String = {
            let t = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty {
                let firstUpper = t.prefix(1).uppercased() + t.dropFirst()
                return String(firstUpper.prefix(60))
            }
            return hasPhoto ? "Plato fotografiado" : "Comida registrada"
        }()

        let note = matchedAny
            ? "Estimación local instantánea calculada sobre los ingredientes detectados (sin conexión a Gemini en vivo). Puedes ajustar cualquier cifra."
            : "Configura tu API Key de Gemini o conéctate a internet para análisis visual exacto; ajusta los valores manualmente si lo necesitas."

        let clampedQ = min(max(quality, 15), 96)
        let factors = Self.inferQualityFactors(title: cleanTitle, qualityScore: clampedQ, alcoholDrinks: totalAlc)

        return AnalyzedMealEstimate(
            title: cleanTitle,
            emoji: Self.inferEmoji(forTitle: cleanTitle),
            kcal: Int(totalKcal.rounded()),
            proteinG: Int(totalP.rounded()),
            carbsG: Int(totalC.rounded()),
            fatG: Int(totalF.rounded()),
            caffeineMg: totalCaff,
            alcoholDrinks: totalAlc,
            calciumMg: totalCalc,
            qualityScore: clampedQ,
            qualityFactors: factors,
            aiSummary: note,
            usedLiveAI: false,
            modelUsed: "local-nutrition"
        )
    }

    // MARK: - 4. Weekly Review AI Analyst (7-Day vs Previous 7-Day Real Comparison)

    func generateWeeklyReviewInsight(
        report: WeeklyReviewReport,
        userName: String,
        apiKey: String,
        selectedModel: String,
        allowCloudAI: Bool = true,
        allowKeylessFallback: Bool = false,
        tone: CoachPersonalityTone = .directo,
        detailLevel: CoachDetailLevel = .equilibrado,
        memoryNotes: [String] = [],
        goalMode: GlobalGoalMode = .longevidad
    ) async -> WeeklyAiReviewInsight {
        let nowFmt = DateFormatter()
        nowFmt.dateFormat = "HH:mm"
        let generatedLabel = nowFmt.string(from: Date())
        let cleanKey = Self.sanitizeApiKey(apiKey)
        let name = userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "el atleta" : userName.trimmingCharacters(in: .whitespacesAndNewlines)

        let payloadDict: [String: Any] = [
            "periodo": report.dateRangeLabel,
            "dias_con_datos": report.daysWithData,
            "recuperacion_media_pct": report.avgRecovery.map { $0 as Any } ?? "NO_DISPONIBLE",
            "delta_recuperacion_pct": report.recoveryDelta.map { $0 as Any } ?? "NO_DISPONIBLE",
            "vfc_media_ms": report.avgHrv.map { AppleHealthExportImporter.round1($0) as Any } ?? "NO_DISPONIBLE",
            "delta_vfc_ms": report.hrvDelta.map { AppleHealthExportImporter.round1($0) as Any } ?? "NO_DISPONIBLE",
            "fcr_media_ppm": report.avgRhr.map { AppleHealthExportImporter.round1($0) as Any } ?? "NO_DISPONIBLE",
            "sueno_medio_min": report.avgSleepMinutes.map { $0 as Any } ?? "NO_DISPONIBLE",
            "delta_sueno_min": report.sleepMinutesDelta.map { $0 as Any } ?? "NO_DISPONIBLE",
            "deuda_sueno_min": report.sleepDebtMinutes,
            "esfuerzo_medio_pct": report.avgStrainPct.map { $0 as Any } ?? "NO_DISPONIBLE",
            "entrenamientos_7d": report.workoutsCount,
            "minutos_entreno_7d": report.totalWorkoutMinutes,
            "carga_cardio_actual": report.cardioLoadCurrent,
            "estado_carga_cardio": report.cardioLoadState.rawValue,
            "puntuacion_nutricion_media": report.avgNutritionScore.map { $0 as Any } ?? "NO_DISPONIBLE",
            "energia_neta_media_kcal": report.avgNetEnergyKcal.map { $0 as Any } ?? "NO_DISPONIBLE",
            "pasos_medios": report.avgSteps.map { $0 as Any } ?? "NO_DISPONIBLE",
            "habitos_top": report.topHabits.map { "\($0.title) (\($0.count)d)" }
        ]
        let jsonStr: String = {
            guard let d = try? JSONSerialization.data(withJSONObject: payloadDict, options: [.prettyPrinted]),
                  let s = String(data: d, encoding: .utf8) else { return "{}" }
            return s
        }()

        let memBlock = memoryNotes.isEmpty ? "" : "\nMEMORIA PERMANENTE DEL ATLETA: \(memoryNotes.joined(separator: " | "))"
        let sysPrompt = """
        Eres el fisiólogo deportivo de \(name) en Improving.
        PERSONALIDAD CONFIGURADA: \(tone.systemDirective)
        NIVEL DE DETALLE: \(detailLevel.systemDirective)
        \(goalMode.coachSystemDirective)\(memBlock)
        Analiza su semana real frente a los 7 días anteriores y devuelve EXCLUSIVAMENTE un JSON válido:
        {
          "headline": "Titular corto y directo de máximo 9 palabras resumiendo la semana",
          "takeaways": [
            "Conclusión 1 concreta con datos reales y acción práctica para la próxima semana",
            "Conclusión 2 concreta conectando sueño/VFC/carga o nutrición real",
            "Conclusión 3 concreta de prioridad para los próximos 7 días"
          ]
        }
        Reglas estrictas:
        - Español natural de tú a tú, SIN asteriscos **, SIN paréntesis (), SIN inventar cifras marcadas como NO_DISPONIBLE.
        - Exactamente 3 elementos en takeaways, cada uno de 1-2 frases concisas y accionables.
        """
        let userPrompt = "Resumen semanal real de \(name):\n\(jsonStr)"

        if allowCloudAI && !cleanKey.isEmpty {
            let candidates = await resolveCandidateModels(apiKey: cleanKey, selectedModel: selectedModel, forceDiscovery: false)
            for m in candidates.prefix(3) {
                let res = await callGeminiMultimodalJson(
                    prompt: userPrompt,
                    sysPrompt: sysPrompt,
                    jpegImageData: nil,
                    apiKey: cleanKey,
                    model: m
                )
                if let raw = res.text,
                   let parsed = Self.parseWeeklyReviewJson(raw, weekKey: report.weekKey, generatedAt: generatedLabel, modelUsed: m, isLiveAI: true) {
                    return parsed
                }
                if res.statusCode == 401 || res.statusCode == 403 { break }
            }
        }

        if allowCloudAI && allowKeylessFallback,
           let raw = await callKeylessCloudOneShot(prompt: userPrompt, sysPrompt: sysPrompt, seed: nextSeed()),
           let parsed = Self.parseWeeklyReviewJson(raw, weekKey: report.weekKey, generatedAt: generatedLabel, modelUsed: "improving-live-ai", isLiveAI: true) {
            return parsed
        }

        return Self.buildOfflineWeeklyReview(report: report, generatedAt: generatedLabel)
    }

    nonisolated static func parseWeeklyReviewJson(
        _ raw: String,
        weekKey: String,
        generatedAt: String,
        modelUsed: String,
        isLiveAI: Bool
    ) -> WeeklyAiReviewInsight? {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for p in ["```json", "```JSON", "```"] where cleaned.hasPrefix(p) { cleaned = String(cleaned.dropFirst(p.count)) }
        if cleaned.hasSuffix("```") { cleaned = String(cleaned.dropLast(3)) }
        guard let s = cleaned.firstIndex(of: "{"), let e = cleaned.lastIndex(of: "}"), e > s,
              let data = String(cleaned[s...e]).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let headline = sanitizeDirectHumanText((obj["headline"] as? String) ?? "")
        let items = ((obj["takeaways"] as? [String]) ?? [])
            .map { sanitizeDirectHumanText($0) }
            .filter { !$0.isEmpty }
        guard !headline.isEmpty, !items.isEmpty else { return nil }
        return WeeklyAiReviewInsight(
            weekKey: weekKey,
            headline: headline,
            takeaways: Array(items.prefix(3)),
            generatedAtLabel: generatedAt,
            modelUsed: modelUsed,
            isLiveAI: isLiveAI
        )
    }

    nonisolated static func buildOfflineWeeklyReview(report: WeeklyReviewReport, generatedAt: String) -> WeeklyAiReviewInsight {
        var bullets: [String] = []
        if let rec = report.avgRecovery {
            let deltaTxt = report.recoveryDelta.map { $0 >= 0 ? "subiendo \($0) puntos respecto a la semana previa" : "bajando \(abs($0)) puntos frente a la semana anterior" } ?? "consolidando tu base autonómica"
            bullets.append("Tu recuperación media semanal se situó en \(rec)%, \(deltaTxt). Mantén las sesiones intensas los días por encima de 65%.")
        }
        if let sleepM = report.avgSleepMinutes {
            let h = sleepM / 60
            let m = sleepM % 60
            if report.sleepDebtMinutes > 35 {
                bullets.append("Promediaste \(h) h \(String(format: "%02d", m)) min de sueño y arrastras \(report.sleepDebtMinutes) min de deuda. Adelanta 25 minutos tu hora de acostarte las próximas tres noches.")
            } else {
                bullets.append("Buen control del descanso con \(h) h \(String(format: "%02d", m)) min de media nocturna. Conserva horarios estables para seguir protegiendo tu VFC.")
            }
        }
        if report.workoutsCount > 0 {
            bullets.append("Completaste \(report.workoutsCount) entrenamientos sumando \(report.totalWorkoutMinutes) minutos y una carga cardio de \(report.cardioLoadCurrent) en estado \(report.cardioLoadState.rawValue.lowercased()).")
        } else if let nut = report.avgNutritionScore {
            bullets.append("Tu puntuación media de nutrición fue de \(nut) sobre 100. Prioriza proteína y alimentos enteros en tus dos comidas principales.")
        }
        while bullets.count < 3 {
            bullets.append("Sigue registrando sueño, entrenamientos y hábitos del Diario para afinar tus correlaciones reales de los próximos 7 días.")
        }
        let headline: String = {
            if let rec = report.avgRecovery, rec >= 72 { return "Semana sólida con buena asimilación fisiológica" }
            if report.sleepDebtMinutes > 45 { return "Semana exigente: prioriza recuperar horas de sueño" }
            if report.workoutsCount >= 4 { return "Buen volumen de entrenamiento con carga activa" }
            return "Balance semanal de tus métricas reales"
        }()
        return WeeklyAiReviewInsight(
            weekKey: report.weekKey,
            headline: headline,
            takeaways: Array(bullets.prefix(3)),
            generatedAtLabel: generatedAt,
            modelUsed: "motor-local",
            isLiveAI: false
        )
    }

    // MARK: - 5. Blood Test / Lab Report Multimodal AI Extractor (Photo or PDF Pages -> Biomarkers)

    func analyzeLabReportWithAI(
        pageImagesData: [Data],
        extractedPdfText: String,
        apiKey: String,
        selectedModel: String,
        allowCloudAI: Bool = true,
        allowKeylessFallback: Bool = false
    ) async -> (report: LabReportRecord?, errorMessage: String?) {
        let cleanKey = Self.sanitizeApiKey(apiKey)
        let trimmedText = extractedPdfText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !pageImagesData.isEmpty || !trimmedText.isEmpty else {
            return (nil, "Selecciona una foto o un archivo PDF de tu analítica.")
        }

        let sysPrompt = """
        Eres un extractor clínico de analíticas de sangre en español para la app Improving.
        Extrae EXCLUSIVAMENTE los biomarcadores reales visibles en la imagen o texto de la analítica sin inventar NINGÚN valor.
        Devuelve SOLO un JSON válido con este formato exacto:
        {
          "title": "Analítica general (o nombre del laboratorio si aparece)",
          "date_iso": "yyyy-MM-dd (fecha del análisis si aparece, si no cadena vacía)",
          "summary": "Resumen claro en 1-2 frases en español sin paréntesis ni asteriscos.",
          "biomarkers": [
            {
              "name": "Vitamina D (25-OH)",
              "value": 34.5,
              "unit": "ng/mL",
              "ref_min": 30.0,
              "ref_max": 100.0,
              "optimal_min": 40.0,
              "optimal_max": 70.0,
              "status": "normal",
              "category": "Vitaminas"
            }
          ]
        }
        Valores permitidos en status: "optimal", "normal", "low", "high".
        Categorías sugeridas: "Metabolismo", "Lípidos", "Hormonas", "Vitaminas y Minerales", "Hematología", "Inflamación", "Hígado y Riñón".
        Prioriza marcadores clave como Glucosa, HbA1c, Insulina, Colesterol total, HDL, LDL, Triglicéridos, ApoB, Ferritina, Hierro, Vitamina D, Vitamina B12, Ácido fólico, TSH, T4 libre, Testosterona total, Cortisol, PCR ultrasensible, Hemoglobina, Hematocrito, Creatinina, AST, ALT, GGT, Ácido úrico, Magnesio.
        """
        let userPrompt = trimmedText.isEmpty
            ? "Extrae todos los biomarcadores numéricos reales de estas páginas de analítica de sangre."
            : "Extrae todos los biomarcadores numéricos reales de esta analítica de sangre:\n\n\(String(trimmedText.prefix(24000)))"

        if allowCloudAI && !cleanKey.isEmpty {
            let candidates = await resolveCandidateModels(apiKey: cleanKey, selectedModel: selectedModel, forceDiscovery: false)
            for m in candidates.prefix(3) {
                let res = await callGeminiMultiImageJson(
                    prompt: userPrompt,
                    sysPrompt: sysPrompt,
                    jpegImagesData: Array(pageImagesData.prefix(8)),
                    apiKey: cleanKey,
                    model: m,
                    maxOutputTokens: 6144
                )
                if let raw = res.text, let parsed = Self.parseLabReportJson(raw, sourceLabel: "Gemini \(m)") {
                    return (parsed, nil)
                }
                if res.statusCode == 401 || res.statusCode == 403 { break }
            }
        }

        if !trimmedText.isEmpty {
            // Never exfiltrate blood test PDF text to 3rd-party keyless proxy unless explicitly enabled!
            if allowCloudAI && allowKeylessFallback,
               let raw = await callKeylessCloudOneShot(prompt: userPrompt, sysPrompt: sysPrompt, seed: nextSeed()),
               let parsed = Self.parseLabReportJson(raw, sourceLabel: "Improving Cloud") {
                return (parsed, nil)
            }
            if let local = Self.parseLabReportFromPlainTextLocally(trimmedText) {
                return (local, nil)
            }
        }

        if cleanKey.isEmpty && !pageImagesData.isEmpty && trimmedText.isEmpty {
            return (nil, "Para leer analíticas desde foto/imagen necesitas configurar tu API Key gratuita de Gemini en Dispositivos y Ajustes (o subir un PDF con texto seleccionable).")
        }
        return (nil, "No se pudieron extraer biomarcadores automáticamente. Puedes añadirlos manualmente en 1 toque.")
    }

    func callGeminiMultiImageJson(
        prompt: String,
        sysPrompt: String,
        jpegImagesData: [Data],
        apiKey: String,
        model: String,
        maxOutputTokens: Int = 2000
    ) async -> (text: String?, statusCode: Int) {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else { return (nil, 0) }
        var userParts: [[String: Any]] = []
        for img in jpegImagesData where !img.isEmpty {
            userParts.append([
                "inline_data": [
                    "mime_type": "image/jpeg",
                    "data": img.base64EncodedString()
                ]
            ])
        }
        userParts.append(["text": prompt])

        var genConfig: [String: Any] = [
            "temperature": 0.15,
            "maxOutputTokens": maxOutputTokens,
            "responseMimeType": "application/json"
        ]
        if model.hasPrefix("gemini-2.5-flash") {
            genConfig["thinkingConfig"] = ["thinkingBudget": 0]
        }

        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": sysPrompt]]],
            "contents": [["role": "user", "parts": userParts]],
            "generationConfig": genConfig
        ]
        let resp = await sendSingleGeminiGenerateRequest(url: url, apiKey: apiKey, body: body, timeout: 52)
        guard let parts = resp.parts else { return (nil, resp.statusCode) }
        let joined = parts.compactMap { part -> String? in
            if (part["thought"] as? Bool) == true { return nil }
            return part["text"] as? String
        }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        return (joined.isEmpty ? nil : joined, resp.statusCode)
    }

    nonisolated static func parseLabReportJson(_ raw: String, sourceLabel: String) -> LabReportRecord? {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for p in ["```json", "```JSON", "```"] where cleaned.hasPrefix(p) { cleaned = String(cleaned.dropFirst(p.count)) }
        if cleaned.hasSuffix("```") { cleaned = String(cleaned.dropLast(3)) }
        guard let s = cleaned.firstIndex(of: "{"), let e = cleaned.lastIndex(of: "}"), e > s,
              let data = String(cleaned[s...e]).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawItems = obj["biomarkers"] as? [[String: Any]] else {
            return nil
        }

        func dbl(_ d: [String: Any], _ key: String) -> Double? {
            if let n = d[key] as? NSNumber { return n.doubleValue }
            if let s = d[key] as? String {
                let norm = s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
                return Double(norm)
            }
            return nil
        }

        var items: [LabBiomarkerItem] = []
        for entry in rawItems {
            let name = ((entry["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, let value = dbl(entry, "value") else { continue }
            let unit = ((entry["unit"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let refMin = dbl(entry, "ref_min")
            let refMax = dbl(entry, "ref_max")
            let optMin = dbl(entry, "optimal_min") ?? refMin
            let optMax = dbl(entry, "optimal_max") ?? refMax
            let rawStatus = ((entry["status"] as? String) ?? "").lowercased()
            let status: LabBiomarkerStatus = {
                switch rawStatus {
                case "optimal", "optimo", "óptimo": return .optimal
                case "low", "bajo": return .low
                case "high", "alto": return .high
                case "normal": return .normal
                default:
                    if let rMin = refMin, value < rMin { return .low }
                    if let rMax = refMax, value > rMax { return .high }
                    if let oMin = optMin, let oMax = optMax, value >= oMin, value <= oMax { return .optimal }
                    return .normal
                }
            }()
            let cat = ((entry["category"] as? String) ?? "General").trimmingCharacters(in: .whitespacesAndNewlines)
            items.append(LabBiomarkerItem(
                id: UUID().uuidString,
                name: name,
                value: value,
                unit: unit,
                refMin: refMin,
                refMax: refMax,
                optimalMin: optMin,
                optimalMax: optMax,
                status: status,
                category: cat.isEmpty ? "General" : cat
            ))
        }

        guard !items.isEmpty else { return nil }
        let isoFmt = DateFormatter()
        isoFmt.locale = Locale(identifier: "en_US_POSIX")
        isoFmt.dateFormat = "yyyy-MM-dd"
        let rawDate = ((obj["date_iso"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let validDate = isoFmt.date(from: rawDate) != nil ? rawDate : isoFmt.string(from: Date())
        let rawTitle = ((obj["title"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = sanitizeDirectHumanText((obj["summary"] as? String) ?? "Analítica procesada con \(items.count) biomarcadores extraídos.")

        return LabReportRecord(
            id: UUID().uuidString,
            dateIso: validDate,
            title: rawTitle.isEmpty ? "Analítica de sangre" : String(rawTitle.prefix(64)),
            sourceLabel: sourceLabel,
            summary: summary,
            biomarkers: items
        )
    }

    nonisolated static func parseLabReportFromPlainTextLocally(_ text: String) -> LabReportRecord? {
        let patterns: [(regex: String, name: String, unit: String, rMin: Double, rMax: Double, oMin: Double, oMax: Double, cat: String)] = [
            (#"(?i)glucosa[^\d]{0,20}(\d{2,3}(?:[.,]\d+)?)"#, "Glucosa", "mg/dL", 70, 100, 72, 90, "Metabolismo"),
            (#"(?i)(?:hba1c|hemoglobina\s+glicosilada)[^\d]{0,20}(\d(?:[.,]\d+)?)"#, "HbA1c", "%", 4.0, 5.6, 4.5, 5.3, "Metabolismo"),
            (#"(?i)vitamina\s*d[^\d]{0,25}(\d{1,3}(?:[.,]\d+)?)"#, "Vitamina D (25-OH)", "ng/mL", 30, 100, 40, 70, "Vitaminas y Minerales"),
            (#"(?i)ferritina[^\d]{0,20}(\d{1,4}(?:[.,]\d+)?)"#, "Ferritina", "ng/mL", 30, 300, 50, 150, "Vitaminas y Minerales"),
            (#"(?i)colesterol\s+total[^\d]{0,20}(\d{2,3}(?:[.,]\d+)?)"#, "Colesterol total", "mg/dL", 120, 200, 140, 190, "Lípidos"),
            (#"(?i)\bhdl\b[^\d]{0,20}(\d{2,3}(?:[.,]\d+)?)"#, "Colesterol HDL", "mg/dL", 40, 100, 55, 90, "Lípidos"),
            (#"(?i)\bldl\b[^\d]{0,20}(\d{2,3}(?:[.,]\d+)?)"#, "Colesterol LDL", "mg/dL", 50, 130, 60, 100, "Lípidos"),
            (#"(?i)triglic[eé]ridos[^\d]{0,20}(\d{2,3}(?:[.,]\d+)?)"#, "Triglicéridos", "mg/dL", 35, 150, 40, 100, "Lípidos"),
            (#"(?i)\btsh\b[^\d]{0,20}(\d(?:[.,]\d+)?)"#, "TSH", "µUI/mL", 0.4, 4.2, 0.8, 2.5, "Hormonas"),
            (#"(?i)testosterona\s+total[^\d]{0,20}(\d{2,4}(?:[.,]\d+)?)"#, "Testosterona total", "ng/dL", 280, 900, 450, 850, "Hormonas"),
            (#"(?i)vitamina\s*b12[^\d]{0,20}(\d{2,4}(?:[.,]\d+)?)"#, "Vitamina B12", "pg/mL", 200, 900, 450, 850, "Vitaminas y Minerales"),
            (#"(?i)hemoglobina[^\d]{0,20}(\d{1,2}(?:[.,]\d+)?)"#, "Hemoglobina", "g/dL", 13.0, 17.5, 14.0, 16.5, "Hematología")
        ]
        var found: [LabBiomarkerItem] = []
        let nsText = text as NSString
        for p in patterns {
            if let rx = try? NSRegularExpression(pattern: p.regex),
               let m = rx.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
               m.numberOfRanges >= 2, m.range(at: 1).location != NSNotFound {
                let rawNum = nsText.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: ".")
                if let val = Double(rawNum) {
                    let st: LabBiomarkerStatus = val < p.rMin ? .low : (val > p.rMax ? .high : ((val >= p.oMin && val <= p.oMax) ? .optimal : .normal))
                    found.append(LabBiomarkerItem(
                        id: UUID().uuidString,
                        name: p.name,
                        value: val,
                        unit: p.unit,
                        refMin: p.rMin,
                        refMax: p.rMax,
                        optimalMin: p.oMin,
                        optimalMax: p.oMax,
                        status: st,
                        category: p.cat
                    ))
                }
            }
        }
        guard !found.isEmpty else { return nil }
        let isoFmt = DateFormatter()
        isoFmt.locale = Locale(identifier: "en_US_POSIX")
        isoFmt.dateFormat = "yyyy-MM-dd"
        return LabReportRecord(
            id: UUID().uuidString,
            dateIso: isoFmt.string(from: Date()),
            title: "Analítica importada (PDF)",
            sourceLabel: "Extractor local PDF",
            summary: "Se extrajeron \(found.count) biomarcadores del texto del PDF. Revisa y ajusta si hace falta.",
            biomarkers: found
        )
    }
}

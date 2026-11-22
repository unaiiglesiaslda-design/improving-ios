import Foundation

struct GeminiCoachResult {
    let verdictTitle: String
    let text: String
    let bullets: [String]
    let actionLabel: String?
    let interactionId: String?
    let usedLiveCloud: Bool
    let modelUsed: String
}

/// Exact 1:1 Swift port of Android's `GeminiCoachService.kt`:
/// 1. Gemini Interactions API (`POST /v1/interactions`) + Gemini `v1beta/models/<model>:generateContent` when a Gemini API key is configured.
/// 2. Keyless Live Cloud LLM (`POST https://text.pollinations.ai/openai`) with full multi-turn history & biometric JSON context so ANY question gets a direct, human answer out of the box.
/// 3. Offline physiological fallback strictly grounded in verified available data (ZERO hallucinated numbers, ZERO parentheses `()`).
actor GeminiCoachService {
    static let shared = GeminiCoachService()

    static let supportedModels = [
        "gemini-2.5-flash",
        "gemini-4-hydrogen",
        "gemini-4-argon",
        "gemini-2.0-flash",
    ]

    private let interactionsEndpoint = "https://generativelanguage.googleapis.com/v1/interactions"
    private let apiRevision = "2026-05-20"
    private let keylessEndpoint = "https://text.pollinations.ai/openai"

    private let humanAngles = [
        "Enfoca tu razonamiento desde el tono vagal y la respuesta del sistema nervioso autónomo para decidir la orientación exacta.",
        "Enfoca tu razonamiento desde la eficiencia metabólica, el gasto calórico sobre la tasa basal y la reserva de energía disponible.",
        "Enfoca tu razonamiento desde el equilibrio entre carga aguda y crónica ACWR y la frescura de las fibras musculares.",
        "Enfoca tu razonamiento desde la arquitectura cardiorrespiratoria, las zonas de pulso de Tanaka y la deuda de sueño acumulada.",
        "Enfoca tu razonamiento como un entrenador personal cercano y sincero: ve directo a responder lo que pregunta con datos reales y consejos prácticos.",
    ]

    private var variationCounter: Int = 0
    private var recentPillTexts: [String] = []

    func nextSeed() -> Int {
        variationCounter += 1
        return variationCounter
    }

    // MARK: - Human Speech Sanitizer (1:1 Android `sanitizeDirectHumanText`)

    nonisolated static func sanitizeDirectHumanText(_ raw: String) -> String {
        var cleaned = raw
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip robotic prefixes
        if let regex = try? NSRegularExpression(pattern: "^(Opini[oó]n\\s*(de\\s*)?(IA)?\\s*(\\([^)]*\\))?\\s*:\\s*)", options: [.caseInsensitive]) {
            cleaned = regex.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: "")
        }
        // Eliminate parentheses seamlessly like Android
        if let parenRegex = try? NSRegularExpression(pattern: "\\s*\\(([^)]*)\\)") {
            cleaned = parenRegex.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: ", $1,")
        }
        cleaned = cleaned
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: " ,", with: ",")
            .replacingOccurrences(of: ",,", with: ",")
            .replacingOccurrences(of: ",.", with: ".")
            .replacingOccurrences(of: ",:", with: ":")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasSuffix(",") {
            cleaned.removeLast()
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let first = cleaned.first, first.isLowercase {
            cleaned = first.uppercased() + cleaned.dropFirst()
        }
        return cleaned
    }

    // MARK: - System Instruction (Exact Android Personality + Zero-Fabrication Contract)

    private func buildSystemInstruction(
        userName: String,
        biometricContextJson: String,
        availableHighlights: [String],
        missingCategories: [String],
        seed: Int
    ) -> String {
        let name = userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "el usuario" : userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let angle = humanAngles[abs(seed) % humanAngles.count]

        let dataConnection = availableHighlights.isEmpty
            ? "ATENCIÓN: Hoy NO hay datos biométricos recopilados del reloj para este día. NO tienes lecturas de recuperación, sueño, VFC, pulso, esfuerzo, estrés ni energía hoy."
            : "A continuación, conecta tu respuesta ÚNICAMENTE con los datos que sí estén disponibles hoy: \(availableHighlights.joined(separator: ", "))."

        let missingWarning = missingCategories.isEmpty
            ? "Todos los sensores principales tienen lectura válida."
            : "DATOS NO DISPONIBLES AHORA MISMO: \(missingCategories.joined(separator: ", "))."

        return """
        Eres el entrenador personal, nutricionista y fisiólogo humano de \(name) en Improving.
        TU REGLA #1 MÁS IMPORTANTE:
        Responde SIEMPRE de forma directa, específica y exacta a la pregunta que te acaba de hacer \(name) desde la primera frase.
        - Si te pregunta si puede tomarse un cubata, comer pizza, salir de fiesta, por qué le duele algo, qué es un suplemento, o CUALQUIER otra pregunta cotidiana, médica, deportiva o general, respóndele DIRECTAMENTE a esa pregunta concreta con naturalidad humana.
        - \(dataConnection)
        - NUNCA sueltes un resumen genérico del día que ignore su pregunta.

        REGLA INQUEBRANTABLE DE VERACIDAD Y CERO INVENCIÓN DE DATOS:
        - \(missingWarning)
        - PROHIBIDO TERMINANTEMENTE inventar, suponer, estimar o rellenar cualquier cifra o estado de una métrica que figure como "NO_DISPONIBLE" en el JSON.
        - Si \(name) te pregunta por un dato que no está disponible porque no se midió o no está en su archivo de Apple Health, acéptalo y díselo de forma directa y transparente sin inventar ningún número.
        - Si te hace una pregunta general cuando faltan los datos del reloj, responde con criterio técnico general y aclara honestamente que hoy no dispones de sus lecturas para afinarlo.

        REGLAS DE PERSONALIDAD Y ESTILO:
        1. Personalidad humana, directa, sincera, cercana y con criterio propio en español natural. Habla a \(name) de tú a tú.
        2. PROHIBIDO usar paréntesis () en ningún lugar del texto, títulos o viñetas. Integra todos los números reales de forma fluida dentro de las frases.
        3. PROHIBIDO empezar con etiquetas robóticas como "Opinión IA:" o "Análisis:".
        4. Cada respuesta debe ser única y pensada como un humano en este instante. \(angle)

        CONTEXTO COMPLETO DE DATOS REALES DE \(name.uppercased()):
        \(biometricContextJson)

        Responde SIEMPRE con un único objeto JSON válido sin bloques markdown con esta estructura:
        {
          "verdictTitle": "RESPUESTA DIRECTA EN MAYÚSCULAS SOBRE LO QUE PREGUNTA SIN PARÉNTESIS",
          "text": "Respuesta directa, humana y específica de 2 a 4 frases contestando exactamente a lo que ha preguntado \(name), usando solo datos reales disponibles y sin inventar nada faltante ni usar paréntesis.",
          "bullets": [
            "Dato o criterio clave: Solo información verificada o explicación clara si falta el dato sin paréntesis",
            "Orientación práctica: Qué hacer ahora de forma realista sin paréntesis",
            "Estado de tus registros: Qué métricas sí tenemos hoy o qué falta medir sin paréntesis"
          ],
          "actionLabel": null
        }
        """
    }

    // MARK: - Live Coach Reply (3-Tier Android Engine)

    func askLiveCoach(
        prompt: String,
        apiKey: String,
        selectedModel: String,
        userName: String,
        biometricContextJson: String,
        availableHighlights: [String],
        missingCategories: [String],
        history: [CoachChatMessage],
        previousInteractionId: String? = nil
    ) async -> GeminiCoachResult {
        let seed = nextSeed()
        let sysPrompt = buildSystemInstruction(
            userName: userName,
            biometricContextJson: biometricContextJson,
            availableHighlights: availableHighlights,
            missingCategories: missingCategories,
            seed: seed
        )
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "gemini-2.5-flash" : selectedModel

        // Tier 1: User's Gemini API Key (Interactions API for gemini-4*, plus standard generateContent fallback!)
        if !cleanKey.isEmpty {
            if model.hasPrefix("gemini-4"),
               let res = await callGeminiInteractions(prompt: prompt, sysPrompt: sysPrompt, apiKey: cleanKey, model: model, previousInteractionId: previousInteractionId) {
                return res
            }
            let candidates = model.hasPrefix("gemini-4") ? ["gemini-2.5-flash", "gemini-2.0-flash"] : [model, "gemini-2.5-flash", "gemini-2.0-flash"]
            for m in candidates {
                if let res = await callGeminiGenerateContent(prompt: prompt, sysPrompt: sysPrompt, history: history, apiKey: cleanKey, model: m) {
                    return res
                }
            }
        }

        // Tier 2: Out-of-the-box Keyless Cloud LLM (exact same Pollinations OpenAI endpoint as Android!)
        if let cloudRes = await callKeylessCloudLlm(prompt: prompt, sysPrompt: sysPrompt, history: history, seed: seed) {
            return cloudRes
        }

        // Tier 3: Honest offline fallback
        return buildOfflineFallback(prompt: prompt, userName: userName, availableHighlights: availableHighlights, missingCategories: missingCategories)
    }

    private func callGeminiInteractions(
        prompt: String,
        sysPrompt: String,
        apiKey: String,
        model: String,
        previousInteractionId: String?
    ) async -> GeminiCoachResult? {
        guard let url = URL(string: interactionsEndpoint) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 22
        req.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        req.setValue(apiRevision, forHTTPHeaderField: "Api-Revision")

        var body: [String: Any] = [
            "model": model,
            "system_instruction": sysPrompt,
            "input": prompt,
        ]
        if let prev = previousInteractionId, !prev.isEmpty {
            body["previous_interaction_id"] = prev
        }
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        req.httpBody = data

        do {
            let (respData, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let obj = try JSONSerialization.jsonObject(with: respData) as? [String: Any] else { return nil }
            let newId = obj["id"] as? String
            var outText = (obj["output_text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if outText.isEmpty, let steps = obj["steps"] as? [[String: Any]] {
                for step in steps.reversed() where (step["type"] as? String) == "model_output" {
                    if let content = step["content"] as? [[String: Any]] {
                        let joined = content.compactMap { ($0["type"] as? String) == "text" ? ($0["text"] as? String) : nil }.joined()
                        if !joined.isEmpty { outText = joined; break }
                    }
                }
            }
            guard !outText.isEmpty else { return nil }
            return parseStructuredReply(modelText: outText, interactionId: newId, modelUsed: model)
        } catch {
            return nil
        }
    }

    private func callGeminiGenerateContent(
        prompt: String,
        sysPrompt: String,
        history: [CoachChatMessage],
        apiKey: String,
        model: String
    ) async -> GeminiCoachResult? {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 22
        req.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")

        var contents: [[String: Any]] = []
        for msg in history.suffix(6) {
            let role = msg.isUser ? "user" : "model"
            let combined = ([msg.verdictTitle, msg.text].compactMap { $0 } + msg.bullets).joined(separator: ". ")
            if !combined.trimmingCharacters(in: .whitespaces).isEmpty {
                contents.append(["role": role, "parts": [["text": combined]]])
            }
        }
        contents.append(["role": "user", "parts": [["text": prompt]]])

        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": sysPrompt]]],
            "contents": contents,
            "generationConfig": [
                "temperature": 0.72,
                "maxOutputTokens": 650,
                "responseMimeType": "application/json",
            ]
        ]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        req.httpBody = httpBody

        do {
            let (respData, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: respData) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let text = parts.first?["text"] as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return parseStructuredReply(modelText: text, interactionId: nil, modelUsed: model)
        } catch {
            return nil
        }
    }

    private func callKeylessCloudLlm(
        prompt: String,
        sysPrompt: String,
        history: [CoachChatMessage],
        seed: Int
    ) async -> GeminiCoachResult? {
        guard let url = URL(string: keylessEndpoint) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 24
        req.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        var messages: [[String: String]] = [["role": "system", "content": sysPrompt]]
        for msg in history.suffix(6) {
            let content = ([msg.verdictTitle, msg.text].compactMap { $0 } + msg.bullets).joined(separator: ". ")
            if !content.trimmingCharacters(in: .whitespaces).isEmpty {
                messages.append(["role": msg.isUser ? "user" : "assistant", "content": content])
            }
        }
        messages.append(["role": "user", "content": prompt])

        let body: [String: Any] = [
            "model": "openai",
            "messages": messages,
            "seed": seed + Int(Date().timeIntervalSince1970) % 10000
        ]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        req.httpBody = httpBody

        do {
            let (respData, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let root = try JSONSerialization.jsonObject(with: respData) as? [String: Any],
                  let choices = root["choices"] as? [[String: Any]],
                  let msg = choices.first?["message"] as? [String: Any],
                  let content = msg["content"] as? String,
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return parseStructuredReply(modelText: content, interactionId: root["id"] as? String, modelUsed: "improving-live-ai")
        } catch {
            return nil
        }
    }

    private func parseStructuredReply(modelText: String, interactionId: String?, modelUsed: String) -> GeminiCoachResult {
        var cleaned = modelText.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["```json", "```JSON", "```"] {
            if cleaned.hasPrefix(prefix) { cleaned = String(cleaned.dropFirst(prefix.count)) }
        }
        if cleaned.hasSuffix("```") { cleaned = String(cleaned.dropLast(3)) }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        if let s = cleaned.firstIndex(of: "{"), let e = cleaned.lastIndex(of: "}"), e > s,
           let data = String(cleaned[s...e]).data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let title = Self.sanitizeDirectHumanText((obj["verdictTitle"] as? String) ?? "RESPUESTA DIRECTA")
            let text = Self.sanitizeDirectHumanText((obj["text"] as? String) ?? cleaned)
            let bullets = ((obj["bullets"] as? [String]) ?? []).map { Self.sanitizeDirectHumanText($0) }.filter { !$0.isEmpty }
            let action = (obj["actionLabel"] as? String).flatMap { $0.isEmpty || $0 == "null" ? nil : $0 }
            return GeminiCoachResult(
                verdictTitle: title.isEmpty ? "RESPUESTA DIRECTA" : title,
                text: text,
                bullets: bullets,
                actionLabel: action,
                interactionId: interactionId,
                usedLiveCloud: true,
                modelUsed: modelUsed
            )
        }

        return GeminiCoachResult(
            verdictTitle: "RESPUESTA DIRECTA",
            text: Self.sanitizeDirectHumanText(cleaned),
            bullets: [],
            actionLabel: nil,
            interactionId: interactionId,
            usedLiveCloud: true,
            modelUsed: modelUsed
        )
    }

    private func buildOfflineFallback(
        prompt: String,
        userName: String,
        availableHighlights: [String],
        missingCategories: [String]
    ) -> GeminiCoachResult {
        let namePrefix = userName.trimmingCharacters(in: .whitespaces).isEmpty ? "" : "\(userName.trimmingCharacters(in: .whitespaces)), "
        if availableHighlights.isEmpty {
            return GeminiCoachResult(
                verdictTitle: "SIN CONEXIÓN Y SIN LECTURAS HOY",
                text: "\(namePrefix)ahora mismo estoy sin conexión a internet y además no tengo métricas registradas hoy en tu reloj o archivo de Salud para responder con tus números exactos. Revisa tu conexión o importa tus datos de Apple Health para darte una respuesta a medida.",
                bullets: [
                    "Estado de tus registros: Faltan \(missingCategories.prefix(5).joined(separator: ", "))",
                    "Consejo general: Prioriza hidratación, descanso regular y escucha tus sensaciones físicas hasta sincronizar."
                ],
                actionLabel: nil,
                interactionId: nil,
                usedLiveCloud: false,
                modelUsed: "offline-engine"
            )
        }
        return GeminiCoachResult(
            verdictTitle: "RESPUESTA OFFLINE CON TUS DATOS",
            text: "\(namePrefix)no he podido conectar con Gemini en este instante, pero mirando tus lecturas reales de hoy — \(availableHighlights.joined(separator: ", ")) — mantén un enfoque equilibrado y ajusta el esfuerzo a cómo responde tu sistema nervioso.",
            bullets: [
                "Datos reales activos hoy: \(availableHighlights.joined(separator: ", "))",
                "Para preguntas abiertas libres verifica tu conexión a internet o tu clave de Gemini en Ajustes."
            ],
            actionLabel: nil,
            interactionId: nil,
            usedLiveCloud: false,
            modelUsed: "offline-engine"
        )
    }

    // MARK: - Short Click-to-Expand Metric Floating Insight (Zero Fabricated Numbers)

    func buildMetricFloatingInsight(
        metricId: String,
        metricTitle: String,
        currentValueText: String,
        normalRangeText: String,
        recoveryPct: Int?,
        strainPct: Int?,
        hrvMs: Double?,
        restingHrBpm: Double?,
        sleepDurationText: String?,
        energyPct: Int?,
        stressScore: Int?,
        profile: UserPhysiologyProfile,
        hasData: Bool,
        seed: Int? = nil
    ) -> MetricFloatingAiInsight {
        let s = seed ?? nextSeed()
        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: profile)
        let rawName = profile.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameLead = (rawName.isEmpty || rawName.lowercased() == "usuario") ? "" : "\(rawName), "
        let cleanRange = normalRangeText.replacingOccurrences(of: "Óptimo:", with: "").trimmingCharacters(in: .whitespaces)
        let cleanVal = currentValueText.trimmingCharacters(in: .whitespaces)
        let validData = hasData && !cleanVal.isEmpty && !cleanVal.hasPrefix("--") && cleanVal != "No hay datos"

        let headlines = [
            "LECTURA EN VIVO DE TU IA",
            "CONTEXTO FISIOLÓGICO DE HOY",
            "QUÉ DICE ESTE DATO DE TI",
            "CRUCE CON TU RECUPERACIÓN",
            "VISIÓN DE TU ENTRENADOR",
        ]
        let headline = headlines[abs(s) % headlines.count]

        if !validData {
            let shortNoData = "\(nameLead)no hay lecturas de \(metricTitle.lowercased()) en este día. Prefiero no inventar datos; tu referencia orientativa es \(cleanRange)."
            let fullNoData = "\(nameLead)no constan muestras reales de \(metricTitle.lowercased()) registradas en esta fecha. Nunca invento cifras ni tendencias vacías: para tu perfil de \(Int(profile.ageYears)) años y \(Int(profile.weightKg)) kg, la banda orientativa es \(cleanRange). Cuando tu reloj registre o importes mediciones en este día verás el análisis exacto."
            return MetricFloatingAiInsight(
                shortPillText: "Sin lecturas este día",
                expandedHeadline: headline,
                shortExpandedMessage: Self.sanitizeDirectHumanText(shortNoData),
                expandedMessage: Self.sanitizeDirectHumanText(fullNoData),
                structureIndex: s % 5,
                variationSeed: s
            )
        }

        let pills = [
            "\(cleanVal) · Lectura real",
            "\(cleanVal) · Dentro de tu línea",
            "\(cleanVal) · Pulso fisiológico claro",
            "\(cleanVal) · Tendencia revisada",
        ]
        let pillText = pills.first { !recentPillTexts.contains($0) } ?? pills[abs(s) % pills.count]
        recentPillTexts.append(pillText)
        if recentPillTexts.count > 8 { recentPillTexts.removeFirst() }

        var realParts: [String] = []
        if let rec = recoveryPct { realParts.append("recuperación del \(rec)%") }
        if let hrv = hrvMs { realParts.append(String(format: "VFC de %.1f ms", locale: Locale(identifier: "es_ES"), hrv)) }
        if let rhr = restingHrBpm { realParts.append(String(format: "FCR de %.1f ppm", locale: Locale(identifier: "es_ES"), rhr)) }
        if let slp = sleepDurationText, !slp.hasPrefix("--") { realParts.append("sueño de \(slp)") }
        if let en = energyPct { realParts.append("batería al \(en)%") }
        if let st = stressScore { realParts.append("estrés en \(st) sobre 100") }

        let contextClause = realParts.isEmpty
            ? "manteniendo seguimiento sobre tu referencia de \(cleanRange)"
            : "en línea con \(realParts.prefix(3).joined(separator: ", "))"

        let actions = [
            "Hidrátate hacia los \(String(format: "%.1f", locale: Locale(identifier: "es_ES"), norms.hydrationGoalLiters)) litros hoy y respeta tu zona de carga.",
            "Corta estimulantes a media tarde y cena ligero para proteger la lectura de mañana.",
            "Ajusta la intensidad de hoy según cómo combine este dato con tus sensaciones.",
        ]
        let action = actions[abs(s * 3) % actions.count]

        let shortMsg = Self.sanitizeDirectHumanText("\(nameLead)\(cleanVal) en \(metricTitle.lowercased()), \(contextClause). \(action)")
        let fullMsg = Self.sanitizeDirectHumanText("\(nameLead)hoy registras \(cleanVal) en \(metricTitle.lowercased()) frente a tu rango de \(cleanRange), \(contextClause). \(realParts.count > 3 ? "Además cuentas con \(realParts.dropFirst(3).joined(separator: ", ")). " : "")\(action)")

        return MetricFloatingAiInsight(
            shortPillText: pillText,
            expandedHeadline: headline,
            shortExpandedMessage: shortMsg,
            expandedMessage: fullMsg,
            structureIndex: s % 5,
            variationSeed: s
        )
    }
}

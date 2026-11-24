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

/// 3-Tier Live AI Engine for Improving iOS:
/// 1. True multi-turn conversational human chat (unlimited back-and-forth turns, strictly normalized roles, natural prose, remembers context).
/// 2. 4-hour time-aware, section-specific Live AI Coaching (non-generic, non-repetitive, strictly grounded in real measured user data).
/// 3. Tiered cloud transport: User Gemini API Key (`v1beta/models/<model>:generateContent` + `v1/interactions`) -> Keyless Live Cloud LLM -> Honest zero-fabrication offline fallback.
actor GeminiCoachService {
    static let shared = GeminiCoachService()

    static let supportedModels = [
        "auto",
        "gemini-3.1-flash-lite",
        "gemini-3-flash",
        "gemini-flash-latest",
        "gemini-2.5-flash",
    ]

    nonisolated static func displayLabel(for modelId: String) -> String {
        switch modelId {
        case "auto": return "Auto (Recomendado)"
        case "gemini-flash-latest": return "gemini-flash-latest"
        default: return modelId
        }
    }

    private let interactionsEndpoint = "https://generativelanguage.googleapis.com/v1/interactions"
    private let apiRevision = "2026-05-20"
    private let keylessEndpoint = "https://text.pollinations.ai/openai"
    private var discoveredModelsByKeyHash: [Int: [String]] = [:]

    /// Ranks raw Gemini API `/v1beta/models` identifiers, keeping only active text-generation Gemini models
    /// (filtering out embedding/image/video/tts/audio/robotics/gemma models) with newest Flash models first!
    nonisolated static func rankDiscoveredModels(_ rawEntries: [(name: String, methods: [String])]) -> [String] {
        let excludedTokens = [
            "embedding", "imagen", "veo", "tts", "audio", "aqa", "robotics",
            "computer-use", "bison", "gecko", "learnlm", "gemma", "deep-research",
            "native-audio", "live", "image"
        ]
        var names: [String] = []
        var seen = Set<String>()
        for entry in rawEntries {
            guard entry.methods.contains("generateContent") else { continue }
            let clean = entry.name.hasPrefix("models/") ? String(entry.name.dropFirst(7)) : entry.name
            let low = clean.lowercased()
            guard low.hasPrefix("gemini-") else { continue }
            if excludedTokens.contains(where: { low.contains($0) }) { continue }
            if seen.insert(clean).inserted {
                names.append(clean)
            }
        }
        func priorityScore(_ m: String) -> Int {
            let low = m.lowercased()
            if low.hasPrefix("gemini-4") && low.contains("flash") { return 100 }
            if low.hasPrefix("gemini-3.8") && low.contains("flash") { return 96 }
            if low.hasPrefix("gemini-3.5") && low.contains("flash-lite") { return 94 }
            if low.hasPrefix("gemini-3.5") && low.contains("flash") { return 93 }
            if low.hasPrefix("gemini-3.1") && low.contains("flash-lite") { return 91 }
            if low.hasPrefix("gemini-3.1") && low.contains("flash") { return 90 }
            if low.hasPrefix("gemini-3") && low.contains("flash") { return 88 }
            if low == "gemini-flash-latest" { return 85 }
            if low == "gemini-flash-lite-latest" { return 84 }
            if low.hasPrefix("gemini-3") { return 80 }
            if low.hasPrefix("gemini-2.5-flash") && !low.contains("lite") { return 72 }
            if low.hasPrefix("gemini-2.5-flash-lite") { return 68 }
            if low.hasPrefix("gemini-2.5-pro") { return 64 }
            if low.contains("flash") { return 55 }
            return 40
        }
        return names.sorted { a, b in
            let pa = priorityScore(a)
            let pb = priorityScore(b)
            if pa != pb { return pa > pb }
            // Prefer stable non-preview names when priority ties
            let aPrev = a.contains("preview") || a.contains("exp")
            let bPrev = b.contains("preview") || b.contains("exp")
            if aPrev != bPrev { return !aPrev }
            return a > b
        }
    }

    private func discoverAvailableModels(apiKey: String, forceRefresh: Bool = false) async -> [String] {
        let keyHash = apiKey.hashValue
        if !forceRefresh, let cached = discoveredModelsByKeyHash[keyHash], !cached.isEmpty {
            return cached
        }
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=100") else {
            return []
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 14
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["models"] as? [[String: Any]] else {
                return []
            }
            let rawEntries: [(String, [String])] = models.compactMap { m in
                guard let name = m["name"] as? String else { return nil }
                let methods = (m["supportedGenerationMethods"] as? [String]) ?? []
                return (name, methods)
            }
            let ranked = Self.rankDiscoveredModels(rawEntries)
            if !ranked.isEmpty {
                discoveredModelsByKeyHash[keyHash] = ranked
            }
            return ranked
        } catch {
            return []
        }
    }

    private func resolveCandidateModels(apiKey: String, selectedModel: String, forceDiscovery: Bool = false) async -> [String] {
        let trimmed = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let isAuto = trimmed.isEmpty || trimmed == "auto"
        let staticFallbacks = [
            "gemini-flash-latest",
            "gemini-3.5-flash-lite",
            "gemini-3.1-flash-lite",
            "gemini-3-flash",
            "gemini-3-flash-preview",
            "gemini-2.5-flash",
        ]
        var list: [String] = []
        if !isAuto {
            list.append(trimmed)
        }
        if isAuto || forceDiscovery {
            let discovered = await discoverAvailableModels(apiKey: apiKey, forceRefresh: forceDiscovery)
            list.append(contentsOf: discovered.prefix(5))
        }
        list.append(contentsOf: staticFallbacks)
        var seen = Set<String>()
        return list.filter { !$0.isEmpty && $0 != "auto" && seen.insert($0).inserted }
    }

    nonisolated static func sanitizeApiKey(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("bearer ") {
            s = String(s.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return s.filter { !$0.isWhitespace && !$0.isNewline }
    }

    private static func extractGeminiErrorMessage(from data: Data, statusCode: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = json["error"] as? [String: Any],
           let msg = err["message"] as? String, !msg.isEmpty {
            let short = msg.count > 120 ? String(msg.prefix(120)) + "…" : msg
            return "HTTP \(statusCode): \(short)"
        }
        return "HTTP \(statusCode)"
    }

    func testGeminiConnection(apiKey: String, selectedModel: String) async -> (ok: Bool, detail: String, resolvedModel: String?) {
        let cleanKey = Self.sanitizeApiKey(apiKey)
        let trimmedModel = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            // Test keyless cloud fallback when user has no API key
            if let _ = await callKeylessCloudChat(prompt: "Di solo OK", sysPrompt: "Responde únicamente OK.", history: [], seed: nextSeed()) {
                return (true, "✓ Motor cloud Improving IA activo (sin API Key)", nil)
            }
            return (false, "Introduce una API Key de Google AI Studio o revisa tu conexión.", nil)
        }
        let start = Date()
        let candidates = await resolveCandidateModels(apiKey: cleanKey, selectedModel: trimmedModel, forceDiscovery: true)
        var lastErr: String? = nil

        for m in candidates.prefix(5) {
            let attempt = await callGeminiChatGenerateContent(
                prompt: "Responde únicamente con la palabra OK.",
                sysPrompt: "Responde en español brevemente.",
                history: [],
                apiKey: cleanKey,
                model: m
            )
            if attempt.result != nil {
                let ms = Int((Date().timeIntervalSince(start) * 1000.0).rounded())
                let switched = !trimmedModel.isEmpty && trimmedModel != "auto" && trimmedModel != m
                let msg = switched
                    ? "✓ Conectado automáticamente a \(m) (\(ms) ms)"
                    : "✓ Conectado a \(m) (\(ms) ms)"
                return (true, msg, m)
            }
            if let err = attempt.errorDetail {
                lastErr = err
                if err.contains("API_KEY_INVALID") || err.contains("API key not valid") {
                    return (false, "API Key no válida: \(err)", nil)
                }
            }
        }
        return (false, "Error conectando con Gemini: \(lastErr ?? "sin respuesta")", nil)
    }

    private let coachingStyles = [
        "Abre con una observación fisiológica concreta conectando dos números reales del usuario y cierra con una decisión táctica para las próximas 4 horas.",
        "Habla como un entrenador de élite revisando el parte a esta hora exacta del día: directo, cálido, específico y orientado a la acción inmediata.",
        "Empieza señalando qué está respondiendo mejor o peor en su cuerpo ahora mismo y explica brevemente el porqué fisiológico antes de dar el paso práctico.",
        "Adopta un tono conversacional cercano y humano, poniendo el foco en cómo gestionar el ritmo desde esta hora hasta la siguiente ventana de 4 horas.",
        "Enfócate en el impacto práctico sobre la energía, el sistema nervioso y la noche que viene, sin sonar jamás a informe automático ni plantilla.",
        "Destaca el contraste entre los datos de hoy y cómo conviene dosificar esfuerzos, comida, hidratación o descanso justo en esta franja horaria."
    ]

    private var variationCounter: Int = 0
    private var recentPillTexts: [String] = []

    func nextSeed() -> Int {
        variationCounter += 1
        return variationCounter
    }

    // MARK: - Human Speech Sanitizer (Zero Parentheses, Zero Robotic Prefixes)

    nonisolated static func sanitizeDirectHumanText(_ raw: String) -> String {
        var cleaned = raw
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let regex = try? NSRegularExpression(pattern: "^(Opini[oó]n\\s*(de\\s*)?(IA)?\\s*(\\([^)]*\\))?\\s*:\\s*)", options: [.caseInsensitive]) {
            cleaned = regex.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: "")
        }
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

    // MARK: - Time-of-Day Spanish Context Helper

    private func describeLocalMoment(_ date: Date) -> (hhmm: String, periodName: String, guidance: String, blockIndex: Int) {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        let minute = cal.component(.minute, from: date)
        let hhmm = String(format: "%02d:%02d", hour, minute)
        let block = hour / 4
        switch block {
        case 0:
            return (hhmm, "madrugada", "Es plena madrugada. Si el usuario sigue despierto o acaba de acostarse, prioriza higiene del sueño, calma del sistema nervioso y cero pantallas.", block)
        case 1:
            return (hhmm, "primera hora de la mañana", "Está amaneciendo o recién despertado. Enfócate en cómo ha amanecido su cuerpo, hidratación inicial, luz natural y cómo plantear la mañana.", block)
        case 2:
            return (hhmm, "mañana", "Es por la mañana. Enfócate en la ventana de rendimiento matinal, gestión de cafeína, trabajo/entrenamiento y ritmo de energía para antes de comer.", block)
        case 3:
            return (hhmm, "mediodía y sobremesa", "Es mediodía o primera hora de la tarde. Evalúa cómo evoluciona el día a mitad de jornada, comidas, bajón postprandial y planificación del entrenamiento de tarde.", block)
        case 4:
            return (hhmm, "tarde", "Es media/última tarde. Enfócate en el balance entre el esfuerzo ya acumulado y la batería restante, corte de cafeína y cierre productivo sin quemar la noche.", block)
        default:
            return (hhmm, "noche", "Es de noche. Enfócate en desacelerar el sistema nervioso, cena ligera, preparar la hora de dormir y maximizar la recuperación nocturna de mañana.", block)
        }
    }

    // MARK: - 1. Multi-Turn Conversational System Instruction

    private func buildChatSystemInstruction(
        userName: String,
        currentDate: Date,
        biometricContextJson: String,
        availableHighlights: [String],
        missingCategories: [String],
        isFollowUp: Bool
    ) -> String {
        let name = userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "el usuario" : userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let moment = describeLocalMoment(currentDate)

        let dataConnection = availableHighlights.isEmpty
            ? "ATENCIÓN: En la fecha consultada NO hay métricas biométricas recopiladas del reloj ni de Apple Health."
            : "Lecturas reales confirmadas del usuario: \(availableHighlights.joined(separator: ", "))."

        let missingWarning = missingCategories.isEmpty
            ? "Todos los sensores principales tienen lectura real."
            : "Métricas SIN lectura hoy: \(missingCategories.joined(separator: ", "))."

        let continuityRule = isFollowUp
            ? "Estás en medio de una conversación activa con \(name). Continúa de forma totalmente natural a partir del hilo anterior: NO repitas saludos ni vuelvas a recitar todas sus métricas si ya las mencionaste, responde exactamente a su nuevo mensaje, pregunta de vuelta si ayuda a afinar, y mantén el hilo como un entrenador real hablando por WhatsApp."
            : "Responde desde la primera frase de forma directa, cercana y humana a exactamente lo que te pregunta \(name)."

        return """
        Eres el entrenador personal, fisiólogo y nutricionista humano de \(name) dentro de Improving.
        HORA LOCAL ACTUAL: \(moment.hhmm), franja de \(moment.periodName). \(moment.guidance)

        CÓMO CONVERSAR:
        - \(continuityRule)
        - Si te pregunta sobre entrenamiento, sueño, comida, salir de fiesta, suplementos, molestias, horarios o cualquier tema cotidiano o deportivo, responde con naturalidad, criterio real y cercanía.
        - Puedes hacer repreguntas breves si necesitas contexto adicional para ayudarle mejor, exactamente como haría una persona real.
        - Escribe en texto natural fluido en español de tú a tú, en 1 a 3 párrafos cortos y claros, o viñetas simples con guion solo si el usuario pide un plan o lista.
        - NO respondas en JSON, NO uses llaves {}, NO uses markdown con asteriscos ** ni paréntesis (). Integra las cifras de forma natural en la frase.
        - NO empieces con prefijos robóticos como "Análisis:", "Veredicto:" ni "Opinión IA:".

        VERACIDAD ABSOLUTA Y CERO INVENCIÓN DE DATOS:
        - \(dataConnection)
        - \(missingWarning)
        - PROHIBIDO inventar, estimar o rellenar ninguna cifra marcada como "NO_DISPONIBLE". Si pregunta por una métrica ausente, díselo con total naturalidad sin inventar ningún número.
        - Presta especial atención al bloque `diario_hoy` (hábitos personalizados, `nota_del_dia` y `notas_recientes`) y `nutricion_hoy` (comidas, macros, cafeína, hidratación y alcohol) para explicar variaciones reales en su VFC, sueño, recuperación o energía cuando vengan al caso.

        DATOS REALES DE \(name.uppercased()):
        \(biometricContextJson)
        """
    }

    // MARK: - Multi-Turn Role Normalization (Prevents Gemini HTTP 400 on Turn 2+ & Supports Photo Attachments!)

    private func buildNormalizedGeminiContents(history: [CoachChatMessage], currentPrompt: String, jpegImageData: Data? = nil) -> [[String: Any]] {
        var turns: [(role: String, text: String)] = []

        for msg in history.suffix(16) {
            let role = msg.isUser ? "user" : "model"
            var pieces: [String] = []
            if let t = msg.verdictTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                pieces.append(t)
            }
            let body = msg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { pieces.append(body) }
            if !msg.bullets.isEmpty {
                pieces.append(msg.bullets.joined(separator: " "))
            }
            let combined = pieces.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !combined.isEmpty else { continue }

            // Drop leading model messages so Gemini always begins with a user turn
            if turns.isEmpty && role == "model" { continue }

            if let last = turns.last, last.role == role {
                turns[turns.count - 1].text = last.text + "\n\n" + combined
            } else {
                turns.append((role, combined))
            }
        }

        let cleanPrompt = currentPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if let last = turns.last, last.role == "user" {
            turns[turns.count - 1].text = last.text + "\n\n" + cleanPrompt
        } else {
            turns.append(("user", cleanPrompt))
        }

        return turns.enumerated().map { idx, turn in
            var parts: [[String: Any]] = []
            if idx == turns.count - 1, let img = jpegImageData, !img.isEmpty {
                parts.append([
                    "inline_data": [
                        "mime_type": "image/jpeg",
                        "data": img.base64EncodedString()
                    ]
                ])
            }
            parts.append(["text": turn.text])
            return ["role": turn.role, "parts": parts]
        }
    }

    private func buildNormalizedOpenAIMessages(sysPrompt: String, history: [CoachChatMessage], currentPrompt: String) -> [[String: String]] {
        var messages: [[String: String]] = [["role": "system", "content": sysPrompt]]
        var turns: [(role: String, text: String)] = []

        for msg in history.suffix(16) {
            let role = msg.isUser ? "user" : "assistant"
            let combined = ([msg.verdictTitle, msg.text].compactMap { $0 }.filter { !$0.isEmpty } + msg.bullets)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !combined.isEmpty else { continue }
            if turns.isEmpty && role == "assistant" { continue }
            if let last = turns.last, last.role == role {
                turns[turns.count - 1].text = last.text + "\n\n" + combined
            } else {
                turns.append((role, combined))
            }
        }

        let cleanPrompt = currentPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if let last = turns.last, last.role == "user" {
            turns[turns.count - 1].text = last.text + "\n\n" + cleanPrompt
        } else {
            turns.append(("user", cleanPrompt))
        }

        for t in turns {
            messages.append(["role": t.role, "content": t.text])
        }
        return messages
    }

    // MARK: - Live Multi-Turn Coach Reply

    func askLiveCoach(
        prompt: String,
        apiKey: String,
        selectedModel: String,
        userName: String,
        currentDate: Date = Date(),
        biometricContextJson: String,
        availableHighlights: [String],
        missingCategories: [String],
        history: [CoachChatMessage],
        previousInteractionId: String? = nil,
        jpegImageData: Data? = nil
    ) async -> GeminiCoachResult {
        let seed = nextSeed()
        let isFollowUp = !history.isEmpty
        let sysPrompt = buildChatSystemInstruction(
            userName: userName,
            currentDate: currentDate,
            biometricContextJson: biometricContextJson,
            availableHighlights: availableHighlights,
            missingCategories: missingCategories,
            isFollowUp: isFollowUp
        )
        let cleanKey = Self.sanitizeApiKey(apiKey)
        let model = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "gemini-2.5-flash" : selectedModel
        var lastCloudError: String? = nil

        // Tier 1: User's Gemini API Key (auto-discovers live active models via /v1beta/models so 404 deprecations self-heal!)
        if !cleanKey.isEmpty {
            if jpegImageData == nil, model.hasPrefix("gemini-4"),
               let res = await callGeminiInteractionsChat(
                prompt: prompt,
                sysPrompt: sysPrompt,
                history: history,
                apiKey: cleanKey,
                model: model,
                previousInteractionId: previousInteractionId
               ) {
                return res
            }

            var candidates = await resolveCandidateModels(apiKey: cleanKey, selectedModel: model, forceDiscovery: false)
            var tried = Set<String>()
            var didDynamicDiscovery = (model.isEmpty || model == "auto")

            var idx = 0
            while idx < candidates.count {
                let m = candidates[idx]
                idx += 1
                guard tried.insert(m).inserted else { continue }
                let attempt = await callGeminiChatGenerateContent(
                    prompt: prompt,
                    sysPrompt: sysPrompt,
                    history: history,
                    apiKey: cleanKey,
                    model: m,
                    jpegImageData: jpegImageData
                )
                if let res = attempt.result {
                    return res
                }
                if let err = attempt.errorDetail {
                    lastCloudError = err
                    if err.contains("API_KEY_INVALID") || err.contains("API key not valid") {
                        break
                    }
                    // On HTTP 404 (model retired / unavailable to new users), immediately query Google's live /models endpoint!
                    if !didDynamicDiscovery && (err.contains("404") || err.lowercased().contains("no longer available") || err.lowercased().contains("not found")) {
                        didDynamicDiscovery = true
                        let fresh = await discoverAvailableModels(apiKey: cleanKey, forceRefresh: true)
                        if !fresh.isEmpty {
                            candidates.insert(contentsOf: fresh.prefix(4), at: idx)
                        }
                    }
                }
            }
        }

        // Tier 2: Out-of-the-box Keyless Cloud LLM with full multi-turn history & multi-model retry
        if jpegImageData == nil, let cloudRes = await callKeylessCloudChat(prompt: prompt, sysPrompt: sysPrompt, history: history, seed: seed) {
            return cloudRes
        }

        // Tier 3: Honest offline conversational fallback with real diagnostic cause
        let extraDiag: String? = (jpegImageData != nil && cleanKey.isEmpty)
            ? "Para analizar imágenes en el chat añade tu API Key gratuita de Google AI Studio en Dispositivos y Ajustes."
            : lastCloudError
        return buildOfflineChatFallback(
            prompt: prompt,
            userName: userName,
            currentDate: currentDate,
            availableHighlights: availableHighlights,
            missingCategories: missingCategories,
            diagnosticNote: extraDiag
        )
    }

    private func callGeminiInteractionsChat(
        prompt: String,
        sysPrompt: String,
        history: [CoachChatMessage],
        apiKey: String,
        model: String,
        previousInteractionId: String?
    ) async -> GeminiCoachResult? {
        guard let url = URL(string: interactionsEndpoint) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 25
        req.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        req.setValue(apiRevision, forHTTPHeaderField: "Api-Revision")

        // Include recent conversation recap when previous_interaction_id isn't available
        var inputText = prompt
        if previousInteractionId == nil && !history.isEmpty {
            let recap = history.suffix(8).map { ($0.isUser ? "Usuario: " : "Coach: ") + $0.text }.joined(separator: "\n")
            inputText = "Contexto de la conversación previa:\n\(recap)\n\nNuevo mensaje del usuario:\n\(prompt)"
        }

        var body: [String: Any] = [
            "model": model,
            "system_instruction": sysPrompt,
            "input": inputText
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
            return parseConversationalReply(rawText: outText, interactionId: newId, modelUsed: model)
        } catch {
            return nil
        }
    }

    private func callGeminiChatGenerateContent(
        prompt: String,
        sysPrompt: String,
        history: [CoachChatMessage],
        apiKey: String,
        model: String,
        jpegImageData: Data? = nil
    ) async -> (result: GeminiCoachResult?, errorDetail: String?) {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            return (nil, "URL de modelo inválida")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 28
        req.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let contents = buildNormalizedGeminiContents(history: history, currentPrompt: prompt, jpegImageData: jpegImageData)
        var genConfig: [String: Any] = [
            "temperature": 0.78,
            "maxOutputTokens": model.contains("pro") ? 2400 : 1600
        ]
        if model.hasPrefix("gemini-2.5-flash") {
            genConfig["thinkingConfig"] = ["thinkingBudget": 0]
        }
        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": sysPrompt]]],
            "contents": contents,
            "generationConfig": genConfig
        ]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            return (nil, "Error serializando consulta")
        }
        req.httpBody = httpBody

        for attemptIdx in 0..<2 {
            do {
                let (respData, resp) = try await URLSession.shared.data(for: req)
                guard let http = resp as? HTTPURLResponse else {
                    return (nil, "Respuesta de red inválida")
                }
                if (200...299).contains(http.statusCode) {
                    if let json = try JSONSerialization.jsonObject(with: respData) as? [String: Any],
                       let candidates = json["candidates"] as? [[String: Any]],
                       let content = candidates.first?["content"] as? [String: Any],
                       let parts = content["parts"] as? [[String: Any]] {
                        // Prefer non-thought text parts; fall back to any text part
                        let visible = parts.compactMap { part -> String? in
                            if (part["thought"] as? Bool) == true { return nil }
                            return part["text"] as? String
                        }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
                        let joined = visible.isEmpty
                            ? parts.compactMap { $0["text"] as? String }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
                            : visible
                        if !joined.isEmpty {
                            return (parseConversationalReply(rawText: joined, interactionId: nil, modelUsed: model), nil)
                        }
                    }
                    return (nil, "Respuesta vacía de \(model)")
                }
                let errTxt = Self.extractGeminiErrorMessage(from: respData, statusCode: http.statusCode)
                if (http.statusCode == 500 || http.statusCode == 503) && attemptIdx == 0 {
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    continue
                }
                return (nil, errTxt)
            } catch {
                if attemptIdx == 0 {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    continue
                }
                return (nil, error.localizedDescription)
            }
        }
        return (nil, "Sin respuesta de Gemini")
    }

    private func callKeylessCloudChat(
        prompt: String,
        sysPrompt: String,
        history: [CoachChatMessage],
        seed: Int
    ) async -> GeminiCoachResult? {
        guard let url = URL(string: keylessEndpoint) else { return nil }
        let messages = buildNormalizedOpenAIMessages(sysPrompt: sysPrompt, history: history, currentPrompt: prompt)

        for (idx, cloudModel) in ["openai-fast", "openai-fast"].enumerated() {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 24
            req.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("Improving-iOS/2.0", forHTTPHeaderField: "User-Agent")

            let body: [String: Any] = [
                "model": cloudModel,
                "messages": messages,
                "temperature": 0.78
            ]
            guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { continue }
            req.httpBody = httpBody

            do {
                let (respData, resp) = try await URLSession.shared.data(for: req)
                guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    if idx == 0 { try? await Task.sleep(nanoseconds: 350_000_000) }
                    continue
                }
                if let root = try? JSONSerialization.jsonObject(with: respData) as? [String: Any],
                   let choices = root["choices"] as? [[String: Any]],
                   let msg = choices.first?["message"] as? [String: Any],
                   let content = msg["content"] as? String,
                   !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return parseConversationalReply(rawText: content, interactionId: root["id"] as? String, modelUsed: "improving-live-ai")
                }
                // Some keyless providers return plain text directly on HTTP 200
                if let plain = String(data: respData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !plain.isEmpty, !plain.hasPrefix("{"), !plain.hasPrefix("<") {
                    return parseConversationalReply(rawText: plain, interactionId: nil, modelUsed: "improving-live-ai")
                }
            } catch {
                if idx == 0 { try? await Task.sleep(nanoseconds: 350_000_000) }
                continue
            }
        }
        return nil
    }

    private func parseConversationalReply(rawText: String, interactionId: String?, modelUsed: String) -> GeminiCoachResult {
        var cleaned = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip accidental code fences or JSON if a model still emitted JSON
        for prefix in ["```json", "```JSON", "```"] {
            if cleaned.hasPrefix(prefix) { cleaned = String(cleaned.dropFirst(prefix.count)) }
        }
        if cleaned.hasSuffix("```") { cleaned = String(cleaned.dropLast(3)) }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.hasPrefix("{"), cleaned.hasSuffix("}"),
           let data = cleaned.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = obj["text"] as? String, !text.isEmpty {
            let bullets = ((obj["bullets"] as? [String]) ?? []).map { Self.sanitizeDirectHumanText($0) }.filter { !$0.isEmpty }
            return GeminiCoachResult(
                verdictTitle: "",
                text: Self.sanitizeDirectHumanText(text),
                bullets: bullets,
                actionLabel: nil,
                interactionId: interactionId,
                usedLiveCloud: true,
                modelUsed: modelUsed
            )
        }

        // Preserve natural paragraph breaks while sanitizing each paragraph cleanly
        let paragraphs = cleaned
            .components(separatedBy: "\n\n")
            .map { Self.sanitizeDirectHumanText($0) }
            .filter { !$0.isEmpty }
        let finalText = paragraphs.isEmpty ? Self.sanitizeDirectHumanText(cleaned) : paragraphs.joined(separator: "\n\n")

        return GeminiCoachResult(
            verdictTitle: "",
            text: finalText,
            bullets: [],
            actionLabel: nil,
            interactionId: interactionId,
            usedLiveCloud: true,
            modelUsed: modelUsed
        )
    }

    private func buildOfflineChatFallback(
        prompt: String,
        userName: String,
        currentDate: Date,
        availableHighlights: [String],
        missingCategories: [String],
        diagnosticNote: String? = nil
    ) -> GeminiCoachResult {
        let namePrefix = userName.trimmingCharacters(in: .whitespaces).isEmpty ? "" : "\(userName.trimmingCharacters(in: .whitespaces)), "
        let moment = describeLocalMoment(currentDate)
        let diagSuffix: String = {
            guard let d = diagnosticNote, !d.isEmpty else { return "" }
            if d.contains("400") || d.contains("403") || d.contains("API_KEY") {
                return " Revisa tu API Key de Gemini en Dispositivos y Ajustes — Google respondió \(d)."
            }
            if d.contains("429") || d.contains("RESOURCE_EXHAUSTED") {
                return " Tu cuota gratuita de Gemini llegó al límite temporal — \(d). Prueba el modelo gemini-2.5-flash-lite en Ajustes."
            }
            return " Detalle de red: \(d)."
        }()
        if availableHighlights.isEmpty {
            return GeminiCoachResult(
                verdictTitle: "",
                text: "\(namePrefix)son las \(moment.hhmm) y ahora mismo no pude completar la llamada a la nube para responder a «\(prompt)».\(diagSuffix) Cuando se restablezca la conexión seguimos la charla con tus datos reales.",
                bullets: [],
                actionLabel: nil,
                interactionId: nil,
                usedLiveCloud: false,
                modelUsed: "offline-engine"
            )
        }
        return GeminiCoachResult(
            verdictTitle: "",
            text: "\(namePrefix)ahora mismo a las \(moment.hhmm) no pude completar la conexión en vivo para responder en detalle a «\(prompt)», pero viendo tus lecturas reales activas — \(availableHighlights.joined(separator: ", ")) — ajusta la intensidad a lo que te queda de jornada.\(diagSuffix)",
            bullets: [],
            actionLabel: nil,
            interactionId: nil,
            usedLiveCloud: false,
            modelUsed: "offline-engine"
        )
    }

    // MARK: - 2. Time-Aware, 4-Hour-Refreshing, Section-Specific Live AI Coaching

    func generateSectionCoaching(
        section: CoachingSection,
        currentDate: Date,
        selectedDateIso: String,
        isViewingToday: Bool,
        userName: String,
        biometricContextJson: String,
        sectionFacts: [String],
        missingCategories: [String],
        previousHeadline: String?,
        hasSectionData: Bool,
        slotKey: String,
        generatedAtLabel: String,
        nextUpdateLabel: String,
        apiKey: String,
        selectedModel: String
    ) async -> SectionCoachingCard {
        let seed = nextSeed()
        let moment = describeLocalMoment(currentDate)
        let defaultEmoji = Self.defaultEmoji(for: section)

        // Strictly honest no-data card (ZERO invention!)
        if !hasSectionData {
            let noDataBody: String
            switch section {
            case .sueno:
                noDataBody = "No hay registros reales de sueño para esta fecha en Apple Health ni en tu reloj. En cuanto sincronices una noche medida verás aquí tu análisis detallado de fases, eficiencia y constantes."
            case .esfuerzo:
                noDataBody = "Todavía no constan lecturas de esfuerzo, zonas de pulso ni entrenamientos para esta fecha. Cuando registres actividad o importes tu historial, este coaching se adaptará a tu carga real."
            case .recuperacion:
                noDataBody = "No se ha registrado VFC ni frecuencia cardíaca en reposo en esta fecha, así que prefiero no inventar tu recuperación. Usa las flechas o el calendario para ver un día con lecturas."
            case .estres:
                noDataBody = "No existen muestras intradía de frecuencia cardíaca para calcular el estrés en esta fecha. En cuanto haya mediciones reales verás la lectura cada 5 minutos y su consejo horario."
            case .energia:
                noDataBody = "No hay curva de energía disponible para esta fecha porque faltan lecturas continuas del reloj. Sincroniza Apple Health o navega a un día con datos."
            case .fitness:
                noDataBody = "Sin sesiones ni carga cardiovascular registrada todavía en esta ventana. Cuando entrenes o importes tu historial verás tu recomendación personalizada de carga."
            case .hoy:
                noDataBody = "No constan mediciones recopiladas en Apple Health ni en tu reloj para esta fecha. Usa las flechas o el calendario para consultar días con registros, o sincroniza en Ajustes."
            }
            return SectionCoachingCard(
                section: section,
                emoji: defaultEmoji,
                headline: "Sin lecturas de \(section.displayName.lowercased())",
                body: noDataBody,
                slotKey: slotKey,
                generatedAtLabel: generatedAtLabel,
                nextUpdateLabel: nextUpdateLabel,
                isLiveAI: false
            )
        }

        let name = userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "el usuario" : userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let sectionIndex = CoachingSection.allCases.firstIndex(of: section) ?? 0
        let styleAngle = coachingStyles[(moment.blockIndex * 7 + sectionIndex + seed) % coachingStyles.count]
        let focusDirective = Self.sectionFocusDirective(for: section)
        let avoidRepeat = previousHeadline.map { "PROHIBIDO repetir la idea, estructura ni frases del titular previo: «\($0)». Escribe algo totalmente distinto y fresco." } ?? "Crea un titular y un análisis completamente originales, jamás genéricos."
        let dayFrame = isViewingToday
            ? "Estás analizando el día de HOY y son exactamente las \(moment.hhmm) de la \(moment.periodName). \(moment.guidance) Adapta tu consejo específicamente a esta hora exacta y a lo que conviene hacer en las próximas 4 horas hasta las \(nextUpdateLabel)."
            : "El usuario está revisando una fecha histórica del \(selectedDateIso), aunque ahora mismo en su reloj son las \(moment.hhmm). Analiza los datos reales de aquel día en profundidad y extrae una lección útil aplicable hoy."

        let sysPrompt = """
        Eres el entrenador personal y fisiólogo de \(name) en Improving.
        APARTADO ACTUAL: \(section.displayName.uppercased()).
        ENFOQUE EXCLUSIVO DEL APARTADO: \(focusDirective)

        CONSCIENCIA HORARIA:
        - \(dayFrame)

        REGLAS DE CALIDAD Y ANTI-GENÉRICOS:
        1. Cita al menos 2 cifras REALES concretas del usuario del bloque de datos de este apartado y explica qué implican para su cuerpo ahora mismo.
        2. \(styleAngle)
        3. \(avoidRepeat)
        4. PROHIBIDO usar frases vacías como "escucha a tu cuerpo", "mantén un enfoque equilibrado", "lectura real del día:" ni paréntesis ().
        5. PROHIBIDO inventar o suponer cualquier métrica que aparezca como "NO_DISPONIBLE".
        6. Habla a \(name) en español natural, directo, cercano y humano.

        DATOS ESPECÍFICOS REALES DE \(section.displayName.uppercased()):
        - \(sectionFacts.joined(separator: "\n- "))

        MÉTRICAS NO DISPONIBLES HOY: \(missingCategories.isEmpty ? "Ninguna" : missingCategories.joined(separator: ", "))

        CONTEXTO BIOMÉTRICO COMPLETO:
        \(biometricContextJson)

        Devuelve ÚNICAMENTE un JSON válido sin bloques markdown con este formato exacto:
        {
          "emoji": "1 emoji relevante para \(section.displayName)",
          "headline": "Titular fresco y específico de 3 a 6 palabras sin paréntesis",
          "body": "Mensaje único y detallado de 2 a 4 frases adaptado a las \(moment.hhmm) y enfocado principalmente en \(section.displayName.lowercased()), citando los números reales del usuario sin paréntesis."
        }
        """

        let userPrompt = "Genera el mensaje de coaching de las \(moment.hhmm) para el apartado \(section.displayName) de \(name). Semilla de variación: \(seed)-\(moment.blockIndex)-\(sectionIndex)."

        let cleanKey = Self.sanitizeApiKey(apiKey)
        let model = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "gemini-2.5-flash" : selectedModel

        // Tier 1: User's Gemini API Key (auto-discovers live active models on 404/auto!)
        if !cleanKey.isEmpty {
            let candidates = await resolveCandidateModels(apiKey: cleanKey, selectedModel: model, forceDiscovery: model == "auto")
            for m in candidates.prefix(4) {
                if let raw = await callGeminiJsonOneShot(prompt: userPrompt, sysPrompt: sysPrompt, apiKey: cleanKey, model: m),
                   let card = parseSectionCoachingJson(
                    raw: raw,
                    section: section,
                    fallbackEmoji: defaultEmoji,
                    slotKey: slotKey,
                    generatedAtLabel: generatedAtLabel,
                    nextUpdateLabel: nextUpdateLabel
                   ) {
                    return card
                }
            }
        }

        // Tier 2: Keyless Live Cloud LLM
        if let raw = await callKeylessCloudOneShot(prompt: userPrompt, sysPrompt: sysPrompt, seed: seed + moment.blockIndex * 19),
           let card = parseSectionCoachingJson(
            raw: raw,
            section: section,
            fallbackEmoji: defaultEmoji,
            slotKey: slotKey,
            generatedAtLabel: generatedAtLabel,
            nextUpdateLabel: nextUpdateLabel
           ) {
            return card
        }

        // Tier 3: Rich time-aware, section-specific local engine (rotates by 4-hour block & cites real user facts)
        return buildLocalTimeAwareSectionCoaching(
            section: section,
            userName: name,
            moment: moment,
            isViewingToday: isViewingToday,
            selectedDateIso: selectedDateIso,
            sectionFacts: sectionFacts,
            slotKey: slotKey,
            generatedAtLabel: generatedAtLabel,
            nextUpdateLabel: nextUpdateLabel,
            seed: seed
        )
    }

    private func callGeminiJsonOneShot(prompt: String, sysPrompt: String, apiKey: String, model: String) async -> String? {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        var genConfig: [String: Any] = [
            "temperature": 0.9,
            "maxOutputTokens": 600,
            "responseMimeType": "application/json"
        ]
        if model.hasPrefix("gemini-2.5-flash") {
            genConfig["thinkingConfig"] = ["thinkingBudget": 0]
        }
        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": sysPrompt]]],
            "contents": [["role": "user", "parts": [["text": prompt]]]],
            "generationConfig": genConfig
        ]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        req.httpBody = httpBody

        do {
            let (respData, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: respData) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else { return nil }
            let joined = parts.compactMap { part -> String? in
                if (part["thought"] as? Bool) == true { return nil }
                return part["text"] as? String
            }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
            return joined.isEmpty ? nil : joined
        } catch {
            return nil
        }
    }

    private func callKeylessCloudOneShot(prompt: String, sysPrompt: String, seed: Int) async -> String? {
        guard let url = URL(string: keylessEndpoint) else { return nil }
        for (idx, cloudModel) in ["openai-fast", "openai-fast"].enumerated() {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 22
            req.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("Improving-iOS/2.0", forHTTPHeaderField: "User-Agent")

            let body: [String: Any] = [
                "model": cloudModel,
                "temperature": 0.9,
                "messages": [
                    ["role": "system", "content": sysPrompt],
                    ["role": "user", "content": prompt]
                ]
            ]
            guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { continue }
            req.httpBody = httpBody

            do {
                let (respData, resp) = try await URLSession.shared.data(for: req)
                guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                      let root = try JSONSerialization.jsonObject(with: respData) as? [String: Any],
                      let choices = root["choices"] as? [[String: Any]],
                      let msg = choices.first?["message"] as? [String: Any],
                      let content = msg["content"] as? String,
                      !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    if idx == 0 { try? await Task.sleep(nanoseconds: 350_000_000) }
                    continue
                }
                return content
            } catch {
                if idx == 0 { try? await Task.sleep(nanoseconds: 350_000_000) }
                continue
            }
        }
        return nil
    }

    private func parseSectionCoachingJson(
        raw: String,
        section: CoachingSection,
        fallbackEmoji: String,
        slotKey: String,
        generatedAtLabel: String,
        nextUpdateLabel: String
    ) -> SectionCoachingCard? {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["```json", "```JSON", "```"] {
            if cleaned.hasPrefix(prefix) { cleaned = String(cleaned.dropFirst(prefix.count)) }
        }
        if cleaned.hasSuffix("```") { cleaned = String(cleaned.dropLast(3)) }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let s = cleaned.firstIndex(of: "{"), let e = cleaned.lastIndex(of: "}"), e > s,
              let data = String(cleaned[s...e]).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawBody = obj["body"] as? String else {
            return nil
        }
        let body = Self.sanitizeDirectHumanText(rawBody)
        guard body.count >= 25 else { return nil }
        let rawHead = (obj["headline"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let headline = rawHead.isEmpty ? "Pulso de \(section.displayName.lowercased())" : Self.sanitizeDirectHumanText(rawHead)
        let rawEmoji = (obj["emoji"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let emoji = rawEmoji.isEmpty ? fallbackEmoji : String(rawEmoji.prefix(2))

        return SectionCoachingCard(
            section: section,
            emoji: emoji,
            headline: headline,
            body: body,
            slotKey: slotKey,
            generatedAtLabel: generatedAtLabel,
            nextUpdateLabel: nextUpdateLabel,
            isLiveAI: true
        )
    }

    private func buildLocalTimeAwareSectionCoaching(
        section: CoachingSection,
        userName: String,
        moment: (hhmm: String, periodName: String, guidance: String, blockIndex: Int),
        isViewingToday: Bool,
        selectedDateIso: String,
        sectionFacts: [String],
        slotKey: String,
        generatedAtLabel: String,
        nextUpdateLabel: String,
        seed: Int
    ) -> SectionCoachingCard {
        let lead = (userName == "el usuario" || userName.isEmpty) ? "" : "\(userName), "
        let factsJoined = sectionFacts.prefix(3).joined(separator: ", ")
        let idx = (moment.blockIndex + seed) % 3

        let timeAction: String = switch moment.blockIndex {
        case 0: "A estas horas de madrugada tu única prioridad es apagar estímulos y proteger el sueño profundo."
        case 1: "Recién arrancada la mañana, hidrátate bien y busca luz natural en la próxima hora."
        case 2: "Aprovecha esta franja matinal hasta las \(nextUpdateLabel) para tus tareas o bloque físico principal."
        case 3: "A mitad de jornada conviene vigilar la comida ligera y dosificar el pulso de cara a la tarde."
        case 4: "En esta recta de la tarde corta la cafeína y decide si toca rematar carga o bajar revoluciones."
        default: "De cara a la noche, cena ligero y ve bajando el ritmo nervioso para cuidar las lecturas de mañana."
        }

        let (emoji, headline, body): (String, String, String)
        switch section {
        case .sueno:
            let heads = ["Arquitectura nocturna a las \(moment.hhmm)", "Cómo rindió tu descanso", "Balance real de tu noche"]
            emoji = "🌙"
            headline = heads[idx]
            body = isViewingToday
                ? "\(lead)viendo tu descanso real — \(factsJoined) — el impacto se nota justo ahora en la \(moment.periodName). \(timeAction)"
                : "\(lead)el \(selectedDateIso) tu noche dejó estas señales reales: \(factsJoined). Compara esa estructura de fases con tus noches más frescas para detectar qué rutina te funciona mejor."
        case .esfuerzo:
            let heads = ["Carga física en esta franja", "Ritmo de esfuerzo a las \(moment.hhmm)", "Dosificación de tu carga"]
            emoji = "🔥"
            headline = heads[idx]
            body = isViewingToday
                ? "\(lead)a las \(moment.hhmm) tu parte real de carga marca \(factsJoined). \(timeAction)"
                : "\(lead)el \(selectedDateIso) acumulaste \(factsJoined). Úsalo como referencia para calibrar cuánto volumen asimila bien tu corazón sin disparar fatiga."
        case .recuperacion:
            let heads = ["Estado autonómico a las \(moment.hhmm)", "Lectura de tu sistema nervioso", "Margen real de recuperación"]
            emoji = "🌿"
            headline = heads[idx]
            body = isViewingToday
                ? "\(lead)tu sistema nervioso refleja hoy \(factsJoined). Con ese margen real a las \(moment.hhmm), \(timeAction.lowercased())"
                : "\(lead)el \(selectedDateIso) tu recuperación se apoyó en \(factsJoined), mostrando cómo responde tu tono vagal tras la carga previa."
        case .estres:
            let heads = ["Pulso del estrés a las \(moment.hhmm)", "Activación simpática actual", "Gestión de tensión hoy"]
            emoji = "🧠"
            headline = heads[idx]
            body = isViewingToday
                ? "\(lead)a las \(moment.hhmm) tu curva real de estrés marca \(factsJoined). Introduce 3 minutos de respiración lenta si notas picos sostenidos antes de las \(nextUpdateLabel)."
                : "\(lead)durante el \(selectedDateIso) tu estrés registró \(factsJoined). Revisa en el gráfico de 5 minutos qué momentos elevaron más tu pulso."
        case .energia:
            let heads = ["Batería disponible a las \(moment.hhmm)", "Balance real de energía", "Reserva corporal en vivo"]
            emoji = "⚡"
            headline = heads[idx]
            body = isViewingToday
                ? "\(lead)tu curva continua de energía muestra \(factsJoined) a las \(moment.hhmm). \(timeAction)"
                : "\(lead)el \(selectedDateIso) tu batería evolucionó con \(factsJoined), reflejando exactamente cuánto recargaste dormido frente al gasto diurno."
        case .fitness:
            let heads = ["Ventana de entrenamiento \(moment.hhmm)", "Carga cardio y muscular", "Estrategia de sesión hoy"]
            emoji = "🏋️"
            headline = heads[idx]
            body = isViewingToday
                ? "\(lead)con \(factsJoined) en tu historial reciente, a las \(moment.hhmm) conviene decidir si toca sesión exigente o estímulo técnico limpio. \(timeAction)"
                : "\(lead)en torno al \(selectedDateIso) tu bloque de fitness sumaba \(factsJoined). Vigila la progresión semanal para seguir sumando sin sobreentrenar."
        case .hoy:
            let heads = ["Hoja de ruta a las \(moment.hhmm)", "Tu pulso de la \(moment.periodName)", "Prioridad hasta las \(nextUpdateLabel)"]
            emoji = "✨"
            headline = heads[idx]
            body = isViewingToday
                ? "\(lead)a las \(moment.hhmm) tus señales reales del día combinan \(factsJoined). \(timeAction)"
                : "\(lead)en la jornada del \(selectedDateIso) registraste \(factsJoined). Navega a cada apartado para revisar la relación entre descanso, pulso y carga."
        }

        return SectionCoachingCard(
            section: section,
            emoji: emoji,
            headline: Self.sanitizeDirectHumanText(headline),
            body: Self.sanitizeDirectHumanText(body),
            slotKey: slotKey,
            generatedAtLabel: generatedAtLabel,
            nextUpdateLabel: nextUpdateLabel,
            isLiveAI: false
        )
    }

    private static func defaultEmoji(for section: CoachingSection) -> String {
        switch section {
        case .hoy: return "✨"
        case .esfuerzo: return "🔥"
        case .recuperacion: return "🌿"
        case .sueno: return "🌙"
        case .estres: return "🧠"
        case .energia: return "⚡"
        case .fitness: return "🏋️"
        }
    }

    private static func sectionFocusDirective(for section: CoachingSection) -> String {
        switch section {
        case .hoy:
            return "Visión integradora del día: conecta recuperación, esfuerzo, sueño y batería de energía para darle la prioridad exacta para las próximas 4 horas."
        case .esfuerzo:
            return "HABLA PRINCIPALMENTE DE ESFUERZO Y CARGA FÍSICA: porcentaje de esfuerzo frente a su rango objetivo óptimo, entrenamientos realizados, pulso medio, zonas cardíacas, pasos y calorías activas. No divagues sobre otros temas."
        case .recuperacion:
            return "HABLA PRINCIPALMENTE DE RECUPERACIÓN Y SISTEMA NERVIOSO AUTÓNOMO: porcentaje de recuperación, VFC nocturna frente a su línea base personal, FC en reposo durmiendo, frecuencia respiratoria, SpO2 y temperatura de muñeca."
        case .sueno:
            return "HABLA PRINCIPALMENTE DE SUEÑO: duración real, hora de acostarse y despertar, eficiencia, sueño profundo y MOR, latencia, disminución de la FC nocturna y cómo proteger el descanso de la próxima noche."
        case .estres:
            return "HABLA PRINCIPALMENTE DE ESTRÉS FISIOLÓGICO: media, pico máximo, mínimo, tiempo en estrés alto frente a bajo, estrés nocturno y estrategias prácticas concretas para bajar activación simpática."
        case .energia:
            return "HABLA PRINCIPALMENTE DE LA BATERÍA DE ENERGÍA CONTINUA: con qué porcentaje arrancó el día desde la noche anterior, cuánto recargó al dormir, cuánto lleva gastado hasta esta hora y cómo dosificar la batería restante."
        case .fitness:
            return "HABLA PRINCIPALMENTE DE FITNESS Y ENTRENAMIENTO: carga cardiovascular y muscular de 7 días, volumen de los últimos 30 días, VO2 máx., recuperación de FC, zonas cardíacas y qué tipo de sesión conviene hoy."
        }
    }

    // MARK: - 3. Click-to-Expand Metric Floating Insight (Zero Fabricated Numbers)

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
            let fullNoData = "\(nameLead)no constan muestras reales de \(metricTitle.lowercased()) registradas en esta fecha. Nunca invento cifras ni tendencias vacías: para tu perfil de \(Int(profile.effectiveAgeYears.rounded(.down))) años y \(Int(profile.weightKg)) kg, la banda orientativa es \(cleanRange). Cuando tu reloj registre o importes mediciones en este día verás el análisis exacto."
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

    // MARK: - 4. Multimodal Nutrition Analyzer (Photo + Natural Spanish Text via Gemini 3/3.1 Flash)

    func analyzeMealWithAI(
        descriptionText: String,
        jpegImageData: Data?,
        apiKey: String,
        selectedModel: String
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
        if !cleanKey.isEmpty {
            let candidates = await resolveCandidateModels(apiKey: cleanKey, selectedModel: model, forceDiscovery: model == "auto")
            for m in candidates.prefix(5) {
                if let raw = await callGeminiMultimodalJson(
                    prompt: userPrompt,
                    sysPrompt: sysPrompt,
                    jpegImageData: jpegImageData,
                    apiKey: cleanKey,
                    model: m
                ), let parsed = Self.parseMealEstimateJson(raw, usedLiveAI: true, modelUsed: m) {
                    return parsed
                }
            }
        }

        // Tier 2: Keyless Live Cloud LLM when text description is available
        if !trimmedDesc.isEmpty {
            if let raw = await callKeylessCloudOneShot(prompt: userPrompt, sysPrompt: sysPrompt, seed: nextSeed()),
               let parsed = Self.parseMealEstimateJson(raw, usedLiveAI: true, modelUsed: "improving-cloud") {
                return parsed
            }
        }

        // Tier 3: Deterministic Spanish Nutrition Lexicon Fallback (instant offline resilience, editable before saving)
        return Self.estimateMealLocally(from: trimmedDesc, hasPhoto: jpegImageData != nil)
    }

    private func callGeminiMultimodalJson(
        prompt: String,
        sysPrompt: String,
        jpegImageData: Data?,
        apiKey: String,
        model: String
    ) async -> String? {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 28
        req.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

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
            "maxOutputTokens": 650,
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
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        req.httpBody = httpBody

        do {
            let (respData, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: respData) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else { return nil }
            let joined = parts.compactMap { part -> String? in
                if (part["thought"] as? Bool) == true { return nil }
                return part["text"] as? String
            }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
            return joined.isEmpty ? nil : joined
        } catch {
            return nil
        }
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
        selectedModel: String
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

        let sysPrompt = """
        Eres el fisiólogo deportivo de \(name) en Improving. Analiza su semana real frente a los 7 días anteriores y devuelve EXCLUSIVAMENTE un JSON válido:
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

        if !cleanKey.isEmpty {
            let candidates = await resolveCandidateModels(apiKey: cleanKey, selectedModel: selectedModel, forceDiscovery: false)
            for m in candidates.prefix(4) {
                if let raw = await callGeminiMultimodalJson(
                    prompt: userPrompt,
                    sysPrompt: sysPrompt,
                    jpegImageData: nil,
                    apiKey: cleanKey,
                    model: m
                ), let parsed = Self.parseWeeklyReviewJson(raw, weekKey: report.weekKey, generatedAt: generatedLabel, modelUsed: m, isLiveAI: true) {
                    return parsed
                }
            }
        }

        if let raw = await callKeylessCloudOneShot(prompt: userPrompt, sysPrompt: sysPrompt, seed: nextSeed()),
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
        selectedModel: String
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
            : "Extrae todos los biomarcadores numéricos reales de esta analítica de sangre:\n\n\(String(trimmedText.prefix(12000)))"

        if !cleanKey.isEmpty {
            let candidates = await resolveCandidateModels(apiKey: cleanKey, selectedModel: selectedModel, forceDiscovery: false)
            for m in candidates.prefix(4) {
                if let raw = await callGeminiMultiImageJson(
                    prompt: userPrompt,
                    sysPrompt: sysPrompt,
                    jpegImagesData: Array(pageImagesData.prefix(4)),
                    apiKey: cleanKey,
                    model: m,
                    maxOutputTokens: 2200
                ), let parsed = Self.parseLabReportJson(raw, sourceLabel: "Gemini \(m)") {
                    return (parsed, nil)
                }
            }
        }

        if !trimmedText.isEmpty {
            if let raw = await callKeylessCloudOneShot(prompt: userPrompt, sysPrompt: sysPrompt, seed: nextSeed()),
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

    private func callGeminiMultiImageJson(
        prompt: String,
        sysPrompt: String,
        jpegImagesData: [Data],
        apiKey: String,
        model: String,
        maxOutputTokens: Int = 2000
    ) async -> String? {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 36
        req.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

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
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        req.httpBody = httpBody

        do {
            let (respData, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: respData) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else { return nil }
            let joined = parts.compactMap { part -> String? in
                if (part["thought"] as? Bool) == true { return nil }
                return part["text"] as? String
            }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
            return joined.isEmpty ? nil : joined
        } catch {
            return nil
        }
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
            (#"(?i)hba1c|hemoglobina\s+glicosilada[^\d]{0,20}(\d(?:[.,]\d+)?)"#, "HbA1c", "%", 4.0, 5.6, 4.5, 5.3, "Metabolismo"),
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

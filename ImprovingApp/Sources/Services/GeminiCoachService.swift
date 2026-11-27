import Foundation

struct CoachToolOutcome {
    let ok: Bool
    let responseDict: [String: Any]
    let appliedAction: CoachAppliedAction?
}

struct GeminiCoachResult {
    let verdictTitle: String
    let text: String
    let bullets: [String]
    let actionLabel: String?
    let interactionId: String?
    let usedLiveCloud: Bool
    let modelUsed: String
    let appliedActions: [CoachAppliedAction]
    let followUpChips: [String]

    init(
        verdictTitle: String,
        text: String,
        bullets: [String],
        actionLabel: String?,
        interactionId: String?,
        usedLiveCloud: Bool,
        modelUsed: String,
        appliedActions: [CoachAppliedAction] = [],
        followUpChips: [String] = []
    ) {
        self.verdictTitle = verdictTitle
        self.text = text
        self.bullets = bullets
        self.actionLabel = actionLabel
        self.interactionId = interactionId
        self.usedLiveCloud = usedLiveCloud
        self.modelUsed = modelUsed
        self.appliedActions = appliedActions
        self.followUpChips = followUpChips
    }
}

/// 3-Tier Live AI Engine for Improving iOS:
/// 1. True multi-turn conversational human chat (unlimited back-and-forth turns, strictly normalized roles, natural prose, remembers context).
/// 2. 4-hour time-aware, section-specific Live AI Coaching (non-generic, non-repetitive, strictly grounded in real measured user data).
/// 3. Tiered cloud transport: User Gemini API Key (`v1beta/models/<model>:generateContent` + `v1/interactions`) -> Keyless Live Cloud LLM -> Honest zero-fabrication offline fallback.
actor GeminiCoachService {
    static let shared = GeminiCoachService()

    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

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

    let interactionsEndpoint = "https://generativelanguage.googleapis.com/v1/interactions"
    let apiRevision = "2026-05-20"
    let keylessEndpoint = "https://text.pollinations.ai/openai"
    var discoveredModelsByKeyHash: [Int: [String]] = [:]

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

    func discoverAvailableModels(apiKey: String, forceRefresh: Bool = false) async -> [String] {
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
            let (data, resp) = try await session.data(for: req)
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

    func resolveCandidateModels(apiKey: String, selectedModel: String, forceDiscovery: Bool = false) async -> [String] {
        let trimmed = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let isAuto = trimmed.isEmpty || trimmed == "auto"
        let staticFallbacks = [
            "gemini-flash-latest",
            "gemini-2.5-flash",
            "gemini-2.5-flash-lite",
            "gemini-3-flash-preview",
        ]
        var list: [String] = []
        if !isAuto {
            list.append(trimmed)
        }
        if isAuto || forceDiscovery {
            let discovered = await discoverAvailableModels(apiKey: apiKey, forceRefresh: forceDiscovery)
            list.append(contentsOf: discovered.prefix(3))
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

    static func extractGeminiErrorMessage(from data: Data, statusCode: Int) -> String {
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

    let coachingStyles = [
        "Abre con una observación fisiológica concreta conectando dos números reales del usuario y cierra con una decisión táctica para las próximas 4 horas.",
        "Habla como un entrenador de élite revisando el parte a esta hora exacta del día: directo, cálido, específico y orientado a la acción inmediata.",
        "Empieza señalando qué está respondiendo mejor o peor en su cuerpo ahora mismo y explica brevemente el porqué fisiológico antes de dar el paso práctico.",
        "Adopta un tono conversacional cercano y humano, poniendo el foco en cómo gestionar el ritmo desde esta hora hasta la siguiente ventana de 4 horas.",
        "Enfócate en el impacto práctico sobre la energía, el sistema nervioso y la noche que viene, sin sonar jamás a informe automático ni plantilla.",
        "Destaca el contraste entre los datos de hoy y cómo conviene dosificar esfuerzos, comida, hidratación o descanso justo en esta franja horaria."
    ]

    var variationCounter: Int = 0
    var recentPillTexts: [String] = []

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

        if let regex = try? NSRegularExpression(pattern: "^(Opini[oó]n\\s*(de\\s*)?(IA)?\\s*(\\([^)]*\\))?\\s*:\\s*|Veredicto\\s*:\\s*|An[aá]lisis\\s*:\\s*)", options: [.caseInsensitive]) {
            cleaned = regex.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: "")
        }
        // Preserve numbered lists like "1) Haz esto" -> "1. Haz esto" before parenthetical cleanup
        if let listRegex = try? NSRegularExpression(pattern: "(^|\\n)(\\s*\\d+)\\)\\s+") {
            cleaned = listRegex.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: "$1$2. ")
        }
        // Keep short clinical/biomarker codes like "Vitamina D (25-OH)" clean without ugly double commas
        if let codeParenRegex = try? NSRegularExpression(pattern: "\\s*\\(([A-Za-z0-9/\\-\\+%]{1,10})\\)") {
            cleaned = codeParenRegex.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: " $1")
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
            .replacingOccurrences(of: ",;", with: ";")
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

    func describeLocalMoment(_ date: Date) -> (hhmm: String, periodName: String, guidance: String, blockIndex: Int) {
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
}

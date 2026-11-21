import Foundation

actor GeminiCoachService {
    static let shared = GeminiCoachService()

    private var variationCounter: Int = 0
    private var recentPillTexts: [String] = []

    func nextSeed() -> Int {
        variationCounter += 1
        return variationCounter
    }

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
        let validData = hasData && !cleanVal.isEmpty && !cleanVal.hasPrefix("--")

        let headlines = [
            "LECTURA EN VIVO DE TU IA",
            "CONTEXTO FISIOLÓGICO DE HOY",
            "QUÉ DICE ESTE DATO DE TI",
            "CRUCE CON TU RECUPERACIÓN",
            "VISIÓN DE TU ENTRENADOR",
        ]
        let headline = headlines[abs(s) % headlines.count]

        if !validData {
            let shortNoData = "\(nameLead)aún no hay lecturas de \(metricTitle.lowercased()) hoy. Tu referencia personal es \(cleanRange); sincroniza Apple Health, WHOOP o importa tu archivo."
            let fullNoData = "\(nameLead)todavía no hay muestras reales de \(metricTitle.lowercased()) registradas hoy en tu dispositivo. Prefiero no inventar cifras: para tus \(Int(profile.ageYears)) años y \(Int(profile.weightKg)) kg, tu corredor esperado es \(cleanRange). En cuanto conectes Apple Health/WHOOP o importes tu historial verás la lectura exacta."
            return MetricFloatingAiInsight(
                shortPillText: "Esperando lectura real",
                expandedHeadline: headline,
                shortExpandedMessage: shortNoData,
                expandedMessage: fullNoData,
                structureIndex: s % 5,
                variationSeed: s
            )
        }

        let pills = [
            "\(cleanVal) · Lectura estable",
            "\(cleanVal) · Dentro de tu línea",
            "\(cleanVal) · Pulso fisiológico claro",
            "\(cleanVal) · Ritmo optimizado",
            "\(cleanVal) · Revisado por tu IA",
        ]
        let pillText = pills.first { !recentPillTexts.contains($0) } ?? pills[abs(s) % pills.count]
        recentPillTexts.append(pillText)
        if recentPillTexts.count > 8 { recentPillTexts.removeFirst() }

        let recText = recoveryPct.map { "\($0)% de recuperación" } ?? "tu recuperación actual"
        let hrvText = hrvMs.map { String(format: "%.1f ms de VFC", $0) } ?? "tu tono vagal"
        let rhrText = restingHrBpm.map { String(format: "%.1f ppm de reposo", $0) } ?? "tu pulso basal"
        let energyText = energyPct.map { "\($0)% de energía" } ?? "tu batería corporal"
        let stressText = stressScore.map { "estrés en \($0)/100" } ?? "estrés estable"
        let strainText = strainPct.map { "\($0)% de esfuerzo" } ?? "carga controlada"
        let sleepText = sleepDurationText ?? "tu descanso nocturno"

        let actions = [
            "Mantén hidratación sobre \(String(format: "%.1f", norms.hydrationGoalLiters)) L hoy y respeta tu zona objetivo de esfuerzo.",
            "Corta estimulantes tras las 15:00 y cena ligero para consolidar este patrón mañana.",
            "Tienes buen margen para entrenar con control técnico o meter bloque aeróbico en zona 2.",
            "Busca tus \(String(format: "%.1f", norms.sleepTargetHours)) h de sueño esta noche para proteger tu recuperación."
        ]
        let action = actions[abs(s * 3) % actions.count]

        let shortMsg = "\(cleanVal) hoy (\(metricTitle.lowercased())), en línea con \(recText). \(action)"
        let fullMsg = "Al cruzar este \(cleanVal) de \(metricTitle.lowercased()) con tu \(recText), \(hrvText) y \(rhrText), tu sistema nervioso y cardiovascular responden de forma coherente frente a tu banda de \(cleanRange). Con \(energyText), \(strainText), \(stressText) y \(sleepText), \(action.prefix(1).lowercased() + action.dropFirst())"

        return MetricFloatingAiInsight(
            shortPillText: pillText,
            expandedHeadline: headline,
            shortExpandedMessage: shortMsg,
            expandedMessage: fullMsg,
            structureIndex: s % 5,
            variationSeed: s
        )
    }

    func generateLiveCoachReply(
        prompt: String,
        apiKey: String,
        selectedModel: String,
        contextSummary: String
    ) async -> String {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            if let geminiReply = await callGeminiApi(prompt: prompt, apiKey: trimmedKey, model: selectedModel, context: contextSummary) {
                return geminiReply
            }
        }
        return buildOfflineCoachReply(prompt: prompt, context: contextSummary)
    }

    private func callGeminiApi(prompt: String, apiKey: String, model: String, context: String) async -> String? {
        let safeModel = model.isEmpty ? "gemini-2.5-flash" : model
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(safeModel):generateContent?key=\(apiKey)") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 18
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let sysPrompt = """
        Eres el coach fisiológico de Improving en iPhone. Hablas en español natural, directo y cercano, sin usar asteriscos ni negritas markdown. Usa exclusivamente los datos reales proporcionados del usuario:
        \(context)
        """
        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": sysPrompt]]],
            "contents": [["role": "user", "parts": [["text": prompt]]]],
            "generationConfig": ["temperature": 0.65, "maxOutputTokens": 420]
        ]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let candidates = json["candidates"] as? [[String: Any]],
               let content = candidates.first?["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]],
               let text = parts.first?["text"] as? String {
                return text.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            return nil
        }
        return nil
    }

    private func buildOfflineCoachReply(prompt: String, context: String) -> String {
        let low = prompt.lowercased()
        if low.contains("sueño") || low.contains("dorm") {
            return "Revisando tu descanso en \(context): prioriza mantener un horario regular de acostarte, cena al menos 2 horas antes y evita pantallas los últimos 30 minutos para maximizar sueño profundo y REM."
        }
        if low.contains("entreno") || low.contains("entrenar") || low.contains("esfuerzo") || low.contains("fuerza") {
            return "Con tu contexto actual (\(context)), ajusta la intensidad al rango óptimo de tu anillo de esfuerzo: si estás por encima del 70% de recuperación puedes apretar, si estás por debajo prioriza técnica o zona 2."
        }
        return "Basándome en tus métricas reales actuales (\(context)), mantén una progresión estable de carga, hidrátate bien durante la jornada y vigila tu VFC y pulso en reposo al despertar."
    }
}

import Foundation

extension GeminiCoachService {
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
        selectedModel: String,
        allowCloudAI: Bool = true,
        allowKeylessFallback: Bool = false,
        tone: CoachPersonalityTone = .directo,
        detailLevel: CoachDetailLevel = .equilibrado
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
            case .diario:
                noDataBody = "Marca tus hábitos de hoy, añade una nota o registra tus comidas para que cruce tu Diario con tu nutrición, analíticas, clima y biometría."
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
        PERSONALIDAD CONFIGURADA POR EL USUARIO: \(tone.systemDirective)
        NIVEL DE DETALLE CONFIGURADO: \(detailLevel.systemDirective)

        CONSCIENCIA HORARIA:
        - \(dayFrame)

        REGLAS DE CALIDAD Y ANTI-GENÉRICOS:
        1. Cita al menos 2 cifras REALES concretas del usuario del bloque de datos de este apartado y explica qué implican para su cuerpo ahora mismo.
        2. \(styleAngle)
        3. \(avoidRepeat)
        4. PROHIBIDO usar frases vacías como "escucha a tu cuerpo", "mantén un enfoque equilibrado", "lectura real del día:" ni paréntesis ().
        5. PROHIBIDO inventar o suponer cualquier métrica que aparezca como "NO_DISPONIBLE".
        6. Habla a \(name) en español natural respetando estrictamente la personalidad y el nivel de detalle elegidos.

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
        if allowCloudAI && !cleanKey.isEmpty {
            let candidates = await resolveCandidateModels(apiKey: cleanKey, selectedModel: model, forceDiscovery: model == "auto")
            for m in candidates.prefix(3) {
                let res = await callGeminiJsonOneShot(prompt: userPrompt, sysPrompt: sysPrompt, apiKey: cleanKey, model: m)
                if let raw = res.text,
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
                if res.statusCode == 401 || res.statusCode == 403 { break }
            }
        }

        // Tier 2: Optional Keyless Cloud LLM (disabled by default for privacy)
        if allowCloudAI && allowKeylessFallback,
           let raw = await callKeylessCloudOneShot(prompt: userPrompt, sysPrompt: sysPrompt, seed: seed + moment.blockIndex * 19),
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

    func callGeminiJsonOneShot(prompt: String, sysPrompt: String, apiKey: String, model: String) async -> (text: String?, statusCode: Int) {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else { return (nil, 0) }
        var genConfig: [String: Any] = [
            "temperature": 0.85,
            "maxOutputTokens": 1400,
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
        let resp = await sendSingleGeminiGenerateRequest(url: url, apiKey: apiKey, body: body, timeout: 20)
        guard let parts = resp.parts else { return (nil, resp.statusCode) }
        let joined = parts.compactMap { part -> String? in
            if (part["thought"] as? Bool) == true { return nil }
            return part["text"] as? String
        }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        return (joined.isEmpty ? nil : joined, resp.statusCode)
    }

    func callKeylessCloudOneShot(prompt: String, sysPrompt: String, seed: Int) async -> String? {
        guard let url = URL(string: keylessEndpoint) else { return nil }
        for attempt in 0..<2 {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 22
            req.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("Improving-iOS/2.0", forHTTPHeaderField: "User-Agent")

            let body: [String: Any] = [
                "model": "openai-fast",
                "seed": seed + attempt,
                "temperature": 0.9,
                "messages": [
                    ["role": "system", "content": sysPrompt],
                    ["role": "user", "content": prompt]
                ]
            ]
            guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { continue }
            req.httpBody = httpBody

            do {
                let (respData, resp) = try await session.data(for: req)
                guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                      let root = try JSONSerialization.jsonObject(with: respData) as? [String: Any],
                      let choices = root["choices"] as? [[String: Any]],
                      let msg = choices.first?["message"] as? [String: Any],
                      let content = msg["content"] as? String,
                      !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    if attempt == 0 { try? await Task.sleep(nanoseconds: 350_000_000) }
                    continue
                }
                return content
            } catch {
                if attempt == 0 { try? await Task.sleep(nanoseconds: 350_000_000) }
                continue
            }
        }
        return nil
    }

    func parseSectionCoachingJson(
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

    func buildLocalTimeAwareSectionCoaching(
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
        case .diario:
            let heads = ["Valoración causal del Diario", "Cruce hábitos, comida y VFC", "Lectura del día en tu Diario"]
            emoji = "📓"
            headline = heads[idx]
            body = isViewingToday
                ? "\(lead)cruzando tu Diario con tu biometría, nutrición y analíticas reales destaca \(factsJoined). Protege tu ventana de cafeína y cena temprana para impulsar la recuperación de mañana."
                : "\(lead)el \(selectedDateIso) tu Diario combinó \(factsJoined). Revisa tus correlaciones de 30 días y 6 meses para consolidar qué hábitos te hacen rendir mejor."
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

    static func defaultEmoji(for section: CoachingSection) -> String {
        switch section {
        case .hoy: return "✨"
        case .esfuerzo: return "🔥"
        case .recuperacion: return "🌿"
        case .sueno: return "🌙"
        case .estres: return "🧠"
        case .energia: return "⚡"
        case .fitness: return "🏋️"
        case .diario: return "📓"
        }
    }

    static func sectionFocusDirective(for section: CoachingSection) -> String {
        switch section {
        case .hoy:
            return "Visión integradora del día: conecta recuperación, esfuerzo, sueño y batería de energía para darle la prioridad exacta para las próximas 4 horas."
        case .esfuerzo:
            return "HABLA PRINCIPALMENTE DE ESFUERZO Y CARGA FÍSICA: porcentaje de esfuerzo frente a su rango objetivo óptimo, entrenamientos realizados, pulso medio, zonas cardíacas, pasos, calorías activas y el impacto térmico del clima real si hay calor o humedad."
        case .recuperacion:
            return "HABLA PRINCIPALMENTE DE RECUPERACIÓN Y SISTEMA NERVIOSO AUTÓNOMO: porcentaje de recuperación, VFC nocturna frente a su línea base personal, FC en reposo durmiendo, frecuencia respiratoria, SpO2, temperatura de muñeca e hidratación climática si aplica."
        case .sueno:
            return "HABLA PRINCIPALMENTE DE SUEÑO: duración real, hora de acostarse y despertar, eficiencia, sueño profundo y REM, latencia, disminución de la FC nocturna y cómo proteger el descanso de la próxima noche."
        case .estres:
            return "HABLA PRINCIPALMENTE DE ESTRÉS FISIOLÓGICO: media, pico máximo, mínimo, tiempo en estrés alto frente a bajo, estrés nocturno y estrategias prácticas concretas para bajar activación simpática."
        case .energia:
            return "HABLA PRINCIPALMENTE DE LA BATERÍA DE ENERGÍA CONTINUA: con qué porcentaje arrancó el día desde la noche anterior, cuánto recargó al dormir, cuánto lleva gastado hasta esta hora y cómo dosificar la batería restante."
        case .fitness:
            return "HABLA PRINCIPALMENTE DE FITNESS Y ENTRENAMIENTO: carga cardiovascular y muscular de 7 días, volumen de los últimos 30 días, VO2 máx., recuperación de FC, zonas cardíacas y qué tipo de sesión conviene hoy."
        case .diario:
            return "VALORACIÓN CAUSAL INTEGRAL DEL DIARIO: cruza los hábitos marcados hoy, la nota del día, las correlaciones de 30 días y 6 meses, la nutrición real (proteína, hora de cena, cafeína residual y Carb Cycling), las analíticas de sangre guardadas y el clima local para explicar qué está impulsando o frenando su VFC, sueño profundo y recuperación."
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
            ? "manteniendo seguimiento sobre tu referencia personal de \(cleanRange)"
            : "cruzado con \(realParts.prefix(3).joined(separator: ", "))"

        let moment = describeLocalMoment(Date())
        let isLowRec = (recoveryPct ?? 70) < 42
        let isHighStress = (stressScore ?? 30) >= 62
        let action: String = {
            if isLowRec {
                return "Con recuperación baja hoy, prioriza movilidad o Zona 1–2 suave, añade electrolitos y adelanta el descanso nocturno."
            }
            if isHighStress {
                return "Tu activación simpática va elevada; 4 minutos de respiración con exhalación doble bajarán tu pulso antes del siguiente bloque."
            }
            switch moment.blockIndex {
            case 0, 5:
                return "En esta franja nocturna evita cenas copiosas y pantallas brillantes para consolidar sueño profundo y VFC mañana."
            case 1, 2:
                return "Aprovecha esta ventana matinal para hidratarte hacia los \(String(format: "%.1f", locale: Locale(identifier: "es_ES"), norms.hydrationGoalLiters)) L y concentrar tu estímulo principal del día."
            case 3:
                return "A mitad de jornada prioriza proteína limpia y un paseo breve post-comida para sostener tu batería sin picos de estrés."
            default:
                return "En esta franja de tarde vigila tu corte personal de cafeína y ajusta el esfuerzo restante según tus sensaciones reales."
            }
        }()

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

import Foundation
import Combine
import SwiftUI
import UIKit
import AppleWatchReader
import WhoopBLE
import WhoopProtocol

extension ImprovingStore {
    // MARK: - AI Coach Context & Multi-Turn Chat

    func buildBiometricContextJson() -> (json: String, highlights: [String]) {
        let av = dataAvailability
        let d = currentDaySummary
        var highlights: [String] = []
        if av.hasRecoveryData { highlights.append("recuperación del \(recoveryPercent)%") }
        if av.hasStrainData { highlights.append("esfuerzo del \(strainPercent)%") }
        if av.hasSleepData { highlights.append("sueño de \(sleepDurationText) con puntuación \(sleepPercent)%") }
        if av.hasHrvData { highlights.append(String(format: "VFC de %.1f ms", locale: Locale(identifier: "es_ES"), hrvMs)) }
        if av.hasRestingHrData { highlights.append(String(format: "FC en reposo de %.1f ppm", locale: Locale(identifier: "es_ES"), restingHrBpm)) }
        if av.hasRespData { highlights.append(String(format: "FR de %.1f rpm", locale: Locale(identifier: "es_ES"), respRateRpm)) }
        if let sp = spo2Value { highlights.append(String(format: "SpO2 de %.1f%%", locale: Locale(identifier: "es_ES"), sp)) }
        if av.hasStressData { highlights.append("estrés actual de \(displayStressScore) y media diaria de \(stressAvg ?? stressScore) sobre 100") }
        if av.hasEnergyData { highlights.append("batería de energía al \(energyPercent)%") }
        if let steps = stepsCount { highlights.append("\(steps) pasos") }

        let dayJournal = journalCheckinsByDate[selectedDateIso] ?? [:]
        let dayHabitTimes = journalEventTimesByDate[selectedDateIso] ?? [:]
        let allManualSpecs = allCatalogAndCustomEntries.filter { !$0.isAuto }
        let yesHabits = allManualSpecs.filter { dayJournal[$0.id] == .yes }.map { spec -> String in
            if let t = dayHabitTimes[spec.id], !t.isEmpty {
                return "\(spec.title) (\(t))"
            }
            return spec.title
        }
        let noHabits = allManualSpecs.filter { dayJournal[$0.id] == .no }.map(\.title)
        let noteToday = journalNote(for: selectedDateIso)
        if !noteToday.isEmpty {
            highlights.append("nota del diario: «\(noteToday)»")
        }
        if totalCaloriesToday > 0 {
            highlights.append("nutrición hoy: \(totalCaloriesToday) kcal (\(totalProteinToday)g P, \(totalCarbsToday)g C, \(totalFatToday)g G)")
        }

        let recentNotes: [String: String] = {
            var dict: [String: String] = [:]
            for item in trailingCalendarSummaries(days: 7) {
                let n = (journalNotesByDate[item.iso] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !n.isEmpty { dict[item.iso] = n }
            }
            return dict
        }()

        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: userProfile)
        let perfil: [String: Any] = redactPIIFromAI ? [
            "nombre": "Usuario",
            "edad": Int(userProfile.effectiveAgeYears.rounded(.down)),
            "sexo": userProfile.sex.rawValue,
            "peso_kg": latestBodyWeightKg ?? userProfile.weightKg,
            "altura_cm": userProfile.heightCm,
            "imc": norms.bmi,
            "fc_max_tanaka": norms.maxHrBpm,
            "vfc_esperada_ms": norms.hrvExpectedMs,
            "meta_sueno_h": norms.sleepTargetHours,
            "meta_hidratacion_l": norms.hydrationGoalLiters
        ] : [
            "nombre": userProfile.displayFirstName.isEmpty ? "Usuario" : userProfile.displayFirstName,
            "nombre_completo": userProfile.fullName.isEmpty ? "Usuario" : userProfile.fullName,
            "fecha_nacimiento": userProfile.birthDateIso ?? "NO_INDICADA",
            "edad": Int(userProfile.effectiveAgeYears.rounded(.down)),
            "sexo": userProfile.sex.rawValue,
            "peso_kg": latestBodyWeightKg ?? userProfile.weightKg,
            "altura_cm": userProfile.heightCm,
            "imc": norms.bmi,
            "fc_max_tanaka": norms.maxHrBpm,
            "vfc_esperada_ms": norms.hrvExpectedMs,
            "meta_sueno_h": norms.sleepTargetHours,
            "meta_hidratacion_l": norms.hydrationGoalLiters
        ]

        var metricas: [String: Any] = [:]
        metricas["recuperacion_pct"] = av.hasRecoveryData ? (recoveryPercent as Any) : "NO_DISPONIBLE"
        metricas["esfuerzo_pct"] = av.hasStrainData ? (strainPercent as Any) : "NO_DISPONIBLE"
        metricas["strain_21"] = av.hasStrainData ? (strain21 as Any) : "NO_DISPONIBLE"
        metricas["sueno_pct"] = av.hasSleepData ? (sleepPercent as Any) : "NO_DISPONIBLE"
        metricas["sueno_duracion"] = av.hasSleepData ? (sleepDurationText as Any) : "NO_DISPONIBLE"
        metricas["sueno_profundo_min"] = (d?.deepMinutes ?? 0) > 0 ? ((d?.deepMinutes ?? 0) as Any) : "NO_DISPONIBLE"
        metricas["sueno_rem_min"] = (d?.remMinutes ?? 0) > 0 ? ((d?.remMinutes ?? 0) as Any) : "NO_DISPONIBLE"
        metricas["vfc_ms"] = av.hasHrvData ? (hrvMs as Any) : "NO_DISPONIBLE"
        metricas["fc_reposo_ppm"] = av.hasRestingHrData ? (restingHrBpm as Any) : "NO_DISPONIBLE"
        metricas["frecuencia_respiratoria_rpm"] = av.hasRespData ? (respRateRpm as Any) : "NO_DISPONIBLE"
        metricas["spo2_pct"] = spo2Value.map { $0 as Any } ?? "NO_DISPONIBLE"
        metricas["temperatura_muneca_c"] = wristTempAbsoluteC.map { $0 as Any } ?? "NO_DISPONIBLE"
        metricas["estres_actual"] = av.hasStressData ? (displayStressScore as Any) : "NO_DISPONIBLE"
        metricas["estres_medio"] = av.hasStressData ? ((stressAvg ?? stressScore) as Any) : "NO_DISPONIBLE"
        metricas["energia_pct"] = av.hasEnergyData ? (energyPercent as Any) : "NO_DISPONIBLE"
        metricas["pasos"] = stepsCount.map { $0 as Any } ?? "NO_DISPONIBLE"
        metricas["vo2_max"] = latestVo2Max.map { $0 as Any } ?? "NO_DISPONIBLE"
        if workoutsToday.isEmpty {
            metricas["entrenamientos_hoy"] = "NINGUNO"
        } else {
            metricas["entrenamientos_hoy"] = workoutsToday.map { w -> [String: Any] in
                [
                    "id": w.id,
                    "titulo": w.title,
                    "horario": w.timeRange,
                    "duracion_min": w.durationMin,
                    "kcal": w.kcal,
                    "categoria": w.categoryLabel
                ]
            }
        }

        let habitCatalogForAi = allManualSpecs.map { "\($0.id): \($0.title)" }
        let diarioHoy: [String: Any] = [
            "marcados_si": yesHabits,
            "marcados_no": noHabits,
            "horarios_habitos_hoy": dayHabitTimes,
            "estado_animo_1_a_5": journalMoodByDate[selectedDateIso].map { $0 as Any } ?? "NO_REGISTRADO",
            "nota_del_dia": redactPIIFromAI ? "OMITIDA_POR_PRIVACIDAD" : (noteToday.isEmpty ? "SIN_NOTA" : noteToday),
            "notas_recientes_7d": redactPIIFromAI ? [:] : recentNotes,
            "habitos_disponibles": habitCatalogForAi
        ]

        let cal = Calendar.current
        let todayIsoStr = isoFormatter.string(from: Date())
        let yesterdayIsoStr = isoFormatter.string(from: cal.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        let yesterdayMeals = mealsByDate[yesterdayIsoStr] ?? []
        let goalsNow = effectiveNutritionGoals

        let nutricionHoy: [String: Any] = [
            "kcal_ingeridas": totalCaloriesToday,
            "proteina_g": totalProteinToday,
            "carbos_g": totalCarbsToday,
            "grasas_g": totalFatToday,
            "objetivos_actuales": [
                "kcal": goalsNow.kcal,
                "proteina_g": goalsNow.proteinG,
                "carbos_g": goalsNow.carbsG,
                "grasas_g": goalsNow.fatG
            ],
            "calidad_media": foodQualityScore.map { $0 as Any } ?? "SIN_COMIDAS",
            "hidratacion_ml": Int(totalHydrationTodayMl.rounded()),
            "cafeina_mg": Int(totalCaffeineTodayMg.rounded()),
            "alcohol_bebidas": totalAlcoholTodayDrinks,
            "comidas_registradas": mealsToday.map { m -> [String: Any] in
                [
                    "id": m.id,
                    "hora": m.timeLabel,
                    "titulo": m.title,
                    "kcal": m.kcal,
                    "proteina_g": m.proteinG,
                    "carbos_g": m.carbsG,
                    "grasas_g": m.fatG,
                    "calidad": m.qualityScore
                ]
            },
            "comidas_ayer": yesterdayMeals.map { m -> [String: Any] in
                [
                    "id": m.id,
                    "fecha": yesterdayIsoStr,
                    "hora": m.timeLabel,
                    "titulo": m.title,
                    "kcal": m.kcal
                ]
            }
        ]

        let latestLabsSummary: [[String: Any]] = latestBiomarkersByName.prefix(14).map { b in
            [
                "nombre": b.name,
                "valor": b.value,
                "unidad": b.unit,
                "estado": b.status.rawValue,
                "categoria": b.category
            ]
        }

        let bioSnap = biologicalAgeSnapshot()
        let edadBiologicaDict: [String: Any] = [
            "edad_biologica_anos": bioSnap.hasData ? bioSnap.eval.bioAgeYears : bioSnap.eval.chronoAgeYears,
            "edad_cronologica_anos": bioSnap.eval.chronoAgeYears,
            "diferencia_total_anos": bioSnap.hasData ? bioSnap.eval.deltaYears : 0.0,
            "impacto_sueno_anos": bioSnap.eval.sleepDelta,
            "impacto_actividad_anos": bioSnap.eval.activityDelta,
            "impacto_fitness_anos": bioSnap.eval.fitnessDelta,
            "impacto_vfc_anos": bioSnap.eval.autonomicDelta,
            "impacto_cuerpo_anos": bioSnap.eval.bodyDelta,
            "impacto_analiticas_anos": bioSnap.eval.bloodLabsDelta
        ]

        let nowFmt = DateFormatter()
        nowFmt.dateFormat = "HH:mm"
        var payload: [String: Any] = [
            "hora_local_actual": nowFmt.string(from: Date()),
            "fecha_hoy": todayIsoStr,
            "fecha_ayer": yesterdayIsoStr,
            "fecha_seleccionada": selectedDateIso,
            "origen_datos": hasImportedOrPairedRealData ? "Apple Health / Sensores reales" : "Modo vista previa",
            "perfil": perfil,
            "metricas_hoy": metricas,
            "edad_biologica": edadBiologicaDict,
            "diario_hoy": diarioHoy,
            "nutricion_hoy": nutricionHoy
        ]
        if !redactPIIFromAI && !latestLabsSummary.isEmpty {
            payload["analiticas_recientes"] = latestLabsSummary
        }

        // Compact JSON (no .prettyPrinted) cuts Gemini input tokens by ~25-35%!
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
           let str = String(data: data, encoding: .utf8) {
            return (str, highlights)
        }
        return ("{}", highlights)
    }

    /// Context-aware suggested questions adapted to today's actual physiological metrics!
    var dynamicCoachSuggestions: [CoachDynamicSuggestion] {
        var list: [CoachDynamicSuggestion] = []
        let avail = dataAvailability
        let debt = currentDaySummary?.sleepDebtMinutes ?? 0

        if avail.hasRecoveryData && recoveryPercent < 50 {
            list.append(CoachDynamicSuggestion(
                id: "low_rec",
                icon: "heart.text.square.fill",
                title: "Recuperación baja (\(recoveryPercent)%)",
                subtitle: "¿Qué hago hoy para remontar?",
                prompt: "Hoy tengo la recuperación en \(recoveryPercent)%. Analiza mis constantes reales y dime cómo plantear el día y el entrenamiento."
            ))
        } else if avail.hasRecoveryData && recoveryPercent >= 72 {
            list.append(CoachDynamicSuggestion(
                id: "high_rec",
                icon: "flame.fill",
                title: "Recuperación alta (\(recoveryPercent)%)",
                subtitle: "Plan de sesión intensa",
                prompt: "Hoy amanecí con \(recoveryPercent)% de recuperación. ¿Qué entrenamiento me recomiendas aprovechar según mi carga y frescura muscular?"
            ))
        } else {
            list.append(CoachDynamicSuggestion(
                id: "train_today",
                icon: "figure.run",
                title: "¿Entreno fuerte hoy?",
                subtitle: "Según mi recuperación real",
                prompt: "¿Debería entrenar fuerte hoy o ir suave según mis datos reales?"
            ))
        }

        if debt >= 35 {
            list.append(CoachDynamicSuggestion(
                id: "sleep_debt",
                icon: "moon.zzz.fill",
                title: "Deuda de sueño (\(debt) min)",
                subtitle: "Cómo recuperarla esta semana",
                prompt: "Tengo \(debt) minutos de deuda de sueño y dormí \(sleepDurationText). Dame un plan realista para recuperarla sin arruinar mis horarios."
            ))
        } else {
            list.append(CoachDynamicSuggestion(
                id: "sleep_check",
                icon: "moon.stars.fill",
                title: "Analizar mi sueño",
                subtitle: "Fases y descanso real",
                prompt: "Analiza mi última noche de sueño y dime qué puedo mejorar hoy"
            ))
        }

        if let nutScore = foodQualityScore, nutScore < 65 {
            list.append(CoachDynamicSuggestion(
                id: "nut_fix",
                icon: "fork.knife",
                title: "Mejorar mi nutrición (\(nutScore))",
                subtitle: "Qué cenar hoy para equilibrar",
                prompt: "Mi puntuación de nutrición hoy está en \(nutScore) con \(totalCaloriesToday) kcal y \(totalProteinToday) g de proteína. ¿Qué cena rápida me ayuda a cuadrar el día?"
            ))
        } else if !latestBiomarkersByName.isEmpty {
            list.append(CoachDynamicSuggestion(
                id: "lab_review",
                icon: "cross.case.fill",
                title: "Revisar mi analítica",
                subtitle: "\(latestBiomarkersByName.count) biomarcadores guardados",
                prompt: "Revisa los biomarcadores de mi última analítica junto con mi sueño y recuperación, y dime qué prioridades tengo."
            ))
        } else {
            list.append(CoachDynamicSuggestion(
                id: "open_food",
                icon: "fork.knife",
                title: "¿Qué me conviene cenar hoy?",
                subtitle: "Adaptado a mi gasto real",
                prompt: "Con mi actividad y comida de hoy, ¿qué cena me recomiendas para dormir mejor y recuperar bien?"
            ))
        }

        return list
    }

    func sendCoachPrompt(_ rawPrompt: String, jpegImageData: Data? = nil, attachedPhotoFilename: String? = nil) {
        let trimmed = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = trimmed.isEmpty && jpegImageData != nil ? "Analiza esta imagen en relación con mis datos reales de salud y entrenamiento." : trimmed
        guard !prompt.isEmpty, !isCoachThinking else { return }

        let now = Date()
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"
        let tsLabel = timeFmt.string(from: now)

        let historySnap = Array(coachMessages.suffix(16))
        let userMsg = CoachChatMessage(
            id: UUID().uuidString,
            isUser: true,
            text: prompt,
            timestampLabel: tsLabel,
            isSuggestionChip: false,
            attachedPhotoFilename: attachedPhotoFilename
        )
        coachMessages.append(userMsg)
        syncCurrentChatIntoThreads(updatedAtLabel: tsLabel)
        isCoachThinking = true
        lastCoachErrorMessage = nil

        let ctx = buildBiometricContextJson()
        let key = geminiApiKey
        let model = selectedGeminiModel
        let allowCloud = cloudAIEnabled
        let allowKeyless = allowKeylessAIFallback
        let userName = redactPIIFromAI ? "Usuario" : userProfile.userName
        let missing = dataAvailability.missingCategoryNames
        let prevId = activeCoachInteractionId
        let originThreadId = activeCoachThreadId

        coachReplyTask?.cancel()
        coachReplyTask = Task { [weak self] in
            let executor: @Sendable (String, String) async -> (responseJson: String, appliedAction: CoachAppliedAction?) = { toolName, argsJson in
                await MainActor.run {
                    guard let self, self.activeCoachThreadId == originThreadId else {
                        return ("{\"ok\":false,\"error\":\"thread_changed\"}", nil)
                    }
                    return self.executeCoachToolCall(
                        name: toolName,
                        argsJson: argsJson,
                        attachedPhotoFilename: attachedPhotoFilename
                    )
                }
            }
            let result = await GeminiCoachService.shared.askLiveCoach(
                prompt: prompt,
                apiKey: key,
                selectedModel: model,
                userName: userName,
                currentDate: now,
                biometricContextJson: ctx.json,
                availableHighlights: ctx.highlights,
                missingCategories: missing,
                history: historySnap,
                previousInteractionId: prevId,
                jpegImageData: jpegImageData,
                allowCloudAI: allowCloud,
                allowKeylessFallback: allowKeyless,
                actionExecutor: executor
            )
            await MainActor.run {
                guard let self, !Task.isCancelled else { return }
                // Prevent cross-thread injection if the user switched threads mid-request!
                guard self.activeCoachThreadId == originThreadId else { return }
                self.isCoachThinking = false
                if !result.usedLiveCloud && allowCloud && !key.isEmpty {
                    self.lastCoachErrorMessage = "No se pudo conectar con Gemini en vivo. Respuesta local mostrada."
                }
                if let newId = result.interactionId {
                    self.activeCoachInteractionId = newId
                }
                if !result.appliedActions.isEmpty {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    self.publishWidgetSnapshot(triggerReload: true, forceReload: false)
                }
                let replyFmt = DateFormatter()
                replyFmt.dateFormat = "HH:mm"
                let replyTs = replyFmt.string(from: Date())
                self.coachMessages.append(
                    CoachChatMessage(
                        id: UUID().uuidString,
                        isUser: false,
                        verdictTitle: result.verdictTitle.isEmpty ? nil : result.verdictTitle,
                        text: result.text,
                        bullets: result.bullets,
                        timestampLabel: replyTs,
                        isSuggestionChip: false,
                        modelUsed: result.modelUsed,
                        appliedActions: result.appliedActions
                    )
                )
                self.syncCurrentChatIntoThreads(updatedAtLabel: replyTs)
            }
        }
    }

    func cancelCoachReply() {
        coachReplyTask?.cancel()
        coachReplyTask = nil
        isCoachThinking = false
    }

    // MARK: - Agentic AI Tool Executor & 1-Tap Undo Engine

    func parseStrictCoachDateIso(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return selectedDateIso
        }
        let low = raw.lowercased()
        if low == "hoy" || low == "today" {
            return isoFormatter.string(from: Date())
        }
        if low == "ayer" || low == "yesterday" {
            let y = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
            return isoFormatter.string(from: y)
        }
        if low == "mañana" || low == "manana" || low == "tomorrow" {
            let t = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            return isoFormatter.string(from: t)
        }
        // Strictly validate yyyy-MM-dd format (reject invalid dates like 2026-13-45 or 23/11/2026!)
        let parts = raw.split(separator: "-")
        if parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
           let dt = isoFormatter.date(from: raw),
           isoFormatter.string(from: dt) == raw {
            return raw
        }
        return nil
    }

    func resolveCoachDateIso(_ raw: String?) -> String {
        parseStrictCoachDateIso(raw) ?? selectedDateIso
    }

    func normalizeCoachHHmm(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let cleaned = raw
            .replacingOccurrences(of: "h", with: ":")
            .replacingOccurrences(of: "H", with: ":")
            .replacingOccurrences(of: ".", with: ":")
            .trimmingCharacters(in: CharacterSet(charactersIn: " :"))
        let parts = cleaned.split(separator: ":")
        if parts.count >= 2, let h = Int(parts[0]), let m = Int(parts[1]),
           (0...23).contains(h), (0...59).contains(m) {
            return String(format: "%02d:%02d", h, m)
        }
        if parts.count == 1, let h = Int(parts[0]), (0...23).contains(h) {
            return String(format: "%02d:00", h)
        }
        return nil
    }

    func encodeToolResponse(_ dict: [String: Any]) -> String {
        if let d = try? JSONSerialization.data(withJSONObject: dict),
           let s = String(data: d, encoding: .utf8) {
            return s
        }
        return "{\"ok\":true}"
    }

    func executeCoachToolCall(
        name: String,
        argsJson: String,
        attachedPhotoFilename: String? = nil
    ) -> (responseJson: String, appliedAction: CoachAppliedAction?) {
        let args: [String: Any] = {
            guard let d = argsJson.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
            return obj
        }()

        func str(_ k: String) -> String? {
            (args[k] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func intVal(_ k: String) -> Int? {
            if let i = args[k] as? Int { return i }
            if let d = args[k] as? Double { return Int(d.rounded()) }
            if let n = args[k] as? NSNumber { return Int(n.doubleValue.rounded()) }
            if let s = args[k] as? String, let d = Double(s.replacingOccurrences(of: ",", with: ".")) { return Int(d.rounded()) }
            return nil
        }
        func dblVal(_ k: String) -> Double? {
            if let d = args[k] as? Double { return d }
            if let i = args[k] as? Int { return Double(i) }
            if let n = args[k] as? NSNumber { return n.doubleValue }
            if let s = args[k] as? String { return Double(s.replacingOccurrences(of: ",", with: ".")) }
            return nil
        }
        func boolVal(_ k: String) -> Bool? {
            if let b = args[k] as? Bool { return b }
            if let n = args[k] as? NSNumber { return n.boolValue }
            if let s = args[k] as? String { return s.lowercased() == "true" || s == "1" }
            return nil
        }
        func nowHHmm() -> String {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return f.string(from: Date())
        }
        func fold(_ s: String) -> String {
            s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        switch name {
        case "log_meal":
            guard let dateIso = parseStrictCoachDateIso(str("date_iso")) else {
                return (encodeToolResponse(["ok": false, "error": "Fecha inválida. Usa formato yyyy-MM-dd, 'hoy' o 'ayer'."]), nil)
            }
            let title = str("title") ?? "Comida"
            let kcal = max(0, intVal("kcal") ?? 0)
            let p = max(0, intVal("protein_g") ?? 0)
            let c = max(0, intVal("carbs_g") ?? 0)
            let f = max(0, intVal("fat_g") ?? 0)
            let timeLabel = normalizeCoachHHmm(str("time_hhmm")) ?? nowHHmm()
            let quality = min(max(intVal("quality_score") ?? 78, 1), 100)
            let emoji = (str("emoji").flatMap { $0.isEmpty ? nil : String($0.prefix(2)) }) ?? "🍽️"

            let qFactors = NutritionQualityFactors(
                wholeGrains: abs(dblVal("whole_grains") ?? 0),
                excessSugar: -abs(dblVal("excess_sugar") ?? 0),
                excessSodium: -abs(dblVal("excess_sodium") ?? 0),
                vegetables: abs(dblVal("vegetables") ?? 0),
                healthyFats: abs(dblVal("healthy_fats") ?? 0),
                fruit: abs(dblVal("fruit") ?? 0),
                nutsLegumes: abs(dblVal("nuts_legumes") ?? 0),
                omega3: abs(dblVal("omega3") ?? 0),
                redMeat: -abs(dblVal("red_meat") ?? 0),
                processedMeat: -abs(dblVal("processed_meat") ?? 0),
                alcohol: -abs(dblVal("alcohol_factor") ?? 0)
            )

            let meal = NutritionMealItem(
                id: UUID().uuidString,
                title: title,
                timeLabel: timeLabel,
                kcal: kcal,
                proteinG: p,
                carbsG: c,
                fatG: f,
                qualityScore: quality,
                caffeineMg: dblVal("caffeine_mg"),
                alcoholDrinks: dblVal("alcohol_drinks"),
                calciumMg: dblVal("calcium_mg"),
                aiNotes: str("notes"),
                photoFilename: attachedPhotoFilename,
                emoji: emoji,
                qualityFactors: qFactors.hasAnyNonZero ? qFactors : nil
            )
            saveMeal(meal, for: dateIso)
            let action = CoachAppliedAction(
                id: UUID().uuidString,
                icon: "fork.knife",
                badgeColorHex: 0x3BD671,
                title: "Comida registrada",
                detail: "\(title) · \(timeLabel) · \(kcal) kcal (P \(p)g · C \(c)g · G \(f)g)",
                undoPayload: .deleteMeal(mealId: meal.id, dateIso: dateIso)
            )
            return (encodeToolResponse(["ok": true, "meal_id": meal.id, "date_iso": dateIso, "time": timeLabel, "kcal": kcal]), action)

        case "edit_meal":
            let rawSourceDate = str("source_date_iso")
            guard let preferredDate = parseStrictCoachDateIso(rawSourceDate) else {
                return (encodeToolResponse(["ok": false, "error": "Fecha de origen inválida. Usa yyyy-MM-dd."]), nil)
            }
            let mealId = str("meal_id")
            let matchTitle = str("match_title").map(fold)
            guard (mealId != nil && !mealId!.isEmpty) || (matchTitle != nil && matchTitle!.count >= 2) else {
                return (encodeToolResponse(["ok": false, "error": "Indica el ID o el nombre de la comida a editar."]), nil)
            }

            // If a specific date was given, search ONLY that date (never silently edit a meal from days ago!)
            var candidateDates = [preferredDate]
            if rawSourceDate == nil || rawSourceDate!.isEmpty {
                let cal = Calendar.current
                for back in 0..<2 {
                    if let dt = cal.date(byAdding: .day, value: -back, to: Date()) {
                        let iso = isoFormatter.string(from: dt)
                        if !candidateDates.contains(iso) { candidateDates.append(iso) }
                    }
                }
            }

            var foundDate: String? = nil
            var foundMeal: NutritionMealItem? = nil
            for iso in candidateDates {
                let list = mealsByDate[iso] ?? []
                if let id = mealId, !id.isEmpty, let m = list.first(where: { $0.id == id }) {
                    foundDate = iso; foundMeal = m; break
                }
                if let mt = matchTitle, !mt.isEmpty {
                    if let exact = list.first(where: { fold($0.title) == mt }) {
                        foundDate = iso; foundMeal = exact; break
                    }
                    if let partial = list.first(where: { fold($0.title).contains(mt) }) {
                        foundDate = iso; foundMeal = partial; break
                    }
                }
            }
            guard let oldDate = foundDate, let original = foundMeal else {
                return (encodeToolResponse(["ok": false, "error": "No encontré esa comida registrada en \(preferredDate)."]), nil)
            }

            var edited = original
            if let nt = normalizeCoachHHmm(str("new_time_hhmm")) { edited.timeLabel = nt }
            if let nTitle = str("new_title"), !nTitle.isEmpty { edited.title = nTitle }
            if let k = intVal("kcal") { edited.kcal = max(0, k) }
            if let p = intVal("protein_g") { edited.proteinG = max(0, p) }
            if let c = intVal("carbs_g") { edited.carbsG = max(0, c) }
            if let f = intVal("fat_g") { edited.fatG = max(0, f) }
            if let q = intVal("quality_score") { edited.qualityScore = min(max(q, 1), 100) }

            let targetDate: String
            if let rawNewDate = str("new_date_iso"), !rawNewDate.isEmpty {
                guard let validNew = parseStrictCoachDateIso(rawNewDate) else {
                    return (encodeToolResponse(["ok": false, "error": "Nueva fecha inválida. Usa yyyy-MM-dd."]), nil)
                }
                targetDate = validNew
            } else {
                targetDate = oldDate
            }
            if targetDate != oldDate {
                deleteMeal(id: original.id, for: oldDate, deletePhotoFromDisk: false)
                saveMeal(edited, for: targetDate)
            } else {
                saveMeal(edited, for: oldDate)
            }

            let detail = targetDate != oldDate
                ? "\(edited.title) · \(targetDate) \(edited.timeLabel) · \(edited.kcal) kcal"
                : "\(edited.title) · \(edited.timeLabel) · \(edited.kcal) kcal"
            let action = CoachAppliedAction(
                id: UUID().uuidString,
                icon: "clock.arrow.circlepath",
                badgeColorHex: 0x6E95F5,
                title: "Comida actualizada",
                detail: detail,
                undoPayload: .restoreMeal(meal: original, dateIso: oldDate, removeFromDateIso: targetDate != oldDate ? targetDate : nil)
            )
            return (encodeToolResponse(["ok": true, "meal_id": edited.id, "date_iso": targetDate, "time": edited.timeLabel, "title": edited.title]), action)

        case "delete_meal":
            let rawDelDate = str("date_iso")
            guard let preferredDate = parseStrictCoachDateIso(rawDelDate) else {
                return (encodeToolResponse(["ok": false, "error": "Fecha inválida. Usa yyyy-MM-dd."]), nil)
            }
            let mealId = str("meal_id")
            let matchTitle = str("match_title").map(fold)
            guard (mealId != nil && !mealId!.isEmpty) || (matchTitle != nil && matchTitle!.count >= 2) else {
                return (encodeToolResponse(["ok": false, "error": "Indica el ID o el nombre exacto de la comida a eliminar."]), nil)
            }
            // Never silently delete a meal from 5 days ago when a date was explicitly specified!
            var candidateDates = [preferredDate]
            if rawDelDate == nil || rawDelDate!.isEmpty {
                let cal = Calendar.current
                if let y = cal.date(byAdding: .day, value: -1, to: Date()) {
                    let yIso = isoFormatter.string(from: y)
                    if !candidateDates.contains(yIso) { candidateDates.append(yIso) }
                }
            }
            var foundDate: String? = nil
            var foundMeal: NutritionMealItem? = nil
            for iso in candidateDates {
                let list = mealsByDate[iso] ?? []
                if let id = mealId, !id.isEmpty, let m = list.first(where: { $0.id == id }) {
                    foundDate = iso; foundMeal = m; break
                }
                if let mt = matchTitle, !mt.isEmpty {
                    if let exact = list.first(where: { fold($0.title) == mt }) {
                        foundDate = iso; foundMeal = exact; break
                    }
                    if let partial = list.first(where: { fold($0.title).contains(mt) }) {
                        foundDate = iso; foundMeal = partial; break
                    }
                }
            }
            guard let iso = foundDate, let target = foundMeal else {
                return (encodeToolResponse(["ok": false, "error": "No encontré esa comida para eliminar en \(preferredDate)."]), nil)
            }
            // Keep photo on disk until undo expires so 1-tap Undo restores the full meal with its photo!
            deleteMeal(id: target.id, for: iso, deletePhotoFromDisk: false)
            let action = CoachAppliedAction(
                id: UUID().uuidString,
                icon: "trash.fill",
                badgeColorHex: 0xF97316,
                title: "Comida eliminada",
                detail: "\(target.title) · \(target.timeLabel) · \(target.kcal) kcal",
                undoPayload: .restoreMeal(meal: target, dateIso: iso, removeFromDateIso: nil)
            )
            return (encodeToolResponse(["ok": true, "deleted_title": target.title, "date_iso": iso]), action)

        case "add_quick_nutrient":
            guard let nutrient = str("nutrient"), let amount = dblVal("amount"), amount > 0 else {
                return (encodeToolResponse(["ok": false, "error": "Falta nutriente o cantidad válida."]), nil)
            }
            let iso = resolveCoachDateIso(str("date_iso"))
            let prevGlasses = hydrationGlassesByDate[iso]
            let prevMap = manualNutrientsByDate[iso]
            addNutrientAmount(key: nutrient, amount: amount, dateIso: iso)
            let bucket = Self.normalizedNutrientBucketKey(nutrient)
            let labelUnit: (String, String, String) = {
                switch bucket {
                case "hidratacion": return ("Hidratación añadida", String(format: "+%.0f ml", amount), "drop.fill")
                case "cafeina": return ("Cafeína añadida", String(format: "+%.0f mg", amount), "cup.and.saucer.fill")
                case "alcohol": return ("Alcohol registrado", String(format: "+%.1f bebida(s)", locale: Locale(identifier: "es_ES"), amount), "wineglass.fill")
                default: return ("Nutriente añadido", String(format: "+%.0f mg", amount), "pills.fill")
                }
            }()
            let action = CoachAppliedAction(
                id: UUID().uuidString,
                icon: labelUnit.2,
                badgeColorHex: 0x38BDF8,
                title: labelUnit.0,
                detail: "\(labelUnit.1) (\(iso))",
                undoPayload: .restoreNutrientDay(dateIso: iso, previousGlasses: prevGlasses, previousManualMap: prevMap)
            )
            return (encodeToolResponse(["ok": true, "nutrient": bucket, "amount": amount, "date_iso": iso]), action)

        case "update_nutrition_goals":
            let prev = customNutritionGoals
            var updated = customNutritionGoals
            var changed = false
            if let c = intVal("calories_kcal"), c >= 900, c <= 7000 { updated.caloriesKcal = c; changed = true }
            if let p = intVal("protein_g"), p >= 30, p <= 450 { updated.proteinG = p; changed = true }
            if let cb = intVal("carbs_g"), cb >= 20, cb <= 800 { updated.carbsG = cb; changed = true }
            if let f = intVal("fat_g"), f >= 20, f <= 300 { updated.fatG = f; changed = true }
            guard changed else {
                return (encodeToolResponse(["ok": false, "error": "Ningún objetivo recibido está dentro de rangos fisiológicos válidos (kcal 900-7000, P 30-450g, C 20-800g, G 20-300g)."]), nil)
            }
            updateNutritionGoals(updated)
            let eff = effectiveNutritionGoals
            let action = CoachAppliedAction(
                id: UUID().uuidString,
                icon: "target",
                badgeColorHex: 0x38D9B5,
                title: "Objetivos actualizados",
                detail: "\(eff.kcal) kcal · P \(eff.proteinG)g · C \(eff.carbsG)g · G \(eff.fatG)g",
                undoPayload: .restoreNutritionGoals(goals: prev)
            )
            return (encodeToolResponse(["ok": true, "kcal": eff.kcal, "protein_g": eff.proteinG, "carbs_g": eff.carbsG, "fat_g": eff.fatG]), action)

        case "set_journal_habit":
            guard let rawHabit = str("habit_id"), !rawHabit.isEmpty else {
                return (encodeToolResponse(["ok": false, "error": "Falta el hábito."]), nil)
            }
            let iso = resolveCoachDateIso(str("date_iso"))
            let targetFold = fold(rawHabit)
            let manualSpecs = allCatalogAndCustomEntries.filter { !$0.isAuto }
            let matchedSpec = manualSpecs.first(where: { fold($0.id) == targetFold })
                ?? manualSpecs.first(where: { fold($0.title) == targetFold })
                ?? manualSpecs.first(where: { fold($0.title).contains(targetFold) || targetFold.contains(fold($0.title)) })
            guard let spec = matchedSpec else {
                return (encodeToolResponse(["ok": false, "error": "No encontré el hábito «\(rawHabit)» en tu Diario."]), nil)
            }

            let rawState = (str("state") ?? "yes").lowercased()
            let nextState: JournalCheckState = {
                switch rawState {
                case "yes", "si", "sí", "true": return .yes
                case "no", "false": return .no
                default: return .unset
                }
            }()
            let prevState = journalCheckinsByDate[iso]?[spec.id]
            let prevTime = journalEventTimesByDate[iso]?[spec.id]

            let rawTimeArg = str("event_time")
            let normalizedTime: String? = {
                guard let rt = rawTimeArg, !rt.isEmpty else { return nil }
                if rt.lowercased() == "clear" || rt.lowercased() == "none" || rt.lowercased() == "sin" {
                    return ""
                }
                return normalizeCoachHHmm(rt)
            }()

            setJournalCheck(habitId: spec.id, state: nextState, for: iso, eventTime: normalizedTime)
            let finalTime = journalEventTime(habitId: spec.id, for: iso)
            let stateWord = nextState == .yes ? "Sí" : (nextState == .no ? "No" : "Sin marcar")
            let timeSuffix = (nextState == .yes && finalTime != nil) ? " · \(finalTime!)" : ""
            let action = CoachAppliedAction(
                id: UUID().uuidString,
                icon: nextState == .yes ? "checkmark.circle.fill" : (nextState == .no ? "xmark.circle.fill" : "minus.circle"),
                badgeColorHex: nextState == .yes ? 0x3BD671 : 0xF59E0B,
                title: "Diario actualizado",
                detail: "\(spec.title): \(stateWord)\(timeSuffix)",
                undoPayload: .restoreJournalHabit(dateIso: iso, habitId: spec.id, previousState: prevState, previousTime: prevTime)
            )
            return (encodeToolResponse(["ok": true, "habit_id": spec.id, "title": spec.title, "state": stateWord, "event_time": finalTime ?? ""]), action)

        case "set_journal_note_and_mood":
            let iso = resolveCoachDateIso(str("date_iso"))
            let prevNote = journalNotesByDate[iso]
            let prevMood = journalMoodByDate[iso]
            var summaryBits: [String] = []

            if let newNote = str("note"), !newNote.isEmpty {
                let append = boolVal("append_note") ?? false
                if append, let existing = prevNote, !existing.isEmpty {
                    setJournalNote("\(existing) · \(newNote)", for: iso)
                } else {
                    setJournalNote(newNote, for: iso)
                }
                summaryBits.append("Nota: «\(String(newNote.prefix(42)))»")
            }
            if let mood = intVal("mood"), (1...5).contains(mood) {
                setJournalMood(mood, for: iso)
                let labels = ["Agotado", "Bajo", "Normal", "Bien", "Excelente"]
                summaryBits.append("Ánimo: \(labels[mood - 1])")
            }
            guard !summaryBits.isEmpty else {
                return (encodeToolResponse(["ok": false, "error": "No se especificó nota ni ánimo."]), nil)
            }
            let action = CoachAppliedAction(
                id: UUID().uuidString,
                icon: "note.text",
                badgeColorHex: 0x6E95F5,
                title: "Diario guardado",
                detail: summaryBits.joined(separator: " · "),
                undoPayload: .restoreJournalNoteAndMood(dateIso: iso, previousNote: prevNote, previousMood: prevMood)
            )
            return (encodeToolResponse(["ok": true, "date_iso": iso, "summary": summaryBits.joined(separator: ", ")]), action)

        case "create_custom_habit":
            guard let title = str("title"), !title.isEmpty else {
                return (encodeToolResponse(["ok": false, "error": "Falta nombre del hábito."]), nil)
            }
            let emoji = (str("emoji").flatMap { $0.isEmpty ? nil : $0 }) ?? "✨"
            let isNight = boolVal("is_night_habit") ?? false
            addCustomJournalHabit(emoji: emoji, title: title, isNightHabit: isNight)
            guard let created = customJournalHabits.last else {
                return (encodeToolResponse(["ok": false, "error": "No se pudo crear el hábito."]), nil)
            }
            if boolVal("mark_today_yes") == true {
                setJournalCheck(habitId: created.id, state: .yes, for: selectedDateIso, eventTime: normalizeCoachHHmm(str("event_time")))
            }
            let action = CoachAppliedAction(
                id: UUID().uuidString,
                icon: "plus.circle.fill",
                badgeColorHex: 0x38D9B5,
                title: "Hábito creado",
                detail: "\(created.emoji) \(created.title) (\(isNight ? "Noche" : "Día"))",
                undoPayload: .deleteCustomHabit(habitId: created.id)
            )
            return (encodeToolResponse(["ok": true, "habit_id": created.id, "title": created.title]), action)

        case "log_workout":
            guard let title = str("title"), !title.isEmpty, let dur = intVal("duration_min"), dur > 0 else {
                return (encodeToolResponse(["ok": false, "error": "Falta nombre o duración del entrenamiento."]), nil)
            }
            let iso = resolveCoachDateIso(str("date_iso"))
            let cat = str("category") ?? "Cardio"
            let startStr = normalizeCoachHHmm(str("start_time_hhmm")) ?? nowHHmm()
            let endStr: String = {
                let parts = startStr.split(separator: ":")
                if parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) {
                    let totalM = (h * 60 + m + dur) % (24 * 60)
                    return String(format: "%02d:%02d", totalM / 60, totalM % 60)
                }
                return startStr
            }()
            let estKcal = intVal("kcal") ?? max(Int((Double(dur) * (cat == "Fuerza" ? 6.2 : 8.0)).rounded()), 40)
            let avgHr = max(0, intVal("avg_hr_bpm") ?? 0)
            let distKm = dblVal("distance_km")
            let wk = EffortEventItem(
                id: "ai_wk_\(UUID().uuidString.prefix(8))",
                title: title,
                timeRange: "\(startStr) - \(endStr)",
                durationMin: min(max(dur, 1), 600),
                avgHrBpm: avgHr,
                strainScore: 0,
                strainPct: 0,
                categoryLabel: cat,
                kcal: max(0, estKcal),
                distanceKm: distKm,
                dateIso: iso
            )
            updateWorkout(wk, originalDateIso: iso)
            let action = CoachAppliedAction(
                id: UUID().uuidString,
                icon: "figure.run",
                badgeColorHex: 0xF59E0B,
                title: "Entreno registrado",
                detail: "\(title) · \(dur) min · \(startStr) · \(estKcal) kcal",
                undoPayload: .deleteWorkout(workoutId: wk.id, dateIso: iso)
            )
            return (encodeToolResponse(["ok": true, "workout_id": wk.id, "date_iso": iso, "duration_min": dur, "kcal": estKcal]), action)

        case "edit_or_delete_workout":
            guard let iso = parseStrictCoachDateIso(str("date_iso")) else {
                return (encodeToolResponse(["ok": false, "error": "Fecha inválida. Usa yyyy-MM-dd."]), nil)
            }
            let wkId = str("workout_id")
            let matchTitle = str("match_title").map(fold)
            let isDelete = boolVal("delete") == true
            let list = activeHistory[iso]?.workouts ?? []
            let target: EffortEventItem? = {
                if let id = wkId, !id.isEmpty { return list.first(where: { $0.id == id }) }
                if let mt = matchTitle, !mt.isEmpty {
                    return list.first(where: { fold($0.title) == mt })
                        ?? list.first(where: { fold($0.title).contains(mt) })
                }
                // NEVER delete an unspecified workout by falling back to list.first!
                if isDelete { return nil }
                return list.count == 1 ? list.first : nil
            }()
            guard let original = target else {
                let errMsg = (isDelete && wkId == nil && matchTitle == nil)
                    ? "Indica el nombre o ID exacto del entrenamiento que quieres eliminar."
                    : "No encontré ese entrenamiento en \(iso)."
                return (encodeToolResponse(["ok": false, "error": errMsg]), nil)
            }
            if boolVal("delete") == true {
                deleteWorkout(id: original.id, dateIso: iso)
                let action = CoachAppliedAction(
                    id: UUID().uuidString,
                    icon: "trash.fill",
                    badgeColorHex: 0xF97316,
                    title: "Entreno eliminado",
                    detail: "\(original.title) · \(original.durationMin) min",
                    undoPayload: .restoreWorkout(workout: original, dateIso: iso)
                )
                return (encodeToolResponse(["ok": true, "deleted_title": original.title]), action)
            }

            var edited = original
            if let nt = str("new_title"), !nt.isEmpty { edited.title = nt }
            if let nd = intVal("new_duration_min"), nd > 0 { edited.durationMin = min(nd, 600) }
            if let nk = intVal("new_kcal"), nk >= 0 { edited.kcal = nk }
            if let nhr = intVal("new_avg_hr_bpm"), nhr >= 0 { edited.avgHrBpm = nhr }
            if let ncat = str("new_category"), !ncat.isEmpty { edited.categoryLabel = ncat }
            if let ns = normalizeCoachHHmm(str("new_start_time_hhmm")) {
                let parts = ns.split(separator: ":")
                if parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) {
                    let endM = (h * 60 + m + edited.durationMin) % (24 * 60)
                    edited.timeRange = "\(ns) - \(String(format: "%02d:%02d", endM / 60, endM % 60))"
                }
            }
            updateWorkout(edited, originalDateIso: iso)
            let action = CoachAppliedAction(
                id: UUID().uuidString,
                icon: "figure.run",
                badgeColorHex: 0x6E95F5,
                title: "Entreno actualizado",
                detail: "\(edited.title) · \(edited.durationMin) min · \(edited.timeRange)",
                undoPayload: .restoreWorkout(workout: original, dateIso: iso)
            )
            return (encodeToolResponse(["ok": true, "workout_id": edited.id, "title": edited.title]), action)

        case "log_body_measurement":
            let iso = resolveCoachDateIso(str("date_iso"))
            let targetDate = isoFormatter.date(from: iso) ?? Date()
            let prevDay = activeHistory[iso]
            let w = dblVal("weight_kg")
            let bf = dblVal("body_fat_pct")
            let lm = dblVal("lean_mass_kg")
            let sys = intVal("systolic_bp")
            let dia = intVal("diastolic_bp")
            guard w != nil || bf != nil || lm != nil || (sys != nil && dia != nil) else {
                return (encodeToolResponse(["ok": false, "error": "Indica al menos peso, grasa o tensión arterial."]), nil)
            }
            logManualScaleReading(
                date: targetDate,
                weightKg: w,
                bodyFatPct: bf,
                leanMassKg: lm,
                systolicBp: sys,
                diastolicBp: dia
            )
            var bits: [String] = []
            if let w { bits.append(String(format: "%.1f kg", locale: Locale(identifier: "es_ES"), w)) }
            if let bf { bits.append(String(format: "%.1f%% grasa", locale: Locale(identifier: "es_ES"), bf)) }
            if let sys, let dia { bits.append("\(sys)/\(dia) mmHg") }
            let action = CoachAppliedAction(
                id: UUID().uuidString,
                icon: "scalemass.fill",
                badgeColorHex: 0x38D9B5,
                title: "Biología actualizada",
                detail: bits.joined(separator: " · "),
                undoPayload: .restoreBodyMeasurement(
                    dateIso: iso,
                    prevWeight: prevDay?.bodyWeightKg,
                    prevFat: prevDay?.bodyFatPct,
                    prevLean: prevDay?.leanMassKg,
                    prevSys: prevDay?.systolicBp,
                    prevDia: prevDay?.diastolicBp
                )
            )
            return (encodeToolResponse(["ok": true, "date_iso": iso, "summary": bits.joined(separator: ", ")]), action)

        default:
            return (encodeToolResponse(["ok": false, "error": "Herramienta no reconocida: \(name)"]), nil)
        }
    }

    func undoCoachAction(messageId: String, actionId: String) {
        guard let mIdx = coachMessages.firstIndex(where: { $0.id == messageId }),
              let aIdx = coachMessages[mIdx].appliedActions.firstIndex(where: { $0.id == actionId }),
              !coachMessages[mIdx].appliedActions[aIdx].isUndone,
              let payload = coachMessages[mIdx].appliedActions[aIdx].undoPayload else { return }

        switch payload {
        case .deleteMeal(let mealId, let dateIso):
            deleteMeal(id: mealId, for: dateIso)

        case .restoreMeal(let meal, let dateIso, let removeFromDateIso):
            if let rem = removeFromDateIso {
                deleteMeal(id: meal.id, for: rem)
            }
            saveMeal(meal, for: dateIso)

        case .restoreNutrientDay(let dateIso, let prevGlasses, let prevManualMap):
            if let g = prevGlasses { hydrationGlassesByDate[dateIso] = g }
            else { hydrationGlassesByDate.removeValue(forKey: dateIso) }
            if let m = prevManualMap { manualNutrientsByDate[dateIso] = m }
            else { manualNutrientsByDate.removeValue(forKey: dateIso) }
            dataRevision += 1
            persistState()

        case .restoreNutritionGoals(let goals):
            updateNutritionGoals(goals)

        case .restoreJournalHabit(let dateIso, let habitId, let prevState, let prevTime):
            var map = journalCheckinsByDate[dateIso] ?? [:]
            if let st = prevState {
                map[habitId] = st
            } else {
                map.removeValue(forKey: habitId)
            }
            journalCheckinsByDate[dateIso] = map
            setJournalEventTime(habitId: habitId, timeLabel: prevTime, for: dateIso)

        case .restoreJournalNoteAndMood(let dateIso, let prevNote, let prevMood):
            setJournalNote(prevNote ?? "", for: dateIso)
            if let pm = prevMood {
                journalMoodByDate[dateIso] = pm
            } else {
                journalMoodByDate.removeValue(forKey: dateIso)
            }
            persistState()

        case .deleteCustomHabit(let habitId):
            deleteCustomJournalHabit(id: habitId)

        case .deleteWorkout(let workoutId, let dateIso):
            deleteWorkout(id: workoutId, dateIso: dateIso)

        case .restoreWorkout(let workout, let dateIso):
            updateWorkout(workout, originalDateIso: dateIso)

        case .restoreBodyMeasurement(let dateIso, let prevW, let prevF, let prevL, let prevSys, let prevDia):
            if var d = realHistory[dateIso] ?? activeHistory[dateIso] {
                d.bodyWeightKg = prevW
                d.bodyFatPct = prevF
                d.leanMassKg = prevL
                d.systolicBp = prevSys
                d.diastolicBp = prevDia
                if let pw = prevW { userProfile.weightKg = pw }
                if let pf = prevF { userProfile.bodyFatPct = pf }
                realHistory[dateIso] = d
                if !hasImportedOrPairedRealData {
                    simulatedHistory[dateIso] = d
                }
                dataRevision += 1
                persistState()
            }
        }

        coachMessages[mIdx].appliedActions[aIdx].isUndone = true
        if let activeId = activeCoachThreadId, let tIdx = coachThreads.firstIndex(where: { $0.id == activeId }) {
            coachThreads[tIdx].messages = coachMessages
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        publishWidgetSnapshot(triggerReload: true, forceReload: true)
        persistState()
    }

    func syncCurrentChatIntoThreads(updatedAtLabel: String) {
        guard !coachMessages.isEmpty else { return }
        let todayIso = isoFormatter.string(from: Date())
        let firstUserText = coachMessages.first(where: { $0.isUser })?.text ?? "Conversación"
        let cleanTitle = String(firstUserText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(48))

        if let activeId = activeCoachThreadId, let idx = coachThreads.firstIndex(where: { $0.id == activeId }) {
            coachThreads[idx].messages = coachMessages
            coachThreads[idx].updatedAtLabel = updatedAtLabel
            if coachThreads[idx].title.isEmpty { coachThreads[idx].title = cleanTitle }
            let updated = coachThreads.remove(at: idx)
            coachThreads.insert(updated, at: 0)
        } else {
            let newId = UUID().uuidString
            activeCoachThreadId = newId
            let thread = CoachChatThread(
                id: newId,
                title: cleanTitle.isEmpty ? "Consulta Coach IA" : cleanTitle,
                dateIso: todayIso,
                updatedAtLabel: updatedAtLabel,
                messages: coachMessages
            )
            coachThreads.insert(thread, at: 0)
        }
        if coachThreads.count > 30 {
            let dropped = coachThreads.dropFirst(30)
            for t in dropped {
                for m in t.messages {
                    if let fn = m.attachedPhotoFilename { MealPhotoStorage.deletePhoto(filename: fn) }
                }
            }
            coachThreads = Array(coachThreads.prefix(30))
        }
        persistState()
    }

    func selectCoachThread(_ id: String) {
        guard let thread = coachThreads.first(where: { $0.id == id }) else { return }
        coachReplyTask?.cancel()
        coachReplyTask = nil
        activeCoachThreadId = thread.id
        coachMessages = thread.messages
        activeCoachInteractionId = nil
        isCoachThinking = false
        lastCoachErrorMessage = nil
        persistState()
    }

    func deleteCoachThread(_ id: String) {
        if let doomed = coachThreads.first(where: { $0.id == id }) {
            for m in doomed.messages {
                if let fn = m.attachedPhotoFilename { MealPhotoStorage.deletePhoto(filename: fn) }
            }
        }
        coachThreads.removeAll { $0.id == id }
        if activeCoachThreadId == id {
            coachReplyTask?.cancel()
            coachReplyTask = nil
            if let next = coachThreads.first {
                activeCoachThreadId = next.id
                coachMessages = next.messages
            } else {
                activeCoachThreadId = nil
                coachMessages = []
            }
            activeCoachInteractionId = nil
            isCoachThinking = false
        }
        persistState()
    }

    func startNewCleanChat() {
        coachReplyTask?.cancel()
        coachReplyTask = nil
        coachMessages = []
        activeCoachThreadId = nil
        activeCoachInteractionId = nil
        isCoachThinking = false
        lastCoachErrorMessage = nil
        persistState()
    }

}

import Foundation

extension GeminiCoachService {
    // MARK: - 1. Multi-Turn Conversational System Instruction

    func buildChatSystemInstruction(
        userName: String,
        currentDate: Date,
        biometricContextJson: String,
        availableHighlights: [String],
        missingCategories: [String],
        isFollowUp: Bool,
        tone: CoachPersonalityTone = .directo,
        detailLevel: CoachDetailLevel = .equilibrado
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
        PERSONALIDAD CONFIGURADA: \(tone.systemDirective)
        NIVEL DE DETALLE CONFIGURADO: \(detailLevel.systemDirective)

        CÓMO CONVERSAR Y ACTUAR DENTRO DE LA APP:
        - \(continuityRule)
        - Si te pregunta sobre entrenamiento, sueño, comida, salir de fiesta, suplementos, molestias, horarios o cualquier tema cotidiano o deportivo, responde con naturalidad, criterio real y cercanía.
        - TIENES CAPACIDAD REAL PARA PLANIFICAR, REGISTRAR, EDITAR Y BORRAR DATOS EN IMPROVING mediante tus 14 herramientas (`log_meal`, `edit_meal`, `delete_meal`, `add_quick_nutrient`, `update_nutrition_goals`, `set_journal_habit`, `set_journal_note_and_mood`, `create_custom_habit`, `log_workout`, `edit_or_delete_workout`, `log_body_measurement`, `save_coach_memory`, `create_strength_routine`, `propose_macro_meals`).
        - PLANIFICACIÓN EJECUTABLE DE ENTRENOS: Cuando \(name) te pida que le crees o prepares una rutina de fuerza para hoy ("créame la rutina de hoy según mi recuperación y músculos frescos", "diseña mi sesión de hoy"), revisa `metricas_hoy.recuperacion_pct`, `frescura_muscular` y `diario_hoy.modo_objetivo_global`, y LLAMA DIRECTAMENTE a `create_strength_routine` con 4 a 6 ejercicios reales (series, repeticiones, kg aproximados y grupo muscular) para guardarla y abrirla en 1 toque en Strength Builder.
        - PLANIFICACIÓN EJECUTABLE DE COMIDAS PARA CLAVAR MACROS: Cuando \(name) te pregunte qué cenar, comer o merendar para cuadrar los macros que le faltan hoy ("dime qué cenar para clavar mis macros", "qué puedo comer ahora"), consulta `nutricion_hoy.macros_restantes_hoy` y `nutricion_dinamica_strain`, y LLAMA DIRECTAMENTE a `propose_macro_meals` proponiendo exactamente 2 opciones realistas en español con gramos aproximados que claven esos macros restantes para que pueda guardarlas en 1 toque desde el chat.
        - MEMORIA A LARGO PLAZO Y MODO ACTIVO: Respeta siempre los recuerdos permanentes en `diario_hoy.memoria_largo_plazo_usuario` (lesiones, objetivos deportivos, intolerancias, horarios) y la directriz del modo elegido en `diario_hoy.modo_objetivo_global`. Si \(name) te pide que recuerdes algo para el futuro ("recuerda que tengo tendinitis", "apunta que preparo media maratón"), llama directamente a `save_coach_memory`.
        - CONTEXTO INTEGRAL: Aprovecha `contexto_meteorologico_hoy` (si hay calor/humedad explica la deriva de FC y sube hidratación), `nutricion_dinamica_strain` (Carb Cycling según Strain), `causalidad_cruzada_local` (Nutrición × Analíticas × Biometría) y `correlaciones_diario_30d_6m` para dar explicaciones causales de alto nivel.
        - Cuando \(name) te pida registrar algo ("he comido...", "apunta...", "hoy pesé...", "hice 45 min de pádel...", "marca creatina en el diario...") o modificar/borrar un registro ("cambia la hora del desayuno a las 9:15", "borra la merienda", "pasa la cena a ayer"), EJECUTA LA HERRAMIENTA DIRECTAMENTE SIN PEDIR PERMISO PREVIO (el usuario siempre tiene un botón Deshacer en tu respuesta).
        - Si \(name) adjunta una foto de un plato y dice que se lo comió o pide registrarlo, estima con precisión título, kcal, proteína, carbos, grasas, puntuación 1–100 y factores nutricionales y llama a `log_meal` directamente con la hora indicada (o la hora actual si no indicó otra).
        - Para editar o borrar comidas/entrenamientos usa siempre el `id` exacto que aparece en `nutricion_hoy.comidas_registradas`, `comidas_ayer` o `metricas_hoy.entrenamientos_hoy`.
        - En el Diario (`set_journal_habit`), la hora del evento (`event_time`) es SIEMPRE OPCIONAL: pásala SOLO si el usuario dice una hora concreta (ej. "café a las 16:30"); si no dice hora, omítela.
        - Cuando el usuario solo hace una consulta general sin pedir acción ni plan ejecutable, NO llames a ninguna herramienta y responde normalmente.
        - Escribe en texto natural fluido en español de tú a tú respetando la personalidad y el nivel de detalle configurados.
        - NO respondas en JSON, NO uses llaves {}, NO uses markdown con asteriscos ** ni paréntesis (). Integra las cifras de forma natural en la frase.
        - NO empieces con prefijos robóticos como "Análisis:", "Veredicto:" ni "Opinión IA:".

        VERACIDAD ABSOLUTA Y CERO INVENCIÓN DE DATOS:
        - \(dataConnection)
        - \(missingWarning)
        - PROHIBIDO inventar, estimar o rellenar ninguna cifra marcada como "NO_DISPONIBLE". Si pregunta por una métrica ausente, díselo con total naturalidad sin inventar ningún número.
        - Presta especial atención al bloque `diario_hoy` (hábitos personalizados, `nota_del_dia` y `notas_recientes`), `nutricion_hoy` (comidas, macros, cafeína, hidratación y alcohol), `analiticas_recientes` y `causalidad_cruzada_local` para explicar variaciones reales en su VFC, sueño, recuperación o energía cuando vengan al caso.

        DATOS REALES DE \(name.uppercased()):
        \(biometricContextJson)
        """
    }

    // MARK: - Multi-Turn Role Normalization (Prevents Gemini HTTP 400 on Turn 2+ & Supports Photo Attachments!)

    func buildNormalizedGeminiContents(history: [CoachChatMessage], currentPrompt: String, jpegImageData: Data? = nil) -> [[String: Any]] {
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

    func buildNormalizedOpenAIMessages(sysPrompt: String, history: [CoachChatMessage], currentPrompt: String) -> [[String: String]] {
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

    // MARK: - Native Gemini Tool Declarations (Agentic App Editing with 1-Tap Undo)

    nonisolated static let coachToolDeclarations: [[String: Any]] = [
        [
            "name": "log_meal",
            "description": "Registra una comida nueva en el apartado de Nutrición con su hora, fecha, calorías, macros y calidad nutricional.",
            "parameters": [
                "type": "OBJECT",
                "properties": [
                    "title": ["type": "STRING", "description": "Nombre claro del plato en español"],
                    "emoji": ["type": "STRING", "description": "Un único emoji representativo del alimento"],
                    "time_hhmm": ["type": "STRING", "description": "Hora HH:mm (ej. 14:20). Si no se indica, usar hora actual"],
                    "date_iso": ["type": "STRING", "description": "Fecha yyyy-MM-dd (opcional; por defecto la fecha seleccionada)"],
                    "kcal": ["type": "INTEGER", "description": "Calorías estimadas"],
                    "protein_g": ["type": "INTEGER", "description": "Gramos de proteína"],
                    "carbs_g": ["type": "INTEGER", "description": "Gramos de carbohidratos"],
                    "fat_g": ["type": "INTEGER", "description": "Gramos de grasa"],
                    "quality_score": ["type": "INTEGER", "description": "Puntuación de calidad nutricional 1-100"],
                    "caffeine_mg": ["type": "NUMBER", "description": "Cafeína en mg si aplica"],
                    "alcohol_drinks": ["type": "NUMBER", "description": "Bebidas estándar de alcohol si aplica"],
                    "calcium_mg": ["type": "NUMBER", "description": "Calcio en mg si aplica"],
                    "notes": ["type": "STRING", "description": "Nota breve nutricional"],
                    "whole_grains": ["type": "NUMBER", "description": "Factor cereales integrales (0 a +10)"],
                    "excess_sugar": ["type": "NUMBER", "description": "Factor exceso azúcar (0 a -15)"],
                    "excess_sodium": ["type": "NUMBER", "description": "Factor exceso sodio (0 a -12)"],
                    "vegetables": ["type": "NUMBER", "description": "Factor verdura (0 a +12)"],
                    "healthy_fats": ["type": "NUMBER", "description": "Factor grasas saludables (0 a +10)"],
                    "fruit": ["type": "NUMBER", "description": "Factor fruta (0 a +10)"],
                    "nuts_legumes": ["type": "NUMBER", "description": "Factor frutos secos/legumbres (0 a +10)"],
                    "omega3": ["type": "NUMBER", "description": "Factor omega-3 (0 a +10)"],
                    "red_meat": ["type": "NUMBER", "description": "Factor carne roja (0 a -10)"],
                    "processed_meat": ["type": "NUMBER", "description": "Factor carne procesada (0 a -12)"],
                    "alcohol_factor": ["type": "NUMBER", "description": "Factor alcohol (0 a -15)"]
                ],
                "required": ["title", "kcal", "protein_g", "carbs_g", "fat_g"]
            ]
        ],
        [
            "name": "edit_meal",
            "description": "Edita una comida ya registrada: cambiar su hora, moverla de día, renombrarla o corregir sus calorías/macros.",
            "parameters": [
                "type": "OBJECT",
                "properties": [
                    "meal_id": ["type": "STRING", "description": "ID exacto de la comida desde el contexto"],
                    "match_title": ["type": "STRING", "description": "Título o fragmento del plato si no hay ID"],
                    "source_date_iso": ["type": "STRING", "description": "Fecha yyyy-MM-dd donde está registrada ahora"],
                    "new_date_iso": ["type": "STRING", "description": "Nueva fecha yyyy-MM-dd si el usuario pide cambiarla de día"],
                    "new_time_hhmm": ["type": "STRING", "description": "Nueva hora HH:mm (ej. 09:15)"],
                    "new_title": ["type": "STRING", "description": "Nuevo nombre del plato"],
                    "kcal": ["type": "INTEGER", "description": "Nuevas calorías"],
                    "protein_g": ["type": "INTEGER", "description": "Nueva proteína en g"],
                    "carbs_g": ["type": "INTEGER", "description": "Nuevos carbos en g"],
                    "fat_g": ["type": "INTEGER", "description": "Nuevas grasas en g"],
                    "quality_score": ["type": "INTEGER", "description": "Nueva puntuación 1-100"]
                ]
            ]
        ],
        [
            "name": "delete_meal",
            "description": "Elimina una comida registrada por su ID o nombre.",
            "parameters": [
                "type": "OBJECT",
                "properties": [
                    "meal_id": ["type": "STRING", "description": "ID exacto de la comida"],
                    "match_title": ["type": "STRING", "description": "Nombre aproximado de la comida"],
                    "date_iso": ["type": "STRING", "description": "Fecha yyyy-MM-dd (opcional)"]
                ]
            ]
        ],
        [
            "name": "add_quick_nutrient",
            "description": "Añade hidratación (ml), cafeína (mg), alcohol (bebidas) o calcio (mg) al registro diario.",
            "parameters": [
                "type": "OBJECT",
                "properties": [
                    "nutrient": ["type": "STRING", "description": "Uno de: hidratacion, cafeina, alcohol, calcio"],
                    "amount": ["type": "NUMBER", "description": "Cantidad (ml para hidratacion, mg para cafeina/calcio, bebidas para alcohol)"],
                    "date_iso": ["type": "STRING", "description": "Fecha yyyy-MM-dd (opcional)"]
                ],
                "required": ["nutrient", "amount"]
            ]
        ],
        [
            "name": "update_nutrition_goals",
            "description": "Actualiza los objetivos diarios de calorías, proteína, carbohidratos o grasas.",
            "parameters": [
                "type": "OBJECT",
                "properties": [
                    "calories_kcal": ["type": "INTEGER", "description": "Meta diaria de kcal"],
                    "protein_g": ["type": "INTEGER", "description": "Meta diaria de proteína en g"],
                    "carbs_g": ["type": "INTEGER", "description": "Meta diaria de carbohidratos en g"],
                    "fat_g": ["type": "INTEGER", "description": "Meta diaria de grasas en g"]
                ]
            ]
        ],
        [
            "name": "set_journal_habit",
            "description": "Marca un hábito del Diario como Sí, No o sin marcar, con hora del evento OPCIONAL (solo si el usuario indica una hora).",
            "parameters": [
                "type": "OBJECT",
                "properties": [
                    "habit_id": ["type": "STRING", "description": "ID o nombre del hábito (ej. caffeine, creatine, alcohol, late_meal o título personalizado)"],
                    "state": ["type": "STRING", "description": "Uno de: yes, no, unset"],
                    "event_time": ["type": "STRING", "description": "Hora opcional HH:mm SOLO si el usuario especificó hora; usa 'clear' para borrar una hora existente"],
                    "date_iso": ["type": "STRING", "description": "Fecha yyyy-MM-dd (opcional)"]
                ],
                "required": ["habit_id", "state"]
            ]
        ],
        [
            "name": "set_journal_note_and_mood",
            "description": "Guarda o actualiza la nota del día y/o el estado de ánimo diario (1 a 5) en el Diario.",
            "parameters": [
                "type": "OBJECT",
                "properties": [
                    "note": ["type": "STRING", "description": "Texto de la nota diaria"],
                    "append_note": ["type": "BOOLEAN", "description": "Si true, añade el texto a la nota existente en lugar de reemplazarla"],
                    "mood": ["type": "INTEGER", "description": "Estado de ánimo 1 (Agotado) a 5 (Excelente)"],
                    "date_iso": ["type": "STRING", "description": "Fecha yyyy-MM-dd (opcional)"]
                ]
            ]
        ],
        [
            "name": "create_custom_habit",
            "description": "Crea un nuevo hábito personalizado en el Diario (día o noche).",
            "parameters": [
                "type": "OBJECT",
                "properties": [
                    "title": ["type": "STRING", "description": "Nombre del nuevo hábito"],
                    "emoji": ["type": "STRING", "description": "Emoji representativo"],
                    "is_night_habit": ["type": "BOOLEAN", "description": "true si es hábito nocturno, false si es de día"],
                    "mark_today_yes": ["type": "BOOLEAN", "description": "true para marcarlo además como Sí hoy"],
                    "event_time": ["type": "STRING", "description": "Hora opcional HH:mm si se marca hoy"]
                ],
                "required": ["title"]
            ]
        ],
        [
            "name": "log_workout",
            "description": "Registra un entrenamiento nuevo en Fitness y recalcula el Esfuerzo diario.",
            "parameters": [
                "type": "OBJECT",
                "properties": [
                    "title": ["type": "STRING", "description": "Nombre del entrenamiento (ej. Pádel, Gimnasio, Carrera)"],
                    "category": ["type": "STRING", "description": "Fuerza, Cardio, Carrera, Ciclismo, Natación, Movilidad o Deporte"],
                    "duration_min": ["type": "INTEGER", "description": "Duración en minutos"],
                    "start_time_hhmm": ["type": "STRING", "description": "Hora de inicio HH:mm (opcional)"],
                    "kcal": ["type": "INTEGER", "description": "Calorías quemadas (opcional, se estima si falta)"],
                    "avg_hr_bpm": ["type": "INTEGER", "description": "FC media en ppm si el usuario la indica"],
                    "distance_km": ["type": "NUMBER", "description": "Distancia en km si aplica"],
                    "date_iso": ["type": "STRING", "description": "Fecha yyyy-MM-dd (opcional)"]
                ],
                "required": ["title", "duration_min"]
            ]
        ],
        [
            "name": "edit_or_delete_workout",
            "description": "Edita la hora, duración, calorías, título o elimina un entrenamiento existente.",
            "parameters": [
                "type": "OBJECT",
                "properties": [
                    "workout_id": ["type": "STRING", "description": "ID exacto del entrenamiento"],
                    "match_title": ["type": "STRING", "description": "Título aproximado si no hay ID"],
                    "date_iso": ["type": "STRING", "description": "Fecha yyyy-MM-dd (opcional)"],
                    "delete": ["type": "BOOLEAN", "description": "true para eliminar el entrenamiento"],
                    "new_title": ["type": "STRING", "description": "Nuevo nombre"],
                    "new_duration_min": ["type": "INTEGER", "description": "Nueva duración en min"],
                    "new_start_time_hhmm": ["type": "STRING", "description": "Nueva hora de inicio HH:mm"],
                    "new_kcal": ["type": "INTEGER", "description": "Nuevas kcal"],
                    "new_avg_hr_bpm": ["type": "INTEGER", "description": "Nueva FC media"],
                    "new_category": ["type": "STRING", "description": "Nueva categoría"]
                ]
            ]
        ],
        [
            "name": "log_body_measurement",
            "description": "Registra peso, porcentaje de grasa, masa magra y/o tensión arterial en Biología.",
            "parameters": [
                "type": "OBJECT",
                "properties": [
                    "weight_kg": ["type": "NUMBER", "description": "Peso en kg"],
                    "body_fat_pct": ["type": "NUMBER", "description": "Porcentaje de grasa corporal"],
                    "lean_mass_kg": ["type": "NUMBER", "description": "Masa magra en kg"],
                    "systolic_bp": ["type": "INTEGER", "description": "Tensión sistólica mmHg"],
                    "diastolic_bp": ["type": "INTEGER", "description": "Tensión diastólica mmHg"],
                    "date_iso": ["type": "STRING", "description": "Fecha yyyy-MM-dd (opcional)"]
                ]
            ]
        ],
        [
            "name": "save_coach_memory",
            "description": "Guarda una nota permanente en la memoria a largo plazo del Coach IA (lesión, objetivo deportivo, preferencia alimentaria u horario habitual) para recordarla siempre.",
            "parameters": [
                "type": "OBJECT",
                "properties": [
                    "note": ["type": "STRING", "description": "Texto conciso a recordar a largo plazo en español"]
                ],
                "required": ["note"]
            ]
        ],
        [
            "name": "create_strength_routine",
            "description": "Crea y guarda una rutina de fuerza personalizada adaptada a la recuperación y músculos frescos del usuario, lista para abrirse y entrenarse al instante en Strength Builder.",
            "parameters": [
                "type": "OBJECT",
                "properties": [
                    "name": ["type": "STRING", "description": "Nombre de la rutina en español (ej. Empuje Hipertrofia Recuperación Alta)"],
                    "category": ["type": "STRING", "description": "Fuerza, Cardio o Movilidad"],
                    "exercises": [
                        "type": "ARRAY",
                        "description": "Lista de 3 a 7 ejercicios concretos",
                        "items": [
                            "type": "OBJECT",
                            "properties": [
                                "name": ["type": "STRING", "description": "Nombre del ejercicio en español"],
                                "sets": ["type": "INTEGER", "description": "Número de series (2 a 6)"],
                                "reps": ["type": "INTEGER", "description": "Repeticiones objetivo (4 a 20)"],
                                "weight_kg": ["type": "NUMBER", "description": "Peso inicial sugerido en kg"],
                                "primary_muscle": ["type": "STRING", "description": "Músculo principal: Pectorales, Dorsales, Hombros, Cuádriceps, Isquiotibiales, Glúteos, Bíceps, Tríceps o Abdominales"]
                            ],
                            "required": ["name", "sets", "reps"]
                        ]
                    ]
                ],
                "required": ["name", "exercises"]
            ]
        ],
        [
            "name": "propose_macro_meals",
            "description": "Propone 2 opciones concretas de comida o cena con cantidades y macros exactos para cuadrar los macros restantes del usuario, mostrándolas en el chat como tarjetas guardables en 1 toque.",
            "parameters": [
                "type": "OBJECT",
                "properties": [
                    "options": [
                        "type": "ARRAY",
                        "description": "Exactamente 2 opciones realistas que cuadren los macros restantes",
                        "items": [
                            "type": "OBJECT",
                            "properties": [
                                "title": ["type": "STRING", "description": "Nombre apetecible del plato en español"],
                                "emoji": ["type": "STRING", "description": "1 emoji representativo"],
                                "description": ["type": "STRING", "description": "Ingredientes concretos con gramos aproximados"],
                                "kcal": ["type": "INTEGER", "description": "Calorías totales"],
                                "protein_g": ["type": "INTEGER", "description": "Gramos de proteína"],
                                "carbs_g": ["type": "INTEGER", "description": "Gramos de carbohidratos"],
                                "fat_g": ["type": "INTEGER", "description": "Gramos de grasa"],
                                "fiber_g": ["type": "NUMBER", "description": "Gramos de fibra"],
                                "quality_score": ["type": "INTEGER", "description": "Calidad nutricional 1-100"]
                            ],
                            "required": ["title", "kcal", "protein_g", "carbs_g", "fat_g"]
                        ]
                    ]
                ],
                "required": ["options"]
            ]
        ]
    ]

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
        jpegImageData: Data? = nil,
        allowCloudAI: Bool = true,
        allowKeylessFallback: Bool = false,
        tone: CoachPersonalityTone = .directo,
        detailLevel: CoachDetailLevel = .equilibrado,
        actionExecutor: (@Sendable (String, String) async -> (responseJson: String, appliedAction: CoachAppliedAction?))? = nil
    ) async -> GeminiCoachResult {
        let seed = nextSeed()
        let isFollowUp = !history.isEmpty
        let sysPrompt = buildChatSystemInstruction(
            userName: userName,
            currentDate: currentDate,
            biometricContextJson: biometricContextJson,
            availableHighlights: availableHighlights,
            missingCategories: missingCategories,
            isFollowUp: isFollowUp,
            tone: tone,
            detailLevel: detailLevel
        )
        let cleanKey = Self.sanitizeApiKey(apiKey)
        let model = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "gemini-2.5-flash" : selectedModel
        var lastCloudError: String? = nil

        // Tier 1: User's Gemini API Key (auto-discovers live active models via /v1beta/models + Native Function Calling!)
        if allowCloudAI && !cleanKey.isEmpty {
            var candidates = await resolveCandidateModels(apiKey: cleanKey, selectedModel: model, forceDiscovery: false)
            var tried = Set<String>()
            var didDynamicDiscovery = (model.isEmpty || model == "auto")

            var idx = 0
            while idx < candidates.count && tried.count < 3 {
                let m = candidates[idx]
                idx += 1
                guard tried.insert(m).inserted else { continue }
                let attempt = await callGeminiChatGenerateContent(
                    prompt: prompt,
                    sysPrompt: sysPrompt,
                    history: history,
                    apiKey: cleanKey,
                    model: m,
                    jpegImageData: jpegImageData,
                    actionExecutor: actionExecutor
                )
                if let res = attempt.result {
                    return res
                }
                if let err = attempt.errorDetail {
                    lastCloudError = err
                    if err.contains("401") || err.contains("403") || err.contains("API_KEY_INVALID") || err.contains("API key not valid") {
                        break
                    }
                    // On HTTP 404 (model retired / unavailable to new users), immediately query Google's live /models endpoint!
                    if !didDynamicDiscovery && (err.contains("404") || err.lowercased().contains("no longer available") || err.lowercased().contains("not found")) {
                        didDynamicDiscovery = true
                        let fresh = await discoverAvailableModels(apiKey: cleanKey, forceRefresh: true)
                        if !fresh.isEmpty {
                            candidates.insert(contentsOf: fresh.prefix(2), at: idx)
                        }
                    }
                }
            }
        }

        // Tier 2: Optional Keyless Cloud LLM — DISABLED by default for privacy (never sends health data to 3rd-party proxy unless user opts in!)
        if allowCloudAI && allowKeylessFallback && jpegImageData == nil,
           let cloudRes = await callKeylessCloudChat(prompt: prompt, sysPrompt: sysPrompt, history: history, seed: seed) {
            return cloudRes
        }

        // Tier 3: Honest offline conversational fallback with real diagnostic cause
        let extraDiag: String? = {
            if !allowCloudAI {
                return "La IA en la nube está desactivada en Privacidad (Dispositivos y Ajustes). Respondiendo en modo 100 % local."
            }
            if cleanKey.isEmpty {
                return "Para activar respuestas en la nube con privacidad directa añade tu API Key gratuita de Google AI Studio en Dispositivos y Ajustes."
            }
            return lastCloudError
        }()
        return buildOfflineChatFallback(
            prompt: prompt,
            userName: userName,
            currentDate: currentDate,
            availableHighlights: availableHighlights,
            missingCategories: missingCategories,
            diagnosticNote: extraDiag
        )
    }

    func callGeminiInteractionsChat(
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
            let (respData, resp) = try await session.data(for: req)
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

    func sendSingleGeminiGenerateRequest(
        url: URL,
        apiKey: String,
        body: [String: Any],
        timeout: TimeInterval = 30
    ) async -> (parts: [[String: Any]]?, statusCode: Int, errorDetail: String?) {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            return (nil, 0, "Error serializando consulta")
        }
        req.httpBody = httpBody

        for attemptIdx in 0..<3 {
            if Task.isCancelled {
                return (nil, 0, "Cancelado")
            }
            do {
                let (respData, resp) = try await session.data(for: req)
                guard let http = resp as? HTTPURLResponse else {
                    return (nil, 0, "Respuesta de red inválida")
                }
                if (200...299).contains(http.statusCode) {
                    if let json = try JSONSerialization.jsonObject(with: respData) as? [String: Any],
                       let candidates = json["candidates"] as? [[String: Any]],
                       let content = candidates.first?["content"] as? [String: Any],
                       let parts = content["parts"] as? [[String: Any]] {
                        return (parts, http.statusCode, nil)
                    }
                    return (nil, http.statusCode, "Respuesta vacía del modelo")
                }
                let errTxt = Self.extractGeminiErrorMessage(from: respData, statusCode: http.statusCode)
                // Abort immediately on invalid auth/permissions (never retry 401/403)
                if http.statusCode == 401 || http.statusCode == 403 {
                    return (nil, http.statusCode, errTxt)
                }
                // Respect HTTP 429 rate-limit with Retry-After or bounded exponential backoff (max 3s)
                if http.statusCode == 429 && attemptIdx < 2 {
                    let retryAfterSec = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
                    let delaySec = min(max(retryAfterSec ?? (0.7 * pow(2.0, Double(attemptIdx))), 0.4), 3.0)
                    try? await Task.sleep(nanoseconds: UInt64(delaySec * 1_000_000_000))
                    continue
                }
                if (http.statusCode == 500 || http.statusCode == 503) && attemptIdx == 0 {
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    continue
                }
                return (nil, http.statusCode, errTxt)
            } catch is CancellationError {
                return (nil, 0, "Cancelado")
            } catch {
                if attemptIdx == 0 {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    continue
                }
                return (nil, 0, error.localizedDescription)
            }
        }
        return (nil, 0, "Sin respuesta de Gemini")
    }

    func callGeminiChatGenerateContent(
        prompt: String,
        sysPrompt: String,
        history: [CoachChatMessage],
        apiKey: String,
        model: String,
        jpegImageData: Data? = nil,
        actionExecutor: (@Sendable (String, String) async -> (responseJson: String, appliedAction: CoachAppliedAction?))? = nil
    ) async -> (result: GeminiCoachResult?, errorDetail: String?) {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            return (nil, "URL de modelo inválida")
        }

        var contents = buildNormalizedGeminiContents(history: history, currentPrompt: prompt, jpegImageData: jpegImageData)
        var genConfig: [String: Any] = [
            "temperature": actionExecutor != nil ? 0.65 : 0.78,
            "maxOutputTokens": model.contains("pro") ? 2400 : 1800
        ]
        if model.hasPrefix("gemini-2.5-flash") {
            genConfig["thinkingConfig"] = ["thinkingBudget": 0]
        }

        func makeRequestBody(withTools: Bool) -> [String: Any] {
            var b: [String: Any] = [
                "system_instruction": ["parts": [["text": sysPrompt]]],
                "contents": contents,
                "generationConfig": genConfig
            ]
            if withTools {
                b["tools"] = [["functionDeclarations": Self.coachToolDeclarations]]
                b["toolConfig"] = ["functionCallingConfig": ["mode": "AUTO"]]
            }
            return b
        }

        var useTools = (actionExecutor != nil)
        var collectedActions: [CoachAppliedAction] = []

        // Allow up to 2 tool-calling rounds so multi-step edits finish cleanly and return a natural reply
        for _ in 0..<3 {
            var resp = await sendSingleGeminiGenerateRequest(url: url, apiKey: apiKey, body: makeRequestBody(withTools: useTools))
            // Graceful fallback if a specific model doesn't support functionDeclarations (HTTP 400)
            if resp.parts == nil, useTools, resp.statusCode == 400, collectedActions.isEmpty {
                let lowErr = (resp.errorDetail ?? "").lowercased()
                if lowErr.contains("tool") || lowErr.contains("function") || lowErr.contains("declaration") {
                    useTools = false
                    resp = await sendSingleGeminiGenerateRequest(url: url, apiKey: apiKey, body: makeRequestBody(withTools: false))
                }
            }

            guard let parts = resp.parts else {
                if !collectedActions.isEmpty {
                    let recap = collectedActions.map { "\($0.title): \($0.detail)" }.joined(separator: ". ")
                    return (
                        GeminiCoachResult(
                            verdictTitle: "",
                            text: "Hecho, ya lo he dejado actualizado en tu app. \(recap).",
                            bullets: [],
                            actionLabel: nil,
                            interactionId: nil,
                            usedLiveCloud: true,
                            modelUsed: model,
                            appliedActions: collectedActions
                        ),
                        nil
                    )
                }
                return (nil, resp.errorDetail)
            }

            // Check if Gemini invoked one or more tools (`functionCall` parts)
            let functionCallParts = parts.filter { $0["functionCall"] is [String: Any] }
            if !functionCallParts.isEmpty, let executor = actionExecutor {
                // Preserve EXACT raw model parts (including any Gemini 3 `thoughtSignature`!) in conversation history
                contents.append(["role": "model", "parts": parts])

                var responseParts: [[String: Any]] = []
                for callPart in functionCallParts {
                    guard let fc = callPart["functionCall"] as? [String: Any],
                          let toolName = fc["name"] as? String else { continue }
                    let argsObj = (fc["args"] as? [String: Any]) ?? [:]
                    let argsJsonStr: String = {
                        if let d = try? JSONSerialization.data(withJSONObject: argsObj),
                           let s = String(data: d, encoding: .utf8) {
                            return s
                        }
                        return "{}"
                    }()

                    let outcome = await executor(toolName, argsJsonStr)
                    if let applied = outcome.appliedAction {
                        collectedActions.append(applied)
                    }
                    let respObj: [String: Any] = {
                        if let d = outcome.responseJson.data(using: .utf8),
                           let parsed = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                            return parsed
                        }
                        return ["ok": true, "message": outcome.responseJson]
                    }()
                    responseParts.append([
                        "functionResponse": [
                            "name": toolName,
                            "response": respObj
                        ]
                    ])
                }

                contents.append(["role": "user", "parts": responseParts])
                continue
            }

            // Plain visible conversational text reply
            let visible = parts.compactMap { part -> String? in
                if (part["thought"] as? Bool) == true { return nil }
                return part["text"] as? String
            }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
            let joined = visible.isEmpty
                ? parts.compactMap { $0["text"] as? String }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
                : visible

            if !joined.isEmpty {
                let base = parseConversationalReply(rawText: joined, interactionId: nil, modelUsed: model)
                return (
                    GeminiCoachResult(
                        verdictTitle: base.verdictTitle,
                        text: base.text,
                        bullets: base.bullets,
                        actionLabel: base.actionLabel,
                        interactionId: base.interactionId,
                        usedLiveCloud: base.usedLiveCloud,
                        modelUsed: base.modelUsed,
                        appliedActions: collectedActions
                    ),
                    nil
                )
            }
            if !collectedActions.isEmpty {
                let recap = collectedActions.map { "\($0.title): \($0.detail)" }.joined(separator: ". ")
                return (
                    GeminiCoachResult(
                        verdictTitle: "",
                        text: "Listo, cambios aplicados en Improving. \(recap).",
                        bullets: [],
                        actionLabel: nil,
                        interactionId: nil,
                        usedLiveCloud: true,
                        modelUsed: model,
                        appliedActions: collectedActions
                    ),
                    nil
                )
            }
            return (nil, "Respuesta vacía de \(model)")
        }

        if !collectedActions.isEmpty {
            let recap = collectedActions.map { "\($0.title): \($0.detail)" }.joined(separator: ". ")
            return (
                GeminiCoachResult(
                    verdictTitle: "",
                    text: "Listo, cambios aplicados. \(recap).",
                    bullets: [],
                    actionLabel: nil,
                    interactionId: nil,
                    usedLiveCloud: true,
                    modelUsed: model,
                    appliedActions: collectedActions
                ),
                nil
            )
        }
        return (nil, "Sin respuesta de Gemini")
    }

    func callKeylessCloudChat(
        prompt: String,
        sysPrompt: String,
        history: [CoachChatMessage],
        seed: Int
    ) async -> GeminiCoachResult? {
        guard let url = URL(string: keylessEndpoint) else { return nil }
        let messages = buildNormalizedOpenAIMessages(sysPrompt: sysPrompt, history: history, currentPrompt: prompt)

        for attempt in 0..<2 {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 24
            req.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("Improving-iOS/2.0", forHTTPHeaderField: "User-Agent")

            let body: [String: Any] = [
                "model": "openai-fast",
                "seed": seed + attempt,
                "messages": messages,
                "temperature": 0.78
            ]
            guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { continue }
            req.httpBody = httpBody

            do {
                let (respData, resp) = try await session.data(for: req)
                guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    if attempt == 0 { try? await Task.sleep(nanoseconds: 350_000_000) }
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
                if attempt == 0 { try? await Task.sleep(nanoseconds: 350_000_000) }
                continue
            }
        }
        return nil
    }

    func parseConversationalReply(rawText: String, interactionId: String?, modelUsed: String) -> GeminiCoachResult {
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

    func buildOfflineChatFallback(
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
}

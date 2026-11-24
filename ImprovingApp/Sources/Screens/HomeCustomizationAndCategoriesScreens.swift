import SwiftUI

// MARK: - N2A. Editar Inicio Sheet (Reorder & Toggle Home Sections + Health Monitor Metrics)

struct HomeLayoutEditorSheet: View {
    @ObservedObject var store: ImprovingStore
    var initialFocusHealthMonitor: Bool = false
    let onClose: () -> Void

    @State private var activeTab: Int = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Personalizar", selection: $activeTab) {
                        Text("Tarjetas de Inicio").tag(0)
                        Text("Monitor de salud").tag(1)
                    }
                    .pickerStyle(.segmented)

                    if activeTab == 0 {
                        Text("Activa, oculta o cambia el orden de los bloques de tu pantalla de Inicio.")
                            .font(ImprovingFont.body(13))
                            .foregroundColor(BevelColors.textSecondary)

                        let ordered = store.homeLayout.normalizedOrder
                        ForEach(Array(ordered.enumerated()), id: \.element.id) { idx, kind in
                            let visible = store.homeLayout.isSectionVisible(kind)
                            BevelCard(cornerRadius: 18) {
                                HStack(spacing: 12) {
                                    VStack(spacing: 4) {
                                        Button {
                                            UISelectionFeedbackGenerator().selectionChanged()
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                store.moveHomeSection(kind, direction: -1)
                                            }
                                        } label: {
                                            Image(systemName: "chevron.up")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(idx > 0 ? BevelColors.textSecondary : BevelColors.textMuted.opacity(0.28))
                                                .frame(width: 24, height: 18)
                                        }
                                        .disabled(idx == 0)

                                        Button {
                                            UISelectionFeedbackGenerator().selectionChanged()
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                store.moveHomeSection(kind, direction: 1)
                                            }
                                        } label: {
                                            Image(systemName: "chevron.down")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(idx < ordered.count - 1 ? BevelColors.textSecondary : BevelColors.textMuted.opacity(0.28))
                                                .frame(width: 24, height: 18)
                                        }
                                        .disabled(idx == ordered.count - 1)
                                    }

                                    Image(systemName: kind.systemIcon)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(visible ? BevelColors.greenPrimary : BevelColors.textMuted)
                                        .frame(width: 34, height: 34)
                                        .background(Circle().fill(visible ? BevelColors.greenSoftBg : BevelColors.cardSubtle))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(kind.rawValue)
                                            .font(ImprovingFont.cardTitle(14.5))
                                            .foregroundColor(visible ? BevelColors.textPrimary : BevelColors.textMuted)
                                        Text(kind.subtitle)
                                            .font(ImprovingFont.caption(11.5))
                                            .foregroundColor(BevelColors.textSecondary)
                                            .lineLimit(2)
                                    }

                                    Spacer()

                                    Toggle("", isOn: Binding(
                                        get: { store.homeLayout.isSectionVisible(kind) },
                                        set: { _ in store.toggleHomeSection(kind) }
                                    ))
                                    .labelsHidden()
                                    .tint(BevelColors.emeraldEnd)
                                }
                                .padding(13)
                            }
                        }
                    } else {
                        Text("Elige qué constantes nocturnas aparecen en la cuadrícula de Monitor de salud.")
                            .font(ImprovingFont.body(13))
                            .foregroundColor(BevelColors.textSecondary)

                        ForEach(HealthMetricKind.allCases) { metric in
                            let visible = store.homeLayout.isHealthMetricVisible(metric)
                            BevelCard(cornerRadius: 18) {
                                HStack(spacing: 12) {
                                    Text(metric.shortLabel)
                                        .font(ImprovingFont.cardTitle(13))
                                        .foregroundColor(visible ? BevelColors.skyBlue : BevelColors.textMuted)
                                        .frame(width: 44, height: 34)
                                        .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.cardSubtle))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(metric.title)
                                            .font(ImprovingFont.cardTitle(14.5))
                                            .foregroundColor(visible ? BevelColors.textPrimary : BevelColors.textMuted)
                                        if !metric.unit.isEmpty {
                                            Text("Unidad: \(metric.unit)")
                                                .font(ImprovingFont.caption(11.5))
                                                .foregroundColor(BevelColors.textSecondary)
                                        }
                                    }
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { store.homeLayout.isHealthMetricVisible(metric) },
                                        set: { _ in store.toggleHealthMonitorMetric(metric) }
                                    ))
                                    .labelsHidden()
                                    .tint(BevelColors.emeraldEnd)
                                }
                                .padding(14)
                            }
                        }
                    }

                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        store.resetHomeLayout()
                    } label: {
                        Text("Restaurar orden y tarjetas por defecto")
                            .font(ImprovingFont.caption(13))
                            .fontWeight(.semibold)
                            .foregroundColor(BevelColors.skyBlue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                }
                .padding(16)
            }
            .background(BevelColors.canvas)
            .navigationTitle("Editar Inicio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo", action: onClose)
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                activeTab = initialFocusHealthMonitor ? 1 : 0
            }
        }
    }
}

// MARK: - N2B. Ver Todas las Categorías Screen (Searchable Full App Directory)

struct AllCategoriesDirectoryScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void
    let onNavigate: (OverlayRoute) -> Void
    let onSelectHealthMetric: (HealthMetricKind) -> Void
    let onOpenCardioMetric: (CardioMetricRoute) -> Void
    let onOpenBodyMetric: (BodyCompositionMetricKind) -> Void
    let onOpenNutrient: (String) -> Void
    let onSelectMainTab: (MainTab) -> Void

    @State private var searchText: String = ""

    private struct DirectoryRow: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let valueText: String
        let icon: String
        let accent: Color
        let action: () -> Void
    }

    private struct DirectorySection: Identifiable {
        let id: String
        let title: String
        let rows: [DirectoryRow]
    }

    var body: some View {
        let avail = store.dataAvailability
        let cardio = store.trainingLoadAnalysis(tab: .cardio, spanDays: 14, windowPageOffset: 0)
        let muscular = store.trainingLoadAnalysis(tab: .muscular, spanDays: 14, windowPageOffset: 0)
        let nutTotals = store.nutritionDayTotals(for: store.selectedDateIso)
        let netInfo = store.netEnergyKcal(for: store.selectedDateIso)

        let sections: [DirectorySection] = [
            DirectorySection(id: "pillars", title: "Pilares Principales", rows: [
                DirectoryRow(id: "p_strain", title: "Esfuerzo", subtitle: store.strainStatusText, valueText: avail.hasStrainData ? "\(store.strainPercent)%" : "--", icon: "flame.fill", accent: BevelColors.amberStart) { onNavigate(.esfuerzo) },
                DirectoryRow(id: "p_rec", title: "Recuperación", subtitle: store.recoveryStatusText, valueText: avail.hasRecoveryData ? "\(store.recoveryPercent)%" : "--", icon: "leaf.fill", accent: BevelColors.greenPrimary) { onNavigate(.recuperacion) },
                DirectoryRow(id: "p_sleep", title: "Sueño", subtitle: store.sleepDurationText, valueText: avail.hasSleepData ? "\(store.sleepPercent)%" : "--", icon: "moon.stars.fill", accent: BevelColors.periwinkleStart) { onNavigate(.suenoDetail) },
                DirectoryRow(id: "p_stress", title: "Estrés fisiológico", subtitle: store.stressStatusLabel, valueText: avail.hasStressData ? "\(store.displayStressScore)/100" : "--", icon: "waveform.path", accent: BevelColors.tealLow) { onNavigate(.estres) },
                DirectoryRow(id: "p_energy", title: "Batería Corporal", subtitle: "Reservas de energía 24 h", valueText: avail.hasEnergyData ? "\(store.energyPercent)%" : "--", icon: "bolt.fill", accent: BevelColors.limeStart) { onNavigate(.energia) },
                DirectoryRow(id: "p_weekly", title: "Resumen Semanal IA", subtitle: "Comparativa 7 días + Gemini", valueText: "7 d", icon: "calendar.badge.checkmark", accent: BevelColors.indigoEnd) { onNavigate(.weeklyReview) }
            ]),
            DirectorySection(id: "vitals", title: "Monitor de Salud y Constantes", rows: [
                DirectoryRow(id: "v_hrv", title: "VFC en reposo", subtitle: "Variabilidad cardíaca nocturna", valueText: avail.hasHrvData ? String(format: "%.1f ms", locale: Locale(identifier: "es_ES"), store.hrvMs) : "--", icon: "waveform.path.ecg", accent: BevelColors.greenPrimary) { onSelectHealthMetric(.hrv) },
                DirectoryRow(id: "v_rhr", title: "FC en reposo", subtitle: "Pulsaciones nocturnas", valueText: avail.hasRestingHrData ? String(format: "%.1f ppm", locale: Locale(identifier: "es_ES"), store.restingHrBpm) : "--", icon: "heart.fill", accent: BevelColors.coralHigh) { onSelectHealthMetric(.restingHeartRate) },
                DirectoryRow(id: "v_resp", title: "Frecuencia respiratoria", subtitle: "Respiraciones por minuto", valueText: avail.hasRespData ? String(format: "%.1f rpm", locale: Locale(identifier: "es_ES"), store.respRateRpm) : "--", icon: "lungs.fill", accent: BevelColors.skyBlue) { onSelectHealthMetric(.respiratoryRate) },
                DirectoryRow(id: "v_spo2", title: "Saturación de oxígeno (SpO₂)", subtitle: "Oxigenación nocturna", valueText: avail.hasSpo2Data ? String(format: "%.1f%%", locale: Locale(identifier: "es_ES"), store.spo2DisplayDouble) : "--", icon: "drop.fill", accent: BevelColors.cyanBright) { onSelectHealthMetric(.oxygenSaturation) },
                DirectoryRow(id: "v_temp", title: "Temperatura de muñeca", subtitle: "Desviación térmica basal", valueText: store.wristTempAbsoluteC.map { String(format: "%.1f °C", locale: Locale(identifier: "es_ES"), $0) } ?? "--", icon: "thermometer.medium", accent: BevelColors.amberStart) { onSelectHealthMetric(.wristTemperature) },
                DirectoryRow(id: "v_sleep_need", title: "Necesidad de sueño y Alarma", subtitle: "Deuda y despertar inteligente", valueText: "\(store.tonightSleepNeedBreakdown.totalMin / 60)h \(store.tonightSleepNeedBreakdown.totalMin % 60)m", icon: "alarm.fill", accent: BevelColors.periwinkleStart) { onNavigate(.sleepNeedDetail) }
            ]),
            DirectorySection(id: "nutrition", title: "Nutrición e Hidratación", rows: [
                DirectoryRow(id: "n_main", title: "Panel de Nutrición", subtitle: "\(store.mealsToday.count) comida(s) hoy · \(nutTotals.kcal) kcal", valueText: nutTotals.score.map { "\($0)/100" } ?? "--", icon: "fork.knife", accent: NutritionPalette.scoreLavender) { onNavigate(.nutricion) },
                DirectoryRow(id: "n_net", title: "Energía neta", subtitle: "Ingerido vs gasto total", valueText: "\(netInfo.net > 0 ? "+" : "")\(netInfo.net) kcal", icon: "plus.forwardslash.minus", accent: NutritionPalette.burnedOrange) {
                    store.selectedNutritionTrendTab = .netEnergy
                    onNavigate(.nutritionTrends)
                },
                DirectoryRow(id: "n_prot", title: "Proteína", subtitle: "Meta \(store.effectiveNutritionGoals.proteinG) g", valueText: "\(store.totalProteinToday) g", icon: "flame.fill", accent: NutritionPalette.proteinPink) { onOpenNutrient("Proteína") },
                DirectoryRow(id: "n_water", title: "Hidratación", subtitle: "Agua registrada hoy", valueText: "\(Int(store.totalHydrationTodayMl.rounded())) ml", icon: "drop.fill", accent: BevelColors.skyBlue) { onOpenNutrient("Hidratación") },
                DirectoryRow(id: "n_caff", title: "Cafeína", subtitle: "Consumo diario", valueText: "\(Int(store.totalCaffeineTodayMg.rounded())) mg", icon: "cup.and.saucer.fill", accent: BevelColors.limeStart) { onOpenNutrient("Cafeína") }
            ]),
            DirectorySection(id: "fitness", title: "Fitness y Rendimiento", rows: [
                DirectoryRow(id: "f_cardio", title: "Carga cardiovascular", subtitle: cardio.currentState.rawValue, valueText: cardio.hasAnyData ? "\(cardio.currentLoad)" : "--", icon: "figure.run", accent: BevelColors.periwinkleStart) { onNavigate(.trainingLoad) },
                DirectoryRow(id: "f_musc", title: "Carga muscular y Frescura", subtitle: muscular.currentState.rawValue, valueText: muscular.hasAnyData ? "\(muscular.currentLoad)" : "--", icon: "figure.strengthtraining.traditional", accent: BevelColors.amberStart) { onOpenCardioMetric(.muscleGroups) },
                DirectoryRow(id: "f_vo2", title: "VO₂ máx.", subtitle: "Capacidad aeróbica", valueText: store.latestVo2Max.map { String(format: "%.1f", locale: Locale(identifier: "es_ES"), $0) } ?? "--", icon: "lungs.fill", accent: BevelColors.greenPrimary) { onOpenCardioMetric(.vo2Max) },
                DirectoryRow(id: "f_hrr", title: "Recuperación de FC (1 min)", subtitle: "Descenso post-esfuerzo", valueText: store.latestHrRecoveryRecord.map { "\(Int($0.value.rounded())) ppm" } ?? "--", icon: "heart.circle.fill", accent: BevelColors.skyBlue) { onOpenCardioMetric(.hrRecovery) },
                DirectoryRow(id: "f_zones", title: "Zonas de frecuencia cardíaca", subtitle: "Distribución Z0–Z5", valueText: "30 d", icon: "chart.bar.fill", accent: BevelColors.coralHigh) { onOpenCardioMetric(.hrZones) }
            ]),
            DirectorySection(id: "biology", title: "Biología, Composición y Analíticas", rows: [
                DirectoryRow(id: "b_age", title: "Edad biológica y Analíticas", subtitle: "\(store.latestBiomarkersByName.count) biomarcador(es) de sangre", valueText: "Biología", icon: "heart.text.square.fill", accent: BevelColors.bioTeal) { onSelectMainTab(.biologia) },
                DirectoryRow(id: "b_weight", title: "Peso corporal", subtitle: "Historial y registro manual", valueText: store.latestBodyWeightKg.map { String(format: "%.1f kg", locale: Locale(identifier: "es_ES"), $0) } ?? "--", icon: "scalemass.fill", accent: BevelColors.skyBlue) { onOpenBodyMetric(.weight) },
                DirectoryRow(id: "b_fat", title: "Grasa corporal", subtitle: "Evolución porcentual", valueText: store.latestBodyFatPct.map { String(format: "%.1f%%", locale: Locale(identifier: "es_ES"), $0) } ?? "--", icon: "drop.triangle.fill", accent: BevelColors.amberStart) { onOpenBodyMetric(.bodyFat) },
                DirectoryRow(id: "b_lean", title: "Masa magra", subtitle: "Masa libre de grasa", valueText: store.latestLeanMassKg.map { String(format: "%.1f kg", locale: Locale(identifier: "es_ES"), $0) } ?? "--", icon: "figure.arms.open", accent: BevelColors.bioTeal) { onOpenBodyMetric(.leanMass) },
                DirectoryRow(id: "b_bp", title: "Presión arterial", subtitle: "Sistólica / Diastólica", valueText: store.latestBloodPressure.map { "\($0.sys)/\($0.dia)" } ?? "--", icon: "stethoscope", accent: BevelColors.coralHigh) { onOpenBodyMetric(.bloodPressure) }
            ]),
            DirectorySection(id: "journal", title: "Diario, IA y Ajustes", rows: [
                DirectoryRow(id: "j_habits", title: "Diario y Hábitos", subtitle: "Registro diario y notas", valueText: "Diario", icon: "book.fill", accent: BevelColors.amberStart) { onSelectMainTab(.diario) },
                DirectoryRow(id: "j_impact", title: "Correlaciones del Diario (30 d)", subtitle: "Qué mejora tu recuperación", valueText: "Insights", icon: "chart.xyaxis.line", accent: BevelColors.greenPrimary) { onNavigate(.journalInsights) },
                DirectoryRow(id: "j_coach", title: "Coach Improving IA", subtitle: "Chat multimodal con tus datos", valueText: "IA", icon: "sparkles", accent: BevelColors.indigoEnd) { onNavigate(.askBevel) },
                DirectoryRow(id: "j_dev", title: "Dispositivos, Atajos y Avisos", subtitle: "Salud, WHOOP, Gemini y notificaciones", valueText: "Ajustes", icon: "gearshape.fill", accent: BevelColors.textSecondary) { onNavigate(.dispositivos) }
            ])
        ]

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))

        let filteredSections: [DirectorySection] = sections.compactMap { sec in
            if query.isEmpty { return sec }
            let matching = sec.rows.filter { r in
                let hay = "\(sec.title) \(r.title) \(r.subtitle)".folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
                return hay.contains(query)
            }
            return matching.isEmpty ? nil : DirectorySection(id: sec.id, title: sec.title, rows: matching)
        }

        VStack(spacing: 0) {
            DetailSheetHeader(title: "Todas las categorías", onBack: onBack)

            // Search bar
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(BevelColors.textMuted)
                TextField("Buscar métrica, biomarcador o sección…", text: $searchText)
                    .font(ImprovingFont.body(14.5))
                    .foregroundColor(BevelColors.textPrimary)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundColor(BevelColors.textMuted)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(BevelColors.card))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if filteredSections.isEmpty {
                        BevelCard(cornerRadius: 20) {
                            Text("No se encontraron categorías para «\(searchText)».")
                                .font(ImprovingFont.body(14))
                                .foregroundColor(BevelColors.textSecondary)
                                .padding(18)
                        }
                    } else {
                        ForEach(filteredSections) { sec in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(sec.title)
                                    .font(ImprovingFont.sectionTitle(16.5))
                                    .foregroundColor(BevelColors.textPrimary)

                                BevelCard(cornerRadius: 20) {
                                    VStack(spacing: 0) {
                                        ForEach(Array(sec.rows.enumerated()), id: \.element.id) { idx, row in
                                            Button {
                                                UISelectionFeedbackGenerator().selectionChanged()
                                                row.action()
                                            } label: {
                                                HStack(spacing: 12) {
                                                    Image(systemName: row.icon)
                                                        .font(.system(size: 15, weight: .semibold))
                                                        .foregroundColor(row.accent)
                                                        .frame(width: 34, height: 34)
                                                        .background(Circle().fill(row.accent.opacity(0.15)))
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text(row.title)
                                                            .font(ImprovingFont.cardTitle(14.5))
                                                            .foregroundColor(BevelColors.textPrimary)
                                                        Text(row.subtitle)
                                                            .font(ImprovingFont.caption(12))
                                                            .foregroundColor(BevelColors.textSecondary)
                                                            .lineLimit(1)
                                                    }
                                                    Spacer(minLength: 6)
                                                    Text(row.valueText)
                                                        .font(ImprovingFont.caption(13))
                                                        .fontWeight(.semibold)
                                                        .monospacedDigit()
                                                        .foregroundColor(BevelColors.textPrimary)
                                                    Image(systemName: "chevron.right")
                                                        .font(.system(size: 11.5, weight: .semibold))
                                                        .foregroundColor(BevelColors.textMuted)
                                                }
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 12)
                                            }
                                            .buttonStyle(.plain)

                                            if idx < sec.rows.count - 1 {
                                                Divider()
                                                    .background(BevelColors.divider)
                                                    .padding(.leading, 58)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 150)
            }
        }
        .background(BevelColors.canvas.ignoresSafeArea())
    }
}

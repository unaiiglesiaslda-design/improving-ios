import SwiftUI

// MARK: - Open-Meteo Environmental & Thermal Physiology Card (Effort & Recovery)

struct WeatherPhysiologyCard: View {
    @ObservedObject var store: ImprovingStore
    var compactForRecovery: Bool = false

    @State private var showCitySheet: Bool = false

    var body: some View {
        Group {
            if let w = store.weatherSnapshot {
                let accent: Color = w.heatStressLevel >= 2
                    ? BevelColors.coralHigh
                    : (w.heatStressLevel == 1 ? BevelColors.amberStart : BevelColors.skyBlue)

                BevelCard(cornerRadius: compactForRecovery ? 18 : 20) {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 10) {
                            Image(systemName: w.sfSymbol)
                                .font(.system(size: compactForRecovery ? 15 : 17, weight: .semibold))
                                .foregroundColor(accent)
                                .frame(width: compactForRecovery ? 32 : 36, height: compactForRecovery ? 32 : 36)
                                .background(Circle().fill(accent.opacity(0.15)))

                            VStack(alignment: .leading, spacing: 1.5) {
                                HStack(spacing: 6) {
                                    Text("CLIMA · \(w.cityName.uppercased())")
                                        .font(ImprovingFont.microLabel(9.5))
                                        .foregroundColor(BevelColors.textMuted)
                                    if w.estimatedHrDriftBpm >= 4 {
                                        Text("+\(w.estimatedHrDriftBpm) ppm FC")
                                            .font(ImprovingFont.microLabel(9.5))
                                            .foregroundColor(accent)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(accent.opacity(0.14)))
                                    }
                                }
                                Text("\(Int(w.temperatureC.rounded())) °C · \(w.humidityPct)% hum. · UV \(Int(w.uvIndex.rounded())) · \(w.conditionLabel)")
                                    .font(ImprovingFont.cardTitle(compactForRecovery ? 13.5 : 14.5))
                                    .monospacedDigit()
                                    .foregroundColor(BevelColors.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.84)
                            }

                            Spacer(minLength: 4)

                            Button {
                                showCitySheet = true
                            } label: {
                                Image(systemName: store.isRefreshingWeather ? "arrow.triangle.2.circlepath" : "location.circle")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(BevelColors.skyBlue)
                                    .frame(width: 30, height: 30)
                                    .background(Circle().fill(BevelColors.skySoftBg))
                            }
                            .buttonStyle(.plain)
                        }

                        Text(compactForRecovery ? w.recoveryImpactSummary : w.effortImpactSummary)
                            .font(ImprovingFont.caption(12))
                            .foregroundColor(BevelColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if !compactForRecovery && (w.extraHydrationMl > 0 || w.strainAdjustmentPct > 0) {
                            HStack(spacing: 8) {
                                if w.extraHydrationMl > 0 {
                                    Label("+\(w.extraHydrationMl) ml agua", systemImage: "drop.fill")
                                        .font(ImprovingFont.caption(11))
                                        .fontWeight(.semibold)
                                        .foregroundColor(BevelColors.skyBlue)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(BevelColors.skySoftBg))
                                }
                                if w.strainAdjustmentPct > 0 {
                                    Label("Esfuerzo −\(w.strainAdjustmentPct)%", systemImage: "flame.fill")
                                        .font(ImprovingFont.caption(11))
                                        .fontWeight(.semibold)
                                        .foregroundColor(accent)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(accent.opacity(0.14)))
                                }
                                Spacer()
                            }
                        }
                    }
                    .padding(compactForRecovery ? 13 : 15)
                }
            } else {
                Button {
                    showCitySheet = true
                } label: {
                    BevelCard(cornerRadius: 16) {
                        HStack(spacing: 10) {
                            Image(systemName: "sun.max.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(BevelColors.amberStart)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(BevelColors.amberSoftBg))
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Activar contexto meteorológico (Open-Meteo)")
                                    .font(ImprovingFont.cardTitle(13))
                                    .foregroundColor(BevelColors.textPrimary)
                                Text("Gratis y sin API Key · explica deriva de pulso por calor/humedad y ajusta agua")
                                    .font(ImprovingFont.caption(11))
                                    .foregroundColor(BevelColors.textSecondary)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(BevelColors.textMuted)
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 11)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showCitySheet) {
            WeatherCitySetupSheet(store: store, onClose: { showCitySheet = false })
        }
        .task {
            if store.dayOffset == 0 {
                store.refreshWeatherContext(force: false, requestGPS: false)
            }
        }
    }
}

struct WeatherCitySetupSheet: View {
    @ObservedObject var store: ImprovingStore
    let onClose: () -> Void

    @State private var cityDraft: String = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                BevelCard(cornerRadius: 18) {
                    VStack(alignment: .leading, spacing: 11) {
                        Text("CLIMA LOCAL CON OPEN-METEO (GRATIS)")
                            .font(ImprovingFont.microLabel(10.5))
                            .foregroundColor(BevelColors.skyBlue)
                        Text("Introduce tu ciudad o usa tu ubicación puntual para obtener temperatura, humedad e índice UV reales sin API Key.")
                            .font(ImprovingFont.caption(12.5))
                            .foregroundColor(BevelColors.textSecondary)

                        TextField("Ej: Madrid, Bilbao, Valencia, Barcelona…", text: $cityDraft)
                            .font(ImprovingFont.body(14.5))
                            .foregroundColor(BevelColors.textPrimary)
                            .padding(11)
                            .background(RoundedRectangle(cornerRadius: 12).fill(BevelColors.cardSubtle))
                            .onSubmit {
                                store.updateWeatherCity(cityDraft)
                                onClose()
                            }

                        HStack(spacing: 10) {
                            Button {
                                AppHaptics.selection()
                                store.updateWeatherCity(cityDraft)
                                onClose()
                            } label: {
                                Text("Guardar ciudad")
                                    .font(ImprovingFont.caption(13))
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                                    .background(Capsule().fill(BevelColors.emeraldEnd))
                            }

                            Button {
                                AppHaptics.selection()
                                store.weatherCityName = ""
                                store.refreshWeatherContext(force: true, requestGPS: true)
                                onClose()
                            } label: {
                                Label("Usar GPS", systemImage: "location.fill")
                                    .font(ImprovingFont.caption(13))
                                    .fontWeight(.bold)
                                    .foregroundColor(BevelColors.skyBlue)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                                    .background(Capsule().fill(BevelColors.skySoftBg))
                            }
                        }

                        if store.weatherSnapshot != nil {
                            Button(role: .destructive) {
                                store.updateWeatherCity("")
                                onClose()
                            } label: {
                                Text("Desactivar clima local")
                                    .font(ImprovingFont.caption(12))
                                    .foregroundColor(BevelColors.coralHigh)
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 4)
                            }
                        }
                    }
                    .padding(15)
                }
                Spacer()
            }
            .padding(16)
            .background(BevelColors.canvas.ignoresSafeArea())
            .navigationTitle("Contexto Meteorológico")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar", action: onClose)
                }
            }
            .onAppear {
                cityDraft = store.weatherCityName
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Dynamic Strain-Based Carb Cycling Card (Nutrition)

struct DynamicCarbCyclingCard: View {
    @ObservedObject var store: ImprovingStore

    var body: some View {
        let dyn = store.dynamicStrainNutritionSnapshot
        let accent: Color = !dyn.isEnabled
            ? BevelColors.textMuted
            : (dyn.isHighLoad ? BevelColors.amberStart : (dyn.isRestDay ? BevelColors.greenPrimary : BevelColors.skyBlue))

        BevelCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 9) {
                    Image(systemName: dyn.phaseIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(accent)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(accent.opacity(0.14)))

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text("CARB CYCLING POR STRAIN")
                                .font(ImprovingFont.microLabel(9.5))
                                .foregroundColor(BevelColors.textMuted)
                            if dyn.isEnabled && (dyn.isHighLoad || dyn.isRestDay) {
                                Text(dyn.phaseTitle)
                                    .font(ImprovingFont.microLabel(9.5))
                                    .foregroundColor(accent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(accent.opacity(0.14)))
                            }
                        }
                        Text(dyn.summaryText)
                            .font(ImprovingFont.caption(12))
                            .foregroundColor(BevelColors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 4)

                    Toggle("", isOn: Binding(
                        get: { store.dynamicStrainNutritionEnabled },
                        set: { store.setDynamicStrainNutrition(enabled: $0) }
                    ))
                    .labelsHidden()
                    .tint(BevelColors.emeraldEnd)
                }

                if dyn.isEnabled && dyn.isManualOverrideBlocking {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(BevelColors.amberStart)
                        Text("Tienes metas manuales activas.")
                            .font(ImprovingFont.caption(11))
                            .foregroundColor(BevelColors.amberStart)
                        Spacer()
                        Button("Usar automático") {
                            AppHaptics.selection()
                            store.clearCustomNutritionGoals()
                        }
                        .font(ImprovingFont.caption(11))
                        .fontWeight(.bold)
                        .foregroundColor(BevelColors.skyBlue)
                    }
                } else if let elec = dyn.electrolyteNote, dyn.isEnabled {
                    Label(elec, systemImage: "drop.fill")
                        .font(ImprovingFont.caption(11.5))
                        .foregroundColor(BevelColors.skyBlue)
                }
            }
            .padding(13)
        }
    }
}

// MARK: - Coach Personality Selector & Searchable Insights Archive Sheet (Bevel Intelligence + WHOOP)

struct CoachPersonalityAndArchiveSheet: View {
    @ObservedObject var store: ImprovingStore
    let onOpenSettings: (() -> Void)?
    let onClose: () -> Void

    @State private var selectedTab: Int
    @State private var searchQuery: String = ""
    @State private var sectionFilter: String = "Todos"

    init(
        store: ImprovingStore,
        initialTab: Int = 0,
        onOpenSettings: (() -> Void)? = nil,
        onClose: @escaping () -> Void
    ) {
        self.store = store
        self.onOpenSettings = onOpenSettings
        self.onClose = onClose
        _selectedTab = State(initialValue: initialTab)
    }

    private let sectionFilterOptions = ["Todos", "Diario", "Resumen del día", "Recuperación", "Esfuerzo", "Sueño", "Fitness"]

    private var filteredArchive: [ArchivedAiInsight] {
        store.archivedAiInsights.filter { item in
            let secOk = sectionFilter == "Todos" || item.sectionTitle == sectionFilter
            let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if q.isEmpty { return secOk }
            let hay = "\(item.headline) \(item.body) \(item.sectionTitle) \(item.dateIso)".folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
            let needle = q.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
            return secOk && hay.contains(needle)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Vista", selection: $selectedTab) {
                    Text("Personalidad").tag(0)
                    Text("Archivo (\(store.archivedAiInsights.count))").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 6)

                if selectedTab == 0 {
                    personalityTabView
                } else {
                    archiveTabView
                }
            }
            .background(BevelColors.canvas.ignoresSafeArea())
            .navigationTitle(selectedTab == 0 ? "Estilo del Coach IA" : "Archivo de Insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo", action: onClose)
                        .fontWeight(.bold)
                }
            }
        }
        .presentationDetents([.large])
    }

    private var personalityTabView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Personalidad del entrenador")
                    .font(ImprovingFont.sectionTitle(16.5))
                    .foregroundColor(BevelColors.textPrimary)

                ForEach(CoachPersonalityTone.allCases) { tone in
                    let active = store.coachPersonalityTone == tone
                    Button {
                        AppHaptics.selection()
                        store.setCoachPersonality(tone: tone, detail: store.coachDetailLevel)
                    } label: {
                        BevelCard(cornerRadius: 16) {
                            HStack(spacing: 12) {
                                Image(systemName: tone.icon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(active ? .white : BevelColors.indigoEnd)
                                    .frame(width: 36, height: 36)
                                    .background(Circle().fill(active ? BevelColors.indigoEnd : BevelColors.indigoSoftBg))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tone.rawValue)
                                        .font(ImprovingFont.cardTitle(14.5))
                                        .foregroundColor(BevelColors.textPrimary)
                                    Text(tone.shortSubtitle)
                                        .font(ImprovingFont.caption(12))
                                        .foregroundColor(BevelColors.textSecondary)
                                }
                                Spacer()
                                if active {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(BevelColors.greenPrimary)
                                }
                            }
                            .padding(13)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(active ? BevelColors.indigoEnd.opacity(0.7) : .clear, lineWidth: 1.2)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Text("Nivel de detalle")
                    .font(ImprovingFont.sectionTitle(16.5))
                    .foregroundColor(BevelColors.textPrimary)
                    .padding(.top, 4)

                HStack(spacing: 8) {
                    ForEach(CoachDetailLevel.allCases) { lvl in
                        let sel = store.coachDetailLevel == lvl
                        Button {
                            AppHaptics.selection()
                            store.setCoachPersonality(tone: store.coachPersonalityTone, detail: lvl)
                        } label: {
                            Text(lvl.rawValue)
                                .font(ImprovingFont.caption(13))
                                .fontWeight(.bold)
                                .foregroundColor(sel ? .white : BevelColors.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(Capsule().fill(sel ? BevelColors.emeraldEnd : BevelColors.card))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("Aplica automáticamente al chat con el Coach IA y a todas las tarjetas de valoración en Hoy, Diario, Esfuerzo, Recuperación y Sueño.")
                    .font(ImprovingFont.caption(12))
                    .foregroundColor(BevelColors.textMuted)

                if let onOpenSettings {
                    Button {
                        AppHaptics.selection()
                        onOpenSettings()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Configurar API Key y modelo Gemini")
                                .font(ImprovingFont.caption(13))
                                .fontWeight(.bold)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(BevelColors.skyBlue)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(BevelColors.skySoftBg))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
            .padding(16)
        }
    }

    private var archiveTabView: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(BevelColors.textMuted)
                TextField("Buscar en tus valoraciones pasadas…", text: $searchQuery)
                    .font(ImprovingFont.body(14))
                    .foregroundColor(BevelColors.textPrimary)
                if !searchQuery.isEmpty {
                    Button { searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(BevelColors.textMuted)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 12).fill(BevelColors.card))
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(sectionFilterOptions, id: \.self) { opt in
                        let sel = sectionFilter == opt
                        Button {
                            sectionFilter = opt
                        } label: {
                            Text(opt)
                                .font(ImprovingFont.caption(12))
                                .fontWeight(.semibold)
                                .foregroundColor(sel ? .white : BevelColors.textSecondary)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(sel ? BevelColors.indigoEnd : BevelColors.card))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }

            if filteredArchive.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "archivebox")
                        .font(.system(size: 32))
                        .foregroundColor(BevelColors.textMuted)
                    Text(store.archivedAiInsights.isEmpty ? "Todavía no hay insights archivados" : "Sin resultados para «\(searchQuery)»")
                        .font(ImprovingFont.cardTitle(15))
                        .foregroundColor(BevelColors.textPrimary)
                    Text("Cada valoración del Diario, Hoy, Esfuerzo, Recuperación y respuestas del Coach se guardan automáticamente aquí.")
                        .font(ImprovingFont.caption(12.5))
                        .foregroundColor(BevelColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredArchive) { item in
                            BevelCard(cornerRadius: 16) {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("\(item.emoji) \(item.sectionTitle.uppercased())")
                                            .font(ImprovingFont.microLabel(10))
                                            .foregroundColor(BevelColors.skyBlue)
                                        Spacer()
                                        Text(item.dateIso)
                                            .font(ImprovingFont.caption(11))
                                            .monospacedDigit()
                                            .foregroundColor(BevelColors.textMuted)
                                        Button {
                                            store.deleteArchivedInsight(id: item.id)
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.system(size: 11))
                                                .foregroundColor(BevelColors.textMuted)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    Text(item.headline)
                                        .font(ImprovingFont.cardTitle(14.5))
                                        .foregroundColor(BevelColors.textPrimary)
                                    Text(item.body)
                                        .font(ImprovingFont.caption(12.5))
                                        .foregroundColor(BevelColors.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(13)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
        }
    }
}

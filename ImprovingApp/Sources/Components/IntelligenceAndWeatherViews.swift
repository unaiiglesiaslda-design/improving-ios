import SwiftUI
import AVFoundation

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

    private let sectionFilterOptions = ["Todos", "Chat Coach", "Diario", "Resumen del día", "Recuperación", "Esfuerzo", "Sueño", "Fitness"]

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

                Toggle(isOn: Binding(
                    get: { store.voiceReadoutAutoEnabled },
                    set: {
                        store.voiceReadoutAutoEnabled = $0
                        if !$0 { CoachVoiceSynthesizer.shared.stop() }
                        store.persistState()
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Respuestas por voz automáticas")
                            .font(ImprovingFont.cardTitle(13.5))
                            .foregroundColor(BevelColors.textPrimary)
                        Text("Lee en voz natural española cada respuesta del Coach (sin cortar tu música al terminar).")
                            .font(ImprovingFont.caption(11.5))
                            .foregroundColor(BevelColors.textSecondary)
                    }
                }
                .tint(BevelColors.emeraldEnd)
                .padding(.top, 4)

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


// MARK: - Natural Spanish Voice Synthesizer (100% Local AVSpeechSynthesizer + Clean AudioSession Deactivation)

final class CoachVoiceSynthesizer: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = CoachVoiceSynthesizer()

    @Published var speakingMessageId: String? = nil
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func toggleSpeak(text: String, messageId: String) {
        if speakingMessageId == messageId && synthesizer.isSpeaking {
            stop()
        } else {
            speak(text: text, messageId: messageId)
        }
    }

    func speak(text: String, messageId: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        let utterance = AVSpeechUtterance(string: clean)
        utterance.voice = AVSpeechSynthesisVoice(language: "es-ES")
        utterance.rate = 0.51
        utterance.pitchMultiplier = 1.0
        speakingMessageId = messageId
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        DispatchQueue.main.async {
            self.speakingMessageId = nil
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.speakingMessageId = nil
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.speakingMessageId = nil
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

// MARK: - Proactive 24-48h Immunity, Overreaching & Subjective Sensation Radar Card

struct ProactiveImmunityRadarCard: View {
    @ObservedObject var store: ImprovingStore

    var body: some View {
        let radar = store.proactiveImmunityRadarSnapshot
        if radar.hasActiveWarning {
            let accent: Color = radar.riskLevel >= 2
                ? BevelColors.coralHigh
                : (radar.riskLevel == 1 ? BevelColors.amberStart : BevelColors.skyBlue)

            BevelCard(cornerRadius: 18) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 10) {
                        Image(systemName: radar.riskLevel >= 2 ? "cross.vial.fill" : "waveform.path.ecg.rectangle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(accent)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(accent.opacity(0.15)))

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("RADAR PROACTIVO IA")
                                    .font(ImprovingFont.microLabel(9.5))
                                    .foregroundColor(BevelColors.textMuted)
                                Text("Confianza \(radar.confidencePct)%")
                                    .font(ImprovingFont.microLabel(9.5))
                                    .foregroundColor(accent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(accent.opacity(0.14)))
                            }
                            Text(radar.headline)
                                .font(ImprovingFont.cardTitle(14))
                                .foregroundColor(BevelColors.textPrimary)
                        }
                        Spacer()
                    }

                    Text(radar.summary)
                        .font(ImprovingFont.caption(12))
                        .foregroundColor(BevelColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !radar.signals.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(radar.signals, id: \.self) { sig in
                                    Text(sig)
                                        .font(ImprovingFont.caption(10.5))
                                        .fontWeight(.semibold)
                                        .foregroundColor(accent)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(accent.opacity(0.12)))
                                }
                            }
                        }
                    }

                    if !store.autoDeloadModeActive && radar.riskLevel >= 1 {
                        Button {
                            store.applyImmunityProtectiveProtocol()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "shield.checkered")
                                    .font(.system(size: 11.5, weight: .bold))
                                Text("Aplicar protocolo protector (Descarga + Sueño 100% + Agua)")
                                    .font(ImprovingFont.caption(11.5))
                                    .fontWeight(.bold)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(accent))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(accent.opacity(0.35), lineWidth: 0.9)
            )
        }
    }
}

// MARK: - Proactive Evening Check-In Card (20:00+ Night Optimization)

struct EveningCheckInProactiveCard: View {
    @ObservedObject var store: ImprovingStore
    let onAskDinnerCoach: () -> Void

    var body: some View {
        let ev = store.eveningCheckInSnapshot
        BevelCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 9) {
                    Image(systemName: "moon.haze.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(BevelColors.periwinkleStart)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(BevelColors.indigoSoftBg))
                    VStack(alignment: .leading, spacing: 1.5) {
                        Text("CIERRE NOCTURNO PROACTIVO")
                            .font(ImprovingFont.microLabel(9.5))
                            .foregroundColor(BevelColors.textMuted)
                        Text(ev.headline)
                            .font(ImprovingFont.cardTitle(13.5))
                            .foregroundColor(BevelColors.textPrimary)
                    }
                    Spacer()
                }

                Text(ev.summaryText)
                    .font(ImprovingFont.caption(12))
                    .foregroundColor(BevelColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if ev.remainingProteinG > 10 {
                    Button(action: onAskDinnerCoach) {
                        HStack(spacing: 5) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11, weight: .bold))
                            Text("Proponer cena para clavar +\(ev.remainingProteinG) g proteína")
                                .font(ImprovingFont.caption(11.5))
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(BevelColors.indigoEnd))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(13)
        }
    }
}

// MARK: - Hyper-Personalized Physiological Twin & Interactive What-If Simulator

struct PersonalTwinAndSimulatorCard: View {
    @ObservedObject var store: ImprovingStore
    @State private var showSimulatorSheet: Bool = false

    var body: some View {
        let twin = store.personalSensitivityTwinSnapshot

        BevelCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "person.wave.2.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(BevelColors.skyBlue)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(BevelColors.skySoftBg))

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("GEMELO FISIOLÓGICO PERSONAL")
                                .font(ImprovingFont.microLabel(9.5))
                                .foregroundColor(BevelColors.textMuted)
                            Text(twin.isCalibrated ? "Calibrado" : "Aprendiendo")
                                .font(ImprovingFont.microLabel(9.5))
                                .foregroundColor(twin.isCalibrated ? BevelColors.greenPrimary : BevelColors.amberStart)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill((twin.isCalibrated ? BevelColors.greenPrimary : BevelColors.amberStart).opacity(0.15)))
                        }
                        Text("Tus umbrales únicos aprendidos en local")
                            .font(ImprovingFont.cardTitle(14))
                            .foregroundColor(BevelColors.textPrimary)
                    }
                    Spacer()
                }

                HStack(spacing: 8) {
                    twinMetricPill(icon: "cup.and.saucer.fill", label: "Corte café", value: twin.recommendedCaffeineCutoffLabel)
                    twinMetricPill(icon: "fork.knife", label: "Cena ideal", value: String(format: "≥%.1f h", locale: Locale(identifier: "es_ES"), twin.optimalDinnerLeadHours))
                    twinMetricPill(icon: "bed.double.fill", label: "Sueño pico", value: String(format: "%.1f h", locale: Locale(identifier: "es_ES"), twin.personalOptimalSleepHours))
                    twinMetricPill(icon: "flame.fill", label: "Strain dulce", value: String(format: "%.1f", locale: Locale(identifier: "es_ES"), twin.personalStrainSweetSpot))
                }

                Button {
                    AppHaptics.selection()
                    showSimulatorSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.below.waveform")
                            .font(.system(size: 12, weight: .bold))
                        Text("Simulador «¿Qué pasa mañana si…?»")
                            .font(ImprovingFont.caption(12.5))
                            .fontWeight(.bold)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(BevelColors.indigoEnd))
                }
                .buttonStyle(.plain)
            }
            .padding(14)
        }
        .sheet(isPresented: $showSimulatorSheet) {
            WhatIfPhysiologySimulatorSheet(store: store, onClose: { showSimulatorSheet = false })
        }
    }

    private func twinMetricPill(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(BevelColors.skyBlue)
            Text(value)
                .font(ImprovingFont.cardTitle(12.5))
                .monospacedDigit()
                .foregroundColor(BevelColors.textPrimary)
            Text(label)
                .font(ImprovingFont.caption(9.5))
                .foregroundColor(BevelColors.textMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 11).fill(BevelColors.cardSubtle))
    }
}

struct WhatIfPhysiologySimulatorSheet: View {
    @ObservedObject var store: ImprovingStore
    let onClose: () -> Void

    @State private var input = WhatIfScenarioInput()

    var body: some View {
        let sim = store.simulateWhatIf(input)
        let accent: Color = sim.predictedRecoveryPct >= 67
            ? BevelColors.greenPrimary
            : (sim.predictedRecoveryPct >= 34 ? BevelColors.amberStart : BevelColors.coralHigh)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Live Prediction Header Card
                    BevelCard(cornerRadius: 20) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("RECUPERACIÓN ESTIMADA MAÑANA")
                                        .font(ImprovingFont.microLabel(10))
                                        .foregroundColor(BevelColors.textMuted)
                                    Text(sim.verdictTitle)
                                        .font(ImprovingFont.sectionTitle(17))
                                        .foregroundColor(accent)
                                }
                                Spacer()
                                Text("\(sim.predictedRecoveryPct)%")
                                    .font(ImprovingFont.displayLarge(34))
                                    .monospacedDigit()
                                    .foregroundColor(accent)
                            }

                            HStack(spacing: 8) {
                                simDeltaBadge(label: "VFC", value: String(format: "%+.1f ms", locale: Locale(identifier: "es_ES"), sim.hrvDeltaMs), good: sim.hrvDeltaMs >= 0)
                                simDeltaBadge(label: "Profundo", value: String(format: "%+d min", sim.deepSleepDeltaMin), good: sim.deepSleepDeltaMin >= 0)
                                simDeltaBadge(label: "FCR", value: String(format: "%+.1f ppm", locale: Locale(identifier: "es_ES"), sim.rhrDeltaBpm), good: sim.rhrDeltaBpm <= 0)
                            }

                            Text(sim.explanation)
                                .font(ImprovingFont.caption(12))
                                .foregroundColor(BevelColors.textSecondary)
                        }
                        .padding(16)
                    }

                    // Interactive Scenario Sliders
                    BevelCard(cornerRadius: 20) {
                        VStack(alignment: .leading, spacing: 14) {
                            sliderRow(
                                title: "Horas de sueño esta noche",
                                valueText: String(format: "%.1f h", locale: Locale(identifier: "es_ES"), input.sleepHours),
                                value: $input.sleepHours,
                                range: 4.5...10.0,
                                step: 0.5,
                                tint: BevelColors.periwinkleStart
                            )
                            sliderRow(
                                title: "Bebidas de alcohol",
                                valueText: input.alcoholDrinks == 0 ? "0" : String(format: "%.0f copas", input.alcoholDrinks),
                                value: $input.alcoholDrinks,
                                range: 0...6,
                                step: 1,
                                tint: BevelColors.coralHigh
                            )
                            sliderRow(
                                title: "Última cafeína (mg)",
                                valueText: "\(Int(input.caffeineMg)) mg a las \(input.caffeineHour):00",
                                value: $input.caffeineMg,
                                range: 0...300,
                                step: 30,
                                tint: BevelColors.amberStart
                            )
                            if input.caffeineMg > 0 {
                                Stepper("Hora del último café: \(input.caffeineHour):00", value: $input.caffeineHour, in: 7...22)
                                    .font(ImprovingFont.caption(12.5))
                                    .foregroundColor(BevelColors.textSecondary)
                            }
                            sliderRow(
                                title: "Margen cena → acostarse",
                                valueText: String(format: "%.1f h antes", locale: Locale(identifier: "es_ES"), input.dinnerLeadHours),
                                value: $input.dinnerLeadHours,
                                range: 0.5...5.0,
                                step: 0.5,
                                tint: BevelColors.emeraldEnd
                            )

                            Toggle("Sesión física intensa hoy (Strain ≥ 15)", isOn: $input.highStrainSession)
                                .font(ImprovingFont.caption(13))
                                .foregroundColor(BevelColors.textPrimary)
                                .tint(BevelColors.amberStart)

                            Toggle("Magnesio / Sauna / Respiración nocturna", isOn: $input.magnesiumOrSauna)
                                .font(ImprovingFont.caption(13))
                                .foregroundColor(BevelColors.textPrimary)
                                .tint(BevelColors.greenPrimary)
                        }
                        .padding(16)
                    }

                    // Mitigation Protocol
                    BevelCard(cornerRadius: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("PROTOCOLO DE MITIGACIÓN PERSONALIZADO")
                                .font(ImprovingFont.microLabel(10))
                                .foregroundColor(BevelColors.skyBlue)
                            ForEach(sim.mitigationSteps, id: \.self) { step in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(BevelColors.greenPrimary)
                                        .padding(.top, 2)
                                    Text(step)
                                        .font(ImprovingFont.caption(12.5))
                                        .foregroundColor(BevelColors.textPrimary)
                                }
                            }
                        }
                        .padding(15)
                    }
                }
                .padding(16)
            }
            .background(BevelColors.canvas.ignoresSafeArea())
            .navigationTitle("Simulador «¿Qué pasa si…?»")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo", action: onClose).fontWeight(.bold)
                }
            }
            .onAppear {
                let twin = store.personalSensitivityTwinSnapshot
                input.sleepHours = twin.personalOptimalSleepHours
                input.dinnerLeadHours = twin.optimalDinnerLeadHours
            }
        }
    }

    private func simDeltaBadge(label: String, value: String, good: Bool) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(ImprovingFont.cardTitle(13))
                .monospacedDigit()
                .foregroundColor(good ? BevelColors.greenPrimary : BevelColors.coralHigh)
            Text(label)
                .font(ImprovingFont.caption(10))
                .foregroundColor(BevelColors.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.cardSubtle))
    }

    private func sliderRow(title: String, valueText: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(ImprovingFont.caption(12.5))
                    .foregroundColor(BevelColors.textSecondary)
                Spacer()
                Text(valueText)
                    .font(ImprovingFont.cardTitle(13))
                    .monospacedDigit()
                    .foregroundColor(tint)
            }
            Slider(value: value, in: range, step: step)
                .tint(tint)
        }
    }
}

// MARK: - Adaptive Event Periodization Microcycle Card (Fitness) & Setup Sheet

struct AdaptiveMicrocycleCard: View {
    @ObservedObject var store: ImprovingStore
    @State private var showSetupSheet: Bool = false

    var body: some View {
        Group {
            if let micro = store.adaptiveMicrocycleSnapshot {
                let badgeColor = Color(hex: micro.phaseBadgeColorHex)
                BevelCard(cornerRadius: 20) {
                    VStack(alignment: .leading, spacing: 11) {
                        HStack(spacing: 10) {
                            Image(systemName: "flag.checkered")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(badgeColor)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(badgeColor.opacity(0.15)))

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text("MICROCICLO ADAPTATIVO")
                                        .font(ImprovingFont.microLabel(9.5))
                                        .foregroundColor(BevelColors.textMuted)
                                    Text(micro.phaseName)
                                        .font(ImprovingFont.microLabel(9.5))
                                        .foregroundColor(badgeColor)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(badgeColor.opacity(0.15)))
                                }
                                Text("\(micro.plan.title) · Faltan \(micro.daysRemaining) d")
                                    .font(ImprovingFont.cardTitle(14.5))
                                    .foregroundColor(BevelColors.textPrimary)
                            }
                            Spacer()
                            Button {
                                showSetupSheet = true
                            } label: {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(BevelColors.textSecondary)
                                    .frame(width: 30, height: 30)
                                    .background(Circle().fill(BevelColors.cardSubtle))
                            }
                            .buttonStyle(.plain)
                        }

                        Text(micro.todayPrescription)
                            .font(ImprovingFont.caption(12))
                            .foregroundColor(BevelColors.textSecondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(micro.days) { d in
                                    let c = Color(hex: d.accentHex)
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(d.dayShortLabel.uppercased())
                                                .font(ImprovingFont.microLabel(9.5))
                                                .foregroundColor(d.isToday ? .white : BevelColors.textMuted)
                                            Spacer()
                                            Text(d.targetStrainRange)
                                                .font(ImprovingFont.caption(10))
                                                .monospacedDigit()
                                                .foregroundColor(c)
                                        }
                                        Text(d.sessionTitle)
                                            .font(ImprovingFont.caption(11.5))
                                            .fontWeight(.semibold)
                                            .foregroundColor(BevelColors.textPrimary)
                                            .lineLimit(2)
                                        Text(d.intensityTag)
                                            .font(ImprovingFont.microLabel(9))
                                            .foregroundColor(c)
                                    }
                                    .frame(width: 132, alignment: .leading)
                                    .padding(10)
                                    .background(RoundedRectangle(cornerRadius: 13).fill(d.isToday ? c.opacity(0.16) : BevelColors.cardSubtle))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 13)
                                            .strokeBorder(d.isToday ? c.opacity(0.65) : .clear, lineWidth: 1)
                                    )
                                }
                            }
                        }
                    }
                    .padding(15)
                }
            } else {
                Button {
                    showSetupSheet = true
                } label: {
                    BevelCard(cornerRadius: 18) {
                        HStack(spacing: 11) {
                            Image(systemName: "flag.checkered")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(BevelColors.periwinkleStart)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(BevelColors.indigoSoftBg))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Periodización por objetivo o competición")
                                    .font(ImprovingFont.cardTitle(13.5))
                                    .foregroundColor(BevelColors.textPrimary)
                                Text("Crea un microciclo semanal vivo con taper que se recalibra cada día a tu recuperación")
                                    .font(ImprovingFont.caption(11.5))
                                    .foregroundColor(BevelColors.textSecondary)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(BevelColors.indigoEnd)
                        }
                        .padding(14)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showSetupSheet) {
            GoalEventSetupSheet(store: store, onClose: { showSetupSheet = false })
        }
    }
}

struct GoalEventSetupSheet: View {
    @ObservedObject var store: ImprovingStore
    let onClose: () -> Void

    @State private var titleDraft: String = ""
    @State private var focusDraft: String = "Híbrido / Rendimiento"
    @State private var targetDate: Date = Calendar.current.date(byAdding: .day, value: 45, to: Date()) ?? Date()

    private let focusOptions = ["Carrera / Resistencia", "Fuerza / Hipertrofia", "Híbrido / Rendimiento", "Definición / Salud"]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                BevelCard(cornerRadius: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("OBJETIVO CON FECHA Y PERIODIZACIÓN VIVA")
                            .font(ImprovingFont.microLabel(10))
                            .foregroundColor(BevelColors.skyBlue)

                        TextField("Ej: Media Maratón Valencia, Bloque Fuerza 8 sem…", text: $titleDraft)
                            .font(ImprovingFont.body(14.5))
                            .foregroundColor(BevelColors.textPrimary)
                            .padding(11)
                            .background(RoundedRectangle(cornerRadius: 12).fill(BevelColors.cardSubtle))

                        Picker("Foco", selection: $focusDraft) {
                            ForEach(focusOptions, id: \.self) { opt in
                                Text(opt).tag(opt)
                            }
                        }
                        .pickerStyle(.menu)

                        DatePicker("Fecha objetivo", selection: $targetDate, in: Date()..., displayedComponents: .date)
                            .font(ImprovingFont.body(14))
                            .foregroundColor(BevelColors.textPrimary)

                        Button {
                            let clean = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !clean.isEmpty else { return }
                            let plan = GoalEventPlan(
                                id: store.activeGoalEventPlan?.id ?? "goal_\(UUID().uuidString.prefix(8))",
                                title: clean,
                                sportFocus: focusDraft,
                                targetDateIso: store.isoFormatter.string(from: targetDate),
                                createdAtIso: store.isoFormatter.string(from: Date()),
                                notes: ""
                            )
                            store.setGoalEventPlan(plan)
                            onClose()
                        } label: {
                            Text("Activar microciclo inteligente")
                                .font(ImprovingFont.cardTitle(14))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Capsule().fill(BevelColors.indigoEnd))
                        }

                        if store.activeGoalEventPlan != nil {
                            Button(role: .destructive) {
                                store.setGoalEventPlan(nil)
                                onClose()
                            } label: {
                                Text("Eliminar plan activo")
                                    .font(ImprovingFont.caption(12.5))
                                    .foregroundColor(BevelColors.coralHigh)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .padding(15)
                }
                Spacer()
            }
            .padding(16)
            .background(BevelColors.canvas.ignoresSafeArea())
            .navigationTitle("Planificar Objetivo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar", action: onClose)
                }
            }
            .onAppear {
                if let cur = store.activeGoalEventPlan {
                    titleDraft = cur.title
                    focusDraft = cur.sportFocus
                    if let dt = store.isoFormatter.date(from: cur.targetDateIso) {
                        targetDate = dt
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Post-Workout AI Physiological Audit Card (WorkoutDetailScreen)

struct PostWorkoutPhysiologyAuditCard: View {
    let audit: PostWorkoutPhysiologyAudit

    var body: some View {
        let accent = Color(hex: audit.efficiencyColorHex)
        BevelCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "bolt.heart.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(accent)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(accent.opacity(0.15)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AUDITORÍA POST-ENTRENO IA")
                            .font(ImprovingFont.microLabel(9.5))
                            .foregroundColor(BevelColors.textMuted)
                        Text(audit.efficiencyLabel)
                            .font(ImprovingFont.cardTitle(14.5))
                            .foregroundColor(accent)
                    }
                    Spacer()
                }

                Text(audit.summaryText)
                    .font(ImprovingFont.caption(12.5))
                    .foregroundColor(BevelColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    refillPill(label: "Carbos", value: "+\(audit.glycogenRefillCarbsG) g", color: BevelColors.amberStart)
                    refillPill(label: "Proteína", value: "+\(audit.proteinRefillG) g", color: BevelColors.greenPrimary)
                    refillPill(label: "Rehidratar", value: "+\(audit.rehydrationMl) ml", color: BevelColors.skyBlue)
                    refillPill(label: "Sodio", value: "~\(audit.sodiumMg) mg", color: BevelColors.periwinkleStart)
                }
            }
            .padding(15)
        }
    }

    private func refillPill(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(ImprovingFont.cardTitle(12.5))
                .monospacedDigit()
                .foregroundColor(color)
            Text(label)
                .font(ImprovingFont.caption(10))
                .foregroundColor(BevelColors.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.cardSubtle))
    }
}

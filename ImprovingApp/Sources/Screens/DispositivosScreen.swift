import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

struct DispositivosScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void

    @State private var showingImporter = false
    @State private var showShortcutsGuide = false
    @State private var copiedUrlToast = false
    @State private var apiKeyDraft: String = ""
    @State private var selectedModelDraft: String = "gemini-2.5-flash"
    @State private var shortcutNameDraft: String = "Sync Improving (Automático)"
    @State private var autoRunShortcutToggle: Bool = false
    @State private var savedBanner: Bool = false
    @State private var profileSavedBanner: Bool = false
    @State private var darkToggle: Bool = BevelColors.isDarkMode

    // Editable Personal Physiology Profile + Avatar Photo Picker
    @State private var profileDraft: UserPhysiologyProfile = UserPhysiologyProfile()
    @State private var birthDateDraft: Date = Date()
    @State private var selectedAvatarPhoto: PhotosPickerItem? = nil
    @State private var savingAvatarPhoto: Bool = false

    private var minBirthDate: Date {
        Calendar.current.date(byAdding: .year, value: -95, to: Date()) ?? Date()
    }
    private var maxBirthDate: Date {
        Calendar.current.date(byAdding: .year, value: -13, to: Date()) ?? Date()
    }

    var body: some View {
        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: profileDraft)
        let exactAge = Int(profileDraft.effectiveAgeYears.rounded(.down))
        let sleepH = Int(norms.sleepTargetHours)
        let sleepM = Int(((norms.sleepTargetHours - Double(sleepH)) * 60.0).rounded())

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DetailSheetHeader(title: "Dispositivos y Ajustes", onBack: onBack)

                // Personal Physiological Profile & Photo Editor Card
                BevelCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 14) {
                            PhotosPicker(selection: $selectedAvatarPhoto, matching: .images, photoLibrary: .shared()) {
                                ZStack(alignment: .bottomTrailing) {
                                    UserProfileAvatarView(
                                        photoPath: profileDraft.profilePhotoPath,
                                        initials: profileDraft.initials,
                                        size: 64,
                                        showGradientRing: true,
                                        ringWidth: 2.4
                                    )
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(width: 22, height: 22)
                                        .background(Circle().fill(BevelColors.emeraldEnd))
                                        .overlay(Circle().strokeBorder(BevelColors.card, lineWidth: 1.8))
                                        .offset(x: 2, y: 2)
                                }
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(profileDraft.fullName.isEmpty ? "Tu Perfil Fisiológico" : profileDraft.fullName)
                                    .font(ImprovingFont.cardTitle(16))
                                    .foregroundColor(BevelColors.textPrimary)
                                Text("\(exactAge) años · \(profileDraft.sex.rawValue) · \(Int(profileDraft.heightCm.rounded())) cm · \(String(format: "%.1f", locale: Locale(identifier: "es_ES"), profileDraft.weightKg)) kg")
                                    .font(ImprovingFont.caption(11.5))
                                    .foregroundColor(BevelColors.textSecondary)

                                HStack(spacing: 8) {
                                    PhotosPicker(selection: $selectedAvatarPhoto, matching: .images, photoLibrary: .shared()) {
                                        Text(savingAvatarPhoto ? "Guardando…" : (profileDraft.profilePhotoPath != nil ? "Cambiar foto" : "Añadir foto"))
                                            .font(ImprovingFont.caption(11))
                                            .fontWeight(.semibold)
                                            .foregroundColor(BevelColors.skyBlue)
                                    }
                                    if profileDraft.profilePhotoPath != nil {
                                        Button("Quitar") {
                                            ProfilePhotoStorage.deleteSavedPhotos()
                                            profileDraft.profilePhotoPath = nil
                                            store.updateProfile(profileDraft)
                                        }
                                        .font(ImprovingFont.caption(11))
                                        .foregroundColor(BevelColors.textMuted)
                                    }
                                }
                            }
                            Spacer()
                        }

                        HStack(spacing: 10) {
                            TextField("Nombre", text: $profileDraft.userName)
                                .font(ImprovingFont.body(13.5))
                                .foregroundColor(BevelColors.textPrimary)
                                .textInputAutocapitalization(.words)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 9)
                                .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.cardSubtle))
                            TextField("Apellido", text: $profileDraft.lastName)
                                .font(ImprovingFont.body(13.5))
                                .foregroundColor(BevelColors.textPrimary)
                                .textInputAutocapitalization(.words)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 9)
                                .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.cardSubtle))
                        }

                        HStack {
                            Text("Fecha de nacimiento")
                                .font(ImprovingFont.caption(12.5))
                                .foregroundColor(BevelColors.textSecondary)
                            Spacer()
                            DatePicker(
                                "",
                                selection: $birthDateDraft,
                                in: minBirthDate...maxBirthDate,
                                displayedComponents: .date
                            )
                            .labelsHidden()
                            .environment(\.locale, Locale(identifier: "es_ES"))
                        }

                        HStack(spacing: 8) {
                            ForEach(BiologicalSexOption.allCases, id: \.self) { opt in
                                let active = profileDraft.sex == opt
                                Button {
                                    profileDraft.sex = opt
                                } label: {
                                    Text(opt.rawValue)
                                        .font(ImprovingFont.caption(12))
                                        .fontWeight(.semibold)
                                        .foregroundColor(active ? .white : BevelColors.textSecondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(RoundedRectangle(cornerRadius: 10).fill(active ? BevelColors.emeraldEnd : BevelColors.cardSubtle))
                                }
                            }
                        }

                        HStack(spacing: 10) {
                            compactStepper("Altura", "\(Int(profileDraft.heightCm.rounded())) cm",
                                           onMinus: { profileDraft.heightCm = max(135, profileDraft.heightCm - 1) },
                                           onPlus: { profileDraft.heightCm = min(220, profileDraft.heightCm + 1) })
                            compactStepper("Peso", String(format: "%.1f kg", locale: Locale(identifier: "es_ES"), profileDraft.weightKg),
                                           onMinus: { profileDraft.weightKg = max(35, ((profileDraft.weightKg - 0.5) * 10).rounded() / 10) },
                                           onPlus: { profileDraft.weightKg = min(180, ((profileDraft.weightKg + 0.5) * 10).rounded() / 10) })
                        }

                        HStack(spacing: 10) {
                            Button {
                                profileDraft.userName = profileDraft.userName.trimmingCharacters(in: .whitespacesAndNewlines)
                                profileDraft.lastName = profileDraft.lastName.trimmingCharacters(in: .whitespacesAndNewlines)
                                profileDraft.setBirthDate(birthDateDraft)
                                profileDraft.profileSetupVersion = 2
                                profileDraft.onboardingCompleted = true
                                store.updateProfile(profileDraft)
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                profileSavedBanner = true
                            } label: {
                                Text("Guardar y recalcular métricas")
                                    .font(ImprovingFont.caption(12.5))
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(Capsule().fill(BevelColors.emeraldEnd))
                            }

                            if profileSavedBanner {
                                Label("Actualizado", systemImage: "checkmark.circle.fill")
                                    .font(ImprovingFont.caption(11.5))
                                    .foregroundColor(BevelColors.greenPrimary)
                            }
                            Spacer()
                        }

                        Text("Calibración activa: VFC esperada \(Int(norms.hrvExpectedMs.rounded())) ms · Sueño objetivo \(sleepH)h \(String(format: "%02d", sleepM))m · IMC \(String(format: "%.1f", locale: Locale(identifier: "es_ES"), norms.bmi)) (\(norms.bmiStatusLabel))")
                            .font(ImprovingFont.caption(11))
                            .foregroundColor(BevelColors.textMuted)
                    }
                    .padding(16)
                }
                .padding(.horizontal, 16)

                // Zero-Entitlement Automatic Sync via Apple Shortcuts (Atajos) & Files Folder
                BevelCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Image(systemName: "bolt.badge.automatic.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(BevelColors.skyBlue)
                                .frame(width: 38, height: 38)
                                .background(Circle().fill(BevelColors.skySoftBg))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Atajos de Apple · Sync Automática")
                                    .font(ImprovingFont.cardTitle(15.5))
                                    .foregroundColor(BevelColors.textPrimary)
                                Text("Sin cuenta Apple Developer · 100 % automático en segundo plano")
                                    .font(ImprovingFont.caption(11.5))
                                    .foregroundColor(BevelColors.greenPrimary)
                            }
                            Spacer()
                        }

                        HStack(spacing: 6) {
                            Image(systemName: store.isAutoSyncing ? "arrow.triangle.2.circlepath" : "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(store.isAutoSyncing ? BevelColors.amberStart : BevelColors.skyBlue)
                            Text(store.autoSyncStatusText)
                                .font(ImprovingFont.caption(12))
                                .foregroundColor(BevelColors.textSecondary)
                                .lineLimit(2)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.cardSubtle))

                        HStack(spacing: 10) {
                            Button {
                                store.updateShortcutSyncConfig(name: shortcutNameDraft, autoRunOnOpen: autoRunShortcutToggle)
                                store.triggerShortcutRefreshSync(userInitiated: true)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                    Text(store.isAutoSyncing ? "Sincronizando…" : "Ejecutar Atajo")
                                }
                                .font(ImprovingFont.caption(12.5))
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(RoundedRectangle(cornerRadius: 12).fill(BevelColors.indigoEnd))
                            }

                            Button {
                                store.scanAutoSyncInboxIfNeeded(force: true, showBanner: true)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "folder.badge.gearshape")
                                    Text("Leer carpeta")
                                }
                                .font(ImprovingFont.caption(12.5))
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(RoundedRectangle(cornerRadius: 12).fill(BevelColors.floatingDarkButton))
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Nombre exacto de tu Atajo en iOS")
                                .font(ImprovingFont.caption(11))
                                .foregroundColor(BevelColors.textSecondary)
                            TextField("Sync Improving (Automático)", text: $shortcutNameDraft)
                                .font(ImprovingFont.body(13))
                                .foregroundColor(BevelColors.textPrimary)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 9)
                                .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.cardSubtle))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(BevelColors.cardBorder, lineWidth: 0.7))
                                .onSubmit {
                                    store.updateShortcutSyncConfig(name: shortcutNameDraft, autoRunOnOpen: autoRunShortcutToggle)
                                }
                                .onChange(of: shortcutNameDraft) { _, newVal in
                                    store.updateShortcutSyncConfig(name: newVal, autoRunOnOpen: autoRunShortcutToggle)
                                }
                        }

                        Toggle("Abrir app Atajos al abrir / recargar", isOn: $autoRunShortcutToggle)
                            .font(ImprovingFont.caption(12.5))
                            .foregroundColor(BevelColors.textPrimary)
                            .onChange(of: autoRunShortcutToggle) { _, newVal in
                                store.updateShortcutSyncConfig(name: shortcutNameDraft, autoRunOnOpen: newVal)
                            }

                        if !autoRunShortcutToggle {
                            Text("Modo 100 % sin salir de Improving activo: configura en Atajos → Automatización → App «Improving» → Al abrirse → Ejecutar inmediatamente.")
                                .font(ImprovingFont.caption(11))
                                .foregroundColor(BevelColors.textSecondary)
                        }

                        Button {
                            showShortcutsGuide = true
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "sparkles")
                                Text("Ver guía de configuración de Atajos")
                            }
                            .font(ImprovingFont.caption(12))
                            .fontWeight(.semibold)
                            .foregroundColor(BevelColors.skyBlue)
                        }
                    }
                    .padding(16)
                }
                .padding(.horizontal, 16)

                // Apple Health Live & Export Importer Card
                BevelCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "heart.text.square.fill")
                                .font(.system(size: 24))
                                .foregroundColor(BevelColors.redAlert)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Apple Health y Archivo Salud")
                                    .font(ImprovingFont.cardTitle(15.5))
                                    .foregroundColor(BevelColors.textPrimary)
                                Text("HealthKit en vivo + importador exportar.zip / export.xml")
                                    .font(ImprovingFont.caption(11.5))
                                    .foregroundColor(BevelColors.textSecondary)
                            }
                            Spacer()
                        }

                        HStack(spacing: 10) {
                            Button {
                                store.connectAndSyncAppleHealth()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                    Text(store.healthKitSyncing ? "Sincronizando…" : "Conectar Salud en vivo")
                                }
                                .font(ImprovingFont.caption(12.5))
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(RoundedRectangle(cornerRadius: 12).fill(BevelColors.emeraldEnd))
                            }

                            Button {
                                showingImporter = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "square.and.arrow.down")
                                    Text(store.importStatus.isImporting ? "Leyendo…" : "Importar .zip / .xml")
                                }
                                .font(ImprovingFont.caption(12.5))
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(RoundedRectangle(cornerRadius: 12).fill(BevelColors.floatingDarkButton))
                            }
                        }

                        Text("En tu iPhone: App Salud → foto de perfil → Exportar todos los datos de salud → selecciona exportar.zip o export.xml aquí. Solo se mostrarán datos reales recopilados.")
                            .font(ImprovingFont.caption(11.5))
                            .foregroundColor(BevelColors.textSecondary)

                        if let okMsg = store.importStatus.summaryMessage, store.importStatus.errorMessage == nil {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(BevelColors.emeraldEnd)
                                Text(okMsg).font(ImprovingFont.caption(12)).fontWeight(.semibold).foregroundColor(BevelColors.emeraldEnd)
                            }
                        }
                        if let errMsg = store.importStatus.errorMessage {
                            Text(errMsg).font(ImprovingFont.caption(12)).foregroundColor(BevelColors.redAlert)
                        }
                        if !store.realHistory.isEmpty {
                            Text("\(store.realHistory.count) días reales almacenados en este iPhone (cero datos inventados).")
                                .font(ImprovingFont.caption(11.5))
                                .foregroundColor(BevelColors.textPrimary)
                        }
                    }
                    .padding(16)
                }
                .padding(.horizontal, 16)

                // Gemini AI Key & Model Selector (Exact 1:1 Android Structure!)
                BevelCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            BevelMascotOrb(size: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("INTELIGENCIA ARTIFICIAL (GEMINI)")
                                    .font(ImprovingFont.microLabel(11))
                                    .foregroundColor(BevelColors.greenPrimary)
                                Text("Personalidad directa, preguntas libres y cero datos inventados")
                                    .font(ImprovingFont.caption(11.5))
                                    .foregroundColor(BevelColors.textSecondary)
                            }
                        }

                        SecureField("Pega tu API Key de Google Gemini (AIza...)", text: $apiKeyDraft)
                            .font(ImprovingFont.body(13.5))
                            .foregroundColor(BevelColors.textPrimary)
                            .padding(11)
                            .background(RoundedRectangle(cornerRadius: 12).fill(BevelColors.cardSubtle))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))

                        Text("Modelo Gemini")
                            .font(ImprovingFont.caption(12))
                            .foregroundColor(BevelColors.textSecondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(GeminiCoachService.supportedModels, id: \.self) { m in
                                    let active = selectedModelDraft == m
                                    Button {
                                        selectedModelDraft = m
                                    } label: {
                                        Text(m)
                                            .font(ImprovingFont.caption(12))
                                            .fontWeight(.semibold)
                                            .foregroundColor(active ? .white : BevelColors.textSecondary)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 7)
                                            .background(Capsule().fill(active ? BevelColors.indigoEnd : BevelColors.cardSubtle))
                                    }
                                }
                            }
                        }

                        HStack {
                            Button {
                                store.updateGeminiConfig(apiKey: apiKeyDraft, model: selectedModelDraft)
                                savedBanner = true
                            } label: {
                                Text("Guardar configuración IA")
                                    .font(ImprovingFont.caption(13))
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(Capsule().fill(BevelColors.emeraldEnd))
                            }

                            if savedBanner {
                                Label("Guardado", systemImage: "checkmark.circle.fill")
                                    .font(ImprovingFont.caption(12))
                                    .foregroundColor(BevelColors.greenPrimary)
                            }
                            Spacer()
                        }

                        Text("Con tu clave de Gemini usa la API oficial directamente. Sin clave funciona igualmente en vivo con el motor cloud de respaldo.")
                            .font(ImprovingFont.caption(11))
                            .foregroundColor(BevelColors.textMuted)
                    }
                    .padding(16)
                }
                .padding(.horizontal, 16)

                // WHOOP BLE Live Connection
                BevelCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "wave.3.right.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(BevelColors.periwinkleStart)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("WHOOP Bluetooth (4.0 / 5.0)")
                                    .font(ImprovingFont.cardTitle(15.5))
                                    .foregroundColor(BevelColors.textPrimary)
                                Text(store.whoopConnected ? "Conectado · Batería \(store.whoopBatteryPct ?? 0)%" : (store.whoopScanning ? "Buscando pulsera WHOOP…" : "Desconectado"))
                                    .font(ImprovingFont.caption(11.5))
                                    .foregroundColor(store.whoopConnected ? BevelColors.emeraldEnd : BevelColors.textSecondary)
                            }
                            Spacer()
                            Button(store.whoopScanning ? "Detener" : (store.whoopConnected ? "Sync" : "Escanear")) {
                                if store.whoopConnected { store.forceWhoopSync() } else { store.toggleWhoopScan() }
                            }
                            .font(ImprovingFont.caption(12))
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(store.whoopConnected ? BevelColors.emeraldEnd : BevelColors.indigoEnd))
                        }

                        if store.whoopConnected {
                            Button("Desconectar pulsera", role: .destructive) {
                                store.disconnectWhoop()
                            }
                            .font(ImprovingFont.caption(12))
                        }
                    }
                    .padding(16)
                }
                .padding(.horizontal, 16)

                // Appearance & Profile
                BevelCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("APARIENCIA Y PERFIL")
                            .font(ImprovingFont.microLabel(11))
                            .foregroundColor(BevelColors.textSecondary)

                        Toggle("Modo oscuro", isOn: $darkToggle)
                            .font(ImprovingFont.body(14))
                            .foregroundColor(BevelColors.textPrimary)
                            .onChange(of: darkToggle) { _, newVal in
                                store.setDarkMode(newVal)
                            }

                        Divider().background(BevelColors.divider)

                        HStack {
                            Text("Método VFC").font(ImprovingFont.body(13.5)).foregroundColor(BevelColors.textSecondary)
                            Spacer()
                            Text("RMSSD (Bevel / WHOOP)").font(ImprovingFont.cardTitle(13.5)).foregroundColor(BevelColors.greenPrimary)
                        }
                        HStack {
                            Text("Fuente VFC").font(ImprovingFont.body(13.5)).foregroundColor(BevelColors.textSecondary)
                            Spacer()
                            Text(store.currentDaySummary?.hrvMethodLabel ?? "Todo el sueño")
                                .font(ImprovingFont.cardTitle(13.5))
                                .foregroundColor(BevelColors.textPrimary)
                        }
                        if let diag = store.currentDaySummary?.syncDiagnosticLine, !diag.isEmpty {
                            Text(diag)
                                .font(ImprovingFont.caption(11))
                                .foregroundColor(BevelColors.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 8).fill(BevelColors.cardSubtle))
                        }
                        if let lbl = store.currentDaySummary?.hrvMethodLabel, lbl.hasPrefix("SDNN") {
                            Text("Atajos de iOS solo exporta SDNN (sin serie latido a latido). Para RMSSD exacto como Bevel: importa exportar.zip o conecta Salud en vivo.")
                                .font(ImprovingFont.caption(10.5))
                                .foregroundColor(BevelColors.textMuted)
                        }
                        HStack {
                            Text("FC máx. Tanaka").font(ImprovingFont.body(13.5)).foregroundColor(BevelColors.textSecondary)
                            Spacer()
                            Text("\(norms.maxHrBpm) ppm").font(ImprovingFont.cardTitle(14)).monospacedDigit().foregroundColor(BevelColors.textPrimary)
                        }
                        HStack {
                            Text("Tasa metabólica basal").font(ImprovingFont.body(13.5)).foregroundColor(BevelColors.textSecondary)
                            Spacer()
                            Text("\(norms.bmrKcal) kcal").font(ImprovingFont.cardTitle(14)).monospacedDigit().foregroundColor(BevelColors.textPrimary)
                        }

                        Divider().background(BevelColors.divider)

                        Button {
                            onBack()
                            store.replayOnboarding()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles.tv")
                                Text("Ver presentación inicial de nuevo")
                            }
                            .font(ImprovingFont.caption(12.5))
                            .fontWeight(.semibold)
                            .foregroundColor(BevelColors.skyBlue)
                        }
                    }
                    .padding(16)
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 120)
        }
        .background(BevelColors.canvas)
        .onAppear {
            profileDraft = store.userProfile
            birthDateDraft = store.userProfile.birthDate
            apiKeyDraft = store.geminiApiKey
            selectedModelDraft = store.selectedGeminiModel
            shortcutNameDraft = store.shortcutSyncName
            autoRunShortcutToggle = store.autoRunShortcutOnOpen
            darkToggle = BevelColors.isDarkMode
            savedBanner = false
            profileSavedBanner = false
        }
        .onChange(of: birthDateDraft) { _, newDate in
            profileDraft.setBirthDate(newDate)
            profileSavedBanner = false
        }
        .onChange(of: selectedAvatarPhoto) { _, newItem in
            guard let item = newItem else { return }
            savingAvatarPhoto = true
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let savedName = ProfilePhotoStorage.savePickedImageData(data) {
                    await MainActor.run {
                        profileDraft.profilePhotoPath = savedName
                        store.updateProfile(profileDraft)
                        savingAvatarPhoto = false
                        profileSavedBanner = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                } else {
                    await MainActor.run { savingAvatarPhoto = false }
                }
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.zip, .xml, .json, .plainText, .commaSeparatedText, .data],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                store.importExportFiles(urls: urls)
            }
        }
            .sheet(isPresented: $showShortcutsGuide) {
                ShortcutsAutomationGuideSheet(
                    copiedUrlToast: $copiedUrlToast,
                    onSyncNow: { store.scanAutoSyncInboxIfNeeded(force: true) },
                    onClose: { showShortcutsGuide = false }
                )
            }
    }

    private func compactStepper(_ label: String, _ value: String, onMinus: @escaping () -> Void, onPlus: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(ImprovingFont.caption(11))
                .foregroundColor(BevelColors.textSecondary)
            HStack {
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    onMinus()
                    profileSavedBanner = false
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(BevelColors.textPrimary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(BevelColors.trackGroove))
                }
                Spacer()
                Text(value)
                    .font(ImprovingFont.caption(12.5))
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundColor(BevelColors.textPrimary)
                Spacer()
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    onPlus()
                    profileSavedBanner = false
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(BevelColors.textPrimary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(BevelColors.trackGroove))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.cardSubtle))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Step-by-Step Apple Shortcuts Setup Guide Sheet

private struct ShortcutsAutomationGuideSheet: View {
    @Binding var copiedUrlToast: Bool
    let onSyncNow: () -> Void
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Atajos de Apple · Guía rápida")
                            .font(ImprovingFont.sectionTitle(19))
                            .foregroundColor(BevelColors.textPrimary)
                        Text("Sincroniza Apple Salud gratis y sin cuenta de desarrollador")
                            .font(ImprovingFont.caption(12))
                            .foregroundColor(BevelColors.greenPrimary)
                    }
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(BevelColors.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(BevelColors.card))
                    }
                }
                .padding(.top, 8)

                guideCard(
                    step: "1",
                    title: "Crea el Atajo (sin bucles, 1 minuto)",
                    lines: [
                        "Abre la app Atajos de Apple y pulsa + (Nuevo atajo) → llámalo «Sync Improving».",
                        "Añade una acción «Buscar muestras de Salud» por cada métrica (Últimos 2 días): Frecuencia cardíaca, Variabilidad de la frecuencia cardíaca (VFC), FC en reposo, Sueño, Frecuencia respiratoria, Oxígeno en sangre, Temperatura de la muñeca, Pasos y Energía activa.",
                        "Al final añade la acción nativa de Improving: «Sincronizar Salud en Improving» (búscala escribiendo Improving).",
                        "En cada campo (Valores FC, Fechas FC, Valores VFC, Fechas VFC, Fases de Sueño, Inicios/Fines de Sueño…), selecciona la variable de su «Buscar muestras de Salud» y toca la variable para elegir Valor, Fecha de inicio o Fecha de finalización."
                    ]
                )

                guideCard(
                    step: "2",
                    title: "Hazlo 100 % automático en segundo plano",
                    lines: [
                        "Ve a la pestaña Automatización en Atajos → pulsa + → «Momento del día» (por ejemplo 08:00, 12:00, 16:00 y 20:00) o «App» → «Al abrir Improving».",
                        "Activa «Ejecutar inmediatamente» y desactiva «Notificar al ejecutar».",
                        "Elige tu atajo «Sync Improving». Se ejecutará en segundo plano sin abrir pantallas y actualizará Improving al instante."
                    ]
                )

                guideCard(
                    step: "3",
                    title: "Alternativa: Carpeta Archivos o Health Auto Export",
                    lines: [
                        "También puedes guardar cualquier archivo JSON/TXT/XML directamente en Archivos → En mi iPhone → Improving (por ejemplo desde Health Auto Export o la acción «Guardar archivo» de Atajos).",
                        "Cada vez que abras Improving leerá los archivos nuevos automáticamente y mantendrá tu curva continua de energía y tus medias de 60 días."
                    ]
                )

                HStack(spacing: 10) {
                    Button {
                        if let url = URL(string: "shortcuts://") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.forward.app.fill")
                            Text("Abrir app Atajos")
                        }
                        .font(ImprovingFont.caption(13))
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 14).fill(BevelColors.indigoEnd))
                    }

                    Button {
                        UIPasteboard.general.string = "improving://sync"
                        copiedUrlToast = true
                        onSyncNow()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: copiedUrlToast ? "checkmark" : "doc.on.doc")
                            Text(copiedUrlToast ? "URL copiada" : "Copiar URL Sync")
                        }
                        .font(ImprovingFont.caption(13))
                        .fontWeight(.semibold)
                        .foregroundColor(BevelColors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 14).fill(BevelColors.card))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
                    }
                }
            }
            .padding(18)
        }
        .background(BevelColors.sheetHeaderBg.ignoresSafeArea())
        .presentationDetents([.large])
    }

    private func guideCard(step: String, title: String, lines: [String]) -> some View {
        BevelCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Text(step)
                        .font(ImprovingFont.caption(12))
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(BevelColors.indigoEnd))
                    Text(title)
                        .font(ImprovingFont.cardTitle(14.5))
                        .foregroundColor(BevelColors.textPrimary)
                }
                ForEach(lines, id: \.self) { line in
                    HStack(alignment: .top, spacing: 7) {
                        Circle()
                            .fill(BevelColors.periwinkleStart)
                            .frame(width: 5, height: 5)
                            .padding(.top, 7)
                        Text(line)
                            .font(ImprovingFont.body(13))
                            .foregroundColor(BevelColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(15)
        }
    }
}

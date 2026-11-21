import SwiftUI
import UniformTypeIdentifiers

struct DispositivosScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void

    @State private var showingImporter = false
    @State private var apiKeyDraft: String = ""
    @State private var darkToggle: Bool = BevelColors.isDarkMode

    var body: some View {
        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: store.userProfile)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DetailSheetHeader(title: "Dispositivos y Ajustes", onBack: onBack)

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

                        Text("En tu iPhone: App Salud → foto de perfil → Exportar todos los datos de salud → selecciona exportar.zip o export.xml aquí.")
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
                            Text("\(store.realHistory.count) días reales almacenados en este iPhone.")
                                .font(ImprovingFont.caption(11.5))
                                .foregroundColor(BevelColors.textPrimary)
                        }
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

                        Toggle("Modo oscuro (fondo negro puro)", isOn: $darkToggle)
                            .font(ImprovingFont.body(14))
                            .foregroundColor(BevelColors.textPrimary)
                            .onChange(of: darkToggle) { _, newVal in
                                store.setDarkMode(newVal)
                            }

                        Divider().background(BevelColors.divider)

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
                    }
                    .padding(16)
                }
                .padding(.horizontal, 16)

                // Gemini AI Key Config
                BevelCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("INTELIGENCIA ARTIFICIAL (GEMINI)")
                            .font(ImprovingFont.microLabel(11))
                            .foregroundColor(BevelColors.textSecondary)
                        SecureField("API Key de Gemini (opcional)", text: $apiKeyDraft)
                            .font(ImprovingFont.body(13.5))
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.cardSubtle))
                        Button("Guardar clave IA") {
                            store.updateGeminiConfig(apiKey: apiKeyDraft, model: store.selectedGeminiModel)
                        }
                        .font(ImprovingFont.caption(12.5))
                        .fontWeight(.semibold)
                        .foregroundColor(BevelColors.emeraldEnd)
                    }
                    .padding(16)
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 120)
        }
        .background(BevelColors.canvas)
        .onAppear {
            apiKeyDraft = store.geminiApiKey
            darkToggle = BevelColors.isDarkMode
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.zip, .xml, .commaSeparatedText, .data],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                store.importExportFiles(urls: urls)
            }
        }
    }
}

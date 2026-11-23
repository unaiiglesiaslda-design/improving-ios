import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct DispositivosScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void

    @State private var showingImporter = false
    @State private var showShortcutsGuide = false
    @State private var copiedUrlToast = false
    @State private var apiKeyDraft: String = ""
    @State private var selectedModelDraft: String = "gemini-2.5-flash"
    @State private var savedBanner: Bool = false
    @State private var darkToggle: Bool = BevelColors.isDarkMode

    var body: some View {
        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: store.userProfile)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DetailSheetHeader(title: "Dispositivos y Ajustes", onBack: onBack)

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
                                showShortcutsGuide = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "sparkles")
                                    Text("Configurar Atajo")
                                }
                                .font(ImprovingFont.caption(12.5))
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(RoundedRectangle(cornerRadius: 12).fill(BevelColors.indigoEnd))
                            }

                            Button {
                                store.scanAutoSyncInboxIfNeeded(force: true)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.clockwise")
                                    Text(store.isAutoSyncing ? "Leyendo…" : "Sincronizar ya")
                                }
                                .font(ImprovingFont.caption(12.5))
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(RoundedRectangle(cornerRadius: 12).fill(BevelColors.floatingDarkButton))
                            }
                        }

                        Text("Usa la acción nativa «Sincronizar Salud en Improving» dentro de la app Atajos de Apple, o guarda un JSON en En mi iPhone → Improving (compatible también con Health Auto Export).")
                            .font(ImprovingFont.caption(11.5))
                            .foregroundColor(BevelColors.textSecondary)
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
            }
            .padding(.bottom, 120)
        }
        .background(BevelColors.canvas)
        .onAppear {
            apiKeyDraft = store.geminiApiKey
            selectedModelDraft = store.selectedGeminiModel
            darkToggle = BevelColors.isDarkMode
            savedBanner = false
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

import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum ShareSummaryKind: Identifiable {
    case sleep
    case recovery
    case strain
    case stress
    case energy
    case workout(EffortEventItem)

    var id: String {
        switch self {
        case .sleep: return "share_sleep"
        case .recovery: return "share_recovery"
        case .strain: return "share_strain"
        case .stress: return "share_stress"
        case .energy: return "share_energy"
        case .workout(let w): return "share_workout_\(w.id)"
        }
    }
}

struct RenderedShareCardImage: Transferable {
    let pngData: Data
    let suggestedFilename: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            item.pngData
        }
        .suggestedFileName { item in
            item.suggestedFilename
        }
    }
}

struct ShareCardMetricTile: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let value: String
}

struct ShareCardPayload {
    let pillarBadge: String
    let title: String
    let subtitle: String
    let progress: Double
    let centerValue: String
    let centerCaption: String
    let ringColors: [Color]
    let backgroundColors: [Color]
    let metrics: [ShareCardMetricTile]

    @MainActor
    static func build(for kind: ShareSummaryKind, store: ImprovingStore) -> ShareCardPayload {
        let avail = store.dataAvailability
        let userName = store.userProfile.displayFirstName
        let dateLine = userName.isEmpty ? store.dateLabel : "\(userName) · \(store.dateLabel)"

        switch kind {
        case .sleep:
            let sess = store.currentDaySummary?.sleepSession
            let deepTxt = store.currentDaySummary?.deepMinutes.map { "\($0) min" } ?? "--"
            let remTxt = store.currentDaySummary?.remMinutes.map { "\($0) min" } ?? "--"
            let effTxt = sess?.efficiencyPct.map { "\($0)%" } ?? "--"
            return ShareCardPayload(
                pillarBadge: "SUEÑO",
                title: "Descanso Nocturno",
                subtitle: dateLine,
                progress: avail.hasSleepData ? Double(store.sleepPercent) / 100.0 : 0.0,
                centerValue: avail.hasSleepData ? "\(store.sleepPercent)%" : "--",
                centerCaption: avail.hasSleepData ? store.sleepStatusText : "Sin datos",
                ringColors: [Color(hex: 0x7A90EE), Color(hex: 0x93A8F8)],
                backgroundColors: [Color(hex: 0x16224A), Color(hex: 0x13192E), Color(hex: 0x0E121B)],
                metrics: [
                    ShareCardMetricTile(icon: "clock.fill", label: "Duración", value: store.sleepDurationText),
                    ShareCardMetricTile(icon: "sparkles", label: "Eficiencia", value: effTxt),
                    ShareCardMetricTile(icon: "moon.zzz.fill", label: "Profundo", value: deepTxt),
                    ShareCardMetricTile(icon: "brain.head.profile", label: "Sueño REM", value: remTxt)
                ]
            )

        case .recovery:
            return ShareCardPayload(
                pillarBadge: "RECUPERACIÓN",
                title: "Estado Autonómico",
                subtitle: dateLine,
                progress: avail.hasRecoveryData ? Double(store.recoveryPercent) / 100.0 : 0.0,
                centerValue: avail.hasRecoveryData ? "\(store.recoveryPercent)%" : "--",
                centerCaption: avail.hasRecoveryData ? store.recoveryStatusText : "Sin datos",
                ringColors: [Color(hex: 0x4ADE80), Color(hex: 0x10B981)],
                backgroundColors: [Color(hex: 0x183429), Color(hex: 0x13201D), Color(hex: 0x0E1318)],
                metrics: [
                    ShareCardMetricTile(icon: "waveform.path.ecg", label: "VFC reposo", value: avail.hasHrvData ? String(format: "%.1f ms", locale: Locale(identifier: "es_ES"), store.hrvMs) : "--"),
                    ShareCardMetricTile(icon: "heart.fill", label: "FC reposo", value: avail.hasRestingHrData ? String(format: "%.1f ppm", locale: Locale(identifier: "es_ES"), store.restingHrBpm) : "--"),
                    ShareCardMetricTile(icon: "bed.double.fill", label: "Sueño", value: avail.hasSleepData ? "\(store.sleepPercent)%" : "--"),
                    ShareCardMetricTile(icon: "bolt.fill", label: "Batería", value: avail.hasEnergyData ? "\(store.energyPercent)%" : "--")
                ]
            )

        case .strain:
            let totalMin = store.workoutsToday.reduce(0) { $0 + $1.durationMin }
            let kcalTxt = store.currentDaySummary?.activeKcal.map { "\($0) kcal" } ?? "--"
            let stepsTxt = store.stepsCount.map { "\($0)" } ?? "--"
            return ShareCardPayload(
                pillarBadge: "ESFUERZO",
                title: "Carga Diaria",
                subtitle: dateLine,
                progress: avail.hasStrainData ? Double(store.strainPercent) / 100.0 : 0.0,
                centerValue: avail.hasStrainData ? "\(store.strainPercent)%" : "--",
                centerCaption: avail.hasStrainData ? String(format: "Strain %.1f / 21", locale: Locale(identifier: "es_ES"), store.strain21) : "Sin datos",
                ringColors: [Color(hex: 0xFBBF24), Color(hex: 0xF97316)],
                backgroundColors: [Color(hex: 0x3D2516), Color(hex: 0x221814), Color(hex: 0x101217)],
                metrics: [
                    ShareCardMetricTile(icon: "flame.fill", label: "Calorías act.", value: kcalTxt),
                    ShareCardMetricTile(icon: "timer", label: "Ejercicio", value: totalMin > 0 ? "\(totalMin) min" : "0 min"),
                    ShareCardMetricTile(icon: "shoeprints.fill", label: "Pasos", value: stepsTxt),
                    ShareCardMetricTile(icon: "target", label: "Zona óptima", value: store.effortTargetRangeText)
                ]
            )

        case .stress:
            return ShareCardPayload(
                pillarBadge: "ESTRÉS",
                title: "Balance Simpático",
                subtitle: dateLine,
                progress: avail.hasStressData ? Double(store.displayStressScore) / 100.0 : 0.0,
                centerValue: avail.hasStressData ? "\(store.displayStressScore)" : "--",
                centerCaption: store.stressStatusLabel,
                ringColors: [Color(hex: 0x56D5C6), Color(hex: 0x38BDF8)],
                backgroundColors: [Color(hex: 0x2A2338), Color(hex: 0x1A1826), Color(hex: 0x0F1219)],
                metrics: [
                    ShareCardMetricTile(icon: "chart.line.uptrend.xyaxis", label: "Media hoy", value: store.stressAvg.map { "\($0)/100" } ?? "--"),
                    ShareCardMetricTile(icon: "arrow.up.to.line", label: "Pico máx.", value: store.stressMax.map { "\($0)/100" } ?? "--"),
                    ShareCardMetricTile(icon: "waveform.path.ecg", label: "VFC", value: avail.hasHrvData ? String(format: "%.1f ms", locale: Locale(identifier: "es_ES"), store.hrvMs) : "--"),
                    ShareCardMetricTile(icon: "bolt.fill", label: "Energía", value: avail.hasEnergyData ? "\(store.energyPercent)%" : "--")
                ]
            )

        case .energy:
            let peakVal = store.energySamplesToday.map(\.value).max().map { "\(Int($0.rounded()))%" } ?? "--"
            return ShareCardPayload(
                pillarBadge: "RESERVAS DE ENERGÍA",
                title: "Batería Corporal",
                subtitle: dateLine,
                progress: avail.hasEnergyData ? Double(store.energyPercent) / 100.0 : 0.0,
                centerValue: avail.hasEnergyData ? "\(store.energyPercent)%" : "--",
                centerCaption: " Pico hoy \(peakVal)",
                ringColors: [Color(hex: 0x4ADE80), Color(hex: 0xFACC15)],
                backgroundColors: [Color(hex: 0x362B19), Color(hex: 0x1E1B16), Color(hex: 0x101318)],
                metrics: [
                    ShareCardMetricTile(icon: "battery.100percent.bolt", label: "Pico carga", value: peakVal),
                    ShareCardMetricTile(icon: "leaf.fill", label: "Recuperación", value: avail.hasRecoveryData ? "\(store.recoveryPercent)%" : "--"),
                    ShareCardMetricTile(icon: "bed.double.fill", label: "Sueño", value: avail.hasSleepData ? "\(store.sleepPercent)%" : "--"),
                    ShareCardMetricTile(icon: "flame.fill", label: "Esfuerzo", value: avail.hasStrainData ? "\(store.strainPercent)%" : "--")
                ]
            )

        case .workout(let w):
            let durTxt = w.durationMin >= 60 ? "\(w.durationMin / 60)h \(w.durationMin % 60)m" : "\(w.durationMin) min"
            let hrTxt = w.avgHrBpm > 0 ? "\(w.avgHrBpm) ppm" : "--"
            let extraTile: ShareCardMetricTile = {
                if let dist = w.distanceKm, dist > 0.05 {
                    return ShareCardMetricTile(icon: "point.topleft.down.curvedto.point.bottomright.up", label: "Distancia", value: String(format: "%.2f km", locale: Locale(identifier: "es_ES"), dist))
                }
                if let vol = w.totalVolumeKg, vol > 0 {
                    return ShareCardMetricTile(icon: "dumbbell.fill", label: "Volumen", value: "\(Int(vol.rounded())) kg")
                }
                if let hrr = w.hrRecovery1MinBpm ?? store.currentDaySummary?.hrRecoveryBpm {
                    return ShareCardMetricTile(icon: "heart.text.square.fill", label: "Recup. FC 1m", value: "-\(Int(hrr.rounded())) ppm")
                }
                return ShareCardMetricTile(icon: "tag.fill", label: "Categoría", value: w.categoryLabel)
            }()

            return ShareCardPayload(
                pillarBadge: "ENTRENAMIENTO · \(w.categoryLabel.uppercased())",
                title: w.title,
                subtitle: "\(userName.isEmpty ? "" : "\(userName) · ")\(w.timeRange)",
                progress: min(max(Double(w.strainPct) / 100.0, 0.04), 1.0),
                centerValue: "\(w.strainPct)%",
                centerCaption: String(format: "Strain %.1f / 21", locale: Locale(identifier: "es_ES"), w.strainScore),
                ringColors: [Color(hex: 0xFB923C), Color(hex: 0xF43F5E)],
                backgroundColors: [Color(hex: 0x3A221A), Color(hex: 0x1F181B), Color(hex: 0x0F1218)],
                metrics: [
                    ShareCardMetricTile(icon: "timer", label: "Duración", value: durTxt),
                    ShareCardMetricTile(icon: "flame.fill", label: "Energía activa", value: w.kcal > 0 ? "\(w.kcal) kcal" : "--"),
                    ShareCardMetricTile(icon: "heart.fill", label: "FC media", value: hrTxt),
                    extraTile
                ]
            )
        }
    }
}

// MARK: - Crisp Vector Card Rendered via SwiftUI ImageRenderer (@3x = 1080x1440 Story/WhatsApp Ready)

struct ShareableSummaryCardView: View {
    let payload: ShareCardPayload

    var body: some View {
        ZStack {
            LinearGradient(
                colors: payload.backgroundColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 18) {
                // Header Branding
                HStack {
                    HStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.10))
                                .frame(width: 28, height: 28)
                            Circle()
                                .trim(from: 0, to: 0.76)
                                .stroke(Color(hex: 0x22C55E), style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .frame(width: 16, height: 16)
                        }
                        Text("Improving")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    Text(payload.pillarBadge)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.1)
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                }

                VStack(spacing: 3) {
                    Text(payload.title)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(payload.subtitle)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.68))
                        .lineLimit(1)
                }

                // Center Signature Ring
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.09), lineWidth: 15)
                        .frame(width: 152, height: 152)

                    if payload.progress > 0.005 {
                        Circle()
                            .trim(from: 0, to: CGFloat(min(max(payload.progress, 0.03), 1.0)))
                            .stroke(
                                LinearGradient(
                                    colors: payload.ringColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 15, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 152, height: 152)
                    }

                    VStack(spacing: 2) {
                        Text(payload.centerValue)
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white)
                        Text(payload.centerCaption)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.75))
                    }
                }
                .padding(.vertical, 4)

                // 2x2 Real KPI Grid
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(payload.metrics) { tile in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 5) {
                                Image(systemName: tile.icon)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(payload.ringColors.first ?? .white)
                                Text(tile.label)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.65))
                                    .lineLimit(1)
                            }
                            Text(tile.value)
                                .font(.system(size: 16.5, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.07)))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8))
                    }
                }

                Spacer(minLength: 0)

                HStack {
                    Text("DATOS BIOMÉTRICOS REALES")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .tracking(1.3)
                        .foregroundColor(.white.opacity(0.45))
                    Spacer()
                    Text("improving.app")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                }
            }
            .padding(22)
        }
        .frame(width: 340, height: 470)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        )
    }
}

// MARK: - Share Card Preview & Export Sheet (ImageRenderer + ShareLink)

struct ShareSummaryCardSheet: View {
    @ObservedObject var store: ImprovingStore
    let kind: ShareSummaryKind
    let onClose: () -> Void

    @State private var renderedTransferable: RenderedShareCardImage? = nil
    @State private var renderedUIImage: UIImage? = nil
    @State private var feedbackMessage: String? = nil

    var body: some View {
        let payload = ShareCardPayload.build(for: kind, store: store)

        NavigationStack {
            VStack(spacing: 18) {
                ShareableSummaryCardView(payload: payload)
                    .shadow(color: Color.black.opacity(0.38), radius: 22, y: 10)
                    .padding(.top, 8)

                if let msg = feedbackMessage {
                    Text(msg)
                        .font(ImprovingFont.caption(12.5))
                        .fontWeight(.semibold)
                        .foregroundColor(BevelColors.greenPrimary)
                }

                VStack(spacing: 10) {
                    if let item = renderedTransferable {
                        ShareLink(
                            item: item,
                            preview: SharePreview(
                                "\(payload.title) · Improving",
                                image: Image(uiImage: renderedUIImage ?? UIImage())
                            )
                        ) {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 15, weight: .bold))
                                Text("Compartir en WhatsApp / Stories")
                                    .font(ImprovingFont.cardTitle(15))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(BevelColors.emeraldEnd))
                        }
                    } else {
                        ProgressView("Generando tarjeta en alta resolución…")
                            .font(ImprovingFont.caption(13))
                            .foregroundColor(BevelColors.textSecondary)
                            .padding(.vertical, 12)
                    }

                    HStack(spacing: 10) {
                        Button {
                            guard let img = renderedUIImage else { return }
                            UIPasteboard.general.image = img
                            feedbackMessage = "✓ Imagen copiada lista para pegar"
                        } label: {
                            Label("Copiar imagen", systemImage: "doc.on.doc")
                                .font(ImprovingFont.caption(13))
                                .fontWeight(.semibold)
                                .foregroundColor(BevelColors.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Capsule().fill(BevelColors.card))
                                .overlay(Capsule().strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
                        }

                        Button {
                            guard let img = renderedUIImage else { return }
                            UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
                            feedbackMessage = "✓ Guardada en tu Fototeca"
                        } label: {
                            Label("Guardar en Fotos", systemImage: "arrow.down.to.line")
                                .font(ImprovingFont.caption(13))
                                .fontWeight(.semibold)
                                .foregroundColor(BevelColors.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Capsule().fill(BevelColors.card))
                                .overlay(Capsule().strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
                        }
                    }
                }
                .padding(.horizontal, 20)

                Spacer()
            }
            .padding(.bottom, 16)
            .background(BevelColors.sheetHeaderBg.ignoresSafeArea())
            .navigationTitle("Compartir resumen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar", action: onClose)
                }
            }
            .onAppear {
                renderCardImage(payload: payload)
            }
        }
    }

    @MainActor
    private func renderCardImage(payload: ShareCardPayload) {
        let renderer = ImageRenderer(content: ShareableSummaryCardView(payload: payload))
        renderer.scale = 3.0
        if let uiImg = renderer.uiImage, let png = uiImg.pngData() {
            renderedUIImage = uiImg
            renderedTransferable = RenderedShareCardImage(
                pngData: png,
                suggestedFilename: "Improving_\(store.selectedDateIso).png"
            )
        }
    }
}

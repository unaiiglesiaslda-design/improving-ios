import SwiftUI
import PhotosUI
import PDFKit
import UniformTypeIdentifiers
import UIKit

// MARK: - P2. Dedicated Body Composition & Blood Pressure History Detail Screen

struct BodyCompositionDetailScreen: View {
    @ObservedObject var store: ImprovingStore
    let kind: BodyCompositionMetricKind
    let onBack: () -> Void

    @State private var selectedRange: String = "30 d"
    @State private var windowOffset: Int = 0
    @State private var showManualScaleSheet: Bool = false

    private let ranges = ["30 d", "3 M", "6 M", "1 A"]

    private func spanDays(for range: String) -> Int {
        switch range {
        case "30 d": return 30
        case "3 M": return 90
        case "6 M": return 180
        default: return 365
        }
    }

    var body: some View {
        let span = spanDays(for: selectedRange)
        let series = store.bodyMetricSeries(for: kind, spanDays: span, windowPageOffset: windowOffset)
        let entries = store.bodyMetricHistoryEntries(for: kind, limit: 30)
        let realVals = series.realPoints
        let avgVal: Double? = realVals.isEmpty ? nil : (realVals.reduce(0, +) / Double(realVals.count))
        let minVal: Double? = realVals.min()
        let maxVal: Double? = realVals.max()
        let deltaVal: Double? = (realVals.count >= 2)
            ? zip(realVals.first.map { [$0] } ?? [], realVals.last.map { [$0] } ?? []).first.map { $0.1 - $0.0 }
            : nil

        let latestText: String = {
            switch kind {
            case .weight:
                return store.latestBodyWeightKg.map { String(format: "%.1f kg", locale: Locale(identifier: "es_ES"), $0) } ?? "--"
            case .bodyFat:
                return store.latestBodyFatPct.map { String(format: "%.1f %%", locale: Locale(identifier: "es_ES"), $0) } ?? "--"
            case .leanMass:
                return store.latestLeanMassKg.map { String(format: "%.1f kg", locale: Locale(identifier: "es_ES"), $0) } ?? "--"
            case .bloodPressure:
                return store.latestBloodPressure.map { "\($0.sys)/\($0.dia) mmHg" } ?? "--"
            }
        }()

        VStack(spacing: 0) {
            DetailSheetHeader(
                title: kind.rawValue,
                onBack: onBack,
                rightSystemIcon: "plus",
                onRightAction: { showManualScaleSheet = true }
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Range selector pills
                    HStack(spacing: 8) {
                        ForEach(ranges, id: \.self) { r in
                            Button {
                                UISelectionFeedbackGenerator().selectionChanged()
                                selectedRange = r
                                windowOffset = 0
                            } label: {
                                Text(r)
                                    .font(ImprovingFont.caption(12.5))
                                    .fontWeight(.bold)
                                    .foregroundColor(selectedRange == r ? .white : BevelColors.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Capsule().fill(selectedRange == r ? kind.accentColor : BevelColors.card))
                            }
                        }
                    }

                    // Hero Value & Paginated Chart Card
                    BevelCard(cornerRadius: 22) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("ÚLTIMA LECTURA")
                                        .font(ImprovingFont.microLabel(10.5))
                                        .foregroundColor(BevelColors.textMuted)
                                    Text(latestText)
                                        .font(ImprovingFont.displayLarge(30))
                                        .monospacedDigit()
                                        .foregroundColor(BevelColors.textPrimary)
                                }
                                Spacer()
                                if let delta = deltaVal {
                                    let fmt = String(format: "%+.1f %@", locale: Locale(identifier: "es_ES"), delta, kind.unit)
                                    Text(fmt)
                                        .font(ImprovingFont.caption(12.5))
                                        .fontWeight(.bold)
                                        .foregroundColor(kind.accentColor)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Capsule().fill(kind.accentColor.opacity(0.16)))
                                }
                            }

                            HStack {
                                Button {
                                    if series.canStepBackward { windowOffset += 1 }
                                } label: {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(series.canStepBackward ? BevelColors.textPrimary : BevelColors.textMuted.opacity(0.3))
                                }
                                .disabled(!series.canStepBackward)
                                Spacer()
                                Text(series.windowRangeLabel)
                                    .font(ImprovingFont.caption(12))
                                    .foregroundColor(BevelColors.textSecondary)
                                Spacer()
                                Button {
                                    if series.canStepForward { windowOffset = max(0, windowOffset - 1) }
                                } label: {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(series.canStepForward ? BevelColors.textPrimary : BevelColors.textMuted.opacity(0.3))
                                }
                                .disabled(!series.canStepForward)
                            }

                            if realVals.count >= 2 {
                                TrendSparklineWithBand(
                                    optionalPoints: series.values,
                                    lineColor: kind.accentColor,
                                    fillUnder: true,
                                    showGlowDot: true
                                )
                                .frame(height: 150)
                            } else {
                                Text("Registra al menos 2 mediciones en esta ventana para dibujar la curva de tendencia.")
                                    .font(ImprovingFont.body(13))
                                    .foregroundColor(BevelColors.textSecondary)
                                    .frame(maxWidth: .infinity, minHeight: 90, alignment: .center)
                            }

                            HStack(spacing: 10) {
                                statChip("Media", val: avgVal.map { String(format: "%.1f", locale: Locale(identifier: "es_ES"), $0) } ?? "--")
                                statChip("Mínimo", val: minVal.map { String(format: "%.1f", locale: Locale(identifier: "es_ES"), $0) } ?? "--")
                                statChip("Máximo", val: maxVal.map { String(format: "%.1f", locale: Locale(identifier: "es_ES"), $0) } ?? "--")
                            }
                        }
                        .padding(16)
                    }

                    // Explanation Card
                    BevelCard(cornerRadius: 18) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: kind.systemIcon)
                                .font(.system(size: 16))
                                .foregroundColor(kind.accentColor)
                            Text(kind.explanation)
                                .font(ImprovingFont.body(13))
                                .foregroundColor(BevelColors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                    }

                    // Quick Log CTA
                    Button { showManualScaleSheet = true } label: {
                        Label("Añadir medición manual", systemImage: "plus.circle.fill")
                            .font(ImprovingFont.cardTitle(14.5))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Capsule().fill(BevelColors.emeraldEnd))
                    }

                    // Recorded History List
                    Text("Mediciones registradas")
                        .font(ImprovingFont.sectionTitle(17))
                        .foregroundColor(BevelColors.textPrimary)

                    if entries.isEmpty {
                        BevelCard(cornerRadius: 18) {
                            Text("Todavía no hay registros para \(kind.rawValue.lowercased()). Pulsa «Añadir medición manual» o sincroniza tu báscula en Apple Salud.")
                                .font(ImprovingFont.body(13.5))
                                .foregroundColor(BevelColors.textSecondary)
                                .padding(16)
                        }
                    } else {
                        BevelCard(cornerRadius: 20) {
                            VStack(spacing: 0) {
                                ForEach(Array(entries.enumerated()), id: \.offset) { idx, item in
                                    HStack {
                                        Text(item.dateIso)
                                            .font(ImprovingFont.caption(13))
                                            .monospacedDigit()
                                            .foregroundColor(BevelColors.textSecondary)
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 1) {
                                            Text(item.primary)
                                                .font(ImprovingFont.cardTitle(14.5))
                                                .monospacedDigit()
                                                .foregroundColor(BevelColors.textPrimary)
                                            if let sec = item.secondary {
                                                Text(sec)
                                                    .font(ImprovingFont.caption(11))
                                                    .foregroundColor(BevelColors.textMuted)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    if idx < entries.count - 1 {
                                        Divider().background(BevelColors.divider).padding(.horizontal, 16)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 140)
            }
        }
        .background(BevelColors.canvas.ignoresSafeArea())
        .sheet(isPresented: $showManualScaleSheet) {
            ManualScaleLoggerSheet(store: store, onClose: { showManualScaleSheet = false })
        }
    }

    private func statChip(_ label: String, val: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(ImprovingFont.caption(11)).foregroundColor(BevelColors.textMuted)
            Text(val).font(ImprovingFont.cardTitle(15)).monospacedDigit().foregroundColor(BevelColors.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(BevelColors.cardSubtle))
    }
}

// MARK: - N6A. Manual Scale & Blood Pressure Logger Sheet

struct ManualScaleLoggerSheet: View {
    @ObservedObject var store: ImprovingStore
    let onClose: () -> Void

    @State private var date: Date = Date()
    @State private var weightText: String = ""
    @State private var fatText: String = ""
    @State private var leanText: String = ""
    @State private var sysText: String = ""
    @State private var diaText: String = ""

    private func parseDbl(_ s: String) -> Double? {
        Double(s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    BevelCard(cornerRadius: 20) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("BÁSCULA Y COMPOSICIÓN CORPORAL")
                                .font(ImprovingFont.microLabel(10.5))
                                .foregroundColor(BevelColors.skyBlue)

                            DatePicker("Fecha", selection: $date, in: ...Date(), displayedComponents: [.date])
                                .font(ImprovingFont.body(14))
                                .foregroundColor(BevelColors.textPrimary)
                                .tint(BevelColors.emeraldEnd)
                                .environment(\.locale, Locale(identifier: "es_ES"))

                            rowField("Peso corporal (kg)", placeholder: "Ej: 71,4", text: $weightText, decimal: true)
                            rowField("Grasa corporal (%)", placeholder: "Opcional · Ej: 14,5", text: $fatText, decimal: true)
                            rowField("Masa magra (kg)", placeholder: "Auto si pones peso + grasa", text: $leanText, decimal: true)
                        }
                        .padding(16)
                    }

                    BevelCard(cornerRadius: 20) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("TENSIÓN ARTERIAL (OPCIONAL)")
                                .font(ImprovingFont.microLabel(10.5))
                                .foregroundColor(BevelColors.coralHigh)

                            HStack(spacing: 10) {
                                rowField("Sistólica", placeholder: "118", text: $sysText, decimal: false)
                                rowField("Diastólica", placeholder: "76", text: $diaText, decimal: false)
                            }
                        }
                        .padding(16)
                    }

                    Button {
                        let w = parseDbl(weightText)
                        let f = parseDbl(fatText)
                        let l = parseDbl(leanText)
                        let s = Int(sysText.trimmingCharacters(in: .whitespaces))
                        let d = Int(diaText.trimmingCharacters(in: .whitespaces))
                        guard w != nil || f != nil || l != nil || (s != nil && d != nil) else { return }
                        store.logManualScaleReading(
                            date: date,
                            weightKg: w,
                            bodyFatPct: f,
                            leanMassKg: l,
                            systolicBp: s,
                            diastolicBp: d
                        )
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        onClose()
                    } label: {
                        Text("Guardar medición")
                            .font(ImprovingFont.cardTitle(15))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(BevelColors.emeraldEnd))
                    }
                }
                .padding(16)
            }
            .background(BevelColors.canvas)
            .navigationTitle("Registrar báscula")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Cerrar", action: onClose) }
            }
            .onAppear {
                if let w = store.latestBodyWeightKg {
                    weightText = String(format: "%.1f", w)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func rowField(_ label: String, placeholder: String, text: Binding<String>, decimal: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(ImprovingFont.caption(12)).foregroundColor(BevelColors.textSecondary)
            TextField(placeholder, text: text)
                .keyboardType(decimal ? .decimalPad : .numberPad)
                .keyboardDoneToolbar()
                .font(ImprovingFont.cardTitle(15))
                .monospacedDigit()
                .foregroundColor(BevelColors.textPrimary)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.cardSubtle))
        }
    }
}

// MARK: - N6B. Blood Test / Lab Report AI Scanner Sheet (Photo or PDF via PDFKit + Gemini Vision!)

struct LabReportScannerSheet: View {
    @ObservedObject var store: ImprovingStore
    let onClose: () -> Void

    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var showPdfImporter: Bool = false
    @State private var pageImages: [UIImage] = []
    @State private var pageJpegs: [Data] = []
    @State private var extractedPdfText: String = ""
    @State private var selectedSourceName: String = ""

    @State private var isAnalyzing: Bool = false
    @State private var errorMsg: String? = nil
    @State private var draftReport: LabReportRecord? = nil

    // Quick manual biomarker fields
    @State private var manualName: String = ""
    @State private var manualValue: String = ""
    @State private var manualUnit: String = "ng/mL"
    @State private var manualStatus: LabBiomarkerStatus = .normal

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // 1. Upload Photo or PDF Card
                    BevelCard(cornerRadius: 20) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 7) {
                                Image(systemName: "doc.text.viewfinder")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(BevelColors.bioTeal)
                                Text("LECTOR DE ANALÍTICAS CON GEMINI IA")
                                    .font(ImprovingFont.microLabel(11))
                                    .foregroundColor(BevelColors.bioTeal)
                            }

                            Text("Sube una foto o el PDF de tu analítica de sangre. Gemini extrae automáticamente Vitamina D, Ferritina, Glucosa, HbA1c, Colesterol, TSH, Testosterona y rangos óptimos.")
                                .font(ImprovingFont.caption(12.5))
                                .foregroundColor(BevelColors.textSecondary)

                            HStack(spacing: 10) {
                                PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                                    Label("Foto analítica", systemImage: "photo.on.rectangle")
                                        .font(ImprovingFont.caption(13))
                                        .fontWeight(.semibold)
                                        .foregroundColor(BevelColors.textPrimary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 11)
                                        .background(RoundedRectangle(cornerRadius: 12).fill(BevelColors.cardSubtle))
                                }

                                Button { showPdfImporter = true } label: {
                                    Label("Importar PDF", systemImage: "doc.richtext.fill")
                                        .font(ImprovingFont.caption(13))
                                        .fontWeight(.semibold)
                                        .foregroundColor(BevelColors.textPrimary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 11)
                                        .background(RoundedRectangle(cornerRadius: 12).fill(BevelColors.cardSubtle))
                                }
                            }

                            if !selectedSourceName.isEmpty {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(BevelColors.greenPrimary)
                                    Text(selectedSourceName)
                                        .font(ImprovingFont.caption(12.5))
                                        .foregroundColor(BevelColors.textPrimary)
                                        .lineLimit(1)
                                    Spacer()
                                }
                            }

                            if let firstImg = pageImages.first {
                                Image(uiImage: firstImg)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 140)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }

                            Button { runLabExtraction() } label: {
                                HStack(spacing: 8) {
                                    if isAnalyzing {
                                        ProgressView().tint(.white)
                                        Text("Extrayendo biomarcadores con Gemini…")
                                    } else {
                                        Image(systemName: "sparkles")
                                        Text("Analizar analítica con IA")
                                    }
                                }
                                .font(ImprovingFont.cardTitle(14))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Capsule().fill((pageJpegs.isEmpty && extractedPdfText.isEmpty) ? Color.gray.opacity(0.45) : BevelColors.indigoEnd))
                            }
                            .disabled(isAnalyzing || (pageJpegs.isEmpty && extractedPdfText.isEmpty))

                            if let err = errorMsg {
                                Text(err)
                                    .font(ImprovingFont.caption(12))
                                    .foregroundColor(BevelColors.amberStart)
                            }
                        }
                        .padding(16)
                    }

                    // 2. Extracted Draft Review & Save
                    if let rep = draftReport {
                        BevelCard(cornerRadius: 20) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(rep.title)
                                            .font(ImprovingFont.sectionTitle(16.5))
                                            .foregroundColor(BevelColors.textPrimary)
                                        Text("\(rep.dateIso) · \(rep.biomarkers.count) biomarcadores · \(rep.sourceLabel)")
                                            .font(ImprovingFont.caption(12))
                                            .foregroundColor(BevelColors.textSecondary)
                                    }
                                    Spacer()
                                }

                                if !rep.summary.isEmpty {
                                    Text(rep.summary)
                                        .font(ImprovingFont.body(13))
                                        .foregroundColor(BevelColors.textSecondary)
                                }

                                ForEach(rep.biomarkers) { item in
                                    LabBiomarkerBarRow(item: item)
                                }

                                Button {
                                    store.saveLabReport(rep)
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                    onClose()
                                } label: {
                                    Text("Guardar analítica en Biología (\(rep.biomarkers.count) marcadores)")
                                        .font(ImprovingFont.cardTitle(14.5))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 13)
                                        .background(Capsule().fill(BevelColors.emeraldEnd))
                                }
                            }
                            .padding(16)
                        }
                    }

                    // 3. Quick Manual Biomarker Entry
                    BevelCard(cornerRadius: 20) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("AÑADIR BIOMARCADOR MANUAL")
                                .font(ImprovingFont.microLabel(10.5))
                                .foregroundColor(BevelColors.textMuted)

                            TextField("Ej: Vitamina D, Ferritina, Glucosa, TSH…", text: $manualName)
                                .font(ImprovingFont.body(14))
                                .foregroundColor(BevelColors.textPrimary)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.cardSubtle))

                            HStack(spacing: 8) {
                                TextField("Valor", text: $manualValue)
                                    .keyboardType(.decimalPad)
                                    .keyboardDoneToolbar()
                                    .font(ImprovingFont.cardTitle(14.5))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .padding(10)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.cardSubtle))

                                TextField("Unidad", text: $manualUnit)
                                    .font(ImprovingFont.body(14))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .frame(width: 96)
                                    .padding(10)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.cardSubtle))

                                Picker("Estado", selection: $manualStatus) {
                                    ForEach(LabBiomarkerStatus.allCases, id: \.self) { st in
                                        Text(st.rawValue).tag(st)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(manualStatus.color)
                            }

                            Button {
                                let cleanName = manualName.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !cleanName.isEmpty,
                                      let val = Double(manualValue.replacingOccurrences(of: ",", with: ".")) else { return }
                                let item = LabBiomarkerItem(
                                    id: UUID().uuidString,
                                    name: cleanName,
                                    value: val,
                                    unit: manualUnit.trimmingCharacters(in: .whitespacesAndNewlines),
                                    refMin: nil,
                                    refMax: nil,
                                    optimalMin: nil,
                                    optimalMax: nil,
                                    status: manualStatus,
                                    category: "Manual"
                                )
                                store.addManualBiomarker(item)
                                manualName = ""
                                manualValue = ""
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                onClose()
                            } label: {
                                Text("Guardar biomarcador manual")
                                    .font(ImprovingFont.cardTitle(14))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                                    .background(Capsule().fill(BevelColors.floatingDarkButton))
                            }
                        }
                        .padding(16)
                    }
                }
                .padding(16)
            }
            .background(BevelColors.canvas)
            .navigationTitle("Analítica de sangre IA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Cerrar", action: onClose) }
            }
            .onChange(of: selectedPhotoItem) { _, item in
                guard let item else { return }
                Task {
                    if let raw = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: raw),
                       let jpg = MealPhotoStorage.prepareJpegData(from: img, maxDimension: 1500, quality: 0.82) {
                        await MainActor.run {
                            pageImages = [img]
                            pageJpegs = [jpg]
                            extractedPdfText = ""
                            selectedSourceName = "Foto cargada (1 página)"
                            errorMsg = nil
                        }
                    }
                }
            }
            .fileImporter(isPresented: $showPdfImporter, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    loadPdfDocument(url: url)
                case .failure(let err):
                    errorMsg = err.localizedDescription
                }
            }
        }
    }

    private func loadPdfDocument(url: URL) {
        selectedSourceName = "Cargando PDF…"
        errorMsg = nil
        Task.detached(priority: .userInitiated) {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            guard let doc = PDFDocument(url: url) else {
                await MainActor.run {
                    selectedSourceName = ""
                    errorMsg = "No se pudo abrir el PDF seleccionado."
                }
                return
            }
            var imgs: [UIImage] = []
            var jpegs: [Data] = []
            var fullText = ""
            let pageCount = doc.pageCount
            let maxPages = min(pageCount, 4)
            for idx in 0..<maxPages {
                guard let page = doc.page(at: idx) else { continue }
                if let t = page.string, !t.isEmpty {
                    fullText += t + "\n"
                }
                let thumb = page.thumbnail(of: CGSize(width: 1100, height: 1500), for: .mediaBox)
                imgs.append(thumb)
                if let jpg = MealPhotoStorage.prepareJpegData(from: thumb, maxDimension: 1400, quality: 0.80) {
                    jpegs.append(jpg)
                }
            }
            let fileName = url.lastPathComponent
            await MainActor.run {
                pageImages = imgs
                pageJpegs = jpegs
                extractedPdfText = fullText
                selectedSourceName = "\(fileName) (\(pageCount) pág.)"
                errorMsg = nil
            }
        }
    }

    private func runLabExtraction() {
        isAnalyzing = true
        errorMsg = nil
        let jpegs = pageJpegs
        let pdfTxt = extractedPdfText
        let key = store.geminiApiKey
        let model = store.selectedGeminiModel
        let allowCloud = store.cloudAIEnabled
        let allowKeyless = store.allowKeylessAIFallback

        Task {
            let res = await GeminiCoachService.shared.analyzeLabReportWithAI(
                pageImagesData: jpegs,
                extractedPdfText: pdfTxt,
                apiKey: key,
                selectedModel: model,
                allowCloudAI: allowCloud,
                allowKeylessFallback: allowKeyless
            )
            await MainActor.run {
                isAnalyzing = false
                if let rep = res.report {
                    draftReport = rep
                } else {
                    errorMsg = res.errorMessage ?? "No se detectaron biomarcadores."
                }
            }
        }
    }
}

// MARK: - Biomarker Visual Range Bar Row (Shared between BiologiaScreen & Scanner)

struct LabBiomarkerBarRow: View {
    let item: LabBiomarkerItem
    var ageDeltaYears: Double? = nil

    private var pointerFraction: Double {
        if let lo = item.refMin, let hi = item.refMax, hi > lo {
            let span = hi - lo
            let extendedLow = lo - span * 0.25
            let extendedHigh = hi + span * 0.25
            return min(max((item.value - extendedLow) / (extendedHigh - extendedLow), 0.04), 0.96)
        }
        switch item.status {
        case .low: return 0.16
        case .normal: return 0.48
        case .optimal: return 0.62
        case .high: return 0.86
        }
    }

    private func formattedDelta(_ d: Double) -> String {
        if abs(d) < 0.05 { return "0,0 años" }
        return String(format: "%+.1f años", locale: Locale(identifier: "es_ES"), d)
    }

    private func deltaTint(_ d: Double) -> Color {
        if d <= -0.05 { return BevelColors.bioTeal }
        if d >= 0.05 { return BevelColors.coralHigh }
        return BevelColors.textMuted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(ImprovingFont.cardTitle(14))
                        .foregroundColor(BevelColors.textPrimary)
                    if let lo = item.refMin, let hi = item.refMax {
                        Text(String(format: "Ref: %.1f – %.1f %@", locale: Locale(identifier: "es_ES"), lo, hi, item.unit))
                            .font(ImprovingFont.caption(11))
                            .foregroundColor(BevelColors.textMuted)
                    } else {
                        Text(item.category)
                            .font(ImprovingFont.caption(11))
                            .foregroundColor(BevelColors.textMuted)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.1f %@", locale: Locale(identifier: "es_ES"), item.value, item.unit))
                        .font(ImprovingFont.cardTitle(14.5))
                        .monospacedDigit()
                        .foregroundColor(BevelColors.textPrimary)
                    HStack(spacing: 6) {
                        Text(item.status.rawValue)
                            .font(ImprovingFont.caption(10.5))
                            .fontWeight(.bold)
                            .foregroundColor(item.status.color)
                        if let delta = ageDeltaYears {
                            Text(formattedDelta(delta))
                                .font(ImprovingFont.caption(10.5))
                                .fontWeight(.bold)
                                .monospacedDigit()
                                .foregroundColor(deltaTint(delta))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(deltaTint(delta).opacity(0.14)))
                        }
                    }
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    HStack(spacing: 2) {
                        Capsule().fill(BevelColors.amberStart.opacity(0.28)).frame(width: geo.size.width * 0.20, height: 6)
                        Capsule().fill(BevelColors.greenPrimary.opacity(0.35)).frame(width: geo.size.width * 0.56, height: 6)
                        Capsule().fill(BevelColors.coralHigh.opacity(0.28)).frame(maxWidth: .infinity, maxHeight: 6)
                    }
                    Circle()
                        .fill(item.status.color)
                        .frame(width: 11, height: 11)
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
                        .offset(x: max(0, min(geo.size.width - 11, geo.size.width * CGFloat(pointerFraction) - 5.5)))
                }
            }
            .frame(height: 12)
        }
        .padding(.vertical, 4)
    }
}

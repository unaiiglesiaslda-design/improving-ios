import SwiftUI
import UIKit

// MARK: - N5 + Apartado 1.6. Evaluación Semanal (7d), Mensual MPA (30d) y Trimestral (90d) + Exportación PDF Clínico y CSV

struct WeeklyReviewScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void
    let onAskCoach: () -> Void

    @State private var showShareSheet: Bool = false
    @State private var selectedPeriod: PerformanceAssessmentPeriod = .weekly7d

    private func formatHM(_ mins: Int) -> String {
        "\(mins / 60)h \(String(format: "%02d", mins % 60))m"
    }

    private func computePeriodSummary(days: Int) -> (
        avgRec: Int?, recDelta: Int?,
        avgHrv: Double?, hrvDelta: Double?,
        avgSleepMin: Int?, sleepDelta: Int?,
        avgStrain: Int?, strainDelta: Int?,
        daysWithData: Int
    ) {
        let window = store.trailingCalendarSummaries(days: days * 2)
        let prev = Array(window.prefix(days))
        let cur = Array(window.suffix(days))

        func avgInt(_ vals: [Int]) -> Int? { vals.isEmpty ? nil : Int((Double(vals.reduce(0, +)) / Double(vals.count)).rounded()) }
        func avgDbl(_ vals: [Double]) -> Double? { vals.isEmpty ? nil : (vals.reduce(0, +) / Double(vals.count)) }

        let cRec = avgInt(cur.compactMap { $0.summary?.recoveryPct })
        let pRec = avgInt(prev.compactMap { $0.summary?.recoveryPct })
        let cHrv = avgDbl(cur.compactMap { $0.summary?.hrvMs })
        let pHrv = avgDbl(prev.compactMap { $0.summary?.hrvMs })
        let cSlp = avgInt(cur.compactMap { $0.summary?.asleepMinutes })
        let pSlp = avgInt(prev.compactMap { $0.summary?.asleepMinutes })
        let cStr = avgInt(cur.compactMap { $0.summary?.strainPct })
        let pStr = avgInt(prev.compactMap { $0.summary?.strainPct })
        let validDays = cur.filter { $0.summary?.recoveryPct != nil || $0.summary?.asleepMinutes != nil || $0.summary?.strainPct != nil }.count

        return (
            cRec, (cRec != nil && pRec != nil) ? (cRec! - pRec!) : nil,
            cHrv, (cHrv != nil && pHrv != nil) ? (cHrv! - pHrv!) : nil,
            cSlp, (cSlp != nil && pSlp != nil) ? (cSlp! - pSlp!) : nil,
            cStr, (cStr != nil && pStr != nil) ? (cStr! - pStr!) : nil,
            validDays
        )
    }

    var body: some View {
        let report = store.computeWeeklyReview()
        let aiInsight = store.weeklyAiInsightsCache[report.weekKey]
        let span = selectedPeriod.rawValue
        let periodStats = computePeriodSummary(days: span)
        let curWindow = store.trailingCalendarSummaries(days: span)
        let recSeries: [Double?] = curWindow.map { $0.summary?.recoveryPct.map { Double($0) } }
        let sleepSeries: [Double?] = curWindow.map { $0.summary?.asleepMinutes.map { Double($0) / 60.0 } }
        let strainSeries: [Double?] = curWindow.map { $0.summary?.strainPct.map { Double($0) } }
        let zoneProg = store.longevityZoneProgress

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Atmospheric Header
                ZStack(alignment: .top) {
                    LinearGradient(
                        colors: BevelColors.isDarkMode
                            ? [Color(hex: 0x202744), Color(hex: 0x171A2A), BevelColors.canvas]
                            : [Color(hex: 0xEDF0FA), BevelColors.canvas],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea(edges: .top)

                    VStack(spacing: 14) {
                        HStack {
                            Button(action: onBack) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .frame(width: 40, height: 40)
                                    .background(Circle().fill(BevelColors.glassChromeFill))
                                    .overlay(Circle().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.8))
                            }
                            Spacer()
                            Button { showShareSheet = true } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 13.5, weight: .semibold))
                                    Text("Compartir")
                                        .font(ImprovingFont.caption(12.5))
                                        .fontWeight(.semibold)
                                }
                                .foregroundColor(BevelColors.textPrimary)
                                .padding(.horizontal, 14)
                                .frame(height: 38)
                                .background(Capsule().fill(BevelColors.glassChromeFill))
                                .overlay(Capsule().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.8))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                        VStack(spacing: 6) {
                            Text(selectedPeriod.badgeTitle)
                                .font(ImprovingFont.microLabel(11))
                                .foregroundColor(BevelColors.periwinkleStart)
                            Text(selectedPeriod == .weekly7d ? report.dateRangeLabel : "Últimos \(selectedPeriod.rawValue) días")
                                .font(ImprovingFont.displayLarge(26))
                                .foregroundColor(BevelColors.textPrimary)
                            Text("Comparado con los \(selectedPeriod.rawValue) días anteriores · \(periodStats.daysWithData) días con lecturas reales")
                                .font(ImprovingFont.caption(12.5))
                                .foregroundColor(BevelColors.textSecondary)

                            // 7d / 30d MPA / 90d Period Selector
                            HStack(spacing: 8) {
                                ForEach(PerformanceAssessmentPeriod.allCases) { p in
                                    let sel = selectedPeriod == p
                                    Button {
                                        AppHaptics.selection()
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            selectedPeriod = p
                                        }
                                    } label: {
                                        Text(p.title)
                                            .font(ImprovingFont.caption(12))
                                            .fontWeight(.bold)
                                            .foregroundColor(sel ? .white : BevelColors.textSecondary)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Capsule().fill(sel ? BevelColors.indigoEnd : BevelColors.card))
                                    }
                                }
                            }
                            .padding(.top, 4)
                        }
                        .padding(.bottom, 8)
                    }
                }

                VStack(alignment: .leading, spacing: 16) {
                    // 1. Gemini AI 3 Actionable Conclusions Card
                    BevelCard(cornerRadius: 22) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                BevelMascotOrb(size: 26)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("ANÁLISIS SEMANAL GEMINI IA")
                                        .font(ImprovingFont.microLabel(10.5))
                                        .foregroundColor(BevelColors.greenPrimary)
                                    if let ins = aiInsight {
                                        Text("\(ins.modelUsed) · \(ins.generatedAtLabel)")
                                            .font(ImprovingFont.caption(10.5))
                                            .foregroundColor(BevelColors.textMuted)
                                    }
                                }
                                Spacer()
                                Button {
                                    store.generateWeeklyReviewAI(report: report, force: true)
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(BevelColors.textSecondary)
                                        .frame(width: 32, height: 32)
                                        .background(Circle().fill(BevelColors.cardSubtle))
                                }
                                .disabled(store.isGeneratingWeeklyReviewAI)
                            }

                            if store.isGeneratingWeeklyReviewAI {
                                HStack(spacing: 10) {
                                    ProgressView().scaleEffect(0.85)
                                    Text("Sintetizando tus últimos 14 días reales…")
                                        .font(ImprovingFont.body(13.5))
                                        .foregroundColor(BevelColors.textSecondary)
                                }
                                .padding(.vertical, 8)
                            } else if let ins = aiInsight {
                                Text(ins.headline)
                                    .font(ImprovingFont.sectionTitle(17))
                                    .foregroundColor(BevelColors.textPrimary)

                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(Array(ins.takeaways.enumerated()), id: \.offset) { idx, item in
                                        HStack(alignment: .top, spacing: 10) {
                                            Text("\(idx + 1)")
                                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                                .foregroundColor(.white)
                                                .frame(width: 22, height: 22)
                                                .background(Circle().fill(BevelColors.indigoEnd))
                                            Text(item)
                                                .font(ImprovingFont.body(13.5))
                                                .foregroundColor(BevelColors.textSecondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }

                                Button(action: onAskCoach) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "bubble.left.and.sparkles.fill")
                                            .font(.system(size: 12))
                                        Text("Profundizar en el chat con Improving IA")
                                            .font(ImprovingFont.caption(12.5))
                                            .fontWeight(.semibold)
                                    }
                                    .foregroundColor(BevelColors.periwinkleStart)
                                    .padding(.top, 4)
                                }
                            } else {
                                Button {
                                    store.generateWeeklyReviewAI(report: report, force: true)
                                } label: {
                                    Label("Generar 3 conclusiones con Gemini IA", systemImage: "sparkles")
                                        .font(ImprovingFont.cardTitle(14))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Capsule().fill(BevelColors.indigoEnd))
                                }
                            }
                        }
                        .padding(16)
                    }

                    // 2. Core KPIs Grid (7d / 30d MPA / 90d vs Prev Period Deltas)
                    Text("Evolución frente a los \(selectedPeriod.rawValue) días previos")
                        .font(ImprovingFont.sectionTitle(18))
                        .foregroundColor(BevelColors.textPrimary)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        kpiTile(
                            title: "Recuperación",
                            icon: "leaf.fill",
                            accent: BevelColors.greenPrimary,
                            value: periodStats.avgRec.map { "\($0)%" } ?? "--",
                            deltaText: periodStats.recDelta.map { "\($0 >= 0 ? "+" : "")\($0) pts" },
                            isGoodDelta: (periodStats.recDelta ?? 0) >= 0,
                            spark: recSeries
                        )
                        kpiTile(
                            title: "VFC media",
                            icon: "waveform.path.ecg",
                            accent: BevelColors.bioTeal,
                            value: periodStats.avgHrv.map { String(format: "%.1f ms", locale: Locale(identifier: "es_ES"), $0) } ?? "--",
                            deltaText: periodStats.hrvDelta.map { String(format: "%+.1f ms", locale: Locale(identifier: "es_ES"), $0) },
                            isGoodDelta: (periodStats.hrvDelta ?? 0) >= 0,
                            spark: curWindow.map { $0.summary?.hrvMs }
                        )
                        kpiTile(
                            title: "Sueño medio",
                            icon: "moon.stars.fill",
                            accent: BevelColors.periwinkleStart,
                            value: periodStats.avgSleepMin.map { formatHM($0) } ?? "--",
                            deltaText: periodStats.sleepDelta.map { "\($0 >= 0 ? "+" : "")\($0) min" },
                            isGoodDelta: (periodStats.sleepDelta ?? 0) >= 0,
                            spark: sleepSeries
                        )
                        kpiTile(
                            title: "Esfuerzo medio",
                            icon: "flame.fill",
                            accent: BevelColors.amberStart,
                            value: periodStats.avgStrain.map { "\($0)%" } ?? "--",
                            deltaText: periodStats.strainDelta.map { "\($0 >= 0 ? "+" : "")\($0) pts" },
                            isGoodDelta: true,
                            spark: strainSeries
                        )
                    }

                    // 2B. Longevity HR Zones & Weekly Strength Compliance Card (Apartado 1.6)
                    BevelCard(cornerRadius: 20) {
                        VStack(alignment: .leading, spacing: 11) {
                            HStack {
                                Image(systemName: "heart.text.square.fill")
                                    .foregroundColor(BevelColors.greenPrimary)
                                Text("METAS DE LONGEVIDAD SEMANAL (OMS / HEALTHSPAN)")
                                    .font(ImprovingFont.microLabel(10))
                                    .foregroundColor(BevelColors.textMuted)
                                Spacer()
                                Text("\(zoneProg.overallCompliancePct)% cumplido")
                                    .font(ImprovingFont.caption(11))
                                    .fontWeight(.bold)
                                    .monospacedDigit()
                                    .foregroundColor(zoneProg.overallCompliancePct >= 75 ? BevelColors.greenPrimary : BevelColors.amberStart)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill((zoneProg.overallCompliancePct >= 75 ? BevelColors.greenPrimary : BevelColors.amberStart).opacity(0.14)))
                            }
                            summaryMetricRow(
                                icon: "figure.run",
                                color: BevelColors.greenPrimary,
                                label: "Zonas 1–3 Aeróbica (base mitocondrial)",
                                value: "\(zoneProg.weeklyZone1To3Minutes) / \(zoneProg.targetZone1To3Minutes) min",
                                sub: "Objetivo clínico ≥150 min/semana"
                            )
                            Divider().background(BevelColors.divider)
                            summaryMetricRow(
                                icon: "bolt.heart.fill",
                                color: BevelColors.coralHigh,
                                label: "Zonas 4–5 Alta intensidad (VO₂ máx.)",
                                value: "\(zoneProg.weeklyZone4To5Minutes) / \(zoneProg.targetZone4To5Minutes) min",
                                sub: "Objetivo pico ≥25 min/semana"
                            )
                            Divider().background(BevelColors.divider)
                            summaryMetricRow(
                                icon: "figure.strengthtraining.traditional",
                                color: BevelColors.amberStart,
                                label: "Fuerza muscular semanal",
                                value: "\(zoneProg.weeklyStrengthSessions) / \(zoneProg.targetStrengthSessions) ses. (\(zoneProg.weeklyStrengthMinutes)m)",
                                sub: "Objetivo ≥3 sesiones o ≥75 min/semana"
                            )
                        }
                        .padding(16)
                    }

                    // 3. Training, Nutrition & Sleep Debt Breakdown
                    BevelCard(cornerRadius: 20) {
                        VStack(spacing: 12) {
                            summaryMetricRow(
                                icon: "figure.run",
                                color: BevelColors.orangeEnd,
                                label: "Entrenamientos completados",
                                value: "\(report.workoutsCount) (\(report.totalWorkoutMinutes) min)",
                                sub: report.workoutsDelta == 0 ? "Igual que semana previa" : (report.workoutsDelta > 0 ? "+\(report.workoutsDelta) vs semana pasada" : "\(report.workoutsDelta) vs semana pasada")
                            )
                            Divider().background(BevelColors.divider)
                            summaryMetricRow(
                                icon: "heart.circle.fill",
                                color: report.cardioLoadState.accentColor,
                                label: "Carga cardiovascular EWMA",
                                value: "\(report.cardioLoadCurrent)",
                                sub: report.cardioLoadState.rawValue
                            )
                            Divider().background(BevelColors.divider)
                            summaryMetricRow(
                                icon: "bed.double.fill",
                                color: report.sleepDebtMinutes > 40 ? BevelColors.amberStart : BevelColors.greenPrimary,
                                label: "Deuda de sueño actual",
                                value: report.sleepDebtMinutes > 0 ? formatHM(report.sleepDebtMinutes) : "0 min",
                                sub: report.sleepDebtMinutes > 40 ? "Conviene adelantar la hora de dormir" : "Deuda controlada"
                            )
                            Divider().background(BevelColors.divider)
                            summaryMetricRow(
                                icon: "fork.knife",
                                color: NutritionPalette.scoreLavender,
                                label: "Nutrición media (7 d)",
                                value: report.avgNutritionScore.map { "\($0)/100" } ?? "--",
                                sub: report.avgNetEnergyKcal.map { "Balance neto medio: \($0 > 0 ? "+" : "")\($0) kcal/día" } ?? "Registra comidas para ver balance"
                            )
                            if let steps = report.avgSteps {
                                Divider().background(BevelColors.divider)
                                summaryMetricRow(
                                    icon: "shoeprints.fill",
                                    color: BevelColors.skyBlue,
                                    label: "Pasos medios diarios",
                                    value: "\(steps)",
                                    sub: steps >= 8000 ? "Por encima del objetivo activo" : "Margen de mejora en actividad diaria"
                                )
                            }
                        }
                        .padding(16)
                    }

                    // 4. Most Consistent Journal Habits
                    if !report.topHabits.isEmpty {
                        Text("Hábitos más constantes del Diario")
                            .font(ImprovingFont.sectionTitle(17.5))
                            .foregroundColor(BevelColors.textPrimary)

                        BevelCard(cornerRadius: 20) {
                            VStack(spacing: 10) {
                                ForEach(Array(report.topHabits.enumerated()), id: \.offset) { idx, h in
                                    HStack(spacing: 10) {
                                        Text(h.emoji).font(.system(size: 18))
                                        Text(h.title)
                                            .font(ImprovingFont.cardTitle(14))
                                            .foregroundColor(BevelColors.textPrimary)
                                        Spacer()
                                        Text("\(h.count) / 7 días")
                                            .font(ImprovingFont.caption(12.5))
                                            .fontWeight(.bold)
                                            .monospacedDigit()
                                            .foregroundColor(BevelColors.greenPrimary)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(Capsule().fill(BevelColors.greenSoftBg))
                                    }
                                    if idx < report.topHabits.count - 1 {
                                        Divider().background(BevelColors.divider)
                                    }
                                }
                            }
                            .padding(14)
                        }
                    }

                    // 5. Clinical PDF & CSV Export Card (Apartado 1.6)
                    ClinicalReportExportCard(store: store, periodDays: selectedPeriod.rawValue)
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 150)
        }
        .background(BevelColors.canvas)
        .onAppear {
            if store.weeklyAiInsightsCache[report.weekKey] == nil {
                store.generateWeeklyReviewAI(report: report, force: false)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSummaryCardSheet(store: store, kind: .weeklyReview(report), onClose: { showShareSheet = false })
        }
    }

    private func kpiTile(
        title: String,
        icon: String,
        accent: Color,
        value: String,
        deltaText: String?,
        isGoodDelta: Bool,
        spark: [Double?]
    ) -> some View {
        BevelCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(accent)
                    Text(title)
                        .font(ImprovingFont.caption(12.5))
                        .foregroundColor(BevelColors.textSecondary)
                        .lineLimit(1)
                }

                Text(value)
                    .font(ImprovingFont.metricHero(22))
                    .monospacedDigit()
                    .foregroundColor(BevelColors.textPrimary)

                HStack {
                    if let d = deltaText {
                        Text(d)
                            .font(ImprovingFont.caption(11.5))
                            .fontWeight(.semibold)
                            .foregroundColor(isGoodDelta ? BevelColors.greenPrimary : BevelColors.coralHigh)
                    } else {
                        Text("Sin previa")
                            .font(ImprovingFont.caption(11))
                            .foregroundColor(BevelColors.textMuted)
                    }
                    Spacer()
                    if spark.compactMap({ $0 }).count >= 2 {
                        TrendSparklineWithBand(optionalPoints: spark, lineColor: accent, fillUnder: true, showGlowDot: true)
                            .frame(width: 58, height: 24)
                    }
                }
            }
            .padding(14)
        }
    }

    private func summaryMetricRow(icon: String, color: Color, label: String, value: String, sub: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 34, height: 34)
                .background(Circle().fill(color.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(ImprovingFont.cardTitle(14))
                    .foregroundColor(BevelColors.textPrimary)
                Text(sub)
                    .font(ImprovingFont.caption(11.5))
                    .foregroundColor(BevelColors.textSecondary)
            }
            Spacer(minLength: 6)
            Text(value)
                .font(ImprovingFont.cardTitle(14.5))
                .monospacedDigit()
                .foregroundColor(BevelColors.textPrimary)
        }
    }
}

// MARK: - Clinical PDF & CSV Exporter for Doctors, Nutritionists & Coaches (Apartado 1.6)

struct ClinicalReportExportCard: View {
    @ObservedObject var store: ImprovingStore
    let periodDays: Int

    @State private var cachedPdfURL: URL? = nil
    @State private var cachedCsvURL: URL? = nil

    private func refreshExports() {
        cachedPdfURL = try? ClinicalReportExporter.generateClinicalPDF(store: store, periodDays: periodDays)
        cachedCsvURL = try? ClinicalReportExporter.generateBiometricCSV(store: store, periodDays: periodDays)
    }

    var body: some View {
        let exportKey = "\(periodDays)#\(store.dataRevision)#\(store.labReports.count)"
        BevelCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.richtext.fill")
                        .foregroundColor(BevelColors.skyBlue)
                    Text("EXPORTACIÓN CLÍNICA Y DEPORTIVA (PDF / CSV)")
                        .font(ImprovingFont.microLabel(10))
                        .foregroundColor(BevelColors.textMuted)
                }
                Text("Genera un informe clínico completo con tus medias de \(periodDays) días (VFC, FCR, Sueño, Esfuerzo, Zonas Cardíacas, Edad Biológica y última Analítica de Sangre) o una tabla CSV para Excel.")
                    .font(ImprovingFont.caption(12))
                    .foregroundColor(BevelColors.textSecondary)

                HStack(spacing: 10) {
                    if let pdfURL = cachedPdfURL {
                        ShareLink(item: pdfURL) {
                            Label("Exportar PDF médico", systemImage: "doc.fill")
                                .font(ImprovingFont.caption(12.5))
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(RoundedRectangle(cornerRadius: 12).fill(BevelColors.indigoEnd))
                        }
                    } else {
                        Button { refreshExports() } label: {
                            Label("Preparar PDF médico", systemImage: "doc.fill")
                                .font(ImprovingFont.caption(12.5))
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(RoundedRectangle(cornerRadius: 12).fill(BevelColors.indigoEnd))
                        }
                    }
                    if let csvURL = cachedCsvURL {
                        ShareLink(item: csvURL) {
                            Label("Exportar CSV", systemImage: "tablecells.fill")
                                .font(ImprovingFont.caption(12.5))
                                .fontWeight(.bold)
                                .foregroundColor(BevelColors.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(RoundedRectangle(cornerRadius: 12).fill(BevelColors.cardSubtle))
                        }
                    } else {
                        Button { refreshExports() } label: {
                            Label("Preparar CSV", systemImage: "tablecells.fill")
                                .font(ImprovingFont.caption(12.5))
                                .fontWeight(.bold)
                                .foregroundColor(BevelColors.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(RoundedRectangle(cornerRadius: 12).fill(BevelColors.cardSubtle))
                        }
                    }
                }
            }
            .padding(16)
        }
        .task(id: exportKey) {
            refreshExports()
        }
    }
}

@MainActor
enum ClinicalReportExporter {
    static func generateBiometricCSV(store: ImprovingStore, periodDays: Int = 30) throws -> URL {
        let items = store.trailingCalendarSummaries(days: periodDays)
        var lines: [String] = [
            "Fecha,Recuperacion_Pct,Sueno_Min,Sueno_Pct,Esfuerzo_Pct,Strain_21,VFC_ms,FCR_ppm,FR_rpm,SpO2_Pct,Temp_C,Pasos,Kcal_Ingeridas,Proteina_g"
        ]
        for item in items {
            let d = item.summary
            let nut = store.nutritionDayTotals(for: item.iso)
            let recS: String = d?.recoveryPct.map { "\($0)" } ?? ""
            let slpMinS: String = d?.asleepMinutes.map { "\($0)" } ?? ""
            let slpPctS: String = d?.sleepPct.map { "\($0)" } ?? ""
            let strPctS: String = d?.strainPct.map { "\($0)" } ?? ""
            let str21S: String = d?.strain21.map { String(format: "%.1f", $0) } ?? ""
            let hrvS: String = d?.hrvMs.map { String(format: "%.1f", $0) } ?? ""
            let rhrS: String = d?.restingHrBpm.map { String(format: "%.1f", $0) } ?? ""
            let rrS: String = d?.respRateRpm.map { String(format: "%.1f", $0) } ?? ""
            let spo2S: String = d?.spo2Percent.map { String(format: "%.1f", $0) } ?? ""
            let tmpS: String = d?.wristTempAbsoluteC.map { String(format: "%.2f", $0) } ?? ""
            let stpS: String = d?.stepsCount.map { "\($0)" } ?? ""
            let kcalS: String = nut.kcal > 0 ? "\(nut.kcal)" : ""
            let protS: String = nut.proteinG > 0 ? "\(Int(nut.proteinG.rounded()))" : ""
            let cols: [String] = [item.iso, recS, slpMinS, slpPctS, strPctS, str21S, hrvS, rhrS, rrS, spo2S, tmpS, stpS, kcalS, protS]
            lines.append(cols.joined(separator: ","))
        }
        let csvData = Data(lines.joined(separator: "\n").utf8)
        let outURL = FileManager.default.temporaryDirectory.appendingPathComponent("Improving_MPA_\(periodDays)d.csv")
        try csvData.write(to: outURL, options: [.atomic, .completeFileProtection])
        return outURL
    }

    static func generateClinicalPDF(store: ImprovingStore, periodDays: Int = 30) throws -> URL {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842) // A4
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let items = store.trailingCalendarSummaries(days: periodDays)
        let bio = store.biologicalAgeSnapshot()
        let pace = store.paceOfAgingSnapshot()
        let zp = store.longevityZoneProgress
        let name = store.userProfile.fullName.isEmpty ? "Usuario Improving" : store.userProfile.fullName

        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 18),
                .foregroundColor: UIColor.black
            ]
            let sectionAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 13),
                .foregroundColor: UIColor.darkGray
            ]
            let bodyAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11),
                .foregroundColor: UIColor.black
            ]

            var y: CGFloat = 36
            func draw(_ text: String, attrs: [NSAttributedString.Key: Any], spacing: CGFloat = 18) {
                (text as NSString).draw(in: CGRect(x: 36, y: y, width: 523, height: 44), withAttributes: attrs)
                y += spacing
            }

            draw("IMPROVING · INFORME CLÍNICO Y EVALUACIÓN DE RENDIMIENTO (\(periodDays) DÍAS)", attrs: titleAttrs, spacing: 26)
            draw("Paciente / Atleta: \(name) · Edad cronológica: \(String(format: "%.1f", bio.eval.chronoAgeYears)) años · Modo: \(store.globalGoalMode.rawValue)", attrs: bodyAttrs, spacing: 20)
            draw("Edad Biológica (9 pilares Healthspan): \(String(format: "%.1f", bio.eval.bioAgeYears)) años (Delta \(String(format: "%+.1f", bio.eval.deltaYears)) a) · Ritmo: \(pace.map { String(format: "%.2fx", $0.multiplier) } ?? "1.00x")", attrs: bodyAttrs, spacing: 24)

            draw("1. MEDIAS FISIOLÓGICAS (\(periodDays) DÍAS)", attrs: sectionAttrs, spacing: 20)
            let recs = items.compactMap { $0.summary?.recoveryPct }
            let hrvs = items.compactMap { $0.summary?.hrvMs }
            let rhrs = items.compactMap { $0.summary?.restingHrBpm }
            let slps = items.compactMap { $0.summary?.asleepMinutes }
            let avgRec = recs.isEmpty ? "--" : "\(recs.reduce(0, +) / recs.count)%"
            let avgHrv = hrvs.isEmpty ? "--" : String(format: "%.1f ms", hrvs.reduce(0, +) / Double(hrvs.count))
            let avgRhr = rhrs.isEmpty ? "--" : String(format: "%.1f ppm", rhrs.reduce(0, +) / Double(rhrs.count))
            let avgSlp = slps.isEmpty ? "--" : String(format: "%.1f h", Double(slps.reduce(0, +)) / Double(slps.count) / 60.0)
            draw("• Recuperación media: \(avgRec)   |   VFC media: \(avgHrv)   |   FCR media: \(avgRhr)   |   Sueño medio: \(avgSlp)", attrs: bodyAttrs, spacing: 22)

            draw("2. CUMPLIMIENTO SEMANAL DE ZONAS CARDÍACAS Y FUERZA", attrs: sectionAttrs, spacing: 20)
            draw("• Zonas 1–3 Aeróbica: \(zp.weeklyZone1To3Minutes) / 150 min   |   Zonas 4–5 VO2: \(zp.weeklyZone4To5Minutes) / 25 min   |   Fuerza: \(zp.weeklyStrengthSessions) sesiones (\(zp.weeklyStrengthMinutes) min)", attrs: bodyAttrs, spacing: 24)

            let labs = store.latestBiomarkersByName
            if !labs.isEmpty {
                draw("3. ÚLTIMOS BIOMARCADORES DE SANGRE (\(labs.count))", attrs: sectionAttrs, spacing: 20)
                for b in labs.prefix(12) {
                    draw("• \(b.name): \(String(format: "%.1f", b.value)) \(b.unit) [\(b.status.rawValue)]", attrs: bodyAttrs, spacing: 16)
                    if y > 780 { break }
                }
            }
        }

        let outURL = FileManager.default.temporaryDirectory.appendingPathComponent("Improving_Informe_Clinico_\(periodDays)d.pdf")
        try data.write(to: outURL, options: [.atomic, .completeFileProtection])
        return outURL
    }
}

import SwiftUI

// MARK: - N5. Resumen Semanal Inteligente (7d vs Previous 7d + Gemini AI 3 Takeaways + Share Card)

struct WeeklyReviewScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void
    let onAskCoach: () -> Void

    @State private var showShareSheet: Bool = false

    private func formatHM(_ mins: Int) -> String {
        "\(mins / 60)h \(String(format: "%02d", mins % 60))m"
    }

    var body: some View {
        let report = store.computeWeeklyReview()
        let aiInsight = store.weeklyAiInsightsCache[report.weekKey]
        let last7 = store.trailingCalendarSummaries(days: 7)
        let recSeries: [Double?] = last7.map { $0.summary?.recoveryPct.map { Double($0) } }
        let sleepSeries: [Double?] = last7.map { $0.summary?.asleepMinutes.map { Double($0) / 60.0 } }
        let strainSeries: [Double?] = last7.map { $0.summary?.strainPct.map { Double($0) } }

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

                        VStack(spacing: 4) {
                            Text("RESUMEN SEMANAL")
                                .font(ImprovingFont.microLabel(11))
                                .foregroundColor(BevelColors.periwinkleStart)
                            Text(report.dateRangeLabel)
                                .font(ImprovingFont.displayLarge(26))
                                .foregroundColor(BevelColors.textPrimary)
                            Text("Comparado con los 7 días anteriores · \(report.daysWithData) días con lecturas reales")
                                .font(ImprovingFont.caption(12.5))
                                .foregroundColor(BevelColors.textSecondary)
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

                    // 2. Core KPIs Grid (7d vs Prev 7d Deltas)
                    Text("Evolución frente a la semana pasada")
                        .font(ImprovingFont.sectionTitle(18))
                        .foregroundColor(BevelColors.textPrimary)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        kpiTile(
                            title: "Recuperación",
                            icon: "leaf.fill",
                            accent: BevelColors.greenPrimary,
                            value: report.avgRecovery.map { "\($0)%" } ?? "--",
                            deltaText: report.recoveryDelta.map { "\($0 >= 0 ? "+" : "")\($0) pts" },
                            isGoodDelta: (report.recoveryDelta ?? 0) >= 0,
                            spark: recSeries
                        )
                        kpiTile(
                            title: "VFC media",
                            icon: "waveform.path.ecg",
                            accent: BevelColors.bioTeal,
                            value: report.avgHrv.map { String(format: "%.1f ms", locale: Locale(identifier: "es_ES"), $0) } ?? "--",
                            deltaText: report.hrvDelta.map { String(format: "%+.1f ms", locale: Locale(identifier: "es_ES"), $0) },
                            isGoodDelta: (report.hrvDelta ?? 0) >= 0,
                            spark: last7.map { $0.summary?.hrvMs }
                        )
                        kpiTile(
                            title: "Sueño medio",
                            icon: "moon.stars.fill",
                            accent: BevelColors.periwinkleStart,
                            value: report.avgSleepMinutes.map { formatHM($0) } ?? "--",
                            deltaText: report.sleepMinutesDelta.map { "\($0 >= 0 ? "+" : "")\($0) min" },
                            isGoodDelta: (report.sleepMinutesDelta ?? 0) >= 0,
                            spark: sleepSeries
                        )
                        kpiTile(
                            title: "Esfuerzo medio",
                            icon: "flame.fill",
                            accent: BevelColors.amberStart,
                            value: report.avgStrainPct.map { "\($0)%" } ?? "--",
                            deltaText: report.strainDelta.map { "\($0 >= 0 ? "+" : "")\($0) pts" },
                            isGoodDelta: true,
                            spark: strainSeries
                        )
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

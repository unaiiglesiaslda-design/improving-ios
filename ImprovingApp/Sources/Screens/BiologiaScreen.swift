import SwiftUI

struct BiologiaScreen: View {
    @ObservedObject var store: ImprovingStore
    let onSelectHealthMetric: (HealthMetricKind) -> Void
    let onOpenBodyMetric: (BodyCompositionMetricKind) -> Void
    let onOpenVo2Max: () -> Void
    let onNavigate: (OverlayRoute) -> Void

    @State private var expandedCategoryId: String? = "sleep"
    @State private var showBioInfoSheet: Bool = false
    @State private var showShareBioSheet: Bool = false
    @State private var showScaleSheet: Bool = false
    @State private var showLabScannerSheet: Bool = false
    @State private var pendingDeleteLabReport: LabReportRecord? = nil

    var body: some View {
        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: store.userProfile)
        let recent30 = store.trailingCalendarSummaries(days: 30)
        let bioSnap = store.biologicalAgeSnapshot()
        let bioEval = bioSnap.eval
        let hasBioBase = bioSnap.hasData
        let meanRhr = bioSnap.meanRhr
        let meanHrv = bioSnap.meanHrv
        let meanSleep = bioSnap.meanSleep
        let meanSteps = bioSnap.meanSteps
        let vo2Val = bioSnap.vo2Val

        let chronologicalAge = bioEval.chronoAgeYears
        let bioDelta = hasBioBase ? bioEval.deltaYears : 0.0
        let bioAge = hasBioBase ? bioEval.bioAgeYears : chronologicalAge

        let hrvSeries = recent30.map { $0.summary?.hrvMs }
        let rhrSeries = recent30.map { $0.summary?.restingHrBpm }
        let weightSeries = recent30.map { $0.summary?.bodyWeightKg }
        let fatSeries = recent30.map { $0.summary?.bodyFatPct }
        let leanSeries = recent30.map { $0.summary?.leanMassKg }
        let vo2Series = recent30.map { $0.summary?.vo2MaxMlKgMin }
        let latestBiomarkers = store.latestBiomarkersByName

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                // 1. Atmospheric Biological Age Hero (P2: Real Action Menu on ···)
                ZStack(alignment: .top) {
                    LinearGradient(
                        colors: BevelColors.isDarkMode ? [Color(hex: 0x1A2E2A), Color(hex: 0x172022), BevelColors.canvas] : [BevelColors.canvas, BevelColors.canvas],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 330)
                    .ignoresSafeArea(edges: .top)

                    VStack(spacing: 8) {
                        HStack {
                            Spacer()
                            Menu {
                                Button { showShareBioSheet = true } label: {
                                    Label("Compartir Edad Biológica", systemImage: "square.and.arrow.up")
                                }
                                Button { showBioInfoSheet = true } label: {
                                    Label("Cómo se calcula", systemImage: "info.circle")
                                }
                                Divider()
                                Button { showScaleSheet = true } label: {
                                    Label("Registrar peso / báscula", systemImage: "scalemass.fill")
                                }
                                Button { showLabScannerSheet = true } label: {
                                    Label("Subir analítica de sangre (IA)", systemImage: "doc.text.viewfinder")
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .frame(width: 40, height: 40)
                                    .background(Circle().fill(BevelColors.glassChromeFill))
                                    .overlay(Circle().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.8))
                            }
                        }

                        Text("Edad biológica")
                            .font(ImprovingFont.displayLarge(23))
                            .foregroundColor(BevelColors.textPrimary)
                        Text("A fecha \(store.fullDateLabel)")
                            .font(ImprovingFont.caption(13.5))
                            .foregroundColor(BevelColors.textSecondary)

                        BioAgeCurvedDial(
                            bioAgeYears: bioAge,
                            chronoAgeYears: chronologicalAge,
                            diffYears: bioDelta,
                            sampledDays: store.trailingCalendarSummaries(days: 30).filter { $0.summary != nil }.count,
                            hasData: hasBioBase
                        )
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Edad biológica")
                        .accessibilityValue(hasBioBase ? String(format: "%.1f años", locale: Locale(identifier: "es_ES"), bioAge) : "Sin datos suficientes")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }

                VStack(alignment: .leading, spacing: 16) {
                    // Quick Biology Actions: Scale + Blood Test AI (N6!)
                    if let pace = store.paceOfAgingSnapshot() {
                        paceOfAgingCard(pace)
                    }
                    if !hasBioBase {
                        Button { onNavigate(.dispositivos) } label: {
                            BevelCard(cornerRadius: 20) {
                                HStack(spacing: 12) {
                                    Image(systemName: "heart.text.square.fill")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundColor(BevelColors.bioTeal)
                                        .frame(width: 42, height: 42)
                                        .background(Circle().fill(BevelColors.bioTeal.opacity(0.15)))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Activa tu Edad Biológica real")
                                            .font(ImprovingFont.cardTitle(14.5))
                                            .foregroundColor(BevelColors.textPrimary)
                                        Text("Sincroniza Apple Salud o importa exportar.zip para calcular sueño, VFC, FCR y pasos reales.")
                                            .font(ImprovingFont.caption(12))
                                            .foregroundColor(BevelColors.textSecondary)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(BevelColors.bioTeal)
                                }
                                .padding(14)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 10) {
                        Button { showScaleSheet = true } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "scalemass.fill")
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundColor(BevelColors.skyBlue)
                                Text("+ Báscula / TA")
                                    .font(ImprovingFont.cardTitle(13.5))
                                    .foregroundColor(BevelColors.textPrimary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BevelColors.card))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
                        }

                        Button { showLabScannerSheet = true } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "doc.text.viewfinder")
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundColor(BevelColors.bioTeal)
                                Text("+ Analítica IA")
                                    .font(ImprovingFont.cardTitle(13.5))
                                    .foregroundColor(BevelColors.textPrimary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BevelColors.card))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(BevelColors.bioTeal.opacity(0.35), lineWidth: 0.8))
                        }
                    }

                    HStack(alignment: .firstTextBaseline) {
                        Text("Biomarcadores de edad")
                            .font(ImprovingFont.sectionTitle(18.5))
                            .foregroundColor(BevelColors.textPrimary)
                        Spacer()
                        if hasBioBase {
                            Text(impactPillText(bioDelta))
                                .font(ImprovingFont.caption(12))
                                .fontWeight(.bold)
                                .monospacedDigit()
                                .foregroundColor(impactColor(bioDelta))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(impactColor(bioDelta).opacity(0.14)))
                        }
                    }

                    if meanSleep != nil || store.sleepConsistencyPct != nil {
                        let consPct = store.sleepConsistencyPct
                        let combinedSleepDelta = (meanSleep != nil ? bioEval.sleepDelta : 0) + (consPct != nil ? bioEval.sleepConsistencyDelta : 0)
                        let sleepSub: String = {
                            if let avgS = meanSleep {
                                let hrs = Int(avgS)
                                let mins = Int(((avgS - Double(hrs)) * 60).rounded())
                                if let c = consPct {
                                    return "\(hrs) h \(String(format: "%02d", mins)) min · Consistencia \(c)%"
                                }
                                return "\(hrs) h \(String(format: "%02d", mins)) min promedio"
                            }
                            return "\(consPct ?? 0)% regularidad horaria"
                        }()
                        bioCategoryCard(
                            id: "sleep",
                            icon: "moon.fill",
                            ringPrimary: impactColor(combinedSleepDelta),
                            ringSecondary: BevelColors.trackGroove,
                            title: "Sueño",
                            subtitle: sleepSub,
                            subtitleColor: BevelColors.textSecondary,
                            deltaYears: combinedSleepDelta
                        ) {
                            if let avgS = meanSleep {
                                let hrs = Int(avgS)
                                let mins = Int(((avgS - Double(hrs)) * 60).rounded())
                                BioDotRangeSlider(
                                    title: "Duración media (30 d)",
                                    valueLabel: "\(hrs) h \(String(format: "%02d", mins)) min",
                                    minLabel: "5 h",
                                    maxLabel: "10 h",
                                    deltaText: sliderDeltaNumber(bioEval.sleepDelta),
                                    deltaUnit: "años",
                                    positionFrac: min(max((avgS - 5.0) / 5.0, 0.05), 0.95),
                                    fillStartFrac: min(max((norms.sleepLowHours - 5.0) / 5.0, 0.10), 0.70),
                                    fillEndFrac: min(max((norms.sleepHighHours - 5.0) / 5.0, 0.45), 0.96),
                                    accentColor: BevelColors.bioTeal,
                                    deltaColor: impactColor(bioEval.sleepDelta)
                                )
                            }
                            if let c = consPct {
                                if meanSleep != nil { Divider().background(BevelColors.divider) }
                                BioDotRangeSlider(
                                    title: "Consistencia circadiana del sueño",
                                    valueLabel: "\(c)%",
                                    minLabel: "30%",
                                    maxLabel: "100%",
                                    deltaText: sliderDeltaNumber(bioEval.sleepConsistencyDelta),
                                    deltaUnit: "años",
                                    positionFrac: min(max(Double(c - 30) / 70.0, 0.05), 0.95),
                                    fillStartFrac: 0.64,
                                    fillEndFrac: 0.96,
                                    accentColor: BevelColors.periwinkleStart,
                                    deltaColor: impactColor(bioEval.sleepConsistencyDelta)
                                )
                            }
                        }
                    }

                    if meanSteps != nil || bioEval.hasWeeklyZones || bioEval.hasWeeklyStrength {
                        let zp = store.longevityZoneProgress
                        let combinedActivityDelta = (meanSteps != nil ? bioEval.activityDelta : 0)
                            + (bioEval.hasWeeklyZones ? bioEval.weeklyZonesDelta : 0)
                            + (bioEval.hasWeeklyStrength ? bioEval.weeklyStrengthDelta : 0)
                        let activitySub: String = {
                            var parts: [String] = []
                            if let avgSt = meanSteps { parts.append("\(avgSt) pasos/d") }
                            if bioEval.hasWeeklyZones { parts.append("Z1–5: \(zp.weeklyZone1To3Minutes + zp.weeklyZone4To5Minutes)m") }
                            if bioEval.hasWeeklyStrength { parts.append("Fuerza: \(zp.weeklyStrengthMinutes)m") }
                            return parts.joined(separator: " · ")
                        }()
                        bioCategoryCard(
                            id: "activity",
                            icon: "figure.run",
                            ringPrimary: impactColor(combinedActivityDelta),
                            ringSecondary: BevelColors.trackGroove,
                            title: "Actividad",
                            subtitle: activitySub,
                            subtitleColor: BevelColors.textSecondary,
                            deltaYears: combinedActivityDelta
                        ) {
                            if let avgSt = meanSteps {
                                BioDotRangeSlider(
                                    title: "Número de pasos medio (30 d)",
                                    valueLabel: String(format: "%.1fk", Double(avgSt) / 1000.0),
                                    minLabel: "0",
                                    maxLabel: "16k",
                                    deltaText: sliderDeltaNumber(bioEval.activityDelta),
                                    deltaUnit: "años",
                                    positionFrac: min(max(Double(avgSt) / 16000.0, 0.04), 0.96),
                                    fillStartFrac: min(max(Double(norms.dailyStepsGoal) / 16000.0, 0.25), 0.75),
                                    fillEndFrac: 0.90,
                                    accentColor: BevelColors.bioTeal,
                                    deltaColor: impactColor(bioEval.activityDelta)
                                )
                            }
                            if bioEval.hasWeeklyZones {
                                if meanSteps != nil { Divider().background(BevelColors.divider) }
                                BioDotRangeSlider(
                                    title: "Zonas cardíacas semanales (Z1–3: \(zp.weeklyZone1To3Minutes)m · Z4–5: \(zp.weeklyZone4To5Minutes)m)",
                                    valueLabel: "\(zp.weeklyZone1To3Minutes + zp.weeklyZone4To5Minutes) min/sem",
                                    minLabel: "0",
                                    maxLabel: "240m",
                                    deltaText: sliderDeltaNumber(bioEval.weeklyZonesDelta),
                                    deltaUnit: "años",
                                    positionFrac: min(max(Double(zp.weeklyZone1To3Minutes + zp.weeklyZone4To5Minutes) / 240.0, 0.05), 0.95),
                                    fillStartFrac: 0.60,
                                    fillEndFrac: 0.95,
                                    accentColor: BevelColors.greenPrimary,
                                    deltaColor: impactColor(bioEval.weeklyZonesDelta)
                                )
                            }
                            if bioEval.hasWeeklyStrength {
                                if meanSteps != nil || bioEval.hasWeeklyZones { Divider().background(BevelColors.divider) }
                                BioDotRangeSlider(
                                    title: "Fuerza muscular semanal (\(zp.weeklyStrengthSessions) sesiones / 7 d)",
                                    valueLabel: "\(zp.weeklyStrengthMinutes) min",
                                    minLabel: "0",
                                    maxLabel: "180m",
                                    deltaText: sliderDeltaNumber(bioEval.weeklyStrengthDelta),
                                    deltaUnit: "años",
                                    positionFrac: min(max(Double(zp.weeklyStrengthMinutes) / 180.0, 0.05), 0.95),
                                    fillStartFrac: 0.42,
                                    fillEndFrac: 0.92,
                                    accentColor: BevelColors.amberStart,
                                    deltaColor: impactColor(bioEval.weeklyStrengthDelta)
                                )
                            }
                        }
                    }

                    if meanRhr != nil || vo2Val != nil {
                        bioCategoryCard(
                            id: "fitness",
                            icon: "heart.fill",
                            ringPrimary: impactColor(bioEval.fitnessDelta),
                            ringSecondary: BevelColors.trackGroove,
                            title: "Fitness cardiovascular",
                            subtitle: meanRhr.map { String(format: "FCR media %.1f ppm", locale: Locale(identifier: "es_ES"), $0) } ?? "VO₂ máx. registrado",
                            subtitleColor: BevelColors.textSecondary,
                            deltaYears: bioEval.fitnessDelta
                        ) {
                            if let v = vo2Val {
                                BioDotRangeSlider(
                                    title: "VO₂ máx.",
                                    valueLabel: String(format: "%.1f", locale: Locale(identifier: "es_ES"), v),
                                    minLabel: "20",
                                    maxLabel: "65",
                                    deltaText: sliderDeltaNumber(bioEval.vo2Delta),
                                    deltaUnit: "años",
                                    positionFrac: min(max((v - 20.0) / 45.0, 0.05), 0.95),
                                    fillStartFrac: min(max((norms.vo2GoodThreshold - 20.0) / 45.0, 0.10), 0.75),
                                    fillEndFrac: min(max((norms.vo2ExcellentThreshold - 20.0) / 45.0, 0.35), 0.95),
                                    accentColor: BevelColors.amberStart,
                                    deltaColor: impactColor(bioEval.vo2Delta)
                                )
                            }
                            if let r = meanRhr {
                                if vo2Val != nil { Divider().background(BevelColors.divider) }
                                BioDotRangeSlider(
                                    title: "FC en reposo (30 d)",
                                    valueLabel: String(format: "%.1f ppm", locale: Locale(identifier: "es_ES"), r),
                                    minLabel: "40",
                                    maxLabel: "90",
                                    deltaText: sliderDeltaNumber(bioEval.rhrDelta),
                                    deltaUnit: "años",
                                    positionFrac: min(max((r - 40.0) / 50.0, 0.05), 0.95),
                                    fillStartFrac: min(max((norms.rhrLowBpm - 40.0) / 50.0, 0.04), 0.50),
                                    fillEndFrac: min(max((norms.rhrHighBpm - 40.0) / 50.0, 0.20), 0.80),
                                    accentColor: BevelColors.bioTeal,
                                    deltaColor: impactColor(bioEval.rhrDelta)
                                )
                            }
                        }
                    }

                    if let avgH = meanHrv, avgH > 2.0 {
                        bioCategoryCard(
                            id: "autonomic",
                            icon: "waveform.path.ecg",
                            ringPrimary: impactColor(bioEval.autonomicDelta),
                            ringSecondary: BevelColors.trackGroove,
                            title: "Sistema autónomo (VFC)",
                            subtitle: String(format: "%.1f ms promedio (30 d)", locale: Locale(identifier: "es_ES"), avgH),
                            subtitleColor: BevelColors.textSecondary,
                            deltaYears: bioEval.autonomicDelta
                        ) {
                            BioDotRangeSlider(
                                title: "VFC media (30 d)",
                                valueLabel: String(format: "%.1f ms", locale: Locale(identifier: "es_ES"), avgH),
                                minLabel: "20 ms",
                                maxLabel: "130 ms",
                                deltaText: sliderDeltaNumber(bioEval.autonomicDelta),
                                deltaUnit: "años",
                                positionFrac: min(max((avgH - 20.0) / 110.0, 0.04), 0.96),
                                fillStartFrac: min(max((norms.hrvLowMs - 20.0) / 110.0, 0.12), 0.72),
                                fillEndFrac: min(max((norms.hrvHighMs - 20.0) / 110.0, 0.35), 0.94),
                                accentColor: BevelColors.greenPrimary,
                                deltaColor: impactColor(bioEval.autonomicDelta)
                            )
                        }
                    }

                    if bioEval.hasBody {
                        let wNow = store.latestBodyWeightKg ?? store.userProfile.weightKg
                        let hm = max(store.userProfile.heightCm / 100.0, 1.2)
                        let bmiNow = wNow / (hm * hm)
                        let bfOpt = store.latestBodyFatPct
                        bioCategoryCard(
                            id: "body",
                            icon: "figure.stand",
                            ringPrimary: impactColor(bioEval.bodyDelta),
                            ringSecondary: BevelColors.trackGroove,
                            title: "Composición corporal",
                            subtitle: bfOpt.map { String(format: "Grasa %.1f%% · IMC %.1f", locale: Locale(identifier: "es_ES"), $0, bmiNow) }
                                ?? String(format: "IMC %.1f · %.1f kg", locale: Locale(identifier: "es_ES"), bmiNow, wNow),
                            subtitleColor: BevelColors.textSecondary,
                            deltaYears: bioEval.bodyDelta
                        ) {
                            if let bf = bfOpt {
                                BioDotRangeSlider(
                                    title: "Grasa corporal",
                                    valueLabel: String(format: "%.1f%%", locale: Locale(identifier: "es_ES"), bf),
                                    minLabel: "6%",
                                    maxLabel: "38%",
                                    deltaText: sliderDeltaNumber(bioEval.bodyDelta),
                                    deltaUnit: "años",
                                    positionFrac: min(max((bf - 6.0) / 32.0, 0.04), 0.96),
                                    fillStartFrac: min(max((norms.optimalBodyFatLowPct - 6.0) / 32.0, 0.08), 0.65),
                                    fillEndFrac: min(max((norms.optimalBodyFatHighPct - 6.0) / 32.0, 0.25), 0.85),
                                    accentColor: BevelColors.skyBlue,
                                    deltaColor: impactColor(bioEval.bodyDelta)
                                )
                            } else {
                                BioDotRangeSlider(
                                    title: "Índice de masa corporal (IMC)",
                                    valueLabel: String(format: "%.1f", locale: Locale(identifier: "es_ES"), bmiNow),
                                    minLabel: "16",
                                    maxLabel: "34",
                                    deltaText: sliderDeltaNumber(bioEval.bodyDelta),
                                    deltaUnit: "años",
                                    positionFrac: min(max((bmiNow - 16.0) / 18.0, 0.04), 0.96),
                                    fillStartFrac: min(max((norms.bmiOptimalLow - 16.0) / 18.0, 0.10), 0.55),
                                    fillEndFrac: min(max((norms.bmiOptimalHigh - 16.0) / 18.0, 0.30), 0.75),
                                    accentColor: BevelColors.skyBlue,
                                    deltaColor: impactColor(bioEval.bodyDelta)
                                )
                            }
                        }
                    }

                    // Analíticas de Sangre (integradas directamente en la Edad Biológica con impacto por biomarcador!)
                    if latestBiomarkers.isEmpty {
                        Button { showLabScannerSheet = true } label: {
                            BevelCard(cornerRadius: 24) {
                                HStack(spacing: 14) {
                                    Image(systemName: "cross.case.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(BevelColors.bioTeal)
                                        .frame(width: 48, height: 48)
                                        .background(Circle().fill(BevelColors.bioTeal.opacity(0.15)))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Analíticas de sangre")
                                            .font(ImprovingFont.cardTitle(16))
                                            .foregroundColor(BevelColors.textPrimary)
                                        Text("Sube tu PDF o foto para que ajusten tu Edad Biológica")
                                            .font(ImprovingFont.caption(12))
                                            .foregroundColor(BevelColors.textSecondary)
                                    }
                                    Spacer()
                                    Text("+ Subir")
                                        .font(ImprovingFont.caption(12))
                                        .fontWeight(.bold)
                                        .foregroundColor(BevelColors.bioTeal)
                                }
                                .padding(16)
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        let latestRep = store.labReports.first
                        bioCategoryCard(
                            id: "labs",
                            icon: "cross.case.fill",
                            ringPrimary: impactColor(bioEval.bloodLabsDelta),
                            ringSecondary: BevelColors.trackGroove,
                            title: "Analíticas de sangre",
                            subtitle: "\(latestBiomarkers.count) biomarcadores\(latestRep.map { " · \($0.dateIso)" } ?? "")",
                            subtitleColor: BevelColors.textSecondary,
                            deltaYears: bioEval.bloodLabsDelta
                        ) {
                            if let rep = latestRep {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(rep.title)
                                            .font(ImprovingFont.cardTitle(14))
                                            .foregroundColor(BevelColors.textPrimary)
                                        Text("Impacto clínico acumulado: \(impactDescription(bioEval.bloodLabsDelta))")
                                            .font(ImprovingFont.caption(11.5))
                                            .foregroundColor(impactColor(bioEval.bloodLabsDelta))
                                    }
                                    Spacer()
                                    Menu {
                                        Button("Añadir nueva analítica / marcador", systemImage: "plus") {
                                            showLabScannerSheet = true
                                        }
                                        Button("Eliminar último informe", systemImage: "trash", role: .destructive) {
                                            pendingDeleteLabReport = rep
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                            .font(.system(size: 16))
                                            .foregroundColor(BevelColors.textMuted)
                                    }
                                }
                                Divider().background(BevelColors.divider)
                            }

                            ForEach(Array(bioEval.labImpacts.enumerated()), id: \.element.id) { idx, impact in
                                LabBiomarkerBarRow(item: impact.biomarker, ageDeltaYears: impact.deltaYears)
                                if idx < bioEval.labImpacts.count - 1 {
                                    Divider().background(BevelColors.divider)
                                }
                            }
                        }
                    }

                    // 4. Otros biomarcadores (P2: All wired to dedicated charts & VO₂ max bug FIXED!)
                    Text("Otros biomarcadores")
                        .font(ImprovingFont.sectionTitle(18.5))
                        .foregroundColor(BevelColors.textPrimary)
                        .padding(.top, 4)

                    if let w = store.latestBodyWeightKg {
                        otherBioCard(title: "Peso", statusText: "Registrado", statusColor: BevelColors.skyBlue, value: String(format: "%.1f kg", locale: Locale(identifier: "es_ES"), w), lineColor: BevelColors.skyBlue, points: weightSeries) {
                            onOpenBodyMetric(.weight)
                        }
                    }
                    if store.dataAvailability.hasHrvData || meanHrv != nil {
                        let val = store.dataAvailability.hasHrvData ? store.hrvMs : (meanHrv ?? 0)
                        otherBioCard(title: "VFC histórico", statusText: "Real", statusColor: BevelColors.greenPrimary, value: String(format: "%.1f ms", locale: Locale(identifier: "es_ES"), val), lineColor: BevelColors.greenPrimary, points: hrvSeries) {
                            onSelectHealthMetric(.hrv)
                        }
                    }
                    if store.dataAvailability.hasRestingHrData || meanRhr != nil {
                        let val = store.dataAvailability.hasRestingHrData ? store.restingHrBpm : (meanRhr ?? 0)
                        otherBioCard(title: "Históricos FCR", statusText: "Real", statusColor: BevelColors.skyBlue, value: String(format: "%.1f ppm", locale: Locale(identifier: "es_ES"), val), lineColor: BevelColors.skyBlue, points: rhrSeries) {
                            onSelectHealthMetric(.restingHeartRate)
                        }
                    }
                    if let fat = store.latestBodyFatPct {
                        otherBioCard(title: "Grasa corporal", statusText: "Registrado", statusColor: BevelColors.amberStart, value: String(format: "%.1f %%", locale: Locale(identifier: "es_ES"), fat), lineColor: BevelColors.amberStart, points: fatSeries) {
                            onOpenBodyMetric(.bodyFat)
                        }
                    }
                    if let lean = store.latestLeanMassKg {
                        otherBioCard(title: "Masa magra", statusText: "Registrado", statusColor: BevelColors.bioTeal, value: String(format: "%.1f kg", locale: Locale(identifier: "es_ES"), lean), lineColor: BevelColors.bioTeal, points: leanSeries) {
                            onOpenBodyMetric(.leanMass)
                        }
                    }
                    if let v = vo2Val {
                        otherBioCard(title: "VO₂ máx.", statusText: "Registrado", statusColor: BevelColors.amberStart, value: String(format: "%.1f", locale: Locale(identifier: "es_ES"), v), lineColor: BevelColors.amberStart, points: vo2Series) {
                            onOpenVo2Max()
                        }
                    }
                    if let bp = store.latestBloodPressure {
                        Button { onOpenBodyMetric(.bloodPressure) } label: {
                            BevelCard(cornerRadius: 20) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("Presión arterial").font(ImprovingFont.cardTitle(15)).foregroundColor(BevelColors.textPrimary)
                                        Text("\(bp.sys)/\(bp.dia) mmHg")
                                            .font(ImprovingFont.caption(13.5))
                                            .fontWeight(.semibold)
                                            .foregroundColor(BevelColors.greenPrimary)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(BevelColors.textMuted)
                                }
                                .padding(16)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    if !hasBioBase {
                        BevelCard(cornerRadius: 20) {
                            Text("Importa tus datos de Apple Health o conecta tu dispositivo en Ajustes para calcular tu biología real sin valores inventados.")
                                .font(ImprovingFont.body(13.5))
                                .foregroundColor(BevelColors.textSecondary)
                                .padding(16)
                        }
                    }

                    // Seguimiento de Ciclo Menstrual y Calibración de Fase Lútea (solo visible si perfil femenino o activo)
                    if store.userProfile.sex == .female || store.cycleTrackingSettings.isEnabled {
                        CycleTrackingBiologyCard(store: store)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 155)
        }
        .background(BevelColors.canvas)
        .sheet(isPresented: $showBioInfoSheet) {
            MetricMethodologyInfoSheet(kind: .biologicalAge, onClose: { showBioInfoSheet = false })
        }
        .sheet(isPresented: $showShareBioSheet) {
            ShareSummaryCardSheet(store: store, kind: .biologicalAge, onClose: { showShareBioSheet = false })
        }
        .sheet(isPresented: $showScaleSheet) {
            ManualScaleLoggerSheet(store: store, onClose: { showScaleSheet = false })
        }
        .sheet(isPresented: $showLabScannerSheet) {
            LabReportScannerSheet(store: store, onClose: { showLabScannerSheet = false })
        }
        .confirmationDialog(
            "¿Eliminar informe de analítica?",
            isPresented: Binding(
                get: { pendingDeleteLabReport != nil },
                set: { if !$0 { pendingDeleteLabReport = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Eliminar informe permanentemente", role: .destructive) {
                if let rep = pendingDeleteLabReport {
                    store.deleteLabReport(id: rep.id)
                }
                pendingDeleteLabReport = nil
            }
            Button("Cancelar", role: .cancel) { pendingDeleteLabReport = nil }
        } message: {
            Text("Se borrarán «\(pendingDeleteLabReport?.title ?? "este informe")» y sus \(pendingDeleteLabReport?.biomarkers.count ?? 0) biomarcadores.")
        }
    }

    private func paceOfAgingCard(_ pace: PaceOfAgingSnapshot) -> some View {
        let accent: Color = {
            if pace.multiplier <= 0.88 { return BevelColors.bioTeal }
            if pace.multiplier <= 1.12 { return BevelColors.skyBlue }
            return BevelColors.coralHigh
        }()
        let clampedFrac = min(max((pace.multiplier - 0.3) / 2.2, 0.04), 0.96)
        return BevelCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "speedometer")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(accent)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(accent.opacity(0.15)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("RITMO DE ENVEJECIMIENTO")
                            .font(ImprovingFont.microLabel(10.5))
                            .foregroundColor(BevelColors.textMuted)
                        Text(pace.statusLabel)
                            .font(ImprovingFont.cardTitle(15))
                            .foregroundColor(BevelColors.textPrimary)
                    }
                    Spacer()
                    Text(String(format: "%.2fx", locale: Locale(identifier: "es_ES"), pace.multiplier))
                        .font(ImprovingFont.displayLarge(22))
                        .monospacedDigit()
                        .foregroundColor(accent)
                }

                GeometryReader { geo in
                    let w = max(geo.size.width, 1)
                    let oneXPos = w * ((1.0 - 0.3) / 2.2)
                    let curPos = w * clampedFrac
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [BevelColors.bioTeal, BevelColors.skyBlue, BevelColors.amberStart, BevelColors.coralHigh],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 8)
                            .opacity(0.32)
                        Rectangle()
                            .fill(BevelColors.textMuted.opacity(0.55))
                            .frame(width: 1.5, height: 14)
                            .offset(x: oneXPos)
                        Circle()
                            .fill(accent)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            .offset(x: max(0, min(curPos - 7, w - 14)))
                    }
                }
                .frame(height: 16)

                HStack {
                    Text("0,3x (Lento)")
                        .font(ImprovingFont.caption(10.5))
                        .foregroundColor(BevelColors.bioTeal)
                    Spacer()
                    Text("1,0x (Normal)")
                        .font(ImprovingFont.caption(10.5))
                        .foregroundColor(BevelColors.textMuted)
                    Spacer()
                    Text("2,5x (Rápido)")
                        .font(ImprovingFont.caption(10.5))
                        .foregroundColor(BevelColors.coralHigh)
                }

                Text(pace.explanation)
                    .font(ImprovingFont.caption(12))
                    .foregroundColor(BevelColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let delta = pace.deltaVsPrior30d {
                    let signText = delta <= -0.05 ? "Mejora" : (delta >= 0.05 ? "Aceleración" : "Estable")
                    Text("\(signText) vs. 30 días previos: \(String(format: "%+.1f", locale: Locale(identifier: "es_ES"), delta)) años biológicos")
                        .font(ImprovingFont.caption(11.5))
                        .fontWeight(.semibold)
                        .foregroundColor(accent)
                }
            }
            .padding(16)
        }
        .accessibilityElement(children: .combine)
    }

    private func impactColor(_ deltaYears: Double) -> Color {
        if deltaYears <= -0.05 { return BevelColors.bioTeal }
        if deltaYears >= 0.05 { return BevelColors.coralHigh }
        return BevelColors.textSecondary
    }

    private func impactPillText(_ deltaYears: Double) -> String {
        if abs(deltaYears) < 0.05 { return "0,0 años" }
        return String(format: "%+.1f años", locale: Locale(identifier: "es_ES"), deltaYears)
    }

    private func sliderDeltaNumber(_ deltaYears: Double) -> String {
        if abs(deltaYears) < 0.05 { return "0,0" }
        return String(format: "%+.1f", locale: Locale(identifier: "es_ES"), deltaYears)
    }

    private func impactDescription(_ deltaYears: Double) -> String {
        if deltaYears <= -0.05 {
            return String(format: "resta %.1f años", locale: Locale(identifier: "es_ES"), abs(deltaYears))
        }
        if deltaYears >= 0.05 {
            return String(format: "suma %.1f años", locale: Locale(identifier: "es_ES"), deltaYears)
        }
        return "efecto neutro (0,0 años)"
    }

    private func bioCategoryCard<Content: View>(
        id: String,
        icon: String,
        ringPrimary: Color,
        ringSecondary: Color,
        title: String,
        subtitle: String,
        subtitleColor: Color,
        deltaYears: Double,
        @ViewBuilder details: @escaping () -> Content
    ) -> some View {
        let isExpanded = expandedCategoryId == id
        let deltaCol = impactColor(deltaYears)
        return BevelCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        expandedCategoryId = isExpanded ? nil : id
                    }
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Canvas { ctx, sz in
                                let center = CGPoint(x: sz.width / 2, y: sz.height / 2)
                                let r = min(sz.width, sz.height) / 2 - 4
                                var p1 = Path()
                                p1.addArc(center: center, radius: r, startAngle: .degrees(-80), endAngle: .degrees(80), clockwise: false)
                                ctx.stroke(p1, with: .color(ringPrimary), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                                var p2 = Path()
                                p2.addArc(center: center, radius: r, startAngle: .degrees(100), endAngle: .degrees(260), clockwise: false)
                                ctx.stroke(p2, with: .color(ringSecondary), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                            }
                            .frame(width: 48, height: 48)
                            Image(systemName: icon)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(ringPrimary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(ImprovingFont.cardTitle(15.5))
                                .foregroundColor(BevelColors.textPrimary)
                                .lineLimit(1)
                            Text(subtitle)
                                .font(ImprovingFont.caption(12.5))
                                .foregroundColor(subtitleColor)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        Text(impactPillText(deltaYears))
                            .font(ImprovingFont.caption(12))
                            .fontWeight(.bold)
                            .monospacedDigit()
                            .foregroundColor(deltaCol)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(deltaCol.opacity(0.14)))
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(BevelColors.textMuted)
                    }
                }

                if isExpanded {
                    Divider().background(BevelColors.divider)
                    details()
                }
            }
            .padding(16)
        }
    }

    private func otherBioCard(title: String, statusText: String, statusColor: Color, value: String, lineColor: Color, points: [Double?], onClick: @escaping () -> Void) -> some View {
        Button(action: onClick) {
            BevelCard(cornerRadius: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title).font(ImprovingFont.cardTitle(15)).foregroundColor(BevelColors.textPrimary)
                        HStack(spacing: 5) {
                            Text(statusText).font(ImprovingFont.caption(13)).fontWeight(.semibold).foregroundColor(statusColor)
                            Text("·").foregroundColor(BevelColors.textMuted)
                            Text(value).font(ImprovingFont.caption(13)).fontWeight(.semibold).monospacedDigit().foregroundColor(BevelColors.textPrimary)
                        }
                    }
                    Spacer()
                    if points.compactMap({ $0 }).count >= 2 {
                        TrendSparklineWithBand(optionalPoints: points, lineColor: lineColor, fillUnder: true, showGlowDot: true)
                            .frame(width: 82, height: 34)
                    }
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(BevelColors.textMuted)
                }
                .padding(16)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Menstrual Cycle Tracking & Luteal Phase Physiological Calibration Card (Apartado 1.8)

struct CycleTrackingBiologyCard: View {
    @ObservedObject var store: ImprovingStore
    @State private var showCycleSheet: Bool = false

    var body: some View {
        let snap = store.currentCyclePhaseSnapshot
        let isRelevant = store.userProfile.sex == .female || store.cycleTrackingSettings.isEnabled

        VStack(alignment: .leading, spacing: 10) {
            if let s = snap {
                BevelCard(cornerRadius: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: s.phase.icon)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(BevelColors.coralHigh)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(BevelColors.coralSoftBg))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("CICLO FISIOLÓGICO · DÍA \(s.dayOfCycle)/\(s.cycleLengthDays)")
                                    .font(ImprovingFont.microLabel(10))
                                    .foregroundColor(BevelColors.textMuted)
                                Text("Fase \(s.phase.rawValue)")
                                    .font(ImprovingFont.cardTitle(15.5))
                                    .foregroundColor(BevelColors.textPrimary)
                            }
                            Spacer()
                            if s.isLutealCalibrationActive {
                                Text("Calibración +\(String(format: "%.2f", locale: Locale(identifier: "es_ES"), s.expectedTempShiftC)) °C")
                                    .font(ImprovingFont.microLabel(9.5))
                                    .foregroundColor(BevelColors.greenPrimary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(BevelColors.greenSoftBg))
                            }
                            Button {
                                showCycleSheet = true
                            } label: {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundColor(BevelColors.textSecondary)
                            }
                        }

                        Text(s.trainingAdvice)
                            .font(ImprovingFont.caption(12))
                            .foregroundColor(BevelColors.textPrimary)
                        Text(s.nutritionAdvice)
                            .font(ImprovingFont.caption(11.5))
                            .foregroundColor(BevelColors.textSecondary)
                    }
                    .padding(16)
                }
            } else if isRelevant {
                Button { showCycleSheet = true } label: {
                    BevelCard(cornerRadius: 20) {
                        HStack(spacing: 12) {
                            Image(systemName: "drop.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(BevelColors.coralHigh)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(BevelColors.coralSoftBg))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Activar seguimiento de ciclo menstrual")
                                    .font(ImprovingFont.cardTitle(14.5))
                                    .foregroundColor(BevelColors.textPrimary)
                                Text("Adapta entrenamiento y evita falsas alertas de temperatura en fase lútea")
                                    .font(ImprovingFont.caption(11.5))
                                    .foregroundColor(BevelColors.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(BevelColors.textMuted)
                        }
                        .padding(14)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showCycleSheet) {
            CycleTrackingSettingsSheet(store: store, onClose: { showCycleSheet = false })
        }
    }
}

private struct CycleTrackingSettingsSheet: View {
    @ObservedObject var store: ImprovingStore
    let onClose: () -> Void

    @State private var isEnabled: Bool = false
    @State private var lastStartDate: Date = Date()
    @State private var cycleLength: Int = 28
    @State private var periodDuration: Int = 5

    var body: some View {
        NavigationStack {
            Form {
                Section("Seguimiento de ciclo y calibración térmica") {
                    Toggle("Activar seguimiento de ciclo", isOn: $isEnabled)
                    DatePicker("Inicio del último periodo", selection: $lastStartDate, in: ...Date(), displayedComponents: .date)
                    Stepper("Duración media del ciclo: \(cycleLength) días", value: $cycleLength, in: 21...38)
                    Stepper("Duración de fase menstrual: \(periodDuration) días", value: $periodDuration, in: 3...8)
                }
                Section {
                    Text("Durante la fase lútea la temperatura de muñeca sube de forma natural (~+0,3 °C). Cuando está activo, el Monitor de Salud calibra tu banda térmica para no confundir la fase lútea con fiebre o sobreentrenamiento.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Ciclo Fisiológico")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar", action: onClose)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Guardar") {
                        let iso = store.isoFormatter.string(from: lastStartDate)
                        store.updateCycleTrackingSettings(
                            CycleTrackingSettings(
                                isEnabled: isEnabled,
                                lastPeriodStartIso: iso,
                                cycleLengthDays: cycleLength,
                                periodDurationDays: periodDuration
                            )
                        )
                        onClose()
                    }
                    .fontWeight(.bold)
                }
            }
            .onAppear {
                let cfg = store.cycleTrackingSettings
                isEnabled = cfg.isEnabled || store.userProfile.sex == .female
                cycleLength = cfg.cycleLengthDays
                periodDuration = cfg.periodDurationDays
                if let dt = store.isoFormatter.date(from: cfg.lastPeriodStartIso) {
                    lastStartDate = dt
                }
            }
        }
        .presentationDetents([.medium])
    }
}

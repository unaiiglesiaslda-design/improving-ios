import SwiftUI

// MARK: - Ventana de Cafeína (Compact Card + Full Pharmacokinetic Sheet — Improving Style)

struct CaffeineWindowCard: View {
    @ObservedObject var store: ImprovingStore
    var onAskCoach: (() -> Void)? = nil

    @State private var showDetailSheet: Bool = false
    @State private var showQuickLoggerSheet: Bool = false

    private func phasePillStyle(_ phase: CaffeineWindowPhase) -> (bg: Color, fg: Color) {
        switch phase {
        case .optimal:
            return (BevelColors.greenSoftBg, BevelColors.greenPrimary)
        case .postWakeDelay, .caution:
            return (BevelColors.amberSoftBg, BevelColors.amberStart)
        case .tooLate:
            return (BevelColors.coralSoftBg, BevelColors.coralHigh)
        }
    }

    var body: some View {
        let snap = store.caffeineWindowSnapshot
        let pill = phasePillStyle(snap.phase)

        BevelCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Button {
                    AppHaptics.selection()
                    showDetailSheet = true
                } label: {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 8) {
                            Image(systemName: "cup.and.saucer.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(BevelColors.periwinkleStart)
                            Text("Ventana de cafeína")
                                .font(ImprovingFont.sectionTitle(16.5))
                                .foregroundColor(BevelColors.textPrimary)
                            Spacer()
                            Text(snap.phase.rawValue)
                                .font(ImprovingFont.caption(11.5))
                                .fontWeight(.bold)
                                .foregroundColor(pill.fg)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(pill.bg))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundColor(BevelColors.textMuted)
                        }

                        CaffeinePhaseTimelineBar(snapshot: snap, isCompactCard: true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    AppHaptics.selection()
                    showQuickLoggerSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 13.5, weight: .bold))
                        Text("Registrar cafeína")
                            .font(ImprovingFont.cardTitle(14.5))
                    }
                    .foregroundColor(BevelColors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12.5)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(BevelColors.cardSubtle))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(BevelColors.cardBorder, lineWidth: 0.7))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .sheet(isPresented: $showDetailSheet) {
            CaffeineWindowDetailSheet(
                store: store,
                onAskCoach: {
                    showDetailSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                        onAskCoach?()
                    }
                },
                onClose: { showDetailSheet = false }
            )
        }
        .sheet(isPresented: $showQuickLoggerSheet) {
            CaffeineQuickLoggerSheet(store: store, onClose: { showQuickLoggerSheet = false })
        }
    }
}

// MARK: - 4-Segment Timeline Bar with Floating Start/Cutoff Callouts & Live Marker

struct CaffeinePhaseTimelineBar: View {
    let snapshot: CaffeineWindowTimelineSnapshot
    let isCompactCard: Bool

    var body: some View {
        let dFrac = CGFloat(snapshot.delayFraction)
        let oFrac = CGFloat(snapshot.optimalEndFraction)
        let cFrac = CGFloat(snapshot.cautionEndFraction)
        let nowFrac = CGFloat(snapshot.nowProgressFraction)

        VStack(spacing: 7) {
            // Top callout pills: ☕ Optimal Start & ☕ Cutoff
            GeometryReader { geo in
                let w = max(geo.size.width, 1)
                let startX = min(max(w * dFrac + 26, 48), w * 0.44)
                let cutX = min(max(w * oFrac, startX + 86), w - 48)
                ZStack {
                    calloutPill(
                        timeLabel: snapshot.optimalStartLabel,
                        iconColor: BevelColors.greenPrimary
                    )
                    .position(x: startX, y: 15)

                    calloutPill(
                        timeLabel: snapshot.cutoffLabel,
                        iconColor: BevelColors.coralHigh
                    )
                    .position(x: cutX, y: 15)
                }
            }
            .frame(height: 30)

            // 4-Segment Phase Bar + White Live Current-Time Pointer (▼)
            GeometryReader { geo in
                let w = max(geo.size.width, 1)
                let gap: CGFloat = 4
                let seg1W = max(w * dFrac - gap, 10)
                let seg2W = max(w * (oFrac - dFrac) - gap, 24)
                let seg3W = max(w * (cFrac - oFrac) - gap, 16)
                let seg4W = max(w * (1.0 - cFrac) - gap, 28)

                let delayCol: Color = isCompactCard ? BevelColors.trackGroove : Color(hex: 0xFF6B4A)
                let optTrackCol: Color = isCompactCard ? Color(hex: 0x1D4B30) : Color(hex: 0x2CE680)
                let optFillCol: Color = Color(hex: 0x2CE680)
                let cautionCol: Color = isCompactCard ? BevelColors.trackGroove : Color(hex: 0xFF6B4A)
                let lateCol: Color = isCompactCard ? BevelColors.trackGroove : Color(hex: 0xF5197A)

                let markerX = min(max(w * nowFrac, 8), w - 8)
                let optProgress: CGFloat = {
                    if nowFrac <= dFrac { return 0 }
                    if nowFrac >= oFrac { return 1 }
                    return (nowFrac - dFrac) / max(oFrac - dFrac, 0.01)
                }()

                ZStack(alignment: .leading) {
                    HStack(spacing: gap) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(delayCol)
                            .frame(width: seg1W, height: 18)

                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(optTrackCol)
                            if isCompactCard && optProgress > 0 {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(optFillCol)
                                    .frame(width: max(8, seg2W * optProgress), height: 18)
                            }
                        }
                        .frame(width: seg2W, height: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(cautionCol)
                            .frame(width: seg3W, height: 18)

                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(lateCol)
                            .frame(maxWidth: .infinity, minHeight: 18, maxHeight: 18)
                            .frame(minWidth: seg4W)
                    }

                    // White downward triangle live position marker
                    Path { p in
                        p.move(to: CGPoint(x: markerX - 6, y: -3))
                        p.addLine(to: CGPoint(x: markerX + 6, y: -3))
                        p.addLine(to: CGPoint(x: markerX, y: 7))
                        p.closeSubpath()
                    }
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                }
            }
            .frame(height: 20)

            // 5 Time Axis Labels
            HStack {
                ForEach(Array(snapshot.axisTickLabels.enumerated()), id: \.offset) { idx, lbl in
                    if idx > 0 { Spacer() }
                    Text(lbl)
                        .font(ImprovingFont.caption(11))
                        .monospacedDigit()
                        .foregroundColor(BevelColors.textSecondary)
                }
            }
            .padding(.top, 2)
        }
    }

    private func calloutPill(timeLabel: String, iconColor: Color) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "cup.and.saucer")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(iconColor)
                Text(timeLabel)
                    .font(ImprovingFont.caption(11.5))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundColor(BevelColors.textPrimary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(BevelColors.cardSubtle))
            .overlay(Capsule().strokeBorder(BevelColors.cardBorder, lineWidth: 0.7))

            Path { p in
                p.move(to: CGPoint(x: 0, y: 0))
                p.addLine(to: CGPoint(x: 8, y: 0))
                p.addLine(to: CGPoint(x: 4, y: 4))
                p.closeSubpath()
            }
            .fill(BevelColors.cardSubtle)
            .frame(width: 8, height: 4)
        }
    }
}

// MARK: - Pharmacokinetic Decay Curve Chart (5.5h Half-Life + 20 mg Sleep Threshold)

private struct CaffeineDecayCurveChart: View {
    let snapshot: CaffeineWindowTimelineSnapshot

    var body: some View {
        let maxCurveMg = snapshot.curvePoints.map(\.mg).max() ?? 0
        let yMax = max(120.0, ceil((maxCurveMg * 1.18) / 40.0) * 40.0)
        let thresholdFrac = CGFloat(min(max(snapshot.sleepThresholdMg / yMax, 0.08), 0.5))

        ZStack(alignment: .bottomTrailing) {
            Canvas { ctx, sz in
                let w = sz.width
                let h = sz.height
                let span = max(snapshot.totalSpanMinutes, 1.0)

                // 1. Subtle optimal window vertical band (green) & sleep-risk band (magenta/coral)
                let optStartX = w * CGFloat(snapshot.delayFraction)
                let optEndX = w * CGFloat(snapshot.optimalEndFraction)
                let optRect = CGRect(x: optStartX, y: 0, width: max(optEndX - optStartX, 2), height: h)
                ctx.fill(Path(optRect), with: .color(BevelColors.greenPrimary.opacity(0.08)))

                let riskStartX = w * CGFloat(snapshot.cautionEndFraction)
                let riskRect = CGRect(x: riskStartX, y: 0, width: max(w - riskStartX, 2), height: h)
                ctx.fill(Path(riskRect), with: .color(Color(hex: 0xF5197A).opacity(0.07)))

                // 2. Faint dashed horizontal gridlines
                for level in [0.25, 0.50, 0.75, 1.0] {
                    let y = h * CGFloat(1.0 - level)
                    var grid = Path()
                    grid.move(to: CGPoint(x: 0, y: y))
                    grid.addLine(to: CGPoint(x: w, y: y))
                    ctx.stroke(
                        grid,
                        with: .color(BevelColors.divider.opacity(0.55)),
                        style: StrokeStyle(lineWidth: 0.7, dash: [3, 4])
                    )
                }

                // 3. Sleep threshold dotted reference line (20 mg)
                let threshY = h * (1.0 - thresholdFrac)
                var threshPath = Path()
                threshPath.move(to: CGPoint(x: 0, y: threshY))
                threshPath.addLine(to: CGPoint(x: w, y: threshY))
                ctx.stroke(
                    threshPath,
                    with: .color(BevelColors.periwinkleStart.opacity(0.75)),
                    style: StrokeStyle(lineWidth: 1.2, dash: [3, 3.5])
                )

                // 4. Pharmacokinetic decay curve (up to now bright, projected future softer)
                let pts: [CGPoint] = snapshot.curvePoints.map { pt in
                    let x = w * CGFloat(pt.minuteOffsetFromWake / span)
                    let y = h * CGFloat(1.0 - min(max(pt.mg / yMax, 0.0), 1.0))
                    return CGPoint(x: x, y: max(4, min(y, h - 2)))
                }

                if pts.count >= 2 {
                    var line = Path()
                    line.move(to: pts[0])
                    for p in pts.dropFirst() {
                        line.addLine(to: p)
                    }

                    var area = line
                    area.addLine(to: CGPoint(x: pts.last!.x, y: h))
                    area.addLine(to: CGPoint(x: pts.first!.x, y: h))
                    area.closeSubpath()

                    ctx.fill(
                        area,
                        with: .linearGradient(
                            Gradient(colors: [BevelColors.periwinkleStart.opacity(0.32), BevelColors.periwinkleStart.opacity(0.02)]),
                            startPoint: CGPoint(x: 0, y: 0),
                            endPoint: CGPoint(x: 0, y: h)
                        )
                    )

                    ctx.stroke(
                        line,
                        with: .color(BevelColors.textPrimary.opacity(0.85)),
                        style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round)
                    )
                }

                // 5. Current live point glowing dot
                let nowX = w * CGFloat(snapshot.nowProgressFraction)
                let nowY = max(6, min(h * CGFloat(1.0 - min(snapshot.currentBodyMg / yMax, 1.0)), h - 3))
                let glowRect = CGRect(x: nowX - 7, y: nowY - 7, width: 14, height: 14)
                ctx.fill(Path(ellipseIn: glowRect), with: .color(BevelColors.periwinkleStart.opacity(0.38)))
                let dotRect = CGRect(x: nowX - 4, y: nowY - 4, width: 8, height: 8)
                ctx.fill(Path(ellipseIn: dotRect), with: .color(.white))
            }
            .frame(height: 158)

            Text("umbral de sueño")
                .font(ImprovingFont.caption(10.5))
                .fontWeight(.semibold)
                .foregroundColor(BevelColors.periwinkleStart)
                .padding(.trailing, 4)
                .padding(.bottom, max(12, 158 * thresholdFrac + 4))
        }
    }
}

// MARK: - Full Caffeine Window Detail Sheet (Exact Match to Reference Screenshots 2–8, Improving Style)

struct CaffeineWindowDetailSheet: View {
    @ObservedObject var store: ImprovingStore
    let onAskCoach: () -> Void
    let onClose: () -> Void

    @State private var showAllSources: Bool = false
    @State private var showQuickLogger: Bool = false
    @State private var activeGuide: CaffeineGuideArticle? = nil

    private struct CaffeineGuideArticle: Identifiable {
        let id: String
        let tag: String
        let title: String
        let subtitle: String
        let bodyText: String
        let accent: Color
    }

    private let guides: [CaffeineGuideArticle] = [
        CaffeineGuideArticle(
            id: "delay",
            tag: "Cafeína",
            title: "Retrasar la cafeína",
            subtitle: "Por qué esperar 30–90 minutos tras levantarte ayuda a mantener tu energía estable toda la tarde.",
            bodyText: "Al despertar, el cortisol sube de forma natural para activarte mientras los restos de adenosina terminan de despejarse. Si tomas cafeína en los primeros minutos, bloqueas temporalmente esos receptores y cuando la cafeína cae a media tarde aparece el clásico bajón energético. Esperar entre 45 y 90 minutos tras levantarte produce un foco más limpio y sostenido.",
            accent: Color(hex: 0xC98B4B)
        ),
        CaffeineGuideArticle(
            id: "sleep",
            tag: "Cafeína",
            title: "Cómo afecta al sueño",
            subtitle: "Momento y dosis para proteger tu sueño profundo (SWS) y REM sin renunciar al café.",
            bodyText: "Incluso cuando consigues conciliar el sueño, tener más de 20 mg de cafeína circulando al acostarte reduce la amplitud de las ondas lentas (sueño profundo reparador) y aumenta los microdespertares. Mantener tu última toma dentro de tu ventana óptima y respetar el límite de ~400 mg/día protege tu VFC y Recuperación del día siguiente.",
            accent: BevelColors.periwinkleStart
        )
    ]

    var body: some View {
        let snap = store.caffeineWindowSnapshot
        let visibleSources = showAllSources
            ? CaffeineBeverageSource.commonSources
            : Array(CaffeineBeverageSource.commonSources.prefix(6))

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    heroHeaderSection(snap)
                    chartAndBarSection(snap)
                    registerCaffeineButton
                    coachInsightSection(snap)

                    if !snap.intakes.isEmpty {
                        loggedIntakesSection(snap)
                    }

                    commonSourcesSection(snap: snap, sources: visibleSources)
                    moreInfoCarouselSection
                    methodologyAndSourcesSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 40)
            }
            .background(BevelColors.canvas)
            .navigationTitle("Ventana de cafeína")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onClose) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundColor(BevelColors.textPrimary)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(BevelColors.card))
                    }
                }
            }
            .sheet(isPresented: $showQuickLogger) {
                CaffeineQuickLoggerSheet(store: store, onClose: { showQuickLogger = false })
            }
            .sheet(item: $activeGuide) { g in
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(g.tag.uppercased())
                                .font(ImprovingFont.microLabel(11))
                                .foregroundColor(g.accent)
                            Text(g.title)
                                .font(ImprovingFont.displayLarge(26))
                                .foregroundColor(BevelColors.textPrimary)
                            Text(g.subtitle)
                                .font(ImprovingFont.cardTitle(15))
                                .foregroundColor(BevelColors.textSecondary)
                            Divider().background(BevelColors.divider)
                            Text(g.bodyText)
                                .font(ImprovingFont.body(14.5))
                                .foregroundColor(BevelColors.textPrimary)
                                .lineSpacing(4)
                        }
                        .padding(20)
                    }
                    .background(BevelColors.canvas)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Cerrar") { activeGuide = nil }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
    }

    private func heroHeaderSection(_ snap: CaffeineWindowTimelineSnapshot) -> some View {
        let riskColor: Color = {
            if snap.residualAtBedtimeMg <= snap.sleepThresholdMg { return BevelColors.greenPrimary }
            if snap.residualAtBedtimeMg <= 45 { return BevelColors.amberStart }
            return BevelColors.coralHigh
        }()
        let riskText: String = {
            if snap.residualAtBedtimeMg <= snap.sleepThresholdMg {
                return "Sin riesgo al acostarte"
            }
            return "~\(Int(snap.residualAtBedtimeMg.rounded())) mg al acostarte (\(snap.bedtimeLabel))"
        }()

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(snap.currentBodyMg.rounded()))")
                    .font(ImprovingFont.displayLarge(44))
                    .monospacedDigit()
                    .foregroundColor(BevelColors.textPrimary)
                Text("mg en el cuerpo")
                    .font(ImprovingFont.sectionTitle(21))
                    .foregroundColor(BevelColors.periwinkleStart)
            }
            Text(riskText)
                .font(ImprovingFont.cardTitle(14.5))
                .foregroundColor(riskColor)
        }
    }

    private func chartAndBarSection(_ snap: CaffeineWindowTimelineSnapshot) -> some View {
        VStack(spacing: 10) {
            CaffeineDecayCurveChart(snapshot: snap)
            CaffeinePhaseTimelineBar(snapshot: snap, isCompactCard: false)
        }
    }

    private var registerCaffeineButton: some View {
        Button {
            AppHaptics.selection()
            showQuickLogger = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                Text("Registrar cafeína")
                    .font(ImprovingFont.cardTitle(15))
            }
            .foregroundColor(BevelColors.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BevelColors.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }

    private func coachInsightSection(_ snap: CaffeineWindowTimelineSnapshot) -> some View {
        let guidance: String = {
            switch snap.phase {
            case .optimal:
                let remStr = WhoopPhysiologyEngine.formatClearanceDuration(snap.minutesRemainingInOptimal)
                return "Estás en tu ventana óptima. Puedes tomar cafeína durante las próximas \(remStr); saldrá de tu sistema antes de las \(snap.bedtimeLabel)."
            case .postWakeDelay:
                let waitStr = WhoopPhysiologyEngine.formatClearanceDuration(snap.minutesUntilOptimalStarts)
                return "Acabas de despertar. Espera \(waitStr) (hasta las \(snap.optimalStartLabel)) para tu primera toma y evita el bajón de energía de la tarde."
            case .caution:
                return "Estás en zona de precaución (corte óptimo a las \(snap.cutoffLabel)). Si tomas algo, elige dosis suaves (té verde o descafeinado) para no afectar a tu sueño profundo."
            case .tooLate:
                return "Has superado tu ventana segura de cafeína. Tomar cafeína ahora mantendrá niveles por encima del umbral de 20 mg al acostarte (\(snap.bedtimeLabel))."
            }
        }()

        return BevelCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(BevelColors.textPrimary)
                        Text("INFORMACIÓN IMPROVING")
                            .font(ImprovingFont.microLabel(11))
                            .foregroundColor(BevelColors.textSecondary)
                    }
                    Spacer()
                    Button(action: onAskCoach) {
                        HStack(spacing: 3) {
                            Text("Preguntar al Coach")
                                .font(ImprovingFont.caption(12.5))
                                .fontWeight(.semibold)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10.5, weight: .bold))
                        }
                        .foregroundColor(BevelColors.textPrimary)
                    }
                    .buttonStyle(.plain)
                }

                Text(guidance)
                    .font(ImprovingFont.body(14))
                    .foregroundColor(BevelColors.textPrimary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
    }

    private func loggedIntakesSection(_ snap: CaffeineWindowTimelineSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tomas registradas hoy")
                    .font(ImprovingFont.sectionTitle(17))
                    .foregroundColor(BevelColors.textPrimary)
                Spacer()
                Text("\(Int(snap.totalTodayMg.rounded())) / 400 mg")
                    .font(ImprovingFont.caption(12))
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundColor(snap.totalTodayMg > 400 ? BevelColors.coralHigh : BevelColors.periwinkleStart)
            }

            BevelCard(cornerRadius: 18) {
                VStack(spacing: 0) {
                    ForEach(Array(snap.intakes.enumerated()), id: \.element.id) { idx, intake in
                        HStack(spacing: 10) {
                            Image(systemName: "cup.and.saucer.fill")
                                .font(.system(size: 13))
                                .foregroundColor(BevelColors.periwinkleStart)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(intake.title)
                                    .font(ImprovingFont.cardTitle(14))
                                    .foregroundColor(BevelColors.textPrimary)
                                Text("\(intake.timeLabel) · \(Int(intake.mg.rounded())) mg")
                                    .font(ImprovingFont.caption(12))
                                    .monospacedDigit()
                                    .foregroundColor(BevelColors.textSecondary)
                            }
                            Spacer()
                            Button {
                                AppHaptics.selection()
                                store.deleteCaffeineIntake(id: intake.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 13))
                                    .foregroundColor(BevelColors.coralHigh)
                                    .frame(width: 34, height: 34)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                        if idx < snap.intakes.count - 1 {
                            Divider().background(BevelColors.divider).padding(.horizontal, 14)
                        }
                    }
                }
            }
        }
    }

    private func commonSourcesSection(snap: CaffeineWindowTimelineSnapshot, sources: [CaffeineBeverageSource]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Fuentes habituales de cafeína")
                    .font(ImprovingFont.sectionTitle(18))
                    .foregroundColor(BevelColors.textPrimary)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        showAllSources.toggle()
                    }
                } label: {
                    Text(showAllSources ? "Ver menos" : "Ver todas")
                        .font(ImprovingFont.caption(12.5))
                        .fontWeight(.semibold)
                        .foregroundColor(BevelColors.textPrimary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(BevelColors.card))
                        .overlay(Capsule().strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
                }
                .buttonStyle(.plain)
            }

            BevelCard(cornerRadius: 22) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Límite adulto: ~400 mg/día (≈4 tazas de café). Los tiempos de eliminación suponen un metabolismo medio.")
                        .font(ImprovingFont.caption(12.5))
                        .foregroundColor(BevelColors.textSecondary)
                        .lineSpacing(2)
                        .padding(.horizontal, 16)
                        .padding(.top, 15)
                        .padding(.bottom, 12)

                    ForEach(Array(sources.enumerated()), id: \.element.id) { idx, src in
                        let clearMin = WhoopPhysiologyEngine.caffeineClearanceMinutes(totalMg: src.mg)
                        let clearTxt = WhoopPhysiologyEngine.formatClearanceDuration(clearMin)
                        let isOk = WhoopPhysiologyEngine.isDrinkSafeForSleepNow(drinkMg: src.mg, snapshot: snap)

                        HStack(alignment: .center, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(src.displayTitle)
                                    .font(ImprovingFont.cardTitle(15))
                                    .foregroundColor(BevelColors.textPrimary)
                                Text("\(Int(src.mg)) mg de cafeína · Se elimina en \(clearTxt)")
                                    .font(ImprovingFont.caption(12.5))
                                    .foregroundColor(BevelColors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 6)
                            VStack(alignment: .trailing, spacing: 8) {
                                Text(isOk ? "OK para dormir" : "Demasiado tarde")
                                    .font(ImprovingFont.caption(11.5))
                                    .fontWeight(.bold)
                                    .foregroundColor(isOk ? BevelColors.greenPrimary : BevelColors.coralHigh)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(isOk ? BevelColors.greenSoftBg : BevelColors.coralSoftBg))

                                Button {
                                    AppHaptics.success()
                                    store.logQuickCaffeineDrink(title: src.displayTitle, mg: src.mg, emoji: src.emoji)
                                } label: {
                                    Image(systemName: "plus")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(BevelColors.textPrimary)
                                        .frame(width: 34, height: 34)
                                        .background(Circle().fill(BevelColors.cardSubtle))
                                        .overlay(Circle().strokeBorder(BevelColors.cardBorder, lineWidth: 0.7))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Registrar \(src.displayTitle)")
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)

                        if idx < sources.count - 1 {
                            Divider()
                                .background(BevelColors.divider)
                                .padding(.horizontal, 16)
                        }
                    }
                }
            }
        }
    }

    private var moreInfoCarouselSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Más información")
                .font(ImprovingFont.sectionTitle(18))
                .foregroundColor(BevelColors.textPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(guides) { guide in
                        Button {
                            activeGuide = guide
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ZStack {
                                    LinearGradient(
                                        colors: [guide.accent.opacity(0.68), BevelColors.card],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                    VStack(spacing: 4) {
                                        Text(guide.tag)
                                            .font(ImprovingFont.caption(11))
                                            .fontWeight(.semibold)
                                            .foregroundColor(.white.opacity(0.85))
                                        Text(guide.title)
                                            .font(ImprovingFont.sectionTitle(19))
                                            .foregroundColor(.white)
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal, 12)
                                    }
                                }
                                .frame(width: 224, height: 118)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))

                                Text(guide.title == "Retrasar la cafeína"
                                     ? "Retrasa tu primera toma de cafeína para tener más energía"
                                     : "Cómo afecta la cafeína a tu sueño profundo y REM")
                                    .font(ImprovingFont.cardTitle(14))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .lineLimit(2)
                                    .frame(width: 224, alignment: .leading)

                                Text(guide.subtitle)
                                    .font(ImprovingFont.caption(12))
                                    .foregroundColor(BevelColors.textSecondary)
                                    .lineLimit(2)
                                    .frame(width: 224, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var methodologyAndSourcesSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Divider().background(BevelColors.divider)

            VStack(alignment: .leading, spacing: 6) {
                Text("Cómo se elimina la cafeína")
                    .font(ImprovingFont.sectionTitle(17))
                    .foregroundColor(BevelColors.textPrimary)
                Text("La vida media de la cafeína ronda las 5,5 horas pero varía mucho (1,5–10 h) según la genética. Los «metabolizadores rápidos» con genes CYP1A2 eficientes eliminan la cafeína pronto; los «lentos» tardan más y son más sensibles. Una bebida de 200 mg tarda aproximadamente 18 h 16 min en bajar por debajo de 20 mg (con metabolismo medio).")
                    .font(ImprovingFont.body(13.5))
                    .foregroundColor(BevelColors.textSecondary)
                    .lineSpacing(3)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Variación individual")
                    .font(ImprovingFont.sectionTitle(17))
                    .foregroundColor(BevelColors.textPrimary)
                Text("Tu metabolismo personal de la cafeína puede diferir mucho. Escucha a tu cuerpo: si notas nerviosismo, ansiedad o problemas de sueño, quizá seas metabolizador lento y debas ajustar el momento o reducir la ingesta.")
                    .font(ImprovingFont.body(13.5))
                    .foregroundColor(BevelColors.textSecondary)
                    .lineSpacing(3)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Fuentes")
                    .font(ImprovingFont.sectionTitle(16.5))
                    .foregroundColor(BevelColors.textPrimary)
                Group {
                    Text("Límite adulto (~400 mg/día): orientación para consumidores de la FDA.")
                    Text("Retrasar 30–90 min tras despertar: Oura Ring; Houston Methodist.")
                    Text("Corte antes de dormir: ≥6 h (PubMed); 8+ h en personas sensibles (Sleep Foundation).")
                    Text("Vida media ~5,5 h (intervalo 1,5–10 h): revisión JISSN.")
                    Text("Variabilidad genética (metabolizadores rápidos/lentos CYP1A2): JAMA; Coffee & Health.")
                    Text("Incluir todas las fuentes de cafeína en los totales: FDA.")
                }
                .font(ImprovingFont.caption(12.5))
                .foregroundColor(BevelColors.textSecondary)
            }
        }
    }
}

// MARK: - Quick Custom Caffeine Logger Sheet

struct CaffeineQuickLoggerSheet: View {
    @ObservedObject var store: ImprovingStore
    let onClose: () -> Void

    @State private var selectedTitle: String = "Espresso (30 ml)"
    @State private var selectedMg: Double = 65
    @State private var selectedEmoji: String = "☕"
    @State private var intakeDate: Date = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    BevelCard(cornerRadius: 18) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("REGISTRAR TOMA DE CAFEÍNA")
                                .font(ImprovingFont.microLabel(10))
                                .foregroundColor(BevelColors.textMuted)

                            TextField("Bebida (ej. Café con leche, Espresso…)", text: $selectedTitle)
                                .font(ImprovingFont.cardTitle(14.5))
                                .foregroundColor(BevelColors.textPrimary)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.cardSubtle))

                            HStack {
                                Text("Cantidad: \(Int(selectedMg.rounded())) mg")
                                    .font(ImprovingFont.cardTitle(14.5))
                                    .monospacedDigit()
                                    .foregroundColor(BevelColors.periwinkleStart)
                                Spacer()
                                Text("Elimina en \(WhoopPhysiologyEngine.formatClearanceDuration(WhoopPhysiologyEngine.caffeineClearanceMinutes(totalMg: selectedMg)))")
                                    .font(ImprovingFont.caption(12))
                                    .foregroundColor(BevelColors.textSecondary)
                            }

                            Slider(value: $selectedMg, in: 15...350, step: 5)
                                .tint(BevelColors.periwinkleStart)

                            DatePicker("Hora de la toma", selection: $intakeDate, displayedComponents: .hourAndMinute)
                                .font(ImprovingFont.body(13.5))
                                .foregroundColor(BevelColors.textPrimary)
                        }
                        .padding(14)
                    }

                    Text("Atajos rápidos")
                        .font(ImprovingFont.caption(12))
                        .foregroundColor(BevelColors.textMuted)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(CaffeineBeverageSource.commonSources.prefix(8)) { src in
                            Button {
                                selectedTitle = src.displayTitle
                                selectedMg = src.mg
                                selectedEmoji = src.emoji
                                AppHaptics.selection()
                            } label: {
                                HStack(spacing: 6) {
                                    Text(src.emoji)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(src.name)
                                            .font(ImprovingFont.caption(12))
                                            .fontWeight(.semibold)
                                            .foregroundColor(BevelColors.textPrimary)
                                            .lineLimit(1)
                                        Text("\(Int(src.mg)) mg")
                                            .font(ImprovingFont.caption(11))
                                            .monospacedDigit()
                                            .foregroundColor(BevelColors.periwinkleStart)
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 12).fill(BevelColors.card))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BevelColors.cardBorder, lineWidth: 0.7))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button {
                        let f = DateFormatter()
                        f.dateFormat = "HH:mm"
                        let clean = selectedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        store.logQuickCaffeineDrink(
                            title: clean.isEmpty ? "Café" : clean,
                            mg: selectedMg,
                            emoji: selectedEmoji,
                            timeLabel: f.string(from: intakeDate)
                        )
                        AppHaptics.success()
                        onClose()
                    } label: {
                        Text("Guardar \(Int(selectedMg.rounded())) mg de cafeína")
                            .font(ImprovingFont.cardTitle(14.5))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 15).fill(BevelColors.indigoEnd))
                    }
                }
                .padding(16)
            }
            .background(BevelColors.canvas)
            .navigationTitle("Registrar cafeína")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar", action: onClose)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

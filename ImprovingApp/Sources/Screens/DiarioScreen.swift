import SwiftUI

private enum DiarioRowKind {
    case triState(id: String)
    case moodPicker
    case hydrationLink
}

private struct DiarioEntrySpec: Identifiable {
    let id: String
    let emoji: String
    let title: String
    let kind: DiarioRowKind
}

private let dayEntries: [DiarioEntrySpec] = [
    DiarioEntrySpec(id: "fish_oil", emoji: "💊", title: "Aceite de pescado", kind: .triState(id: "fish_oil")),
    DiarioEntrySpec(id: "sexual_activity", emoji: "❣️", title: "Actividad sexual", kind: .triState(id: "sexual_activity")),
    DiarioEntrySpec(id: "alcohol", emoji: "🍷", title: "Alcohol", kind: .triState(id: "alcohol")),
    DiarioEntrySpec(id: "ashwagandha", emoji: "💊", title: "Ashwagandha", kind: .triState(id: "ashwagandha")),
    DiarioEntrySpec(id: "added_sugar", emoji: "🍬", title: "Azúcar añadido", kind: .triState(id: "added_sugar")),
    DiarioEntrySpec(id: "caffeine", emoji: "☕", title: "Cafeína", kind: .triState(id: "caffeine")),
    DiarioEntrySpec(id: "creatine", emoji: "💊", title: "Creatina", kind: .triState(id: "creatine")),
    DiarioEntrySpec(id: "turmeric", emoji: "🫚", title: "Cúrcuma", kind: .triState(id: "turmeric")),
    DiarioEntrySpec(id: "low_carb", emoji: "🥖", title: "Dieta baja en carbohidratos", kind: .triState(id: "low_carb")),
    DiarioEntrySpec(id: "keto", emoji: "🥑", title: "Dieta keto", kind: .triState(id: "keto")),
    DiarioEntrySpec(id: "illness", emoji: "😷", title: "Enfermedad", kind: .triState(id: "illness")),
    DiarioEntrySpec(id: "mood", emoji: "😊", title: "Estado de ánimo diario", kind: .moodPicker),
    DiarioEntrySpec(id: "fever", emoji: "🤒", title: "Fiebre", kind: .triState(id: "fever")),
    DiarioEntrySpec(id: "physio", emoji: "🚶", title: "Fisioterapia", kind: .triState(id: "physio")),
    DiarioEntrySpec(id: "hydration", emoji: "💧", title: "Hidratación", kind: .hydrationLink),
    DiarioEntrySpec(id: "injury", emoji: "🩹", title: "Lesión", kind: .triState(id: "injury")),
    DiarioEntrySpec(id: "morning_sun", emoji: "☀️", title: "Luz del sol por la mañana", kind: .triState(id: "morning_sun")),
    DiarioEntrySpec(id: "dairy", emoji: "🥛", title: "Lácteos", kind: .triState(id: "dairy")),
    DiarioEntrySpec(id: "magnesium", emoji: "💊", title: "Magnesio", kind: .triState(id: "magnesium")),
    DiarioEntrySpec(id: "pain_meds", emoji: "℞", title: "Medicación para el dolor", kind: .triState(id: "pain_meds")),
    DiarioEntrySpec(id: "probiotic", emoji: "🦠", title: "Probiótico", kind: .triState(id: "probiotic")),
]

private let nightEntries: [DiarioEntrySpec] = [
    DiarioEntrySpec(id: "shared_bed", emoji: "🛏️", title: "Cama compartida", kind: .triState(id: "shared_bed")),
    DiarioEntrySpec(id: "late_meal", emoji: "🍽️", title: "Comer tarde", kind: .triState(id: "late_meal")),
    DiarioEntrySpec(id: "device_bed", emoji: "📱", title: "Dispositivo en la cama", kind: .triState(id: "device_bed")),
    DiarioEntrySpec(id: "sleep_interrupt", emoji: "🥱", title: "Interrupción del sueño", kind: .triState(id: "sleep_interrupt")),
    DiarioEntrySpec(id: "reading_bed", emoji: "📖", title: "Lectura en la cama", kind: .triState(id: "reading_bed")),
]

private struct AutoDiarioRow: Identifiable {
    let id: String
    let emoji: String
    let title: String
    let state: JournalCheckState
}

struct DiarioScreen: View {
    @ObservedObject var store: ImprovingStore
    let onNavigate: (OverlayRoute) -> Void

    @State private var showMoodSheet: Bool = false
    @State private var showCalendarSheet: Bool = false

    var body: some View {
        // STRICT RULE: Every manual checkbox starts UNSET (center —) unless the user actively chooses ✓ or ✕!
        let dayMap = store.journalCheckinsByDate[store.selectedDateIso] ?? [:]
        let moodOpt = store.journalMoodByDate[store.selectedDateIso]
        let moodLabels = ["Agotado", "Bajo", "Normal", "Bien", "Excelente"]
        let moodText = moodOpt.map { moodLabels[max(0, min(4, $0 - 1))] } ?? "Sin seleccionar"
        let glasses = store.hydrationGlassesByDate[store.selectedDateIso] ?? 0
        let waterMl = Double(glasses) * 250.0
        let curSummary = store.currentDaySummary

        let autoRows: [AutoDiarioRow] = [
            AutoDiarioRow(id: "a_steps", emoji: "👟", title: "10.000+ pasos", state: store.automaticHabitState(id: "a_steps", day: curSummary)),
            AutoDiarioRow(id: "a_cardio", emoji: "🏃", title: "20+ minutos de cardio", state: store.automaticHabitState(id: "a_cardio", day: curSummary)),
            AutoDiarioRow(id: "a_strength", emoji: "🏋️", title: "20+ minutos de fuerza", state: store.automaticHabitState(id: "a_strength", day: curSummary)),
            AutoDiarioRow(id: "a_daylight", emoji: "☀️", title: "20+ minutos de luz natural", state: store.automaticHabitState(id: "a_daylight", day: curSummary)),
            AutoDiarioRow(id: "a_z2", emoji: "🟠", title: "30+ minutos en la zona 2", state: store.automaticHabitState(id: "a_z2", day: curSummary)),
            AutoDiarioRow(id: "a_stress", emoji: "💢", title: "50+ puntuación del Estrés", state: store.automaticHabitState(id: "a_stress", day: curSummary)),
            AutoDiarioRow(id: "a_strain", emoji: "😮‍💨", title: "Objetivo de Esfuerzo superado", state: store.automaticHabitState(id: "a_strain", day: curSummary)),
            AutoDiarioRow(id: "a_noise", emoji: "🔊", title: "Ruido al dormir de 50+ dB", state: store.automaticHabitState(id: "a_noise", day: curSummary)),
        ]

        // Real 7-day calendar strip ending today + tomorrow preview
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let stripOffsets = [-5, -4, -3, -2, -1, 0, 1]
        let wdFmt = DateFormatter()
        wdFmt.locale = Locale(identifier: "es_ES")
        wdFmt.dateFormat = "EEE"
        let shortDayFmt = DateFormatter()
        shortDayFmt.locale = Locale(identifier: "es_ES")
        shortDayFmt.dateFormat = "d MMM"
        let prevNightDate = cal.date(byAdding: .day, value: -1, to: store.selectedDate) ?? store.selectedDate
        let nightRangeLabel = "\(shortDayFmt.string(from: prevNightDate).replacingOccurrences(of: ".", with: "")) - \(shortDayFmt.string(from: store.selectedDate).replacingOccurrences(of: ".", with: ""))"

        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button { showCalendarSheet = true } label: {
                        Image(systemName: "calendar")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(BevelColors.textPrimary)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(BevelColors.glassChromeFill))
                            .overlay(Circle().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.8))
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Button { onNavigate(.journalInsights) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 13))
                                    .foregroundColor(BevelColors.textPrimary)
                                Text("Información")
                                    .font(ImprovingFont.cardTitle(13.5))
                                    .foregroundColor(BevelColors.textPrimary)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                            .background(Capsule().fill(BevelColors.glassChromeFill))
                            .overlay(Capsule().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.8))
                        }

                        Button { onNavigate(.journalInsights) } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(BevelColors.textPrimary)
                                .frame(width: 38, height: 38)
                                .background(Circle().fill(BevelColors.glassChromeFill))
                                .overlay(Circle().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.8))
                        }
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Diario")
                            .font(ImprovingFont.displayLarge(28))
                            .foregroundColor(BevelColors.textPrimary)
                        Text(store.monthYearLabel)
                            .font(ImprovingFont.body(14))
                            .foregroundColor(BevelColors.textSecondary)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        Button { store.shiftDay(1) } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(BevelColors.textPrimary)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(BevelColors.card))
                        }
                        Button { if store.dayOffset > 0 { store.shiftDay(-1) } } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(store.dayOffset > 0 ? BevelColors.textPrimary : BevelColors.textMuted.opacity(0.35))
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(BevelColors.card.opacity(store.dayOffset > 0 ? 1 : 0.45)))
                        }
                        .disabled(store.dayOffset == 0)
                    }
                }

                // Dynamic 7-day strip with real dates & checkmarks only on days with logged entries
                HStack(spacing: 4) {
                    ForEach(stripOffsets, id: \.self) { offset in
                        let dt = cal.date(byAdding: .day, value: offset, to: todayStart) ?? todayStart
                        let pastOffset = max(0, -offset)
                        let isFuture = offset > 0
                        let isSelected = !isFuture && (pastOffset == store.dayOffset)
                        let dayNum = cal.component(.day, from: dt)
                        let dayName = wdFmt.string(from: dt).replacingOccurrences(of: ".", with: "").prefix(3)
                        let iso = store.isoFormatter.string(from: dt)
                        let hasLogged = (store.journalCheckinsByDate[iso]?.values.contains { $0 != .unset } ?? false)

                        Button {
                            if !isFuture { store.selectDayOffset(pastOffset) }
                        } label: {
                            VStack(spacing: 6) {
                                Text(String(dayName))
                                    .font(ImprovingFont.caption(11.5))
                                    .foregroundColor(BevelColors.textMuted)
                                Text("\(dayNum)")
                                    .font(ImprovingFont.cardTitle(14))
                                    .foregroundColor(isSelected ? BevelColors.textPrimary : (offset == 0 ? BevelColors.skyBlue : (isFuture ? BevelColors.textMuted : BevelColors.textPrimary)))

                                ZStack {
                                    if isFuture {
                                        Circle()
                                            .strokeBorder(BevelColors.trackGroove, lineWidth: 1.2)
                                            .frame(width: 24, height: 24)
                                    } else if hasLogged {
                                        Circle()
                                            .fill(isSelected ? BevelColors.greenPrimary : Color(hex: 0xBA923A))
                                            .frame(width: 24, height: 24)
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.white)
                                    } else {
                                        Circle()
                                            .strokeBorder(isSelected ? BevelColors.greenPrimary : BevelColors.trackGroove, lineWidth: 1.5)
                                            .frame(width: 24, height: 24)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isSelected ? BevelColors.card : .clear)
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 10)
            .background(BevelColors.sheetHeaderBg)

            Divider().background(BevelColors.divider)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(store.dayOffset == 0 ? "Entradas de hoy" : "Entradas · \(store.dateLabel)")
                        .font(ImprovingFont.sectionTitle(18))
                        .foregroundColor(BevelColors.textPrimary)
                        .padding(.top, 12)

                    Text("Las casillas en el centro (—) no se tienen en cuenta. Marca ✓ en verde o ✕ en rojo para analizar su impacto en tu sueño y recuperación.")
                        .font(ImprovingFont.caption(12))
                        .foregroundColor(BevelColors.textSecondary)

                    Text("Día")
                        .font(ImprovingFont.body(14))
                        .foregroundColor(BevelColors.textSecondary)
                        .padding(.top, 2)

                    ForEach(dayEntries) { entry in
                        switch entry.kind {
                        case .triState(let hid):
                            triStateRow(emoji: entry.emoji, title: entry.title, state: dayMap[hid] ?? .unset) { next in
                                store.setJournalCheck(habitId: hid, state: next)
                            }
                        case .hydrationLink:
                            Button {
                                store.selectedNutrientKey = "Hidratación"
                                onNavigate(.nutrientDetail)
                            } label: {
                                BevelCard(cornerRadius: 16) {
                                    HStack(spacing: 10) {
                                        Text(entry.emoji).font(.system(size: 18))
                                        Text(entry.title)
                                            .font(ImprovingFont.cardTitle(14.5))
                                            .foregroundColor(BevelColors.textPrimary)
                                        Spacer()
                                        Text(glasses > 0 ? String(format: "%.0f ml", waterMl) : "Sin registrar")
                                            .font(ImprovingFont.cardTitle(13.5))
                                            .monospacedDigit()
                                            .foregroundColor(glasses >= 8 ? BevelColors.greenPrimary : BevelColors.textSecondary)
                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(BevelColors.textSecondary)
                                            .frame(width: 34, height: 34)
                                            .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.cardSubtle))
                                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                }
                            }
                        case .moodPicker:
                            Button { showMoodSheet = true } label: {
                                BevelCard(cornerRadius: 16) {
                                    HStack(spacing: 12) {
                                        Text(entry.emoji).font(.system(size: 18))
                                        Text(entry.title)
                                            .font(ImprovingFont.cardTitle(14.5))
                                            .foregroundColor(BevelColors.textPrimary)
                                        Spacer()
                                        Text(moodText)
                                            .font(ImprovingFont.body(13.5))
                                            .foregroundColor(moodOpt != nil ? BevelColors.textPrimary : BevelColors.textMuted)
                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(BevelColors.textSecondary)
                                            .frame(width: 34, height: 34)
                                            .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.cardSubtle))
                                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                }
                            }
                        }
                    }

                    // Noche Section (ALL start .unset!)
                    HStack {
                        Text("Noche")
                            .font(ImprovingFont.body(14))
                            .foregroundColor(BevelColors.textSecondary)
                        Spacer()
                        Text(nightRangeLabel)
                            .font(ImprovingFont.caption(13))
                            .foregroundColor(BevelColors.textMuted)
                    }
                    .padding(.top, 12)

                    ForEach(nightEntries) { entry in
                        if case .triState(let hid) = entry.kind {
                            triStateRow(emoji: entry.emoji, title: entry.title, state: dayMap[hid] ?? .unset) { next in
                                store.setJournalCheck(habitId: hid, state: next)
                            }
                        }
                    }

                    // Automático Section (strictly grounded in real collected data)
                    Text("Automático")
                        .font(ImprovingFont.body(14))
                        .foregroundColor(BevelColors.textSecondary)
                        .padding(.top, 12)

                    ForEach(autoRows) { row in
                        BevelCard(cornerRadius: 16) {
                            HStack(spacing: 12) {
                                Text(row.emoji).font(.system(size: 18))
                                Text(row.title)
                                    .font(ImprovingFont.cardTitle(14.5))
                                    .foregroundColor(BevelColors.textPrimary)
                                Spacer()
                                if row.state == .unset {
                                    Image(systemName: "minus.circle")
                                        .font(.system(size: 20))
                                        .foregroundColor(BevelColors.textMuted)
                                } else {
                                    HStack(spacing: 6) {
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 14))
                                            .foregroundColor(row.state == .yes ? BevelColors.greenPrimary : BevelColors.coralHigh)
                                        Image(systemName: row.state == .yes ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .font(.system(size: 22))
                                            .foregroundColor(row.state == .yes ? BevelColors.greenPrimary : BevelColors.coralHigh)
                                    }
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 155)
            }
            .background(BevelColors.canvas)
        }
        .background(BevelColors.canvas)
        .sheet(isPresented: $showCalendarSheet) {
            DatePickerSheetView(
                selectedDate: Binding(
                    get: { store.selectedDate },
                    set: { d in store.selectDate(d); showCalendarSheet = false }
                ),
                onJumpToday: { store.selectDayOffset(0); showCalendarSheet = false },
                onClose: { showCalendarSheet = false }
            )
        }
        .sheet(isPresented: $showMoodSheet) {
            VStack(spacing: 16) {
                Capsule().fill(BevelColors.trackGroove).frame(width: 40, height: 4).padding(.top, 10)
                Text("Estado de ánimo diario")
                    .font(ImprovingFont.sectionTitle(18))
                    .foregroundColor(BevelColors.textPrimary)
                HStack(spacing: 10) {
                    let emojis = ["😫", "😕", "😐", "🙂", "🤩"]
                    ForEach(1...5, id: \.self) { m in
                        Button {
                            store.setJournalMood(m)
                            showMoodSheet = false
                        } label: {
                            VStack(spacing: 6) {
                                Text(emojis[m - 1]).font(.system(size: 28))
                                Text(moodLabels[m - 1]).font(ImprovingFont.caption(11)).foregroundColor(BevelColors.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 14).fill(moodOpt == m ? BevelColors.greenSoftBg : BevelColors.card))
                        }
                    }
                }
            }
            .padding(20)
            .background(BevelColors.sheetHeaderBg.ignoresSafeArea())
            .presentationDetents([.height(220)])
        }
    }

    private func triStateRow(emoji: String, title: String, state: JournalCheckState, onSelect: @escaping (JournalCheckState) -> Void) -> some View {
        BevelCard(cornerRadius: 16) {
            HStack(spacing: 10) {
                Text(emoji).font(.system(size: 18))
                Text(title)
                    .font(ImprovingFont.cardTitle(14.5))
                    .foregroundColor(BevelColors.textPrimary)
                    .lineLimit(1)
                Spacer()
                HStack(spacing: 2) {
                    triBtn(icon: "xmark", active: state == .no, activeFill: Color(hex: 0x7A3229), activeBorder: BevelColors.coralHigh) {
                        UISelectionFeedbackGenerator().selectionChanged()
                        onSelect(state == .no ? .unset : .no)
                    }
                    triBtn(icon: "minus", active: state == .unset, activeFill: BevelColors.floatingDarkButton, activeBorder: Color.white.opacity(0.22)) {
                        UISelectionFeedbackGenerator().selectionChanged()
                        onSelect(.unset)
                    }
                    triBtn(icon: "checkmark", active: state == .yes, activeFill: Color(hex: 0x1E6B45), activeBorder: BevelColors.greenPrimary) {
                        UISelectionFeedbackGenerator().selectionChanged()
                        onSelect(state == .yes ? .unset : .yes)
                    }
                }
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 11).fill(BevelColors.cardSubtle))
                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
    }

    private func triBtn(icon: String, active: Bool, activeFill: Color, activeBorder: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(active ? .white : BevelColors.textMuted.opacity(0.6))
                .frame(width: 34, height: 32)
                .background(RoundedRectangle(cornerRadius: 9).fill(active ? activeFill : .clear))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(active ? activeBorder : .clear, lineWidth: 1.2))
        }
    }
}

// MARK: - Diario ✨ Información Screen (Literal Match to Screenshots 1 & 2: Puntuación del Sueño & Recuperación)

struct JournalInsightsScreen: View {
    @ObservedObject var store: ImprovingStore
    let onBack: () -> Void

    @State private var target: JournalImpactTarget = .sleep

    var body: some View {
        let allItems = store.computeJournalImpacts(for: target)
        let highItems = allItems.filter { $0.reliability == .high }
        let lowItems = allItems.filter { $0.reliability == .low }
        let lockedItems = allItems.filter { $0.reliability == .locked }

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Atmospheric Header (Starry Night for Sueño, Misty Dusk Hills for Recuperación)
                ZStack(alignment: .topLeading) {
                    if target == .sleep {
                        LinearGradient(
                            colors: [Color(hex: 0x26386B), Color(hex: 0x1A2241), BevelColors.canvas],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        // Subtle starry night sky + crescent moon (Screenshot 1)
                        Canvas { ctx, sz in
                            let stars: [(CGFloat, CGFloat, CGFloat)] = [
                                (0.12, 0.16, 1.5), (0.28, 0.24, 1.2), (0.45, 0.14, 1.8),
                                (0.62, 0.20, 1.4), (0.82, 0.18, 1.6), (0.91, 0.30, 1.2),
                                (0.18, 0.36, 1.2), (0.54, 0.34, 1.5), (0.76, 0.40, 1.3)
                            ]
                            for (fx, fy, r) in stars {
                                ctx.fill(Path(ellipseIn: CGRect(x: sz.width * fx, y: sz.height * fy, width: r * 2, height: r * 2)), with: .color(Color.white.opacity(0.45)))
                            }
                        }
                        HStack {
                            Spacer()
                            Image(systemName: "moon.fill")
                                .font(.system(size: 32))
                                .foregroundColor(Color.white.opacity(0.82))
                                .shadow(color: Color.white.opacity(0.45), radius: 10)
                                .padding(.top, 52)
                                .padding(.trailing, 76)
                        }
                    } else {
                        // Misty dusk hills atmosphere (Screenshot 2)
                        LinearGradient(
                            colors: [Color(hex: 0x676B78), Color(hex: 0x3D4150), BevelColors.canvas],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Button(action: onBack) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(Color.black.opacity(0.32)))
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8))
                        }
                        .padding(.top, 8)

                        Spacer(minLength: 26)

                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white.opacity(0.92))
                            Text("Información")
                                .font(ImprovingFont.cardTitle(16))
                                .foregroundColor(.white.opacity(0.92))
                        }

                        Text(target == .sleep ? "Puntuación del Sueño" : "Puntuación de Recuperación")
                            .font(ImprovingFont.displayLarge(27))
                            .foregroundColor(.white)

                        Text(target == .sleep
                             ? "Aquí se analiza cómo tus comportamientos y hábitos diarios afectan el sueño."
                             : "Aquí se analiza cómo tus comportamientos y hábitos diarios afectan la recuperación.")
                            .font(ImprovingFont.body(14))
                            .foregroundColor(.white.opacity(0.84))
                            .fixedSize(horizontal: false, vertical: true)

                        // Dual Pill Selector: [ Recuperación ] [ Sueño ]
                        HStack(spacing: 10) {
                            ForEach(JournalImpactTarget.allCases) { tab in
                                let active = target == tab
                                Button {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        target = tab
                                    }
                                } label: {
                                    Text(tab.rawValue)
                                        .font(ImprovingFont.cardTitle(14.5))
                                        .foregroundColor(active ? .white : BevelColors.textSecondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Capsule().fill(active ? Color(hex: 0x6A6E7A) : Color(hex: 0x2F323B).opacity(0.85)))
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 18)
                }

                VStack(alignment: .leading, spacing: 14) {
                    // 1. High Reliability Section (when ≥5 ✓ and ≥5 ✕ in last 90 days)
                    if !highItems.isEmpty {
                        impactAxisHeader
                        ForEach(highItems) { item in
                            impactBarCard(item: item, isHighReliability: true)
                        }
                    }

                    // 2. Fiabilidad baja Section (when ≥1 ✓ and ≥1 ✕, but < 5 on either side)
                    if !lowItems.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Fiabilidad baja")
                                .font(ImprovingFont.sectionTitle(18))
                                .foregroundColor(BevelColors.textPrimary)
                            Text("Sigue registrando datos para mejorar la puntuación de fiabilidad.")
                                .font(ImprovingFont.body(13.5))
                                .foregroundColor(BevelColors.textSecondary)
                        }
                        .padding(.top, highItems.isEmpty ? 6 : 16)

                        impactAxisHeader
                        ForEach(lowItems) { item in
                            impactBarCard(item: item, isHighReliability: false)
                        }
                    }

                    // 3. Etiquetas bloqueadas Section
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Etiquetas bloqueadas")
                            .font(ImprovingFont.sectionTitle(18))
                            .foregroundColor(BevelColors.textPrimary)
                        Text("Registra al menos 5 positivos y 5 negativos para los últimos 90 días para desbloquear el análisis de fiabilidad alta.")
                            .font(ImprovingFont.body(13.5))
                            .foregroundColor(BevelColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 16)

                    if lockedItems.isEmpty {
                        BevelCard(cornerRadius: 16) {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.seal.fill").foregroundColor(BevelColors.greenPrimary)
                                Text("Todas tus etiquetas ya cuentan con suficiente historial para calcular su impacto.")
                                    .font(ImprovingFont.caption(13))
                                    .foregroundColor(BevelColors.textSecondary)
                            }
                            .padding(14)
                        }
                    } else {
                        ForEach(lockedItems) { item in
                            BevelCard(cornerRadius: 16) {
                                HStack(spacing: 12) {
                                    Text(item.emoji).font(.system(size: 18))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(ImprovingFont.cardTitle(14))
                                            .foregroundColor(BevelColors.textPrimary)
                                            .lineLimit(1)
                                        Text("✓ \(item.yesCount)/5 positivos  ·  ✕ \(item.noCount)/5 negativos")
                                            .font(ImprovingFont.caption(11.5))
                                            .foregroundColor(BevelColors.textMuted)
                                    }
                                    Spacer()
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 13))
                                        .foregroundColor(BevelColors.textMuted)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 150)
            }
        }
        .background(BevelColors.canvas)
    }

    private var impactAxisHeader: some View {
        HStack {
            Text("Negativo")
                .font(ImprovingFont.caption(12))
                .fontWeight(.semibold)
                .foregroundColor(Color(hex: 0xE67E5A))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x3F261F)))
            Spacer()
            Text("Impacto %")
                .font(ImprovingFont.caption(12.5))
                .foregroundColor(BevelColors.textSecondary)
            Spacer()
            Text("Positivo")
                .font(ImprovingFont.caption(12))
                .fontWeight(.semibold)
                .foregroundColor(Color(hex: 0x6EA4FF))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x1F2D46)))
        }
        .padding(.vertical, 4)
    }

    private func impactBarCard(item: JournalHabitImpactItem, isHighReliability: Bool) -> some View {
        let pct = item.impactPct
        let isPositive = pct > 0
        let signText = pct > 0 ? "+\(pct)%" : (pct == 0 ? "-0%" : "\(pct)%")
        let barColor: Color = {
            if !isHighReliability { return Color(hex: 0x6B7080) }
            return isPositive ? Color(hex: 0x6095FF) : Color(hex: 0xE67E5A)
        }()
        let textColor: Color = {
            if !isHighReliability { return BevelColors.textMuted }
            return isPositive ? Color(hex: 0x6095FF) : Color(hex: 0xE67E5A)
        }()
        // Scale: ±15% fills full half-bar
        let frac = min(max(Double(abs(pct)) / 15.0, pct == 0 ? 0.0 : 0.08), 1.0)

        return BevelCard(cornerRadius: 18) {
            VStack(spacing: 11) {
                HStack(spacing: 10) {
                    Text(item.emoji).font(.system(size: 18))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .font(ImprovingFont.cardTitle(14.5))
                            .foregroundColor(BevelColors.textPrimary)
                            .lineLimit(1)
                        Text("✓ \(item.yesCount) días · ✕ \(item.noCount) días")
                            .font(ImprovingFont.caption(11))
                            .foregroundColor(BevelColors.textMuted)
                    }
                    Spacer()
                    Text(signText)
                        .font(ImprovingFont.metricTile(18))
                        .monospacedDigit()
                        .foregroundColor(textColor)
                }

                // Centered Bidirectional Impact Bar (Literal match to Screenshots 1 & 2!)
                GeometryReader { geo in
                    let midX = geo.size.width / 2
                    let halfW = max(midX - 12, 10)
                    let fillW = halfW * CGFloat(frac)

                    ZStack {
                        // Left track
                        Capsule()
                            .fill(Color.white.opacity(0.06))
                            .frame(width: halfW, height: 6)
                            .position(x: midX - 10 - halfW / 2, y: geo.size.height / 2)

                        // Right track
                        Capsule()
                            .fill(Color.white.opacity(0.06))
                            .frame(width: halfW, height: 6)
                            .position(x: midX + 10 + halfW / 2, y: geo.size.height / 2)

                        // Filled half-bar
                        if fillW > 2 {
                            if isPositive {
                                Capsule()
                                    .fill(barColor)
                                    .frame(width: fillW, height: 6)
                                    .position(x: midX + 10 + fillW / 2, y: geo.size.height / 2)
                            } else {
                                Capsule()
                                    .fill(barColor)
                                    .frame(width: fillW, height: 6)
                                    .position(x: midX - 10 - fillW / 2, y: geo.size.height / 2)
                            }
                        }

                        // Glowing center dot
                        Circle()
                            .fill(barColor.opacity(0.24))
                            .frame(width: 18, height: 18)
                            .position(x: midX, y: geo.size.height / 2)
                        Circle()
                            .fill(barColor)
                            .frame(width: 9, height: 9)
                            .position(x: midX, y: geo.size.height / 2)
                    }
                }
                .frame(height: 18)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
        }
    }
}

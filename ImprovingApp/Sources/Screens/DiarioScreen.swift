import SwiftUI

private enum DiarioRowKind {
    case triState(id: String)
    case nutritionLinked(key: String, valueText: String, isMet: Bool)
    case moodPicker
    case sugarPopup
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
    DiarioEntrySpec(id: "alcohol", emoji: "🍷", title: "Alcohol", kind: .nutritionLinked(key: "Alcohol", valueText: "0,0 bebidas", isMet: true)),
    DiarioEntrySpec(id: "ashwagandha", emoji: "💊", title: "Ashwagandha", kind: .triState(id: "ashwagandha")),
    DiarioEntrySpec(id: "added_sugar", emoji: "🍬", title: "Azúcar añadido", kind: .sugarPopup),
    DiarioEntrySpec(id: "caffeine", emoji: "☕", title: "Cafeína", kind: .nutritionLinked(key: "Cafeína", valueText: "3,1 mg", isMet: false)),
    DiarioEntrySpec(id: "calcium", emoji: "💊", title: "Calcio", kind: .nutritionLinked(key: "Calcio", valueText: "513,0 mg", isMet: true)),
    DiarioEntrySpec(id: "creatine", emoji: "💊", title: "Creatina", kind: .triState(id: "creatine")),
    DiarioEntrySpec(id: "turmeric", emoji: "🫚", title: "Cúrcuma", kind: .triState(id: "turmeric")),
    DiarioEntrySpec(id: "low_carb", emoji: "🥖", title: "Dieta baja en carbohidratos", kind: .triState(id: "low_carb")),
    DiarioEntrySpec(id: "keto", emoji: "🥑", title: "Dieta keto", kind: .triState(id: "keto")),
    DiarioEntrySpec(id: "illness", emoji: "😷", title: "Enfermedad", kind: .triState(id: "illness")),
    DiarioEntrySpec(id: "mood", emoji: "😊", title: "Estado de ánimo diario", kind: .moodPicker),
    DiarioEntrySpec(id: "fever", emoji: "🤒", title: "Fiebre", kind: .triState(id: "fever")),
    DiarioEntrySpec(id: "physio", emoji: "🚶", title: "Fisioterapia", kind: .triState(id: "physio")),
    DiarioEntrySpec(id: "hydration", emoji: "💧", title: "Hidratación", kind: .nutritionLinked(key: "Hidratación", valueText: "2083,8 ml", isMet: true)),
    DiarioEntrySpec(id: "injury", emoji: "🩹", title: "Lesión", kind: .triState(id: "injury")),
    DiarioEntrySpec(id: "morning_sun", emoji: "☀️", title: "Luz del sol por la mañana", kind: .triState(id: "morning_sun")),
    DiarioEntrySpec(id: "dairy", emoji: "🥛", title: "Lácteos", kind: .triState(id: "dairy")),
    DiarioEntrySpec(id: "magnesium", emoji: "💊", title: "Magnesio", kind: .nutritionLinked(key: "Magnesio", valueText: "265,7 mg", isMet: true)),
    DiarioEntrySpec(id: "pain_meds", emoji: "℞", title: "Medicación para el dolor", kind: .triState(id: "pain_meds")),
    DiarioEntrySpec(id: "probiotic", emoji: "🦠", title: "Probiótico", kind: .triState(id: "probiotic")),
    DiarioEntrySpec(id: "vit_a", emoji: "🥕", title: "Vitamina A", kind: .nutritionLinked(key: "Vitamina A", valueText: "405,3 μg", isMet: true)),
    DiarioEntrySpec(id: "vit_b12", emoji: "🅱️", title: "Vitamina B-12", kind: .nutritionLinked(key: "Vitamina B-12", valueText: "4,8 μg", isMet: true)),
    DiarioEntrySpec(id: "vit_b6", emoji: "🍗", title: "Vitamina B6", kind: .nutritionLinked(key: "Vitamina B6", valueText: "2,4 mg", isMet: true)),
    DiarioEntrySpec(id: "vit_c", emoji: "🍊", title: "Vitamina C", kind: .nutritionLinked(key: "Vitamina C", valueText: "62,3 mg", isMet: true)),
    DiarioEntrySpec(id: "vit_d", emoji: "☀️", title: "Vitamina D", kind: .nutritionLinked(key: "Vitamina D", valueText: "4,7 μg", isMet: true)),
    DiarioEntrySpec(id: "vit_e", emoji: "🌻", title: "Vitamina E", kind: .nutritionLinked(key: "Vitamina E", valueText: "7,4 mg", isMet: true)),
    DiarioEntrySpec(id: "vit_k", emoji: "🥦", title: "Vitamina K", kind: .nutritionLinked(key: "Vitamina K", valueText: "48,7 μg", isMet: true)),
    DiarioEntrySpec(id: "zinc", emoji: "💊", title: "Zinc", kind: .nutritionLinked(key: "Zinc", valueText: "4,8 mg", isMet: true)),
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

    @State private var showInsightsSheet: Bool = false
    @State private var showSugarSheet: Bool = false
    @State private var showMoodSheet: Bool = false

    private let dayNames = ["lun", "mar", "mié", "jue", "vie", "sáb", "dom"]
    private let dayOffsets = [-5, -4, -3, -2, -1, 0, 1]

    var body: some View {
        let dayMap = store.journalCheckinsByDate[store.selectedDateIso] ?? defaultMap
        let mood = store.journalMoodByDate[store.selectedDateIso] ?? 3
        let moodLabels = ["Agotado", "Bajo", "Normal", "Bien", "Excelente"]
        let moodText = moodLabels[max(0, min(4, mood - 1))]
        let glasses = store.hydrationGlassesByDate[store.selectedDateIso] ?? 8
        let waterMl = Double(glasses) * 250.0 + 83.8

        let autoRows: [AutoDiarioRow] = [
            AutoDiarioRow(id: "a_steps", emoji: "👟", title: "10.000+ pasos", state: store.stepsCount >= 10000 ? .yes : .no),
            AutoDiarioRow(id: "a_cardio", emoji: "🏃", title: "20+ minutos de cardio", state: (store.workoutsToday.first?.durationMin ?? 0) >= 20 ? .yes : .no),
            AutoDiarioRow(id: "a_strength", emoji: "🏋️", title: "20+ minutos de fuerza", state: (store.currentDaySummary?.strengthMinutes ?? 0) >= 20 ? .yes : .no),
            AutoDiarioRow(id: "a_daylight", emoji: "☀️", title: "20+ minutos de luz natural", state: .unset),
            AutoDiarioRow(id: "a_z2", emoji: "🟠", title: "30+ minutos en la zona 2", state: (store.currentDaySummary?.hrZoneMinutes[safe: 1] ?? 0) >= 30 ? .yes : .no),
            AutoDiarioRow(id: "a_stress", emoji: "💢", title: "50+ puntuación del Estrés", state: store.stressScore >= 50 ? .yes : .no),
            AutoDiarioRow(id: "a_nutri", emoji: "🍎", title: "67+ puntuación de nutrición", state: store.foodQualityScore >= 67 ? .yes : .no),
            AutoDiarioRow(id: "a_msun", emoji: "☀️", title: "Luz del sol por la mañana (automático)", state: .no),
            AutoDiarioRow(id: "a_strain", emoji: "😮‍💨", title: "Objetivo de Esfuerzo superado", state: store.strainPercent > 84 ? .yes : .no),
            AutoDiarioRow(id: "a_noise", emoji: "🔊", title: "Ruido al dormir de 50+ dB", state: .no),
            AutoDiarioRow(id: "a_mind", emoji: "🧘", title: "Sesión de «mindfulness»", state: .no),
            AutoDiarioRow(id: "a_nap", emoji: "😴", title: "Siestas", state: .no),
        ]

        VStack(spacing: 0) {
            // Sticky Header Matching Screenshots 34–40
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Button { showInsightsSheet = true } label: {
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

                        Button { showInsightsSheet = true } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(BevelColors.textPrimary)
                                .frame(width: 38, height: 38)
                                .background(Circle().fill(BevelColors.glassChromeFill))
                                .overlay(Circle().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.8))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Diario")
                        .font(ImprovingFont.displayLarge(28))
                        .foregroundColor(BevelColors.textPrimary)
                    Text("nov 2026")
                        .font(ImprovingFont.body(14))
                        .foregroundColor(BevelColors.textSecondary)
                }

                // 7-day strip with gold & emerald checkmarks (Screenshots 34–40)
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { idx in
                        let offset = dayOffsets[idx]
                        let pastOffset = max(0, -offset)
                        let isFuture = offset > 0
                        let isSelected = !isFuture && (pastOffset == store.dayOffset)
                        let dayNum = 21 + offset

                        Button {
                            if !isFuture { store.selectDayOffset(pastOffset) }
                        } label: {
                            VStack(spacing: 6) {
                                Text(dayNames[idx])
                                    .font(ImprovingFont.caption(11.5))
                                    .foregroundColor(BevelColors.textMuted)
                                Text("\(dayNum)")
                                    .font(ImprovingFont.cardTitle(14))
                                    .foregroundColor(isSelected ? BevelColors.textPrimary : (idx == 5 ? BevelColors.skyBlue : (isFuture ? BevelColors.textMuted : BevelColors.textPrimary)))

                                ZStack {
                                    if isFuture {
                                        Circle()
                                            .strokeBorder(BevelColors.trackGroove, lineWidth: 1.2)
                                            .frame(width: 24, height: 24)
                                    } else {
                                        Circle()
                                            .fill(isSelected ? BevelColors.greenPrimary : Color(hex: 0xBA923A))
                                            .frame(width: 24, height: 24)
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.white)
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
                    Text(store.dayOffset == 0 ? "Entradas de hoy" : "Entradas de ayer")
                        .font(ImprovingFont.sectionTitle(18))
                        .foregroundColor(BevelColors.textPrimary)
                        .padding(.top, 12)

                    Text("Día")
                        .font(ImprovingFont.body(14))
                        .foregroundColor(BevelColors.textSecondary)
                        .padding(.top, 2)

                    ForEach(dayEntries) { entry in
                        switch entry.kind {
                        case .triState(let hid):
                            triStateRow(emoji: entry.emoji, title: entry.title, state: dayMap[hid] ?? .no) { next in
                                store.setJournalCheck(habitId: hid, state: next)
                            }
                        case .sugarPopup:
                            Button { showSugarSheet = true } label: {
                                triStateRow(emoji: entry.emoji, title: entry.title, state: dayMap["added_sugar"] ?? .no) { next in
                                    store.setJournalCheck(habitId: "added_sugar", state: next)
                                }
                            }
                        case .nutritionLinked(let key, let defaultVal, let isMet):
                            let valStr = key == "Hidratación"
                                ? String(format: "%.1f ml", locale: Locale(identifier: "es_ES"), waterMl)
                                : defaultVal
                            nutritionLinkedRow(emoji: entry.emoji, title: entry.title, valueText: valStr, isMet: isMet) {
                                store.selectedNutrientKey = key
                                onNavigate(.nutrientDetail)
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
                                            .font(ImprovingFont.body(14))
                                            .foregroundColor(BevelColors.textSecondary)
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

                    // Noche Section (Screenshot 38)
                    HStack {
                        Text("Noche")
                            .font(ImprovingFont.body(14))
                            .foregroundColor(BevelColors.textSecondary)
                        Spacer()
                        Text("19 nov - 20 nov")
                            .font(ImprovingFont.caption(13))
                            .foregroundColor(BevelColors.textMuted)
                    }
                    .padding(.top, 12)

                    ForEach(nightEntries) { entry in
                        if case .triState(let hid) = entry.kind {
                            triStateRow(emoji: entry.emoji, title: entry.title, state: dayMap[hid] ?? (hid == "device_bed" ? .yes : .no)) { next in
                                store.setJournalCheck(habitId: hid, state: next)
                            }
                        }
                    }

                    // Automático Section (Screenshots 39–40)
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
        // Screenshot 42: Azúcar añadido bottom sheet popup
        .sheet(isPresented: $showSugarSheet) {
            VStack(spacing: 16) {
                Capsule().fill(BevelColors.trackGroove).frame(width: 40, height: 4).padding(.top, 10)
                Text("Azúcar añadido")
                    .font(ImprovingFont.sectionTitle(18))
                    .foregroundColor(BevelColors.textPrimary)
                Text("Estos alimentos con azúcares añadidos se detectan automáticamente basándose en tu registro de nutrición de hoy.")
                    .font(ImprovingFont.body(13.5))
                    .foregroundColor(BevelColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)

                VStack(spacing: 10) {
                    sugarFoodCard(emoji: "🥛", name: "Leche con chocolate", detail: "Incluye 9g de Azúcares añadidos")
                    sugarFoodCard(emoji: "🍪", name: "Galletas de avena con chispas de chocolate", detail: "Incluye 11,9g de Azúcares añadidos")
                }

                Button {
                    store.setJournalCheck(habitId: "added_sugar", state: .no)
                    showSugarSheet = false
                } label: {
                    Text("Anulación manual")
                        .font(ImprovingFont.cardTitle(15))
                        .foregroundColor(BevelColors.coralHigh)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(BevelColors.coralSoftBg))
                }

                Button("Cancelar") { showSugarSheet = false }
                    .font(ImprovingFont.cardTitle(15))
                    .foregroundColor(BevelColors.textPrimary)
                    .padding(.bottom, 12)
            }
            .padding(.horizontal, 20)
            .background(BevelColors.sheetHeaderBg.ignoresSafeArea())
            .presentationDetents([.medium])
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
                            .background(RoundedRectangle(cornerRadius: 14).fill(mood == m ? BevelColors.greenSoftBg : BevelColors.card))
                        }
                    }
                }
            }
            .padding(20)
            .background(BevelColors.sheetHeaderBg.ignoresSafeArea())
            .presentationDetents([.height(220)])
        }
        .sheet(isPresented: $showInsightsSheet) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Impacto estadístico sobre tu Recuperación (90 días)")
                            .font(ImprovingFont.caption(13))
                            .foregroundColor(BevelColors.textSecondary)
                        ForEach([
                            ("💧", "Hidratación (2+ L)", "+5,4% Recuperación"),
                            ("💊", "Magnesio nocturno", "+6,1% Sueño profundo"),
                            ("☀️", "Luz del sol matutina", "+4,2% VFC"),
                            ("📱", "Dispositivo en la cama", "-4,8% Eficiencia sueño"),
                            ("🍷", "Alcohol (0 bebidas)", "+7,3% Recuperación"),
                        ], id: \.1) { emoji, label, impact in
                            BevelCard(cornerRadius: 16) {
                                HStack {
                                    Text(emoji)
                                    Text(label).font(ImprovingFont.cardTitle(14)).foregroundColor(BevelColors.textPrimary)
                                    Spacer()
                                    Text(impact).font(ImprovingFont.caption(12.5)).fontWeight(.semibold).foregroundColor(impact.hasPrefix("+") ? BevelColors.greenPrimary : BevelColors.coralHigh)
                                }
                                .padding(14)
                            }
                        }
                    }
                    .padding(16)
                }
                .background(BevelColors.canvas)
                .navigationTitle("Información del Diario")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private var defaultMap: [String: JournalCheckState] {
        ["dairy": .yes, "device_bed": .yes]
    }

    private func sugarFoodCard(emoji: String, name: String, detail: String) -> some View {
        BevelCard(cornerRadius: 16, backgroundColor: BevelColors.card) {
            HStack(spacing: 12) {
                Text(emoji)
                    .font(.system(size: 20))
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.cardSubtle))
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(ImprovingFont.cardTitle(14)).foregroundColor(BevelColors.textPrimary)
                    Text(detail).font(ImprovingFont.caption(12)).foregroundColor(BevelColors.textSecondary)
                }
                Spacer()
            }
            .padding(12)
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
                    triBtn(icon: "xmark", active: state == .no, activeFill: Color(hex: 0x7A4232), activeBorder: BevelColors.coralHigh) { onSelect(.no) }
                    triBtn(icon: "minus", active: state == .unset, activeFill: BevelColors.floatingDarkButton, activeBorder: Color.white.opacity(0.2)) { onSelect(.unset) }
                    triBtn(icon: "checkmark", active: state == .yes, activeFill: Color(hex: 0x355C9E), activeBorder: BevelColors.skyBlue) { onSelect(.yes) }
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(active ? .white : BevelColors.textMuted.opacity(0.6))
                .frame(width: 34, height: 32)
                .background(RoundedRectangle(cornerRadius: 9).fill(active ? activeFill : .clear))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(active ? activeBorder : .clear, lineWidth: 1.2))
        }
    }

    private func nutritionLinkedRow(emoji: String, title: String, valueText: String, isMet: Bool, onClick: @escaping () -> Void) -> some View {
        Button(action: onClick) {
            BevelCard(cornerRadius: 16) {
                HStack(spacing: 10) {
                    Text(emoji).font(.system(size: 18))
                    Text(title)
                        .font(ImprovingFont.cardTitle(14.5))
                        .foregroundColor(BevelColors.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(valueText)
                        .font(ImprovingFont.cardTitle(14))
                        .monospacedDigit()
                        .foregroundColor(isMet ? BevelColors.greenPrimary : BevelColors.coralHigh)
                    Image(systemName: isMet ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 19))
                        .foregroundColor(isMet ? BevelColors.greenPrimary : BevelColors.coralHigh)
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
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

import SwiftUI

private struct HabitMeta: Identifiable {
    let id: String
    let icon: String
    let label: String
    let impactHint: String
    let isDay: Bool
}

private let allJournalHabits: [HabitMeta] = [
    HabitMeta(id: "caffeine", icon: "☕", label: "Cafeína", impactHint: "1–2 tazas antes de 14h · +1,5% Rec.", isDay: true),
    HabitMeta(id: "hydration", icon: "💧", label: "Hidratación (2.5L)", impactHint: "+5,4% Recuperación", isDay: true),
    HabitMeta(id: "sunlight", icon: "☀️", label: "Luz solar matutina", impactHint: "+4,2% Sueño profundo", isDay: true),
    HabitMeta(id: "creatine", icon: "⚡", label: "Creatina (5g)", impactHint: "+2,1% Fuerza muscular", isDay: true),
    HabitMeta(id: "omega3", icon: "🐟", label: "Omega-3 EPA/DHA", impactHint: "-1,4 bpm FC reposo", isDay: true),
    HabitMeta(id: "vitd", icon: "🌞", label: "Vitamina D3 + K2", impactHint: "+3,0% Inmunidad / VFC", isDay: true),
    HabitMeta(id: "sauna", icon: "🧖", label: "Sauna / Exposición calor", impactHint: "+6,5% VFC nocturna", isDay: true),
    HabitMeta(id: "cold_plunge", icon: "🧊", label: "Baño frío / Crioterapia", impactHint: "-14% Dolor muscular", isDay: true),
    HabitMeta(id: "zone2", icon: "🏃", label: "Zona 2 Aeróbica", impactHint: "+2,8% Capacidad mitocondrial", isDay: true),
    HabitMeta(id: "strength", icon: "🏋️", label: "Fuerza / Hipertrofia", impactHint: "+4,1% Tonificación", isDay: true),
    HabitMeta(id: "stretching", icon: "🧘", label: "Estiramientos / Movilidad", impactHint: "-18% Rigidez articular", isDay: true),
    HabitMeta(id: "deep_work", icon: "💻", label: "Trabajo profundo (>4h)", impactHint: "+8 pts Estrés cognitivo", isDay: true),

    HabitMeta(id: "magnesium", icon: "💊", label: "Magnesio Bisglicinato", impactHint: "+6,1% Recuperación", isDay: false),
    HabitMeta(id: "reading", icon: "📖", label: "Lectura antes de dormir", impactHint: "+3,8% Eficiencia sueño", isDay: false),
    HabitMeta(id: "meditation", icon: "🫁", label: "Meditación / Respiración", impactHint: "-11% Estrés nocturno", isDay: false),
    HabitMeta(id: "alcohol", icon: "🍷", label: "Alcohol (0 bebidas)", impactHint: "-14,2% Recuperación si >1", isDay: false),
    HabitMeta(id: "early_dinner", icon: "🍽️", label: "Cena temprana (>3h antes)", impactHint: "+7,3% VFC nocturna", isDay: false),
    HabitMeta(id: "cold_room", icon: "❄️", label: "Dormitorio frío (<19°C)", impactHint: "+5,2% Sueño REM", isDay: false),
    HabitMeta(id: "blue_light", icon: "🕶️", label: "Gafas bloqueo luz azul", impactHint: "-12 min Latencia sueño", isDay: false),
    HabitMeta(id: "sleep_mask", icon: "😴", label: "Antifaz / Tapones", impactHint: "-2 Despertares nocturnos", isDay: false),
]

struct DiarioScreen: View {
    @ObservedObject var store: ImprovingStore
    let onNavigate: (OverlayRoute) -> Void

    @State private var showInsightsSheet: Bool = false

    private let dayNames = ["lun", "mar", "mié", "jue", "vie", "sáb", "dom"]
    private let dayOffsets = [-5, -4, -3, -2, -1, 0, 1]

    var body: some View {
        let dayMap = store.journalCheckinsByDate[store.selectedDateIso] ?? defaultHabitsMap
        let mood = store.journalMoodByDate[store.selectedDateIso] ?? 4
        let yesCount = dayMap.values.filter { $0 == .yes }.count
        let totalCount = allJournalHabits.count
        let meals = store.mealsByDate[store.selectedDateIso] ?? []
        let glasses = store.hydrationGlassesByDate[store.selectedDateIso] ?? 8
        let waterMl = glasses * 250

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 1. Header Row: Información pill + •••
                HStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Button { showInsightsSheet = true } label: {
                            HStack(spacing: 6) {
                                Text("✨")
                                    .font(.system(size: 12))
                                Text("Información")
                                    .font(ImprovingFont.caption(12.5))
                                    .fontWeight(.semibold)
                                    .foregroundColor(BevelColors.textPrimary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(BevelColors.card))
                            .overlay(Capsule().strokeBorder(BevelColors.cardBorder, lineWidth: 1))
                        }

                        Button { showInsightsSheet = true } label: {
                            Text("•••")
                                .font(ImprovingFont.caption(12))
                                .fontWeight(.bold)
                                .foregroundColor(BevelColors.textPrimary)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(BevelColors.card))
                                .overlay(Circle().strokeBorder(BevelColors.cardBorder, lineWidth: 1))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Diario")
                        .font(ImprovingFont.displayLarge(28))
                        .foregroundColor(BevelColors.textPrimary)
                    Text("noviembre 2026")
                        .font(ImprovingFont.body(14))
                        .foregroundColor(BevelColors.textSecondary)
                }

                // 2. 7-Day Week Calendar Strip
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { idx in
                        let offset = dayOffsets[idx]
                        let isSelected = offset == store.selectedDayOffset
                        let dayNum = 21 + offset
                        let isFuture = offset > 0

                        Button {
                            if !isFuture {
                                store.shiftDay(offset - store.selectedDayOffset)
                            }
                        } label: {
                            VStack(spacing: 6) {
                                Text(dayNames[idx])
                                    .font(ImprovingFont.caption(11.5))
                                    .foregroundColor(isSelected ? .white.opacity(0.85) : BevelColors.textSecondary)
                                Text("\(dayNum)")
                                    .font(ImprovingFont.cardTitle(14.5))
                                    .foregroundColor(isSelected ? .white : (isFuture ? BevelColors.textMuted : BevelColors.textPrimary))

                                ZStack {
                                    Circle()
                                        .fill(isFuture ? BevelColors.trackGroove : (idx == 2 ? BevelColors.amberStart : BevelColors.emeraldEnd))
                                        .frame(width: 22, height: 22)
                                    if !isFuture {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(isSelected ? BevelColors.floatingDarkButton : .clear)
                            )
                        }
                    }
                }

                // 3. Entradas de hoy + Badge
                HStack {
                    Text("Entradas de hoy")
                        .font(ImprovingFont.sectionTitle(18))
                        .foregroundColor(BevelColors.textPrimary)
                    Spacer()
                    Text("\(yesCount) métricas · \(yesCount >= totalCount / 2 ? "Verde" : "Ámbar")")
                        .font(ImprovingFont.caption(12))
                        .fontWeight(.semibold)
                        .foregroundColor(yesCount >= totalCount / 2 ? BevelColors.emeraldEnd : BevelColors.orangeEnd)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(yesCount >= totalCount / 2 ? BevelColors.greenSoftBg : BevelColors.amberSoftBg))
                }

                // 4. DÍA Section
                Text("Día")
                    .font(ImprovingFont.cardTitle(15))
                    .foregroundColor(BevelColors.textSecondary)

                // Mood Check-in Card
                BevelCard(cornerRadius: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("¿Cómo te sientes hoy?")
                                .font(ImprovingFont.cardTitle(14.5))
                                .foregroundColor(BevelColors.textPrimary)
                            Spacer()
                            Text(["Agotado", "Bajo", "Normal", "Bien", "Increíble"][max(0, min(4, mood - 1))])
                                .font(ImprovingFont.caption(12))
                                .fontWeight(.semibold)
                                .foregroundColor(BevelColors.emeraldEnd)
                        }
                        HStack(spacing: 8) {
                            let emojis = ["😫", "😕", "😐", "🙂", "🤩"]
                            ForEach(1...5, id: \.self) { m in
                                let active = mood == m
                                Button { store.setJournalMood(m) } label: {
                                    Text(emojis[m - 1])
                                        .font(.system(size: 20))
                                        .frame(width: 44, height: 44)
                                        .background(Circle().fill(active ? BevelColors.greenSoftBg : BevelColors.trackGroove))
                                        .overlay(Circle().strokeBorder(active ? BevelColors.emeraldEnd : .clear, lineWidth: 1.5))
                                }
                                if m < 5 { Spacer() }
                            }
                        }
                    }
                    .padding(16)
                }

                // Nutrition Linked Entries
                Button { onNavigate(.nutricion) } label: {
                    BevelCard(cornerRadius: 18) {
                        HStack(spacing: 12) {
                            Text("💧")
                                .font(.system(size: 16))
                                .frame(width: 38, height: 38)
                                .background(Circle().fill(BevelColors.skySoftBg))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Hidratación registrada")
                                    .font(ImprovingFont.cardTitle(14.5))
                                    .foregroundColor(BevelColors.textPrimary)
                                Text("Sincronizado con Nutrición · \(waterMl) ml")
                                    .font(ImprovingFont.caption(11.5))
                                    .foregroundColor(BevelColors.textSecondary)
                            }
                            Spacer()
                            Text("\(waterMl) ml")
                                .font(ImprovingFont.caption(12))
                                .fontWeight(.bold)
                                .foregroundColor(BevelColors.skyBlue)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(BevelColors.skySoftBg))
                        }
                        .padding(14)
                    }
                }

                Button { onNavigate(.nutricion) } label: {
                    BevelCard(cornerRadius: 18) {
                        HStack(spacing: 12) {
                            Text("🥑")
                                .font(.system(size: 16))
                                .frame(width: 38, height: 38)
                                .background(Circle().fill(BevelColors.greenSoftBg))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Desayuno / Comida registrada")
                                    .font(ImprovingFont.cardTitle(14.5))
                                    .foregroundColor(BevelColors.textPrimary)
                                Text(meals.first.map { "\($0.name) (\($0.kcal) kcal)" } ?? "Tostada masa madre, aguacate y huevos")
                                    .font(ImprovingFont.caption(11.5))
                                    .foregroundColor(BevelColors.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text("\(meals.count) comidas")
                                .font(ImprovingFont.caption(12))
                                .fontWeight(.bold)
                                .foregroundColor(BevelColors.emeraldEnd)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(BevelColors.greenSoftBg))
                        }
                        .padding(14)
                    }
                }

                ForEach(allJournalHabits.filter(\.isDay)) { habit in
                    habitRowCard(habit: habit, state: dayMap[habit.id] ?? .yes)
                }

                // 5. NOCHE Section
                Text("Noche")
                    .font(ImprovingFont.cardTitle(15))
                    .foregroundColor(BevelColors.textSecondary)
                    .padding(.top, 4)

                ForEach(allJournalHabits.filter { !$0.isDay }) { habit in
                    habitRowCard(habit: habit, state: dayMap[habit.id] ?? .yes)
                }

                // 6. AUTOMÁTICO Section
                Text("Automático")
                    .font(ImprovingFont.cardTitle(15))
                    .foregroundColor(BevelColors.textSecondary)
                    .padding(.top, 4)

                autoEntryRow(icon: "☀️", title: "Luz diurna", subtitle: "68 mins · Apple Health / Sensor ambiental")
                autoEntryRow(icon: "👣", title: "Pasos", subtitle: "\(store.stepsCount) pasos · Podómetro activo")
                autoEntryRow(icon: "🛏️", title: "Hora de dormir", subtitle: "23:12 · Detectado por WHOOP 5.0")

                // 7. Consistencia (42 días)
                Text("Consistencia (42 días)")
                    .font(ImprovingFont.sectionTitle(18))
                    .foregroundColor(BevelColors.textPrimary)
                    .padding(.top, 4)

                BevelCard {
                    VStack(alignment: .leading, spacing: 10) {
                        ConsistencyHeatmapGrid(levels: (0..<42).map { i in (i % 4 == 0) ? 2 : 3 })
                    }
                    .padding(16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 120)
        }
        .background(BevelColors.canvas)
        .sheet(isPresented: $showInsightsSheet) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Correlaciones con tu Recuperación (90 días)")
                            .font(ImprovingFont.cardTitle(15))
                            .foregroundColor(BevelColors.textSecondary)
                        ForEach(allJournalHabits) { h in
                            BevelCard(cornerRadius: 16) {
                                HStack {
                                    Text(h.icon).font(.system(size: 18))
                                    Text(h.label).font(ImprovingFont.cardTitle(14)).foregroundColor(BevelColors.textPrimary)
                                    Spacer()
                                    Text(h.impactHint).font(ImprovingFont.caption(12)).fontWeight(.semibold).foregroundColor(BevelColors.emeraldEnd)
                                }
                                .padding(14)
                            }
                        }
                    }
                    .padding(16)
                }
                .background(BevelColors.canvas)
                .navigationTitle("Impacto de tus hábitos")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private var defaultHabitsMap: [String: JournalCheckState] {
        var map: [String: JournalCheckState] = [:]
        for (i, h) in allJournalHabits.enumerated() {
            map[h.id] = (i % 6 == 4) ? .no : .yes
        }
        return map
    }

    private func habitRowCard(habit: HabitMeta, state: JournalCheckState) -> some View {
        BevelCard(cornerRadius: 18) {
            HStack(spacing: 12) {
                Text(habit.icon)
                    .font(.system(size: 16))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(BevelColors.trackGroove))
                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.label)
                        .font(ImprovingFont.cardTitle(14.5))
                        .foregroundColor(BevelColors.textPrimary)
                    Text(habit.impactHint)
                        .font(ImprovingFont.caption(11.5))
                        .foregroundColor(BevelColors.textSecondary)
                }
                Spacer()
                triStatePill(current: state) { next in
                    store.setJournalCheck(habitId: habit.id, state: next)
                }
            }
            .padding(14)
        }
    }

    private func autoEntryRow(icon: String, title: String, subtitle: String) -> some View {
        BevelCard(cornerRadius: 18) {
            HStack(spacing: 12) {
                Text(icon)
                    .font(.system(size: 16))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(BevelColors.trackGroove))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(ImprovingFont.cardTitle(14.5))
                        .foregroundColor(BevelColors.textPrimary)
                    Text(subtitle)
                        .font(ImprovingFont.caption(12))
                        .foregroundColor(BevelColors.textSecondary)
                }
                Spacer()
                Text("✓ Registrado")
                    .font(ImprovingFont.caption(11.5))
                    .fontWeight(.semibold)
                    .foregroundColor(BevelColors.emeraldEnd)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(BevelColors.greenSoftBg))
            }
            .padding(14)
        }
    }

    private func triStatePill(current: JournalCheckState, onSelect: @escaping (JournalCheckState) -> Void) -> some View {
        HStack(spacing: 4) {
            pillBtn(label: "✕", active: current == .no, activeBg: BevelColors.coralHigh, activeFg: .white) { onSelect(.no) }
            pillBtn(label: "—", active: current == .unset, activeBg: BevelColors.journalNeutralBg, activeFg: BevelColors.textPrimary) { onSelect(.unset) }
            pillBtn(label: "✓", active: current == .yes, activeBg: BevelColors.emeraldEnd, activeFg: .white) { onSelect(.yes) }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 12).fill(BevelColors.trackGroove))
    }

    private func pillBtn(label: String, active: Bool, activeBg: Color, activeFg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(ImprovingFont.caption(12))
                .fontWeight(.bold)
                .foregroundColor(active ? activeFg : BevelColors.textSecondary)
                .frame(width: 30, height: 26)
                .background(RoundedRectangle(cornerRadius: 9).fill(active ? activeBg : .clear))
        }
    }
}

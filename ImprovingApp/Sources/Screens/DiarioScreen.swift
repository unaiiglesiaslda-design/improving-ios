import SwiftUI

struct DiarioScreen: View {
    @ObservedObject var store: ImprovingStore
    let onNavigate: (OverlayRoute) -> Void

    private let habits: [(id: String, title: String, category: String)] = [
        ("cafeina", "Sin cafeína tarde (>15:00)", "Sueño"),
        ("pantallas", "Sin pantallas antes de dormir", "Sueño"),
        ("cena_ligera", "Cena 2h+ antes de acostarte", "Digestión"),
        ("hidratacion", "2,5 L de hidratación cumplida", "Hidratación"),
        ("magnesio", "Magnesio / Electrolitos nocturnos", "Suplementos"),
        ("sol_manana", "Luz solar matinal (15 min)", "Ritmo Circadiano"),
    ]

    var body: some View {
        let dayMap = store.journalCheckinsByDate[store.selectedDateIso] ?? [:]
        let mood = store.journalMoodByDate[store.selectedDateIso] ?? 4

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Diario")
                        .font(ImprovingFont.displayLarge(26))
                        .foregroundColor(BevelColors.textPrimary)
                    Spacer()
                    Button { onNavigate(.nutricion) } label: {
                        Text("Nutrición →")
                            .font(ImprovingFont.caption(12.5))
                            .foregroundColor(BevelColors.emeraldEnd)
                    }
                }

                // Mood check-in
                BevelCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("¿CÓMO TE SIENTES HOY?")
                            .font(ImprovingFont.microLabel(11))
                            .foregroundColor(BevelColors.textSecondary)
                        HStack(spacing: 8) {
                            ForEach(1...5, id: \.self) { m in
                                Button { store.setJournalMood(m) } label: {
                                    Text(["😫", "😕", "😐", "🙂", "🔥"][m - 1])
                                        .font(.system(size: 22))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(RoundedRectangle(cornerRadius: 12).fill(mood == m ? BevelColors.greenSoftBg : BevelColors.cardSubtle))
                                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(mood == m ? BevelColors.emeraldEnd : .clear, lineWidth: 1.2))
                                }
                            }
                        }
                    }
                    .padding(16)
                }

                // Habits Tri-State Switch
                Text("Hábitos de hoy")
                    .font(ImprovingFont.sectionTitle(18))
                    .foregroundColor(BevelColors.textPrimary)

                BevelCard {
                    VStack(spacing: 0) {
                        ForEach(Array(habits.enumerated()), id: \.element.id) { idx, h in
                            let st = dayMap[h.id] ?? .unset
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(h.title).font(ImprovingFont.cardTitle(14)).foregroundColor(BevelColors.textPrimary)
                                    Text(h.category).font(ImprovingFont.caption(11)).foregroundColor(BevelColors.textSecondary)
                                }
                                Spacer()
                                triStatePill(current: st) { next in
                                    store.setJournalCheck(habitId: h.id, state: next)
                                }
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 14)

                            if idx < habits.count - 1 {
                                Divider().background(BevelColors.divider)
                            }
                        }
                    }
                }

                // Consistency Heatmap
                Text("Consistencia (42 días)")
                    .font(ImprovingFont.sectionTitle(18))
                    .foregroundColor(BevelColors.textPrimary)

                BevelCard {
                    VStack(alignment: .leading, spacing: 10) {
                        let levels = (0..<42).map { i -> Int in
                            let d = Calendar.current.date(byAdding: .day, value: -i, to: Date()) ?? Date()
                            let f = DateFormatter()
                            f.dateFormat = "yyyy-MM-dd"
                            let entries = store.journalCheckinsByDate[f.string(from: d)]?.values.filter { $0 == .yes }.count ?? 0
                            return min(entries, 3)
                        }.reversed()
                        ConsistencyHeatmapGrid(levels: Array(levels))
                    }
                    .padding(16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 118)
        }
        .background(BevelColors.canvas)
    }

    private func triStatePill(current: JournalCheckState, onSelect: @escaping (JournalCheckState) -> Void) -> some View {
        HStack(spacing: 2) {
            pillBtn(icon: "xmark", active: current == .no, activeBg: BevelColors.redAlert) { onSelect(.no) }
            pillBtn(icon: "minus", active: current == .unset, activeBg: BevelColors.journalNeutralBg) { onSelect(.unset) }
            pillBtn(icon: "checkmark", active: current == .yes, activeBg: BevelColors.greenPrimary) { onSelect(.yes) }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 12).fill(BevelColors.trackGroove))
    }

    private func pillBtn(icon: String, active: Bool, activeBg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(active ? (activeBg == Color(hex: 0xFFFFFF) ? Color(hex: 0x111827) : .white) : BevelColors.textMuted)
                .frame(width: 28, height: 24)
                .background(RoundedRectangle(cornerRadius: 9).fill(active ? activeBg : .clear))
        }
    }
}

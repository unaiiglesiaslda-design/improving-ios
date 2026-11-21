import SwiftUI

struct FitnessScreen: View {
    @ObservedObject var store: ImprovingStore
    let onNavigate: (OverlayRoute) -> Void
    let onOpenTrainingLoad: (TrainingLoadTab) -> Void
    let onOpenCardioMetric: (CardioMetricRoute) -> Void

    var body: some View {
        let avail = store.dataAvailability
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Fitness")
                        .font(ImprovingFont.displayLarge(26))
                        .foregroundColor(BevelColors.textPrimary)
                    Spacer()
                    Button { onNavigate(.esfuerzo) } label: {
                        StatusDotPill(text: "Esfuerzo \(avail.hasStrainData ? "\(store.strainPercent)%" : "--")", dotColor: BevelColors.orangeEnd, bgColor: BevelColors.card)
                    }
                }

                // Cardio Load & Strain Card
                BevelCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("CARGA DE ENTRENAMIENTO")
                                .font(ImprovingFont.microLabel(11))
                                .foregroundColor(BevelColors.textSecondary)
                            Spacer()
                            Button("Ver detalle →") { onOpenTrainingLoad(.cardio) }
                                .font(ImprovingFont.caption(12))
                                .foregroundColor(BevelColors.emeraldEnd)
                        }
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(avail.hasStrainData ? String(format: "%.1f", store.strain21) : "--")
                                    .font(ImprovingFont.metricHero(28))
                                    .monospacedDigit()
                                    .foregroundColor(BevelColors.textPrimary)
                                Text("Strain 0–21").font(ImprovingFont.caption(11.5)).foregroundColor(BevelColors.textSecondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(avail.hasStrainData ? store.effortTargetRangeText : "--")
                                    .font(ImprovingFont.cardTitle(16))
                                    .monospacedDigit()
                                    .foregroundColor(BevelColors.orangeEnd)
                                Text("Rango óptimo hoy").font(ImprovingFont.caption(11.5)).foregroundColor(BevelColors.textSecondary)
                            }
                        }
                    }
                    .padding(16)
                }

                // Strength Tracker & Rest Timer
                HStack {
                    Text("Entrenamiento de fuerza")
                        .font(ImprovingFont.sectionTitle(18))
                        .foregroundColor(BevelColors.textPrimary)
                    Spacer()
                    Button { store.addStrengthSet() } label: {
                        Text("+ Serie")
                            .font(ImprovingFont.caption(12))
                            .fontWeight(.semibold)
                            .foregroundColor(BevelColors.emeraldEnd)
                    }
                }

                BevelCard {
                    VStack(spacing: 10) {
                        HStack {
                            Label("Temporizador de descanso: \(store.restTimerSeconds) s", systemImage: "timer")
                                .font(ImprovingFont.caption(12.5))
                                .monospacedDigit()
                                .foregroundColor(BevelColors.textPrimary)
                            Spacer()
                            Button(store.restTimerRunning ? "Pausar" : "Iniciar") {
                                store.toggleRestTimer()
                            }
                            .font(ImprovingFont.caption(12))
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(store.restTimerRunning ? BevelColors.orangeEnd : BevelColors.emeraldEnd))
                        }

                        Divider().background(BevelColors.divider)

                        ForEach(store.strengthSets, id: \.id) { s in
                            Button { store.toggleSetCompleted(s.id) } label: {
                                HStack {
                                    Image(systemName: s.completed ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(s.completed ? BevelColors.greenPrimary : BevelColors.textMuted)
                                    Text(s.exercise)
                                        .font(ImprovingFont.cardTitle(13.5))
                                        .foregroundColor(BevelColors.textPrimary)
                                    Spacer()
                                    Text("\(s.reps) × \(Int(s.weightKg)) kg")
                                        .font(ImprovingFont.caption(12.5))
                                        .monospacedDigit()
                                        .foregroundColor(BevelColors.textSecondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .padding(16)
                }

                // Cardio Metrics Grid
                Text("Métricas cardiovasculares")
                    .font(ImprovingFont.sectionTitle(18))
                    .foregroundColor(BevelColors.textPrimary)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(CardioMetricRoute.allCases) { route in
                        Button { onOpenCardioMetric(route) } label: {
                            BevelCard(cornerRadius: 18) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(route.rawValue)
                                        .font(ImprovingFont.caption(12))
                                        .foregroundColor(BevelColors.textSecondary)
                                        .lineLimit(2)
                                    Text(cardioValue(route))
                                        .font(ImprovingFont.metricTile(19))
                                        .monospacedDigit()
                                        .foregroundColor(BevelColors.textPrimary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 118)
        }
        .background(BevelColors.canvas)
    }

    private func cardioValue(_ route: CardioMetricRoute) -> String {
        let d = store.currentDaySummary
        switch route {
        case .activitiesDuration:
            let totalMin = store.workoutsToday.reduce(0) { $0 + $1.durationMin }
            return totalMin > 0 ? "\(totalMin) min" : "--"
        case .cardioLoad:
            return d?.strain21.map { String(format: "%.1f", $0) } ?? "--"
        case .vo2Max:
            return d?.vo2MaxMlKgMin.map { String(format: "%.1f ml/kg", $0) } ?? "--"
        case .hrRecovery:
            return d?.restingHrBpm != nil ? "32 ppm" : "--"
        }
    }
}

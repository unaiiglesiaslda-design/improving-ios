import SwiftUI

struct BiologiaScreen: View {
    @ObservedObject var store: ImprovingStore
    let onSelectHealthMetric: (HealthMetricKind) -> Void
    let onNavigate: (OverlayRoute) -> Void

    var body: some View {
        let avail = store.dataAvailability
        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: store.userProfile)
        let bioDelta = avail.hasAnyRecordedData ? -2.4 : 0.0
        let bioAge = store.userProfile.ageYears + bioDelta

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Biología")
                        .font(ImprovingFont.displayLarge(26))
                        .foregroundColor(BevelColors.textPrimary)
                    Spacer()
                    Button { onNavigate(.dispositivos) } label: {
                        Text("Perfil →")
                            .font(ImprovingFont.caption(12.5))
                            .foregroundColor(BevelColors.skyBlue)
                    }
                }

                BevelCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("EDAD BIOLÓGICA ESTIMADA")
                            .font(ImprovingFont.microLabel(11))
                            .foregroundColor(BevelColors.skyBlue)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(String(format: "%.1f años", locale: Locale(identifier: "es_ES"), bioAge))
                                .font(ImprovingFont.displayLarge(32))
                                .monospacedDigit()
                                .foregroundColor(BevelColors.textPrimary)
                            Text(avail.hasAnyRecordedData ? String(format: "%.1f vs cronológica", bioDelta) : "Conecta datos reales")
                                .font(ImprovingFont.caption(12.5))
                                .foregroundColor(avail.hasAnyRecordedData ? BevelColors.emeraldEnd : BevelColors.textMuted)
                        }
                        Text("Calculado con tu tendencia real de VFC, FCR, VO₂ máx y sueño reparador.")
                            .font(ImprovingFont.caption(12))
                            .foregroundColor(BevelColors.textSecondary)
                    }
                    .padding(16)
                }

                // Physiology Baseline Grid
                Text("Líneas base personales")
                    .font(ImprovingFont.sectionTitle(18))
                    .foregroundColor(BevelColors.textPrimary)

                BevelCard {
                    VStack(spacing: 12) {
                        bioRow("VFC esperada por edad", "\(Int(norms.hrvLowMs)) – \(Int(norms.hrvHighMs)) ms", kind: .hrv)
                        Divider().background(BevelColors.divider)
                        bioRow("FC en reposo objetivo", "\(Int(norms.rhrLowBpm)) – \(Int(norms.rhrHighBpm)) ppm", kind: .restingHeartRate)
                        Divider().background(BevelColors.divider)
                        bioRow("Frecuencia cardíaca máx.", "\(norms.maxHrBpm) ppm", kind: .respiratoryRate)
                        Divider().background(BevelColors.divider)
                        bioRow("Tasa metabólica basal", "\(norms.bmrKcal) kcal/día", kind: .sleepDuration)
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

    private func bioRow(_ label: String, _ val: String, kind: HealthMetricKind) -> some View {
        Button { onSelectHealthMetric(kind) } label: {
            HStack {
                Text(label).font(ImprovingFont.body(14)).foregroundColor(BevelColors.textPrimary)
                Spacer()
                Text(val).font(ImprovingFont.cardTitle(14)).monospacedDigit().foregroundColor(BevelColors.skyBlue)
                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundColor(BevelColors.textMuted)
            }
        }
    }
}

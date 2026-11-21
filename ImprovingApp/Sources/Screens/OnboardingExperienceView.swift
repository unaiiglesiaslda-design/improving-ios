import SwiftUI

struct OnboardingExperienceView: View {
    @State private var step: Int = 0
    @State private var name: String = ""
    @State private var sex: BiologicalSexOption = .male
    @State private var age: Double = 24
    @State private var weight: Double = 70
    @State private var height: Double = 176

    let onFinish: (UserPhysiologyProfile) -> Void

    var body: some View {
        ZStack {
            BevelColors.canvas.ignoresSafeArea()

            VStack(spacing: 20) {
                HStack {
                    Text("IMPROVING")
                        .font(ImprovingFont.microLabel(12))
                        .tracking(2)
                        .foregroundColor(BevelColors.emeraldEnd)
                    Spacer()
                    Text("\(step + 1) / 3")
                        .font(ImprovingFont.caption(12))
                        .foregroundColor(BevelColors.textSecondary)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                TabView(selection: $step) {
                    editorialSlide(
                        imageName: "onboarding_wearable",
                        title: "Tu fisiología, en tiempo real",
                        subtitle: "Conecta Apple Health, importa tu archivo exportar.zip o enlaza tu pulsera WHOOP para medir recuperación, VFC y carga real."
                    ).tag(0)

                    editorialSlide(
                        imageName: "onboarding_sleep",
                        title: "Sueño y recuperación precisos",
                        subtitle: "Detecta fases profundas, REM y necesidad exacta de descanso adaptada a tu edad y nivel de esfuerzo diario."
                    ).tag(1)

                    profileSetupSlide.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                Button {
                    if step < 2 {
                        withAnimation { step += 1 }
                    } else {
                        var p = UserPhysiologyProfile()
                        p.userName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        p.sex = sex
                        p.ageYears = age
                        p.weightKg = weight
                        p.heightCm = height
                        p.onboardingCompleted = true
                        onFinish(p)
                    }
                } label: {
                    Text(step < 2 ? "Continuar" : "Empezar ahora")
                        .font(ImprovingFont.cardTitle(16))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Capsule().fill(BevelColors.emeraldEnd))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
    }

    private func editorialSlide(imageName: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 18) {
            if let path = Bundle.main.path(forResource: imageName, ofType: "jpg"),
               let uiImg = UIImage(contentsOfFile: path) {
                Image(uiImage: uiImg)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 310)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .padding(.horizontal, 24)
            } else {
                RoundedRectangle(cornerRadius: 26)
                    .fill(BevelColors.card)
                    .frame(height: 310)
                    .padding(.horizontal, 24)
            }

            VStack(spacing: 10) {
                Text(title)
                    .font(ImprovingFont.displayLarge(26))
                    .foregroundColor(BevelColors.textPrimary)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(ImprovingFont.body(14.5))
                    .foregroundColor(BevelColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
            Spacer()
        }
    }

    private var profileSetupSlide: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Calibra tu perfil fisiológico")
                    .font(ImprovingFont.displayLarge(24))
                    .foregroundColor(BevelColors.textPrimary)
                Text("Personaliza tus zonas de frecuencia cardíaca, tasa basal y necesidad de sueño.")
                    .font(ImprovingFont.body(13.5))
                    .foregroundColor(BevelColors.textSecondary)

                BevelCard {
                    VStack(spacing: 14) {
                        TextField("Tu nombre (opcional)", text: $name)
                            .font(ImprovingFont.body(15))
                            .foregroundColor(BevelColors.textPrimary)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(BevelColors.cardSubtle))

                        HStack(spacing: 8) {
                            ForEach(BiologicalSexOption.allCases, id: \.self) { opt in
                                Button { sex = opt } label: {
                                    Text(opt.rawValue)
                                        .font(ImprovingFont.caption(12))
                                        .foregroundColor(sex == opt ? .white : BevelColors.textSecondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 9)
                                        .background(RoundedRectangle(cornerRadius: 11).fill(sex == opt ? BevelColors.emeraldEnd : BevelColors.cardSubtle))
                                }
                            }
                        }

                        stepperRow("Edad", "\(Int(age)) años", onMinus: { age = max(14, age - 1) }, onPlus: { age = min(90, age + 1) })
                        stepperRow("Peso", String(format: "%.1f kg", weight), onMinus: { weight = max(35, weight - 0.5) }, onPlus: { weight = min(180, weight + 0.5) })
                        stepperRow("Altura", "\(Int(height)) cm", onMinus: { height = max(135, height - 1) }, onPlus: { height = min(220, height + 1) })
                    }
                    .padding(16)
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private func stepperRow(_ label: String, _ val: String, onMinus: @escaping () -> Void, onPlus: @escaping () -> Void) -> some View {
        HStack {
            Text(label).font(ImprovingFont.cardTitle(14)).foregroundColor(BevelColors.textPrimary)
            Spacer()
            HStack(spacing: 10) {
                Button(action: onMinus) {
                    Image(systemName: "minus").frame(width: 28, height: 28).background(Circle().fill(BevelColors.trackGroove))
                }
                Text(val).font(ImprovingFont.cardTitle(13.5)).monospacedDigit().foregroundColor(BevelColors.textPrimary).frame(minWidth: 74)
                Button(action: onPlus) {
                    Image(systemName: "plus").frame(width: 28, height: 28).background(Circle().fill(BevelColors.trackGroove))
                }
            }
            .foregroundColor(BevelColors.textPrimary)
        }
    }
}

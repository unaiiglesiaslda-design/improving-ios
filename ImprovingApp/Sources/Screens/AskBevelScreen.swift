import SwiftUI

// MARK: - Ask Improving AI Screen (Literal Match to Screenshot 75)

struct AskBevelScreen: View {
    @ObservedObject var store: ImprovingStore
    let onClose: () -> Void
    let onOpenSettings: () -> Void

    @State private var inputText: String = ""

    private var hasUserConversation: Bool {
        store.coachMessages.contains(where: \.isUser)
    }

    var body: some View {
        let userName = store.userProfile.userName.isEmpty ? "Unai" : store.userProfile.userName

        ZStack {
            // Deep atmospheric midnight-indigo gradient (Screenshot 75)
            RadialGradient(
                colors: BevelColors.isDarkMode
                    ? [Color(hex: 0x262B3D), Color(hex: 0x16181F), Color(hex: 0x121317)]
                    : [BevelColors.canvas, BevelColors.canvas],
                center: UnitPoint(x: 0.5, y: 0.25),
                startRadius: 20,
                endRadius: 520
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Bar (Screenshot 75): [ ≡ ] left  ...  [ (mascot) | ✕ ] right
                HStack {
                    Button { store.startNewCleanChat() } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(BevelColors.textPrimary)
                            .frame(width: 42, height: 42)
                            .background(Circle().fill(BevelColors.glassChromeFill))
                            .overlay(Circle().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.8))
                    }

                    Spacer()

                    HStack(spacing: 14) {
                        Button(action: onOpenSettings) {
                            Image(systemName: "face.smiling")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(BevelColors.textPrimary)
                        }
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(BevelColors.textPrimary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .background(Capsule().fill(BevelColors.glassChromeFill))
                    .overlay(Capsule().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.8))
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                if !hasUserConversation {
                    // Clean Welcome Hero (Exact Match to Screenshot 75)
                    Spacer()
                    VStack(spacing: 18) {
                        BevelMascotOrb(size: 92)
                        VStack(spacing: 6) {
                            Text(store.dateLabel)
                                .font(ImprovingFont.caption(14))
                                .foregroundColor(BevelColors.textSecondary)
                            Text("Hola, \(userName).")
                                .font(ImprovingFont.displayLarge(28))
                                .foregroundColor(BevelColors.textPrimary)
                        }
                    }
                    Spacer()
                    Spacer()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 12) {
                                ForEach(store.coachMessages) { msg in
                                    HStack {
                                        if msg.isUser { Spacer(minLength: 48) }
                                        Text(msg.text)
                                            .font(ImprovingFont.body(14.5))
                                            .foregroundColor(msg.isUser ? .white : BevelColors.textPrimary)
                                            .padding(.horizontal, 15)
                                            .padding(.vertical, 11)
                                            .background(
                                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                    .fill(msg.isUser ? BevelColors.indigoEnd : BevelColors.card)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                    .strokeBorder(msg.isUser ? .clear : BevelColors.cardBorder, lineWidth: 0.8)
                                            )
                                        if !msg.isUser { Spacer(minLength: 48) }
                                    }
                                    .id(msg.id)
                                }

                                if store.isCoachThinking {
                                    HStack {
                                        HStack(spacing: 8) {
                                            ProgressView().scaleEffect(0.85)
                                            Text("Analizando tus métricas...")
                                                .font(ImprovingFont.caption(12.5))
                                                .foregroundColor(BevelColors.textSecondary)
                                        }
                                        .padding(12)
                                        .background(RoundedRectangle(cornerRadius: 16).fill(BevelColors.card))
                                        Spacer()
                                    }
                                }
                            }
                            .padding(16)
                        }
                        .onChange(of: store.coachMessages.count) { _, _ in
                            if let last = store.coachMessages.last {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                    }
                }

                // Bottom Suggestion Cards (Screenshot 75)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        suggestionCard(icon: "calendar", title: "Comprobarlo yo mismo", subtitle: "Programar comprobaciones regulares") {
                            store.sendCoachPrompt("Hazme un chequeo completo de mi recuperación, sueño y VFC hoy")
                        }
                        suggestionCard(icon: "figure.run", title: "Plan de entrenamiento", subtitle: "Según mi esfuerzo óptimo hoy") {
                            store.sendCoachPrompt("¿Cómo debería entrenar hoy según mi recuperación y esfuerzo?")
                        }
                        suggestionCard(icon: "moon.stars.fill", title: "Analizar mi sueño", subtitle: "Fases REM, profundo y deuda") {
                            store.sendCoachPrompt("Analiza mi calidad de sueño y qué mejorar esta noche")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                }

                // Frosted Glass Composer Box (Exact Match to Screenshot 75)
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Pregunta a Improving lo que sea", text: $inputText)
                        .font(ImprovingFont.body(15))
                        .foregroundColor(BevelColors.textPrimary)

                    HStack(spacing: 8) {
                        Button(action: onOpenSettings) {
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(BevelColors.textPrimary)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(Color.white.opacity(0.08)))
                        }

                        Text("Adaptable")
                            .font(ImprovingFont.caption(13))
                            .fontWeight(.semibold)
                            .foregroundColor(BevelColors.textPrimary)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(Capsule().fill(Color.white.opacity(0.08)))

                        Spacer()

                        Image(systemName: "mic")
                            .font(.system(size: 16))
                            .foregroundColor(BevelColors.textSecondary)
                            .padding(.trailing, 4)

                        Button {
                            let q = inputText
                            inputText = ""
                            store.sendCoachPrompt(q)
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.black)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(.white))
                        }
                        .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
                        .opacity(inputText.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1.0)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(BevelColors.glassChromeFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.9)
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
        }
    }

    private func suggestionCard(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(BevelColors.skyBlue)
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.cardSubtle))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(ImprovingFont.cardTitle(13.5)).foregroundColor(BevelColors.textPrimary)
                    Text(subtitle).font(ImprovingFont.caption(12)).foregroundColor(BevelColors.textSecondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 18).fill(BevelColors.glassChromeFill))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.8))
        }
    }
}

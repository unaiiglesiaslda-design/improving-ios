import SwiftUI

// MARK: - Ask Improving AI Screen (Android Coach Personality + Structured Verdicts & Bullets + Open-Ended Freedom)

struct AskBevelScreen: View {
    @ObservedObject var store: ImprovingStore
    let onClose: () -> Void
    let onOpenSettings: () -> Void

    @State private var inputText: String = ""

    private var hasUserConversation: Bool {
        !store.coachMessages.isEmpty
    }

    var body: some View {
        let userName = store.userProfile.displayFirstName.isEmpty ? "tú" : store.userProfile.displayFirstName
        let hasKey = !store.geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        ZStack {
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
                // Top Bar
                HStack {
                    Button { store.startNewCleanChat() } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(BevelColors.textPrimary)
                            .frame(width: 42, height: 42)
                            .background(Circle().fill(BevelColors.glassChromeFill))
                            .overlay(Circle().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.8))
                    }

                    Spacer()

                    Button(action: onOpenSettings) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(hasKey ? BevelColors.greenPrimary : BevelColors.skyBlue)
                                .frame(width: 7, height: 7)
                            Text(hasKey ? (store.selectedGeminiModel == "auto" ? "Gemini Auto" : store.selectedGeminiModel) : "Improving IA Live")
                                .font(ImprovingFont.caption(12))
                                .fontWeight(.semibold)
                                .foregroundColor(BevelColors.textPrimary)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(Capsule().fill(BevelColors.glassChromeFill))
                        .overlay(Capsule().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.8))
                    }

                    Spacer()

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(BevelColors.textPrimary)
                            .frame(width: 42, height: 42)
                            .background(Circle().fill(BevelColors.glassChromeFill))
                            .overlay(Circle().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.8))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                if !hasUserConversation {
                    Spacer()
                    VStack(spacing: 18) {
                        BevelMascotOrb(size: 92)
                        VStack(spacing: 6) {
                            Text(store.dateLabel)
                                .font(ImprovingFont.caption(14))
                                .foregroundColor(BevelColors.textSecondary)
                            Text(userName == "tú" ? "Hola, ¿qué necesitas?" : "Hola, \(userName).")
                                .font(ImprovingFont.displayLarge(28))
                                .foregroundColor(BevelColors.textPrimary)
                            Text("Pregúntame cualquier cosa sobre tu cuerpo, entrenamiento, comida, descanso o planes de hoy.")
                                .font(ImprovingFont.body(13.5))
                                .foregroundColor(BevelColors.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 34)
                        }
                    }
                    Spacer()
                    Spacer()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 14) {
                                ForEach(store.coachMessages) { msg in
                                    if msg.isUser {
                                        HStack {
                                            Spacer(minLength: 44)
                                            Text(msg.text)
                                                .font(ImprovingFont.body(14.5))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 15)
                                                .padding(.vertical, 11)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                        .fill(BevelColors.indigoEnd)
                                                )
                                        }
                                        .id(msg.id)
                                    } else {
                                        HStack(alignment: .top, spacing: 10) {
                                            BevelMascotOrb(size: 28)
                                                .padding(.top, 4)

                                            VStack(alignment: .leading, spacing: 9) {
                                                if let title = msg.verdictTitle, !title.isEmpty {
                                                    Text(title)
                                                        .font(ImprovingFont.microLabel(11))
                                                        .foregroundColor(BevelColors.greenPrimary)
                                                }

                                                Text(msg.text)
                                                    .font(ImprovingFont.body(14.5))
                                                    .foregroundColor(BevelColors.textPrimary)
                                                    .fixedSize(horizontal: false, vertical: true)

                                                if !msg.bullets.isEmpty {
                                                    VStack(alignment: .leading, spacing: 6) {
                                                        ForEach(msg.bullets, id: \.self) { b in
                                                            HStack(alignment: .top, spacing: 7) {
                                                                Circle()
                                                                    .fill(BevelColors.periwinkleStart)
                                                                    .frame(width: 5, height: 5)
                                                                    .padding(.top, 7)
                                                                Text(b)
                                                                    .font(ImprovingFont.caption(13))
                                                                    .foregroundColor(BevelColors.textSecondary)
                                                                    .fixedSize(horizontal: false, vertical: true)
                                                            }
                                                        }
                                                    }
                                                    .padding(.top, 2)
                                                }

                                                if let model = msg.modelUsed, !model.isEmpty {
                                                    HStack(spacing: 6) {
                                                        Text(msg.timestampLabel)
                                                        Text("·")
                                                        Text(model)
                                                    }
                                                    .font(ImprovingFont.caption(10.5))
                                                    .foregroundColor(BevelColors.textMuted)
                                                    .padding(.top, 2)
                                                }
                                            }
                                            .padding(.horizontal, 15)
                                            .padding(.vertical, 13)
                                            .background(
                                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                    .fill(BevelColors.card)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                    .strokeBorder(BevelColors.cardBorder, lineWidth: 0.8)
                                            )
                                            Spacer(minLength: 16)
                                        }
                                        .id(msg.id)
                                    }
                                }

                                if store.isCoachThinking {
                                    HStack(spacing: 10) {
                                        BevelMascotOrb(size: 26)
                                        HStack(spacing: 8) {
                                            ProgressView().scaleEffect(0.85)
                                            Text("Escribiendo con tus datos reales...")
                                                .font(ImprovingFont.caption(12.5))
                                                .foregroundColor(BevelColors.textSecondary)
                                        }
                                        .padding(12)
                                        .background(RoundedRectangle(cornerRadius: 16).fill(BevelColors.card))
                                        Spacer()
                                    }
                                    .id("thinking_indicator")
                                }
                            }
                            .padding(16)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .onChange(of: store.coachMessages.count) { _, _ in
                            DispatchQueue.main.async {
                                if store.isCoachThinking {
                                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("thinking_indicator", anchor: .bottom) }
                                } else if let last = store.coachMessages.last {
                                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(last.id, anchor: .bottom) }
                                }
                            }
                        }
                        .onChange(of: store.isCoachThinking) { _, thinking in
                            DispatchQueue.main.async {
                                if thinking {
                                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("thinking_indicator", anchor: .bottom) }
                                } else if let last = store.coachMessages.last {
                                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(last.id, anchor: .bottom) }
                                }
                            }
                        }
                    }
                }

                // Bottom Suggestion Cards (only before first message so chat stays clean)
                if !hasUserConversation {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            suggestionCard(icon: "figure.run", title: "¿Entreno fuerte hoy?", subtitle: "Según mi recuperación real") {
                                store.sendCoachPrompt("¿Debería entrenar fuerte hoy o ir suave según mis datos reales?")
                            }
                            suggestionCard(icon: "moon.stars.fill", title: "Analizar mi sueño", subtitle: "Fases y descanso real") {
                                store.sendCoachPrompt("Analiza mi última noche de sueño y dime qué puedo mejorar hoy")
                            }
                            suggestionCard(icon: "fork.knife", title: "¿Puedo cenar pizza hoy?", subtitle: "Pregunta abierta libre") {
                                store.sendCoachPrompt("¿Me afecta mucho si hoy ceno pizza o me tomo algo con amigos?")
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                    }
                }

                // Frosted Glass Open-Ended Composer Box
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Pregunta a Improving lo que sea", text: $inputText, axis: .vertical)
                        .lineLimit(1...4)
                        .font(ImprovingFont.body(15))
                        .foregroundColor(BevelColors.textPrimary)
                        .onSubmit { sendCurrentInput() }

                    HStack(spacing: 8) {
                        Button(action: onOpenSettings) {
                            HStack(spacing: 5) {
                                Image(systemName: "key.fill").font(.system(size: 11))
                                Text(hasKey ? "Gemini activo" : "API Key")
                                    .font(ImprovingFont.caption(12))
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(hasKey ? BevelColors.greenPrimary : BevelColors.textSecondary)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                        }

                        Spacer()

                        Button(action: sendCurrentInput) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.black)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(.white))
                        }
                        .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isCoachThinking)
                        .opacity(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1.0)
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

    private func sendCurrentInput() {
        let q = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !store.isCoachThinking else { return }
        inputText = ""
        store.sendCoachPrompt(q)
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

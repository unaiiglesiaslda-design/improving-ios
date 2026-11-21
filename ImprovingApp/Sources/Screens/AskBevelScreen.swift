import SwiftUI

struct AskBevelScreen: View {
    @ObservedObject var store: ImprovingStore
    let onClose: () -> Void
    let onOpenSettings: () -> Void

    @State private var inputText: String = ""

    private let suggestions = [
        "¿Cómo debería entrenar hoy?",
        "Analiza mi sueño y VFC",
        "¿Cuánto he dormido esta semana?",
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(BevelColors.textPrimary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(BevelColors.trackGroove))
                }
                IridescentPearlOrb(size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ask Improving")
                        .font(ImprovingFont.cardTitle(16))
                        .foregroundColor(BevelColors.textPrimary)
                    Text(store.geminiApiKey.isEmpty ? "Motor fisiológico local" : "Gemini AI activo")
                        .font(ImprovingFont.caption(11))
                        .foregroundColor(BevelColors.emeraldEnd)
                }
                Spacer()
                Button { store.startNewCleanChat() } label: {
                    Image(systemName: "square.and.pencil")
                        .foregroundColor(BevelColors.textSecondary)
                }
                Button(action: onOpenSettings) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(BevelColors.textSecondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(BevelColors.card)

            Divider().background(BevelColors.divider)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(store.coachMessages) { msg in
                            HStack {
                                if msg.isUser { Spacer(minLength: 48) }
                                Text(msg.text)
                                    .font(ImprovingFont.body(14))
                                    .foregroundColor(msg.isUser ? .white : BevelColors.textPrimary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .fill(msg.isUser ? BevelColors.emeraldEnd : BevelColors.card)
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
                                    ProgressView().scaleEffect(0.8)
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

            // Suggestion Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { sug in
                        Button {
                            store.sendCoachPrompt(sug)
                        } label: {
                            Text(sug)
                                .font(ImprovingFont.caption(12))
                                .foregroundColor(BevelColors.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(BevelColors.cardSubtle))
                                .overlay(Capsule().strokeBorder(BevelColors.cardBorder, lineWidth: 0.7))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }

            // Input bar
            HStack(spacing: 10) {
                TextField("Pregunta sobre tu recuperación, sueño...", text: $inputText)
                    .font(ImprovingFont.body(14))
                    .foregroundColor(BevelColors.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(BevelColors.card))
                    .overlay(Capsule().strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))

                Button {
                    let q = inputText
                    inputText = ""
                    store.sendCoachPrompt(q)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 34))
                        .foregroundColor(inputText.trimmingCharacters(in: .whitespaces).isEmpty ? BevelColors.textMuted : BevelColors.emeraldEnd)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(BevelColors.canvas)
        }
        .background(BevelColors.canvas)
    }
}

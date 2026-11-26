import SwiftUI
import PhotosUI
import UIKit
import Speech
import AVFoundation

// MARK: - Ask Improving AI Screen (P6 + Apartado 1.4: Long-Term Memory + Voice Dictation + Threads + Photo Attachments!)

struct AskBevelScreen: View {
    @ObservedObject var store: ImprovingStore
    let onClose: () -> Void
    let onOpenSettings: () -> Void

    @State private var inputText: String = ""
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var pendingImage: UIImage? = nil
    @State private var pendingJpegData: Data? = nil
    @State private var showHistorySheet: Bool = false
    @State private var showMemorySheet: Bool = false
    @State private var copiedMessageId: String? = nil
    @StateObject private var speechRecognizer = SpeechDictationController()

    private var hasUserConversation: Bool {
        !store.coachMessages.isEmpty
    }

    var body: some View {
        let userName = store.userProfile.displayFirstName.isEmpty ? "tú" : store.userProfile.displayFirstName
        let hasKey = !store.geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let suggestions = store.dynamicCoachSuggestions

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
                // Top Bar: History + New Chat | Model Status Pill | Close
                HStack(spacing: 8) {
                    Button { showHistorySheet = true } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(BevelColors.textPrimary)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(BevelColors.glassChromeFill))
                                .overlay(Circle().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.8))
                            if !store.coachThreads.isEmpty {
                                Text("\(min(store.coachThreads.count, 99))")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4.5)
                                    .padding(.vertical, 1.5)
                                    .background(Capsule().fill(BevelColors.indigoEnd))
                                    .offset(x: 3, y: -3)
                            }
                        }
                    }

                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        store.startNewCleanChat()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(BevelColors.textPrimary)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(BevelColors.glassChromeFill))
                            .overlay(Circle().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.8))
                    }

                    Button {
                        showMemorySheet = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(BevelColors.skyBlue)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(BevelColors.glassChromeFill))
                                .overlay(Circle().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.8))
                            if !store.coachMemoryNotes.isEmpty {
                                Text("\(min(store.coachMemoryNotes.count, 99))")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4.5)
                                    .padding(.vertical, 1.5)
                                    .background(Capsule().fill(BevelColors.greenPrimary))
                                    .offset(x: 3, y: -3)
                            }
                        }
                    }
                    .accessibilityLabel("Memoria a largo plazo del Coach")

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
                                .lineLimit(1)
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
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(BevelColors.glassChromeFill))
                            .overlay(Circle().strokeBorder(BevelColors.glassChromeBorder, lineWidth: 0.8))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                if !hasUserConversation {
                    VStack(spacing: 18) {
                        Spacer()
                        BevelMascotOrb(size: 92)
                        VStack(spacing: 6) {
                            Text(store.dateLabel)
                                .font(ImprovingFont.caption(14))
                                .foregroundColor(BevelColors.textSecondary)
                            Text(userName == "tú" ? "Hola, ¿qué necesitas?" : "Hola, \(userName).")
                                .font(ImprovingFont.displayLarge(28))
                                .foregroundColor(BevelColors.textPrimary)
                            Text("Pregúntame lo que sea o pídeme registrar y editar comidas, horas, hábitos del diario, entrenos o peso.")
                                .font(ImprovingFont.body(13.5))
                                .foregroundColor(BevelColors.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 34)
                        }
                        Spacer()
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 14) {
                                ForEach(store.coachMessages) { msg in
                                    coachMessageRow(msg)
                                        .id(msg.id)
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

                // Dynamic Data-Aware Suggestion Cards (adapted to today's actual metrics!)
                if !hasUserConversation {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(suggestions) { item in
                                suggestionCard(icon: item.icon, title: item.title, subtitle: item.subtitle) {
                                    store.sendCoachPrompt(item.prompt)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                    }
                }

                if let errBanner = store.lastCoachErrorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(BevelColors.amberStart)
                        Text(errBanner)
                            .font(ImprovingFont.caption(11.5))
                            .foregroundColor(BevelColors.textSecondary)
                            .lineLimit(2)
                        Spacer(minLength: 4)
                        if let lastUser = store.coachMessages.last(where: { $0.isUser })?.text {
                            Button("Reintentar") {
                                store.lastCoachErrorMessage = nil
                                store.sendCoachPrompt(lastUser)
                            }
                            .font(ImprovingFont.caption(11.5))
                            .fontWeight(.bold)
                            .foregroundColor(BevelColors.indigoEnd)
                        }
                        Button {
                            store.lastCoachErrorMessage = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(BevelColors.textMuted)
                                .frame(width: 28, height: 28)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 14).fill(BevelColors.amberSoftBg))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
                }

                // Frosted Glass Open-Ended Multimodal Composer Box
                VStack(alignment: .leading, spacing: 10) {
                    if let img = pendingImage {
                        HStack(spacing: 10) {
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 62, height: 62)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                Button {
                                    pendingImage = nil
                                    pendingJpegData = nil
                                    selectedPhotoItem = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(.white)
                                        .shadow(radius: 3)
                                        .offset(x: 5, y: -5)
                                }
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Imagen adjunta")
                                    .font(ImprovingFont.cardTitle(12.5))
                                    .foregroundColor(BevelColors.textPrimary)
                                Text("Gemini la analizará junto con tus métricas")
                                    .font(ImprovingFont.caption(11))
                                    .foregroundColor(BevelColors.textSecondary)
                            }
                            Spacer()
                        }
                    }

                    TextField("Pregunta a Improving lo que sea", text: $inputText, axis: .vertical)
                        .lineLimit(1...4)
                        .font(ImprovingFont.body(15))
                        .foregroundColor(BevelColors.textPrimary)
                        .onSubmit { sendCurrentInput() }

                    HStack(spacing: 8) {
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                            HStack(spacing: 5) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Foto")
                                    .font(ImprovingFont.caption(12))
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(pendingImage != nil ? BevelColors.greenPrimary : BevelColors.textPrimary)
                            .padding(.horizontal, 11)
                            .frame(height: 34)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                        }

                        Button(action: onOpenSettings) {
                            HStack(spacing: 5) {
                                Image(systemName: "key.fill").font(.system(size: 11))
                                Text(hasKey ? "Gemini activo" : "API Key")
                                    .font(ImprovingFont.caption(12))
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(hasKey ? BevelColors.greenPrimary : BevelColors.textSecondary)
                            .padding(.horizontal, 11)
                            .frame(height: 34)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                        }

                        Button {
                            AppHaptics.selection()
                            speechRecognizer.toggleRecording { transcript in
                                inputText = transcript
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: speechRecognizer.isRecording ? "waveform.circle.fill" : "mic.fill")
                                    .font(.system(size: 12.5, weight: .semibold))
                                Text(speechRecognizer.isRecording ? "Escuchando…" : "Voz")
                                    .font(ImprovingFont.caption(12))
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(speechRecognizer.isRecording ? .white : BevelColors.skyBlue)
                            .padding(.horizontal, 11)
                            .frame(height: 34)
                            .background(Capsule().fill(speechRecognizer.isRecording ? BevelColors.coralHigh : Color.white.opacity(0.08)))
                        }
                        .accessibilityLabel("Dictar por voz")

                        Spacer()

                        if store.isCoachThinking {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                store.cancelCoachReply()
                            } label: {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 40, height: 40)
                                    .background(Circle().fill(BevelColors.coralHigh))
                            }
                            .accessibilityLabel("Detener respuesta")
                        } else {
                            let canSend = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pendingJpegData != nil
                            Button(action: sendCurrentInput) {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(BevelColors.isDarkMode ? .black : .white)
                                    .frame(width: 40, height: 40)
                                    .background(Circle().fill(BevelColors.isDarkMode ? Color.white : BevelColors.floatingDarkButton))
                            }
                            .accessibilityLabel("Enviar mensaje")
                            .disabled(!canSend)
                            .opacity(canSend ? 1.0 : 0.45)
                        }
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
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let rawData = try? await newItem.loadTransferable(type: Data.self),
                   let uiImg = UIImage(data: rawData),
                   let jpg = MealPhotoStorage.prepareJpegData(from: uiImg, maxDimension: 1280, quality: 0.78) {
                    await MainActor.run {
                        pendingImage = uiImg
                        pendingJpegData = jpg
                    }
                }
            }
        }
        .sheet(isPresented: $showHistorySheet) {
            CoachChatHistorySheet(
                store: store,
                onSelect: { id in
                    store.selectCoachThread(id)
                    showHistorySheet = false
                },
                onNewChat: {
                    store.startNewCleanChat()
                    showHistorySheet = false
                },
                onClose: { showHistorySheet = false }
            )
        }
        .sheet(isPresented: $showMemorySheet) {
            CoachLongTermMemorySheet(store: store, onClose: { showMemorySheet = false })
        }
        .onDisappear {
            if speechRecognizer.isRecording {
                speechRecognizer.stopRecording()
            }
        }
    }

    @ViewBuilder
    private func coachMessageRow(_ msg: CoachChatMessage) -> some View {
        if msg.isUser {
            userMessageBubble(msg)
        } else {
            assistantMessageBubble(msg)
        }
    }

    private func userMessageBubble(_ msg: CoachChatMessage) -> some View {
        HStack {
            Spacer(minLength: 44)
            VStack(alignment: .trailing, spacing: 6) {
                if let photoImg = MealPhotoStorage.loadImage(filename: msg.attachedPhotoFilename) {
                    Image(uiImage: photoImg)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 170, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
                        )
                }
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
        }
    }

    private func assistantMessageBubble(_ msg: CoachChatMessage) -> some View {
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

                if !msg.appliedActions.isEmpty {
                    VStack(spacing: 7) {
                        ForEach(msg.appliedActions) { act in
                            appliedActionRow(act, messageId: msg.id)
                        }
                    }
                    .padding(.top, 2)
                }

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

                assistantMessageFooter(msg)
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
    }

    private func appliedActionRow(_ act: CoachAppliedAction, messageId: String) -> some View {
        let tint: Color = act.isUndone ? BevelColors.textMuted : Color(hex: act.badgeColorHex)
        return HStack(spacing: 10) {
            Image(systemName: act.isUndone ? "arrow.uturn.backward.circle" : act.icon)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 28, height: 28)
                .background(Circle().fill(tint.opacity(0.16)))

            VStack(alignment: .leading, spacing: 1.5) {
                Text(act.isUndone ? "\(act.title) · Deshecho" : act.title)
                    .font(ImprovingFont.caption(12))
                    .fontWeight(.bold)
                    .foregroundColor(act.isUndone ? BevelColors.textMuted : BevelColors.textPrimary)
                Text(act.detail)
                    .font(ImprovingFont.caption(11.5))
                    .foregroundColor(BevelColors.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)

            if act.undoPayload != nil {
                if act.isUndone {
                    Text("Deshecho")
                        .font(ImprovingFont.caption(10.5))
                        .fontWeight(.semibold)
                        .foregroundColor(BevelColors.textMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.05)))
                } else {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            store.undoCoachAction(messageId: messageId, actionId: act.id)
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 10, weight: .bold))
                            Text("Deshacer")
                                .font(ImprovingFont.caption(11))
                                .fontWeight(.bold)
                        }
                        .foregroundColor(BevelColors.textPrimary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.7))
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(BevelColors.cardSubtle))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(tint.opacity(act.isUndone ? 0.14 : 0.32), lineWidth: 0.8)
        )
    }

    private func assistantMessageFooter(_ msg: CoachChatMessage) -> some View {
        let isCopied = copiedMessageId == msg.id
        return HStack(spacing: 8) {
            if let model = msg.modelUsed, !model.isEmpty {
                Text("\(msg.timestampLabel) · \(model)")
                    .font(ImprovingFont.caption(10.5))
                    .foregroundColor(BevelColors.textMuted)
            } else {
                Text(msg.timestampLabel)
                    .font(ImprovingFont.caption(10.5))
                    .foregroundColor(BevelColors.textMuted)
            }
            Spacer()
            Button {
                var full = msg.text
                if !msg.bullets.isEmpty {
                    full += "\n" + msg.bullets.map { "• \($0)" }.joined(separator: "\n")
                }
                UIPasteboard.general.string = full
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.easeInOut(duration: 0.2)) {
                    copiedMessageId = msg.id
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    if copiedMessageId == msg.id {
                        withAnimation(.easeOut(duration: 0.2)) {
                            copiedMessageId = nil
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10.5, weight: .semibold))
                    Text(isCopied ? "Copiado" : "Copiar")
                        .font(ImprovingFont.caption(10.5))
                        .fontWeight(.semibold)
                }
                .foregroundColor(isCopied ? BevelColors.greenPrimary : BevelColors.textMuted)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.06)))
            }
        }
        .padding(.top, 2)
    }

    private func sendCurrentInput() {
        let q = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!q.isEmpty || pendingJpegData != nil), !store.isCoachThinking else { return }
        let jpg = pendingJpegData
        let savedName = jpg.flatMap { MealPhotoStorage.savePhotoData($0) }
        inputText = ""
        pendingImage = nil
        pendingJpegData = nil
        selectedPhotoItem = nil
        store.sendCoachPrompt(q, jpegImageData: jpg, attachedPhotoFilename: savedName)
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

private struct CoachChatHistorySheet: View {
    @ObservedObject var store: ImprovingStore
    let onSelect: (String) -> Void
    let onNewChat: () -> Void
    let onClose: () -> Void
    @State private var pendingDeleteThread: CoachChatThread? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Button(action: onNewChat) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.bubble.fill")
                            Text("Nueva conversación")
                                .font(ImprovingFont.cardTitle(14.5))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Capsule().fill(BevelColors.indigoEnd))
                    }

                    if store.coachThreads.isEmpty {
                        BevelCard(cornerRadius: 18) {
                            Text("Tus conversaciones con el Coach IA se guardarán automáticamente aquí para que puedas retomarlas cuando quieras.")
                                .font(ImprovingFont.body(13.5))
                                .foregroundColor(BevelColors.textSecondary)
                                .padding(16)
                        }
                    } else {
                        ForEach(store.coachThreads) { thread in
                            let isActive = store.activeCoachThreadId == thread.id
                            BevelCard(cornerRadius: 18) {
                                HStack(spacing: 12) {
                                    Button { onSelect(thread.id) } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(spacing: 6) {
                                                if isActive {
                                                    Circle().fill(BevelColors.greenPrimary).frame(width: 7, height: 7)
                                                }
                                                Text(thread.title)
                                                    .font(ImprovingFont.cardTitle(14.5))
                                                    .foregroundColor(BevelColors.textPrimary)
                                                    .lineLimit(1)
                                            }
                                            Text("\(thread.dateIso) · \(thread.updatedAtLabel) · \(thread.messages.count) mensajes")
                                                .font(ImprovingFont.caption(12))
                                                .foregroundColor(BevelColors.textSecondary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        pendingDeleteThread = thread
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 13.5))
                                            .foregroundColor(BevelColors.textMuted)
                                            .frame(width: 44, height: 44)
                                    }
                                    .accessibilityLabel("Eliminar conversación")
                                }
                                .padding(14)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(BevelColors.canvas)
            .navigationTitle("Historial Coach IA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar", action: onClose)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .confirmationDialog(
            "¿Eliminar esta conversación?",
            isPresented: Binding(
                get: { pendingDeleteThread != nil },
                set: { if !$0 { pendingDeleteThread = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Eliminar conversación", role: .destructive) {
                if let t = pendingDeleteThread {
                    store.deleteCoachThread(t.id)
                }
                pendingDeleteThread = nil
            }
            Button("Cancelar", role: .cancel) { pendingDeleteThread = nil }
        } message: {
            Text("Se eliminará permanentemente «\(pendingDeleteThread?.title ?? "")».")
        }
    }
}

// MARK: - Long-Term Coach Memory Sheet & Native iOS Speech Dictation Controller (Apartado 1.4)

struct CoachLongTermMemorySheet: View {
    @ObservedObject var store: ImprovingStore
    let onClose: () -> Void
    @State private var draftNote: String = ""

    private let quickTemplates = [
        "Entreno fuerza 4 días/semana por la mañana",
        "Objetivo: bajar grasa manteniendo masa muscular",
        "Molestia ocasional en hombro derecho al hacer press",
        "Evito lactosa y cenas después de las 21:00",
        "Priorizo ≥150 min/semana de Zona 2 y longevidad"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    BevelCard(cornerRadius: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "brain.head.profile")
                                    .foregroundColor(BevelColors.skyBlue)
                                Text("MEMORIA PERMANENTE DEL COACH IA")
                                    .font(ImprovingFont.microLabel(10))
                                    .foregroundColor(BevelColors.textMuted)
                            }
                            Text("Todo lo que guardes aquí (lesiones, objetivos deportivos, alergias, horarios) se recuerda en cada conversación y ajusta las recomendaciones diarias.")
                                .font(ImprovingFont.caption(12.5))
                                .foregroundColor(BevelColors.textSecondary)

                            HStack(spacing: 8) {
                                TextField("Ej. Prepara media maratón en noviembre…", text: $draftNote)
                                    .font(ImprovingFont.body(13.5))
                                    .foregroundColor(BevelColors.textPrimary)
                                    .padding(10)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.cardSubtle))
                                Button {
                                    store.addCoachMemoryNote(draftNote)
                                    draftNote = ""
                                    AppHaptics.selection()
                                } label: {
                                    Text("Añadir")
                                        .font(ImprovingFont.caption(12.5))
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 13)
                                        .padding(.vertical, 10)
                                        .background(RoundedRectangle(cornerRadius: 10).fill(BevelColors.indigoEnd))
                                }
                                .disabled(draftNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                        .padding(14)
                    }

                    Text("Sugerencias rápidas")
                        .font(ImprovingFont.caption(12))
                        .foregroundColor(BevelColors.textMuted)

                    ForEach(quickTemplates, id: \.self) { tpl in
                        if !store.coachMemoryNotes.contains(tpl) {
                            Button {
                                store.addCoachMemoryNote(tpl)
                                AppHaptics.selection()
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(BevelColors.skyBlue)
                                    Text(tpl)
                                        .font(ImprovingFont.caption(12.5))
                                        .foregroundColor(BevelColors.textPrimary)
                                    Spacer()
                                }
                                .padding(11)
                                .background(RoundedRectangle(cornerRadius: 12).fill(BevelColors.card))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text("Recuerdos activos (\(store.coachMemoryNotes.count))")
                        .font(ImprovingFont.sectionTitle(16))
                        .foregroundColor(BevelColors.textPrimary)
                        .padding(.top, 6)

                    if store.coachMemoryNotes.isEmpty {
                        BevelCard(cornerRadius: 16) {
                            Text("Todavía no has guardado notas permanentes en la memoria del Coach.")
                                .font(ImprovingFont.caption(12.5))
                                .foregroundColor(BevelColors.textSecondary)
                                .padding(14)
                        }
                    } else {
                        ForEach(Array(store.coachMemoryNotes.enumerated()), id: \.offset) { idx, note in
                            BevelCard(cornerRadius: 16) {
                                HStack {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundColor(BevelColors.greenPrimary)
                                    Text(note)
                                        .font(ImprovingFont.body(13.5))
                                        .foregroundColor(BevelColors.textPrimary)
                                    Spacer()
                                    Button {
                                        store.removeCoachMemoryNote(at: idx)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 13))
                                            .foregroundColor(BevelColors.coralHigh)
                                    }
                                }
                                .padding(13)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(BevelColors.canvas)
            .navigationTitle("Memoria del Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar", action: onClose)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

final class SpeechDictationController: ObservableObject {
    @Published var isRecording: Bool = false
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "es-ES"))

    func toggleRecording(onTranscript: @escaping (String) -> Void) {
        if isRecording {
            stopRecording()
            return
        }
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard status == .authorized else { return }
            DispatchQueue.main.async {
                self?.startSession(onTranscript: onTranscript)
            }
        }
    }

    private func startSession(onTranscript: @escaping (String) -> Void) {
        stopRecording()
        let session = AVAudioSession.sharedInstance()
        guard (try? session.setCategory(.record, mode: .measurement, options: .duckOthers)) != nil,
              (try? session.setActive(true, options: .notifyOthersOnDeactivation)) != nil else {
            return
        }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        self.recognitionRequest = req

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer)
        }
        audioEngine.prepare()
        guard (try? audioEngine.start()) != nil else {
            inputNode.removeTap(onBus: 0)
            return
        }
        isRecording = true
        recognitionTask = speechRecognizer?.recognitionTask(with: req) { [weak self] result, error in
            if let r = result {
                let text = r.bestTranscription.formattedString
                DispatchQueue.main.async {
                    onTranscript(text)
                }
            }
            if error != nil || (result?.isFinal == true) {
                DispatchQueue.main.async {
                    self?.stopRecording()
                }
            }
        }
    }

    func stopRecording() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

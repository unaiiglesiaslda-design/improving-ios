import SwiftUI
import PhotosUI
import UIKit

// MARK: - 5-Step High-Craft Motion Graphics Onboarding + Full Physiological Profile & Photo Setup

private struct OnboardingStorySlide: Identifiable {
    let id: Int
    let imageName: String
    let eyebrow: String
    let eyebrowBg: Color
    let eyebrowColor: Color
    let title: String
    let subtitle: String
    let floatingBadges: [(String, String)]
    let highlights: [String]
}

struct OnboardingExperienceView: View {
    let initialProfile: UserPhysiologyProfile
    var onConnectAppleHealth: (() -> Void)? = nil
    let onFinish: (UserPhysiologyProfile) -> Void

    @State private var currentStep: Int = 0 // 0,1,2 = Motion Graphics Story, 3 = Sensors/Privacy, 4 = Personal Profile & Photo
    @State private var draftProfile: UserPhysiologyProfile
    @State private var birthDateDraft: Date
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var savingPhoto: Bool = false
    @State private var healthConnectTapped: Bool = false
    @State private var movingForward: Bool = true

    private let totalSteps = 5

    init(
        initialProfile: UserPhysiologyProfile = UserPhysiologyProfile(),
        onConnectAppleHealth: (() -> Void)? = nil,
        onFinish: @escaping (UserPhysiologyProfile) -> Void
    ) {
        self.initialProfile = initialProfile
        self.onConnectAppleHealth = onConnectAppleHealth
        self.onFinish = onFinish
        _draftProfile = State(initialValue: initialProfile)
        _birthDateDraft = State(initialValue: initialProfile.birthDate)
    }

    private var slides: [OnboardingStorySlide] {
        [
            OnboardingStorySlide(
                id: 0,
                imageName: "onboarding_wearable",
                eyebrow: "BIOMETRÍA EN TIEMPO REAL",
                eyebrowBg: BevelColors.greenSoftBg,
                eyebrowColor: BevelColors.emeraldEnd,
                title: "Entiende tu cuerpo al milímetro",
                subtitle: "Analiza tu VFC RMSSD durante todo el sueño, frecuencia en reposo, esfuerzo y recuperación real — sincronizado con Apple Salud, Atajos o WHOOP BLE sin inventar datos.",
                floatingBadges: [
                    ("VFC RMSSD", "78 ms"),
                    ("Recuperación", "91%"),
                    ("Sensores", "En vivo")
                ],
                highlights: [
                    "Cálculo RMSSD durante todo el sueño (estilo Bevel / WHOOP)",
                    "Histórico navegable de 7 días hasta 1 año completo",
                    "Sincronización automática en segundo plano sin datos falsos"
                ]
            ),
            OnboardingStorySlide(
                id: 1,
                imageName: "onboarding_sleep",
                eyebrow: "SUEÑO Y LONGEVIDAD",
                eyebrowBg: BevelColors.indigoSoftBg,
                eyebrowColor: BevelColors.indigoEnd,
                title: "Duerme mejor, vive más joven",
                subtitle: "Calculamos tu necesidad exacta de descanso, tus fases Profundo y REM, tu batería de energía hora a hora y tu Edad Biológica real adaptada a tu fecha de nacimiento.",
                floatingBadges: [
                    ("Sueño", "8h 12m"),
                    ("Batería", "94%"),
                    ("Edad Bio", "−2,1 años")
                ],
                highlights: [
                    "Objetivo de sueño y sueño profundo ajustado a tu edad",
                    "Curva continua de estrés y energía 24 h sin saltos",
                    "Edad Biológica calibrada contra los rangos de tu generación"
                ]
            ),
            OnboardingStorySlide(
                id: 2,
                imageName: "onboarding_nutrition",
                eyebrow: "PERSONALIZACIÓN TOTAL",
                eyebrowBg: BevelColors.amberSoftBg,
                eyebrowColor: BevelColors.orangeEnd,
                title: "Cada métrica adaptada a tu cuerpo",
                subtitle: "Tu edad, sexo, altura y peso calibran automáticamente tu FC máxima Tanaka, zonas de esfuerzo, recuperación, sueño, calorías, hidratación, cafeína y Coach IA.",
                floatingBadges: [
                    ("Zonas FC", "Tanaka"),
                    ("Hidratación", "Por peso"),
                    ("Coach IA", "A medida")
                ],
                highlights: [
                    "Esfuerzo, recuperación y sueño adaptados a joven o mayor",
                    "Macros, agua y límite de cafeína por edad, sexo y talla",
                    "Asistente IA que razona sobre tu perfil y lecturas reales"
                ]
            )
        ]
    }

    var body: some View {
        ZStack {
            BevelColors.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                topProgressBar

                ZStack {
                    switch currentStep {
                    case 0, 1, 2:
                        MotionStorySlideView(
                            slide: slides[currentStep],
                            onNext: { goToStep(currentStep + 1) }
                        )
                        .id("story_\(currentStep)")
                        .transition(stepTransition)
                    case 3:
                        SensorsAndPrivacyStepView(
                            healthTapped: healthConnectTapped,
                            onConnectHealth: {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                healthConnectTapped = true
                                onConnectAppleHealth?()
                            },
                            onContinue: { goToStep(4) }
                        )
                        .id("sensors_step")
                        .transition(stepTransition)
                    default:
                        ProfileCalibrationStepView(
                            profile: $draftProfile,
                            birthDate: $birthDateDraft,
                            selectedPhotoItem: $selectedPhotoItem,
                            savingPhoto: savingPhoto,
                            onRemovePhoto: {
                                ProfilePhotoStorage.deleteSavedPhotos()
                                draftProfile.profilePhotoPath = nil
                            },
                            onComplete: {
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                var finalProfile = draftProfile
                                finalProfile.userName = draftProfile.userName.trimmingCharacters(in: .whitespacesAndNewlines)
                                finalProfile.lastName = draftProfile.lastName.trimmingCharacters(in: .whitespacesAndNewlines)
                                finalProfile.setBirthDate(birthDateDraft)
                                finalProfile.profileSetupVersion = 2
                                finalProfile.onboardingCompleted = true
                                onFinish(finalProfile)
                            }
                        )
                        .id("profile_step")
                        .transition(stepTransition)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.spring(response: 0.42, dampingFraction: 0.86), value: currentStep)
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let item = newItem else { return }
            savingPhoto = true
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let savedName = ProfilePhotoStorage.savePickedImageData(data) {
                    await MainActor.run {
                        draftProfile.profilePhotoPath = savedName
                        savingPhoto = false
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                } else {
                    await MainActor.run { savingPhoto = false }
                }
            }
        }
        .onChange(of: birthDateDraft) { _, newDate in
            draftProfile.setBirthDate(newDate)
        }
    }

    private var stepTransition: AnyTransition {
        let enterEdge: Edge = movingForward ? .trailing : .leading
        let exitEdge: Edge = movingForward ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: enterEdge).combined(with: .opacity).combined(with: .scale(scale: 0.97)),
            removal: .move(edge: exitEdge).combined(with: .opacity)
        )
    }

    private func goToStep(_ next: Int) {
        let clamped = min(max(next, 0), totalSteps - 1)
        movingForward = clamped >= currentStep
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            currentStep = clamped
        }
    }

    private var topProgressBar: some View {
        HStack(spacing: 10) {
            if currentStep > 0 {
                Button { goToStep(currentStep - 1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(BevelColors.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(BevelColors.card))
                        .overlay(Circle().strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
                }
            } else {
                Spacer().frame(width: 36, height: 36)
            }

            // Animated 5-segment progress indicator
            HStack(spacing: 6) {
                ForEach(0..<totalSteps, id: \.self) { idx in
                    let isCurrent = idx == currentStep
                    let isDone = idx < currentStep
                    Capsule()
                        .fill(isCurrent ? BevelColors.textPrimary : (isDone ? BevelColors.greenPrimary : BevelColors.trackGroove))
                        .frame(height: 4.5)
                        .frame(maxWidth: isCurrent ? .infinity : .infinity)
                        .scaleEffect(x: 1.0, y: isCurrent ? 1.18 : 1.0)
                        .animation(.spring(response: 0.35, dampingFraction: 0.78), value: currentStep)
                }
            }
            .frame(maxWidth: .infinity)

            if currentStep < 4 {
                Button { goToStep(4) } label: {
                    Text("Saltar")
                        .font(ImprovingFont.caption(12.5))
                        .fontWeight(.semibold)
                        .foregroundColor(BevelColors.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
            } else {
                Spacer().frame(width: 48)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
}

// MARK: - Slides 0, 1, 2: Motion Graphics Hero + Ken Burns + Live Canvas Telemetry Overlay

private struct MotionStorySlideView: View {
    let slide: OnboardingStorySlide
    let onNext: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var kenBurnsActive: Bool = false
    @State private var badgeFloat: Bool = false
    @State private var entered: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    // Editorial Motion Graphics Hero Frame
                    ZStack {
                        if let path = Bundle.main.path(forResource: slide.imageName, ofType: "jpg"),
                           let uiImg = UIImage(contentsOfFile: path) {
                            Image(uiImage: uiImg)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .scaleEffect(reduceMotion ? 1.0 : (kenBurnsActive ? 1.09 : 1.01))
                                .offset(x: reduceMotion ? 0 : (kenBurnsActive ? 10 : -10))
                                .animation(.easeInOut(duration: 7.5).repeatForever(autoreverses: true), value: kenBurnsActive)
                        } else {
                            LinearGradient(
                                colors: [Color(hex: 0x162420), Color(hex: 0x101828)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }

                        // Cinematic vignette for crisp telemetry legibility
                        LinearGradient(
                            colors: [Color.black.opacity(0.18), Color.clear, Color.black.opacity(0.68)],
                            startPoint: .top,
                            endPoint: .bottom
                        )

                        // Live 60fps Motion Graphics Telemetry HUD Layer
                        if !reduceMotion {
                            OnboardingSlideMotionGraphicHUD(slideId: slide.id, accentColor: slide.eyebrowColor)
                        }

                        // Top-left frosted eyebrow badge
                        VStack {
                            HStack {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(slide.eyebrowColor)
                                        .frame(width: 7, height: 7)
                                    Text(slide.eyebrow)
                                        .font(ImprovingFont.microLabel(9.5))
                                        .fontWeight(.bold)
                                        .foregroundColor(Color(hex: 0x0F172A))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.white.opacity(0.92)))
                                .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
                                Spacer()
                            }
                            .padding(14)
                            .opacity(entered ? 1 : 0)
                            .offset(y: entered ? 0 : -12)

                            Spacer()

                            // Bottom floating frosted metric pills
                            HStack(spacing: 8) {
                                ForEach(Array(slide.floatingBadges.enumerated()), id: \.offset) { _, pair in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(pair.0.uppercased(with: Locale(identifier: "es_ES")))
                                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                                            .foregroundColor(Color(hex: 0x475569))
                                            .lineLimit(1)
                                        Text(pair.1)
                                            .font(.system(size: 13.5, weight: .heavy, design: .rounded))
                                            .foregroundColor(Color(hex: 0x0F172A))
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color.white.opacity(0.92)))
                                    .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Color.white, lineWidth: 0.8))
                                }
                            }
                            .padding(12)
                            .opacity(entered ? 1 : 0)
                            .offset(y: (entered ? 0 : 18) + (reduceMotion ? 0 : (badgeFloat ? -3 : 3)))
                            .animation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true), value: badgeFloat)
                        }
                    }
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: Color.black.opacity(0.16), radius: 16, y: 8)

                    // Editorial Headline & Subtitle
                    VStack(alignment: .leading, spacing: 8) {
                        Text(slide.title)
                            .font(.system(size: 27, weight: .heavy, design: .rounded))
                            .foregroundColor(BevelColors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(slide.subtitle)
                            .font(ImprovingFont.body(14.5))
                            .foregroundColor(BevelColors.textSecondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .opacity(entered ? 1 : 0)
                    .offset(y: entered ? 0 : 12)

                    // Feature Checklist
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(slide.highlights.enumerated()), id: \.offset) { idx, item in
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(slide.eyebrowColor)
                                    .frame(width: 22, height: 22)
                                    .background(Circle().fill(slide.eyebrowBg))
                                Text(item)
                                    .font(ImprovingFont.body(13.5))
                                    .fontWeight(.medium)
                                    .foregroundColor(BevelColors.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .opacity(entered ? 1 : 0)
                            .offset(y: entered ? 0 : CGFloat(10 + idx * 6))
                        }
                    }
                    .padding(.bottom, 10)
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
            }

            // Primary Tactile CTA
            OnboardingPrimaryCTA(title: "Continuar", systemImage: "arrow.right", action: onNext)
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 18)
        }
        .onAppear {
            kenBurnsActive = true
            badgeFloat = true
            withAnimation(.spring(response: 0.52, dampingFraction: 0.84).delay(0.06)) {
                entered = true
            }
        }
    }
}

/// Real-time 60fps procedural vector motion graphics overlaid on each onboarding hero card:
/// - Slide 0: Animated live ECG / PPG biometric pulse trace + sweeping recovery halo
/// - Slide 1: Animated nocturnal sleep-stage hypnogram + glowing recharge energy wave
/// - Slide 2: Orbiting physiological calibration rings reacting to age, sex, height & weight
private struct OnboardingSlideMotionGraphicHUD: View {
    let slideId: Int
    let accentColor: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, sz in
                let w = sz.width
                let h = sz.height

                switch slideId {
                case 0:
                    // Live glowing ECG / HRV pulse trace sweeping horizontally across upper-mid hero
                    let baseY = h * 0.48
                    let phase = t * 1.45
                    var path = Path()
                    let steps = 90
                    for i in 0...steps {
                        let u = Double(i) / Double(steps)
                        let x = CGFloat(u) * w
                        let local = (u * 2.4 - phase).truncatingRemainder(dividingBy: 1.0)
                        let norm = local < 0 ? local + 1.0 : local
                        let amp: Double
                        if norm > 0.38 && norm < 0.43 {
                            amp = sin((norm - 0.38) / 0.05 * .pi) * 9.0
                        } else if norm >= 0.46 && norm < 0.49 {
                            amp = -12.0 * sin((norm - 0.46) / 0.03 * .pi)
                        } else if norm >= 0.49 && norm < 0.54 {
                            amp = 36.0 * sin((norm - 0.49) / 0.05 * .pi)
                        } else if norm >= 0.54 && norm < 0.58 {
                            amp = -16.0 * sin((norm - 0.54) / 0.04 * .pi)
                        } else if norm >= 0.63 && norm < 0.72 {
                            amp = 11.0 * sin((norm - 0.63) / 0.09 * .pi)
                        } else {
                            amp = sin(u * 14.0 + phase * 3.0) * 1.6
                        }
                        let pt = CGPoint(x: x, y: baseY - CGFloat(amp))
                        if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                    }
                    ctx.stroke(path, with: .color(Color(hex: 0x4ADE80).opacity(0.28)), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                    ctx.stroke(path, with: .color(Color(hex: 0x4ADE80).opacity(0.92)), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))

                    // Sweeping orbital recovery ring on top-right
                    let ringCenter = CGPoint(x: w - 48, y: 48)
                    let ringR: CGFloat = 22
                    var bgRing = Path()
                    bgRing.addEllipse(in: CGRect(x: ringCenter.x - ringR, y: ringCenter.y - ringR, width: ringR * 2, height: ringR * 2))
                    ctx.stroke(bgRing, with: .color(Color.white.opacity(0.22)), lineWidth: 4.5)
                    let sweep = 210.0 + sin(t * 1.4) * 55.0
                    var fgRing = Path()
                    fgRing.addArc(center: ringCenter, radius: ringR, startAngle: .degrees(-90 + t * 25), endAngle: .degrees(-90 + t * 25 + sweep), clockwise: false)
                    ctx.stroke(fgRing, with: .color(Color(hex: 0x4ADE80)), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))

                case 1:
                    // Smooth flowing Sleep / Energy recharge wave across center
                    let baseY = h * 0.52
                    var energyPath = Path()
                    var sleepPath = Path()
                    let steps = 70
                    for i in 0...steps {
                        let u = Double(i) / Double(steps)
                        let x = CGFloat(u) * w
                        let yEnergy = baseY + CGFloat(sin(u * 5.2 - t * 1.3) * 18.0 - u * 16.0)
                        let ySleep = baseY + 14 + CGFloat(cos(u * 7.0 - t * 1.0) * 11.0)
                        if i == 0 {
                            energyPath.move(to: CGPoint(x: x, y: yEnergy))
                            sleepPath.move(to: CGPoint(x: x, y: ySleep))
                        } else {
                            energyPath.addLine(to: CGPoint(x: x, y: yEnergy))
                            sleepPath.addLine(to: CGPoint(x: x, y: ySleep))
                        }
                    }
                    ctx.stroke(sleepPath, with: .color(Color(hex: 0x818CF8).opacity(0.55)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    ctx.stroke(energyPath, with: .color(Color(hex: 0x38BDF8).opacity(0.30)), style: StrokeStyle(lineWidth: 7.5, lineCap: .round))
                    ctx.stroke(energyPath, with: .color(Color(hex: 0x38BDF8).opacity(0.92)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

                    // Pulsing nocturnal moon halo top-right
                    let c = CGPoint(x: w - 46, y: 46)
                    let pulse = CGFloat(1.0 + 0.18 * sin(t * 2.0))
                    let r = 20 * pulse
                    var halo = Path()
                    halo.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                    ctx.stroke(halo, with: .color(Color(hex: 0xA5B4FC).opacity(0.65)), lineWidth: 2.0)

                default:
                    // Concentric calibrating physiology rings (Age / Sex / Height / Weight)
                    let center = CGPoint(x: w * 0.5, y: h * 0.45)
                    let colors: [Color] = [Color(hex: 0x4ADE80), Color(hex: 0x38BDF8), Color(hex: 0xFBBF24)]
                    for idx in 0..<3 {
                        let radius = CGFloat(34 + idx * 17)
                        let rot = t * (idx % 2 == 0 ? 32.0 : -24.0) + Double(idx) * 90.0
                        var arc = Path()
                        arc.addArc(center: center, radius: radius, startAngle: .degrees(rot), endAngle: .degrees(rot + 135.0), clockwise: false)
                        ctx.stroke(arc, with: .color(colors[idx].opacity(0.82)), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Slide 3: Sensors & Privacy Step

private struct SensorsAndPrivacyStepView: View {
    let healthTapped: Bool
    let onConnectHealth: () -> Void
    let onContinue: () -> Void

    @State private var pulseShield: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 15) {
                    HStack(spacing: 14) {
                        Image(systemName: healthTapped ? "checkmark.shield.fill" : "shield.lefthalf.filled")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(healthTapped ? BevelColors.emeraldEnd : BevelColors.indigoEnd)
                            .frame(width: 56, height: 56)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(healthTapped ? BevelColors.greenSoftBg : BevelColors.indigoSoftBg))
                            .scaleEffect(pulseShield ? 1.06 : 1.0)
                            .animation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true), value: pulseShield)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("SENSORES Y PRIVACIDAD")
                                .font(ImprovingFont.microLabel(10.5))
                                .fontWeight(.bold)
                                .foregroundColor(healthTapped ? BevelColors.emeraldEnd : BevelColors.indigoEnd)
                            Text("Conecta tus datos reales")
                                .font(.system(size: 23, weight: .heavy, design: .rounded))
                                .foregroundColor(BevelColors.textPrimary)
                        }
                    }

                    Text("Tus métricas biométricas se procesan localmente en tu iPhone. Puedes sincronizar desde Apple Salud, Atajos en segundo plano o tu pulsera WHOOP BLE en cualquier momento.")
                        .font(ImprovingFont.body(13.5))
                        .foregroundColor(BevelColors.textSecondary)
                        .lineSpacing(2)

                    sensorFeatureCard(
                        icon: "heart.text.square.fill",
                        tint: BevelColors.redAlert,
                        softBg: BevelColors.redAlert.opacity(0.14),
                        title: "Apple Salud y exportar.zip",
                        subtitle: "Lee sueño real, VFC latido a latido (RMSSD), FC nocturna y entrenamientos.",
                        badge: healthTapped ? "Solicitado" : "Conectar",
                        active: healthTapped,
                        action: onConnectHealth
                    )

                    sensorFeatureCard(
                        icon: "bolt.badge.automatic.fill",
                        tint: BevelColors.skyBlue,
                        softBg: BevelColors.skySoftBg,
                        title: "Atajos en Segundo Plano",
                        subtitle: "Sincronización automática sin cuenta Apple Developer y sin salir de Improving.",
                        badge: "Incluido",
                        active: true,
                        action: onContinue
                    )

                    sensorFeatureCard(
                        icon: "wave.3.right.circle.fill",
                        tint: BevelColors.periwinkleStart,
                        softBg: BevelColors.indigoSoftBg,
                        title: "WHOOP 4.0 / 5.0 Bluetooth",
                        subtitle: "Conexión BLE directa en tiempo real desde Dispositivos y Ajustes.",
                        badge: "Listo",
                        active: true,
                        action: onContinue
                    )

                    HStack(spacing: 10) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 16))
                            .foregroundColor(BevelColors.emeraldEnd)
                        Text("Cero datos inventados: tus métricas se guardan únicamente en tu iPhone y puedes editar todo luego en Ajustes.")
                            .font(ImprovingFont.caption(11.5))
                            .foregroundColor(BevelColors.textSecondary)
                    }
                    .padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BevelColors.card))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
            }

            OnboardingPrimaryCTA(title: "Configurar mi perfil", systemImage: "arrow.right", action: onContinue)
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 18)
        }
        .onAppear { pulseShield = true }
    }

    private func sensorFeatureCard(
        icon: String,
        tint: Color,
        softBg: Color,
        title: String,
        subtitle: String,
        badge: String,
        active: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            BevelCard(cornerRadius: 20) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(tint)
                        .frame(width: 44, height: 44)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(softBg))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(ImprovingFont.cardTitle(14.5))
                            .foregroundColor(BevelColors.textPrimary)
                        Text(subtitle)
                            .font(ImprovingFont.caption(11.5))
                            .foregroundColor(BevelColors.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 4)
                    Text(badge)
                        .font(ImprovingFont.microLabel(10))
                        .fontWeight(.bold)
                        .foregroundColor(active ? .white : BevelColors.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(active ? BevelColors.greenPrimary : BevelColors.cardSubtle))
                }
                .padding(14)
            }
        }
    }
}

// MARK: - Slide 4: Full Personal Profile (Nombre, Apellido, Fecha, Sexo, Altura, Peso, Foto) + Live Norms Preview

private struct ProfileCalibrationStepView: View {
    @Binding var profile: UserPhysiologyProfile
    @Binding var birthDate: Date
    @Binding var selectedPhotoItem: PhotosPickerItem?
    let savingPhoto: Bool
    let onRemovePhoto: () -> Void
    let onComplete: () -> Void

    private var minBirthDate: Date {
        Calendar.current.date(byAdding: .year, value: -95, to: Date()) ?? Date()
    }
    private var maxBirthDate: Date {
        Calendar.current.date(byAdding: .year, value: -13, to: Date()) ?? Date()
    }

    var body: some View {
        let norms = WhoopPhysiologyEngine.computePersonalizedNorms(profile: profile)
        let exactAge = Int(profile.effectiveAgeYears.rounded(.down))
        let sleepH = Int(norms.sleepTargetHours)
        let sleepM = Int(((norms.sleepTargetHours - Double(sleepH)) * 60.0).rounded())

        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 15) {
                    VStack(spacing: 4) {
                        Text("ÚLTIMO PASO · TU PERFIL FISIOLÓGICO")
                            .font(ImprovingFont.microLabel(10.5))
                            .fontWeight(.bold)
                            .foregroundColor(BevelColors.emeraldEnd)
                        Text("Hazlo 100 % tuyo")
                            .font(.system(size: 25, weight: .heavy, design: .rounded))
                            .foregroundColor(BevelColors.textPrimary)
                        Text("Tu edad, sexo, altura y peso calibran al instante recuperación, esfuerzo, sueño y todos tus rangos.")
                            .font(ImprovingFont.caption(12.5))
                            .foregroundColor(BevelColors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 2)

                    // Interactive Profile Photo Picker with luminous ring & camera badge
                    VStack(spacing: 8) {
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                            ZStack(alignment: .bottomTrailing) {
                                UserProfileAvatarView(
                                    photoPath: profile.profilePhotoPath,
                                    initials: profile.initials,
                                    size: 98,
                                    showGradientRing: true,
                                    ringWidth: 3.0
                                )
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(BevelColors.textPrimary))
                                    .overlay(Circle().strokeBorder(BevelColors.canvas, lineWidth: 2.2))
                                    .offset(x: 2, y: 2)
                            }
                        }

                        HStack(spacing: 8) {
                            PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                                Text(savingPhoto ? "Guardando foto…" : (profile.profilePhotoPath != nil ? "Cambiar foto" : "Añadir foto de perfil"))
                                    .font(ImprovingFont.caption(11.5))
                                    .fontWeight(.semibold)
                                    .foregroundColor(BevelColors.textPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(BevelColors.card))
                                    .overlay(Capsule().strokeBorder(BevelColors.cardBorder, lineWidth: 0.8))
                            }

                            if profile.profilePhotoPath != nil {
                                Button(action: onRemovePhoto) {
                                    HStack(spacing: 3) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 10, weight: .bold))
                                        Text("Quitar")
                                            .font(ImprovingFont.caption(11))
                                    }
                                    .foregroundColor(BevelColors.textSecondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(BevelColors.cardSubtle))
                                }
                            }
                        }
                    }

                    // Personal Data Card: Nombre, Apellido, Fecha de nacimiento, Sexo, Altura, Peso
                    BevelCard(cornerRadius: 22) {
                        VStack(spacing: 13) {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Nombre")
                                        .font(ImprovingFont.caption(11))
                                        .foregroundColor(BevelColors.textSecondary)
                                    TextField("Ej. Aitor", text: $profile.userName)
                                        .font(ImprovingFont.body(14.5))
                                        .foregroundColor(BevelColors.textPrimary)
                                        .textInputAutocapitalization(.words)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .background(RoundedRectangle(cornerRadius: 12).fill(BevelColors.cardSubtle))
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Apellido")
                                        .font(ImprovingFont.caption(11))
                                        .foregroundColor(BevelColors.textSecondary)
                                    TextField("Ej. Iglesias", text: $profile.lastName)
                                        .font(ImprovingFont.body(14.5))
                                        .foregroundColor(BevelColors.textPrimary)
                                        .textInputAutocapitalization(.words)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .background(RoundedRectangle(cornerRadius: 12).fill(BevelColors.cardSubtle))
                                }
                            }

                            // Birth Date Picker with live computed age badge
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Fecha de nacimiento")
                                        .font(ImprovingFont.cardTitle(13.5))
                                        .foregroundColor(BevelColors.textPrimary)
                                    Text("\(exactAge) años · Calibra tu fisiología")
                                        .font(ImprovingFont.caption(11))
                                        .foregroundColor(BevelColors.emeraldEnd)
                                }
                                Spacer()
                                DatePicker(
                                    "",
                                    selection: $birthDate,
                                    in: minBirthDate...maxBirthDate,
                                    displayedComponents: .date
                                )
                                .labelsHidden()
                                .environment(\.locale, Locale(identifier: "es_ES"))
                            }
                            .padding(.vertical, 2)

                            Divider().background(BevelColors.divider)

                            // Sex Segmented Pills
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Sexo biológico")
                                    .font(ImprovingFont.caption(11.5))
                                    .foregroundColor(BevelColors.textSecondary)
                                HStack(spacing: 8) {
                                    ForEach(BiologicalSexOption.allCases, id: \.self) { opt in
                                        let active = profile.sex == opt
                                        Button {
                                            UISelectionFeedbackGenerator().selectionChanged()
                                            profile.sex = opt
                                        } label: {
                                            Text(opt.rawValue)
                                                .font(ImprovingFont.caption(12))
                                                .fontWeight(.semibold)
                                                .foregroundColor(active ? .white : BevelColors.textSecondary)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 9)
                                                .background(RoundedRectangle(cornerRadius: 11).fill(active ? BevelColors.emeraldEnd : BevelColors.cardSubtle))
                                        }
                                    }
                                }
                            }

                            Divider().background(BevelColors.divider)

                            profileStepperRow(
                                label: "Altura",
                                value: "\(Int(profile.heightCm.rounded())) cm",
                                onMinus: { profile.heightCm = max(135, profile.heightCm - 1) },
                                onPlus: { profile.heightCm = min(220, profile.heightCm + 1) }
                            )
                            profileStepperRow(
                                label: "Peso",
                                value: String(format: "%.1f kg", locale: Locale(identifier: "es_ES"), profile.weightKg),
                                onMinus: { profile.weightKg = max(35, ((profile.weightKg - 0.5) * 10).rounded() / 10) },
                                onPlus: { profile.weightKg = min(180, ((profile.weightKg + 0.5) * 10).rounded() / 10) }
                            )
                        }
                        .padding(16)
                    }

                    // Live Aha! Moment Personalized Physiology Preview Card
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(BevelColors.emeraldEnd)
                            Text("TUS RANGOS ÓPTIMOS EN TIEMPO REAL")
                                .font(ImprovingFont.microLabel(10))
                                .fontWeight(.bold)
                                .foregroundColor(BevelColors.emeraldEnd)
                        }

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            normCell("FC MÁX.", "\(norms.maxHrBpm) ppm")
                            normCell("VFC BASE", "\(Int(norms.hrvExpectedMs.rounded())) ms")
                            normCell("SUEÑO", "\(sleepH)h \(String(format: "%02d", sleepM))m")
                            normCell("TMB / DÍA", "\(norms.maintenanceCaloriesKcal) kcal")
                            normCell("AGUA", String(format: "%.1f L", locale: Locale(identifier: "es_ES"), norms.hydrationGoalLiters))
                            normCell("PESO IDEAL", "\(Int(norms.healthyWeightLowKg.rounded()))–\(Int(norms.healthyWeightHighKg.rounded())) kg")
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(BevelColors.greenSoftBg))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(BevelColors.emeraldEnd.opacity(0.28), lineWidth: 0.9))
                    .padding(.bottom, 10)
                }
                .padding(.horizontal, 18)
            }

            OnboardingPrimaryCTA(title: "Empezar con Improving", systemImage: "checkmark", isEmerald: true, action: onComplete)
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 18)
        }
    }

    private func profileStepperRow(label: String, value: String, onMinus: @escaping () -> Void, onPlus: @escaping () -> Void) -> some View {
        HStack {
            Text(label)
                .font(ImprovingFont.cardTitle(13.5))
                .foregroundColor(BevelColors.textPrimary)
            Spacer()
            HStack(spacing: 10) {
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    onMinus()
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(BevelColors.textPrimary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(BevelColors.trackGroove))
                }
                Text(value)
                    .font(ImprovingFont.cardTitle(13.5))
                    .monospacedDigit()
                    .foregroundColor(BevelColors.textPrimary)
                    .frame(minWidth: 74)
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    onPlus()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(BevelColors.textPrimary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(BevelColors.trackGroove))
                }
            }
        }
    }

    private func normCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                .foregroundColor(BevelColors.textSecondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundColor(BevelColors.textPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(BevelColors.card))
    }
}

private struct OnboardingPrimaryCTA: View {
    let title: String
    let systemImage: String
    var isEmerald: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(ImprovingFont.cardTitle(16))
                    .fontWeight(.bold)
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                Capsule().fill(
                    LinearGradient(
                        colors: isEmerald
                            ? [BevelColors.greenPrimary, BevelColors.emeraldEnd]
                            : [BevelColors.emeraldEnd, BevelColors.indigoEnd],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            )
            .shadow(color: BevelColors.emeraldEnd.opacity(0.28), radius: 12, y: 5)
        }
    }
}

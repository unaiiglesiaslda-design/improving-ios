import SwiftUI

// MARK: - Color Helpers

extension Color {
    init(hex: UInt64, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }

    static func lerp(_ a: Color, _ b: Color, t: Double) -> Color {
        let clamped = min(max(t, 0.0), 1.0)
        let ua = UIColor(a)
        let ub = UIColor(b)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        ua.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        ub.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return Color(
            .sRGB,
            red: Double(r1 + (r2 - r1) * clamped),
            green: Double(g1 + (g2 - g1) * clamped),
            blue: Double(b1 + (b2 - b1) * clamped),
            opacity: Double(a1 + (a2 - a1) * clamped)
        )
    }
}

// MARK: - BevelColors (Exact iOS Liquid-Glass Dark Graphite + Light Mode Support)

final class ThemeSettings: ObservableObject {
    static let shared = ThemeSettings()
    @Published var isDarkMode: Bool = true
}

enum BevelColors {
    static var isDarkMode: Bool {
        get { ThemeSettings.shared.isDarkMode }
        set { ThemeSettings.shared.isDarkMode = newValue }
    }

    // Core Surfaces (Matched pixel-for-pixel to iOS screenshots 01–75)
    static var canvas: Color { isDarkMode ? Color(hex: 0x141518) : Color(hex: 0xF2F4F7) }
    static var sheetHeaderBg: Color { isDarkMode ? Color(hex: 0x1E2026) : Color(hex: 0xFFFFFF) }
    static var card: Color { isDarkMode ? Color(hex: 0x22242A) : Color(hex: 0xFFFFFF) }
    static var cardHeaderStrip: Color { isDarkMode ? Color(hex: 0x2B2E36) : Color(hex: 0xF1F5F9) }
    static var cardSubtle: Color { isDarkMode ? Color(hex: 0x1B1D22) : Color(hex: 0xF8FAFC) }
    static var surfaceOverlay: Color { cardSubtle }
    static var cardBorder: Color { isDarkMode ? Color.white.opacity(0.085) : Color(hex: 0x0F172A, alpha: 0.06) }
    static var glassChromeFill: Color { isDarkMode ? Color(hex: 0x262932, alpha: 0.86) : Color.white.opacity(0.92) }
    static var glassChromeBorder: Color { isDarkMode ? Color.white.opacity(0.16) : Color(hex: 0x0F172A, alpha: 0.08) }
    static var divider: Color { isDarkMode ? Color.white.opacity(0.07) : Color(hex: 0xEAECEF) }
    static var trackGroove: Color { isDarkMode ? Color(hex: 0x2E313A) : Color(hex: 0xE7EBF0) }
    static var trackInnerShadow: Color { isDarkMode ? Color(hex: 0x1A1C21) : Color(hex: 0xD9DFE7) }

    // Adaptive Chart & Gauge Tokens (high contrast in BOTH Dark Mode & Light Mode!)
    static var chartGridLine: Color { isDarkMode ? Color.white.opacity(0.08) : Color(hex: 0x0F172A, alpha: 0.09) }
    static var chartAxisStroke: Color { isDarkMode ? Color.white.opacity(0.16) : Color(hex: 0x0F172A, alpha: 0.16) }
    static var chartTickInactive: Color { isDarkMode ? Color.white.opacity(0.16) : Color(hex: 0x0F172A, alpha: 0.16) }
    static var chartTrackSubtle: Color { isDarkMode ? Color.white.opacity(0.12) : Color(hex: 0x0F172A, alpha: 0.10) }
    static var chartPointerFill: Color { isDarkMode ? Color.white : Color(hex: 0x111827) }
    static var chartGhostCurve: Color { isDarkMode ? Color.white.opacity(0.28) : Color(hex: 0x0F172A, alpha: 0.28) }
    static var chartTooltipBg: Color { isDarkMode ? Color(hex: 0x262932) : Color(hex: 0xFFFFFF) }

    // Typography
    static var textPrimary: Color { isDarkMode ? Color(hex: 0xF3F4F6) : Color(hex: 0x111827) }
    static var textSecondary: Color { isDarkMode ? Color(hex: 0x9094A0) : Color(hex: 0x6B7280) }
    static var textMuted: Color { isDarkMode ? Color(hex: 0x636773) : Color(hex: 0x9CA3AF) }

    // Recovery & Energy
    static let limeStart = Color(hex: 0xC6F23B)
    static let emeraldStart = Color(hex: 0x4ADE80)
    static let emeraldEnd = Color(hex: 0x22C55E)
    static let greenPrimary = Color(hex: 0x3BD671)
    static let bioTeal = Color(hex: 0x38D4B0)
    static var greenSoftBg: Color { isDarkMode ? Color(hex: 0x1C2E27) : Color(hex: 0xECFDF5) }
    static var greenSoftBorder: Color { isDarkMode ? Color(hex: 0x2B4C3E) : Color(hex: 0xA7F3D0) }

    // Strain / Effort
    static let amberStart = Color(hex: 0xF5B942)
    static let orangeEnd = Color(hex: 0xEC7D42)
    static var orangeSoftBg: Color { isDarkMode ? Color(hex: 0x33241B) : Color(hex: 0xFFF7ED) }
    static var amberSoftBg: Color { orangeSoftBg }
    static var strainHatchBg: Color { isDarkMode ? Color(hex: 0x423528) : Color(hex: 0xEADBC8) }
    static var strainHatchLine: Color { isDarkMode ? Color(hex: 0x997954) : Color(hex: 0xC8B29A) }

    // Sleep
    static let periwinkleStart = Color(hex: 0xA5B8FC)
    static let indigoEnd = Color(hex: 0x6C7AE0)
    static var indigoSoftBg: Color { isDarkMode ? Color(hex: 0x232740) : Color(hex: 0xEEF2FF) }

    // Stress & Alerts
    static let tealLow = Color(hex: 0x56D5C6)
    static let coralHigh = Color(hex: 0xDE6B48)
    static var coralSoftBg: Color { isDarkMode ? Color(hex: 0x38201E) : Color(hex: 0xFEF2F2) }
    static let redAlert = Color(hex: 0xDC2626)

    // Biology & Cardio
    static let skyBlue = Color(hex: 0x4DA6FF)
    static let cyanBright = Color(hex: 0x49D5F2)
    static let strengthPink = Color(hex: 0xEE6D88)
    static var skySoftBg: Color { isDarkMode ? Color(hex: 0x1A293B) : Color(hex: 0xF0F9FF) }

    // Floating Chrome
    static var floatingDarkButton: Color { isDarkMode ? Color(hex: 0x3C404D) : Color(hex: 0x181C24) }
    static var journalNeutralBg: Color { isDarkMode ? Color(hex: 0x343844) : Color(hex: 0xFFFFFF) }
}

// MARK: - Modern Clean Typography (Plus Jakarta Sans)

enum ImprovingFont {
    static func custom(_ weight: Font.Weight, size: CGFloat) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "PlusJakartaSans-Bold"
        case .semibold: name = "PlusJakartaSans-SemiBold"
        case .medium: name = "PlusJakartaSans-Medium"
        default: name = "PlusJakartaSans-Regular"
        }
        return Font.custom(name, size: size)
    }

    static func displayLarge(_ size: CGFloat = 30) -> Font { custom(.bold, size: size) }
    static func metricHero(_ size: CGFloat = 26) -> Font { custom(.bold, size: size) }
    static func metricTile(_ size: CGFloat = 20) -> Font { custom(.bold, size: size) }
    static func sectionTitle(_ size: CGFloat = 18) -> Font { custom(.semibold, size: size) }
    static func cardTitle(_ size: CGFloat = 15) -> Font { custom(.semibold, size: size) }
    static func microLabel(_ size: CGFloat = 11) -> Font { custom(.semibold, size: size) }
    static func body(_ size: CGFloat = 14) -> Font { custom(.regular, size: size) }
    static func caption(_ size: CGFloat = 12) -> Font { custom(.medium, size: size) }
}

// MARK: - Reusable Liquid Glass Card Surface

struct BevelCard<Content: View>: View {
    var cornerRadius: CGFloat = 20
    var backgroundColor: Color? = nil
    var borderColor: Color? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundColor ?? BevelColors.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                borderColor ?? (BevelColors.isDarkMode ? Color.white.opacity(0.12) : BevelColors.cardBorder),
                                borderColor ?? (BevelColors.isDarkMode ? Color.white.opacity(0.03) : BevelColors.cardBorder)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.9
                    )
            )
    }
}

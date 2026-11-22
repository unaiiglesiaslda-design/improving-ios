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

// MARK: - BevelColors (1:1 Parity with Android Dark Blue-Grey + Pure Black Canvas)

final class ThemeSettings: ObservableObject {
    static let shared = ThemeSettings()
    @Published var isDarkMode: Bool = true
}

enum BevelColors {
    static var isDarkMode: Bool {
        get { ThemeSettings.shared.isDarkMode }
        set { ThemeSettings.shared.isDarkMode = newValue }
    }

    static var canvas: Color { isDarkMode ? Color(hex: 0x000000) : Color(hex: 0xF2F4F7) }
    static var card: Color { isDarkMode ? Color(hex: 0x1A2230) : Color(hex: 0xFFFFFF) }
    static var cardSubtle: Color { isDarkMode ? Color(hex: 0x222C3E) : Color(hex: 0xF8FAFC) }
    static var cardBorder: Color { isDarkMode ? Color(hex: 0x94A3B8, alpha: 0.14) : Color(hex: 0x0F172A, alpha: 0.06) }
    static var divider: Color { isDarkMode ? Color(hex: 0x2A3548) : Color(hex: 0xEAECEF) }
    static var trackGroove: Color { isDarkMode ? Color(hex: 0x283347) : Color(hex: 0xE7EBF0) }
    static var trackInnerShadow: Color { isDarkMode ? Color(hex: 0x1E2738) : Color(hex: 0xD9DFE7) }

    static var textPrimary: Color { isDarkMode ? Color(hex: 0xE6EBF2) : Color(hex: 0x111827) }
    static var textSecondary: Color { isDarkMode ? Color(hex: 0x9AA7BC) : Color(hex: 0x6B7280) }
    static var textMuted: Color { isDarkMode ? Color(hex: 0x6E7D95) : Color(hex: 0x9CA3AF) }

    // Recovery & Energy
    static let limeStart = Color(hex: 0xA3E635)
    static let emeraldStart = Color(hex: 0x4ADE80)
    static let emeraldEnd = Color(hex: 0x16A34A)
    static let greenPrimary = Color(hex: 0x22C55E)
    static var greenSoftBg: Color { isDarkMode ? Color(hex: 0x102A22) : Color(hex: 0xECFDF5) }
    static var greenSoftBorder: Color { isDarkMode ? Color(hex: 0x1D4D3C) : Color(hex: 0xA7F3D0) }
    static var surfaceOverlay: Color { cardSubtle }

    // Strain / Effort
    static let amberStart = Color(hex: 0xFBBF24)
    static let orangeEnd = Color(hex: 0xF97316)
    static var orangeSoftBg: Color { isDarkMode ? Color(hex: 0x2B1F14) : Color(hex: 0xFFF7ED) }
    static var amberSoftBg: Color { orangeSoftBg }
    static var strainHatchBg: Color { isDarkMode ? Color(hex: 0x2B2219) : Color(hex: 0xEADBC8) }
    static var strainHatchLine: Color { isDarkMode ? Color(hex: 0x5C4936) : Color(hex: 0xC8B29A) }

    // Sleep
    static let periwinkleStart = Color(hex: 0x818CF8)
    static let indigoEnd = Color(hex: 0x4F46E5)
    static var indigoSoftBg: Color { isDarkMode ? Color(hex: 0x1B1F36) : Color(hex: 0xEEF2FF) }

    // Stress & Alerts
    static let tealLow = Color(hex: 0x2DD4BF)
    static let coralHigh = Color(hex: 0xE07A5F)
    static var coralSoftBg: Color { isDarkMode ? Color(hex: 0x331B1A) : Color(hex: 0xFEF2F2) }
    static let redAlert = Color(hex: 0xDC2626)

    // Biology & Cardio
    static let skyBlue = Color(hex: 0x0EA5E9)
    static let cyanBright = Color(hex: 0x06B6D4)
    static var skySoftBg: Color { isDarkMode ? Color(hex: 0x112538) : Color(hex: 0xF0F9FF) }

    // Floating Chrome
    static var floatingDarkButton: Color { isDarkMode ? Color(hex: 0x2A364C) : Color(hex: 0x181C24) }
    static var journalNeutralBg: Color { isDarkMode ? Color(hex: 0x303D54) : Color(hex: 0xFFFFFF) }
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

// MARK: - Reusable Card Surface

struct BevelCard<Content: View>: View {
    var cornerRadius: CGFloat = 22
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
                    .strokeBorder(borderColor ?? BevelColors.cardBorder, lineWidth: 0.9)
            )
    }
}

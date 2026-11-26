import UIKit

/// Centralized, pre-warmed haptic feedback helper so rapid gestures (chart scrubbing, steppers, toggles)
/// reuse shared UIFeedbackGenerator instances instead of allocating new ones on every event.
@MainActor
enum AppHaptics {
    private static let selectionGenerator: UISelectionFeedbackGenerator = {
        let g = UISelectionFeedbackGenerator()
        g.prepare()
        return g
    }()

    private static let lightImpactGenerator: UIImpactFeedbackGenerator = {
        let g = UIImpactFeedbackGenerator(style: .light)
        g.prepare()
        return g
    }()

    private static let mediumImpactGenerator: UIImpactFeedbackGenerator = {
        let g = UIImpactFeedbackGenerator(style: .medium)
        g.prepare()
        return g
    }()

    private static let notificationGenerator: UINotificationFeedbackGenerator = {
        let g = UINotificationFeedbackGenerator()
        g.prepare()
        return g
    }()

    static func selection() {
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }

    static func lightImpact() {
        lightImpactGenerator.impactOccurred()
        lightImpactGenerator.prepare()
    }

    static func mediumImpact() {
        mediumImpactGenerator.impactOccurred()
        mediumImpactGenerator.prepare()
    }

    static func success() {
        notificationGenerator.notificationOccurred(.success)
        notificationGenerator.prepare()
    }

    static func warning() {
        notificationGenerator.notificationOccurred(.warning)
        notificationGenerator.prepare()
    }

    static func error() {
        notificationGenerator.notificationOccurred(.error)
        notificationGenerator.prepare()
    }
}

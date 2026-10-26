import UIKit

/// Haptic feedback. The app makes no sound — haptics are the primary confirmation.
enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// The weighty thud for the one deliberate gesture (slide-to-confirm) —
    /// heavier than a tap, more physical than the success chime.
    static func heavy() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

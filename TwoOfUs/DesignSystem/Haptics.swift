import UIKit

/// Haptic feedback. The app makes no sound — haptics are the primary confirmation.
enum Haptics {
    // Long-lived generators: one kept alive can be prepare()d ahead of a tap,
    // which warms the Taptic Engine for a few seconds and cuts the haptic's
    // latency (a generator built per call never gets that chance). Feedback is
    // unchanged.
    private static let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private static let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private static let notificationFeedback = UINotificationFeedbackGenerator()

    static func tap() {
        mediumImpact.impactOccurred()
    }

    /// Warms the tap generator ahead of an expected tap (e.g. on touch-down),
    /// so the haptic at touch-up fires with less latency.
    static func prepareTap() {
        mediumImpact.prepare()
    }

    /// The weighty thud for the one deliberate gesture (slide-to-confirm) —
    /// heavier than a tap, more physical than the success chime.
    static func heavy() {
        heavyImpact.impactOccurred()
    }

    static func success() {
        notificationFeedback.notificationOccurred(.success)
    }

    static func warning() {
        notificationFeedback.notificationOccurred(.warning)
    }
}

import SwiftUI

/// Green → amber → red as the next event approaches/passes its target interval.
enum Urgency {
    case green, amber, red

    var color: Color {
        switch self {
        case .green: return AppColor.urgencyGreen
        case .amber: return AppColor.urgencyAmber
        case .red:   return AppColor.urgencyRed
        }
    }

    /// "Quiet until it matters": green draws nothing extra, amber/red do.
    var needsAttention: Bool { self != .green }

    /// Since-line text color on the log tiles: calm gray at green, a darkened
    /// readable tint once attention is due. The *presence* of color is the
    /// signal, so it doesn't lean on red-vs-green discrimination.
    var sinceTextColor: Color {
        switch self {
        case .green: return AppColor.text2
        case .amber: return AppColor.urgencyAmberText
        case .red:   return AppColor.urgencyRedText
        }
    }

    /// Spoken for VoiceOver — color is never the only signal.
    var accessibilityWord: String {
        switch self {
        case .green: return "recent"
        case .amber: return "due soon"
        case .red:   return "overdue"
        }
    }

    /// Shape cue on the log tiles so amber-vs-red isn't carried by hue alone: a
    /// plain dot for "due soon", an exclamation for "overdue". nil at green (no
    /// marker at all — quiet until it matters).
    var marker: String? {
        switch self {
        case .green: return nil
        case .amber: return "circle.fill"
        case .red:   return "exclamationmark.circle.fill"
        }
    }

    /// Ratio of elapsed time to the target interval.
    static func from(since date: Date?, now: Date = .now, target: TimeInterval) -> Urgency {
        guard let date, target > 0 else { return .green }
        let ratio = now.timeIntervalSince(date) / target
        if ratio < 0.66 { return .green }
        if ratio <= 1.0 { return .amber }
        return .red
    }
}

/// Default target intervals per event kind (seconds). Feed comes from SharedSettings.
enum UrgencyDefaults {
    static let diaper: TimeInterval = 3 * 3600
    static let sleep: TimeInterval = 2.5 * 3600
}

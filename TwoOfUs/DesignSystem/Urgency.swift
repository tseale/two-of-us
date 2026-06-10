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

    /// Spoken for VoiceOver — color is never the only signal.
    var accessibilityWord: String {
        switch self {
        case .green: return "recent"
        case .amber: return "due soon"
        case .red:   return "overdue"
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

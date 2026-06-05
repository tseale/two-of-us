import Foundation

/// Kind of diaper event.
enum DiaperType: String, Codable, CaseIterable, Identifiable {
    case wet
    case dirty
    case both

    var id: String { rawValue }

    var label: String {
        switch self {
        case .wet: return "Wet"
        case .dirty: return "Dirty"
        case .both: return "Both"
        }
    }

    var emoji: String {
        switch self {
        case .wet: return "💧"
        case .dirty: return "💩"
        case .both: return "💧💩"
        }
    }
}

/// A participant's access level. Both roles are read-write at the data layer;
/// the difference is enforced in the app UI (Logger can't change settings).
enum ParticipantRole: String, Codable {
    case full      // co-parent: log, edit, delete, change settings
    case logger    // caregiver: log + edit events, no settings/baby changes
}

/// The three loggable event categories (used for "time since" lookups).
enum EventKind: String, CaseIterable, Identifiable {
    case feed
    case sleep
    case diaper

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .feed: return "🍼"
        case .sleep: return "💤"
        case .diaper: return "💩"
        }
    }
}

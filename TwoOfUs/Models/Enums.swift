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

/// Where an event record originated. Absent (nil `sourceRaw`) means logged by
/// hand; `snoo` marks sleeps imported from the SNOO integration, `brightwheel`
/// marks events imported from the daycare's Brightwheel log — so the timeline
/// can tell imported records apart from what a parent tapped in.
/// (Renamed from `SleepSource` when Brightwheel made sources apply to every
/// event type; raw values are unchanged, so synced records still decode.)
enum EventSource: String, Codable {
    case snoo
    case brightwheel

    var label: String {
        switch self {
        case .snoo: return "SNOO"
        case .brightwheel: return "Daycare"
        }
    }
}

/// A participant's access level. Both roles are read-write at the data layer;
/// the difference is enforced in the app UI (Logger can't change settings).
enum ParticipantRole: String, Codable {
    case full      // co-parent: log, edit, delete, change settings
    case logger    // caregiver: log + edit events, no settings/baby changes

    /// User-facing label. Raw values stay "full"/"logger" for sync compatibility.
    var displayName: String {
        switch self {
        case .full: return "Co-parent"
        case .logger: return "Guest"
        }
    }
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

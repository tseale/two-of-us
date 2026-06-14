import Foundation

/// A unified view of the three event types for the rolling timeline.
enum TimelineEntry: Identifiable {
    case feed(FeedEvent)
    case sleep(SleepEvent)
    case diaper(DiaperEvent)

    var id: UUID {
        switch self {
        case .feed(let e): return e.id
        case .sleep(let e): return e.id
        case .diaper(let e): return e.id
        }
    }

    /// The instant used to sort and place the entry on the timeline.
    var sortDate: Date {
        switch self {
        case .feed(let e): return e.timestamp
        case .sleep(let e): return e.startedAt
        case .diaper(let e): return e.timestamp
        }
    }

    var kind: EventKind {
        switch self {
        case .feed: return .feed
        case .sleep: return .sleep
        case .diaper: return .diaper
        }
    }

    /// The logger's participant id, so a row can resolve their current avatar
    /// photo (name/color are denormalized on the event; the photo is not).
    var loggedByID: UUID {
        switch self {
        case .feed(let e): return e.loggedByID
        case .sleep(let e): return e.loggedByID
        case .diaper(let e): return e.loggedByID
        }
    }

    var loggedByName: String {
        switch self {
        case .feed(let e): return e.loggedByName
        case .sleep(let e): return e.loggedByName
        case .diaper(let e): return e.loggedByName
        }
    }

    var loggedByColorHex: String {
        switch self {
        case .feed(let e): return e.loggedByColorHex
        case .sleep(let e): return e.loggedByColorHex
        case .diaper(let e): return e.loggedByColorHex
        }
    }

    /// Optional free-text note the parent attached to this event.
    var notes: String? {
        switch self {
        case .feed(let e): return e.notes
        case .sleep(let e): return e.notes
        case .diaper(let e): return e.notes
        }
    }

    /// Short detail string for the row, e.g. "3 oz", "1h 22m", "Wet".
    var detail: String {
        switch self {
        case .feed(let e):
            return OzFormat.string(e.amountOz) + " oz"
        case .sleep(let e):
            if let end = e.endedAt {
                return "Sleep · " + TimeFormatting.duration(from: e.startedAt, to: end)
            } else {
                return "Sleep · in progress"
            }
        case .diaper(let e):
            return "Diaper · " + e.type.label
        }
    }

    var title: String {
        switch self {
        case .feed(let e): return "Feed · " + OzFormat.string(e.amountOz) + " oz"
        case .sleep: return detail
        case .diaper: return detail
        }
    }
}

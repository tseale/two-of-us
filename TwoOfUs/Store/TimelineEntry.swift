import Foundation

/// A unified view of the event types for the rolling timeline.
enum TimelineEntry: Identifiable {
    case feed(FeedEvent)
    case sleep(SleepEvent)
    case diaper(DiaperEvent)
    case note(NoteEvent)
    case activity(ActivityEvent)
    case media(MediaEvent)
    case check(CheckEvent)
    case medication(MedicationEvent)
    case healthCheck(HealthCheckEvent)
    case mood(MoodEvent)
    case potty(PottyEvent)
    case milestone(MilestoneEvent)
    case staffNote(StaffNoteEvent)

    var id: UUID {
        switch self {
        case .feed(let e): return e.id
        case .sleep(let e): return e.id
        case .diaper(let e): return e.id
        case .note(let e): return e.id
        case .activity(let e): return e.id
        case .media(let e): return e.id
        case .check(let e): return e.id
        case .medication(let e): return e.id
        case .healthCheck(let e): return e.id
        case .mood(let e): return e.id
        case .potty(let e): return e.id
        case .milestone(let e): return e.id
        case .staffNote(let e): return e.id
        }
    }

    /// The instant used to sort and place the entry on the timeline.
    var sortDate: Date {
        switch self {
        case .feed(let e): return e.timestamp
        case .sleep(let e): return e.startedAt
        case .diaper(let e): return e.timestamp
        case .note(let e): return e.timestamp
        case .activity(let e): return e.timestamp
        case .media(let e): return e.timestamp
        case .check(let e): return e.timestamp
        case .medication(let e): return e.timestamp
        case .healthCheck(let e): return e.timestamp
        case .mood(let e): return e.timestamp
        case .potty(let e): return e.timestamp
        case .milestone(let e): return e.timestamp
        case .staffNote(let e): return e.timestamp
        }
    }

    /// The tracker kind, nil for everything else — `EventKind` drives tracker
    /// toggles, tiles, ribbons, and Siri; the daycare-era types (like notes)
    /// belong in none of those.
    var kind: EventKind? {
        switch self {
        case .feed: return .feed
        case .sleep: return .sleep
        case .diaper: return .diaper
        default: return nil
        }
    }

    /// The row's leading glyph. Non-tracker types aren't an `EventKind`, so
    /// their emoji live here rather than on the enum.
    var emoji: String {
        switch self {
        case .note: return "📝"
        case .diaper(let e): return e.type == .wet ? "💧" : "💩"
        case .activity(let e): return e.type.emoji
        case .media(let e): return e.kind.emoji
        case .check(let e): return e.type.emoji
        case .medication: return "💊"
        case .healthCheck(let e): return e.type.emoji
        case .mood(let e): return e.level.emoji
        case .potty: return "🚽"
        case .milestone: return "🏆"
        case .staffNote: return "💬"
        default: return kind?.emoji ?? ""
        }
    }

    /// The logger's participant id, so a row can resolve their current avatar
    /// photo (name/color are denormalized on the event; the photo is not).
    var loggedByID: UUID {
        switch self {
        case .feed(let e): return e.loggedByID
        case .sleep(let e): return e.loggedByID
        case .diaper(let e): return e.loggedByID
        case .note(let e): return e.loggedByID
        case .activity(let e): return e.loggedByID
        case .media(let e): return e.loggedByID
        case .check(let e): return e.loggedByID
        case .medication(let e): return e.loggedByID
        case .healthCheck(let e): return e.loggedByID
        case .mood(let e): return e.loggedByID
        case .potty(let e): return e.loggedByID
        case .milestone(let e): return e.loggedByID
        case .staffNote(let e): return e.loggedByID
        }
    }

    var loggedByName: String {
        switch self {
        case .feed(let e): return e.loggedByName
        case .sleep(let e): return e.loggedByName
        case .diaper(let e): return e.loggedByName
        case .note(let e): return e.loggedByName
        case .activity(let e): return e.loggedByName
        case .media(let e): return e.loggedByName
        case .check(let e): return e.loggedByName
        case .medication(let e): return e.loggedByName
        case .healthCheck(let e): return e.loggedByName
        case .mood(let e): return e.loggedByName
        case .potty(let e): return e.loggedByName
        case .milestone(let e): return e.loggedByName
        case .staffNote(let e): return e.loggedByName
        }
    }

    var loggedByColorHex: String {
        switch self {
        case .feed(let e): return e.loggedByColorHex
        case .sleep(let e): return e.loggedByColorHex
        case .diaper(let e): return e.loggedByColorHex
        case .note(let e): return e.loggedByColorHex
        case .activity(let e): return e.loggedByColorHex
        case .media(let e): return e.loggedByColorHex
        case .check(let e): return e.loggedByColorHex
        case .medication(let e): return e.loggedByColorHex
        case .healthCheck(let e): return e.loggedByColorHex
        case .mood(let e): return e.loggedByColorHex
        case .potty(let e): return e.loggedByColorHex
        case .milestone(let e): return e.loggedByColorHex
        case .staffNote(let e): return e.loggedByColorHex
        }
    }

    /// True for sleep records imported from the SNOO integration — the
    /// timeline tags them so bassinet time reads apart from hand-logged naps.
    var isFromSnoo: Bool {
        if case .sleep(let e) = self { return e.isFromSnoo }
        return false
    }

    /// True for events imported from the daycare's Brightwheel log — the
    /// timeline tags them so daycare entries read apart from the parents' own.
    var isFromDaycare: Bool {
        switch self {
        case .feed(let e): return e.isFromDaycare
        case .sleep(let e): return e.isFromDaycare
        case .diaper(let e): return e.isFromDaycare
        case .note(let e): return e.isFromDaycare
        case .activity(let e): return e.isFromDaycare
        case .media(let e): return e.isFromDaycare
        case .check(let e): return e.isFromDaycare
        case .medication(let e): return e.isFromDaycare
        case .healthCheck(let e): return e.isFromDaycare
        case .mood(let e): return e.isFromDaycare
        case .potty(let e): return e.isFromDaycare
        case .milestone(let e): return e.isFromDaycare
        case .staffNote(let e): return e.isFromDaycare
        }
    }

    /// Whether the edit sheet handles this entry. The daycare-era types are
    /// read-only for now (they arrive from Brightwheel; delete/undo still
    /// works) — their edit UI lands with the polish pass, not the scaffolding.
    var isEditable: Bool {
        switch self {
        case .feed, .sleep, .diaper, .note: return true
        default: return false
        }
    }

    /// Optional free-text note attached to this event. Nil for a standalone
    /// note and a staff note — their text IS the title, not a caption under
    /// one. A media caption and a milestone's note render here.
    var notes: String? {
        switch self {
        case .feed(let e): return e.notes
        case .sleep(let e): return e.notes
        case .diaper(let e): return e.notes
        case .note: return nil
        case .activity(let e): return e.notes
        case .media(let e): return e.caption
        case .check(let e): return e.notes
        case .medication(let e): return e.notes
        case .healthCheck(let e): return e.notes
        case .mood(let e): return e.notes
        case .potty(let e): return e.notes
        case .milestone(let e): return e.notes
        // Quote-card style: the staff's words read as a quotation.
        case .staffNote(let e): return "“\(e.text)”"
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
        case .note(let e):
            return e.text
        case .activity(let e):
            var s = "Activity · " + e.type.label
            if let minutes = e.durationMinutes, minutes > 0 {
                s += " · " + TimeFormatting.duration(minutes: minutes)
            }
            return s
        case .media(let e):
            return e.kind.label
        case .check(let e):
            var s = e.type.label
            if let name = e.byName, !name.isEmpty { s += " by \(name)" }
            return s
        case .medication(let e):
            var s = "Medication · " + e.name
            if let dosage = e.dosage, !dosage.isEmpty { s += " · " + dosage }
            return s
        case .healthCheck(let e):
            return "Health · \(e.type.label) \(e.type.format(e.value))"
        case .mood(let e):
            return "Mood · " + e.level.label
        case .potty(let e):
            return "Potty · " + e.outcome.label
        case .milestone(let e):
            return "Milestone · " + e.text
        case .staffNote(let e):
            if let author = e.authorName, !author.isEmpty {
                return "Note from \(author)"
            }
            return "Daycare note"
        }
    }

    var title: String {
        switch self {
        case .feed(let e): return "Feed · " + OzFormat.string(e.amountOz) + " oz"
        default: return detail
        }
    }
}

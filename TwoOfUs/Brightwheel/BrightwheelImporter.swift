import Foundation
import SwiftData

/// Turns Brightwheel activities into Two of Us events. Source-agnostic: the
/// mock day, a pasted JSON file, and the live API all hand it the same DTOs,
/// so swapping in real data changes nothing downstream.
///
/// Imported events are ordinary Feed/Sleep/Diaper/Note events stamped
/// `source: .brightwheel` + the activity's `object_id` as `externalID` — that
/// is what makes the timeline, CloudKit sync, stats, and the prediction
/// engine consume them with zero extra plumbing, exactly like SNOO sleeps.
///
/// Dedupe, in order:
/// 1. `externalID` — survives re-imports, re-installs, and both parents
///    importing, because the id travels on the synced record itself.
/// 2. Same type + `.brightwheel` source within ±90 s — catches a re-imported
///    activity whose id changed (Brightwheel edits reissue objects).
@MainActor
struct BrightwheelImporter {
    let store: EventStore
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
        self.store = EventStore(context: context)
    }

    struct Summary: Equatable {
        var feeds = 0
        var sleeps = 0
        var diapers = 0
        var notes = 0
        var skippedDuplicates = 0
        var skippedUnmapped = 0

        var imported: Int { feeds + sleeps + diapers + notes }

        var line: String {
            imported == 0
                ? "Nothing new to import."
                : "Imported \(Plural.unit(feeds, "feed")), \(Plural.unit(sleeps, "nap")), \(Plural.unit(diapers, "diaper")), \(Plural.unit(notes, "note"))."
        }
    }

    private static let duplicateWindow: TimeInterval = 90

    @discardableResult
    func importActivities(_ activities: [BrightwheelActivity]) -> Summary {
        var summary = Summary()
        // Oldest first so the timeline fills in chronological order and a
        // mid-import failure leaves a clean prefix, not holes.
        let ordered = activities.sorted { ($0.when ?? .distantPast) < ($1.when ?? .distantPast) }
        for activity in ordered {
            importOne(activity, into: &summary)
        }
        return summary
    }

    private func importOne(_ activity: BrightwheelActivity, into summary: inout Summary) {
        guard let when = activity.when, let action = activity.actionType else {
            summary.skippedUnmapped += 1
            return
        }
        if isDuplicate(activity, when: when) {
            summary.skippedDuplicates += 1
            return
        }
        let id = activity.objectID
        let note = activity.note

        switch action {
        case "ac_food":
            // Bottle ounces: the one field whose real encoding is still
            // unverified (research §8). A feed without a parseable amount
            // imports as a note — visible and countable, never a fabricated
            // "0 oz" bottle.
            if let oz = activity.detailsBlob?.amount, EventBounds.isLoggableOz(oz) {
                if store.logFeed(amountOz: oz, at: when, notes: note,
                                 source: .brightwheel, externalID: id) != nil {
                    summary.feeds += 1
                }
            } else if store.logNote(noteText("Bottle at daycare", note), at: when,
                                    source: .brightwheel, externalID: id) != nil {
                summary.notes += 1
            }
        case "ac_nap":
            let start = BrightwheelActivity.parseDate(activity.detailsBlob?.startTime) ?? when
            // An in-progress nap has no end yet; it re-imports cleanly on the
            // next sync once staff close it (its object_id hasn't been used).
            guard let end = activity.end, end > start else {
                summary.skippedUnmapped += 1
                return
            }
            if store.logCompletedSleep(startedAt: start, endedAt: end, notes: note,
                                       source: .brightwheel, externalID: id) != nil {
                summary.sleeps += 1
            }
        case "ac_potty":
            if store.logDiaper(diaperType(from: activity), at: when, notes: note,
                               source: .brightwheel, externalID: id) != nil {
                summary.diapers += 1
            }
        case "ac_checkin":
            let text = checkinText(from: activity) ?? "Checked in at daycare"
            if store.logNote(text, at: when, source: .brightwheel, externalID: id) != nil {
                summary.notes += 1
            }
        case "ac_note", "ac_observation", "ac_kudo", "ac_incident", "ac_meds",
             "ac_health_check", "ac_activity", "ac_learning_activity":
            guard let text = note ?? activity.detailsBlob?.tags?.first else {
                summary.skippedUnmapped += 1
                return
            }
            if store.logNote(text, at: when, source: .brightwheel, externalID: id) != nil {
                summary.notes += 1
            }
        default:
            // ac_photo/ac_video (media import is a later phase), ac_absence,
            // and anything Brightwheel adds after this build.
            summary.skippedUnmapped += 1
        }
    }

    private func noteText(_ title: String, _ note: String?) -> String {
        guard let note, !note.isEmpty else { return title }
        return "\(title) — \(note)"
    }

    private func diaperType(from activity: BrightwheelActivity) -> DiaperType {
        let tags = (activity.detailsBlob?.tags ?? []).map { $0.lowercased() }
        let wet = tags.contains { $0.contains("wet") }
        let dirty = tags.contains { $0.contains("bm") || $0.contains("dirty") || $0.contains("soiled") }
        switch (wet, dirty) {
        case (true, true): return .both
        case (false, true): return .dirty
        default: return .wet
        }
    }

    private func checkinText(from activity: BrightwheelActivity) -> String? {
        let tags = (activity.detailsBlob?.tags ?? []).map { $0.lowercased() }
        if tags.contains(where: { $0.contains("out") || $0.contains("pick") }) {
            return "Picked up from daycare"
        }
        if !tags.isEmpty || activity.note != nil {
            return "Dropped off at daycare"
        }
        return nil
    }

    // MARK: Dedupe

    private func isDuplicate(_ activity: BrightwheelActivity, when: Date) -> Bool {
        if let id = activity.objectID, hasEvent(externalID: id) { return true }
        // Fallback: same type + source in the window. Only checks
        // Brightwheel-sourced events — a parent's own 12:00 bottle must not
        // block the daycare's 12:00 bottle (that near-miss is exactly what
        // the timeline's Daycare tag is for).
        let lo = when.addingTimeInterval(-Self.duplicateWindow)
        let hi = when.addingTimeInterval(Self.duplicateWindow)
        let source = EventSource.brightwheel.rawValue
        switch activity.actionType {
        case "ac_food":
            return fetchCount(FetchDescriptor<FeedEvent>(predicate: #Predicate {
                $0.deletedAt == nil && $0.sourceRaw == source
                    && $0.timestamp >= lo && $0.timestamp <= hi
            })) > 0
        case "ac_nap":
            let start = BrightwheelActivity.parseDate(activity.detailsBlob?.startTime) ?? when
            let slo = start.addingTimeInterval(-Self.duplicateWindow)
            let shi = start.addingTimeInterval(Self.duplicateWindow)
            return fetchCount(FetchDescriptor<SleepEvent>(predicate: #Predicate {
                $0.deletedAt == nil && $0.sourceRaw == source
                    && $0.startedAt >= slo && $0.startedAt <= shi
            })) > 0
        case "ac_potty":
            return fetchCount(FetchDescriptor<DiaperEvent>(predicate: #Predicate {
                $0.deletedAt == nil && $0.sourceRaw == source
                    && $0.timestamp >= lo && $0.timestamp <= hi
            })) > 0
        default:
            return fetchCount(FetchDescriptor<NoteEvent>(predicate: #Predicate {
                $0.deletedAt == nil && $0.sourceRaw == source
                    && $0.timestamp >= lo && $0.timestamp <= hi
            })) > 0
        }
    }

    private func hasEvent(externalID id: String) -> Bool {
        // Deleted events count on purpose: a daycare entry the parents
        // deliberately removed must not resurrect on the next sync.
        fetchCount(FetchDescriptor<FeedEvent>(predicate: #Predicate { $0.externalID == id })) > 0
            || fetchCount(FetchDescriptor<SleepEvent>(predicate: #Predicate { $0.externalID == id })) > 0
            || fetchCount(FetchDescriptor<DiaperEvent>(predicate: #Predicate { $0.externalID == id })) > 0
            || fetchCount(FetchDescriptor<NoteEvent>(predicate: #Predicate { $0.externalID == id })) > 0
    }

    private func fetchCount<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> Int {
        (try? context.fetchCount(descriptor)) ?? 0
    }
}

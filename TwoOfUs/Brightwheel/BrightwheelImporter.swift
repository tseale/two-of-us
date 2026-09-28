import Foundation
import SwiftData

/// Turns Brightwheel activities into Two of Us events. Source-agnostic: the
/// mock day, a pasted JSON file, and the live API all hand it the same
/// decoded wire format, so swapping in real data changes nothing downstream.
///
/// Imported events are ordinary Feed/Sleep/Diaper/Note events stamped
/// `source: .brightwheel` + the activity's `object_id` as `externalID` — that
/// is what makes the timeline, CloudKit sync, stats, and the prediction
/// engine consume them with zero extra plumbing, exactly like SNOO sleeps.
///
/// Naps arrive as TWO activities — fell-asleep (`state == "1"`) and woke-up
/// (`state == "0"`) — which this importer pairs chronologically into one
/// completed sleep, keyed on the woke-up activity's id (a nap missing its
/// wake-up is still in progress and imports on a later sync).
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
        // The API delivers newest-first; work oldest-first so nap pairing is
        // a simple forward scan and the timeline fills chronologically.
        let ordered = activities.sorted { ($0.when ?? .distantPast) < ($1.when ?? .distantPast) }

        var openNapStart: BrightwheelActivity?
        for activity in ordered {
            guard let when = activity.when, let action = activity.actionType else {
                summary.skippedUnmapped += 1
                continue
            }
            if action == "ac_nap" {
                importNapHalf(activity, when: when, openStart: &openNapStart, into: &summary)
            } else {
                importSingle(activity, action: action, when: when, into: &summary)
            }
        }
        // A fell-asleep with no woke-up yet: the nap is still running at
        // daycare. Skip it — the pair imports whole once staff log the wake.
        if openNapStart != nil { summary.skippedUnmapped += 1 }
        return summary
    }

    // MARK: Naps (start/end pairing)

    private func importNapHalf(_ activity: BrightwheelActivity, when: Date,
                               openStart: inout BrightwheelActivity?,
                               into summary: inout Summary) {
        switch activity.napState {
        case "1":
            // Two starts in a row: the first never got its wake-up (staff
            // corrected it) — the newer start wins.
            if openStart != nil { summary.skippedUnmapped += 1 }
            openStart = activity
        case "0":
            guard let start = openStart, let startWhen = start.when, startWhen < when else {
                // Orphan woke-up (its start predates the fetch window).
                summary.skippedUnmapped += 1
                return
            }
            openStart = nil
            let id = activity.objectID
            if isDuplicateSleep(externalID: id, start: startWhen) {
                summary.skippedDuplicates += 1
                return
            }
            if store.logCompletedSleep(startedAt: startWhen, endedAt: when,
                                       notes: activity.note ?? start.note,
                                       source: .brightwheel, externalID: id) != nil {
                summary.sleeps += 1
            }
        default:
            summary.skippedUnmapped += 1
        }
    }

    // MARK: Everything else

    private func importSingle(_ activity: BrightwheelActivity, action: String, when: Date,
                              into summary: inout Summary) {
        let id = activity.objectID
        if isDuplicate(activity, action: action, when: when) {
            summary.skippedDuplicates += 1
            return
        }
        switch action {
        case "ac_food":
            if activity.isBottle, let oz = activity.bottleOz, EventBounds.isLoggableOz(oz) {
                if store.logFeed(amountOz: oz, at: when, notes: activity.note,
                                 source: .brightwheel, externalID: id) != nil {
                    summary.feeds += 1
                }
            } else if store.logNote(mealText(activity), at: when,
                                    source: .brightwheel, externalID: id) != nil {
                // Solids, or a bottle whose amount didn't parse — visible and
                // countable, never a fabricated 0 oz feed.
                summary.notes += 1
            }
        case "ac_potty", "ac_bathroom":
            if let type = diaperType(from: activity) {
                if store.logDiaper(type, at: when, notes: activity.note,
                                   source: .brightwheel, externalID: id) != nil {
                    summary.diapers += 1
                }
            } else if store.logNote(noteText("Diaper check — dry", activity.note), at: when,
                                    source: .brightwheel, externalID: id) != nil {
                summary.notes += 1
            }
        case "ac_checkin":
            if store.logNote(checkinText(from: activity), at: when,
                             source: .brightwheel, externalID: id) != nil {
                summary.notes += 1
            }
        case "ac_note", "ac_observation", "ac_kudo", "ac_incident", "ac_meds",
             "ac_medication", "ac_health_check", "ac_activity", "ac_learning_activity":
            guard let text = activity.note else {
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

    private func mealText(_ activity: BrightwheelActivity) -> String {
        let items = (activity.menuItemTags ?? []).compactMap(\.name).filter { !$0.isEmpty }
        let what = items.isEmpty ? (activity.isBottle ? "Bottle" : "Meal") : items.joined(separator: ", ")
        return noteText("\(what) at daycare", activity.note)
    }

    /// wet/bm from `potty_type` (+ extras/tags as corroboration); nil for a
    /// dry check — that's an observation, not a change.
    private func diaperType(from activity: BrightwheelActivity) -> DiaperType? {
        let blob = activity.detailsBlob
        var words = [blob?.pottyType ?? ""]
        words += blob?.pottyExtras ?? []
        words += blob?.tags ?? []
        let lowered = words.map { $0.lowercased() }
        let wet = lowered.contains { $0.contains("wet") }
        let dirty = lowered.contains { $0.contains("bm") || $0.contains("dirty") || $0.contains("soiled") }
        switch (wet, dirty) {
        case (true, true): return .both
        case (false, true): return .dirty
        case (true, false): return .wet
        case (false, false):
            let dry = lowered.contains { $0.contains("dry") || $0.contains("nothing") }
            // No usable detail at all: staff logged a change, and wet is the
            // overwhelmingly common kind — better than dropping the event.
            return dry ? nil : .wet
        }
    }

    private func checkinText(from activity: BrightwheelActivity) -> String {
        var words = activity.detailsBlob?.tags ?? []
        if let note = activity.note { words.append(note) }
        let lowered = words.map { $0.lowercased() }
        if lowered.contains(where: { $0.contains("out") || $0.contains("pick") }) {
            return noteText("Picked up from daycare", activity.note)
        }
        return noteText("Dropped off at daycare", activity.note)
    }

    // MARK: Dedupe

    private func isDuplicateSleep(externalID id: String?, start: Date) -> Bool {
        if let id, hasEvent(externalID: id) { return true }
        let lo = start.addingTimeInterval(-Self.duplicateWindow)
        let hi = start.addingTimeInterval(Self.duplicateWindow)
        let source = EventSource.brightwheel.rawValue
        return fetchCount(FetchDescriptor<SleepEvent>(predicate: #Predicate {
            $0.sourceRaw == source && $0.startedAt >= lo && $0.startedAt <= hi
        })) > 0
    }

    private func isDuplicate(_ activity: BrightwheelActivity, action: String, when: Date) -> Bool {
        if let id = activity.objectID, hasEvent(externalID: id) { return true }
        // Fallback: same type + source in the window. Only checks
        // Brightwheel-sourced events — a parent's own 12:00 bottle must not
        // block the daycare's 12:00 bottle (that near-miss is exactly what
        // the timeline's Daycare tag is for).
        let lo = when.addingTimeInterval(-Self.duplicateWindow)
        let hi = when.addingTimeInterval(Self.duplicateWindow)
        let source = EventSource.brightwheel.rawValue
        switch action {
        case "ac_food" where activity.isBottle && activity.bottleOz != nil:
            return fetchCount(FetchDescriptor<FeedEvent>(predicate: #Predicate {
                $0.sourceRaw == source && $0.timestamp >= lo && $0.timestamp <= hi
            })) > 0
        case "ac_potty", "ac_bathroom":
            return fetchCount(FetchDescriptor<DiaperEvent>(predicate: #Predicate {
                $0.sourceRaw == source && $0.timestamp >= lo && $0.timestamp <= hi
            })) > 0
        default:
            return fetchCount(FetchDescriptor<NoteEvent>(predicate: #Predicate {
                $0.sourceRaw == source && $0.timestamp >= lo && $0.timestamp <= hi
            })) > 0
        }
    }

    /// Deleted events count on purpose: a daycare entry the parents
    /// deliberately removed must not resurrect on the next sync (which is
    /// also why the time-window fallbacks above don't filter `deletedAt`).
    private func hasEvent(externalID id: String) -> Bool {
        fetchCount(FetchDescriptor<FeedEvent>(predicate: #Predicate { $0.externalID == id })) > 0
            || fetchCount(FetchDescriptor<SleepEvent>(predicate: #Predicate { $0.externalID == id })) > 0
            || fetchCount(FetchDescriptor<DiaperEvent>(predicate: #Predicate { $0.externalID == id })) > 0
            || fetchCount(FetchDescriptor<NoteEvent>(predicate: #Predicate { $0.externalID == id })) > 0
    }

    private func fetchCount<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> Int {
        (try? context.fetchCount(descriptor)) ?? 0
    }
}

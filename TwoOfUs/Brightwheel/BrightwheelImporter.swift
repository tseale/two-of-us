import Foundation
import SwiftData

/// Turns Brightwheel activities into Two of Us events. Source-agnostic: the
/// mock day, a pasted JSON file, and the live API all hand it the same
/// decoded wire format, so swapping in real data changes nothing downstream.
///
/// Imported events are ordinary Two of Us events — bottles become FeedEvents,
/// naps SleepEvents, diaper changes DiaperEvents, and the daycare-era types
/// map to their own models (ActivityEvent, MediaEvent, CheckEvent,
/// MedicationEvent, HealthCheckEvent, MoodEvent, PottyEvent, MilestoneEvent,
/// StaffNoteEvent) — all stamped `source: .brightwheel` + the activity's
/// `object_id` as `externalID`. That is what makes the timeline, CloudKit
/// sync, stats, and the prediction engine consume them with zero extra
/// plumbing, exactly like SNOO sleeps.
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
        var activities = 0
        var media = 0
        var checks = 0
        var medications = 0
        var healthChecks = 0
        var moods = 0
        var potties = 0
        var milestones = 0
        var staffNotes = 0
        var skippedDuplicates = 0
        var skippedUnmapped = 0

        var imported: Int {
            feeds + sleeps + diapers + notes + activities + media + checks
                + medications + healthChecks + moods + potties + milestones + staffNotes
        }

        var line: String {
            guard imported > 0 else { return "Nothing new to import." }
            // The trackers get named; everything else lumps into "more" — the
            // timeline tells the full story.
            var parts: [String] = []
            if feeds > 0 { parts.append(Plural.count(feeds, "feed")) }
            if sleeps > 0 { parts.append(Plural.count(sleeps, "nap")) }
            if diapers > 0 { parts.append(Plural.count(diapers, "diaper")) }
            let more = imported - feeds - sleeps - diapers
            if more > 0 {
                parts.append(parts.isEmpty
                    ? "\(more) daycare \(more == 1 ? "entry" : "entries")"
                    : "\(more) more")
            }
            return "Imported " + parts.joined(separator: ", ") + "."
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
        case "ac_potty":
            if let type = diaperType(from: activity) {
                if store.logDiaper(type, at: when, notes: activity.note,
                                   source: .brightwheel, externalID: id) != nil {
                    summary.diapers += 1
                }
            } else if store.logNote(noteText("Diaper check — dry", activity.note), at: when,
                                    source: .brightwheel, externalID: id) != nil {
                summary.notes += 1
            }
        case "ac_bathroom":
            // Toilet, not diaper — the older-kid rooms' kind (takeout's query
            // filter). The per-entry blob is unverified until Miller is old
            // enough to produce one; keyword fallback covers the meantime.
            if store.logPotty(pottyOutcome(from: activity), at: when, notes: activity.note,
                              source: .brightwheel, externalID: id) != nil {
                summary.potties += 1
            }
        case "ac_checkin":
            if store.logCheck(checkType(from: activity), at: when,
                              byName: byName(from: activity.note), notes: activity.note,
                              source: .brightwheel, externalID: id) != nil {
                summary.checks += 1
            }
        case "ac_activity", "ac_learning_activity":
            if store.logActivity(activityType(from: activity), at: when,
                                 durationMinutes: activity.detailsBlob?.durationMinutes,
                                 notes: activity.note,
                                 source: .brightwheel, externalID: id) != nil {
                summary.activities += 1
            }
        case "ac_photo", "ac_video":
            let kind: MediaKind = action == "ac_video" ? .video : .photo
            let url = kind == .video
                ? (activity.videoInfo?.streamableURL ?? activity.videoInfo?.downloadableURL)
                : (activity.media?.imageURL ?? activity.media?.thumbnailURL)
            // Caching the bytes locally (so the photo outlives the signed CDN
            // link) is a later phase — the row falls back to the URL, then a
            // placeholder.
            if store.logMedia(kind, at: when, caption: activity.note, remoteURL: url,
                              source: .brightwheel, externalID: id) != nil {
                summary.media += 1
            }
        case "ac_meds", "ac_medication":
            if store.logMedication(name: activity.detailsBlob?.medicationName ?? "Medication",
                                   dosage: activity.detailsBlob?.dosage, at: when,
                                   administeredBy: staffName(activity), notes: activity.note,
                                   source: .brightwheel, externalID: id) != nil {
                summary.medications += 1
            }
        case "ac_health_check", "ac_health_screen":
            if let (type, value) = healthMeasurement(from: activity) {
                if store.logHealthCheck(type, value: value, at: when, notes: activity.note,
                                        source: .brightwheel, externalID: id) != nil {
                    summary.healthChecks += 1
                }
            } else if let text = activity.note,
                      store.logStaffNote(text, authorName: staffName(activity), at: when,
                                         source: .brightwheel, externalID: id) != nil {
                // A check with no parseable measurement is still worth reading.
                summary.staffNotes += 1
            } else {
                summary.skippedUnmapped += 1
            }
        case "ac_mood":
            // ⚠️ SPECULATIVE action type — not in the 2026-09-28 bundle
            // taxonomy. Handled defensively in case Brightwheel adds it; the
            // MoodEvent model itself is exercised by the mock day.
            if store.logMood(moodLevel(from: activity), at: when, notes: activity.note,
                             source: .brightwheel, externalID: id) != nil {
                summary.moods += 1
            }
        case "ac_note", "ac_observation", "ac_kudo", "ac_incident", "ac_milestone":
            guard let text = activity.note, !text.isEmpty else {
                summary.skippedUnmapped += 1
                return
            }
            // Observations tagged with a development domain read as
            // milestones ("Rolled over!" + [Physical]); everything else is a
            // staff note, quote-card style. (`ac_milestone` itself is
            // speculative, like `ac_mood`.)
            if action == "ac_milestone" || (action == "ac_observation" && milestoneCategory(from: activity) != nil) {
                if store.logMilestone(text, category: milestoneCategory(from: activity) ?? .physical,
                                      at: when, source: .brightwheel, externalID: id) != nil {
                    summary.milestones += 1
                }
            } else if store.logStaffNote(text, authorName: staffName(activity), at: when,
                                         source: .brightwheel, externalID: id) != nil {
                summary.staffNotes += 1
            }
        default:
            // ac_absence, ac_internal_checkin, and anything Brightwheel adds
            // after this build.
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
        let lowered = detailWords(of: activity)
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

    // MARK: Keyword mapping (wire vocabulary → typed enums)
    //
    // The per-type blobs for the daycare-era kinds are unverified until
    // Miller's first real day (see BrightwheelDTOs.DetailsBlob) — these scan
    // the blob words AND the note, and every one has a safe default, so an
    // unrecognized vocabulary degrades to a generic-but-correct event, never
    // a dropped one.

    /// The activity's descriptive words: `potty_type`, extras, tags — lowered.
    private func detailWords(of activity: BrightwheelActivity) -> [String] {
        let blob = activity.detailsBlob
        var words = [blob?.pottyType ?? ""]
        words += blob?.pottyExtras ?? []
        words += blob?.tags ?? []
        return words.map { $0.lowercased() }
    }

    /// Detail words plus the free-text note, for the fuzzier lookups.
    private func allWords(of activity: BrightwheelActivity) -> [String] {
        var words = detailWords(of: activity)
        if let note = activity.note { words.append(note.lowercased()) }
        return words
    }

    private func checkType(from activity: BrightwheelActivity) -> CheckType {
        let words = allWords(of: activity)
        if words.contains(where: { $0.contains("out") || $0.contains("pick") }) {
            return .checkOut
        }
        return .checkIn
    }

    /// "Dropped off by Dad" → "Dad".
    private func byName(from note: String?) -> String? {
        guard let note,
              let range = note.range(of: " by ", options: .caseInsensitive) else { return nil }
        let name = note[range.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!"))
        return name.isEmpty ? nil : name
    }

    private func activityType(from activity: BrightwheelActivity) -> ActivityType {
        let words = allWords(of: activity)
        func has(_ keywords: String...) -> Bool {
            words.contains { word in keywords.contains { word.contains($0) } }
        }
        if has("tummy") { return .tummyTime }
        if has("outdoor", "outside", "walk", "playground") { return .outdoorPlay }
        if has("craft", "art", "paint") { return .crafts }
        if has("read", "book", "story") { return .reading }
        if has("circle") { return .circleTime }
        if has("sensory") { return .sensoryPlay }
        if has("music", "song", "sing") { return .music }
        return .freePlay
    }

    private func pottyOutcome(from activity: BrightwheelActivity) -> PottyOutcome {
        let words = allWords(of: activity)
        if words.contains(where: { $0.contains("accident") }) { return .accident }
        if words.contains(where: { $0.contains("success") || $0.contains("pee") || $0.contains("bm") || $0.contains("poop") }) {
            return .success
        }
        return .attempt
    }

    private func moodLevel(from activity: BrightwheelActivity) -> MoodLevel {
        var words = allWords(of: activity)
        if let mood = activity.detailsBlob?.mood { words.insert(mood.lowercased(), at: 0) }
        func has(_ keywords: String...) -> Bool {
            words.contains { word in keywords.contains { word.contains($0) } }
        }
        if has("happy", "great", "smil") { return .happy }
        if has("fussy", "cranky") { return .fussy }
        if has("upset", "cry", "sad") { return .upset }
        if has("sleepy", "tired", "drowsy") { return .sleepy }
        return .content
    }

    /// Temperature from the blob or the note ("Temp 98.6°F"), else a weight
    /// ("12.4 lb"); nil means no parseable measurement.
    private func healthMeasurement(from activity: BrightwheelActivity) -> (HealthCheckType, Double)? {
        if let temp = activity.detailsBlob?.temperature, temp > 0 {
            return (.temperature, temp)
        }
        guard let note = activity.note else { return nil }
        if let match = note.firstMatch(of: /([0-9]{2,3}(?:\.[0-9])?)\s*°?\s*[Ff]/),
           let value = Double(match.1) {
            return (.temperature, value)
        }
        if let match = note.firstMatch(of: /([0-9]+(?:\.[0-9]+)?)\s*(?:lbs?|pounds)/.ignoresCase()),
           let value = Double(match.1) {
            return (.weight, value)
        }
        return nil
    }

    /// A development-domain tag makes an observation a milestone.
    private func milestoneCategory(from activity: BrightwheelActivity) -> MilestoneCategory? {
        let words = detailWords(of: activity)
        func has(_ keywords: String...) -> Bool {
            words.contains { word in keywords.contains { word.contains($0) } }
        }
        if has("physical", "gross motor", "fine motor") { return .physical }
        if has("cognitive", "problem solving") { return .cognitive }
        if has("social", "emotional") { return .social }
        if has("language", "communication") { return .language }
        return nil
    }

    private func staffName(_ activity: BrightwheelActivity) -> String? {
        let parts = [activity.actor?.firstName, activity.actor?.lastName]
            .compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
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
        case "ac_potty":
            return fetchCount(FetchDescriptor<DiaperEvent>(predicate: #Predicate {
                $0.sourceRaw == source && $0.timestamp >= lo && $0.timestamp <= hi
            })) > 0
        case "ac_bathroom":
            return fetchCount(FetchDescriptor<PottyEvent>(predicate: #Predicate {
                $0.sourceRaw == source && $0.timestamp >= lo && $0.timestamp <= hi
            })) > 0
        case "ac_checkin":
            return fetchCount(FetchDescriptor<CheckEvent>(predicate: #Predicate {
                $0.sourceRaw == source && $0.timestamp >= lo && $0.timestamp <= hi
            })) > 0
        case "ac_activity", "ac_learning_activity":
            return fetchCount(FetchDescriptor<ActivityEvent>(predicate: #Predicate {
                $0.sourceRaw == source && $0.timestamp >= lo && $0.timestamp <= hi
            })) > 0
        case "ac_photo", "ac_video":
            return fetchCount(FetchDescriptor<MediaEvent>(predicate: #Predicate {
                $0.sourceRaw == source && $0.timestamp >= lo && $0.timestamp <= hi
            })) > 0
        case "ac_meds", "ac_medication":
            return fetchCount(FetchDescriptor<MedicationEvent>(predicate: #Predicate {
                $0.sourceRaw == source && $0.timestamp >= lo && $0.timestamp <= hi
            })) > 0
        case "ac_health_check", "ac_health_screen":
            return fetchCount(FetchDescriptor<HealthCheckEvent>(predicate: #Predicate {
                $0.sourceRaw == source && $0.timestamp >= lo && $0.timestamp <= hi
            })) > 0
        case "ac_mood":
            return fetchCount(FetchDescriptor<MoodEvent>(predicate: #Predicate {
                $0.sourceRaw == source && $0.timestamp >= lo && $0.timestamp <= hi
            })) > 0
        default:
            // Note-ish kinds can land as StaffNoteEvent, MilestoneEvent, or
            // NoteEvent — a same-window Brightwheel entry in any of them
            // counts as the same re-issued activity.
            return fetchCount(FetchDescriptor<StaffNoteEvent>(predicate: #Predicate {
                $0.sourceRaw == source && $0.timestamp >= lo && $0.timestamp <= hi
            })) > 0
                || fetchCount(FetchDescriptor<MilestoneEvent>(predicate: #Predicate {
                    $0.sourceRaw == source && $0.timestamp >= lo && $0.timestamp <= hi
                })) > 0
                || fetchCount(FetchDescriptor<NoteEvent>(predicate: #Predicate {
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
            || fetchCount(FetchDescriptor<ActivityEvent>(predicate: #Predicate { $0.externalID == id })) > 0
            || fetchCount(FetchDescriptor<MediaEvent>(predicate: #Predicate { $0.externalID == id })) > 0
            || fetchCount(FetchDescriptor<CheckEvent>(predicate: #Predicate { $0.externalID == id })) > 0
            || fetchCount(FetchDescriptor<MedicationEvent>(predicate: #Predicate { $0.externalID == id })) > 0
            || fetchCount(FetchDescriptor<HealthCheckEvent>(predicate: #Predicate { $0.externalID == id })) > 0
            || fetchCount(FetchDescriptor<MoodEvent>(predicate: #Predicate { $0.externalID == id })) > 0
            || fetchCount(FetchDescriptor<PottyEvent>(predicate: #Predicate { $0.externalID == id })) > 0
            || fetchCount(FetchDescriptor<MilestoneEvent>(predicate: #Predicate { $0.externalID == id })) > 0
            || fetchCount(FetchDescriptor<StaffNoteEvent>(predicate: #Predicate { $0.externalID == id })) > 0
    }

    private func fetchCount<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> Int {
        (try? context.fetchCount(descriptor)) ?? 0
    }
}

import CloudKit
import Foundation
import SwiftData

/// How the dynamic nighttime schedule assigns parents to feed slots.
/// Raw-string backed so it syncs as a plain field and an unknown future value
/// degrades to the default instead of crashing an older build.
enum NightRotation: String, CaseIterable {
    /// Whoever logs tonight's first feed takes it; later slots alternate
    /// through the active parents from there.
    case alternating
    /// No assignments — every slot stays unassigned, so both phones ring.
    case none
}

/// App-wide settings that are shared between all participants (synced in
/// Increment 2). Stored as a single record.
@Model
final class SharedSettings {
    var id: UUID = UUID()
    var targetFeedIntervalMinutes: Int = 180   // next-feed countdown target (3h)
    var ozPresets: [Double] = [2, 3, 4]
    var defaultFeedOz: Double = 4              // one-tap feed amount (widget / Siri)
    // Per-kind tracker switches — shared, so both parents see the same buttons.
    // Turning one off hides its logging UI and blocks new events of that kind;
    // existing entries stay. Defaulted (not optional) so pre-upgrade stores and
    // records that predate the field read as "on".
    var feedLoggingEnabled: Bool = true
    var diaperLoggingEnabled: Bool = true
    var sleepLoggingEnabled: Bool = true
    // Nighttime schedule — the shared overnight rotation both parents see.
    // Wall-clock minutes-from-midnight (same convention as PlanSlot.minuteOfDay)
    // so the window survives DST and renders identically on both phones.
    // Defaulted (not optional) so pre-upgrade stores and records that predate
    // the fields read as the standard 8pm–8am night.
    var nightStartMinute: Int = 1200           // night starts 8:00 PM
    var nightEndMinute: Int = 480              // night ends 8:00 AM
    /// Legacy fixed anchor — unused since the schedule went dynamic (the first
    /// logged nighttime feed anchors the night now). Kept, and still synced, so
    /// older builds sharing the zone keep reading a sane value.
    var nightFirstFeedMinute: Int = 1260       // first feed 9:00 PM
    var nightFeedSpacingMinutes: Int = 180     // 3h between night feeds
    var nightRotationRaw: String = NightRotation.alternating.rawValue
    /// Who takes the night's first shift (→ Participant.id); the rotation
    /// alternates from them. Nil = the first parent in join order.
    var nightFirstShiftID: UUID?
    /// The household SNOO connection (`SnooSharedCredentials` JSON; nil = not
    /// connected). One parent signs in and every participant's device adopts
    /// the refresh token from here — deliberately shared account access, the
    /// same trust boundary as the rest of the zone. Never the password (§5).
    var snooCredentials: String?
    /// On-device predictions + the Stats insights card. Family-wide (one baby,
    /// one policy — same reasoning as the tracker toggles). Defaulted (not
    /// optional) so pre-upgrade stores and records that predate the field
    /// read as "on".
    var aiPredictionsEnabled: Bool = true
    var ckSystemFields: Data?                  // archived CKRecord system fields (see Baby.ckSystemFields)

    init(
        id: UUID = UUID(),
        targetFeedIntervalMinutes: Int = 180,
        ozPresets: [Double] = [2, 3, 4],
        defaultFeedOz: Double = 4,
        feedLoggingEnabled: Bool = true,
        diaperLoggingEnabled: Bool = true,
        sleepLoggingEnabled: Bool = true,
        nightStartMinute: Int = 1200,
        nightEndMinute: Int = 480,
        nightFirstFeedMinute: Int = 1260,
        nightFeedSpacingMinutes: Int = 180,
        nightRotation: NightRotation = .alternating,
        nightFirstShiftID: UUID? = nil,
        aiPredictionsEnabled: Bool = true
    ) {
        self.id = id
        self.targetFeedIntervalMinutes = targetFeedIntervalMinutes
        self.ozPresets = ozPresets
        self.defaultFeedOz = defaultFeedOz
        self.feedLoggingEnabled = feedLoggingEnabled
        self.diaperLoggingEnabled = diaperLoggingEnabled
        self.sleepLoggingEnabled = sleepLoggingEnabled
        self.nightStartMinute = nightStartMinute
        self.nightEndMinute = nightEndMinute
        self.nightFirstFeedMinute = nightFirstFeedMinute
        self.nightFeedSpacingMinutes = nightFeedSpacingMinutes
        self.nightRotationRaw = nightRotation.rawValue
        self.nightFirstShiftID = nightFirstShiftID
        self.aiPredictionsEnabled = aiPredictionsEnabled
    }

    /// The interval that should drive "when's the next bottle" after a feed at
    /// `lastFeed`: the night spacing when the bottle it predicts would land
    /// inside the night window — that bottle IS the night's first (or next)
    /// feed under the anchor rules, so a 7:45pm feed against an 11pm–8am/4h
    /// night predicts 11:45pm, not a daytime 10:45 — else the daytime target.
    /// This is the ONE place day-vs-night branches: the feed card, reminders,
    /// alarms, and widgets all call it so none of them can drift from what
    /// the Tonight card itself is counting down to.
    func feedInterval(after lastFeed: Date, calendar: Calendar = .current) -> TimeInterval {
        let night = TimeInterval(nightFeedSpacingMinutes * 60)
        let c = calendar.dateComponents([.hour, .minute], from: lastFeed.addingTimeInterval(night))
        let minuteOfDay = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        let isNightFeed = NightScheduleGenerator.isWithinNight(
            minuteOfDay: minuteOfDay,
            nightStartMinute: nightStartMinute,
            nightEndMinute: nightEndMinute
        )
        return isNightFeed ? night : TimeInterval(targetFeedIntervalMinutes * 60)
    }

    /// Deterministic winner among SharedSettings rows. The record is a
    /// singleton by intent, but a reinstall that re-onboards into an existing
    /// zone mints a second row (upsert is by UUID) — and an unordered
    /// `.first` then lets two devices read DIFFERENT rows, splitting a value
    /// one phone wrote from the row the other phone reads.
    ///
    /// The ESTABLISHED record must win — the earliest server creation date
    /// (from `ckSystemFields`, identical on every synced device), so a
    /// reinstall's freshly-minted defaults row can never dethrone (and, via
    /// the merge pass, zone-delete) the household's configured record. Rows
    /// that never reached the server sort last; ties fall back to UUID so the
    /// pick stays total and device-independent either way.
    /// `SyncManager.mergeDuplicateSettingsIfNeeded` folds and deletes losers.
    static func canonical(_ rows: [SharedSettings]) -> SharedSettings? {
        rows.min { a, b in
            switch (a.serverCreatedAt, b.serverCreatedAt) {
            case let (x?, y?) where x != y: return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a.id.uuidString < b.id.uuidString
            }
        }
    }

    /// When the server first stored this row — decoded from the archived
    /// CKRecord system fields; nil until the record has round-tripped.
    /// Decoded inline (not via RecordMapping) because this file also compiles
    /// into targets that don't include the Sync sources.
    private var serverCreatedAt: Date? {
        guard let data = ckSystemFields,
              let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)?.creationDate
    }

    /// An unknown raw value (a future build's new pattern) reads as the
    /// default rather than crashing or silently disabling the rotation.
    var nightRotation: NightRotation {
        get { NightRotation(rawValue: nightRotationRaw) ?? .alternating }
        set { nightRotationRaw = newValue.rawValue }
    }

    private func rawEnabled(_ kind: EventKind) -> Bool {
        switch kind {
        case .feed: return feedLoggingEnabled
        case .diaper: return diaperLoggingEnabled
        case .sleep: return sleepLoggingEnabled
        }
    }

    /// Whether `kind` is being tracked. An all-off state can only arise from a
    /// sync merge of two parents' concurrent toggles (the UI pins the last
    /// tracker on) — it would hide every log button, so it fails open to all-on.
    func isEnabled(_ kind: EventKind) -> Bool {
        EventKind.allCases.contains(where: rawEnabled) ? rawEnabled(kind) : true
    }

    /// How many trackers are on. The UI refuses to drop below one — an app with
    /// nothing to log is a brick — and `EventStore.updateSettings` backstops it.
    var enabledTrackerCount: Int {
        EventKind.allCases.count(where: isEnabled)
    }
}

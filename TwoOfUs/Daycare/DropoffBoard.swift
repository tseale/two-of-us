import Foundation
import SwiftData

/// The drop-off whiteboard's answers — display strings, not raw events: the
/// card (`DropoffBoardSheet`), the geofence drop-off notification, and the
/// notification's expanded view all read the same five rows.
struct DropoffBoardInfo: Identifiable {
    let id = UUID()
    let name: String
    let lastBottle: String?       // "6:45 AM · 4 oz"
    let lastDiaper: String?       // "7:10 AM · wet"
    let wokeUpAt: String?         // "6:30 AM"
    let overnightSleep: String?   // "10h 2m — slept well"
    let notes: String?            // recent parent notes; nil reads "None"

    /// The whole card as plain text, for the Copy button — the same rows,
    /// one per line, pasteable into a message to the daycare too.
    var clipboardText: String {
        """
        \(name)
        Last bottle: \(lastBottle ?? "—")
        Last diaper: \(lastDiaper ?? "—")
        Woke up at: \(wokeUpAt ?? "—")
        Sleep: \(overnightSleep ?? "—")
        Notes: \(notes ?? "None")
        """
    }

    /// The rows as a notification body: one line per answer the daycare
    /// asks for, so the lock-screen banner IS the whiteboard. Empty rows
    /// are dropped rather than shown as "—" (the banner has four lines of
    /// room; a dash wastes one), and wake time shares a line with the
    /// overnight total so the four core answers fit even on a full morning.
    var notificationBody: String {
        var lines: [String] = []
        if let lastBottle { lines.append("🍼 Last bottle \(lastBottle)") }
        if let lastDiaper { lines.append("💧 Last diaper \(lastDiaper)") }
        let sleep = [wokeUpAt.map { "☀️ Woke \($0)" },
                     overnightSleep.map { "💤 \($0)" }].compactMap { $0 }
        if !sleep.isEmpty { lines.append(sleep.joined(separator: " · ")) }
        if let notes { lines.append("📝 \(notes)") }
        return lines.joined(separator: "\n")
    }

    // MARK: Notification userInfo

    /// Carried on the drop-off notification so the content extension can
    /// render the rows even when it can't open the App Group store — and so
    /// the expanded card shows the same answers the banner did.
    private enum Key {
        static let name = "board.name"
        static let lastBottle = "board.lastBottle"
        static let lastDiaper = "board.lastDiaper"
        static let wokeUpAt = "board.wokeUpAt"
        static let overnightSleep = "board.overnightSleep"
        static let notes = "board.notes"
    }

    var userInfo: [String: String] {
        var info = [Key.name: name]
        info[Key.lastBottle] = lastBottle
        info[Key.lastDiaper] = lastDiaper
        info[Key.wokeUpAt] = wokeUpAt
        info[Key.overnightSleep] = overnightSleep
        info[Key.notes] = notes
        return info
    }

    init(name: String, lastBottle: String?, lastDiaper: String?,
         wokeUpAt: String?, overnightSleep: String?, notes: String?) {
        self.name = name
        self.lastBottle = lastBottle
        self.lastDiaper = lastDiaper
        self.wokeUpAt = wokeUpAt
        self.overnightSleep = overnightSleep
        self.notes = notes
    }

    /// nil when the payload isn't a board (any other notification's userInfo).
    init?(userInfo: [AnyHashable: Any]) {
        guard let name = userInfo[Key.name] as? String else { return nil }
        self.init(name: name,
                  lastBottle: userInfo[Key.lastBottle] as? String,
                  lastDiaper: userInfo[Key.lastDiaper] as? String,
                  wokeUpAt: userInfo[Key.wokeUpAt] as? String,
                  overnightSleep: userInfo[Key.overnightSleep] as? String,
                  notes: userInfo[Key.notes] as? String)
    }
}

/// Builds the whiteboard from the app's own data. Pure `compute` takes
/// value tuples (HomeView passes its @Query arrays, tests pass fixtures);
/// `load` fetches them from any context — the app's main context when the
/// geofence prompt posts, the App Group store inside the notification
/// content extension.
enum DropoffBoard {

    /// Compiles everywhere `DropoffBoardInfo` does; `NoteEvent` and friends
    /// aren't needed — only their fields.
    struct Feed { let timestamp: Date; let amountOz: Double }
    struct Diaper { let timestamp: Date; let typeLabel: String }
    struct Sleep { let startedAt: Date; let endedAt: Date? }
    struct Note { let timestamp: Date; let text: String; let isFromDaycare: Bool }

    /// - Parameters:
    ///   - feeds, diapers, sleeps, notes: live (non-deleted) events, NEWEST
    ///     FIRST — the order every `@Query` on Home already uses.
    ///   - nightStartMinute / nightEndMinute: the configured night window;
    ///     "overnight" is yesterday's start through this morning's end.
    static func compute(
        name: String,
        feeds: [Feed],
        diapers: [Diaper],
        sleeps: [Sleep],
        notes: [Note],
        nightStartMinute: Int,
        nightEndMinute: Int,
        dayStart: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> DropoffBoardInfo {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: dayStart) ?? dayStart
        let windowStart = yesterday.addingTimeInterval(TimeInterval(nightStartMinute * 60))
        let windowEnd = dayStart.addingTimeInterval(TimeInterval(nightEndMinute * 60))

        let bottle = feeds.first.map {
            "\(TimeFormatting.clock($0.timestamp)) · \(OzFormat.string($0.amountOz)) oz"
        }
        let diaper = diapers.first.map {
            "\(TimeFormatting.clock($0.timestamp)) · \($0.typeLabel.lowercased())"
        }

        // Overnight total: every sleep's overlap with the night window — the
        // 10 PM–6 AM stretch whole, a 5 AM catnap's share, nothing from
        // yesterday's daytime naps.
        let overnightSeconds = sleeps.reduce(TimeInterval(0)) { total, sleep in
            let end = sleep.endedAt ?? now
            let overlap = min(end, windowEnd).timeIntervalSince(max(sleep.startedAt, windowStart))
            return total + max(0, overlap)
        }
        let overnight: String? = overnightSeconds >= 60 ? {
            let quality = overnightSeconds >= 9 * 3600 ? "slept well"
                : overnightSeconds >= 7 * 3600 ? "slept okay" : "a restless night"
            return "\(TimeFormatting.duration(minutes: Int(overnightSeconds / 60))) — \(quality)"
        }() : nil

        // Parents' own notes since the night window opened (the daycare's
        // notes came FROM the daycare — nothing to tell them back), oldest
        // first: the order they were written in.
        let noteTexts = notes
            .prefix(while: { $0.timestamp >= windowStart })
            .filter { !$0.isFromDaycare && !$0.text.isEmpty }
            .map(\.text)

        return DropoffBoardInfo(
            name: name,
            lastBottle: bottle,
            lastDiaper: diaper,
            wokeUpAt: sleeps.first(where: { $0.endedAt != nil })?.endedAt.map(TimeFormatting.clock),
            overnightSleep: overnight,
            notes: noteTexts.isEmpty ? nil : noteTexts.reversed().joined(separator: " · "))
    }

    /// The board off a store: the same queries Home's tiles use, newest first.
    static func load(from context: ModelContext, now: Date = .now,
                     calendar: Calendar = .current) -> DropoffBoardInfo {
        let settings = SharedSettings.canonical(
            (try? context.fetch(FetchDescriptor<SharedSettings>())) ?? [])
        let name = (try? context.fetch(FetchDescriptor<Baby>()))?.first
            .flatMap { $0.name.isEmpty ? nil : $0.name } ?? "Baby"
        // Last bottle / diaper are the newest live rows, however old (Home
        // shows the same); overnight sleep and notes only look back to
        // yesterday evening, so a 48h slice is plenty for those.
        let since = now.addingTimeInterval(-48 * 3600)

        var feedQuery = FetchDescriptor<FeedEvent>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        feedQuery.fetchLimit = 1
        let feeds = ((try? context.fetch(feedQuery)) ?? [])
            .map { Feed(timestamp: $0.timestamp, amountOz: $0.amountOz) }
        var diaperQuery = FetchDescriptor<DiaperEvent>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        diaperQuery.fetchLimit = 1
        let diapers = ((try? context.fetch(diaperQuery)) ?? [])
            .map { Diaper(timestamp: $0.timestamp, typeLabel: $0.type.label) }
        let sleeps = ((try? context.fetch(FetchDescriptor<SleepEvent>(
            predicate: #Predicate { $0.deletedAt == nil && $0.startedAt >= since },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))) ?? [])
            .map { Sleep(startedAt: $0.startedAt, endedAt: $0.endedAt) }
        let notes = ((try? context.fetch(FetchDescriptor<NoteEvent>(
            predicate: #Predicate { $0.deletedAt == nil && $0.timestamp >= since },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]))) ?? [])
            .map { Note(timestamp: $0.timestamp, text: $0.text, isFromDaycare: $0.isFromDaycare) }

        return compute(
            name: name,
            feeds: feeds, diapers: diapers, sleeps: sleeps, notes: notes,
            nightStartMinute: settings?.nightStartMinute ?? 1200,
            nightEndMinute: settings?.nightEndMinute ?? 480,
            dayStart: calendar.startOfDay(for: now),
            now: now, calendar: calendar)
    }
}

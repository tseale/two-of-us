import Foundation

/// The "Today's outlook" card, assembled — not generated. Every row is a
/// number the prediction engine computed plus the basis it rests on, so the
/// card reads like a knowledgeable co-parent ("next bottle ~8:55 PM · ~5 oz")
/// and can never invent a nap that doesn't exist. This replaced a Foundation
/// Models generation step that kept parroting its own prompt example ("the
/// 2:15 nap") — the numbers were always the engine's; now the words are too.
///
/// Pure functions over plain values, `PredictionEngine`-style: callers fetch
/// and map. Rows appear only at medium-or-better confidence — better no
/// prediction than a bad one — so an empty array means "hide the card."
enum TodayOutlook {

    struct Row: Equatable, Identifiable {
        enum Kind: String { case nextFeed, wake, nextNap, bedtime }
        let kind: Kind
        /// Short all-caps-styled label, e.g. "Next bottle".
        let title: String
        /// The prediction itself, e.g. "~8:55 PM · ~5 oz".
        let value: String
        /// Where the number came from, e.g. "usually ~3h10m between feeds ·
        /// last fed 5:40 PM" — explainability is the trust feature.
        let basis: String

        var id: String { kind.rawValue }
    }

    // swiftlint:disable:next function_body_length
    static func rows(
        feeds: [(timestamp: Date, oz: Double)],
        sleeps: [(startedAt: Date, endedAt: Date?)],
        dateOfBirth: Date,
        targetFeedInterval: (Date) -> TimeInterval,
        nightStartMinute: Int,
        nightEndMinute: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Row] {
        let ageInDays = WakeWindow.ageInDays(dateOfBirth: dateOfBirth, now: now, calendar: calendar)
        let isNightNow = WakeWindow.isNight(now, startMinute: nightStartMinute,
                                            endMinute: nightEndMinute, calendar: calendar)
        var rows: [Row] = []

        // Next bottle — anchored to the last feed, sized for the predicted
        // moment. Past-due reads "any time now" rather than vanishing: the
        // interval evidence is unchanged, only the clock has moved.
        if let lastFeed = feeds.map(\.timestamp).max() {
            let next = PredictionEngine.nextFeed(
                lastFeed: lastFeed, feeds: feeds.map(\.timestamp),
                targetInterval: targetFeedInterval(lastFeed),
                nightStartMinute: nightStartMinute, nightEndMinute: nightEndMinute,
                now: now, calendar: calendar)
            if next.confidence != .low {
                let amount = PredictionEngine.feedAmount(
                    feeds: feeds, ageInDays: ageInDays, at: max(next.date, now),
                    nightStartMinute: nightStartMinute, nightEndMinute: nightEndMinute,
                    now: now, calendar: calendar)
                var value = next.date > now ? "~\(TimeFormatting.clock(next.date))" : "any time now"
                if amount.confidence != .low { value += " · ~\(OzFormat.string(amount.oz)) oz" }
                rows.append(Row(
                    kind: .nextFeed, title: "Next bottle", value: value,
                    basis: "usually ~\(WakeWindow.shortLabel(next.date.timeIntervalSince(lastFeed))) "
                        + "between feeds · last fed \(TimeFormatting.clock(lastFeed))"))
            }
        }

        let completed = sleeps.filter { $0.endedAt != nil }
        let running = sleeps.filter { $0.endedAt == nil }.max { $0.startedAt < $1.startedAt }

        if let running {
            // He's down right now: the question is when he surfaces.
            let duration = PredictionEngine.sleepDuration(
                startingAt: running.startedAt, sleeps: sleeps,
                ageInDays: ageInDays,
                nightStartMinute: nightStartMinute, nightEndMinute: nightEndMinute,
                now: now, calendar: calendar)
            let wake = running.startedAt.addingTimeInterval(duration.duration)
            if duration.confidence != .low, wake > now {
                rows.append(Row(
                    kind: .wake, title: "Waking up", value: "~\(TimeFormatting.clock(wake))",
                    basis: duration.isNight
                        ? "night stretches run ~\(WakeWindow.shortLabel(duration.duration)) lately"
                        : "naps run ~\(WakeWindow.shortLabel(duration.duration)) lately"))
            }
        } else if !isNightNow, let lastWake = completed.compactMap(\.endedAt).max() {
            // Awake in daytime: project the next nap from the wake window.
            let weekAgo = now.addingTimeInterval(-7 * 24 * 3600)
            let target = WakeWindow.predicted(
                ageInDays: ageInDays,
                observedGaps: WakeWindow.wakeGaps(
                    sleeps: sleeps.filter { $0.startedAt >= weekAgo },
                    nightStartMinute: nightStartMinute, nightEndMinute: nightEndMinute,
                    calendar: calendar),
                now: now)
            let napAt = lastWake.addingTimeInterval(target)
            // An evening wake projects into the night window — that's
            // bedtime's territory, not a nap's.
            if !WakeWindow.isNight(max(napAt, now), startMinute: nightStartMinute,
                                   endMinute: nightEndMinute, calendar: calendar) {
                let length = PredictionEngine.sleepDuration(
                    startingAt: max(napAt, now), sleeps: sleeps, ageInDays: ageInDays,
                    nightStartMinute: nightStartMinute, nightEndMinute: nightEndMinute,
                    now: now, calendar: calendar)
                var value = napAt > now ? "~\(TimeFormatting.clock(napAt))" : "due now"
                if length.confidence != .low, !length.isNight {
                    value += " · usually ~\(WakeWindow.shortLabel(length.duration))"
                }
                rows.append(Row(
                    kind: .nextNap, title: "Next nap", value: value,
                    basis: "after ~\(WakeWindow.shortLabel(target)) awake"))
            }
        }

        // Bedtime — shown while it's still ahead and he isn't already down
        // for the night.
        let downForTheNight = running.map {
            WakeWindow.isNight($0.startedAt, startMinute: nightStartMinute,
                               endMinute: nightEndMinute, calendar: calendar)
        } ?? false
        if !downForTheNight {
            let bed = PredictionEngine.bedtime(
                sleeps: sleeps, nightStartMinute: nightStartMinute,
                nightEndMinute: nightEndMinute, now: now, calendar: calendar)
            if bed.confidence != .low, bed.date > now {
                var basis = "usually down \(TimeFormatting.clock(bed.range.lowerBound))"
                    + "–\(TimeFormatting.clock(bed.range.upperBound))"
                let stretch = PredictionEngine.sleepDuration(
                    startingAt: bed.date, sleeps: sleeps, ageInDays: ageInDays,
                    nightStartMinute: nightStartMinute, nightEndMinute: nightEndMinute,
                    now: now, calendar: calendar)
                if stretch.confidence != .low, stretch.isNight {
                    basis += " · first stretch ~\(WakeWindow.shortLabel(stretch.duration))"
                }
                rows.append(Row(
                    kind: .bedtime, title: "Bedtime",
                    value: "~\(TimeFormatting.clock(bed.date))", basis: basis))
            }
        }

        return rows
    }
}

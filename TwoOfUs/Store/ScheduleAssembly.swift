import Foundation
import SwiftData

// App-target-only assembly of the two schedule sources — the standing
// (sleep-only) plan and the dynamic night feed schedule — into one occurrence
// list. Lives outside QuickLogger.swift on purpose: QuickLogger also compiles
// into the widget/notification extensions, which don't carry the engines.
// (The `NightSchedule(settings:participants:…)` init lives in
// NightSchedule.swift — the watch complication carries the engines too.)

extension QuickLogger {
    /// The full upcoming schedule this device should act on: standing sleep
    /// slots (with overrides applied) merged with tonight's dynamic feed
    /// schedule, ascending. Standing FEED slots are excluded even if some
    /// still exist locally (a not-yet-retired fixed-era slot, or one synced
    /// in from a co-parent's older build) — the dynamic schedule owns night
    /// feeds now, and rendering or ringing both would double every night.
    func scheduleOccurrences(lookback: TimeInterval = 0,
                             horizon: TimeInterval = 24 * 3600,
                             now: Date = .now) -> [ScheduleOccurrence] {
        let feeds = recentFeeds()
        let sleepSlots = planSlots.filter { $0.kind != .feed }
        let engine = ScheduleEngine(
            slots: sleepSlots,
            overrides: planOverrides,
            feeds: feeds, sleeps: recentSleeps(),
            now: now
        )
        var merged = engine.occurrences(lookback: lookback, horizon: horizon)
        if let settings = sharedSettings {
            let night = NightSchedule(settings: settings, participants: allParticipants,
                                      feeds: feeds, overrides: planOverrides,
                                      sleepSlots: sleepSlots, now: now)
            merged += night.occurrences().filter {
                $0.date >= now.addingTimeInterval(-lookback)
                    && $0.date <= now.addingTimeInterval(horizon)
            }
        }
        return merged.sorted { $0.date < $1.date }
    }

    /// The next expected feed, for the sleep Live Activity's trailing column.
    /// Two candidates, earliest wins:
    /// - the schedule's next upcoming feed occurrence (tonight's dynamic slot,
    ///   carrying its assigned parent) — but the schedule speaks for TONIGHT
    ///   even at noon, so it can't be taken unconditionally;
    /// - the canonical last-feed + interval prediction (the same
    ///   `feedInterval(after:)` maths the feed alarm re-arms with), which is
    ///   what "next feed" means during the day.
    /// A tie prefers the scheduled slot — it knows whose turn it is. Nil when
    /// there's nothing to predict from, or the only prediction is already past
    /// (the countdown would render frozen at 0:00 from the start).
    func nextFeedPrediction(now: Date = .now) -> SleepActivityManager.NextFeed? {
        let predicted: Date? = lastFeed.flatMap {
            let date = $0.timestamp.addingTimeInterval(feedInterval(after: $0.timestamp))
            return date > now ? date : nil
        }
        if let slot = scheduleOccurrences(now: now)
            .first(where: { $0.kind == .feed && $0.status == .upcoming }),
           slot.date <= predicted ?? .distantFuture {
            return SleepActivityManager.NextFeed(
                date: slot.date,
                ownerName: slot.assignedToName.isEmpty ? nil : slot.assignedToName,
                ownerColorHex: slot.assignedToColorHex.isEmpty ? nil : slot.assignedToColorHex
            )
        }
        return predicted.map { SleepActivityManager.NextFeed(date: $0, ownerName: nil, ownerColorHex: nil) }
    }
}

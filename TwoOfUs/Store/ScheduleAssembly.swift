import Foundation
import SwiftData

// App-target-only assembly of the two schedule sources — the standing
// (sleep-only) plan and the dynamic night feed schedule — into one occurrence
// list. Lives outside QuickLogger.swift on purpose: QuickLogger also compiles
// into the widget/notification extensions, which don't carry the engines.

extension NightSchedule {
    /// Builds tonight's engine from app models. Participants are filtered and
    /// ordered here (active, join order) so every call site derives the same
    /// rotation both phones agree on.
    init(settings: SharedSettings, participants: [Participant], feeds: [FeedEvent],
         calendar: Calendar = .current, now: Date = .now) {
        self.init(
            nightStartMinute: settings.nightStartMinute,
            nightEndMinute: settings.nightEndMinute,
            spacingMinutes: settings.nightFeedSpacingMinutes,
            rotation: settings.nightRotation,
            parents: participants
                .filter(\.isActive)
                .sorted { ($0.invitedAt, $0.id.uuidString) < ($1.invitedAt, $1.id.uuidString) }
                .map { Parent(id: $0.id, name: $0.displayName, colorHex: $0.colorHex) },
            feeds: feeds,
            calendar: calendar,
            now: now
        )
    }
}

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
        let engine = ScheduleEngine(
            slots: planSlots.filter { $0.kind != .feed },
            overrides: planOverrides,
            feeds: feeds, sleeps: recentSleeps(),
            now: now
        )
        var merged = engine.occurrences(lookback: lookback, horizon: horizon)
        if let settings = sharedSettings {
            let night = NightSchedule(settings: settings, participants: allParticipants,
                                      feeds: feeds, now: now)
            merged += night.occurrences().filter {
                $0.date >= now.addingTimeInterval(-lookback)
                    && $0.date <= now.addingTimeInterval(horizon)
            }
        }
        return merged.sorted { $0.date < $1.date }
    }
}

import Foundation
import SwiftData
import WidgetKit
import os

/// One read of the watch app's App Group store, shared by every complication
/// provider. A timeline build takes a single snapshot and stages entries from
/// it, so the store opens once per build — not once per fact displayed.
///
/// Freshness model (unchanged from the original Glance complication): the data
/// only moves when WatchSyncManager fetches or a log lands, and both already
/// call `WidgetCenter.reloadAllTimelines()` — so providers stage threshold
/// entries (urgency flips, slot times) and keep only a lazy fallback reload.
struct ComplicationSnapshot {
    /// The next expected bottle, resolved the same way the phone's sleep Live
    /// Activity does (`QuickLogger.nextFeedPrediction`): tonight's dynamic
    /// schedule slot when it's due no later than the plain projection (the
    /// slot knows whose turn it is), else last feed + the night-aware interval.
    struct NextFeed {
        let date: Date
        /// The parent on duty for tonight's slot; nil for plain projections
        /// and for unassigned slots (unassigned means both parents are up).
        let ownerName: String?
        /// True when `date` is one of tonight's schedule slots.
        let isNightSlot: Bool
    }

    let date: Date
    let babyName: String

    let lastFeedDate: Date?
    let lastFeedOz: Double?
    /// Night spacing when the next bottle lands in the night window, else the
    /// daytime target — `SharedSettings.feedInterval(after:)`, the one rule.
    let feedTargetInterval: TimeInterval

    let lastDiaperDate: Date?
    let lastDiaperType: DiaperType?

    /// Set while a sleep is running.
    let sleepStartedAt: Date?
    /// When the most recent finished sleep ended — the awake clock's zero.
    let lastSleepEndedAt: Date?
    let lastSleepDuration: TimeInterval?
    /// Age + observed-history wake window (`WakeWindow`), the sleep-side
    /// counterpart of the feed target.
    let sleepTargetInterval: TimeInterval

    let todayFeedCount: Int
    let todayFeedOz: Double
    let todaySleepMinutes: Int
    let todayDiaperCount: Int

    let nextFeed: NextFeed?
    /// True while tonight's schedule is speaking — the window is open or
    /// approaching (`NightSchedule.State` is not `.day`).
    let nightActive: Bool

    var nextFeedDate: Date? {
        lastFeedDate.map { $0.addingTimeInterval(feedTargetInterval) }
    }

    static let empty = ComplicationSnapshot(
        date: .now, babyName: "Baby",
        lastFeedDate: nil, lastFeedOz: nil, feedTargetInterval: 180 * 60,
        lastDiaperDate: nil, lastDiaperType: nil,
        sleepStartedAt: nil, lastSleepEndedAt: nil, lastSleepDuration: nil,
        sleepTargetInterval: WakeWindow.baseline(ageInDays: 0),
        todayFeedCount: 0, todayFeedOz: 0, todaySleepMinutes: 0, todayDiaperCount: 0,
        nextFeed: nil, nightActive: false)

    /// Daytime preview/placeholder data.
    static let placeholder = ComplicationSnapshot(
        date: .now, babyName: "Miller",
        lastFeedDate: Calendar.current.date(byAdding: .minute, value: -135, to: .now),
        lastFeedOz: 4, feedTargetInterval: 180 * 60,
        lastDiaperDate: Calendar.current.date(byAdding: .minute, value: -90, to: .now),
        lastDiaperType: .wet,
        sleepStartedAt: nil,
        lastSleepEndedAt: Calendar.current.date(byAdding: .minute, value: -45, to: .now),
        lastSleepDuration: 130 * 60,
        sleepTargetInterval: 90 * 60,
        todayFeedCount: 8, todayFeedOz: 26, todaySleepMinutes: 390, todayDiaperCount: 7,
        nextFeed: NextFeed(date: Calendar.current.date(byAdding: .minute, value: 45, to: .now) ?? .now,
                           ownerName: nil, isNightSlot: false),
        nightActive: false)

    /// Night preview/placeholder: a slot with an owner, mid-sleep.
    static let nightPlaceholder = ComplicationSnapshot(
        date: .now, babyName: "Miller",
        lastFeedDate: Calendar.current.date(byAdding: .minute, value: -95, to: .now),
        lastFeedOz: 4, feedTargetInterval: 180 * 60,
        lastDiaperDate: Calendar.current.date(byAdding: .minute, value: -95, to: .now),
        lastDiaperType: .wet,
        sleepStartedAt: Calendar.current.date(byAdding: .minute, value: -47, to: .now),
        lastSleepEndedAt: nil, lastSleepDuration: nil,
        sleepTargetInterval: 90 * 60,
        todayFeedCount: 6, todayFeedOz: 21, todaySleepMinutes: 300, todayDiaperCount: 5,
        nextFeed: NextFeed(date: Calendar.current.date(byAdding: .minute, value: 85, to: .now) ?? .now,
                           ownerName: "GT", isNightSlot: true),
        nightActive: true)
}

enum ComplicationStore {
    private static let log = Logger(subsystem: "com.taylorseale.twoofus", category: "watchComplication")

    static func snapshot(now: Date = .now) -> ComplicationSnapshot {
        guard
            let storeURL = AppGroup.storeURL,
            FileManager.default.fileExists(atPath: storeURL.path)
        else {
            log.debug("Complication store unavailable (missing App Group or store file)")
            return .empty
        }
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        guard let container = try? ModelContainer(for: schema, configurations: [config]) else {
            log.error("Complication failed to open the shared model container")
            return .empty
        }
        let ctx = ModelContext(container)
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)

        let baby = (try? ctx.fetch(FetchDescriptor<Baby>()))?.first
        let settings = SharedSettings.canonical((try? ctx.fetch(FetchDescriptor<SharedSettings>())) ?? [])

        // Feeds: the recent window feeds tonight's schedule engine and today's
        // tally; a separate limit-1 fetch keeps "last feed" honest even when
        // nothing was logged for days.
        let feedLookback = now.addingTimeInterval(-48 * 3600)
        let recentFeeds = (try? ctx.fetch(FetchDescriptor<FeedEvent>(
            predicate: #Predicate { $0.deletedAt == nil && $0.timestamp >= feedLookback }
        ))) ?? []
        var lastFeedDesc = FetchDescriptor<FeedEvent>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        lastFeedDesc.fetchLimit = 1
        let lastFeed = (try? ctx.fetch(lastFeedDesc))?.first
        let feedTarget = lastFeed.flatMap { settings?.feedInterval(after: $0.timestamp) }
            ?? TimeInterval((settings?.targetFeedIntervalMinutes ?? 180) * 60)

        var lastDiaperDesc = FetchDescriptor<DiaperEvent>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        lastDiaperDesc.fetchLimit = 1
        let lastDiaper = (try? ctx.fetch(lastDiaperDesc))?.first

        var openSleepDesc = FetchDescriptor<SleepEvent>(
            predicate: #Predicate { $0.endedAt == nil && $0.deletedAt == nil }
        )
        openSleepDesc.fetchLimit = 1
        let openSleep = (try? ctx.fetch(openSleepDesc))?.first

        // One week of sleeps covers everything sleep-shaped: the last finished
        // nap, today's total, and the observed wake gaps for the wake window.
        let weekAgo = now.addingTimeInterval(-7 * 24 * 3600)
        let recentSleeps = (try? ctx.fetch(FetchDescriptor<SleepEvent>(
            predicate: #Predicate { $0.deletedAt == nil && $0.startedAt >= weekAgo }
        ))) ?? []
        let lastFinished = recentSleeps
            .filter { $0.endedAt != nil }
            .max { ($0.startedAt, $0.id.uuidString) < ($1.startedAt, $1.id.uuidString) }
        let sleepTarget = WakeWindow.predicted(
            ageInDays: baby.map { WakeWindow.ageInDays(dateOfBirth: $0.dateOfBirth) } ?? 0,
            observedGaps: WakeWindow.wakeGaps(
                sleeps: recentSleeps.map { ($0.startedAt, $0.endedAt) },
                nightStartMinute: settings?.nightStartMinute ?? 1200,
                nightEndMinute: settings?.nightEndMinute ?? 480))

        // Today's tallies. Sleep counts the minutes actually slept inside
        // [midnight, now], so last night's stretch contributes only its
        // morning tail and a running nap counts up to this instant.
        let todayFeeds = recentFeeds.filter { $0.timestamp >= dayStart }
        let todayDiapers = (try? ctx.fetch(FetchDescriptor<DiaperEvent>(
            predicate: #Predicate { $0.deletedAt == nil && $0.timestamp >= dayStart }
        ))) ?? []
        let todaySleepSeconds = recentSleeps.reduce(0.0) { total, sleep in
            let start = max(sleep.startedAt, dayStart)
            let end = min(sleep.endedAt ?? now, now)
            return total + max(0, end.timeIntervalSince(start))
        }

        // Tonight's schedule — who's up next, and whether the night is live.
        var nightActive = false
        var nextFeed: ComplicationSnapshot.NextFeed?
        let predicted = lastFeed.map { $0.timestamp.addingTimeInterval(feedTarget) }
        if let settings {
            let participants = (try? ctx.fetch(FetchDescriptor<Participant>())) ?? []
            let overrides = (try? ctx.fetch(FetchDescriptor<PlanOverride>(
                predicate: #Predicate { $0.deletedAt == nil }
            ))) ?? []
            let feedKind = EventKind.feed.rawValue
            let sleepSlots = (try? ctx.fetch(FetchDescriptor<PlanSlot>(
                predicate: #Predicate { $0.deletedAt == nil && $0.kindRaw != feedKind }
            ))) ?? []
            let night = NightSchedule(settings: settings, participants: participants,
                                      feeds: recentFeeds, overrides: overrides,
                                      sleepSlots: sleepSlots, now: now)
            if case .day = night.state {} else { nightActive = true }
            // Same tie-break as `nextFeedPrediction`: the slot wins when it's
            // no later than the projection, because it knows whose turn it is.
            if nightActive,
               let slot = night.occurrences().first(where: { $0.status == .upcoming }),
               slot.date <= predicted ?? .distantFuture {
                nextFeed = ComplicationSnapshot.NextFeed(
                    date: slot.date,
                    ownerName: slot.assignedToName.isEmpty ? nil : slot.assignedToName,
                    isNightSlot: true)
            }
        }
        if nextFeed == nil, let predicted {
            // Unlike the Live Activity, a past prediction is kept: the
            // complication shows "~2:30 AM" in urgency red rather than
            // blanking the face the moment a feed runs late.
            nextFeed = ComplicationSnapshot.NextFeed(date: predicted, ownerName: nil, isNightSlot: false)
        }

        return ComplicationSnapshot(
            date: now,
            babyName: baby?.name ?? "Baby",
            lastFeedDate: lastFeed?.timestamp,
            lastFeedOz: lastFeed?.amountOz,
            feedTargetInterval: feedTarget,
            lastDiaperDate: lastDiaper?.timestamp,
            lastDiaperType: lastDiaper?.type,
            sleepStartedAt: openSleep?.startedAt,
            lastSleepEndedAt: lastFinished?.endedAt,
            lastSleepDuration: lastFinished.flatMap { sleep in
                sleep.endedAt.map { $0.timeIntervalSince(sleep.startedAt) }
            },
            sleepTargetInterval: sleepTarget,
            todayFeedCount: todayFeeds.count,
            todayFeedOz: todayFeeds.reduce(0) { $0 + $1.amountOz },
            todaySleepMinutes: Int((todaySleepSeconds / 60).rounded()),
            todayDiaperCount: todayDiapers.count,
            nextFeed: nextFeed,
            nightActive: nightActive)
    }
}

// MARK: - Shared timeline & timer helpers

/// `Text(timerInterval:)` needs a concrete range end and freezes once it's
/// reached — same bound and reasoning as the Live Activity's `maxSleepDuration`
/// (SleepLiveActivityView.swift): a week covers even a timer someone forgot to
/// stop, so a complication never sits on a frozen, wrong number.
let maxSleepDuration: TimeInterval = 7 * 24 * 3600

func sleepRange(from start: Date) -> ClosedRange<Date> {
    start...start.addingTimeInterval(maxSleepDuration)
}

enum ComplicationTimeline {
    /// Lazy safety-net reload — logs and sync fetches already push
    /// `reloadAllTimelines`, so nothing leans on this being prompt.
    static let fallbackReload: TimeInterval = 30 * 60

    /// The urgency flip moments after `last`: amber at 2/3 of target, red 1s
    /// PAST it (`Urgency.from` is amber at ratio ≤ 1.0, so an entry at exactly
    /// 100% would re-render amber). Only future dates — past flips are already
    /// baked into the base entry.
    static func urgencyFlips(last: Date, target: TimeInterval, now: Date) -> [Date] {
        guard target > 0 else { return [] }
        return [last.addingTimeInterval(target * 2 / 3),
                last.addingTimeInterval(target + 1)]
            .filter { $0 > now }
    }

    /// Standard policy: reload a beat after the last staged entry.
    static func policy(after entries: [any TimelineEntry], base now: Date) -> Date {
        ((entries.map(\.date).max() ?? now)).addingTimeInterval(fallbackReload)
    }
}

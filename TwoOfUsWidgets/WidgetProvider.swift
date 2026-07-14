import WidgetKit
import SwiftData
import Foundation
import os

/// Reads the shared SwiftData store and produces WidgetEntry values.
struct WidgetProvider: TimelineProvider {
    // Inline logger — the widget extension can't see the app target's AppLog.
    private static let log = Logger(subsystem: "com.taylorseale.twoofus", category: "widgets")

    func placeholder(in context: Context) -> WidgetEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(context.isPreview ? .placeholder : buildEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let base = buildEntry()

        // Stage entries at the feed urgency thresholds so the dot/accent color flips
        // at the exact moment (amber at 66% of target, red at 100%) without waking
        // code, and so the widget's Smart Stack relevance rises as feed time nears.
        var entries: [WidgetEntry] = [base.redated(to: base.date, relevance: relevance(for: base, at: base.date))]
        if let last = base.lastFeedDate, base.feedTargetInterval > 0 {
            let amberAt = last.addingTimeInterval(base.feedTargetInterval * 0.66)
            let redAt = last.addingTimeInterval(base.feedTargetInterval)
            for date in [amberAt, redAt] where date > base.date {
                entries.append(base.redated(to: date, relevance: relevance(for: base, at: date)))
            }
        }
        entries.sort { $0.date < $1.date }

        // Reload ~15 min after the last staged entry; EventStore /
        // QuickLogger also push WidgetCenter.reloadAllTimelines() on each write.
        let anchor = entries.last?.date ?? base.date
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: anchor)
            ?? anchor.addingTimeInterval(15 * 60)
        completion(Timeline(entries: entries, policy: .after(nextUpdate)))
    }

    /// Relevance score for the feed widget at a given moment — 0 while recent,
    /// rising through "due soon" to "overdue" so the Smart Stack surfaces it.
    private func relevance(for entry: WidgetEntry, at date: Date) -> TimelineEntryRelevance? {
        guard let last = entry.lastFeedDate, entry.feedTargetInterval > 0 else { return nil }
        let ratio = date.timeIntervalSince(last) / entry.feedTargetInterval
        let score: Float
        switch ratio {
        case ..<0.66: score = 0
        case ..<1.0:  score = 0.5
        default:      score = 1.0
        }
        return TimelineEntryRelevance(score: score)
    }

    // MARK: Private

    private func buildEntry() -> WidgetEntry {
        guard
            let storeURL = AppGroup.storeURL,
            FileManager.default.fileExists(atPath: storeURL.path)
        else {
            // No App Group / store yet is normal pre-onboarding, but log it so a
            // misconfigured App Group entitlement isn't an invisible blank widget.
            Self.log.debug("Widget store unavailable (missing App Group or store file)")
            return .empty
        }

        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(schema: schema, url: storeURL)
        guard let container = try? ModelContainer(for: schema, configurations: [config]) else {
            Self.log.error("Widget failed to open the shared model container")
            return .empty
        }

        let ctx = ModelContext(container)
        let feedTarget = (try? ctx.fetch(FetchDescriptor<SharedSettings>()))?.first?.targetFeedInterval ?? 10800
        let babyName = (try? ctx.fetch(FetchDescriptor<Baby>()))?.first?.name ?? "Baby"

        // Last feed
        var feedDesc = FetchDescriptor<FeedEvent>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        feedDesc.fetchLimit = 1
        let lastFeedDate = (try? ctx.fetch(feedDesc))?.first?.timestamp

        // Last sleep
        var sleepDesc = FetchDescriptor<SleepEvent>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        sleepDesc.fetchLimit = 1
        let lastSleepEvent = (try? ctx.fetch(sleepDesc))?.first
        let isActive = lastSleepEvent?.isActive ?? false
        let lastSleepDate: Date? = isActive ? nil : lastSleepEvent?.endedAt

        // Last diaper
        var diaperDesc = FetchDescriptor<DiaperEvent>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        diaperDesc.fetchLimit = 1
        let lastDiaperDate = (try? ctx.fetch(diaperDesc))?.first?.timestamp

        // Recent items for large widget
        let recentItems = fetchRecentItems(ctx: ctx, since: .now.addingTimeInterval(-86400), limit: 5)

        // Today's ribbon marks
        let todayMarks = fetchTodayMarks(ctx: ctx)

        return WidgetEntry(
            date: .now,
            babyName: babyName,
            lastFeedDate: lastFeedDate,
            lastSleepDate: lastSleepDate,
            lastDiaperDate: lastDiaperDate,
            feedTargetInterval: feedTarget,
            isActiveSleep: isActive,
            activeSleepStartedAt: isActive ? lastSleepEvent?.startedAt : nil,
            recentItems: recentItems,
            todayMarks: todayMarks
        )
    }

    private func fetchRecentItems(ctx: ModelContext, since: Date, limit: Int) -> [WidgetItem] {
        var items: [WidgetItem] = []

        if let feeds = try? ctx.fetch(FetchDescriptor<FeedEvent>(
            predicate: #Predicate { $0.deletedAt == nil && $0.timestamp >= since }
        )) {
            items += feeds.map {
                WidgetItem(kind: .feed, date: $0.timestamp, detail: OzFormat.string($0.amountOz) + " oz")
            }
        }

        if let sleeps = try? ctx.fetch(FetchDescriptor<SleepEvent>(
            predicate: #Predicate { $0.deletedAt == nil && $0.startedAt >= since }
        )) {
            items += sleeps.filter { !$0.isActive }.map { sleep in
                let dur: String
                if let end = sleep.endedAt {
                    dur = TimeFormatting.duration(from: sleep.startedAt, to: end)
                } else {
                    dur = "–"
                }
                return WidgetItem(kind: .sleep, date: sleep.startedAt, detail: dur)
            }
        }

        if let diapers = try? ctx.fetch(FetchDescriptor<DiaperEvent>(
            predicate: #Predicate { $0.deletedAt == nil && $0.timestamp >= since }
        )) {
            items += diapers.map {
                WidgetItem(kind: .diaper, date: $0.timestamp, detail: $0.type.label)
            }
        }

        return items.sorted { $0.date > $1.date }.prefix(limit).map { $0 }
    }

    private func fetchTodayMarks(ctx: ModelContext) -> [RibbonMark] {
        let start = Calendar.current.startOfDay(for: .now)
        let feeds = (try? ctx.fetch(FetchDescriptor<FeedEvent>(
            predicate: #Predicate { $0.deletedAt == nil && $0.timestamp >= start }
        ))) ?? []
        // Sleeps overlapping today: started today, still running, OR started
        // yesterday and ended this morning (the overnight sleep). Fetch back to
        // yesterday and let `forDay` clip to today's window — the previous
        // `startedAt >= start` predicate dropped last night's sleep from today's
        // ribbon + tally. (A day's lookback is plenty; no baby sleeps 24h+.)
        let sleepFetchStart = Calendar.current.date(byAdding: .day, value: -1, to: start)
            ?? start.addingTimeInterval(-86_400)
        let sleeps = (try? ctx.fetch(FetchDescriptor<SleepEvent>(
            predicate: #Predicate { $0.deletedAt == nil && ($0.startedAt >= sleepFetchStart || $0.endedAt == nil) }
        ))) ?? []
        let diapers = (try? ctx.fetch(FetchDescriptor<DiaperEvent>(
            predicate: #Predicate { $0.deletedAt == nil && $0.timestamp >= start }
        ))) ?? []
        return RibbonMark.forDay(.now, feeds: feeds, sleeps: sleeps, diapers: diapers)
    }
}

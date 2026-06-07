import WidgetKit
import SwiftData
import Foundation

/// Reads the shared SwiftData store and produces WidgetEntry values.
struct WidgetProvider: TimelineProvider {

    func placeholder(in context: Context) -> WidgetEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(context.isPreview ? .placeholder : buildEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let entry = buildEntry()
        // Reload every 15 min; EventStore also calls WidgetCenter.reloadAllTimelines() on each log.
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: entry.date)!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    // MARK: Private

    private func buildEntry() -> WidgetEntry {
        guard
            let storeURL = AppGroup.storeURL,
            FileManager.default.fileExists(atPath: storeURL.path)
        else {
            return .empty
        }

        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(schema: schema, url: storeURL)
        guard let container = try? ModelContainer(for: schema, configurations: [config]) else {
            return .empty
        }

        let ctx = ModelContext(container)
        let feedTarget = (try? ctx.fetch(FetchDescriptor<SharedSettings>()))?.first?.targetFeedInterval ?? 10800

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

        return WidgetEntry(
            date: .now,
            lastFeedDate: lastFeedDate,
            lastSleepDate: lastSleepDate,
            lastDiaperDate: lastDiaperDate,
            feedTargetInterval: feedTarget,
            isActiveSleep: isActive,
            activeSleepStartedAt: isActive ? lastSleepEvent?.startedAt : nil,
            recentItems: recentItems
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
}

import WidgetKit
import SwiftUI
import SwiftData
import Foundation
import os

/// Watch complication: time since the last feed — the one number a parent
/// checks most. Reads the watch app's App Group store (kept fresh by
/// WatchSyncManager, which reloads timelines after every fetch/log).
@main
struct TwoOfUsWatchComplicationBundle: WidgetBundle {
    var body: some Widget {
        LastFeedComplication()
    }
}

struct LastFeedEntry: TimelineEntry {
    let date: Date
    let lastFeedDate: Date?
    let lastAmountOz: Double?

    static let placeholder = LastFeedEntry(
        date: .now,
        lastFeedDate: Calendar.current.date(byAdding: .minute, value: -135, to: .now),
        lastAmountOz: 4)
    static let empty = LastFeedEntry(date: .now, lastFeedDate: nil, lastAmountOz: nil)
}

struct LastFeedProvider: TimelineProvider {
    private static let log = Logger(subsystem: "com.taylorseale.twoofus", category: "watchComplication")

    func placeholder(in context: Context) -> LastFeedEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (LastFeedEntry) -> Void) {
        completion(context.isPreview ? .placeholder : buildEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LastFeedEntry>) -> Void) {
        let entry = buildEntry()
        // Relative-date Text keeps ticking on its own; refresh the underlying
        // data every 30 minutes as a backstop (writes and sync fetches also
        // push reloadAllTimelines).
        let next = entry.date.addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func buildEntry() -> LastFeedEntry {
        guard
            let storeURL = AppGroup.storeURL,
            FileManager.default.fileExists(atPath: storeURL.path)
        else {
            Self.log.debug("Complication store unavailable (missing App Group or store file)")
            return .empty
        }
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        guard let container = try? ModelContainer(for: schema, configurations: [config]) else {
            Self.log.error("Complication failed to open the shared model container")
            return .empty
        }
        let ctx = ModelContext(container)
        var d = FetchDescriptor<FeedEvent>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        d.fetchLimit = 1
        guard let feed = try? ctx.fetch(d).first else { return .empty }
        return LastFeedEntry(date: .now, lastFeedDate: feed.timestamp, lastAmountOz: feed.amountOz)
    }
}

struct LastFeedComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LastFeedComplication", provider: LastFeedProvider()) { entry in
            LastFeedComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Last Feed")
        .description("Time since the last feed.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

struct LastFeedComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LastFeedEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            VStack(spacing: 0) {
                Image(systemName: "waterbottle.fill")
                    .font(.caption2)
                if let last = entry.lastFeedDate {
                    Text(last, style: .relative)
                        .font(.system(size: 12, weight: .semibold))
                        .minimumScaleFactor(0.5)
                        .multilineTextAlignment(.center)
                } else {
                    Text("—")
                        .font(.caption)
                }
            }

        case .accessoryCorner:
            Image(systemName: "waterbottle.fill")
                .font(.title3)
                .widgetLabel {
                    if let last = entry.lastFeedDate {
                        Text(last, style: .relative)
                    } else {
                        Text("No feeds")
                    }
                }

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("Last feed", systemImage: "waterbottle.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let last = entry.lastFeedDate {
                    Text(last, style: .relative)
                        .font(.headline)
                    if let oz = entry.lastAmountOz {
                        Text("\(OzFormat.string(oz)) oz")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No feeds yet")
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        default: // .accessoryInline
            if let last = entry.lastFeedDate {
                Text("🍼 \(last, style: .relative)")
            } else {
                Text("🍼 No feeds yet")
            }
        }
    }
}

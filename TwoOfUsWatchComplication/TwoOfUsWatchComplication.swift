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
    /// Target interval after the last feed (night-aware, from SharedSettings) —
    /// drives the circular gauge and the urgency tint, same math as the phone.
    let targetInterval: TimeInterval

    var nextFeedDate: Date? {
        lastFeedDate.map { $0.addingTimeInterval(targetInterval) }
    }

    func urgency(at date: Date) -> Urgency {
        Urgency.from(since: lastFeedDate, now: date, target: targetInterval)
    }

    static let placeholder = LastFeedEntry(
        date: .now,
        lastFeedDate: Calendar.current.date(byAdding: .minute, value: -135, to: .now),
        lastAmountOz: 4,
        targetInterval: 180 * 60)
    static let empty = LastFeedEntry(date: .now, lastFeedDate: nil, lastAmountOz: nil,
                                     targetInterval: 180 * 60)
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
        let base = buildEntry()
        // Stage entries at the urgency thresholds so the tint flips at the
        // exact moment with no waking code — the same staging the phone
        // widgets use. The red entry lands 1s PAST the target: `Urgency.from`
        // is amber at ratio ≤ 1.0, so an entry at exactly 100% re-renders
        // amber and red would wait for the next budgeted reload. The ring and
        // relative text tick on their own between entries.
        var entries = [base]
        if let last = base.lastFeedDate, base.targetInterval > 0 {
            for date in [last.addingTimeInterval(base.targetInterval * 2 / 3),
                         last.addingTimeInterval(base.targetInterval + 1)] where date > base.date {
                entries.append(LastFeedEntry(date: date, lastFeedDate: last,
                                             lastAmountOz: base.lastAmountOz,
                                             targetInterval: base.targetInterval))
            }
        }
        let anchor = entries.last?.date ?? base.date
        completion(Timeline(entries: entries, policy: .after(anchor.addingTimeInterval(30 * 60))))
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
        let settings = (try? ctx.fetch(FetchDescriptor<SharedSettings>()))?.first
        guard let feed = try? ctx.fetch(d).first else {
            return LastFeedEntry(date: .now, lastFeedDate: nil, lastAmountOz: nil,
                                 targetInterval: TimeInterval((settings?.targetFeedIntervalMinutes ?? 180) * 60))
        }
        let target = settings?.feedInterval(after: feed.timestamp)
            ?? TimeInterval((settings?.targetFeedIntervalMinutes ?? 180) * 60)
        return LastFeedEntry(date: .now, lastFeedDate: feed.timestamp,
                             lastAmountOz: feed.amountOz, targetInterval: target)
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

    /// Feed teal at rest, urgency amber/red as the next bottle nears/passes —
    /// the same "quiet until it matters" flip as every phone surface.
    private var tint: Color {
        let urgency = entry.urgency(at: entry.date)
        return urgency.needsAttention ? urgency.color : AppColor.accentFeed
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            // The phone's NextFeedGaugeWidget, wrist edition: a
            // ProgressView(timerInterval:) ring that self-advances toward the
            // next bottle with zero reloads (a static Gauge would freeze
            // between the budgeted timeline entries), remaining time in the
            // center. `drop.fill` is the accessory-surface feed glyph the
            // phone ships everywhere.
            ZStack {
                AccessoryWidgetBackground()
                if let last = entry.lastFeedDate, let due = entry.nextFeedDate {
                    ProgressView(timerInterval: last...due, countsDown: false) {
                        Image(systemName: "drop.fill")
                            .widgetAccentable()
                    } currentValueLabel: {
                        Text(due, style: .relative)
                            .font(.caption2)
                            .minimumScaleFactor(0.5)
                    }
                    .progressViewStyle(.circular)
                    .tint(tint)
                } else {
                    Gauge(value: 0) {
                        Image(systemName: "drop.fill")
                            .widgetAccentable()
                    } currentValueLabel: {
                        Text("—")
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(AppColor.accentFeed)
                }
            }

        case .accessoryCorner:
            Image(systemName: "drop.fill")
                .font(.title3)
                .foregroundStyle(tint)
                .widgetAccentable()
                .widgetLabel {
                    if let last = entry.lastFeedDate {
                        Text(last, style: .relative)
                    } else {
                        Text("No feeds")
                    }
                }

        case .accessoryRectangular:
            // MetricStack ordering, same as the phone's lock-screen accessory:
            // emoji + uppercase tracked eyebrow over a rounded mono value.
            // Live-ticking `.relative` is a deliberate liveness trade over the
            // app's compact "2h 31m" (a complication can't reload each minute).
            HStack(spacing: 4) {
                Text("🍼")
                    .font(.subheadline)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Last feed")
                        .sectionLabelStyle(color: tint)
                        .widgetAccentable()
                    if let last = entry.lastFeedDate {
                        Text(last, style: .relative)
                            .font(.system(.headline, design: .rounded).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text("next ~\(TimeFormatting.clock(entry.nextFeedDate ?? entry.date))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No feeds yet")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        default: // .accessoryInline
            if let last = entry.lastFeedDate {
                Label {
                    Text(last, style: .relative)
                } icon: {
                    Image(systemName: "drop.fill")
                }
            } else {
                Label("No feeds yet", systemImage: "drop.fill")
            }
        }
    }
}

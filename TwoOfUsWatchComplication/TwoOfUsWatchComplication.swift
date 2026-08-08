import WidgetKit
import SwiftUI
import SwiftData
import Foundation
import os

/// The watch complication family. `GlanceComplication` is the original
/// switch-hitter (sleep timer while he's down, else last feed); the rest are
/// single-purpose faces added around it. All read the watch app's App Group
/// store (kept fresh by WatchSyncManager, which reloads timelines after every
/// fetch/log). Nested bundle keeps each builder under the block limit.
@main
struct TwoOfUsWatchComplicationBundle: WidgetBundle {
    var body: some Widget {
        GlanceComplication()
        FeedComplication()
        DiaperComplication()
        SleepComplication()
        MoreComplicationsBundle().body
    }
}

struct MoreComplicationsBundle: WidgetBundle {
    var body: some Widget {
        NextFeedComplication()
        DailySummaryComplication()
        NightShiftComplication()
        LauncherComplication()
    }
}

struct GlanceEntry: TimelineEntry {
    let date: Date
    let babyName: String
    /// Set while a sleep is running — when present it wins the whole surface.
    let sleepStartedAt: Date?
    let lastFeedDate: Date?
    let lastAmountOz: Double?
    /// Target interval after the last feed (night-aware, from SharedSettings) —
    /// drives the circular gauge and the urgency tint, same math as the phone.
    let targetInterval: TimeInterval

    var isSleeping: Bool { sleepStartedAt != nil }

    var nextFeedDate: Date? {
        lastFeedDate.map { $0.addingTimeInterval(targetInterval) }
    }

    func urgency(at date: Date) -> Urgency {
        Urgency.from(since: lastFeedDate, now: date, target: targetInterval)
    }

    static let placeholder = GlanceEntry(
        date: .now,
        babyName: "Miller",
        sleepStartedAt: nil,
        lastFeedDate: Calendar.current.date(byAdding: .minute, value: -135, to: .now),
        lastAmountOz: 4,
        targetInterval: 180 * 60)

    static let sleepingPlaceholder = GlanceEntry(
        date: .now,
        babyName: "Miller",
        sleepStartedAt: Calendar.current.date(byAdding: .minute, value: -47, to: .now),
        lastFeedDate: Calendar.current.date(byAdding: .minute, value: -75, to: .now),
        lastAmountOz: 4,
        targetInterval: 180 * 60)

    static let empty = GlanceEntry(date: .now, babyName: "Baby", sleepStartedAt: nil,
                                   lastFeedDate: nil, lastAmountOz: nil,
                                   targetInterval: 180 * 60)
}

struct GlanceProvider: TimelineProvider {
    private static let log = Logger(subsystem: "com.taylorseale.twoofus", category: "watchComplication")

    func placeholder(in context: Context) -> GlanceEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (GlanceEntry) -> Void) {
        completion(context.isPreview ? .placeholder : buildEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GlanceEntry>) -> Void) {
        let base = buildEntry()

        // A running sleep needs no staged entries: the timer text ticks itself
        // and there's no threshold to cross. The reload that matters is the one
        // WatchSyncManager fires when the sleep ends (or a co-parent ends it),
        // so this is only a safety-net refresh.
        guard !base.isSleeping else {
            completion(Timeline(entries: [base], policy: .after(base.date.addingTimeInterval(30 * 60))))
            return
        }

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
                entries.append(GlanceEntry(date: date, babyName: base.babyName,
                                           sleepStartedAt: nil,
                                           lastFeedDate: last,
                                           lastAmountOz: base.lastAmountOz,
                                           targetInterval: base.targetInterval))
            }
        }
        let anchor = entries.last?.date ?? base.date
        completion(Timeline(entries: entries, policy: .after(anchor.addingTimeInterval(30 * 60))))
    }

    private func buildEntry() -> GlanceEntry {
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

        let babyName = (try? ctx.fetch(FetchDescriptor<Baby>()))?.first?.name ?? "Baby"

        var sleepDescriptor = FetchDescriptor<SleepEvent>(
            predicate: #Predicate { $0.endedAt == nil && $0.deletedAt == nil }
        )
        sleepDescriptor.fetchLimit = 1
        let openSleep = (try? ctx.fetch(sleepDescriptor))?.first

        var d = FetchDescriptor<FeedEvent>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        d.fetchLimit = 1
        let settings = (try? ctx.fetch(FetchDescriptor<SharedSettings>()))?.first
        guard let feed = try? ctx.fetch(d).first else {
            return GlanceEntry(date: .now, babyName: babyName,
                               sleepStartedAt: openSleep?.startedAt,
                               lastFeedDate: nil, lastAmountOz: nil,
                               targetInterval: TimeInterval((settings?.targetFeedIntervalMinutes ?? 180) * 60))
        }
        let target = settings?.feedInterval(after: feed.timestamp)
            ?? TimeInterval((settings?.targetFeedIntervalMinutes ?? 180) * 60)
        return GlanceEntry(date: .now, babyName: babyName,
                           sleepStartedAt: openSleep?.startedAt,
                           lastFeedDate: feed.timestamp,
                           lastAmountOz: feed.amountOz, targetInterval: target)
    }
}

struct GlanceComplication: Widget {
    /// Kind is unchanged from when this shipped as feed-only — renaming it would
    /// silently orphan every complication already placed on a watch face.
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LastFeedComplication", provider: GlanceProvider()) { entry in
            GlanceComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Feed & Sleep")
        .description("Time since the last feed — or the running sleep timer while he's down.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

struct GlanceComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GlanceEntry

    /// Feed teal at rest, urgency amber/red as the next bottle nears/passes —
    /// the same "quiet until it matters" flip as every phone surface. While a
    /// sleep runs the surface belongs to sleep, so it takes the periwinkle.
    private var tint: Color {
        if entry.isSleeping { return AppColor.accentSleep }
        let urgency = entry.urgency(at: entry.date)
        return urgency.needsAttention ? urgency.color : AppColor.accentFeed
    }

    var body: some View {
        if let startedAt = entry.sleepStartedAt {
            sleeping(startedAt: startedAt)
        } else {
            feed
        }
    }

    // MARK: Sleeping — the Live Activity's language, wrist-sized

    @ViewBuilder
    private func sleeping(startedAt: Date) -> some View {
        switch family {
        case .accessoryCircular:
            // No ring: a sleep has no target to fill toward, and a full-looking
            // gauge would read as "done". Glyph over a self-ticking timer.
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 11))
                        .widgetAccentable()
                    Text(startedAt, style: .timer)
                        .font(.system(.caption2, design: .rounded).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal, 2)
                }
            }

        case .accessoryCorner:
            Image(systemName: "moon.zzz.fill")
                .font(.title3)
                .foregroundStyle(tint)
                .widgetAccentable()
                .widgetLabel {
                    Text(startedAt, style: .timer)
                }

        case .accessoryRectangular:
            // The lock-screen card's structure, minus the moon halo: eyebrow,
            // big rounded-mono timer, "since 7:42 PM". `showsHours` pins the
            // shape to H:MM:SS from second zero so crossing an hour doesn't
            // silently widen the string mid-sleep.
            HStack(spacing: 4) {
                Text("💤")
                    .font(.subheadline)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(entry.babyName) is sleeping")
                        .sectionLabelStyle(color: tint)
                        .widgetAccentable()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(timerInterval: sleepRange(from: startedAt),
                         countsDown: false,
                         showsHours: true)
                        .font(.system(.headline, design: .rounded).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("since \(TimeFormatting.clock(startedAt))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        default: // .accessoryInline
            Label {
                Text(startedAt, style: .timer)
            } icon: {
                Image(systemName: "moon.zzz.fill")
            }
        }
    }

    // MARK: Awake — time since the last bottle

    @ViewBuilder
    private var feed: some View {
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

// MARK: - Previews

// Both states, at both sizes that carry real layout risk: the rectangular one
// has three stacked lines to fit, and the circular one has to hold a live
// H:MM:SS timer inside a small circle.

#Preview("Rectangular", as: .accessoryRectangular) {
    GlanceComplication()
} timeline: {
    GlanceEntry.sleepingPlaceholder
    GlanceEntry.placeholder
    GlanceEntry.empty
}

#Preview("Circular", as: .accessoryCircular) {
    GlanceComplication()
} timeline: {
    GlanceEntry.sleepingPlaceholder
    GlanceEntry.placeholder
    GlanceEntry.empty
}

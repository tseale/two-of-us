import WidgetKit
import SwiftUI

/// Sleep Status — the running sleep timer while he's down, the awake clock
/// (time since the last sleep ended) once he's up. The awake side tints by
/// his wake window, so the face quietly warms as nap time nears.
struct SleepEntry: TimelineEntry {
    let date: Date
    let babyName: String
    /// Set while a sleep is running — when present it wins the surface.
    let sleepStartedAt: Date?
    let lastSleepEndedAt: Date?
    let lastSleepDuration: TimeInterval?
    let targetInterval: TimeInterval

    var isSleeping: Bool { sleepStartedAt != nil }

    init(date: Date, snapshot: ComplicationSnapshot) {
        self.date = date
        self.babyName = snapshot.babyName
        self.sleepStartedAt = snapshot.sleepStartedAt
        self.lastSleepEndedAt = snapshot.lastSleepEndedAt
        self.lastSleepDuration = snapshot.lastSleepDuration
        self.targetInterval = snapshot.sleepTargetInterval
    }
}

struct SleepProvider: TimelineProvider {
    func placeholder(in context: Context) -> SleepEntry {
        SleepEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SleepEntry) -> Void) {
        let snapshot: ComplicationSnapshot = context.isPreview ? .placeholder : ComplicationStore.snapshot()
        completion(SleepEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SleepEntry>) -> Void) {
        let snapshot = ComplicationStore.snapshot()
        var entries = [SleepEntry(date: snapshot.date, snapshot: snapshot)]
        // A running sleep needs no staged entries — the timer ticks itself and
        // the reload that matters is the one WatchSyncManager fires when the
        // sleep ends. Awake, the tint flips at the wake-window thresholds.
        if snapshot.sleepStartedAt == nil, let woke = snapshot.lastSleepEndedAt {
            entries += ComplicationTimeline
                .urgencyFlips(last: woke, target: snapshot.sleepTargetInterval, now: snapshot.date)
                .map { SleepEntry(date: $0, snapshot: snapshot) }
        }
        completion(Timeline(entries: entries,
                            policy: .after(ComplicationTimeline.policy(after: entries, base: snapshot.date))))
    }
}

struct SleepComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchSleepStatus", provider: SleepProvider()) { entry in
            SleepComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Sleep")
        .description("The running sleep timer — or how long he's been awake.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

struct SleepComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SleepEntry

    /// Sleep periwinkle while he's down; awake, the wake-window urgency warms
    /// the surface as the next nap comes due.
    private var tint: Color {
        if entry.isSleeping { return AppColor.accentSleep }
        let urgency = Urgency.from(since: entry.lastSleepEndedAt, now: entry.date,
                                   target: entry.targetInterval)
        return urgency.needsAttention ? urgency.color : AppColor.accentSleep
    }

    var body: some View {
        if let startedAt = entry.sleepStartedAt {
            sleeping(startedAt: startedAt)
        } else {
            awake
        }
    }

    // MARK: Sleeping — the Glance complication's language, unchanged

    @ViewBuilder
    private func sleeping(startedAt: Date) -> some View {
        switch family {
        case .accessoryCircular:
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
            HStack(spacing: 4) {
                Text("💤")
                    .font(.subheadline)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Sleeping")
                        .sectionLabelStyle(color: tint)
                        .widgetAccentable()
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

    // MARK: Awake — time since the last sleep ended

    @ViewBuilder
    private var awake: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(tint)
                        .widgetAccentable()
                    if let woke = entry.lastSleepEndedAt {
                        Text(woke, style: .relative)
                            .font(.system(.caption2, design: .rounded).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .padding(.horizontal, 2)
                    } else {
                        Text("--")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }

        case .accessoryCorner:
            Image(systemName: "sun.max.fill")
                .font(.title3)
                .foregroundStyle(tint)
                .widgetAccentable()
                .widgetLabel {
                    if let woke = entry.lastSleepEndedAt {
                        Text(woke, style: .relative)
                    } else {
                        Text("No sleeps")
                    }
                }

        case .accessoryRectangular:
            HStack(spacing: 4) {
                Text("☀️")
                    .font(.subheadline)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Awake")
                        .sectionLabelStyle(color: tint)
                        .widgetAccentable()
                    if let woke = entry.lastSleepEndedAt {
                        Text(woke, style: .relative)
                            .font(.system(.headline, design: .rounded).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if let duration = entry.lastSleepDuration {
                            Text("last nap \(TimeFormatting.duration(minutes: Int(duration / 60)))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    } else {
                        Text("No sleeps yet")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        default: // .accessoryInline
            if let woke = entry.lastSleepEndedAt {
                Label {
                    Text(woke, style: .relative)
                } icon: {
                    Image(systemName: "sun.max.fill")
                }
            } else {
                Label("No sleeps yet", systemImage: "sun.max.fill")
            }
        }
    }
}

#Preview("Rectangular", as: .accessoryRectangular) {
    SleepComplication()
} timeline: {
    SleepEntry(date: .now, snapshot: .nightPlaceholder)
    SleepEntry(date: .now, snapshot: .placeholder)
    SleepEntry(date: .now, snapshot: .empty)
}

#Preview("Circular", as: .accessoryCircular) {
    SleepComplication()
} timeline: {
    SleepEntry(date: .now, snapshot: .nightPlaceholder)
    SleepEntry(date: .now, snapshot: .placeholder)
    SleepEntry(date: .now, snapshot: .empty)
}

import WidgetKit
import SwiftUI

/// Open App — no data, just the brand mark in a face slot. Every complication
/// tap already launches the app; this one exists for the parent who wants a
/// dedicated, recognizable "open Two of Us" button rather than a metric.
struct LauncherEntry: TimelineEntry {
    let date: Date
}

struct LauncherProvider: TimelineProvider {
    func placeholder(in context: Context) -> LauncherEntry {
        LauncherEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (LauncherEntry) -> Void) {
        completion(LauncherEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LauncherEntry>) -> Void) {
        // Nothing on this face ever changes — one entry, no reloads.
        completion(Timeline(entries: [LauncherEntry(date: .now)], policy: .never))
    }
}

struct LauncherComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchAppLauncher", provider: LauncherProvider()) { entry in
            LauncherComplicationView()
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Open Two of Us")
        .description("One tap straight into the app.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}

struct LauncherComplicationView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                mark(size: 38)
            }

        case .accessoryCorner:
            mark(size: 24)
                .widgetLabel {
                    Text("Two of Us")
                }

        default: // .accessoryInline
            Text("🍼 Two of Us")
        }
    }

    /// The mark's screen-blend was designed for black — which is exactly what
    /// a watch face is. In the face's tinted/accented rendering the colors
    /// flatten to the accent, which still reads as the two-circles mark.
    private func mark(size: CGFloat) -> some View {
        CradleMark(size: size)
    }
}

#Preview("Circular", as: .accessoryCircular) {
    LauncherComplication()
} timeline: {
    LauncherEntry(date: .now)
}

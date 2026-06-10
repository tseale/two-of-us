import SwiftUI

/// A single mark on the 24-hour day ribbon.
/// Feed and diaper are instantaneous; sleep carries an `end` and renders as a span.
struct RibbonMark: Identifiable, Hashable {
    enum Kind: Hashable { case feed, sleep, diaper }

    let id: UUID
    let kind: Kind
    let start: Date
    let end: Date?   // sleep only

    init(id: UUID = UUID(), kind: Kind, start: Date, end: Date? = nil) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
    }
}

extension RibbonMark {
    /// Marks for the calendar day containing `day`, built from live events.
    /// Sleep spans are clipped to the day's bounds; an active sleep ends "now".
    static func forDay(
        _ day: Date = .now,
        feeds: [FeedEvent],
        sleeps: [SleepEvent],
        diapers: [DiaperEvent],
        calendar: Calendar = .current
    ) -> [RibbonMark] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)

        var marks: [RibbonMark] = []

        for feed in feeds where feed.deletedAt == nil {
            guard feed.timestamp >= start, feed.timestamp < end else { continue }
            marks.append(RibbonMark(id: feed.id, kind: .feed, start: feed.timestamp))
        }

        for diaper in diapers where diaper.deletedAt == nil {
            guard diaper.timestamp >= start, diaper.timestamp < end else { continue }
            marks.append(RibbonMark(id: diaper.id, kind: .diaper, start: diaper.timestamp))
        }

        for sleep in sleeps where sleep.deletedAt == nil {
            let sStart = sleep.startedAt
            let sEnd = sleep.endedAt ?? day        // active sleep counts up to `day`
            guard sEnd >= start, sStart < end else { continue }
            marks.append(RibbonMark(
                id: sleep.id, kind: .sleep,
                start: max(sStart, start),
                end: min(sEnd, end)
            ))
        }

        return marks
    }
}

/// Render style for `DayRibbonView`.
/// `.color` uses the event accent palette (in-app + home-screen widgets);
/// `.tinted` uses primary/secondary so the lock-screen accessory tint can desaturate it,
/// encoding type by shape instead of color (● feed · ○ diaper · — sleep).
enum RibbonStyle { case color, tinted }

/// A 24-hour strip showing when events happened: feed/diaper dots above a baseline,
/// sleep as a span below it, with an optional "now" marker. Reused on the Home tab,
/// the History swimlane, and the widgets.
struct DayRibbonView: View {
    let marks: [RibbonMark]
    var style: RibbonStyle = .color
    var day: Date = .now
    var showNowMarker: Bool = true

    private let calendar = Calendar.current

    var body: some View {
        Canvas { ctx, size in
            let dayStart = calendar.startOfDay(for: day)
            let span: TimeInterval = 86_400
            func x(_ date: Date) -> CGFloat {
                let f = max(0, min(1, date.timeIntervalSince(dayStart) / span))
                return CGFloat(f) * size.width
            }

            let markY = size.height * 0.34
            let baselineY = size.height * 0.66
            let dotR: CGFloat = max(2.6, size.height * 0.10)

            // Baseline
            var baseline = Path()
            baseline.move(to: CGPoint(x: 0, y: baselineY))
            baseline.addLine(to: CGPoint(x: size.width, y: baselineY))
            ctx.stroke(baseline, with: .color(baselineColor), lineWidth: 1)

            // Sleep spans (below baseline)
            for mark in marks where mark.kind == .sleep {
                let x0 = x(mark.start)
                let x1 = max(x0 + 3, x(mark.end ?? day))
                let rect = CGRect(x: x0, y: baselineY + 3, width: x1 - x0, height: max(3, dotR))
                ctx.fill(
                    Path(roundedRect: rect, cornerRadius: rect.height / 2),
                    with: .color(color(for: .sleep))
                )
            }

            // Instantaneous marks (above baseline)
            for mark in marks where mark.kind != .sleep {
                let rect = CGRect(x: x(mark.start) - dotR, y: markY - dotR, width: dotR * 2, height: dotR * 2)
                let path = Path(ellipseIn: rect)
                if style == .tinted && mark.kind == .diaper {
                    ctx.stroke(path, with: .color(color(for: .diaper)), lineWidth: 1.5)  // hollow ring
                } else {
                    ctx.fill(path, with: .color(color(for: mark.kind)))
                }
            }

            // "Now" marker (only on today)
            if showNowMarker, calendar.isDate(day, inSameDayAs: .now) {
                let nx = x(.now)
                var nowLine = Path()
                nowLine.move(to: CGPoint(x: nx, y: markY - dotR - 3))
                nowLine.addLine(to: CGPoint(x: nx, y: baselineY + dotR + 3))
                ctx.stroke(nowLine, with: .color(nowColor.opacity(0.55)),
                           style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            }
        }
        .accessibilityHidden(true)
    }

    private var baselineColor: Color {
        style == .tinted ? .secondary.opacity(0.7) : AppColor.separator
    }
    private var nowColor: Color {
        style == .tinted ? .primary : AppColor.text
    }
    private func color(for kind: RibbonMark.Kind) -> Color {
        if style == .tinted {
            return kind == .diaper ? .secondary : .primary
        }
        switch kind {
        case .feed:   return AppColor.accentFeed
        case .sleep:  return AppColor.accentSleep
        case .diaper: return AppColor.accentDiaper
        }
    }
}

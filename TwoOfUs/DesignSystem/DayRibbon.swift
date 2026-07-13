import SwiftUI

/// A single mark on the 24-hour day ribbon.
/// Feed and diaper are instantaneous; sleep carries an `end` and renders as a span.
struct RibbonMark: Identifiable, Hashable {
    enum Kind: Hashable { case feed, sleep, diaper }

    let id: UUID
    let kind: Kind
    let start: Date
    let end: Date?   // sleep only
    let diaperType: DiaperType?   // diaper only

    init(id: UUID = UUID(), kind: Kind, start: Date, end: Date? = nil, diaperType: DiaperType? = nil) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.diaperType = diaperType
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
            marks.append(RibbonMark(id: diaper.id, kind: .diaper, start: diaper.timestamp, diaperType: diaper.type))
        }

        for sleep in sleeps where sleep.deletedAt == nil {
            let sStart = sleep.startedAt
            // Active sleep counts up to *now*, clipped to this lane's end — NOT to
            // `day`. On the Home ribbon `day` is now so both agree, but History
            // passes each row's midnight, which made an active sleep collapse to a
            // 0-width (inverted) span rendered as a 3px sliver.
            let sEnd = sleep.endedAt ?? min(Date(), end)
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
/// `.color` draws small emoji marks (🍼 feed · 💧 wet / 💩 dirty-or-both diaper) above the baseline
/// and sleep as a pale purple pill with "z z z" resting inside it (in-app + home-screen widgets);
/// `.tinted` uses primary/secondary shapes so the lock-screen accessory tint can desaturate it,
/// encoding type by shape instead (● feed · ○ diaper · — sleep).
enum RibbonStyle { case color, tinted }

/// A 24-hour strip showing when events happened: feed/diaper marks above a baseline,
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
            let bandH: CGFloat = max(3, size.height * 0.26)
            let emojiSize: CGFloat = max(8, size.height * 0.26)

            // Baseline
            var baseline = Path()
            baseline.move(to: CGPoint(x: 0, y: baselineY))
            baseline.addLine(to: CGPoint(x: size.width, y: baselineY))
            ctx.stroke(baseline, with: .color(baselineColor), lineWidth: 1)

            // Sleep spans (below baseline)
            for mark in marks where mark.kind == .sleep {
                let x0 = x(mark.start)
                let x1 = max(x0 + 3, x(mark.end ?? day))
                if style == .color {
                    // A pale pill with "z z z" resting inside it.
                    let band = CGRect(x: x0, y: baselineY + 2, width: x1 - x0, height: bandH)
                    ctx.fill(
                        Path(roundedRect: band, cornerRadius: band.height / 2),
                        with: .color(AppColor.accentSleep.opacity(0.35))
                    )
                    let zzz = ctx.resolve(
                        Text("z z z")
                            .font(.system(size: bandH * 0.62, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColor.accentSleep)
                    )
                    let zzzSize = zzz.measure(in: size)
                    // Short naps and slim ribbons (History lanes) stay clean bands.
                    if bandH >= 7, zzzSize.width <= band.width - 6 {
                        ctx.draw(zzz, at: CGPoint(x: band.midX, y: band.midY), anchor: .center)
                    }
                } else {
                    let rect = CGRect(x: x0, y: baselineY + 3, width: x1 - x0, height: max(3, dotR))
                    ctx.fill(
                        Path(roundedRect: rect, cornerRadius: rect.height / 2),
                        with: .color(color(for: .sleep))
                    )
                }
            }

            // Instantaneous marks (above baseline)
            if style == .color {
                // Resolve each emoji, then nudge near-simultaneous marks apart
                // left-to-right so they sit side by side instead of stacking.
                let stamps = marks
                    .filter { $0.kind != .sleep }
                    .sorted { $0.start < $1.start }
                    .map { mark in
                        // "Both" shows just 💩 on the ribbon; the full 💧💩 stays in the event list.
                        let emoji = mark.kind == .feed ? "🍼" : (mark.diaperType == .wet ? "💧" : "💩")
                        let resolved = ctx.resolve(Text(emoji).font(.system(size: emojiSize)))
                        return (text: resolved, width: resolved.measure(in: size).width, x: x(mark.start))
                    }
                var centers: [CGFloat] = []
                for stamp in stamps {
                    var cx = min(max(stamp.x, stamp.width / 2), size.width - stamp.width / 2)
                    if let i = centers.indices.last {
                        cx = max(cx, centers[i] + (stamps[i].width + stamp.width) / 2 + 1)
                    }
                    centers.append(cx)
                }
                for (stamp, cx) in zip(stamps, centers) {
                    ctx.draw(stamp.text, at: CGPoint(x: cx, y: markY), anchor: .center)
                }
            } else {
                for mark in marks where mark.kind != .sleep {
                    let rect = CGRect(x: x(mark.start) - dotR, y: markY - dotR, width: dotR * 2, height: dotR * 2)
                    let path = Path(ellipseIn: rect)
                    if mark.kind == .diaper {
                        ctx.stroke(path, with: .color(color(for: .diaper)), lineWidth: 1.5)  // hollow ring
                    } else {
                        ctx.fill(path, with: .color(color(for: mark.kind)))
                    }
                }
            }

            // "Now" marker (only on today)
            if showNowMarker, calendar.isDate(day, inSameDayAs: .now) {
                let nx = x(.now)
                let bottomY = style == .color ? baselineY + bandH + 4 : baselineY + dotR + 3
                var nowLine = Path()
                nowLine.move(to: CGPoint(x: nx, y: markY - dotR - 3))
                nowLine.addLine(to: CGPoint(x: nx, y: bottomY))
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

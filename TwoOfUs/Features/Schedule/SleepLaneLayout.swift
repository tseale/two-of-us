import Foundation

/// Row-aligned geometry for the schedule's sleep lanes: given the rail's
/// rendered elements (bottle rows and the NOW cap, in list order) and the
/// parents' sleep-window spans, produce per-element, per-lane band slices in
/// row-local coordinates — 0 at the row's top, 0.5 on the node line, 1 at the
/// bottom.
///
/// The vertical axis is the LIST's, not the clock's: each element's lane
/// represents the stretch from the midpoint above its node to the midpoint
/// below, and times map linearly within those two halves. Transitions carry
/// their exact clock on a cap, so the lanes stay honest even though row
/// spacing isn't time-proportional. Same-parent windows that touch or overlap
/// merge into one unbroken block — the same reading the assignment engine
/// uses. Anything before the first element or after the last is clamped: an
/// in-progress block runs off the edge, and windows entirely outside the
/// rendered range contribute nothing (the standing-plan list below the
/// timeline still shows every window).
///
/// Pure and store-free, same idiom as the engines: callers pass plain values,
/// tests pass fixtures.
struct SleepLaneLayout {
    /// One parent sleep-window span on the visible schedule — a window
    /// occurrence reduced to what the lanes need. `id` is the occurrence's id,
    /// carried through so a tapped band can reopen its per-night actions.
    struct Span {
        let id: String
        let parentID: UUID
        let start: Date
        let end: Date
    }

    /// A fall-asleep or wake moment rendered on a band edge.
    struct Cap: Equatable {
        enum Kind { case fallsAsleep, wakes }
        let y: Double            // 0...1 row-local; 0.5 is the node line
        let time: Date
        let kind: Kind
    }

    /// One lane's rendering inside one rail element.
    struct Slice: Equatable {
        var runs: [ClosedRange<Double>] = []
        var caps: [Cap] = []
        /// Whether the parent is asleep at the element's own time — the
        /// "who's down at THIS bottle" read, and the a11y summary.
        var asleepAtNode = false
        /// The span covering (or nearest inside) this element, for band taps.
        var primarySpanID: String? = nil
    }

    /// `slices[elementIndex][laneIndex]`, lanes ordered as `laneParentIDs`.
    let slices: [[Slice]]

    init(elementDates: [Date], laneParentIDs: [UUID], spans: [Span]) {
        guard !elementDates.isEmpty, !laneParentIDs.isEmpty else {
            slices = []
            return
        }
        let intervals = Self.mergedIntervals(spans: spans, parentIDs: laneParentIDs)
        slices = elementDates.indices.map { index in
            let node = elementDates[index]
            let top = index == 0 ? node
                : Self.midpoint(elementDates[index - 1], node)
            let bottom = index == elementDates.count - 1 ? node
                : Self.midpoint(node, elementDates[index + 1])
            return laneParentIDs.map {
                Self.slice(intervals: intervals[$0] ?? [], node: node, top: top, bottom: bottom)
            }
        }
    }

    // MARK: Interval merging

    private struct Interval {
        let start: Date
        let end: Date
        let spanID: String
    }

    /// Each parent's spans as disjoint asleep intervals, ascending — touching
    /// or overlapping windows become one block (keeping the first constituent's
    /// span id for taps). Degenerate spans (end ≤ start) are dropped.
    private static func mergedIntervals(spans: [Span], parentIDs: [UUID]) -> [UUID: [Interval]] {
        var byParent: [UUID: [Interval]] = [:]
        for id in parentIDs { byParent[id] = [] }
        let sorted = spans
            .filter { $0.end > $0.start }
            .sorted { ($0.start, $0.id) < ($1.start, $1.id) }
        for span in sorted {
            guard var list = byParent[span.parentID] else { continue }
            if let last = list.last, span.start <= last.end {
                list[list.count - 1] = Interval(start: last.start,
                                                end: max(last.end, span.end),
                                                spanID: last.spanID)
            } else {
                list.append(Interval(start: span.start, end: span.end, spanID: span.id))
            }
            byParent[span.parentID] = list
        }
        return byParent
    }

    // MARK: Slice construction

    private static func slice(intervals: [Interval], node: Date, top: Date, bottom: Date) -> Slice {
        var slice = Slice()
        slice.asleepAtNode = asleep(at: node, intervals)
        slice.primarySpanID = (intervals.first { $0.start <= node && node < $0.end }
            ?? intervals.first { $0.end > top && $0.start < bottom })?.spanID
        // Each element owns transitions in [top, bottom) — half-open, so a cap
        // landing exactly on a midpoint belongs to exactly one element.
        appendHalf(&slice, intervals, from: top, to: node, yStart: 0)
        appendHalf(&slice, intervals, from: node, to: bottom, yStart: 0.5)
        slice.runs = merged(slice.runs)
        return slice
    }

    /// Fills one half of the element (`yStart` 0 = top half, 0.5 = bottom)
    /// from the asleep intervals overlapping (from, to), with caps for the
    /// transitions inside [from, to). A zero-length half — the clamped edge of
    /// the first/last element — fills on the state a second beyond the node,
    /// so an in-progress block runs off the edge without inventing caps.
    private static func appendHalf(_ slice: inout Slice, _ intervals: [Interval],
                                   from: Date, to: Date, yStart: Double) {
        let duration = to.timeIntervalSince(from)
        guard duration > 1 else {
            let probe = from.addingTimeInterval(yStart == 0 ? -1 : 1)
            if asleep(at: probe, intervals) {
                slice.runs.append(yStart...(yStart + 0.5))
            }
            return
        }
        for interval in intervals where interval.end > from && interval.start < to {
            let lower = yStart + 0.5 * max(0, interval.start.timeIntervalSince(from)) / duration
            let upper = yStart + 0.5 * min(duration, interval.end.timeIntervalSince(from)) / duration
            slice.runs.append(lower...upper)
            if interval.start >= from && interval.start < to {
                slice.caps.append(Cap(y: lower, time: interval.start, kind: .fallsAsleep))
            }
            if interval.end >= from && interval.end < to {
                slice.caps.append(Cap(y: upper, time: interval.end, kind: .wakes))
            }
        }
    }

    private static func asleep(at date: Date, _ intervals: [Interval]) -> Bool {
        intervals.contains { $0.start <= date && date < $0.end }
    }

    /// Runs sorted and stitched — an interval crossing the node line arrives
    /// as two half-runs that must read as one unbroken band.
    private static func merged(_ runs: [ClosedRange<Double>]) -> [ClosedRange<Double>] {
        var out: [ClosedRange<Double>] = []
        for run in runs.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = out.last, run.lowerBound <= last.upperBound + 0.0001 {
                out[out.count - 1] = last.lowerBound...max(last.upperBound, run.upperBound)
            } else {
                out.append(run)
            }
        }
        return out
    }

    private static func midpoint(_ a: Date, _ b: Date) -> Date {
        Date(timeIntervalSinceReferenceDate:
                (a.timeIntervalSinceReferenceDate + b.timeIntervalSinceReferenceDate) / 2)
    }
}

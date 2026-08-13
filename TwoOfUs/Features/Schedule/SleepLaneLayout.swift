import Foundation

/// Row-aligned geometry for the schedule's sleep lanes: given the rail's
/// rendered elements (bottle rows and the NOW cap, in list order) and the
/// parents' sleep-window spans, produce per-element, per-lane band runs in
/// row-local coordinates — 0 at the row's top, 0.5 on the node line, 1 at the
/// bottom.
///
/// The vertical axis is the LIST's, not the clock's: each element's lane
/// represents the stretch from the midpoint above its node to the midpoint
/// below, and times map linearly within those two halves. Every run carries
/// whether its ends are REAL transitions (a fall-asleep / wake) or clamps at
/// the element's edge — the view rounds only real ends and bleeds clamped
/// ends past the row boundary, so a block spanning many rows renders as one
/// unbroken band. A transition landing too close to an element boundary to
/// draw its own cap is handed to the neighboring element, which has the room.
/// Same-parent windows that touch or overlap merge into one block — the same
/// reading the assignment engine uses. Anything before the
/// first element or after the last is clamped: an in-progress block runs off
/// the edge, and windows entirely outside the rendered range contribute
/// nothing (the standing-plan list below the timeline still shows every
/// window).
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

    /// One filled stretch of a lane inside one element. The flags say whether
    /// each end is a real transition owned by this element (rounded, and the
    /// fall-asleep end carries the 💤) or a continuation to be fused with the
    /// neighboring element's run (squared and overshot).
    struct Run: Equatable {
        let range: ClosedRange<Double>
        let startsHere: Bool     // top is the block's real fall-asleep
        let endsHere: Bool       // bottom is the block's real wake
    }

    /// One lane's rendering inside one rail element.
    struct Slice: Equatable {
        var runs: [Run] = []
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
        let built = elementDates.indices.map { index in
            let node = elementDates[index]
            let top = index == 0 ? node
                : Self.midpoint(elementDates[index - 1], node)
            let bottom = index == elementDates.count - 1 ? node
                : Self.midpoint(node, elementDates[index + 1])
            return laneParentIDs.map {
                Self.slice(intervals: intervals[$0] ?? [], node: node, top: top, bottom: bottom)
            }
        }
        slices = Self.handingOffCrampedCaps(built)
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
        // Each element owns the transitions inside its own [top, bottom)
        // stretch — half-open, so a transition landing exactly on a midpoint
        // is drawn (rounded) by exactly one element.
        appendHalf(&slice, intervals, from: top, to: node, yStart: 0)
        appendHalf(&slice, intervals, from: node, to: bottom, yStart: 0.5)
        slice.runs = merged(slice.runs)
        return slice
    }

    /// Fills one half of the element (`yStart` 0 = top half, 0.5 = bottom)
    /// from the asleep intervals overlapping (from, to). An interval edge
    /// inside the half is a real transition (`startsHere`/`endsHere`); one
    /// clamped at the half's bounds continues into the neighbor. A zero-length
    /// half — the clamped edge of the first/last element — fills on the state
    /// a second beyond the node, flagless, so an in-progress block runs off
    /// the rail's edge.
    private static func appendHalf(_ slice: inout Slice, _ intervals: [Interval],
                                   from: Date, to: Date, yStart: Double) {
        let duration = to.timeIntervalSince(from)
        guard duration > 1 else {
            let probe = from.addingTimeInterval(yStart == 0 ? -1 : 1)
            if asleep(at: probe, intervals) {
                slice.runs.append(Run(range: yStart...(yStart + 0.5),
                                      startsHere: false, endsHere: false))
            }
            return
        }
        for interval in intervals where interval.end > from && interval.start < to {
            let lower = yStart + 0.5 * max(0, interval.start.timeIntervalSince(from)) / duration
            let upper = yStart + 0.5 * min(duration, interval.end.timeIntervalSince(from)) / duration
            slice.runs.append(Run(range: lower...upper,
                                  startsHere: interval.start >= from,
                                  endsHere: interval.end <= to))
        }
    }

    private static func asleep(at date: Date, _ intervals: [Interval]) -> Bool {
        intervals.contains { $0.start <= date && date < $0.end }
    }

    // MARK: Cap hand-off

    /// A run this short can't draw its own cap: the band's rounded end wants a
    /// radius' worth of height (8pt of a row that's 46pt at its shortest,
    /// hence ~0.18) and a stub gets the corners squashed flat — plus, on a
    /// fall-asleep, a 💤 with nowhere to sit.
    private static let minCapRun = 0.18

    /// Moves a transition that lands a hair from an element boundary onto the
    /// boundary itself, so the cap is drawn by the element with room for it.
    ///
    /// A fall-asleep three minutes before a row boundary would otherwise leave
    /// a 2pt rounded stub at the bottom of one row with the real block starting
    /// square-topped in the next — the cap detached from the thing it caps.
    /// Dropping the stub and handing `startsHere` to the neighbor's leading run
    /// puts one clean cap at the row boundary; a wake landing just *after* a
    /// boundary hands `endsHere` back the other way. The band shifts by less
    /// than the cap's own radius — a broken cap reads as a rendering bug, a
    /// few points of drift on a rail that isn't to scale reads as nothing.
    private static func handingOffCrampedCaps(_ built: [[Slice]]) -> [[Slice]] {
        var out = built
        guard out.count > 1, let laneCount = out.first?.count else { return out }
        func isStub(_ run: Run) -> Bool {
            run.range.upperBound - run.range.lowerBound < minCapRun
        }
        for lane in 0..<laneCount {
            // Fall-asleep stub at an element's bottom edge → the next element.
            for i in 0..<(out.count - 1) {
                guard let stub = out[i][lane].runs.last,
                      stub.startsHere, !stub.endsHere,
                      stub.range.upperBound > 0.999, isStub(stub),
                      let j = out[i + 1][lane].runs
                        .firstIndex(where: { $0.range.lowerBound < 0.001 })
                else { continue }
                out[i][lane].runs.removeLast()
                let heir = out[i + 1][lane].runs[j]
                out[i + 1][lane].runs[j] = Run(range: heir.range, startsHere: true,
                                               endsHere: heir.endsHere)
            }
            // Wake stub at an element's top edge → the previous element.
            for i in stride(from: out.count - 1, to: 0, by: -1) {
                guard let stub = out[i][lane].runs.first,
                      stub.endsHere, !stub.startsHere,
                      stub.range.lowerBound < 0.001, isStub(stub),
                      let j = out[i - 1][lane].runs
                        .firstIndex(where: { $0.range.upperBound > 0.999 })
                else { continue }
                out[i][lane].runs.removeFirst()
                let heir = out[i - 1][lane].runs[j]
                out[i - 1][lane].runs[j] = Run(range: heir.range,
                                               startsHere: heir.startsHere, endsHere: true)
            }
        }
        return out
    }

    /// Runs sorted and stitched — an interval crossing the node line arrives
    /// as two half-runs that must read as one unbroken band. The fused run
    /// keeps the outer ends' flags.
    private static func merged(_ runs: [Run]) -> [Run] {
        var out: [Run] = []
        for run in runs.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
            if let last = out.last, run.range.lowerBound <= last.range.upperBound + 0.0001 {
                out[out.count - 1] = Run(
                    range: last.range.lowerBound...max(last.range.upperBound, run.range.upperBound),
                    startsHere: last.startsHere,
                    endsHere: run.range.upperBound >= last.range.upperBound
                        ? run.endsHere : last.endsHere)
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

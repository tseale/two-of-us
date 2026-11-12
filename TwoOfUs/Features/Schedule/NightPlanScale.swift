import CoreGraphics
import Foundation

/// The night as a ruler: the shared night window — its start and end minutes
/// on the wall clock, from `SharedSettings` — laid out from one end to the
/// other, so the standing plan can be drawn to scale. Each parent's sleep
/// window becomes a pill as long as the sleep it stands for, in the place
/// the night puts it.
///
/// Everything is in the night's own terms. A *position* runs from 0 at the
/// night's start to 1 at its end, whatever the clock does in between: a night
/// that wraps past midnight (9 PM – 7 AM) is one unbroken length, and so is a
/// window that does (10 PM – 2 AM). A window is clipped to the night — the
/// part of it outside is not drawn — and the cut end is flagged, so the strip
/// can square it off the way the Tonight rail squares a band that carries on
/// into the next row.
///
/// Pure and store-free, the same idiom as `SleepLaneLayout`: plain minutes
/// in, plain fractions out. `NightPlanScaleTests` covers every case.
struct NightPlanScale: Equatable {
    static let minutesPerDay = 1440

    /// The night's first minute on the wall clock, 0..<1440.
    let startMinute: Int
    /// How long the night runs, in minutes: 1...1439.
    let lengthMinutes: Int

    /// The scale for a night from `nightStartMinute` to `nightEndMinute`, an
    /// end at or before the start meaning the next morning. Nil when the two
    /// are the same minute: a zero-length night is no night at all (the same
    /// reading `NightSchedule` makes), and there is nothing to draw to.
    init?(nightStartMinute: Int, nightEndMinute: Int) {
        let start = Self.wrap(nightStartMinute)
        let length = Self.wrap(nightEndMinute - start)
        guard length > 0 else { return nil }
        self.startMinute = start
        self.lengthMinutes = length
    }

    /// The night's last minute on the wall clock, 0..<1440.
    var endMinute: Int { Self.wrap(startMinute + lengthMinutes) }

    // MARK: Minute of day → position → x

    /// Where a wall-clock minute falls across the night: 0 at its start, 1
    /// at its end. Nil for a minute the night does not reach (noon, on a
    /// 9 PM – 7 AM night).
    func position(ofMinute minute: Int) -> Double? {
        let offset = Self.wrap(minute - startMinute)
        guard offset <= lengthMinutes else { return nil }
        return Double(offset) / Double(lengthMinutes)
    }

    /// A position as a distance along a track `width` points long.
    static func x(at position: Double, width: CGFloat) -> CGFloat {
        CGFloat(position) * max(width, 0)
    }

    /// A wall-clock minute as a distance along a track `width` points long,
    /// or nil for a minute outside the night.
    func x(ofMinute minute: Int, width: CGFloat) -> CGFloat? {
        position(ofMinute: minute).map { Self.x(at: $0, width: width) }
    }

    // MARK: Windows → pills

    /// One parent's unbroken stretch of planned sleep, as much of it as
    /// falls inside the night.
    struct Pill: Equatable {
        let parentID: UUID
        /// Where the stretch starts and ends across the night, 0...1.
        let start: Double
        let end: Double
        /// Whether each end is the window's own — a fall-asleep or a wake
        /// inside the night — rather than the night's edge cutting a window
        /// that runs on past it.
        let startsInNight: Bool
        let endsInNight: Bool
    }

    /// The parents' standing windows as pills, earliest first. Windows are
    /// clipped to the night, and one that lies wholly outside it contributes
    /// nothing. A window that wraps past midnight is followed round the
    /// clock, so it lands where the night has it — and one long enough to
    /// overlap the night at both ends becomes two pills. Windows of the same
    /// parent that touch or overlap merge into one, the reading the Tonight
    /// rail and the assignment engine make.
    func pills(for windows: [SleepWindow]) -> [Pill] {
        var parents: [UUID] = []
        var stretches: [UUID: [Stretch]] = [:]
        for window in windows where window.durationMinutes > 0 {
            if stretches[window.parentID] == nil {
                parents.append(window.parentID)
                stretches[window.parentID] = []
            }
            let duration = min(window.durationMinutes, Self.minutesPerDay)
            let offset = Self.wrap(window.startMinute - startMinute)
            // The window as it begins on or after the night's start, and the
            // same window begun the evening before: its wrap, seen from the
            // start of the night.
            for begin in [offset, offset - Self.minutesPerDay] {
                let finish = begin + duration
                let lower = max(begin, 0)
                let upper = min(finish, lengthMinutes)
                guard upper > lower else { continue }
                stretches[window.parentID]?.append(
                    Stretch(lower: lower, upper: upper,
                            startsInNight: begin >= 0,
                            endsInNight: finish <= lengthMinutes))
            }
        }

        let length = Double(lengthMinutes)
        var placed: [(parent: Int, pill: Pill)] = []
        for (index, parentID) in parents.enumerated() {
            for stretch in Self.merged(stretches[parentID] ?? []) {
                placed.append((index, Pill(parentID: parentID,
                                           start: Double(stretch.lower) / length,
                                           end: Double(stretch.upper) / length,
                                           startsInNight: stretch.startsInNight,
                                           endsInNight: stretch.endsInNight)))
            }
        }
        // Earliest first; two that start together keep the windows' order.
        return placed
            .sorted { ($0.pill.start, $0.parent) < ($1.pill.start, $1.parent) }
            .map { $0.pill }
    }

    /// Minutes from the night's start, already clipped to it.
    private struct Stretch {
        var lower: Int
        var upper: Int
        var startsInNight: Bool
        var endsInNight: Bool
    }

    /// One parent's stretches, ascending, with any that touch or overlap
    /// joined. A joined stretch's end is only its own if nothing joined to
    /// it runs on past the night there.
    private static func merged(_ stretches: [Stretch]) -> [Stretch] {
        var out: [Stretch] = []
        for stretch in stretches.sorted(by: { ($0.lower, $0.upper) < ($1.lower, $1.upper) }) {
            guard let last = out.last, stretch.lower <= last.upper else {
                out.append(stretch)
                continue
            }
            var joined = last
            if stretch.lower == last.lower {
                joined.startsInNight = last.startsInNight && stretch.startsInNight
            }
            if stretch.upper > last.upper {
                joined.upper = stretch.upper
                joined.endsInNight = stretch.endsInNight
            } else if stretch.upper == last.upper {
                joined.endsInNight = last.endsInNight && stretch.endsInNight
            }
            out[out.count - 1] = joined
        }
        return out
    }

    // MARK: Pills → rows

    /// Whether two parents are down at once anywhere on the strip. Pills
    /// that only meet — one parent waking as the other lies down — don't
    /// count.
    static func overlaps(_ pills: [Pill]) -> Bool {
        for (index, pill) in pills.enumerated() {
            for other in pills[(index + 1)...] where other.parentID != pill.parentID {
                if other.start < pill.end && pill.start < other.end { return true }
            }
        }
        return false
    }

    /// The pills as the rows of one track. Parents who hand the night over
    /// share a single row — the plan reads as one line of sleep. Once two of
    /// them are down at the same time, one pill would hide part of the
    /// other, so each parent gets a row of their own, in `parentOrder` (any
    /// parent missing from it follows, in the pills' order).
    static func rows(_ pills: [Pill], parentOrder: [UUID]) -> [[Pill]] {
        guard !pills.isEmpty else { return [] }
        guard overlaps(pills) else { return [pills] }
        var order = parentOrder
        for pill in pills where !order.contains(pill.parentID) {
            order.append(pill.parentID)
        }
        return order
            .map { id in pills.filter { $0.parentID == id } }
            .filter { !$0.isEmpty }
    }

    // MARK: Hour marks

    /// One labelled mark under the strip.
    struct Tick: Equatable {
        enum Kind: Equatable {
            /// The night's own start and end — always marked, at the strip's
            /// two ends.
            case start, end
            /// A clock hour in between.
            case hour
        }

        /// The wall-clock minute the mark names, 0..<1440.
        let minuteOfDay: Int
        /// Where it sits across the night, 0...1.
        let position: Double
        let kind: Kind
    }

    /// The marks under the strip: the night's start, the clock's own
    /// three-hourly hours inside it (midnight, 3, 6…), and its end.
    ///
    /// `minSeparation` is the room one label needs, as a fraction of the
    /// strip. An hour mark closer than that to either end is left out — the
    /// end's own label is the one that stays — and when the hours themselves
    /// would sit closer together than that, every three hours becomes every
    /// six, then every twelve. So a short strip or a large text size thins
    /// the marks out rather than running them into each other.
    ///
    /// `everyMinutes` should divide the day evenly (the default and its
    /// doublings do), so the marks stay on the clock's hours across midnight.
    func ticks(everyMinutes: Int = 180, minSeparation: Double = 0) -> [Tick] {
        var step = max(everyMinutes, 1)
        while Double(step) / Double(lengthMinutes) < minSeparation, step < Self.minutesPerDay {
            step *= 2
        }
        var ticks = [Tick(minuteOfDay: startMinute, position: 0, kind: .start)]
        // The first of the clock's own marks after the night's start.
        var offset = step - startMinute % step
        while offset < lengthMinutes {
            let position = Double(offset) / Double(lengthMinutes)
            if position >= minSeparation, position <= 1 - minSeparation {
                ticks.append(Tick(minuteOfDay: Self.wrap(startMinute + offset),
                                  position: position, kind: .hour))
            }
            offset += step
        }
        ticks.append(Tick(minuteOfDay: endMinute, position: 1, kind: .end))
        return ticks
    }

    /// A mark's label, as short as a time gets: "9p", "12a", "8:30p" — or,
    /// on a 24-hour clock, "21", "0", "20:30".
    static func label(minuteOfDay: Int, twentyFourHour: Bool = false) -> String {
        let minute = wrap(minuteOfDay)
        let hour = minute / 60
        let past = minute % 60
        let minutes = past == 0 ? "" : (past < 10 ? ":0\(past)" : ":\(past)")
        if twentyFourHour { return "\(hour)\(minutes)" }
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        return "\(hour12)\(minutes)\(hour < 12 ? "a" : "p")"
    }

    /// Any minute count as a wall-clock minute, 0..<1440.
    private static func wrap(_ minute: Int) -> Int {
        ((minute % minutesPerDay) + minutesPerDay) % minutesPerDay
    }
}

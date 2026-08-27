import Foundation

/// Pure computation of the nighttime rotation from the shared settings: feed
/// times marching from "first feed" by "spacing" until the night window
/// closes, and the default alternating assignment. Sibling of `ScheduleEngine`
/// — no store access, no side effects; `EventStore.applyNightSchedule`
/// persists the result, tests hit this directly.
enum NightScheduleGenerator {
    /// Below this the spacing is garbage input (a corrupt synced setting could
    /// otherwise loop the generator around the clock). The UI never offers it.
    static let minimumSpacingMinutes = 60
    /// Backstop cap — a full 12h night at 1h spacing is 13 slots; anything
    /// beyond that isn't a newborn schedule, it's a bug.
    static let maxSlots = 16

    /// Wall-clock minutes (0..<1440) for each feed of the night, in night
    /// order (first feed onward, wrapping midnight). A first feed outside the
    /// window snaps to night start; a zero-length window (start == end)
    /// generates nothing.
    static func feedMinutes(nightStartMinute: Int, nightEndMinute: Int,
                            firstFeedMinute: Int, spacingMinutes: Int) -> [Int] {
        let start = wrap(nightStartMinute)
        let windowLength = (wrap(nightEndMinute) - start + 1440) % 1440
        guard windowLength > 0, spacingMinutes >= minimumSpacingMinutes else { return [] }
        var firstOffset = (wrap(firstFeedMinute) - start + 1440) % 1440
        if firstOffset > windowLength { firstOffset = 0 }
        // `through:` keeps a feed landing exactly at night's end — "9am if the
        // night runs to 9am" — matching how a parent reads the window.
        return stride(from: firstOffset, through: windowLength, by: spacingMinutes)
            .prefix(maxSlots)
            .map { wrap(start + $0) }
    }

    /// The default rotation: slot i alternates through `parents` in order
    /// (Taylor → Katie → Taylor…). With fewer than two parents there's no
    /// rotation to suggest — every slot stays unassigned (both phones ring).
    static func alternatingAssignee<P>(index: Int, parents: [P]) -> P? {
        guard parents.count >= 2 else { return nil }
        return parents[index % parents.count]
    }

    /// True when `minuteOfDay` falls inside the night window (which typically
    /// wraps midnight, e.g. 20:00–08:00). A zero-length window contains nothing.
    static func isWithinNight(minuteOfDay: Int, nightStartMinute: Int, nightEndMinute: Int) -> Bool {
        let start = wrap(nightStartMinute)
        let windowLength = (wrap(nightEndMinute) - start + 1440) % 1440
        let offset = (wrap(minuteOfDay) - start + 1440) % 1440
        return windowLength > 0 && offset <= windowLength
    }

    private static func wrap(_ minute: Int) -> Int {
        ((minute % 1440) + 1440) % 1440
    }
}

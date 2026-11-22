import Foundation

/// The season the land is in: his first year read in the hills — bare
/// late-autumn slopes, snow, blossom, fireflies on summer evenings.
///
/// A port of the sky lab's design/sky-lab/lab/season.js, number for number
/// (`SkySeasonTests` holds every day of his first year against the lab's
/// own output). From the day of the year and the latitude's sign: the
/// southern hemisphere is half a year out of step. Everything is continuous;
/// there is no day on which the hills change.
///
/// Every amount is 0 to 1.
struct SkySeason: Equatable {
    enum Name: String, Equatable {
        case winter, spring, summer, autumn
    }

    /// How much of each season the day holds; the four sum to 1.
    struct Weights: Equatable {
        let winter: Double
        let spring: Double
        let summer: Double
        let autumn: Double
    }

    /// The strongest of the four.
    let name: Name
    let weights: Weights
    /// Snow lying on the land: mid-December to early March.
    let snow: Double
    /// Snow in the air — only on some winter days (about two in five).
    let snowfall: Double
    /// 0 bare branches … 1 full leaf: leafing out in late April, bare by
    /// mid-November.
    let foliage: Double
    /// 0 fresh spring green · 0.5 deep summer green · 0.8 amber · 1 russet.
    /// (The one amount with a seam: it winds back from russet to green at
    /// the year's end, when the tree has been bare for six weeks.)
    let leafHue: Double
    /// Leaves in the air: October to mid-November.
    let leafFall: Double
    /// The tree in flower: mid-April to mid-May.
    let blossom: Double
    /// Petals in the air.
    let petals: Double
    /// June to mid-August (a sky shows them only from dusk).
    let fireflies: Double
    /// 0 dormant straw … 1 green.
    let grass: Double
    /// Hoar on the ground: late autumn and early spring, where no snow lies.
    let frost: Double

    // MARK: The season of a day

    /// The season on `dayOfYear` (1 on 1 January) at `latitude` (only its
    /// sign matters). `snowfall`, when given, says how much snow is in the
    /// air instead of the day's own roll — the bench's switch, the lab's
    /// `snowfall=`; the snow lying on the land is always the date's.
    static func on(dayOfYear: Double, latitude: Double, snowfall told: Double? = nil) -> SkySeason {
        let day = latitude < 0 ? dayOfYear + 182.5 : dayOfYear
        let angle = (2 * Double.pi * (day - 15)) / 365           // 0 in mid-January
        let winter = max(0, cos(angle))
        let spring = max(0, sin(angle))
        let summer = max(0, -cos(angle))
        let autumn = max(0, -sin(angle))
        let total = winter + spring + summer + autumn
        let weights = Weights(winter: winter / total, spring: spring / total,
                              summer: summer / total, autumn: autumn / total)
        // The strongest; where two are level, the earlier in this order.
        var name = Name.winter
        var strongest = weights.winter
        for (candidate, weight) in [(Name.spring, weights.spring), (.summer, weights.summer),
                                    (.autumn, weights.autumn)] where weight > strongest {
            name = candidate
            strongest = weight
        }

        let inYear = wrapped(day)
        let snow = window(day, 345, 60, soft: 12)                // mid-December → early March
        let foliage = window(day, 115, 305, soft: 16)            // leafing out late April, bare by mid-November
        let turning = SkyMath.smoothstep(255, 300, inYear)               // mid-September → late October
        let greening = 1 - SkyMath.smoothstep(115, 165, inYear)
        let leafHue = turning > 0 ? 0.5 + 0.5 * turning : 0.5 - 0.5 * greening
        let blossom = window(day, 105, 135, soft: 9)             // mid-April → mid-May
        let fireflies = window(day, 160, 232, soft: 12)          // June → mid-August
        let leafFall = window(day, 275, 322, soft: 10)           // October → mid-November
        let grass = window(day, 95, 300, soft: 22)
        let frost = window(day, 300, 345, soft: 14) * (1 - snow) + window(day, 60, 95, soft: 12) * (1 - snow)

        // Snow falls on about two winter days in five: the day's own roll,
        // from the calendar's day whichever hemisphere it is.
        let seed = sin(dayOfYear.rounded(.down) * 127.1) * 43758.5453
        let daySeed = seed - seed.rounded(.down)
        let falling: Double
        if let told, told.isFinite {
            falling = SkyMath.clamped(told)
        } else {
            falling = snow > 0.5 && daySeed < 0.4 ? 0.5 + daySeed : 0
        }

        return SkySeason(name: name, weights: weights, snow: snow, snowfall: falling, foliage: foliage,
                         leafHue: leafHue, leafFall: leafFall, blossom: blossom, petals: blossom * 0.8,
                         fireflies: fireflies, grass: grass, frost: frost)
    }

    /// The season at `date`, by the household's calendar and place: the day
    /// of the year is the local one, as the lab's is.
    static func at(_ date: Date, place: SkyPlace, calendar: Calendar, snowfall: Double? = nil) -> SkySeason {
        let day = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        return on(dayOfYear: Double(day), latitude: place.latitude, snowfall: snowfall)
    }

    // MARK: The tree's step

    /// The season as the tree is cut for it: foliage, blossom, snow, frost,
    /// leaf fall, grass and leaf hue, each to the nearest fortieth — the
    /// lab's key for its tree masks and painted planes
    /// (skies/hill-painted.js, `seaKey`). Two days with the same step show
    /// the same tree, so nothing is cut again until one of the seven has
    /// moved by a fortieth: 186 steps in his first year by the lab's count,
    /// and not one in the eleven weeks from 2 July to mid-September.
    var step: [Int] {
        [foliage, blossom, snow, frost, leafFall, grass, leafHue].map {
            Int(($0 * 40).rounded(.toNearestOrAwayFromZero))
        }
    }

    // MARK: The lab's arithmetic

    /// A day number brought into 0 ..< 365.
    private static func wrapped(_ day: Double) -> Double {
        (day.truncatingRemainder(dividingBy: 365) + 365).truncatingRemainder(dividingBy: 365)
    }

    /// 1 inside `start ... end` (days of the year, wrapping past 365),
    /// easing in and out over `soft` days either side of each end.
    private static func window(_ day: Double, _ start: Double, _ end: Double, soft: Double) -> Double {
        let d = wrapped(day)
        let last = end < start ? end + 365 : end
        let inside = { (x: Double) in
            SkyMath.smoothstep(start - soft, start + soft, x) * (1 - SkyMath.smoothstep(last - soft, last + soft, x))
        }
        return max(inside(d), inside(d + 365), inside(d - 365))
    }
}

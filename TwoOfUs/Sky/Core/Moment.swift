import Foundation

/// One instant of the bedtime moment: everything that plays, as plain
/// numbers — a value of its own, so the moment is unit-tested without a
/// display (`MomentTests`).
struct MomentFrame: Equatable {
    /// The band of light that leaves tonight's star once the view is up and
    /// crosses the anchor window to its farthest corner. It only tells the
    /// eye where to look; his stars answering as it passes carry the gesture.
    struct Band: Equatable {
        /// How far the crest has gone from tonight's star, in points. It runs
        /// on after the band has crossed (which stars it has passed is asked
        /// of it for as long as the moment lasts).
        var radius: CGFloat
        /// How strongly his stars answer as the crest passes, 0 … 1: all the
        /// way across, and nothing once it has crossed.
        var strength: Double
        /// The band's own light, 0 … 1 of its peak. It is never a circle
        /// round the star — that is sonar: held until the crest is 150 pt
        /// out, fullest two fifths of the way across, gone by nine tenths.
        var light: Double
    }

    /// How far the phone page's cards have stepped back, 0 … 1: a card's
    /// opacity is 1 − `cards`.
    var cards: Double
    /// How far the camera has looked up: 0 at rest … 1 up, where it stays for
    /// the night. Under Reduce Motion there is no move: this is then the
    /// weight of the looked-up still in a short dissolve.
    var look: Double
    /// How lit tonight's star is: 0 … 1, and past it (to about 1.3) at the
    /// spark's flare. Under Reduce Motion it has no spark: it is lit, and
    /// belongs to the looked-up still, which dissolves in by `look`.
    var star: Double
    /// Nil until the band leaves, and always under Reduce Motion.
    var band: Band?
    /// The opacity of "✦ Night 143", the page's one line: there only while
    /// the cards are away and the view is up — never read through a
    /// returning card.
    var caption: Double
    /// How far the room has dimmed because he sleeps, 0 … 1. The sky gets
    /// deeper and stiller with it, never brighter.
    var depth: Double
    /// The faint presence his stars keep while the cards are away, whatever
    /// the hour: in a sky still too light for stars (a July bedtime) the held
    /// frame is then a sky of stars, not a crescent of them. Up to 0.34; they
    /// are let go as the cards come back.
    var starsKept: Double
}

/// The bedtime moment, and the quieter events beside it — time as data.
///
/// When a night sleep is started by hand on this phone and the night begins
/// with it, Home plays one timeline, seconds since the tap: the cards fall
/// back, the view rises into every night of his life, tonight's star is lit,
/// a band of light leaves it and his stars answer, "✦ Night 143" stands at
/// the foot, and the cards return over the sky that is already there. The
/// sky keeps its pace; the cards give up the time. The view does not come
/// back down: looking up is a state, and lasts until first light.
///
/// One table for the sky and for the cards, so the two cannot drift apart:
/// the caption has gone before a card is back, and the band has crossed
/// before that. Every value is a pure function of the moment's age — nothing
/// is stored, and SwiftUI's own animations need drive nothing of the sky.
///
/// The sky lab's curves to the sample (`lab/presence.js`: `MOMENT`,
/// `momentVeil`, `momentCaption`, `roomDepth`; `hill-painted.js`: `lookOf`,
/// `sparkOf`, `ringOf`), pinned every 0.05 s in `MomentTests`. The touch that
/// ends the moment is the design's rule only: the lab has no touch.
///
/// What the camera does is written once, with the events (`SkyEvent.Move`):
/// this table says WHEN the view rises (`Beats.rise`), and reads `look`
/// through the same move the driver's glide is given, so the sky this
/// frame describes and the sky a running glide draws are one.
enum Moment {
    // MARK: The table

    /// The moment's beats, in seconds since the tap.
    struct Beats: Equatable {
        /// The cards fall back (a smoothstep): under 5 % by 0.87 s. SwiftUI's
        /// `.easeInOut` over the same second is not this curve — it runs up
        /// to 3 % of a card ahead — so a card faded by a SwiftUI animation
        /// and the sky reading `cards` from here are that far apart.
        let fall: ClosedRange<TimeInterval>
        /// The view rises (a quintic ease, from standing to standing). The
        /// slab's sky is twice as tall as the Duo's, so its rise is 0.3 s
        /// longer and its peak stays under 500 pt/s. Under Reduce Motion
        /// there is no move: the looked-up still dissolves in (a smoothstep)
        /// once the cards are away.
        let rise: ClosedRange<TimeInterval>
        /// The band leaves tonight's star as the view arrives, and crosses
        /// the anchor window to its farthest corner in this long (276 pt/s on
        /// the Duo, 410 on the slab). Nil under Reduce Motion: no band.
        let bandLeaves: TimeInterval?
        /// How long the band takes to cross.
        let bandCrosses: TimeInterval?
        /// "✦ Night 143": in as the view comes to rest…
        let captionIn: ClosedRange<TimeInterval>
        /// …and out before the cards begin to come back.
        let captionOut: ClosedRange<TimeInterval>
        /// The cards return, with an ease-out (SwiftUI's `.easeOut`),
        /// starting as the caption has gone.
        let back: ClosedRange<TimeInterval>

        /// The whole moment: the cards are back.
        var whole: TimeInterval { back.upperBound }
    }

    /// The table for a world, in full or under Reduce Motion — where the
    /// cards go, the looked-up still dissolves in once they are away, the
    /// caption stands for two seconds and the cards return: about 4 s.
    static func beats(world: SkyWorld.Kind, reduced: Bool = false) -> Beats {
        if reduced {
            return Beats(fall: 0...0.6, rise: 0.6...1.2, bandLeaves: nil, bandCrosses: nil,
                         captionIn: 1.2...1.6, captionOut: 3.0...3.4, back: 3.4...4.0)
        }
        switch world {
        case .duo:
            return Beats(fall: 0...1.0, rise: 0.3...2.4, bandLeaves: 2.1, bandCrosses: 2.1,
                         captionIn: 2.0...2.8, captionOut: 4.15...4.6, back: 4.6...5.8)
        case .slab:
            return Beats(fall: 0...1.0, rise: 0.3...2.7, bandLeaves: 2.3, bandCrosses: 2.0,
                         captionIn: 2.0...2.8, captionOut: 4.15...4.6, back: 4.6...5.8)
        }
    }

    /// A touch ends the moment at once: the cards are back in this long…
    static let touchReturnsCards: TimeInterval = 0.3
    /// …and the band and the caption are out in this long.
    static let touchPutsOutLights: TimeInterval = 0.2
    /// When the moment is over — the cards are back: 5.8 s (about 4 s under
    /// Reduce Motion), or 0.3 s after the touch that ended it.
    static func whole(world: SkyWorld.Kind, reduced: Bool = false, endedAt: TimeInterval? = nil) -> TimeInterval {
        let natural = beats(world: world, reduced: reduced).whole
        guard let endedAt else { return natural }
        return min(natural, max(0, endedAt) + touchReturnsCards)
    }

    // MARK: The bedtime moment

    /// The moment at `age` seconds since the tap.
    ///
    /// - `world`: the rise and the band keep the pace of the world's size.
    /// - `reduced`: Reduce Motion — no move, no band, no spark.
    /// - `endedAt`: the age at which a touch on Home ended it, if one did.
    ///   From then the cards are back in 0.3 s and the band and the caption
    ///   are out in 0.2 s, each from wherever it was; nothing that had not
    ///   begun begins. The view stays up — `look` runs on at its own pace,
    ///   the star stays lit, the room goes on dimming: a touch does not
    ///   change them.
    static func frame(age: TimeInterval, world: SkyWorld.Kind, reduced: Bool = false,
                      endedAt: TimeInterval? = nil) -> MomentFrame {
        let now = untouched(age: age, world: world, reduced: reduced)
        guard let endedAt, age > endedAt else { return now }

        let then = untouched(age: endedAt, world: world, reduced: reduced)
        let since = age - endedAt
        let cardsLeft = 1 - easeOut(since / touchReturnsCards)
        let lightsLeft = 1 - SkyMath.smoothstep(0, touchPutsOutLights, since)
        var frame = now
        // (never slower than the moment's own course: a touch as the cards
        // are already returning does not hold them back)
        frame.cards = min(now.cards, then.cards * cardsLeft)
        frame.starsKept = min(now.starsKept, then.starsKept * cardsLeft)
        frame.caption = min(now.caption, then.caption * lightsLeft)
        if let was = then.band, let band = now.band {
            frame.band = MomentFrame.Band(radius: band.radius,
                                          strength: min(band.strength, was.strength * lightsLeft),
                                          light: min(band.light, was.light * lightsLeft))
        } else {
            frame.band = nil
        }
        return frame
    }

    /// The moment as it plays when nothing touches it.
    private static func untouched(age: TimeInterval, world kind: SkyWorld.Kind, reduced: Bool) -> MomentFrame {
        let table = beats(world: kind, reduced: reduced)
        let cards = stepBack(age, table)
        // (the rise is the table's, carried as every event carries `look`:
        // a quintic from standing to standing, a smoothstep's dissolve
        // under Reduce Motion)
        let look = SkyEvent.Move.bedtime(world: kind, reduced: reduced).look(age: age, from: 0)
        let lit = SkyMath.smoothstep(table.captionIn.lowerBound, table.captionIn.upperBound, age)
            * (1 - SkyMath.smoothstep(table.captionOut.lowerBound, table.captionOut.upperBound, age))
        // The faint stars come up as the view arrives, ahead of the band,
        // and are let go as the cards come back.
        let arrives = table.bandLeaves ?? table.rise.lowerBound
        let kept = 0.34 * SkyMath.smoothstep(arrives - 0.5, arrives + 0.4, age)
            * (1 - easeOut((age - table.back.lowerBound) / (table.back.upperBound - table.back.lowerBound)))
        return MomentFrame(
            cards: cards,
            look: look,
            star: reduced ? 1 : spark(age),
            band: band(age: age, table: table, world: SkyWorld.world(kind)),
            // (By the view: the line comes in over the last of the rise, so
            // on a slab, whose rise is longer, a little later.)
            caption: caption(cards: cards, lit: lit, look: look),
            depth: depth(of: .night, begins: .withTheMoment, age: age),
            starsKept: kept)
    }

    /// The opacity of "✦ Night 143" for how far the cards have stepped back
    /// (0 … 1), how lit the line's own beat has it (0 … 1) and how far the
    /// view has looked up. The page's one line is there only while the cards
    /// are away and the view is up: nothing of it until a card is more than
    /// a hundredth gone, then by the cards' fade SQUARED — at a card half
    /// back it is a quarter, so it is never read through a returning card —
    /// and it comes in over the last two fifths of the rise.
    ///
    /// The lab's rule (`drawCaption`). In the moment's own table the cards
    /// are wholly away for as long as the line is lit, so there the square
    /// is 1 and no sample of the timeline can show it: `MomentTests` pins
    /// it against the lab's rule asked OFF the table — it is for any other
    /// clock that plays the line (a view retargeted mid-moment).
    static func caption(cards: Double, lit: Double, look: Double) -> Double {
        guard cards > 0.01 else { return 0 }
        let away = SkyMath.clamped(cards)
        return away * away * lit * SkyMath.smoothstep(0.6, 1, look)
    }

    /// How far the cards have stepped back: they fall back with a smoothstep
    /// and return with an ease-out.
    private static func stepBack(_ age: TimeInterval, _ table: Beats) -> Double {
        if !(age > table.fall.lowerBound) || age >= table.back.upperBound { return 0 }
        if age >= table.back.lowerBound {
            return 1 - easeOut((age - table.back.lowerBound) / (table.back.upperBound - table.back.lowerBound))
        }
        return SkyMath.smoothstep(table.fall.lowerBound, table.fall.upperBound, age)
    }

    /// How lit tonight's star is, `age` seconds after he went down: a spark
    /// that swells past full and settles. Lit from the first instant, the
    /// flare at 1.5 s. A star is lit ONCE: it is never put out to be lit
    /// again.
    private static func spark(_ age: TimeInterval) -> Double {
        if age <= 0 { return 0 }
        let rise = 1 - exp(-age / 0.55)
        let late = (age - 1.5) / 0.9
        return rise + 0.35 * exp(-late * late)
    }

    /// How far the band has to go: from tonight's star's looked-up home to
    /// the farthest corner of the anchor window (the pace is the anchor
    /// window's, so the spread's phone page is the cover's picture at every
    /// instant of it).
    static func bandReach(world: SkyWorld) -> Double {
        let home = world.tonightUp
        let across = Double(max(home.x, world.anchor.width - home.x))
        let down = Double(max(home.y, world.anchor.height - home.y))
        return (across * across + down * down).squareRoot()
    }

    private static func band(age: TimeInterval, table: Beats, world: SkyWorld) -> MomentFrame.Band? {
        guard let leaves = table.bandLeaves, let crosses = table.bandCrosses, age > leaves else { return nil }
        let since = age - leaves
        let reach = bandReach(world: world)
        let radius = reach / crosses * since
        var strength = SkyMath.smoothstep(0, 0.4, since) * (1 - SkyMath.smoothstep(reach * 1.04, reach * 1.3, radius))
        if strength <= 0.003 { strength = 0 }
        let light = strength > 0
            ? SkyMath.smoothstep(150, max(reach * 0.42, 230), radius) * (1 - SkyMath.smoothstep(reach * 0.44, reach * 0.9, radius))
            : 0
        return MomentFrame.Band(radius: CGFloat(radius), strength: strength, light: light)
    }

    // MARK: The quiet events

    /// The view and tonight's star through a quiet event: no veil, no band,
    /// no caption — it plays behind the cards.
    struct Quiet: Equatable {
        /// 0 at rest … 1 looking up (under Reduce Motion: the weight of the
        /// looked-up still).
        var look: Double
        /// How lit tonight's star is, 0 … 1.
        var star: Double
    }

    /// A night sleep that begins the night from anywhere but this phone's
    /// hand (the other phone, Siri, a widget, SNOO) while Home is on screen:
    /// the quiet rise. The view is up over 2.5 s (`SkyEvent.Move.arrive`),
    /// and the star fades in over the first 0.8 s beside the tree and rises
    /// with it. Under Reduce Motion: a 0.6 s dissolve, the star with the
    /// looked-up still.
    static func arrive(age: TimeInterval, reduced: Bool = false) -> Quiet {
        Quiet(look: SkyEvent.Move.arrive(reduced: reduced).look(age: age, from: 0),
              star: reduced ? 1 : SkyMath.smoothstep(0, 0.8, age))
    }

    /// First light, Home on screen: the quiet settle. The view holds for a
    /// tenth of a second and is down by 2.7 s (`SkyEvent.Move.settle`); the
    /// star goes out with the other stars, by 2.3 s, on its way back to the
    /// tree. Under Reduce Motion: a 0.6 s dissolve.
    static func settle(age: TimeInterval, reduced: Bool = false) -> Quiet {
        Quiet(look: SkyEvent.Move.settle(reduced: reduced).look(age: age, from: 1),
              star: reduced ? 1 : 1 - SkyMath.smoothstep(0.1, 2.3, age))
    }

    // MARK: The room

    /// How a sleep began, for the room: with the bedtime moment, or quietly
    /// (it arrived from elsewhere; a nap; put down again after a feed).
    enum Beginning: Equatable {
        case withTheMoment, quietly
    }

    /// The room's depth `age` seconds after a sleep starts: toward what that
    /// sleep dims it to (`SleepKind.depth`: a night's all the way, a nap's
    /// not half). It never jumps: it eases in from 0 — with the moment,
    /// after the cards have gone (from 1.2 s, and to 9 s: long after the
    /// cards are back); quietly, at once, over four seconds.
    static func depth(of sleep: SleepKind, begins: Beginning, age: TimeInterval) -> Double {
        switch begins {
        case .withTheMoment: return sleep.depth * SkyMath.smoothstep(1.2, 9, age)
        case .quietly: return sleep.depth * SkyMath.smoothstep(0, 4, age)
        }
    }

    /// The room's depth `age` seconds after he wakes: still as dim as that
    /// sleep had it, and un-dimmed over about five seconds — so the first
    /// frame after he wakes is the frame before it. Waking moves nothing
    /// else, at any hour, after any sleep.
    static func depth(wokenFrom sleep: SleepKind, age: TimeInterval) -> Double {
        sleep.depth * (1 - SkyMath.smoothstep(0.3, 5, age))
    }

    // MARK: Easings

    /// SwiftUI's `.easeOut` — the cubic Bézier (0, 0, 0.58, 1) — at
    /// `progress` 0 … 1: quick away and soft to rest, half way at a third of
    /// the time, 95 % by 0.83.
    static func easeOut(_ progress: Double) -> Double {
        if !(progress > 0) { return 0 }
        if progress >= 1 { return 1 }
        // x(s) = 3·0.58·(1 − s)·s² + s³ is monotonic on 0 … 1: solve
        // x(s) = progress by bisection, then take y(s).
        var low = 0.0, high = 1.0
        for _ in 0..<40 {
            let s = (low + high) / 2
            if 1.74 * (1 - s) * s * s + s * s * s < progress { low = s } else { high = s }
        }
        let s = (low + high) / 2
        return 3 * (1 - s) * s * s + s * s * s
    }
}

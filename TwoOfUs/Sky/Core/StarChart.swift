import Foundation

/// His stars: "a star for every night of his life". Night 1 is the night he
/// was born; tonight is night N. Every night has one star and it never
/// moves: its place is a function of the night's number, the world and the
/// layout alone, so the sky fills as he grows and a star cast on this phone
/// stands where the other parent's phone puts it. Nothing is stored and
/// nothing is random.
///
/// The sky is laid out for the LOOKED-UP view, because that is the night:
/// in boxes, top to bottom, each with a density — thickest overhead and
/// thinning toward the land; a few more in the header's clear gap; fewer in
/// the strip's clear window, where tonight's star is to be the one bright
/// thing; and, low down, the two parts of the sky the rest pose shows,
/// weighted so the night he is awake is not empty. Places are gathered a
/// little, slowly, into loose knots with open sky between them. Then the
/// rules, each a taken place — the night is cast again, somewhere else, and
/// the count is what it was:
///
///  · no star behind the header's words and buttons (and one em past the
///    last glyph: a star on the baseline after "old" reads as punctuation),
///    the strip's furniture, the clock at rest or the tab capsule; none in
///    the land or the tree's crown; none closer to another than 5.6 pt;
///  · tonight's star has dark sky of its own in both poses: nothing within
///    30 pt of it looking up, nor 17 pt of it beside the tree;
///  · the first night's star — the brightest in his sky — has a place of its
///    own on the Duo, in the header's gap between his name and the gear,
///    with 18 pt of sky to itself;
///  · a four-point star (the first night's, the month-nights') is never at a
///    card's edge: 10 pt from every edge of every card in the standing
///    layouts, never cut by the display's own edge, 9 pt further from the
///    words than an ordinary night, 70 pt from tonight's place, and 80 pt
///    from another of its kind while the sky has the room (60, then 44, at
///    two years).
///
/// It is ORDER-DEPENDENT: each night is judged only against the nights
/// before it, so a new night moves no earlier star — and one number read
/// wrongly here would move every later one. It is the lab's `starsFor`
/// (`design/sky-lab/skies/hill-painted.js`) line for line, with its hash and
/// noise (`SkyNoise`) and its skyline (`Skyline`), and it is pinned to the
/// lab's own places at fourteen ages on three displays.
///
/// This is where the stars ARE. How they are drawn — the sprites, the
/// twinkle, the band's answers, a four-point star as a point under glass or
/// beside the moon — is the renderer's; each star carries the numbers it
/// will ask for.
///
/// Pure: `StarChartTests` (`SkyCoreFixturesStars`, exported by
/// `design/sky-lab/tools/swift-fixtures/stars.mjs`).
enum StarChart {
    // MARK: A star

    /// One night's star, where it stands.
    struct Star: Equatable {
        /// Which night it is the star of.
        enum Kind: String, Equatable, CaseIterable {
            /// An ordinary night.
            case night
            /// A month-birthday's night: a brighter star with four points.
            case month
            /// The night he was born: the brightest star in his sky.
            case first
            /// Tonight: warm, and lit only once the night has begun.
            case tonight
        }

        /// THE ORDER OF RANK, by summed light, least first: an ordinary
        /// night; one of the brighter fifth (a larger core, a little glow);
        /// a month-night (twice the brightest ordinary night or more); the
        /// first night; tonight.
        enum Light: Int, Equatable, Comparable, CaseIterable {
            /// A small faint light: most nights.
            case ordinary
            /// One of the brighter fifth of the ordinary nights.
            case brighter
            /// A month-night's four-point mark: never under 0.8 of its full
            /// strength — "a four-point star is never a ghost".
            case monthNight
            /// The first night's: the same mark, larger.
            case firstNight
            /// Tonight's: drawn over everything, and never dimmed.
            case tonight

            static func < (a: Light, b: Light) -> Bool { a.rawValue < b.rawValue }
        }

        /// An ordinary night's colour in the dark print (the pale page's are
        /// all white; a four-point star is tonight's cream).
        enum Tint: String, Equatable {
            /// Blue-white: warmth under −0.25.
            case cool
            /// Neither.
            case plain
            /// Cream: warmth over 0.3.
            case warm
            /// One in ten of the plain ones.
            case rose
        }

        /// The night's number: 1 the night he was born.
        let night: Int
        /// What kind of night.
        let kind: Kind
        /// Its place LOOKING UP, in display points with x from the anchor
        /// window's leading edge. Tonight's: its home in the clear window.
        let up: CGPoint
        /// Its place AT REST, the everyday view (world points: the same
        /// measure): the looked-up place turned back and lowered — most are
        /// above the top of the display then. Tonight's: its home above the
        /// tree's left shoulder.
        let rest: CGPoint
        /// How strong a light it is, 0 – 1: most nights are faint, a few are
        /// bright, as in a real sky (0.22 – 0.72); a month-night is 0.78,
        /// tonight 0.92, the first night 1. Stars come out in this order as
        /// the sky darkens (`comesOut`).
        let magnitude: Double
        /// −1 cool blue-white … +1 warm cream.
        let warmth: Double
        /// Its slow swell, for the renderer's clock.
        let twinkle: Twinkle
        /// The radius of its point, in points: an ordinary night's is 0.52
        /// to 1.15 (capped: the largest were as strong as a month-night's
        /// mark); a four-point star's is the cap — what it is drawn as under
        /// glass or beside the moon. The slab's are a tenth smaller.
        let radius: CGFloat
        /// Half the box of its four-point mark, in points, as it stands: a
        /// month-night's 9.8 (about 10 × 13 pt drawn), the first night's
        /// 12.04 (about 16 pt across), tonight's 14 at rest (it is drawn
        /// 1.42 × that looking up). 0 for an ordinary night: a round point.
        let reach: CGFloat
        /// Where it stands in the order of rank of this sky: 1 the first by
        /// summed light (tonight's, then the first night's, then the
        /// month-nights, then the ordinary nights by strength).
        let rank: Int
        /// How many times the night was cast again before its place was
        /// free: 0, its own first place. A four-point star is cast up to 90
        /// times for each room it may settle for (80, 60, 44 pt), an
        /// ordinary one 30 times; past those, a step of the spiral round its
        /// first place (480 of them); and where even that finds nothing (a
        /// sky far fuller than two years makes it) it stands where it was
        /// first cast, and the count is one more than every try: `foundNoPlace`.
        let again: Int

        /// Every place it tried was taken: it stands where it was first
        /// cast, over whatever is there. Never to two years, on any display.
        var foundNoPlace: Bool { again > (kind == .night ? 30 : 270) + 480 }

        /// It is drawn with four points: the first night, the month-nights
        /// and tonight. "One mark, one meaning."
        var isFourPoint: Bool { kind != .night }

        /// Its light among the ordinary range, 0 the faintest … 1.
        var brightness: Double { min(1, max(0, (magnitude - 0.22) / 0.5)) }

        /// Its class of light.
        var light: Light {
            switch kind {
            case .tonight: return .tonight
            case .first: return .firstNight
            case .month: return .monthNight
            case .night: return brightness > StarChart.brighterFrom ? .brighter : .ordinary
            }
        }

        /// How dark the sky must be for it to show: it is out by the time
        /// "stars out" (0 at the sun 4° under the horizon … 1 at 12°) is
        /// this much and a fifth more. The brightest come out first.
        var comesOut: Double { (1 - magnitude) * 0.8 }

        /// An ordinary night's tint in the dark print: warm or cool by its
        /// warmth, and of the rest one in ten is rose.
        var tint: Tint {
            if warmth > 0.3 { return .warm }
            if warmth < -0.25 { return .cool }
            return SkyNoise.hash(night, salt: 8) > 0.9 ? .rose : .plain
        }

        /// Which way it steps aside should the moon stand exactly on it, in
        /// turns (0 – 1): a star stands off the moon's disc along the line
        /// between them, and here there is none.
        var steppingAside: Double { SkyNoise.hash(night, salt: 9) }

        /// Whether it is in view LOOKING UP on a display of this size (the
        /// lab's census: 143 of 143 at 142 days, on all three displays).
        func isInViewLookingUp(_ display: SkyWorld.Display) -> Bool {
            up.y > 2 && up.y < display.size.height && up.x > 2 && up.x < display.anchorWidth - 2
        }

        /// Whether it is in view AT REST, in the everyday view's sky (60 on
        /// the cover at 142 days, 28 on the slab: the rest pose at night is
        /// only the evening before bedtime).
        func isInViewAtRest(_ display: SkyWorld.Display) -> Bool {
            rest.y > 2 && rest.x < display.anchorWidth - 2 && rest.x > 2
        }
    }

    /// A star's slow swell: the renderer's `twinkle`.
    struct Twinkle: Equatable {
        /// Seconds for one swell: 2.4 – 5.6 for his, 3 – 7 on the leading page.
        let period: Double
        /// Where in it the star is at time 0, 0 – 1.
        let phase: Double
        /// A third of his stars do not twinkle at all.
        let steady: Bool
    }

    /// From this `brightness` an ordinary night is one of "the brighter
    /// fifth": on the pale page a larger crisp round core on its own bit of
    /// dusk. (The dark print gives a small soft glow from 0.5; once his sky
    /// is dense, past 180 nights, the pale page keeps the core for the
    /// brightest tenth, from 0.76 at 330 — both the renderer's.)
    static let brighterFrom = 0.6

    // MARK: A night's own numbers

    /// What a night's number alone says of its star (`lab/nights.js`,
    /// `nights`): where in the sky it is first cast, and its light.
    struct Night: Equatable {
        /// The night's number: 1 the night he was born.
        let number: Int
        /// Tonight's, the first night's, a month-night's or an ordinary one.
        let kind: Star.Kind
        /// Its cast across the sky's width, 0 – 1…
        let u: Double
        /// …and down it, 0 the zenith – 1 the land: a low-discrepancy
        /// sequence (the plastic number's), so each new star lands in the
        /// widest gap the earlier ones left, with a hair of jitter.
        let v: Double
        /// How strong its light is, 0 – 1 (`Star.magnitude`).
        let magnitude: Double
        /// −1 cool blue-white … +1 warm cream: tonight's 1, the first
        /// night's 0.55, any other within ±0.55.
        let warmth: Double
        /// Its slow swell.
        let twinkle: Twinkle
    }

    /// The numbers of night `number` in a sky of `count` nights. The last
    /// night is tonight's whatever else it is; the first is the first
    /// night's; `monthNights` are his month-birthdays' nights — by the
    /// calendar, from his real date of birth (`NightCount`), where the lab
    /// counts 30.44-day months.
    static func night(_ number: Int, of count: Int, monthNights: Set<Int>) -> Night {
        let jitter = 0.018
        let n = Double(number)
        let u = fraction(0.5 + n * castAcross + (SkyNoise.hash(number, salt: 1) - 0.5) * jitter)
        let v = fraction(0.5 + n * castDown + (SkyNoise.hash(number, salt: 2) - 0.5) * jitter)
        let isTonight = number == count
        let isFirst = number == 1
        let isMonth = !isFirst && monthNights.contains(number)
        // Most stars are faint, a few are bright — as in a real sky.
        let roll = SkyNoise.hash(number, salt: 3)
        var magnitude = 0.22 + 0.5 * pow(roll, 2.6)
        if isMonth { magnitude = 0.78 }
        if isFirst { magnitude = 1 }
        if isTonight { magnitude = 0.92 }
        let warmth = isTonight ? 1 : isFirst ? 0.55 : (SkyNoise.hash(number, salt: 4) - 0.5) * 1.1
        return Night(
            number: number,
            kind: isTonight ? .tonight : isFirst ? .first : isMonth ? .month : .night,
            u: u, v: v, magnitude: magnitude, warmth: warmth,
            twinkle: Twinkle(period: 2.4 + SkyNoise.hash(number, salt: 5) * 3.2,
                             phase: SkyNoise.hash(number, salt: 6),
                             steady: SkyNoise.hash(number, salt: 7) > 0.65))
    }

    // MARK: The layout

    /// What of Home's layout his stars are cast round, at scroll-top. Rects
    /// are in display points, as measured; `anchorX` brings them into the
    /// anchor window's own x. A different name, type size or locale re-casts
    /// the stars near the header — so these are to be the layout's settled
    /// numbers, never a frame mid-animation.
    struct Layout: Equatable {
        /// Display x of the anchor window's leading edge: 0 on the cover and
        /// the slab, 485 on the spread (whose leading page then has an
        /// ordinary sky of its own, `ordinarySky`).
        var anchorX: CGFloat = 0
        /// His name…
        var name: CGRect?
        /// …and the age line under it. With the avatar they are one block:
        /// no star squeezes between them.
        var age: CGRect?
        /// The avatar button.
        var avatar: CGRect?
        /// The gear button.
        var gear: CGRect?
        /// Display x where the Duo's strip window begins (the phone page's
        /// cards end there). Nil: the world's own, THE LAB'S 362 pt from
        /// the anchor window's leading edge.
        var stripWindow: CGFloat?
        /// The leading page's title: none of the page's own stars stands
        /// behind it (it changes with the hour — "The day so far",
        /// "Miller's book" — and the page's sky with it)…
        var title: CGRect?
        /// …nor behind the line under it.
        var subtitle: CGRect?
        /// The phone page's cards in the standing layouts (display points,
        /// like the rest): what a four-point star keeps 10 pt clear of. The
        /// FIRST is the Today card, whose edges count at rest too. A fixed
        /// table measured once per layout in both night layouts — never
        /// whatever is on screen, or a star would move when he wakes. Nil:
        /// the world's own, THE LAB'S (`SkyWorld.labCards`).
        var cards: [CGRect]?
    }

    /// A rect by its edges, in looked-up points with the anchor window's x
    /// (kept as edges: the lab's arithmetic is on them).
    struct Edges: Equatable {
        /// Its leading edge…
        let x0: Double
        /// …its top…
        let y0: Double
        /// …its trailing edge…
        let x1: Double
        /// …and its foot.
        let y1: Double

        /// The same as a rect.
        var rect: CGRect {
            CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        }
    }

    // MARK: Casting

    /// His sky on night `nights`: one star for every night, in order, each
    /// where it stands looking up and at rest. The last is TONIGHT'S, at its
    /// two homes; it is in the list whether or not it is lit yet — it takes
    /// nobody's place (every other night keeps clear of both its homes from
    /// the first), so the same list serves before he is down and after, and
    /// the renderer lights it by the moment's `star`.
    static func cast(nights count: Int, monthNights: Set<Int>, world: SkyWorld, layout: Layout) -> [Star] {
        guard count >= 1 else { return [] }
        var sky = Casting(field: Field(world: world, layout: layout))
        sky.taken.reserveCapacity(count)
        let field = sky.field
        var cast: [(night: Night, up: Spot, again: Int)] = []
        cast.reserveCapacity(count)

        for number in 1...count {
            let night = self.night(number, of: count, monthNights: monthNights)
            if night.kind == .tonight {
                cast.append((night, field.tonightUp, 0))
                sky.taken.append(Taken(x: field.tonightUp.x, y: field.tonightUp.y, ordinary: false, fourPoint: false))
                continue
            }
            // the first night — the brightest star in his sky — has a place
            // of its own where the night's view shows it with the cards on
            // (if that place is free on this display)
            if night.kind == .first, let own = field.firstUp, sky.free(own.x, own.y, big: false) {
                cast.append((night, own, 0))
                sky.taken.append(Taken(x: own.x, y: own.y, ordinary: false, fourPoint: true))
                sky.firstAt = own
                continue
            }
            let at = field.place(u: night.u, v: night.v)
            let big = night.kind != .night
            var spot = at
            var again = 0
            // One star per night has to be countable: a place that is
            // taken, hidden or behind the words gives way to another —
            // judged only against the nights before it.
            if !sky.free(at.x, at.y, big: big) {
                var found = false
                let casts = big ? 90 : 30
                let rooms: [Double] = big ? [80, 60, 44] : [0]
                // first, cast again: the night's own second, third… place,
                // anywhere in the sky (the nearest free place would line
                // the stars up along the edge of whatever they could not
                // sit behind)
                for (settled, pair) in rooms.enumerated() where !found {
                    for k in 1...casts {
                        let next = field.place(u: fraction(night.u + Double(k) * 0.6180339887),
                                               v: fraction(night.v + Double(k) * 0.7548776662))
                        if sky.free(next.x, next.y, big: big, pair: pair) {
                            spot = next
                            again = settled * casts + k
                            found = true
                            break
                        }
                    }
                }
                // then the nearest free place, on a spiral round the first
                if !found {
                    let turn = SkyNoise.hash(number, salt: 31)
                    search: for ring in 1...40 {
                        for k in 0..<12 {
                            let angle = (Double(k) / 12 + turn + Double(ring) * 0.07) * (Double.pi * 2)
                            let reach = Double(ring) * field.apart * 0.6
                            let x = at.x + cos(angle) * reach, y = at.y + sin(angle) * reach * 0.9
                            if sky.free(x, y, big: big, pair: 20) {
                                spot = Spot(x: x, y: y)
                                again = rooms.count * casts + (ring - 1) * 12 + k + 1
                                found = true
                                break search
                            }
                        }
                    }
                }
                if !found { again = rooms.count * casts + 40 * 12 + 1 }
            }
            cast.append((night, spot, again))
            sky.taken.append(Taken(x: spot.x, y: spot.y, ordinary: !big, fourPoint: big))
        }

        // the order of rank: by class of light, then by strength, then by night
        let order = cast.indices.sorted { a, b in
            let la = lightRank(cast[a].night), lb = lightRank(cast[b].night)
            if la != lb { return la > lb }
            if cast[a].night.magnitude != cast[b].night.magnitude { return cast[a].night.magnitude > cast[b].night.magnitude }
            return a < b
        }
        var rank = [Int](repeating: 0, count: cast.count)
        for (place, index) in order.enumerated() { rank[index] = place + 1 }

        let scale = Double(world.starScale)
        return cast.enumerated().map { index, entry in
            let night = entry.night
            // world coordinates (rest pose): the looked-up place, turned
            // back and lowered (tonight's: its place beside the tree)
            let rest = night.kind == .tonight
                ? world.tonight
                : CGPoint(x: entry.up.x + field.turn, y: entry.up.y - field.drop)
            let m = min(1, max(0, (night.magnitude - 0.22) / 0.5))
            let radius = night.kind == .night ? min(pointCap, 0.52 + 0.95 * pow(m, 0.85)) * scale : pointCap * scale
            let reach: Double
            switch night.kind {
            case .night: reach = 0
            case .month: reach = markHalf * 0.70 * scale
            case .first: reach = markHalf * 0.86 * scale
            case .tonight: reach = markHalf * scale
            }
            return Star(night: night.number, kind: night.kind,
                        up: CGPoint(x: entry.up.x, y: entry.up.y), rest: rest,
                        magnitude: night.magnitude, warmth: night.warmth, twinkle: night.twinkle,
                        radius: CGFloat(radius), reach: CGFloat(reach), rank: rank[index], again: entry.again)
        }
    }

    /// His sky as it stands, asked about one more place: the rule every
    /// night is cast by, for a bench that wants to know why a star is where
    /// it is — and so that the rule's own distances can be tested a tenth
    /// of a point either side of each.
    struct CastSky {
        private let casting: Casting

        /// The sky in which `stars` stand, for this world and layout.
        init(_ stars: [Star], world: SkyWorld, layout: Layout) {
            var casting = Casting(field: Field(world: world, layout: layout))
            for star in stars {
                let spot = Spot(x: Double(star.up.x), y: Double(star.up.y))
                casting.taken.append(Taken(x: spot.x, y: spot.y, ordinary: star.kind == .night,
                                           fourPoint: star.kind == .month || star.kind == .first))
                if star.kind == .first, let own = casting.field.firstUp, own.x == spot.x, own.y == spot.y {
                    casting.firstAt = own
                }
            }
            self.casting = casting
        }

        /// Whether a star could take this looked-up place: in the sky and
        /// over the land, behind nothing, clear of tonight's two homes and
        /// of the first night's own place, never closer than 5.6 pt to an
        /// ordinary night (5 pt more round any other star, and for a
        /// four-point star, which also keeps 10 pt from every card's
        /// edge). `room`: what two four-point stars keep between them —
        /// 80 pt while the sky has it, then 60, then 44; on the spiral, 20.
        func isFree(_ place: CGPoint, fourPoint: Bool, room: CGFloat = 80) -> Bool {
            casting.free(Double(place.x), Double(place.y), big: fourPoint, pair: Double(room))
        }
    }

    /// The rects no star may sit behind, in looked-up points (the anchor
    /// window's x), each header rect twice — where it is looking up and
    /// where the rest pose shows that part of the sky: the avatar, name and
    /// age as one block, 7 pt of room and one em (13 pt) past the last
    /// glyph; the gear with 3 pt. On the Duo, THE LAB'S strip: the clock,
    /// island and status icons (y −10 to 192), the clock at rest, the tab
    /// capsule (y 388 to 652). On the slab: the status bar and the island
    /// (y under 64). A four-point star keeps 9 pt further from each.
    static func keepOuts(world: SkyWorld, layout: Layout) -> [Edges] {
        let ox = Double(layout.anchorX)
        let width = Double(world.anchor.width)
        let turn = Double(world.turn), drop = Double(world.drop)
        func padded(x: Double, y: Double, width w: Double, height h: Double, by p: Double) -> Edges {
            Edges(x0: x - ox - p, y0: y - p, x1: x - ox + w + p, y1: y + h + p)
        }
        func padded(_ r: CGRect, by p: Double) -> Edges {
            padded(x: Double(r.origin.x), y: Double(r.origin.y), width: Double(r.size.width), height: Double(r.size.height), by: p)
        }

        var header: [Edges] = []
        if let name = layout.name, let age = layout.age {
            // avatar, name and age are one block: no star squeezes between them
            let avatar = layout.avatar
            let x0 = min(Double(name.origin.x), Double(age.origin.x), avatar.map { Double($0.origin.x) } ?? .infinity)
            let x1 = max(Double(name.origin.x) + Double(name.size.width), Double(age.origin.x) + Double(age.size.width))
            let y0 = min(Double(name.origin.y), avatar.map { Double($0.origin.y) } ?? .infinity)
            let y1 = max(Double(age.origin.y) + Double(age.size.height) + 10,
                         avatar.map { Double($0.origin.y) + Double($0.size.height) } ?? 0)
            // (one em of clear sky past the last glyph)
            header.append(padded(x: x0, y: y0, width: x1 - x0 + 13, height: y1 - y0, by: 7))
        } else if let avatar = layout.avatar {
            header.append(padded(avatar, by: 2))
        }
        if let gear = layout.gear { header.append(padded(gear, by: 3)) }

        var outs: [Edges] = []
        for r in header {
            outs.append(r)                                                                          // looking up
            outs.append(Edges(x0: r.x0 - turn, y0: r.y0 + drop, x1: r.x1 - turn, y1: r.y1 + drop))  // at rest
        }
        switch world.kind {
        case .duo:
            // the strip's own column
            let column = stripWindow(world: world, layout: layout) + 20 - ox
            outs.append(Edges(x0: column - 2, y0: -10, x1: width + 4, y1: 192))                      // clock, island, status icons
            outs.append(Edges(x0: column + 8 - turn, y0: 14 + drop, x1: width + 4 - turn, y1: 44 + drop))   // …and, at rest, the clock
            outs.append(Edges(x0: column + 4, y0: 388, x1: width + 4, y1: 652))                      // the tab capsule
        case .slab:
            outs.append(Edges(x0: -10, y0: -10, x1: width + 10, y1: 64))                             // the status bar and the island
        }
        return outs
    }

    /// The lowest a star may sit at looked-up x, in looked-up points: 8 pt
    /// clear of the land's skyline, 5 pt clear of the tree's crown, and
    /// never within 12 pt of the horizon.
    static func floor(at x: Double, world: SkyWorld) -> Double {
        Ground(world: world).floor(x)
    }

    // MARK: The leading page's ordinary sky

    /// A star of the leading page's sky: nobody's.
    struct PageStar: Equatable {
        /// An ordinary star's colour: two in five cool, one in ten warm.
        enum Tint: String, Equatable {
            case cool, plain, warm
        }

        /// World x (left of the fold: under `turn`, and negative past the
        /// anchor window's leading edge at rest) and rest-pose y.
        /// Looking up it is `turn` to the left and `drop` lower, like his.
        let place: CGPoint
        /// 0 the faintest … 1: most are faint, a few are bright.
        let brightness: Double
        /// Its radius in points (none larger than the largest of his)…
        let radius: CGFloat
        /// …and its strength, both a little less toward the far edge.
        let strength: Double
        /// Its colour in the dark print.
        let tint: Tint
        /// Its slow swell: 3 – 7 s, two in five of them steady.
        let twinkle: Twinkle
    }

    /// The ordinary sky of the open Duo's leading page — nobody's stars, on
    /// the whole tall sky: fainter than his, as thick as his at the fold (so
    /// that, looking up, there is no boundary where the anchor window
    /// begins) and thinning and dimming to the far left. It fills as his
    /// does — by his nights, tonight's among them whether its star is lit
    /// or not: a newborn's sky is not upstaged by the page beside it — from
    /// 80 to 460 stars. None behind the page's title at rest. Empty where
    /// there is no leading page (`layout.anchorX` 0).
    static func ordinarySky(nights: Int, world: SkyWorld, layout: Layout) -> [PageStar] {
        let ox = Double(layout.anchorX)
        guard ox > 0 else { return [] }
        let skyline = Skyline.of(world.kind)
        let turn = Double(world.turn), drop = Double(world.drop), width = Double(world.anchor.width)
        // from the fold (looking up) to the leading edge
        let span = ox + turn - 2
        let count = Int(min(460, max(80, SkyMath.round(1.12 * Double(max(1, nights)) * (span / width) * 0.84))))
        let crowding = 0.36, fall = 190.0
        // (20 pt of plain sky before the title's first letter: a star 15 pt
        // left of "T" read as a mark on the title)
        var title: Edges?
        if let t = layout.title {
            let sub = layout.subtitle
            let widest = max(Double(t.size.width), sub.map { Double($0.size.width) } ?? 0)
            let foot = sub.map { Double($0.origin.y) + Double($0.size.height) } ?? (Double(t.origin.y) + Double(t.size.height))
            title = Edges(x0: Double(t.origin.x) - ox - 20, y0: Double(t.origin.y) - 8,
                          x1: Double(t.origin.x) - ox + widest + 22, y1: foot + 8)
        }
        var stars: [PageStar] = []
        for n in 0..<count {
            // how far left of the fold: a third of them crowd toward it, the rest lie evenly
            let u = SkyNoise.hash(n, salt: 41)
            let left = SkyNoise.hash(n, salt: 47) < crowding
                ? -fall * log(1 - u * (1 - exp(-span / fall)))
                : u * span
            let x = turn - 2 - left                      // world x (the fold, looking up, is at `turn`)
            let sky = skyline.top(at: x) + drop - 14     // the looked-up sky's foot there
            // a few more low in the sky, where the everyday view shows them
            let v = SkyNoise.hash(n, salt: 42)
            let y = SkyNoise.hash(n, salt: 48) < 0.09 ? drop + 5 + v * 96 : 6 + pow(v, 0.95) * (sky - 6)
            if let t = title, x > t.x0, x < t.x1, y - drop > t.y0, y - drop < t.y1 { continue }
            let near = exp(-left / 300)                  // 1 at the fold … 0.15 at the far edge
            let m = pow(SkyNoise.hash(n, salt: 43), 2.2)
            let roll = SkyNoise.hash(n, salt: 49)
            stars.append(PageStar(
                place: CGPoint(x: x, y: y - drop),
                brightness: m,
                radius: CGFloat((0.5 + 0.72 * m) * (0.86 + 0.14 * near)),
                strength: (0.46 + 0.5 * m) * (0.6 + 0.4 * near),
                tint: roll < 0.42 ? .cool : roll < 0.9 ? .plain : .warm,
                twinkle: Twinkle(period: 3 + 4 * SkyNoise.hash(n, salt: 46),
                                 phase: SkyNoise.hash(n, salt: 45),
                                 steady: SkyNoise.hash(n, salt: 44) > 0.6)))
        }
        return stars
    }

    // MARK: Private

    /// The plastic number: its powers step a point across a square so that
    /// each new one lands in the widest gap the earlier ones left.
    private static let plastic = 1.32471795724474602596
    private static let castAcross = 1 / plastic
    private static let castDown = 1 / (plastic * plastic)

    /// An ordinary night's point is capped at this radius.
    private static let pointCap = 1.15
    /// Half the four-point sprite's box at full size.
    private static let markHalf = 14.0

    private static func fraction(_ value: Double) -> Double {
        value - value.rounded(.down)
    }

    private static func lightRank(_ night: Night) -> Int {
        switch night.kind {
        case .tonight: return 3
        case .first: return 2
        case .month: return 1
        case .night: return 0
        }
    }

    /// Display x where the strip's window begins.
    private static func stripWindow(world: SkyWorld, layout: Layout) -> Double {
        if let told = layout.stripWindow { return Double(told) }
        return Double(layout.anchorX) + Double(world.labStripWindow ?? world.anchor.width)
    }

    /// A place in the looked-up sky.
    private struct Spot {
        let x: Double
        let y: Double
    }

    /// A place a night has taken, and what stands there.
    private struct Taken {
        let x: Double
        let y: Double
        /// An ordinary night's (never closer than 5.6 pt; anything else, 5 pt more).
        let ordinary: Bool
        /// The first night's or a month-night's (two of them are not neighbours).
        let fourPoint: Bool
    }

    /// The sky as far as it has been cast: the places taken, in order.
    private struct Casting {
        let field: Field
        var taken: [Taken] = []
        /// The first night's own place, once it has taken it.
        var firstAt: Spot?

        /// A place is free: in the sky, behind nothing, with the room its
        /// kind keeps from tonight's star, the first night's and every
        /// night before it. `pair`: the room between two four-point stars.
        func free(_ x: Double, _ y: Double, big: Bool, pair: Double = 80) -> Bool {
            if x < field.xMin || x > field.xMax || y < field.yMin || y > field.floor(x) { return false }
            // (a four-point star keeps further from the words and the
            // buttons: beside a line of text it is an asterisk)
            let wide: Double = big ? 9 : 0
            for r in field.keepOuts where x > r.x0 - wide && x < r.x1 + wide && y > r.y0 - wide && y < r.y1 + wide {
                return false
            }
            if big && field.atCardEdge(x, y) { return false }
            // tonight's star has dark sky of its own round it in the clear
            // window (and no four-point star near enough to be taken for
            // it); beside the tree, at rest, a smaller clearing
            if SkyMath.hypot(x - field.tonightUp.x, y - field.tonightUp.y) < (big ? 70 : 30 * field.starScale) { return false }
            if SkyMath.hypot(x - field.tonightRest.x, y - field.tonightRest.y) < 17 { return false }
            // …and so has the first night's, where it has a place of its own
            if let first = firstAt, SkyMath.hypot(x - first.x, y - first.y) < (big ? 60 : 18) { return false }
            for other in taken {
                let gap = big && other.fourPoint
                    ? pair
                    : (other.ordinary ? field.apart : field.apart + 5) + (big ? 5 : 0)
                if abs(x - other.x) < gap && SkyMath.hypot(x - other.x, y - other.y) < gap { return false }
            }
            return true
        }
    }

    /// What his stars stand over, looking up: the land's skyline and the
    /// tree, lowered and turned with the view.
    private struct Ground {
        let skyline: Skyline
        let turn: Double
        let drop: Double
        /// The tree's foot, looking up, and how tall it stands.
        let treeUp: Spot
        let treeHeight: Double
        /// 12 pt over the looked-up horizon: no star lower, whatever the land.
        let lowest: Double

        init(world: SkyWorld) {
            skyline = Skyline.of(world.kind)
            turn = Double(world.turn)
            drop = Double(world.drop)
            let treeX = Double(world.tree.x)
            treeUp = Spot(x: treeX - turn, y: skyline.treeFoot(at: treeX) + drop)
            treeHeight = Double(world.tree.height)
            lowest = Double(world.horizon) + drop - 12
        }

        /// The lowest a star may sit at looked-up x: clear of the land's
        /// skyline and of the tree's crown.
        func floor(_ x: Double) -> Double {
            var bottom = skyline.top(at: x + turn) + drop - 8
            if let top = Skyline.crownTop(at: (x - treeUp.x) / treeHeight) {
                bottom = min(bottom, treeUp.y + top * treeHeight - 5)
            }
            return min(bottom, lowest)
        }
    }

    /// The looked-up sky as his stars are laid out in it: the boxes and
    /// their shares, the floor, what is kept clear.
    private struct Field {
        struct Box {
            let x0: Double
            let x1: Double
            let y0: Double
            let y1: Double
            /// Its share of his stars: area × density.
            let weight: Double
            let columns: [(x0: Double, x1: Double, weight: Double)]
        }

        let ground: Ground
        let xMin: Double
        let xMax: Double
        let yMin: Double
        let width: Double
        let turn: Double
        let drop: Double
        let starScale: Double
        /// Never closer than this (on the light page two stars' soft
        /// patches would run together).
        let apart: Double
        /// How far the slow drift carries a place, at the most.
        let knots: Double
        let boxes: [Box]
        let boxTotal: Double
        let keepOuts: [Edges]
        let cardEdges: [Edges]
        /// Tonight's star: its place looking up, and where it is at rest,
        /// both in looked-up points.
        let tonightUp: Spot
        let tonightRest: Spot
        let firstUp: Spot?

        init(world: SkyWorld, layout: Layout) {
            ground = Ground(world: world)
            xMin = Double(world.starInset)
            width = Double(world.anchor.width)
            xMax = width - Double(world.starInset)
            yMin = Double(world.starTop)
            turn = Double(world.turn)
            drop = Double(world.drop)
            starScale = Double(world.starScale)
            apart = max(5.6 * Double(world.starScale), 5.6)
            knots = world.kind == .duo ? 30 : 26

            let strip = StarChart.stripWindow(world: world, layout: layout) - Double(layout.anchorX)
            var total = 0.0
            boxes = world.starBoxes(stripWindow: CGFloat(strip)).map { box in
                let x0 = Double(box.x0), x1 = Double(box.x1), y0 = Double(box.y0), y1 = Double(box.y1)
                let weight = (x1 - x0) * (y1 - y0) * box.density
                total += weight
                let columns = box.columns.isEmpty
                    ? [(x0: x0, x1: x1, weight: 1.0)]
                    : box.columns.map { (x0: Double($0.x0), x1: Double($0.x1), weight: $0.weight) }
                return Box(x0: x0, x1: x1, y0: y0, y1: y1, weight: weight, columns: columns)
            }
            boxTotal = total
            keepOuts = StarChart.keepOuts(world: world, layout: layout)

            // A FOUR-POINT STAR IS NEVER AT A CARD'S EDGE: every card of the
            // standing layouts and, for the Today card, the rest pose (its
            // edges there are the header band's foot and the strip's side).
            // (the layout's are in display points; the world's own table is
            // already in the anchor window's x)
            let shift = layout.cards == nil ? 0 : Double(layout.anchorX)
            let cards = (layout.cards ?? world.labCards).map {
                Edges(x0: Double($0.origin.x) - shift, y0: Double($0.origin.y),
                      x1: Double($0.origin.x) - shift + Double($0.size.width), y1: Double($0.origin.y) + Double($0.size.height))
            }
            let turn = self.turn, drop = self.drop
            cardEdges = cards + cards.prefix(1).map {
                Edges(x0: $0.x0 - turn, y0: $0.y0 + drop, x1: $0.x1 - turn, y1: $0.y1 + drop)
            }

            tonightUp = Spot(x: Double(world.tonightUp.x), y: Double(world.tonightUp.y))
            tonightRest = Spot(x: Double(world.tonight.x) - turn, y: Double(world.tonight.y) + drop)
            firstUp = world.firstNightUp.map { Spot(x: Double($0.x), y: Double($0.y)) }
        }

        func floor(_ x: Double) -> Double {
            ground.floor(x)
        }

        /// Where a cast (u across, v down) lands: v picks the box and the
        /// height in it, u the x through the box's weighted columns; then
        /// the slow drift that gathers the sky into loose knots — a smooth
        /// drift of every place, the same for every night.
        func place(u: Double, v: Double) -> Spot {
            var box = boxes[boxes.count - 1]
            var down = v
            var passed = 0.0
            for candidate in boxes {
                let share = candidate.weight / boxTotal
                if v < passed + share {
                    box = candidate
                    down = (v - passed) / share
                    break
                }
                passed += share
            }
            var total = 0.0
            for column in box.columns { total += (column.x1 - column.x0) * column.weight }
            var x = box.x1
            var across = 0.0
            for column in box.columns {
                let part = ((column.x1 - column.x0) * column.weight) / total
                if u <= across + part {
                    x = column.x0 + ((u - across) / part) * (column.x1 - column.x0)
                    break
                }
                across += part
            }
            let lowest = floor(x)
            let foot = min(box.y1, lowest)
            let y = box.y0 + down * max(4, foot - box.y0)
            let wx = (SkyNoise.drift(x / 150 + 3.7, y / 150 + 1.3, octaves: 2) - 0.5) * 2
            let wy = (SkyNoise.drift(x / 150 + 9.1, y / 150 + 6.6, octaves: 2) - 0.5) * 2
            return Spot(x: min(xMax - 1, max(xMin + 1, x + wx * knots)),
                        y: max(yMin + 1, min(y + wy * knots, lowest - 1)))
        }

        /// A four-point star here would be at a card's edge, or cut by the
        /// display's own (in either pose: at 13 pt tall a mark 5 pt under
        /// the top of the everyday view lost the tip of its upper ray).
        func atCardEdge(_ x: Double, _ y: Double) -> Bool {
            if x < xMin + 2 || x > xMax - 2 || y < yMin + 2 { return true }
            if abs(y - drop) < 9 || (y > drop - 9 && abs(x + turn - width) < 7) { return true }
            for card in cardEdges {
                let inside = min(x - card.x0, card.x1 - x, y - card.y0, card.y1 - y)
                let distance = inside >= 0
                    ? inside
                    : SkyMath.hypot(max(card.x0 - x, 0, x - card.x1), max(card.y0 - y, 0, y - card.y1))
                if distance < 10 { return true }
            }
            return false
        }
    }
}

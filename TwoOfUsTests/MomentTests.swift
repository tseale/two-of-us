import XCTest
@testable import TwoOfUs

/// The bedtime moment and the quiet events (`Moment`) against the sky lab's
/// own curves, sampled every 0.05 s from 0 to 10 s on the cover, the spread
/// and the slab, in full and under Reduce Motion
/// (`SkyCoreFixturesMoment.bedtime`, `.quiet` and `.table`, exported by
/// `design/sky-lab/tools/swift-fixtures/moment.mjs`), and against the rules
/// the design states for it (design/sky-lab/BRIEF.md, round three).
final class MomentTests: XCTestCase {
    // (Read once for the class: XCTest makes an instance for every test,
    // and each would otherwise parse six thousand rows of its own.)
    private static let bedtimeTable = SkyCoreFixture.Table(SkyCoreFixturesMoment.bedtime)
    private static let quietTable = SkyCoreFixture.Table(SkyCoreFixturesMoment.quiet)
    private static let tableRecords = SkyCoreFixture.records(SkyCoreFixturesMoment.table)
    private var bedtime: SkyCoreFixture.Table { Self.bedtimeTable }
    private var quiet: SkyCoreFixture.Table { Self.quietTable }
    private var table: [String: [String]] { Self.tableRecords }

    private let displays: [(name: String, display: SkyWorld.Display)] =
        [("cover", .cover), ("spread", .spread), ("slab", .slab)]
    private let worlds: [SkyWorld.Kind] = [.duo, .slab]

    private func lab(_ key: String, file: StaticString = #filePath, line: UInt = #line) -> [Double] {
        guard let values = table[key] else {
            XCTFail("the lab exports no \(key)", file: file, line: line)
            return []
        }
        return values.map { Double($0) ?? .nan }
    }

    private func span(_ range: ClosedRange<TimeInterval>) -> [Double] {
        [range.lowerBound, range.upperBound]
    }

    /// Every sample of an age grid from `from` to `to`, a thousandth apart.
    private func ages(_ from: Double, _ to: Double) -> [Double] {
        stride(from: Int((from * 1000).rounded()), through: Int((to * 1000).rounded()), by: 1).map { Double($0) / 1000 }
    }

    // MARK: The lab's curves

    func testTheMomentFollowsTheLabsTable() {
        var compared = 0
        for (name, display) in displays {
            for (motion, reduced) in [("full", false), ("reduced", true)] {
                let rows = bedtime.rows(where: ["display": name, "motion": motion])
                XCTAssertEqual(rows.count, 201, "\(name) \(motion): every 0.05 s from 0 to 10 s")
                for row in rows {
                    let age = bedtime.number(row, "age")
                    let at = "\(name) \(motion) at \(age) s"
                    let frame = Moment.frame(age: age, world: display.kind, reduced: reduced)
                    XCTAssertEqual(frame.cards, bedtime.number(row, "cards"), accuracy: 1e-6, "cards, \(at)")
                    XCTAssertEqual(frame.look, bedtime.number(row, "look"), accuracy: 1e-6, "look, \(at)")
                    XCTAssertEqual(frame.star, bedtime.number(row, "star"), accuracy: 1e-6, "star, \(at)")
                    XCTAssertEqual(frame.caption, bedtime.number(row, "caption"), accuracy: 1e-6, "caption, \(at)")
                    XCTAssertEqual(Double(frame.band?.radius ?? 0), bedtime.number(row, "bandRadius"), accuracy: 1e-5,
                                   "the band's radius, \(at)")
                    XCTAssertEqual(frame.band?.strength ?? 0, bedtime.number(row, "bandStrength"), accuracy: 1e-6,
                                   "the band's strength, \(at)")
                    XCTAssertEqual(frame.band?.light ?? 0, bedtime.number(row, "bandLight"), accuracy: 1e-6,
                                   "the band's own light, \(at)")
                    XCTAssertEqual(frame.depth, bedtime.number(row, "depth"), accuracy: 1e-6, "depth, \(at)")
                    XCTAssertEqual(frame.starsKept, bedtime.number(row, "kept"), accuracy: 1e-6, "kept, \(at)")
                    compared += 1
                }
            }
        }
        XCTAssertEqual(compared, 1206)
        XCTAssertEqual(compared, bedtime.rows.count, "a row of the lab's the test did not read")
    }

    func testTheBeatsAreTheLabs() {
        var read: Set<String> = []
        func check(_ actual: [Double], _ key: String, accuracy: Double = 1e-9,
                   file: StaticString = #filePath, line: UInt = #line) {
            read.insert(key)
            let want = lab(key, file: file, line: line)
            XCTAssertEqual(actual.count, want.count, key, file: file, line: line)
            for (got, expected) in zip(actual, want) {
                XCTAssertEqual(got, expected, accuracy: accuracy, key, file: file, line: line)
            }
        }
        for kind in worlds {
            let beats = Moment.beats(world: kind)
            let k = kind.rawValue
            check(span(beats.fall), "fall")
            check(span(beats.rise), "rise.\(k)")
            check([beats.bandLeaves ?? .nan, beats.bandCrosses ?? .nan], "band.\(k)")
            check(span(beats.captionIn), "caption.in")
            check(span(beats.captionOut), "caption.out")
            check(span(beats.back), "back")

            let still = Moment.beats(world: kind, reduced: true)
            check(span(still.fall), "reduced.fall")
            check(span(still.rise), "reduced.dissolve")
            check(span(still.captionIn), "reduced.caption.in")
            check(span(still.captionOut), "reduced.caption.out")
            check(span(still.back), "reduced.back")
            XCTAssertNil(still.bandLeaves, "Reduce Motion has no band")
            XCTAssertNil(still.bandCrosses)

            // The band crosses the anchor window to its farthest corner, at the lab's pace.
            let reach = Moment.bandReach(world: .world(kind))
            check([reach], "band.\(k).reach", accuracy: 1e-6)
            check([reach / (beats.bandCrosses ?? .nan)], "band.\(k).speed", accuracy: 1e-6)

            // The anchors the lab's own curves give (the design's are below).
            check([Moment.whole(world: kind)], "anchor.whole")
            check([Moment.whole(world: kind, reduced: true)], "anchor.wholeReduced")
            check([beats.rise.upperBound], "anchor.up.\(k)")
            check([peakPace(kind)], "anchor.peak.\(k)", accuracy: 0.01)
            // …and the last millisecond his stars answer the band, with the
            // strength they answer by there.
            let last = lastAnswerToTheBand(kind)
            check([last.age, last.strength], "anchor.bandAnswers.\(k)", accuracy: 1e-6)
        }
        check([SkyEvent.dissolveDuration], "quiet.dissolve")
        check([SleepKind.night.depth], "depth.night")
        check([SleepKind.nap.depth], "depth.nap")
        check([firstAgeTheCardsAreUnderATwentieth(.duo)], "anchor.cardsUnderATwentieth")
        XCTAssertEqual(Set(table.keys).subtracting(read).sorted(), [], "records of the lab's table no test reads")
    }

    /// The rise's steepest millisecond, in points a second of the sky's travel.
    private func peakPace(_ kind: SkyWorld.Kind) -> Double {
        let drop = Double(SkyWorld.world(kind).drop)
        var most = 0.0
        for index in 0..<4000 {
            let a = Moment.frame(age: Double(index) / 1000, world: kind).look
            let b = Moment.frame(age: Double(index + 1) / 1000, world: kind).look
            most = max(most, (b - a) * 1000)
        }
        return most * drop
    }

    /// The last millisecond at which his stars still answer the band, and
    /// how strongly.
    private func lastAnswerToTheBand(_ kind: SkyWorld.Kind) -> (age: Double, strength: Double) {
        var last = (age: Double.nan, strength: 0.0)
        for millisecond in 0...8000 {
            let age = Double(millisecond) / 1000
            if let band = Moment.frame(age: age, world: kind).band, band.strength > 0 { last = (age, band.strength) }
        }
        return last
    }

    private func firstAgeTheCardsAreUnderATwentieth(_ kind: SkyWorld.Kind) -> Double {
        for hundredth in 0...1000 {
            let age = Double(hundredth) / 100
            if 1 - Moment.frame(age: age, world: kind).cards < 0.05 { return age }
        }
        return .nan
    }

    // MARK: The design's anchors

    func testTheCardsAreUnderFivePercentAtPoint87Seconds() {
        for kind in worlds {
            XCTAssertLessThan(1 - Moment.frame(age: 0.87, world: kind).cards, 0.05)
            XCTAssertGreaterThanOrEqual(1 - Moment.frame(age: 0.86, world: kind).cards, 0.05)
            XCTAssertEqual(firstAgeTheCardsAreUnderATwentieth(kind), 0.87)
            // They fall back in about a second, and are wholly away until the caption has gone.
            for age in ages(1.0, 4.6) {
                XCTAssertEqual(Moment.frame(age: age, world: kind).cards, 1, "at \(age) s")
            }
        }
    }

    func testTheWholeIsFivePointEightSeconds() {
        for kind in worlds {
            XCTAssertEqual(Moment.whole(world: kind), 5.8)
            XCTAssertLessThan(Moment.whole(world: kind), 6, "the whole is under 6 s")
            XCTAssertGreaterThan(Moment.frame(age: 5.79, world: kind).cards, 0)
            XCTAssertEqual(Moment.frame(age: 5.8, world: kind).cards, 0)
            XCTAssertEqual(Moment.frame(age: 7, world: kind).cards, 0)
            // The cards return in about 1.2 s with an ease-out: quick away
            // and soft to rest — half back at a third of the time.
            XCTAssertEqual(Moment.frame(age: 4.6 + 1.2 * 0.34, world: kind).cards, 0.5, accuracy: 0.02)
        }
        XCTAssertEqual(Moment.whole(world: .duo, reduced: true), 4.0, "Reduce Motion: about 4 s")
    }

    func testTheViewIsUpByTwoPointFourSecondsOnTheDuoAndTwoPointSevenOnTheSlab() {
        for (kind, up) in [(SkyWorld.Kind.duo, 2.4), (.slab, 2.7)] {
            XCTAssertEqual(Moment.frame(age: 0.3, world: kind).look, 0, "0 until 0.3 s")
            XCTAssertGreaterThan(Moment.frame(age: 0.4, world: kind).look, 0)
            XCTAssertLessThan(Moment.frame(age: up - 0.05, world: kind).look, 1)
            XCTAssertEqual(Moment.frame(age: up, world: kind).look, 1)
            // …and it stays: there is no way back down inside the moment.
            for age in ages(up, 10) where Int((age * 1000).rounded()) % 50 == 0 {
                XCTAssertEqual(Moment.frame(age: age, world: kind).look, 1, "at \(age) s")
            }
        }
        // The slab's sky is twice as tall, so its rise is 0.3 s longer: at
        // its peak 492 pt/s, not 563 (the Duo's: 279) — under about 500.
        XCTAssertEqual(peakPace(.duo), 279, accuracy: 1)
        XCTAssertEqual(peakPace(.slab), 492, accuracy: 1)
        XCTAssertLessThan(peakPace(.slab), 500)
    }

    func testTheViewOnlyEverRises() {
        for kind in worlds {
            for reduced in [false, true] {
                var last = 0.0
                for age in ages(0, 6) {
                    let look = Moment.frame(age: age, world: kind, reduced: reduced).look
                    XCTAssertGreaterThanOrEqual(look, last, "at \(age) s")
                    XCTAssertTrue(look >= 0 && look <= 1)
                    last = look
                }
                XCTAssertEqual(last, 1)
            }
        }
    }

    func testTheCaptionHasGoneBeforeACardIsBackAndTheBandHasCrossedBeforeThat() {
        for kind in worlds {
            let beats = Moment.beats(world: kind)
            // In by 2.8 s, as the view comes to rest; gone at 4.6 s.
            XCTAssertEqual(Moment.frame(age: 2.0, world: kind).caption, 0)
            XCTAssertEqual(Moment.frame(age: 2.8, world: kind).caption, 1, accuracy: 1e-9, "in by 2.8 s")
            XCTAssertEqual(Moment.frame(age: 3.5, world: kind).caption, 1, accuracy: 1e-9)
            XCTAssertEqual(Moment.frame(age: 4.6, world: kind).caption, 0)
            for age in ages(4.6, 6) {
                XCTAssertEqual(Moment.frame(age: age, world: kind).caption, 0, "read through a returning card at \(age) s")
            }
            XCTAssertLessThanOrEqual(beats.captionOut.upperBound, beats.back.lowerBound)
            // It is lit only while the cards are wholly away, in full and
            // under Reduce Motion, and it comes in over the last of the rise:
            // nothing of it until the view is three fifths of the way up.
            for reduced in [false, true] {
                for age in ages(0, 6) {
                    let frame = Moment.frame(age: age, world: kind, reduced: reduced)
                    if frame.caption > 0 {
                        XCTAssertEqual(frame.cards, 1, "the caption over a card at \(age) s")
                        XCTAssertGreaterThan(frame.look, 0.6, "the caption before the view is up, at \(age) s")
                    }
                }
            }
            // The band leaves as the view arrives and has crossed before the caption goes.
            guard let leaves = beats.bandLeaves, let crosses = beats.bandCrosses else {
                return XCTFail("the full moment has a band")
            }
            let crossed = leaves + crosses
            XCTAssertLessThan(crossed, beats.captionOut.upperBound)
            XCTAssertNil(Moment.frame(age: leaves, world: kind).band, "it has not left yet")
            // …from the star's place in the clear window, which the star is
            // then within a few points of.
            let world = SkyWorld.world(kind)
            let star = SkyCamera.tonightHome(look: Moment.frame(age: leaves, world: kind).look, world: world)
            let short = hypot(Double(star.x - world.tonightUp.x), Double(star.y - world.tonightUp.y))
            XCTAssertLessThan(short, 3, "the star is still \(short) pt from its window as the band leaves")
            let reach = Moment.bandReach(world: .world(kind))
            XCTAssertEqual(Double(Moment.frame(age: crossed, world: kind).band?.radius ?? 0), reach, accuracy: 1e-6)
            // Its own light has gone at nine tenths of the way; nothing of it
            // is left, and no star answers, once the cards begin to return.
            let late = Moment.frame(age: leaves + 0.9 * crosses, world: kind).band
            XCTAssertEqual(late?.light ?? .nan, 0, accuracy: 1e-9)
            XCTAssertGreaterThan(late?.strength ?? 0, 0.99, "the stars answer all the way across")
            XCTAssertEqual(Moment.frame(age: 5.0, world: kind).band?.strength, 0)
            XCTAssertEqual(Moment.frame(age: 5.0, world: kind).band?.light, 0)
        }
    }

    func testHisStarsStopAnsweringTheBandAllAtOnce() {
        // "`strength` is 0 once it has crossed": the answers do not trail
        // away into thousandths of themselves — under three thousandths the
        // band is out, between one frame and the next. The lab's samples,
        // 0.05 s apart, step over that instant; so the lab was also asked,
        // millisecond by millisecond, for the last at which a star answers
        // (4.812 s on the Duo, 4.883 s on a slab) and its strength there.
        for kind in worlds {
            let last = lab("anchor.bandAnswers.\(kind.rawValue)")
            guard last.count == 2 else { return XCTFail("the lab's last answer to the band") }
            XCTAssertGreaterThan(last[1], 0.003, "the lab's last answer is not a trace")
            XCTAssertEqual(Moment.frame(age: last[0], world: kind).band?.strength ?? 0, last[1], accuracy: 1e-6)
            let next = Moment.frame(age: last[0] + 0.001, world: kind).band
            XCTAssertNotNil(next, "the band's radius runs on")
            XCTAssertEqual(next?.strength, 0, "a trace of an answer after the lab's last")
            XCTAssertEqual(next?.light, 0)
        }
    }

    func testTheCaptionIsNeverReadThroughAReturningCard() {
        // The line's own rule. In the moment's table the cards are wholly
        // away for as long as the line is lit, so no sample of the timeline
        // shows what a card does to it: the lab's rule (drawCaption) was
        // asked OFF the table — cards part-way back, the view part-way up,
        // an opacity past 1.
        let rule = SkyCoreFixture.Table(SkyCoreFixturesMoment.captionRule)
        XCTAssertEqual(rule.rows.count, 12 * 7 * 4, "twelve fades of the cards, seven looks, four ages")
        var bitten = 0
        for row in rule.rows {
            let cards = rule.number(row, "cards"), look = rule.number(row, "look"), lit = rule.number(row, "lit")
            let shown = Moment.caption(cards: cards, lit: lit, look: look)
            XCTAssertEqual(shown, rule.number(row, "caption"), accuracy: 1e-6, "cards \(cards), look \(look), lit \(lit)")
            if shown > 0 && shown < lit - 1e-6 { bitten += 1 }
        }
        XCTAssertGreaterThan(bitten, 100, "the lab was asked where the rule bites")
        // By the cards' fade SQUARED: behind a card half back the line is a
        // quarter of itself, not a half…
        XCTAssertEqual(Moment.caption(cards: 0.5, lit: 1, look: 1), 0.25, accuracy: 1e-12)
        // …there is nothing of it until a card is more than a hundredth gone…
        XCTAssertEqual(Moment.caption(cards: 0.01, lit: 1, look: 1), 0)
        XCTAssertGreaterThan(Moment.caption(cards: 0.011, lit: 1, look: 1), 0)
        // …it is never more than its own beat, whatever a card's opacity is said to be…
        XCTAssertEqual(Moment.caption(cards: 1.2, lit: 0.8, look: 1), 0.8, accuracy: 1e-12)
        // …and it comes in over the last two fifths of the rise.
        XCTAssertEqual(Moment.caption(cards: 1, lit: 1, look: 0.6), 0)
        XCTAssertEqual(Moment.caption(cards: 1, lit: 1, look: 0.8), 0.5, accuracy: 1e-12)
        XCTAssertEqual(Moment.caption(cards: 1, lit: 1, look: 1), 1)
    }

    func testTheCaptionComesInOverTheLastOfTheRise() {
        // The caption's own beat is the same on every display (in over
        // 2.0 – 2.8 s), but it is shown by the view: while the view is still
        // on its way the line is fainter than its beat — a little on the Duo,
        // more on a slab, whose rise is 0.3 s longer. In the lab the two
        // columns part only while the view rises.
        let duo = Moment.frame(age: 2.3, world: .duo), slab = Moment.frame(age: 2.3, world: .slab)
        XCTAssertGreaterThan(duo.look, slab.look)
        XCTAssertGreaterThan(duo.caption, slab.caption)
        XCTAssertGreaterThan(slab.caption, 0)
        var parted: [String: Int] = [:]
        for row in bedtime.rows(where: ["motion": "full"]) {
            let shown = bedtime.number(row, "caption"), lit = bedtime.number(row, "captionLit")
            XCTAssertLessThanOrEqual(shown, lit + 1e-9)
            if abs(shown - lit) > 1e-6 {
                let slab = bedtime.text(row, "display") == "slab"
                XCTAssertLessThan(bedtime.number(row, "age"), slab ? 2.7 : 2.4, "the view is up: the line is its beat")
                parted[bedtime.text(row, "display"), default: 0] += 1
            }
        }
        XCTAssertEqual(parted["cover"], parted["spread"])
        XCTAssertGreaterThan(parted["slab"] ?? 0, parted["cover"] ?? 0, "longer on a slab")
        XCTAssertGreaterThan(parted["cover"] ?? 0, 0)
    }

    func testTheBandIsNeverACircleRoundTheStar() {
        // Its light is held until the crest is 150 pt out — wider than the
        // strip's window — and is fullest about two fifths of the way across.
        for kind in worlds {
            let reach = Moment.bandReach(world: .world(kind))
            var fullest = (light: 0.0, radius: 0.0)
            for age in ages(2.0, 5.0) {
                guard let band = Moment.frame(age: age, world: kind).band else { continue }
                if band.radius <= 150 { XCTAssertEqual(band.light, 0, "a ring round the star at \(age) s") }
                if band.light > fullest.light { fullest = (band.light, Double(band.radius)) }
                XCTAssertTrue(band.light >= 0 && band.light <= 1 && band.strength >= 0 && band.strength <= 1)
            }
            XCTAssertEqual(fullest.light, 1, accuracy: 1e-6)
            XCTAssertEqual(fullest.radius / reach, 0.43, accuracy: 0.02)
        }
        // The Duo's crosses at 276 pt/s, the slab's at 410.
        XCTAssertEqual(Moment.bandReach(world: .duo) / 2.1, 276, accuracy: 0.5)
        XCTAssertEqual(Moment.bandReach(world: .slab) / 2.0, 410, accuracy: 0.5)
    }

    func testTonightsStarIsLitFromTheFirstInstantAndFlares() {
        for kind in worlds {
            XCTAssertEqual(Moment.frame(age: 0, world: kind).star, 0, "unlit before the tap")
            XCTAssertGreaterThan(Moment.frame(age: 0.05, world: kind).star, 0, "lit from the first instant")
            // A spark that swells past full and settles: the flare at 1.5 s.
            let samples = ages(0, 6).map { Moment.frame(age: $0, world: kind).star }
            let peak = samples.max() ?? 0
            XCTAssertGreaterThan(peak, 1.25)
            XCTAssertLessThanOrEqual(peak, 1.35)
            XCTAssertGreaterThan(Moment.frame(age: 1.5, world: kind).star, 1.28)
            XCTAssertEqual(Moment.frame(age: 4.6, world: kind).star, 1, accuracy: 0.001, "itself by the cards' return")
            XCTAssertEqual(Moment.frame(age: 40, world: kind).star, 1, accuracy: 1e-12)
        }
    }

    func testTheRoomDimsAfterTheCardsHaveGone() {
        for kind in worlds {
            XCTAssertEqual(Moment.frame(age: 1.2, world: kind).depth, 0)
            XCTAssertGreaterThan(Moment.frame(age: 1.3, world: kind).depth, 0)
            XCTAssertLessThan(Moment.frame(age: 5.8, world: kind).depth, 1, "it goes on dimming after the cards are back")
            XCTAssertEqual(Moment.frame(age: 9, world: kind).depth, 1)
            var last = 0.0
            for age in ages(0, 10) where Int((age * 1000).rounded()) % 10 == 0 {
                let depth = Moment.frame(age: age, world: kind).depth
                XCTAssertGreaterThanOrEqual(depth, last, "the room never brightens as he goes down")
                last = depth
            }
        }
    }

    func testNoJoinJumps() {
        // The first frame of the moment is the evening as it stood, and its
        // last frame is the standing night.
        for kind in worlds {
            for reduced in [false, true] {
                let first = Moment.frame(age: 0, world: kind, reduced: reduced)
                XCTAssertEqual(first.cards, 0)
                XCTAssertEqual(first.look, 0)
                XCTAssertNil(first.band)
                XCTAssertEqual(first.caption, 0)
                XCTAssertEqual(first.depth, 0)
                XCTAssertEqual(first.starsKept, 0)
                let last = Moment.frame(age: 40, world: kind, reduced: reduced)
                XCTAssertEqual(last.cards, 0)
                XCTAssertEqual(last.look, 1)
                XCTAssertEqual(last.star, 1, accuracy: 1e-12)
                XCTAssertEqual(last.band?.strength ?? 0, 0)
                XCTAssertEqual(last.band?.light ?? 0, 0)
                XCTAssertEqual(last.caption, 0)
                XCTAssertEqual(last.depth, 1)
                XCTAssertEqual(last.starsKept, 0)
            }
            XCTAssertEqual(Moment.frame(age: 0, world: kind).star, 0)
        }
    }

    func testTheCoverIsTheSpreadsPhonePageAtEveryInstant() {
        // In the lab the two displays play the same moment, sample for sample…
        let cover = bedtime.rows(where: ["display": "cover"]).map { $0.dropFirst() }
        let spread = bedtime.rows(where: ["display": "spread"]).map { $0.dropFirst() }
        XCTAssertEqual(cover.count, 402)
        XCTAssertEqual(cover, spread)
        // …and here the moment knows only the world.
        XCTAssertEqual(SkyWorld.Display.cover.kind, SkyWorld.Display.spread.kind)
    }

    func testTheTreeGoesWithTheCardsReturn() {
        // What the cards uncover at bedtime is the tree, and it goes as they
        // come back over the sky: the lab's `treeShown` for the moment's own
        // look and cards, at every sample.
        for (name, display) in displays {
            for row in bedtime.rows(where: ["display": name, "motion": "full"]) {
                let age = bedtime.number(row, "age")
                let frame = Moment.frame(age: age, world: display.kind)
                XCTAssertEqual(SkyCamera.treeShown(look: frame.look, cards: 1 - frame.cards),
                               bedtime.number(row, "tree"), accuracy: 1e-6, "\(name) at \(age) s")
            }
        }
        let poster = Moment.frame(age: 3.5, world: .duo)
        XCTAssertEqual(SkyCamera.treeShown(look: poster.look, cards: 1 - poster.cards), 1, "the bare poster")
        let after = Moment.frame(age: 6, world: .duo)
        XCTAssertEqual(SkyCamera.treeShown(look: after.look, cards: 1 - after.cards), 0, "not drawn with the cards on")
    }

    func testHisStarsKeepAFaintPresenceWhileTheCardsAreAway() {
        // A July bedtime: the sky is too light for stars, so they come up
        // faintly over the whole sky as the view arrives and are let go as
        // the cards come back.
        for kind in worlds {
            let leaves = Moment.beats(world: kind).bandLeaves ?? .nan
            XCTAssertEqual(Moment.frame(age: leaves - 0.5, world: kind).starsKept, 0)
            XCTAssertEqual(Moment.frame(age: leaves + 0.4, world: kind).starsKept, 0.34, accuracy: 1e-9)
            XCTAssertEqual(Moment.frame(age: 4.6, world: kind).starsKept, 0.34, accuracy: 1e-9)
            XCTAssertEqual(Moment.frame(age: 5.8, world: kind).starsKept, 0)
        }
    }

    // MARK: Reduce Motion

    func testUnderReduceMotionTheLookedUpStillDissolvesIn() {
        for kind in worlds {
            let beats = Moment.beats(world: kind, reduced: true)
            XCTAssertEqual(beats, Moment.beats(world: .duo, reduced: true), "the same table on every display")
            for age in ages(0, 6) where Int((age * 1000).rounded()) % 10 == 0 {
                let frame = Moment.frame(age: age, world: kind, reduced: true)
                XCTAssertNil(frame.band, "no band")
                XCTAssertEqual(frame.star, 1, "no spark: the star belongs to the looked-up still")
            }
            // The cards go; the still dissolves in once they are away, over
            // 0.6 s; the caption stands for two seconds; the cards return.
            XCTAssertEqual(Moment.frame(age: 0.6, world: kind, reduced: true).cards, 1)
            XCTAssertEqual(Moment.frame(age: 0.6, world: kind, reduced: true).look, 0)
            XCTAssertEqual(Moment.frame(age: 0.9, world: kind, reduced: true).look, 0.5, accuracy: 1e-9)
            XCTAssertEqual(Moment.frame(age: 1.2, world: kind, reduced: true).look, 1)
            XCTAssertEqual(beats.rise.upperBound - beats.rise.lowerBound, SkyEvent.dissolveDuration, accuracy: 1e-9)
            XCTAssertEqual(Moment.frame(age: 1.6, world: kind, reduced: true).caption, 1, accuracy: 1e-9)
            XCTAssertEqual(Moment.frame(age: 3.0, world: kind, reduced: true).caption, 1, accuracy: 1e-9)
            XCTAssertEqual(Moment.frame(age: 3.4, world: kind, reduced: true).caption, 0)
            XCTAssertEqual(Moment.frame(age: 4.0, world: kind, reduced: true).cards, 0)
        }
    }

    // MARK: A touch ends it

    func testATouchEndsTheMomentAtOnce() {
        for kind in worlds {
            // 3.2 s: the cards away, the view up, the band crossing, the caption standing.
            let touched = 3.2
            let before = Moment.frame(age: touched, world: kind)
            XCTAssertEqual(before.cards, 1)
            XCTAssertEqual(before.caption, 1, accuracy: 1e-9)
            XCTAssertGreaterThan(before.band?.light ?? 0, 0.5)
            // The frame of the touch is the frame before it.
            XCTAssertEqual(Moment.frame(age: touched, world: kind, endedAt: touched), before)

            // The band and the caption are out in 0.2 s…
            let lights = Moment.frame(age: touched + 0.2, world: kind, endedAt: touched)
            XCTAssertEqual(lights.caption, 0, accuracy: 1e-12)
            XCTAssertEqual(lights.band?.light ?? .nan, 0, accuracy: 1e-12)
            XCTAssertEqual(lights.band?.strength ?? .nan, 0, accuracy: 1e-12)
            XCTAssertGreaterThan(lights.cards, 0, "the cards are still on their way")
            // …and the cards are back in 0.3 s.
            XCTAssertEqual(Moment.frame(age: touched + 0.3, world: kind, endedAt: touched).cards, 0)
            XCTAssertEqual(Moment.whole(world: kind, endedAt: touched), touched + 0.3, accuracy: 1e-12)
            XCTAssertEqual(Moment.frame(age: touched + 0.1, world: kind, endedAt: touched).cards,
                           1 - Moment.easeOut(1.0 / 3), accuracy: 1e-9, "with the moment's own ease-out")

            // Nothing comes back after it, and everything goes one way.
            var last = before
            for age in ages(touched, 6.5) {
                let frame = Moment.frame(age: age, world: kind, endedAt: touched)
                XCTAssertLessThanOrEqual(frame.cards, last.cards + 1e-12, "at \(age) s")
                XCTAssertLessThanOrEqual(frame.caption, last.caption + 1e-12, "at \(age) s")
                XCTAssertLessThanOrEqual(frame.band?.light ?? 0, (last.band?.light ?? 0) + 1e-12, "at \(age) s")
                XCTAssertLessThanOrEqual(frame.starsKept, last.starsKept + 1e-12, "at \(age) s")
                last = frame
            }
        }
    }

    func testAfterATouchTheFaintStarsGoWithTheCards() {
        // "They are let go as the cards come back over the sky": with the
        // cards, over their 0.3 s — not with the band and the caption, which
        // are out in 0.2 s. While a card is still part-way back, the sky
        // behind it still has its stars.
        for kind in worlds {
            let touched = 3.2
            XCTAssertEqual(Moment.frame(age: touched, world: kind).starsKept, 0.34, accuracy: 1e-9)
            for age in ages(touched, touched + 0.4) {
                let frame = Moment.frame(age: age, world: kind, endedAt: touched)
                XCTAssertEqual(frame.starsKept, 0.34 * frame.cards, accuracy: 1e-12, "at \(age) s")
            }
            let lightsOut = Moment.frame(age: touched + 0.2, world: kind, endedAt: touched)
            XCTAssertEqual(lightsOut.caption, 0, accuracy: 1e-12)
            XCTAssertGreaterThan(lightsOut.starsKept, 0.01, "his stars went out with the lights, ahead of the cards")
            XCTAssertEqual(Moment.frame(age: touched + 0.3, world: kind, endedAt: touched).starsKept, 0)
        }
    }

    func testATouchPutsTheLightsOutWithoutAStep() {
        // The band and the caption are out 0.2 s after a touch, eased at
        // both ends — no join jumps: a hundredth of a second after the touch
        // under a hundredth of them has gone, half way they are half, and a
        // hundredth of a second before the end under a hundredth is left to
        // snap off. (3.2 s: the caption stands at 1 and his stars answer in
        // full, so what is left of each is the touch's doing alone.)
        for kind in worlds {
            let touched = 3.2
            func left(_ since: Double) -> MomentFrame {
                Moment.frame(age: touched + since, world: kind, endedAt: touched)
            }
            XCTAssertGreaterThan(left(0.01).caption, 0.99)
            XCTAssertEqual(left(0.1).caption, 0.5, accuracy: 1e-9)
            XCTAssertLessThan(left(0.19).caption, 0.01)
            XCTAssertGreaterThan(left(0.19).caption, 0)
            for since in [0.01, 0.05, 0.1, 0.15, 0.19] {
                let frame = left(since)
                XCTAssertEqual(frame.band?.strength ?? .nan, frame.caption, accuracy: 1e-12, "the answers go out as the caption does")
                XCTAssertLessThanOrEqual(frame.band?.light ?? .nan, frame.caption + 1e-12, "…and the band's own light")
            }
        }
    }

    func testATouchLeavesTheViewUpAndTheStarLit() {
        // The view stays up and runs on at its own pace; nothing is brought
        // back down, the star stays lit, the room goes on dimming.
        for kind in worlds {
            for touched in [0.2, 0.8, 1.4, 2.2, 3.0, 5.0] {
                for age in ages(0, 10) where Int((age * 1000).rounded()) % 50 == 0 {
                    let plain = Moment.frame(age: age, world: kind)
                    let frame = Moment.frame(age: age, world: kind, endedAt: touched)
                    XCTAssertEqual(frame.look, plain.look, "touched at \(touched), at \(age) s")
                    XCTAssertEqual(frame.star, plain.star, "touched at \(touched), at \(age) s")
                    XCTAssertEqual(frame.depth, plain.depth, "touched at \(touched), at \(age) s")
                    if age <= touched { XCTAssertEqual(frame, plain, "before the touch nothing differs") }
                }
            }
        }
    }

    func testAfterATouchNothingThatHadNotBegunBegins() {
        for kind in worlds {
            // Touched as the cards fall, 0.5 s in: they return from where
            // they are, and the band and the caption never play.
            let touched = 0.5
            let then = Moment.frame(age: touched, world: kind)
            XCTAssertEqual(then.cards, 0.5, accuracy: 1e-9)
            XCTAssertEqual(Moment.frame(age: 0.8, world: kind, endedAt: touched).cards, 0)
            for age in ages(touched, 8) where Int((age * 1000).rounded()) % 20 == 0 {
                let frame = Moment.frame(age: age, world: kind, endedAt: touched)
                XCTAssertLessThanOrEqual(frame.cards, then.cards)
                XCTAssertNil(frame.band, "at \(age) s")
                XCTAssertEqual(frame.caption, 0, "at \(age) s")
                XCTAssertEqual(frame.starsKept, 0, "at \(age) s")
            }
            XCTAssertEqual(Moment.frame(age: 2.4 + 0.3, world: kind, endedAt: touched).look,
                           Moment.frame(age: 2.4 + 0.3, world: kind).look, "…while the view still comes up")
        }
    }

    func testATouchAsTheCardsReturnNeverHoldsThemBack() {
        for kind in worlds {
            let touched = 5.5   // the cards are nearly back
            for age in ages(touched, 6) {
                let plain = Moment.frame(age: age, world: kind)
                let frame = Moment.frame(age: age, world: kind, endedAt: touched)
                XCTAssertLessThanOrEqual(frame.cards, plain.cards, "at \(age) s")
            }
            XCTAssertEqual(Moment.whole(world: kind, endedAt: touched), 5.8, "no later than the moment's own end")
            XCTAssertEqual(Moment.whole(world: kind, endedAt: 9), 5.8, "a touch after the moment ends nothing")
            XCTAssertEqual(Moment.frame(age: 9.5, world: kind, endedAt: 9), Moment.frame(age: 9.5, world: kind))
        }
    }

    func testATouchNeverHoldsAnythingUp() {
        // Whatever is already on its way out when the touch lands goes no
        // slower for it: the caption as it fades (4.15 – 4.6 s), the band's
        // own light and his stars' answers as they let go, the faint stars
        // and the cards as the cards return.
        for kind in worlds {
            for touched in [3.9, 4.3, 4.5, 4.7, 4.8, 5.0, 5.5] {
                for age in ages(touched, touched + 0.5) {
                    let plain = Moment.frame(age: age, world: kind)
                    let frame = Moment.frame(age: age, world: kind, endedAt: touched)
                    let at = "touched at \(touched), at \(age) s"
                    XCTAssertLessThanOrEqual(frame.cards, plain.cards, "the cards, \(at)")
                    XCTAssertLessThanOrEqual(frame.caption, plain.caption, "the caption, \(at)")
                    XCTAssertLessThanOrEqual(frame.band?.strength ?? 0, plain.band?.strength ?? 0, "his stars' answers, \(at)")
                    XCTAssertLessThanOrEqual(frame.band?.light ?? 0, plain.band?.light ?? 0, "the band's light, \(at)")
                    XCTAssertLessThanOrEqual(frame.starsKept, plain.starsKept, "the faint stars, \(at)")
                }
            }
        }
    }

    func testATouchUnderReduceMotionEndsItTheSameWay() {
        let touched = 2.0   // the still is in, the caption standing
        let before = Moment.frame(age: touched, world: .slab, reduced: true)
        XCTAssertEqual(before.caption, 1, accuracy: 1e-9)
        // (from where the REDUCED moment had it: in the full one the caption has not begun at 2 s)
        XCTAssertEqual(Moment.frame(age: touched, world: .slab).caption, 0)
        XCTAssertEqual(Moment.frame(age: touched + 0.1, world: .slab, reduced: true, endedAt: touched).caption, 0.5,
                       accuracy: 1e-9, "half out, half way")
        XCTAssertEqual(Moment.frame(age: touched + 0.2, world: .slab, reduced: true, endedAt: touched).caption, 0,
                       accuracy: 1e-12)
        XCTAssertEqual(Moment.frame(age: touched + 0.3, world: .slab, reduced: true, endedAt: touched).cards, 0)
        XCTAssertEqual(Moment.frame(age: touched + 0.3, world: .slab, reduced: true, endedAt: touched).look, 1)
        XCTAssertEqual(Moment.whole(world: .slab, reduced: true, endedAt: touched), 2.3, accuracy: 1e-12)
    }

    // MARK: The quiet events

    private func quietRows(_ event: String, file: StaticString = #filePath, line: UInt = #line) -> [[String]] {
        let rows = quiet.rows(where: ["event": event])
        // the cover and the slab, in full and under Reduce Motion, every 0.05 s from 0 to 10 s
        XCTAssertEqual(rows.count, 804, event, file: file, line: line)
        return rows
    }

    func testAQuietRiseFollowsTheLab() {
        for row in quietRows("arrive") {
            let age = quiet.number(row, "age"), reduced = quiet.text(row, "motion") == "reduced"
            let at = "\(row[1]) \(row[2]) at \(age) s"
            let rise = Moment.arrive(age: age, reduced: reduced)
            XCTAssertEqual(rise.look, quiet.number(row, "look"), accuracy: 1e-6, "look, \(at)")
            XCTAssertEqual(rise.star, quiet.number(row, "star"), accuracy: 1e-6, "star, \(at)")
            XCTAssertEqual(Moment.depth(of: .night, begins: .quietly, age: age), quiet.number(row, "depth"),
                           accuracy: 1e-6, "depth, \(at)")
            // Behind the cards the tree leaves early in the rise.
            if !reduced {
                XCTAssertEqual(SkyCamera.treeShown(look: rise.look, cards: 1), quiet.number(row, "tree"),
                               accuracy: 1e-6, "tree, \(at)")
            }
        }
        // Up over 2.5 s, the star in over the first 0.8 s; a 0.6 s dissolve under Reduce Motion.
        XCTAssertEqual(Moment.arrive(age: 0), Moment.Quiet(look: 0, star: 0))
        XCTAssertLessThan(Moment.arrive(age: 2.45).look, 1)
        XCTAssertEqual(Moment.arrive(age: 2.5), Moment.Quiet(look: 1, star: 1))
        XCTAssertEqual(Moment.arrive(age: 0.8).star, 1)
        XCTAssertEqual(Moment.arrive(age: 0, reduced: true).look, 0)
        XCTAssertEqual(Moment.arrive(age: 0.3, reduced: true).look, 0.5, accuracy: 1e-9)
        XCTAssertEqual(Moment.arrive(age: 0.6, reduced: true), Moment.Quiet(look: 1, star: 1))
    }

    func testFirstLightSettlesAsInTheLab() {
        for row in quietRows("settle") {
            let age = quiet.number(row, "age"), reduced = quiet.text(row, "motion") == "reduced"
            let at = "\(row[1]) \(row[2]) at \(age) s"
            let settle = Moment.settle(age: age, reduced: reduced)
            XCTAssertEqual(settle.look, quiet.number(row, "look"), accuracy: 1e-6, "look, \(at)")
            XCTAssertEqual(settle.star, quiet.number(row, "star"), accuracy: 1e-6, "star, \(at)")
            // He still sleeps: first light does not touch the room.
            XCTAssertEqual(quiet.number(row, "depth"), SleepKind.night.depth, "depth, \(at)")
            if !reduced {
                XCTAssertEqual(SkyCamera.treeShown(look: settle.look, cards: 1), quiet.number(row, "tree"),
                               accuracy: 1e-6, "tree, \(at)")
            }
        }
        // 1 until 0.1 s, down by 2.7 s; the star out by 2.3 s, on its way back to the tree.
        XCTAssertEqual(Moment.settle(age: 0), Moment.Quiet(look: 1, star: 1))
        XCTAssertEqual(Moment.settle(age: 0.1), Moment.Quiet(look: 1, star: 1))
        XCTAssertLessThan(Moment.settle(age: 0.2).look, 1)
        XCTAssertEqual(Moment.settle(age: 2.3).star, 0)
        XCTAssertGreaterThan(Moment.settle(age: 2.3).look, 0)
        XCTAssertEqual(Moment.settle(age: 2.7), Moment.Quiet(look: 0, star: 0))
        XCTAssertEqual(Moment.settle(age: 0.6, reduced: true).look, 0)
    }

    func testANightFeedMovesNothing() {
        // He wakes at 3 a.m.: the room un-dims, the view stays up, the star
        // stays in its window. He is put down again: the room dims. In the
        // lab the look and the star are 1 at every sample of both.
        for row in quietRows("wakeNight") {
            let age = quiet.number(row, "age")
            XCTAssertEqual(quiet.number(row, "look"), 1)
            XCTAssertEqual(quiet.number(row, "star"), 1)
            XCTAssertEqual(Moment.depth(wokenFrom: .night, age: age), quiet.number(row, "depth"), accuracy: 1e-6,
                           "at \(age) s")
        }
        for row in quietRows("arriveAgain") {
            let age = quiet.number(row, "age")
            XCTAssertEqual(quiet.number(row, "look"), 1)
            XCTAssertEqual(quiet.number(row, "star"), 1)
            XCTAssertEqual(Moment.depth(of: .night, begins: .quietly, age: age), quiet.number(row, "depth"),
                           accuracy: 1e-6, "at \(age) s")
        }
    }

    func testANapOnlyDimsTheRoom() {
        for row in quietRows("arriveNap") {
            let age = quiet.number(row, "age")
            XCTAssertEqual(quiet.number(row, "look"), 0)
            XCTAssertEqual(quiet.number(row, "star"), 0)
            XCTAssertEqual(Moment.depth(of: .nap, begins: .quietly, age: age), quiet.number(row, "depth"),
                           accuracy: 1e-6, "at \(age) s")
        }
        for row in quietRows("wakeNap") {
            let age = quiet.number(row, "age")
            XCTAssertEqual(quiet.number(row, "look"), 0)
            XCTAssertEqual(quiet.number(row, "star"), 0)
            XCTAssertEqual(Moment.depth(wokenFrom: .nap, age: age), quiet.number(row, "depth"), accuracy: 1e-6,
                           "at \(age) s")
        }
        XCTAssertEqual(quiet.rows.count, 6 * 804, "an event of the lab's the tests do not read")
    }

    func testTheRoomsDepthNeverJumps() {
        // It eases in from 0 when a sleep starts, and out from what that
        // sleep had when he wakes — a night's 1, a nap's 0.45 — so the first
        // frame after a change is the frame before it.
        for sleep in [SleepKind.night, .nap] {
            XCTAssertEqual(Moment.depth(of: sleep, begins: .quietly, age: 0), 0)
            XCTAssertEqual(Moment.depth(of: sleep, begins: .withTheMoment, age: 0), 0)
            XCTAssertEqual(Moment.depth(of: sleep, begins: .quietly, age: 4), sleep.depth)
            XCTAssertEqual(Moment.depth(of: sleep, begins: .withTheMoment, age: 9), sleep.depth)
            XCTAssertEqual(Moment.depth(wokenFrom: sleep, age: 0), sleep.depth)
            XCTAssertEqual(Moment.depth(wokenFrom: sleep, age: 0.3), sleep.depth, "still as dim for a moment")
            XCTAssertEqual(Moment.depth(wokenFrom: sleep, age: 5), 0)
        }
        XCTAssertEqual(SleepKind.night.depth, 1)
        XCTAssertEqual(SleepKind.nap.depth, 0.45)
    }

    // MARK: The cards' return

    func testTheCardsReturnWithSwiftUIsEaseOut() {
        // The cubic Bézier (0, 0, 0.58, 1): half way at a third of the time,
        // 95 % by 0.83.
        XCTAssertEqual(Moment.easeOut(0), 0)
        XCTAssertEqual(Moment.easeOut(1), 1)
        XCTAssertEqual(Moment.easeOut(0.34), 0.5, accuracy: 0.01)
        XCTAssertEqual(Moment.easeOut(0.83), 0.95, accuracy: 0.01)
        XCTAssertEqual(Moment.easeOut(-1), 0)
        XCTAssertEqual(Moment.easeOut(2), 1)
        // On the curve: for the Bézier's own parameter s, x = 1.74 (1 − s) s² + s³ and y = 3 (1 − s) s² + s³.
        for s in stride(from: 0.05, through: 0.95, by: 0.05) {
            let x = 1.74 * (1 - s) * s * s + s * s * s
            XCTAssertEqual(Moment.easeOut(x), 3 * (1 - s) * s * s + s * s * s, accuracy: 1e-9)
        }
    }
}

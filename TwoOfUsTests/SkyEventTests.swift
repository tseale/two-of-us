import XCTest
@testable import TwoOfUs

/// How each event carries the camera (`SkyEvent.move`), against `look` as
/// the sky lab's own page plays the same event (`SkyCoreFixturesLook`, read
/// out of skies/hill-painted.js `lookOf` frame by frame) and, for bedtime,
/// against the moment's own timeline (`Moment.frame`).
final class SkyEventTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 4096)

    private func labLook(_ play: String) -> [(age: Double, look: Double)] {
        SkyCoreFixture.rows(SkyCoreFixturesLook.look).filter { $0[0] == play }
            .map { (SkyCoreFixture.number($0[1]), SkyCoreFixture.number($0[2])) }
    }

    private func assertLook(_ glide: Glide, plays play: String, frames: Int,
                            file: StaticString = #filePath, line: UInt = #line) {
        let lab = labLook(play)
        XCTAssertEqual(lab.count, frames, file: file, line: line)
        for frame in lab {
            XCTAssertEqual(glide.value(at: start.addingTimeInterval(frame.age)), frame.look, accuracy: 1e-12,
                           "\(play) at \(frame.age) s", file: file, line: line)
        }
    }

    func testANightSleepFromElsewhereRisesOverTwoAndAHalfSeconds() {
        // "A quiet rise behind the cards": up from the first frame, there
        // by 2.5 s.
        let look = SkyEvent.arrive.carrying(.resting(at: 0), at: start, world: .duo, reduced: false)
        assertLook(look, plays: "arrive", frames: 29)
        XCTAssertEqual(look.end.timeIntervalSince(start), 2.5, accuracy: 1e-9)
    }

    func testFirstLightSettlesByTwoPointSevenSeconds() {
        // "A quiet settle behind the cards": it holds a tenth of a second,
        // and is back on the hill at 2.7 s.
        let look = SkyEvent.settle.carrying(.resting(at: 1), at: start, world: .duo, reduced: false)
        assertLook(look, plays: "settle", frames: 31)
        XCTAssertEqual(look.value(at: start.addingTimeInterval(0.1)), 1)
        XCTAssertEqual(look.end.timeIntervalSince(start), 2.7, accuracy: 1e-9)
    }

    func testUnderReduceMotionTheQuietEventsAreAShortDissolve() {
        // No move: `look` is the weight of the looked-up still, in or out
        // over the lab's 0.6 s.
        XCTAssertEqual(SkyCoreFixture.number(SkyCoreFixture.rows(SkyCoreFixturesNight.labQuiet)[0][0]),
                       SkyEvent.dissolveDuration)
        assertLook(SkyEvent.arrive.carrying(.resting(at: 0), at: start, world: .duo, reduced: true),
                   plays: "arrive-reduced", frames: 17)
        assertLook(SkyEvent.settle.carrying(.resting(at: 1), at: start, world: .duo, reduced: true),
                   plays: "settle-reduced", frames: 17)
    }

    func testADissolveIsThatSameCrossFadeWhateverTheMotionSetting() {
        // The night found already begun (a late sync), or the morning found
        // long after first light: the same 0.6 s, with or without motion.
        for reduced in [false, true] {
            assertLook(SkyEvent.dissolve(lookingUp: true).carrying(.resting(at: 0), at: start, world: .duo, reduced: reduced),
                       plays: "arrive-reduced", frames: 17)
            assertLook(SkyEvent.dissolve(lookingUp: false).carrying(.resting(at: 1), at: start, world: .duo, reduced: reduced),
                       plays: "settle-reduced", frames: 17)
        }
    }

    func testBedtimesRiseIsTheMomentsOwnTable() {
        // The bedtime rise belongs to the moment's table (0.3 s longer on
        // the slab, whose sky is twice as tall), and the event carries
        // `look` by it: frame for frame what the lab's page drew…
        assertLook(SkyEvent.bedtime.carrying(.resting(at: 0), at: start, world: .duo, reduced: false),
                   plays: "bedtime-duo", frames: 28)
        assertLook(SkyEvent.bedtime.carrying(.resting(at: 0), at: start, world: .slab, reduced: false),
                   plays: "bedtime-slab", frames: 31)
        // …and, every twentieth of a second, what the moment's own
        // timeline says — one table for the sky and for the cards, so a
        // running glide and `Moment.frame` cannot give two answers. (From
        // the reference date itself, where a date plus an age is that age
        // to the bit: the two are then the same number, not nearly it.)
        let tap = Date(timeIntervalSinceReferenceDate: 0)
        for world in SkyWorld.Kind.allCases {
            for reduced in [false, true] {
                let look = SkyEvent.bedtime.carrying(.resting(at: 0), at: tap, world: world, reduced: reduced)
                for step in 0...200 {
                    let age = Double(step) * 0.05
                    XCTAssertEqual(look.value(at: tap.addingTimeInterval(age)),
                                   Moment.frame(age: age, world: world, reduced: reduced).look,
                                   "\(world), reduced \(reduced), at \(age) s")
                }
                let rise = Moment.beats(world: world, reduced: reduced).rise
                XCTAssertEqual(look.value(at: tap.addingTimeInterval(rise.lowerBound)), 0,
                               "still, until the cards have begun to go")
                XCTAssertEqual(look.end.timeIntervalSince(tap), rise.upperBound, accuracy: 1e-9)
            }
        }
        XCTAssertEqual(SkyEvent.bedtime.move(world: .slab, reduced: false).duration
                       - SkyEvent.bedtime.move(world: .duo, reduced: false).duration, 0.3, accuracy: 1e-9)
    }

    func testAnUndoInTheMiddleOfTheRiseSettlesFromWhereTheViewIs() {
        // The mis-tap: the moment has begun, the view is half way up, and
        // Undo takes the sleep back. The settle starts from THERE — not
        // from the top (a jump up before coming down) and not from the hill.
        let rising = SkyEvent.bedtime.carrying(.resting(at: 0), at: start, world: .duo, reduced: false)
        let undo = start.addingTimeInterval(1.35)
        let partWay = rising.value(at: undo)
        XCTAssertEqual(partWay, 0.5, accuracy: 1e-9, "1.35 s is the middle of the Duo's 0.3 – 2.4 s rise")
        let settling = SkyEvent.settle.carrying(rising, at: undo, world: .duo, reduced: false)
        XCTAssertEqual(settling.value(at: undo), partWay)
        XCTAssertEqual(settling.value(at: undo.addingTimeInterval(0.1)), partWay, "it holds a tenth of a second")
        XCTAssertLessThan(settling.value(at: undo.addingTimeInterval(1)), partWay)
        XCTAssertGreaterThan(settling.value(at: undo.addingTimeInterval(1)), 0)
        XCTAssertEqual(settling.value(at: undo.addingTimeInterval(2.7)), 0, accuracy: 1e-12)
        // Undone before the view has left the hill, nothing moves at all.
        let early = start.addingTimeInterval(0.2)
        let still = SkyEvent.settle.carrying(rising, at: early, world: .duo, reduced: false)
        for step in 0...30 {
            XCTAssertEqual(still.value(at: early.addingTimeInterval(Double(step) * 0.1)), 0)
        }
    }

    func testAnEventDuringAnotherEasesFromWhereTheViewIs() {
        // The night is un-begun by a delete and the view starts down; one
        // second later a new night sleep arrives. The lab, with one event
        // at a time, would snap to the foot of the rise. Here the rise
        // starts from where the settle had got to.
        let settling = SkyEvent.settle.carrying(.resting(at: 1), at: start, world: .duo, reduced: false)
        let later = start.addingTimeInterval(1)
        let partWay = settling.value(at: later)
        XCTAssertGreaterThan(partWay, 0.5)
        XCTAssertLessThan(partWay, 1)
        let rising = SkyEvent.arrive.carrying(settling, at: later, world: .duo, reduced: false)
        XCTAssertEqual(rising.value(at: later), partWay)
        XCTAssertEqual(rising.value(at: later.addingTimeInterval(2.5)), 1, accuracy: 1e-12)
        // And an arrival while the view is already on its way up changes
        // nothing: it runs on at its own pace.
        XCTAssertEqual(SkyEvent.arrive.carrying(rising, at: later.addingTimeInterval(0.4), world: .duo, reduced: false), rising)
    }
}

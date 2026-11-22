import XCTest
@testable import TwoOfUs

/// The lab's arithmetic (`SkyMath`) against the lab's own: `smoothstep` and
/// `lerp` as design/sky-lab/lab/oklab.js computes them
/// (`SkyCoreFixturesColour`), the camera's ease as the lab's page plays it
/// (`SkyCoreFixturesLook`), and JavaScript's `Math.hypot` as the lab's
/// browser computes it, to the bit (`SkyCoreFixturesStars`).
final class SkyMathTests: XCTestCase {
    private let close = 1e-12

    // MARK: Held, eased, mixed

    func testSmoothstepAndLerpAreTheLabs() {
        // `smoothstep` and `lerp` (lab/oklab.js), which every rule of the
        // sky is written in — also with the greater edge first, for an
        // amount that falls as its measure rises.
        let colour = SkyCoreFixturesColour.self
        let eased = SkyCoreFixture.rows(colour.smoothstep)
        XCTAssertEqual(eased.count, 160)
        for row in eased {
            let cells = row.map(SkyCoreFixture.number)
            XCTAssertEqual(SkyMath.smoothstep(cells[0], cells[1], cells[2]), cells[3], accuracy: close, "\(row)")
        }
        let mixed = SkyCoreFixture.rows(colour.lerp)
        XCTAssertEqual(mixed.count, 60)
        for row in mixed {
            let cells = row.map(SkyCoreFixture.number)
            XCTAssertEqual(SkyMath.lerp(cells[0], cells[1], cells[2]), cells[3], accuracy: close, "\(row)")
        }
        XCTAssertEqual(SkyMath.smoothstep(0.2, 0.04, 0.2), 0, accuracy: close)
        XCTAssertEqual(SkyMath.smoothstep(0.2, 0.04, 0.04), 1, accuracy: close)
        XCTAssertEqual(SkyMath.smoothstep(0.2, 0.04, 0.12), 0.5, accuracy: close)
        XCTAssertEqual(SkyMath.lerp(2, 4, 1.5), 5, accuracy: close, "a mix may run past its end")
    }

    func testANumberIsHeldBetweenNoughtAndOne() {
        XCTAssertEqual(SkyMath.clamped(-0.2), 0)
        XCTAssertEqual(SkyMath.clamped(0.37), 0.37)
        XCTAssertEqual(SkyMath.clamped(1.2), 1)
        XCTAssertEqual(SkyMath.clamped(-.infinity), 0)
        XCTAssertEqual(SkyMath.clamped(.infinity), 1)
        // A number that is not one must never reach a colour or a pose.
        XCTAssertEqual(SkyMath.clamped(.nan), 0)
    }

    func testTheCamerasEaseIsTheLabsQuintic() {
        // skies/hill-painted.js, `lookOf`: a night sleep arriving from
        // elsewhere takes the view up over 2.5 s on t³(6t² − 15t + 10) —
        // frame for frame what the lab's page drew.
        let look = SkyCoreFixturesLook.self
        let frames = SkyCoreFixture.rows(look.look).filter { $0[0] == "arrive" }
        XCTAssertEqual(frames.count, 29)
        for frame in frames {
            XCTAssertEqual(SkyMath.quintic(SkyCoreFixture.number(frame[1]) / 2.5), SkyCoreFixture.number(frame[2]), accuracy: close,
                           "arrive at \(frame[1]) s")
        }
    }

    func testTheCameraLeavesRestAndComesToRestWithoutAStartOrAStop() {
        // Standing to standing: no speed and no acceleration at either
        // end, half way at half time, the same going as coming, never
        // backwards — and its fastest 1.875 times its average, which is
        // where the lab's "peak 279 pt/s" comes from.
        XCTAssertEqual(SkyMath.quintic(0), 0)
        XCTAssertEqual(SkyMath.quintic(1), 1)
        XCTAssertEqual(SkyMath.quintic(0.5), 0.5, accuracy: close)
        let h = 1e-4
        XCTAssertEqual(SkyMath.quintic(h) / h, 0, accuracy: 1e-6, "no speed at the start")
        XCTAssertEqual((1 - SkyMath.quintic(1 - h)) / h, 0, accuracy: 1e-6, "none at the end")
        XCTAssertEqual((SkyMath.quintic(0.5 + h) - SkyMath.quintic(0.5 - h)) / (2 * h), 1.875, accuracy: 1e-6)
        var last = 0.0
        for step in 0...1000 {
            let t = Double(step) / 1000
            let value = SkyMath.quintic(t)
            XCTAssertGreaterThanOrEqual(value, last, "at \(t)")
            XCTAssertEqual(value + SkyMath.quintic(1 - t), 1, accuracy: close, "at \(t)")
            last = value
        }
    }

    func testALookIsNeverPastEitherPose() {
        // A hair short of the end the polynomial's own arithmetic rounds
        // to a hair past it; `look` is held to 0 … 1 all the same, and
        // outside its time the ease is simply at its end.
        var t = 1.0
        for _ in 0..<4096 {
            t = t.nextDown
            XCTAssertLessThanOrEqual(SkyMath.quintic(t), 1, "at \(t)")
        }
        t = 0
        for _ in 0..<4096 {
            t = t.nextUp
            XCTAssertGreaterThanOrEqual(SkyMath.quintic(t), 0, "at \(t)")
        }
        XCTAssertEqual(SkyMath.quintic(-3), 0)
        XCTAssertEqual(SkyMath.quintic(7), 1)
    }

    // MARK: Where JavaScript's arithmetic is not Swift's

    func testDistanceIsMeasuredAsTheLabMeasuresIt() {
        // The lab's browser's `Math.hypot`, to the bit: "never closer than
        // 5.6 pt" is a comparison, and must fall the same way on a phone.
        let stars = SkyCoreFixturesStars.self
        let rows = SkyCoreFixture.words(stars.drift).filter { $0.first == "hypot" }
        XCTAssertEqual(rows.count, 158)
        for row in rows {
            let a = Double(row[1]) ?? .nan, b = Double(row[2]) ?? .nan
            let got = SkyMath.hypot(a, b)
            XCTAssertEqual(got.bitPattern, SkyCoreFixture.double(bits: row[3]).bitPattern, "hypot(\(row[1]), \(row[2])) = \(got)")
        }
        XCTAssertEqual(SkyMath.hypot(3, 4), 5)
        XCTAssertEqual(SkyMath.hypot(-50, 0), 50)
        XCTAssertEqual(SkyMath.hypot(.infinity, .nan), .infinity)
        XCTAssertTrue(SkyMath.hypot(1, .nan).isNaN)
    }

    func testAHalfRoundsUpAsInTheLab() {
        // JavaScript's `Math.round`: −2.5 → −2 and −0.5 → 0, where Swift's
        // `rounded()` gives −3 and −1.
        XCTAssertEqual(SkyMath.round(2.5), 3)
        XCTAssertEqual(SkyMath.round(-2.5), -2)
        XCTAssertEqual(SkyMath.round(-0.5), 0)
        XCTAssertEqual(SkyMath.round(-0.51), -1)
        XCTAssertEqual(SkyMath.round(0.49999999999999994), 0)
        XCTAssertEqual(SkyMath.round(7), 7)
        XCTAssertEqual(SkyMath.round(-1.2), -1)
        XCTAssertEqual(SkyMath.round(1.7), 2)
    }
}

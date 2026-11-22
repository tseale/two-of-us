import XCTest
@testable import TwoOfUs

/// An eased value that can be given a new target from wherever it is
/// (`Glide`). Its two curves are held against the sky lab's own samples: the
/// camera's rise as the lab's page plays it (`SkyCoreFixturesLook`, read out
/// of skies/hill-painted.js while it runs) and the room's dimming
/// (`SkyCoreFixturesNight.labRoomDepth`, lab/presence.js `roomDepth`).
final class GlideTests: XCTestCase {
    /// The moment an event starts. Close to the reference date, so that a
    /// tenth of a second added to it is exactly a tenth of a second and the
    /// curves can be compared to twelve places; `testAtTonightsDate…` does
    /// it again at a real date.
    private let tap = Date(timeIntervalSinceReferenceDate: 4096)

    private func lookRows(_ play: String) -> [(age: Double, look: Double)] {
        SkyCoreFixture.rows(SkyCoreFixturesLook.look).filter { $0[0] == play }
            .map { (SkyCoreFixture.number($0[1]), SkyCoreFixture.number($0[2])) }
    }

    private func rise(_ display: String) throws -> (starts: Double, ends: Double) {
        let row = try XCTUnwrap(SkyCoreFixture.rows(SkyCoreFixturesLook.rise).first { $0[0] == display })
        return (SkyCoreFixture.number(row[1]), SkyCoreFixture.number(row[2]))
    }

    private func depthRows(_ curve: String) -> [(age: Double, depth: Double)] {
        SkyCoreFixture.rows(SkyCoreFixturesNight.labRoomDepth).filter { $0[0] == curve }
            .map { (SkyCoreFixture.number($0[1]), SkyCoreFixture.number($0[2])) }
    }

    // MARK: The lab's curves

    func testTheCameraRisesOnTheLabsQuintic() throws {
        // The bedtime moment's rise: nothing until 0.3 s, up by 2.4 s on the
        // Duo and by 2.7 s on the slab, on t³(6t² − 15t + 10). Frame for
        // frame what the lab's page drew.
        for (display, play) in [("duo", "bedtime-duo"), ("slab", "bedtime-slab")] {
            let timing = try rise(display)
            let look = Glide.resting(at: 0).retargeted(to: 1, at: tap, over: timing.ends - timing.starts,
                                                       after: timing.starts)
            let frames = lookRows(play)
            XCTAssertGreaterThan(frames.count, 25)
            for frame in frames {
                XCTAssertEqual(look.value(at: tap.addingTimeInterval(frame.age)), frame.look, accuracy: 1e-12,
                               "\(play) at \(frame.age) s")
            }
            XCTAssertEqual(look.value(at: tap.addingTimeInterval(timing.starts)), 0, "still, until the cards have begun to go")
            XCTAssertEqual(look.value(at: tap.addingTimeInterval(timing.ends)), 1, accuracy: 1e-12)
            XCTAssertEqual(look.value(at: tap.addingTimeInterval(timing.ends + 0.001)), 1, "and exactly up, once it is up")
        }
    }

    func testTheRoomDimsOnTheLabsSmoothstep() {
        // lab/presence.js, `roomDepth`: with the moment the room dims from
        // 1.2 s to 9 s; a sleep arriving from elsewhere dims it over 4 s —
        // a nap's to 0.45; a wake un-dims it from what that sleep had, from
        // 0.3 s to 5 s.
        let night = SleepKind.night.depth, nap = SleepKind.nap.depth
        let curves: [(String, Glide)] = [
            ("bedtime-night", Glide.resting(at: 0).retargeted(to: night, at: tap, over: 7.8, after: 1.2, curve: .smoothstep)),
            ("arrive-night", Glide.resting(at: 0).retargeted(to: night, at: tap, over: 4, curve: .smoothstep)),
            ("arrive-nap", Glide.resting(at: 0).retargeted(to: nap, at: tap, over: 4, curve: .smoothstep)),
            ("wake-night", Glide.resting(at: night).retargeted(to: 0, at: tap, over: 4.7, after: 0.3, curve: .smoothstep)),
            ("wake-nap", Glide.resting(at: nap).retargeted(to: 0, at: tap, over: 4.7, after: 0.3, curve: .smoothstep)),
        ]
        for (name, glide) in curves {
            let samples = depthRows(name)
            XCTAssertEqual(samples.count, 101)
            for sample in samples {
                XCTAssertEqual(glide.value(at: tap.addingTimeInterval(sample.age)), sample.depth, accuracy: 1e-12,
                               "\(name) at \(sample.age) s")
            }
        }
        // And where the room rests: the lab's two depths.
        XCTAssertEqual(depthRows("standing-night").first?.depth, SleepKind.night.depth)
        XCTAssertEqual(depthRows("standing-nap").first?.depth, SleepKind.nap.depth)
        XCTAssertEqual(depthRows("standing-awake").first?.depth, 0)
    }

    func testAtTonightsDateTheCurveIsStillTheLabs() throws {
        // A Date counts seconds from 2001 in a Double: by November 2026 its
        // grain is a tenth of a microsecond. The rise still matches the lab
        // to a millionth of the way up — a thousandth of a pixel.
        var chicagoTime = Calendar(identifier: .gregorian)
        chicagoTime.timeZone = TimeZone(identifier: "America/Chicago")!
        let bedtime = chicagoTime.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 19, minute: 40))!
        let timing = try rise("duo")
        let look = Glide.resting(at: 0).retargeted(to: 1, at: bedtime, over: timing.ends - timing.starts,
                                                   after: timing.starts)
        for frame in lookRows("bedtime-duo") {
            XCTAssertEqual(look.value(at: bedtime.addingTimeInterval(frame.age)), frame.look, accuracy: 1e-6)
        }
    }

    func testTheRiseStaysUnderFiveHundredPointsASecond() {
        // lab/presence.js: "the slab's sky is twice as tall as the Duo's
        // (630 pt against 312), so its rise is 0.3 s longer: at its peak
        // 492 pt/s, not 563 (the Duo's: 279)". The quintic's fastest is
        // 1.875 times its average, half way.
        func peak(travel: Double, over duration: Double) -> Double {
            let look = Glide.resting(at: 0).retargeted(to: 1, at: tap, over: duration)
            var fastest = 0.0
            let frame = 1.0 / 240
            for step in 0..<Int(duration * 240) {
                let now = tap.addingTimeInterval(Double(step) * frame)
                fastest = max(fastest, (look.value(at: now.addingTimeInterval(frame)) - look.value(at: now)) / frame)
            }
            return fastest * travel
        }
        XCTAssertEqual(peak(travel: 312, over: 2.1), 279, accuracy: 1)
        XCTAssertEqual(peak(travel: 630, over: 2.4), 492, accuracy: 1)
        XCTAssertEqual(peak(travel: 630, over: 2.1), 563, accuracy: 1, "what the slab would have had at the Duo's pace")
    }

    // MARK: No join may jump

    func testARetargetStartsFromWhereTheValueIs() {
        // Whenever a new target arrives — here, first light interrupting a
        // rise at every tenth of a second of it — the value at that instant
        // is the value it had, and a frame later it has barely moved.
        let rising = Glide.resting(at: 0).retargeted(to: 1, at: tap, over: 2.5)
        for tenth in 0...30 {
            let now = tap.addingTimeInterval(Double(tenth) / 10)
            let before = rising.value(at: now)
            let settling = rising.retargeted(to: 0, at: now, over: 2.6, after: 0.1)
            XCTAssertEqual(settling.value(at: now), before, "at \(tenth) tenths: the frame before is the first frame after")
            XCTAssertEqual(settling.from, before)
            let nextFrame = settling.value(at: now.addingTimeInterval(1.0 / 60))
            XCTAssertEqual(nextFrame, before, accuracy: 1e-9, "and it is still holding a frame later")
            XCTAssertEqual(settling.value(at: now.addingTimeInterval(0.1 + 2.6)), 0, accuracy: 1e-12)
            XCTAssertEqual(settling.value(at: now.addingTimeInterval(0.1 + 2.6 + 0.001)), 0)
            // On the way it never leaves the span between where it was and
            // where it is going.
            for step in 0...54 {
                let value = settling.value(at: now.addingTimeInterval(Double(step) / 20))
                XCTAssertGreaterThanOrEqual(value, 0)
                XCTAssertLessThanOrEqual(value, before)
            }
        }
    }

    func testGivenTheTargetItAlreadyHasItRunsOnAtItsOwnPace() {
        // Half a second into the rise something else asks for "up" (a second
        // sleep the same night; the Duo opening). The rise is not restarted.
        let rising = Glide.resting(at: 0).retargeted(to: 1, at: tap, over: 2.5)
        let again = rising.retargeted(to: 1, at: tap.addingTimeInterval(0.5), over: 0.6, curve: .smoothstep)
        XCTAssertEqual(again, rising)
        // A value at rest asked to be where it is does not move either.
        let up = Glide.resting(at: 1)
        XCTAssertEqual(up.retargeted(to: 1, at: tap, over: 2.5), up)
        XCTAssertTrue(up.isResting(at: tap))
    }

    func testItHoldsUntilItStartsAndStaysOnceItHasArrived() {
        let glide = Glide.resting(at: 0.25).retargeted(to: 1, at: tap, over: 2, after: 0.5)
        XCTAssertEqual(glide.value(at: tap.addingTimeInterval(-10)), 0.25)
        XCTAssertEqual(glide.value(at: tap), 0.25)
        XCTAssertEqual(glide.value(at: tap.addingTimeInterval(0.5)), 0.25)
        XCTAssertEqual(glide.value(at: tap.addingTimeInterval(1.5)), 0.625, accuracy: 1e-12, "half way in time is half way there")
        XCTAssertEqual(glide.value(at: tap.addingTimeInterval(2.5)), 1)
        XCTAssertEqual(glide.value(at: tap.addingTimeInterval(86_400)), 1)
        XCTAssertEqual(glide.end.timeIntervalSince(tap), 2.5, accuracy: 1e-9)
        XCTAssertFalse(glide.isResting(at: tap.addingTimeInterval(2.4)))
        XCTAssertTrue(glide.isResting(at: tap.addingTimeInterval(2.5)))
        // No time at all is a cut, not a division by zero.
        let cut = Glide.resting(at: 0).retargeted(to: 1, at: tap, over: 0)
        XCTAssertEqual(cut.value(at: tap), 0)
        XCTAssertEqual(cut.value(at: tap.addingTimeInterval(0.001)), 1)
    }

    func testNothingRestsWhileThereIsStillAFrameToDraw() {
        // The driver draws at sixty a second only until a glide says it is
        // resting. So resting has to mean that the value drawn at that
        // instant IS the target. A cut asked at its own instant still
        // answers with the frame before it (no join may jump): it is not
        // resting yet, or the old pose would be left standing.
        let cut = Glide.resting(at: 0).retargeted(to: 1, at: tap, over: 0)
        XCTAssertEqual(cut.value(at: tap), 0)
        XCTAssertFalse(cut.isResting(at: tap), "one more frame to draw")
        XCTAssertTrue(cut.isResting(at: tap.addingTimeInterval(1.0 / 120)))
        XCTAssertEqual(cut.value(at: tap.addingTimeInterval(1.0 / 120)), 1)

        // And so for every glide the sky makes: wherever one says it rests,
        // its value is its target, and before that it is not.
        let held = Glide.resting(at: 1).retargeted(to: 0, at: tap, over: 0, after: 0.1)
        let glides = [cut, held,
                      Glide.resting(at: 0).retargeted(to: 1, at: tap, over: 2.5),
                      Glide.resting(at: 1).retargeted(to: 0, at: tap, over: 2.6, after: 0.1),
                      Glide.resting(at: 0.3).retargeted(to: 1, at: tap, over: 0.6, curve: .smoothstep),
                      Glide.resting(at: 1)]
        for glide in glides {
            for step in -6...200 {
                let now = tap.addingTimeInterval(Double(step) / 60)
                if glide.isResting(at: now) {
                    XCTAssertEqual(glide.value(at: now), glide.to, "\(glide) at frame \(step)")
                } else {
                    XCTAssertLessThanOrEqual(now, glide.end, "\(glide) at frame \(step): past its end and not resting")
                }
            }
        }
        XCTAssertFalse(held.isResting(at: tap.addingTimeInterval(0.1)))
        XCTAssertTrue(held.isResting(at: tap.addingTimeInterval(0.2)))
    }

    func testBothCurvesOnlyEverGoForward() {
        for curve in [Glide.Curve.quintic, .smoothstep] {
            var previous = 0.0
            for step in 0...1000 {
                let value = curve.eased(Double(step) / 1000)
                XCTAssertGreaterThanOrEqual(value, previous)
                previous = value
            }
            XCTAssertEqual(curve.eased(0), 0)
            XCTAssertEqual(curve.eased(0.5), 0.5, accuracy: 1e-12)
            XCTAssertEqual(curve.eased(1), 1)
            XCTAssertEqual(curve.eased(-3), 0)
            XCTAssertEqual(curve.eased(7), 1)
        }
    }
}

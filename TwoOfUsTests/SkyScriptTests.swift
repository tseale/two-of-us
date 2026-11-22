import XCTest
@testable import TwoOfUs

/// Which event a change of tonight plays (`SkyScript`), rule by rule, on
/// states `NightRule` really derives from a sleep log — 21 November 2026 in
/// Chicago, the lab's default evening. Bedtime is 7:40 pm.
///
/// The rules are the design's (design/sky-lab/BRIEF.md, "The night lasts
/// until first light": the moment plays for a night sleep started by hand on
/// this phone, once a night; a night sleep from anywhere else rises quietly;
/// first light settles; nothing else moves) and the port plan's answers to
/// what the real log does to them (edits change ids, syncs land late and in
/// halves, Undo exists).
final class SkyScriptTests: XCTestCase {
    private let chicago = SkyPlace(latitude: 41.8781, longitude: -87.6298)

    private var chicagoTime: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }

    private func at(_ d: Int, _ h: Int, _ min: Int = 0, _ s: Int = 0) -> Date {
        chicagoTime.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: min, second: s))!
    }

    private var bedtime: Date { at(21, 19, 40) }

    private func sleep(_ start: Date, until end: Date? = nil) -> SleepSpan {
        SleepSpan(id: UUID(), start: start, end: end)
    }

    private func night(_ now: Date, _ sleeps: [SleepSpan]) -> NightState {
        NightRule.state(at: now, sleeps: sleeps, place: chicago, calendar: chicagoTime)
    }

    /// Home on screen, having already settled on `state`.
    private func showing(_ state: NightState) -> SkyScript.Standing {
        SkyScript.Standing(night: state, unbegunSince: nil)
    }

    private func step(from: SkyScript.Standing?, to: NightState, hand: HandStart? = nil,
                      playedTonight: Bool = false, now: Date) -> SkyScript.Step {
        SkyScript.step(from: from, to: to, hand: hand, playedTonight: playedTonight, now: now)
    }

    // MARK: 1. The first evaluation plays nothing

    func testTheFirstEvaluationPlaysNothing() {
        // Home opened cold at 3 am with him asleep since 7:40: it is simply
        // looking up. Nothing rises, even with a tap in memory.
        let asleep = night(at(22, 3), [sleep(bedtime)])
        XCTAssertTrue(asleep.hasBegun)
        let first = step(from: nil, to: asleep, hand: HandStart(sleepID: UUID(), at: at(22, 3)), now: at(22, 3))
        XCTAssertNil(first.event)
        XCTAssertEqual(first.standing, showing(asleep))
        XCTAssertNil(first.askAgainAt)
        // Nor does anything settle when it opens on the hill.
        XCTAssertNil(step(from: nil, to: night(at(22, 9), [sleep(bedtime)]), now: at(22, 9)).event)
    }

    // MARK: 2. By hand, on this phone: the moment

    func testAHandStartPlaysTheMoment() {
        let awake = night(bedtime.addingTimeInterval(-30), [])
        let down = sleep(bedtime)
        let now = bedtime.addingTimeInterval(0.2)
        let begun = night(now, [down])
        let played = step(from: showing(awake), to: begun, hand: HandStart(sleepID: down.id, at: bedtime), now: now)
        XCTAssertEqual(played.event, .bedtime)
        XCTAssertEqual(played.standing, showing(begun))
    }

    func testAHandStartAfterTheNightHasBegunPlaysNothing() {
        // The 3 am feed: he was put down again with Home's own button. The
        // night began at 7:40; "there is no resettle any more".
        let firstStretch = sleep(bedtime, until: at(22, 3))
        let feeding = night(at(22, 3, 20), [firstStretch])
        let again = sleep(at(22, 3, 25))
        let downAgain = night(at(22, 3, 25, 1), [firstStretch, again])
        let result = step(from: showing(feeding), to: downAgain,
                          hand: HandStart(sleepID: again.id, at: at(22, 3, 25)), now: at(22, 3, 25, 1))
        XCTAssertNil(result.event)
    }

    func testAHandStartedNapPlaysNothing() {
        // 2 pm, by hand: a nap begins no night. ("Naps: the rest pose.")
        let nap = sleep(at(21, 14))
        let result = step(from: showing(night(at(21, 13, 59), [])), to: night(at(21, 14, 0, 1), [nap]),
                          hand: HandStart(sleepID: nap.id, at: at(21, 14)), now: at(21, 14, 0, 1))
        XCTAssertNil(result.event)
    }

    func testATokenOlderThanFiveSecondsIsNoLongerThisTap() {
        // The tap's token is a few seconds' memory, not a flag on the sleep:
        // a night that begins 20 seconds after an unrelated tap began some
        // other way.
        let awake = night(bedtime.addingTimeInterval(-30), [])
        let begun = night(bedtime.addingTimeInterval(1), [sleep(bedtime)])
        let stale = HandStart(sleepID: UUID(), at: bedtime.addingTimeInterval(-20))
        XCTAssertEqual(step(from: showing(awake), to: begun, hand: stale, now: bedtime.addingTimeInterval(1)).event, .arrive)
        let fresh = HandStart(sleepID: UUID(), at: bedtime.addingTimeInterval(-4))
        XCTAssertEqual(step(from: showing(awake), to: begun, hand: fresh, now: bedtime.addingTimeInterval(1)).event, .bedtime)
        // Five seconds, to the twentieth of one: a save that took the whole
        // five still gets the moment, and nothing later does.
        let played = { (age: TimeInterval) -> SkyEvent? in
            let now = self.bedtime.addingTimeInterval(1)
            return self.step(from: self.showing(awake), to: begun,
                             hand: HandStart(sleepID: UUID(), at: now.addingTimeInterval(-age)), now: now).event
        }
        XCTAssertEqual(played(5), .bedtime)
        XCTAssertEqual(played(5.05), .arrive)
    }

    func testATapThatWasUndoneIsNotAHandStart() {
        // The wrong tile at 7:40, undone a second later. Three seconds
        // after the tap the other phone starts the night's sleep. This
        // phone's tap is still fresh by the clock — but it was taken back,
        // and it is not what began the night: a quiet rise, no moment.
        let awake = night(bedtime.addingTimeInterval(1.5), [])
        var taken = HandStart(sleepID: UUID(), at: bedtime)
        taken.undoneAt = bedtime.addingTimeInterval(1)
        let now = bedtime.addingTimeInterval(3)
        let begun = night(now, [sleep(bedtime.addingTimeInterval(2.5))])
        XCTAssertEqual(step(from: showing(awake), to: begun, hand: taken, now: now).event, .arrive)
        // The same tap not taken back would have been the moment's.
        XCTAssertEqual(step(from: showing(awake), to: begun, hand: HandStart(sleepID: UUID(), at: bedtime), now: now).event,
                       .bedtime)
    }

    // MARK: 3. Any other way: a quiet rise, or simply up

    func testANightSleepFromElsewhereJustNowRisesQuietly() {
        // The other phone, Siri, a widget: no hand token here. It started
        // 20 seconds ago and Home is on screen: the quiet rise.
        let awake = night(bedtime.addingTimeInterval(-30), [])
        let now = bedtime.addingTimeInterval(20)
        XCTAssertEqual(step(from: showing(awake), to: night(now, [sleep(bedtime)]), now: now).event, .arrive)
        // The other phone's clock is ahead: the start is 40 s in this
        // phone's future. Still a rise, at once.
        let ahead = night(bedtime, [sleep(bedtime.addingTimeInterval(40))])
        XCTAssertEqual(step(from: showing(awake), to: ahead, now: bedtime).event, .arrive)
    }

    func testALateArrivalDissolves() {
        // A SNOO sleep logged with the bassinet's own start, ten minutes
        // back; or the fetch that lands a few seconds after Home is opened
        // on an evening he has been down for an hour. The night did not
        // begin just now: Home is "simply up", by a 0.6 s dissolve.
        let awake = night(at(21, 19, 49), [])
        let now = at(21, 19, 50)
        XCTAssertEqual(step(from: showing(awake), to: night(now, [sleep(bedtime)]), now: now).event,
                       .dissolve(lookingUp: true))
        // The line is 90 seconds.
        let edge = { (age: TimeInterval) -> SkyEvent? in
            let now = self.bedtime.addingTimeInterval(age)
            return self.step(from: self.showing(awake), to: self.night(now, [self.sleep(self.bedtime)]), now: now).event
        }
        XCTAssertEqual(edge(90), .arrive)
        XCTAssertEqual(edge(91), .dissolve(lookingUp: true))
    }

    func testAnArrivalAlreadyEndedDissolves() {
        // A sync can deliver a sleep's start and its end as one change: an
        // evening catnap on the other phone, 6:05 to 6:06 and a bit, first
        // seen here when it is already over. It began the night (a decision
        // pinned in `NightRuleTests`), but nobody is being put down: no rise.
        let awake = night(at(21, 18, 6), [])
        let now = at(21, 18, 6, 20)
        let over = sleep(at(21, 18, 5), until: at(21, 18, 6, 10))
        let begun = night(now, [over])
        XCTAssertTrue(begun.hasBegun)
        XCTAssertLessThan(now.timeIntervalSince(over.start), SkyScript.arrivalWindow, "inside the 90 seconds, and yet")
        XCTAssertEqual(step(from: showing(awake), to: begun, now: now).event, .dissolve(lookingUp: true))
    }

    func testAnEditThatSwapsTheIDPlaysNothing() {
        // Backdating the running sleep's start by ten minutes replaces the
        // row: new id, new start. The night was begun and is begun.
        let before = night(at(21, 20), [sleep(bedtime)])
        let after = night(at(21, 20, 0, 1), [sleep(bedtime.addingTimeInterval(-600))])
        XCTAssertNotEqual(before.begunBy?.id, after.begunBy?.id)
        let result = step(from: showing(before), to: after, now: at(21, 20, 0, 1))
        XCTAssertNil(result.event)
        XCTAssertEqual(result.standing, showing(after))
        // Even with a hand token around, and even though the "new" sleep
        // started within the 90 seconds.
        let swapped = night(at(21, 19, 40, 30), [sleep(bedtime)])
        let again = night(at(21, 19, 40, 31), [sleep(bedtime.addingTimeInterval(5))])
        XCTAssertNil(step(from: showing(swapped), to: again, hand: HandStart(sleepID: UUID(), at: at(21, 19, 40, 30)),
                          now: at(21, 19, 40, 31)).event)
    }

    // MARK: 4. First light

    func testFirstLightSettles() throws {
        // Home on screen at the minute the sun comes up through −7°, him
        // still asleep: "a quiet settle behind the cards". At once — the
        // clock needs no second look.
        let log = [sleep(bedtime)]
        let frame = try XCTUnwrap(night(at(22, 6), log).frame)
        let before = night(frame.firstLight.addingTimeInterval(-20), log)
        let now = frame.firstLight.addingTimeInterval(40)
        let after = night(now, log)
        XCTAssertTrue(before.hasBegun)
        XCTAssertFalse(after.hasBegun)
        let result = step(from: showing(before), to: after, now: now)
        XCTAssertEqual(result.event, .settle)
        XCTAssertNil(result.askAgainAt)
        XCTAssertEqual(result.standing, showing(after))
        // Awake at first light, the same.
        let up = [sleep(bedtime, until: at(22, 5, 30))]
        XCTAssertEqual(step(from: showing(night(frame.firstLight.addingTimeInterval(-20), up)),
                            to: night(now, up), now: now).event, .settle)
    }

    func testAMorningFoundLongAfterFirstLightOnlyDissolves() throws {
        // The lab plays the settle only while the sun is within half a
        // degree of first light: "a settle at 09:00 would begin from the
        // looked-up pose in daylight". If the sky was not asked again until
        // a quarter of an hour after, the hill dissolves in instead.
        let log = [sleep(bedtime)]
        let frame = try XCTUnwrap(night(at(22, 6), log).frame)
        let before = night(frame.firstLight.addingTimeInterval(-20), log)
        let fiveMinutes = frame.firstLight.addingTimeInterval(5 * 60)
        XCTAssertEqual(step(from: showing(before), to: night(fiveMinutes, log), now: fiveMinutes).event, .settle)
        let late = frame.firstLight.addingTimeInterval(15 * 60)
        XCTAssertEqual(step(from: showing(before), to: night(late, log), now: late).event, .dissolve(lookingUp: false))
        // The line is five minutes — "the first three to five minutes" the
        // lab's half a degree lasts — and not a second more.
        let justOver = frame.firstLight.addingTimeInterval(301)
        XCTAssertEqual(step(from: showing(before), to: night(justOver, log), now: justOver).event,
                       .dissolve(lookingUp: false))
    }

    // MARK: 5. Un-begun: hold, then settle

    func testADeleteSettlesOnlyAfterTheHold() {
        // The other parent deletes tonight's sleep from the timeline. It
        // might be half of an edit, so nothing moves for a second and a
        // half; then, still un-begun, the view settles.
        let begun = night(at(21, 21), [sleep(bedtime)])
        let seen = at(21, 21, 0, 10)
        let gone = night(seen, [])
        let held = step(from: showing(begun), to: gone, now: seen)
        XCTAssertNil(held.event)
        XCTAssertEqual(held.standing.night, begun, "the sky is still showing the night")
        XCTAssertEqual(held.standing.unbegunSince, seen)
        XCTAssertEqual(held.askAgainAt, seen.addingTimeInterval(1.5))

        let early = step(from: held.standing, to: night(seen.addingTimeInterval(1), []), now: seen.addingTimeInterval(1))
        XCTAssertNil(early.event)
        XCTAssertEqual(early.askAgainAt, seen.addingTimeInterval(1.5), "the hold is counted from when it was first seen")

        let due = seen.addingTimeInterval(1.5)
        let settled = step(from: early.standing, to: night(due, []), now: due)
        XCTAssertEqual(settled.event, .settle)
        XCTAssertEqual(settled.standing, showing(night(due, [])))
        XCTAssertNil(settled.askAgainAt)
    }

    func testASplitEditDoesNotSettle() {
        // An edit is a delete and an insert, and a sync can deliver them in
        // two batches: for a moment there is no night sleep in the log.
        // Held, the sky plays nothing at all — no settle, and no rise when
        // the other half lands.
        let begun = night(at(21, 21), [sleep(bedtime)])
        let seen = at(21, 21, 0, 10)
        let held = step(from: showing(begun), to: night(seen, []), now: seen)
        XCTAssertNil(held.event)

        let landed = seen.addingTimeInterval(0.4)
        let edited = night(landed, [sleep(bedtime.addingTimeInterval(-300))])
        let result = step(from: held.standing, to: edited, now: landed)
        XCTAssertNil(result.event)
        XCTAssertEqual(result.standing, showing(edited))
        XCTAssertNil(result.askAgainAt, "the hold is over")
        // And nothing is owed later.
        XCTAssertNil(step(from: result.standing, to: night(seen.addingTimeInterval(2), [sleep(bedtime.addingTimeInterval(-300))]),
                          now: seen.addingTimeInterval(2)).event)
    }

    func testThisPhonesUndoSettlesAtOnce() {
        // Undo on the toast is certain: no hold.
        let down = sleep(bedtime)
        let begun = night(bedtime.addingTimeInterval(4), [down])
        let now = bedtime.addingTimeInterval(4.2)
        var hand = HandStart(sleepID: down.id, at: bedtime)
        hand.undoneAt = bedtime.addingTimeInterval(4.1)
        let result = step(from: showing(begun), to: night(now, []), hand: hand, playedTonight: true, now: now)
        XCTAssertEqual(result.event, .settle)
        XCTAssertNil(result.askAgainAt)
        // A token that was not undone does not skip it.
        XCTAssertNil(step(from: showing(begun), to: night(now, []), hand: HandStart(sleepID: down.id, at: bedtime), now: now).event)
        // Nor does an Undo from longer ago than the token lives: whatever
        // un-begins the night twenty seconds after it is something else,
        // and is held like anything else.
        var old = HandStart(sleepID: UUID(), at: bedtime.addingTimeInterval(-24))
        old.undoneAt = bedtime.addingTimeInterval(-20)
        let later = step(from: showing(begun), to: night(now, []), hand: old, playedTonight: true, now: now)
        XCTAssertNil(later.event)
        XCTAssertEqual(later.askAgainAt, now.addingTimeInterval(SkyScript.unbeginHold))
        // Five seconds is the line here too.
        var justInside = HandStart(sleepID: down.id, at: bedtime)
        justInside.undoneAt = now.addingTimeInterval(-5)
        XCTAssertEqual(step(from: showing(begun), to: night(now, []), hand: justInside, now: now).event, .settle)
        justInside.undoneAt = now.addingTimeInterval(-5.05)
        XCTAssertNil(step(from: showing(begun), to: night(now, []), hand: justInside, now: now).event)
    }

    func testFirstLightDuringAHoldSettlesWithoutWaiting() throws {
        let log = [sleep(bedtime)]
        let frame = try XCTUnwrap(night(at(22, 6), log).frame)
        let seen = frame.firstLight.addingTimeInterval(-1)
        let held = step(from: showing(night(seen.addingTimeInterval(-60), log)), to: night(seen, []), now: seen)
        XCTAssertNil(held.event)
        let now = frame.firstLight.addingTimeInterval(0.2)
        XCTAssertEqual(step(from: held.standing, to: night(now, []), now: now).event, .settle)
    }

    // MARK: 6. Nothing else moves the sky

    func testWakingTheNightFeedAndMidnightPlayNothing() {
        // One standing carried through a whole night's worth of changes
        // that are not the night beginning or ending.
        let firstStretch = sleep(bedtime, until: at(22, 3))
        let moments: [(Date, [SleepSpan])] = [
            (at(21, 20), [sleep(bedtime)]),                               // asleep
            (at(21, 23, 59, 59), [sleep(bedtime)]),
            (at(22, 0, 0, 1), [sleep(bedtime)]),                          // midnight
            (at(22, 3, 0, 5), [firstStretch]),                            // he wakes
            (at(22, 3, 25), [firstStretch, sleep(at(22, 3, 24, 50))]),    // down again, from the other phone
            (at(22, 5, 0), [firstStretch, sleep(at(22, 3, 24, 50), until: at(22, 4, 50))]),
            (at(22, 5, 5), [firstStretch, sleep(at(22, 3, 24, 50), until: at(22, 4, 50)), sleep(at(22, 5, 4))]),
        ]
        var standing = showing(night(at(21, 19, 50), [sleep(bedtime)]))
        for (now, log) in moments {
            let result = step(from: standing, to: night(now, log), now: now)
            XCTAssertNil(result.event, "\(now)")
            XCTAssertNil(result.askAgainAt)
            standing = result.standing
        }
        // By day, a nap coming and going plays nothing either.
        var day = showing(night(at(21, 13), []))
        for (now, log) in [(at(21, 14), [sleep(at(21, 14))]), (at(21, 15), [sleep(at(21, 14), until: at(21, 15))])] {
            let result = step(from: day, to: night(now, log), now: now)
            XCTAssertNil(result.event)
            day = result.standing
        }
    }

    // MARK: 7. Once a night

    /// The driver's whole part, as the script's contract has it: keep the
    /// standing, the hand token and the night the moment was spent on, and
    /// play what a step names.
    private struct Home {
        var standing: SkyScript.Standing?
        var hand: HandStart?
        var playedOn: NightFrame?
        var moment: (began: Date, frame: NightFrame)?
    }

    private func reconcile(_ home: inout Home, _ now: Date, _ log: [SleepSpan]) -> SkyEvent? {
        if let moment = home.moment, SkyScript.momentIsSpent(age: now.timeIntervalSince(moment.began), world: .duo) {
            home.playedOn = moment.frame
            home.moment = nil
        }
        let state = night(now, log)
        let result = SkyScript.step(from: home.standing, to: state, hand: home.hand,
                                    playedTonight: SkyScript.hasPlayed(home.playedOn, tonight: state), now: now)
        home.standing = result.standing
        if result.event == .bedtime, let frame = state.frame { home.moment = (now, frame) }
        if result.event == .settle { home.moment = nil }
        return result.event
    }

    func testUndoThenASecondTapRisesQuietly() {
        // He is put down at 7:40 and the moment plays. Four seconds in —
        // the caption has stood — Undo. Then the button again: "the view
        // rises quietly behind the cards. No veil, no band, no caption, no
        // new star. The full moment plays once a night."
        var home = Home()
        XCTAssertNil(reconcile(&home, bedtime.addingTimeInterval(-60), []))

        let first = sleep(bedtime)
        home.hand = HandStart(sleepID: first.id, at: bedtime)
        XCTAssertEqual(reconcile(&home, bedtime.addingTimeInterval(0.1), [first]), .bedtime)

        home.hand?.undoneAt = bedtime.addingTimeInterval(4)
        XCTAssertEqual(reconcile(&home, bedtime.addingTimeInterval(4.1), []), .settle)

        let second = sleep(bedtime.addingTimeInterval(9))
        home.hand = HandStart(sleepID: second.id, at: second.start)
        XCTAssertEqual(reconcile(&home, bedtime.addingTimeInterval(9.1), [second]), .arrive)
    }

    func testAMisTapUndoneAtOnceDoesNotSpendTheMoment() {
        // The wrong tile, undone after a second: the caption never stood,
        // so the night still has its moment for the real bedtime.
        var home = Home()
        XCTAssertNil(reconcile(&home, bedtime.addingTimeInterval(-60), []))

        let mistake = sleep(bedtime)
        home.hand = HandStart(sleepID: mistake.id, at: bedtime)
        XCTAssertEqual(reconcile(&home, bedtime.addingTimeInterval(0.1), [mistake]), .bedtime)
        home.hand?.undoneAt = bedtime.addingTimeInterval(1)
        XCTAssertEqual(reconcile(&home, bedtime.addingTimeInterval(1.1), []), .settle)

        let real = sleep(bedtime.addingTimeInterval(600))
        home.hand = HandStart(sleepID: real.id, at: real.start)
        XCTAssertEqual(reconcile(&home, real.start.addingTimeInterval(0.1), [real]), .bedtime)

        // "Up" is the moment's own table's: 2.8 s on the Duo and on the
        // slab; under Reduce Motion, whose table is shorter, 1.6 s.
        for world in SkyWorld.Kind.allCases {
            XCTAssertFalse(SkyScript.momentIsSpent(age: 2.7, world: world))
            XCTAssertTrue(SkyScript.momentIsSpent(age: 2.8, world: world))
            XCTAssertEqual(Moment.frame(age: 2.8, world: world).caption, 1, accuracy: 1e-6,
                           "spent as the line is fully lit, not before")
            XCTAssertFalse(SkyScript.momentIsSpent(age: 1.5, world: world, reduced: true))
            XCTAssertTrue(SkyScript.momentIsSpent(age: 1.6, world: world, reduced: true))
            XCTAssertEqual(Moment.frame(age: 1.6, world: world, reduced: true).caption, 1, accuracy: 1e-6)
        }
    }

    func testTheMomentIsSpentForTonightOnly() throws {
        let tonight = night(at(21, 21), [sleep(bedtime)])
        let frame = try XCTUnwrap(tonight.frame)
        XCTAssertTrue(SkyScript.hasPlayed(frame, tonight: tonight))
        XCTAssertTrue(SkyScript.hasPlayed(frame, tonight: night(at(22, 3), [])), "after midnight it is the same night")
        XCTAssertFalse(SkyScript.hasPlayed(nil, tonight: tonight))
        let tomorrow = night(at(22, 19, 40), [sleep(at(22, 19, 40))])
        XCTAssertFalse(SkyScript.hasPlayed(frame, tonight: tomorrow), "tomorrow night has its own")
        XCTAssertFalse(SkyScript.hasPlayed(frame, tonight: night(at(22, 12), [])), "by day there is no tonight")
    }

    // MARK: A whole night

    func testOneNightFromBedtimeToFirstLight() throws {
        // Home stays on screen from the evening to the morning, asked once
        // a minute as its minute clock would, and at each change of the
        // log. The whole night plays exactly two events: the moment at
        // bedtime, and the settle at first light.
        var home = Home()
        let down = sleep(bedtime)
        let firstStretch = SleepSpan(id: down.id, start: bedtime, end: at(22, 3))
        let again = sleep(at(22, 3, 25))
        func log(_ now: Date) -> [SleepSpan] {
            if now < bedtime { return [] }
            if now < at(22, 3) { return [down] }
            if now < at(22, 3, 25) { return [firstStretch] }
            return [firstStretch, again]
        }
        var played: [(Date, SkyEvent)] = []
        var now = at(21, 17)
        while now <= at(22, 8) {
            if now == bedtime { home.hand = HandStart(sleepID: down.id, at: bedtime) }
            if now == at(22, 3, 25) { home.hand = HandStart(sleepID: again.id, at: now) }
            if let event = reconcile(&home, now, log(now)) { played.append((now, event)) }
            now = now.addingTimeInterval(60)
        }
        XCTAssertEqual(played.map(\.1), [.bedtime, .settle])
        XCTAssertEqual(played.first?.0, bedtime)
        let frame = try XCTUnwrap(night(at(22, 3), log(at(22, 3))).frame)
        let settled = try XCTUnwrap(played.last?.0)
        XCTAssertGreaterThanOrEqual(settled, frame.firstLight)
        XCTAssertLessThan(settled.timeIntervalSince(frame.firstLight), 60, "at the first minute past first light: 6:13")
    }
}

import XCTest
@testable import TwoOfUs

/// "The night has begun" (`NightRule`), case by case from the design brief
/// (design/sky-lab/BRIEF.md, "The night lasts until first light" and
/// "Signed off"), then minute by minute against the sky lab's own answers
/// (`SkyCoreFixturesNight.labNightHours`, exported from lab/core.js).
///
/// The household is in Chicago, the lab's stand-in: every date is built with
/// a calendar in America/Chicago, so 6 pm and 4 am are that city's, on the
/// nights the clocks change too.
final class NightRuleTests: XCTestCase {
    private let chicago = SkyPlace(latitude: 41.8781, longitude: -87.6298)

    private var chicagoTime: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0, _ s: Int = 0) -> Date {
        chicagoTime.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))!
    }

    /// The time on Chicago's clock, "06:12". (Read as plain numbers, not
    /// compared as `DateComponents`: what else a calendar fills in on those
    /// is not the same on every platform.)
    private func clock(_ date: Date) -> String {
        String(format: "%02d:%02d", chicagoTime.component(.hour, from: date),
               chicagoTime.component(.minute, from: date))
    }

    private func sleep(_ start: Date, until end: Date? = nil, id: UUID = UUID()) -> SleepSpan {
        SleepSpan(id: id, start: start, end: end)
    }

    private func night(_ now: Date, _ sleeps: [SleepSpan], policy: NightRule.Policy = .signedOff) -> NightState {
        NightRule.state(at: now, sleeps: sleeps, place: chicago, policy: policy, calendar: chicagoTime)
    }

    private func labInstant(_ label: String, file: StaticString = #filePath, line: UInt = #line) throws -> Date {
        let row = try XCTUnwrap(SkyCoreFixture.rows(SkyCoreFixturesNight.sunRises)
            .first { $0[0] == label }, "no fixture row \(label)", file: file, line: line)
        return Date(timeIntervalSince1970: SkyCoreFixture.number(row[5]) / 1000)
    }

    // MARK: What begins the night

    func testASevenFortyBedtimeBeginsTheNight() throws {
        // 21 November 2026, the lab's default day: down at 7:40 pm.
        let bedtime = sleep(at(2026, 11, 21, 19, 40))
        XCTAssertFalse(night(at(2026, 11, 21, 19, 39), []).hasBegun, "a minute before, nothing has")

        let state = night(at(2026, 11, 21, 19, 40), [bedtime])
        XCTAssertTrue(state.hasBegun)
        XCTAssertEqual(state.begunBy, bedtime)
        XCTAssertEqual(state.running, .night)

        // The night's frame: from 6 pm, welcoming a first sleep until 4 am,
        // over at first light — the lab's 06:12:14 the next morning.
        let frame = try XCTUnwrap(state.frame)
        XCTAssertEqual(frame.evening, at(2026, 11, 21, 18))
        XCTAssertEqual(frame.lastStart, at(2026, 11, 22, 4))
        XCTAssertEqual(frame.firstLight.timeIntervalSince1970,
                       try labInstant("chicago-first-light-22-nov-2026").timeIntervalSince1970, accuracy: 1)
    }

    func testASevenFortyBedtimeBeginsTheNightInJulyBeforeSunset() {
        // Signed off, item 2: "Summer evenings: look up anyway." On 15 July
        // the sun is still eight degrees up at 7:40 pm, and the night begins
        // all the same. The view is not held back until sunset.
        let bedtime = at(2027, 7, 15, 19, 40)
        XCTAssertGreaterThan(SolarClock.altitudeInDegrees(at: bedtime, latitude: chicago.latitude,
                                                 longitude: chicago.longitude), 5, "the sun is up")
        let state = night(bedtime, [sleep(bedtime)])
        XCTAssertTrue(state.hasBegun)
        XCTAssertEqual(state.running, .night)
        XCTAssertEqual(state.frame?.evening, at(2027, 7, 15, 18))
    }

    func testAFiveAMSleepDoesNot() {
        // "A night sleep is one begun between 6 pm and 4 am." It is still
        // dark at 5 am in November — the night's hours run on to first
        // light — but a sleep begun then is the morning's, and dims the room
        // as a nap does.
        let early = sleep(at(2026, 11, 22, 5))
        let state = night(at(2026, 11, 22, 5, 10), [early])
        XCTAssertNotNil(state.frame, "5:10 am is before first light")
        XCTAssertFalse(state.hasBegun)
        XCTAssertEqual(state.running, .nap)

        // The line is 4 am to the minute.
        XCTAssertTrue(night(at(2026, 11, 22, 4, 30), [sleep(at(2026, 11, 22, 3, 59))]).hasBegun)
        XCTAssertFalse(night(at(2026, 11, 22, 4, 30), [sleep(at(2026, 11, 22, 4, 0))]).hasBegun)
    }

    func testAnAfternoonNapIsNotTheNight() {
        let nap = sleep(at(2026, 11, 21, 14))
        let state = night(at(2026, 11, 21, 14, 30), [nap])
        XCTAssertNil(state.frame, "half past two is the day")
        XCTAssertFalse(state.hasBegun)
        XCTAssertEqual(state.running, .nap)
    }

    func testAnEveningCatnapBeginsTheNight() {
        // A DECISION TO PUT TO THE OWNER (the plan's decision 2), pinned so
        // that it cannot change by accident: the rule goes by when a sleep
        // began and nothing else, so a 6:05 pm catnap is "tonight's night
        // sleep first starting". Home looks up from then on, and the real
        // bedtime at 7:40 finds the night already begun.
        let catnap = sleep(at(2026, 11, 21, 18, 5), until: at(2026, 11, 21, 18, 40))
        let awake = night(at(2026, 11, 21, 18, 50), [catnap])
        XCTAssertTrue(awake.hasBegun)
        XCTAssertEqual(awake.begunBy, catnap)
        XCTAssertNil(awake.running)

        let bedtime = sleep(at(2026, 11, 21, 19, 40))
        let down = night(at(2026, 11, 21, 19, 41), [bedtime, catnap])
        XCTAssertEqual(down.begunBy, catnap, "the night began with the catnap, not with bedtime")
        XCTAssertEqual(down.running, .night)
    }

    func testABedtimeTenMinutesBeforeSixNeverBeginsTheNight() {
        // The other side of the same line, and open with the owner too (the
        // plan's decision 3): down at 5:50 pm and asleep all night, Home
        // stays on the hill, dimmed. Nothing here guesses that a long
        // late-afternoon sleep "became" the night.
        let early = sleep(at(2026, 11, 21, 17, 50))
        for now in [at(2026, 11, 21, 18, 30), at(2026, 11, 21, 23, 0), at(2026, 11, 22, 3, 0)] {
            let state = night(now, [early])
            XCTAssertNotNil(state.frame)
            XCTAssertFalse(state.hasBegun)
            XCTAssertEqual(state.running, .nap)
        }
    }

    func testAFastClockStillBeginsTheNight() {
        // The other phone's clock runs 40 seconds ahead of this one, so the
        // sleep it has just started is, by this clock, in the future. The
        // sleep card is already counting it; the sky looks up at once too.
        let now = at(2026, 11, 21, 19, 40)
        let ahead = sleep(now.addingTimeInterval(40))
        let state = night(now, [ahead])
        XCTAssertTrue(state.hasBegun)
        XCTAssertEqual(state.begunBy, ahead)
        XCTAssertEqual(state.running, .night)
    }

    // MARK: What does not move it

    func testANightFeedMovesNothing() {
        // "He wakes at 3 a.m.: the view stays up, the star stays in its
        // window. He is put down again." Ended sleeps count exactly as
        // running ones do, so the night is the same night throughout: same
        // frame, begun by the same sleep.
        let bedtime = at(2026, 11, 21, 19, 40)
        let asleep = night(at(2026, 11, 22, 2, 59), [sleep(bedtime)])
        let firstStretch = sleep(bedtime, until: at(2026, 11, 22, 3, 0))
        let feeding = night(at(2026, 11, 22, 3, 10), [firstStretch])
        let downAgain = night(at(2026, 11, 22, 3, 26), [firstStretch, sleep(at(2026, 11, 22, 3, 25))])

        for state in [asleep, feeding, downAgain] {
            XCTAssertTrue(state.hasBegun)
            XCTAssertEqual(state.begunBy?.start, bedtime)
            XCTAssertEqual(state.frame, asleep.frame)
        }
        // Only the room changes: un-dimmed while he feeds, dimmed again.
        XCTAssertEqual(asleep.running, .night)
        XCTAssertNil(feeding.running)
        XCTAssertEqual(downAgain.running, .night)
    }

    func testMidnightChangesNothing() {
        let bedtime = sleep(at(2026, 11, 21, 19, 40))
        let before = night(at(2026, 11, 21, 23, 59, 59), [bedtime])
        let after = night(at(2026, 11, 22, 0, 0, 1), [bedtime])
        XCTAssertTrue(before.hasBegun)
        XCTAssertEqual(before, after)
        XCTAssertEqual(after.frame?.evening, at(2026, 11, 21, 18), "still yesterday evening's night")
    }

    func testASleepEditedSoItsIDChangesIsTheSameNight() {
        // Editing a sleep soft-deletes its row and inserts a new one under a
        // new id (`EventStore.editSleep`). The derived fact does not notice.
        let start = at(2026, 11, 21, 19, 40)
        let original = night(at(2026, 11, 21, 21, 0), [sleep(start)])
        let edited = night(at(2026, 11, 21, 21, 0), [sleep(start)])
        XCTAssertNotEqual(original.begunBy?.id, edited.begunBy?.id)
        XCTAssertEqual(original.hasBegun, edited.hasBegun)
        XCTAssertEqual(original.frame, edited.frame)
        XCTAssertEqual(original.begunBy?.start, edited.begunBy?.start)
        XCTAssertEqual(original.running, edited.running)

        // Nor when the edit moves the start to another minute of the evening.
        let moved = night(at(2026, 11, 21, 21, 0), [sleep(at(2026, 11, 21, 19, 25))])
        XCTAssertTrue(moved.hasBegun)
        XCTAssertEqual(moved.frame, original.frame)
    }

    func testADeletedSleepUnBeginsTheNight() {
        // Undo, or a delete in the timeline: the row is gone from the live
        // log, and with it the night's beginning. (It is still the night's
        // hours; nothing has begun in them.)
        let bedtime = sleep(at(2026, 11, 21, 19, 40))
        XCTAssertTrue(night(at(2026, 11, 21, 19, 41), [bedtime]).hasBegun)
        let undone = night(at(2026, 11, 21, 19, 41), [])
        XCTAssertFalse(undone.hasBegun)
        XCTAssertNotNil(undone.frame)
        XCTAssertNil(undone.running)

        // Moving its start back before 6 pm un-begins it just the same.
        XCTAssertFalse(night(at(2026, 11, 21, 19, 41), [sleep(at(2026, 11, 21, 17, 55))]).hasBegun)
    }

    func testLastNightsSleepDoesNotBeginTonight() {
        let lastNight = sleep(at(2026, 11, 20, 19, 40), until: at(2026, 11, 21, 6, 40))
        let state = night(at(2026, 11, 21, 18, 30), [lastNight])
        XCTAssertEqual(state.frame?.evening, at(2026, 11, 21, 18))
        XCTAssertFalse(state.hasBegun)
    }

    // MARK: What ends it

    func testFirstLightEndsTheNight() throws {
        // "First light brings the view down." He is still asleep: a second
        // before the sun comes up through −7° the night has begun; a second
        // after, it is the day — the day's picture, dimmed.
        let bedtime = sleep(at(2026, 11, 21, 19, 40))
        let firstLight = try labInstant("chicago-first-light-22-nov-2026")
        XCTAssertEqual(clock(firstLight), "06:12")

        let before = night(firstLight.addingTimeInterval(-2), [bedtime])
        XCTAssertTrue(before.hasBegun)
        let after = night(firstLight.addingTimeInterval(2), [bedtime])
        XCTAssertFalse(after.hasBegun)
        XCTAssertNil(after.frame)
        XCTAssertEqual(after.running, .night, "the sleep is still the night's, for the room's dimming")
        // And it does not begin again that day.
        XCTAssertFalse(night(at(2026, 11, 22, 12), [bedtime]).hasBegun)
    }

    func testAtFirstLightItselfTheNightIsOver() throws {
        // The night's hours run from the evening up to, and not including,
        // first light: 6 pm on the dot is the night's, and the instant of
        // first light is already the day's.
        let frame = try XCTUnwrap(NightRule.frame(ofNightOn: at(2026, 11, 21, 12), place: chicago,
                                                  calendar: chicagoTime))
        XCTAssertFalse(frame.contains(frame.evening.addingTimeInterval(-1)))
        XCTAssertTrue(frame.contains(frame.evening))
        XCTAssertTrue(frame.contains(frame.firstLight.addingTimeInterval(-1)))
        XCTAssertFalse(frame.contains(frame.firstLight))

        let bedtime = sleep(at(2026, 11, 21, 19, 40))
        XCTAssertEqual(night(frame.evening, []).frame, frame)
        XCTAssertTrue(night(frame.firstLight.addingTimeInterval(-1), [bedtime]).hasBegun)
        let atFirstLight = night(frame.firstLight, [bedtime])
        XCTAssertNil(atFirstLight.frame)
        XCTAssertFalse(atFirstLight.hasBegun)
    }

    func testInJuneFirstLightComesBeforeFour() throws {
        // 21 June: first light is 04:34:12, so 4 am still closes the
        // welcome; but a place whose first light came at 3:30 would close it
        // then (`lastStart` is whichever is sooner).
        let frame = try XCTUnwrap(NightRule.frame(ofNightOn: at(2027, 6, 20, 12), place: chicago,
                                                  calendar: chicagoTime))
        XCTAssertEqual(frame.firstLight.timeIntervalSince1970,
                       try labInstant("chicago-first-light-21-jun-2027").timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(frame.lastStart, at(2027, 6, 21, 4))

        var stockholmTime = Calendar(identifier: .gregorian)
        stockholmTime.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        let noon = stockholmTime.date(from: DateComponents(year: 2027, month: 6, day: 20, hour: 12))!
        let north = try XCTUnwrap(NightRule.frame(ofNightOn: noon,
                                                  place: SkyPlace(latitude: 59.3293, longitude: 18.0686),
                                                  calendar: stockholmTime))
        XCTAssertEqual(north.firstLight.timeIntervalSince1970,
                       try labInstant("stockholm-first-light-21-jun-2027").timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(north.lastStart, north.firstLight, "first light, about 01:19, comes before 4 am")
        XCTAssertLessThan(north.firstLight, stockholmTime.date(from: DateComponents(year: 2027, month: 6, day: 21, hour: 2))!)
    }

    func testWhereTheSunGivesNoFirstLightTheNightEndsAtFour() throws {
        var osloTime = Calendar(identifier: .gregorian)
        osloTime.timeZone = TimeZone(identifier: "Europe/Oslo")!
        func oslo(_ y: Int, _ m: Int, _ d: Int, _ h: Int) -> Date {
            osloTime.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
        }
        // Bergen at midsummer never gets as dark as −7°…
        let bergen = SkyPlace(latitude: 60.3913, longitude: 5.3221)
        let summer = try XCTUnwrap(NightRule.frame(ofNightOn: oslo(2027, 6, 20, 12), place: bergen, calendar: osloTime))
        XCTAssertEqual(summer.evening, oslo(2027, 6, 20, 18))
        XCTAssertEqual(summer.firstLight, oslo(2027, 6, 21, 4))
        XCTAssertEqual(summer.lastStart, oslo(2027, 6, 21, 4))
        // …and Longyearbyen at midwinter never as light. Either way a
        // bedtime still begins a night, and it is over by breakfast.
        let longyearbyen = SkyPlace(latitude: 78.2232, longitude: 15.6267)
        let winter = try XCTUnwrap(NightRule.frame(ofNightOn: oslo(2026, 12, 21, 12), place: longyearbyen, calendar: osloTime))
        XCTAssertEqual(winter.firstLight, oslo(2026, 12, 22, 4))

        let bedtime = SleepSpan(id: UUID(), start: oslo(2027, 6, 20, 20), end: nil)
        let late = NightRule.state(at: oslo(2027, 6, 21, 3), sleeps: [bedtime], place: bergen, calendar: osloTime)
        XCTAssertTrue(late.hasBegun)
        let morning = NightRule.state(at: oslo(2027, 6, 21, 5), sleeps: [bedtime], place: bergen, calendar: osloTime)
        XCTAssertFalse(morning.hasBegun)
    }

    func testANightNeverRunsPastTheNextEvening() throws {
        // Each night is over before the next one's evening, whatever the
        // sun does. The one way it can try is a place whose sun is nowhere
        // near the clock's: the pin in Bergen, the phone on Chicago's time
        // for a week. By Chicago's clock Bergen's summer sun is lowest at
        // about a quarter to seven in the evening. On 6 July 2027 it does
        // not get under −7° at all; on the 7th it does, just, and comes
        // back up through it at 18:55 — twenty-five hours after the evening
        // of the 6th. That is not the night of the 6th's first light. With
        // none of its own, that night ends by the clock, at four.
        let bergen = SkyPlace(latitude: 60.3913, longitude: 5.3221)
        let evening = at(2027, 7, 6, 18)
        let nextRise = try XCTUnwrap(SolarClock.rises(through: -7, after: evening, latitude: bergen.latitude,
                                                      longitude: bergen.longitude))
        XCTAssertEqual(clock(nextRise), "18:55")
        XCTAssertGreaterThan(nextRise.timeIntervalSince(evening), 24 * 3600)

        let frame = try XCTUnwrap(NightRule.frame(ofNightOn: at(2027, 7, 6, 12), place: bergen,
                                                  calendar: chicagoTime))
        XCTAssertEqual(frame.evening, evening)
        XCTAssertEqual(frame.firstLight, at(2027, 7, 7, 4))
        XCTAssertEqual(frame.lastStart, at(2027, 7, 7, 4))
        // So the two nights do not overlap, and at seven the next evening
        // it is the night of the 7th, not still the night of the 6th.
        let next = try XCTUnwrap(NightRule.frame(ofNightOn: at(2027, 7, 7, 12), place: bergen,
                                                 calendar: chicagoTime))
        XCTAssertLessThanOrEqual(frame.firstLight, next.evening)
        XCTAssertNil(NightRule.frame(containing: at(2027, 7, 7, 12), place: bergen, calendar: chicagoTime))
        XCTAssertEqual(NightRule.frame(containing: at(2027, 7, 7, 18, 30), place: bergen,
                                       calendar: chicagoTime)?.evening, at(2027, 7, 7, 18))
    }

    // MARK: The nights the clocks change

    func testTheNightTheClocksGoBack() throws {
        // 7 November 2027, Chicago: 2 am becomes 1 am. The evening is still
        // 6 pm and the last start still 4 am by the clock on the wall, so
        // this night's welcome is eleven hours long, not ten.
        let frame = try XCTUnwrap(NightRule.frame(ofNightOn: at(2027, 11, 6, 12), place: chicago, calendar: chicagoTime))
        XCTAssertEqual(frame.evening, at(2027, 11, 6, 18))
        XCTAssertEqual(frame.lastStart, at(2027, 11, 7, 4))
        XCTAssertEqual(frame.lastStart.timeIntervalSince(frame.evening), 11 * 3600, accuracy: 0.5)
        XCTAssertEqual(frame.firstLight.timeIntervalSince1970,
                       try labInstant("chicago-first-light-7-nov-2027").timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(clock(frame.firstLight), "05:54", "standard time again")

        // A sleep begun in the hour that happens twice (the second 1:30)
        // begins the night; so does one at 3:30, ten and a half hours after
        // the evening; one at 4:06 does not.
        let secondOneThirty = frame.evening.addingTimeInterval(8.5 * 3600)
        XCTAssertEqual(clock(secondOneThirty), "01:30")
        XCTAssertTrue(night(secondOneThirty, [sleep(secondOneThirty)]).hasBegun)
        XCTAssertTrue(night(at(2027, 11, 7, 3, 45), [sleep(frame.evening.addingTimeInterval(10.5 * 3600))]).hasBegun)
        XCTAssertFalse(night(at(2027, 11, 7, 4, 10), [sleep(at(2027, 11, 7, 4, 6))]).hasBegun)
        // A bedtime before the change is the same night after it.
        let bedtime = sleep(at(2027, 11, 6, 19, 40))
        XCTAssertEqual(night(at(2027, 11, 7, 0, 30), [bedtime]), night(at(2027, 11, 7, 3, 0), [bedtime]))
    }

    func testTheNightTheClocksGoForward() throws {
        // 14 March 2027: 2 am becomes 3 am, and the welcome is nine hours.
        let frame = try XCTUnwrap(NightRule.frame(ofNightOn: at(2027, 3, 13, 12), place: chicago, calendar: chicagoTime))
        XCTAssertEqual(frame.evening, at(2027, 3, 13, 18))
        XCTAssertEqual(frame.lastStart, at(2027, 3, 14, 4))
        XCTAssertEqual(frame.lastStart.timeIntervalSince(frame.evening), 9 * 3600, accuracy: 0.5)
        XCTAssertEqual(frame.firstLight.timeIntervalSince1970,
                       try labInstant("chicago-first-light-14-mar-2027").timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(clock(frame.firstLight), "06:32", "daylight time already")

        // Half past three by the new clock begins the night; half past four
        // does not, though it is only nine and a half hours after 6 pm.
        XCTAssertTrue(night(at(2027, 3, 14, 3, 40), [sleep(at(2027, 3, 14, 3, 30))]).hasBegun)
        let late = frame.evening.addingTimeInterval(9.5 * 3600)
        XCTAssertEqual(clock(late), "04:30")
        XCTAssertFalse(night(late.addingTimeInterval(60), [sleep(late)]).hasBegun)
        // An ordinary night is ten hours.
        let ordinary = try XCTUnwrap(NightRule.frame(ofNightOn: at(2026, 11, 21, 12), place: chicago, calendar: chicagoTime))
        XCTAssertEqual(ordinary.lastStart.timeIntervalSince(ordinary.evening), 10 * 3600, accuracy: 0.5)
    }

    // MARK: The hours are the owner's

    func testThePolicyHoldsTheHours() {
        XCTAssertEqual(NightRule.Policy.signedOff.evening, 18 * 60)
        XCTAssertEqual(NightRule.Policy.signedOff.lastStart, 4 * 60)
        XCTAssertEqual(NightRule.Policy.signedOff.firstLightDegrees, -7)

        // Moved to 7 pm and 5 am, the same log reads differently.
        var later = NightRule.Policy.signedOff
        later.evening = 19 * 60
        later.lastStart = 5 * 60
        let halfSix = sleep(at(2026, 11, 21, 18, 30))
        XCTAssertTrue(night(at(2026, 11, 21, 20), [halfSix]).hasBegun)
        XCTAssertFalse(night(at(2026, 11, 21, 20), [halfSix], policy: later).hasBegun)
        let halfFour = sleep(at(2026, 11, 22, 4, 30))
        XCTAssertFalse(night(at(2026, 11, 22, 4, 40), [halfFour]).hasBegun)
        XCTAssertTrue(night(at(2026, 11, 22, 4, 40), [halfFour], policy: later).hasBegun)
    }

    func testTheWelcomeMayEndBeforeMidnight() throws {
        // Nothing says the last start has to be after midnight. Were the
        // owner to close the welcome at 11 pm, a night sleep would be one
        // begun between 6 pm and 11 pm of the same evening — and a sleep
        // begun at 1 am, or at five to four, would be neither the night's
        // beginning nor the night's sleep.
        var early = NightRule.Policy.signedOff
        early.lastStart = 23 * 60
        let cases: [(Int, Int, Bool)] = [(17, 59, false), (18, 0, true), (22, 59, true), (23, 0, false),
                                         (0, 0, false), (1, 0, false), (3, 55, false), (14, 0, false)]
        for (hour, minute, expected) in cases {
            XCTAssertEqual(NightRule.isNightSleep(start: at(2026, 11, 21, hour, minute), policy: early,
                                                  calendar: chicagoTime),
                           expected, "\(hour):\(minute)")
        }
        let frame = try XCTUnwrap(NightRule.frame(ofNightOn: at(2026, 11, 21, 12), place: chicago,
                                                  policy: early, calendar: chicagoTime))
        XCTAssertEqual(frame.evening, at(2026, 11, 21, 18))
        XCTAssertEqual(frame.lastStart, at(2026, 11, 21, 23), "eleven that same evening, not the next one")
        XCTAssertEqual(clock(frame.firstLight), "06:12", "first light is the sun's, whatever the welcome")

        XCTAssertTrue(night(at(2026, 11, 21, 22, 45), [sleep(at(2026, 11, 21, 22, 30))], policy: early).hasBegun)
        let small = night(at(2026, 11, 22, 1, 30), [sleep(at(2026, 11, 22, 1, 0))], policy: early)
        XCTAssertNotNil(small.frame, "half past one is still the night's hours")
        XCTAssertFalse(small.hasBegun)
        XCTAssertEqual(small.running, .nap)
    }

    func testANightSleepIsOneBegunBetweenSixAndFour() {
        let cases: [(Int, Int, Bool)] = [(17, 59, false), (18, 0, true), (19, 40, true), (23, 59, true),
                                         (0, 0, true), (3, 59, true), (4, 0, false), (5, 0, false), (14, 0, false)]
        for (hour, minute, expected) in cases {
            XCTAssertEqual(NightRule.isNightSleep(start: at(2026, 11, 21, hour, minute), calendar: chicagoTime),
                           expected, "\(hour):\(minute)")
        }
    }

    // MARK: Against the lab, minute by minute

    /// One exported day of the lab's answers.
    private struct LabDay {
        let year: Int, month: Int, day: Int
        let tz: Double
        let place: SkyPlace
        let bedtime: Int, wake: Int
        let hours: [Bool], begunAwake: [Bool], begunAsleepNight: [Bool]
    }

    private func labDays() -> [LabDay] {
        SkyCoreFixture.rows(SkyCoreFixturesNight.labNightHours).map { row in
            let ymd = row[0].split(separator: "-").map { Int($0) ?? 0 }
            let bits = { (cell: String) in cell.map { $0 == "1" } }
            return LabDay(year: ymd[0], month: ymd[1], day: ymd[2], tz: SkyCoreFixture.number(row[1]),
                          place: SkyPlace(latitude: SkyCoreFixture.number(row[2]),
                                          longitude: SkyCoreFixture.number(row[3])),
                          bedtime: Int(SkyCoreFixture.number(row[4])), wake: Int(SkyCoreFixture.number(row[5])),
                          hours: bits(row[6]), begunAwake: bits(row[7]), begunAsleepNight: bits(row[8]))
        }
    }

    /// Runs `body` for every minute of every exported day and returns the
    /// minutes it objects to, so a broken rule fails once with a list rather
    /// than thirteen thousand times.
    private func sweep(_ body: (LabDay, Int, Date, Date?) -> String?) -> [String] {
        var complaints: [String] = []
        let days = labDays()
        XCTAssertEqual(days.count, 9)
        for day in days {
            XCTAssertEqual(day.hours.count, 1440)
            let noon = at(day.year, day.month, day.day, 12)
            XCTAssertEqual(Double(chicagoTime.timeZone.secondsFromGMT(for: noon)), day.tz * 3600,
                           "the lab's fixed offset is Chicago's own on \(day.year)-\(day.month)-\(day.day)")
            let sunset = SolarClock.day(containing: noon, latitude: day.place.latitude,
                                        longitude: day.place.longitude, calendar: chicagoTime)?.sunset
            for minute in 0..<1440 {
                let now = at(day.year, day.month, day.day, minute / 60, minute % 60)
                if let complaint = body(day, minute, now, sunset) {
                    complaints.append("\(day.year)-\(day.month)-\(day.day) \(minute / 60):\(minute % 60) \(complaint)")
                }
            }
        }
        return complaints
    }

    func testTheNightsHoursAreTheLabsExceptThatTheEveningIsAlwaysSix() {
        // lab/core.js `nightHours`: from the evening until the sun comes up
        // through −7°. The app's frame is the same hours on every minute of
        // nine days, with ONE deliberate difference: in the lab the evening
        // starts at sunset where that is before 6 pm (16:27 on 21 November),
        // and here it is 6 pm all year — "the 6 pm rule stands". Between a
        // winter sunset and 6 pm the lab says night and the app says day.
        var disagreements = 0
        let complaints = sweep { day, minute, now, sunset in
            let app = NightRule.frame(containing: now, place: day.place, calendar: chicagoTime) != nil
            let lab = day.hours[minute]
            if let sunset, now > sunset, minute < 18 * 60 {
                disagreements += 1
                return lab && !app ? nil : "between sunset and six: lab \(lab), app \(app)"
            }
            return app == lab ? nil : "lab \(lab), app \(app)"
        }
        XCTAssertEqual(complaints, [])
        // 93 + 97 + 57 + 12 minutes: 21 Nov, 21 Dec, 31 Jan and 31 Oct.
        XCTAssertEqual(disagreements, 259, "the minutes between sunset and 6 pm on the four winter days")
    }

    func testWithTheLabsSampleBedtimeInTheLogTheNightBeginsWhenTheLabSays() {
        // The lab has no sleep log: awake, it takes the night to have begun
        // once its sample day's 20:10 bedtime has passed (`SAMPLE_NIGHT`,
        // `nightHasBegun`). Give the app that sample night as real sleeps —
        // down at 20:10, up at 06:40, every night — and the two agree on
        // every minute, with no exception: before 20:10 nothing has begun,
        // from 20:10 it has, and it lasts until first light, not until he
        // wakes.
        let complaints = sweep { day, minute, now, _ in
            let midnight = at(day.year, day.month, day.day, 0)
            let down = { (offset: Int) in
                self.chicagoTime.date(byAdding: .minute, value: day.bedtime,
                                      to: self.chicagoTime.date(byAdding: .day, value: offset, to: midnight)!)!
            }
            let up = { (offset: Int) in
                self.chicagoTime.date(byAdding: .minute, value: day.wake,
                                      to: self.chicagoTime.date(byAdding: .day, value: offset, to: midnight)!)!
            }
            // The log as it stands at this minute: nothing from the future.
            let log = [SleepSpan(id: UUID(), start: down(-1), end: up(0)),
                       SleepSpan(id: UUID(), start: down(0), end: nil)].filter { $0.start <= now }
            let app = NightRule.state(at: now, sleeps: log, place: day.place, calendar: chicagoTime).hasBegun
            let lab = day.begunAwake[minute]
            return app == lab ? nil : "lab \(lab), app \(app)"
        }
        XCTAssertEqual(complaints, [])
    }

    func testASleepBegunThisMinuteBeginsTheNightWhenTheLabSaysExceptBeforeSixAndAfterFour() {
        // The lab's `asleep=night`: a night sleep is running, so the night
        // has begun whenever it is night hours. The app's nearest question
        // is "a sleep begun this very minute". They agree on every minute
        // except the two the design decided otherwise:
        //  - between a winter sunset and 6 pm (no "sunset if earlier");
        //  - from 4 am until first light (BRIEF: "between 6 pm and 4 am";
        //    the lab has no 4 am end).
        var beforeSix = 0, afterFour = 0
        let complaints = sweep { day, minute, now, sunset in
            let state = NightRule.state(at: now, sleeps: [SleepSpan(id: UUID(), start: now, end: nil)],
                                        place: day.place, calendar: chicagoTime)
            let lab = day.begunAsleepNight[minute]
            if let sunset, now > sunset, minute < 18 * 60 {
                beforeSix += 1
                return lab && !state.hasBegun ? nil : "between sunset and six: lab \(lab), app \(state.hasBegun)"
            }
            if minute >= 4 * 60, minute < 12 * 60, state.frame != nil {
                afterFour += 1
                return lab && !state.hasBegun ? nil : "after four: lab \(lab), app \(state.hasBegun)"
            }
            return state.hasBegun == lab ? nil : "lab \(lab), app \(state.hasBegun)"
        }
        XCTAssertEqual(complaints, [])
        XCTAssertEqual(beforeSix, 259)
        XCTAssertGreaterThan(afterFour, 9 * 30, "every day has more than half an hour between 4 am and first light")
    }
}

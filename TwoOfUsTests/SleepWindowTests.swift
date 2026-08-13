import XCTest
@testable import TwoOfUs

/// Pure-logic tests for parent sleep windows: the wall-clock window itself
/// (midnight wrap), `NightSchedule` routing feeds to the awake parent (or,
/// when both are asleep, the one whose planned wake-up comes soonest), and
/// `ScheduleEngine` materializing windows as timeline spans that never ring,
/// never match logged events, and never go "overdue". No store, no CloudKit —
/// pinned calendar and `now`, same idiom as the sibling engine tests.
final class SleepWindowTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        return c
    }()

    private let taylorID = UUID()
    private let katieID = UUID()

    private var parents: [NightSchedule.Parent] {
        [NightSchedule.Parent(id: taylorID, name: "Taylor", colorHex: "#AABBCC"),
         NightSchedule.Parent(id: katieID, name: "Katie", colorHex: "#112233")]
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    /// Night 9pm–8am, spacing 4h, alternating with the roster's first parent
    /// (Taylor) on first shift — same worked example as NightScheduleTests.
    private func schedule(
        feeds: [FeedEvent] = [], overrides: [PlanOverride] = [],
        windows: [SleepWindow] = [], now: Date
    ) -> NightSchedule {
        NightSchedule(nightStartMinute: 21 * 60, nightEndMinute: 8 * 60,
                      spacingMinutes: 240,
                      rotation: .alternating, firstShiftID: nil,
                      parents: parents, feeds: feeds, overrides: overrides,
                      sleepWindows: windows, calendar: calendar, now: now)
    }

    private func feed(at date: Date) -> FeedEvent {
        FeedEvent(baby: nil, amountOz: 3, timestamp: date,
                  loggedByID: taylorID, loggedByName: "Taylor", loggedByColorHex: "")
    }

    // MARK: The window itself

    func testWindowContainsWrapsMidnight() {
        let window = SleepWindow(parentID: taylorID, startMinute: 22 * 60, durationMinutes: 7 * 60)
        XCTAssertTrue(window.contains(minuteOfDay: 23 * 60))
        XCTAssertTrue(window.contains(minuteOfDay: 1 * 60), "1am is inside 10pm–5am")
        XCTAssertTrue(window.contains(minuteOfDay: 22 * 60), "the start minute is inside")
        XCTAssertFalse(window.contains(minuteOfDay: 5 * 60), "the end minute is outside")
        XCTAssertFalse(window.contains(minuteOfDay: 12 * 60))
    }

    func testWindowFromSlotRequiresAssigneeAndRealSpan() {
        let good = PlanSlot(kind: .sleep, minuteOfDay: 22 * 60, endMinuteOfDay: 5 * 60,
                            assignedToID: taylorID)
        XCTAssertEqual(SleepWindow(slot: good)?.durationMinutes, 7 * 60)

        let unowned = PlanSlot(kind: .sleep, minuteOfDay: 22 * 60, endMinuteOfDay: 5 * 60)
        XCTAssertNil(SleepWindow(slot: unowned), "a window nobody owns routes nothing")

        let legacy = PlanSlot(kind: .sleep, minuteOfDay: 20 * 60, assignedToID: taylorID)
        XCTAssertNil(SleepWindow(slot: legacy), "a legacy put-down instant is not a window")

        let zero = PlanSlot(kind: .sleep, minuteOfDay: 22 * 60, endMinuteOfDay: 22 * 60,
                            assignedToID: taylorID)
        XCTAssertNil(SleepWindow(slot: zero), "start == end has no sane reading")

        let deleted = PlanSlot(kind: .sleep, minuteOfDay: 22 * 60, endMinuteOfDay: 5 * 60,
                               assignedToID: taylorID, deletedAt: .now)
        XCTAssertNil(SleepWindow(slot: deleted))
    }

    // MARK: NightSchedule routing

    func testFeedDuringOneParentsSleepGoesToTheOther() {
        // Fed 5:30pm → night runs 9:30pm, 1:30am, 5:30am. Taylor sleeps
        // 9pm–2am, so the 9:30 and 1:30 are Katie's; 5:30 falls to the
        // rotation. Without windows the rotation would give Taylor the 9:30.
        let windows = [SleepWindow(parentID: taylorID, startMinute: 21 * 60,
                                   durationMinutes: 5 * 60)]
        let occs = schedule(feeds: [feed(at: date(2026, 7, 21, 17, 30))],
                            windows: windows, now: date(2026, 7, 21, 20, 0)).occurrences()

        XCTAssertEqual(occs.count, 3)
        XCTAssertEqual(occs[0].assignedToID, katieID, "9:30pm is inside Taylor's sleep — Katie's bottle")
        XCTAssertEqual(occs[0].assignedToName, "Katie")
        XCTAssertEqual(occs[1].assignedToID, katieID, "1:30am too")
    }

    func testComplementaryWindowsSplitTheNight() {
        // Taylor sleeps 9pm–2am, Katie 2am–8am: every bottle before 2am is
        // Katie's, every one after is Taylor's — the balanced-shift setup.
        let windows = [
            SleepWindow(parentID: taylorID, startMinute: 21 * 60, durationMinutes: 5 * 60),
            SleepWindow(parentID: katieID, startMinute: 2 * 60, durationMinutes: 6 * 60),
        ]
        let occs = schedule(feeds: [feed(at: date(2026, 7, 21, 17, 30))],
                            windows: windows, now: date(2026, 7, 21, 20, 0)).occurrences()

        // 9:30pm, 1:30am → Katie; 5:30am → Taylor.
        XCTAssertEqual(occs.map(\.assignedToID), [katieID, katieID, taylorID])
    }

    func testBothAsleepGoesToTheSoonestWakeUp() {
        // Both are asleep at the 9:30pm bottle, but Katie's up at 11pm while
        // Taylor sleeps through to 5am — the bottle is hers (her block was
        // ending anyway) and Taylor's long stretch stays whole. The 1:30am
        // (only Taylor asleep) is hers by the awake rule; 5:30am (both up)
        // falls to the rotation, which has Taylor at index 2.
        let windows = [
            SleepWindow(parentID: taylorID, startMinute: 21 * 60, durationMinutes: 8 * 60),
            SleepWindow(parentID: katieID, startMinute: 20 * 60, durationMinutes: 3 * 60),
        ]
        let occs = schedule(feeds: [feed(at: date(2026, 7, 21, 17, 30))],
                            windows: windows, now: date(2026, 7, 21, 20, 0)).occurrences()

        XCTAssertEqual(occs.map(\.assignedToID), [katieID, katieID, taylorID])
    }

    func testSoonestWakeUpReadsChainedWindowsAsOneBlock() {
        // Katie's 8–11pm and 11pm–2am windows touch: one block until 2am.
        // Taylor sleeps 9pm–1am. Both are asleep at 9:30 — Taylor's up first
        // (1am vs her 2am), so the bottle is his despite Katie's first
        // window "ending" at 11.
        let windows = [
            SleepWindow(parentID: taylorID, startMinute: 21 * 60, durationMinutes: 4 * 60),
            SleepWindow(parentID: katieID, startMinute: 20 * 60, durationMinutes: 3 * 60),
            SleepWindow(parentID: katieID, startMinute: 23 * 60, durationMinutes: 3 * 60),
        ]
        let occs = schedule(feeds: [feed(at: date(2026, 7, 21, 17, 30))],
                            windows: windows, now: date(2026, 7, 21, 20, 0)).occurrences()

        XCTAssertEqual(occs[0].assignedToID, taylorID,
                       "without chaining Katie would look up at 11pm and lose her block")
    }

    func testRoundTheClockWindowsNeverWinTheBottle() {
        // Taylor's windows cover the entire clock — he's never planned-awake,
        // so the wake-up walk caps at a full day instead of looping, and
        // Katie (up at 11pm) takes the 9:30 bottle.
        let windows = [
            SleepWindow(parentID: taylorID, startMinute: 0, durationMinutes: 12 * 60),
            SleepWindow(parentID: taylorID, startMinute: 12 * 60, durationMinutes: 12 * 60),
            SleepWindow(parentID: katieID, startMinute: 20 * 60, durationMinutes: 3 * 60),
        ]
        let occs = schedule(feeds: [feed(at: date(2026, 7, 21, 17, 30))],
                            windows: windows, now: date(2026, 7, 21, 20, 0)).occurrences()

        XCTAssertEqual(occs[0].assignedToID, katieID)
    }

    func testBothAsleepDeadTieFallsBackToRotation() {
        // Identical windows cover 9:30pm for BOTH parents with the same
        // wake-up — "soonest awake" can't pick either, so the rotation
        // (Taylor first) stands.
        let windows = [
            SleepWindow(parentID: taylorID, startMinute: 21 * 60, durationMinutes: 120),
            SleepWindow(parentID: katieID, startMinute: 21 * 60, durationMinutes: 120),
        ]
        let occs = schedule(feeds: [feed(at: date(2026, 7, 21, 17, 30))],
                            windows: windows, now: date(2026, 7, 21, 20, 0)).occurrences()

        XCTAssertEqual(occs[0].assignedToID, taylorID,
                       "windows that don't decide leave the rotation in charge")
    }

    func testDriftedNightStaysWithTheParentWhoPlannedToBeUp() {
        // The real night this rule exists for. Katie front-loads 8pm–2:30am,
        // then naps 3–5:30 and 6–7:45 with get-up gaps left around the
        // expected ~2:30 and ~5:30 bottles; Taylor sleeps 1–9am. The night
        // anchors 27 minutes late (first bottle 10:27pm, every 2½h), sliding
        // the later bottles INTO her naps. Soonest-wake still hands the whole
        // night out right — 10:27 and 12:57 his (she's down, he's up), 3:27
        // hers (both down, but she's up at 5:30 vs his 9:00), 5:57 hers (her
        // get-up gap) — with zero manual overrides.
        let windows = [
            SleepWindow(parentID: katieID, startMinute: 20 * 60, durationMinutes: 6 * 60 + 30),
            SleepWindow(parentID: katieID, startMinute: 3 * 60, durationMinutes: 2 * 60 + 30),
            SleepWindow(parentID: katieID, startMinute: 6 * 60, durationMinutes: 1 * 60 + 45),
            SleepWindow(parentID: taylorID, startMinute: 1 * 60, durationMinutes: 8 * 60),
        ]
        let night = NightSchedule(
            nightStartMinute: 21 * 60, nightEndMinute: 7 * 60, spacingMinutes: 150,
            rotation: .alternating, firstShiftID: nil, parents: parents,
            feeds: [feed(at: date(2026, 8, 12, 22, 27))], overrides: [],
            sleepWindows: windows, calendar: calendar, now: date(2026, 8, 12, 22, 30))

        XCTAssertEqual(night.occurrences().map(\.assignedToID),
                       [taylorID, taylorID, katieID, katieID])
    }

    func testNobodyAsleepFallsBackToRotation() {
        // A window that covers none of the night's bottles changes nothing.
        let windows = [SleepWindow(parentID: taylorID, startMinute: 12 * 60,
                                   durationMinutes: 60)]
        let with = schedule(feeds: [feed(at: date(2026, 7, 21, 17, 30))],
                            windows: windows, now: date(2026, 7, 21, 20, 0)).occurrences()
        let without = schedule(feeds: [feed(at: date(2026, 7, 21, 17, 30))],
                               now: date(2026, 7, 21, 20, 0)).occurrences()

        XCTAssertEqual(with.map(\.assignedToID), without.map(\.assignedToID))
    }

    func testPerNightOverrideStillBeatsTheWindow() {
        // Taylor's asleep at 9:30 so the window says Katie — but tonight they
        // swapped it to Taylor explicitly. The override wins.
        let windows = [SleepWindow(parentID: taylorID, startMinute: 21 * 60,
                                   durationMinutes: 5 * 60)]
        let nightKey = ScheduleEngine.dayKey(for: date(2026, 7, 21, 21, 0), calendar: calendar)
        let override = PlanOverride(
            slotID: NightSchedule.syntheticSlotID(nightKey: nightKey, index: 0),
            dayKey: nightKey, assignedToID: taylorID, assignedToName: "Taylor",
            createdByID: katieID)
        let occs = schedule(feeds: [feed(at: date(2026, 7, 21, 17, 30))],
                            overrides: [override], windows: windows,
                            now: date(2026, 7, 21, 20, 0)).occurrences()

        XCTAssertEqual(occs[0].assignedToID, taylorID, "an explicit swap outranks the windows")
    }

    // MARK: ScheduleEngine materialization

    private func engine(slots: [PlanSlot], sleeps: [SleepEvent] = [],
                        overrides: [PlanOverride] = [], now: Date) -> ScheduleEngine {
        ScheduleEngine(slots: slots, overrides: overrides, feeds: [], sleeps: sleeps,
                       calendar: calendar, now: now)
    }

    func testWindowMaterializesAsSpan() {
        let slot = PlanSlot(kind: .sleep, minuteOfDay: 22 * 60, endMinuteOfDay: 5 * 60,
                            assignedToID: taylorID, assignedToName: "Taylor")
        let occs = engine(slots: [slot], now: date(2026, 7, 21, 20, 0)).occurrences()

        let tonight = occs.first { $0.date == date(2026, 7, 21, 22, 0) }
        XCTAssertEqual(tonight?.endDate, date(2026, 7, 22, 5, 0),
                       "10pm–5am wraps midnight into a 7h span")
        XCTAssertEqual(tonight?.status, .upcoming)
    }

    func testInProgressWindowStaysOnTheSchedule() {
        // 2am, window started 10pm YESTERDAY relative to the 2h lookback —
        // the span is mid-flight and must still be on the rail.
        let slot = PlanSlot(kind: .sleep, minuteOfDay: 22 * 60, endMinuteOfDay: 5 * 60,
                            assignedToID: taylorID, assignedToName: "Taylor")
        let occs = engine(slots: [slot], now: date(2026, 7, 22, 2, 0)).occurrences()

        XCTAssertTrue(occs.contains {
            $0.date == date(2026, 7, 21, 22, 0) && $0.endDate == date(2026, 7, 22, 5, 0)
                && $0.status == .upcoming
        }, "a window in progress is still tonight's plan")
    }

    func testEndedWindowDropsWithoutOverduePhase() {
        // 6am: the 10pm–5am window fully ended an hour ago — no row, and
        // never an "overdue" (finished sleep can't be late).
        let slot = PlanSlot(kind: .sleep, minuteOfDay: 22 * 60, endMinuteOfDay: 5 * 60,
                            assignedToID: taylorID, assignedToName: "Taylor")
        let occs = engine(slots: [slot], now: date(2026, 7, 22, 6, 0)).occurrences()

        XCTAssertFalse(occs.contains { $0.date == date(2026, 7, 21, 22, 0) })
        XCTAssertFalse(occs.contains { $0.status == .overdue })
    }

    func testBabySleepNeverFulfillsAWindow() {
        // A logged baby sleep right at the window's start must not tick the
        // window off — the window is the PARENT's sleep.
        let slot = PlanSlot(kind: .sleep, minuteOfDay: 22 * 60, endMinuteOfDay: 5 * 60,
                            assignedToID: taylorID, assignedToName: "Taylor")
        let babySleep = SleepEvent(baby: nil, startedAt: date(2026, 7, 21, 22, 0),
                                   loggedByID: taylorID, loggedByName: "Taylor",
                                   loggedByColorHex: "")
        let occs = engine(slots: [slot], sleeps: [babySleep],
                          now: date(2026, 7, 21, 23, 0)).occurrences()

        let tonight = occs.first { $0.date == date(2026, 7, 21, 22, 0) }
        XCTAssertEqual(tonight?.status, .upcoming, "windows have no fulfillment")
    }

    func testMovedWindowKeepsItsDuration() {
        // Tonight's 10pm window moved to 11pm: the span shifts whole — still
        // 7 hours, now 11pm–6am.
        let slot = PlanSlot(kind: .sleep, minuteOfDay: 22 * 60, endMinuteOfDay: 5 * 60,
                            assignedToID: taylorID, assignedToName: "Taylor")
        let override = PlanOverride(slotID: slot.id, dayKey: 20_260_721,
                                    assignedToID: taylorID, assignedToName: "Taylor",
                                    minuteOfDayOverride: 23 * 60, createdByID: taylorID)
        let occs = engine(slots: [slot], overrides: [override],
                          now: date(2026, 7, 21, 20, 0)).occurrences()

        let tonight = occs.first { $0.dayKey == 20_260_721 }
        XCTAssertEqual(tonight?.date, date(2026, 7, 21, 23, 0))
        XCTAssertEqual(tonight?.endDate, date(2026, 7, 22, 6, 0))
    }

    // MARK: Ring surfaces stay dark

    func testWindowsNeverAlarmOrRemind() {
        let slot = PlanSlot(kind: .sleep, minuteOfDay: 22 * 60, endMinuteOfDay: 5 * 60,
                            assignedToID: taylorID, assignedToName: "Taylor")
        let e = engine(slots: [slot], now: date(2026, 7, 21, 20, 0))

        XCTAssertTrue(e.upcomingAssigned(to: taylorID).isEmpty,
                      "no reminder input from windows")
        XCTAssertTrue(e.upcomingAlarmable(for: taylorID).isEmpty,
                      "no alarms from windows")

        let planned = ScheduleReminderPlanner.plan(
            occurrences: e.occurrences(), myID: taylorID,
            babyName: "Miller", now: date(2026, 7, 21, 20, 0))
        XCTAssertTrue(planned.isEmpty, "the planner skips spans outright")
    }
}

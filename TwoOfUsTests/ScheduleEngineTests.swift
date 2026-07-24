import XCTest
@testable import TwoOfUs

/// Pure-logic tests for `ScheduleEngine`: slot materialization (incl. midnight
/// and DST), override precedence, fulfillment matching, overdue handling, and
/// predictions. No store, no CloudKit — models are built standalone and the
/// calendar + `now` are pinned so every run sees the same night.
final class ScheduleEngineTests: XCTestCase {
    /// Fixed zone with a 2026 DST transition we can aim at (Mar 8, 02:00→03:00).
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        return c
    }()

    /// Tue July 21 2026, 8pm local — a typical evening, night shift ahead.
    private var now: Date { date(2026, 7, 21, 20, 0) }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    private func engine(
        slots: [PlanSlot] = [], overrides: [PlanOverride] = [],
        feeds: [FeedEvent] = [], sleeps: [SleepEvent] = [],
        interval: TimeInterval = 3 * 3600, now: Date? = nil
    ) -> ScheduleEngine {
        ScheduleEngine(slots: slots, overrides: overrides, feeds: feeds, sleeps: sleeps,
                       targetFeedInterval: interval, calendar: calendar, now: now ?? self.now)
    }

    private func feed(at date: Date, deleted: Bool = false) -> FeedEvent {
        let f = FeedEvent(baby: nil, amountOz: 3, timestamp: date,
                          loggedByID: UUID(), loggedByName: "Taylor", loggedByColorHex: "")
        if deleted { f.deletedAt = date }
        return f
    }

    // MARK: Materialization

    func testMaterializesNightSlotsAcrossMidnight() {
        let eleven = PlanSlot(kind: .feed, minuteOfDay: 23 * 60, assignedToName: "Katie")
        let three = PlanSlot(kind: .feed, minuteOfDay: 3 * 60, assignedToName: "Taylor")

        let occs = engine(slots: [eleven, three]).occurrences()

        XCTAssertEqual(occs.count, 2)
        XCTAssertEqual(occs[0].date, date(2026, 7, 21, 23, 0), "11pm lands tonight")
        XCTAssertEqual(occs[0].dayKey, 20_260_721)
        XCTAssertEqual(occs[1].date, date(2026, 7, 22, 3, 0), "3am lands tomorrow morning")
        XCTAssertEqual(occs[1].dayKey, 20_260_722, "the 3am occurrence keys to ITS calendar day")
        XCTAssertEqual(occs[1].assignedToName, "Taylor")
    }

    func testStableOccurrenceIDs() {
        let slot = PlanSlot(kind: .feed, minuteOfDay: 23 * 60)
        let occ = engine(slots: [slot]).occurrences()[0]
        XCTAssertEqual(occ.id, "slot.\(slot.id.uuidString).20260721",
                       "ids must be stable so reminders/rows self-replace across re-plans")
    }

    func testDSTSpringForwardStillMaterializes() {
        // 02:30 does not exist on Mar 8 2026 in Chicago; Calendar resolves it
        // rather than dropping the night's slot.
        let slot = PlanSlot(kind: .feed, minuteOfDay: 2 * 60 + 30)
        let occs = engine(slots: [slot], now: date(2026, 3, 8, 0, 30)).occurrences()

        XCTAssertFalse(occs.isEmpty, "the spring-forward night must not lose its slot")
        let day = calendar.dateComponents([.day], from: occs[0].date).day
        XCTAssertEqual(day, 8)
    }

    func testDeletedSlotProducesNothing() {
        let slot = PlanSlot(kind: .feed, minuteOfDay: 23 * 60, deletedAt: .now)
        XCTAssertTrue(engine(slots: [slot]).occurrences().isEmpty)
    }

    // MARK: Override precedence

    func testOverrideReplacesAssignmentForItsNightOnly() {
        let katie = UUID(), taylor = UUID()
        let slot = PlanSlot(kind: .feed, minuteOfDay: 23 * 60,
                            assignedToID: katie, assignedToName: "Katie")
        let swap = PlanOverride(slotID: slot.id, dayKey: 20_260_721,
                                assignedToID: taylor, assignedToName: "Taylor",
                                createdByID: taylor)

        let occs = engine(slots: [slot], overrides: [swap]).occurrences(horizon: 30 * 3600)

        XCTAssertEqual(occs[0].assignedToID, taylor, "tonight is swapped")
        XCTAssertEqual(occs[0].activeOverrideID, swap.id)
        XCTAssertEqual(occs[0].overrideCreatedByID, taylor)
        XCTAssertEqual(occs[1].assignedToID, katie, "tomorrow the standing plan resumes")
        XCTAssertNil(occs[1].activeOverrideID)
    }

    func testConcurrentOverridesResolveDeterministically() {
        let slot = PlanSlot(kind: .feed, minuteOfDay: 23 * 60, assignedToName: "Katie")
        let older = PlanOverride(slotID: slot.id, dayKey: 20_260_721,
                                 assignedToName: "Older", createdByID: UUID(),
                                 createdAt: date(2026, 7, 21, 18, 0))
        let newer = PlanOverride(slotID: slot.id, dayKey: 20_260_721,
                                 assignedToName: "Newer", createdByID: UUID(),
                                 createdAt: date(2026, 7, 21, 19, 0))

        let occ = engine(slots: [slot], overrides: [older, newer]).occurrences()[0]
        XCTAssertEqual(occ.assignedToName, "Newer", "latest createdAt wins")

        // Exact tie → larger id string wins, so both phones agree.
        let tieA = PlanOverride(slotID: slot.id, dayKey: 20_260_721,
                                assignedToName: "A", createdByID: UUID(),
                                createdAt: date(2026, 7, 21, 19, 0))
        let tieB = PlanOverride(slotID: slot.id, dayKey: 20_260_721,
                                assignedToName: "B", createdByID: UUID(),
                                createdAt: date(2026, 7, 21, 19, 0))
        let expected = tieA.id.uuidString > tieB.id.uuidString ? "A" : "B"
        let tied = engine(slots: [slot], overrides: [tieA, tieB]).occurrences()[0]
        XCTAssertEqual(tied.assignedToName, expected)
    }

    func testSoftDeletedOverrideIsIgnored() {
        let katie = UUID()
        let slot = PlanSlot(kind: .feed, minuteOfDay: 23 * 60,
                            assignedToID: katie, assignedToName: "Katie")
        let undone = PlanOverride(slotID: slot.id, dayKey: 20_260_721,
                                  assignedToName: "Taylor", createdByID: UUID(),
                                  deletedAt: .now)

        let occ = engine(slots: [slot], overrides: [undone]).occurrences()[0]
        XCTAssertEqual(occ.assignedToID, katie, "an undone swap restores the standing plan")
        XCTAssertNil(occ.activeOverrideID)
    }

    func testSkipOverrideMarksSkipped() {
        let slot = PlanSlot(kind: .feed, minuteOfDay: 23 * 60, assignedToName: "Katie")
        let skip = PlanOverride(slotID: slot.id, dayKey: 20_260_721,
                                isSkipped: true, createdByID: UUID())

        let occ = engine(slots: [slot], overrides: [skip]).occurrences()[0]
        XCTAssertEqual(occ.status, .skipped)
    }

    // MARK: Fulfillment

    func testFeedNearSlotFulfillsIt() {
        let slot = PlanSlot(kind: .feed, minuteOfDay: 23 * 60)
        let bottle = feed(at: date(2026, 7, 21, 23, 10))

        let occ = engine(slots: [slot], feeds: [bottle],
                         now: date(2026, 7, 21, 23, 30)).occurrences()[0]
        XCTAssertEqual(occ.status, .fulfilled(byEventID: bottle.id))
    }

    func testOneEventCannotFulfillTwoSlots() {
        // 10:30pm and 11pm slots; one bottle at 10:50 — nearer to 11pm.
        let earlier = PlanSlot(kind: .feed, minuteOfDay: 22 * 60 + 30)
        let later = PlanSlot(kind: .feed, minuteOfDay: 23 * 60)
        let bottle = feed(at: date(2026, 7, 21, 22, 50))

        let occs = engine(slots: [earlier, later], feeds: [bottle],
                          now: date(2026, 7, 21, 23, 30)).occurrences()

        XCTAssertEqual(occs[1].status, .fulfilled(byEventID: bottle.id),
                       "the nearer slot claims the bottle")
        XCTAssertEqual(occs[0].status, .overdue,
                       "the other slot stays open — one 10:50 bottle isn't two feeds")
    }

    func testSoftDeletedFeedDoesNotFulfill() {
        let slot = PlanSlot(kind: .feed, minuteOfDay: 23 * 60)
        let deleted = feed(at: date(2026, 7, 21, 23, 0), deleted: true)

        let occ = engine(slots: [slot], feeds: [deleted],
                         now: date(2026, 7, 21, 23, 30)).occurrences()[0]
        XCTAssertEqual(occ.status, .overdue)
    }

    func testSleepStartFulfillsSleepSlot() {
        let slot = PlanSlot(kind: .sleep, minuteOfDay: 19 * 60 + 30)
        let sleep = SleepEvent(baby: nil, startedAt: date(2026, 7, 21, 19, 40),
                               loggedByID: UUID(), loggedByName: "Katie", loggedByColorHex: "")

        let occ = engine(slots: [slot], sleeps: [sleep]).occurrences()[0]
        XCTAssertEqual(occ.status, .fulfilled(byEventID: sleep.id))
    }

    // MARK: Overdue

    func testUnfulfilledPastSlotIsOverdueThenDrops() {
        let slot = PlanSlot(kind: .feed, minuteOfDay: 23 * 60)

        let shortlyAfter = engine(slots: [slot], now: date(2026, 7, 21, 23, 45)).occurrences()
        XCTAssertEqual(shortlyAfter.first?.status, .overdue)

        let longAfter = engine(slots: [slot], now: date(2026, 7, 22, 1, 0))
            .occurrences()
            .filter { $0.dayKey == 20_260_721 }
        XCTAssertTrue(longAfter.isEmpty,
                      "past the grace window a stale 'was due 11pm' row helps no one")
    }

    // MARK: Predictions

    func testFeedPredictionsProjectFromLastFeed() {
        let occs = engine(feeds: [feed(at: date(2026, 7, 21, 19, 0))]).occurrences()

        XCTAssertEqual(occs.first?.date, date(2026, 7, 21, 22, 0),
                       "next bottle = last feed + target interval, same math as Home")
        XCTAssertEqual(occs.first?.source, .predicted)
        XCTAssertNil(occs.first?.assignedToID, "predictions are never assigned")
        XCTAssertEqual(occs.first?.id, "pred.feed.1")
    }

    func testPredictionSuppressedNearPinnedSlot() {
        let slot = PlanSlot(kind: .feed, minuteOfDay: 22 * 60 + 30)   // 10:30pm pinned
        let occs = engine(slots: [slot], feeds: [feed(at: date(2026, 7, 21, 19, 0))]).occurrences()

        // The 10pm prediction sits within the merge window of the pinned 10:30
        // slot — the plan wins; the 1am prediction survives.
        XCTAssertFalse(occs.contains { $0.source == .predicted && $0.date == date(2026, 7, 21, 22, 0) })
        XCTAssertTrue(occs.contains { $0.source == .predicted && $0.date == date(2026, 7, 22, 1, 0) })
    }

    func testNoPredictionsWithoutIntervalOrFeeds() {
        XCTAssertTrue(engine(feeds: [feed(at: date(2026, 7, 21, 19, 0))], interval: 0)
            .occurrences().isEmpty)
        XCTAssertTrue(engine().occurrences().isEmpty)
    }

    func testSleepPredictionFromLastWakeSuppressedWhileAsleep() {
        let woke = SleepEvent(baby: nil, startedAt: date(2026, 7, 21, 17, 0),
                              loggedByID: UUID(), loggedByName: "", loggedByColorHex: "")
        woke.endedAt = date(2026, 7, 21, 18, 30)

        let occs = engine(sleeps: [woke]).occurrences()
        XCTAssertTrue(occs.contains {
            $0.kind == .sleep && $0.date == date(2026, 7, 21, 18, 30).addingTimeInterval(UrgencyDefaults.sleep)
        })

        let active = SleepEvent(baby: nil, startedAt: date(2026, 7, 21, 19, 45),
                                loggedByID: UUID(), loggedByName: "", loggedByColorHex: "")
        let quiet = engine(sleeps: [woke, active]).occurrences()
        XCTAssertFalse(quiet.contains { $0.kind == .sleep },
                       "no 'next sleep' while the baby is asleep")
    }

    // MARK: Assigned filtering (the notification planner's input)

    func testUpcomingAssignedReturnsOnlyMyPinnedUpcoming() {
        let me = UUID(), other = UUID()
        let mine = PlanSlot(kind: .feed, minuteOfDay: 3 * 60, assignedToID: me, assignedToName: "T")
        let theirs = PlanSlot(kind: .feed, minuteOfDay: 23 * 60, assignedToID: other, assignedToName: "K")
        // My 8:30pm slot, fed 25 minutes early — fulfilled, so no reminder due.
        let earlyFedMine = PlanSlot(kind: .feed, minuteOfDay: 20 * 60 + 30, assignedToID: me, assignedToName: "T")
        let bottle = feed(at: date(2026, 7, 21, 19, 55))

        let mineUpcoming = engine(slots: [mine, theirs, earlyFedMine], feeds: [bottle])
            .upcomingAssigned(to: me)

        XCTAssertEqual(mineUpcoming.count, 1, "only my un-fulfilled upcoming slots qualify")
        XCTAssertEqual(mineUpcoming.first?.date, date(2026, 7, 22, 3, 0))
    }

    func testSwapMovesAssignmentForReminderPurposes() {
        let me = UUID(), other = UUID()
        let slot = PlanSlot(kind: .feed, minuteOfDay: 23 * 60, assignedToID: other, assignedToName: "K")
        let swap = PlanOverride(slotID: slot.id, dayKey: 20_260_721,
                                assignedToID: me, assignedToName: "T", createdByID: me)

        XCTAssertEqual(engine(slots: [slot], overrides: [swap]).upcomingAssigned(to: me).count, 1)
        XCTAssertTrue(engine(slots: [slot], overrides: [swap]).upcomingAssigned(to: other).isEmpty,
                      "after the swap the off-duty parent has nothing tonight")
    }

    // MARK: assignedElsewhere (the off-duty phone's generic-alarm stand-down)

    func testAssignedElsewhereTrueOnlyForTheOtherParentsSlot() {
        let me = UUID(), other = UUID()
        let theirs = PlanSlot(kind: .feed, minuteOfDay: 23 * 60, assignedToID: other, assignedToName: "K")
        let eleven = date(2026, 7, 21, 23, 0)

        XCTAssertTrue(engine(slots: [theirs]).assignedElsewhere(near: eleven, kind: .feed, me: me),
                      "the off-duty phone must recognize the other parent's slot")
        XCTAssertFalse(engine(slots: [theirs]).assignedElsewhere(near: eleven, kind: .feed, me: other),
                       "the assigned parent keeps their own generic alarm")
    }

    func testAssignedElsewhereFailSafesToFalse() {
        let me = UUID(), other = UUID()
        let unassigned = PlanSlot(kind: .feed, minuteOfDay: 23 * 60)
        let theirs = PlanSlot(kind: .feed, minuteOfDay: 23 * 60, assignedToID: other, assignedToName: "K")
        let eleven = date(2026, 7, 21, 23, 0)

        XCTAssertFalse(engine(slots: [unassigned]).assignedElsewhere(near: eleven, kind: .feed, me: me),
                       "an unassigned slot is everyone's — keep the alarm")
        XCTAssertFalse(engine(slots: [theirs]).assignedElsewhere(near: eleven, kind: .feed, me: nil),
                       "unknown local identity must never silently skip the alarm")
        XCTAssertFalse(engine(slots: []).assignedElsewhere(near: eleven, kind: .feed, me: me),
                       "no schedule → no stand-down")
        XCTAssertFalse(engine(slots: [theirs])
            .assignedElsewhere(near: date(2026, 7, 22, 1, 0), kind: .feed, me: me),
                       "a fire time outside the ±window isn't covered by the slot")
        XCTAssertFalse(engine(slots: [theirs]).assignedElsewhere(near: eleven, kind: .sleep, me: me),
                       "kind must match — a feed slot doesn't silence sleep reminders")
    }

    func testAssignedElsewhereRespectsTonightsSwapAndSkip() {
        let me = UUID(), other = UUID()
        let theirs = PlanSlot(kind: .feed, minuteOfDay: 23 * 60, assignedToID: other, assignedToName: "K")
        let eleven = date(2026, 7, 21, 23, 0)

        let swapToMe = PlanOverride(slotID: theirs.id, dayKey: 20_260_721,
                                    assignedToID: me, assignedToName: "T", createdByID: me)
        XCTAssertFalse(engine(slots: [theirs], overrides: [swapToMe])
            .assignedElsewhere(near: eleven, kind: .feed, me: me),
                       "after tonight's swap to me, my alarm must come back")

        let skipped = PlanOverride(slotID: theirs.id, dayKey: 20_260_721,
                                   isSkipped: true, createdByID: other)
        XCTAssertFalse(engine(slots: [theirs], overrides: [skipped])
            .assignedElsewhere(near: eleven, kind: .feed, me: me),
                       "a skipped night belongs to nobody — the generic alarm stays on duty")
    }

    func testAssignedElsewhereIgnoresFulfilledSlots() {
        // Their 8:30pm slot, fed 35 minutes early — the slot is spoken for, so
        // it must not silence this phone's generic alarm for the NEXT interval.
        let me = UUID(), other = UUID()
        let theirs = PlanSlot(kind: .feed, minuteOfDay: 20 * 60 + 30, assignedToID: other, assignedToName: "K")
        let bottle = feed(at: date(2026, 7, 21, 19, 55))

        XCTAssertFalse(engine(slots: [theirs], feeds: [bottle])
            .assignedElsewhere(near: date(2026, 7, 21, 20, 30), kind: .feed, me: me),
                       "a slot their bottle already covered can't silence the next interval alarm")
    }

    // MARK: Consistency across call sites

    /// The Schedule tab (2h lookback) and the reminder planner / slot alarm
    /// (lookback 0) must agree on which slot a bottle covered — fulfillment
    /// matches against the same recent-past set regardless of display window.
    func testFulfillmentAgreesAcrossLookbackWindows() {
        let past = PlanSlot(kind: .feed, minuteOfDay: 22 * 60 + 30)
        let future = PlanSlot(kind: .feed, minuteOfDay: 23 * 60 + 30)
        let bottle = feed(at: date(2026, 7, 21, 22, 55))
        let at = date(2026, 7, 21, 23, 5)
        let futureID = "slot.\(future.id.uuidString).20260721"

        let wide = engine(slots: [past, future], feeds: [bottle], now: at)
            .occurrences().first { $0.id == futureID }?.status
        let narrow = engine(slots: [past, future], feeds: [bottle], now: at)
            .occurrences(lookback: 0).first { $0.id == futureID }?.status

        XCTAssertEqual(wide, narrow)
        XCTAssertEqual(narrow, .upcoming,
                       "the 22:55 bottle belongs to the nearer 22:30 slot even when the past isn't displayed")
    }

    func testEqualDistanceFulfillmentTieIsDeterministic() {
        // A bottle exactly between two slots (30m each side): the earlier slot
        // claims it, regardless of input array order.
        let ten = PlanSlot(kind: .feed, minuteOfDay: 22 * 60)
        let eleven = PlanSlot(kind: .feed, minuteOfDay: 23 * 60)
        let bottle = feed(at: date(2026, 7, 21, 22, 30))

        let occs = engine(slots: [eleven, ten], feeds: [bottle],
                          now: date(2026, 7, 21, 23, 30)).occurrences()
        XCTAssertEqual(occs[0].status, .fulfilled(byEventID: bottle.id))
        XCTAssertEqual(occs[1].status, .overdue)
    }

    func testStaleLastFeedStillPredicts() {
        // Last feed 5+ days ago (interval budget would be exhausted walking the
        // past): predictions must still project into the window.
        let occs = engine(feeds: [feed(at: date(2026, 7, 16, 12, 0))]).occurrences()

        XCTAssertFalse(occs.isEmpty, "a stale anchor must not silence predictions")
        XCTAssertEqual(occs.first?.date, date(2026, 7, 21, 21, 0),
                       "first prediction is the first interval multiple after now")
        XCTAssertTrue(occs.allSatisfy { $0.date > now })
    }

    // MARK: dayKey helper

    func testDayKeyMatchesLocalCalendarDay() {
        XCTAssertEqual(ScheduleEngine.dayKey(for: date(2026, 7, 21, 23, 59), calendar: calendar), 20_260_721)
        XCTAssertEqual(ScheduleEngine.dayKey(for: date(2026, 7, 22, 0, 1), calendar: calendar), 20_260_722)
    }
}

import XCTest
@testable import TwoOfUs

/// Pure-logic tests for `NightSchedule`, the dynamic nighttime feed schedule:
/// window resolution (incl. the midnight wrap and the upcoming-night case),
/// the projected anchor (the last feed plus the night spacing, when that
/// predicted bottle lands inside the window), re-anchoring to a real
/// in-window feed, the first-shift rotation, per-night overrides, fulfillment
/// matching, and the day/approaching/active states. No store, no CloudKit —
/// models are built standalone with a pinned calendar and `now`.
final class NightScheduleTests: XCTestCase {
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

    /// Night 9pm–8am, spacing 4h, alternating with Taylor on first shift —
    /// the worked example, unless overridden.
    private func schedule(
        feeds: [FeedEvent] = [], overrides: [PlanOverride] = [], now: Date,
        startMinute: Int = 21 * 60, endMinute: Int = 8 * 60,
        spacing: Int = 240,
        rotation: NightRotation = .alternating, firstShiftID: UUID? = nil,
        parents: [NightSchedule.Parent]? = nil
    ) -> NightSchedule {
        NightSchedule(nightStartMinute: startMinute, nightEndMinute: endMinute,
                      spacingMinutes: spacing,
                      rotation: rotation, firstShiftID: firstShiftID,
                      parents: parents ?? self.parents, feeds: feeds,
                      overrides: overrides, calendar: calendar, now: now)
    }

    private func feed(at date: Date, deleted: Bool = false) -> FeedEvent {
        let f = FeedEvent(baby: nil, amountOz: 3, timestamp: date,
                          loggedByID: taylorID, loggedByName: "Taylor",
                          loggedByColorHex: "")
        if deleted { f.deletedAt = date }
        return f
    }

    // MARK: The projected anchor

    func testPredictionFromLastFeedAnchorsTheNight() {
        // Fed 5:30pm, spacing 4h → 9:30pm lands inside the 9pm–8am window →
        // tonight runs 9:30, then 1:30, 5:30.
        let feeds = [feed(at: date(2026, 7, 21, 17, 30))]
        let occs = schedule(feeds: feeds, now: date(2026, 7, 21, 22, 0)).occurrences()

        XCTAssertEqual(occs.map(\.date), [
            date(2026, 7, 21, 21, 30), date(2026, 7, 22, 1, 30), date(2026, 7, 22, 5, 30),
        ])
        XCTAssertEqual(occs[0].status, .overdue, "9:30 passed unfed by 10pm — say so")
        XCTAssertTrue(occs.allSatisfy { $0.source == .night && $0.kind == .feed })
    }

    func testProjectionVisibleBeforeTheWindowOpens() {
        // 7pm — the window hasn't opened, but the evening glance (and the slot
        // alarm) should already see tonight starting at 9:30.
        let feeds = [feed(at: date(2026, 7, 21, 17, 30))]
        let occs = schedule(feeds: feeds, now: date(2026, 7, 21, 19, 0)).occurrences()

        XCTAssertEqual(occs.first?.date, date(2026, 7, 21, 21, 30))
        XCTAssertTrue(occs.allSatisfy { $0.status == .upcoming })
    }

    func testPredictionLandingExactlyOnWindowStartAnchorsThere() {
        // Fed 5pm, every 4h → 9pm is exactly the window edge → night starts 9pm.
        let feeds = [feed(at: date(2026, 7, 21, 17, 0))]
        let occs = schedule(feeds: feeds, now: date(2026, 7, 21, 21, 30)).occurrences()
        XCTAssertEqual(occs.first?.date, date(2026, 7, 21, 21, 0))
    }

    func testReportedBugScenarioElevenPMWindow() {
        // The live-app bug: window 11pm–8am, spacing 4h, last feed 7:45pm,
        // now 9:41pm. The night must run 11:45pm → 3:45am → 7:45am — NOT
        // anchor at 1:45am (the old day-interval chain 7:45 → 10:45 → 1:45).
        let feeds = [feed(at: date(2026, 7, 28, 19, 45))]
        let s = schedule(feeds: feeds, now: date(2026, 7, 28, 21, 41), startMinute: 23 * 60)

        guard case .approaching(let occs) = s.state else {
            return XCTFail("9:41pm with an 11:45pm night bottle predicted is the run-up to the night")
        }
        XCTAssertEqual(occs.map(\.date), [
            date(2026, 7, 28, 23, 45), date(2026, 7, 29, 3, 45), date(2026, 7, 29, 7, 45),
        ])
        XCTAssertEqual(occs.map(\.assignedToName), ["Taylor", "Katie", "Taylor"])
    }

    func testRealInWindowFeedReplacesTheProjection() {
        // Projection says 11:30, but the baby actually fed at 11:10 — the
        // night re-anchors: 11:10 (done), 3:10, 7:10.
        let feeds = [feed(at: date(2026, 7, 21, 17, 30)),
                     feed(at: date(2026, 7, 21, 23, 10))]
        let occs = schedule(feeds: feeds, now: date(2026, 7, 21, 23, 30)).occurrences()

        XCTAssertEqual(occs.map(\.date), [
            date(2026, 7, 21, 23, 10), date(2026, 7, 22, 3, 10), date(2026, 7, 22, 7, 10),
        ])
        XCTAssertEqual(occs[0].status, .fulfilled(byEventID: feeds[1].id))
    }

    func testEveningFeedBeyondGraceShiftsTheProjection() {
        // A 7:30pm top-up — more than an hour before the 9pm window, so not a
        // grace anchor — becomes the new prediction base: 7:30 + 4h = 11:30 →
        // the night moves with the baby's rhythm.
        let feeds = [feed(at: date(2026, 7, 21, 17, 30)),
                     feed(at: date(2026, 7, 21, 19, 30))]
        let occs = schedule(feeds: feeds, now: date(2026, 7, 21, 22, 0)).occurrences()
        XCTAssertEqual(occs.first?.date, date(2026, 7, 21, 23, 30))
    }

    func testDeletedFeedsCannotAnchorOrProject() {
        // A deleted feed neither anchors nor projects — the night falls back
        // to the window-start default, and nothing reads as fulfilled.
        let feeds = [feed(at: date(2026, 7, 21, 17, 30), deleted: true)]
        let occs = schedule(feeds: feeds, now: date(2026, 7, 21, 22, 0)).occurrences()
        XCTAssertEqual(occs.first?.date, date(2026, 7, 21, 21, 0))
        XCTAssertEqual(occs.first?.status, .overdue)
    }

    func testPredictionShortOfTheWindowFallsBackToWindowStart() {
        // Fed 1pm → 5pm is hours before the window: no bottle predicts into
        // the night, so its start is the default first feed.
        let feeds = [feed(at: date(2026, 7, 21, 13, 0))]
        let occs = schedule(feeds: feeds, now: date(2026, 7, 21, 22, 0)).occurrences()
        XCTAssertEqual(occs.first?.date, date(2026, 7, 21, 21, 0))
    }

    // MARK: The pre-window grace anchor

    func testFeedWithinHourBeforeWindowAnchorsTheNight() {
        // The spec example: window 9pm–8am, feed logged 8:15pm — inside the
        // grace hour, so it IS the night's first feed: 8:15pm → 12:15am →
        // 4:15am → 8:15am (the night keeps its full length, so starting 45
        // minutes early runs 45 minutes past the window's end).
        let early = feed(at: date(2026, 7, 21, 20, 15))
        let occs = schedule(feeds: [early], now: date(2026, 7, 21, 22, 0)).occurrences()

        XCTAssertEqual(occs.map(\.date), [
            date(2026, 7, 21, 20, 15), date(2026, 7, 22, 0, 15),
            date(2026, 7, 22, 4, 15), date(2026, 7, 22, 8, 15),
        ])
        XCTAssertEqual(occs[0].status, .fulfilled(byEventID: early.id))
    }

    func testGraceAnchorBeatsProjection() {
        // Both a 5:30pm feed (projects to 11:30) and an 8:15pm grace feed
        // exist — the logged grace feed wins; projection is only a fallback.
        let feeds = [feed(at: date(2026, 7, 21, 17, 30)),
                     feed(at: date(2026, 7, 21, 20, 15))]
        let occs = schedule(feeds: feeds, now: date(2026, 7, 21, 22, 0)).occurrences()
        XCTAssertEqual(occs.first?.date, date(2026, 7, 21, 20, 15))
    }

    func testGraceAnchorVisibleBeforeWindowOpens() {
        // 8:30pm, fed at 8:15 — the upcoming night already anchors to 8:15.
        let early = feed(at: date(2026, 7, 21, 20, 15))
        let occs = schedule(feeds: [early], now: date(2026, 7, 21, 20, 30)).occurrences()
        XCTAssertEqual(occs.first?.date, date(2026, 7, 21, 20, 15))
    }

    // MARK: The window-start default

    func testNoFeedsAtAllDefaultsToWindowStart() {
        // Nothing to project from → the window's start is the first feed:
        // 9pm, 1am, 5am (9am overshoots the 8am close).
        let occs = schedule(now: date(2026, 7, 21, 22, 0)).occurrences()
        XCTAssertEqual(occs.map(\.date), [
            date(2026, 7, 21, 21, 0), date(2026, 7, 22, 1, 0), date(2026, 7, 22, 5, 0),
        ])
        XCTAssertEqual(occs.first?.status, .overdue, "9pm passed unfed — say so")
    }

    func testPredictionMissingTheWindowDefaultsToWindowStart() {
        // Fed 8:45am → 12:45pm is nowhere near the window — the default
        // takes over.
        let feeds = [feed(at: date(2026, 7, 21, 8, 45))]
        let occs = schedule(feeds: feeds, now: date(2026, 7, 21, 22, 0)).occurrences()
        XCTAssertEqual(occs.first?.date, date(2026, 7, 21, 21, 0))
    }

    func testSlotsStopAtWindowEnd() {
        // Anchor 9:30, 4h spacing in a night ending 8am → 9:30, 1:30, 5:30;
        // 9:30am is out.
        let feeds = [feed(at: date(2026, 7, 21, 17, 30))]
        let occs = schedule(feeds: feeds, now: date(2026, 7, 21, 22, 0)).occurrences()
        XCTAssertEqual(occs.count, 3)
    }

    func testGarbageNightSpacingYieldsOnlyTheAnchorSlot() {
        let feeds = [feed(at: date(2026, 7, 21, 17, 30))]
        let occs = schedule(feeds: feeds, now: date(2026, 7, 21, 22, 0), spacing: 5).occurrences()
        XCTAssertEqual(occs.count, 1, "sub-minimum spacing must not loop the night away")
    }

    // MARK: States

    func testDaytimeIsDayState() {
        XCTAssertEqual(schedule(now: date(2026, 7, 21, 14, 0)).state, .day)
    }

    func testDaytimeWithStaleFeedIsStillDay() {
        // Fed 9am, now 2pm: 1pm predicted long past, nothing points at the
        // night yet — the Tonight card stays down.
        let feeds = [feed(at: date(2026, 7, 21, 9, 0))]
        XCTAssertEqual(schedule(feeds: feeds, now: date(2026, 7, 21, 14, 0)).state, .day)
    }

    func testEveningPredictionIntoTheWindowIsApproaching() {
        // Fed 5:30pm → 9:30pm is a night bottle. From that moment the run-up
        // is on: the Tonight card should already be up at 6pm, well before
        // the 8pm grace hour.
        let feeds = [feed(at: date(2026, 7, 21, 17, 30))]
        guard case .approaching(let occs) =
            schedule(feeds: feeds, now: date(2026, 7, 21, 18, 0)).state else {
            return XCTFail("a predicted night bottle means the night is approaching")
        }
        XCTAssertEqual(occs.first?.date, date(2026, 7, 21, 21, 30))
    }

    func testGraceHourIsApproachingEvenWithNoFeeds() {
        // 8:30pm, nothing logged: inside the grace hour before the 9pm window
        // the card comes up with the window-start default.
        guard case .approaching(let occs) = schedule(now: date(2026, 7, 21, 20, 30)).state else {
            return XCTFail("the grace hour is the night's run-up")
        }
        XCTAssertEqual(occs.first?.date, date(2026, 7, 21, 21, 0))
    }

    func testEveningBeforeGraceWithNoPredictionIsDay() {
        // 7pm, last fed 1pm: the prediction (5pm) misses the window and the
        // grace hour hasn't started — still daytime.
        let feeds = [feed(at: date(2026, 7, 21, 13, 0))]
        XCTAssertEqual(schedule(feeds: feeds, now: date(2026, 7, 21, 19, 0)).state, .day)
    }

    func testInWindowIsAlwaysActiveEvenWithNoFeeds() {
        // No "waiting" state anymore: the window-start default means a night
        // in progress always has a schedule.
        if case .active(let occs) = schedule(now: date(2026, 7, 21, 22, 0)).state {
            XCTAssertEqual(occs.first?.date, date(2026, 7, 21, 21, 0))
        } else {
            XCTFail("a night in progress is always active")
        }
    }

    func testAfterMidnightWindowStartWasYesterday() {
        // 2am, no feeds: the window opened at 9pm YESTERDAY — the default
        // anchor lands there, not at 9pm tonight.
        if case .active(let occs) = schedule(now: date(2026, 7, 22, 2, 0)).state {
            XCTAssertEqual(occs.first?.date, date(2026, 7, 21, 21, 0))
        } else {
            XCTFail("a night in progress is always active")
        }
    }

    func testInWindowWithProjectionIsActive() {
        let feeds = [feed(at: date(2026, 7, 21, 17, 30))]
        if case .active(let occs) = schedule(feeds: feeds, now: date(2026, 7, 21, 22, 0)).state {
            XCTAssertEqual(occs.count, 3)
        } else {
            XCTFail("a projectable night is active")
        }
    }

    func testZeroLengthWindowIsAlwaysDay() {
        let s = schedule(now: date(2026, 7, 21, 22, 0), startMinute: 21 * 60, endMinute: 21 * 60)
        XCTAssertEqual(s.state, .day)
        XCTAssertTrue(s.occurrences().isEmpty)
    }

    // MARK: Rotation (first shift)

    func testRotationStartsFromTheConfiguredFirstShift() {
        let feeds = [feed(at: date(2026, 7, 21, 17, 30))]
        let occs = schedule(feeds: feeds, now: date(2026, 7, 21, 22, 0),
                            firstShiftID: katieID).occurrences()
        XCTAssertEqual(occs.map(\.assignedToName), ["Katie", "Taylor", "Katie"])
    }

    func testNilFirstShiftDefaultsToJoinOrder() {
        let feeds = [feed(at: date(2026, 7, 21, 17, 30))]
        let occs = schedule(feeds: feeds, now: date(2026, 7, 21, 22, 0)).occurrences()
        XCTAssertEqual(occs.map(\.assignedToName), ["Taylor", "Katie", "Taylor"],
                       "no explicit choice → the first parent in join order, same on both phones")
    }

    func testDepartedFirstShiftFallsBackToJoinOrder() {
        let feeds = [feed(at: date(2026, 7, 21, 17, 30))]
        let occs = schedule(feeds: feeds, now: date(2026, 7, 21, 22, 0),
                            firstShiftID: UUID()).occurrences()
        XCTAssertEqual(occs.first?.assignedToID, taylorID)
    }

    func testRotationOffLeavesEverySlotUnassigned() {
        let feeds = [feed(at: date(2026, 7, 21, 17, 30))]
        let occs = schedule(feeds: feeds, now: date(2026, 7, 21, 22, 0),
                            rotation: .none).occurrences()
        XCTAssertTrue(occs.allSatisfy { $0.assignedToID == nil },
                      "no rotation → unassigned → both phones ring")
    }

    func testSoloParentLeavesSlotsUnassigned() {
        let solo = [NightSchedule.Parent(id: taylorID, name: "Taylor", colorHex: "")]
        let feeds = [feed(at: date(2026, 7, 21, 17, 30))]
        let occs = schedule(feeds: feeds, now: date(2026, 7, 21, 22, 0),
                            parents: solo).occurrences()
        XCTAssertTrue(occs.allSatisfy { $0.assignedToID == nil })
    }

    // MARK: Per-night overrides

    private func override(slotID: UUID, dayKey: Int, assignedToID: UUID? = nil,
                          name: String = "", skipped: Bool = false, minute: Int? = nil,
                          deleted: Bool = false, createdAt: Date = .distantPast) -> PlanOverride {
        let o = PlanOverride(slotID: slotID, dayKey: dayKey,
                             assignedToID: assignedToID, assignedToName: name,
                             isSkipped: skipped, minuteOfDayOverride: minute,
                             createdByID: taylorID)
        o.createdAt = createdAt
        if deleted { o.deletedAt = .distantPast }
        return o
    }

    /// A live move override on the night's FIRST slot — the manual anchor.
    private func manualAnchor(minute: Int, nightKey: Int = 20_260_721,
                              assignedToID: UUID? = nil, name: String = "",
                              deleted: Bool = false) -> PlanOverride {
        override(slotID: NightSchedule.syntheticSlotID(nightKey: nightKey, index: 0),
                 dayKey: nightKey, assignedToID: assignedToID, name: name,
                 minute: minute, deleted: deleted)
    }

    // MARK: Manual first-feed anchor

    func testManualAnchorRetimesTheWholeNight() {
        // No feeds at all; a parent set tonight's first feed to 10:30pm —
        // the night runs 10:30, 2:30, 6:30 instead of the 9pm default.
        let occs = schedule(overrides: [manualAnchor(minute: 22 * 60 + 30)],
                            now: date(2026, 7, 21, 22, 0)).occurrences()
        XCTAssertEqual(occs.map(\.date), [
            date(2026, 7, 21, 22, 30), date(2026, 7, 22, 2, 30), date(2026, 7, 22, 6, 30),
        ])
        XCTAssertNotNil(occs[0].activeOverrideID,
                        "the anchor row carries its override so Undo is offered")
    }

    func testManualAnchorBeatsLoggedFeed() {
        // A stray 9:05pm bottle would anchor the night, but the parents said
        // 10pm — their word wins; undoing the change restores the computed
        // anchor.
        let stray = feed(at: date(2026, 7, 21, 21, 5))
        let manual = manualAnchor(minute: 22 * 60)
        let occs = schedule(feeds: [stray], overrides: [manual],
                            now: date(2026, 7, 21, 22, 30)).occurrences()
        XCTAssertEqual(occs.first?.date, date(2026, 7, 21, 22, 0))

        let undone = schedule(feeds: [stray],
                              overrides: [manualAnchor(minute: 22 * 60, deleted: true)],
                              now: date(2026, 7, 21, 22, 30)).occurrences()
        XCTAssertEqual(undone.first?.date, date(2026, 7, 21, 21, 5),
                       "undo falls back to the logged anchor")
    }

    func testManualAnchorSmallHoursRollsToMorning() {
        // "First feed at 1:30am" belongs to tomorrow morning, not this
        // afternoon: 1:30am → 5:30am (9:30 overshoots the 8am close).
        let occs = schedule(overrides: [manualAnchor(minute: 90)],
                            now: date(2026, 7, 21, 22, 0)).occurrences()
        XCTAssertEqual(occs.map(\.date), [
            date(2026, 7, 22, 1, 30), date(2026, 7, 22, 5, 30),
        ])
    }

    func testManualAnchorInGraceHourExtendsTheFarEnd() {
        // 8:30pm — inside the grace hour before the 9pm window; the night
        // keeps its full length, running 30 minutes past the 8am close.
        let occs = schedule(overrides: [manualAnchor(minute: 20 * 60 + 30)],
                            now: date(2026, 7, 21, 22, 0)).occurrences()
        XCTAssertEqual(occs.map(\.date), [
            date(2026, 7, 21, 20, 30), date(2026, 7, 22, 0, 30),
            date(2026, 7, 22, 4, 30), date(2026, 7, 22, 8, 30),
        ])
    }

    func testManualAnchorOutsideWindowIsIgnored() {
        // Noon is no night — a nonsense manual time must not hijack the
        // schedule; the window-start default stands.
        let occs = schedule(overrides: [manualAnchor(minute: 12 * 60)],
                            now: date(2026, 7, 21, 22, 0)).occurrences()
        XCTAssertEqual(occs.first?.date, date(2026, 7, 21, 21, 0))
    }

    func testManualAnchorCarriesItsAssignee() {
        let manual = manualAnchor(minute: 22 * 60, assignedToID: katieID, name: "Katie")
        let occs = schedule(overrides: [manual], now: date(2026, 7, 21, 22, 0),
                            firstShiftID: taylorID).occurrences()
        XCTAssertEqual(occs[0].assignedToName, "Katie",
                       "the move carried tonight's assignee — re-timing never drops a swap")
        XCTAssertEqual(occs[1].assignedToName, "Katie",
                       "later slots still follow the rotation (slot 1 from Taylor's first shift)")
        // (Taylor first shift → slot 1 is Katie by rotation — both hold.)
    }

    func testManualAnchorShowsApproachingBeforeTheWindow() {
        // 6pm, no feeds: normally .day — but a manually set first feed means
        // tonight is planned, so the card surfaces.
        let state = schedule(overrides: [manualAnchor(minute: 22 * 60)],
                             now: date(2026, 7, 21, 18, 0)).state
        if case .approaching(let occs) = state {
            XCTAssertEqual(occs.first?.date, date(2026, 7, 21, 22, 0))
        } else {
            XCTFail("a manually planned night should surface in the evening run-up, got \(state)")
        }
    }

    func testOverrideReassignsOneNightSlot() {
        // Rotation says slot 1 (3:30am) is Katie's; tonight it's overridden
        // back to Taylor. The other slots keep the rotation.
        let feeds = [feed(at: date(2026, 7, 21, 17, 30))]
        let o = override(slotID: NightSchedule.syntheticSlotID(nightKey: 20_260_721, index: 1),
                         dayKey: 20_260_721, assignedToID: taylorID, name: "Taylor")
        let occs = schedule(feeds: feeds, overrides: [o], now: date(2026, 7, 21, 22, 0),
                            firstShiftID: katieID).occurrences()

        XCTAssertEqual(occs.map(\.assignedToName), ["Katie", "Taylor", "Katie"])
        XCTAssertEqual(occs[1].activeOverrideID, o.id, "the swapped row carries its override for undo")
        XCTAssertNil(occs[0].activeOverrideID)
    }

    func testSkipOverrideSilencesOneNightSlot() {
        let feeds = [feed(at: date(2026, 7, 21, 17, 30))]
        let o = override(slotID: NightSchedule.syntheticSlotID(nightKey: 20_260_721, index: 1),
                         dayKey: 20_260_721, skipped: true)
        let occs = schedule(feeds: feeds, overrides: [o], now: date(2026, 7, 21, 22, 0)).occurrences()

        XCTAssertEqual(occs[1].status, .skipped)
        XCTAssertEqual(occs[2].status, .upcoming, "only the skipped night goes quiet")
    }

    func testDeletedOverrideDoesNotApply() {
        let feeds = [feed(at: date(2026, 7, 21, 17, 30))]
        let o = override(slotID: NightSchedule.syntheticSlotID(nightKey: 20_260_721, index: 1),
                         dayKey: 20_260_721, skipped: true, deleted: true)
        let occs = schedule(feeds: feeds, overrides: [o], now: date(2026, 7, 21, 22, 0)).occurrences()
        XCTAssertEqual(occs[1].status, .upcoming, "an undone override leaves the rotation in charge")
    }

    func testOverrideSurvivesReanchoring() {
        // Override tonight's SECOND feed, then the anchor shifts (real feed at
        // 11:10 instead of the projected 11:30) — the override stays attached
        // to "tonight's second feed", whatever its time now is.
        let projected = [feed(at: date(2026, 7, 21, 17, 30))]
        let o = override(slotID: NightSchedule.syntheticSlotID(nightKey: 20_260_721, index: 1),
                         dayKey: 20_260_721, assignedToID: taylorID, name: "Taylor")
        let before = schedule(feeds: projected, overrides: [o],
                              now: date(2026, 7, 21, 22, 0), firstShiftID: katieID).occurrences()
        XCTAssertEqual(before[1].assignedToName, "Taylor")

        let anchored = projected + [feed(at: date(2026, 7, 21, 23, 10))]
        let after = schedule(feeds: anchored, overrides: [o],
                             now: date(2026, 7, 21, 23, 30), firstShiftID: katieID).occurrences()
        XCTAssertEqual(after[1].date, date(2026, 7, 22, 3, 10))
        XCTAssertEqual(after[1].assignedToName, "Taylor",
                       "slot identity is ordinal — the swap follows the re-anchored time")
    }

    func testConcurrentOverridesResolveDeterministically() {
        let feeds = [feed(at: date(2026, 7, 21, 17, 30))]
        let slotID = NightSchedule.syntheticSlotID(nightKey: 20_260_721, index: 1)
        let older = override(slotID: slotID, dayKey: 20_260_721, assignedToID: taylorID,
                             name: "Taylor", createdAt: date(2026, 7, 21, 20, 0))
        let newer = override(slotID: slotID, dayKey: 20_260_721, assignedToID: katieID,
                             name: "Katie", createdAt: date(2026, 7, 21, 20, 5))
        let occs = schedule(feeds: feeds, overrides: [older, newer],
                            now: date(2026, 7, 21, 22, 0)).occurrences()
        XCTAssertEqual(occs[1].assignedToName, "Katie", "latest createdAt wins on both phones")
    }

    // MARK: Fulfillment & overdue

    func testLaterFeedFulfillsItsNearbySlot() {
        let anchor = feed(at: date(2026, 7, 21, 23, 30))
        let threeThirtyFive = feed(at: date(2026, 7, 22, 3, 35))
        let occs = schedule(feeds: [anchor, threeThirtyFive],
                            now: date(2026, 7, 22, 4, 0)).occurrences()

        XCTAssertEqual(occs[1].status, .fulfilled(byEventID: threeThirtyFive.id),
                       "a bottle near the 3:30 slot ticks it off")
        XCTAssertEqual(occs[2].status, .upcoming)
    }

    func testUnfulfilledPastSlotReadsOverdue() {
        let anchor = feed(at: date(2026, 7, 21, 23, 30))
        let occs = schedule(feeds: [anchor], now: date(2026, 7, 22, 5, 0)).occurrences()
        XCTAssertEqual(occs[1].status, .overdue, "3:30am came and went with no bottle")
    }

    // MARK: Identity

    func testOccurrenceIDsAreStableAndKeyedToTheNight() {
        // The night is keyed to the day it STARTED, even after midnight —
        // ids, synthetic slot ids, AND dayKey (the override key) all hold.
        let anchor = feed(at: date(2026, 7, 21, 23, 30))
        let evening = schedule(feeds: [anchor], now: date(2026, 7, 21, 23, 45)).occurrences()
        let smallHours = schedule(feeds: [anchor], now: date(2026, 7, 22, 2, 0)).occurrences()

        XCTAssertEqual(evening.map(\.id), smallHours.map(\.id),
                       "ids must survive midnight so rows/reminders self-replace")
        XCTAssertEqual(evening[0].id, "night.20260721.0")
        XCTAssertEqual(evening.map(\.slotID), smallHours.map(\.slotID))
        XCTAssertTrue(evening.allSatisfy { $0.dayKey == 20_260_721 },
                      "dayKey is the NIGHT's key — overrides must match across midnight")
    }
}

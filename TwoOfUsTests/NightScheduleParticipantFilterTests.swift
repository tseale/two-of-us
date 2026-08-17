import XCTest
@testable import TwoOfUs

/// Tests for `NightSchedule.init(settings:participants:...)` — the app-model
/// entry point that filters/orders `Participant` rows into the rotation
/// roster. Covers the two nighttime-schedule bugs reported together: a guest
/// (non-co-parent) participant showing up in the default rotation, and that
/// same guest corrupting sleep-window-aware assignment (a participant with no
/// sleep window reads as permanently awake, so leaving them in the roster
/// broke the "don't assign the sleeping co-parent" logic even for the real
/// co-parents).
final class NightScheduleParticipantFilterTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        return c
    }()

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    private func makeSettings(startMinute: Int = 20 * 60, endMinute: Int = 8 * 60,
                              spacing: Int = 150) -> SharedSettings {
        SharedSettings(nightStartMinute: startMinute, nightEndMinute: endMinute,
                      nightFeedSpacingMinutes: spacing, nightRotation: .alternating)
    }

    func testGuestParticipantIsExcludedFromTheDefaultRotation() {
        let taylor = Participant(displayName: "Taylor", colorHex: "#AABBCC", role: .full)
        let katie = Participant(displayName: "Katie", colorHex: "#112233", role: .full)
        let buddy = Participant(displayName: "Buddy", colorHex: "#DDCCBB", role: .logger)

        let night = NightSchedule(settings: makeSettings(),
                                  participants: [taylor, katie, buddy],
                                  feeds: [], now: date(2026, 8, 17, 21, 0))

        let occurrences = night.occurrences()
        XCTAssertFalse(occurrences.isEmpty)
        for occ in occurrences {
            XCTAssertNotEqual(occ.assignedToID, buddy.id,
                              "a guest/pet participant must never take a default rotation slot")
        }
    }

    /// The reported bug, reproduced end to end: GT is planned-asleep 8pm–2:30am,
    /// Taylor is not, and a non-co-parent participant sits in the roster too.
    /// Bottles inside GT's sleep window must still go to Taylor — the guest's
    /// absent sleep window must not read as "always awake" and short-circuit
    /// the routing to a dead tie.
    func testSleepingCoParentIsNotAssignedABottleEvenWithAGuestInTheRoster() {
        let taylor = Participant(displayName: "Taylor", colorHex: "#AABBCC", role: .full)
        let gt = Participant(displayName: "GT", colorHex: "#112233", role: .full)
        let buddy = Participant(displayName: "Buddy", colorHex: "#DDCCBB", role: .logger)

        let settings = makeSettings(startMinute: 20 * 60, endMinute: 8 * 60, spacing: 120)
        let sleepSlot = PlanSlot(kind: .sleep, minuteOfDay: 20 * 60, endMinuteOfDay: 2 * 60 + 30,
                                 assignedToID: gt.id, assignedToName: "GT", assignedToColorHex: "#112233")

        let night = NightSchedule(settings: settings,
                                  participants: [taylor, gt, buddy],
                                  feeds: [], sleepSlots: [sleepSlot],
                                  calendar: calendar, now: date(2026, 8, 17, 21, 0))

        let tenPM = night.occurrences().first { $0.date == date(2026, 8, 17, 22, 0) }
        XCTAssertEqual(tenPM?.assignedToID, taylor.id,
                       "GT is planned-asleep at 10pm — the bottle must route to Taylor, who's awake")
        XCTAssertNotEqual(tenPM?.assignedToID, gt.id)
        XCTAssertNotEqual(tenPM?.assignedToID, buddy.id)
    }

    func testInactiveCoParentIsExcludedAlongsideGuests() {
        let taylor = Participant(displayName: "Taylor", colorHex: "#AABBCC", role: .full)
        let departed = Participant(displayName: "Departed", colorHex: "#112233", role: .full,
                                   isActive: false)
        let buddy = Participant(displayName: "Buddy", colorHex: "#DDCCBB", role: .logger)

        let night = NightSchedule(settings: makeSettings(),
                                  participants: [taylor, departed, buddy],
                                  feeds: [], now: date(2026, 8, 17, 21, 0))

        // A solo remaining co-parent leaves rotation slots unassigned rather
        // than assigning to anyone who shouldn't be on duty.
        for occ in night.occurrences() {
            XCTAssertNil(occ.assignedToID)
        }
    }
}

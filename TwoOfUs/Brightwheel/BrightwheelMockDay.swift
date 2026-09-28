import Foundation

/// A realistic simulated daycare day, emitted as the same DTOs the live API
/// decodes into — so "Load sample daycare day" exercises the entire import
/// pipeline, and swapping in real data is a data change, not a code change.
///
/// The day is Miller-realistic at ~2 months: 4–5 oz bottles, 45 min–1.5 h
/// naps. Object ids are deterministic (`mock-<day>-<slot>`), which makes the
/// sample idempotent to re-load and lets "Remove sample day" find exactly
/// what it inserted.
enum BrightwheelMockDay {
    static let idPrefix = "mock-"

    static func activities(for day: Date = .now, calendar: Calendar = .current) -> [BrightwheelActivity] {
        let dayKey = day.formatted(.iso8601.year().month().day())
        func at(_ hour: Int, _ minute: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        // Matches the live API's UTC ISO-8601 encoding, so the mock exercises
        // the same parse path (`BrightwheelActivity.parseDate`) as real data.
        func iso(_ date: Date) -> String {
            ISO8601DateFormatter().string(from: date)
        }
        func id(_ slot: String) -> String { "\(idPrefix)\(dayKey)-\(slot)" }
        let staff = BrightwheelActivity.Person(firstName: "Ms.", lastName: "Rivera")
        let room = BrightwheelActivity.Room(name: "Infant Room")

        func activity(_ slot: String, _ action: String, _ when: Date,
                      note: String? = nil,
                      details: BrightwheelActivity.DetailsBlob? = nil) -> BrightwheelActivity {
            BrightwheelActivity(objectID: id(slot), actionType: action,
                                eventDate: iso(when), createdAt: iso(when),
                                note: note, staffOnly: false,
                                detailsBlob: details, actor: staff, room: room)
        }

        return [
            activity("dropoff", "ac_checkin", at(7, 30),
                     note: "Dropped off by Dad",
                     details: .init(tags: ["Checked in"])),
            activity("feed-1", "ac_food", at(9, 0),
                     note: "Took the whole bottle",
                     details: .init(amount: 4)),
            activity("nap-1", "ac_nap", at(10, 30),
                     details: .init(startTime: iso(at(9, 45)), endTime: iso(at(10, 30)))),
            activity("diaper-1", "ac_potty", at(10, 45),
                     details: .init(tags: ["Wet"])),
            activity("feed-2", "ac_food", at(12, 0),
                     details: .init(amount: 5)),
            activity("nap-2", "ac_nap", at(14, 15),
                     note: "Slept great!",
                     details: .init(startTime: iso(at(12, 45)), endTime: iso(at(14, 15)))),
            activity("diaper-2", "ac_potty", at(14, 30),
                     details: .init(tags: ["BM"])),
            activity("feed-3", "ac_food", at(15, 0),
                     note: "A little fussy, took most of it",
                     details: .init(amount: 4)),
            activity("pickup", "ac_checkin", at(16, 30),
                     details: .init(tags: ["Checked out", "Picked up by Mom"])),
        ]
    }
}

import Foundation

/// A realistic simulated daycare day, emitted as a raw JSON document in the
/// REAL wire format — same field names, nesting, ordering (newest-first),
/// timestamp encoding, and pagination wrapper as
/// `GET /students/{id}/activities` — then decoded by the same `JSONDecoder`
/// path the network response takes. Swapping mock → real is a change of data
/// source, with zero transformation code in between.
///
/// The day is Miller-realistic at ~2 months: 4–5 oz bottles, 45 min–1.5 h
/// naps. Naps are two activities each (fell asleep `state:"1"`, woke up
/// `state:"0"`), exactly as the live API delivers them. Object ids are
/// deterministic (`mock-<day>-<slot>`), which makes the sample idempotent to
/// re-load and lets "Remove sample day" find exactly what it inserted.
enum BrightwheelMockDay {
    static let idPrefix = "mock-"

    /// The decoded activities, via the raw JSON below — never constructed
    /// directly, so the mock exercises every line of the decode path.
    static func activities(for day: Date = .now, calendar: Calendar = .current) -> [BrightwheelActivity] {
        let data = responseData(for: day, calendar: calendar)
        let page = (try? JSONDecoder().decode(BrightwheelActivityPage.self, from: data))
        return page?.activities ?? []
    }

    /// The full mock response document, byte-comparable to a live capture.
    static func responseData(for day: Date = .now, calendar: Calendar = .current) -> Data {
        let dayKey = day.formatted(.iso8601.year().month().day())
        func at(_ hour: Int, _ minute: Int) -> String {
            let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.string(from: date)
        }
        func id(_ slot: String) -> String { "\(idPrefix)\(dayKey)-\(slot)" }
        let staff: [String: Any] = ["object_id": id("staff"), "first_name": "Amanda",
                                    "last_name": "R", "user_type": "employee"]
        let student: [String: Any] = ["object_id": id("student"), "first_name": "Miller",
                                      "last_name": "Seale"]
        let room: [String: Any] = ["object_id": id("room"), "name": "Infant Room"]

        func activity(_ slot: String, _ action: String, _ when: String,
                      note: String? = nil, state: String? = nil,
                      details: [String: Any]? = nil,
                      menuItems: [String]? = nil) -> [String: Any] {
            var a: [String: Any] = [
                "object_id": id(slot),
                "action_type": action,
                "event_date": when,
                "created_at": when,
                "staff_only": false,
                "actor": staff,
                "target": student,
                "room": room,
                "note": note as Any,
                "media": NSNull(),
                "video_info": NSNull(),
                "likes": 0,
            ]
            if let state { a["state"] = state }
            if let details { a["details_blob"] = details }
            if let menuItems { a["menu_item_tags"] = menuItems.map { ["name": $0] } }
            return a
        }

        func bottle(_ slot: String, _ when: String, oz: Double, note: String? = nil) -> [String: Any] {
            activity(slot, "ac_food", when, note: note,
                     details: ["food_type": "bottle", "amount": oz, "amount_type": "oz"],
                     menuItems: ["Bottle"])
        }

        // Newest first, matching the live API's delivery order.
        let activities: [[String: Any]] = [
            activity("pickup", "ac_checkin", at(16, 30), note: "Picked up by Mom",
                     details: ["tags": ["Checked out"]]),
            bottle("feed-3", at(15, 0), oz: 4, note: "A little fussy, took most of it"),
            activity("diaper-2", "ac_potty", at(14, 30),
                     details: ["potty_type": "bm", "potty_extras": ["diaper_cream"]]),
            activity("nap-2-end", "ac_nap", at(14, 15), note: "Slept great!", state: "0"),
            activity("nap-2-start", "ac_nap", at(12, 45), state: "1"),
            bottle("feed-2", at(12, 0), oz: 5),
            activity("diaper-1", "ac_potty", at(10, 45),
                     details: ["potty_type": "wet", "potty_extras": []]),
            activity("nap-1-end", "ac_nap", at(10, 30), state: "0"),
            activity("nap-1-start", "ac_nap", at(9, 45), state: "1"),
            bottle("feed-1", at(9, 0), oz: 4, note: "Took the whole bottle"),
            activity("dropoff", "ac_checkin", at(7, 30), note: "Dropped off by Dad",
                     details: ["tags": ["Checked in"]]),
        ]
        let page: [String: Any] = [
            "activities": activities,
            "count": activities.count,
            "offset": 0,
            "page": 0,
            "page_size": 100,
        ]
        return (try? JSONSerialization.data(withJSONObject: page)) ?? Data()
    }
}

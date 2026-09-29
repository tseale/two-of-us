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
///
/// One honest caveat: the day now also exercises every daycare-era event
/// type, and a few of those shapes are beyond what the 2026-09-28 source pass
/// verified — the medication / health-check / activity `details_blob` keys,
/// and the `ac_mood` / potty entries (marked SPECULATIVE inline). They decode
/// through the same defensive path as everything else, so a wrong guess
/// degrades gracefully; re-check them against the first live capture on
/// Miller's first day and correct both this file and the DTOs.
enum BrightwheelMockDay {
    static let idPrefix = "mock-"

    /// The decoded activities, via the raw JSON below — never constructed
    /// directly, so the mock exercises every line of the decode path.
    static func activities(for day: Date = .now, calendar: Calendar = .current) -> [BrightwheelActivity] {
        let data = responseData(for: day, calendar: calendar)
        let page = (try? JSONDecoder().decode(BrightwheelActivityPage.self, from: data))
        return page?.activities ?? []
    }

    /// The full mock response document, structured like a live capture.
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
                      menuItems: [String]? = nil,
                      media: [String: Any]? = nil,
                      videoInfo: [String: Any]? = nil) -> [String: Any] {
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
                "media": media ?? NSNull(),
                "video_info": videoInfo ?? NSNull(),
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

        // Signed-CDN-shaped links (unreachable on purpose — the UI's
        // placeholder path is exactly what an expired real link exercises).
        func mediaLinks(_ slot: String) -> [String: Any] {
            ["image_url": "https://cdn.mybrightwheel.com/media/\(id(slot)).jpg",
             "thumbnail_url": "https://cdn.mybrightwheel.com/media/\(id(slot))-thumb.jpg"]
        }

        // Newest first, matching the live API's delivery order.
        let activities: [[String: Any]] = [
            activity("pickup", "ac_checkin", at(16, 30), note: "Picked up by Mom",
                     details: ["tags": ["Checked out"]]),
            activity("kudo", "ac_kudo", at(16, 15),
                     note: "Miller was so smiley today — we loved having him!"),
            // SPECULATIVE potty entry: infant rooms won't send these for
            // months; included so the PottyEvent path renders end to end.
            activity("potty", "ac_bathroom", at(15, 45),
                     note: "Sat on the potty before pickup — just practicing!",
                     details: ["potty_type": "potty", "potty_extras": []]),
            activity("photo", "ac_photo", at(15, 30), note: "All smiles after his bottle",
                     media: mediaLinks("photo")),
            bottle("feed-3", at(15, 0), oz: 4, note: "A little fussy, took most of it"),
            activity("diaper-2", "ac_potty", at(14, 30),
                     details: ["potty_type": "bm", "potty_extras": ["diaper_cream"]]),
            activity("milestone", "ac_observation", at(14, 20),
                     note: "Rolled from tummy to back for the first time!",
                     details: ["tags": ["Physical"]]),
            activity("nap-2-end", "ac_nap", at(14, 15), note: "Slept great!", state: "0"),
            activity("nap-2-start", "ac_nap", at(12, 45), state: "1"),
            // SPECULATIVE mood entry: `ac_mood` is not in the verified
            // taxonomy; the importer handles it defensively if it ever comes.
            activity("mood", "ac_mood", at(12, 30), note: "Happy as a clam all morning",
                     details: ["mood": "happy"]),
            bottle("feed-2", at(12, 0), oz: 5),
            activity("meds", "ac_medication", at(11, 30), note: "Tylenol for teething, per Mom",
                     details: ["medication_name": "Tylenol", "dosage": "2.5 ml"]),
            activity("video", "ac_video", at(11, 15), note: "Giggling at the mirror",
                     videoInfo: ["streamable_url": "https://cdn.mybrightwheel.com/video/\(id("video")).m3u8",
                                 "downloadable_url": "https://cdn.mybrightwheel.com/video/\(id("video")).mp4"]),
            activity("activity", "ac_activity", at(11, 0), note: "Tummy time on the play mat",
                     details: ["duration": 15, "tags": ["Tummy Time"]]),
            activity("diaper-1", "ac_potty", at(10, 45),
                     details: ["potty_type": "wet", "potty_extras": []]),
            activity("nap-1-end", "ac_nap", at(10, 30), state: "0"),
            activity("nap-1-start", "ac_nap", at(9, 45), state: "1"),
            bottle("feed-1", at(9, 0), oz: 4, note: "Took the whole bottle"),
            activity("health", "ac_health_check", at(7, 35),
                     note: "Temp 98.6°F at drop-off check",
                     details: ["temperature": 98.6]),
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

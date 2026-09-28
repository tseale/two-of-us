import Foundation

/// Decodable layer over `GET /students/{id}/activities`.
///
/// Field names and shapes are the REAL wire format, cross-checked 2026-09-28
/// against three independent parsers of the live API (see
/// docs/BRIGHTWHEEL-INTEGRATION.md §3): the brightwheel-home-assistant
/// integration (bottle/nap/diaper parsing), brightwheel-takeout's test
/// fixtures, and hubot-brightwheel (whose potty shape matches HA's across a
/// five-year gap — the stable core). The wrapper shape was verified against
/// Taylor's live account.
///
/// Every field stays optional on purpose: the API is unofficial, and a field
/// Brightwheel renames degrades one activity to "skipped", never a decode
/// failure that drops the whole page. `BrightwheelMockDay` emits this same
/// wire format as raw JSON, so mock and real data share every line of the
/// decode + import path.
struct BrightwheelActivityPage: Decodable, Sendable {
    let activities: [BrightwheelActivity]
    let count: Int?
    let page: Int?
    let pageSize: Int?

    enum CodingKeys: String, CodingKey {
        case activities, count, page
        case pageSize = "page_size"
    }
}

struct BrightwheelActivity: Decodable, Sendable {
    let objectID: String?
    let actionType: String?
    /// When it happened (staff can backdate); `createdAt` is when it was typed.
    let eventDate: String?
    let createdAt: String?
    let note: String?
    /// Naps: "1" = fell asleep, "0" = woke up — a nap is TWO activities,
    /// paired by the importer. Arrives as a string, occasionally a number,
    /// sometimes inside `details_blob` instead (the decoder normalizes).
    let state: String?
    let staffOnly: Bool?
    let detailsBlob: DetailsBlob?
    let actor: Person?
    let target: Person?
    let room: Room?
    let menuItemTags: [MenuItem]?

    enum CodingKeys: String, CodingKey {
        case objectID = "object_id"
        case actionType = "action_type"
        case eventDate = "event_date"
        case createdAt = "created_at"
        case note, state
        case staffOnly = "staff_only"
        case detailsBlob = "details_blob"
        case actor, target, room
        case menuItemTags = "menu_item_tags"
    }

    struct Person: Decodable, Sendable {
        let objectID: String?
        let firstName: String?
        let lastName: String?
        enum CodingKeys: String, CodingKey {
            case objectID = "object_id"
            case firstName = "first_name"
            case lastName = "last_name"
        }
    }

    struct Room: Decodable, Sendable {
        let name: String?
    }

    struct MenuItem: Decodable, Sendable {
        let name: String?
    }

    /// The per-type payload. Bottles: `food_type == "bottle"`, numeric
    /// `amount` + `amount_type` ("oz"/"ml"). Diapers: `potty_type`
    /// ("wet"/"bm"/"dry") + `potty_extras`. Naps: may duplicate `state`.
    /// `amount` tolerates string/number wire encodings — and non-numeric
    /// values like "most" (solids), which parse to nil.
    struct DetailsBlob: Decodable, Sendable {
        let foodType: String?
        let amount: Double?
        let amountType: String?
        let pottyType: String?
        let pottyExtras: [String]?
        let state: String?
        let tags: [String]?

        enum CodingKeys: String, CodingKey {
            case foodType = "food_type"
            case amount
            case amountType = "amount_type"
            case pottyType = "potty_type"
            case pottyExtras = "potty_extras"
            case state, tags
        }

        init(foodType: String? = nil, amount: Double? = nil, amountType: String? = nil,
             pottyType: String? = nil, pottyExtras: [String]? = nil,
             state: String? = nil, tags: [String]? = nil) {
            self.foodType = foodType
            self.amount = amount
            self.amountType = amountType
            self.pottyType = pottyType
            self.pottyExtras = pottyExtras
            self.state = state
            self.tags = tags
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            foodType = try? c.decode(String.self, forKey: .foodType)
            if let d = try? c.decode(Double.self, forKey: .amount) {
                amount = d
            } else if let s = try? c.decode(String.self, forKey: .amount) {
                amount = Double(s)
            } else {
                amount = nil
            }
            amountType = try? c.decode(String.self, forKey: .amountType)
            pottyType = try? c.decode(String.self, forKey: .pottyType)
            pottyExtras = try? c.decode([String].self, forKey: .pottyExtras)
            if let s = try? c.decode(String.self, forKey: .state) {
                state = s
            } else if let n = try? c.decode(Int.self, forKey: .state) {
                state = String(n)
            } else {
                state = nil
            }
            tags = try? c.decode([String].self, forKey: .tags)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        objectID = try? c.decode(String.self, forKey: .objectID)
        actionType = try? c.decode(String.self, forKey: .actionType)
        eventDate = try? c.decode(String.self, forKey: .eventDate)
        createdAt = try? c.decode(String.self, forKey: .createdAt)
        note = try? c.decode(String.self, forKey: .note)
        if let s = try? c.decode(String.self, forKey: .state) {
            state = s
        } else if let n = try? c.decode(Int.self, forKey: .state) {
            state = String(n)
        } else {
            state = nil
        }
        staffOnly = try? c.decode(Bool.self, forKey: .staffOnly)
        detailsBlob = try? c.decode(DetailsBlob.self, forKey: .detailsBlob)
        actor = try? c.decode(Person.self, forKey: .actor)
        target = try? c.decode(Person.self, forKey: .target)
        room = try? c.decode(Room.self, forKey: .room)
        menuItemTags = try? c.decode([MenuItem].self, forKey: .menuItemTags)
    }

    /// Brightwheel timestamps are UTC ISO-8601 with fractional seconds; accept
    /// the plain variant too since the fractional part is an observation, not
    /// a contract.
    static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        return plain.date(from: string)
    }

    var when: Date? { Self.parseDate(eventDate) ?? Self.parseDate(createdAt) }

    /// Nap state, wherever the wire put it.
    var napState: String? { state ?? detailsBlob?.state }

    /// Bottle detection, HA-style: explicit `food_type`, else keyword
    /// fallback for older entries, else "no menu items" (solids carry them).
    var isBottle: Bool {
        guard actionType == "ac_food" else { return false }
        if let foodType = detailsBlob?.foodType { return foodType == "bottle" }
        let lowered = (note ?? "").lowercased()
        for keyword in ["bottle", "formula", "breast milk", "breastmilk", "oz", "ml"]
        where lowered.contains(keyword) { return true }
        return (menuItemTags ?? []).isEmpty
    }

    /// Bottle amount normalized to ounces (ml converts; non-numeric amounts
    /// like "most" are nil and fall back to a note import).
    var bottleOz: Double? {
        guard let amount = detailsBlob?.amount, amount > 0 else { return nil }
        let unit = (detailsBlob?.amountType ?? "").lowercased()
        if unit.contains("ml") { return amount / 29.5735 }
        return amount
    }
}

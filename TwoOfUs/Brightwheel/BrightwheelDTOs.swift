import Foundation

/// Decodable layer over `GET /students/{id}/activities`
/// (docs/BRIGHTWHEEL-INTEGRATION.md §3). Every field is optional on purpose:
/// the schema is unofficial and only the wrapper shape has been verified live
/// (2026-09-28); a field Brightwheel renames degrades that activity to
/// "skipped", never to a decode failure that drops the whole page. The mock
/// generator (`BrightwheelMockDay`) emits these same DTOs, so the import
/// pipeline is identical for sample and real data.
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
    let staffOnly: Bool?
    let detailsBlob: DetailsBlob?
    let actor: Person?
    let room: Room?

    enum CodingKeys: String, CodingKey {
        case objectID = "object_id"
        case actionType = "action_type"
        case eventDate = "event_date"
        case createdAt = "created_at"
        case note
        case staffOnly = "staff_only"
        case detailsBlob = "details_blob"
        case actor, room
    }

    struct Person: Decodable, Sendable {
        let firstName: String?
        let lastName: String?
        enum CodingKeys: String, CodingKey {
            case firstName = "first_name"
            case lastName = "last_name"
        }
    }

    struct Room: Decodable, Sendable {
        let name: String?
    }

    /// The per-type payload. Real shapes are unverified (research §3), so
    /// amounts tolerate both string and number encodings and everything else
    /// rides on `tags`.
    struct DetailsBlob: Decodable, Sendable {
        let tags: [String]?
        let amount: Double?
        let startTime: String?
        let endTime: String?

        enum CodingKeys: String, CodingKey {
            case tags, amount
            case startTime = "start_time"
            case endTime = "end_time"
        }

        init(tags: [String]? = nil, amount: Double? = nil,
             startTime: String? = nil, endTime: String? = nil) {
            self.tags = tags
            self.amount = amount
            self.startTime = startTime
            self.endTime = endTime
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            tags = try? c.decode([String].self, forKey: .tags)
            if let d = try? c.decode(Double.self, forKey: .amount) {
                amount = d
            } else if let s = try? c.decode(String.self, forKey: .amount) {
                amount = Double(s)
            } else {
                amount = nil
            }
            startTime = try? c.decode(String.self, forKey: .startTime)
            endTime = try? c.decode(String.self, forKey: .endTime)
        }
    }

    init(objectID: String?, actionType: String?, eventDate: String?,
         createdAt: String? = nil, note: String? = nil, staffOnly: Bool? = nil,
         detailsBlob: DetailsBlob? = nil, actor: Person? = nil, room: Room? = nil) {
        self.objectID = objectID
        self.actionType = actionType
        self.eventDate = eventDate
        self.createdAt = createdAt
        self.note = note
        self.staffOnly = staffOnly
        self.detailsBlob = detailsBlob
        self.actor = actor
        self.room = room
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
    var end: Date? { Self.parseDate(detailsBlob?.endTime) }
}

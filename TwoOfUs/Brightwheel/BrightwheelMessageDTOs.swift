import Foundation

/// Decodable layer over Brightwheel's guardian messaging (API **v2**, unlike
/// the v1 activity feed):
///
/// - `GET /guardians/{id}/message_threads` → `{results: [thread], has_more, page_size}`
/// - `GET /guardians/{id}/message_threads/{thread_id}/messages?page_limit=&starting_after=`
///   → `{results: [{message: {...}}], has_more, page_size}`
///
/// Shapes are lifted from the zod schemas in the live web bundle (fetched
/// 2026-11-17, see docs/BRIGHTWHEEL-INTEGRATION.md §9). Same posture as the
/// activity DTOs: every field optional, so a rename degrades one message to
/// "skipped" instead of failing the page.
struct BrightwheelThreadPage: Decodable, Sendable {
    let results: [BrightwheelThread]
}

struct BrightwheelThread: Decodable, Sendable {
    let objectID: String?
    let threadID: String?
    let type: String?
    let student: Person?
    /// The thread's latest message — lets a sync skip threads with nothing new.
    let message: BrightwheelMessage?

    enum CodingKeys: String, CodingKey {
        case objectID = "object_id"
        case threadID = "thread_id"
        case type, student, message
    }

    struct Person: Decodable, Sendable {
        let objectID: String?
        enum CodingKeys: String, CodingKey { case objectID = "object_id" }
    }

    /// The id the messages endpoint takes. The bundle passes `thread_id`
    /// where present, `object_id` otherwise.
    var id: String? { threadID ?? objectID }
}

/// A list of messages in whichever wrapper the route uses: v2's
/// `{results: [{message: …}]}`, a flat `{results|messages|data: […]}`, or a
/// bare array. Only the v2 shape is in the bundle's schemas; the v1
/// per-child route's isn't, so this takes any of them.
struct BrightwheelMessagePage: Decodable, Sendable {
    let messages: [BrightwheelMessage]

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    /// One array element: either `{message: {...}}` or the message itself.
    private struct Element: Decodable {
        let message: BrightwheelMessage?
        init(from decoder: Decoder) throws {
            let keyed = try? decoder.container(keyedBy: Key.self)
            if let keyed, keyed.contains(Key(stringValue: "message")),
               let wrapped = try? keyed.decode(BrightwheelMessage.self, forKey: Key(stringValue: "message")) {
                message = wrapped
            } else {
                message = try? BrightwheelMessage(from: decoder)
            }
        }
    }

    init(from decoder: Decoder) throws {
        if let array = try? decoder.singleValueContainer().decode([Element].self) {
            messages = array.compactMap(\.message)
            return
        }
        let keyed = try decoder.container(keyedBy: Key.self)
        for name in ["results", "messages", "data"] {
            if let array = try? keyed.decode([Element].self, forKey: Key(stringValue: name)) {
                messages = array.compactMap(\.message)
                return
            }
        }
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                debugDescription: "no message list"))
    }
}

struct BrightwheelMessage: Decodable, Sendable {
    let objectID: String?
    let body: String?
    let createdAt: String?
    let type: String?               // simple_message | alert | reminder | newsletter_send | document_notification
    let broadcast: Bool?
    let sender: Sender?
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case objectID = "object_id"
        case body, type, broadcast, sender
        case createdAt = "created_at"
        case deletedAt = "deleted_at"
    }

    struct Sender: Decodable, Sendable {
        let firstName: String?
        let lastName: String?
        let userType: String?       // "guardian" for parents; staff otherwise

        enum CodingKeys: String, CodingKey {
            case firstName = "first_name"
            case lastName = "last_name"
            case userType = "user_type"
        }

        var displayName: String? {
            let parts = [firstName, lastName].compactMap { $0 }.filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts.joined(separator: " ")
        }
    }

    var when: Date? { BrightwheelActivity.parseDate(createdAt) }

    /// Written by a parent (us, or the co-parent) — never imported: the
    /// timeline wants what the daycare said.
    var isFromGuardian: Bool { sender?.userType?.lowercased() == "guardian" }
}

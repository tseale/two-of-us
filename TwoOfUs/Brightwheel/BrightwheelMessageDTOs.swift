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

struct BrightwheelMessagePage: Decodable, Sendable {
    struct Entry: Decodable, Sendable { let message: BrightwheelMessage? }
    let results: [Entry]
    var messages: [BrightwheelMessage] { results.compactMap(\.message) }
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

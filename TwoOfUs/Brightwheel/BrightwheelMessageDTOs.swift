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
    /// Photos (and the odd video or PDF) a teacher attached — the "Thanksgiving
    /// Week Dress-Up Days" flyer under "Next weeks festive days!". The bundle's
    /// schema names the field but not its element shape, so each element is
    /// read leniently (see `Attachment`); a message-level `media` block (the
    /// activity feed's shape) is honored too.
    let attachments: [Attachment]

    enum CodingKeys: String, CodingKey {
        case objectID = "object_id"
        case body, type, broadcast, sender, attachments, media
        case createdAt = "created_at"
        case deletedAt = "deleted_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        objectID = try? c.decode(String.self, forKey: .objectID)
        body = try? c.decode(String.self, forKey: .body)
        createdAt = try? c.decode(String.self, forKey: .createdAt)
        type = try? c.decode(String.self, forKey: .type)
        broadcast = try? c.decode(Bool.self, forKey: .broadcast)
        sender = try? c.decode(Sender.self, forKey: .sender)
        deletedAt = try? c.decode(String.self, forKey: .deletedAt)
        var found: [Attachment] = []
        if let list = try? c.decode([LooseJSON].self, forKey: .attachments) {
            found = list.compactMap(Attachment.init(json:))
        } else if let single = try? c.decode(LooseJSON.self, forKey: .attachments),
                  let one = Attachment(json: single) {
            found = [one]   // a lone object instead of a list
        }
        if found.isEmpty, let media = try? c.decode(LooseJSON.self, forKey: .media),
           let one = Attachment(json: media) {
            found = [one]
        }
        attachments = found
    }

    /// One attachment, distilled to the link worth storing and what it is.
    /// Brightwheel's element shape isn't in the bundle's zod schemas, so this
    /// takes any object (or bare URL string) and picks the best full-size
    /// http(s) link it holds — `image_url`/`url`/`file_url`/… over thumbnails,
    /// nested objects included — and reads the kind from a content-type-ish
    /// field, else the URL's extension.
    struct Attachment: Sendable, Equatable {
        enum Kind: Sendable, Equatable { case image, video, document }

        let objectID: String?
        let url: String
        let kind: Kind

        init(objectID: String?, url: String, kind: Kind) {
            self.objectID = objectID
            self.url = url
            self.kind = kind
        }

        init?(json: LooseJSON) {
            if case .string(let s) = json {
                guard Self.isLink(s) else { return nil }
                self.init(objectID: nil, url: s, kind: Self.kind(fromURL: s) ?? .image)
                return
            }
            guard case .object(let root) = json else { return nil }
            var links: [(key: String, url: String)] = []
            var typeHints: [String] = []
            func walk(_ value: LooseJSON, key: String) {
                switch value {
                case .string(let s):
                    if Self.isLink(s) {
                        links.append((key, s))
                    } else if Self.typeKeys.contains(key) {
                        typeHints.append(s.lowercased())
                    }
                case .object(let dict):
                    for (k, v) in dict { walk(v, key: k.lowercased()) }
                case .array(let items):
                    for item in items { walk(item, key: key) }
                default:
                    break
                }
            }
            for (k, v) in root { walk(v, key: k.lowercased()) }
            // Ties break on the key name: dictionary order isn't stable.
            guard let best = links.min(by: { (Self.rank($0.key), $0.key) < (Self.rank($1.key), $1.key) })
            else { return nil }

            let hinted: Kind? = typeHints.lazy.compactMap { hint -> Kind? in
                if hint.contains("image") || hint.contains("photo") || hint.contains("picture") { return .image }
                if hint.contains("video") || hint.contains("movie") { return .video }
                if hint.contains("pdf") || hint.contains("document") || hint.contains("application") { return .document }
                return nil
            }.first
            let keyed: Kind? = best.key.contains("video") || best.key.contains("stream") ? .video
                : best.key.contains("image") || best.key.contains("photo") ? .image : nil
            let objectID: String? = {
                for key in ["object_id", "id", "uuid"] {
                    if case .string(let s)? = root[key], !s.isEmpty { return s }
                    if case .number(let n)? = root[key] { return String(Int(n)) }
                }
                return nil
            }()
            self.init(objectID: objectID, url: best.url,
                      kind: hinted ?? Self.kind(fromURL: best.url) ?? keyed ?? .image)
        }

        private static let typeKeys: Set<String> = [
            "content_type", "mime_type", "mimetype", "file_type", "media_type", "type", "kind",
            "attachment_type", "category",
        ]

        /// Lower is better: full-size image links, then generic file links,
        /// then anything else, thumbnails last.
        private static func rank(_ key: String) -> Int {
            if key.contains("thumb") || key.contains("preview") || key.contains("small") { return 9 }
            switch key {
            case "image_url", "original_url", "full_url", "large_url", "photo_url": return 0
            case "url", "file_url", "download_url", "downloadable_url", "signed_url", "src",
                 "streamable_url", "video_url", "media_url": return 1
            case "medium_url": return 2
            default: return key.contains("url") ? 3 : 5
            }
        }

        private static func isLink(_ s: String) -> Bool {
            let lower = s.lowercased()
            return lower.hasPrefix("https://") || lower.hasPrefix("http://")
        }

        static func kind(fromURL string: String) -> Kind? {
            guard let ext = URL(string: string)?.pathExtension.lowercased(), !ext.isEmpty else { return nil }
            switch ext {
            case "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "bmp", "tif", "tiff": return .image
            case "mp4", "mov", "m4v", "m3u8", "webm": return .video
            case "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "csv": return .document
            default: return nil
            }
        }
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

    /// The attachments the timeline can show: photos and videos.
    var visualAttachments: [Attachment] { attachments.filter { $0.kind != .document } }

    /// Written by a parent (us, or the co-parent) — never imported: the
    /// timeline wants what the daycare said.
    var isFromGuardian: Bool { sender?.userType?.lowercased() == "guardian" }
}

/// Any JSON value — just enough structure to dig links out of an attachment
/// whose shape isn't documented.
indirect enum LooseJSON: Decodable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: LooseJSON])
    case array([LooseJSON])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([LooseJSON].self) { self = .array(v) }
        else if let v = try? c.decode([String: LooseJSON].self) { self = .object(v) }
        else { self = .null }
    }
}

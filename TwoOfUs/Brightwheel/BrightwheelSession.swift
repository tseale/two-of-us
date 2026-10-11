import Foundation
import Security

enum BrightwheelFeature {
    static let disclaimer = "Not affiliated with or endorsed by Brightwheel."
}

/// A connected Brightwheel guardian session: the `_brightwheel_v2` cookie the
/// web app signed in with, plus the identifiers resolved right after sign-in.
/// The cookie is a full-account credential — Keychain only, never UserDefaults,
/// and (unlike SNOO) there is no password anywhere: sign-in happens inside a
/// web view and we only ever see the resulting cookie.
struct BrightwheelSession: Codable, Sendable {
    var cookie: String
    var email: String
    var guardianID: String
    var studentID: String
    var studentName: String
    var signedInAt: Date
}

/// Keychain-only persistence, one JSON item under a dedicated service so
/// disconnect wipes everything with a single delete. Same shape as
/// `SnooTokenStore`.
struct BrightwheelSessionStore: Sendable {
    static let service = "com.taylorseale.twoofus.brightwheel"
    private static let account = "brightwheel.session"

    func load() -> BrightwheelSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(BrightwheelSession.self, from: data)
    }

    func save(_ session: BrightwheelSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        var query = baseQuery
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            query.merge(attributes) { _, new in new }
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    func clear() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service
        ] as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account
        ]
    }
}

/// The household's Brightwheel connection as it travels in the shared CloudKit
/// zone (`SharedSettings.brightwheelStatus`). **Status only** — unlike SNOO's
/// shareable refresh token, the `_brightwheel_v2` cookie is a full-account
/// web-session credential whose behavior under two-device reuse is unverified
/// (docs/BRIGHTWHEEL-INTEGRATION.md §5), so it never leaves the connecting
/// phone's Keychain. The other phone only needs to KNOW the household is
/// connected and who runs the imports; the imported events themselves reach
/// it through normal event sync. JSON-encoded so the payload can evolve
/// without a CloudKit schema change.
struct BrightwheelSharedStatus: Codable, Equatable, Sendable {
    /// Participant.id of the parent whose phone holds the session — drives
    /// "Connected by Taylor" on the other phone, and scopes disconnect so a
    /// stale blob from one parent can't be cleared by the other's cookie-less
    /// disconnect.
    var connectedByID: UUID?
    var connectedByName: String
    var email: String
    var studentName: String
    /// When the sign-in happened — the recency signal conflict resolution
    /// uses so a household disconnect ("") beats only blobs that predate it
    /// (same semantics as `SnooSharedCredentials.signedInAt`).
    var connectedAt: Date

    init?(json: String) {
        guard let decoded = try? JSONDecoder().decode(Self.self, from: Data(json.utf8))
        else { return nil }
        self = decoded
    }

    init(connectedByID: UUID?, connectedByName: String, email: String,
         studentName: String, connectedAt: Date) {
        self.connectedByID = connectedByID
        self.connectedByName = connectedByName
        self.email = email
        self.studentName = studentName
        self.connectedAt = connectedAt
    }

    /// `.sortedKeys` for the same reason as `SnooSharedCredentials`: unpinned
    /// key order encodes different bytes per process and churns CloudKit
    /// writes between the phones.
    var jsonString: String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) }
    }
}

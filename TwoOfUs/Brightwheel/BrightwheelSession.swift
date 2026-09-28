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

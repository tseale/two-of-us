import Foundation
import Security

/// The persisted Happiest Baby credentials: tokens + the signed-in email.
/// The password itself is NEVER stored anywhere (§5).
struct SnooTokens: Codable, Sendable {
    /// The Cognito **IdToken** — what the Happiest Baby REST API wants as
    /// `Bearer` (not the Cognito AccessToken; see docs/SNOO-API.md §A.1).
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
    var email: String
    /// Resolved once at sign-in (devices → babyIds); the per-baby session
    /// endpoints need it on every sync.
    var babyID: String?

    /// Proactive-refresh window: 300 s early, matching python-snoo's observed
    /// margin, so a request never rides a token that dies mid-flight (§5).
    var needsRefresh: Bool {
        Date.now >= expiresAt.addingTimeInterval(-300)
    }
}

/// Keychain-only persistence for SNOO tokens. One item, JSON-encoded, under a
/// dedicated service so sign-out can wipe everything with a single delete.
/// Tokens never touch UserDefaults (§5 security note).
struct SnooTokenStore: Sendable {
    static let service = "com.taylorseale.twoofus.snoo"
    private static let account = "happiestbaby.tokens"

    func load() -> SnooTokens? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(SnooTokens.self, from: data)
    }

    func save(_ tokens: SnooTokens) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        var query = baseQuery
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            // AfterFirstUnlock: the foreground sync can run right after a
            // restart without waiting for a second unlock (§5).
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            query.merge(attributes) { _, new in new }
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    /// Sign-out wipe: removes every item under the SNOO service.
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

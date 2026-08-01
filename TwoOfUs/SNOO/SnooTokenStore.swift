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

/// The household's SNOO connection as it travels in the shared CloudKit zone
/// (`SharedSettings.snooCredentials`): the long-lived refresh token plus
/// display metadata — never the password (§5), never the short-lived IdToken
/// (each device mints its own; Cognito refresh tokens are multi-use and
/// un-rotated, docs/SNOO-API.md §A.1, so every phone can share one).
/// JSON-encoded so the payload can evolve without a CloudKit schema change.
struct SnooSharedCredentials: Codable, Equatable, Sendable {
    var refreshToken: String
    var email: String
    var babyID: String?
    /// Household mode: auto-log SNOO sessions instead of suggesting them.
    /// Optional so blobs written before the flag existed decode unchanged
    /// (nil reads as off). Lives in this blob on purpose — no schema change,
    /// and it travels atomically with the connection it configures.
    var autoLog: Bool?

    init(refreshToken: String, email: String, babyID: String?, autoLog: Bool? = nil) {
        self.refreshToken = refreshToken
        self.email = email
        self.babyID = babyID
        self.autoLog = autoLog
    }

    init?(json: String) {
        guard let decoded = try? JSONDecoder().decode(Self.self, from: Data(json.utf8))
        else { return nil }
        self = decoded
    }

    var jsonString: String? {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) }
    }
}

/// The pure decision behind keeping a device's Keychain in step with the
/// household connection. The shared field is three-state: nil = never
/// written (pre-feature zone — a signed-in device publishes its session so
/// the household inherits it), empty = explicitly signed out (every device
/// disconnects), JSON = connected (adopt when this device is out of step).
enum SnooCredentialSync {
    enum Action: Equatable {
        case adopt(SnooSharedCredentials)
        case publishLocal
        case disconnect
        case none
    }

    static func action(sharedField: String?, localRefreshToken: String?) -> Action {
        guard let field = sharedField else {
            return localRefreshToken == nil ? .none : .publishLocal
        }
        if field.isEmpty {
            return localRefreshToken == nil ? .none : .disconnect
        }
        guard let shared = SnooSharedCredentials(json: field) else {
            // Unreadable payload (a future build's format): leave this
            // device's working session alone rather than tearing it down.
            return .none
        }
        return shared.refreshToken == localRefreshToken ? .none : .adopt(shared)
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

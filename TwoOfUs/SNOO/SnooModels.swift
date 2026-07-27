import Foundation

/// Feature gate for the whole SNOO integration. The API is unofficial and may
/// need to be pulled quickly (§10 of the spec) — flipping this to `false`
/// removes every SNOO surface (Settings row, cards, sync) in one line.
enum SnooFeature {
    static let isEnabled = true

    /// Shown in the login sheet and Settings footer. Required copy (§10).
    static let disclaimer = "Not affiliated with or endorsed by Happiest Baby."
}

/// SNOO motion level as reported by the cloud API. `online` means the bassinet
/// is idle (no session); everything else is an active soothing level.
enum SnooLevel: String, Codable, Sendable {
    case online = "ONLINE", baseline = "BASELINE", weaningBaseline = "WEANING_BASELINE"
    case level1 = "LEVEL1", level2 = "LEVEL2", level3 = "LEVEL3", level4 = "LEVEL4"
    var isSoothing: Bool { self != .online }
}

/// One SNOO session, normalised from whichever endpoint reported it.
/// `endedAt == nil` means the bassinet is still running.
struct SnooSession: Identifiable, Hashable, Sendable {
    let id: String              // sessionId from the API, or a synthesised stable ID
    let startedAt: Date
    let endedAt: Date?          // nil == still running
    let levels: [SnooLevel]

    var duration: TimeInterval? { endedAt.map { $0.timeIntervalSince(startedAt) } }
    var isInProgress: Bool { endedAt == nil }

    /// Stable fallback ID for payloads without a sessionId. Derived from the
    /// start instant so the same session gets the same ID on every sync.
    static func synthesisedID(startedAt: Date) -> String {
        "snoo-" + ISO8601DateFormatter().string(from: startedAt)
    }
}

/// A SNOO device on the account. Only used to confirm the account has one.
struct SnooDevice: Hashable, Sendable {
    let serialNumber: String
    let babyID: String?
}

/// Every way a SNOO API call can fail, mapped from transport/HTTP/decoding.
/// UI copy for each case lives in `userMessage` — views never switch on raw
/// errors.
enum SnooAPIError: Error, Sendable {
    case invalidCredentials
    case needsReauth
    case rateLimited(retryAfter: TimeInterval?)
    case noDeviceOnAccount
    case subscriptionRequired
    case decoding(underlying: Error, endpoint: String)
    case transport(underlying: Error)
    case server(status: Int)

    /// Inline copy for the login sheet and the manual "Sync now" result.
    /// Background syncs stay silent (§9) and surface at most as neutral text
    /// in Settings — this is only shown when the user directly asked for a
    /// result, so it's specific enough to say what actually went wrong.
    var userMessage: String {
        switch self {
        case .invalidCredentials:
            return "That email or password didn't work."
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter, seconds >= 1 {
                return "Too many attempts — try again in \(Int(seconds.rounded(.up)))s."
            }
            return "Too many attempts — wait a few minutes and try again."
        case .transport(let underlying):
            return Self.transportMessage(for: underlying)
        case .server(let status):
            return "Happiest Baby's service returned an error (HTTP \(status)). Try again in a bit."
        case .decoding:
            return "Happiest Baby sent back a response we didn't expect. The service may have changed — try again later."
        case .needsReauth:
            return "Please sign in again."
        case .noDeviceOnAccount:
            return "No SNOO found on this account."
        case .subscriptionRequired:
            return "This account's SNOO history isn't available (subscription required)."
        }
    }

    private static func transportMessage(for underlying: Error) -> String {
        guard let urlError = underlying as? URLError else {
            return "Couldn't reach Happiest Baby (network error). Try again."
        }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            return "You're offline. Check your connection and try again."
        case .timedOut:
            return "The request to Happiest Baby timed out. Try again."
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return "Couldn't reach Happiest Baby's servers. Try again in a bit."
        default:
            return "Couldn't reach Happiest Baby (network error). Try again."
        }
    }
}

/// What the reconciler proposes to the user. Never written to the store until
/// the user accepts (§1: the app suggests, the user confirms).
struct SnooSuggestion: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case completed(endedAt: Date)
        case inProgress
    }

    let id: String              // the SnooSession id
    let startedAt: Date
    let kind: Kind

    var endedAt: Date? {
        if case .completed(let end) = kind { return end }
        return nil
    }
}

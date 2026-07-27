import Foundation

/// Device-local sync bookkeeping (UserDefaults — never tokens, §5). Tracks
/// which SNOO sessions were imported or dismissed so suggestions never
/// resurface, plus throttle/backoff/degraded state.
struct SnooSyncState {
    private let defaults: UserDefaults

    private enum Key {
        static let lastSyncAt = "snoo.lastSyncAt"
        static let lastAttemptAt = "snoo.lastAttemptAt"
        static let dismissed = "snoo.dismissedSessionIDs"
        static let imported = "snoo.importedSessionIDs"
        static let backoffUntil = "snoo.backoffUntil"
        static let backoffInterval = "snoo.backoffInterval"
        static let decodeFailures = "snoo.consecutiveDecodeFailures"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var lastSyncAt: Date? {
        get { defaults.object(forKey: Key.lastSyncAt) as? Date }
        nonmutating set { defaults.set(newValue, forKey: Key.lastSyncAt) }
    }

    /// Last sync *attempt* (success or not) — the 5-minute throttle keys off
    /// this so a failing API isn't hammered on every foreground (§7, §10).
    var lastAttemptAt: Date? {
        get { defaults.object(forKey: Key.lastAttemptAt) as? Date }
        nonmutating set { defaults.set(newValue, forKey: Key.lastAttemptAt) }
    }

    var dismissedSessionIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.dismissed) ?? []) }
        nonmutating set { defaults.set(Array(newValue), forKey: Key.dismissed) }
    }

    var importedSessionIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.imported) ?? []) }
        nonmutating set { defaults.set(Array(newValue), forKey: Key.imported) }
    }

    // MARK: Backoff (§9: 429 honours Retry-After, else 30 min doubling to 4 h)

    var backoffUntil: Date? {
        get { defaults.object(forKey: Key.backoffUntil) as? Date }
        nonmutating set { defaults.set(newValue, forKey: Key.backoffUntil) }
    }

    static let backoffFloor: TimeInterval = 30 * 60
    static let backoffCeiling: TimeInterval = 4 * 3600

    /// Registers a rate-limit and returns the next allowed sync date.
    nonmutating func registerRateLimit(retryAfter: TimeInterval?, now: Date = .now) {
        let previous = defaults.double(forKey: Key.backoffInterval)
        let doubled = previous > 0 ? min(previous * 2, Self.backoffCeiling) : Self.backoffFloor
        let interval = max(retryAfter ?? doubled, Self.backoffFloor)
        defaults.set(interval, forKey: Key.backoffInterval)
        backoffUntil = now.addingTimeInterval(min(interval, Self.backoffCeiling))
    }

    nonmutating func clearBackoff() {
        backoffUntil = nil
        defaults.removeObject(forKey: Key.backoffInterval)
    }

    // MARK: Degraded integration (§9: 3 consecutive decode failures)

    var consecutiveDecodeFailures: Int {
        get { defaults.integer(forKey: Key.decodeFailures) }
        nonmutating set { defaults.set(newValue, forKey: Key.decodeFailures) }
    }

    /// The API's shape has drifted from what we can read — Settings shows a
    /// neutral note and nothing else changes.
    var isDegraded: Bool { consecutiveDecodeFailures >= 3 }

    /// Sign-out reset: wipes everything EXCEPT `importedSessionIDs`, so a
    /// later re-connect can't re-suggest sessions that are already in the
    /// timeline (§5 token lifecycle, step 5).
    nonmutating func resetForSignOut() {
        defaults.removeObject(forKey: Key.lastSyncAt)
        defaults.removeObject(forKey: Key.lastAttemptAt)
        defaults.removeObject(forKey: Key.dismissed)
        defaults.removeObject(forKey: Key.backoffUntil)
        defaults.removeObject(forKey: Key.backoffInterval)
        defaults.removeObject(forKey: Key.decodeFailures)
    }
}

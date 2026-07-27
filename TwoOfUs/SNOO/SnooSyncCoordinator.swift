import Foundation
import Network
import SwiftData
import SwiftUI

/// Where the SNOO integration stands, for the Settings row (§5: four states —
/// "syncing" is `connected` plus `isSyncing`).
enum SnooConnectionState: Equatable {
    case notConnected
    case connected(email: String)
    case needsReauth(email: String)
}

/// Orchestration and throttling for SNOO Sleep Sync. Owns the observable
/// suggestion list; applies accepted suggestions through `EventStore`. All the
/// decisions live in `SnooReconciler` — this class just moves data (§4).
@MainActor
@Observable
final class SnooSyncCoordinator {
    static let shared = SnooSyncCoordinator()

    private(set) var connectionState: SnooConnectionState = .notConnected
    private(set) var isSyncing = false
    private(set) var suggestions: [SnooSuggestion] = []
    private(set) var lastSyncAt: Date?
    /// §9: after 3 consecutive decode failures the integration is "degraded" —
    /// Settings shows a neutral line, nothing else changes.
    private(set) var isDegraded = false
    /// §9: a 429 pauses syncing (backoff) — Settings-only copy, never a card.
    var isRateLimited: Bool {
        guard let until = state.backoffUntil else { return false }
        return Date.now < until
    }

    /// Outcome of the last manual "Sync now" tap, shown inline in
    /// `SnooDetailView`. Unlike background syncs (silent per §9), a manual tap
    /// always gets a visible result — the user asked for it directly.
    enum ManualSyncResult: Equatable {
        case found(summaries: [String])
        case noneFound
        case failed(message: String)
    }
    private(set) var manualSyncResult: ManualSyncResult?

    /// At most this many cards on the logging surface (§7).
    static let maxVisibleSuggestions = 3
    /// Foreground syncs are at least this far apart (§7, §10).
    static let syncThrottle: TimeInterval = 5 * 60

    private let client: SnooAPIClient
    private let tokenStore: SnooTokenStore
    private let state: SnooSyncState
    /// Signed-in account email, mirrored outside the Keychain (it's shown in
    /// Settings and pre-fills re-auth; never the tokens themselves).
    private var accountEmail: String {
        get { UserDefaults.standard.string(forKey: "snoo.accountEmail") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "snoo.accountEmail") }
    }

    init(client: SnooAPIClient = SnooAPIClient(),
         tokenStore: SnooTokenStore = SnooTokenStore(),
         state: SnooSyncState = SnooSyncState()) {
        self.client = client
        self.tokenStore = tokenStore
        self.state = state
        refreshConnectionState()
        lastSyncAt = state.lastSyncAt
        isDegraded = state.isDegraded
    }

    // MARK: Auth

    /// Signs in and flips the Settings row to connected. Throws `SnooAPIError`
    /// for the login sheet's inline error copy.
    func signIn(email: String, password: String) async throws {
        let tokens = try await client.logIn(email: email, password: password)
        accountEmail = tokens.email
        connectionState = .connected(email: tokens.email)
        state.clearBackoff()
        state.consecutiveDecodeFailures = 0
        isDegraded = false
    }

    /// Wipes tokens and per-account sync state. `importedSessionIDs` survives
    /// so a re-connect can't duplicate already-imported sessions (§5).
    func signOut() async {
        await client.signOut()
        state.resetForSignOut()
        accountEmail = ""
        suggestions = []
        lastSyncAt = nil
        isDegraded = false
        manualSyncResult = nil
        connectionState = .notConnected
    }

    private func refreshConnectionState() {
        if tokenStore.load() != nil {
            connectionState = .connected(email: accountEmail)
        } else if !accountEmail.isEmpty {
            connectionState = .needsReauth(email: accountEmail)
        } else {
            connectionState = .notConnected
        }
    }

    // MARK: Sync

    /// App-foreground trigger: throttled, silent, non-blocking (§7).
    func syncOnForeground(context: ModelContext) {
        Task { await sync(context: context, force: false) }
    }

    /// The Settings "Sync now" button: skips the 5-minute throttle but still
    /// honours rate-limit backoff. Unlike the foreground trigger, this always
    /// records a result for `manualSyncResult` to display.
    func syncNow(context: ModelContext) async {
        manualSyncResult = nil
        if let outcome = await sync(context: context, force: true) {
            manualSyncResult = outcome
        }
    }

    /// Returns the outcome when a sync actually ran (or was blocked by
    /// backoff/offline); `nil` for the cases a manual tap can't hit — already
    /// syncing (button disabled) or not connected (button not shown).
    @discardableResult
    private func sync(context: ModelContext, force: Bool) async -> ManualSyncResult? {
        guard SnooFeature.isEnabled,
              !LocalPrefs.shared.demoModeEnabled,
              !isSyncing,
              case .connected = connectionState else { return nil }
        let now = Date.now
        if !force, let last = state.lastAttemptAt,
           now.timeIntervalSince(last) < Self.syncThrottle { return nil }
        if let backoff = state.backoffUntil, now < backoff {
            return .failed(message: "Syncing paused briefly. Try again soon.")
        }
        guard SnooConnectivity.shared.isOnline else {
            return .failed(message: "You're offline. Check your connection and try again.")
        }

        state.lastAttemptAt = now
        isSyncing = true
        defer { isSyncing = false }

        do {
            // ≤3 requests per sync (§10): last session + two aggregated days
            // (today and yesterday, so a midnight-spanning sleep isn't missed).
            let last = try await client.fetchLastSession()
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: now)
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return nil }
            async let todaySessions = client.fetchAggregatedSessions(dayStart: today)
            async let yesterdaySessions = client.fetchAggregatedSessions(dayStart: yesterday)
            let aggregated = try await todaySessions + yesterdaySessions

            let merged = SnooSessionNormaliser.merge(last: last, aggregated: aggregated)
            state.consecutiveDecodeFailures = 0
            state.clearBackoff()
            state.lastSyncAt = now
            lastSyncAt = now
            isDegraded = false
            reconcile(merged, context: context, now: now)
            return suggestions.isEmpty
                ? .noneFound
                : .found(summaries: suggestions.map(Self.summaryLine))
        } catch let error as SnooAPIError {
            handleSyncError(error)
            return .failed(message: error.loginMessage)
        } catch {
            AppLog.snoo.error("SNOO sync failed: \(String(describing: type(of: error)), privacy: .public)")
            return .failed(message: "Something went wrong. Try again.")
        }
    }

    /// One-line summary of a suggestion for the manual sync result (§8 copy,
    /// condensed — full detail lives on the suggestion card itself).
    private static func summaryLine(_ suggestion: SnooSuggestion) -> String {
        switch suggestion.kind {
        case .completed(let endedAt):
            return "\(TimeFormatting.clock(suggestion.startedAt))–\(TimeFormatting.clock(endedAt))"
        case .inProgress:
            return "Running since \(TimeFormatting.clock(suggestion.startedAt))"
        }
    }

    private func reconcile(_ sessions: [SnooSession], context: ModelContext, now: Date) {
        suggestions = Array(
            SnooReconciler.suggestions(
                snooSessions: sessions,
                localSleeps: localSleepSpans(context: context, now: now),
                importedIDs: state.importedSessionIDs,
                dismissedIDs: state.dismissedSessionIDs,
                now: now
            )
            .prefix(Self.maxVisibleSuggestions)
        )
    }

    /// Recent local sleep, reduced to spans. Reaches back 3 days — enough to
    /// cover everything the two aggregated day fetches can return.
    private func localSleepSpans(context: ModelContext, now: Date) -> [LocalSleepSpan] {
        let cutoff = now.addingTimeInterval(-3 * 24 * 3600)
        let descriptor = FetchDescriptor<SleepEvent>(
            predicate: #Predicate { $0.deletedAt == nil && ($0.startedAt >= cutoff || $0.endedAt == nil) }
        )
        return ((try? context.fetch(descriptor)) ?? []).map(LocalSleepSpan.init)
    }

    /// Every sync failure is silent and non-blocking (§9) — state updates only.
    private func handleSyncError(_ error: SnooAPIError) {
        switch error {
        case .needsReauth, .invalidCredentials:
            connectionState = .needsReauth(email: accountEmail)
        case .rateLimited(let retryAfter):
            state.registerRateLimit(retryAfter: retryAfter)
        case .decoding(_, let endpoint):
            state.consecutiveDecodeFailures += 1
            isDegraded = state.isDegraded
            AppLog.snoo.error("SNOO decode failure at \(endpoint, privacy: .public) (\(self.state.consecutiveDecodeFailures) consecutive)")
        case .transport, .server, .subscriptionRequired, .noDeviceOnAccount:
            AppLog.snoo.error("SNOO sync error: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Suggestion actions

    /// Single-tap accept (§8). Writes through the store; only on a successful
    /// write does the session join `importedSessionIDs`.
    func accept(_ suggestion: SnooSuggestion, store: EventStore) -> Bool {
        let saved: Bool
        switch suggestion.kind {
        case .completed(let endedAt):
            saved = store.logCompletedSleep(startedAt: suggestion.startedAt, endedAt: endedAt) != nil
        case .inProgress:
            saved = store.startSleep(at: suggestion.startedAt) != nil
        }
        if saved { markImported(suggestion) }
        return saved
    }

    /// Permanent dismiss (§8) — the session never resurfaces.
    func dismiss(_ suggestion: SnooSuggestion) {
        state.dismissedSessionIDs.insert(suggestion.id)
        suggestions.removeAll { $0.id == suggestion.id }
    }

    /// Called after an edited suggestion is saved through the sleep editor.
    func markImported(_ suggestion: SnooSuggestion) {
        state.importedSessionIDs.insert(suggestion.id)
        suggestions.removeAll { $0.id == suggestion.id }
    }
}

/// Cheap online/offline signal so a foreground sync in airplane mode doesn't
/// even attempt requests (§7).
final class SnooConnectivity: Sendable {
    static let shared = SnooConnectivity()

    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    nonisolated(unsafe) private var online = true

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            self.online = path.status == .satisfied
            self.lock.unlock()
        }
        monitor.start(queue: DispatchQueue(label: "snoo.connectivity"))
    }

    var isOnline: Bool {
        lock.lock()
        defer { lock.unlock() }
        return online
    }
}

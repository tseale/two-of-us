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
        case logged(summaries: [String])   // auto-log mode wrote these directly
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
    /// for the login sheet's inline error copy. One parent's sign-in is the
    /// household's: the refresh token (never the password) is published on
    /// the shared settings record, and every other participant's device
    /// adopts it on its next sync — nobody else signs in.
    func signIn(email: String, password: String, context: ModelContext) async throws {
        let tokens = try await client.logIn(email: email, password: password)
        guard let refresh = tokens.refreshToken else {
            // No refresh token means the session dies within the hour and can
            // never be shared with the household — fail the connect honestly
            // instead of showing "connected" on one phone only (the old
            // silent skip produced exactly that, with no diagnostic).
            await client.signOut()
            AppLog.snoo.error("SNOO login returned no refresh token — refusing the connect")
            throw SnooAPIError.decoding(underlying: SnooAPIError.needsReauth,
                                        endpoint: "login (missing RefreshToken)")
        }
        accountEmail = tokens.email
        connectionState = .connected(email: tokens.email)
        state.clearBackoff()
        state.consecutiveDecodeFailures = 0
        isDegraded = false
        // Re-signing in must not reset the household's auto-log choice.
        let creds = SnooSharedCredentials(refreshToken: refresh, email: tokens.email,
                                          babyID: tokens.babyID,
                                          autoLog: sharedCredentialsBlob(context: context)?.autoLog)
        EventStore(context: context).updateSnooCredentials(creds.jsonString)
    }

    /// The parsed household connection blob, when one is set.
    private func sharedCredentialsBlob(context: ModelContext) -> SnooSharedCredentials? {
        sharedSettingsRow(context: context)?.snooCredentials
            .flatMap(SnooSharedCredentials.init(json:))
    }

    /// The canonical settings row — NEVER an unordered `.first`, which could
    /// disagree with the row `EventStore` publishes onto if duplicates exist.
    private func sharedSettingsRow(context: ModelContext) -> SharedSettings? {
        SharedSettings.canonical((try? context.fetch(FetchDescriptor<SharedSettings>())) ?? [])
    }

    /// Household sign-out: clears the shared connection (empty string — the
    /// explicit "signed out" state, distinct from never-set) so every device
    /// disconnects on its next sync, then disconnects this one. If the clear
    /// couldn't be written (no settings row), the device deliberately STAYS
    /// connected: disconnecting locally anyway would just re-adopt on the
    /// next sync while the dialog claimed the household was signed out.
    func signOut(context: ModelContext) async {
        guard EventStore(context: context).updateSnooCredentials("") else { return }
        await disconnectLocally()
    }

    /// This device lost the household (left the share, was removed by the
    /// owner, or deleted everything): tear down the SNOO connection locally so
    /// an ex-member's phone doesn't keep a working token for the owner's
    /// Happiest Baby account — or re-publish it into a future household via
    /// the `.publishLocal` migration. The shared field isn't touched: the
    /// zone either still belongs to the others (who keep their connection) or
    /// no longer exists.
    func handleHouseholdLeft() async {
        await disconnectLocally()
    }

    /// On-demand household reconciliation for UI surfaces: runs the
    /// adopt/publish/disconnect decision without a full API sync, so a
    /// SharedSettings record that lands mid-session flips the Settings row
    /// the moment it arrives instead of waiting for the next app-foreground.
    func adoptHouseholdConnectionIfNeeded(context: ModelContext) async {
        guard SnooFeature.isEnabled,
              !LocalPrefs.shared.demoModeEnabled,
              !isSyncing else { return }
        await syncSharedCredentials(context: context)
    }

    /// Wipes tokens and per-account sync state on THIS device.
    /// `importedSessionIDs` survives so a re-connect can't duplicate
    /// already-imported sessions (§5).
    private func disconnectLocally() async {
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
              !isSyncing else { return nil }
        // First, fall in step with the household connection: adopt credentials
        // another parent published, or disconnect if they signed out.
        await syncSharedCredentials(context: context)
        guard case .connected = connectionState else { return nil }
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
            // Before reconciling: a SNOO-started timer whose session has since
            // finished gets closed at the SNOO's end time, so the reconcile
            // below already sees it as completed sleep.
            autoEndFinishedSnooSleep(merged, context: context)
            let autoLog = sharedCredentialsBlob(context: context)?.autoLog ?? false
            let logged = reconcile(merged, context: context, now: now, autoLog: autoLog)
            if !logged.isEmpty { return .logged(summaries: logged) }
            return suggestions.isEmpty
                ? .noneFound
                : .found(summaries: suggestions.map(Self.summaryLine))
        } catch let error as SnooAPIError {
            handleSyncError(error)
            return .failed(message: error.userMessage)
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

    /// Runs the reconciler and either surfaces cards or — in auto-log mode —
    /// accepts every suggestion on the spot: in-progress sessions start the
    /// real timer, completed ones land straight in the log, all stamped
    /// `.snoo` and marked imported through the same `accept` path the cards
    /// use, so every reconciler safety rail (imported/dismissed, manual-timer
    /// respect, stale sessions) applies identically. Returns the auto-logged
    /// summaries (empty in card mode).
    private func reconcile(_ sessions: [SnooSession], context: ModelContext, now: Date,
                           autoLog: Bool) -> [String] {
        let all = SnooReconciler.suggestions(
            snooSessions: sessions,
            localSleeps: localSleepSpans(context: context, now: now),
            importedIDs: state.importedSessionIDs,
            dismissedIDs: state.dismissedSessionIDs,
            now: now
        )
        guard autoLog else {
            suggestions = Array(all.prefix(Self.maxVisibleSuggestions))
            return []
        }
        suggestions = []
        let store = EventStore(context: context)
        // Oldest first, so a catch-up of missed completed sessions lands
        // before (and can never block) today's still-running one.
        let logged = all.reversed().compactMap { suggestion in
            accept(suggestion, store: store) ? Self.summaryLine(suggestion) : nil
        }
        if !logged.isEmpty {
            AppLog.snoo.info("Auto-logged \(logged.count) SNOO session(s)")
        }
        return logged
    }

    /// Keeps this device's Keychain in step with the household connection on
    /// the shared settings record. Adoption stores the shared refresh token
    /// with an already-expired access token, so the first request mints this
    /// device's own IdToken; a cleared share disconnects this device too.
    /// If the shared refresh token has died, adoption retries it each sync —
    /// one failed refresh per sync, and the moment a parent signs in again
    /// every device heals from the newly published credentials.
    private func syncSharedCredentials(context: ModelContext) async {
        let field = sharedSettingsRow(context: context)?.snooCredentials
        let local = tokenStore.load()
        switch SnooCredentialSync.action(sharedField: field,
                                         localRefreshToken: local?.refreshToken) {
        case .adopt(let creds):
            tokenStore.save(SnooTokens(accessToken: "", refreshToken: creds.refreshToken,
                                       expiresAt: .distantPast, email: creds.email,
                                       babyID: creds.babyID))
            accountEmail = creds.email
            connectionState = .connected(email: creds.email)
            state.clearBackoff()
            state.consecutiveDecodeFailures = 0
            isDegraded = false
            AppLog.snoo.info("Adopted the household SNOO connection")
        case .publishLocal:
            // Pre-feature migration: this device signed in before the
            // connection was shared — publish it so the household inherits.
            guard let local, let refresh = local.refreshToken else {
                AppLog.snoo.error("Local SNOO session has no refresh token — cannot publish it to the household")
                break
            }
            let creds = SnooSharedCredentials(refreshToken: refresh, email: local.email,
                                              babyID: local.babyID)
            EventStore(context: context).updateSnooCredentials(creds.jsonString)
            AppLog.snoo.info("Published this device's SNOO connection to the household")
        case .disconnect:
            await disconnectLocally()
            AppLog.snoo.info("Household SNOO connection removed — disconnected this device")
        case .none:
            break
        }
    }

    /// Closes an open sleep timer that was started from a SNOO suggestion
    /// once the SNOO reports that session finished — start and end both come
    /// from the bassinet when the parent delegated tracking by accepting the
    /// card. Only ever touches timers stamped `source == .snoo`; a manually
    /// started timer is never ended by the integration. Poll-driven like the
    /// rest of the sync (§2.2): the end lands on the next foreground/manual
    /// sync after the SNOO turns off, stamped with the SNOO's end time, and
    /// tears down the Live Activity through the normal stop path.
    private func autoEndFinishedSnooSleep(_ sessions: [SnooSession], context: ModelContext) {
        let descriptor = FetchDescriptor<SleepEvent>(
            predicate: #Predicate { $0.endedAt == nil && $0.deletedAt == nil }
        )
        guard let open = ((try? context.fetch(descriptor)) ?? []).first(where: \.isFromSnoo),
              let end = SnooReconciler.autoEndDate(openSleepStartedAt: open.startedAt,
                                                   sessions: sessions) else { return }
        EventStore(context: context).stopSleep(open, at: end)
        AppLog.snoo.info("SNOO session ended — closed the SNOO-started sleep timer at \(end, privacy: .public)")
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
            saved = store.logCompletedSleep(startedAt: suggestion.startedAt, endedAt: endedAt,
                                            source: .snoo) != nil
        case .inProgress:
            saved = store.startSleep(at: suggestion.startedAt, source: .snoo) != nil
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

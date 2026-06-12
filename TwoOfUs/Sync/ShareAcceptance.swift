import CloudKit
import Observation

/// Accepts a CloudKit share invite (the joining parent tapping the owner's
/// link) and owns the outcome, so a failed accept surfaces as UI instead of
/// dying as a console print. Both delivery paths — the scene delegate (warm and
/// cold launches) and the app-delegate fallback — funnel through `accept`;
/// `RootView` watches `failed` and offers a retry off the kept metadata.
@MainActor @Observable
final class ShareAcceptance {
    static let shared = ShareAcceptance()

    /// The last accept attempt threw — `RootView` shows a retry alert.
    var failed = false

    /// Metadata of the last attempt, kept so Retry doesn't need the link tapped
    /// again. Cleared on success.
    private var pending: CKShare.Metadata?
    private var inFlight = false

    func accept(_ metadata: CKShare.Metadata) {
        pending = metadata
        guard !inFlight else { return }
        inFlight = true
        failed = false
        Task {
            defer { inFlight = false }
            do {
                try await SyncConstants.container.accept(metadata)
                pending = nil
                // Flip device state directly, NOT only via `SyncManager.shared`:
                // the manager doesn't exist yet on a cold-launch link tap, and
                // never exists while demo mode is on (`configure()` skips it) —
                // optional-chaining alone silently dropped the accept and
                // stranded the joiner on owner onboarding.
                SyncManager.markShareAccepted()
                // Leave demo: the join flow must run against the real store, and
                // exiting demo makes `configure()` build and start the manager,
                // which picks the shared engine up from the role set above.
                LocalPrefs.shared.demoModeEnabled = false
                // Started immediately when the manager already exists —
                // RootView routes to the join flow either way.
                SyncManager.shared?.didAcceptShare()
            } catch {
                print("Failed to accept CloudKit share: \(error)")
                failed = true
            }
        }
    }

    /// Re-runs the last failed accept; no-op if nothing is pending.
    func retry() {
        guard let pending else { return }
        accept(pending)
    }
}

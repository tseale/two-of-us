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
                // Flips this device to the participant role and starts pulling
                // the owner's shared zone — RootView routes to the join flow.
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

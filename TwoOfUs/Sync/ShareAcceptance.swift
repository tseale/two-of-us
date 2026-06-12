import CloudKit
import SwiftData
import Observation

/// Accepts a CloudKit share invite (the joining parent tapping the owner's
/// link) and owns the outcome, so a failed accept surfaces as UI instead of
/// dying as a console print. Both delivery paths — the scene delegate (warm and
/// cold launches) and the app-delegate fallback — funnel through `accept`;
/// `RootView` watches `failed` / `confirmReplace` and renders the alerts.
@MainActor @Observable
final class ShareAcceptance {
    static let shared = ShareAcceptance()

    /// The last accept attempt threw — `RootView` shows a retry alert.
    var failed = false

    /// Set when the link is tapped on a device that already has its own log
    /// (finished solo onboarding): silently becoming a participant would leave
    /// TWO babies in the store, so `RootView` asks before anything is replaced.
    var confirmReplace: CKShare.Metadata?

    /// Metadata of the last attempt, kept so Retry doesn't need the link tapped
    /// again. Cleared on success.
    private var pending: CKShare.Metadata?
    private var inFlight = false

    func accept(_ metadata: CKShare.Metadata) {
        // A link from a DIFFERENT household than the one we're attached to must
        // also replace, never merge — otherwise two owners' zones upsert into
        // one store and writes flip-flop between zones.
        let newOwner = metadata.share.recordID.zoneID.ownerName
        let switchingHousehold = SyncManager.realSyncRole == .participant
            && SyncManager.persistedSharedZoneOwnerName() != nil
            && SyncManager.persistedSharedZoneOwnerName() != newOwner
        if SyncManager.realSyncRole != .participant || switchingHousehold,
           SyncManager.shared?.hasLocalBaby == true {
            confirmReplace = metadata
            return
        }
        proceed(metadata, replacingLocalData: false)
    }

    /// User confirmed: replace this phone's log with the shared one.
    func confirmJoinReplacingLocalData() {
        guard let metadata = confirmReplace else { return }
        confirmReplace = nil
        proceed(metadata, replacingLocalData: true)
    }

    func cancelJoin() {
        confirmReplace = nil
    }

    /// Re-runs the last failed accept; no-op if nothing is pending.
    func retry() {
        guard let pending else { return }
        accept(pending)
    }

    private func proceed(_ metadata: CKShare.Metadata, replacingLocalData: Bool) {
        pending = metadata
        guard !inFlight else { return }
        inFlight = true
        failed = false
        Task {
            defer { inFlight = false }
            do {
                // Leave demo FIRST: the rest of this flow must run against the
                // real store, and `deleteEverything` is demo-guarded — wiping
                // behind the guard would silently no-op the "Replace & Join"
                // the user just confirmed. (markShareAccepted still rewrites
                // the demo backup, so even if the demo teardown lags, exiting
                // can't restore a stale role over the accept.)
                LocalPrefs.shared.demoModeEnabled = false
                try await SyncConstants.container.accept(metadata)
                // Only after the accept succeeded — a failed accept must never
                // cost the user their existing data.
                if replacingLocalData {
                    await SyncManager.shared?.deleteEverything()
                }
                pending = nil
                // Flip device state directly, NOT only via `SyncManager.shared`:
                // the manager may not exist yet on a cold-launch link tap —
                // optional-chaining alone silently dropped the accept and
                // stranded the joiner on owner onboarding. The metadata also
                // carries the owner's zone ID — the one reliable place to learn
                // it (the engine never re-announces an already-fetched zone), so
                // the participant's writes have somewhere to go after relaunch.
                SyncManager.markShareAccepted(zoneID: metadata.share.recordID.zoneID)
                // Started immediately when the manager already exists —
                // RootView routes to the join flow either way.
                SyncManager.shared?.didAcceptShare()
            } catch {
                print("Failed to accept CloudKit share: \(error)")
                failed = true
            }
        }
    }
}

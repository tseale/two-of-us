import Foundation
import CloudKit
import Observation

/// Fresh-install restore: finds this iCloud account's existing family BEFORE
/// owner onboarding can appear.
///
/// A new phone (or a reinstall without a backup) starts with empty local
/// state: no store, `syncRole == .solo`, no `myParticipantID`. Without this,
/// `RootView` shows owner onboarding while the first fetch is still running,
/// and finishing it mints a second Baby and Participant in the family's zone.
/// Worse, a co-parent's phone never looks in the shared database at all, so
/// it acts like a brand-new user until the invite link is tapped again.
///
/// The check runs once per launch, only when the device looks freshly
/// installed (`CloudRestorePlan.shouldCheck`):
/// 1. The shared database holds the owner's `TwoOfUsZone` → this account
///    already accepted a share. Re-attach as a participant, fetch, and adopt
///    the profile that carries this iCloud user record name (no join flow).
/// 2. Otherwise the private zone holds a Baby → this account owns a family.
///    Fetch it and adopt the owner's profile before Home appears.
/// 3. Nothing found (or offline, or no iCloud) → onboarding, exactly as before.
@MainActor @Observable
final class CloudRestore {
    static let shared = CloudRestore()

    enum Kind: Equatable {
        /// This account owns the family's zone (private database).
        case owner
        /// This account accepted the owner's share (shared database).
        case coParent
    }

    enum Phase: Equatable {
        /// Asking iCloud whether a family already exists for this account.
        case checking
        /// A family was found and is downloading.
        case restoring(Kind)
        /// Nothing to restore, or the restore completed; normal routing.
        case finished
    }

    private(set) var phase: Phase
    /// The last restore fetch failed (offline mid-download, CloudKit hiccup).
    /// The restoring screen offers Try again rather than falling through to
    /// onboarding, which is the duplicate-baby trap this exists to avoid.
    private(set) var failed = false

    /// How long the existence check may take before the app gives up and
    /// shows onboarding (a slow network must not hold a genuinely new user
    /// on a spinner).
    static let probeTimeout: Duration = .seconds(8)

    private var running = false

    private init() {
        let prefs = LocalPrefs.shared
        // Fixture launches (UI tests, screenshots) never build sync, so there
        // is nothing to check — route straight to the screen they asked for.
        phase = SyncGate.blockReason == nil && CloudRestorePlan.shouldCheck(
            role: SyncManager.realSyncRole,
            myParticipantID: prefs.myParticipantID,
            demoMode: prefs.demoModeEnabled
        ) ? .checking : .finished
    }

    /// Whether `RootView` should hold on the restoring screen instead of its
    /// normal routes.
    func blocksRouting(hasBaby: Bool) -> Bool {
        CloudRestorePlan.blocksRouting(phase: phase, hasBaby: hasBaby)
    }

    /// Runs the check (and the restore it leads to). Safe to call repeatedly;
    /// only the first call while `.checking` does anything.
    func runIfNeeded() async {
        guard phase == .checking, !running else { return }
        guard let sync = SyncManager.shared, !sync.hasLocalBaby,
              !LocalPrefs.shared.demoModeEnabled else {
            phase = .finished
            return
        }
        running = true
        defer { running = false }

        let found = await Self.firstResult(within: Self.probeTimeout) {
            await sync.probeForExistingFamily()
        } ?? .nothingFound

        // An invite link tapped during the check (a first-time joiner opening
        // the app from it) already took this device's setup — let the normal
        // accept flow own it.
        guard SyncManager.realSyncRole == .solo,
              LocalPrefs.shared.myParticipantID == nil, !sync.hasLocalBaby else {
            phase = .finished
            return
        }

        switch found {
        case .nothingFound:
            AppLog.sync.log("Fresh-install check: no existing family in iCloud")
            phase = .finished
        case .joined(let zoneID):
            AppLog.sync.log("Fresh-install check: found accepted share \(zoneID.zoneName, privacy: .public) owned by \(zoneID.ownerName, privacy: .public)")
            phase = .restoring(.coParent)
            await restore(.coParent, sync: sync, zoneID: zoneID)
        case .owned:
            AppLog.sync.log("Fresh-install check: found an owned family in the private zone")
            phase = .restoring(.owner)
            await restore(.owner, sync: sync, zoneID: nil)
        }
    }

    /// Re-runs a failed or slow restore (the restoring screen's Try again).
    func retry() {
        guard case .restoring(let kind) = phase, !running,
              let sync = SyncManager.shared else { return }
        Task {
            running = true
            defer { running = false }
            let zoneID = kind == .coParent ? SyncManager.attachedSharedZoneID() : nil
            await restore(kind, sync: sync, zoneID: zoneID)
        }
    }

    private func restore(_ kind: Kind, sync: SyncManager, zoneID: CKRecordZone.ID?) async {
        failed = false
        let ok: Bool
        switch kind {
        case .coParent:
            guard let zoneID else { phase = .finished; return }
            ok = await sync.rejoinExistingShare(zoneID: zoneID)
        case .owner:
            ok = await sync.restoreOwnedFamily()
        }
        guard ok else {
            failed = true
            return
        }
        // The new phone is a known parent, not a first run: open the
        // per-device quests (reminders are device-local) the way a finished
        // join does, instead of letting the next launch grandfather them away.
        if sync.hasLocalBaby { SetupProgress.shared.markNewFlowComplete() }
        // Co-parent with no matching profile → RootView now routes to the join
        // flow (the data is already here). Owner with nothing in the zone →
        // onboarding. Either way, normal routing takes over.
        phase = .finished
    }

    /// Returns `operation`'s result, or nil when `timeout` passes first. The
    /// operation keeps running in the background after a timeout (CloudKit
    /// calls don't honor cancellation promptly); its late result is ignored.
    private static func firstResult<T>(within timeout: Duration,
                                       _ operation: @escaping @MainActor () async -> T) async -> T? {
        let box = FirstResultBox<T>()
        return await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            box.continuation = continuation
            Task { @MainActor in box.resume(await operation()) }
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                box.resume(nil)
            }
        }
    }
}

/// Resumes its continuation exactly once: whichever of the operation and the
/// timer finishes first wins. Only ever touched on the main actor (both
/// resuming tasks are `@MainActor`), so the once-check needs no lock.
private final class FirstResultBox<T> {
    var continuation: CheckedContinuation<T?, Never>?
    func resume(_ value: T?) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}

/// The pure decisions behind `CloudRestore`, kept free of CloudKit calls so
/// they're unit-testable.
enum CloudRestorePlan {

    /// What the existence check found for this iCloud account.
    enum Finding: Equatable {
        case nothingFound
        /// The private zone holds this account's own family.
        case owned
        /// The shared database holds the owner's zone: a share this account
        /// already accepted.
        case joined(CKRecordZone.ID)
    }

    /// The fresh-install signature: nothing on this device says it was ever
    /// set up. Any finished onboarding or join leaves `myParticipantID` set,
    /// and any accepted share leaves the role `.participant`, so a device that
    /// was set up never re-runs the check.
    static func shouldCheck(role: SyncRole, myParticipantID: UUID?, demoMode: Bool) -> Bool {
        !demoMode && role == .solo && myParticipantID == nil
    }

    /// Holding screen vs. normal routes. `.checking` stops blocking once a
    /// baby is already in the store (nothing to restore). `.restoring` blocks
    /// until the restore finishes, even after the baby lands: identity is
    /// only adopted at the end, and Home without an identity refuses writes
    /// (the co-parent would also flash the join flow).
    static func blocksRouting(phase: CloudRestore.Phase, hasBaby: Bool) -> Bool {
        switch phase {
        case .finished: false
        case .checking: !hasBaby
        case .restoring: true
        }
    }

    /// Combines the two database probes. An accepted share wins: the
    /// co-parent's private database may also hold a zone (every install
    /// creates an empty one; a parent may have tried the app solo before
    /// joining), but the share is the family both parents actually use.
    /// More than one shared Two of Us zone is ambiguous, so it falls back to
    /// the invite link instead of guessing a household.
    static func decide(sharedZones: [CKRecordZone.ID], privateHasBaby: Bool) -> Finding {
        let shared = sharedZones.filter { $0.zoneName == SyncConstants.zoneName }
        if shared.count == 1, let zone = shared.first { return .joined(zone) }
        if shared.count > 1 { return .nothingFound }
        return privateHasBaby ? .owned : .nothingFound
    }

    /// Which participant is "me" after restoring an OWNED family.
    ///
    /// The `cloudUserID` match is the ground truth. Fallback for owner rows
    /// created before owner-side stamping (2026-07-29) that were never
    /// back-filled: joiners have been stamped since 2026-06-12, so in the
    /// owner's own zone a single active full-access row with no stamp is the
    /// owner. Two or more unstamped rows are ambiguous → nil (never guess).
    static func ownerIdentity(among participants: [Participant], myCloudUserID: String?) -> Participant? {
        let active = participants.filter(\.isActive)
        if let myCloudUserID,
           let match = active.first(where: { $0.cloudUserID == myCloudUserID }) {
            return match
        }
        let unstamped = active.filter { $0.cloudUserID == nil && $0.role == .full }
        return unstamped.count == 1 ? unstamped.first : nil
    }

    /// Network-shaped failures mean "can't tell right now" → show onboarding
    /// as before, rather than holding a new user on a spinner.
    static func isTransient(_ error: Error) -> Bool {
        guard let ck = error as? CKError else { return false }
        switch ck.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable,
             .requestRateLimited, .zoneBusy, .notAuthenticated:
            return true
        default:
            return false
        }
    }
}

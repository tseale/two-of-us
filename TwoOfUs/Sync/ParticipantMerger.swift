import Foundation
import SwiftData

/// Collapses duplicate `Participant` rows that belong to the SAME iCloud
/// account, so one person never shows up twice in Settings → People.
///
/// Duplicates happen when a co-parent re-onboards (reinstall, leave + re-join):
/// the join flow creates a fresh Participant row each time, and the old row —
/// same human, same iCloud account — stays behind in the shared zone with the
/// events it logged still attributed to it.
///
/// `SyncManager.captureCloudUserID` stamps each joiner's CloudKit user record
/// name onto their row; two active rows sharing that id ARE one person. The
/// merge is deterministic — the newest join survives, ties broken by id — so
/// both parents' devices converge on the same survivor instead of fighting
/// over sync. Rows that predate the capture (nil `cloudUserID`) are never
/// auto-merged; Settings offers a manual merge for those.
enum ParticipantMerger {

    /// Merges every set of active participants sharing a `cloudUserID`, then
    /// re-attaches anything still pointing at previously merged-away rows (a
    /// write from the other phone can race the merge and land afterwards).
    /// Pure store surgery — the caller saves and enqueues the returned ids.
    @discardableResult
    static func mergeDuplicates(in context: ModelContext) -> [UUID] {
        let all = (try? context.fetch(FetchDescriptor<Participant>())) ?? []
        let active = all.filter(\.isActive)
        var changed: [UUID] = []

        let groups = Dictionary(grouping: active.filter { $0.cloudUserID != nil },
                                by: { $0.cloudUserID! })
        for (_, rows) in groups where rows.count > 1 {
            // Newest join survives: a re-join's fresh row is the one that
            // device's `myParticipantID` points at, so it must keep working.
            // uuidString tiebreak keeps concurrent mergers deterministic.
            guard let survivor = rows.max(by: {
                ($0.invitedAt, $0.id.uuidString) < ($1.invitedAt, $1.id.uuidString)
            }) else { continue }
            for dup in rows where dup.id != survivor.id {
                changed += merge(dup, into: survivor, in: context)
            }
        }

        // Stragglers: an event synced in attributed to a row that was already
        // merged away re-attaches to that account's live row.
        for tombstone in all where !tombstone.isActive {
            guard let cid = tombstone.cloudUserID,
                  let owner = active.first(where: { $0.cloudUserID == cid && $0.id != tombstone.id }),
                  owner.isActive
            else { continue }
            changed += reattachReferences(from: tombstone, to: owner, in: context)
        }
        return changed
    }

    /// Folds `duplicate` into `survivor`: the survivor fills any gaps from the
    /// duplicate (photo, name, iCloud identity — a re-join that skipped the
    /// photo picker keeps the old avatar), every event and plan reference moves
    /// over, and the duplicate deactivates. Also the manual-merge entry point
    /// for legacy rows with no `cloudUserID`. Returns the changed record ids.
    ///
    /// Deliberately does NOT touch `invitedAt`: the survivor pick keys on it,
    /// and rewriting it could flip a concurrent device's pick mid-sync.
    @discardableResult
    static func merge(_ duplicate: Participant, into survivor: Participant,
                      in context: ModelContext) -> [UUID] {
        guard duplicate.id != survivor.id else { return [] }
        var changed: [UUID] = [survivor.id, duplicate.id]

        if survivor.photoData == nil { survivor.photoData = duplicate.photoData }
        if survivor.displayName.isEmpty { survivor.displayName = duplicate.displayName }
        if survivor.cloudUserID == nil { survivor.cloudUserID = duplicate.cloudUserID }
        // Same person — merging must never demote them.
        if survivor.role != .full && duplicate.role == .full { survivor.role = .full }
        // Same person — a pause on either row survives the merge on the LIVE
        // row (otherwise the owner's Resume button disappears with the
        // duplicate while the pause itself lives on in a tombstone).
        if survivor.pausedAt == nil { survivor.pausedAt = duplicate.pausedAt }
        duplicate.pausedAt = nil

        changed += reattachReferences(from: duplicate, to: survivor, in: context)
        duplicate.isActive = false
        return changed
    }

    /// Rewrites every reference to `old` — event attribution (id + the
    /// denormalized name/color) and schedule assignments — onto `new`.
    private static func reattachReferences(from old: Participant, to new: Participant,
                                           in context: ModelContext) -> [UUID] {
        var changed: [UUID] = []

        func rewriteEvents<T: PersistentModel & AnyEventModel & HasSyncID>(_ type: T.Type) {
            for e in (try? context.fetch(FetchDescriptor<T>())) ?? [] where e.loggedByID == old.id {
                e.loggedByID = new.id
                e.loggedByName = new.displayName
                e.loggedByColorHex = new.colorHex
                changed.append(e.id)
            }
        }
        rewriteEvents(FeedEvent.self)
        rewriteEvents(SleepEvent.self)
        rewriteEvents(DiaperEvent.self)
        rewriteEvents(NoteEvent.self)

        for slot in (try? context.fetch(FetchDescriptor<PlanSlot>())) ?? []
        where slot.assignedToID == old.id {
            slot.assignedToID = new.id
            slot.assignedToName = new.displayName
            slot.assignedToColorHex = new.colorHex
            changed.append(slot.id)
        }
        for override in (try? context.fetch(FetchDescriptor<PlanOverride>())) ?? [] {
            var touched = false
            if override.assignedToID == old.id {
                override.assignedToID = new.id
                override.assignedToName = new.displayName
                override.assignedToColorHex = new.colorHex
                touched = true
            }
            if override.createdByID == old.id {
                override.createdByID = new.id
                touched = true
            }
            if touched { changed.append(override.id) }
        }
        return changed
    }
}

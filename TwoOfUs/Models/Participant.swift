import Foundation
import SwiftData

/// Someone with access to the baby's data. v1 single-device uses one owner
/// Participant; invite/revoke and additional participants arrive in Increment 2.
@Model
final class Participant {
    var id: UUID = UUID()
    var displayName: String = ""
    var colorHex: String = ""
    var roleRaw: String = ParticipantRole.full.rawValue
    var cloudUserID: String?           // CKShare participant identity, when known
    var isActive: Bool = true          // false once access is revoked
    var invitedAt: Date = Date()
    /// Non-nil while access is temporarily paused — distinct from `isActive`
    /// (revoked/removed). A paused participant stays on the CKShare and in the
    /// people list, but is excluded from the night rotation, feed/slot
    /// assignment, and "logged by" pickers, and can't log or see updates from
    /// their own device while it's set. Owner-only, reversible via `resume`.
    var pausedAt: Date?

    /// Optional avatar (downscaled JPEG, synced as a CKAsset; stored inline for
    /// CloudKit-mirroring compatibility). See `ImageDownscale`.
    var photoData: Data?
    var ckSystemFields: Data?           // archived CKRecord system fields (see Baby.ckSystemFields)

    var role: ParticipantRole {
        get { ParticipantRole(rawValue: roleRaw) ?? .full }
        set { roleRaw = newValue.rawValue }
    }

    var isPaused: Bool { pausedAt != nil }

    init(
        id: UUID = UUID(),
        displayName: String,
        colorHex: String,
        role: ParticipantRole = .full,
        cloudUserID: String? = nil,
        isActive: Bool = true,
        invitedAt: Date = Date(),
        pausedAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.colorHex = colorHex
        self.roleRaw = role.rawValue
        self.cloudUserID = cloudUserID
        self.isActive = isActive
        self.invitedAt = invitedAt
        self.pausedAt = pausedAt
    }
}

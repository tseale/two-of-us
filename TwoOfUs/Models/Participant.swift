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

    /// Optional avatar (downscaled JPEG, synced as a CKAsset; stored inline for
    /// CloudKit-mirroring compatibility). See `ImageDownscale`.
    var photoData: Data?
    var ckSystemFields: Data?           // archived CKRecord system fields (see Baby.ckSystemFields)

    var role: ParticipantRole {
        get { ParticipantRole(rawValue: roleRaw) ?? .full }
        set { roleRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        displayName: String,
        colorHex: String,
        role: ParticipantRole = .full,
        cloudUserID: String? = nil,
        isActive: Bool = true,
        invitedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.colorHex = colorHex
        self.roleRaw = role.rawValue
        self.cloudUserID = cloudUserID
        self.isActive = isActive
        self.invitedAt = invitedAt
    }
}

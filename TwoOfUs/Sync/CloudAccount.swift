import Foundation
import CloudKit

/// Lightweight iCloud availability check for the setup flows (the invite step
/// shows a gentle notice instead of the share button when iCloud is off).
enum CloudAccount {
    /// True when this device can actually use CloudKit — i.e. an iCloud account
    /// is signed in. Deliberately NOT `ubiquityIdentityToken`: that token also
    /// requires iCloud Drive to be on, which CloudKit doesn't need — gating on it
    /// read Drive-off as iCloud-off and silently disabled sync for those users.
    /// (`CKContainer(identifier:)` only traps when the iCloud entitlement is
    /// missing from the build, and every configuration ships it.)
    static func isAvailable() async -> Bool {
        let status = try? await SyncConstants.container.accountStatus()
        return status == .available
    }
}

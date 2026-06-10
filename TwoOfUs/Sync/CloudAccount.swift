import Foundation
import CloudKit

/// Lightweight iCloud availability check for the setup flows (the invite step
/// shows a gentle notice instead of the share button when iCloud is off).
enum CloudAccount {
    /// True when this device can actually use CloudKit. The ubiquity-token guard
    /// comes first — `CKContainer(identifier:)` can trap without the iCloud
    /// entitlement/account (same guard as `SyncManager.cloudAvailable`).
    static func isAvailable() async -> Bool {
        guard FileManager.default.ubiquityIdentityToken != nil else { return false }
        let status = try? await SyncConstants.container.accountStatus()
        return status == .available
    }
}

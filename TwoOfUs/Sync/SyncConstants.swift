import Foundation
import CloudKit

/// Shared identifiers and record-type names for the CloudKit sync layer.
enum SyncConstants {
    /// The CloudKit container (matches the iCloud entitlement).
    static let containerID = "iCloud.com.taylorseale.twoofus"

    /// Single custom zone that holds all of the baby's records. A custom zone
    /// (not the default zone) is required to create a zone-wide CKShare.
    /// Renaming this strands existing installs' records (a zone-wide CKShare is
    /// bound to its zone) — only safe while no one is syncing yet.
    static let zoneName = "TwoOfUsZone"

    /// CKRecord type names — one per @Model that syncs.
    enum RecordType {
        static let baby = "Baby"
        static let feed = "FeedEvent"
        static let sleep = "SleepEvent"
        static let diaper = "DiaperEvent"
        static let participant = "Participant"
        static let settings = "SharedSettings"
    }

    static var container: CKContainer { CKContainer(identifier: containerID) }
}

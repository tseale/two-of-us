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
        static let planSlot = "PlanSlot"
        static let planOverride = "PlanOverride"

        /// Every type this build can apply. A new record type MUST be added
        /// here as well as above — this set drives the "did an app update
        /// teach us new record types?" re-fetch (`SyncManager`), which is what
        /// re-delivers records an older build fetched and silently dropped.
        static let all: Set<String> = [
            baby, feed, sleep, diaper, participant, settings, planSlot, planOverride,
        ]
    }

    static var container: CKContainer { CKContainer(identifier: containerID) }
}

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
        static let note = "NoteEvent"
        static let participant = "Participant"
        static let settings = "SharedSettings"
        static let planSlot = "PlanSlot"
        static let planOverride = "PlanOverride"

        /// Every type this build can apply. A new record type MUST be added
        /// here as well as above — this set drives the "did an app update
        /// teach us new record types?" re-fetch (`SyncManager`), which is what
        /// re-delivers records an older build fetched and silently dropped.
        /// Bump whenever a build adds a FIELD to an existing synced record
        /// type (a whole new record type is detected automatically from
        /// `all` below). A device that fetched a record before its build knew
        /// a field silently dropped that field's value, and the checkpointed
        /// fetch token never re-delivers it — growing this number forces the
        /// same one-time whole-zone re-fetch the type mechanism does. This is
        /// exactly how `SharedSettings.snooCredentials` (added Aug 2026 with
        /// no new type alongside it) went missing on the co-parent's phone.
        /// Generation 2: snooCredentials + SleepEvent.sourceRaw.
        static let schemaGeneration = 2

        static let all: Set<String> = [
            baby, feed, sleep, diaper, note, participant, settings, planSlot, planOverride,
        ]
    }

    static var container: CKContainer { CKContainer(identifier: containerID) }
}

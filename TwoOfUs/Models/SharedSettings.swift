import Foundation
import SwiftData

/// App-wide settings that are shared between all participants (synced in
/// Increment 2). Stored as a single record.
@Model
final class SharedSettings {
    var id: UUID = UUID()
    var targetFeedIntervalMinutes: Int = 180   // next-feed countdown target (3h)
    var ozPresets: [Double] = [2, 3, 4]
    var defaultFeedOz: Double = 4              // one-tap feed amount (widget / Siri)
    var ckSystemFields: Data?                  // archived CKRecord system fields (see Baby.ckSystemFields)

    init(
        id: UUID = UUID(),
        targetFeedIntervalMinutes: Int = 180,
        ozPresets: [Double] = [2, 3, 4],
        defaultFeedOz: Double = 4
    ) {
        self.id = id
        self.targetFeedIntervalMinutes = targetFeedIntervalMinutes
        self.ozPresets = ozPresets
        self.defaultFeedOz = defaultFeedOz
    }

    var targetFeedInterval: TimeInterval { TimeInterval(targetFeedIntervalMinutes * 60) }
}

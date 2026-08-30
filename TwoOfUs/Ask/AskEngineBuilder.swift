import Foundation
import SwiftData

/// Bridges the App Group store (via `QuickLogger`) to a fully-populated
/// `AskEngine`. Lives with the Ask code (app target only) so QuickLogger
/// itself stays lean for the widget/watch targets that share it.
extension AskEngine {

    /// Builds an engine over the full live event history. Full-history is
    /// deliberate: "longest stretch ever" and all-time totals need it, and at
    /// this app's scale (one baby, months of events) the fetch is trivial.
    @MainActor
    static func fromStore(_ logger: QuickLogger, now: Date = .now) -> AskEngine {
        var engine = AskEngine()
        engine.now = now
        engine.feeds = (try? logger.context.fetch(
            FetchDescriptor<FeedEvent>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        engine.sleeps = (try? logger.context.fetch(
            FetchDescriptor<SleepEvent>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        engine.diapers = (try? logger.context.fetch(
            FetchDescriptor<DiaperEvent>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        engine.notes = (try? logger.context.fetch(
            FetchDescriptor<NoteEvent>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        engine.babyName = logger.babyName ?? "Baby"
        if let settings = logger.sharedSettings {
            engine.nightStartMinute = settings.nightStartMinute
            engine.nightEndMinute = settings.nightEndMinute
            engine.feedIntervalAfter = { [weak settings] date in
                settings?.feedInterval(after: date) ?? 180 * 60
            }
        }
        engine.sleepTarget = logger.sleepTarget
        return engine
    }
}

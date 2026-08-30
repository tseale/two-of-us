// Maintains the semantic Spotlight index behind the iOS 27 Siri exposure.
// Same compiler fence as EventEntities.swift: stable toolchains skip it.
#if compiler(>=6.4)
import CoreSpotlight
import Foundation
import SwiftData

/// Rebuilds the app's slice of the system semantic index from the live event
/// log. Full rebuild by design: at this app's scale (one baby) it's cheap,
/// and wipe-then-write makes soft-delete eviction airtight — an edited or
/// deleted event can never linger in Siri answers, and events synced from the
/// co-parent index on the next pass with no per-event bookkeeping.
@available(iOS 27.0, *)
enum SpotlightIndexer {

    /// How much history gets indexed. Events older than this are reachable
    /// in-app; Siri questions are overwhelmingly about the recent past.
    private static let eventWindowDays = 90
    private static let summaryWindowDays = 30

    @MainActor private static var pending: Task<Void, Never>?

    /// Debounced entry point — safe to call from any isolation, on every
    /// save and foreground.
    nonisolated static func requestReindex() {
        Task { @MainActor in
            pending?.cancel()
            pending = Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                await reindexNow()
            }
        }
    }

    @MainActor
    static func reindexNow() async {
        guard LocalPrefs.shared.siriIndexingEnabled, !LocalPrefs.shared.demoModeEnabled else {
            try? await CSSearchableIndex.default().deleteAllSearchableItems()
            AppLog.ai.log("Spotlight index cleared (indexing disabled or demo mode)")
            return
        }
        guard let logger = QuickLogger.make() else { return }
        let hours = eventWindowDays * 24

        let feeds = logger.recentFeeds(hours: hours).map(FeedEntity.init)
        let sleeps = logger.recentSleeps(hours: hours).map(SleepEntity.init)
        let since = Date.now.addingTimeInterval(TimeInterval(-hours * 3600))
        let diapers = ((try? logger.context.fetch(FetchDescriptor<DiaperEvent>(
            predicate: #Predicate { $0.deletedAt == nil && $0.timestamp >= since }
        ))) ?? []).map(DiaperEntity.init)
        // Notes are never windowed — "when did we start X" is exactly the
        // question that reaches back months.
        let notes = ((try? logger.context.fetch(FetchDescriptor<NoteEvent>(
            predicate: #Predicate { $0.deletedAt == nil }
        ))) ?? []).map(NoteEntity.init)
        let summaries = daySummaries()

        do {
            let index = CSSearchableIndex.default()
            try await index.deleteAllSearchableItems()
            try await index.indexAppEntities(feeds)
            try await index.indexAppEntities(sleeps)
            try await index.indexAppEntities(diapers)
            try await index.indexAppEntities(notes)
            try await index.indexAppEntities(summaries)
            AppLog.ai.log("Spotlight reindex: \(feeds.count) feeds, \(sleeps.count) sleeps, \(diapers.count) diapers, \(notes.count) notes, \(summaries.count) summaries")
        } catch {
            AppLog.ai.error("Spotlight reindex failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// One prose summary per recent day, re-derived from the event log via
    /// AskEngine so its numbers agree with every other surface.
    @MainActor
    static func daySummaries() -> [DaySummaryEntity] {
        guard let logger = QuickLogger.make() else { return [] }
        let engine = AskEngine.fromStore(logger)
        let calendar = Calendar.current
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        var result: [DaySummaryEntity] = []
        for daysAgo in stride(from: summaryWindowDays - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo,
                                          to: calendar.startOfDay(for: .now)) else { continue }
            var dayEngine = engine
            // Point the engine's clock at that day's end so `.today` /
            // `.lastNight` resolve to the day being summarized.
            dayEngine.now = min(calendar.date(byAdding: .day, value: 1, to: day) ?? day, Date.now)

            let sleep = dayEngine.answer(ParsedQuery(metric: .totalSleep, period: .today))
            let feedOz = dayEngine.answer(ParsedQuery(metric: .feedOz, period: .today))
            let diapers = dayEngine.answer(ParsedQuery(metric: .diaperCount(nil), period: .today))
            let night = dayEngine.answer(ParsedQuery(metric: .nightWakes, period: .lastNight))
            let bedtime = dayEngine.answer(ParsedQuery(metric: .bedtime, period: .lastNight))

            let sentences = [sleep, feedOz, diapers, night, bedtime]
                .map(\.sentence)
                .filter { !$0.hasPrefix("No ") && !$0.hasPrefix("I don't see") }
            guard !sentences.isEmpty else { continue }

            result.append(DaySummaryEntity(
                id: "day-\(formatter.string(from: day))",
                day: day,
                summary: sentences.joined(separator: " ")
            ))
        }
        return result
    }
}
#endif

import AppIntents
import CoreSpotlight

/// Keeps Spotlight's copy of the last month of care events current, so the
/// iOS 27 Siri and Spotlight resolve questions against real entities
/// (`CareEventEntity`). Every local write and every applied sync batch asks
/// for a reindex; bursts coalesce into one run after a short quiet period, so
/// a widget batch or a co-parent's night of logs costs one pass, not N.
@MainActor
enum SpotlightIndexer {
    private static var pending: Task<Void, Never>?

    static func scheduleReindex() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            do {
                try await reindexAll()
            } catch {
                AppLog.store.error("Spotlight reindex failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Replaces the whole index domain rather than diffing: a few hundred
    /// items, and it makes soft-deleted and edited-away events disappear
    /// without tracking them.
    static func reindexAll() async throws {
        let entities = CareEventCatalog.recent(limit: 500)
        let index = CSSearchableIndex.default()
        try await index.deleteAppEntities(ofType: CareEventEntity.self)
        try await index.indexAppEntities(entities)
        AppLog.store.debug("Spotlight indexed \(entities.count) care events")
    }
}

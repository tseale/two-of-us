// iOS 27 Siri exposure: AppEntity + IndexedEntity conformances for the
// event log, so the system semantic index (and with it the Siri app) can
// answer lookup questions over Miller's data directly.
//
// The whole file is fenced to the iOS 27 SDK's compiler (Swift 6.4, Xcode 27):
// stable-toolchain builds (Xcode Cloud, `make test` on release Xcode) compile
// it to nothing, keeping the deployment target's iOS 26 baseline intact.
#if compiler(>=6.4)
import AppIntents
import CoreSpotlight
import Foundation
import SwiftData

// MARK: - Feed

@available(iOS 27.0, *)
struct FeedEntity: AppEntity, IndexedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Feed")
    static let defaultQuery = FeedEntityQuery()

    let id: UUID
    @Property(title: "Amount (oz)") var amountOz: Double
    @Property(title: "Time") var time: Date
    @Property(title: "Logged By") var loggedBy: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(OzFormat.string(amountOz)) oz bottle",
            subtitle: "\(time.formatted(date: .abbreviated, time: .shortened))\(loggedBy.isEmpty ? "" : " · \(loggedBy)")"
        )
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attrs = CSSearchableItemAttributeSet(contentType: .content)
        attrs.title = "\(OzFormat.string(amountOz)) oz bottle"
        attrs.contentDescription = "Feed: \(OzFormat.string(amountOz)) oz at \(time.formatted(date: .abbreviated, time: .shortened))\(loggedBy.isEmpty ? "" : ", logged by \(loggedBy)")"
        attrs.contentCreationDate = time
        return attrs
    }

    @MainActor
    init(_ event: FeedEvent) {
        id = event.id
        amountOz = event.amountOz
        time = event.timestamp
        loggedBy = event.loggedByName
    }
}

@available(iOS 27.0, *)
struct FeedEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [FeedEntity] {
        guard let logger = QuickLogger.make() else { return [] }
        return ((try? logger.context.fetch(FetchDescriptor<FeedEvent>(
            predicate: #Predicate { identifiers.contains($0.id) && $0.deletedAt == nil }
        ))) ?? []).map(FeedEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [FeedEntity] {
        guard let logger = QuickLogger.make() else { return [] }
        return logger.recentFeeds(hours: 24)
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(5)
            .map(FeedEntity.init)
    }
}

// MARK: - Sleep

@available(iOS 27.0, *)
struct SleepEntity: AppEntity, IndexedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Sleep")
    static let defaultQuery = SleepEntityQuery()

    let id: UUID
    @Property(title: "Fell Asleep") var start: Date
    @Property(title: "Woke Up") var end: Date?
    @Property(title: "Duration (minutes)") var minutes: Int?

    var displayRepresentation: DisplayRepresentation {
        let title: LocalizedStringResource = end == nil
            ? "Sleep — still asleep"
            : "Sleep — \(TimeFormatting.duration(minutes: minutes ?? 0))"
        return DisplayRepresentation(
            title: title,
            subtitle: "\(start.formatted(date: .abbreviated, time: .shortened))\(end.map { " to \($0.formatted(date: .omitted, time: .shortened))" } ?? "")"
        )
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attrs = CSSearchableItemAttributeSet(contentType: .content)
        attrs.title = end == nil ? "Sleep in progress" : "Sleep, \(TimeFormatting.duration(minutes: minutes ?? 0))"
        attrs.contentDescription = "Fell asleep \(start.formatted(date: .abbreviated, time: .shortened))"
            + (end.map { ", woke \($0.formatted(date: .abbreviated, time: .shortened))" } ?? ", still asleep")
        attrs.contentCreationDate = start
        return attrs
    }

    @MainActor
    init(_ event: SleepEvent) {
        id = event.id
        start = event.startedAt
        end = event.endedAt
        minutes = event.endedAt.map { Int($0.timeIntervalSince(event.startedAt) / 60) }
    }
}

@available(iOS 27.0, *)
struct SleepEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [SleepEntity] {
        guard let logger = QuickLogger.make() else { return [] }
        return ((try? logger.context.fetch(FetchDescriptor<SleepEvent>(
            predicate: #Predicate { identifiers.contains($0.id) && $0.deletedAt == nil }
        ))) ?? []).map(SleepEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [SleepEntity] {
        guard let logger = QuickLogger.make() else { return [] }
        return logger.recentSleeps(hours: 24)
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(5)
            .map(SleepEntity.init)
    }
}

// MARK: - Diaper

@available(iOS 27.0, *)
struct DiaperEntity: AppEntity, IndexedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Diaper")
    static let defaultQuery = DiaperEntityQuery()

    let id: UUID
    @Property(title: "Type") var type: String
    @Property(title: "Time") var time: Date
    @Property(title: "Logged By") var loggedBy: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(type) diaper",
            subtitle: "\(time.formatted(date: .abbreviated, time: .shortened))"
        )
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attrs = CSSearchableItemAttributeSet(contentType: .content)
        attrs.title = "\(type) diaper"
        attrs.contentDescription = "Diaper change (\(type.lowercased())) at \(time.formatted(date: .abbreviated, time: .shortened))"
        attrs.contentCreationDate = time
        return attrs
    }

    @MainActor
    init(_ event: DiaperEvent) {
        id = event.id
        type = event.type.label
        time = event.timestamp
        loggedBy = event.loggedByName
    }
}

@available(iOS 27.0, *)
struct DiaperEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [DiaperEntity] {
        guard let logger = QuickLogger.make() else { return [] }
        return ((try? logger.context.fetch(FetchDescriptor<DiaperEvent>(
            predicate: #Predicate { identifiers.contains($0.id) && $0.deletedAt == nil }
        ))) ?? []).map(DiaperEntity.init)
    }

    func suggestedEntities() async throws -> [DiaperEntity] { [] }
}

// MARK: - Note

@available(iOS 27.0, *)
struct NoteEntity: AppEntity, IndexedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Note")
    static let defaultQuery = NoteEntityQuery()

    let id: UUID
    @Property(title: "Note") var text: String
    @Property(title: "Time") var time: Date

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(text)",
            subtitle: "\(time.formatted(date: .abbreviated, time: .shortened))"
        )
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attrs = CSSearchableItemAttributeSet(contentType: .text)
        attrs.title = text
        attrs.contentDescription = "Note from \(time.formatted(date: .abbreviated, time: .shortened)): \(text)"
        attrs.contentCreationDate = time
        return attrs
    }

    @MainActor
    init(_ event: NoteEvent) {
        id = event.id
        text = event.text
        time = event.timestamp
    }
}

@available(iOS 27.0, *)
struct NoteEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [NoteEntity] {
        guard let logger = QuickLogger.make() else { return [] }
        return ((try? logger.context.fetch(FetchDescriptor<NoteEvent>(
            predicate: #Predicate { identifiers.contains($0.id) && $0.deletedAt == nil }
        ))) ?? []).map(NoteEntity.init)
    }

    func suggestedEntities() async throws -> [NoteEntity] { [] }
}

// MARK: - Day summary (derived, indexed math)

/// The semantic index reasons over items but does no arithmetic — so the
/// arithmetic becomes an item. One entity per recent day carrying the day's
/// totals as text; "how much did he sleep on Tuesday?" becomes a lookup.
/// Re-derived from the event log on every reindex, never persisted.
@available(iOS 27.0, *)
struct DaySummaryEntity: AppEntity, IndexedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Daily Summary")
    static let defaultQuery = DaySummaryEntityQuery()

    /// Stable per-day id ("day-2026-06-10") so a reindex replaces, not duplicates.
    let id: String
    @Property(title: "Day") var day: Date
    @Property(title: "Summary") var summary: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(day.formatted(date: .complete, time: .omitted))",
            subtitle: "\(summary)"
        )
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attrs = CSSearchableItemAttributeSet(contentType: .text)
        attrs.title = "Daily summary — \(day.formatted(date: .complete, time: .omitted))"
        attrs.contentDescription = summary
        attrs.contentCreationDate = day
        return attrs
    }

    init(id: String, day: Date, summary: String) {
        self.id = id
        self.day = day
        self.summary = summary
    }
}

@available(iOS 27.0, *)
struct DaySummaryEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [DaySummaryEntity] {
        SpotlightIndexer.daySummaries().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [DaySummaryEntity] {
        Array(SpotlightIndexer.daySummaries().suffix(3))
    }
}
#endif

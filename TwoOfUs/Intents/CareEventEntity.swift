import AppIntents
import CoreSpotlight
import Foundation
import SwiftData
import UniformTypeIdentifiers

/// The kind of a logged care event, as Siri and Shortcuts name it.
enum CareEventKind: String, AppEnum {
    case feed, sleep, diaper, note

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Care Event Kind")
    static var caseDisplayRepresentations: [CareEventKind: DisplayRepresentation] = [
        .feed: "Feed", .sleep: "Sleep", .diaper: "Diaper", .note: "Note"
    ]
}

/// One logged feed, sleep, diaper, or note as Siri, Spotlight, and the
/// Shortcuts app see it. Read-only — the log intents create events, this type
/// only describes them — and a plain value snapshotted from the SwiftData
/// models, so it crosses into the App Intents runtime without dragging a
/// model context along.
///
/// `IndexedEntity` puts the last month of events into Spotlight
/// (`SpotlightIndexer`), which is what lets the iOS 27 Siri resolve "Miller's
/// last dirty diaper" against a real record instead of only our canned
/// query intents.
struct CareEventEntity: AppEntity, IndexedEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Care Event")
    static var defaultQuery = CareEventQuery()

    let id: UUID
    let babyName: String

    @Property(title: "Kind") var kind: CareEventKind
    @Property(title: "Time") var time: Date
    @Property(title: "Amount (oz)") var amountOz: Double?
    @Property(title: "Duration (minutes)") var durationMinutes: Int?
    @Property(title: "Diaper Type") var diaperType: String?
    @Property(title: "Logged By") var loggedBy: String
    @Property(title: "Note") var note: String?

    init(id: UUID, babyName: String, kind: CareEventKind, time: Date,
         amountOz: Double? = nil, durationMinutes: Int? = nil, diaperType: String? = nil,
         loggedBy: String, note: String? = nil) {
        self.id = id
        self.babyName = babyName
        self.kind = kind
        self.time = time
        self.amountOz = amountOz
        self.durationMinutes = durationMinutes
        self.diaperType = diaperType
        self.loggedBy = loggedBy
        self.note = note
    }

    init(feed: FeedEvent, babyName: String) {
        self.init(id: feed.id, babyName: babyName, kind: .feed, time: feed.timestamp,
                  amountOz: feed.amountOz, loggedBy: feed.loggedByName, note: feed.notes)
    }

    init(sleep: SleepEvent, babyName: String) {
        let minutes = sleep.endedAt.map { Int($0.timeIntervalSince(sleep.startedAt) / 60) }
        self.init(id: sleep.id, babyName: babyName, kind: .sleep, time: sleep.startedAt,
                  durationMinutes: minutes, loggedBy: sleep.loggedByName, note: sleep.notes)
    }

    init(diaper: DiaperEvent, babyName: String) {
        self.init(id: diaper.id, babyName: babyName, kind: .diaper, time: diaper.timestamp,
                  diaperType: diaper.type.label, loggedBy: diaper.loggedByName, note: diaper.notes)
    }

    init(note: NoteEvent, babyName: String) {
        self.init(id: note.id, babyName: babyName, kind: .note, time: note.timestamp,
                  loggedBy: note.loggedByName, note: note.text)
    }

    var title: String {
        switch kind {
        case .feed:
            return "🍼 \(OzFormat.string(amountOz ?? 0)) oz bottle"
        case .sleep:
            return durationMinutes.map { "💤 Slept \(TimeFormatting.duration(minutes: $0))" } ?? "💤 Sleeping"
        case .diaper:
            return "💩 \(diaperType ?? "Wet") diaper"
        case .note:
            return "📝 \(note ?? "Note")"
        }
    }

    var subtitle: String {
        let who = loggedBy.isEmpty ? "" : " · \(loggedBy)"
        return "\(Self.whenFormatter.string(from: time))\(who)"
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(subtitle)")
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = title
        attributes.contentDescription = "\(babyName) · \(subtitle)"
        attributes.contentCreationDate = time
        attributes.keywords = [babyName, kind.rawValue] + (diaperType.map { [$0.lowercased()] } ?? [])
        return attributes
    }

    private static let whenFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true
        return f
    }()
}

@available(iOS 27, *)
extension CareEventEntity: SyncableEntity, OwnershipProvidingEntity {
    /// Every event is the household's: both parents (and any invited
    /// caregiver) see and edit the same records, so Siri should never treat
    /// one as private to whoever is asking.
    var ownership: EntityOwnership { .shared }
}

// MARK: - Query

struct CareEventQuery: EntityQuery, EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [CareEventEntity] {
        await CareEventCatalog.events(ids: identifiers)
    }

    func suggestedEntities() async throws -> [CareEventEntity] {
        await CareEventCatalog.recent(limit: 12)
    }

    func entities(matching string: String) async throws -> [CareEventEntity] {
        let needle = string.lowercased()
        guard !needle.isEmpty else { return [] }
        return await CareEventCatalog.recent(limit: 300).filter {
            $0.title.lowercased().contains(needle)
                || $0.loggedBy.lowercased().contains(needle)
                || ($0.note?.lowercased().contains(needle) ?? false)
        }
    }
}

/// "Find Care Events" in the Shortcuts app: filter by kind, time, and bottle
/// size, sort by time. This is what makes automations like "if there's been
/// no feed since 4 hours ago, remind me" buildable without us shipping a
/// bespoke intent for each one.
extension CareEventQuery: EntityPropertyQuery {
    static var properties = QueryProperties {
        Property(\CareEventEntity.$kind) {
            EqualToComparator { kind in { $0.kind == kind } }
            NotEqualToComparator { kind in { $0.kind != kind } }
        }
        Property(\CareEventEntity.$time) {
            LessThanComparator { date in { $0.time < date } }
            GreaterThanComparator { date in { $0.time > date } }
            IsBetweenComparator { from, to in { $0.time >= from && $0.time <= to } }
        }
        Property(\CareEventEntity.$amountOz) {
            LessThanComparator { oz in { ($0.amountOz ?? 0) < oz } }
            GreaterThanComparator { oz in { ($0.amountOz ?? 0) > oz } }
        }
        Property(\CareEventEntity.$loggedBy) {
            EqualToComparator { name in { $0.loggedBy.caseInsensitiveCompare(name) == .orderedSame } }
            ContainsComparator { text in { $0.loggedBy.localizedCaseInsensitiveContains(text) } }
        }
    }

    static var sortingOptions = SortingOptions {
        SortableBy(\CareEventEntity.$time)
        SortableBy(\CareEventEntity.$amountOz)
    }

    static var findIntentDescription: IntentDescription? {
        IntentDescription("Finds logged feeds, sleeps, diapers, and notes from the last 30 days.",
                          categoryName: "Ask")
    }

    func entities(matching comparators: [(CareEventEntity) -> Bool],
                  mode: ComparatorMode,
                  sortedBy: [EntityQuerySort<CareEventEntity>],
                  limit: Int?) async throws -> [CareEventEntity] {
        var results = await CareEventCatalog.recent(limit: 1000).filter { entity in
            switch mode {
            case .and: return comparators.allSatisfy { $0(entity) }
            case .or: return comparators.contains { $0(entity) }
            }
        }
        for sort in sortedBy.reversed() {
            let ascending = sort.order == .ascending
            switch sort.by {
            case \CareEventEntity.$amountOz:
                results.sort { ascending ? ($0.amountOz ?? 0) < ($1.amountOz ?? 0) : ($0.amountOz ?? 0) > ($1.amountOz ?? 0) }
            default:
                results.sort { ascending ? $0.time < $1.time : $0.time > $1.time }
            }
        }
        if let limit { results = Array(results.prefix(limit)) }
        return results
    }
}

@available(iOS 27, *)
extension CareEventQuery: IndexedEntityQuery {
    func reindexEntities(for identifiers: [UUID], indexDescription: CSSearchableIndexDescription) async throws {
        let entities = await CareEventCatalog.events(ids: identifiers)
        try await CSSearchableIndex.default().indexAppEntities(entities)
    }

    func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        try await SpotlightIndexer.reindexAll()
    }
}

// MARK: - Store access

/// Reads events for the entity layer through the same App Group store the
/// intents use, so Siri sees exactly what the app and widgets see.
@MainActor
enum CareEventCatalog {
    /// How far back Spotlight is kept current. Older events remain searchable
    /// in-app; Siri questions are about recent days.
    static let indexedWindowDays = 30

    static func recent(limit: Int, days: Int = indexedWindowDays) -> [CareEventEntity] {
        guard let logger = QuickLogger.make() else { return [] }
        let since = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .distantPast
        let name = logger.babyName ?? "Baby"
        let context = logger.context

        var all: [CareEventEntity] = []
        let feeds = (try? context.fetch(FetchDescriptor<FeedEvent>(
            predicate: #Predicate { $0.deletedAt == nil && $0.timestamp >= since }))) ?? []
        all += feeds.map { CareEventEntity(feed: $0, babyName: name) }
        let sleeps = (try? context.fetch(FetchDescriptor<SleepEvent>(
            predicate: #Predicate { $0.deletedAt == nil && $0.startedAt >= since }))) ?? []
        all += sleeps.map { CareEventEntity(sleep: $0, babyName: name) }
        let diapers = (try? context.fetch(FetchDescriptor<DiaperEvent>(
            predicate: #Predicate { $0.deletedAt == nil && $0.timestamp >= since }))) ?? []
        all += diapers.map { CareEventEntity(diaper: $0, babyName: name) }
        let notes = (try? context.fetch(FetchDescriptor<NoteEvent>(
            predicate: #Predicate { $0.deletedAt == nil && $0.timestamp >= since }))) ?? []
        all += notes.map { CareEventEntity(note: $0, babyName: name) }

        return Array(all.sorted { $0.time > $1.time }.prefix(limit))
    }

    static func events(ids: [UUID]) -> [CareEventEntity] {
        guard !ids.isEmpty, let logger = QuickLogger.make() else { return [] }
        let name = logger.babyName ?? "Baby"
        let context = logger.context

        var byID: [UUID: CareEventEntity] = [:]
        for feed in (try? context.fetch(FetchDescriptor<FeedEvent>(
            predicate: #Predicate { $0.deletedAt == nil && ids.contains($0.id) }))) ?? [] {
            byID[feed.id] = CareEventEntity(feed: feed, babyName: name)
        }
        for sleep in (try? context.fetch(FetchDescriptor<SleepEvent>(
            predicate: #Predicate { $0.deletedAt == nil && ids.contains($0.id) }))) ?? [] {
            byID[sleep.id] = CareEventEntity(sleep: sleep, babyName: name)
        }
        for diaper in (try? context.fetch(FetchDescriptor<DiaperEvent>(
            predicate: #Predicate { $0.deletedAt == nil && ids.contains($0.id) }))) ?? [] {
            byID[diaper.id] = CareEventEntity(diaper: diaper, babyName: name)
        }
        for note in (try? context.fetch(FetchDescriptor<NoteEvent>(
            predicate: #Predicate { $0.deletedAt == nil && ids.contains($0.id) }))) ?? [] {
            byID[note.id] = CareEventEntity(note: note, babyName: name)
        }
        return ids.compactMap { byID[$0] }
    }
}

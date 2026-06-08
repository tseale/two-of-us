import Foundation
import SwiftData
import WidgetKit

/// Anything that can be soft-deleted.
protocol SoftDeletable: AnyObject {
    var deletedAt: Date? { get set }
    var id: UUID { get }
}
extension FeedEvent: SoftDeletable {}
extension SleepEvent: SoftDeletable {}
extension DiaperEvent: SoftDeletable {}

/// Thin layer over `ModelContext` so views never hand-roll predicates.
/// Stamps every write with the local user's identity (denormalized) and hands
/// changed record ids to `SyncManager` for CloudKit. MainActor since it's only
/// used from SwiftUI views and talks to the MainActor `SyncManager`.
@MainActor
struct EventStore {
    let context: ModelContext

    // MARK: Lookups

    var baby: Baby? {
        try? context.fetch(FetchDescriptor<Baby>()).first
    }

    /// The local user ("me"). Resolved via `LocalPrefs.myParticipantID` once
    /// sharing introduces a second participant; falls back to the first record.
    var owner: Participant? {
        if let myID = LocalPrefs.shared.myParticipantID {
            var d = FetchDescriptor<Participant>(predicate: #Predicate { $0.id == myID })
            d.fetchLimit = 1
            if let me = try? context.fetch(d).first { return me }
        }
        return try? context.fetch(FetchDescriptor<Participant>()).first
    }

    var settings: SharedSettings? {
        try? context.fetch(FetchDescriptor<SharedSettings>()).first
    }

    var activeSleep: SleepEvent? {
        let descriptor = FetchDescriptor<SleepEvent>(
            predicate: #Predicate { $0.endedAt == nil && $0.deletedAt == nil }
        )
        return try? context.fetch(descriptor).first
    }

    // MARK: Logging

    @discardableResult
    func logFeed(amountOz: Double, at date: Date = .now) -> FeedEvent {
        let event = FeedEvent(
            baby: baby, amountOz: amountOz, timestamp: date,
            loggedByID: owner?.id ?? UUID(),
            loggedByName: owner?.displayName ?? "",
            loggedByColorHex: owner?.colorHex ?? ""
        )
        context.insert(event)
        save()
        sync(save: [event.id])
        reloadWidgets()
        return event
    }

    @discardableResult
    func logDiaper(_ type: DiaperType, at date: Date = .now) -> DiaperEvent {
        let event = DiaperEvent(
            baby: baby, type: type, timestamp: date,
            loggedByID: owner?.id ?? UUID(),
            loggedByName: owner?.displayName ?? "",
            loggedByColorHex: owner?.colorHex ?? ""
        )
        context.insert(event)
        save()
        sync(save: [event.id])
        reloadWidgets()
        return event
    }

    /// Starts a sleep timer. Refuses if one is already active (single-timer guard).
    @discardableResult
    func startSleep(at date: Date = .now) -> SleepEvent? {
        guard activeSleep == nil else { return nil }
        let event = SleepEvent(
            baby: baby, startedAt: date,
            loggedByID: owner?.id ?? UUID(),
            loggedByName: owner?.displayName ?? "",
            loggedByColorHex: owner?.colorHex ?? ""
        )
        context.insert(event)
        save()
        sync(save: [event.id])
        SleepActivityManager.start(babyName: baby?.name ?? "Miller", at: date)
        reloadWidgets()
        return event
    }

    func stopSleep(_ event: SleepEvent, at date: Date = .now) {
        event.endedAt = date
        save()
        sync(save: [event.id])
        SleepActivityManager.end()
        reloadWidgets()
    }

    // MARK: Edit (append-only: soft-delete original, insert replacement)

    @discardableResult
    func editFeed(_ original: FeedEvent, amountOz: Double, timestamp: Date) -> FeedEvent {
        let replacement = FeedEvent(
            baby: original.baby, amountOz: amountOz, timestamp: timestamp,
            notes: original.notes,
            loggedByID: original.loggedByID,
            loggedByName: original.loggedByName,
            loggedByColorHex: original.loggedByColorHex,
            editOfID: original.id
        )
        original.deletedAt = .now
        context.insert(replacement)
        save()
        sync(save: [original.id, replacement.id])
        reloadWidgets()
        return replacement
    }

    @discardableResult
    func editSleep(_ original: SleepEvent, startedAt: Date, endedAt: Date?) -> SleepEvent {
        let replacement = SleepEvent(
            baby: original.baby, startedAt: startedAt, endedAt: endedAt,
            notes: original.notes,
            loggedByID: original.loggedByID,
            loggedByName: original.loggedByName,
            loggedByColorHex: original.loggedByColorHex,
            editOfID: original.id
        )
        original.deletedAt = .now
        context.insert(replacement)
        save()
        sync(save: [original.id, replacement.id])
        reloadWidgets()
        return replacement
    }

    @discardableResult
    func editDiaper(_ original: DiaperEvent, type: DiaperType, timestamp: Date) -> DiaperEvent {
        let replacement = DiaperEvent(
            baby: original.baby, type: type, timestamp: timestamp,
            notes: original.notes,
            loggedByID: original.loggedByID,
            loggedByName: original.loggedByName,
            loggedByColorHex: original.loggedByColorHex,
            editOfID: original.id
        )
        original.deletedAt = .now
        context.insert(replacement)
        save()
        sync(save: [original.id, replacement.id])
        reloadWidgets()
        return replacement
    }

    // MARK: Delete / undo

    func softDelete(_ event: any SoftDeletable) {
        event.deletedAt = .now
        save()
        sync(save: [event.id])   // soft delete travels as a `deletedAt` update
        reloadWidgets()
    }

    // MARK: Time-since

    func lastEventDate(of kind: EventKind) -> Date? {
        switch kind {
        case .feed:
            var d = FetchDescriptor<FeedEvent>(
                predicate: #Predicate { $0.deletedAt == nil },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            d.fetchLimit = 1
            return (try? context.fetch(d))?.first?.timestamp
        case .sleep:
            var d = FetchDescriptor<SleepEvent>(
                predicate: #Predicate { $0.deletedAt == nil },
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
            d.fetchLimit = 1
            // Use endedAt if available, else startedAt (in-progress shows as the active card)
            if let e = (try? context.fetch(d))?.first { return e.endedAt ?? e.startedAt }
            return nil
        case .diaper:
            var d = FetchDescriptor<DiaperEvent>(
                predicate: #Predicate { $0.deletedAt == nil },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            d.fetchLimit = 1
            return (try? context.fetch(d))?.first?.timestamp
        }
    }

    // MARK: Timeline

    /// Live events within the rolling window, newest first.
    func timeline(since: Date) -> [TimelineEntry] {
        var entries: [TimelineEntry] = []

        let feeds = (try? context.fetch(FetchDescriptor<FeedEvent>(
            predicate: #Predicate { $0.deletedAt == nil && $0.timestamp >= since }
        ))) ?? []
        entries += feeds.map(TimelineEntry.feed)

        // Sleeps: include if started within the window OR still active.
        let sleeps = (try? context.fetch(FetchDescriptor<SleepEvent>(
            predicate: #Predicate { $0.deletedAt == nil && $0.startedAt >= since }
        ))) ?? []
        entries += sleeps.filter { !$0.isActive }.map(TimelineEntry.sleep)

        let diapers = (try? context.fetch(FetchDescriptor<DiaperEvent>(
            predicate: #Predicate { $0.deletedAt == nil && $0.timestamp >= since }
        ))) ?? []
        entries += diapers.map(TimelineEntry.diaper)

        return entries.sorted { $0.sortDate > $1.sortDate }
    }

    // MARK: Private

    private func save() {
        do { try context.save() } catch { print("EventStore save error: \(error)") }
    }

    /// Hands changed record ids to the sync engine (no-op when sync is inactive).
    private func sync(save: [UUID] = [], delete: [UUID] = []) {
        SyncManager.shared?.enqueueSave(save)
        SyncManager.shared?.enqueueDelete(delete)
    }

    private func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}

import Foundation
import SwiftData
import CloudKit

/// Translates between SwiftData `@Model` objects and CloudKit `CKRecord`s.
///
/// Records are keyed by each model's own `id: UUID` (stable across the owner and
/// the share participant, whose zone IDs differ). Relationships are stored as
/// UUID strings and resolved locally — no `CKReference`, so there's no
/// cross-zone ordering/integrity problem.
enum RecordMapping {

    // MARK: Outbound (local model → CKRecord)

    /// Builds the CKRecord to upload for a given record id, searching every model
    /// type. Returns nil if no live local model has that id (nothing to send).
    static func record(forRecordName name: String, recordID: CKRecord.ID, in context: ModelContext) -> CKRecord? {
        guard let uuid = UUID(uuidString: name) else { return nil }

        if let m = fetchOne(FeedEvent.self, id: uuid, in: context) {
            let r = CKRecord(recordType: SyncConstants.RecordType.feed, recordID: recordID)
            r["amountOz"] = m.amountOz
            r["timestamp"] = m.timestamp
            r["notes"] = m.notes
            setCommon(r, loggedByID: m.loggedByID, name: m.loggedByName, color: m.loggedByColorHex,
                      deletedAt: m.deletedAt, editOfID: m.editOfID, babyID: m.baby?.id)
            return r
        }
        if let m = fetchOne(SleepEvent.self, id: uuid, in: context) {
            let r = CKRecord(recordType: SyncConstants.RecordType.sleep, recordID: recordID)
            r["startedAt"] = m.startedAt
            r["endedAt"] = m.endedAt
            r["notes"] = m.notes
            setCommon(r, loggedByID: m.loggedByID, name: m.loggedByName, color: m.loggedByColorHex,
                      deletedAt: m.deletedAt, editOfID: m.editOfID, babyID: m.baby?.id)
            return r
        }
        if let m = fetchOne(DiaperEvent.self, id: uuid, in: context) {
            let r = CKRecord(recordType: SyncConstants.RecordType.diaper, recordID: recordID)
            r["typeRaw"] = m.typeRaw
            r["timestamp"] = m.timestamp
            r["notes"] = m.notes
            setCommon(r, loggedByID: m.loggedByID, name: m.loggedByName, color: m.loggedByColorHex,
                      deletedAt: m.deletedAt, editOfID: m.editOfID, babyID: m.baby?.id)
            return r
        }
        if let m = fetchOne(Baby.self, id: uuid, in: context) {
            let r = CKRecord(recordType: SyncConstants.RecordType.baby, recordID: recordID)
            r["name"] = m.name
            r["dateOfBirth"] = m.dateOfBirth
            r["createdAt"] = m.createdAt
            r["photoData"] = asset(from: m.photoData)
            return r
        }
        if let m = fetchOne(Participant.self, id: uuid, in: context) {
            let r = CKRecord(recordType: SyncConstants.RecordType.participant, recordID: recordID)
            r["displayName"] = m.displayName
            r["colorHex"] = m.colorHex
            r["roleRaw"] = m.roleRaw
            r["cloudUserID"] = m.cloudUserID
            r["isActive"] = m.isActive ? 1 : 0
            r["invitedAt"] = m.invitedAt
            r["photoData"] = asset(from: m.photoData)
            return r
        }
        if let m = fetchOne(SharedSettings.self, id: uuid, in: context) {
            let r = CKRecord(recordType: SyncConstants.RecordType.settings, recordID: recordID)
            r["targetFeedIntervalMinutes"] = m.targetFeedIntervalMinutes
            r["ozPresets"] = m.ozPresets
            r["defaultFeedOz"] = m.defaultFeedOz
            return r
        }
        return nil
    }

    private static func setCommon(_ r: CKRecord, loggedByID: UUID, name: String, color: String,
                                  deletedAt: Date?, editOfID: UUID?, babyID: UUID?) {
        r["loggedByID"] = loggedByID.uuidString
        r["loggedByName"] = name
        r["loggedByColorHex"] = color
        r["deletedAt"] = deletedAt
        r["editOfID"] = editOfID?.uuidString
        r["babyID"] = babyID?.uuidString
    }

    // MARK: Inbound (CKRecord → local model, upsert by id)

    static func apply(_ record: CKRecord, in context: ModelContext) {
        guard let uuid = UUID(uuidString: record.recordID.recordName) else { return }
        switch record.recordType {
        case SyncConstants.RecordType.feed:    applyFeed(record, uuid: uuid, in: context)
        case SyncConstants.RecordType.sleep:   applySleep(record, uuid: uuid, in: context)
        case SyncConstants.RecordType.diaper:  applyDiaper(record, uuid: uuid, in: context)
        case SyncConstants.RecordType.baby:    applyBaby(record, uuid: uuid, in: context)
        case SyncConstants.RecordType.participant: applyParticipant(record, uuid: uuid, in: context)
        case SyncConstants.RecordType.settings: applySettings(record, uuid: uuid, in: context)
        default: break
        }
    }

    /// Hard-deletes the local model with this record name (used for true CloudKit
    /// deletions; routine removals travel as `deletedAt` updates).
    static func delete(recordName: String, in context: ModelContext) {
        guard let uuid = UUID(uuidString: recordName) else { return }
        if let m = fetchOne(FeedEvent.self, id: uuid, in: context) { context.delete(m); return }
        if let m = fetchOne(SleepEvent.self, id: uuid, in: context) { context.delete(m); return }
        if let m = fetchOne(DiaperEvent.self, id: uuid, in: context) { context.delete(m); return }
        if let m = fetchOne(Participant.self, id: uuid, in: context) { context.delete(m); return }
        if let m = fetchOne(Baby.self, id: uuid, in: context) { context.delete(m); return }
        if let m = fetchOne(SharedSettings.self, id: uuid, in: context) { context.delete(m); return }
    }

    // MARK: Inbound per-type

    private static func applyFeed(_ r: CKRecord, uuid: UUID, in context: ModelContext) {
        let m = fetchOne(FeedEvent.self, id: uuid, in: context)
            ?? insert(FeedEvent(baby: nil, amountOz: 0, timestamp: .now,
                                loggedByID: UUID(), loggedByName: "", loggedByColorHex: ""), id: uuid, in: context)
        m.amountOz = r["amountOz"] as? Double ?? m.amountOz
        m.timestamp = r["timestamp"] as? Date ?? m.timestamp
        m.notes = r["notes"] as? String
        applyCommon(r, into: m, in: context)
    }

    private static func applySleep(_ r: CKRecord, uuid: UUID, in context: ModelContext) {
        let m = fetchOne(SleepEvent.self, id: uuid, in: context)
            ?? insert(SleepEvent(baby: nil, startedAt: .now,
                                 loggedByID: UUID(), loggedByName: "", loggedByColorHex: ""), id: uuid, in: context)
        m.startedAt = r["startedAt"] as? Date ?? m.startedAt
        m.endedAt = r["endedAt"] as? Date
        m.notes = r["notes"] as? String
        applyCommon(r, into: m, in: context)
    }

    private static func applyDiaper(_ r: CKRecord, uuid: UUID, in context: ModelContext) {
        let m = fetchOne(DiaperEvent.self, id: uuid, in: context)
            ?? insert(DiaperEvent(baby: nil, type: .wet, timestamp: .now,
                                  loggedByID: UUID(), loggedByName: "", loggedByColorHex: ""), id: uuid, in: context)
        m.typeRaw = r["typeRaw"] as? String ?? m.typeRaw
        m.timestamp = r["timestamp"] as? Date ?? m.timestamp
        m.notes = r["notes"] as? String
        applyCommon(r, into: m, in: context)
    }

    private static func applyBaby(_ r: CKRecord, uuid: UUID, in context: ModelContext) {
        let m = fetchOne(Baby.self, id: uuid, in: context)
            ?? insert(Baby(name: "", dateOfBirth: .now), id: uuid, in: context)
        m.name = r["name"] as? String ?? m.name
        m.dateOfBirth = r["dateOfBirth"] as? Date ?? m.dateOfBirth
        m.createdAt = r["createdAt"] as? Date ?? m.createdAt
        m.photoData = data(from: r["photoData"])
    }

    private static func applyParticipant(_ r: CKRecord, uuid: UUID, in context: ModelContext) {
        let m = fetchOne(Participant.self, id: uuid, in: context)
            ?? insert(Participant(displayName: "", colorHex: ""), id: uuid, in: context)
        m.displayName = r["displayName"] as? String ?? m.displayName
        m.colorHex = r["colorHex"] as? String ?? m.colorHex
        m.roleRaw = r["roleRaw"] as? String ?? m.roleRaw
        m.cloudUserID = r["cloudUserID"] as? String
        m.isActive = (r["isActive"] as? Int ?? 1) != 0
        m.invitedAt = r["invitedAt"] as? Date ?? m.invitedAt
        m.photoData = data(from: r["photoData"])
    }

    private static func applySettings(_ r: CKRecord, uuid: UUID, in context: ModelContext) {
        let m = fetchOne(SharedSettings.self, id: uuid, in: context)
            ?? insert(SharedSettings(), id: uuid, in: context)
        m.targetFeedIntervalMinutes = r["targetFeedIntervalMinutes"] as? Int ?? m.targetFeedIntervalMinutes
        m.ozPresets = r["ozPresets"] as? [Double] ?? m.ozPresets
        m.defaultFeedOz = r["defaultFeedOz"] as? Double ?? m.defaultFeedOz
    }

    /// Shared event fields: logger identity, soft-delete, edit pointer, baby link.
    private static func applyCommon(_ r: CKRecord, into m: AnyEventModel, in context: ModelContext) {
        if let s = r["loggedByID"] as? String, let id = UUID(uuidString: s) { m.loggedByID = id }
        m.loggedByName = r["loggedByName"] as? String ?? m.loggedByName
        m.loggedByColorHex = r["loggedByColorHex"] as? String ?? m.loggedByColorHex
        m.deletedAt = r["deletedAt"] as? Date
        if let s = r["editOfID"] as? String { m.editOfID = UUID(uuidString: s) } else { m.editOfID = nil }
        if let s = r["babyID"] as? String, let bid = UUID(uuidString: s) {
            m.babyRef = fetchOne(Baby.self, id: bid, in: context)
        }
    }

    // MARK: Helpers

    /// Wraps avatar bytes in a CKAsset (CloudKit can't store `Data` as a scalar).
    /// Writes to a temp file CloudKit reads on upload; returns nil when there's no
    /// photo, which clears the field on the record.
    private static func asset(from photoData: Data?) -> CKAsset? {
        guard let photoData else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        guard (try? photoData.write(to: url)) != nil else { return nil }
        return CKAsset(fileURL: url)
    }

    /// Reads avatar bytes back from a CKAsset field. Returns nil when the field is
    /// absent or the asset file can't be read (so a missing photo clears locally).
    private static func data(from value: Any?) -> Data? {
        guard let asset = value as? CKAsset, let url = asset.fileURL else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func fetchOne<T: PersistentModel & HasSyncID>(_ type: T.Type, id: UUID, in context: ModelContext) -> T? {
        // In-memory filter avoids #Predicate key-path issues on the shared `id`
        // and is cheap at this app's scale (only runs while applying sync changes).
        let all = (try? context.fetch(FetchDescriptor<T>())) ?? []
        return all.first { $0.id == id }
    }

    @discardableResult
    private static func insert<T: PersistentModel & HasSyncID>(_ model: T, id: UUID, in context: ModelContext) -> T {
        model.id = id
        context.insert(model)
        return model
    }
}

/// Lets RecordMapping set the id on a freshly-inserted synced model.
protocol HasSyncID: AnyObject { var id: UUID { get set } }
extension Baby: HasSyncID {}
extension FeedEvent: HasSyncID {}
extension SleepEvent: HasSyncID {}
extension DiaperEvent: HasSyncID {}
extension Participant: HasSyncID {}
extension SharedSettings: HasSyncID {}

/// Common event surface so `applyCommon` can write to any event type.
protocol AnyEventModel: AnyObject {
    var loggedByID: UUID { get set }
    var loggedByName: String { get set }
    var loggedByColorHex: String { get set }
    var deletedAt: Date? { get set }
    var editOfID: UUID? { get set }
    var babyRef: Baby? { get set }
}
extension FeedEvent: AnyEventModel {
    var babyRef: Baby? { get { baby } set { baby = newValue } }
}
extension SleepEvent: AnyEventModel {
    var babyRef: Baby? { get { baby } set { baby = newValue } }
}
extension DiaperEvent: AnyEventModel {
    var babyRef: Baby? { get { baby } set { baby = newValue } }
}

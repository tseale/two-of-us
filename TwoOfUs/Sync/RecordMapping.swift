import Foundation
import SwiftData
import CloudKit

/// Translates between SwiftData `@Model` objects and CloudKit `CKRecord`s.
///
/// Records are keyed by each model's own `id: UUID` (stable across the owner and
/// the share participant, whose zone IDs differ). Relationships are stored as
/// UUID strings and resolved locally — no `CKReference`, so there's no
/// cross-zone ordering/integrity problem.
///
/// Every synced model carries `ckSystemFields` — the archived system fields of
/// the record's last known server copy. Outbound records MUST be rebuilt on top
/// of that archive: CloudKit saves with if-server-record-unchanged semantics, so
/// an update sent without the server's change tag is rejected as a conflict
/// (`serverRecordChanged`) every single time. Creates are the only saves that
/// succeed from a fresh `CKRecord`.
enum RecordMapping {

    // MARK: Outbound (local model → CKRecord)

    /// Builds the CKRecord to upload for a given record id, searching every model
    /// type. Returns nil if no live local model has that id (nothing to send).
    static func record(forRecordName name: String, recordID: CKRecord.ID, in context: ModelContext) -> CKRecord? {
        guard let uuid = UUID(uuidString: name) else { return nil }

        if let m = FeedEvent.fetchByID(uuid, in: context) {
            let r = baseRecord(type: SyncConstants.RecordType.feed, recordID: recordID, archived: m.ckSystemFields)
            r["amountOz"] = m.amountOz
            r["timestamp"] = m.timestamp
            r["notes"] = m.notes
            setCommon(r, loggedByID: m.loggedByID, name: m.loggedByName, color: m.loggedByColorHex,
                      deletedAt: m.deletedAt, editOfID: m.editOfID, babyID: m.baby?.id)
            return r
        }
        if let m = SleepEvent.fetchByID(uuid, in: context) {
            let r = baseRecord(type: SyncConstants.RecordType.sleep, recordID: recordID, archived: m.ckSystemFields)
            r["startedAt"] = m.startedAt
            r["endedAt"] = m.endedAt
            r["notes"] = m.notes
            setCommon(r, loggedByID: m.loggedByID, name: m.loggedByName, color: m.loggedByColorHex,
                      deletedAt: m.deletedAt, editOfID: m.editOfID, babyID: m.baby?.id)
            return r
        }
        if let m = DiaperEvent.fetchByID(uuid, in: context) {
            let r = baseRecord(type: SyncConstants.RecordType.diaper, recordID: recordID, archived: m.ckSystemFields)
            r["typeRaw"] = m.typeRaw
            r["timestamp"] = m.timestamp
            r["notes"] = m.notes
            setCommon(r, loggedByID: m.loggedByID, name: m.loggedByName, color: m.loggedByColorHex,
                      deletedAt: m.deletedAt, editOfID: m.editOfID, babyID: m.baby?.id)
            return r
        }
        if let m = Baby.fetchByID(uuid, in: context) {
            let r = baseRecord(type: SyncConstants.RecordType.baby, recordID: recordID, archived: m.ckSystemFields)
            r["name"] = m.name
            r["dateOfBirth"] = m.dateOfBirth
            r["createdAt"] = m.createdAt
            r["photoData"] = asset(from: m.photoData)
            return r
        }
        if let m = Participant.fetchByID(uuid, in: context) {
            let r = baseRecord(type: SyncConstants.RecordType.participant, recordID: recordID, archived: m.ckSystemFields)
            r["displayName"] = m.displayName
            r["colorHex"] = m.colorHex
            r["roleRaw"] = m.roleRaw
            r["cloudUserID"] = m.cloudUserID
            r["isActive"] = m.isActive ? 1 : 0
            r["invitedAt"] = m.invitedAt
            r["photoData"] = asset(from: m.photoData)
            return r
        }
        if let m = SharedSettings.fetchByID(uuid, in: context) {
            let r = baseRecord(type: SyncConstants.RecordType.settings, recordID: recordID, archived: m.ckSystemFields)
            r["targetFeedIntervalMinutes"] = m.targetFeedIntervalMinutes
            r["ozPresets"] = m.ozPresets
            r["defaultFeedOz"] = m.defaultFeedOz
            return r
        }
        return nil
    }

    /// Existence check that PROPAGATES store errors, unlike `record(forRecordName:)`
    /// whose nil means both "model deleted" and "fetch failed". Callers that drop
    /// queued sync work on nil (`SyncManager.nextRecordZoneChangeBatch`) need to
    /// tell the two apart, or a transient fetch error silently loses the record.
    static func modelExists(recordName: String, in context: ModelContext) throws -> Bool {
        guard let uuid = UUID(uuidString: recordName) else { return false }
        var feed = FetchDescriptor<FeedEvent>(predicate: #Predicate { $0.id == uuid })
        feed.fetchLimit = 1
        if try context.fetchCount(feed) > 0 { return true }
        var sleep = FetchDescriptor<SleepEvent>(predicate: #Predicate { $0.id == uuid })
        sleep.fetchLimit = 1
        if try context.fetchCount(sleep) > 0 { return true }
        var diaper = FetchDescriptor<DiaperEvent>(predicate: #Predicate { $0.id == uuid })
        diaper.fetchLimit = 1
        if try context.fetchCount(diaper) > 0 { return true }
        var baby = FetchDescriptor<Baby>(predicate: #Predicate { $0.id == uuid })
        baby.fetchLimit = 1
        if try context.fetchCount(baby) > 0 { return true }
        var participant = FetchDescriptor<Participant>(predicate: #Predicate { $0.id == uuid })
        participant.fetchLimit = 1
        if try context.fetchCount(participant) > 0 { return true }
        var settings = FetchDescriptor<SharedSettings>(predicate: #Predicate { $0.id == uuid })
        settings.fetchLimit = 1
        return try context.fetchCount(settings) > 0
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

    // MARK: System fields (the server change tag)

    /// The base record to populate for an outbound save: the archived last-known
    /// server copy when it matches the requested identity, else a fresh record.
    /// The identity check matters after role transitions — e.g. a participant who
    /// left a share and now syncs the same models into their OWN private zone must
    /// not upload records stamped with the old owner's zone.
    static func baseRecord(type: String, recordID: CKRecord.ID, archived: Data?) -> CKRecord {
        if let archived, let decoded = decodeSystemFieldsRecord(archived),
           decoded.recordID == recordID, decoded.recordType == type {
            return decoded
        }
        return CKRecord(recordType: type, recordID: recordID)
    }

    static func archivedSystemFields(of record: CKRecord) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        return archiver.encodedData
    }

    static func decodeSystemFieldsRecord(_ data: Data) -> CKRecord? {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = true
        return CKRecord(coder: unarchiver)
    }

    /// Stores `record`'s system fields onto its local model so the next outbound
    /// save carries the server's current change tag. Guarded "if newer": an
    /// out-of-order older server copy must not clobber a fresher cached tag.
    static func persistSystemFields(of record: CKRecord, in context: ModelContext) {
        guard let uuid = UUID(uuidString: record.recordID.recordName),
              let model = model(ofType: record.recordType, id: uuid, in: context) else { return }
        if let existing = model.ckSystemFields,
           let cachedDate = decodeSystemFieldsRecord(existing)?.modificationDate,
           let newDate = record.modificationDate,
           cachedDate > newDate {
            return
        }
        model.ckSystemFields = archivedSystemFields(of: record)
    }

    /// Drops the cached change tag for one record (server no longer knows it —
    /// the next save must go out as a fresh create).
    static func clearSystemFields(forRecordName name: String, in context: ModelContext) {
        guard let uuid = UUID(uuidString: name) else { return }
        anyModel(id: uuid, in: context)?.ckSystemFields = nil
    }

    /// Drops every cached change tag (the zone was deleted/recreated server-side,
    /// so all cached tags are stale and everything re-uploads as creates).
    static func clearAllSystemFields(in context: ModelContext) {
        func clear<T: PersistentModel & HasSyncID>(_ type: T.Type) {
            for m in (try? context.fetch(FetchDescriptor<T>())) ?? [] { m.ckSystemFields = nil }
        }
        clear(FeedEvent.self); clear(SleepEvent.self); clear(DiaperEvent.self)
        clear(Baby.self); clear(Participant.self); clear(SharedSettings.self)
    }

    // MARK: Conflict resolution

    /// Merge policy when our save lost a race with the server: adopt the server's
    /// change tag (so the re-save succeeds), keep the local model's content (it's
    /// about to be re-uploaded) — EXCEPT terminal fields the other parent may have
    /// set concurrently: a soft-delete or a sleep-stop must never be resurrected
    /// by the race loser re-saving. Returns false when no local model exists
    /// anymore (caller should fall back to applying the server copy).
    @discardableResult
    static func absorbConflict(server: CKRecord, in context: ModelContext) -> Bool {
        guard let uuid = UUID(uuidString: server.recordID.recordName),
              let model = model(ofType: server.recordType, id: uuid, in: context) else {
            apply(server, in: context)
            return false
        }
        if let event = model as? AnyEventModel, event.deletedAt == nil,
           let serverDeleted = server["deletedAt"] as? Date {
            event.deletedAt = serverDeleted
        }
        if let sleep = model as? SleepEvent, sleep.endedAt == nil,
           let serverEnded = server["endedAt"] as? Date {
            sleep.endedAt = serverEnded
        }
        model.ckSystemFields = archivedSystemFields(of: server)
        return true
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
        if let m = FeedEvent.fetchByID(uuid, in: context) { context.delete(m); return }
        if let m = SleepEvent.fetchByID(uuid, in: context) { context.delete(m); return }
        if let m = DiaperEvent.fetchByID(uuid, in: context) { context.delete(m); return }
        if let m = Participant.fetchByID(uuid, in: context) { context.delete(m); return }
        if let m = Baby.fetchByID(uuid, in: context) { context.delete(m); return }
        if let m = SharedSettings.fetchByID(uuid, in: context) { context.delete(m); return }
    }

    /// Attaches the baby to any events that synced in before the Baby record
    /// landed locally (fetch batches carry no ordering guarantee, and `apply`
    /// resolves the relationship only at apply time). Single-baby by design.
    static func relinkOrphanEvents(in context: ModelContext) {
        guard let baby = (try? context.fetch(FetchDescriptor<Baby>()))?.first else { return }
        for e in (try? context.fetch(FetchDescriptor<FeedEvent>(
            predicate: #Predicate { $0.baby == nil }))) ?? [] { e.baby = baby }
        for e in (try? context.fetch(FetchDescriptor<SleepEvent>(
            predicate: #Predicate { $0.baby == nil }))) ?? [] { e.baby = baby }
        for e in (try? context.fetch(FetchDescriptor<DiaperEvent>(
            predicate: #Predicate { $0.baby == nil }))) ?? [] { e.baby = baby }
    }

    // MARK: Inbound per-type

    private static func applyFeed(_ r: CKRecord, uuid: UUID, in context: ModelContext) {
        let m = FeedEvent.fetchByID(uuid, in: context)
            ?? insert(FeedEvent(baby: nil, amountOz: 0, timestamp: .now,
                                loggedByID: UUID(), loggedByName: "", loggedByColorHex: ""), id: uuid, in: context)
        m.amountOz = r["amountOz"] as? Double ?? m.amountOz
        m.timestamp = r["timestamp"] as? Date ?? m.timestamp
        m.notes = r["notes"] as? String
        applyCommon(r, into: m, in: context)
    }

    private static func applySleep(_ r: CKRecord, uuid: UUID, in context: ModelContext) {
        let m = SleepEvent.fetchByID(uuid, in: context)
            ?? insert(SleepEvent(baby: nil, startedAt: .now,
                                 loggedByID: UUID(), loggedByName: "", loggedByColorHex: ""), id: uuid, in: context)
        m.startedAt = r["startedAt"] as? Date ?? m.startedAt
        m.endedAt = r["endedAt"] as? Date
        m.notes = r["notes"] as? String
        applyCommon(r, into: m, in: context)
    }

    private static func applyDiaper(_ r: CKRecord, uuid: UUID, in context: ModelContext) {
        let m = DiaperEvent.fetchByID(uuid, in: context)
            ?? insert(DiaperEvent(baby: nil, type: .wet, timestamp: .now,
                                  loggedByID: UUID(), loggedByName: "", loggedByColorHex: ""), id: uuid, in: context)
        m.typeRaw = r["typeRaw"] as? String ?? m.typeRaw
        m.timestamp = r["timestamp"] as? Date ?? m.timestamp
        m.notes = r["notes"] as? String
        applyCommon(r, into: m, in: context)
    }

    private static func applyBaby(_ r: CKRecord, uuid: UUID, in context: ModelContext) {
        let existing = Baby.fetchByID(uuid, in: context)
        let existed = existing != nil
        let m = existing
            ?? insert(Baby(name: "", dateOfBirth: .now), id: uuid, in: context)
        m.name = r["name"] as? String ?? m.name
        m.dateOfBirth = r["dateOfBirth"] as? Date ?? m.dateOfBirth
        m.createdAt = r["createdAt"] as? Date ?? m.createdAt
        if let resolved = inboundPhoto(r["photoData"]) { m.photoData = resolved }
        // Events can sync in before their Baby. The fetch-batch handler relinks
        // too, but an interrupted fetch could leave events stranded forever — so
        // relink the moment a Baby first appears here as well.
        if !existed { relinkOrphanEvents(in: context) }
    }

    private static func applyParticipant(_ r: CKRecord, uuid: UUID, in context: ModelContext) {
        let m = Participant.fetchByID(uuid, in: context)
            ?? insert(Participant(displayName: "", colorHex: ""), id: uuid, in: context)
        m.displayName = r["displayName"] as? String ?? m.displayName
        m.colorHex = r["colorHex"] as? String ?? m.colorHex
        m.roleRaw = r["roleRaw"] as? String ?? m.roleRaw
        m.cloudUserID = r["cloudUserID"] as? String
        m.isActive = (r["isActive"] as? Int ?? 1) != 0
        m.invitedAt = r["invitedAt"] as? Date ?? m.invitedAt
        if let resolved = inboundPhoto(r["photoData"]) { m.photoData = resolved }
    }

    private static func applySettings(_ r: CKRecord, uuid: UUID, in context: ModelContext) {
        let m = SharedSettings.fetchByID(uuid, in: context)
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
        if let s = r["babyID"] as? String {
            if let bid = UUID(uuidString: s) {
                m.babyRef = Baby.fetchByID(bid, in: context)
            } else {
                // A malformed babyID would silently orphan the event from its baby;
                // log the offending string so QA can trace a broken relationship.
                AppLog.sync.error("Dropped event→baby link: unparseable babyID \"\(s, privacy: .public)\"")
            }
        }
    }

    // MARK: Helpers

    /// Dedicated scratch dir for outbound CKAsset temp files, so they can be
    /// swept as a group (CloudKit gives no "done reading" callback, and a save
    /// that fails before upload otherwise leaks the file forever).
    private static var assetOutbox: URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ckAssetOutbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Wraps avatar bytes in a CKAsset (CloudKit can't store `Data` as a scalar).
    /// Writes to a temp file CloudKit reads on upload; returns nil when there's no
    /// photo, which clears the field on the record.
    private static func asset(from photoData: Data?) -> CKAsset? {
        guard let photoData else { return nil }
        let url = assetOutbox.appendingPathComponent(UUID().uuidString)
        guard (try? photoData.write(to: url)) != nil else { return nil }
        return CKAsset(fileURL: url)
    }

    /// Sweeps outbound asset temp files older than an hour — long past any upload
    /// CloudKit would still be reading. Safe to call on launch.
    static func cleanUpStaleAssetFiles(olderThan age: TimeInterval = 3600) {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-age)
        guard let files = try? fm.contentsOfDirectory(
            at: assetOutbox, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        for url in files {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff { try? fm.removeItem(at: url) }
        }
    }

    /// Resolves an inbound avatar field into an *action*, so a transient unreadable
    /// asset can't wipe a good local photo:
    /// - `.some(data)` — a readable photo (set it locally)
    /// - `.some(nil)`  — the field is genuinely absent (the photo was cleared upstream)
    /// - `nil`         — a present-but-unreadable `CKAsset` (transient; keep the local copy)
    private static func inboundPhoto(_ value: Any?) -> Data?? {
        guard let asset = value as? CKAsset else { return .some(nil) }     // no asset → cleared
        guard let url = asset.fileURL, let bytes = try? Data(contentsOf: url) else {
            return nil                                                     // present but unreadable → keep local
        }
        return .some(bytes)
    }

    /// Resolves the local model for a CKRecord type + id (the type avoids probing
    /// every table when the record tells us where to look).
    private static func model(ofType recordType: String, id: UUID, in context: ModelContext) -> (any HasSyncID)? {
        switch recordType {
        case SyncConstants.RecordType.feed:        FeedEvent.fetchByID(id, in: context)
        case SyncConstants.RecordType.sleep:       SleepEvent.fetchByID(id, in: context)
        case SyncConstants.RecordType.diaper:      DiaperEvent.fetchByID(id, in: context)
        case SyncConstants.RecordType.baby:        Baby.fetchByID(id, in: context)
        case SyncConstants.RecordType.participant: Participant.fetchByID(id, in: context)
        case SyncConstants.RecordType.settings:    SharedSettings.fetchByID(id, in: context)
        default: nil
        }
    }

    /// Probes every model type for an id (used when only the id is known).
    private static func anyModel(id: UUID, in context: ModelContext) -> (any HasSyncID)? {
        FeedEvent.fetchByID(id, in: context)
            ?? SleepEvent.fetchByID(id, in: context)
            ?? DiaperEvent.fetchByID(id, in: context)
            ?? Participant.fetchByID(id, in: context) as (any HasSyncID)?
            ?? Baby.fetchByID(id, in: context)
            ?? SharedSettings.fetchByID(id, in: context)
    }

    @discardableResult
    private static func insert<T: PersistentModel & HasSyncID>(_ model: T, id: UUID, in context: ModelContext) -> T {
        model.id = id
        context.insert(model)
        return model
    }
}

/// Lets RecordMapping set the id and cached server system fields on synced models.
protocol HasSyncID: AnyObject {
    var id: UUID { get set }
    var ckSystemFields: Data? { get set }
    static func fetchByID(_ id: UUID, in context: ModelContext) -> Self?
}

// Each conformance hand-rolls the predicate fetch: #Predicate needs the concrete
// type (a protocol-generic key path won't compile), and an indexed fetchLimit-1
// lookup replaces the old load-the-whole-table scan.
extension Baby: HasSyncID {
    static func fetchByID(_ id: UUID, in context: ModelContext) -> Baby? {
        var d = FetchDescriptor<Baby>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }
}
extension FeedEvent: HasSyncID {
    static func fetchByID(_ id: UUID, in context: ModelContext) -> FeedEvent? {
        var d = FetchDescriptor<FeedEvent>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }
}
extension SleepEvent: HasSyncID {
    static func fetchByID(_ id: UUID, in context: ModelContext) -> SleepEvent? {
        var d = FetchDescriptor<SleepEvent>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }
}
extension DiaperEvent: HasSyncID {
    static func fetchByID(_ id: UUID, in context: ModelContext) -> DiaperEvent? {
        var d = FetchDescriptor<DiaperEvent>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }
}
extension Participant: HasSyncID {
    static func fetchByID(_ id: UUID, in context: ModelContext) -> Participant? {
        var d = FetchDescriptor<Participant>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }
}
extension SharedSettings: HasSyncID {
    static func fetchByID(_ id: UUID, in context: ModelContext) -> SharedSettings? {
        var d = FetchDescriptor<SharedSettings>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }
}

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

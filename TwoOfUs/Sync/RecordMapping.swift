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
            r["sourceRaw"] = m.sourceRaw
            r["externalID"] = m.externalID
            setCommon(r, loggedByID: m.loggedByID, name: m.loggedByName, color: m.loggedByColorHex,
                      deletedAt: m.deletedAt, editOfID: m.editOfID, babyID: m.baby?.id)
            return r
        }
        if let m = SleepEvent.fetchByID(uuid, in: context) {
            let r = baseRecord(type: SyncConstants.RecordType.sleep, recordID: recordID, archived: m.ckSystemFields)
            r["startedAt"] = m.startedAt
            r["endedAt"] = m.endedAt
            r["notes"] = m.notes
            r["sourceRaw"] = m.sourceRaw
            r["externalID"] = m.externalID
            setCommon(r, loggedByID: m.loggedByID, name: m.loggedByName, color: m.loggedByColorHex,
                      deletedAt: m.deletedAt, editOfID: m.editOfID, babyID: m.baby?.id)
            return r
        }
        if let m = DiaperEvent.fetchByID(uuid, in: context) {
            let r = baseRecord(type: SyncConstants.RecordType.diaper, recordID: recordID, archived: m.ckSystemFields)
            r["typeRaw"] = m.typeRaw
            r["timestamp"] = m.timestamp
            r["notes"] = m.notes
            r["sourceRaw"] = m.sourceRaw
            r["externalID"] = m.externalID
            setCommon(r, loggedByID: m.loggedByID, name: m.loggedByName, color: m.loggedByColorHex,
                      deletedAt: m.deletedAt, editOfID: m.editOfID, babyID: m.baby?.id)
            return r
        }
        if let m = NoteEvent.fetchByID(uuid, in: context) {
            let r = baseRecord(type: SyncConstants.RecordType.note, recordID: recordID, archived: m.ckSystemFields)
            r["text"] = m.text
            r["timestamp"] = m.timestamp
            r["sourceRaw"] = m.sourceRaw
            r["externalID"] = m.externalID
            setCommon(r, loggedByID: m.loggedByID, name: m.loggedByName, color: m.loggedByColorHex,
                      deletedAt: m.deletedAt, editOfID: m.editOfID, babyID: m.baby?.id)
            return r
        }
        if let m = ActivityEvent.fetchByID(uuid, in: context) {
            let r = baseRecord(type: SyncConstants.RecordType.activity, recordID: recordID, archived: m.ckSystemFields)
            r["typeRaw"] = m.typeRaw
            r["timestamp"] = m.timestamp
            r["durationMinutes"] = m.durationMinutes
            r["notes"] = m.notes
            r["sourceRaw"] = m.sourceRaw
            r["externalID"] = m.externalID
            setCommon(r, loggedByID: m.loggedByID, name: m.loggedByName, color: m.loggedByColorHex,
                      deletedAt: m.deletedAt, editOfID: m.editOfID, babyID: m.baby?.id)
            return r
        }
        if let m = MediaEvent.fetchByID(uuid, in: context) {
            let r = baseRecord(type: SyncConstants.RecordType.media, recordID: recordID, archived: m.ckSystemFields)
            r["kindRaw"] = m.kindRaw
            r["timestamp"] = m.timestamp
            r["caption"] = m.caption
            r["remoteURL"] = m.remoteURL
            r["mediaData"] = asset(from: m.mediaData)
            r["sourceRaw"] = m.sourceRaw
            r["externalID"] = m.externalID
            setCommon(r, loggedByID: m.loggedByID, name: m.loggedByName, color: m.loggedByColorHex,
                      deletedAt: m.deletedAt, editOfID: m.editOfID, babyID: m.baby?.id)
            return r
        }
        if let m = CheckEvent.fetchByID(uuid, in: context) {
            let r = baseRecord(type: SyncConstants.RecordType.check, recordID: recordID, archived: m.ckSystemFields)
            r["typeRaw"] = m.typeRaw
            r["timestamp"] = m.timestamp
            r["byName"] = m.byName
            r["notes"] = m.notes
            r["sourceRaw"] = m.sourceRaw
            r["externalID"] = m.externalID
            setCommon(r, loggedByID: m.loggedByID, name: m.loggedByName, color: m.loggedByColorHex,
                      deletedAt: m.deletedAt, editOfID: m.editOfID, babyID: m.baby?.id)
            return r
        }
        if let m = MedicationEvent.fetchByID(uuid, in: context) {
            let r = baseRecord(type: SyncConstants.RecordType.medication, recordID: recordID, archived: m.ckSystemFields)
            r["name"] = m.name
            r["dosage"] = m.dosage
            r["timestamp"] = m.timestamp
            r["administeredBy"] = m.administeredBy
            r["notes"] = m.notes
            r["sourceRaw"] = m.sourceRaw
            r["externalID"] = m.externalID
            setCommon(r, loggedByID: m.loggedByID, name: m.loggedByName, color: m.loggedByColorHex,
                      deletedAt: m.deletedAt, editOfID: m.editOfID, babyID: m.baby?.id)
            return r
        }
        if let m = HealthCheckEvent.fetchByID(uuid, in: context) {
            let r = baseRecord(type: SyncConstants.RecordType.healthCheck, recordID: recordID, archived: m.ckSystemFields)
            r["typeRaw"] = m.typeRaw
            r["value"] = m.value
            r["timestamp"] = m.timestamp
            r["notes"] = m.notes
            r["sourceRaw"] = m.sourceRaw
            r["externalID"] = m.externalID
            setCommon(r, loggedByID: m.loggedByID, name: m.loggedByName, color: m.loggedByColorHex,
                      deletedAt: m.deletedAt, editOfID: m.editOfID, babyID: m.baby?.id)
            return r
        }
        if let m = MoodEvent.fetchByID(uuid, in: context) {
            let r = baseRecord(type: SyncConstants.RecordType.mood, recordID: recordID, archived: m.ckSystemFields)
            r["levelRaw"] = m.levelRaw
            r["timestamp"] = m.timestamp
            r["notes"] = m.notes
            r["sourceRaw"] = m.sourceRaw
            r["externalID"] = m.externalID
            setCommon(r, loggedByID: m.loggedByID, name: m.loggedByName, color: m.loggedByColorHex,
                      deletedAt: m.deletedAt, editOfID: m.editOfID, babyID: m.baby?.id)
            return r
        }
        if let m = PottyEvent.fetchByID(uuid, in: context) {
            let r = baseRecord(type: SyncConstants.RecordType.potty, recordID: recordID, archived: m.ckSystemFields)
            r["outcomeRaw"] = m.outcomeRaw
            r["timestamp"] = m.timestamp
            r["notes"] = m.notes
            r["sourceRaw"] = m.sourceRaw
            r["externalID"] = m.externalID
            setCommon(r, loggedByID: m.loggedByID, name: m.loggedByName, color: m.loggedByColorHex,
                      deletedAt: m.deletedAt, editOfID: m.editOfID, babyID: m.baby?.id)
            return r
        }
        if let m = MilestoneEvent.fetchByID(uuid, in: context) {
            let r = baseRecord(type: SyncConstants.RecordType.milestone, recordID: recordID, archived: m.ckSystemFields)
            r["text"] = m.text
            r["categoryRaw"] = m.categoryRaw
            r["timestamp"] = m.timestamp
            r["notes"] = m.notes
            r["photoData"] = asset(from: m.photoData)
            r["sourceRaw"] = m.sourceRaw
            r["externalID"] = m.externalID
            setCommon(r, loggedByID: m.loggedByID, name: m.loggedByName, color: m.loggedByColorHex,
                      deletedAt: m.deletedAt, editOfID: m.editOfID, babyID: m.baby?.id)
            return r
        }
        if let m = StaffNoteEvent.fetchByID(uuid, in: context) {
            let r = baseRecord(type: SyncConstants.RecordType.staffNote, recordID: recordID, archived: m.ckSystemFields)
            r["text"] = m.text
            r["authorName"] = m.authorName
            r["timestamp"] = m.timestamp
            r["sourceRaw"] = m.sourceRaw
            r["externalID"] = m.externalID
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
            r["feedLoggingEnabled"] = m.feedLoggingEnabled ? 1 : 0
            r["diaperLoggingEnabled"] = m.diaperLoggingEnabled ? 1 : 0
            r["sleepLoggingEnabled"] = m.sleepLoggingEnabled ? 1 : 0
            r["nightStartMinute"] = m.nightStartMinute
            r["nightEndMinute"] = m.nightEndMinute
            r["nightFirstFeedMinute"] = m.nightFirstFeedMinute
            r["nightFeedSpacingMinutes"] = m.nightFeedSpacingMinutes
            r["nightRotationRaw"] = m.nightRotationRaw
            r["aiPredictionsEnabled"] = m.aiPredictionsEnabled ? 1 : 0
            // Empty string is the explicit "no first shift chosen": CloudKit
            // never transmits an unset key, so a bare nil could not clear the
            // co-parent's copy.
            r["nightFirstShiftID"] = m.nightFirstShiftID?.uuidString ?? ""
            // Three-state on purpose: nil (never set — pre-feature) writes
            // NO field so it can't stomp another device's copy; "" is the
            // explicit sign-out that must travel; JSON is the connection.
            if let snooCredentials = m.snooCredentials {
                r["snooCredentials"] = snooCredentials
            }
            return r
        }
        if let m = PlanSlot.fetchByID(uuid, in: context) {
            let r = baseRecord(type: SyncConstants.RecordType.planSlot, recordID: recordID, archived: m.ckSystemFields)
            r["kindRaw"] = m.kindRaw
            r["minuteOfDay"] = m.minuteOfDay
            r["endMinuteOfDay"] = m.endMinuteOfDay
            r["assignedToID"] = m.assignedToID?.uuidString
            r["assignedToName"] = m.assignedToName
            r["assignedToColorHex"] = m.assignedToColorHex
            r["createdAt"] = m.createdAt
            r["deletedAt"] = m.deletedAt
            return r
        }
        if let m = PlanOverride.fetchByID(uuid, in: context) {
            let r = baseRecord(type: SyncConstants.RecordType.planOverride, recordID: recordID, archived: m.ckSystemFields)
            r["slotID"] = m.slotID.uuidString
            r["dayKey"] = m.dayKey
            r["assignedToID"] = m.assignedToID?.uuidString
            r["assignedToName"] = m.assignedToName
            r["assignedToColorHex"] = m.assignedToColorHex
            r["isSkipped"] = m.isSkipped ? 1 : 0
            r["minuteOfDayOverride"] = m.minuteOfDayOverride
            r["createdByID"] = m.createdByID.uuidString
            r["createdAt"] = m.createdAt
            r["deletedAt"] = m.deletedAt
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
        var note = FetchDescriptor<NoteEvent>(predicate: #Predicate { $0.id == uuid })
        note.fetchLimit = 1
        if try context.fetchCount(note) > 0 { return true }
        var baby = FetchDescriptor<Baby>(predicate: #Predicate { $0.id == uuid })
        baby.fetchLimit = 1
        if try context.fetchCount(baby) > 0 { return true }
        var participant = FetchDescriptor<Participant>(predicate: #Predicate { $0.id == uuid })
        participant.fetchLimit = 1
        if try context.fetchCount(participant) > 0 { return true }
        var settings = FetchDescriptor<SharedSettings>(predicate: #Predicate { $0.id == uuid })
        settings.fetchLimit = 1
        if try context.fetchCount(settings) > 0 { return true }
        var slot = FetchDescriptor<PlanSlot>(predicate: #Predicate { $0.id == uuid })
        slot.fetchLimit = 1
        if try context.fetchCount(slot) > 0 { return true }
        var override = FetchDescriptor<PlanOverride>(predicate: #Predicate { $0.id == uuid })
        override.fetchLimit = 1
        if try context.fetchCount(override) > 0 { return true }
        var activity = FetchDescriptor<ActivityEvent>(predicate: #Predicate { $0.id == uuid })
        activity.fetchLimit = 1
        if try context.fetchCount(activity) > 0 { return true }
        var media = FetchDescriptor<MediaEvent>(predicate: #Predicate { $0.id == uuid })
        media.fetchLimit = 1
        if try context.fetchCount(media) > 0 { return true }
        var check = FetchDescriptor<CheckEvent>(predicate: #Predicate { $0.id == uuid })
        check.fetchLimit = 1
        if try context.fetchCount(check) > 0 { return true }
        var medication = FetchDescriptor<MedicationEvent>(predicate: #Predicate { $0.id == uuid })
        medication.fetchLimit = 1
        if try context.fetchCount(medication) > 0 { return true }
        var health = FetchDescriptor<HealthCheckEvent>(predicate: #Predicate { $0.id == uuid })
        health.fetchLimit = 1
        if try context.fetchCount(health) > 0 { return true }
        var mood = FetchDescriptor<MoodEvent>(predicate: #Predicate { $0.id == uuid })
        mood.fetchLimit = 1
        if try context.fetchCount(mood) > 0 { return true }
        var potty = FetchDescriptor<PottyEvent>(predicate: #Predicate { $0.id == uuid })
        potty.fetchLimit = 1
        if try context.fetchCount(potty) > 0 { return true }
        var milestone = FetchDescriptor<MilestoneEvent>(predicate: #Predicate { $0.id == uuid })
        milestone.fetchLimit = 1
        if try context.fetchCount(milestone) > 0 { return true }
        var staffNote = FetchDescriptor<StaffNoteEvent>(predicate: #Predicate { $0.id == uuid })
        staffNote.fetchLimit = 1
        return try context.fetchCount(staffNote) > 0
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
        clear(FeedEvent.self); clear(SleepEvent.self); clear(DiaperEvent.self); clear(NoteEvent.self)
        clear(Baby.self); clear(Participant.self); clear(SharedSettings.self)
        clear(PlanSlot.self); clear(PlanOverride.self)
        clear(ActivityEvent.self); clear(MediaEvent.self); clear(CheckEvent.self)
        clear(MedicationEvent.self); clear(HealthCheckEvent.self); clear(MoodEvent.self)
        clear(PottyEvent.self); clear(MilestoneEvent.self); clear(StaffNoteEvent.self)
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
            // A store error here is tolerable to swallow: the pending local save
            // re-pushes the record either way, and the fetch handler's throwing
            // path covers the batch-apply case.
            try? apply(server, in: context)
            return false
        }
        if let soft = model as? SoftDeletable, soft.deletedAt == nil,
           let serverDeleted = server["deletedAt"] as? Date {
            soft.deletedAt = serverDeleted
        }
        if let sleep = model as? SleepEvent, sleep.endedAt == nil,
           let serverEnded = server["endedAt"] as? Date {
            sleep.endedAt = serverEnded
        }
        if let settings = model as? SharedSettings,
           let serverCreds = server["snooCredentials"] as? String {
            if settings.snooCredentials == nil {
                // Local nil means this build/row never held the field — the
                // whole-zone re-fetch delivering it must not be discarded by
                // local-wins just because a settings save was pending (that
                // re-drop was exactly the healed bug coming back).
                settings.snooCredentials = serverCreds
            } else if serverCreds.isEmpty, let local = settings.snooCredentials, !local.isEmpty {
                // A household SNOO sign-out ("") is terminal like a
                // soft-delete — a stale settings edit racing it must not
                // resurrect the severed connection — EXCEPT over a blob
                // whose sign-in is NEWER than the sign-out (a parent
                // legitimately re-connecting right after): that fresh blob
                // wins and re-uploads. Blobs without the recency stamp
                // (pre-field builds) count as old.
                let signedOutAt = server.modificationDate ?? .distantPast
                let signedInAt = SnooSharedCredentials(json: local)?.signedInAt ?? .distantPast
                if signedInAt <= signedOutAt {
                    settings.snooCredentials = ""
                }
            }
        }
        model.ckSystemFields = archivedSystemFields(of: server)
        return true
    }

    // MARK: Inbound (CKRecord → local model, upsert by id)

    /// Upserts a fetched record into the local store, keyed by record name (the
    /// model's `id`). Throws when the store itself errored on the existence
    /// check: the old `try?` there silently turned a transient SQLite hiccup
    /// into a blind INSERT — a second row with the same id whose placeholder
    /// values (0 oz, "wet", `.now`, a random logger UUID, an empty name)
    /// rendered as the "?" ghost events. Callers treat a throw like a failed
    /// batch save (reset the engine and re-fetch) so the record is re-delivered
    /// instead of duplicated or dropped.
    static func apply(_ record: CKRecord, in context: ModelContext) throws {
        guard let uuid = UUID(uuidString: record.recordID.recordName) else { return }
        switch record.recordType {
        case SyncConstants.RecordType.feed:    try applyFeed(record, uuid: uuid, in: context)
        case SyncConstants.RecordType.sleep:   try applySleep(record, uuid: uuid, in: context)
        case SyncConstants.RecordType.diaper:  try applyDiaper(record, uuid: uuid, in: context)
        case SyncConstants.RecordType.note:    try applyNote(record, uuid: uuid, in: context)
        case SyncConstants.RecordType.baby:    try applyBaby(record, uuid: uuid, in: context)
        case SyncConstants.RecordType.participant: try applyParticipant(record, uuid: uuid, in: context)
        case SyncConstants.RecordType.settings: try applySettings(record, uuid: uuid, in: context)
        case SyncConstants.RecordType.planSlot: try applyPlanSlot(record, uuid: uuid, in: context)
        case SyncConstants.RecordType.planOverride: try applyPlanOverride(record, uuid: uuid, in: context)
        case SyncConstants.RecordType.activity:    try applyActivity(record, uuid: uuid, in: context)
        case SyncConstants.RecordType.media:       try applyMedia(record, uuid: uuid, in: context)
        case SyncConstants.RecordType.check:       try applyCheck(record, uuid: uuid, in: context)
        case SyncConstants.RecordType.medication:  try applyMedication(record, uuid: uuid, in: context)
        case SyncConstants.RecordType.healthCheck: try applyHealthCheck(record, uuid: uuid, in: context)
        case SyncConstants.RecordType.mood:        try applyMood(record, uuid: uuid, in: context)
        case SyncConstants.RecordType.potty:       try applyPotty(record, uuid: uuid, in: context)
        case SyncConstants.RecordType.milestone:   try applyMilestone(record, uuid: uuid, in: context)
        case SyncConstants.RecordType.staffNote:   try applyStaffNote(record, uuid: uuid, in: context)
        default:
            // System records (e.g. the zone-wide cloudkit.share) are expected
            // here; an unknown MODEL type means this build predates it — the
            // record is dropped now but re-delivered by the record-type
            // re-fetch after the app updates (SyncManager).
            if !record.recordType.hasPrefix("cloudkit.") {
                AppLog.sync.warning("Ignored inbound record of unknown type \(record.recordType, privacy: .public) — this build predates it")
            }
        }
    }

    /// Hard-deletes the local model with this record name (used for true CloudKit
    /// deletions; routine removals travel as `deletedAt` updates). Throws on a
    /// store error so the caller can re-fetch instead of silently dropping the
    /// deletion (the engine checkpoints the batch either way).
    static func delete(recordName: String, in context: ModelContext) throws {
        guard let uuid = UUID(uuidString: recordName) else { return }
        if let m = try FeedEvent.findByID(uuid, in: context) { context.delete(m); return }
        if let m = try SleepEvent.findByID(uuid, in: context) { context.delete(m); return }
        if let m = try DiaperEvent.findByID(uuid, in: context) { context.delete(m); return }
        if let m = try NoteEvent.findByID(uuid, in: context) { context.delete(m); return }
        if let m = try Participant.findByID(uuid, in: context) { context.delete(m); return }
        if let m = try Baby.findByID(uuid, in: context) { context.delete(m); return }
        if let m = try SharedSettings.findByID(uuid, in: context) { context.delete(m); return }
        if let m = try PlanSlot.findByID(uuid, in: context) { context.delete(m); return }
        if let m = try PlanOverride.findByID(uuid, in: context) { context.delete(m); return }
        if let m = try ActivityEvent.findByID(uuid, in: context) { context.delete(m); return }
        if let m = try MediaEvent.findByID(uuid, in: context) { context.delete(m); return }
        if let m = try CheckEvent.findByID(uuid, in: context) { context.delete(m); return }
        if let m = try MedicationEvent.findByID(uuid, in: context) { context.delete(m); return }
        if let m = try HealthCheckEvent.findByID(uuid, in: context) { context.delete(m); return }
        if let m = try MoodEvent.findByID(uuid, in: context) { context.delete(m); return }
        if let m = try PottyEvent.findByID(uuid, in: context) { context.delete(m); return }
        if let m = try MilestoneEvent.findByID(uuid, in: context) { context.delete(m); return }
        if let m = try StaffNoteEvent.findByID(uuid, in: context) { context.delete(m); return }
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
        for e in (try? context.fetch(FetchDescriptor<NoteEvent>(
            predicate: #Predicate { $0.baby == nil }))) ?? [] { e.baby = baby }
        for e in (try? context.fetch(FetchDescriptor<ActivityEvent>(
            predicate: #Predicate { $0.baby == nil }))) ?? [] { e.baby = baby }
        for e in (try? context.fetch(FetchDescriptor<MediaEvent>(
            predicate: #Predicate { $0.baby == nil }))) ?? [] { e.baby = baby }
        for e in (try? context.fetch(FetchDescriptor<CheckEvent>(
            predicate: #Predicate { $0.baby == nil }))) ?? [] { e.baby = baby }
        for e in (try? context.fetch(FetchDescriptor<MedicationEvent>(
            predicate: #Predicate { $0.baby == nil }))) ?? [] { e.baby = baby }
        for e in (try? context.fetch(FetchDescriptor<HealthCheckEvent>(
            predicate: #Predicate { $0.baby == nil }))) ?? [] { e.baby = baby }
        for e in (try? context.fetch(FetchDescriptor<MoodEvent>(
            predicate: #Predicate { $0.baby == nil }))) ?? [] { e.baby = baby }
        for e in (try? context.fetch(FetchDescriptor<PottyEvent>(
            predicate: #Predicate { $0.baby == nil }))) ?? [] { e.baby = baby }
        for e in (try? context.fetch(FetchDescriptor<MilestoneEvent>(
            predicate: #Predicate { $0.baby == nil }))) ?? [] { e.baby = baby }
        for e in (try? context.fetch(FetchDescriptor<StaffNoteEvent>(
            predicate: #Predicate { $0.baby == nil }))) ?? [] { e.baby = baby }
    }

    // MARK: Inbound per-type
    //
    // Event inserts are built FROM the record's own values — never from
    // placeholder defaults. A record missing its required fields (timestamp +
    // logger identity; every build has always uploaded them) is skipped and
    // logged: materializing it as "0 oz / wet / now / random logger" is exactly
    // the ghost-event shape, and junk on the server must not become a local row.

    /// The shared event identity fields, required before an insert is allowed.
    private static func loggerIdentity(_ r: CKRecord) -> (id: UUID, name: String, color: String)? {
        guard let id = (r["loggedByID"] as? String).flatMap(UUID.init) else { return nil }
        return (id, r["loggedByName"] as? String ?? "", r["loggedByColorHex"] as? String ?? "")
    }

    private static func skip(_ r: CKRecord, missing: String) {
        AppLog.sync.error("Skipped inbound \(r.recordType, privacy: .public) \(r.recordID.recordName, privacy: .public): missing \(missing, privacy: .public) — refusing to materialize a placeholder event")
    }

    private static func applyFeed(_ r: CKRecord, uuid: UUID, in context: ModelContext) throws {
        let m: FeedEvent
        if let existing = try FeedEvent.findByID(uuid, in: context) {
            m = existing
        } else {
            guard let timestamp = r["timestamp"] as? Date,
                  let amountOz = r["amountOz"] as? Double,
                  let logger = loggerIdentity(r) else {
                skip(r, missing: "timestamp/amountOz/loggedByID"); return
            }
            m = insert(FeedEvent(baby: nil, amountOz: amountOz, timestamp: timestamp,
                                 loggedByID: logger.id, loggedByName: logger.name,
                                 loggedByColorHex: logger.color), id: uuid, in: context)
        }
        m.amountOz = r["amountOz"] as? Double ?? m.amountOz
        m.timestamp = r["timestamp"] as? Date ?? m.timestamp
        m.notes = r["notes"] as? String
        m.sourceRaw = r["sourceRaw"] as? String
        m.externalID = r["externalID"] as? String
        applyCommon(r, into: m, in: context)
    }

    private static func applySleep(_ r: CKRecord, uuid: UUID, in context: ModelContext) throws {
        let m: SleepEvent
        if let existing = try SleepEvent.findByID(uuid, in: context) {
            m = existing
        } else {
            guard let startedAt = r["startedAt"] as? Date,
                  let logger = loggerIdentity(r) else {
                skip(r, missing: "startedAt/loggedByID"); return
            }
            m = insert(SleepEvent(baby: nil, startedAt: startedAt,
                                  loggedByID: logger.id, loggedByName: logger.name,
                                  loggedByColorHex: logger.color), id: uuid, in: context)
        }
        m.startedAt = r["startedAt"] as? Date ?? m.startedAt
        m.endedAt = r["endedAt"] as? Date
        m.notes = r["notes"] as? String
        m.sourceRaw = r["sourceRaw"] as? String
        m.externalID = r["externalID"] as? String
        applyCommon(r, into: m, in: context)
    }

    private static func applyDiaper(_ r: CKRecord, uuid: UUID, in context: ModelContext) throws {
        let m: DiaperEvent
        if let existing = try DiaperEvent.findByID(uuid, in: context) {
            m = existing
        } else {
            guard let timestamp = r["timestamp"] as? Date,
                  let typeRaw = r["typeRaw"] as? String,
                  let type = DiaperType(rawValue: typeRaw),
                  let logger = loggerIdentity(r) else {
                skip(r, missing: "timestamp/typeRaw/loggedByID"); return
            }
            m = insert(DiaperEvent(baby: nil, type: type, timestamp: timestamp,
                                   loggedByID: logger.id, loggedByName: logger.name,
                                   loggedByColorHex: logger.color), id: uuid, in: context)
        }
        m.typeRaw = r["typeRaw"] as? String ?? m.typeRaw
        m.timestamp = r["timestamp"] as? Date ?? m.timestamp
        m.notes = r["notes"] as? String
        m.sourceRaw = r["sourceRaw"] as? String
        m.externalID = r["externalID"] as? String
        applyCommon(r, into: m, in: context)
    }

    private static func applyNote(_ r: CKRecord, uuid: UUID, in context: ModelContext) throws {
        let m: NoteEvent
        if let existing = try NoteEvent.findByID(uuid, in: context) {
            m = existing
        } else {
            guard let timestamp = r["timestamp"] as? Date,
                  let text = r["text"] as? String,
                  let logger = loggerIdentity(r) else {
                skip(r, missing: "timestamp/text/loggedByID"); return
            }
            m = insert(NoteEvent(baby: nil, text: text, timestamp: timestamp,
                                 loggedByID: logger.id, loggedByName: logger.name,
                                 loggedByColorHex: logger.color), id: uuid, in: context)
        }
        m.text = r["text"] as? String ?? m.text
        m.timestamp = r["timestamp"] as? Date ?? m.timestamp
        m.sourceRaw = r["sourceRaw"] as? String
        m.externalID = r["externalID"] as? String
        applyCommon(r, into: m, in: context)
    }

    private static func applyBaby(_ r: CKRecord, uuid: UUID, in context: ModelContext) throws {
        let existing = try Baby.findByID(uuid, in: context)
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

    private static func applyParticipant(_ r: CKRecord, uuid: UUID, in context: ModelContext) throws {
        let m: Participant
        if let existing = try Participant.findByID(uuid, in: context) {
            m = existing
        } else {
            // Same placeholder rule as events: a junk record must not become a
            // nameless local row — its id would count as a "known participant",
            // immunizing any ghost events attributed to it against every sweep.
            guard let name = r["displayName"] as? String, !name.isEmpty else {
                skip(r, missing: "displayName"); return
            }
            m = insert(Participant(displayName: name, colorHex: ""), id: uuid, in: context)
        }
        m.displayName = r["displayName"] as? String ?? m.displayName
        m.colorHex = r["colorHex"] as? String ?? m.colorHex
        m.roleRaw = r["roleRaw"] as? String ?? m.roleRaw
        // Only adopt a PRESENT identity: an older build's record (or a sparse
        // copy) carries no cloudUserID field, and nil-ing a locally captured one
        // permanently disarms the duplicate-participant auto-merge.
        if let cid = r["cloudUserID"] as? String { m.cloudUserID = cid }
        m.isActive = (r["isActive"] as? Int ?? 1) != 0
        m.invitedAt = r["invitedAt"] as? Date ?? m.invitedAt
        if let resolved = inboundPhoto(r["photoData"]) { m.photoData = resolved }
    }

    private static func applySettings(_ r: CKRecord, uuid: UUID, in context: ModelContext) throws {
        let m = try SharedSettings.findByID(uuid, in: context)
            ?? insert(SharedSettings(), id: uuid, in: context)
        m.targetFeedIntervalMinutes = r["targetFeedIntervalMinutes"] as? Int ?? m.targetFeedIntervalMinutes
        m.ozPresets = r["ozPresets"] as? [Double] ?? m.ozPresets
        m.defaultFeedOz = r["defaultFeedOz"] as? Double ?? m.defaultFeedOz
        // Absent field (a record written pre-trackers) keeps the local value.
        m.feedLoggingEnabled = (r["feedLoggingEnabled"] as? Int).map { $0 != 0 } ?? m.feedLoggingEnabled
        m.diaperLoggingEnabled = (r["diaperLoggingEnabled"] as? Int).map { $0 != 0 } ?? m.diaperLoggingEnabled
        m.sleepLoggingEnabled = (r["sleepLoggingEnabled"] as? Int).map { $0 != 0 } ?? m.sleepLoggingEnabled
        // Absent fields (a record written pre-nighttime-schedule) keep the
        // local defaults rather than zeroing the night window.
        m.nightStartMinute = r["nightStartMinute"] as? Int ?? m.nightStartMinute
        m.nightEndMinute = r["nightEndMinute"] as? Int ?? m.nightEndMinute
        m.nightFirstFeedMinute = r["nightFirstFeedMinute"] as? Int ?? m.nightFirstFeedMinute
        m.nightFeedSpacingMinutes = r["nightFeedSpacingMinutes"] as? Int ?? m.nightFeedSpacingMinutes
        m.nightRotationRaw = r["nightRotationRaw"] as? String ?? m.nightRotationRaw
        // Absent field (a record written pre-AI-features) keeps the local value.
        m.aiPredictionsEnabled = (r["aiPredictionsEnabled"] as? Int).map { $0 != 0 } ?? m.aiPredictionsEnabled
        // Present-but-empty means "cleared"; absent (an older build's record)
        // keeps the local value.
        if let s = r["nightFirstShiftID"] as? String { m.nightFirstShiftID = UUID(uuidString: s) }
        // Keep "" as "" — it's the explicit sign-out, distinct from nil
        // (never set); absent (an older build's record) keeps the local value.
        if let s = r["snooCredentials"] as? String { m.snooCredentials = s }
    }

    private static func applyPlanSlot(_ r: CKRecord, uuid: UUID, in context: ModelContext) throws {
        let m = try PlanSlot.findByID(uuid, in: context)
            ?? insert(PlanSlot(kind: .feed, minuteOfDay: 0), id: uuid, in: context)
        m.kindRaw = r["kindRaw"] as? String ?? m.kindRaw
        m.minuteOfDay = r["minuteOfDay"] as? Int ?? m.minuteOfDay
        m.endMinuteOfDay = r["endMinuteOfDay"] as? Int
        if let s = r["assignedToID"] as? String { m.assignedToID = UUID(uuidString: s) } else { m.assignedToID = nil }
        m.assignedToName = r["assignedToName"] as? String ?? m.assignedToName
        m.assignedToColorHex = r["assignedToColorHex"] as? String ?? m.assignedToColorHex
        m.createdAt = r["createdAt"] as? Date ?? m.createdAt
        m.deletedAt = r["deletedAt"] as? Date
    }

    private static func applyPlanOverride(_ r: CKRecord, uuid: UUID, in context: ModelContext) throws {
        let m = try PlanOverride.findByID(uuid, in: context)
            ?? insert(PlanOverride(slotID: UUID(), dayKey: 0, createdByID: UUID()), id: uuid, in: context)
        if let s = r["slotID"] as? String, let sid = UUID(uuidString: s) { m.slotID = sid }
        m.dayKey = r["dayKey"] as? Int ?? m.dayKey
        if let s = r["assignedToID"] as? String { m.assignedToID = UUID(uuidString: s) } else { m.assignedToID = nil }
        m.assignedToName = r["assignedToName"] as? String ?? m.assignedToName
        m.assignedToColorHex = r["assignedToColorHex"] as? String ?? m.assignedToColorHex
        m.isSkipped = (r["isSkipped"] as? Int ?? 0) != 0
        // Absent means either "no move" or a pre-move app version; both read as
        // nil — override records are immutable after creation (only deletedAt
        // changes), so absence can't clobber a real move.
        m.minuteOfDayOverride = r["minuteOfDayOverride"] as? Int
        if let s = r["createdByID"] as? String, let cid = UUID(uuidString: s) { m.createdByID = cid }
        m.createdAt = r["createdAt"] as? Date ?? m.createdAt
        m.deletedAt = r["deletedAt"] as? Date
    }

    // Daycare event types. Same placeholder-refusal rule as the core four:
    // inserts require the record's own timestamp + logger identity (plus the
    // type's primary payload where "empty" would render as junk).

    private static func applyActivity(_ r: CKRecord, uuid: UUID, in context: ModelContext) throws {
        let m: ActivityEvent
        if let existing = try ActivityEvent.findByID(uuid, in: context) {
            m = existing
        } else {
            guard let timestamp = r["timestamp"] as? Date,
                  let typeRaw = r["typeRaw"] as? String,
                  let type = ActivityType(rawValue: typeRaw),
                  let logger = loggerIdentity(r) else {
                skip(r, missing: "timestamp/typeRaw/loggedByID"); return
            }
            m = insert(ActivityEvent(baby: nil, type: type, timestamp: timestamp,
                                     loggedByID: logger.id, loggedByName: logger.name,
                                     loggedByColorHex: logger.color), id: uuid, in: context)
        }
        m.typeRaw = r["typeRaw"] as? String ?? m.typeRaw
        m.timestamp = r["timestamp"] as? Date ?? m.timestamp
        m.durationMinutes = r["durationMinutes"] as? Int
        m.notes = r["notes"] as? String
        m.sourceRaw = r["sourceRaw"] as? String
        m.externalID = r["externalID"] as? String
        applyCommon(r, into: m, in: context)
    }

    private static func applyMedia(_ r: CKRecord, uuid: UUID, in context: ModelContext) throws {
        let m: MediaEvent
        if let existing = try MediaEvent.findByID(uuid, in: context) {
            m = existing
        } else {
            guard let timestamp = r["timestamp"] as? Date,
                  let kindRaw = r["kindRaw"] as? String,
                  let kind = MediaKind(rawValue: kindRaw),
                  let logger = loggerIdentity(r) else {
                skip(r, missing: "timestamp/kindRaw/loggedByID"); return
            }
            m = insert(MediaEvent(baby: nil, kind: kind, timestamp: timestamp,
                                  loggedByID: logger.id, loggedByName: logger.name,
                                  loggedByColorHex: logger.color), id: uuid, in: context)
        }
        m.kindRaw = r["kindRaw"] as? String ?? m.kindRaw
        m.timestamp = r["timestamp"] as? Date ?? m.timestamp
        m.caption = r["caption"] as? String
        m.remoteURL = r["remoteURL"] as? String
        // Same transient-asset guard as avatars: an unreadable CKAsset must
        // not wipe locally cached bytes.
        if let resolved = inboundPhoto(r["mediaData"]) { m.mediaData = resolved }
        m.sourceRaw = r["sourceRaw"] as? String
        m.externalID = r["externalID"] as? String
        applyCommon(r, into: m, in: context)
    }

    private static func applyCheck(_ r: CKRecord, uuid: UUID, in context: ModelContext) throws {
        let m: CheckEvent
        if let existing = try CheckEvent.findByID(uuid, in: context) {
            m = existing
        } else {
            guard let timestamp = r["timestamp"] as? Date,
                  let typeRaw = r["typeRaw"] as? String,
                  let type = CheckType(rawValue: typeRaw),
                  let logger = loggerIdentity(r) else {
                skip(r, missing: "timestamp/typeRaw/loggedByID"); return
            }
            m = insert(CheckEvent(baby: nil, type: type, timestamp: timestamp,
                                  loggedByID: logger.id, loggedByName: logger.name,
                                  loggedByColorHex: logger.color), id: uuid, in: context)
        }
        m.typeRaw = r["typeRaw"] as? String ?? m.typeRaw
        m.timestamp = r["timestamp"] as? Date ?? m.timestamp
        m.byName = r["byName"] as? String
        m.notes = r["notes"] as? String
        m.sourceRaw = r["sourceRaw"] as? String
        m.externalID = r["externalID"] as? String
        applyCommon(r, into: m, in: context)
    }

    private static func applyMedication(_ r: CKRecord, uuid: UUID, in context: ModelContext) throws {
        let m: MedicationEvent
        if let existing = try MedicationEvent.findByID(uuid, in: context) {
            m = existing
        } else {
            guard let timestamp = r["timestamp"] as? Date,
                  let name = r["name"] as? String, !name.isEmpty,
                  let logger = loggerIdentity(r) else {
                skip(r, missing: "timestamp/name/loggedByID"); return
            }
            m = insert(MedicationEvent(baby: nil, name: name, timestamp: timestamp,
                                       loggedByID: logger.id, loggedByName: logger.name,
                                       loggedByColorHex: logger.color), id: uuid, in: context)
        }
        m.name = r["name"] as? String ?? m.name
        m.dosage = r["dosage"] as? String
        m.timestamp = r["timestamp"] as? Date ?? m.timestamp
        m.administeredBy = r["administeredBy"] as? String
        m.notes = r["notes"] as? String
        m.sourceRaw = r["sourceRaw"] as? String
        m.externalID = r["externalID"] as? String
        applyCommon(r, into: m, in: context)
    }

    private static func applyHealthCheck(_ r: CKRecord, uuid: UUID, in context: ModelContext) throws {
        let m: HealthCheckEvent
        if let existing = try HealthCheckEvent.findByID(uuid, in: context) {
            m = existing
        } else {
            guard let timestamp = r["timestamp"] as? Date,
                  let typeRaw = r["typeRaw"] as? String,
                  let type = HealthCheckType(rawValue: typeRaw),
                  let value = r["value"] as? Double,
                  let logger = loggerIdentity(r) else {
                skip(r, missing: "timestamp/typeRaw/value/loggedByID"); return
            }
            m = insert(HealthCheckEvent(baby: nil, type: type, value: value, timestamp: timestamp,
                                        loggedByID: logger.id, loggedByName: logger.name,
                                        loggedByColorHex: logger.color), id: uuid, in: context)
        }
        m.typeRaw = r["typeRaw"] as? String ?? m.typeRaw
        m.value = r["value"] as? Double ?? m.value
        m.timestamp = r["timestamp"] as? Date ?? m.timestamp
        m.notes = r["notes"] as? String
        m.sourceRaw = r["sourceRaw"] as? String
        m.externalID = r["externalID"] as? String
        applyCommon(r, into: m, in: context)
    }

    private static func applyMood(_ r: CKRecord, uuid: UUID, in context: ModelContext) throws {
        let m: MoodEvent
        if let existing = try MoodEvent.findByID(uuid, in: context) {
            m = existing
        } else {
            guard let timestamp = r["timestamp"] as? Date,
                  let levelRaw = r["levelRaw"] as? String,
                  let level = MoodLevel(rawValue: levelRaw),
                  let logger = loggerIdentity(r) else {
                skip(r, missing: "timestamp/levelRaw/loggedByID"); return
            }
            m = insert(MoodEvent(baby: nil, level: level, timestamp: timestamp,
                                 loggedByID: logger.id, loggedByName: logger.name,
                                 loggedByColorHex: logger.color), id: uuid, in: context)
        }
        m.levelRaw = r["levelRaw"] as? String ?? m.levelRaw
        m.timestamp = r["timestamp"] as? Date ?? m.timestamp
        m.notes = r["notes"] as? String
        m.sourceRaw = r["sourceRaw"] as? String
        m.externalID = r["externalID"] as? String
        applyCommon(r, into: m, in: context)
    }

    private static func applyPotty(_ r: CKRecord, uuid: UUID, in context: ModelContext) throws {
        let m: PottyEvent
        if let existing = try PottyEvent.findByID(uuid, in: context) {
            m = existing
        } else {
            guard let timestamp = r["timestamp"] as? Date,
                  let outcomeRaw = r["outcomeRaw"] as? String,
                  let outcome = PottyOutcome(rawValue: outcomeRaw),
                  let logger = loggerIdentity(r) else {
                skip(r, missing: "timestamp/outcomeRaw/loggedByID"); return
            }
            m = insert(PottyEvent(baby: nil, outcome: outcome, timestamp: timestamp,
                                  loggedByID: logger.id, loggedByName: logger.name,
                                  loggedByColorHex: logger.color), id: uuid, in: context)
        }
        m.outcomeRaw = r["outcomeRaw"] as? String ?? m.outcomeRaw
        m.timestamp = r["timestamp"] as? Date ?? m.timestamp
        m.notes = r["notes"] as? String
        m.sourceRaw = r["sourceRaw"] as? String
        m.externalID = r["externalID"] as? String
        applyCommon(r, into: m, in: context)
    }

    private static func applyMilestone(_ r: CKRecord, uuid: UUID, in context: ModelContext) throws {
        let m: MilestoneEvent
        if let existing = try MilestoneEvent.findByID(uuid, in: context) {
            m = existing
        } else {
            guard let timestamp = r["timestamp"] as? Date,
                  let text = r["text"] as? String, !text.isEmpty,
                  let categoryRaw = r["categoryRaw"] as? String,
                  let category = MilestoneCategory(rawValue: categoryRaw),
                  let logger = loggerIdentity(r) else {
                skip(r, missing: "timestamp/text/categoryRaw/loggedByID"); return
            }
            m = insert(MilestoneEvent(baby: nil, text: text, category: category, timestamp: timestamp,
                                      loggedByID: logger.id, loggedByName: logger.name,
                                      loggedByColorHex: logger.color), id: uuid, in: context)
        }
        m.text = r["text"] as? String ?? m.text
        m.categoryRaw = r["categoryRaw"] as? String ?? m.categoryRaw
        m.timestamp = r["timestamp"] as? Date ?? m.timestamp
        m.notes = r["notes"] as? String
        if let resolved = inboundPhoto(r["photoData"]) { m.photoData = resolved }
        m.sourceRaw = r["sourceRaw"] as? String
        m.externalID = r["externalID"] as? String
        applyCommon(r, into: m, in: context)
    }

    private static func applyStaffNote(_ r: CKRecord, uuid: UUID, in context: ModelContext) throws {
        let m: StaffNoteEvent
        if let existing = try StaffNoteEvent.findByID(uuid, in: context) {
            m = existing
        } else {
            guard let timestamp = r["timestamp"] as? Date,
                  let text = r["text"] as? String, !text.isEmpty,
                  let logger = loggerIdentity(r) else {
                skip(r, missing: "timestamp/text/loggedByID"); return
            }
            m = insert(StaffNoteEvent(baby: nil, text: text, timestamp: timestamp,
                                      loggedByID: logger.id, loggedByName: logger.name,
                                      loggedByColorHex: logger.color), id: uuid, in: context)
        }
        m.text = r["text"] as? String ?? m.text
        m.authorName = r["authorName"] as? String
        m.timestamp = r["timestamp"] as? Date ?? m.timestamp
        m.sourceRaw = r["sourceRaw"] as? String
        m.externalID = r["externalID"] as? String
        applyCommon(r, into: m, in: context)
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
        case SyncConstants.RecordType.note:        NoteEvent.fetchByID(id, in: context)
        case SyncConstants.RecordType.baby:        Baby.fetchByID(id, in: context)
        case SyncConstants.RecordType.participant: Participant.fetchByID(id, in: context)
        case SyncConstants.RecordType.settings:    SharedSettings.fetchByID(id, in: context)
        case SyncConstants.RecordType.planSlot:    PlanSlot.fetchByID(id, in: context)
        case SyncConstants.RecordType.planOverride: PlanOverride.fetchByID(id, in: context)
        case SyncConstants.RecordType.activity:    ActivityEvent.fetchByID(id, in: context)
        case SyncConstants.RecordType.media:       MediaEvent.fetchByID(id, in: context)
        case SyncConstants.RecordType.check:       CheckEvent.fetchByID(id, in: context)
        case SyncConstants.RecordType.medication:  MedicationEvent.fetchByID(id, in: context)
        case SyncConstants.RecordType.healthCheck: HealthCheckEvent.fetchByID(id, in: context)
        case SyncConstants.RecordType.mood:        MoodEvent.fetchByID(id, in: context)
        case SyncConstants.RecordType.potty:       PottyEvent.fetchByID(id, in: context)
        case SyncConstants.RecordType.milestone:   MilestoneEvent.fetchByID(id, in: context)
        case SyncConstants.RecordType.staffNote:   StaffNoteEvent.fetchByID(id, in: context)
        default: nil
        }
    }

    /// Probes every model type for an id (used when only the id is known).
    /// Sequential returns, not one `??` chain — the existential upcasts made
    /// the chained expression un-type-checkable in reasonable time.
    private static func anyModel(id: UUID, in context: ModelContext) -> (any HasSyncID)? {
        if let m = FeedEvent.fetchByID(id, in: context) { return m }
        if let m = SleepEvent.fetchByID(id, in: context) { return m }
        if let m = DiaperEvent.fetchByID(id, in: context) { return m }
        if let m = NoteEvent.fetchByID(id, in: context) { return m }
        if let m = Participant.fetchByID(id, in: context) { return m }
        if let m = Baby.fetchByID(id, in: context) { return m }
        if let m = SharedSettings.fetchByID(id, in: context) { return m }
        if let m = PlanSlot.fetchByID(id, in: context) { return m }
        if let m = PlanOverride.fetchByID(id, in: context) { return m }
        if let m = ActivityEvent.fetchByID(id, in: context) { return m }
        if let m = MediaEvent.fetchByID(id, in: context) { return m }
        if let m = CheckEvent.fetchByID(id, in: context) { return m }
        if let m = MedicationEvent.fetchByID(id, in: context) { return m }
        if let m = HealthCheckEvent.fetchByID(id, in: context) { return m }
        if let m = MoodEvent.fetchByID(id, in: context) { return m }
        if let m = PottyEvent.fetchByID(id, in: context) { return m }
        if let m = MilestoneEvent.fetchByID(id, in: context) { return m }
        if let m = StaffNoteEvent.fetchByID(id, in: context) { return m }
        return nil
    }

    @discardableResult
    private static func insert<T: PersistentModel & HasSyncID>(_ model: T, id: UUID, in context: ModelContext) -> T {
        model.id = id
        context.insert(model)
        return model
    }
}

/// Lets RecordMapping set the id and cached server system fields on synced models.
/// `findByID` PROPAGATES store errors; `fetchByID` is the convenience form whose
/// nil means "not found" only for callers that don't need to tell the two apart
/// (the inbound upserts do — see `RecordMapping.apply`).
protocol HasSyncID: AnyObject {
    var id: UUID { get set }
    var ckSystemFields: Data? { get set }
    static func findByID(_ id: UUID, in context: ModelContext) throws -> Self?
}

extension HasSyncID {
    static func fetchByID(_ id: UUID, in context: ModelContext) -> Self? {
        try? findByID(id, in: context)
    }
}

// Each conformance hand-rolls the predicate fetch: #Predicate needs the concrete
// type (a protocol-generic key path won't compile), and an indexed fetchLimit-1
// lookup replaces the old load-the-whole-table scan.
extension Baby: HasSyncID {
    static func findByID(_ id: UUID, in context: ModelContext) throws -> Baby? {
        var d = FetchDescriptor<Baby>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try context.fetch(d).first
    }
}
extension FeedEvent: HasSyncID {
    static func findByID(_ id: UUID, in context: ModelContext) throws -> FeedEvent? {
        var d = FetchDescriptor<FeedEvent>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try context.fetch(d).first
    }
}
extension SleepEvent: HasSyncID {
    static func findByID(_ id: UUID, in context: ModelContext) throws -> SleepEvent? {
        var d = FetchDescriptor<SleepEvent>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try context.fetch(d).first
    }
}
extension DiaperEvent: HasSyncID {
    static func findByID(_ id: UUID, in context: ModelContext) throws -> DiaperEvent? {
        var d = FetchDescriptor<DiaperEvent>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try context.fetch(d).first
    }
}
extension NoteEvent: HasSyncID {
    static func findByID(_ id: UUID, in context: ModelContext) throws -> NoteEvent? {
        var d = FetchDescriptor<NoteEvent>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try context.fetch(d).first
    }
}
extension Participant: HasSyncID {
    static func findByID(_ id: UUID, in context: ModelContext) throws -> Participant? {
        var d = FetchDescriptor<Participant>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try context.fetch(d).first
    }
}
extension SharedSettings: HasSyncID {
    static func findByID(_ id: UUID, in context: ModelContext) throws -> SharedSettings? {
        var d = FetchDescriptor<SharedSettings>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try context.fetch(d).first
    }
}
extension PlanSlot: HasSyncID {
    static func findByID(_ id: UUID, in context: ModelContext) throws -> PlanSlot? {
        var d = FetchDescriptor<PlanSlot>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try context.fetch(d).first
    }
}
extension PlanOverride: HasSyncID {
    static func findByID(_ id: UUID, in context: ModelContext) throws -> PlanOverride? {
        var d = FetchDescriptor<PlanOverride>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try context.fetch(d).first
    }
}
extension ActivityEvent: HasSyncID {
    static func findByID(_ id: UUID, in context: ModelContext) throws -> ActivityEvent? {
        var d = FetchDescriptor<ActivityEvent>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try context.fetch(d).first
    }
}
extension MediaEvent: HasSyncID {
    static func findByID(_ id: UUID, in context: ModelContext) throws -> MediaEvent? {
        var d = FetchDescriptor<MediaEvent>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try context.fetch(d).first
    }
}
extension CheckEvent: HasSyncID {
    static func findByID(_ id: UUID, in context: ModelContext) throws -> CheckEvent? {
        var d = FetchDescriptor<CheckEvent>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try context.fetch(d).first
    }
}
extension MedicationEvent: HasSyncID {
    static func findByID(_ id: UUID, in context: ModelContext) throws -> MedicationEvent? {
        var d = FetchDescriptor<MedicationEvent>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try context.fetch(d).first
    }
}
extension HealthCheckEvent: HasSyncID {
    static func findByID(_ id: UUID, in context: ModelContext) throws -> HealthCheckEvent? {
        var d = FetchDescriptor<HealthCheckEvent>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try context.fetch(d).first
    }
}
extension MoodEvent: HasSyncID {
    static func findByID(_ id: UUID, in context: ModelContext) throws -> MoodEvent? {
        var d = FetchDescriptor<MoodEvent>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try context.fetch(d).first
    }
}
extension PottyEvent: HasSyncID {
    static func findByID(_ id: UUID, in context: ModelContext) throws -> PottyEvent? {
        var d = FetchDescriptor<PottyEvent>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try context.fetch(d).first
    }
}
extension MilestoneEvent: HasSyncID {
    static func findByID(_ id: UUID, in context: ModelContext) throws -> MilestoneEvent? {
        var d = FetchDescriptor<MilestoneEvent>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try context.fetch(d).first
    }
}
extension StaffNoteEvent: HasSyncID {
    static func findByID(_ id: UUID, in context: ModelContext) throws -> StaffNoteEvent? {
        var d = FetchDescriptor<StaffNoteEvent>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try context.fetch(d).first
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
extension NoteEvent: AnyEventModel {
    var babyRef: Baby? { get { baby } set { baby = newValue } }
}
extension ActivityEvent: AnyEventModel {
    var babyRef: Baby? { get { baby } set { baby = newValue } }
}
extension MediaEvent: AnyEventModel {
    var babyRef: Baby? { get { baby } set { baby = newValue } }
}
extension CheckEvent: AnyEventModel {
    var babyRef: Baby? { get { baby } set { baby = newValue } }
}
extension MedicationEvent: AnyEventModel {
    var babyRef: Baby? { get { baby } set { baby = newValue } }
}
extension HealthCheckEvent: AnyEventModel {
    var babyRef: Baby? { get { baby } set { baby = newValue } }
}
extension MoodEvent: AnyEventModel {
    var babyRef: Baby? { get { baby } set { baby = newValue } }
}
extension PottyEvent: AnyEventModel {
    var babyRef: Baby? { get { baby } set { baby = newValue } }
}
extension MilestoneEvent: AnyEventModel {
    var babyRef: Baby? { get { baby } set { baby = newValue } }
}
extension StaffNoteEvent: AnyEventModel {
    var babyRef: Baby? { get { baby } set { baby = newValue } }
}

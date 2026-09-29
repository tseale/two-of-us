import Foundation
import Observation
import SwiftData

/// Runtime home of the Brightwheel connection: loads the Keychain session at
/// launch, completes sign-in when the login web view produces a working
/// cookie, runs the daily import, and owns the sample-day preview. The
/// connection stays device-local (no shared CloudKit blob yet — see
/// docs/BRIGHTWHEEL-INTEGRATION.md §5); imported events sync like any other
/// event, so one connected phone covers the household.
@Observable @MainActor
final class BrightwheelManager {
    static let shared = BrightwheelManager()

    private(set) var session: BrightwheelSession?
    private(set) var lastSyncAt: Date?
    private(set) var isSyncing = false
    private let store: BrightwheelSessionStore
    private let client: BrightwheelAPIClient

    private static let autoImportKey = "brightwheel.autoImport"
    private static let lastSyncKey = "brightwheel.lastSyncAt"
    private static let syncInterval: TimeInterval = 10 * 60

    init(store: BrightwheelSessionStore = BrightwheelSessionStore(),
         client: BrightwheelAPIClient = BrightwheelAPIClient()) {
        self.store = store
        self.client = client
        session = store.load()
        autoImport = UserDefaults.standard.bool(forKey: Self.autoImportKey)
        lastSyncAt = UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date
    }

    var isConnected: Bool { session != nil }

    /// Whether foregrounding the app pulls today's daycare report by itself.
    /// Device-local (UserDefaults, not the synced settings): it configures
    /// this phone's fetching, and only one phone needs it on.
    var autoImport: Bool {
        didSet { UserDefaults.standard.set(autoImport, forKey: Self.autoImportKey) }
    }

    // MARK: Sign-in / out

    /// Called by the login sheet with a cookie candidate harvested from the
    /// web view. Verifies it against `/users/me` (the sign-in page sets
    /// cookies before authentication too, so possession alone proves nothing)
    /// and resolves the student roster. Throws `.unauthorized` for a
    /// not-actually-signed-in cookie — the sheet keeps waiting.
    func completeSignIn(cookie: String) async throws -> BrightwheelSession {
        let user = try await client.me(cookie: cookie)
        let students = try await client.students(cookie: cookie, guardianID: user.objectID)
        guard let student = students.first else {
            throw BrightwheelAPIError.decoding
        }
        let session = BrightwheelSession(
            cookie: cookie,
            email: user.email ?? "",
            guardianID: user.objectID,
            studentID: student.objectID,
            studentName: student.displayName,
            signedInAt: .now
        )
        store.save(session)
        self.session = session
        return session
    }

    func disconnect() {
        store.clear()
        session = nil
    }

    // MARK: Import

    /// App-foreground hook (mirrors `SnooSyncCoordinator.syncOnForeground`):
    /// when connected with auto-import on, pull today's report and import
    /// whatever is new. Throttled; failures are logged and left alone — the
    /// next foreground retries, and Settings' debug fetch diagnoses.
    func syncOnForeground(context: ModelContext) {
        guard isConnected, autoImport, !isSyncing else { return }
        if let last = lastSyncAt, Date.now.timeIntervalSince(last) < Self.syncInterval { return }
        Task { await syncNow(context: context) }
    }

    /// One import pass over today's activities. Returns the summary for the
    /// Settings "Sync now" path; nil when not connected or the fetch failed.
    @discardableResult
    func syncNow(context: ModelContext) async -> BrightwheelImporter.Summary? {
        guard let session, !isSyncing else { return nil }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let activities = try await client.activities(
                cookie: session.cookie, studentID: session.studentID, day: .now)
            let summary = BrightwheelImporter(context: context).importActivities(activities)
            markSynced()
            if summary.imported > 0 {
                AppLog.store.info("Brightwheel: imported \(summary.imported) event(s)")
            }
            return summary
        } catch {
            AppLog.store.error("Brightwheel sync failed: \(error)")
            return nil
        }
    }

    // MARK: Sample day (preview before Miller's first real day)

    /// Imports the simulated daycare day through the exact pipeline real data
    /// will use. Safe to tap twice — deterministic ids make it a no-op.
    ///
    /// Real syncs only ever see activities that already happened; the sample
    /// keeps that honest (EventStore clamps future timestamps to "now", which
    /// would smear an afternoon of events onto the current minute). Loaded
    /// before mid-morning, today's day-so-far would be nearly empty, so the
    /// sample falls back to yesterday's full report — every event lands
    /// exactly where the schedule says.
    @discardableResult
    func loadSampleDay(context: ModelContext, now: Date = .now) -> BrightwheelImporter.Summary {
        let todaySoFar = BrightwheelMockDay.activities(for: now)
            .filter { ($0.when ?? .distantFuture) <= now }
        let activities: [BrightwheelActivity]
        if todaySoFar.count >= 4 {
            activities = todaySoFar
        } else {
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
            activities = BrightwheelMockDay.activities(for: yesterday)
        }
        let summary = BrightwheelImporter(context: context).importActivities(activities)
        markSynced()
        return summary
    }

    /// Soft-deletes every event the sample day created (and only those — the
    /// mock id prefix scopes it), on this phone and, via sync, the other one.
    func removeSampleDay(context: ModelContext) -> Int {
        let store = EventStore(context: context)
        let source = EventSource.brightwheel.rawValue
        var removed = 0

        func sweep<T: PersistentModel & SoftDeletable>(_ type: T.Type,
                                                       _ externalID: (T) -> String?,
                                                       _ predicate: Predicate<T>) {
            let events = (try? context.fetch(FetchDescriptor<T>(predicate: predicate))) ?? []
            for event in events where externalID(event)?.hasPrefix(BrightwheelMockDay.idPrefix) == true {
                store.softDelete(event)
                removed += 1
            }
        }

        sweep(FeedEvent.self, { $0.externalID },
              #Predicate { $0.deletedAt == nil && $0.sourceRaw == source })
        sweep(SleepEvent.self, { $0.externalID },
              #Predicate { $0.deletedAt == nil && $0.sourceRaw == source })
        sweep(DiaperEvent.self, { $0.externalID },
              #Predicate { $0.deletedAt == nil && $0.sourceRaw == source })
        sweep(NoteEvent.self, { $0.externalID },
              #Predicate { $0.deletedAt == nil && $0.sourceRaw == source })
        sweep(ActivityEvent.self, { $0.externalID },
              #Predicate { $0.deletedAt == nil && $0.sourceRaw == source })
        sweep(MediaEvent.self, { $0.externalID },
              #Predicate { $0.deletedAt == nil && $0.sourceRaw == source })
        sweep(CheckEvent.self, { $0.externalID },
              #Predicate { $0.deletedAt == nil && $0.sourceRaw == source })
        sweep(MedicationEvent.self, { $0.externalID },
              #Predicate { $0.deletedAt == nil && $0.sourceRaw == source })
        sweep(HealthCheckEvent.self, { $0.externalID },
              #Predicate { $0.deletedAt == nil && $0.sourceRaw == source })
        sweep(MoodEvent.self, { $0.externalID },
              #Predicate { $0.deletedAt == nil && $0.sourceRaw == source })
        sweep(PottyEvent.self, { $0.externalID },
              #Predicate { $0.deletedAt == nil && $0.sourceRaw == source })
        sweep(MilestoneEvent.self, { $0.externalID },
              #Predicate { $0.deletedAt == nil && $0.sourceRaw == source })
        sweep(StaffNoteEvent.self, { $0.externalID },
              #Predicate { $0.deletedAt == nil && $0.sourceRaw == source })
        return removed
    }

    // MARK: Debug fetch (phase-1 console, kept for diagnosing the live API)

    func fetchTodayRawJSON() async throws -> String {
        guard let session else { throw BrightwheelAPIError.unauthorized }
        return try await client.activitiesRawJSON(
            cookie: session.cookie, studentID: session.studentID, day: .now)
    }

    private func markSynced() {
        lastSyncAt = .now
        UserDefaults.standard.set(lastSyncAt, forKey: Self.lastSyncKey)
    }
}

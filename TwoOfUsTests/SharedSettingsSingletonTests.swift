import XCTest
import SwiftData
@testable import TwoOfUs

/// The SharedSettings "singleton" is only an intent — a reinstall that
/// re-onboards into an existing zone can mint a second row (the upsert is by
/// UUID). These tests lock the two defenses: every reader picks the same
/// canonical row on every device, and the SyncManager merge pass folds
/// duplicates back into one.
@MainActor
final class SharedSettingsSingletonTests: XCTestCase {
    private var container: ModelContainer!
    private var manager: SyncManager!
    private var savedDefaults: [String: Any?] = [:]

    /// The merge pass parks its save/delete into the hold queues (no engine in
    /// the test host) — snapshot and restore them, never just delete: the test
    /// host is the real app and a dev device may hold real parked writes.
    private let queueKeys = ["sync.pendingSharedSaves", "sync.pendingSharedDeletes",
                             "sync.pendingPrivateSaves", "sync.pendingPrivateDeletes"]

    override func setUp() {
        super.setUp()
        container = AppModelContainer.make(inMemory: true)
        manager = SyncManager(modelContainer: container)
        savedDefaults = Dictionary(uniqueKeysWithValues: queueKeys.map {
            ($0, UserDefaults.standard.object(forKey: $0))
        })
        queueKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    override func tearDown() {
        for (key, value) in savedDefaults {
            if let value { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        manager = nil
        container = nil
        super.tearDown()
    }

    private func uuid(_ hex: Character) -> UUID {
        UUID(uuidString: String(repeating: String(hex), count: 8) + "-0000-0000-0000-000000000000")!
    }

    func testCanonicalIsOrderIndependent() {
        let low = SharedSettings(id: uuid("1"))
        let high = SharedSettings(id: uuid("f"))
        XCTAssertEqual(SharedSettings.canonical([low, high])?.id, low.id)
        XCTAssertEqual(SharedSettings.canonical([high, low])?.id, low.id,
                       "both devices must converge on the same row regardless of fetch order")
        XCTAssertNil(SharedSettings.canonical([]))
    }

    func testMergeFoldsCredentialsIntoCanonicalRow() throws {
        let context = container.mainContext
        let winner = SharedSettings(id: uuid("1"))
        let loser = SharedSettings(id: uuid("f"))
        loser.snooCredentials = #"{"refreshToken":"rt","email":"t@e.com"}"#
        context.insert(winner)
        context.insert(loser)
        try context.save()

        manager.mergeDuplicateSettingsIfNeeded()

        let rows = try context.fetch(FetchDescriptor<SharedSettings>())
        XCTAssertEqual(rows.count, 1, "duplicates must fold back into a single row")
        XCTAssertEqual(rows.first?.id, winner.id)
        XCTAssertEqual(rows.first?.snooCredentials, #"{"refreshToken":"rt","email":"t@e.com"}"#,
                       "a SNOO connection published onto the doomed row must survive the merge")
    }

    func testMergeKeepsWinnersCredentialsWhenBothRowsHaveThem() throws {
        let context = container.mainContext
        let winner = SharedSettings(id: uuid("1"))
        winner.snooCredentials = #"{"refreshToken":"keep","email":"t@e.com"}"#
        let loser = SharedSettings(id: uuid("f"))
        loser.snooCredentials = #"{"refreshToken":"drop","email":"t@e.com"}"#
        context.insert(winner)
        context.insert(loser)
        try context.save()

        manager.mergeDuplicateSettingsIfNeeded()

        let rows = try context.fetch(FetchDescriptor<SharedSettings>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.snooCredentials, #"{"refreshToken":"keep","email":"t@e.com"}"#,
                       "the canonical row's own connection wins when both rows carry one")
    }

    func testMergeIsANoOpForASingleRow() throws {
        let context = container.mainContext
        let only = SharedSettings(id: uuid("1"))
        context.insert(only)
        try context.save()

        manager.mergeDuplicateSettingsIfNeeded()

        XCTAssertEqual(try context.fetch(FetchDescriptor<SharedSettings>()).count, 1)
        for key in queueKeys {
            XCTAssertNil(UserDefaults.standard.object(forKey: key),
                         "a healthy store must not enqueue anything (\(key))")
        }
    }
}

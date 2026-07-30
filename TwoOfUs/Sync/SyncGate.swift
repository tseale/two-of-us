import Foundation

/// Decides whether this process is allowed to sync at all.
///
/// Why this exists: dev/test fixtures (`-seedSampleData`, `-wipeStore`, …)
/// mutate the REAL App Group store, and the sync layer's one-shot bootstrap
/// (`bootstrapReconcileIfNeeded`) uploads every local record it finds. Run
/// against a simulator or device signed into a real iCloud account — a UI-test
/// pass, an App Store screenshot capture — that combination published a week
/// of seeded "Mom"/"Dad" sample events straight into the family's CloudKit
/// zone, which both parents then pulled as ghost logs. Sync is refused
/// outright when either hazard is present:
/// - **any simulator build** — real sync testing needs two physical iPhones
///   (docs/NOTIFICATIONS.md); a simulator's only sync traffic is a developer's
///   fixtures and pokes, and none of it belongs in production data;
/// - **any fixture launch argument** — a screenshot/UI-test run on a real
///   device must never upload its seed data either.
enum SyncGate {
    /// Launch arguments that mutate the real store with fixture data (see
    /// `TwoOfUsApp.init`). `-previewJoin`/`-resetSetup` don't insert records,
    /// but they only ever accompany dev runs — blocked for the same reason.
    static let fixtureArguments: Set<String> = [
        "-seedSampleData", "-wipeStore", "-previewJoin", "-resetSetup", "-onboardingPage", "-uiScreen"
    ]

    /// Persisted marker: fixture rows were seeded into the REAL on-disk store
    /// at some point (`-seedSampleData` on a device). The seeding PROCESS is
    /// blocked by the argument check, but the rows outlive it — and a later
    /// argument-less launch would upload them the moment anything resets the
    /// bootstrap flag (delete-everything re-onboard, zone recovery). The taint
    /// keeps sync off on that device until `-wipeStore` empties the store.
    static let taintKey = "sync.fixtureTainted"

    /// Human-readable reason sync is blocked for this process, or nil to allow.
    static var blockReason: String? {
        reason(arguments: ProcessInfo.processInfo.arguments, isSimulator: isSimulator,
               fixtureTainted: UserDefaults.standard.bool(forKey: taintKey))
    }

    /// Records/clears the taint for this launch's arguments (called from
    /// `TwoOfUsApp.init` right after the fixture args are applied): seeding
    /// taints, a wipe alone restores a clean store. Order matters when both
    /// are passed — the wipe runs first, the seed re-dirties.
    static func recordFixtureTaint(arguments: [String] = ProcessInfo.processInfo.arguments) {
        if arguments.contains("-wipeStore") {
            UserDefaults.standard.removeObject(forKey: taintKey)
        }
        if arguments.contains("-seedSampleData") {
            UserDefaults.standard.set(true, forKey: taintKey)
        }
    }

    /// Pure form for tests.
    static func reason(arguments: [String], isSimulator: Bool, fixtureTainted: Bool = false) -> String? {
        if isSimulator { return "simulator build" }
        if let arg = arguments.first(where: fixtureArguments.contains) {
            return "fixture launch argument \(arg)"
        }
        if fixtureTainted { return "store holds fixture data from a previous -seedSampleData run (relaunch with -wipeStore to clear)" }
        return nil
    }

    private static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
}

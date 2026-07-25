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

    /// Human-readable reason sync is blocked for this process, or nil to allow.
    static var blockReason: String? {
        reason(arguments: ProcessInfo.processInfo.arguments, isSimulator: isSimulator)
    }

    /// Pure form for tests.
    static func reason(arguments: [String], isSimulator: Bool) -> String? {
        if isSimulator { return "simulator build" }
        if let arg = arguments.first(where: fixtureArguments.contains) {
            return "fixture launch argument \(arg)"
        }
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

import UIKit
import CloudKit
import WidgetKit

/// Drives cross-device freshness and CloudKit sharing:
/// - registers for the silent pushes CKSyncEngine uses to sync,
/// - forwards remote notifications to `SyncManager` so changes (incl. the other
///   parent's) pull in the background and refresh widgets without opening the app,
/// - accepts CloudKit share invitations (the joining parent),
/// - drains widget/Siri-origin writes and reconciles the Live Activity on foreground.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        await MainActor.run { SyncManager.shared?.handleRemoteNotification() }
        // Reload after a brief moment so a just-imported change is reflected.
        WidgetCenter.shared.reloadAllTimelines()
        return .newData
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        WidgetCenter.shared.reloadAllTimelines()
        MainActor.assumeIsolated {
            SyncManager.shared?.drainExtensionQueue()
        }
        guard let logger = QuickLogger.make() else { return }
        SleepActivityManager.reconcile(
            babyName: logger.babyName ?? "Miller",
            activeSleepStartedAt: logger.activeSleep?.startedAt
        )
        // Re-arm the feed alarm off whatever's in the store now — this catches
        // feeds logged via widget/Siri or synced from the co-parent's device.
        let lastFeed = logger.lastFeedDate
        let interval = logger.targetFeedInterval
        Task { await FeedAlarmManager.reschedule(lastFeed: lastFeed, interval: interval) }
    }

    /// The joining parent tapped the share invite — accept it and start syncing
    /// the owner's shared zone.
    func application(_ application: UIApplication,
                     userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task {
            do {
                try await SyncConstants.container.accept(metadata)
                await MainActor.run { SyncManager.shared?.didAcceptShare() }
            } catch {
                print("Failed to accept CloudKit share: \(error)")
            }
        }
    }

    // Silent-push registration callbacks (CKSyncEngine manages the token/subscriptions).
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {}
    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Remote notification registration failed: \(error)")
    }
}

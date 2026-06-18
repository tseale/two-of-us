import UIKit
import CloudKit
import WidgetKit
import UserNotifications

/// Drives cross-device freshness and CloudKit sharing:
/// - registers for the silent pushes CKSyncEngine uses to sync,
/// - forwards remote notifications to `SyncManager` so changes (incl. the other
///   parent's) pull in the background and refresh widgets without opening the app,
/// - accepts CloudKit share invitations (the joining parent),
/// - drains widget/Siri-origin writes and reconciles the Live Activity on foreground.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()

        // Local notifications: become the delegate so action buttons route to us,
        // and register the categories that give those buttons their layout.
        UNUserNotificationCenter.current().delegate = self
        NotificationManager.registerCategories()
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
        let lastFeed = logger.lastFeed?.timestamp
        let interval = logger.targetFeedInterval
        Task { await FeedAlarmManager.reschedule(lastFeed: lastFeed, interval: interval) }

        // Re-arm the gentle local reminders + daily summary off the same state.
        NotificationManager.refreshScheduledReminders()
        NotificationManager.refreshDailyMilestone()
    }

    // MARK: UNUserNotificationCenterDelegate

    /// A tapped action button (or the notification itself). Logging actions run in
    /// the background via `NotificationManager`; the default tap just opens the app.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run { NotificationManager.handle(response) }
    }

    /// Foreground presentation: show the banner in the list, but stay silent —
    /// the app never plays a sound (haptics confirm in-app actions instead).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
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

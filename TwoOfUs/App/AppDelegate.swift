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
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        SyncManager.shared?.handleRemoteNotification()
        // Reload after a brief moment so a just-imported change is reflected.
        WidgetCenter.shared.reloadAllTimelines()
        completionHandler(.newData)
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        WidgetCenter.shared.reloadAllTimelines()
        MainActor.assumeIsolated {
            SyncManager.shared?.drainExtensionQueue()
        }
        guard let logger = QuickLogger.make() else { return }
        let babyName = logger.babyName ?? "Baby"
        SleepActivityManager.reconcile(
            babyName: babyName,
            activeSleepStartedAt: logger.activeSleep?.startedAt
        )
        // Re-arm the feed alarm off whatever's in the store now — this catches
        // feeds logged via widget/Siri or synced from the co-parent's device.
        let lastFeed = logger.lastFeed?.timestamp
        let interval = logger.targetFeedInterval
        Task { await FeedAlarmManager.reschedule(babyName: babyName, lastFeed: lastFeed, interval: interval) }
    }

    /// Scene-based apps (every SwiftUI-lifecycle app) receive CloudKit share
    /// acceptance on the *scene* delegate, not the app delegate — without
    /// vending our own delegate class here, the joining parent's link tap would
    /// be silently dropped. SwiftUI still owns the window; `SceneDelegate`
    /// deliberately creates none.
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }

    /// Safety net for non-scene delivery; on iOS the scene-delegate variant in
    /// `SceneDelegate` is the path that actually fires.
    func application(_ application: UIApplication,
                     userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        ShareAcceptance.shared.accept(metadata)
    }

    // Silent-push registration callbacks (CKSyncEngine manages the token/subscriptions).
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {}
    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Remote notification registration failed: \(error)")
    }
}

/// Receives the joining parent's share-link tap in both launch shapes: warm
/// (app already running → `userDidAcceptCloudKitShareWith`) and cold (the link
/// launches the app → the metadata rides in on the connection options).
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            ShareAcceptance.shared.accept(metadata)
        }
    }

    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        ShareAcceptance.shared.accept(metadata)
    }
}

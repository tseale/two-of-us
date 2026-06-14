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
        // Sync must exist from the very first moment of ANY launch — including
        // a background relaunch for a silent push, where no SwiftUI scene ever
        // connects and `TwoOfUsApp.configure()` never runs.
        MainActor.assumeIsolated {
            SyncManager.bootstrap(container: AppModelContainer.shared)
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Complete only after the engines actually fetched, so iOS keeps the
        // process alive long enough for the changes to land — and the widgets
        // reload with the co-parent's data actually in the store. Reporting
        // .noData when nothing could run keeps iOS's push budget honest.
        Task { @MainActor in
            let fetched = await SyncManager.shared?.handleRemoteNotification() ?? false
            WidgetCenter.shared.reloadAllTimelines()
            completionHandler(fetched ? .newData : .noData)
        }
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        WidgetCenter.shared.reloadAllTimelines()
        MainActor.assumeIsolated {
            // Silent pushes are heavily throttled/coalesced by iOS — a manual
            // fetch on every foreground keeps "within ~10 seconds" honest. Also
            // restarts engines if iCloud was signed into while we were inactive.
            SyncManager.shared?.start()
            // Reload widgets again once the foreground fetch actually lands, so a
            // glance reflects the co-parent's just-synced changes rather than the
            // pre-fetch snapshot. (The in-app UI self-heals via reactive @Query.)
            Task {
                await SyncManager.shared?.handleRemoteNotification()
                WidgetCenter.shared.reloadAllTimelines()
            }
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
        AppLog.sync.error("Remote notification registration failed: \(error.localizedDescription, privacy: .public)")
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

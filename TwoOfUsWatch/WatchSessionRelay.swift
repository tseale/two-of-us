import Foundation
import WatchConnectivity

/// The watch half of the complication-freshness nudge (see the phone's
/// `WatchAppStatus`): the paired phone sends a content-free
/// `transferCurrentComplicationUserInfo` whenever a feed/sleep lands on the
/// server, watchOS launches this app in the background to deliver it, and the
/// handler runs the exact fetch the app would run on foreground activation.
/// The fetch applies changes into the App Group store and reloads the
/// complication timelines (`WatchSyncManager.applyFetchedChanges`).
///
/// Data never crosses this channel — the payload is ignored; it's a doorbell,
/// not a delivery. CloudKit remains the single source of truth, and the
/// background-refresh chain in `TwoOfUsWatchApp` stays as the floor for when
/// the phone is off, out of budget, or unreachable.
final class WatchSessionRelay: NSObject, WCSessionDelegate {
    static let shared = WatchSessionRelay()

    private override init() {
        super.init()
    }

    /// Called once at app init (all launches, including background delivery
    /// launches — watchOS instantiates the App struct for those too).
    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func fetchAndRefresh() {
        Task { @MainActor in
            guard !WatchModelContainer.isDemoRun else { return }
            WatchSyncManager.bootstrap(container: WatchModelContainer.shared)
            await WatchSyncManager.shared?.fetchNow()
        }
    }

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: (any Error)?) {
        if let error {
            AppLog.sync.error("Watch WCSession activation failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Complication transfers arrive here. Also catches plain userInfo
    /// transfers (the phone's fallback when the complication isn't on the
    /// active face) — same response either way: go fetch.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        AppLog.sync.log("Watch woken by phone nudge — fetching")
        fetchAndRefresh()
    }
}

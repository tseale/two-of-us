import Foundation
import WatchConnectivity
import Observation

/// Read-only view of the paired Apple Watch for the Settings row.
///
/// Activates a `WCSession` purely to READ `isPaired`/`isWatchAppInstalled`.
/// The watch app deliberately has NO Watch Connectivity data channel — both
/// devices converge through CloudKit — so nothing here may ever send or
/// receive messages; this class exists only so Settings can answer "is the
/// watch app on my watch?".
@MainActor
@Observable
final class WatchAppStatus: NSObject, WCSessionDelegate {
    static let shared = WatchAppStatus()

    enum State {
        case unavailable    // no Watch Connectivity on this device (iPad)
        case checking       // session still activating
        case notPaired
        case notInstalled
        case installed

        /// Trailing status text for the row; nil hides the row entirely.
        var label: String? {
            switch self {
            case .unavailable: nil
            case .checking: "—"
            case .notPaired: "No watch paired"
            case .notInstalled: "Not installed"
            case .installed: "Installed"
            }
        }
    }

    private(set) var state: State = .checking

    private override init() {
        super.init()
        guard WCSession.isSupported() else {
            state = .unavailable
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func refresh(_ session: WCSession) {
        if !session.isPaired {
            state = .notPaired
        } else if !session.isWatchAppInstalled {
            state = .notInstalled
        } else {
            state = .installed
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        Task { @MainActor in
            guard activationState == .activated else { return }
            self.refresh(session)
        }
    }

    /// Fires when the watch pairs/unpairs or the app is (un)installed on it.
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.refresh(session) }
    }

    // Required by the protocol for multi-watch handover; nothing to do — the
    // next activation re-reads the state.
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
}

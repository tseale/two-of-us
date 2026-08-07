import Foundation
import WatchConnectivity
import Observation
import os

/// The phone's Watch Connectivity session: pairing status for the Settings
/// row, plus the complication-freshness nudge.
///
/// **Data still never crosses this channel.** Both devices converge through
/// CloudKit only — the one thing sent here is `transferCurrentComplicationUserInfo`,
/// a content-free "something changed, fetch now" wake. It exists because
/// watchOS won't run the watch app in the background on its own more than
/// ~4 times an hour: without a nudge, a feed logged on a phone can sit in
/// CloudKit for up to half an hour before the complication's background-refresh
/// chain picks it up. The nudge wakes the watch app promptly (budget: 50/day
/// while the complication is on the active face); the watch then fetches from
/// CloudKit exactly as it would have anyway.
///
/// Reaching the CO-PARENT's watch works by relay: their phone → CloudKit →
/// silent push to THIS phone → this phone applies the changes and nudges its
/// own paired watch. A phone can only ever nudge the watch it is paired with.
@MainActor
@Observable
final class WatchAppStatus: NSObject, WCSessionDelegate {
    static let shared = WatchAppStatus()

    private static let log = Logger(subsystem: "com.taylorseale.twoofus", category: "watchRelay")

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

    /// Debounce for the nudge: one fetched batch can apply a handful of records
    /// back-to-back, and each transfer spends scarce budget (50/day). A short
    /// coalescing window turns a burst into one wake without materially
    /// delaying it.
    private var pendingNudge: Task<Void, Never>?

    private override init() {
        super.init()
        guard WCSession.isSupported() else {
            state = .unavailable
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Idempotent touch-point so app launch can force the lazy singleton into
    /// existence — the session must be activated BEFORE the first sync event
    /// wants to nudge, not on the first visit to Settings.
    func activate() {}

    /// Wake the paired watch so its complication re-fetches. Fire-and-forget:
    /// every failure mode here is "the watch finds out via the background
    /// refresh chain instead", so nothing propagates.
    func nudgeComplication() {
        pendingNudge?.cancel()
        pendingNudge = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.sendNudge()
        }
    }

    private func sendNudge() {
        let session = WCSession.default
        guard WCSession.isSupported(),
              session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled else { return }
        // No complication on the active face → no high-priority budget, and a
        // plain userInfo transfer would only arrive on the next app open —
        // which is exactly when the watch fetches anyway. Skip.
        guard session.isComplicationEnabled else { return }
        guard session.remainingComplicationUserInfoTransfers > 0 else {
            Self.log.log("Complication nudge skipped: daily transfer budget exhausted")
            return
        }
        // Content-free by design: the payload is the wake itself. The watch
        // fetches CloudKit for the actual data, so a lost/coalesced transfer
        // costs nothing but latency.
        session.transferCurrentComplicationUserInfo(["nudge": true])
        Self.log.log("Nudged watch complication (\(session.remainingComplicationUserInfoTransfers, privacy: .public) transfers left today)")
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

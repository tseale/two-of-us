import SwiftUI

/// Parses `twoofus://` URLs from a tapped home-screen widget into a pending
/// in-app action. The Feed and Diaper tiles deep-link here to open their log
/// sheet; the Sleep tile toggles in-process via `ToggleSleepIntent` and never
/// routes through here (so tapping it never launches the app).
@Observable
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()

    /// The log sheets a widget tap can open. Raw values match the URL path
    /// component, e.g. `twoofus://log/feed`.
    enum LogTarget: String { case feed, diaper }

    /// Queue of log sheets widget taps asked us to present. `HomeView` dequeues
    /// one on each `onChange` / `onAppear`. Two fast taps no longer lose the first
    /// action (the second tap enqueues rather than overwriting the first).
    private(set) var pendingLogs: [LogTarget] = []

    /// Mirrors the head of the queue for `onChange` observation — SwiftUI fires
    /// onChange when this value changes, which happens on every enqueue and dequeue.
    var pendingLog: LogTarget? { pendingLogs.first }

    private init() {}

    /// Stages the action for a recognized `twoofus://log/<kind>` URL.
    /// - Returns: true if the URL was a deep link we handle, false otherwise.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard url.scheme == "twoofus", url.host == "log" else {
            AppLog.deeplink.debug("Ignored unrecognized URL: \(url.absoluteString, privacy: .public)")
            return false
        }
        // twoofus://log/feed  ·  twoofus://log/diaper
        guard let kind = url.pathComponents.last(where: { $0 != "/" }),
              let target = LogTarget(rawValue: kind) else {
            AppLog.deeplink.warning("Unrecognized log target in URL: \(url.absoluteString, privacy: .public)")
            return false
        }
        pendingLogs.append(target)
        return true
    }

    /// Removes and returns the next pending action, or nil if the queue is empty.
    func dequeue() -> LogTarget? {
        guard !pendingLogs.isEmpty else { return nil }
        return pendingLogs.removeFirst()
    }

    /// Clears all pending actions. Used in tests and teardown.
    func clearAll() { pendingLogs.removeAll() }
}

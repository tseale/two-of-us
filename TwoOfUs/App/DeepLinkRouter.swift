import SwiftUI

/// Parses `twoofus://` URLs from a tapped home-screen widget into a pending
/// in-app action. The Feed and Diaper tiles deep-link here to open their log
/// sheet; the Sleep tile toggles in-process via `ToggleSleepIntent` and never
/// routes through here (so tapping it never launches the app).
@Observable
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()

    /// The log sheet a tapped widget asked us to present. `HomeView` consumes
    /// and clears it — `onChange` for a warm launch, `onAppear` for a cold one.
    var pendingLog: LogTarget?

    private init() {}

    /// The log sheets a widget tap can open. Raw values match the URL path
    /// component, e.g. `twoofus://log/feed`.
    enum LogTarget: String { case feed, diaper }

    /// Stages the action for a recognized `twoofus://log/<kind>` URL.
    /// - Returns: true if the URL was a deep link we handle, false otherwise.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard url.scheme == "twoofus", url.host == "log" else { return false }
        // twoofus://log/feed  ·  twoofus://log/diaper
        guard let kind = url.pathComponents.last(where: { $0 != "/" }),
              let target = LogTarget(rawValue: kind) else { return false }
        pendingLog = target
        return true
    }
}

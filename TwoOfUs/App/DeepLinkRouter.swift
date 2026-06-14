import Foundation

/// A pending action handed in from outside the app — a widget tap. `HomeView`
/// observes `pending` and runs it (present the matching log sheet, or start the
/// sleep timer), then clears it.
///
/// The small home widgets and lock-screen accessories deep-link via
/// `twoofus://log/<kind>`; the Live Activity uses `twoofus://home` (no action,
/// just opens the app — handled here as a no-op).
@Observable
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()
    private init() {}

    enum Action: String {
        case feed, diaper, sleep
    }

    /// Set by `onOpenURL`, consumed by `HomeView`.
    var pending: Action?

    /// Parse an incoming URL and stage the action. Unknown URLs (e.g.
    /// `twoofus://home`) are ignored — the app simply comes to the foreground.
    func handle(_ url: URL) {
        guard url.scheme == "twoofus", url.host == "log",
              let raw = url.pathComponents.last,
              let action = Action(rawValue: raw)
        else { return }
        pending = action
    }
}

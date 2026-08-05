import Foundation

/// Hands off to the eufy app for a look at the nursery camera.
///
/// There is deliberately no camera-specific destination here: eufy's live-view
/// screen is not an exported entry point, and the only URLs their app answers
/// are a support page, two marketing webviews, and OAuth callbacks. Opening the
/// app is the whole of what's available — the parent taps through from there.
/// Full findings in docs/BABY-CAM-INTEGRATION.md.
enum BabyCamLink {
    /// Probed in order. `eufysecurity` is the unified eufy app; the two eufy
    /// Baby schemes trail it as a cushion for a phone still on the legacy app,
    /// which eufy is folding into the unified one. Drop them once both phones
    /// have migrated.
    static let schemes = ["eufysecurity", "eufybaby", "eufycare"]

    /// The unified eufy app, for when none of the schemes resolve. Must stay the
    /// canonical slug form: iOS matches universal links against the App Store's
    /// association file before making any request, so the slugless
    /// `/us/app/id1424956516` (a 301 to this) can land in Safari instead of
    /// opening the App Store app.
    static let appStore = URL(string: "https://apps.apple.com/us/app/eufy/id1424956516")!

    /// First installed app wins, App Store otherwise. `canOpen` is injected
    /// because `UIApplication.canOpenURL` needs a real device — passing it in
    /// keeps the ordering and fallback testable on the simulator.
    static func destination(canOpen: (URL) -> Bool) -> URL {
        schemes
            .compactMap { URL(string: "\($0)://") }
            .first(where: canOpen) ?? appStore
    }
}

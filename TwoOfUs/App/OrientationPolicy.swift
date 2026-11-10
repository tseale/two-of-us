import UIKit

/// Which orientations a window may take.
///
/// Slab iPhones stay portrait-only, exactly as before. iPad keeps every
/// orientation. A foldable's displays are close to square — iPhone Duo's are
/// 466 × 678 pt outside and 951 × 669 pt inside, against ≈ 2.17 : 1 on every
/// slab iPhone (the squarest, iPhone SE, is 1.78) — and its outer display is
/// the one stood on a nightstand like a tent, so there the app turns with the
/// phone instead of lying on its side. (The inner display ignores orientation
/// locks altogether; this only changes what the outer one does.)
@MainActor
enum OrientationPolicy {
    /// Long ÷ short side below which a phone display counts as a foldable's.
    static let foldableAspectCeiling: CGFloat = 1.6

    static func supportedOrientations(for window: UIWindow?) -> UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .pad { return .all }
        guard let screen = window?.windowScene?.screen else { return .portrait }
        let size = screen.bounds.size
        let long = max(size.width, size.height)
        let short = min(size.width, size.height)
        guard short > 0, long / short < foldableAspectCeiling else { return .portrait }
        return .allButUpsideDown
    }
}

import SwiftUI
import UIKit

/// The app's own icon, for the Settings About footer. Loads the actual installed
/// icon at runtime so it always tracks whatever icon ships; falls back to the
/// brand `CradleMark` (the mark the icon is built from) on the dark ground if the
/// bundle icon can't be resolved.
struct AppIconBadge: View {
    var size: CGFloat = 60

    var body: some View {
        Group {
            if let icon = Bundle.main.appIconImage {
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFill()
            } else {
                CradleMark(size: size * 0.74)
                    .frame(width: size, height: size)
                    .background(AppColor.nightInk)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .strokeBorder(AppColor.separator.opacity(0.4), lineWidth: 0.5)
        )
        .accessibilityHidden(true)
    }
}

extension Bundle {
    /// The app's primary icon as installed (the largest rasterized variant iOS
    /// wrote into `CFBundleIcons`). Nil if the icon isn't a classic asset-catalog
    /// AppIcon (e.g. a pure Icon Composer bundle) — callers should fall back.
    var appIconImage: UIImage? {
        guard let icons = infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String],
              let lastName = files.last else { return nil }
        return UIImage(named: lastName)
    }
}

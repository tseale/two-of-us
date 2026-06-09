import SwiftUI

/// The tinted rounded-square SF Symbol that sits before a settings row's title —
/// the cue Apple Settings, Things, and Flighty all use to make a plain list read
/// as crafted. Works as the label of a `Toggle`, `Picker`, `NavigationLink`, or a
/// plain row.
struct SettingsIconLabel: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label {
            Text(title)
        } icon: {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(tint)
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
        }
    }
}

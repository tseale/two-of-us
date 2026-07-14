import SwiftUI

/// Reusable horizontal palette picker for a participant's color.
/// Shared by onboarding, the co-parent join flow, and profile editing.
struct ParticipantColorPicker: View {
    @Binding var selection: String
    var label: String = "Your color"

    /// Spoken names for the palette — VoiceOver users pick "Teal", not a hex code.
    private static let colorNames: [String: String] = [
        "5AC8B8": "Teal",
        "8E8EFF": "Periwinkle",
        "F5B971": "Amber",
        "FF8FA3": "Pink",
        "7FB2FF": "Blue",
        "B6E36B": "Green",
    ]

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
            Spacer(minLength: 8)
            ForEach(ParticipantColors.palette, id: \.self) { hex in
                let selected = selection == hex
                Button { selection = hex } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 28, height: 28)
                        .overlay(Circle().stroke(AppColor.text, lineWidth: selected ? 2 : 0))
                        // The visible swatch stays 28pt; the tap target doesn't.
                        .frame(width: 34, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.colorNames[hex] ?? "Color")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
    }
}

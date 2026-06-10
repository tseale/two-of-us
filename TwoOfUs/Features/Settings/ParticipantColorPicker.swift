import SwiftUI

/// Reusable horizontal palette picker for a participant's color.
/// Shared by onboarding, the co-parent join flow, and profile editing.
struct ParticipantColorPicker: View {
    @Binding var selection: String
    var label: String = "Your color"

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
            Spacer()
            ForEach(ParticipantColors.palette, id: \.self) { hex in
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 28, height: 28)
                    .overlay(Circle().stroke(AppColor.text, lineWidth: selection == hex ? 2 : 0))
                    .onTapGesture { selection = hex }
                    .accessibilityLabel("Color \(hex)")
            }
        }
    }
}

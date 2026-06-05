import SwiftUI

/// A colored circle with a participant's initial. Scales to N people.
struct ParticipantBadge: View {
    let name: String
    let colorHex: String

    private var initial: String {
        String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    var body: some View {
        Text(initial.isEmpty ? "?" : initial)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(Color(hex: colorHex.isEmpty ? "636366" : colorHex), in: Circle())
            .accessibilityLabel("Logged by \(name.isEmpty ? "unknown" : name)")
    }
}

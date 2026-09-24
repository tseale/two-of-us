import SwiftUI

/// One tappable face per participant, ringed in their color when selected —
/// the "pick a parent" row shared by the edit sheet and the log sheets (and
/// visually identical to the night-shift picker in `SlotActionsSheet`), so
/// assigning an event to a person reads the same everywhere.
struct LoggedByPicker: View {
    let participants: [Participant]
    @Binding var selectedID: UUID?

    var body: some View {
        HStack(spacing: 12) {
            ForEach(participants) { p in
                personButton(p)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func personButton(_ p: Participant) -> some View {
        let selected = selectedID == p.id
        return Button {
            selectedID = p.id
        } label: {
            VStack(spacing: 6) {
                Avatar(photoData: p.photoData, name: p.displayName, colorHex: p.colorHex, size: 56)
                    .overlay {
                        if selected {
                            Circle().strokeBorder(Color(hex: p.colorHex), lineWidth: 3)
                                .frame(width: 64, height: 64)
                        }
                    }
                Text(p.displayName)
                    .font(.caption.weight(selected ? .bold : .regular))
                    .foregroundStyle(AppColor.text)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selected
            ? "Logged by \(p.displayName), selected"
            : "Change logged by to \(p.displayName)")
    }
}

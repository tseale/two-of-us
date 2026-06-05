import SwiftUI

/// Backdate control: defaults to Now; tap to pick any past date-time.
/// Reused by Feed, Diaper, and Edit.
struct TimeControl: View {
    @Binding var date: Date

    var body: some View {
        HStack {
            DatePicker(
                "Time",
                selection: $date,
                in: ...Date(),
                displayedComponents: [.date, .hourAndMinute]
            )
            .font(.subheadline)

            Button {
                date = .now
            } label: {
                Text("Now")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(AppColor.accentFeed)
        }
    }
}

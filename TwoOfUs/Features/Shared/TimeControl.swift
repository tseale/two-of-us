import SwiftUI

/// Backdate control: defaults to Now; tap to pick any past date-time.
/// Reused by Feed, Diaper, and Edit.
struct TimeControl: View {
    @Binding var date: Date
    /// Tint for the "Now" reset button so it matches the hosting sheet's accent
    /// (feed teal / diaper amber) instead of always feed teal.
    var tint: Color = AppColor.accentFeed

    var body: some View {
        HStack {
            // Label hidden — every host wraps this in a `Section("Time")`, so an
            // inline "Time" label would read as "Time" twice on the row.
            DatePicker(
                "Time",
                selection: $date,
                in: ...Date(),
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()
            .font(.subheadline)

            Spacer(minLength: 12)

            Button {
                date = .now
            } label: {
                Text("Now")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(tint)
        }
    }
}

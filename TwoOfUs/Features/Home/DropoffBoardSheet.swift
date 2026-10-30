import SwiftUI

/// The whiteboard cheat sheet: at drop-off the daycare asks for last bottle,
/// last diaper, wake time, sleep quality, and notes on a whiteboard — the
/// exact numbers a sleep-deprived parent reconstructs from memory at 7 AM
/// with a baby on one arm. This card answers every column from the app's
/// own data, in type big enough to read at arm's length while writing. Just
/// the rows: it's read off the phone and written on the board, never pasted.
struct DropoffBoardSheet: View {
    let info: DropoffBoardInfo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 18) {
                    row("🍼", "Last bottle", info.lastBottle)
                    row("💧", "Last diaper", info.lastDiaper)
                    row("☀️", "Woke up at", info.wokeUpAt)
                    row("💤", "Sleep", info.overnightSleep)
                    row("📝", "Notes", info.notes ?? "None")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
        }
        .background(AppColor.bg)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text(info.name)
                .font(AppFont.hero(30))
                .foregroundStyle(AppColor.text)
            Text("for the whiteboard")
                .font(.subheadline)
                .foregroundStyle(AppColor.text2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
    }

    /// One whiteboard column: quiet caption label, the answer at display
    /// scale — the glanceable part.
    private func row(_ emoji: String, _ label: String, _ value: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(emoji).font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(AppColor.text2)
                Text(value ?? "—")
                    .font(AppFont.display(26, weight: .semibold))
                    .foregroundStyle(value == nil ? AppColor.text3 : AppColor.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .surfaceCard(cornerRadius: 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value ?? "nothing logged")")
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        DropoffBoardSheet(info: DropoffBoardInfo(
            name: "Miller",
            lastBottle: "6:45 AM · 4 oz",
            lastDiaper: "7:10 AM · wet",
            wokeUpAt: "6:30 AM",
            overnightSleep: "10h 2m — slept well",
            notes: "A little congested overnight"
        ))
    }
    .preferredColorScheme(.dark)
}

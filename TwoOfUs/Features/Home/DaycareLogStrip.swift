import SwiftUI

/// What the big log tiles collapse into during daycare hours. Between
/// check-in and check-out the parents aren't the ones feeding, changing, or
/// napping him — the primary interaction is watching what daycare reports, so
/// the report card takes the hero slot and this strip keeps the three log
/// actions reachable (the drop-off bottle logged late, a diaper in the car)
/// without letting them command half the screen.
struct DaycareLogStrip: View {
    let babyName: String
    /// Today's first check-in, for the "checked in 7:30 AM" subline.
    let checkIn: Date?
    var showFeed = true
    var showSleep = true
    var showDiaper = true
    let onFeed: () -> Void
    let onSleep: () -> Void
    let onDiaper: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("\u{1F3EB}").font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(babyName) is at daycare")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.text)
                Text(checkIn.map { "checked in \(TimeFormatting.clock($0))" }
                     ?? "they're doing the logging for now")
                    .font(.caption)
                    .foregroundStyle(AppColor.text3)
            }
            Spacer(minLength: 8)
            if showFeed {
                miniButton("🍼", label: "Log a feed", color: AppColor.accentFeed, action: onFeed)
            }
            if showDiaper {
                miniButton("💩", label: "Log a diaper change", color: AppColor.accentDiaper, action: onDiaper)
            }
            if showSleep {
                miniButton("💤", label: "Start sleep timer", color: AppColor.accentSleep, action: onSleep)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .surfaceCard(cornerRadius: 14)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(checkIn.map {
            "\(babyName) is at daycare, checked in \(TimeFormatting.clock($0))"
        } ?? "\(babyName) is at daycare")
    }

    /// 44pt circular target — small next to the tiles, still comfortably
    /// tappable one-handed.
    private func miniButton(_ emoji: String, label: String, color: Color,
                            action: @escaping () -> Void) -> some View {
        Button { action(); Haptics.tap() } label: {
            Text(emoji)
                .font(.body)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.14), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

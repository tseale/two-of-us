import SwiftUI

/// Live "time since last" state for a log tile: the formatted value plus its
/// urgency. `nil` on a tile means no prior event — the tile renders without
/// a since-line so the first-run screen stays clean.
struct TileStatus {
    let value: String      // "2h 31m" / "just now" — from TimeFormatting.since
    let urgency: Urgency

    /// "2h 31m ago", but "just now" stays as-is ("just now ago" reads wrong).
    var sinceText: String {
        value == "just now" ? value : "\(value) ago"
    }
}

/// The three primary log targets. Feed + Diaper (the two highest-frequency
/// logs) side by side, Sleep full-width below. Each tile carries its own
/// time-since value and urgency dot, so the tiles double as the status row.
/// The wide Sleep row is also the slot the active timer card takes over —
/// when sleep is active the caller swaps it in place, so Feed and Diaper
/// never move.
struct LogButtons: View {
    let feedStatus: TileStatus?
    let sleepStatus: TileStatus?
    let diaperStatus: TileStatus?
    let sleepActive: Bool
    let onFeed: () -> Void
    let onSleep: () -> Void
    let onDiaper: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    tile(title: "Feed", hint: "log a bottle", emoji: "🍼", color: AppColor.accentFeed,
                         status: feedStatus, action: onFeed)
                    tile(title: "Diaper", hint: "wet · dirty · both", emoji: "💩", color: AppColor.accentDiaper,
                         status: diaperStatus, action: onDiaper)
                }
                if !sleepActive {
                    wideTile(title: "Sleep", hint: "start timer", emoji: "💤", color: AppColor.accentSleep,
                             status: sleepStatus, action: onSleep)
                        .transition(.opacity.combined(with: .scale(0.96, anchor: .bottom)))
                }
            }
        }
    }

    private func tile(title: String, hint: String, emoji: String, color: Color,
                      status: TileStatus?, action: @escaping () -> Void) -> some View {
        Button(action: { action(); Haptics.tap() }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 5) {
                    Text(emoji).font(.system(size: 30))
                    if let status {
                        urgencyDot(status.urgency)
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .lineLimit(1)
                    if let status {
                        Text(status.sinceText)
                            .font(.subheadline)
                            .foregroundStyle(AppColor.text2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(AppColor.text2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .padding(18)
            .glassTile(cornerRadius: 20, tint: color)
            .foregroundStyle(AppColor.text)
        }
        .buttonStyle(PressableTileStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(title: title, hint: hint, status: status))
    }

    private func wideTile(title: String, hint: String, emoji: String, color: Color,
                          status: TileStatus?, action: @escaping () -> Void) -> some View {
        Button(action: { action(); Haptics.tap() }) {
            HStack(spacing: 14) {
                HStack(spacing: 5) {
                    Text(emoji).font(.system(size: 28))
                    if let status {
                        urgencyDot(status.urgency)
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 0) {
                        Text(title)
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .lineLimit(1)
                        if let status {
                            Text(" · \(status.sinceText)")
                                .font(.subheadline)
                                .foregroundStyle(AppColor.text2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                    }
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(AppColor.text2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .padding(18)
            .glassTile(cornerRadius: 20, tint: color)
            .foregroundStyle(AppColor.text)
        }
        .buttonStyle(PressableTileStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(title: title, hint: hint, status: status))
    }

    private func urgencyDot(_ urgency: Urgency) -> some View {
        Circle()
            .fill(urgency.color)
            .frame(width: 6, height: 6)
    }

    private func accessibilityText(title: String, hint: String, status: TileStatus?) -> String {
        guard let status else { return "\(title), \(hint)" }
        return "\(title), \(status.value) since last, \(status.urgency.accessibilityWord), \(hint)"
    }
}

/// Tactile press feedback for the log tiles: a quick scale-down + spring settle on
/// release, so a tap feels physical. Falls back to no motion under Reduce Motion.
struct PressableTileStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.96 : 1))
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.6),
                       value: configuration.isPressed)
    }
}

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

/// A right-aligned eyebrow-label + value stat for the wide Sleep row — the
/// horizontal slot the square tiles don't have room for.
struct TileDetail {
    let label: String      // "last nap"
    let value: String      // "1h 20m"
}

/// The three primary log targets. Feed + Diaper (the two highest-frequency
/// logs) side by side, Sleep full-width below. Each tile carries its own
/// time-since value, so the tiles double as the status row — quiet until it
/// matters: the since-line stays calm gray at green and gains a tinted color
/// + dot at amber/red. A ⊕ badge keeps the tiles reading as buttons now that
/// they carry status. The wide Sleep row is also the slot the active timer
/// card takes over — when sleep is active the caller swaps it in place, so
/// Feed and Diaper never move.
struct LogButtons: View {
    let feedStatus: TileStatus?
    let sleepStatus: TileStatus?
    let diaperStatus: TileStatus?
    let feedHint: String
    let sleepHint: String
    let sleepDetail: TileDetail?
    let sleepActive: Bool
    let onFeed: () -> Void
    let onSleep: () -> Void
    let onDiaper: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    tile(title: "Feed", hint: feedHint, emoji: "🍼", color: AppColor.accentFeed,
                         status: feedStatus, action: onFeed)
                    tile(title: "Diaper", hint: "wet · dirty · both", emoji: "💩", color: AppColor.accentDiaper,
                         status: diaperStatus, action: onDiaper)
                }
            }
            // Deliberately OUTSIDE the GlassEffectContainer: a glass view removed
            // from a container morphs into its nearest glass sibling, which sent
            // this tile's glass flying into the Feed tile on sleep start.
            // Standalone glass just fades with the view transition.
            if !sleepActive {
                wideTile(title: "Sleep", hint: sleepHint, emoji: "💤", color: AppColor.accentSleep,
                         status: sleepStatus, detail: sleepDetail, action: onSleep)
                    .transition(.opacity.combined(with: .scale(0.96, anchor: .bottom)))
            }
        }
    }

    private func tile(title: String, hint: String, emoji: String, color: Color,
                      status: TileStatus?, action: @escaping () -> Void) -> some View {
        Button(action: { action(); Haptics.tap() }) {
            VStack(alignment: .leading, spacing: 10) {
                Text(emoji).font(.system(size: 30))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .lineLimit(1)
                    if let status {
                        sinceLine(status)
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
            .overlay(alignment: .topTrailing) { plusBadge(color).padding(14) }
            .glassTile(cornerRadius: 20, tint: color)
            .contentShape(.rect(cornerRadius: 20))
            .foregroundStyle(AppColor.text)
        }
        .buttonStyle(PressableTileStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(title: title, hint: hint, status: status))
    }

    private func wideTile(title: String, hint: String, emoji: String, color: Color,
                          status: TileStatus?, detail: TileDetail?,
                          action: @escaping () -> Void) -> some View {
        Button(action: { action(); Haptics.tap() }) {
            HStack(spacing: 14) {
                Text(emoji).font(.system(size: 28))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(title)
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .lineLimit(1)
                        if let status {
                            Text("·")
                                .font(.subheadline)
                                .foregroundStyle(AppColor.text2)
                            sinceLine(status)
                        }
                    }
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(AppColor.text2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Spacer(minLength: 12)
                // The row's width bonus over the square tiles: a trailing stat.
                // Vertically centered, so it stays clear of the topTrailing ⊕.
                if let detail {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(detail.label).sectionLabelStyle(color: AppColor.text3)
                        Text(detail.value)
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundStyle(AppColor.text2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
            }
            // Same minHeight + padding as the square tiles, so all three rows
            // of the grid render at one height.
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .padding(18)
            .overlay(alignment: .topTrailing) { plusBadge(color).padding(14) }
            .glassTile(cornerRadius: 20, tint: color)
            .contentShape(.rect(cornerRadius: 20))
            .foregroundStyle(AppColor.text)
        }
        .buttonStyle(PressableTileStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(title: title, hint: hint, status: status, detail: detail))
    }

    /// Quiet until it matters: plain gray at green, tinted semibold text plus
    /// an 8pt dot once the target interval is approached or passed.
    private func sinceLine(_ status: TileStatus) -> some View {
        HStack(spacing: 5) {
            Text(status.sinceText)
                .fontWeight(status.urgency.needsAttention ? .semibold : .regular)
            if status.urgency.needsAttention {
                Circle()
                    .fill(status.urgency.color)
                    .frame(width: 8, height: 8)
            }
        }
        .font(.subheadline)
        .foregroundStyle(status.urgency.sinceTextColor)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    /// "Tap to add" affordance — the tiles carry status now, so the badge keeps
    /// them reading as buttons at first glance.
    private func plusBadge(_ color: Color) -> some View {
        Image(systemName: "plus.circle.fill")
            .font(.system(size: 22))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, color)
            .accessibilityHidden(true)
    }

    private func accessibilityText(title: String, hint: String, status: TileStatus?,
                                   detail: TileDetail? = nil) -> String {
        var text: String
        if let status {
            text = "\(title), \(status.value) since last, \(status.urgency.accessibilityWord), \(hint)"
        } else {
            text = "\(title), \(hint)"
        }
        if let detail { text += ", \(detail.label) \(detail.value)" }
        return text
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

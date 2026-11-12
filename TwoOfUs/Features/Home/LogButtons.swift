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

/// A tile's bottom hint line. `isAI` marks a `PredictionEngine` forecast,
/// which renders in the AI gradient with the ✦ mark; plain hints keep the
/// quiet gray they've always had.
struct TileHint {
    let text: String
    var isAI: Bool = false
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
    let feedHint: TileHint
    let sleepHint: TileHint
    let diaperHint: TileHint
    let sleepDetail: TileDetail?
    let sleepActive: Bool
    /// True when a feed alarm is armed on this device — shows a bell affordance
    /// on the Feed tile so parents know a reminder is counting down.
    var feedReminderArmed: Bool = false
    /// Per-kind tracker switches (SharedSettings) — a hidden tile is how a
    /// paused tracker reads on Home. With one of the square pair off, the
    /// survivor stretches to full width on its own (it's the sole HStack child).
    var showFeed: Bool = true
    var showSleep: Bool = true
    var showDiaper: Bool = true
    let onFeed: () -> Void
    let onSleep: () -> Void
    let onDiaper: () -> Void

    /// A tile's content is never shorter than this…
    static let tileMinContentHeight: CGFloat = 96
    /// …inside this much padding. Named so `LogTileFootprint` — the stand-in
    /// that lets the running-sleep card take exactly the Sleep tile's height —
    /// is built from the tiles' own numbers.
    static let tilePadding: CGFloat = 18

    var body: some View {
        VStack(spacing: 12) {
            if showFeed || showDiaper {
                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        if showFeed {
                            tile(title: "Feed", hint: feedHint, emoji: "🍼", color: AppColor.accentFeed,
                                 status: feedStatus, reminderArmed: feedReminderArmed, action: onFeed)
                        }
                        if showDiaper {
                            tile(title: "Diaper", hint: diaperHint, emoji: "💩", color: AppColor.accentDiaper,
                                 status: diaperStatus, action: onDiaper)
                        }
                    }
                }
            }
            // Deliberately OUTSIDE the GlassEffectContainer: a glass view removed
            // from a container morphs into its nearest glass sibling, which sent
            // this tile's glass flying into the Feed tile on sleep start.
            // Standalone glass just fades with the view transition.
            if showSleep && !sleepActive {
                tile(title: "Sleep", hint: sleepHint, emoji: "💤", color: AppColor.accentSleep,
                     status: sleepStatus, detail: sleepDetail, action: onSleep)
                    .transition(.opacity.combined(with: .scale(0.96, anchor: .bottom)))
            }
        }
    }

    /// One builder for all three tiles, so the square pair and the wide Sleep
    /// row share alignment and stacking exactly: emoji on top, then title /
    /// since-line / hint, leading-aligned. `detail` is the wide row's width
    /// bonus — a trailing stat the square tiles have no room for.
    private func tile(title: String, hint: TileHint, emoji: String, color: Color,
                      status: TileStatus?, detail: TileDetail? = nil,
                      reminderArmed: Bool = false,
                      action: @escaping () -> Void) -> some View {
        // The tap haptic is unconditional touch acknowledgement, so firing it before
        // the action (for the Sleep tile, the whole start-sleep write) only makes it land sooner.
        Button(action: { Haptics.tap(); action() }) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(emoji).font(.system(size: 30))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .lineLimit(1)
                        if let status {
                            sinceLine(status)
                        }
                        if hint.isAI {
                            AIHintText(text: hint.text, font: .caption)
                        } else {
                            Text(hint.text)
                                .font(.caption)
                                .foregroundStyle(AppColor.text2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                    }
                }
                if let detail {
                    Spacer(minLength: 12)
                    // Vertically centered, so it stays clear of the topTrailing ⊕.
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
            .frame(maxWidth: .infinity, minHeight: Self.tileMinContentHeight, alignment: .leading)
            .padding(Self.tilePadding)
            .overlay(alignment: .topTrailing) { plusBadge(color).padding(14) }
            .overlay(alignment: .bottomTrailing) {
                if reminderArmed {
                    Image(systemName: "bell.fill")
                        .font(.caption2)
                        .foregroundStyle(AppColor.text3)
                        .padding(14)
                        .accessibilityHidden(true)
                }
            }
            .glassTile(cornerRadius: 20, tint: color)
            .contentShape(.rect(cornerRadius: 20))
            .foregroundStyle(AppColor.text)
        }
        .buttonStyle(PressableTileStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(title: title, hint: hint, status: status, detail: detail,
                                              reminderArmed: reminderArmed))
        // Stable hook for UI tests (doesn't affect the VoiceOver label above).
        .accessibilityIdentifier("logTile.\(title.lowercased())")
    }

    /// Quiet until it matters: plain gray at green, tinted semibold text plus
    /// an 8pt dot once the target interval is approached or passed.
    private func sinceLine(_ status: TileStatus) -> some View {
        HStack(spacing: 5) {
            Text(status.sinceText)
                .fontWeight(status.urgency.needsAttention ? .semibold : .regular)
            // A shape marker (dot vs exclamation), not just a colored dot, so
            // "due soon" and "overdue" are distinguishable without color vision.
            if let marker = status.urgency.marker {
                Image(systemName: marker)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(status.urgency.color)
                    .accessibilityHidden(true)
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

    private func accessibilityText(title: String, hint: TileHint, status: TileStatus?,
                                   detail: TileDetail? = nil,
                                   reminderArmed: Bool = false) -> String {
        let hintText = hint.isAI ? "predicted: \(hint.text)" : hint.text
        var text: String
        if let status {
            text = "\(title), \(status.value) since last, \(status.urgency.accessibilityWord), \(hintText)"
        } else {
            text = "\(title), \(hintText)"
        }
        if let detail { text += ", \(detail.label) \(detail.value)" }
        if reminderArmed { text += ", reminder set" }
        return text
    }
}

/// A log tile's height, as an invisible stand-in for layout. It stacks what a
/// tile stacks — emoji, title, since-line, hint — in the same type styles,
/// with the same floor and padding, so it is as tall as the Sleep tile at
/// every text size. The running-sleep card's footprint arrangement (iPhone
/// Duo's pages and cover) lays it under its own content: the card is then
/// exactly the height of the tile it replaces, and nothing else on the page
/// moves when he falls asleep. Draws nothing and says nothing to VoiceOver.
/// Keep it in step with `LogButtons.tile`.
struct LogTileFootprint: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("💤").font(.system(size: 30))
            VStack(alignment: .leading, spacing: 1) {
                Text("Sleep")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .lineLimit(1)
                Text("1h ago")
                    .font(.subheadline)
                    .lineLimit(1)
                Text("next")
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .frame(minHeight: LogButtons.tileMinContentHeight)
        .padding(.vertical, LogButtons.tilePadding)
        .hidden()
        .accessibilityHidden(true)
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
            // Warm the haptic engine on touch-down so the tap haptic at touch-up is immediate.
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.prepareTap() }
            }
    }
}

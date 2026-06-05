import SwiftUI

/// The three primary log targets. Feed + Sleep on top, Diaper full-width below.
/// When sleep is active, the caller replaces the Sleep tile with the active card.
struct LogButtons: View {
    let sleepActive: Bool
    let onFeed: () -> Void
    let onSleep: () -> Void
    let onDiaper: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                tile(title: "Feed", hint: "log a bottle", emoji: "🍼", color: AppColor.accentFeed, action: onFeed)
                if !sleepActive {
                    tile(title: "Sleep", hint: "start timer", emoji: "💤", color: AppColor.accentSleep, action: onSleep)
                }
            }
            wideTile(title: "Diaper", hint: "wet · dirty · both", emoji: "💩", color: AppColor.accentDiaper, action: onDiaper)
        }
    }

    private func tile(title: String, hint: String, emoji: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: { action(); Haptics.tap() }) {
            VStack(alignment: .leading, spacing: 10) {
                Text(emoji).font(.system(size: 30))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.title3.weight(.bold))
                    Text(hint).font(.caption).foregroundStyle(AppColor.text2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .padding(18)
            .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 20))
            .foregroundStyle(AppColor.text)
        }
        .buttonStyle(.plain)
    }

    private func wideTile(title: String, hint: String, emoji: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: { action(); Haptics.tap() }) {
            HStack(spacing: 14) {
                Text(emoji).font(.system(size: 28))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.title3.weight(.bold))
                    Text(hint).font(.caption).foregroundStyle(AppColor.text2)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .padding(18)
            .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 20))
            .foregroundStyle(AppColor.text)
        }
        .buttonStyle(.plain)
    }
}

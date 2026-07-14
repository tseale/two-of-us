import SwiftUI

/// Per-quest presentation, shared by the Home checklist card and the Settings
/// "Finish setting up" rows.
extension SetupQuest {
    var title: String {
        switch self {
        case .rhythm: "Tune your feeding rhythm"
        case .reminders: "Turn on feed reminders"
        }
    }

    var hint: String {
        switch self {
        case .rhythm: "Feed interval and bottle sizes — 30 seconds"
        case .reminders: "A nudge when the next bottle is due"
        }
    }

    var icon: String {
        switch self {
        case .rhythm: "timer"
        case .reminders: "bell.badge"
        }
    }

    var tint: Color {
        switch self {
        case .rhythm: AppColor.accentFeed
        case .reminders: AppColor.urgencyAmber
        }
    }
}

/// The "Getting set up" card on Home: the deliberately small list of setup
/// quests deferred out of onboarding, each opening a 30-second sheet. Dismissible
/// (quests live on in Settings), and self-retiring — once every quest is done it
/// shows a brief "All set" and bows out.
struct SetupChecklistCard: View {
    let quests: [SetupQuest]
    let isComplete: (SetupQuest) -> Bool
    var onQuest: (SetupQuest) -> Void
    var onDismiss: () -> Void

    private var doneCount: Int { quests.filter(isComplete).count }
    private var allDone: Bool { doneCount == quests.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Getting set up").sectionLabelStyle()
                Spacer()
                if allDone {
                    Text("All set")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColor.urgencyGreen)
                } else {
                    Text("\(doneCount) of \(quests.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColor.text3)
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body)
                            .foregroundStyle(AppColor.text3)
                            // 44pt hit target; negative padding keeps the header
                            // row's layout at the icon's visual size.
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(-11)
                    .accessibilityLabel("Dismiss — finish anytime in Settings")
                }
            }

            ForEach(quests) { quest in
                questRow(quest)
            }

            if !allDone {
                Text("Whenever you're ready — defaults work fine until then.")
                    .font(.caption2)
                    .foregroundStyle(AppColor.text3)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard()
        // Retire on its own once everything is done: the "All set" state stays
        // visible until the user scrolls past it (swipe up / new section loads),
        // then onDismiss hides the card for good.  A longer beat (4s) so the
        // parent has time to see the "All set" row if completion arrives via sync.
        .task(id: allDone) {
            guard allDone else { return }
            try? await Task.sleep(for: .seconds(4))
            withAnimation { onDismiss() }
        }
    }

    @ViewBuilder private func questRow(_ quest: SetupQuest) -> some View {
        let done = isComplete(quest)
        Button {
            guard !done else { return }
            Haptics.tap()
            onQuest(quest)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: done ? "checkmark.circle.fill" : quest.icon)
                    .font(.title3)
                    .foregroundStyle(done ? AppColor.urgencyGreen : quest.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(quest.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.text)
                        .strikethrough(done, color: AppColor.text3)
                    if !done {
                        Text(quest.hint)
                            .font(.caption)
                            .foregroundStyle(AppColor.text3)
                    }
                }
                Spacer()
                if !done {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppColor.text3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(done)
        .accessibilityLabel(done ? "\(quest.title) — done" : "\(quest.title). \(quest.hint)")
    }
}

#Preview {
    VStack(spacing: 16) {
        SetupChecklistCard(
            quests: [.rhythm, .reminders],
            isComplete: { $0 == .rhythm },
            onQuest: { _ in },
            onDismiss: {}
        )
        SetupChecklistCard(
            quests: [.rhythm, .reminders],
            isComplete: { _ in true },
            onQuest: { _ in },
            onDismiss: {}
        )
    }
    .padding()
    .background(AppColor.bg)
}

import SwiftUI

/// Small visual card shown after a Siri / Shortcuts / control log, alongside the
/// spoken dialog. Deliberately dependency-light so it compiles into both the app
/// and the widget extension.
struct ConfirmationSnippet: View {
    let emoji: String
    let title: String
    let subtitle: String?

    init(emoji: String, title: String, subtitle: String? = nil) {
        self.emoji = emoji
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(emoji)
                .font(.system(size: 34))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

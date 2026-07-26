import SwiftUI
import UIKit

/// A circular avatar: the participant's (or baby's) photo when set, otherwise a
/// colored monogram — the same fallback look as `ParticipantBadge`, scaled up.
/// Size-parameterized so the same view serves the big profile header, the medium
/// People rows, and the edit sheets.
struct Avatar: View {
    let photoData: Data?
    let name: String
    let colorHex: String
    var size: CGFloat = 44

    private var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return String(trimmed.prefix(1)).uppercased()
    }

    private var tint: Color { Color(hex: colorHex.isEmpty ? "636366" : colorHex) }

    var body: some View {
        Group {
            if let photoData, let image = UIImage(data: photoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                tint.overlay {
                    // Nameless → neutral silhouette, not a "?" (same rationale
                    // as ParticipantBadge).
                    if initial.isEmpty {
                        Image(systemName: "person.fill")
                            .font(.system(size: size * 0.4, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Text(initial)
                            .font(.system(size: size * 0.44, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityLabel(name.isEmpty ? "No name" : name)
    }
}

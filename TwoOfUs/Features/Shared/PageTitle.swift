import SwiftUI

/// Which of a `PageTitle`'s two lines its trailing control keeps company
/// with. (Outside the generic view, so call sites just write `.subtitle`.)
enum PageTitleTrailingAlignment {
    /// Top-aligned with the title: a round button (Settings).
    case title
    /// On the subtitle's baseline: a quiet text action ("+ Add note").
    case subtitle
}

/// The title block at the head of a page on iPhone Duo's open display: the
/// big rounded title — the baby's name on the page that was the cover, the
/// section's name on the page beside it — over a quiet subtitle, with room
/// for one trailing control.
///
/// It is the phone header's own type (the 34 pt hero title, a subheadline in
/// `text2`) without the avatar, which on the spread hangs in the margin
/// beside it (`SpreadGrid.avatarFrame`). The block is ≈ 61 pt tall at the
/// default text size; pad it underneath by `SpreadGrid.titleAir` and give it
/// `SpreadGrid.titleHeight` as a minimum height, top-aligned, and the first
/// surface under it lands on the grid's top line — while a larger text size
/// pushes that surface down, still that air away, instead of overlapping.
///
/// The title never wraps (it truncates, as on the phone); the subtitle may.
/// VoiceOver reads the two lines as one heading and the trailing control as
/// its own element after it.
struct PageTitle<Trailing: View>: View {
    private let title: String
    private let subtitle: String?
    private let trailingAlignment: PageTitleTrailingAlignment
    private let trailing: Trailing

    init(_ title: String, subtitle: String? = nil,
         trailingAlignment: PageTitleTrailingAlignment = .title,
         @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailingAlignment = trailingAlignment
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: trailingAlignment == .subtitle
                   ? VerticalAlignment.lastTextBaseline : .top,
               spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.hero())
                    .foregroundStyle(AppColor.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(AppColor.text2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // One element, announced as the page's heading — the two pages
            // read as two titled sections, leading page first.
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            trailing
        }
    }
}

extension PageTitle where Trailing == EmptyView {
    /// A title with nothing beside it.
    init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle, trailing: { EmptyView() })
    }
}

#Preview("Name and settings") {
    PageTitle("Miller", subtitle: "3 months old") {
        Image(systemName: "gearshape")
            .font(.title3)
            .foregroundStyle(AppColor.text3)
            .frame(width: 44, height: 44)
            .background(AppColor.card, in: Circle())
    }
    .frame(width: 350)
    .padding()
    .background(AppColor.bg)
    .preferredColorScheme(.dark)
}

#Preview("Section and text action") {
    PageTitle("Recent", subtitle: "last 24 hours", trailingAlignment: .subtitle) {
        Text("+ Add note")
            .font(.footnote.weight(.medium))
            .foregroundStyle(AppColor.accentNote)
    }
    .frame(width: 350)
    .padding()
    .background(AppColor.bg)
}

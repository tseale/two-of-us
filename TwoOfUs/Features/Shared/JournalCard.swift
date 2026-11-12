import SwiftUI

/// The journal card's fixed numbers, outside the generic view so a host can
/// read them (to keep its own overlays clear of the fade, say).
enum JournalCardMetrics {
    static let cornerRadius: CGFloat = 18
    /// How much of the card's foot dissolves into the surface.
    static let fadeHeight: CGFloat = 44
    /// Air between the card's top edge and its first row.
    static let topInset: CGFloat = 6
    /// How far a row keeps from the card's sides: the timeline's time gutter
    /// starts close to the leading edge, its avatars and thumbnails stop a
    /// little shorter of the trailing one.
    static let rowLeadingInset: CGFloat = 6
    static let rowTrailingInset: CGFloat = 12
}

/// A page surface for scrolling content — the timeline, as the journal page
/// of iPhone Duo's open display. On the phone the timeline simply runs off
/// the bottom of the screen; on a page that ends on the foot line it needs an
/// edge of its own, or its rows would just stop in mid-air beside the other
/// page's cards. So the rows sit on one solid card (the calm, read-not-tap
/// surface `surfaceCard` gives the data cards: `card` fill, 18 pt corners, a
/// hairline), clipped to it, and the last 44 pt dissolve into the card's own
/// colour instead of ending in a hard cut.
///
/// The card takes all the room it is given; a `List` inside keeps every
/// gesture — taps, swipe actions, pull to refresh — because the fade and the
/// hairline never take touches. The card hides the list's own background and
/// insets its content (a little air above the first row, the fade's height
/// under the last, so the newest and the oldest row can both be read clear of
/// the edges). Rows still need `.listRowBackground(Color.clear)` to sit on the
/// card rather than on the list's cells.
///
/// Anything else works as content too — an empty state is simply centred.
struct JournalCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, JournalCardMetrics.topInset, for: .scrollContent)
            .contentMargins(.bottom, JournalCardMetrics.fadeHeight, for: .scrollContent)
            .background(AppColor.card, in: .rect(cornerRadius: JournalCardMetrics.cornerRadius))
            .overlay(alignment: .bottom) {
                // Rows dissolve into the page rather than being cut by it.
                LinearGradient(colors: [AppColor.card.opacity(0), AppColor.card],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: JournalCardMetrics.fadeHeight)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .clipShape(.rect(cornerRadius: JournalCardMetrics.cornerRadius))
            .overlay {
                // Same hairline as `surfaceCard`, drawn over the clip so the
                // rows scroll under it.
                RoundedRectangle(cornerRadius: JournalCardMetrics.cornerRadius)
                    .strokeBorder(AppColor.separator.opacity(0.5), lineWidth: 0.5)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}

#Preview("Journal") {
    JournalCard {
        List(0..<24, id: \.self) { i in
            Text("Row \(i)")
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {} label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
        }
        .listStyle(.plain)
    }
    .frame(width: 350, height: 420)
    .padding()
    .background(AppColor.bg)
    .preferredColorScheme(.dark)
}

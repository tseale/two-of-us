import SwiftUI

/// Holding screen while `CloudRestore` checks iCloud for an existing family
/// and, when it finds one, downloads it. Shown INSTEAD of owner onboarding on
/// a fresh install, so a parent setting up a new phone can't mint a duplicate
/// baby before their log arrives. `RootView` re-routes on its own when the
/// restore finishes.
struct RestoreFromCloudView: View {
    @State private var restore = CloudRestore.shared
    /// After this long still downloading, explain and offer Try again.
    private static let patienceWindow: Duration = .seconds(30)
    @State private var tookTooLong = false
    /// Compact only on iPhone Duo's outer display stood like a tent (432 pt
    /// tall) — never on a slab iPhone, which is portrait-only.
    @Environment(\.verticalSizeClass) private var vSize
    /// Where the spine is while iPhone Duo is open in landscape (measured by
    /// `RootView`); nil on every other device and in every other pose.
    @Environment(\.spreadSpine) private var spine

    /// On the spine the mark is 1.4 × its usual 150 pt: it has both leaves
    /// to stand across, a parent's circle on each.
    private static let spineMarkSize: CGFloat = 210
    /// How far down the display the mark's centre sits there. The words'
    /// baseline then falls about 62 % down, and the composition has as much
    /// night above it as below.
    private static let spineMarkCentre: CGFloat = 0.4

    var body: some View {
        ZStack {
            AmbientBackground(stop: .nightStage, onSpine: spine != nil)
            if let spine {
                spineLayout(spine)
            } else {
                VStack(spacing: 24) {
                    // Smaller in the tent pose so the escape hatch still fits.
                    CradleMark(size: vSize == .compact ? 100 : 150, staged: true)
                        // In the same readable column as its copy on a
                        // wide screen (no-op on a phone).
                        .onboardingColumn()
                    VStack(spacing: 10) {
                        Text(title)
                            .font(AppFont.hero(24))
                            .foregroundStyle(AppColor.text)
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(AppColor.text2)
                        SyncingShimmer()
                            .padding(.top, 6)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .onboardingColumn()   // readable on a wide screen; no-op on a phone

                    if showsEscapeHatch { escapeHatch }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: restore.phase)
        .animation(.easeInOut(duration: 0.3), value: restore.failed)
        // Keyed on the flag so Try again (which resets it) restarts the window.
        .task(id: tookTooLong) {
            guard !tookTooLong else { return }
            try? await Task.sleep(for: Self.patienceWindow)
            guard !Task.isCancelled else { return }
            withAnimation { tookTooLong = true }
        }
    }

    /// iPhone Duo open in landscape, flat or folded like a book: the mark on
    /// the spine — one parent's circle on each page, the baby's light on the
    /// crease — and the words either side of it like the title spread of a
    /// book. The title closes the leading page, right-aligned to its
    /// fold-side edge; the status opens the trailing page from its own, on
    /// the same baseline, with the shimmer and (when it shows) the escape
    /// hatch under it. Each keeps to its page's width, so no word and no
    /// control ever sits between the pages; only the mark crosses the fold.
    ///
    /// A fixed composition wherever it fits — it does, with room to spare,
    /// at the default text size, escape hatch included — and a scrolling one
    /// at a text size where it does not, so nothing is ever cut off.
    private func spineLayout(_ spine: SpreadSpine) -> some View {
        ScrollView {
            // The stack's own spacing is the one the centred layout keeps
            // between the mark and its words.
            VStack(alignment: .leading, spacing: 24) {
                CradleMark(size: Self.spineMarkSize, staged: true)
                    // Its frame's middle on the crease: the baby's light is
                    // on the mark's own centre line.
                    .padding(.leading, spine.crease - Self.spineMarkSize / 2)
                HStack(alignment: .firstTextBaseline, spacing: spine.gutter) {
                    Text(title)
                        .font(AppFont.hero(24))
                        .foregroundStyle(AppColor.text)
                        .multilineTextAlignment(.trailing)
                        .frame(width: spine.pageWidth, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(AppColor.text2)
                            SyncingShimmer()
                                .padding(.top, 6)
                        }
                        if showsEscapeHatch {
                            escapeHatchLines(alignment: .leading, textAlignment: .leading)
                                .padding(.top, 8)
                                .transition(.opacity)
                        }
                    }
                    .multilineTextAlignment(.leading)
                    .frame(width: spine.pageWidth, alignment: .leading)
                }
                .padding(.leading, spine.leadingPageMinX)
            }
            .padding(.top, spine.top(ofHeight: Self.spineMarkSize,
                                     centredAt: Self.spineMarkCentre))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var isRestoring: Bool {
        if case .restoring = restore.phase { true } else { false }
    }

    /// The restore is under way and has either failed or outlasted the
    /// patience window: time to explain and offer Try again.
    private var showsEscapeHatch: Bool {
        isRestoring && (restore.failed || tookTooLong)
    }

    private var title: String {
        isRestoring ? "Welcome back" : "Checking iCloud…"
    }

    private var subtitle: String {
        switch restore.phase {
        case .restoring(.owner):
            "Bringing your log over from iCloud."
        case .restoring(.coParent):
            "Reconnecting to your family's shared log."
        case .checking, .finished:
            "Looking for your family's log."
        }
    }

    private var escapeHatch: some View {
        escapeHatchLines(alignment: .center, textAlignment: .center)
            .padding(.horizontal, 32)
            .onboardingColumn()
            .padding(.top, 8)
            .transition(.opacity)
    }

    /// The escape hatch itself — what went wrong, what to check, Try again —
    /// written once for both layouts: centred in its column everywhere, and
    /// left-aligned on the trailing page where the mark is on the spine.
    private func escapeHatchLines(alignment: HorizontalAlignment,
                                  textAlignment: TextAlignment) -> some View {
        VStack(alignment: alignment, spacing: 12) {
            Text(restore.failed ? "Couldn't finish downloading." : "This is taking longer than usual.")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppColor.text)
            Text("Make sure this iPhone is online and signed into iCloud, then try again. Everything is safe in iCloud.")
                .font(.footnote)
                .foregroundStyle(AppColor.text2)
                .multilineTextAlignment(textAlignment)
            Button("Try again") {
                tookTooLong = false
                restore.retry()
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.borderedProminent)
            .tint(AppColor.accentFeed)
        }
    }
}

#Preview {
    RestoreFromCloudView()
}

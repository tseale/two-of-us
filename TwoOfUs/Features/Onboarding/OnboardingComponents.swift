import SwiftUI
import PhotosUI

// MARK: - Entrance

/// Staggered entrance for page content: fade + a small rise, one gentle spring
/// per item. Under Reduce Motion every entrance is a plain 0.3s fade — no
/// movement, no stagger.
struct OnboardingEntrance: ViewModifier {
    let revealed: Bool
    var index = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed || reduceMotion ? 0 : 16)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.3)
                    : .spring(response: 0.5, dampingFraction: 0.7).delay(0.08 * Double(index)),
                value: revealed
            )
    }
}

extension View {
    /// Fade-and-rise entrance; `index` staggers siblings (0.08s apart).
    func onboardingEntrance(_ revealed: Bool, index: Int = 0) -> some View {
        modifier(OnboardingEntrance(revealed: revealed, index: index))
    }
}

// MARK: - Step header

/// Eyebrow + title + subtitle stack used by every story and setup page.
struct OnboardingStepHeader: View {
    var eyebrow: String? = nil
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: 8) {
            if let eyebrow {
                Text(eyebrow).sectionLabelStyle(color: AppColor.text3)
            }
            Text(title)
                .font(AppFont.hero(26))
                .foregroundStyle(AppColor.text)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(AppColor.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Bottom bar

/// The floating CTA bar shared by both setup flows. Fixed geometry — the dots,
/// a 52pt primary capsule, and an always-reserved 44pt secondary slot — so the
/// bar never changes height as pages come and go (nothing jumps).
struct OnboardingBottomBar: View {
    struct Primary {
        let title: String
        var enabled = true
        var loading = false
        let action: () -> Void
    }

    struct Secondary {
        let title: String
        /// Accent-tinted attention style (e.g. the "add a name to finish" hint).
        var prominent = false
        var enabled = true
        let action: () -> Void
    }

    let pageCount: Int
    let pageIndex: Int
    let primary: Primary
    var secondary: Secondary? = nil

    /// At rest the bar floats over the empty `barClearance` band its pages
    /// reserve, so it needs no backing. The keyboard breaks that contract by
    /// lifting the bar into the middle of the page, over live cards — glass
    /// appears exactly (and only) while that overlap is possible.
    @State private var keyboardUp = false

    var body: some View {
        VStack(spacing: 14) {
            OnboardingPageDots(count: pageCount, index: pageIndex)

            Button(action: primary.action) {
                ZStack {
                    if primary.loading {
                        ProgressView().tint(.white)
                    } else {
                        Text(primary.title)
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(AppColor.accentFeed.opacity(primary.enabled ? 1 : 0.4), in: Capsule())
            }
            .buttonStyle(PressableTileStyle())
            .disabled(!primary.enabled || primary.loading)

            ZStack {
                if let secondary {
                    Button(action: secondary.action) {
                        Text(secondary.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .tint(secondary.prominent ? AppColor.accentDiaper : AppColor.accentFeed)
                    .disabled(!secondary.enabled)
                }
            }
            // Reserve at least 44pt when empty so the bar doesn't jump between
            // pages, but allow growth so a long secondary label wraps instead of
            // clipping at large Dynamic Type.
            .frame(minHeight: 44)
            .animation(.easeInOut(duration: 0.2), value: secondary?.title)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background {
            if keyboardUp {
                Color.clear
                    .glassCard(cornerRadius: 28)
                    .padding(.horizontal, 8)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: keyboardUp)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardUp = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardUp = false
        }
    }
}

// MARK: - Inputs

/// A glass input card: small eyebrow label over a large rounded text field.
/// Owns its focus; drops the keyboard when the host page stops being current
/// (`active` flips false on a page change or mid-swipe).
struct GlassField: View {
    let label: String
    let prompt: String
    @Binding var text: String
    var tint: Color = AppColor.accentFeed
    var active: Bool = true
    /// Caps the input length so long names don't break layout downstream.
    var maxLength: Int = 40

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).sectionLabelStyle()
            TextField(prompt, text: $text)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(AppColor.text)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit { focused = false }
                .onChange(of: text) { _, new in
                    if new.count > maxLength { text = String(new.prefix(maxLength)) }
                }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(tint.opacity(focused ? 0.7 : 0), lineWidth: 1.5)
        )
        .animation(.easeInOut(duration: 0.2), value: focused)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onChange(of: active) { _, isActive in
            if !isActive { focused = false }
        }
    }
}

/// A glass card hosting an arbitrary control row (date picker, color palette,
/// toggle), so every input shares one visual language.
struct GlassRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
    }
}

/// Optional avatar input: live preview (the monogram updates as the name is
/// typed) + a PhotosPicker, downscaled on the same path as the edit sheets.
struct PhotoPickCard: View {
    let name: String
    let colorHex: String
    @Binding var photoData: Data?

    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        HStack(spacing: 14) {
            Avatar(photoData: photoData, name: name, colorHex: colorHex, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text("Photo")
                    .font(.headline)
                    .foregroundStyle(AppColor.text)
                Text("Optional — add or change it anytime.")
                    .font(.caption)
                    .foregroundStyle(AppColor.text3)
            }
            Spacer()
            PhotosPicker(selection: $photoItem, matching: .images) {
                Text(photoData == nil ? "Add" : "Change")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(AppColor.accentFeed.opacity(0.16), in: Capsule())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .onChange(of: photoItem) { _, item in load(item) }
    }

    private func load(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let raw = try? await item.loadTransferable(type: Data.self),
                  let scaled = ImageDownscale.avatar(from: raw) else { return }
            await MainActor.run { photoData = scaled }
        }
    }
}

// MARK: - Info cards

/// Explains an upcoming permission or feature in the app's own words *before*
/// any system dialog appears, so the ask never feels abrupt.
struct PrimerCard: View {
    let icon: String
    let tint: Color
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppColor.text)
            }
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppColor.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard()
    }
}

/// A gentle, non-blocking notice (e.g. "iCloud is off").
struct InlineNoticeCard: View {
    let icon: String
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(AppColor.text3)
            Text(message)
                .font(.footnote)
                .foregroundStyle(AppColor.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(cornerRadius: 14)
    }
}

// MARK: - Previews

#Preview("Bar + inputs") {
    struct Demo: View {
        @State private var name = "Miller"
        @State private var photo: Data?
        var body: some View {
            ZStack {
                AmbientBackground(stop: AmbientStop(subtle: true, top: AppColor.accentFeed, bottom: AppColor.accentSleep))
                VStack(spacing: 18) {
                    OnboardingStepHeader(eyebrow: "SET UP · 1 OF 3", title: "Who are we tracking?",
                                         subtitle: "Just the essentials — everything is editable later.")
                    GlassField(label: "Name", prompt: "Your baby's name", text: $name)
                    PhotoPickCard(name: name, colorHex: ParticipantColors.babyHex, photoData: $photo)
                    PrimerCard(icon: "bell.badge", tint: AppColor.urgencyAmber,
                               title: "Feed reminders that wake you",
                               message: "After each feed, Two of Us can alert you when the next one is due.")
                    InlineNoticeCard(icon: "icloud.slash", message: "iCloud is off on this iPhone.")
                    Spacer()
                    OnboardingBottomBar(
                        pageCount: 4, pageIndex: 1,
                        primary: .init(title: "Continue", action: {}),
                        secondary: .init(title: "Set up later in Settings", action: {})
                    )
                }
                .padding(.top, 24)
                .padding(.horizontal, 28)
            }
        }
    }
    return Demo()
}

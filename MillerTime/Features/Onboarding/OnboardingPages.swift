import SwiftUI

/// The four stops in the first-launch story. `OnboardingView` owns the paging and
/// the bottom CTA bar; these are the page bodies plus a couple of small presentational
/// helpers. All scrollable so large Dynamic Type never clips, all dark-mode aware.

// MARK: - Pages

/// Warm hello + the value in one line. The demo button lives in the bottom bar.
struct OnboardingWelcomePage: View {
    let babyName: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Spacer(minLength: 48)
                Text("👶")
                    .font(.system(size: 76))
                    .scaleEffect(appeared || reduceMotion ? 1 : 0.6)
                    .opacity(appeared || reduceMotion ? 1 : 0)
                Text("Welcome to Miller Time")
                    .font(AppFont.hero(30))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppColor.text)
                Text("A calm little log for \(babyName)'s feeds, sleeps, and diapers — made for one-handed 3am taps.")
                    .font(.body)
                    .foregroundStyle(AppColor.text2)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 48)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { appeared = true }
        }
    }
}

/// Shows the three things you log, styled exactly like the Home tiles.
struct OnboardingTrackPage: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 24)
                VStack(spacing: 8) {
                    Text("Three things, a tap away")
                        .font(AppFont.hero(26))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(AppColor.text)
                    Text("Feeds, sleep, and diapers — logged in a tap or two, even with a baby in your other arm.")
                        .font(.subheadline)
                        .foregroundStyle(AppColor.text2)
                        .multilineTextAlignment(.center)
                }
                GlassEffectContainer(spacing: 12) {
                    VStack(spacing: 12) {
                        OnboardingShowcaseTile(emoji: "🍼", title: "Feed", hint: "log a bottle", tint: AppColor.accentFeed)
                        OnboardingShowcaseTile(emoji: "💤", title: "Sleep", hint: "start a timer", tint: AppColor.accentSleep)
                        OnboardingShowcaseTile(emoji: "💩", title: "Diaper", hint: "wet · dirty · both", tint: AppColor.accentDiaper)
                    }
                }
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 28)
        }
    }
}

/// The two-parent / CloudKit story.
struct OnboardingSyncPage: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 32)
                HStack(spacing: -16) {
                    OnboardingInitialBadge(initial: "A", colorHex: ParticipantColors.palette[0])
                    OnboardingInitialBadge(initial: "J", colorHex: ParticipantColors.palette[1])
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Two parents")
                VStack(spacing: 8) {
                    Text("Made for both of you")
                        .font(AppFont.hero(26))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(AppColor.text)
                    Text("Log from either phone and it syncs over iCloud — you both see the latest within seconds. No account, no server.")
                        .font(.subheadline)
                        .foregroundStyle(AppColor.text2)
                        .multilineTextAlignment(.center)
                }
                Spacer(minLength: 32)
            }
            .padding(.horizontal, 28)
        }
    }
}

/// The actual setup form — same four fields as before, themed onto the page background.
struct OnboardingSetupPage: View {
    @Binding var babyName: String
    @Binding var dateOfBirth: Date
    @Binding var ownerName: String
    @Binding var ownerColorHex: String

    var body: some View {
        Form {
            Section {
                VStack(spacing: 4) {
                    Text("Last step")
                        .font(AppFont.hero(26))
                        .foregroundStyle(AppColor.text)
                    Text("Who are we tracking, and who's logging?")
                        .font(.subheadline)
                        .foregroundStyle(AppColor.text2)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section("Baby") {
                TextField("Name", text: $babyName)
                DatePicker("Date of birth", selection: $dateOfBirth, in: ...Date(), displayedComponents: .date)
            }

            Section("You") {
                TextField("Your name", text: $ownerName)
                ParticipantColorPicker(selection: $ownerColorHex)
            }
        }
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Presentational helpers

/// A non-interactive twin of the Home log tile — same glass + emoji + copy.
struct OnboardingShowcaseTile: View {
    let emoji: String
    let title: String
    let hint: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            Text(emoji).font(.system(size: 30))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(.title3, design: .rounded).weight(.bold))
                Text(hint).font(.caption).foregroundStyle(AppColor.text2)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(18)
        .glassTile(cornerRadius: 20, tint: tint)
        .foregroundStyle(AppColor.text)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(hint)")
    }
}

/// A round participant avatar with an initial — matches the timeline badge look.
/// The background-colored ring lets two of these overlap cleanly.
struct OnboardingInitialBadge: View {
    let initial: String
    let colorHex: String
    var size: CGFloat = 68

    var body: some View {
        Circle()
            .fill(Color(hex: colorHex))
            .frame(width: size, height: size)
            .overlay(
                Text(initial)
                    .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            )
            .overlay(Circle().strokeBorder(AppColor.bg, lineWidth: 4))
    }
}

/// Slim progress dots for the paged flow; the current page reads as a wider pill.
struct OnboardingPageDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? AppColor.accentFeed : AppColor.separator)
                    .frame(width: i == index ? 20 : 7, height: 7)
            }
        }
        .animation(.easeInOut, value: index)
        .accessibilityHidden(true)
    }
}

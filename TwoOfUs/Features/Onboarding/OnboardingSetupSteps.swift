import SwiftUI
import PhotosUI

/// The setup-chapter pages. Owner onboarding runs baby → you → invite; the
/// rhythm and reminders steps now live in the post-onboarding quest sheets
/// (`QuestSheets.swift`) instead of the first-run flow. Pure presentation:
/// every value binds up into the host, which commits — nothing here touches
/// the store.

// MARK: - Baby

struct BabyStep: View {
    @Binding var name: String
    @Binding var dateOfBirth: Date
    @Binding var notBornYet: Bool
    @Binding var photoData: Data?
    let revealed: Bool
    /// False once this stops being the current page — drops the keyboard.
    let active: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Spacer(minLength: 16)
                OnboardingStepHeader(
                    eyebrow: "Set up · 1 of 3",
                    title: "Who are we tracking?",
                    subtitle: "Just the essentials — everything is editable later."
                )
                .onboardingEntrance(revealed)

                GlassField(label: "Name", prompt: "Your baby's name", text: $name, active: active)
                    .onboardingEntrance(revealed, index: 1)

                GlassRow {
                    Toggle(isOn: $notBornYet) {
                        Text("Not born just yet").foregroundStyle(AppColor.text)
                    }
                    .tint(AppColor.accentSleep)
                }
                .onboardingEntrance(revealed, index: 2)

                GlassRow {
                    HStack {
                        Text(notBornYet ? "Due date" : "Date of birth")
                            .foregroundStyle(AppColor.text)
                        Spacer()
                        DatePicker(notBornYet ? "Due date" : "Date of birth",
                                   selection: $dateOfBirth,
                                   in: notBornYet ? Date()...Date.distantFuture
                                                  : Date.distantPast...Date(),
                                   displayedComponents: .date)
                            .labelsHidden()
                    }
                }
                .onboardingEntrance(revealed, index: 3)
                // Keep the date inside the flipped range — the picker clamps its
                // UI but not the bound value.
                .onChange(of: notBornYet) { _, expecting in
                    if expecting, dateOfBirth <= .now {
                        dateOfBirth = Calendar.current.date(byAdding: .weekOfYear, value: 4, to: .now) ?? .now
                    } else if !expecting, dateOfBirth > .now {
                        dateOfBirth = .now
                    }
                }

                PhotoPickCard(name: name, colorHex: ParticipantColors.babyHex, photoData: $photoData)
                    .onboardingEntrance(revealed, index: 4)
                Spacer(minLength: 16)
            }
            .padding(.horizontal, 28)
        }
        .contentMargins(.bottom, OnboardingLayout.barClearance, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
    }
}

// MARK: - You

struct YouStep: View {
    @Binding var name: String
    @Binding var colorHex: String
    @Binding var photoData: Data?
    let revealed: Bool
    let active: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Spacer(minLength: 16)
                OnboardingStepHeader(
                    eyebrow: "Set up · 2 of 3",
                    title: "And who's logging?",
                    subtitle: "Your name and color mark every entry you make."
                )
                .onboardingEntrance(revealed)

                GlassField(label: "Your name", prompt: "First name", text: $name, active: active)
                    .onboardingEntrance(revealed, index: 1)

                GlassRow {
                    ParticipantColorPicker(selection: colorWithHaptic)
                }
                .onboardingEntrance(revealed, index: 2)

                PhotoPickCard(name: name, colorHex: colorHex, photoData: $photoData)
                    .onboardingEntrance(revealed, index: 3)
                Spacer(minLength: 16)
            }
            .padding(.horizontal, 28)
        }
        .contentMargins(.bottom, OnboardingLayout.barClearance, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
    }

    private var colorWithHaptic: Binding<String> {
        Binding(get: { colorHex }, set: { colorHex = $0; Haptics.tap() })
    }
}

// MARK: - Feeding rhythm

struct RhythmStep: View {
    @Binding var intervalMinutes: Int
    @Binding var ozPresets: [Double]
    let revealed: Bool
    var eyebrow: String? = nil
    /// False when hosted in a sheet (no floating bottom bar to clear).
    var barClearance = true

    @State private var selectedPreset = 1   // middle chip

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Spacer(minLength: 16)
                OnboardingStepHeader(
                    eyebrow: eyebrow,
                    title: "Your feeding rhythm",
                    subtitle: "Drives the next-feed countdown and reminders. Change anytime in Settings."
                )
                .onboardingEntrance(revealed)

                intervalCard.onboardingEntrance(revealed, index: 1)
                presetsCard.onboardingEntrance(revealed, index: 2)
                Spacer(minLength: 16)
            }
            .padding(.horizontal, 28)
        }
        .contentMargins(.bottom, barClearance ? OnboardingLayout.barClearance : 0, for: .scrollContent)
        .scrollBounceBehavior(.basedOnSize)
    }

    private var intervalText: String {
        let h = intervalMinutes / 60, m = intervalMinutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// Fully spelled-out, pluralized form for VoiceOver — the compact "3h" display
    /// reads poorly aloud.
    private var intervalSpoken: String {
        let h = intervalMinutes / 60, m = intervalMinutes % 60
        let hours = h == 1 ? "1 hour" : "\(h) hours"
        if m == 0 { return "Feed every \(hours)" }
        let mins = m == 1 ? "1 minute" : "\(m) minutes"
        return h == 0 ? "Feed every \(mins)" : "Feed every \(hours) \(mins)"
    }

    private var intervalCard: some View {
        VStack(spacing: 10) {
            Text("Feed every").sectionLabelStyle()
            HStack(spacing: 22) {
                roundStepButton("minus", label: "15 minutes less") { adjustInterval(-15) }
                Text(intervalText)
                    .font(AppFont.display(40))
                    .foregroundStyle(AppColor.text)
                    .contentTransition(.numericText())
                    .frame(minWidth: 132)
                    .accessibilityLabel(intervalSpoken)
                roundStepButton("plus", label: "15 minutes more") { adjustInterval(15) }
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    private var presetsCard: some View {
        VStack(spacing: 14) {
            Text("Bottle presets").sectionLabelStyle()
            HStack(spacing: 10) {
                ForEach(ozPresets.indices, id: \.self) { i in
                    presetChip(i)
                }
            }
            HStack(spacing: 22) {
                roundStepButton("minus", label: "Half an ounce less") { adjustPreset(-0.5) }
                Text("Adjust the selected bottle")
                    .font(.caption)
                    .foregroundStyle(AppColor.text3)
                roundStepButton("plus", label: "Half an ounce more") { adjustPreset(0.5) }
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    private func presetChip(_ i: Int) -> some View {
        let isSelected = i == selectedPreset
        return Button {
            Haptics.tap()
            selectedPreset = i
        } label: {
            Text(ozString(ozPresets[i]) + " oz")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(isSelected ? .white : AppColor.text)
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(isSelected ? AppColor.accentFeed : AppColor.card2, in: Capsule())
        }
        .buttonStyle(PressableTileStyle())
        .accessibilityLabel("\(ozString(ozPresets[i])) ounce preset\(isSelected ? ", selected" : "")")
    }

    private func roundStepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(AppColor.text)
                .frame(width: 44, height: 44)
                .background(AppColor.card2, in: Circle())
        }
        .buttonStyle(PressableTileStyle())
        .accessibilityLabel(label)
    }

    private func adjustInterval(_ delta: Int) {
        let next = min(360, max(60, intervalMinutes + delta))
        guard next != intervalMinutes else { return }
        Haptics.tap()
        withAnimation(.snappy) { intervalMinutes = next }
    }

    private func adjustPreset(_ delta: Double) {
        guard ozPresets.indices.contains(selectedPreset) else { return }
        let next = min(12, max(0.5, ozPresets[selectedPreset] + delta))
        guard next != ozPresets[selectedPreset] else { return }
        Haptics.tap()
        withAnimation(.snappy) { ozPresets[selectedPreset] = next }
    }

    private func ozString(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v)
    }
}

// MARK: - Reminders

/// AlarmKit primer + opt-in. Authorization is requested at this calm moment —
/// flipping the toggle on asks immediately; the host's Continue re-checks (a
/// no-op once granted) so swiping past the toggle still can't defer the dialog
/// to a 3am feed log.
struct RemindersStep: View {
    @Binding var on: Bool
    let revealed: Bool
    var eyebrow: String? = nil
    /// Just-in-time variant: what the reminder would say right now, e.g.
    /// "Next bottle around 4:30 PM".
    var contextLine: String? = nil
    /// False when hosted in a sheet (no floating bottom bar to clear).
    var barClearance = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bellRing = false
    @State private var denied = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Spacer(minLength: 16)
                OnboardingStepHeader(
                    eyebrow: eyebrow,
                    title: "A nudge when it's time",
                    subtitle: contextLine
                )
                .onboardingEntrance(revealed)

                PrimerCard(
                    icon: "bell.badge",
                    tint: AppColor.urgencyAmber,
                    title: "Reminders that actually wake you",
                    message: "After each feed, Two of Us can alert you when the next one is due — it breaks through Silent and Focus. Just this iPhone; your partner sets their own."
                )
                .onboardingEntrance(revealed, index: 1)

                GlassRow {
                    HStack(spacing: 12) {
                        Image(systemName: "bell.badge")
                            .font(.title3)
                            .foregroundStyle(AppColor.urgencyAmber)
                            .rotationEffect(.degrees(bellRing ? 8 : 0))
                        Toggle("Remind me", isOn: $on)
                            .tint(AppColor.accentFeed)
                            .foregroundStyle(AppColor.text)
                    }
                }
                .onboardingEntrance(revealed, index: 2)

                if denied {
                    InlineNoticeCard(
                        icon: "bell.slash",
                        message: "Alarms are turned off for Two of Us in iOS Settings — enable them there, or skip for now."
                    )
                }
                Spacer(minLength: 16)
            }
            .padding(.horizontal, 28)
        }
        .contentMargins(.bottom, barClearance ? OnboardingLayout.barClearance : 0, for: .scrollContent)
        .scrollBounceBehavior(.basedOnSize)
        .onChange(of: on) { _, isOn in
            guard isOn else { return }
            ringBell()
            Task {
                if await FeedAlarmManager.requestAuthorization() {
                    denied = false
                } else {
                    on = false
                    denied = true
                }
            }
        }
    }

    private func ringBell() {
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.45)) { bellRing = true }
        Task {
            try? await Task.sleep(for: .seconds(0.18))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) { bellRing = false }
        }
    }
}

// MARK: - Invite

/// The co-parent invite — also the flow's "made for both of you" moment, so the
/// two parent badges drift together as the page lands. The CKShare is zone-wide,
/// so it can be created before the baby record exists — the records land in the
/// zone at commit. The host owns the share/iCloud state; this is just the page
/// body.
struct InviteStep: View {
    /// nil while the account check is in flight.
    let cloudAvailable: Bool?
    /// The share sheet has been offered (primary becomes "Finish").
    let didOfferShare: Bool
    /// `makeShare()` threw — show a gentle notice, never block.
    let shareFailed: Bool
    let revealed: Bool
    /// Personalizes the badge pair with the name/color picked two pages ago.
    var ownerName = ""
    var ownerColorHex = ParticipantColors.palette[0]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Spacer(minLength: 16)
                HStack(spacing: revealed || reduceMotion ? -16 : 24) {
                    OnboardingInitialBadge(initial: ownerInitial, colorHex: ownerColorHex)
                    OnboardingInitialBadge(initial: "+",
                                           colorHex: ParticipantColors.next(avoiding: [ownerColorHex]))
                }
                .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.75), value: revealed)
                .onboardingEntrance(revealed)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("You and your co-parent")

                OnboardingStepHeader(
                    eyebrow: "Set up · 3 of 3",
                    title: "Made for both of you"
                )
                .onboardingEntrance(revealed, index: 1)

                PrimerCard(
                    icon: "person.badge.plus",
                    tint: AppColor.accentSleep,
                    title: "One link, two phones",
                    message: "Send one link. Your co-parent sees every feed, sleep, and diaper seconds after you log it — synced over iCloud, private to the two of you. No account, no server."
                )
                .onboardingEntrance(revealed, index: 2)

                // The app is TestFlight-only, so the link has no App Store page
                // to fall back to — install order is forced, and nothing else
                // in the flow says so.
                InlineNoticeCard(
                    icon: "arrow.down.app",
                    message: "Have your partner install Two of Us first — the invite link only works once the app is on their iPhone."
                )
                .onboardingEntrance(revealed, index: 3)

                if cloudAvailable == false {
                    InlineNoticeCard(
                        icon: "icloud.slash",
                        message: "iCloud is off on this iPhone — you can invite your partner later from Settings → People."
                    )
                    .onboardingEntrance(revealed, index: 4)
                } else if shareFailed {
                    InlineNoticeCard(
                        icon: "wifi.exclamationmark",
                        message: "Couldn't reach iCloud just now — you can invite anytime from Settings → People."
                    )
                } else if didOfferShare {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppColor.urgencyGreen)
                        Text("Invitation ready — manage sharing anytime in Settings → People.")
                            .font(.footnote)
                            .foregroundStyle(AppColor.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .surfaceCard(cornerRadius: 14)
                }
                Spacer(minLength: 16)
            }
            .padding(.horizontal, 28)
        }
        .contentMargins(.bottom, OnboardingLayout.barClearance, for: .scrollContent)
        .scrollBounceBehavior(.basedOnSize)
    }

    private var ownerInitial: String {
        ownerName.trimmingCharacters(in: .whitespaces).first.map(String.init)?.uppercased() ?? "A"
    }
}

// MARK: - Previews

#Preview("Rhythm") {
    struct Demo: View {
        @State private var interval = 180
        @State private var presets: [Double] = [2, 3, 4]
        var body: some View {
            ZStack {
                AmbientBackground(stop: AmbientStop(subtle: true, top: AppColor.accentFeed, bottom: AppColor.accentSleep))
                RhythmStep(intervalMinutes: $interval, ozPresets: $presets, revealed: true)
            }
        }
    }
    return Demo()
}

#Preview("Reminders · dark") {
    struct Demo: View {
        @State private var on = true
        var body: some View {
            ZStack {
                AmbientBackground(stop: AmbientStop(subtle: true, top: AppColor.accentFeed, bottom: AppColor.accentSleep))
                RemindersStep(on: $on, revealed: true)
            }
            .preferredColorScheme(.dark)
        }
    }
    return Demo()
}

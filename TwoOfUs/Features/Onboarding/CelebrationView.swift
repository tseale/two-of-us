import SwiftUI

/// What the post-setup celebration says — built by whichever flow just finished
/// (owner onboarding or the co-parent join flow).
struct CelebrationData: Equatable {
    let title: String
    let subtitle: String?

    /// Owner just created the baby: "Welcome home, Miller".
    static func owner(babyName: String) -> CelebrationData {
        CelebrationData(
            title: babyName.isEmpty ? "Welcome home" : "Welcome home, \(babyName)",
            subtitle: "Logged moments start now — we'll finish setting up as you go."
        )
    }

    /// Co-parent just joined: "Welcome to Miller's log".
    static func joiner(babyName: String) -> CelebrationData {
        CelebrationData(
            title: babyName.isEmpty ? "You're in" : "Welcome to \(babyName)'s log",
            subtitle: "You'll both see every update."
        )
    }
}

/// The closing bookend to the launch splash: an opaque full-screen moment hosted
/// by `RootView` *above* the route swap, so onboarding → main never hard-cuts.
/// The mark blooms, the baby light gives one heartbeat, the welcome line fades up,
/// then the host fades the whole overlay away to reveal Home already settled.
struct CelebrationView: View {
    let data: CelebrationData
    /// Called when the moment has played; the host fades the overlay out.
    var onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var glowOpacity: Double = 0
    @State private var babyScale: CGFloat = 1
    @State private var textOpacity: Double = 0
    @State private var textOffset: CGFloat = 8

    /// Near-black ink for the night-sky stage the mark sits on (see `CradleMark`:
    /// the artwork wants a dark backdrop in both color schemes).
    private let ink = Color(hex: "070710")

    var body: some View {
        ZStack {
            // Opaque base — the route swap underneath stays invisible.
            AppColor.bg.ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    // Soft night-sky halo behind the mark.
                    Circle()
                        .fill(RadialGradient(
                            stops: [
                                .init(color: ink, location: 0),
                                .init(color: ink, location: 0.45),
                                .init(color: ink.opacity(0), location: 1),
                            ],
                            center: .center, startRadius: 0, endRadius: 160
                        ))
                        .frame(width: 320, height: 320)
                    CradleMark(size: 170, babyScale: babyScale, glowOpacity: glowOpacity)
                }

                VStack(spacing: 8) {
                    Text(data.title)
                        .font(AppFont.hero(28))
                        .foregroundStyle(AppColor.text)
                    Text("🤍")
                        .font(.system(size: 22))
                    if let subtitle = data.subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(AppColor.text2)
                    }
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .opacity(textOpacity)
                .offset(y: textOffset)
            }
        }
        .accessibilityElement(children: .combine)
        .task { await run() }
    }

    @MainActor private func run() async {
        if reduceMotion {
            glowOpacity = 1
            withAnimation(.easeIn(duration: 0.3)) {
                textOpacity = 1
                textOffset = 0
            }
            try? await Task.sleep(for: .seconds(1.2))
            onDone()
            return
        }

        // Mirror the splash: glow bloom, one calm heartbeat, text fades up.
        withAnimation(.easeInOut(duration: 0.6)) { glowOpacity = 1 }
        withAnimation(.easeInOut(duration: 0.7).delay(0.15)) { babyScale = 1.07 }
        withAnimation(.easeInOut(duration: 0.5).delay(0.85)) { babyScale = 1.0 }
        withAnimation(.easeOut(duration: 0.45).delay(0.4)) {
            textOpacity = 1
            textOffset = 0
        }

        try? await Task.sleep(for: .seconds(2.0))
        onDone()
    }
}

#Preview("Owner") {
    CelebrationView(data: .owner(babyName: "Miller"), onDone: {})
}

#Preview("Joiner, dark") {
    CelebrationView(data: .joiner(babyName: "Miller"), onDone: {})
        .preferredColorScheme(.dark)
}

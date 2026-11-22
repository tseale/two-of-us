import SwiftUI

/// The bench for building the painted hill (`docs/SKY_BUILD_PLAN.md`, stage
/// 1): one screen per spike, reached from Settings → Data only while the
/// device-local "Painted sky" switch is on. Nothing here is the finished
/// sky; each screen exists to answer one of the plan's risks on a real
/// display.
struct SkyBench: View {
    var body: some View {
        List {
            Section {
                NavigationLink("1 · Sky field and tone") { SkyFieldSpike() }
                NavigationLink("2 · Land in Core Graphics") { SkyLandSpike() }
            } footer: {
                Text("Each screen tries one piece of the new sky on its own. Tap a sky to hide its controls.")
            }
        }
        .navigationTitle("Sky bench")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The spike a `-skyBench <name>` launch opens.
    @ViewBuilder
    static func spike(named name: String?) -> some View {
        switch name {
        case "field": SkyFieldSpike()
        case "land": SkyLandSpike()
        default: SkyBench()
        }
    }
}

/// Launch arguments for shooting the bench from the simulator, e.g.
/// `-skyBench field -skyBenchHour 16.17 -skyBenchPanel 0`. Read everywhere,
/// but only a DEBUG build opens the bench from one (`SkyBenchLaunch`).
enum SkyBenchArguments {
    static func text(_ key: String) -> String? { UserDefaults.standard.string(forKey: key) }

    static func number(_ key: String) -> Double? {
        UserDefaults.standard.object(forKey: key) == nil ? nil : UserDefaults.standard.double(forKey: key)
    }
}

/// DEBUG-only: `-skyBench <spike>` opens the bench over the app at launch,
/// for deterministic captures. Compiled out of TestFlight builds.
struct SkyBenchLaunch: ViewModifier {
    #if DEBUG
    @State private var shown = SkyBenchArguments.text("skyBench") != nil
    #endif

    func body(content: Content) -> some View {
        #if DEBUG
        content.fullScreenCover(isPresented: $shown) {
            NavigationStack { SkyBench.spike(named: SkyBenchArguments.text("skyBench")) }
        }
        #else
        content
        #endif
    }
}

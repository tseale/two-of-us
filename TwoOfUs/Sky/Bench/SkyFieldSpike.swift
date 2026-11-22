import SwiftUI

/// Spike 1 (plan risk 3): the sky field as a shader, and its tone. The tall
/// sky alone, at any hour of 21 November, with the hush, the room's depth
/// and the camera's `look` on sliders — to see whether the `.metal` file
/// builds, whether the print matches the lab's, and whether a moving tone
/// steps on a near-black sky.
struct SkyFieldSpike: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale

    @State private var hour = SkyBenchArguments.number("skyBenchHour") ?? (16 + 10.0 / 60)
    @State private var hush = SkyBenchArguments.number("skyBenchHush")
    @State private var depth = SkyBenchArguments.number("skyBenchDepth") ?? 0
    @State private var look = SkyBenchArguments.number("skyBenchLook") ?? 0
    @State private var probe = Int(SkyBenchArguments.number("skyBenchProbe") ?? 0)
    @State private var cover = SkyBenchArguments.text("skyBenchWorld") == "cover"
    @State private var showsPanel = SkyBenchArguments.number("skyBenchPanel") != 0
    @State private var breathes = false

    @State private var made: (texture: SkyFieldTexture, minute: SkyBenchMinute, key: String)?
    @State private var cost: Double = 0

    private var display: SkyWorld.Display { cover ? .cover : .slab }
    private var key: String { "\(hour)|\(scheme == .dark)|\(cover)" }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.black
                if let made {
                    TimelineView(.animation(paused: !breathes)) { context in
                        let wave = breathes
                            ? 0.5 - 0.5 * cos(context.date.timeIntervalSinceReferenceDate * 2 * .pi / 6) : 0
                        sky(made.texture, made.minute, wave: wave)
                    }
                    .scaleEffect(min(1, proxy.size.width / display.size.width), anchor: .topLeading)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { showsPanel.toggle() }
        .overlay(alignment: .bottom) { if showsPanel { panel } }
        .toolbar(showsPanel ? .visible : .hidden, for: .navigationBar)
        .navigationTitle("Sky field")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: key) { await make() }
    }

    private func sky(_ texture: SkyFieldTexture, _ minute: SkyBenchMinute, wave: Double) -> some View {
        let world = minute.world
        let camera = SkyCamera.offset(of: world.sky, look: look, scale: Double(displayScale), world: world)
        let natural = minute.air.presence
        // "Breathe" runs the tone a bedtime runs: the hush falling and the
        // room deepening together, and back, every six seconds.
        let presence = breathes ? SkyMath.lerp(hush ?? natural, 0, wave) : (hush ?? natural)
        let room = breathes ? SkyMath.lerp(depth, 1, wave) : depth
        return SkyField(texture: texture, minute: minute, presence: presence, depth: room, probe: probe)
            .offset(x: texture.origin.x + minute.display.anchorX + camera.width,
                    y: texture.origin.y + camera.height)
    }

    private func make() async {
        let date = SkyBenchMinute.date(hour: hour)
        let display = display
        let dark = scheme == .dark
        let key = key
        // As the Land screen does: nothing while the Hour slider is moving,
        // then one texture, made through the bench's one painter.
        try? await Task.sleep(for: .seconds(0.2))
        guard !Task.isCancelled else { return }
        let started = Date.now
        let result = await SkyBenchPainter.shared.paint { () -> (SkyFieldTexture, SkyBenchMinute)? in
            let minute = SkyBenchMinute.at(date, display: display, dark: dark,
                                           calendar: SkyBenchMinute.chicagoTime)
            guard let texture = SkyFieldTexture.make(for: minute) else { return nil }
            return (texture, minute)
        }
        guard let result, !Task.isCancelled, key == self.key else { return }
        cost = Date.now.timeIntervalSince(started) * 1000
        made = (result.0, result.1, key)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 6) {
            slider("Hour \(SkyBenchMinute.clock(hour))", $hour, 0...23.99)
            slider("Hush \(String(format: "%.2f", hush ?? made?.minute.air.presence ?? 1))",
                   Binding(get: { hush ?? made?.minute.air.presence ?? 1 }, set: { hush = $0 }), 0...1)
            slider("Room \(String(format: "%.2f", depth))", $depth, 0...1)
            slider("Look \(String(format: "%.2f", look))", $look, 0...1)
            HStack {
                Toggle("Breathe", isOn: $breathes)
                Toggle("Duo", isOn: $cover)
            }
            HStack {
                Picker("Probe", selection: $probe) {
                    Text("Sky").tag(0)
                    Text("Texel").tag(1)
                    Text("Grey").tag(2)
                    Text("Bits").tag(3)
                }
                .pickerStyle(.segmented)
                Button("Natural") { hush = nil }
            }
            if let made {
                Text("\(made.texture.columns) × \(made.texture.rows) samples in \(Int(cost)) ms · sun \(String(format: "%.1f", made.minute.sunAltitude))°")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .font(.footnote)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(12)
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title).monospacedDigit().frame(width: 92, alignment: .leading)
            Slider(value: value, in: range)
        }
    }
}

extension SkyBenchMinute {
    /// Chicago's clock, the lab's.
    static var chicagoTime: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago") ?? .current
        return calendar
    }

    /// 21 November 2026 at `hour` (a fraction is minutes) in Chicago.
    static func date(hour: Double) -> Date {
        let midnight = chicagoTime.date(from: DateComponents(year: 2026, month: 11, day: 21)) ?? .now
        return midnight.addingTimeInterval(hour * 3600)
    }

    static func clock(_ hour: Double) -> String {
        let minutes = Int((hour * 60).rounded())
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}

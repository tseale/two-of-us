import SwiftUI

/// Spike 2 (plan risk 1): the land in Core Graphics. The slab's hills,
/// painted by `SkyLandPainter` off the main thread and laid over the sky
/// field, each plane on its own offset — to judge the drawing against the
/// lab's and to read what a plane costs to paint.
struct SkyLandSpike: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale

    @State private var hour = SkyBenchArguments.number("skyBenchHour") ?? (16 + 10.0 / 60)
    @State private var look = SkyBenchArguments.number("skyBenchLook") ?? 0
    @State private var showsPanel = SkyBenchArguments.number("skyBenchPanel") != 0
    @State private var only = SkyBenchArguments.text("skyBenchPlane")

    @State private var made: Made?
    private var key: String { "\(hour)|\(scheme == .dark)" }

    private struct Made {
        let key: String
        let minute: SkyBenchMinute
        let texture: SkyFieldTexture
        let plates: [SkyLandPainter.Plate]
        let costs: [(String, Double)]
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.black
                if let made {
                    let world = made.minute.world
                    let scale = Double(displayScale)
                    let sky = SkyCamera.offset(of: world.sky, look: look, scale: scale, world: world)
                    SkyField(texture: made.texture, minute: made.minute,
                             presence: made.minute.air.presence, depth: 0)
                        .offset(x: made.texture.origin.x + sky.width, y: made.texture.origin.y + sky.height)
                    ForEach(made.plates, id: \.id) { plate in
                        if only == nil || only == plate.id.rawValue {
                            let camera = SkyCamera.offset(of: world.plane(plate.id), look: look, scale: scale,
                                                          world: world)
                            Image(decorative: plate.image, scale: displayScale)
                                .offset(x: plate.origin.x + camera.width, y: plate.origin.y + camera.height)
                        }
                    }
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
        .navigationTitle("Land")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: key) { await make() }
    }

    private func make() async {
        let date = SkyBenchMinute.date(hour: hour)
        let dark = scheme == .dark
        let scale = Double(displayScale)
        let key = key
        // A drag of the Hour slider asks for a picture at every value it
        // passes, and each new value cancels this task. So wait for the
        // slider to rest before painting anything…
        try? await Task.sleep(for: .seconds(0.2))
        guard !Task.isCancelled else { return }
        // …and paint through the bench's one painter, in this task, looking
        // between planes for a newer value (or the screen gone).
        let result = await SkyBenchPainter.shared.paint { () -> Made? in
            let minute = SkyBenchMinute.at(date, display: .slab, dark: dark, calendar: SkyBenchMinute.chicagoTime)
            guard let texture = SkyFieldTexture.make(for: minute) else { return nil }
            var plates: [SkyLandPainter.Plate] = []
            var costs: [(String, Double)] = []
            for plane in SkyLandPainter.slab {
                guard !Task.isCancelled else { return nil }
                let started = Date.now
                guard let plate = SkyLandPainter.paint(plane, minute: minute, scale: scale) else { continue }
                costs.append((plane.id.rawValue, Date.now.timeIntervalSince(started) * 1000))
                plates.append(plate)
            }
            return Made(key: key, minute: minute, texture: texture, plates: plates, costs: costs)
        }
        guard let result, !Task.isCancelled, key == self.key else { return }
        made = result
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Hour \(SkyBenchMinute.clock(hour))").monospacedDigit().frame(width: 92, alignment: .leading)
                Slider(value: $hour, in: 0...23.99)
            }
            HStack {
                Text("Look \(String(format: "%.2f", look))").monospacedDigit().frame(width: 92, alignment: .leading)
                Slider(value: $look, in: 0...1)
            }
            if let made {
                Text(made.costs.map { "\($0.0) \(Int($0.1)) ms" }.joined(separator: " · "))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                let bytes = made.plates.reduce(0) { $0 + $1.image.bytesPerRow * $1.image.height }
                Text("\(made.plates.count) plates, \(bytes / 1_048_576) MB at \(Int(displayScale))×")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .font(.footnote)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(12)
    }
}

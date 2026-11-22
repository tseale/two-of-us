import QuartzCore
import SwiftUI

/// Spikes 3 to 6 (plan risks 2, 4, 5, 6), tried on the real Home while the
/// device-local "Painted sky" switch is on: a stand-in sky hoisted out of
/// the list and laid under it (`SkyBenchStage`), each card fading on its own
/// (`SkyBenchVeil`), the camera run at the display's pace while Home ticks,
/// and the header's real rects (`SkyBenchMeasure`). None of it is the
/// finished `HillSky`; with the switch off none of it is in the tree.
@MainActor
@Observable
final class SkyBenchDriver {
    static let shared = SkyBenchDriver()

    /// How far the camera has looked up.
    var look = Glide.resting(at: SkyBenchArguments.number("skyBenchLook") ?? 0)
    /// Whether a move is running (the stage's fast clock runs only then).
    var moving = false
    /// The cards' opacity, each card's own.
    var cards = SkyBenchArguments.number("skyBenchCards") ?? 1
    /// An hour of 21 November to show instead of now.
    var hour = SkyBenchArguments.number("skyBenchHour")
    /// The header's pieces where they really are, in the window.
    var rects: [String: CGRect] = [:]
    var showsRects = SkyBenchArguments.number("skyBenchRects") == 1
    /// What the last move measured.
    var report = ""

    private let meter = FrameMeter()

    /// Looks up, or back down, on the camera's own curve and at the lab's
    /// lengths (2.7 s up on a slab, 2.4 s on the Duo; 2.6 s down).
    func toggleLook(slab: Bool) {
        let up = look.to < 0.5
        let length = up ? (slab ? 2.4 : 2.1) : 2.6
        look = look.retargeted(to: up ? 1 : 0, at: .now, over: length, after: up ? 0.3 : 0.1)
        moving = true
        report = "measuring…"
        meter.start()
        Task {
            try? await Task.sleep(for: .seconds(length + 0.5))
            moving = false
            report = meter.stop()
        }
    }

    /// `-skyBenchPlay 1`: plays the rise, then the cards away and back, by
    /// itself a few seconds after launch — for recording from the simulator.
    func playIfAsked(slab: Bool) async {
        guard SkyBenchArguments.number("skyBenchPlay") == 1, !played else { return }
        played = true
        try? await Task.sleep(for: .seconds(5))
        toggleLook(slab: slab)
        try? await Task.sleep(for: .seconds(4))
        toggleCards()
        try? await Task.sleep(for: .seconds(2))
        toggleCards()
    }
    private var played = false

    /// The cards step back, or return, on the plan's curves.
    func toggleCards() {
        let away = cards > 0.5
        withAnimation(away ? .easeInOut(duration: 1.0) : .easeOut(duration: 1.2)) { cards = away ? 0 : 1 }
    }
}

/// Counts the display's frames over a move: how many, the longest, and how
/// many ran long.
@MainActor
private final class FrameMeter: NSObject {
    private var link: CADisplayLink?
    private var stamps: [CFTimeInterval] = []

    func start() {
        stamps = []
        link?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) { stamps.append(link.timestamp) }

    func stop() -> String {
        link?.invalidate()
        link = nil
        guard stamps.count > 2, let first = stamps.first, let last = stamps.last else { return "no frames" }
        let gaps = zip(stamps.dropFirst(), stamps).map { $0 - $1 }
        let usual = gaps.sorted()[gaps.count / 2]
        let long = gaps.filter { $0 > usual * 1.5 }.count
        return String(format: "%d frames in %.1f s · %.0f fps · longest %.0f ms · %d long",
                      stamps.count, last - first, Double(gaps.count) / (last - first),
                      (gaps.max() ?? 0) * 1000, long)
    }
}

// MARK: - The hoisted sky

/// A stand-in for `HillSky`: the sky field and, on a slab, the hills
/// `SkyLandPainter` can paint, each on its own offset, filling the display
/// under Home's list.
struct SkyBenchStage: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale
    @State private var driver = SkyBenchDriver.shared
    @State private var made: Made?

    private struct Made {
        let key: String
        let minute: SkyBenchMinute
        let texture: SkyFieldTexture
        let plates: [SkyLandPainter.Plate]
    }

    var body: some View {
        GeometryReader { proxy in
            let slab = proxy.size.height > 700
            TimelineView(.everyMinute) { tick in
                let date = driver.hour.map(SkyBenchMinute.date(hour:)) ?? tick.date
                let key = "\(Int(date.timeIntervalSinceReferenceDate / 60))|\(scheme == .dark)|\(slab)"
                ZStack(alignment: .topLeading) {
                    Color.black
                    if let made {
                        TimelineView(.animation(paused: !driver.moving)) { frame in
                            ZStack(alignment: .topLeading) {
                                layers(made, look: driver.look.value(at: driver.moving ? frame.date : .now))
                            }
                            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                        }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .clipped()
                .task(id: key) { await make(date, slab: slab, key: key) }
                .task { await driver.playIfAsked(slab: slab) }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func layers(_ made: Made, look: Double) -> some View {
        let world = made.minute.world
        let scale = Double(displayScale)
        let sky = SkyCamera.offset(of: world.sky, look: look, scale: scale, world: world)
        SkyField(texture: made.texture, minute: made.minute, presence: made.minute.air.presence, depth: 0)
            .offset(x: made.texture.origin.x + sky.width, y: made.texture.origin.y + sky.height)
        ForEach(made.plates, id: \.id) { plate in
            let camera = SkyCamera.offset(of: world.plane(plate.id), look: look, scale: scale, world: world)
            Image(decorative: plate.image, scale: displayScale)
                .offset(x: plate.origin.x + camera.width, y: plate.origin.y + camera.height)
        }
    }

    private func make(_ date: Date, slab: Bool, key: String) async {
        let dark = scheme == .dark
        let scale = Double(displayScale)
        let calendar: Calendar = driver.hour == nil ? .current : SkyBenchMinute.chicagoTime
        // Through the bench's one painter, in this task: a paint the bench's
        // own screens have asked for and this one never run together, and
        // when SwiftUI cancels this task (a new minute, the stage gone) the
        // paint stops at the next plane and shows nothing.
        let result = await SkyBenchPainter.shared.paint { () -> Made? in
            let minute = SkyBenchMinute.at(date, display: slab ? .slab : .cover, dark: dark, calendar: calendar)
            guard let texture = SkyFieldTexture.make(for: minute) else { return nil }
            var plates: [SkyLandPainter.Plate] = []
            if slab {
                for plane in SkyLandPainter.slab {
                    guard !Task.isCancelled else { return nil }
                    guard let plate = SkyLandPainter.paint(plane, minute: minute, scale: scale) else { continue }
                    plates.append(plate)
                }
            }
            return Made(key: key, minute: minute, texture: texture, plates: plates)
        }
        guard let result, !Task.isCancelled else { return }
        made = result
    }
}

// MARK: - On Home

/// Each card's own fade (spike 4): the driver's `cards` as this view's
/// opacity. Not in the tree while the switch is off.
struct SkyBenchVeil: ViewModifier {
    @State private var driver = SkyBenchDriver.shared
    @State private var prefs = LocalPrefs.shared

    func body(content: Content) -> some View {
        if prefs.paintedSky {
            content.opacity(driver.cards)
        } else {
            content
        }
    }
}

/// Reports where a piece of the header really is (spike 6).
struct SkyBenchMeasure: ViewModifier {
    let name: String
    @State private var prefs = LocalPrefs.shared

    func body(content: Content) -> some View {
        if prefs.paintedSky {
            content.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { rect in
                SkyBenchDriver.shared.rects[name] = rect
            }
        } else {
            content
        }
    }
}

extension View {
    func skyBenchVeil() -> some View { modifier(SkyBenchVeil()) }
    func skyBenchMeasure(_ name: String) -> some View { modifier(SkyBenchMeasure(name: name)) }
}

/// The bench's controls on Home: look up or down, send the cards away or
/// bring them back, and what the last move measured.
struct SkyBenchPill: View {
    @State private var driver = SkyBenchDriver.shared

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                if driver.showsRects { rects(in: proxy) }
                VStack(alignment: .leading, spacing: 4) {
                    if !driver.report.isEmpty {
                        Text(driver.report).font(.caption2.monospacedDigit())
                    }
                    HStack(spacing: 14) {
                        Button("Look") { driver.toggleLook(slab: proxy.size.height > 700) }
                        Button("Cards") { driver.toggleCards() }
                        Button("Rects") { driver.showsRects.toggle() }
                    }
                    .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
                .padding(.leading, 12)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
    }

    /// The measured rects, outlined where they are and listed in numbers.
    private func rects(in proxy: GeometryProxy) -> some View {
        let origin = proxy.frame(in: .global).origin
        let named = driver.rects.sorted { $0.key < $1.key }
        return ZStack(alignment: .topLeading) {
            ForEach(named, id: \.key) { name, rect in
                Rectangle()
                    .strokeBorder(.green, lineWidth: 0.5)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX - origin.x, y: rect.minY - origin.y)
            }
            Text(named.map { name, rect in
                String(format: "%@ x %.1f y %.1f w %.1f h %.1f", name, rect.minX, rect.minY, rect.width, rect.height)
            }.joined(separator: "\n") + String(format: "\nsafe top %.1f", proxy.safeAreaInsets.top))
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.green)
                .padding(6)
                .background(.black.opacity(0.7))
                .offset(x: 12, y: 330)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

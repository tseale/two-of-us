import SwiftUI
import Combine

/// The light: the app's own mark at the size of the phone. `CradleMark` is
/// two parent circles with the baby's light between them; on iPhone Duo the
/// phone itself has that shape — two leaves and a hinge — so the field puts a
/// pool of one parent's colour behind each leaf (periwinkle leading, teal
/// trailing) and, whenever he sleeps, his warm light in the hinge between
/// them.
///
/// Falling asleep dims the room, it never brightens it: the pools drop to
/// about half and the hinge light comes on, breathing on the day strip's own
/// rhythm. At night the ground under them turns from black to the night ink.
/// No stars, no hue by the clock, never an urgency colour.
///
/// The field is a background and nothing else: it is hidden from VoiceOver,
/// never takes a touch, and every layout must be complete without it — it
/// turns itself off (plain `AppColor.bg`) under Reduce Transparency,
/// Increase Contrast and Low Power Mode. It is cheap: at most four gradient
/// fills (five under the demo-mode pill — see `Plan.topShade`), no blur
/// filters, no `TimelineView`; the only motion is one opacity animation, and
/// none under Reduce Motion.
///
/// **Placing it.** Give the field the same frame as the content it sits
/// behind — a `ZStack` sibling, or a `.background { }` — and do NOT add
/// `.ignoresSafeArea()`. It paints past its own frame through the safe area
/// by itself, so the pools reach the display's corners and run under the
/// system strip, while the hinge stays expressed in the coordinates of the
/// frame you gave it — the same reader `PaneLayout` measured, so
/// `.verticalCrease(x: layout.band.midX)` is right whichever side the strip
/// is on. (Wrapped in `ignoresSafeArea`, its frame would be the whole display
/// and that x would be off by the strip's width when the strip is leading.)
struct CradleField: View {
    /// Where the hinge is in the pose the field is drawn for.
    enum Hinge: Equatable {
        /// The inner display in landscape — flat, or folded like a book: the
        /// fold runs top to bottom at this x (in the field's own frame).
        case verticalCrease(x: CGFloat)
        /// The inner display in portrait — flat, or tabletop: the fold runs
        /// side to side at this y (in the field's own frame).
        case horizontalCrease(y: CGFloat)
        /// The outer display stood on its side like a tent: the hinge is the
        /// ridge, the display's top edge.
        case ridge
        /// The closed cover: the hinge is the spine, down one side edge. No
        /// pools here and no night ground — the cover stays true black, with
        /// only a faint bloom on the spine while he sleeps.
        case spine(SpineEdge)
        /// No hinge to light (the pools only).
        case none
    }

    /// Which side edge of the closed cover the spine is on.
    enum SpineEdge: Equatable {
        case leading, trailing
        /// The edge away from the system strip — where the hinge is, whichever
        /// way up the phone is held. Worked out from the field's own safe
        /// area; with nothing to go on, the leading edge.
        case oppositeSystemStrip
    }

    let hinge: Hinge
    /// A sleep is running: the pools dim and the hinge light comes on.
    let asleep: Bool
    /// That sleep is a night's sleep rather than a nap ("sleeping", not
    /// "napping", in `SleepLanguage`'s words): in dark mode the ground is the
    /// night ink. Ignored while he is awake.
    let night: Bool
    /// How far below the top of its window the field's frame starts, beyond
    /// its top safe-area inset — `PaneLayout.topOffset`: zero, unless a row
    /// sits above the frame (the demo-mode pill's). The field cannot paint
    /// up through such a row, so it softens its own top edge under it
    /// instead (`Plan.topShade`).
    let topOffset: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    init(hinge: Hinge, asleep: Bool, night: Bool, topOffset: CGFloat = 0) {
        self.hinge = hinge
        self.asleep = asleep
        self.night = night
        self.topOffset = topOffset
    }

    /// A change of state is a slow cross-fade — the room dimming, not a cut.
    private static let crossFade = Animation.easeInOut(duration: 1.2)

    /// Off — plain background — wherever the system asks for less: Reduce
    /// Transparency, Increase Contrast, Low Power Mode.
    private var isOn: Bool {
        !(reduceTransparency || contrast == .increased || lowPower)
    }

    /// Peak opacity of the two pools. Asleep is about half of awake; light
    /// mode about half of dark (the same tints read much louder on the light
    /// ground).
    private var poolOpacity: (leading: Double, trailing: Double) {
        let scheme: Double = colorScheme == .dark ? 1 : 0.5
        if asleep {
            return (leading: 0.07 * scheme, trailing: 0.055 * scheme)
        }
        return (leading: 0.13 * scheme, trailing: 0.10 * scheme)
    }

    /// The night ink over black (dark mode only; the light ground never
    /// changes): `nightInk` blended a tenth of the way back toward black.
    private var nightGroundOpacity: Double {
        asleep && night && colorScheme == .dark ? 0.9 : 0
    }

    var body: some View {
        GeometryReader { proxy in
            let plan = Plan.resolve(hinge: hinge, size: proxy.size, insets: proxy.safeAreaInsets,
                                    topOffset: topOffset)
            // Painted larger than the frame it was given, by the safe area on
            // each side, and shifted back so the frame's origin stays put.
            field(plan)
                .frame(width: plan.size.width, height: plan.size.height)
                .clipped()
                .offset(x: -plan.origin.x, y: -plan.origin.y)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onReceive(NotificationCenter.default
            .publisher(for: .NSProcessInfoPowerStateDidChange)
            .receive(on: DispatchQueue.main)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    private func field(_ plan: Plan) -> some View {
        ZStack {
            AppColor.bg
            if isOn {
                if plan.paintsRoom {
                    AppColor.nightInk
                        .opacity(nightGroundOpacity)
                    if let pool = plan.leadingPool {
                        Glow(color: AppColor.accentSleep, reach: pool.reach)
                            .opacity(poolOpacity.leading * pool.strength)
                            .position(pool.center)
                    }
                    if let pool = plan.trailingPool {
                        Glow(color: AppColor.accentFeed, reach: pool.reach)
                            .opacity(poolOpacity.trailing * pool.strength)
                            .position(pool.center)
                    }
                    // Under a row of plain background (the demo-mode pill's)
                    // the room fades in from that colour, instead of
                    // starting at a straight edge with the pools at their
                    // brightest along it.
                    if plan.topShade > 0 {
                        LinearGradient(colors: [AppColor.bg, AppColor.bg.opacity(0)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: plan.topShade)
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                }
                // His light: in the hierarchy only while he sleeps, so it
                // costs nothing — not even a paused animation — by day.
                if asleep, let light = plan.hingeLight {
                    HingeLight(light: light)
                        .transition(.opacity)
                }
            }
        }
        .animation(reduceMotion ? nil : Self.crossFade, value: asleep)
        .animation(reduceMotion ? nil : Self.crossFade, value: night)
    }
}

extension CradleField {
    /// The field for a sleep that may be running: lit while `sleepingSince`
    /// is set, on the night ground once that sleep counts as "sleeping"
    /// rather than "napping" — the same rule every other surface words it by.
    init(hinge: Hinge, sleepingSince: Date?, now: Date = .now, topOffset: CGFloat = 0) {
        let night = sleepingSince.map { !SleepLanguage.isNap(start: $0, end: now) } ?? false
        self.init(hinge: hinge, asleep: sleepingSince != nil, night: night,
                  topOffset: topOffset)
    }
}

// MARK: - Where the lights go

extension CradleField {
    /// One soft light: brightest at `center`, faded to clear by `reach`.
    struct Light: Equatable {
        /// In the painted area's coordinates.
        var center: CGPoint
        /// The horizontal and vertical distance at which it is clear.
        var reach: CGSize
        /// Scales this light's peak opacity (the tent and the cover run
        /// fainter than the inner display).
        var strength: Double
        /// The hinge light's small bright core — the inner display only.
        var hasCore: Bool = false
    }

    /// Everything the field paints for one pose, as plain geometry — a value
    /// of its own rather than part of the view, so it is unit-tested without
    /// a display (`CradleFieldTests`).
    struct Plan: Equatable {
        /// The painted area: the field's frame plus the safe area around it —
        /// the whole display, when the frame is a tab's content area.
        var size: CGSize
        /// Where the field's own frame starts inside the painted area.
        var origin: CGPoint
        /// Pools and the night ground. False on the closed cover, which
        /// stays true black.
        var paintsRoom: Bool
        var leadingPool: Light?
        var trailingPool: Light?
        /// Drawn only while he sleeps.
        var hingeLight: Light?
        /// How much of the room's top edge fades in from the plain
        /// background. Zero in everyday use: the field paints out through
        /// the safe area to the display's edge. Only a row sitting above
        /// the field's frame stops it short, and the one such row is the
        /// demo-mode pill's, a band of plain `AppColor.bg`. The pools are
        /// brightest along their top edge (and the night ground is not
        /// black), so cut off by that band they would meet it in a hard
        /// line; the shade lets the room rise from behind it instead.
        var topShade: CGFloat = 0

        // The lights were drawn on boards the size of each display, as
        // radial gradients of a given radius that reach clear part-way out;
        // `reach` scales those numbers to the display the field is really on.
        private static let innerLandscape = CGSize(width: 951, height: 669)
        private static let innerPortrait = CGSize(width: 669, height: 951)
        private static let tent = CGSize(width: 678, height: 466)
        private static let cover = CGSize(width: 466, height: 678)
        /// The pools are clear at 72 % of their drawn radius, the hinge light
        /// at 70 % of its.
        private static let poolFade: CGFloat = 0.72
        private static let lightFade: CGFloat = 0.70
        /// The hinge light sits below the middle of a vertical hinge — low in
        /// the overlap, where the mark cradles the baby's light.
        private static let hingeHeight: CGFloat = 0.62
        /// How far down the shade under a row above the field runs.
        private static let topShadeDepth: CGFloat = 96

        private static func reach(_ radiusX: CGFloat, _ radiusY: CGFloat, fade: CGFloat,
                                  drawnOn board: CGSize, in full: CGSize) -> CGSize {
            CGSize(width: radiusX * fade / board.width * full.width,
                   height: radiusY * fade / board.height * full.height)
        }

        /// Where the pools and the hinge light go for a field laid out at
        /// `size` with `insets` of safe area around it. `hinge` positions are
        /// in the field's own frame; the plan's are in the painted area.
        /// `topOffset` is non-zero when a row sits above the field's frame
        /// (see `topShade`).
        static func resolve(hinge: Hinge, size: CGSize, insets: EdgeInsets,
                            topOffset: CGFloat = 0) -> Plan {
            let full = CGSize(width: size.width + insets.leading + insets.trailing,
                              height: size.height + insets.top + insets.bottom)
            let origin = CGPoint(x: insets.leading, y: insets.top)
            var plan = Plan(size: full, origin: origin, paintsRoom: true,
                            leadingPool: nil, trailingPool: nil, hingeLight: nil)

            switch hinge {
            case .verticalCrease(let x):
                // One pool from the top outer corner of each leaf.
                let pool = reach(640, 560, fade: poolFade, drawnOn: innerLandscape, in: full)
                plan.leadingPool = Light(center: .zero, reach: pool, strength: 1)
                plan.trailingPool = Light(center: CGPoint(x: full.width, y: 0),
                                          reach: pool, strength: 1)
                plan.hingeLight = Light(
                    center: CGPoint(x: origin.x + x, y: full.height * hingeHeight),
                    reach: reach(280, 500, fade: lightFade, drawnOn: innerLandscape, in: full),
                    strength: 1, hasCore: true)

            case .horizontalCrease(let y):
                // The leaves are the top and bottom halves: the pools take
                // the two corners farthest from each other.
                let pool = reach(620, 560, fade: poolFade, drawnOn: innerPortrait, in: full)
                plan.leadingPool = Light(center: .zero, reach: pool, strength: 1)
                plan.trailingPool = Light(center: CGPoint(x: full.width, y: full.height),
                                          reach: pool, strength: 1)
                plan.hingeLight = Light(
                    center: CGPoint(x: full.width / 2, y: origin.y + y),
                    reach: reach(560, 220, fade: lightFade, drawnOn: innerPortrait, in: full),
                    strength: 1, hasCore: true)

            case .ridge:
                // The light is along the top, so the pools rise from the
                // bottom corners. Everything a little fainter: the outer
                // display is small, and close to the eye on a nightstand.
                plan.leadingPool = Light(
                    center: CGPoint(x: 0, y: full.height),
                    reach: reach(560, 460, fade: poolFade, drawnOn: tent, in: full),
                    strength: 1)
                plan.trailingPool = Light(
                    center: CGPoint(x: full.width, y: full.height),
                    reach: reach(520, 420, fade: poolFade, drawnOn: tent, in: full),
                    strength: 0.8)
                // Centred over the content, not the content plus the strip.
                plan.hingeLight = Light(
                    center: CGPoint(x: origin.x + size.width / 2, y: 0),
                    reach: reach(560, 280, fade: lightFade, drawnOn: tent, in: full),
                    strength: 0.8)

            case .spine(let edge):
                plan.paintsRoom = false
                let onTrailingEdge: Bool
                switch edge {
                case .leading: onTrailingEdge = false
                case .trailing: onTrailingEdge = true
                // The strip is the side with the larger inset; the spine is
                // the other one.
                case .oppositeSystemStrip: onTrailingEdge = insets.leading > insets.trailing
                }
                plan.hingeLight = Light(
                    center: CGPoint(x: onTrailingEdge ? full.width : 0,
                                    y: full.height * hingeHeight),
                    reach: reach(220, 420, fade: lightFade, drawnOn: cover, in: full),
                    strength: 0.55)

            case .none:
                let pool = reach(640, 560, fade: poolFade, drawnOn: innerLandscape, in: full)
                plan.leadingPool = Light(center: .zero, reach: pool, strength: 1)
                plan.trailingPool = Light(center: CGPoint(x: full.width, y: 0),
                                          reach: pool, strength: 1)
            }
            // Half a point of slack: a reader with nothing above it can
            // still measure a hair off the top of its window.
            if plan.paintsRoom, topOffset > 0.5 {
                plan.topShade = min(topShadeDepth, full.height)
            }
            return plan
        }
    }
}

// MARK: - The lights

/// One soft elliptical light. The gradient is drawn once, small and round,
/// and stretched to the ellipse it needs — a transform, not a blur filter and
/// not a display-sized bitmap.
private struct Glow: View {
    let color: Color
    /// Where it has faded to clear, horizontally and vertically.
    let reach: CGSize

    private static let radius: CGFloat = 64

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [color, color.opacity(0)],
                                 center: .center, startRadius: 0, endRadius: Self.radius))
            .frame(width: Self.radius * 2, height: Self.radius * 2)
            .scaleEffect(x: reach.width / Self.radius, y: reach.height / Self.radius)
    }
}

/// The baby's light in the hinge: a wide cream glow and, on the inner
/// display, a small bright core. It breathes between 0.6 and 1 of its
/// strength on the day strip's own constant (the glow at the strip's now
/// edge), so the two pulse as one — and holds still under Reduce Motion.
private struct HingeLight: View {
    let light: CradleField.Light

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        ZStack {
            Glow(color: AppColor.nightlightCream, reach: light.reach)
                .opacity(0.17 * light.strength)
                .position(light.center)
            if light.hasCore {
                Glow(color: AppColor.nightlightCream, reach: CGSize(width: 40, height: 40))
                    .opacity(0.20 * light.strength)
                    .position(light.center)
            }
        }
        .opacity(reduceMotion ? 1 : (breathing ? 1 : 0.6))
        .animation(reduceMotion ? nil
                   : .easeInOut(duration: 2.6).repeatForever(autoreverses: true),
                   value: breathing)
        .onAppear { if !reduceMotion { breathing = true } }
        .onDisappear { breathing = false }
        .onChange(of: reduceMotion) { _, reduced in breathing = !reduced }
    }
}

#Preview("Open in landscape, asleep at night") {
    CradleField(hinge: .verticalCrease(x: 475.5), asleep: true, night: true)
        .frame(width: 951, height: 669)
        .preferredColorScheme(.dark)
}

#Preview("Open in landscape, awake") {
    CradleField(hinge: .verticalCrease(x: 475.5), asleep: false, night: false)
        .frame(width: 951, height: 669)
        .preferredColorScheme(.dark)
}

#Preview("Closed cover, asleep") {
    CradleField(hinge: .spine(.leading), asleep: true, night: true)
        .frame(width: 466, height: 678)
        .preferredColorScheme(.dark)
}

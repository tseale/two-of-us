import Foundation
import CoreGraphics

/// One minute of the hill, for the bench: the light, the season and where
/// the sun stands, worked out from the app's own clocks the way the lab's
/// `resolve` does. A stand-in for the bench's spikes only — the sun's and
/// the moon's places belong to `SkyBodies` once it lands, and the wiring
/// from Home to `SkyInputs` at stage 2.
struct SkyBenchMinute {
    let date: Date
    let display: SkyWorld.Display
    let palette: HillPalette
    /// The sun's altitude, in degrees.
    let sunAltitude: Double
    /// The sun's x as a fraction of the anchor window (`bodyX`: the
    /// baseline's, but for the slab's setting side).
    let sunXFraction: Double
    /// The moon's, while it is up.
    let moonXFraction: Double?

    var world: SkyWorld { display.world }
    var air: Air { palette.air }

    /// The sun's x in world points.
    var sunX: Double { sunXFraction * Double(display.anchorWidth) }
    /// The sun's rest-pose y in the tall sky (`pal.sunSkyY`).
    /// World x of the light the land answers: the sun until it is well
    /// down, then the moon.
    var lampX: Double {
        palette.byMoon ? (moonXFraction ?? sunXFraction) * Double(display.anchorWidth) : sunX
    }
    var sunSkyY: Double { Double(world.horizon) - SkyBenchMinute.height(of: sunAltitude, in: world) }

    /// The signature frame's minute: 21 November 2026, 4:10 pm in Chicago.
    static var signatureDate: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago") ?? .current
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 16, minute: 10)) ?? .now
    }

    /// Chicago, where the lab stands.
    static let chicago = SkyPlace(latitude: 41.8781, longitude: -87.6298)

    static func at(_ date: Date, display: SkyWorld.Display, dark: Bool, depth: Double = 0,
                   presence: Double? = nil, place: SkyPlace = chicago,
                   calendar: Calendar = .current) -> SkyBenchMinute {
        let altitude = SolarClock.altitudeInDegrees(at: date, latitude: place.latitude, longitude: place.longitude)
        let day = SolarClock.day(containing: date, latitude: place.latitude, longitude: place.longitude,
                                 calendar: calendar)
        let phase = day.map { SolarClock.phase(at: date, in: $0) } ?? .day(0.5)
        var moon: HillPalette.Moon?
        var moonX: Double?
        let world = display.world
        if let pass = MoonClock.passProgress(at: date, latitude: place.latitude, longitude: place.longitude) {
            let position = MoonClock.position(at: date, latitude: place.latitude, longitude: place.longitude)
            moon = HillPalette.Moon(altitude: position.altitude * 180 / .pi,
                                    fraction: MoonClock.illumination(at: date).fraction)
            var x = SkyPalette.bodyPosition(progress: pass).x
            if let sets = world.sets, let moon {
                let weight = SkyMath.smoothstep(0.5, 0.62, x) * (1 - SkyMath.smoothstep(6, 12, moon.altitude))
                x -= weight * Double(sets.moon) / Double(display.anchorWidth)
            }
            moonX = x
        }
        let season = SkySeason.at(date, place: place, calendar: calendar)
        let morning = HillPalette.isMorning(phase)
        let palette: HillPalette
        if let presence {
            palette = HillPalette(sunAltitude: altitude, morning: morning, moon: moon, dark: dark,
                                  season: season, presence: presence, depth: depth)
        } else {
            palette = HillPalette(sunAltitude: altitude, morning: morning, moon: moon, dark: dark,
                                  season: season, depth: depth)
        }
        let baseline = baselineX(phase: phase, day: day)
        var x = baseline
        if let sets = world.sets {
            let weight = SkyMath.smoothstep(0.5, 0.62, baseline) * (1 - SkyMath.smoothstep(6, 12, altitude))
            x -= weight * Double(sets.sun) / Double(display.anchorWidth)
        }
        return SkyBenchMinute(date: date, display: display, palette: palette, sunAltitude: altitude,
                              sunXFraction: x, moonXFraction: moonX)
    }

    /// The lab's `sunX`: the baseline's arc by day, and on past sunset at
    /// the day's own pace.
    private static func baselineX(phase: SolarClock.Phase, day: SolarClock.Day?) -> Double {
        let rise = SkyPalette.bodyPosition(progress: 0).x
        let set = SkyPalette.bodyPosition(progress: 1).x
        switch phase {
        case .day(let progress):
            return SkyPalette.bodyPosition(progress: progress).x
        case .night(let progress):
            let dayLength = max(day.map { $0.sunset.timeIntervalSince($0.sunrise) } ?? 43_200, 1)
            let nightLength = max(86_400 - dayLength, 1)
            let span = (set - rise) * (nightLength / dayLength)
            return progress < 0.5 ? set + span * progress : rise - span * (1 - progress)
        }
    }

    /// How high a body at `altitude` degrees stands over the horizon, in
    /// points of the tall sky (`bodyE`).
    static func height(of altitude: Double, in world: SkyWorld) -> Double {
        if altitude < 0 { return 8.5 * altitude }
        return Double(world.zenith) * (1 - exp(-altitude / 45)) + 12 * (1 - exp(-altitude / 2.5))
    }

    /// The world's left edge on the planes: a multiple of 4, so the cover
    /// and the spread sample the same points (`buildGeometry`, `xL`).
    var planeLeading: Double {
        -4 * ((Double(display.anchorX) + Double(SkyWorld.marginLeading)) / 4).rounded(.up)
    }

    /// …and its right edge (`xR`).
    var planeTrailing: Double {
        Double(display.size.width) - Double(display.anchorX) + Double(world.turn) * 1.3
            + Double(SkyWorld.marginTrailing)
    }
}

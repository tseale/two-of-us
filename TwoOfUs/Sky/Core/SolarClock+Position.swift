import Foundation

/// What the painted hill needs from the sun beyond sunrise and sunset: where
/// it stands at any moment, and when it next comes up through a given angle
/// — first light is the sun rising through −7° (`NightRule`), and "Night N"
/// turns as it passes −4° (`NightCount`).
///
/// The solar series is the one `MoonClock` already carries for the moon's
/// light (SunCalc's, after Meeus), in a copy of its own because that one is
/// private; the sky lab's `sunPosition` (design/sky-lab/lab/solar.js) is the
/// same series, and `SkyCoreSunTests` holds the two together to a billionth
/// of a radian.
///
/// It is an extension in its own file, not more lines in SolarClock.swift,
/// for one reason: the lab's standing check (design/sky-lab/tools/
/// test-math.mjs) reads every number in that file and holds it against its
/// port of the NOAA formula. This is another formula, with other numbers.
extension SolarClock {
    /// Where the sun is at `date`, seen from `latitude` / `longitude`
    /// (degrees, east positive). Both angles are radians.
    ///
    /// `altitude` is the sun's centre above the horizon, WITHOUT refraction
    /// (negative below it): at `day(containing:)`'s sunrise and sunset it
    /// reads about −0.83°, which is NOAA's definition of them. `azimuth` is
    /// reckoned from north, clockwise (east π/2, south π, west 3π/2), in
    /// 0 ..< 2π — the lab's convention, not `MoonClock.Position`'s, which is
    /// from south.
    static func position(at date: Date, latitude: Double,
                         longitude: Double) -> (altitude: Double, azimuth: Double) {
        let lw = rad * -longitude
        let phi = rad * latitude
        let d = date.timeIntervalSince1970 / 86_400 - 0.5 + 2_440_588 - 2_451_545
        let sun = sunCoordinates(d)
        let hourAngle = rad * (280.16 + 360.9856235 * d) - lw - sun.rightAscension
        let altitude = asin(sin(phi) * sin(sun.declination)
                            + cos(phi) * cos(sun.declination) * cos(hourAngle))
        let fromSouth = atan2(sin(hourAngle),
                              cos(hourAngle) * sin(phi) - tan(sun.declination) * cos(phi))
        let turned = (fromSouth + .pi).truncatingRemainder(dividingBy: 2 * .pi)
        return (altitude, turned < 0 ? turned + 2 * .pi : turned)
    }

    /// The sun's altitude in DEGREES: the unit the design's rules are
    /// written in (first light at −7°, the stars all out below −12°).
    static func altitudeInDegrees(at date: Date, latitude: Double, longitude: Double) -> Double {
        position(at: date, latitude: latitude, longitude: longitude).altitude / rad
    }

    /// How far ahead `rises` looks: a whole solar day and two hours over,
    /// because near the polar circles the hour of a crossing moves by many
    /// minutes from one day to the next.
    static let riseSearchSpan: TimeInterval = 26 * 3600
    /// The coarse search step; a crossing is then bisected to the second. A
    /// dip under the angle that lasts less than this (the sun grazing it,
    /// for a few nights a year at one latitude) is not seen, and reads as
    /// "never".
    static let riseSearchStep: TimeInterval = 600

    /// The next moment after `date` at which the sun comes UP through
    /// `degrees` of altitude (negative: below the horizon), to the second.
    /// Nil where it does not within `riseSearchSpan`: a summer night too far
    /// north to get that dark, a polar night that never gets that light.
    static func rises(through degrees: Double, after date: Date, latitude: Double,
                      longitude: Double) -> Date? {
        let height = { (t: Date) in
            altitudeInDegrees(at: t, latitude: latitude, longitude: longitude) - degrees
        }
        var t = date
        var current = height(t)
        while t.timeIntervalSince(date) < riseSearchSpan {
            let later = t.addingTimeInterval(riseSearchStep)
            let after = height(later)
            if current < 0, after >= 0 {
                var low = t
                var high = later
                while high.timeIntervalSince(low) > 1 {
                    let mid = low.addingTimeInterval(high.timeIntervalSince(low) / 2)
                    if height(mid) < 0 { low = mid } else { high = mid }
                }
                return low.addingTimeInterval(high.timeIntervalSince(low) / 2)
            }
            t = later
            current = after
        }
        return nil
    }

    // MARK: The series

    private static let rad = Double.pi / 180
    /// The obliquity of the ecliptic.
    private static let obliquity = rad * 23.4397

    /// The sun's right ascension and declination `d` days after J2000.0
    /// (`MoonClock.sunCoordinates`: the sun is on the ecliptic, so the
    /// latitude terms of the general formulas are gone).
    private static func sunCoordinates(_ d: Double) -> (rightAscension: Double, declination: Double) {
        let m = rad * (357.5291 + 0.98560028 * d)
        let c = rad * (1.9148 * sin(m) + 0.02 * sin(2 * m) + 0.0003 * sin(3 * m))
        let perihelion = rad * 102.9372
        let longitude = m + c + perihelion + .pi
        return (atan2(sin(longitude) * cos(obliquity), cos(longitude)),
                asin(sin(obliquity) * sin(longitude)))
    }
}

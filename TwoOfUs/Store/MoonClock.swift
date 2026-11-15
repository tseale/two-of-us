import Foundation

/// Where the moon is: its place in the sky for a time and place, how much of
/// it is lit and which way its bright edge faces, and how far it is through
/// its pass from moonrise to moonset — so Home's sky can draw the moon that
/// is really outside: risen or set, waxing or waning, tilted as it is.
///
/// The low-precision lunar and solar series used by SunCalc (Agafonkin,
/// after Meeus and the astronomy answers at aa.quae.nl): a fraction of a
/// degree in position and well under a minute in rise and set — far finer
/// than a 32 pt moon can show. Pure: `MoonClockTests`.
enum MoonClock {
    // MARK: Results

    /// The moon's place in the sky.
    struct Position: Equatable {
        /// Radians from south, positive towards the west.
        let azimuth: Double
        /// Radians above the horizon, with atmospheric refraction.
        let altitude: Double
        /// Kilometres from the Earth's centre.
        let distance: Double
        /// The parallactic angle: how far the sky's north on the moon's disc
        /// leans from the zenith (radians).
        let parallacticAngle: Double
    }

    /// How the moon is lit.
    struct Illumination: Equatable {
        /// The lit fraction of its face: 0 new, 1 full.
        let fraction: Double
        /// 0 new, 0.25 first quarter, 0.5 full, 0.75 last quarter.
        let phase: Double
        /// The midpoint of the bright limb, in radians reckoned eastward from
        /// the disc's north point: negative while waxing, positive waning.
        let angle: Double
    }

    // MARK: Position and light

    static func position(at date: Date, latitude: Double, longitude: Double) -> Position {
        let lw = rad * -longitude
        let phi = rad * latitude
        let d = days(since2000: date)
        let moon = moonCoordinates(d)
        let hourAngle = siderealTime(d, lw: lw) - moon.rightAscension
        var altitude = Self.altitude(hourAngle: hourAngle, phi: phi, declination: moon.declination)
        let parallactic = atan2(sin(hourAngle),
                                tan(phi) * cos(moon.declination) - sin(moon.declination) * cos(hourAngle))
        altitude += refraction(altitude)
        return Position(azimuth: azimuth(hourAngle: hourAngle, phi: phi, declination: moon.declination),
                        altitude: altitude, distance: moon.distance, parallacticAngle: parallactic)
    }

    static func illumination(at date: Date) -> Illumination {
        let d = days(since2000: date)
        let sun = sunCoordinates(d)
        let moon = moonCoordinates(d)
        let sunDistance = 149_598_000.0
        let elongation = acos(sin(sun.declination) * sin(moon.declination)
                              + cos(sun.declination) * cos(moon.declination)
                              * cos(sun.rightAscension - moon.rightAscension))
        let inclination = atan2(sunDistance * sin(elongation),
                                moon.distance - sunDistance * cos(elongation))
        let angle = atan2(cos(sun.declination) * sin(sun.rightAscension - moon.rightAscension),
                          sin(sun.declination) * cos(moon.declination)
                          - cos(sun.declination) * sin(moon.declination)
                          * cos(sun.rightAscension - moon.rightAscension))
        return Illumination(fraction: (1 + cos(inclination)) / 2,
                            phase: 0.5 + 0.5 * inclination * (angle < 0 ? -1 : 1) / .pi,
                            angle: angle)
    }

    /// Which way the bright limb faces as seen from the ground: its angle
    /// from the zenith (radians, towards the east — the left as you face the
    /// moon). A waxing crescent at dusk is lit low on its right.
    static func brightLimbZenithAngle(at date: Date, latitude: Double, longitude: Double) -> Double {
        illumination(at: date).angle
            - position(at: date, latitude: latitude, longitude: longitude).parallacticAngle
    }

    // MARK: Rise and set

    /// The altitude of the moon's centre at rise and set: its semi-diameter
    /// and refraction already counted in `position`, less this (SunCalc's).
    static let horizon = 0.133 * rad
    /// How far either side of a moment to look for the rise and the set —
    /// more than a lunar day (≈ 24 h 50 min).
    static let searchSpan: TimeInterval = 30 * 3600
    /// The coarse search step; each crossing is then bisected to the second.
    static let searchStep: TimeInterval = 600

    /// When the moon last rose before `date` and next sets after it, while
    /// it is up at `date`; nil while it is below the horizon. Either end is
    /// nil when it doesn't happen within `searchSpan` (near the poles, where
    /// the moon can stay up or down for days).
    static func pass(around date: Date, latitude: Double,
                     longitude: Double) -> (rise: Date?, set: Date?)? {
        let height = { (t: Date) in
            position(at: t, latitude: latitude, longitude: longitude).altitude - horizon
        }
        guard height(date) > 0 else { return nil }
        var rise: Date?
        var t = date
        var current = height(t)
        while date.timeIntervalSince(t) < searchSpan {
            let earlier = t.addingTimeInterval(-searchStep)
            let before = height(earlier)
            if before <= 0, current > 0 {
                rise = crossing(from: earlier, to: t, height: height)
                break
            }
            t = earlier
            current = before
        }
        var set: Date?
        t = date
        current = height(t)
        while t.timeIntervalSince(date) < searchSpan {
            let later = t.addingTimeInterval(searchStep)
            let after = height(later)
            if current > 0, after <= 0 {
                set = crossing(from: t, to: later, height: height)
                break
            }
            t = later
            current = after
        }
        return (rise, set)
    }

    /// How far the moon is through its pass at `date`: 0 at moonrise, 1 at
    /// moonset; nil while it is below the horizon. A pass with no rise or no
    /// set in reach (near the poles) is put at its middle.
    static func passProgress(at date: Date, latitude: Double, longitude: Double) -> Double? {
        guard let pass = pass(around: date, latitude: latitude, longitude: longitude) else { return nil }
        guard let rise = pass.rise, let set = pass.set, set > rise else { return 0.5 }
        return min(max(date.timeIntervalSince(rise) / set.timeIntervalSince(rise), 0), 1)
    }

    /// Bisects to where `height` changes sign between `a` and `b`, to a
    /// second.
    private static func crossing(from a: Date, to b: Date, height: (Date) -> Double) -> Date {
        var low = a
        var high = b
        let lowAbove = height(low) > 0
        while high.timeIntervalSince(low) > 1 {
            let mid = low.addingTimeInterval(high.timeIntervalSince(low) / 2)
            if (height(mid) > 0) == lowAbove { low = mid } else { high = mid }
        }
        return low.addingTimeInterval(high.timeIntervalSince(low) / 2)
    }

    // MARK: The series

    private static let rad = Double.pi / 180
    /// The obliquity of the ecliptic.
    private static let obliquity = rad * 23.4397

    /// Days since J2000.0 (2000-01-01 12:00 TT, near enough UTC here).
    static func days(since2000 date: Date) -> Double {
        date.timeIntervalSince1970 / 86_400 - 0.5 + 2_440_588 - 2_451_545
    }

    private struct Equatorial {
        let rightAscension: Double
        let declination: Double
        var distance: Double = 0
    }

    private static func rightAscension(_ l: Double, _ b: Double) -> Double {
        atan2(sin(l) * cos(obliquity) - tan(b) * sin(obliquity), cos(l))
    }

    private static func declination(_ l: Double, _ b: Double) -> Double {
        asin(sin(b) * cos(obliquity) + cos(b) * sin(obliquity) * sin(l))
    }

    private static func siderealTime(_ d: Double, lw: Double) -> Double {
        rad * (280.16 + 360.9856235 * d) - lw
    }

    private static func altitude(hourAngle h: Double, phi: Double, declination dec: Double) -> Double {
        asin(sin(phi) * sin(dec) + cos(phi) * cos(dec) * cos(h))
    }

    private static func azimuth(hourAngle h: Double, phi: Double, declination dec: Double) -> Double {
        atan2(sin(h), cos(h) * sin(phi) - tan(dec) * cos(phi))
    }

    /// Bennett's formula, for an altitude in radians (clamped at the
    /// horizon so it stays finite below it).
    private static func refraction(_ h: Double) -> Double {
        let altitude = max(h, 0)
        return 0.0002967 / tan(altitude + 0.00312536 / (altitude + 0.08901179))
    }

    private static func sunCoordinates(_ d: Double) -> Equatorial {
        let m = rad * (357.5291 + 0.98560028 * d)
        let c = rad * (1.9148 * sin(m) + 0.02 * sin(2 * m) + 0.0003 * sin(3 * m))
        let perihelion = rad * 102.9372
        let longitude = m + c + perihelion + .pi
        return Equatorial(rightAscension: rightAscension(longitude, 0),
                          declination: declination(longitude, 0))
    }

    private static func moonCoordinates(_ d: Double) -> Equatorial {
        let l0 = rad * (218.316 + 13.176396 * d)   // mean longitude
        let m = rad * (134.963 + 13.064993 * d)    // mean anomaly
        let f = rad * (93.272 + 13.229350 * d)     // mean distance from the node
        let longitude = l0 + rad * 6.289 * sin(m)
        let latitude = rad * 5.128 * sin(f)
        return Equatorial(rightAscension: rightAscension(longitude, latitude),
                          declination: declination(longitude, latitude),
                          distance: 385_001 - 20_905 * cos(m))
    }
}

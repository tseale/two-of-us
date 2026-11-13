import Foundation

/// Where the sun is today: sunrise and sunset for a place, and how far
/// through the day (or the night) a moment is — so Home's sky can put the
/// sun where it really is, and colour itself by the light outside rather
/// than by a fixed clock (a 4:40 PM November sunset gets its dusk at 4:40).
///
/// The NOAA approximation (good to a minute or two away from the poles).
/// Pure: `SolarClockTests`.
enum SolarClock {
    struct Day: Equatable {
        let sunrise: Date
        let sunset: Date
    }

    /// Sunrise and sunset on the local calendar day containing `date`, at
    /// `latitude` / `longitude` (degrees, east positive). Nil where the sun
    /// neither rises nor sets that day (polar day or night).
    static func day(containing date: Date, latitude: Double, longitude: Double,
                    calendar: Calendar = .current) -> Day? {
        // Local noon, so the UTC day used below is the local day's.
        guard let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        let dayOfYear = Double(utc.ordinality(of: .day, in: .year, for: noon) ?? 1)
        let utcMidnight = utc.startOfDay(for: noon)

        let gamma = 2 * Double.pi / 365 * (dayOfYear - 1)
        let eqTime = 229.18 * (0.000075 + 0.001868 * cos(gamma) - 0.032077 * sin(gamma)
                               - 0.014615 * cos(2 * gamma) - 0.040849 * sin(2 * gamma))
        let decl = 0.006918 - 0.399912 * cos(gamma) + 0.070257 * sin(gamma)
            - 0.006758 * cos(2 * gamma) + 0.000907 * sin(2 * gamma)
            - 0.002697 * cos(3 * gamma) + 0.00148 * sin(3 * gamma)
        let lat = latitude * .pi / 180
        let zenith = 90.833 * Double.pi / 180
        let cosHA = cos(zenith) / (cos(lat) * cos(decl)) - tan(lat) * tan(decl)
        guard cosHA >= -1, cosHA <= 1 else { return nil }
        let ha = acos(cosHA) * 180 / .pi
        let sunriseMinutes = 720 - 4 * (longitude + ha) - eqTime
        let sunsetMinutes = 720 - 4 * (longitude - ha) - eqTime
        return Day(sunrise: utcMidnight.addingTimeInterval(sunriseMinutes * 60),
                   sunset: utcMidnight.addingTimeInterval(sunsetMinutes * 60))
    }

    /// A rough place for a phone that hasn't told the app where it is: the
    /// time zone's own meridian (15° per hour from UTC), at a temperate 40°N.
    static func approximateLocation(timeZone: TimeZone = .current,
                                    at date: Date = .now) -> (latitude: Double, longitude: Double) {
        let standardOffset = Double(timeZone.secondsFromGMT(for: date))
            - timeZone.daylightSavingTimeOffset(for: date)
        return (40, standardOffset / 3600 * 15)
    }

    /// Where `date` falls: through the daylight (0 at sunrise, 1 at sunset)
    /// or through the night (0 at sunset, 1 at the next sunrise).
    enum Phase: Equatable {
        case day(Double)
        case night(Double)
    }

    static func phase(at date: Date, in day: Day) -> Phase {
        let dayLength = day.sunset.timeIntervalSince(day.sunrise)
        let nightLength = max(86_400 - dayLength, 1)
        if date >= day.sunrise, date <= day.sunset, dayLength > 0 {
            return .day(date.timeIntervalSince(day.sunrise) / dayLength)
        }
        if date > day.sunset {
            return .night(min(date.timeIntervalSince(day.sunset) / nightLength, 1))
        }
        return .night(max(1 - day.sunrise.timeIntervalSince(date) / nightLength, 0))
    }
}

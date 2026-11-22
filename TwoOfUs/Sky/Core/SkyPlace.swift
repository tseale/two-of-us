import Foundation

/// Where the household's sky is: the one place the sun and the moon are
/// worked out for, so first light, the night's frame and the painted sky all
/// agree about the same horizon.
///
/// It is the daycare's pin when the household has set one (the only place the
/// app is ever told), and otherwise a guess from the phone's clock:
/// `SolarClock.approximateLocation`, 40°N on the time zone's own meridian —
/// the rule today's sky already uses, kept so the two skies cannot disagree
/// while both exist. Degrees, east positive. Pure: `SkyPlaceTests`.
struct SkyPlace: Equatable {
    let latitude: Double
    let longitude: Double

    /// The place to use: `pin` (`SharedSettings.daycareCoordinate`) where
    /// there is one, else the guess for `timeZone` at `date` (the date only
    /// decides which offset is the zone's standard one).
    static func resolve(pin: (latitude: Double, longitude: Double)?, timeZone: TimeZone,
                        at date: Date) -> SkyPlace {
        if let pin { return SkyPlace(latitude: pin.latitude, longitude: pin.longitude) }
        let guess = SolarClock.approximateLocation(timeZone: timeZone, at: date)
        return SkyPlace(latitude: guess.latitude, longitude: guess.longitude)
    }
}

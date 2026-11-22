import Foundation

/// "Night N": the nights of his life, counted from the night he was born.
///
/// In the design's words (design/sky-lab/lab/nights.js): night 1 is the
/// night he was born; tonight is night `ageDays + 1`; every night has one
/// star. So the count belongs to an EVENING's calendar day, not to the
/// calendar: after midnight it is still the same night, and the number under
/// "✦ Night 143" at bedtime is the number of his stars at the 3 am feed.
///
/// It turns in the morning, when the rising sun passes −4° — not at first
/// light (−7°). At first light a third of the stars' light is still out
/// (lab/presence.js: `1 − smoothstep(−12, −4)` of the sun's altitude), and
/// turning there would add last night's star to the sky in the middle of the
/// settle. At −4° the last of the starlight has gone, so the new day's count
/// arrives unseen.
///
/// The date of birth is stored with whatever time of day it had when it was
/// picked; only its calendar day counts. A date of birth still to come is a
/// due date, and there are no nights yet: 0.
///
/// Pure, from the clock, the sun and the date of birth: `NightCountTests`.
enum NightCount {
    /// The altitude, in degrees, the rising sun passes as the count turns:
    /// where the lab's starlight reaches nothing.
    static let turnDegrees = -4.0

    /// Tonight's number at `now`: 1 on the night he was born, 143 on the
    /// evening he is 142 days old, and still 143 until the next morning's
    /// turn. 0 before he is born.
    static func night(at now: Date, born: Date, place: SkyPlace,
                      policy: NightRule.Policy = .signedOff, calendar: Calendar) -> Int {
        night(ofDay: nightDay(at: now, place: place, policy: policy, calendar: calendar),
              born: born, calendar: calendar)
    }

    /// The number of the night that starts on the evening of the calendar
    /// day containing `day`: whole calendar days since the day he was born,
    /// plus one. 0 for any day before that.
    static func night(ofDay day: Date, born: Date, calendar: Calendar) -> Int {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: born),
                                           to: calendar.startOfDay(for: day)).day ?? 0
        return max(0, days + 1)
    }

    /// The start of the calendar day whose evening the count belongs to at
    /// `now`: yesterday until this morning's turn, today from then on.
    static func nightDay(at now: Date, place: SkyPlace, policy: NightRule.Policy = .signedOff,
                         calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
              let turn = turn(afterNightOn: yesterday, place: place, policy: policy, calendar: calendar),
              now < turn
        else { return today }
        return calendar.startOfDay(for: yesterday)
    }

    /// When the count moves on from the night that starts on the evening of
    /// the day containing `day`: the first time after that night's first
    /// light that the sun comes up through `turnDegrees`. Where it does not
    /// before the next evening (the far north: a midsummer night that ends
    /// by the clock, a winter noon that stays under −4°), the count turns
    /// with first light itself.
    static func turn(afterNightOn day: Date, place: SkyPlace, policy: NightRule.Policy = .signedOff,
                     calendar: Calendar) -> Date? {
        guard let frame = NightRule.frame(ofNightOn: day, place: place, policy: policy, calendar: calendar),
              let nextEvening = NightRule.evening(after: calendar.startOfDay(for: day), policy: policy,
                                                  calendar: calendar)
        else { return nil }
        if let rise = SolarClock.rises(through: turnDegrees, after: frame.firstLight,
                                       latitude: place.latitude, longitude: place.longitude),
           rise < nextEvening {
            return rise
        }
        return frame.firstLight
    }

    // MARK: Month-nights

    /// The nights, up to and including `night`, that fall on a
    /// month-birthday: the 2nd of every month for a boy born on 2 July.
    /// Each is a brighter star with a four-point glint. The lab, which has
    /// no calendar for him, counts 30.44-day months; the app uses his real
    /// date of birth (`AgeMarks` counts his months the same way), so its
    /// month-nights can sit a night or two from the lab's. Born on the 31st,
    /// his month-night in a shorter month is its last day.
    ///
    /// Night 1 is not among them: it is the first night, a mark of its own.
    static func monthNights(through night: Int, born: Date, calendar: Calendar) -> Set<Int> {
        var nights: Set<Int> = []
        let birthday = calendar.startOfDay(for: born)
        var months = 1
        // Always counted from the birthday itself, never from the previous
        // month-birthday: 31 January + 1 month is 28 February, and + 2 is
        // 31 March again.
        while let day = calendar.date(byAdding: .month, value: months, to: birthday) {
            let number = self.night(ofDay: day, born: born, calendar: calendar)
            if number > night { break }
            nights.insert(number)
            months += 1
        }
        return nights
    }
}

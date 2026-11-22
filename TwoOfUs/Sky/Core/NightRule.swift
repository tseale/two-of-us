import Foundation

/// "The night has begun": the one rule that says when Home looks up.
///
/// In the design's words (design/sky-lab/BRIEF.md, round three and its
/// sign-off): Home looks up from the start of tonight's night sleep until
/// first light. A night sleep is one begun between 6 pm and 4 am; first light
/// is the sun coming up through −7° at the household's place. Between the
/// two the fact holds whether he is asleep or awake, so a night feed moves
/// nothing, and midnight is not a boundary of anything.
///
/// It is a pure function of the clock, the sun and the sleep log. Nothing is
/// stored, and ended sleeps count exactly as running ones do.
///
/// Two things the lab's stand-in (design/sky-lab/lab/core.js, `nightHours`,
/// `nightHasBegun`) does that this rule deliberately does not:
/// - the lab's evening starts at sunset where that is before 6 pm, so a
///   5 pm November sleep would be the night's. Here the evening is 6 pm all
///   year ("the 6 pm rule stands");
/// - the lab has no 4 am end and no sleep log: awake, it takes the night to
///   have begun at a sample 20:10 bedtime. Here only a real sleep begins it.
///
/// Tested in `NightRuleTests`, case by case from the brief and minute by
/// minute against the lab's own answers.
enum NightRule {
    // MARK: The hours

    /// The hours the rule runs on, so the owner can move them without the
    /// rule changing: they are a decision, not arithmetic.
    struct Policy: Equatable {
        /// When the evening starts, in minutes from local midnight: a sleep
        /// begun from here on can be the night's. 6 pm.
        var evening = 18 * 60
        /// The last minute a sleep can begin and still be the night's, in
        /// minutes from local midnight (of the morning after, when it is
        /// earlier in the day than `evening`). 4 am.
        var lastStart = 4 * 60
        /// First light: the altitude, in degrees, the rising sun passes as
        /// the night ends. −7°, chosen by looking: just under it the
        /// looked-up sky still holds some twenty of his stars and reads as
        /// night; at −6° it has four left.
        var firstLightDegrees = -7.0

        /// The hours as Taylor signed them off on 22 Nov 2026.
        static let signedOff = Policy()
    }

    // MARK: The state

    /// Tonight, as it stands at `now`. `sleeps` are the log's live sleeps in
    /// any order (only those near tonight matter; older ones are ignored);
    /// `calendar` carries the household's time zone, which decides what
    /// "6 pm" and "4 am" are.
    ///
    /// Each call looks for first light afresh (a search of the sun's
    /// altitude, some eighty steps): ask when the log changes and once a
    /// minute, as the sky's own clock ticks — not once a frame.
    static func state(at now: Date, sleeps: [SleepSpan], place: SkyPlace,
                      policy: Policy = .signedOff, calendar: Calendar) -> NightState {
        let frame = frame(containing: now, place: place, policy: policy, calendar: calendar)
        let begunBy = frame.flatMap { frame in
            // The earliest sleep begun inside the night's welcome. A start a
            // little ahead of this phone's clock (the other phone's runs
            // fast) counts at once: the sleep card is already showing it,
            // and the sky must not sit on the hill beside it.
            sleeps
                .filter { frame.evening <= $0.start && $0.start < frame.lastStart }
                .min { ($0.start, $0.id.uuidString) < ($1.start, $1.id.uuidString) }
        }
        let running = sleeps.filter(\.isRunning)
        let kind: SleepKind?
        if running.isEmpty {
            kind = nil
        } else if running.contains(where: { isNightSleep(start: $0.start, policy: policy, calendar: calendar) }) {
            kind = .night
        } else {
            kind = .nap
        }
        return NightState(frame: frame, begunBy: begunBy, running: kind)
    }

    /// Whether a sleep begun at `start` is a night sleep by the clock alone:
    /// begun between the evening and the last start, 6 pm to 4 am. This is
    /// what decides how far a running sleep dims the room; whether it also
    /// BEGINS the night is `state`'s to say (it must fall inside the night's
    /// frame, before first light).
    static func isNightSleep(start: Date, policy: Policy = .signedOff, calendar: Calendar) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: start)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if policy.lastStart > policy.evening {
            return minutes >= policy.evening && minutes < policy.lastStart
        }
        return minutes >= policy.evening || minutes < policy.lastStart
    }

    // MARK: The frame

    /// The night whose hours contain `now`: yesterday evening's until its
    /// first light, or this evening's once it has started. Nil by day.
    static func frame(containing now: Date, place: SkyPlace, policy: Policy = .signedOff,
                      calendar: Calendar) -> NightFrame? {
        let today = calendar.startOfDay(for: now)
        // Before this evening only last night can still be going on; from
        // this evening on, only tonight (a night always ends before the
        // next one's evening).
        let day: Date
        if let evening = clock(policy.evening, on: today, calendar: calendar), now >= evening {
            day = today
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today) {
            day = yesterday
        } else {
            return nil
        }
        guard let frame = frame(ofNightOn: day, place: place, policy: policy, calendar: calendar),
              frame.contains(now) else { return nil }
        return frame
    }

    /// The night that starts on the evening of the calendar day containing
    /// `day`: its evening, the last moment a sleep can begin it, and its
    /// first light — the first time after the evening that the sun comes up
    /// through `policy.firstLightDegrees` at `place`.
    ///
    /// Where the sun does not do that before the next evening (it never
    /// gets that low on a northern midsummer night, never that high in a
    /// polar winter), the night ends at the last start's own hour, 4 am.
    static func frame(ofNightOn day: Date, place: SkyPlace, policy: Policy = .signedOff,
                      calendar: Calendar) -> NightFrame? {
        let start = calendar.startOfDay(for: day)
        guard let evening = clock(policy.evening, on: start, calendar: calendar),
              let nextEvening = self.evening(after: start, policy: policy, calendar: calendar),
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: start),
              let lastClock = clock(policy.lastStart,
                                    on: policy.lastStart > policy.evening ? start : calendar.startOfDay(for: tomorrow),
                                    calendar: calendar)
        else { return nil }
        let firstLight: Date
        if let rise = SolarClock.rises(through: policy.firstLightDegrees, after: evening,
                                       latitude: place.latitude, longitude: place.longitude),
           rise < nextEvening {
            firstLight = rise
        } else {
            firstLight = lastClock
        }
        return NightFrame(evening: evening, lastStart: min(lastClock, firstLight), firstLight: firstLight)
    }

    /// The evening of the day after the one starting at `start`: the bound
    /// no night may run past.
    static func evening(after start: Date, policy: Policy = .signedOff, calendar: Calendar) -> Date? {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        return clock(policy.evening, on: calendar.startOfDay(for: tomorrow), calendar: calendar)
    }

    /// A wall-clock time (minutes from midnight) on the day starting at
    /// `start` — by the calendar, so that 6 pm is 6 pm on the days the
    /// clocks change too.
    private static func clock(_ minutes: Int, on start: Date, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: start)
    }
}

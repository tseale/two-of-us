import Foundation

/// One vocabulary for sleep on every surface — hero card, timeline, widgets,
/// Live Activity, Siri — so "napping", "sleeping", and "nap"/"Sleep" can
/// never disagree between two views of the same event.
///
/// The rules (2026-10, tuned for a 2-month-old):
/// - A sleep that STARTS in the night window (8 PM – 6 AM) is always a
///   "sleep" — there are no night naps. Deliberately distinct from the feed
///   schedule's configurable night window: a 7 AM bottle is still a night
///   bottle, but a 7 AM doze is a morning nap.
/// - A daytime sleep begins as a "nap" and crosses into "sleep" at 2 hours:
///   typical naps run 30m–1.5h at this age, so past 2h it isn't a nap
///   anymore. Revisit the threshold as he grows.
enum SleepLanguage {
    static let nightStartHour = 20   // 8 PM
    static let nightEndHour = 6      // 6 AM
    /// A daytime sleep this long stops being a nap.
    static let napCrossover: TimeInterval = 2 * 3600

    private static func startsAtNight(_ start: Date, calendar: Calendar) -> Bool {
        let hour = calendar.component(.hour, from: start)
        return hour >= nightStartHour || hour < nightEndHour
    }

    /// Nap (true) or full sleep (false) — `end` is "now" for one still running.
    static func isNap(start: Date, end: Date, calendar: Calendar = .current) -> Bool {
        !startsAtNight(start, calendar: calendar)
            && end.timeIntervalSince(start) < napCrossover
    }

    /// "napping" / "sleeping" — for a sleep still running.
    static func gerund(start: Date, now: Date = .now,
                       calendar: Calendar = .current) -> String {
        isNap(start: start, end: now, calendar: calendar) ? "napping" : "sleeping"
    }

    /// "Nap" / "Sleep" — the finished event's noun (lowercase at call sites
    /// that need it).
    static func noun(start: Date, end: Date, calendar: Calendar = .current) -> String {
        isNap(start: start, end: end, calendar: calendar) ? "Nap" : "Sleep"
    }

    /// "nap" / "sleep" for a PROJECTED moment — its duration is unknown, so
    /// only the clock decides: a predicted evening down is a sleep, a
    /// predicted afternoon one a nap.
    static func predictedNoun(at date: Date, calendar: Calendar = .current) -> String {
        startsAtNight(date, calendar: calendar) ? "sleep" : "nap"
    }
}

import Foundation

/// Formats ounce amounts with the minimum decimal places needed.
/// Integers drop the decimal entirely; 0.5-step values use one place; 0.25-step
/// values (e.g. 0.25, 0.75) use two — so "0.25 oz" never silently rounds to "0.2".
enum OzFormat {
    static func string(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        let s = String(format: "%.2f", value)
        return s.hasSuffix("0") ? String(s.dropLast()) : s
    }
}

/// Naive English pluralizer for count labels ("1 diaper" / "3 diapers").
/// Add-an-s only — every unit in the app pluralizes regularly.
enum Plural {
    static func count(_ n: Int, _ unit: String) -> String {
        "\(n) \(unit)\(n == 1 ? "" : "s")"
    }

    /// Unit-only form, for layouts that render the number separately.
    static func unit(_ n: Int, _ unit: String) -> String {
        n == 1 ? unit : unit + "s"
    }
}

enum TimeFormatting {
    /// Compact elapsed string from a past date to now, e.g. "2h 40m", "45m", "just now".
    static func since(_ date: Date, now: Date = .now) -> String {
        elapsed(from: date, to: now)
    }

    /// Duration between two instants, e.g. "1h 22m".
    static func duration(from start: Date, to end: Date) -> String {
        elapsed(from: start, to: end, zeroText: "0m")
    }

    private static func elapsed(from start: Date, to end: Date, zeroText: String = "just now") -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        let minutes = seconds / 60
        if minutes < 1 { return zeroText }
        let h = minutes / 60
        let m = minutes % 60
        if h == 0 { return "\(m)m" }
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }

    /// Absolute local time, e.g. "2:14 PM".
    static func clock(_ date: Date) -> String {
        clockFormatter.string(from: date)
    }

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    /// Adaptive age string: days → weeks → months. A future date of birth is a
    /// due date (expecting parents set up before the arrival) and counts down
    /// in the same brackets the age counts up.
    static func age(from dob: Date, now: Date = .now) -> String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: dob), to: cal.startOfDay(for: now)).day ?? 0
        if days < 0 {
            let until = -days
            if until == 1 { return "due tomorrow" }
            if until < 14 { return "due in \(until) days" }
            if until < 56 {
                let weeks = until / 7
                return weeks == 1 ? "due in 1 week" : "due in \(weeks) weeks"
            }
            let months = until / 30
            return months == 1 ? "due in 1 month" : "due in \(months) months"
        }
        if days < 14 {
            return days == 1 ? "1 day old" : "\(days) days old"
        }
        if days < 56 { // up to 8 weeks
            let weeks = days / 7
            return "\(weeks) weeks old"
        }
        let months = cal.dateComponents([.month], from: dob, to: now).month ?? 0
        return months == 1 ? "1 month old" : "\(months) months old"
    }
}

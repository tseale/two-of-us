import Foundation

/// Formats ounce amounts, dropping a trailing ".0" but keeping half-ounces.
enum OzFormat {
    static func string(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        return String(format: "%.1f", value)
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
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }

    /// Adaptive age string: days → weeks → months.
    static func age(from dob: Date, now: Date = .now) -> String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: dob), to: cal.startOfDay(for: now)).day ?? 0
        if days < 0 { return "due soon" }
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

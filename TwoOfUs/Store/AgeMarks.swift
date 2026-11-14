import Foundation

/// The next birthday-ish day worth looking forward to — "4 months old",
/// "100 days old", "1 year old" — for the evening book page on iPhone Duo's
/// spread. Pure (`AgeMarksTests`).
enum AgeMarks {
    struct Mark: Equatable {
        /// The start of the day it falls on.
        let date: Date
        let title: String
    }

    /// Round day counts worth a line of their own.
    static let dayCounts = [100, 200, 300, 500, 1000]

    /// The earliest mark from today (inclusive) up to `withinDays` ahead, or
    /// nil when none falls that soon. Month marks run to two years.
    static func next(after now: Date, dateOfBirth: Date, withinDays: Int = 31,
                     calendar: Calendar = .current) -> Mark? {
        let born = calendar.startOfDay(for: dateOfBirth)
        let today = calendar.startOfDay(for: now)
        guard let horizon = calendar.date(byAdding: .day, value: withinDays, to: today) else { return nil }

        var marks: [Mark] = []
        for months in 1...24 {
            guard let date = calendar.date(byAdding: .month, value: months, to: born) else { continue }
            let title: String
            switch months {
            case 12: title = "1 year old"
            case 24: title = "2 years old"
            default: title = "\(months) \(months == 1 ? "month" : "months") old"
            }
            marks.append(Mark(date: calendar.startOfDay(for: date), title: title))
        }
        for days in dayCounts {
            guard let date = calendar.date(byAdding: .day, value: days, to: born) else { continue }
            marks.append(Mark(date: date, title: "\(days) days old"))
        }
        return marks
            .filter { $0.date >= today && $0.date <= horizon }
            .min { $0.date < $1.date }
    }
}

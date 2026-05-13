import Foundation

/// Monday-anchored week math. Pure functions, easy to test.
enum WeekCalculator {
    /// Monday-anchored start of the week containing `date`.
    static func weekStart(for date: Date) -> Date {
        date.startOfWeek
    }

    /// The 7 days of the week containing `date`, Monday → Sunday.
    static func daysOfWeek(containing date: Date) -> [Date] {
        let start = weekStart(for: date)
        return (0..<7).map { start.adding(days: $0) }
    }
}

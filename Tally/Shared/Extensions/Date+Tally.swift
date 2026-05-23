import Foundation

extension Date {
    /// Monday-anchored Gregorian calendar in the user's local timezone.
    static var local: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        cal.firstWeekday = 2
        return cal
    }

    var startOfDay: Date {
        Date.local.startOfDay(for: self)
    }

    /// Monday of the week containing this date.
    var startOfWeek: Date {
        let cal = Date.local
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
        return cal.date(from: comps) ?? self
    }

    /// First day of the month containing this date.
    var startOfMonth: Date {
        let cal = Date.local
        let comps = cal.dateComponents([.year, .month], from: self)
        return cal.date(from: comps) ?? self
    }

    /// January 1st of the year containing this date.
    var startOfYear: Date {
        let cal = Date.local
        let comps = cal.dateComponents([.year], from: self)
        return cal.date(from: comps) ?? self
    }

    /// Calendar-day distance from `other` to `self` (positive when self is after).
    func daysSince(_ other: Date) -> Int {
        Date.local.dateComponents([.day], from: other.startOfDay, to: self.startOfDay).day ?? 0
    }

    func adding(days: Int) -> Date {
        Date.local.date(byAdding: .day, value: days, to: self) ?? self
    }

    func adding(hours: Int) -> Date {
        Date.local.date(byAdding: .hour, value: hours, to: self) ?? self
    }

    func adding(months: Int) -> Date {
        Date.local.date(byAdding: .month, value: months, to: self) ?? self
    }

    func adding(years: Int) -> Date {
        Date.local.date(byAdding: .year, value: years, to: self) ?? self
    }
}

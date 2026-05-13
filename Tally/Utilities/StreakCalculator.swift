import Foundation

/// Pure functions over a habit's completion dates. No DB / state access — easy to unit test.
enum StreakCalculator {
    /// Current streak using the strict rule: any missed day after habit creation resets to 0.
    /// If today isn't completed yet, the count walks back from yesterday so the streak doesn't
    /// visibly break until you've actually missed a full day.
    static func currentStreak(
        completions: [Date],
        habitCreatedAt: Date,
        today: Date = .now
    ) -> Int {
        let today = today.startOfDay
        let created = habitCreatedAt.startOfDay
        let completedDays = Set(completions.map { $0.startOfDay })

        var cursor = today
        if !completedDays.contains(cursor) {
            cursor = cursor.adding(days: -1)
        }

        var streak = 0
        while cursor >= created, completedDays.contains(cursor) {
            streak += 1
            cursor = cursor.adding(days: -1)
        }
        return streak
    }

    /// Longest consecutive-day run across all completions.
    static func longestStreak(
        completions: [Date],
        habitCreatedAt: Date
    ) -> Int {
        let dates = Array(Set(completions.map { $0.startOfDay })).sorted()
        guard !dates.isEmpty else { return 0 }

        var longest = 1
        var current = 1
        for i in 1..<dates.count {
            if dates[i].daysSince(dates[i - 1]) == 1 {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
            }
        }
        return longest
    }
}

import CloudKit
import Foundation

/// The four timescales a Goal can be set against. Stored on each `Goal` so a
/// single CloudKit record type covers daily / weekly / monthly / yearly.
enum GoalPeriod: String, Codable, CaseIterable, Hashable {
    case day, week, month, year

    var displayName: String {
        switch self {
        case .day:   "Day"
        case .week:  "Week"
        case .month: "Month"
        case .year:  "Year"
        }
    }

    /// "today / this week / this month / this year" — used as the goal-card noun.
    var thisLabel: String {
        switch self {
        case .day:   "today"
        case .week:  "this week"
        case .month: "this month"
        case .year:  "this year"
        }
    }

    /// Start of the period containing `date` (start of day / Monday / 1st of month / Jan 1).
    func startDate(for date: Date) -> Date {
        switch self {
        case .day:   date.startOfDay
        case .week:  date.startOfWeek
        case .month: date.startOfMonth
        case .year:  date.startOfYear
        }
    }

    /// Shift a period-start by `offset` periods (negative = earlier, positive = later).
    func shift(_ start: Date, by offset: Int) -> Date {
        switch self {
        case .day:   start.adding(days: offset)
        case .week:  start.adding(days: offset * 7)
        case .month: start.adding(months: offset)
        case .year:  start.adding(years: offset)
        }
    }
}

/// A one-off intention scoped to a period (day / week / month / year). Lives in
/// the Circle's shared zone so every member sees each other's goals.
struct Goal: Identifiable, Hashable, Codable {
    let id: UUID
    var userID: String
    var title: String
    var period: GoalPeriod
    /// First day of the period this goal belongs to.
    var periodStartDate: Date
    var completedAt: Date?
    var carriedFromID: UUID?
    var createdAt: Date
}

extension Goal: ZoneRecord {
    static let recordType = "Goal"
    var recordName: String { id.uuidString }

    init?(record: CKRecord) {
        guard
            let idString = record["id"] as? String,
            let id = UUID(uuidString: idString),
            let userID = record["userID"] as? String,
            let title = record["title"] as? String,
            let periodString = record["period"] as? String,
            let period = GoalPeriod(rawValue: periodString),
            let periodStartDate = record["periodStartDate"] as? Date,
            let createdAt = record["createdAt"] as? Date
        else { return nil }
        self.id = id
        self.userID = userID
        self.title = title
        self.period = period
        self.periodStartDate = periodStartDate
        self.completedAt = record["completedAt"] as? Date
        self.carriedFromID = (record["carriedFromID"] as? String).flatMap(UUID.init)
        self.createdAt = createdAt
    }

    func populate(_ record: CKRecord) {
        record["id"] = id.uuidString
        record["userID"] = userID
        record["title"] = title
        record["period"] = period.rawValue
        record["periodStartDate"] = periodStartDate
        record["completedAt"] = completedAt
        record["carriedFromID"] = carriedFromID?.uuidString
        record["createdAt"] = createdAt
    }
}

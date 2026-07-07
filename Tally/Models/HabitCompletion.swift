import CloudKit
import Foundation

struct HabitCompletion: Identifiable, Hashable, Codable {
    let id: UUID
    var habitID: UUID
    var userID: String
    var completedDate: Date
    var createdAt: Date
}

extension HabitCompletion: ZoneRecord {
    static let recordType = "HabitCompletion"
    var recordName: String { id.uuidString }

    init?(record: CKRecord) {
        guard
            let idString = record["id"] as? String,
            let id = UUID(uuidString: idString),
            let habitIDString = record["habitID"] as? String,
            let habitID = UUID(uuidString: habitIDString),
            let userID = record["userID"] as? String,
            let completedDate = record["completedDate"] as? Date,
            let createdAt = record["createdAt"] as? Date
        else { return nil }
        self.id = id
        self.habitID = habitID
        self.userID = userID
        self.completedDate = completedDate
        self.createdAt = createdAt
    }

    func populate(_ record: CKRecord) {
        record["id"] = id.uuidString
        record["habitID"] = habitID.uuidString
        record["userID"] = userID
        record["completedDate"] = completedDate
        record["createdAt"] = createdAt
    }
}

// MARK: - DayNote

/// A private, per-day free-text note the user writes in their history. Stored in
/// the private DB's **default zone** (like `UserProfile`) — NOT the personal
/// zone that's shared with friends — so it never reaches anyone else. One record
/// per calendar day at a stable recordName, so it's fetched directly by ID
/// without a query (the default zone doesn't support the queries a custom zone
/// would). Lives here beside `HabitCompletion` as the other per-day entry model.
struct DayNote: Identifiable, Hashable, Codable {
    static let recordType = "DayNote"

    /// Start-of-day (local) this note belongs to.
    let day: Date
    var text: String
    var updatedAt: Date

    var id: String { Self.dayKey(day) }

    init(day: Date, text: String, updatedAt: Date) {
        self.day = day
        self.text = text
        self.updatedAt = updatedAt
    }

    init?(record: CKRecord) {
        guard
            let day = record["day"] as? Date,
            let text = record["text"] as? String,
            let updatedAt = record["updatedAt"] as? Date
        else { return nil }
        self.day = day
        self.text = text
        self.updatedAt = updatedAt
    }

    func populate(_ record: CKRecord) {
        record["day"] = day
        record["text"] = text
        record["updatedAt"] = updatedAt
    }

    /// Stable yyyy-MM-dd key (local calendar) used to derive the recordName.
    static func dayKey(_ date: Date) -> String {
        let c = Date.local.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Stable CloudKit recordName for a given day, e.g. "dayNote-2026-06-17".
    static func recordName(for date: Date) -> String { "dayNote-\(dayKey(date))" }
}

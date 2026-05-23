import CloudKit
import Foundation

/// A bigger thing the user is working toward — one-time or longer-term. Lives in
/// the Circle's shared zone (today) so every member sees each other's goals.
/// Always shared; the privacy story for personal data is on habits, not goals.
///
/// Goals persist until completed or deleted. Optional `deadline` drives a
/// countdown / overdue label in the UI; goals without a deadline are open-ended
/// "in progress" intentions.
struct Goal: Identifiable, Hashable, Codable {
    let id: UUID
    var userID: String
    var title: String
    var deadline: Date?
    var completedAt: Date?
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
            let createdAt = record["createdAt"] as? Date
        else { return nil }
        self.id = id
        self.userID = userID
        self.title = title
        self.deadline = record["deadline"] as? Date
        self.completedAt = record["completedAt"] as? Date
        self.createdAt = createdAt
    }

    func populate(_ record: CKRecord) {
        record["id"] = id.uuidString
        record["userID"] = userID
        record["title"] = title
        record["deadline"] = deadline
        record["completedAt"] = completedAt
        record["createdAt"] = createdAt
    }
}

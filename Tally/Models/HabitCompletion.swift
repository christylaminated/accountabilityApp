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

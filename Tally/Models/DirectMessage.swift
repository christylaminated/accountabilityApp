import CloudKit
import Foundation

struct DirectMessage: Identifiable, Hashable, Codable {
    let id: UUID
    var circleID: UUID
    var senderID: String
    var recipientID: String
    var body: String
    var createdAt: Date
}

extension DirectMessage: ZoneRecord {
    static let recordType = "DirectMessage"
    var recordName: String { id.uuidString }

    init?(record: CKRecord) {
        guard
            let idString = record["id"] as? String,
            let id = UUID(uuidString: idString),
            let circleIDString = record["circleID"] as? String,
            let circleID = UUID(uuidString: circleIDString),
            let senderID = record["senderID"] as? String,
            let recipientID = record["recipientID"] as? String,
            let body = record["body"] as? String,
            let createdAt = record["createdAt"] as? Date
        else { return nil }
        self.id = id
        self.circleID = circleID
        self.senderID = senderID
        self.recipientID = recipientID
        self.body = body
        self.createdAt = createdAt
    }

    func populate(_ record: CKRecord) {
        record["id"] = id.uuidString
        record["circleID"] = circleID.uuidString
        record["senderID"] = senderID
        record["recipientID"] = recipientID
        record["body"] = body
        record["createdAt"] = createdAt
    }
}

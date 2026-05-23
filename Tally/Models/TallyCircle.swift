import CloudKit
import Foundation

/// Named `TallyCircle` to avoid colliding with SwiftUI.Circle. Maps to the
/// `Circle` record type in CloudKit — the root record of each Circle's shared zone.
///
/// `id` is a UUID we control locally (also encodes the zone name).
/// `ownerID` holds the owner's `CKRecord.ID.recordName` (a String, not a UUID).
struct TallyCircle: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var emoji: String?
    var ownerID: String
    var createdAt: Date
}

extension TallyCircle: CKRecordConvertible {
    static let recordType = "Circle"

    init?(record: CKRecord) {
        guard
            let idString = record["id"] as? String,
            let id = UUID(uuidString: idString),
            let name = record["name"] as? String,
            let ownerID = record["ownerID"] as? String,
            let createdAt = record["createdAt"] as? Date
        else { return nil }
        self.id = id
        self.name = name
        self.emoji = record["emoji"] as? String
        self.ownerID = ownerID
        self.createdAt = createdAt
    }

    func populate(_ record: CKRecord) {
        record["id"] = id.uuidString
        record["name"] = name
        record["emoji"] = emoji
        record["ownerID"] = ownerID
        record["createdAt"] = createdAt
    }
}

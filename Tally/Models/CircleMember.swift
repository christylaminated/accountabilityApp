import CloudKit
import Foundation

enum CircleRole: String, Codable, Hashable {
    case owner
    case member
}

/// A member of a Circle. Lives in the Circle's shared zone. Carries the member's
/// display name + avatar symbol because each user's `UserProfile` is private —
/// this record is how other members learn how to render them.
struct CircleMember: Hashable, Codable, Identifiable {
    /// References `TallyCircle.id`. UUID — we control Circle IDs locally.
    var circleID: UUID
    /// The member's CloudKit `CKRecord.ID.recordName`.
    var userID: String
    var displayName: String
    var avatarSymbol: String
    var role: CircleRole
    var joinedAt: Date

    /// Composite key — unique within (circleID, userID).
    var id: String { "\(circleID.uuidString)|\(userID)" }
}

extension CircleMember: CKRecordConvertible {
    static let recordType = "CircleMember"

    init?(record: CKRecord) {
        guard
            let circleIDString = record["circleID"] as? String,
            let circleID = UUID(uuidString: circleIDString),
            let userID = record["userID"] as? String,
            let displayName = record["displayName"] as? String,
            let avatarSymbol = record["avatarSymbol"] as? String,
            let roleString = record["role"] as? String,
            let role = CircleRole(rawValue: roleString),
            let joinedAt = record["joinedAt"] as? Date
        else { return nil }
        self.circleID = circleID
        self.userID = userID
        self.displayName = displayName
        self.avatarSymbol = avatarSymbol
        self.role = role
        self.joinedAt = joinedAt
    }

    func populate(_ record: CKRecord) {
        record["circleID"] = circleID.uuidString
        record["userID"] = userID
        record["displayName"] = displayName
        record["avatarSymbol"] = avatarSymbol
        record["role"] = role.rawValue
        record["joinedAt"] = joinedAt
    }
}

extension CircleMember: ZoneRecord {
    /// One membership row per user — keyed by user record name so a re-join
    /// upserts rather than duplicates.
    var recordName: String { "member-\(userID)" }
}

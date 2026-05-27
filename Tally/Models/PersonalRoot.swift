import CloudKit
import Foundation

/// The root record inside each user's personal CloudKit zone. Habits, goals,
/// and check-ins live as children of this record so they ride the personal
/// CKShare to every friend.
///
/// Also carries the user's display name + avatar symbol + optional avatar
/// photo data — that's how friends learn how to render this user (the
/// private `UserProfile` stays in the private DB default zone, invisible
/// to friends). When `avatarImageData` is set, views prefer it over the
/// SF Symbol.
struct PersonalRoot: Hashable, Codable {
    var displayName: String
    var avatarSymbol: String
    var avatarImageData: Data?
    var createdAt: Date
}

extension PersonalRoot: CKRecordConvertible {
    static let recordType = "PersonalRoot"

    init?(record: CKRecord) {
        guard let createdAt = record["createdAt"] as? Date else { return nil }
        self.displayName = (record["displayName"] as? String) ?? ""
        self.avatarSymbol = (record["avatarSymbol"] as? String) ?? "leaf"
        self.avatarImageData = record["avatarImageData"] as? Data
        self.createdAt = createdAt
    }

    func populate(_ record: CKRecord) {
        record["displayName"] = displayName
        record["avatarSymbol"] = avatarSymbol
        record["avatarImageData"] = avatarImageData
        record["createdAt"] = createdAt
    }
}

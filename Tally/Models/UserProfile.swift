import CloudKit
import Foundation

/// The signed-in user's own profile. One per user, stored as a single CKRecord
/// at fixed `recordName = "ownProfile"` in their private default zone.
///
/// `avatarSymbol` is an SF Symbol name (e.g. "leaf"), not an emoji.
/// `username` is optional — users can claim a unique handle in profile
/// settings so friends can find them by username. The global uniqueness is
/// enforced by `UsernameRepository` against CloudKit's public DB.
struct UserProfile: Equatable, Hashable, Codable {
    var displayName: String
    var avatarSymbol: String
    var username: String?
    var createdAt: Date
}

extension UserProfile: CKRecordConvertible {
    static let recordType = "UserProfile"

    init?(record: CKRecord) {
        guard
            let displayName = record["displayName"] as? String,
            let avatarSymbol = record["avatarSymbol"] as? String,
            let createdAt = record["createdAt"] as? Date
        else { return nil }
        self.displayName = displayName
        self.avatarSymbol = avatarSymbol
        self.username = record["username"] as? String
        self.createdAt = createdAt
    }

    func populate(_ record: CKRecord) {
        record["displayName"] = displayName
        record["avatarSymbol"] = avatarSymbol
        record["username"] = username
        record["createdAt"] = createdAt
    }
}

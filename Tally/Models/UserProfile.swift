import CloudKit
import Foundation

/// The signed-in user's own profile. There's exactly one per user, stored as a single
/// CKRecord with fixed `recordName = "ownProfile"` in their private default zone.
///
/// Identity is implicit — fetched via `ProfileRepository.ownProfile()`. We don't carry
/// an id field on the struct because there's no "list of profiles" to disambiguate;
/// when we need cross-user identity later (CircleMember, message sender), we use
/// `CKContainer.userRecordID()` directly.
struct UserProfile: Equatable, Hashable, Codable {
    var displayName: String
    var avatarEmoji: String
    var createdAt: Date
}

extension UserProfile: CKRecordConvertible {
    static let recordType = "UserProfile"

    init?(record: CKRecord) {
        guard
            let displayName = record["displayName"] as? String,
            let avatarEmoji = record["avatarEmoji"] as? String,
            let createdAt = record["createdAt"] as? Date
        else { return nil }
        self.displayName = displayName
        self.avatarEmoji = avatarEmoji
        self.createdAt = createdAt
    }

    func populate(_ record: CKRecord) {
        record["displayName"] = displayName
        record["avatarEmoji"] = avatarEmoji
        record["createdAt"] = createdAt
    }
}

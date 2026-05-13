import CloudKit
import Foundation

/// The signed-in user's own profile. One per user, stored as a single CKRecord
/// at fixed `recordName = "ownProfile"` in their private default zone.
///
/// `avatarSymbol` is an SF Symbol name (e.g. "leaf"), not an emoji.
struct UserProfile: Equatable, Hashable, Codable {
    var displayName: String
    var avatarSymbol: String
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
        self.createdAt = createdAt
    }

    func populate(_ record: CKRecord) {
        record["displayName"] = displayName
        record["avatarSymbol"] = avatarSymbol
        record["createdAt"] = createdAt
    }
}

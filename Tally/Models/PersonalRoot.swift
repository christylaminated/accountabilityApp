import CloudKit
import Foundation

/// The root record inside each user's personal CloudKit zone. Habits, goals,
/// and check-ins live as children of this record so they automatically ride
/// the personal CKShare once participants are added (3e+).
///
/// Tiny on purpose — its only job is to exist so child records have a parent
/// to attach to and the share has a root to attach to.
struct PersonalRoot: Hashable, Codable {
    var createdAt: Date
}

extension PersonalRoot: CKRecordConvertible {
    static let recordType = "PersonalRoot"

    init?(record: CKRecord) {
        guard let createdAt = record["createdAt"] as? Date else { return nil }
        self.createdAt = createdAt
    }

    func populate(_ record: CKRecord) {
        record["createdAt"] = createdAt
    }
}

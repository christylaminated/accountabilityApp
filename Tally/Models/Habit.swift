import CloudKit
import Foundation

/// Whether a habit is visible to my friends or just to me.
/// `.shared` is the default; shared habits ride the personal CKShare and show
/// up on every friend's dashboard. `.private` habits are stored only in my
/// private DB default zone — friends never see them, but they still count
/// toward my own streaks.
enum HabitPrivacy: String, Codable, Hashable {
    case shared
    case `private`
}

struct Habit: Identifiable, Hashable, Codable {
    let id: UUID
    /// Owner's CloudKit user record name. String to match CK identity.
    var userID: String
    var title: String
    var privacy: HabitPrivacy
    var createdAt: Date
    var archivedAt: Date?
}

extension Habit: ZoneRecord {
    static let recordType = "Habit"
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
        // Default to .shared when decoding records written before this field
        // existed — that's the natural meaning of "habit synced via Circle zone".
        self.privacy = (record["privacy"] as? String).flatMap(HabitPrivacy.init(rawValue:)) ?? .shared
        self.createdAt = createdAt
        self.archivedAt = record["archivedAt"] as? Date
    }

    func populate(_ record: CKRecord) {
        record["id"] = id.uuidString
        record["userID"] = userID
        record["title"] = title
        record["privacy"] = privacy.rawValue
        record["createdAt"] = createdAt
        record["archivedAt"] = archivedAt
    }
}

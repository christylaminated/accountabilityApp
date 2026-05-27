import Foundation

/// A friend the signed-in user is bidirectionally sharing with. Derived from
/// the union of CKShare participants on my personal share + friend zones in
/// my shared DB. Display name + avatar come from each friend's `PersonalRoot`.
///
/// `avatarImageData` is an optional JPEG-compressed photo the friend
/// uploaded — when present, views prefer it over `avatarSymbol`.
struct Friend: Identifiable, Hashable, Codable {
    /// The friend's CloudKit user record name.
    let userID: String
    var displayName: String
    var avatarSymbol: String
    var avatarImageData: Data?

    init(userID: String, displayName: String, avatarSymbol: String, avatarImageData: Data? = nil) {
        self.userID = userID
        self.displayName = displayName
        self.avatarSymbol = avatarSymbol
        self.avatarImageData = avatarImageData
    }

    var id: String { userID }
}

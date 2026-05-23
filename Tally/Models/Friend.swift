import Foundation

/// A friend the signed-in user is bidirectionally sharing with. Derived from
/// the union of CKShare participants on my personal share + friend zones in
/// my shared DB. Display name + avatar come from each friend's `PersonalRoot`.
struct Friend: Identifiable, Hashable {
    /// The friend's CloudKit user record name.
    let userID: String
    var displayName: String
    var avatarSymbol: String

    var id: String { userID }
}

import Foundation

struct Profile: Identifiable, Hashable, Codable {
    let id: UUID
    var username: String
    var displayName: String
    /// SF Symbol name (e.g. "leaf", "mountain.2"). Replaces the old emoji avatar.
    var avatarSymbol: String
    var createdAt: Date
}

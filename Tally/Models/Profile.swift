import Foundation

struct Profile: Identifiable, Hashable, Codable {
    let id: UUID
    var username: String
    var displayName: String
    var avatarEmoji: String
    var createdAt: Date
}

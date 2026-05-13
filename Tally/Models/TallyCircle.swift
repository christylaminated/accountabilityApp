import Foundation

/// Named `TallyCircle` to avoid colliding with SwiftUI.Circle. Maps to the `circles` table.
struct TallyCircle: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var emoji: String?
    var ownerID: UUID
    var createdAt: Date
}

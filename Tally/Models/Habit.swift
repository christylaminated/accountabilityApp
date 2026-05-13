import Foundation

struct Habit: Identifiable, Hashable, Codable {
    let id: UUID
    var userID: UUID
    var title: String
    var createdAt: Date
    var archivedAt: Date?
}

import Foundation

struct HabitCompletion: Identifiable, Hashable, Codable {
    let id: UUID
    var habitID: UUID
    var userID: UUID
    var completedDate: Date
    var createdAt: Date
}

import Foundation

struct WeeklyGoal: Identifiable, Hashable, Codable {
    let id: UUID
    var userID: UUID
    var title: String
    var weekStartDate: Date
    var completedAt: Date?
    var carriedFromID: UUID?
    var createdAt: Date
}

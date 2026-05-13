import Foundation

struct CircleMessage: Identifiable, Hashable, Codable {
    let id: UUID
    var circleID: UUID
    var senderID: UUID
    var body: String
    var createdAt: Date
}

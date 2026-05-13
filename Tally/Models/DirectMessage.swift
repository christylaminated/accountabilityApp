import Foundation

struct DirectMessage: Identifiable, Hashable, Codable {
    let id: UUID
    var circleID: UUID
    var senderID: UUID
    var recipientID: UUID
    var body: String
    var createdAt: Date
    var readAt: Date?
}

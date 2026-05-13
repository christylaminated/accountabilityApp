import Foundation

enum CircleRole: String, Codable, Hashable {
    case owner
    case member
}

struct CircleMember: Hashable, Codable, Identifiable {
    var circleID: UUID
    var userID: UUID
    var role: CircleRole
    var joinedAt: Date

    var id: String { "\(circleID.uuidString)|\(userID.uuidString)" }
}

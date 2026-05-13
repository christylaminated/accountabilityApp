import Foundation
import Observation

@Observable
final class MockCircleStore {
    var circles: [TallyCircle]
    var members: [CircleMember]

    init(circles: [TallyCircle] = [MockData.circle],
         members: [CircleMember] = MockData.members) {
        self.circles = circles
        self.members = members
    }

    func circle(id: UUID) -> TallyCircle? {
        circles.first { $0.id == id }
    }

    func memberIDs(circleID: UUID) -> [UUID] {
        members.filter { $0.circleID == circleID }.map { $0.userID }
    }
}

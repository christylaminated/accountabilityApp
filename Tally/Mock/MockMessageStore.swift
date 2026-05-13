import Foundation
import Observation

@Observable
final class MockMessageStore {
    var circleMessages: [CircleMessage]
    var directMessages: [DirectMessage]

    init(circleMessages: [CircleMessage] = MockData.circleMessages,
         directMessages: [DirectMessage] = MockData.directMessages) {
        self.circleMessages = circleMessages
        self.directMessages = directMessages
    }

    // MARK: Circle feed

    func feed(circleID: UUID) -> [CircleMessage] {
        circleMessages
            .filter { $0.circleID == circleID }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func sendCircle(body: String, circleID: UUID, senderID: UUID) {
        circleMessages.append(CircleMessage(
            id: UUID(),
            circleID: circleID,
            senderID: senderID,
            body: body,
            createdAt: .now
        ))
    }

    // MARK: Direct messages (per-circle)

    func dmThread(circleID: UUID, between userA: UUID, and userB: UUID) -> [DirectMessage] {
        directMessages.filter {
            $0.circleID == circleID &&
            (($0.senderID == userA && $0.recipientID == userB) ||
             ($0.senderID == userB && $0.recipientID == userA))
        }.sorted { $0.createdAt < $1.createdAt }
    }

    func sendDM(body: String, circleID: UUID, senderID: UUID, recipientID: UUID) {
        directMessages.append(DirectMessage(
            id: UUID(),
            circleID: circleID,
            senderID: senderID,
            recipientID: recipientID,
            body: body,
            createdAt: .now,
            readAt: nil
        ))
    }

    func markDMsRead(circleID: UUID, viewer: UUID, otherUser: UUID) {
        for i in directMessages.indices {
            if directMessages[i].circleID == circleID,
               directMessages[i].recipientID == viewer,
               directMessages[i].senderID == otherUser,
               directMessages[i].readAt == nil {
                directMessages[i].readAt = .now
            }
        }
    }

    func unreadDMCount(for viewer: UUID, fromUser other: UUID, circleID: UUID) -> Int {
        directMessages.filter {
            $0.circleID == circleID &&
            $0.recipientID == viewer &&
            $0.senderID == other &&
            $0.readAt == nil
        }.count
    }
}

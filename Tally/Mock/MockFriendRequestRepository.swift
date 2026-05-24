import CloudKit
import Foundation
import Observation

/// In-memory FriendRequestRepository for SwiftUI Previews and tests.
@Observable
final class MockFriendRequestRepository: FriendRequestRepository, @unchecked Sendable {
    var requests: [FriendRequest]

    init(requests: [FriendRequest] = []) {
        self.requests = requests
    }

    func send(_ request: FriendRequest) async throws {
        requests.removeAll { $0.id == request.id }
        requests.append(request)
    }

    func incoming(for userRecordName: String) async throws -> [FriendRequest] {
        requests
            .filter { $0.toUserRecordName == userRecordName }
            .sorted { $0.sentAt > $1.sentAt }
    }

    func outgoing(for userRecordName: String) async throws -> [FriendRequest] {
        requests
            .filter { $0.fromUserRecordName == userRecordName }
            .sorted { $0.sentAt > $1.sentAt }
    }

    func delete(_ request: FriendRequest) async throws {
        requests.removeAll { $0.id == request.id }
    }
}

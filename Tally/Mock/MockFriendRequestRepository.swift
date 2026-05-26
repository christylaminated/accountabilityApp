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

/// In-memory GroupInviteRepository for SwiftUI Previews and tests.
@Observable
final class MockGroupInviteRepository: GroupInviteRepository, @unchecked Sendable {
    var invites: [GroupInvite]

    init(invites: [GroupInvite] = []) {
        self.invites = invites
    }

    func send(_ invite: GroupInvite) async throws {
        invites.removeAll { $0.id == invite.id }
        invites.append(invite)
    }

    func incoming(for userRecordName: String) async throws -> [GroupInvite] {
        invites
            .filter { $0.toUserRecordName == userRecordName }
            .sorted { $0.sentAt > $1.sentAt }
    }

    func outgoing(for userRecordName: String) async throws -> [GroupInvite] {
        invites
            .filter { $0.fromUserRecordName == userRecordName }
            .sorted { $0.sentAt > $1.sentAt }
    }

    func delete(_ invite: GroupInvite) async throws {
        invites.removeAll { $0.id == invite.id }
    }
}

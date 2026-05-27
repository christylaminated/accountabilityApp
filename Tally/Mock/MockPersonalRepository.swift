import CloudKit
import Foundation

/// In-memory `PersonalRepository` for previews and tests. No CloudKit.
final class MockPersonalRepository: PersonalRepository, @unchecked Sendable {
    var snapshot = PersonalSnapshot()
    var ensureCallCount = 0
    var friends: [CKRecord.ID] = []

    func ensurePersonalZone() async throws {
        ensureCallCount += 1
    }

    func ownSnapshot(since token: CKServerChangeToken?) async throws -> PersonalSnapshot {
        snapshot
    }

    func saveOwn(_ records: [any ZoneRecord]) async throws {}

    func deleteOwn(recordNames: [String]) async throws {}

    func ownPrivateSnapshot(since token: CKServerChangeToken?) async throws -> PersonalSnapshot {
        PersonalSnapshot()
    }

    func saveOwnPrivate(_ records: [any ZoneRecord]) async throws {}

    func deleteOwnPrivate(recordNames: [String]) async throws {}

    func makePersonalShare() async throws -> (CKShare, CKContainer) {
        (CKShare(recordZoneID: CKRecordZone.ID(zoneName: "mock")), .default())
    }

    func addFriendParticipant(userRecordID: CKRecord.ID) async throws {
        friends.append(userRecordID)
    }

    func removeFriendParticipant(userRecordID: CKRecord.ID) async throws {
        friends.removeAll { $0 == userRecordID }
    }

    func leaveFriendShare(ownerRecordName: String) async throws {
        // No-op for the mock; the symmetric half lives on the friend's device
        // in production. Previews don't model the other side.
    }

    func friendZones() async throws -> [CKRecordZone] { [] }

    func friendSnapshot(zoneID: CKRecordZone.ID, since token: CKServerChangeToken?) async throws -> PersonalSnapshot {
        PersonalSnapshot()
    }

    func updatePersonalRootProfile(
        displayName: String,
        avatarSymbol: String,
        avatarImageData: Data?,
        clearAvatarPhoto: Bool
    ) async throws {}
}

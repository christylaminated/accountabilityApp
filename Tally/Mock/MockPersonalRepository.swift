import CloudKit
import Foundation

/// In-memory `PersonalRepository` for previews and tests. No CloudKit.
final class MockPersonalRepository: PersonalRepository, @unchecked Sendable {
    var snapshot = PersonalSnapshot()
    var ensureCallCount = 0
    var friends: [CKRecord.ID] = []
    /// Friend zones surfaced by `friendZones()`. Empty by default (previews
    /// don't model the other side); tests populate it to simulate friends
    /// whose personal zone appears in our sharedDB.
    var friendZoneList: [CKRecordZone] = []
    /// Per-owner snapshots returned by `friendSnapshot`, keyed by the zone's
    /// `ownerName`. Missing owners fall back to an empty snapshot.
    var friendSnapshotsByOwner: [String: PersonalSnapshot] = [:]

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

    func removeFriendParticipant(userRecordID: CKRecord.ID) async throws -> RevokeOutcome {
        friends.removeAll { $0 == userRecordID }
        return .revoked
    }

    func leaveFriendShare(ownerRecordName: String) async throws {
        // No-op for the mock; the symmetric half lives on the friend's device
        // in production. Previews don't model the other side.
    }

    func friendZones() async throws -> [CKRecordZone] { friendZoneList }

    func friendSnapshot(zoneID: CKRecordZone.ID, since token: CKServerChangeToken?) async throws -> PersonalSnapshot {
        friendSnapshotsByOwner[zoneID.ownerName] ?? PersonalSnapshot()
    }

    func updatePersonalRootProfile(
        displayName: String,
        avatarSymbol: String,
        avatarImageData: Data?,
        clearAvatarPhoto: Bool
    ) async throws {}
}

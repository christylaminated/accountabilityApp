import CloudKit
import Foundation
import Observation

/// In-memory CircleRepository for SwiftUI Previews and tests. Share-related
/// methods are no-ops or throw, since CKShare can't be exercised without a real
/// CloudKit container.
@Observable
final class MockCircleRepository: CircleRepository, @unchecked Sendable {
    var owned: [TallyCircle]
    var joined: [TallyCircle]
    var membersByCircle: [UUID: [CircleMember]]

    init(
        owned: [TallyCircle] = [],
        joined: [TallyCircle] = [],
        membersByCircle: [UUID: [CircleMember]] = [:]
    ) {
        self.owned = owned
        self.joined = joined
        self.membersByCircle = membersByCircle
    }

    func ownedCircles() async throws -> [TallyCircle] { owned }
    func joinedCircles() async throws -> [TallyCircle] { joined }

    func createCircle(
        name: String,
        emoji: String?,
        ownerDisplayName: String,
        ownerAvatarSymbol: String,
        kind: CircleKind,
        dmPeerID: String?
    ) async throws -> TallyCircle {
        let circle = TallyCircle(
            id: UUID(),
            name: name,
            emoji: emoji,
            ownerID: "mock-owner",
            createdAt: .now,
            kind: kind,
            dmPeerID: dmPeerID
        )
        owned.append(circle)
        membersByCircle[circle.id] = [
            CircleMember(
                circleID: circle.id,
                userID: "mock-owner",
                displayName: ownerDisplayName,
                avatarSymbol: ownerAvatarSymbol,
                role: .owner,
                joinedAt: .now
            )
        ]
        return circle
    }

    /// Returns a bare CKShare with no backing container — fine for previews;
    /// never presented in a real share sheet.
    func makeShare(for circle: TallyCircle) async throws -> (CKShare, CKContainer) {
        (CKShare(recordZoneID: CKRecordZone.ID(zoneName: "mock")), .default())
    }

    func share(for circle: TallyCircle) async throws -> CKShare? { nil }

    func members(of circle: TallyCircle) async throws -> [CircleMember] {
        membersByCircle[circle.id] ?? []
    }

    func recordOwnMembership(
        circleID: UUID,
        displayName: String,
        avatarSymbol: String
    ) async throws {
        var members = membersByCircle[circleID] ?? []
        members.append(
            CircleMember(
                circleID: circleID,
                userID: "mock-self",
                displayName: displayName,
                avatarSymbol: avatarSymbol,
                role: .member,
                joinedAt: .now
            )
        )
        membersByCircle[circleID] = members
    }

    func removeMember(_ member: CircleMember, from circle: TallyCircle) async throws {
        membersByCircle[circle.id]?.removeAll { $0.userID == member.userID }
    }

    func leaveCircle(_ circle: TallyCircle) async throws {
        joined.removeAll { $0.id == circle.id }
    }

    func deleteCircle(_ circle: TallyCircle) async throws {
        owned.removeAll { $0.id == circle.id }
        membersByCircle[circle.id] = nil
    }

    func rename(_ circle: TallyCircle, to newName: String) async throws -> TallyCircle {
        var updated = circle
        updated.name = newName
        if let idx = owned.firstIndex(where: { $0.id == circle.id }) {
            owned[idx] = updated
        } else if let idx = joined.firstIndex(where: { $0.id == circle.id }) {
            joined[idx] = updated
        }
        return updated
    }

    func addMember(userRecordName: String, to circle: TallyCircle) async throws {
        var members = membersByCircle[circle.id] ?? []
        guard !members.contains(where: { $0.userID == userRecordName }) else { return }
        members.append(
            CircleMember(
                circleID: circle.id,
                userID: userRecordName,
                displayName: userRecordName,
                avatarSymbol: "person",
                role: .member,
                joinedAt: .now
            )
        )
        membersByCircle[circle.id] = members
    }
}

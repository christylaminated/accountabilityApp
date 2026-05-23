import CloudKit
import Foundation


/// Circle lifecycle backed by CloudKit.
///
/// ── DESIGN NOTE: trust-based integrity (deliberate v1 choice) ───────────────
/// CKShare permission is share-wide, not per-record. We use `.readWrite` so
/// participants can write the records they need to (their own messages,
/// completion summaries, membership row). CloudKit has no per-record ACLs within
/// a share, so a determined participant could technically modify another
/// member's records. The app never offers UI to do that. For a friends-and-
/// family accountability app this is an accepted tradeoff — enforced integrity
/// would require a server-mediated database, which we knowingly gave up when we
/// chose CloudKit over Supabase. Revisit if Tally ever opens past trusted pairs.
/// ────────────────────────────────────────────────────────────────────────────
protocol CircleRepository: Sendable {
    /// Circles this user owns (zones in their private DB).
    func ownedCircles() async throws -> [TallyCircle]

    /// Circles this user has joined (zones in their shared DB).
    func joinedCircles() async throws -> [TallyCircle]

    /// Create a Circle: new custom zone, root record, and the owner's
    /// CircleMember row. No share yet — the share is minted lazily by
    /// `makeShare(for:)` when the user actually invites someone.
    func createCircle(
        name: String,
        emoji: String?,
        ownerDisplayName: String,
        ownerAvatarSymbol: String
    ) async throws -> TallyCircle

    /// Create-or-fetch the CKShare for a Circle and return it with its container.
    /// Called lazily by `UICloudSharingController`'s preparationHandler so the
    /// controller owns the save→present timing (avoids "couldn't create a link").
    func makeShare(for circle: TallyCircle) async throws -> (CKShare, CKContainer)

    /// Fetch the existing CKShare for a Circle, or nil if not yet shared.
    func share(for circle: TallyCircle) async throws -> CKShare?

    /// Members of a Circle (CircleMember records in its zone).
    func members(of circle: TallyCircle) async throws -> [CircleMember]

    /// Record the current user's membership after they accept a share invite.
    /// Enforces the member cap client-side before writing.
    func recordOwnMembership(
        circleID: UUID,
        displayName: String,
        avatarSymbol: String
    ) async throws

    /// Owner removes a participant: drops them from the CKShare AND deletes their
    /// CircleMember record in one operation — no tombstone left behind.
    func removeMember(_ member: CircleMember, from circle: TallyCircle) async throws

    /// Participant leaves a Circle (removes self from the share). Not for owners.
    func leaveCircle(_ circle: TallyCircle) async throws

    /// Owner deletes a Circle entirely: deletes the zone, which cascade-deletes
    /// every record inside it (root, members, messages, summaries, the share).
    func deleteCircle(_ circle: TallyCircle) async throws
}

// MARK: - CloudKit implementation

struct CloudKitCircleRepository: CircleRepository {
    let client: CKClient

    /// Fixed recordName for the single Circle root record inside each zone.
    static let rootRecordName = "circleRoot"

    init(client: CKClient = .shared) {
        self.client = client
    }

    // MARK: Fetch

    func ownedCircles() async throws -> [TallyCircle] {
        let zones = try await client.ownedCircleZones()
        return try await circles(in: zones, db: client.privateDB)
    }

    func joinedCircles() async throws -> [TallyCircle] {
        let zones = try await client.joinedCircleZones()
        return try await circles(in: zones, db: client.sharedDB)
    }

    private func circles(in zones: [CKRecordZone], db: CKDatabase) async throws -> [TallyCircle] {
        var result: [TallyCircle] = []
        for zone in zones {
            let rootID = CKRecord.ID(recordName: Self.rootRecordName, zoneID: zone.zoneID)
            do {
                let record = try await db.record(for: rootID)
                if let circle = TallyCircle(record: record) {
                    result.append(circle)
                }
            } catch let error as CKError where error.code == .unknownItem {
                continue // zone exists but no root yet — skip
            }
        }
        return result
    }

    // MARK: Create

    func createCircle(
        name: String,
        emoji: String?,
        ownerDisplayName: String,
        ownerAvatarSymbol: String
    ) async throws -> TallyCircle {
        let circleID = UUID()
        let zoneName = CKClient.circleZoneName(circleID: circleID)
        let ownerID = try await client.userRecordID().recordName

        // 1. Custom zone in the owner's private DB.
        let zone = try await client.createPrivateZone(named: zoneName)
        let zoneID = zone.zoneID

        // 2. Circle root record.
        let circle = TallyCircle(
            id: circleID,
            name: name,
            emoji: emoji,
            ownerID: ownerID,
            createdAt: .now
        )
        let rootID = CKRecord.ID(recordName: Self.rootRecordName, zoneID: zoneID)
        let rootRecord = circle.toRecord(recordID: rootID)

        // 3. Owner's membership row, parented to the root so it follows the share.
        let owner = CircleMember(
            circleID: circleID,
            userID: ownerID,
            displayName: ownerDisplayName,
            avatarSymbol: ownerAvatarSymbol,
            role: .owner,
            joinedAt: .now
        )
        let memberID = CKRecord.ID(recordName: "member-\(ownerID)", zoneID: zoneID)
        let memberRecord = owner.toRecord(
            recordID: memberID,
            parent: CKRecord.Reference(recordID: rootID, action: .none)
        )

        // 4. Save root + owner member. Share is created lazily in makeShare.
        _ = try await client.privateDB.modifyRecords(
            saving: [rootRecord, memberRecord],
            deleting: []
        )

        return circle
    }

    func makeShare(for circle: TallyCircle) async throws -> (CKShare, CKContainer) {
        let (db, zoneID) = try await locate(circle)
        let rootID = CKRecord.ID(recordName: Self.rootRecordName, zoneID: zoneID)
        let root = try await db.record(for: rootID)

        // Reuse an existing share if the root already has one — but fetch it
        // fresh from the server so we hand `UICloudSharingController` a share
        // with current change tag + URL, not a stale local copy.
        if let shareRef = root.share {
            let fetched = try await db.record(for: shareRef.recordID)
            if let existing = fetched as? CKShare {
                return (existing, client.container)
            }
        }

        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = "Join \(circle.name) on Tally" as CKRecordValue
        share.publicPermission = .none

        // Save root + share together. Both must succeed; surface either failure
        // verbatim so the caller can show the real CloudKit error instead of
        // swallowing it into a generic "couldn't create a link".
        let result = try await db.modifyRecords(saving: [root, share], deleting: [])
        if let rootResult = result.saveResults[root.recordID] {
            _ = try rootResult.get()
        }
        guard let saved = try result.saveResults[share.recordID]?.get() as? CKShare else {
            throw CKClientError.unexpected("Share was saved but not returned by the server.")
        }
        return (saved, client.container)
    }

    // MARK: Share

    func share(for circle: TallyCircle) async throws -> CKShare? {
        let (db, zoneID) = try await locate(circle)
        let rootID = CKRecord.ID(recordName: Self.rootRecordName, zoneID: zoneID)
        let root = try await db.record(for: rootID)
        guard let shareRef = root.share else { return nil }
        let shareRecord = try await db.record(for: shareRef.recordID)
        return shareRecord as? CKShare
    }

    // MARK: Members

    func members(of circle: TallyCircle) async throws -> [CircleMember] {
        let (db, zoneID) = try await locate(circle)
        return try await membersInZone(db: db, zoneID: zoneID)
    }

    func recordOwnMembership(
        circleID: UUID,
        displayName: String,
        avatarSymbol: String
    ) async throws {
        let zoneName = CKClient.circleZoneName(circleID: circleID)
        // A joined Circle lives in the shared DB.
        guard let zone = try await client.joinedCircleZones()
            .first(where: { $0.zoneID.zoneName == zoneName })
        else {
            throw CKClientError.unexpected("Joined Circle zone not found.")
        }
        let zoneID = zone.zoneID
        let userID = try await client.userRecordID().recordName

        // Client-side member cap. CloudKit can't enforce this.
        let rootID = CKRecord.ID(recordName: Self.rootRecordName, zoneID: zoneID)
        let rootRecord = try await client.sharedDB.record(for: rootID)
        let existing = try await membersInZone(db: client.sharedDB, zoneID: zoneID)
        if existing.count >= Constants.maxCircleMembers {
            throw CKClientError.unexpected("This Circle is full (\(Constants.maxCircleMembers) members).")
        }

        let member = CircleMember(
            circleID: circleID,
            userID: userID,
            displayName: displayName,
            avatarSymbol: avatarSymbol,
            role: .member,
            joinedAt: .now
        )
        let recordID = CKRecord.ID(recordName: "member-\(userID)", zoneID: zoneID)
        let record = member.toRecord(
            recordID: recordID,
            parent: CKRecord.Reference(recordID: rootRecord.recordID, action: .none)
        )
        _ = try await client.sharedDB.modifyRecords(saving: [record], deleting: [])
    }

    // MARK: Membership changes

    func removeMember(_ member: CircleMember, from circle: TallyCircle) async throws {
        // Owner-only path. Combined op: drop the CKShare participant AND delete
        // the CircleMember record so no tombstone remains.
        let (db, zoneID) = try await locate(circle)

        guard let share = try await share(for: circle) else {
            throw CKClientError.unexpected("Circle has no share to modify.")
        }
        if let participant = share.participants.first(where: {
            $0.userIdentity.userRecordID?.recordName == member.userID
        }) {
            share.removeParticipant(participant)
        }

        let memberRecordID = CKRecord.ID(
            recordName: "member-\(member.userID)",
            zoneID: zoneID
        )
        _ = try await db.modifyRecords(
            saving: [share],
            deleting: [memberRecordID]
        )
    }

    func leaveCircle(_ circle: TallyCircle) async throws {
        // Participant-only path: remove self from the share. CloudKit moves the
        // zone out of our shared DB automatically.
        let (db, _) = try await locate(circle)
        guard let share = try await share(for: circle) else {
            throw CKClientError.unexpected("Circle has no share.")
        }
        let myRecordName = try await client.userRecordID().recordName
        if let me = share.participants.first(where: {
            $0.userIdentity.userRecordID?.recordName == myRecordName
        }) {
            share.removeParticipant(me)
            _ = try await db.modifyRecords(saving: [share], deleting: [])
        }
    }

    func deleteCircle(_ circle: TallyCircle) async throws {
        // Owner-only. Zone deletion cascades: root, members, messages, summaries,
        // and the CKShare all go in one server-side op.
        let zoneName = CKClient.circleZoneName(circleID: circle.id)
        try await client.deletePrivateZone(named: zoneName)
    }

    // MARK: Helpers

    /// Resolve which database + zone a Circle lives in (owned → private,
    /// joined → shared).
    private func locate(_ circle: TallyCircle) async throws -> (CKDatabase, CKRecordZone.ID) {
        let zoneName = CKClient.circleZoneName(circleID: circle.id)
        if let z = try await client.ownedCircleZones()
            .first(where: { $0.zoneID.zoneName == zoneName }) {
            return (client.privateDB, z.zoneID)
        }
        if let z = try await client.joinedCircleZones()
            .first(where: { $0.zoneID.zoneName == zoneName }) {
            return (client.sharedDB, z.zoneID)
        }
        throw CKClientError.unexpected("Circle zone not found: \(zoneName)")
    }

    /// Query-free member lookup: fetch the whole zone and decode the membership
    /// rows. Avoids needing a Queryable index in the CloudKit Dashboard.
    private func membersInZone(db: CKDatabase, zoneID: CKRecordZone.ID) async throws -> [CircleMember] {
        let changes = try await client.fetchZoneChanges(zoneID: zoneID, in: db, since: nil)
        return changes.changedRecords.compactMap(CircleMember.init(record:))
    }
}

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
    /// `kind` distinguishes a normal Group from a 1:1 DM; for DMs the
    /// `dmPeerID` is the other participant's user record name.
    func createCircle(
        name: String,
        emoji: String?,
        ownerDisplayName: String,
        ownerAvatarSymbol: String,
        kind: CircleKind,
        dmPeerID: String?
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

    /// Leave a joined Circle addressed directly by its shared zone — used by
    /// account deletion to leave EVERY joined circle enumerated from CloudKit,
    /// not just the ones currently loaded into the in-memory `joinedCircles`.
    /// Same effect as `leaveCircle` (deletes our member record + drops us from
    /// the share), crash-safe via the exception shim.
    func leaveJoinedCircleZone(_ zone: CKRecordZone) async throws

    /// Owner deletes a Circle entirely: deletes the zone, which cascade-deletes
    /// every record inside it (root, members, messages, summaries, the share).
    func deleteCircle(_ circle: TallyCircle) async throws

    /// Rename a Circle. Any participant can call this — the root record lives in
    /// the shared zone and the share grants .readWrite to everyone.
    func rename(_ circle: TallyCircle, to newName: String) async throws -> TallyCircle

    /// Owner adds a known user to the Circle by their CKRecord.ID.recordName
    /// (resolved upstream from a username lookup). Mirrors PersonalRepository's
    /// addFriendParticipant: ensures the share exists, looks up the participant,
    /// adds them with .readWrite, saves. Only the owner can save the share record.
    func addMember(userRecordName: String, to circle: TallyCircle) async throws
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
        ownerAvatarSymbol: String,
        kind: CircleKind,
        dmPeerID: String?
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
            createdAt: .now,
            kind: kind,
            dmPeerID: dmPeerID
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

        // 4. Save root + owner member. `modifyRecords` does NOT throw on
        //    per-record failures — it returns a per-record results map — so
        //    we MUST inspect the root's result explicitly. A silently
        //    dropped root would make every later `makeShare` fail with
        //    "Record not found" (which is exactly the group-invite error
        //    the user hit). Throwing here surfaces it at creation time
        //    instead of leaving a half-created, un-shareable group.
        let result = try await client.privateDB.modifyRecords(
            saving: [rootRecord, memberRecord],
            deleting: []
        )
        guard let rootResult = result.saveResults[rootID] else {
            throw CKClientError.unexpected("Group root wasn't saved — try again.")
        }
        _ = try rootResult.get()

        return circle
    }

    func makeShare(for circle: TallyCircle) async throws -> (CKShare, CKContainer) {
        let (db, zoneID) = try await locate(circle)
        let rootID = CKRecord.ID(recordName: Self.rootRecordName, zoneID: zoneID)

        // Fetch the root with retry. Right after `createCircle`, the root
        // record can briefly lag before a subsequent fetch sees it
        // (CloudKit eventual consistency in a freshly-created zone). Without
        // this, inviting a member immediately after creating the group
        // fails with "Error fetching record … circleRoot … Record not
        // found" — the exact error from the user's screenshot.
        var root: CKRecord?
        for attempt in 0..<5 {
            do {
                root = try await db.record(for: rootID)
                break
            } catch let error as CKError where error.code == .unknownItem {
                NSLog("[Tally] makeShare: circleRoot not visible yet (attempt \(attempt + 1)) — retrying")
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
        }
        guard let root else {
            throw CKClientError.unexpected("Couldn't load the group yet — try again in a moment.")
        }

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
        // .readWrite so anyone tapping the link can join AND write messages /
        // their own membership record. Link sharing is the whole point — with
        // .none the recipient would get "permission denied" on accept.
        share.publicPermission = .readWrite

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
        // Participant-only path: clean up our membership record AND remove
        // self from the share. Order matters — we delete the CircleMember
        // record FIRST while we still have .readWrite access to the shared
        // zone (granted by the share), because we lose that access the
        // moment we leave the share. Otherwise the member record would
        // tombstone-leak in the owner's zone, showing us as a former member
        // forever.
        let (db, zoneID) = try await locate(circle)
        guard let share = try await share(for: circle) else {
            throw CKClientError.unexpected("Circle has no share.")
        }
        let myRecordName = try await client.userRecordID().recordName

        let memberRecordID = CKRecord.ID(
            recordName: "member-\(myRecordName)",
            zoneID: zoneID
        )
        _ = try? await db.deleteRecord(withID: memberRecordID)

        if let me = share.participants.first(where: {
            $0.userIdentity.userRecordID?.recordName == myRecordName
        }) {
            // Same iOS 26 NSException risk as PersonalRepository.leaveFriendShare
            // (removeParticipant on an owner's share we don't own) — run it
            // through the shim so a raised exception is caught, not fatal.
            do {
                try ExceptionCatcher.catchException { share.removeParticipant(me) }
            } catch {
                NSLog("[Tally] leaveCircle: removeParticipant raised, caught via shim — skipping: \(error.localizedDescription)")
                return
            }
            _ = try await db.modifyRecords(saving: [share], deleting: [])
        }
    }

    /// Leave a joined Circle by its shared zone. Mirrors `leaveCircle` but
    /// works purely from the zone (no TallyCircle needed), so account deletion
    /// can leave circles it enumerated straight from CloudKit.
    func leaveJoinedCircleZone(_ zone: CKRecordZone) async throws {
        let db = client.sharedDB
        let zoneID = zone.zoneID
        let myRecordName = try await client.userRecordID().recordName

        // Delete our membership row FIRST, while the share still grants write
        // access to the zone (same ordering rationale as leaveCircle).
        let memberRecordID = CKRecord.ID(recordName: "member-\(myRecordName)", zoneID: zoneID)
        _ = try? await db.deleteRecord(withID: memberRecordID)

        let rootID = CKRecord.ID(recordName: Self.rootRecordName, zoneID: zoneID)
        let root: CKRecord
        do {
            root = try await db.record(for: rootID)
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            // Zone already being torn down server-side — nothing left to leave.
            return
        }
        guard let shareRef = root.share,
              let share = try await db.record(for: shareRef.recordID) as? CKShare,
              let me = share.currentUserParticipant,
              me.role != .owner,
              me.acceptanceStatus == .accepted,
              share.participants.contains(where: { $0 == me })
        else { return }

        do {
            try ExceptionCatcher.catchException { share.removeParticipant(me) }
        } catch {
            NSLog("[Tally] leaveJoinedCircleZone: removeParticipant raised, caught via shim — skipping (\(zoneID.zoneName)): \(error.localizedDescription)")
            return
        }
        _ = try await db.modifyRecords(
            saving: [share],
            deleting: [],
            savePolicy: .ifServerRecordUnchanged,
            atomically: false
        )
    }

    func deleteCircle(_ circle: TallyCircle) async throws {
        // Owner-only. Zone deletion cascades: root, members, messages, summaries,
        // and the CKShare all go in one server-side op.
        let zoneName = CKClient.circleZoneName(circleID: circle.id)
        try await client.deletePrivateZone(named: zoneName)
    }

    func rename(_ circle: TallyCircle, to newName: String) async throws -> TallyCircle {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CKClientError.unexpected("Circle name can't be empty.")
        }
        let (db, zoneID) = try await locate(circle)
        let rootID = CKRecord.ID(recordName: Self.rootRecordName, zoneID: zoneID)
        let root = try await db.record(for: rootID)
        root["name"] = trimmed
        _ = try await db.modifyRecords(saving: [root], deleting: [])
        var updated = circle
        updated.name = trimmed
        return updated
    }

    func addMember(userRecordName: String, to circle: TallyCircle) async throws {
        // Adding a participant modifies the share record, which lives in the
        // owner's private DB. CloudKit will reject this from a non-owner.
        let (share, _) = try await makeShare(for: circle)

        let userRecordID = CKRecord.ID(recordName: userRecordName)
        if share.participants.contains(where: {
            $0.userIdentity.userRecordID == userRecordID
        }) {
            return
        }

        let existing = try await members(of: circle)
        if existing.count >= Constants.maxCircleMembers {
            throw CKClientError.unexpected("This Circle is full (\(Constants.maxCircleMembers) members).")
        }

        let participant = try await lookupParticipant(userRecordID: userRecordID)
        participant.permission = .readWrite
        share.addParticipant(participant)

        _ = try await client.privateDB.modifyRecords(
            saving: [share],
            deleting: [],
            savePolicy: .allKeys,
            atomically: false
        )
    }

    /// Resolve a user record ID into a `CKShare.Participant` we can add to a share.
    /// Mirrors `PersonalRepository.lookupParticipant`.
    private func lookupParticipant(userRecordID: CKRecord.ID) async throws -> CKShare.Participant {
        let lookupInfo = CKUserIdentity.LookupInfo(userRecordID: userRecordID)
        return try await withCheckedThrowingContinuation { continuation in
            var fetched: CKShare.Participant?
            let op = CKFetchShareParticipantsOperation(userIdentityLookupInfos: [lookupInfo])
            op.perShareParticipantResultBlock = { _, result in
                if case .success(let participant) = result {
                    fetched = participant
                }
            }
            op.fetchShareParticipantsResultBlock = { result in
                switch result {
                case .success:
                    if let participant = fetched {
                        continuation.resume(returning: participant)
                    } else {
                        continuation.resume(throwing: CKClientError.unexpected(
                            "Couldn't resolve user to a share participant."
                        ))
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            client.container.add(op)
        }
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

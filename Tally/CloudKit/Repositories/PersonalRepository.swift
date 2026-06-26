import CloudKit
import Foundation

/// Decoded contents of a personal CloudKit zone — habits, completions, goals.
/// Returned both for my own zone (private DB) and for each friend's zone
/// (shared DB) by `PersonalRepository`.
struct PersonalSnapshot {
    var root: PersonalRoot?
    var habits: [Habit] = []
    var completions: [HabitCompletion] = []
    var goals: [Goal] = []
    var deletedRecordNames: [String] = []
    var token: CKServerChangeToken?
    var isIncremental = false
}

/// Result of attempting to revoke a friend's access to my personal share.
/// Lets the caller distinguish "they definitely have no access" (the unfriend
/// can finish cleanly) from "I couldn't revoke and their access may persist"
/// (the caller should flag it). Without this, `removeFriendParticipant`'s
/// defensive early-returns all looked identical to success, so a corrupt
/// state silently left a friend with retained access while the app reported
/// the unfriend as complete.
enum RevokeOutcome: CustomStringConvertible {
    /// `removeParticipant` ran and the share saved — access is gone.
    case revoked
    /// They weren't a live participant to begin with (no share, not on it,
    /// or already `.removed`): nothing to revoke, they have no access. Safe
    /// for the unfriend to finish.
    case alreadyAbsent
    /// A guard prevented removal in a state where access MAY still remain
    /// (e.g. a corrupt owner-role participant, an unknown acceptance status).
    /// The associated reason is human-readable for surfacing to the user.
    case refused(String)

    var description: String {
        switch self {
        case .revoked:            return "revoked"
        case .alreadyAbsent:      return "alreadyAbsent"
        case .refused(let r):     return "refused(\(r))"
        }
    }
}

/// Manages the signed-in user's personal CloudKit zone — the one holding their
/// shared habits + goals — *and* fetches each friend's personal zone from the
/// shared DB. The friend graph is the participant list of my personal CKShare.
protocol PersonalRepository: Sendable {
    /// Idempotent. Creates both personal zones + root records if absent:
    /// `personalData` (shared with friends) and `personalPrivate` (just me).
    func ensurePersonalZone() async throws

    /// Fetch my shared personal zone. `token == nil` loads everything;
    /// otherwise returns the delta since that token.
    func ownSnapshot(since token: CKServerChangeToken?) async throws -> PersonalSnapshot

    /// Upsert records into my shared personal zone, parented to PersonalRoot.
    func saveOwn(_ records: [any ZoneRecord]) async throws

    /// Delete records by name from my shared personal zone.
    func deleteOwn(recordNames: [String]) async throws

    /// Fetch my private zone (the one no friend ever sees).
    func ownPrivateSnapshot(since token: CKServerChangeToken?) async throws -> PersonalSnapshot

    /// Upsert records into my private zone. No share, no parent — these stay
    /// on my own devices only (synced across them via the private DB).
    func saveOwnPrivate(_ records: [any ZoneRecord]) async throws

    /// Delete records by name from my private zone.
    func deleteOwnPrivate(recordNames: [String]) async throws

    /// Write the user's display name + avatar (symbol + optional photo bytes)
    /// into PersonalRoot so friends can render this user. Idempotent. Pass
    /// `clearAvatarPhoto: true` to wipe a previously-set photo; otherwise a
    /// nil `avatarImageData` preserves whatever's already stored.
    func updatePersonalRootProfile(
        displayName: String,
        avatarSymbol: String,
        avatarImageData: Data?,
        clearAvatarPhoto: Bool
    ) async throws

    /// Mint or fetch the CKShare on my personal zone. Required before inviting
    /// anyone as a friend.
    func makePersonalShare() async throws -> (CKShare, CKContainer)

    /// Look up the given user record ID and add them as a participant on my
    /// personal share — the bidirectional half of accepting their share.
    func addFriendParticipant(userRecordID: CKRecord.ID) async throws

    /// Remove a friend from my personal share (unfriend, on my side).
    /// Returns a `RevokeOutcome` so the caller can tell a real revocation /
    /// already-absent (both safe) from a refusal where access may persist.
    /// Still `throws` on an actual CloudKit write failure (network) — that's
    /// distinct from a refusal and should abort the unfriend for retry.
    func removeFriendParticipant(userRecordID: CKRecord.ID) async throws -> RevokeOutcome

    /// Leave a friend's personal share (the symmetric half of unfriending —
    /// removes me from their share so their zone drops out of my sharedDB).
    /// Non-owners can remove themselves from a share via sharedDB; CloudKit
    /// permits this so participants always have an "I'm out" option.
    func leaveFriendShare(ownerRecordName: String) async throws

    /// All personal zones from friends who've shared with me (lives in shared DB).
    /// Their data is fetched via `friendSnapshot`.
    func friendZones() async throws -> [CKRecordZone]

    /// Fetch a specific friend's personal zone.
    func friendSnapshot(zoneID: CKRecordZone.ID, since token: CKServerChangeToken?) async throws -> PersonalSnapshot
}

// MARK: - CloudKit implementation

struct CloudKitPersonalRepository: PersonalRepository {
    let client: CKClient

    /// Fixed zone name for the *shared* personal zone in the user's private DB.
    /// One per user, ever. Friend zones in the shared DB also use this name —
    /// every user names their shared zone the same thing; the zone's ownerName
    /// disambiguates whose zone it is.
    static let zoneName = "personalData"

    /// Fixed zone name for the *private* zone in the user's private DB. Same
    /// custom-zone mechanism as `zoneName` (so we can use change-tokens), but
    /// never shared with anyone.
    static let privateZoneName = "personalPrivate"

    /// Fixed root record name inside each zone.
    static let rootRecordName = "personalRoot"

    init(client: CKClient = .shared) {
        self.client = client
    }

    /// Resolved zone ID for the shared personal zone.
    var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
    }

    /// Resolved zone ID for the private personal zone.
    var privateZoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: Self.privateZoneName, ownerName: CKCurrentUserDefaultName)
    }

    /// Root record ID inside the shared personal zone.
    var rootRecordID: CKRecord.ID {
        CKRecord.ID(recordName: Self.rootRecordName, zoneID: zoneID)
    }

    /// Root record ID inside the private personal zone.
    var privateRootRecordID: CKRecord.ID {
        CKRecord.ID(recordName: Self.rootRecordName, zoneID: privateZoneID)
    }

    // MARK: Lifecycle

    func ensurePersonalZone() async throws {
        try await ensureZone(rootID: rootRecordID, zoneName: Self.zoneName)
        try await ensureZone(rootID: privateRootRecordID, zoneName: Self.privateZoneName)
    }

    /// Idempotent: fetch the root record; on `.zoneNotFound` create the zone +
    /// root; on `.unknownItem` create just the root.
    private func ensureZone(rootID: CKRecord.ID, zoneName: String) async throws {
        do {
            _ = try await client.privateDB.record(for: rootID)
        } catch let error as CKError where error.code == .zoneNotFound {
            _ = try await client.createPrivateZone(named: zoneName)
            try await createRoot(at: rootID)
        } catch let error as CKError where error.code == .unknownItem {
            try await createRoot(at: rootID)
        }
    }

    // MARK: Own zone CRUD

    func ownSnapshot(since token: CKServerChangeToken?) async throws -> PersonalSnapshot {
        try await snapshot(zoneID: zoneID, in: client.privateDB, since: token)
    }

    func saveOwn(_ records: [any ZoneRecord]) async throws {
        guard !records.isEmpty else { return }
        let parent = CKRecord.Reference(recordID: rootRecordID, action: .none)
        let ckRecords = records.map { record -> CKRecord in
            let id = CKRecord.ID(recordName: record.recordName, zoneID: zoneID)
            return record.toRecord(recordID: id, parent: parent)
        }
        _ = try await client.privateDB.modifyRecords(
            saving: ckRecords,
            deleting: [],
            savePolicy: .allKeys,
            atomically: false
        )
    }

    func deleteOwn(recordNames: [String]) async throws {
        guard !recordNames.isEmpty else { return }
        let ids = recordNames.map { CKRecord.ID(recordName: $0, zoneID: zoneID) }
        _ = try await client.privateDB.modifyRecords(
            saving: [],
            deleting: ids,
            savePolicy: .allKeys,
            atomically: false
        )
    }

    // MARK: Private zone CRUD

    func ownPrivateSnapshot(since token: CKServerChangeToken?) async throws -> PersonalSnapshot {
        try await snapshot(zoneID: privateZoneID, in: client.privateDB, since: token)
    }

    func saveOwnPrivate(_ records: [any ZoneRecord]) async throws {
        guard !records.isEmpty else { return }
        let parent = CKRecord.Reference(recordID: privateRootRecordID, action: .none)
        let ckRecords = records.map { record -> CKRecord in
            let id = CKRecord.ID(recordName: record.recordName, zoneID: privateZoneID)
            return record.toRecord(recordID: id, parent: parent)
        }
        _ = try await client.privateDB.modifyRecords(
            saving: ckRecords,
            deleting: [],
            savePolicy: .allKeys,
            atomically: false
        )
    }

    func deleteOwnPrivate(recordNames: [String]) async throws {
        guard !recordNames.isEmpty else { return }
        let ids = recordNames.map { CKRecord.ID(recordName: $0, zoneID: privateZoneID) }
        _ = try await client.privateDB.modifyRecords(
            saving: [],
            deleting: ids,
            savePolicy: .allKeys,
            atomically: false
        )
    }

    // MARK: Share / friend graph

    func makePersonalShare() async throws -> (CKShare, CKContainer) {
        try await ensurePersonalZone()
        let root = try await client.privateDB.record(for: rootRecordID)

        if let shareRef = root.share {
            let fetched = try await client.privateDB.record(for: shareRef.recordID)
            if let existing = fetched as? CKShare {
                return (existing, client.container)
            }
        }

        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = "Add me on Tally" as CKRecordValue
        // .readOnly so anyone tapping the link can join (otherwise they'd get
        // "permission denied"), but they can only *read* my data — they can't
        // modify my habits or goals. The bidirectional friend graph means
        // they'll share their own zone back with the same permission.
        share.publicPermission = .readOnly

        let result = try await client.privateDB.modifyRecords(saving: [root, share], deleting: [])
        if let rootResult = result.saveResults[root.recordID] {
            _ = try rootResult.get()
        }
        guard let saved = try result.saveResults[share.recordID]?.get() as? CKShare else {
            throw CKClientError.unexpected("Personal share was saved but not returned by the server.")
        }
        return (saved, client.container)
    }

    func addFriendParticipant(userRecordID: CKRecord.ID) async throws {
        let (share, _) = try await makePersonalShare()

        // Already a participant? Nothing to do.
        if share.participants.contains(where: { $0.userIdentity.userRecordID == userRecordID }) {
            return
        }

        // Friend graph cap (client-side; CloudKit's hard ceiling is higher).
        let nonOwnerCount = share.participants.filter { $0.role != .owner }.count
        guard nonOwnerCount < Constants.maxPersonalShareParticipants else {
            throw CKClientError.unexpected("Friend limit reached (\(Constants.maxPersonalShareParticipants)).")
        }

        let participant = try await lookupParticipant(userRecordID: userRecordID)
        // Friends only need to *read* my data, not modify it.
        participant.permission = .readOnly
        share.addParticipant(participant)

        _ = try await client.privateDB.modifyRecords(
            saving: [share],
            deleting: [],
            savePolicy: .allKeys,
            atomically: false
        )
    }

    func removeFriendParticipant(userRecordID: CKRecord.ID) async throws -> RevokeOutcome {
        NSLog("[Tally] removeFriendParticipant: start friend=\(userRecordID.recordName)")
        let root: CKRecord
        do {
            root = try await client.privateDB.record(for: rootRecordID)
        } catch let error as CKError where error.code == .unknownItem {
            // No personal root → no share exists → they can't be a
            // participant → they have no access. Safe.
            NSLog("[Tally] removeFriendParticipant: no own root — nothing to revoke")
            return .alreadyAbsent
        }
        guard let shareRef = root.share else {
            NSLog("[Tally] removeFriendParticipant: no share on my root — nothing to revoke")
            return .alreadyAbsent
        }
        let fetched: CKRecord
        do {
            fetched = try await client.privateDB.record(for: shareRef.recordID)
        } catch let error as CKError where error.code == .unknownItem {
            NSLog("[Tally] removeFriendParticipant: share record missing — nothing to revoke")
            return .alreadyAbsent
        }
        guard let share = fetched as? CKShare else {
            // Unexpected: the share ref points at a non-share record. We
            // can't revoke and can't reason about access → refuse.
            NSLog("[Tally] removeFriendParticipant: share record cast failed")
            return .refused("Share record couldn't be read as a CKShare.")
        }

        // Compare by recordName rather than full CKRecord.ID — userRecordIDs
        // always live in `_defaultZone` but the equality check is finicky.
        guard let participant = share.participants.first(where: {
            $0.userIdentity.userRecordID?.recordName == userRecordID.recordName
        }) else {
            // Not on the share → no access. Safe (e.g. re-unfriending
            // someone already removed).
            NSLog("[Tally] removeFriendParticipant: not a participant — already absent")
            return .alreadyAbsent
        }

        // Defensive guards (the build-16 crash log showed CKShare.removeParticipant
        // raising an uncatchable NSException from this call site in certain
        // states). Each guard now maps to a RevokeOutcome so the caller knows
        // whether access is genuinely gone or merely couldn't be revoked.

        // Owner-role participant: should be impossible (a friend can't own MY
        // share) → corrupt state. We cannot safely remove, and access may
        // remain → REFUSED so the caller can flag it.
        guard participant.role != .owner else {
            NSLog("[Tally] removeFriendParticipant: friend appears as OWNER — refusing")
            return .refused("Friend appears as the owner of my share (corrupt state); access may remain.")
        }

        // Acceptance status:
        //   .accepted / .pending → live participant, proceed to remove.
        //   .removed             → already gone → alreadyAbsent (safe).
        //   .unknown / future    → can't confirm access state → refused.
        switch participant.acceptanceStatus {
        case .accepted, .pending:
            break
        case .removed:
            NSLog("[Tally] removeFriendParticipant: status=removed — already absent")
            return .alreadyAbsent
        default:
            NSLog("[Tally] removeFriendParticipant: status=\(participant.acceptanceStatus.rawValue) — refusing")
            return .refused("Participant acceptance status is \(participant.acceptanceStatus.rawValue); can't confirm revocation.")
        }

        // Sanity: participant still in the array (CKShare.Participant equality
        // is finicky). If it vanished mid-op we didn't revoke → refuse.
        guard share.participants.contains(where: { $0 == participant }) else {
            NSLog("[Tally] removeFriendParticipant: participant vanished from array — refusing")
            return .refused("Participant vanished from the share mid-operation (race).")
        }

        NSLog("[Tally] removeFriendParticipant: removing (role=\(participant.role.rawValue), status=\(participant.acceptanceStatus.rawValue))")
        share.removeParticipant(participant)
        // A throw here is a real CloudKit write failure (network) — distinct
        // from a refusal. It propagates so the caller aborts + the user retries.
        _ = try await client.privateDB.modifyRecords(
            saving: [share],
            deleting: [],
            savePolicy: .ifServerRecordUnchanged,
            atomically: false
        )
        NSLog("[Tally] removeFriendParticipant: revoked friend's access")
        return .revoked
    }

    func leaveFriendShare(ownerRecordName: String) async throws {
        // The friend's personal zone lives in our sharedDB under their
        // ownerName. Find it; if it's already gone (e.g., they unfriended
        // us first), the call is a no-op. Each early-return path logs so
        // partial-state debugging is possible from the console.
        NSLog("[Tally] leaveFriendShare: start owner=\(ownerRecordName)")
        let zones = try await client.sharedDB.allRecordZones()
        guard let zone = zones.first(where: {
            $0.zoneID.zoneName == Self.zoneName
                && $0.zoneID.ownerName == ownerRecordName
        }) else {
            NSLog("[Tally] leaveFriendShare: no shared zone for owner=\(ownerRecordName) (already gone)")
            return
        }

        let rootID = CKRecord.ID(recordName: Self.rootRecordName, zoneID: zone.zoneID)
        let root: CKRecord
        do {
            root = try await client.sharedDB.record(for: rootID)
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            // Zone is being torn down server-side — nothing left to leave.
            NSLog("[Tally] leaveFriendShare: root missing for owner=\(ownerRecordName) — \(error.code)")
            return
        }

        guard let shareRef = root.share else {
            NSLog("[Tally] leaveFriendShare: root has no share for owner=\(ownerRecordName)")
            return
        }
        let fetched: CKRecord
        do {
            fetched = try await client.sharedDB.record(for: shareRef.recordID)
        } catch let error as CKError where error.code == .unknownItem {
            NSLog("[Tally] leaveFriendShare: share record missing — \(error.code)")
            return
        }
        guard let share = fetched as? CKShare else {
            NSLog("[Tally] leaveFriendShare: share record cast failed")
            return
        }

        // Use CKShare.currentUserParticipant — Apple's blessed accessor
        // for "the participant entry representing this device's iCloud
        // user". Replaces our earlier hand-rolled recordName match,
        // which had to special-case the `__defaultOwner__` sentinel and
        // wasn't bulletproof against participant-identity edge cases.
        guard let me = share.currentUserParticipant else {
            NSLog("[Tally] leaveFriendShare: no currentUserParticipant (already left?) participants=\(share.participants.count)")
            return
        }

        // Defensive precondition checks for share.removeParticipant.
        // That method raises NSInternalInconsistencyException — an Obj-C
        // exception Swift `try` can't catch — when its inputs violate any
        // of these invariants. A real crash log from build 12 shows an
        // unhandled obj-c exception thrown by CloudKit on the unfriend
        // path, so each precondition gets its own log + early return.

        // 1. Never call removeParticipant on the share's owner. If we'd
        //    be removing ourselves AS the owner, we're operating on the
        //    wrong share entirely.
        guard me.role != .owner else {
            NSLog("[Tally] leaveFriendShare: refusing to remove self as OWNER of share for \(ownerRecordName)")
            return
        }

        // 2. Acceptance status must be `.accepted`. Removing a
        //    `.pending` / `.removed` / `.unknown` participant is
        //    documented to be undefined and has raised in the field.
        guard me.acceptanceStatus == .accepted else {
            NSLog("[Tally] leaveFriendShare: my acceptanceStatus=\(me.acceptanceStatus.rawValue) — skipping remove")
            return
        }

        // 3. Sanity check: the participant we resolved is actually in
        //    the share's participants array. Should always be true if
        //    currentUserParticipant returned non-nil, but the share
        //    record might be in a transient state — guard anyway.
        guard share.participants.contains(where: { $0 == me }) else {
            NSLog("[Tally] leaveFriendShare: currentUserParticipant not in participants array — race? bailing")
            return
        }

        NSLog("[Tally] leaveFriendShare: about to remove self (role=\(me.role.rawValue), status=\(me.acceptanceStatus.rawValue))")
        // `share.removeParticipant` is the exact call that has raised an
        // uncatchable Obj-C NSException on iOS 26 (see ExceptionCatcher.h).
        // The guards above prevent the states we know about, but the shim is
        // the real safety net: a raised exception becomes a thrown Swift
        // error we can swallow instead of crashing the app. If it throws we
        // bail WITHOUT saving — the participant wasn't removed, so there's
        // nothing to persist.
        do {
            try ExceptionCatcher.catchException {
                share.removeParticipant(me)
            }
        } catch {
            NSLog("[Tally] leaveFriendShare: removeParticipant raised, caught via shim — skipping (owner=\(ownerRecordName)): \(error.localizedDescription)")
            return
        }
        do {
            _ = try await client.sharedDB.modifyRecords(
                saving: [share],
                deleting: [],
                // `.ifServerRecordUnchanged` instead of `.allKeys` so a
                // concurrent change (e.g., owner modifying the share at
                // the same time) returns a regular CKError instead of
                // server-side rejection that could surface oddly.
                savePolicy: .ifServerRecordUnchanged,
                atomically: false
            )
            NSLog("[Tally] leaveFriendShare: removed self from owner=\(ownerRecordName)'s share")
        } catch {
            NSLog("[Tally] leaveFriendShare: modifyRecords failed — \(error.localizedDescription)")
            throw error
        }
    }

    func friendZones() async throws -> [CKRecordZone] {
        let zones = try await client.sharedDB.allRecordZones()
        return zones.filter { $0.zoneID.zoneName == Self.zoneName }
    }

    func friendSnapshot(zoneID: CKRecordZone.ID, since token: CKServerChangeToken?) async throws -> PersonalSnapshot {
        try await snapshot(zoneID: zoneID, in: client.sharedDB, since: token)
    }

    // MARK: Internals

    /// Decode a personal-zone fetch into a `PersonalSnapshot`. Shared by own and
    /// friend zone reads.
    private func snapshot(
        zoneID: CKRecordZone.ID,
        in db: CKDatabase,
        since token: CKServerChangeToken?
    ) async throws -> PersonalSnapshot {
        let changes = try await client.fetchZoneChanges(zoneID: zoneID, in: db, since: token)
        var snap = PersonalSnapshot(token: changes.token, isIncremental: token != nil)
        for record in changes.changedRecords {
            switch record.recordType {
            case PersonalRoot.recordType:
                snap.root = PersonalRoot(record: record)
            case Habit.recordType:
                if let h = Habit(record: record) { snap.habits.append(h) }
            case HabitCompletion.recordType:
                if let c = HabitCompletion(record: record) { snap.completions.append(c) }
            case Goal.recordType:
                if let g = Goal(record: record) { snap.goals.append(g) }
            default:
                break
            }
        }
        snap.deletedRecordNames = changes.deletedRecordIDs.map { $0.recordName }
        return snap
    }

    /// Resolve a user record ID into a `CKShare.Participant` we can add to a share.
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

    func updatePersonalRootProfile(
        displayName: String,
        avatarSymbol: String,
        avatarImageData: Data?,
        clearAvatarPhoto: Bool
    ) async throws {
        let record = try await client.privateDB.record(for: rootRecordID)
        record["displayName"] = displayName
        record["avatarSymbol"] = avatarSymbol
        // Three-way merge for the photo, same semantics as ProfileRepository
        // — keep stored value when caller just wants to update name only.
        if clearAvatarPhoto {
            record["avatarImageData"] = nil as Data?
        } else if let avatarImageData {
            record["avatarImageData"] = avatarImageData
        }
        _ = try await client.privateDB.save(record)
    }

    private func createRoot(at rootID: CKRecord.ID) async throws {
        let root = PersonalRoot(displayName: "", avatarSymbol: "leaf", avatarImageData: nil, createdAt: .now)
        let record = root.toRecord(recordID: rootID)
        _ = try await client.privateDB.save(record)
    }
}

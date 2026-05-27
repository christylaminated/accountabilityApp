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
    func removeFriendParticipant(userRecordID: CKRecord.ID) async throws

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

    func removeFriendParticipant(userRecordID: CKRecord.ID) async throws {
        let root = try await client.privateDB.record(for: rootRecordID)
        guard let shareRef = root.share else { return }
        let fetched = try await client.privateDB.record(for: shareRef.recordID)
        guard let share = fetched as? CKShare else { return }

        // Compare by recordName rather than full CKRecord.ID — userRecordIDs
        // always live in `_defaultZone` but the equality check is finicky.
        guard let participant = share.participants.first(where: {
            $0.userIdentity.userRecordID?.recordName == userRecordID.recordName
        }) else { return }

        share.removeParticipant(participant)
        _ = try await client.privateDB.modifyRecords(
            saving: [share],
            deleting: [],
            savePolicy: .allKeys,
            atomically: false
        )
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

        // Find my own participant entry. CloudKit substitutes the sentinel
        // `__defaultOwner__` for the CURRENT user's userRecordID.recordName
        // when reading a participant list (same quirk we hit in the
        // UsernameRepository creator-ID code). Match against either the
        // sentinel OR my real record name.
        let myRecordName = try await client.userRecordID().recordName
        let participantNames = share.participants.compactMap {
            $0.userIdentity.userRecordID?.recordName
        }
        NSLog("[Tally] leaveFriendShare: my=\(myRecordName) participants=\(participantNames)")

        guard let me = share.participants.first(where: { p in
            let name = p.userIdentity.userRecordID?.recordName
            return name == myRecordName || name == CKCurrentUserDefaultName
        }) else {
            NSLog("[Tally] leaveFriendShare: couldn't find self in participants — already left?")
            return
        }

        // Defensive: never try to "leave" a share I own. removeParticipant
        // on the owner participant raises an NSException — that would
        // crash with no Swift `catch` recourse. If we ever end up here on
        // a share whose owner is us, it's a state we don't understand;
        // bail loudly instead of swinging at it.
        guard me.role != .owner else {
            NSLog("[Tally] leaveFriendShare: refusing to remove self as OWNER of share for \(ownerRecordName)")
            return
        }

        share.removeParticipant(me)
        do {
            _ = try await client.sharedDB.modifyRecords(
                saving: [share],
                deleting: [],
                savePolicy: .allKeys,
                atomically: false
            )
            NSLog("[Tally] leaveFriendShare: removed self from owner=\(ownerRecordName)'s share")
        } catch {
            // Most likely a server-record-changed conflict from stale
            // share state — surface it but don't crash, the caller can
            // decide whether to retry.
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

import CloudKit
import Foundation

/// Backed by CloudKit's public database. Records are written by the sender
/// and queried by the recipient via a Queryable index on `toUserRecordName`.
///
/// IMPORTANT — schema setup (one-time after the type is created in dev):
///   - In CloudKit Dashboard → Development → Schema → Record Types →
///     `FriendRequest`, mark `toUserRecordName` as **Queryable** (and
///     **Sortable** if you want predictable inbox ordering).
///     The default schema CloudKit auto-creates does NOT make custom
///     fields queryable, so the `incoming(for:)` fetch will return
///     "field is not marked queryable" until you toggle this.
///   - Then deploy dev → prod so the index ships.
protocol FriendRequestRepository: Sendable {
    /// Write a new FriendRequest to the public DB. The sender becomes the
    /// CloudKit creator of the record, which is what allows them to delete
    /// it later (recipients can't modify records they didn't create).
    func send(_ request: FriendRequest) async throws

    /// All requests addressed to `userRecordName` (both fresh and reciprocal).
    /// The caller filters by `isReciprocal` and by "already a friend" itself.
    func incoming(for userRecordName: String) async throws -> [FriendRequest]

    /// All requests this user created. Used for outgoing-cleanup: when the
    /// target appears in the user's friends list, the request is no longer
    /// pending and should be removed.
    func outgoing(for userRecordName: String) async throws -> [FriendRequest]

    /// Delete a request. Only succeeds when called by the request's creator —
    /// public-DB security rules block non-creator writes by default.
    func delete(_ request: FriendRequest) async throws
}

struct CloudKitFriendRequestRepository: FriendRequestRepository {
    let client: CKClient

    init(client: CKClient = .shared) {
        self.client = client
    }

    private var publicDB: CKDatabase { client.container.publicCloudDatabase }

    func send(_ request: FriendRequest) async throws {
        let recordID = CKRecord.ID(recordName: request.id.uuidString)
        let record = request.toRecord(recordID: recordID)
        _ = try await publicDB.save(record)
    }

    func incoming(for userRecordName: String) async throws -> [FriendRequest] {
        let predicate = NSPredicate(format: "toUserRecordName == %@", userRecordName)
        return try await query(predicate: predicate)
    }

    func outgoing(for userRecordName: String) async throws -> [FriendRequest] {
        let predicate = NSPredicate(format: "fromUserRecordName == %@", userRecordName)
        return try await query(predicate: predicate)
    }

    func delete(_ request: FriendRequest) async throws {
        let recordID = CKRecord.ID(recordName: request.id.uuidString)
        _ = try await publicDB.deleteRecord(withID: recordID)
    }

    private func query(predicate: NSPredicate) async throws -> [FriendRequest] {
        let query = CKQuery(recordType: FriendRequest.recordType, predicate: predicate)
        // Newest first so the inbox feels live; the field is queryable +
        // sortable by definition once the dashboard index is set up.
        query.sortDescriptors = [NSSortDescriptor(key: "sentAt", ascending: false)]
        let (matchResults, _) = try await publicDB.records(matching: query)
        return matchResults.compactMap { _, result -> FriendRequest? in
            guard case .success(let record) = result else { return nil }
            return FriendRequest(record: record)
        }
    }
}

// MARK: - Group invite repository

/// Backed by CloudKit's public database. Records are written by the owner
/// adding a friend to a Circle, and queried by the recipient via a Queryable
/// index on `toUserRecordName`. Same mechanism + same caveats as
/// `FriendRequestRepository` — they're identical inboxes, different record
/// types.
///
/// IMPORTANT — schema setup (one-time in CloudKit Dashboard):
///   - Development → Schema → Record Types → create `GroupInvite` with the
///     fields from `GroupInvite.populate(_:)` (id, fromUserRecordName,
///     toUserRecordName, circleID, circleName, circleKind, dmPeerID,
///     shareURL, fromDisplayName, fromUsername, fromAvatarSymbol, sentAt).
///   - Mark `toUserRecordName` as **Queryable** and `sentAt` as **Sortable**.
///   - Then **Deploy Schema to Production** so TestFlight builds can read it.
///     The orange "Friend-request sync error" banner pattern (reused for
///     group invites below) will surface the exact error if you forget.
protocol GroupInviteRepository: Sendable {
    /// Write a new GroupInvite to the public DB.
    func send(_ invite: GroupInvite) async throws

    /// Invites addressed to `userRecordName`.
    func incoming(for userRecordName: String) async throws -> [GroupInvite]

    /// Invites this user created. Used for owner-side cleanup: when the
    /// invitee shows up as a Circle member the invite has served its purpose
    /// and gets removed.
    func outgoing(for userRecordName: String) async throws -> [GroupInvite]

    /// Delete an invite. Only the creator (the inviting owner) can call this.
    func delete(_ invite: GroupInvite) async throws
}

struct CloudKitGroupInviteRepository: GroupInviteRepository {
    let client: CKClient

    init(client: CKClient = .shared) {
        self.client = client
    }

    private var publicDB: CKDatabase { client.container.publicCloudDatabase }

    func send(_ invite: GroupInvite) async throws {
        let recordID = CKRecord.ID(recordName: invite.id.uuidString)
        let record = invite.toRecord(recordID: recordID)
        _ = try await publicDB.save(record)
    }

    func incoming(for userRecordName: String) async throws -> [GroupInvite] {
        let predicate = NSPredicate(format: "toUserRecordName == %@", userRecordName)
        return try await query(predicate: predicate)
    }

    func outgoing(for userRecordName: String) async throws -> [GroupInvite] {
        let predicate = NSPredicate(format: "fromUserRecordName == %@", userRecordName)
        return try await query(predicate: predicate)
    }

    func delete(_ invite: GroupInvite) async throws {
        let recordID = CKRecord.ID(recordName: invite.id.uuidString)
        _ = try await publicDB.deleteRecord(withID: recordID)
    }

    private func query(predicate: NSPredicate) async throws -> [GroupInvite] {
        let query = CKQuery(recordType: GroupInvite.recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "sentAt", ascending: false)]
        let (matchResults, _) = try await publicDB.records(matching: query)
        return matchResults.compactMap { _, result -> GroupInvite? in
            guard case .success(let record) = result else { return nil }
            return GroupInvite(record: record)
        }
    }
}

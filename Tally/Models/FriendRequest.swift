import CloudKit
import Foundation

/// An in-app friend request that lives in CloudKit's *public* database.
///
/// Why this exists: the older flow added the recipient as a `.readOnly`
/// participant on the sender's personal CKShare and relied on iOS to deliver
/// an iCloud system notification — but in practice that notification often
/// doesn't fire (varies by iOS version, account state, and TestFlight builds),
/// leaving the recipient with no way to know they were invited. The
/// public-DB record gives the recipient a reliable, in-app surface to see
/// pending requests and accept them programmatically via the share URL.
///
/// Reciprocity: when B accepts A's request, B's app writes a *new*
/// FriendRequest from B → A with `isReciprocal == true`. A's app picks
/// it up on next refresh, auto-accepts B's share silently (no UI prompt),
/// and the bidirectional friend graph is wired up.
///
/// Lifecycle: requests are deleted by their creator. The recipient can't
/// modify another user's public record, so cleanup happens when the sender's
/// app sees the recipient appear in their friends list and removes its own
/// outgoing request. Declined requests get hidden locally via UserDefaults.
struct FriendRequest: Identifiable, Hashable {
    let id: UUID
    var fromUserRecordName: String
    var toUserRecordName: String
    var shareURL: String
    var fromDisplayName: String
    var fromUsername: String
    var fromAvatarSymbol: String
    var sentAt: Date
    /// True when this request was created by a recipient accepting an earlier
    /// request — the original sender's app auto-accepts these silently without
    /// showing them in the inbox.
    var isReciprocal: Bool
}

extension FriendRequest: CKRecordConvertible {
    static let recordType = "FriendRequest"

    init?(record: CKRecord) {
        guard
            let idString = record["id"] as? String,
            let id = UUID(uuidString: idString),
            let fromUserRecordName = record["fromUserRecordName"] as? String,
            let toUserRecordName = record["toUserRecordName"] as? String,
            let shareURL = record["shareURL"] as? String,
            let fromDisplayName = record["fromDisplayName"] as? String,
            let fromUsername = record["fromUsername"] as? String,
            let fromAvatarSymbol = record["fromAvatarSymbol"] as? String,
            let sentAt = record["sentAt"] as? Date
        else { return nil }
        self.id = id
        self.fromUserRecordName = fromUserRecordName
        self.toUserRecordName = toUserRecordName
        self.shareURL = shareURL
        self.fromDisplayName = fromDisplayName
        self.fromUsername = fromUsername
        self.fromAvatarSymbol = fromAvatarSymbol
        self.sentAt = sentAt
        // CKRecord doesn't have a native Bool — store as Int 0/1.
        self.isReciprocal = (record["isReciprocal"] as? Int ?? 0) != 0
    }

    func populate(_ record: CKRecord) {
        record["id"] = id.uuidString
        record["fromUserRecordName"] = fromUserRecordName
        record["toUserRecordName"] = toUserRecordName
        record["shareURL"] = shareURL
        record["fromDisplayName"] = fromDisplayName
        record["fromUsername"] = fromUsername
        record["fromAvatarSymbol"] = fromAvatarSymbol
        record["sentAt"] = sentAt
        record["isReciprocal"] = isReciprocal ? 1 : 0
    }
}

// MARK: - Group invites

/// An in-app invitation to join a Group (or DM) — public-DB equivalent of
/// `FriendRequest`, for the same reason: relying on iOS to deliver a CKShare
/// invite notification proved unreliable on TestFlight, so we mirror the
/// invitation in the public database and let the recipient's app poll for it.
///
/// Recipient flow on Accept:
///   1. Fetch share metadata for `shareURL`.
///   2. CKAcceptSharesOperation → the Circle's zone appears in their sharedDB.
///   3. recordOwnMembership(circleID:) writes their CircleMember row.
///   4. The invite stays in the public DB until the owner's cleanup pass
///      removes it (recipients can't delete records they didn't create).
///
/// Decline: hidden locally (declinedGroupInviteIDs), since the recipient
/// can't delete the underlying record — same constraint as FriendRequest.
struct GroupInvite: Identifiable, Hashable {
    let id: UUID
    var fromUserRecordName: String
    var toUserRecordName: String
    var circleID: UUID
    var circleName: String
    var circleKind: CircleKind
    var dmPeerID: String?
    var shareURL: String
    var fromDisplayName: String
    var fromUsername: String
    var fromAvatarSymbol: String
    var sentAt: Date
}

extension GroupInvite: CKRecordConvertible {
    static let recordType = "GroupInvite"

    init?(record: CKRecord) {
        guard
            let idString = record["id"] as? String,
            let id = UUID(uuidString: idString),
            let fromUserRecordName = record["fromUserRecordName"] as? String,
            let toUserRecordName = record["toUserRecordName"] as? String,
            let circleIDString = record["circleID"] as? String,
            let circleID = UUID(uuidString: circleIDString),
            let circleName = record["circleName"] as? String,
            let shareURL = record["shareURL"] as? String,
            let fromDisplayName = record["fromDisplayName"] as? String,
            let fromUsername = record["fromUsername"] as? String,
            let fromAvatarSymbol = record["fromAvatarSymbol"] as? String,
            let sentAt = record["sentAt"] as? Date
        else { return nil }
        self.id = id
        self.fromUserRecordName = fromUserRecordName
        self.toUserRecordName = toUserRecordName
        self.circleID = circleID
        self.circleName = circleName
        self.circleKind = (record["circleKind"] as? String)
            .flatMap(CircleKind.init(rawValue:)) ?? .group
        self.dmPeerID = record["dmPeerID"] as? String
        self.shareURL = shareURL
        self.fromDisplayName = fromDisplayName
        self.fromUsername = fromUsername
        self.fromAvatarSymbol = fromAvatarSymbol
        self.sentAt = sentAt
    }

    func populate(_ record: CKRecord) {
        record["id"] = id.uuidString
        record["fromUserRecordName"] = fromUserRecordName
        record["toUserRecordName"] = toUserRecordName
        record["circleID"] = circleID.uuidString
        record["circleName"] = circleName
        record["circleKind"] = circleKind.rawValue
        record["dmPeerID"] = dmPeerID
        record["shareURL"] = shareURL
        record["fromDisplayName"] = fromDisplayName
        record["fromUsername"] = fromUsername
        record["fromAvatarSymbol"] = fromAvatarSymbol
        record["sentAt"] = sentAt
    }
}

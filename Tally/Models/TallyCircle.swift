import CloudKit
import Foundation

/// Named `TallyCircle` to avoid colliding with SwiftUI.Circle. Maps to the
/// `Circle` record type in CloudKit — the root record of each Circle's shared zone.
///
/// `id` is a UUID we control locally (also encodes the zone name).
/// `ownerID` holds the owner's `CKRecord.ID.recordName` (a String, not a UUID).
///
/// `kind` separates multi-person Groups from 1:1 private DMs. The chat plumbing
/// (members, CKShare, CircleMessage feed) is identical for both — the distinction
/// is only how the Circle is rendered and how it's looked up when the user taps
/// "Message" on a friend's profile.
struct TallyCircle: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var emoji: String?
    var ownerID: String
    var createdAt: Date
    var kind: CircleKind = .group
    /// For `.dm` Circles only: the user record name of the non-owner participant.
    /// Combined with `ownerID`, this gives us both sides of the conversation
    /// without having to fetch the members list. Nil for `.group` Circles.
    var dmPeerID: String?
}

enum CircleKind: String, Codable, Hashable {
    case group
    case dm
}

extension TallyCircle {
    /// The "other person" in a DM from `viewerID`'s perspective. Returns nil for
    /// Group Circles, or for DMs where the viewer isn't a participant.
    func dmPeer(forViewer viewerID: String) -> String? {
        guard kind == .dm else { return nil }
        if ownerID == viewerID { return dmPeerID }
        if dmPeerID == viewerID { return ownerID }
        return nil
    }
}

extension TallyCircle: CKRecordConvertible {
    static let recordType = "Circle"

    init?(record: CKRecord) {
        guard
            let idString = record["id"] as? String,
            let id = UUID(uuidString: idString),
            let name = record["name"] as? String,
            let ownerID = record["ownerID"] as? String,
            let createdAt = record["createdAt"] as? Date
        else { return nil }
        self.id = id
        self.name = name
        self.emoji = record["emoji"] as? String
        self.ownerID = ownerID
        self.createdAt = createdAt
        // Legacy records written before the kind field default to .group.
        // Reading a missing or unrecognized value as .group keeps every
        // existing Circle working without a schema migration.
        if let raw = record["kind"] as? String, let parsed = CircleKind(rawValue: raw) {
            self.kind = parsed
        } else {
            self.kind = .group
        }
        self.dmPeerID = record["dmPeerID"] as? String
    }

    func populate(_ record: CKRecord) {
        record["id"] = id.uuidString
        record["name"] = name
        // NOTE: `emoji` is NOT in the production CloudKit schema. This write
        // is safe ONLY while `emoji` is nil (a nil subscript writes no key,
        // so CloudKit never validates it). Add the `emoji` field to the
        // `Circle` record type in production before shipping any circle-emoji
        // UI, or this save will be rejected with "Cannot create or modify
        // field 'emoji'".
        record["emoji"] = emoji
        record["ownerID"] = ownerID
        record["createdAt"] = createdAt
        record["kind"] = kind.rawValue
        record["dmPeerID"] = dmPeerID
    }
}

import CloudKit
import Foundation

/// Central entry point for CloudKit. Wraps `CKContainer.default()` and exposes
/// helpers for identity, account status, and zone management.
///
/// Every repository depends on this. We use an actor so the cached user record ID
/// is shielded from race conditions; stateless operations are `nonisolated`
/// to avoid forcing callers through actor hops.
actor CKClient {
    /// Shared instance. Repositories grab this rather than constructing their own
    /// so the cached identity stays a single source of truth.
    static let shared = CKClient()

    let container: CKContainer

    /// Zones whose name starts with this prefix represent Circles. The Circle's
    /// CKShare attaches to the root record in its own zone, so child records
    /// (members, messages, summaries) automatically follow the share to participants.
    static let circleZonePrefix = "circle-"

    nonisolated var privateDB: CKDatabase { container.privateCloudDatabase }
    nonisolated var sharedDB:  CKDatabase { container.sharedCloudDatabase }

    private var cachedUserRecordID: CKRecord.ID?

    init(container: CKContainer = .default()) {
        self.container = container
    }

    // MARK: - Identity

    /// The current user's iCloud record ID. Cached after first fetch.
    func userRecordID() async throws -> CKRecord.ID {
        if let cached = cachedUserRecordID { return cached }
        let id = try await container.userRecordID()
        cachedUserRecordID = id
        return id
    }

    /// Clear the cached identity. Call when iCloud account changes (signed out,
    /// switched accounts). Subsequent reads will refetch.
    func invalidateIdentityCache() {
        cachedUserRecordID = nil
    }

    /// Current iCloud account status. Not cached — we read on demand so sign-out /
    /// sign-in transitions are observed without stale state.
    nonisolated func accountStatus() async throws -> CKAccountStatus {
        try await container.accountStatus()
    }

    // MARK: - Zone helpers

    /// Stable zone name for a given Circle UUID. Lowercased for case-safety.
    nonisolated static func circleZoneName(circleID: UUID) -> String {
        "\(circleZonePrefix)\(circleID.uuidString.lowercased())"
    }

    /// Extract a Circle UUID from a zone name, or nil if not a Circle zone.
    nonisolated static func circleID(fromZoneName name: String) -> UUID? {
        guard name.hasPrefix(circleZonePrefix) else { return nil }
        return UUID(uuidString: String(name.dropFirst(circleZonePrefix.count)))
    }

    /// Create a new custom zone in the user's private DB. Called when this user
    /// creates a Circle; the Circle root record and all child records live here.
    nonisolated func createPrivateZone(named name: String) async throws -> CKRecordZone {
        let zone = CKRecordZone(zoneName: name)
        let result = try await privateDB.modifyRecordZones(saving: [zone], deleting: [])
        guard let saveResult = result.saveResults[zone.zoneID] else {
            throw CKClientError.zoneCreationFailed(name: name)
        }
        return try saveResult.get()
    }

    /// Delete a custom zone *and every record inside it* from the owner's private DB.
    /// CloudKit cascades the deletion server-side — the Circle root, its CKShare,
    /// CircleMembers, messages, summaries are all removed in this single op.
    /// Participants see the zone disappear from their shared DB on their next sync.
    nonisolated func deletePrivateZone(named name: String) async throws {
        let zoneID = CKRecordZone.ID(zoneName: name, ownerName: CKCurrentUserDefaultName)
        _ = try await privateDB.modifyRecordZones(saving: [], deleting: [zoneID])
    }

    /// Circles this user owns (their zones in the private DB).
    nonisolated func ownedCircleZones() async throws -> [CKRecordZone] {
        let all = try await privateDB.allRecordZones()
        return all.filter { Self.circleID(fromZoneName: $0.zoneID.zoneName) != nil }
    }

    /// Circles this user has joined (others' zones in the shared DB).
    nonisolated func joinedCircleZones() async throws -> [CKRecordZone] {
        let all = try await sharedDB.allRecordZones()
        return all.filter { Self.circleID(fromZoneName: $0.zoneID.zoneName) != nil }
    }

    /// Every Circle zone the user can see, tagged with which database it's in.
    /// Used by `CircleRepository.listAll()` to enumerate Circles across owned + joined.
    nonisolated func allCircleZones() async throws -> [(zone: CKRecordZone, scope: CKDatabase.Scope)] {
        async let owned = ownedCircleZones()
        async let joined = joinedCircleZones()
        let ownedTagged  = try await owned.map  { ($0, CKDatabase.Scope.private) }
        let joinedTagged = try await joined.map { ($0, CKDatabase.Scope.shared)  }
        return ownedTagged + joinedTagged
    }

    // MARK: - Zone changes

    /// The delta returned by `fetchZoneChanges`. On a first (nil-token) fetch this
    /// is the full contents of the zone; on later fetches, only what changed.
    struct ZoneChanges {
        var changedRecords: [CKRecord] = []
        var deletedRecordIDs: [CKRecord.ID] = []
        var token: CKServerChangeToken?
    }

    /// Fetch all records in a zone (token == nil) or just what changed since a
    /// prior token. This is query-free — no CloudKit Dashboard indexes required —
    /// which is why every Circle record type loads without schema setup.
    /// Pages internally until CloudKit reports no more changes.
    nonisolated func fetchZoneChanges(
        zoneID: CKRecordZone.ID,
        in db: CKDatabase,
        since startToken: CKServerChangeToken?
    ) async throws -> ZoneChanges {
        var result = ZoneChanges(token: startToken)
        var moreComing = true
        while moreComing {
            let page = try await fetchZoneChangesPage(zoneID: zoneID, in: db, since: result.token)
            result.changedRecords += page.changedRecords
            result.deletedRecordIDs += page.deletedRecordIDs
            result.token = page.token
            moreComing = page.moreComing
        }
        return result
    }

    private nonisolated func fetchZoneChangesPage(
        zoneID: CKRecordZone.ID,
        in db: CKDatabase,
        since startToken: CKServerChangeToken?
    ) async throws -> (changedRecords: [CKRecord], deletedRecordIDs: [CKRecord.ID], token: CKServerChangeToken?, moreComing: Bool) {
        try await withCheckedThrowingContinuation { continuation in
            var changed: [CKRecord] = []
            var deleted: [CKRecord.ID] = []
            var token: CKServerChangeToken? = startToken
            var moreComing = false

            let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            config.previousServerChangeToken = startToken
            let op = CKFetchRecordZoneChangesOperation(
                recordZoneIDs: [zoneID],
                configurationsByRecordZoneID: [zoneID: config]
            )
            op.recordWasChangedBlock = { _, recordResult in
                if case .success(let record) = recordResult { changed.append(record) }
            }
            op.recordWithIDWasDeletedBlock = { recordID, _ in
                deleted.append(recordID)
            }
            op.recordZoneFetchResultBlock = { _, zoneResult in
                if case .success(let success) = zoneResult {
                    token = success.serverChangeToken
                    moreComing = success.moreComing
                }
            }
            op.fetchRecordZoneChangesResultBlock = { overall in
                switch overall {
                case .success:
                    continuation.resume(returning: (changed, deleted, token, moreComing))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            db.add(op)
        }
    }

    // MARK: - Subscriptions

    /// Register a silent-push subscription for a zone so CloudKit notifies this
    /// device whenever a friend changes anything in the Circle. Idempotent —
    /// re-saving an existing subscription just updates it.
    nonisolated func ensureZoneSubscription(zoneID: CKRecordZone.ID, in db: CKDatabase) async throws {
        let subscription = CKRecordZoneSubscription(
            zoneID: zoneID,
            subscriptionID: "tally-zone-\(zoneID.zoneName)"
        )
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true // silent push — no alert, no permission prompt
        subscription.notificationInfo = info
        _ = try await db.modifySubscriptions(saving: [subscription], deleting: [])
    }
}

enum CKClientError: LocalizedError {
    case zoneCreationFailed(name: String)
    case notSignedIn
    case unexpected(String)

    var errorDescription: String? {
        switch self {
        case .zoneCreationFailed(let n): return "Couldn't create the Circle's iCloud zone (\(n))."
        case .notSignedIn:               return "iCloud account isn't available."
        case .unexpected(let msg):       return msg
        }
    }
}

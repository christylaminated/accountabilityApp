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

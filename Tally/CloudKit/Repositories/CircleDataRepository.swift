import CloudKit
import Foundation

/// Decoded contents of a Circle's CloudKit zone — every record type that lives
/// alongside the Circle root record (members, habits, completions, goals,
/// messages). Returned by `CircleDataRepository`.
///
/// On a full load `isIncremental` is false and the arrays are the whole zone.
/// On a token-based fetch they hold only what changed, and `deletedRecordNames`
/// lists what was removed — the caller merges these into its cached state.
struct CircleSnapshot {
    var circle: TallyCircle?
    var members: [CircleMember] = []
    var habits: [Habit] = []
    var completions: [HabitCompletion] = []
    var goals: [Goal] = []
    var circleMessages: [CircleMessage] = []
    var directMessages: [DirectMessage] = []

    /// Record names removed since the last fetch. Empty on a full load.
    var deletedRecordNames: [String] = []
    /// Server change token to feed into the next incremental fetch.
    var token: CKServerChangeToken?
    /// True when this snapshot is a delta (token-based) rather than a full load.
    var isIncremental = false
}

/// Reads and writes the per-Circle data that lives inside the Circle's shared
/// CloudKit zone. Because every member's habits, check-ins, goals, and messages
/// live in this one zone, every participant sees them — that's what makes the
/// accountability loop work across friends.
protocol CircleDataRepository: Sendable {
    /// Fetch the zone. `token == nil` loads everything; otherwise returns the
    /// delta since that token.
    func snapshot(for circle: TallyCircle, since token: CKServerChangeToken?) async throws -> CircleSnapshot

    /// Upsert records into the Circle's zone, parented to the root so they ride
    /// the CKShare and stay visible to every participant.
    func save(_ records: [any ZoneRecord], in circle: TallyCircle) async throws

    /// Delete records by name from the Circle's zone.
    func delete(recordNames: [String], in circle: TallyCircle) async throws

    /// Register for silent CloudKit pushes when the Circle's zone changes, so a
    /// friend's check-ins and messages arrive without reopening the app.
    func subscribeToChanges(for circle: TallyCircle) async throws
}

// MARK: - CloudKit implementation

struct CloudKitCircleDataRepository: CircleDataRepository {
    let client: CKClient

    /// Fixed recordName of the Circle root record inside each zone.
    static let rootRecordName = "circleRoot"

    init(client: CKClient = .shared) {
        self.client = client
    }

    func snapshot(for circle: TallyCircle, since token: CKServerChangeToken?) async throws -> CircleSnapshot {
        let (db, zoneID) = try await locate(circle)
        let changes = try await client.fetchZoneChanges(zoneID: zoneID, in: db, since: token)

        var snap = CircleSnapshot(token: changes.token, isIncremental: token != nil)
        for record in changes.changedRecords {
            switch record.recordType {
            case TallyCircle.recordType:
                snap.circle = TallyCircle(record: record)
            case CircleMember.recordType:
                if let m = CircleMember(record: record) { snap.members.append(m) }
            case Habit.recordType:
                if let h = Habit(record: record) { snap.habits.append(h) }
            case HabitCompletion.recordType:
                if let c = HabitCompletion(record: record) { snap.completions.append(c) }
            case Goal.recordType:
                if let g = Goal(record: record) { snap.goals.append(g) }
            case CircleMessage.recordType:
                if let m = CircleMessage(record: record) { snap.circleMessages.append(m) }
            case DirectMessage.recordType:
                if let m = DirectMessage(record: record) { snap.directMessages.append(m) }
            default:
                break // cloudkit.share and any unknown types
            }
        }
        snap.deletedRecordNames = changes.deletedRecordIDs.map { $0.recordName }
        return snap
    }

    func save(_ records: [any ZoneRecord], in circle: TallyCircle) async throws {
        guard !records.isEmpty else { return }
        let (db, zoneID) = try await locate(circle)
        let rootID = CKRecord.ID(recordName: Self.rootRecordName, zoneID: zoneID)
        let parent = CKRecord.Reference(recordID: rootID, action: .none)

        let ckRecords = records.map { record -> CKRecord in
            let id = CKRecord.ID(recordName: record.recordName, zoneID: zoneID)
            return record.toRecord(recordID: id, parent: parent)
        }
        // .allKeys upserts: freshly built records overwrite the server copy
        // without a change-tag conflict. Acceptable here — each record is only
        // ever written by the one member it belongs to.
        _ = try await db.modifyRecords(
            saving: ckRecords,
            deleting: [],
            savePolicy: .allKeys,
            atomically: false
        )
    }

    func delete(recordNames: [String], in circle: TallyCircle) async throws {
        guard !recordNames.isEmpty else { return }
        let (db, zoneID) = try await locate(circle)
        let ids = recordNames.map { CKRecord.ID(recordName: $0, zoneID: zoneID) }
        _ = try await db.modifyRecords(
            saving: [],
            deleting: ids,
            savePolicy: .allKeys,
            atomically: false
        )
    }

    func subscribeToChanges(for circle: TallyCircle) async throws {
        let (db, zoneID) = try await locate(circle)
        try await client.ensureZoneSubscription(zoneID: zoneID, in: db)
    }

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
}

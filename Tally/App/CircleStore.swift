import CloudKit
import Foundation
import Observation

/// The observable store for an active Circle's *chat-room* concerns —
/// members and messages. Habits, completions, and goals moved out to
/// `PersonalStore` in 3d (they're per-user, not per-Circle).
///
/// Reads are synchronous against in-memory arrays so SwiftUI views stay simple.
/// Writes (messages) are optimistic: local arrays update immediately, and the
/// change is pushed to CloudKit in the background. `refresh()` reconciles with
/// the server so friends' changes appear.
@MainActor
@Observable
final class CircleStore {
    private let dataRepo: any CircleDataRepository

    /// The Circle this store is scoped to. Set via `activate`.
    private(set) var circle: TallyCircle?

    var members: [CircleMember] = []
    var circleMessages: [CircleMessage] = []
    var directMessages: [DirectMessage] = []

    var isLoading = false
    var lastError: String?

    /// Signed-in user's CloudKit record name. Set by `AppState` on activation.
    var currentUserID: String = ""

    /// Server change token for incremental fetches. Reset when the Circle changes.
    private var token: CKServerChangeToken?

    init(dataRepo: any CircleDataRepository = CloudKitCircleDataRepository()) {
        self.dataRepo = dataRepo
    }

    // MARK: - Lifecycle

    /// Point the store at a Circle and load its contents. Clears cached state
    /// when switching to a different Circle.
    func activate(_ circle: TallyCircle, currentUserID: String) async {
        self.currentUserID = currentUserID
        if self.circle?.id != circle.id {
            self.circle = circle
            token = nil
            members = []; circleMessages = []; directMessages = []
        } else {
            self.circle = circle
        }
        await load()
        // Best-effort: register for live CloudKit pushes on this Circle's zone.
        try? await dataRepo.subscribeToChanges(for: circle)
    }

    /// Full load — replaces all cached state.
    func load() async {
        guard let circle else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let snap = try await dataRepo.snapshot(for: circle, since: nil)
            token = snap.token
            members = snap.members
            circleMessages = snap.circleMessages
            directMessages = snap.directMessages
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Incremental refresh — merges the server delta into cached state. Falls back
    /// to a full load if the change token has expired. Called on foreground and
    /// when a CloudKit push arrives.
    func refresh() async {
        guard let circle else { return }
        guard token != nil else { await load(); return }
        do {
            let snap = try await dataRepo.snapshot(for: circle, since: token)
            apply(snap)
        } catch let error as CKError where error.code == .changeTokenExpired {
            token = nil
            await load()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func apply(_ snap: CircleSnapshot) {
        token = snap.token
        let deleted = Set(snap.deletedRecordNames)
        if let c = snap.circle { circle = c }
        Self.merge(snap.members, deleted: deleted, into: &members)
        Self.merge(snap.circleMessages, deleted: deleted, into: &circleMessages)
        Self.merge(snap.directMessages, deleted: deleted, into: &directMessages)
    }

    /// Upsert changed records by `recordName`, then drop anything deleted.
    private static func merge<T: ZoneRecord>(
        _ changes: [T], deleted: Set<String>, into array: inout [T]
    ) {
        for item in changes {
            if let i = array.firstIndex(where: { $0.recordName == item.recordName }) {
                array[i] = item
            } else {
                array.append(item)
            }
        }
        if !deleted.isEmpty {
            array.removeAll { deleted.contains($0.recordName) }
        }
    }

    // MARK: - Members

    func member(id userID: String) -> CircleMember? {
        members.first { $0.userID == userID }
    }

    /// Members other than the signed-in user, in join order.
    var otherMembers: [CircleMember] {
        members
            .filter { $0.userID != currentUserID }
            .sorted { $0.joinedAt < $1.joinedAt }
    }

    /// Members with the signed-in user first, then others by join order.
    var orderedMembers: [CircleMember] {
        let me = members.filter { $0.userID == currentUserID }
        return me + otherMembers
    }

    // MARK: - Messages

    /// Circle feed, oldest first.
    var feed: [CircleMessage] {
        circleMessages.sorted { $0.createdAt < $1.createdAt }
    }

    func sendCircleMessage(body: String, senderID: String) {
        guard let circle else { return }
        let msg = CircleMessage(
            id: UUID(),
            circleID: circle.id,
            senderID: senderID,
            body: body,
            createdAt: .now
        )
        circleMessages.append(msg)
        persistSave([msg])
    }

    /// Direct-message thread between two users, oldest first.
    func dmThread(between userA: String, and userB: String) -> [DirectMessage] {
        directMessages
            .filter {
                ($0.senderID == userA && $0.recipientID == userB) ||
                ($0.senderID == userB && $0.recipientID == userA)
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func sendDM(body: String, senderID: String, recipientID: String) {
        guard let circle else { return }
        let msg = DirectMessage(
            id: UUID(),
            circleID: circle.id,
            senderID: senderID,
            recipientID: recipientID,
            body: body,
            createdAt: .now
        )
        directMessages.append(msg)
        persistSave([msg])
    }

    /// Count of messages the viewer has received from another member. Mock-era
    /// approximation — real per-message read state is a later addition.
    func unreadDMCount(for viewer: String, fromUser other: String) -> Int {
        directMessages.filter {
            $0.recipientID == viewer && $0.senderID == other
        }.count
    }

    // MARK: - Write-through

    private func persistSave(_ records: [any ZoneRecord]) {
        guard let circle else { return }
        Task {
            do {
                try await dataRepo.save(records, in: circle)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }
}

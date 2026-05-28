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

    /// Record names of writes currently in flight (and ones that have failed,
    /// pending retry). load() preserves these across a server fetch so a quick
    /// re-navigation doesn't wipe an optimistic send before its CloudKit
    /// write completes. Entries are removed only when the save succeeds —
    /// failures stay in the set so the message remains visible and the user
    /// can see something's wrong via `lastError`.
    private var pendingSaves: Set<String> = []

    init(dataRepo: any CircleDataRepository = CloudKitCircleDataRepository()) {
        self.dataRepo = dataRepo
    }

    // MARK: - Lifecycle

    /// Nuke every piece of in-memory state. Used by `AppState.deleteAccount`
    /// so the dashboard doesn't keep painting the previous account's
    /// circle members, messages, or pending optimistic sends between the
    /// CloudKit deletes and the re-onboarding flow.
    func reset() {
        circle = nil
        currentUserID = ""
        members = []
        circleMessages = []
        directMessages = []
        token = nil
        pendingSaves = []
        isLoading = false
        lastError = nil
    }

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

    // MARK: - Read tracking (unread indicator)

    /// Mark this circle as fully read as of now. Called by `CircleFeedView`
    /// when the chat appears so FriendsView can stop showing the unread
    /// indicator for it. Persisted so the indicator state survives
    /// relaunches.
    func markCircleRead(circleID: UUID) {
        var dict = Self.loadDict(forKey: LocalCacheKey.circleLastReadAt)
        dict[circleID.uuidString] = Date.now.timeIntervalSince1970
        Self.saveDict(dict, forKey: LocalCacheKey.circleLastReadAt)
    }

    /// True when this circle has a newer message timestamp on record
    /// than the last time the user opened it. Cheap lookup against
    /// LocalCache — no CloudKit call.
    static func hasUnread(circleID: UUID) -> Bool {
        let readDict = loadDict(forKey: LocalCacheKey.circleLastReadAt)
        let msgDict = loadDict(forKey: LocalCacheKey.circleLastMessageAt)
        let lastRead = readDict[circleID.uuidString] ?? 0
        let lastMsg = msgDict[circleID.uuidString] ?? 0
        return lastMsg > lastRead
    }

    /// Record the latest message timestamp observed for a circle. Called
    /// from `load()` and `refresh()` so other circles' unread state stays
    /// reasonably current without requiring a separate fetch per circle.
    private static func recordLatestMessage(circleID: UUID, at timestamp: Date) {
        var dict = loadDict(forKey: LocalCacheKey.circleLastMessageAt)
        let key = circleID.uuidString
        let existing = dict[key] ?? 0
        let candidate = timestamp.timeIntervalSince1970
        if candidate > existing {
            dict[key] = candidate
            saveDict(dict, forKey: LocalCacheKey.circleLastMessageAt)
        }
    }

    private static func loadDict(forKey key: String) -> [String: Double] {
        LocalCache.load([String: Double].self, forKey: key) ?? [:]
    }

    private static func saveDict(_ dict: [String: Double], forKey key: String) {
        LocalCache.save(dict, forKey: key)
    }

    /// Full load — replaces all cached state, except for records whose writes
    /// are still in flight (or have failed and not retried). Those stay so a
    /// just-sent message doesn't blink out of view when the user navigates
    /// back into a Circle before its persist completes.
    func load() async {
        guard let circle else { return }
        // Capture pending entries BEFORE the fetch so we can splice them
        // back in afterwards.
        let pendingCircleMsgs = circleMessages.filter {
            pendingSaves.contains($0.recordName)
        }
        let pendingDirectMsgs = directMessages.filter {
            pendingSaves.contains($0.recordName)
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let snap = try await dataRepo.snapshot(for: circle, since: nil)
            token = snap.token
            members = snap.members
            circleMessages = Self.spliceIn(pendingCircleMsgs, into: snap.circleMessages)
            directMessages = Self.spliceIn(pendingDirectMsgs, into: snap.directMessages)
            // Record the latest observed message timestamp for this
            // circle so FriendsView's unread indicator has fresh data.
            if let latest = circleMessages.map(\.createdAt).max() {
                Self.recordLatestMessage(circleID: circle.id, at: latest)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Append `pending` entries to `fetched` unless the same recordName
    /// already came back from the server. Used during full reloads to keep
    /// optimistic-send records on screen while their CloudKit write is in
    /// flight.
    private static func spliceIn<T: ZoneRecord>(_ pending: [T], into fetched: [T]) -> [T] {
        guard !pending.isEmpty else { return fetched }
        let serverNames = Set(fetched.map(\.recordName))
        return fetched + pending.filter { !serverNames.contains($0.recordName) }
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
        if let id = circle?.id, let latest = circleMessages.map(\.createdAt).max() {
            Self.recordLatestMessage(circleID: id, at: latest)
        }
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
        let names = records.map(\.recordName)
        // Mark as pending BEFORE the network call so load() running
        // concurrently with the send still preserves these records.
        for n in names { pendingSaves.insert(n) }
        Task {
            do {
                try await dataRepo.save(records, in: circle)
                // Success: drop from pending so the next refresh can
                // treat the record as canonical-server.
                for n in names { pendingSaves.remove(n) }
                // Clear any prior error if this save succeeded.
                if lastError != nil { lastError = nil }
            } catch {
                // KEEP in pendingSaves so the local copy stays visible,
                // and surface the error so the user can see something
                // failed instead of silently losing the message.
                NSLog("[Tally] persistSave failed: \(error.localizedDescription)")
                lastError = error.localizedDescription
            }
        }
    }
}

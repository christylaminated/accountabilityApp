import CloudKit
import Foundation
import Observation

/// Marker conformance for records that carry a `userID` — used by
/// `PersonalStore`'s merge to scope deletions to one friend's zone.
protocol HasUserID {
    var userID: String { get }
}

extension Habit: HasUserID {}
extension HabitCompletion: HasUserID {}
extension Goal: HasUserID {}

/// Holds everything in the signed-in user's *personal* CloudKit zone — habits,
/// completions, goals. In a later step (3e), it'll also hold each connected
/// friend's data fetched from their personal zones.
///
/// Reads are synchronous against in-memory arrays so SwiftUI views stay simple.
/// Writes are optimistic: local arrays update immediately, and the change is
/// pushed to CloudKit in the background. `refresh()` reconciles with the server.
@MainActor
@Observable
final class PersonalStore {
    private let repository: any PersonalRepository

    var habits: [Habit] = []
    var completions: [HabitCompletion] = []
    var goals: [Goal] = []
    /// Friends derived from the personal zones visible in my shared DB.
    /// Display name + avatar come from each friend's `PersonalRoot`.
    var friends: [Friend] = []

    var isLoading = false
    var lastError: String?

    /// Signed-in user's CloudKit record name. Set by `AppState` on activation.
    var currentUserID: String = ""

    /// Server change token for my shared personal zone.
    private var ownToken: CKServerChangeToken?
    /// Server change token for my private personal zone (private habits live here).
    private var ownPrivateToken: CKServerChangeToken?
    /// Server change tokens per friend zone.
    private var friendTokens: [CKRecordZone.ID: CKServerChangeToken] = [:]

    /// User record names of friends the user has unfriended on this device.
    /// Persisted across launches via `LocalCacheKey.locallyUnfriendedIDs`.
    /// Filters out friend zones at load + refresh time so unfriended
    /// friends stay gone — replaces the old `leaveFriendShare` approach
    /// which called `CKShare.removeParticipant` on someone else's share
    /// and could raise an uncatchable NSException in iOS 26's CloudKit.
    private var locallyUnfriendedIDs: Set<String> = []

    init(repository: any PersonalRepository = CloudKitPersonalRepository()) {
        self.repository = repository
        // Restore cached arrays synchronously so the dashboard renders
        // immediately on launch — the CloudKit refresh runs in the background
        // and atomically replaces these once it completes.
        if let cached = LocalCache.load(CachedState.self, forKey: LocalCacheKey.personalStore) {
            self.habits = cached.habits
            self.completions = cached.completions
            self.goals = cached.goals
            self.friends = cached.friends
        }
        self.locallyUnfriendedIDs = Set(
            LocalCache.load([String].self, forKey: LocalCacheKey.locallyUnfriendedIDs) ?? []
        )
    }

    /// On-disk shape of the cached store. Excludes change tokens (CloudKit
    /// internals don't serialize cleanly) — refresh after launch does a full
    /// fetch and rebuilds tokens for the session.
    private struct CachedState: Codable {
        var habits: [Habit]
        var completions: [HabitCompletion]
        var goals: [Goal]
        var friends: [Friend]
    }

    private func saveCache() {
        LocalCache.save(
            CachedState(habits: habits, completions: completions, goals: goals, friends: friends),
            forKey: LocalCacheKey.personalStore
        )
    }

    // MARK: - Lifecycle

    /// Point the store at the signed-in user and do a full load. Only wipes
    /// cached arrays if we're switching to a *different* user — when called
    /// with the same user (the common case on launch after restoring from
    /// `LocalCache`), the cached data stays visible while `load()` runs and
    /// gets atomically replaced when fresh data arrives.
    func activate(currentUserID: String) async {
        let userChanged = !self.currentUserID.isEmpty && self.currentUserID != currentUserID
        self.currentUserID = currentUserID
        if userChanged {
            ownToken = nil
            ownPrivateToken = nil
            friendTokens = [:]
            habits = []; completions = []; goals = []; friends = []
        }
        await load()
    }

    /// Full load — fetches every zone, then atomically replaces the in-memory
    /// arrays. Doing the assignment at the end (rather than as we go) means
    /// cached data stays on screen during the network round-trip; nothing
    /// flashes empty.
    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let mine = try await repository.ownSnapshot(since: nil)
            let minePrivate = try await repository.ownPrivateSnapshot(since: nil)
            // Filter out zones belonging to locally-unfriended users so
            // they never enter the visible friend graph. Their zone may
            // still be in our sharedDB (we don't leave their share), but
            // we treat them as gone.
            let zones = try await repository.friendZones()
                .filter { !locallyUnfriendedIDs.contains($0.zoneID.ownerName) }

            var nextHabits = mine.habits + minePrivate.habits
            var nextCompletions = mine.completions + minePrivate.completions
            var nextGoals = mine.goals
            // Goals are always shared — minePrivate.goals stays unused.
            var nextFriends: [Friend] = []
            var nextFriendTokens: [CKRecordZone.ID: CKServerChangeToken] = [:]

            for zone in zones {
                let snap = try await repository.friendSnapshot(zoneID: zone.zoneID, since: nil)
                nextFriendTokens[zone.zoneID] = snap.token
                nextHabits.append(contentsOf: snap.habits)
                nextCompletions.append(contentsOf: snap.completions)
                nextGoals.append(contentsOf: snap.goals)

                let userID = zone.zoneID.ownerName
                if let root = snap.root {
                    nextFriends.append(Friend(
                        userID: userID,
                        displayName: root.displayName.isEmpty ? "Friend" : root.displayName,
                        avatarSymbol: root.avatarSymbol,
                        avatarImageData: root.avatarImageData
                    ))
                } else {
                    nextFriends.append(Friend(userID: userID, displayName: "Friend", avatarSymbol: "leaf"))
                }
            }

            // Atomic swap. The UI sees cached data right up until this point.
            ownToken = mine.token
            ownPrivateToken = minePrivate.token
            friendTokens = nextFriendTokens
            habits = nextHabits
            completions = nextCompletions
            goals = nextGoals
            friends = nextFriends
            saveCache()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Incremental refresh of every zone (own shared + own private + friends').
    /// Discovers new friend zones, drops data from friends who've vanished,
    /// applies per-zone deltas.
    func refresh() async {
        guard ownToken != nil else { await load(); return }
        do {
            // Own shared zone delta
            let mine = try await repository.ownSnapshot(since: ownToken)
            ownToken = mine.token
            apply(mine, ownerUserID: currentUserID)

            // Own private zone delta
            let minePrivate = try await repository.ownPrivateSnapshot(since: ownPrivateToken)
            ownPrivateToken = minePrivate.token
            apply(minePrivate, ownerUserID: currentUserID)

            // Friend zones — pick up new ones, drop departed ones,
            // delta-fetch the rest. Locally-unfriended zones get
            // filtered out before any further processing so they're
            // treated as departed even when the underlying share is
            // still there.
            let zones = try await repository.friendZones()
                .filter { !locallyUnfriendedIDs.contains($0.zoneID.ownerName) }
            let currentZoneIDs = Set(zones.map { $0.zoneID })
            let knownZoneIDs = Set(friendTokens.keys)

            // Drop departed friends' data
            let departed = knownZoneIDs.subtracting(currentZoneIDs)
            for zoneID in departed {
                friendTokens.removeValue(forKey: zoneID)
                let departedUserID = zoneID.ownerName
                habits.removeAll { $0.userID == departedUserID }
                completions.removeAll { $0.userID == departedUserID }
                goals.removeAll { $0.userID == departedUserID }
                friends.removeAll { $0.userID == departedUserID }
            }

            for zone in zones {
                do {
                    let snap = try await repository.friendSnapshot(
                        zoneID: zone.zoneID,
                        since: friendTokens[zone.zoneID]
                    )
                    friendTokens[zone.zoneID] = snap.token
                    apply(snap, ownerUserID: zone.zoneID.ownerName)
                    // Update friend's profile from PersonalRoot if it arrived
                    // in this delta, or add a fresh Friend entry on first sight.
                    if let root = snap.root {
                        upsertFriend(
                            userID: zone.zoneID.ownerName,
                            displayName: root.displayName.isEmpty ? "Friend" : root.displayName,
                            avatarSymbol: root.avatarSymbol,
                            avatarImageData: root.avatarImageData
                        )
                    } else if !friends.contains(where: { $0.userID == zone.zoneID.ownerName }) {
                        friends.append(Friend(
                            userID: zone.zoneID.ownerName,
                            displayName: "Friend",
                            avatarSymbol: "leaf"
                        ))
                    }
                } catch let error as CKError where error.code == .changeTokenExpired {
                    // Reset just this zone's token and do a full refetch for it.
                    // Wrapped in do/catch too — a refetch that itself fails
                    // shouldn't abort sibling zones.
                    do {
                        friendTokens.removeValue(forKey: zone.zoneID)
                        let snap = try await repository.friendSnapshot(zoneID: zone.zoneID, since: nil)
                        friendTokens[zone.zoneID] = snap.token
                        let userID = zone.zoneID.ownerName
                        habits.removeAll { $0.userID == userID }
                        completions.removeAll { $0.userID == userID }
                        goals.removeAll { $0.userID == userID }
                        habits.append(contentsOf: snap.habits)
                        completions.append(contentsOf: snap.completions)
                        goals.append(contentsOf: snap.goals)
                    } catch {
                        NSLog("[Tally] PersonalStore.refresh: zone=\(zone.zoneID.zoneName)/\(zone.zoneID.ownerName) refetch after token-expire failed: \(error.localizedDescription)")
                    }
                } catch {
                    // Per-zone defensive catch: previously ANY other error
                    // from friendSnapshot would propagate out of this for-loop
                    // and abort the WHOLE refresh, so a freshly-accepted
                    // reciprocal share that wasn't yet readable (eventual
                    // consistency) would prevent every OTHER friend's data
                    // from refreshing too. Now we log and continue.
                    NSLog("[Tally] PersonalStore.refresh: zone=\(zone.zoneID.zoneName)/\(zone.zoneID.ownerName) snapshot failed: \(error.localizedDescription) — continuing with other zones")
                }
            }
        } catch let error as CKError where error.code == .changeTokenExpired {
            ownToken = nil
            ownPrivateToken = nil
            friendTokens = [:]
            await load()
            return
        } catch {
            lastError = error.localizedDescription
            return
        }
        saveCache()
    }

    /// Merge a per-zone delta into our cached arrays. `ownerUserID` scopes the
    /// merge so deletions from one friend's zone don't accidentally touch
    /// another's records.
    private func apply(_ snap: PersonalSnapshot, ownerUserID: String) {
        let deleted = Set(snap.deletedRecordNames)
        Self.merge(snap.habits, deleted: deleted, ownerUserID: ownerUserID, into: &habits)
        Self.merge(snap.completions, deleted: deleted, ownerUserID: ownerUserID, into: &completions)
        Self.merge(snap.goals, deleted: deleted, ownerUserID: ownerUserID, into: &goals)
    }

    /// Insert-or-update a friend row keyed by userID.
    private func upsertFriend(
        userID: String,
        displayName: String,
        avatarSymbol: String,
        avatarImageData: Data? = nil
    ) {
        if let i = friends.firstIndex(where: { $0.userID == userID }) {
            friends[i].displayName = displayName
            friends[i].avatarSymbol = avatarSymbol
            if let avatarImageData {
                friends[i].avatarImageData = avatarImageData
            }
        } else {
            friends.append(Friend(
                userID: userID,
                displayName: displayName,
                avatarSymbol: avatarSymbol,
                avatarImageData: avatarImageData
            ))
        }
    }

    /// Look up a friend by user record ID.
    func friend(id userID: String) -> Friend? {
        friends.first { $0.userID == userID }
    }

    /// Drop a friend (and all their cached habits / goals / completions) from
    /// in-memory state without waiting for a CloudKit refresh to catch up,
    /// AND persist the unfriend so subsequent refreshes don't re-add them
    /// from the still-present zone in our sharedDB.
    func dropFriendLocally(userID: String) {
        friends.removeAll { $0.userID == userID }
        habits.removeAll { $0.userID == userID }
        completions.removeAll { $0.userID == userID }
        goals.removeAll { $0.userID == userID }
        let zoneIDs = friendTokens.keys.filter { $0.ownerName == userID }
        for zoneID in zoneIDs {
            friendTokens.removeValue(forKey: zoneID)
        }
        locallyUnfriendedIDs.insert(userID)
        LocalCache.save(Array(locallyUnfriendedIDs), forKey: LocalCacheKey.locallyUnfriendedIDs)
        saveCache()
    }

    /// Nuke every piece of in-memory state. Used by `AppState.deleteAccount`
    /// so the dashboard doesn't keep painting the previous account's
    /// habits, completions, goals, friends, or change tokens between the
    /// CloudKit deletes and the re-onboarding flow. Persisted caches are
    /// wiped separately by `LocalCache.clearAll`; this only owns the
    /// `@Observable` arrays that SwiftUI is reading.
    ///
    /// Important: `locallyUnfriendedIDs` is re-read from LocalCache rather
    /// than emptied. `deleteAccount` augments the persisted hide-list with
    /// every current friend's userID BEFORE calling reset, so on a same-
    /// iCloud re-signup `refresh()` filters those friends' shared zones
    /// out of the friend graph. If we emptied the in-memory copy here,
    /// the post-delete refresh would see no filter and old friends would
    /// reappear — the exact bug the user reported.
    func reset() {
        currentUserID = ""
        ownToken = nil
        ownPrivateToken = nil
        friendTokens = [:]
        habits = []
        completions = []
        goals = []
        friends = []
        lastError = nil
        locallyUnfriendedIDs = Set(
            LocalCache.load([String].self, forKey: LocalCacheKey.locallyUnfriendedIDs) ?? []
        )
    }

    /// Drop the change token for any zones owned by `userID`. Used by the
    /// reciprocal-accept flow: after the sender's app accepts the friend's
    /// share metadata, the friend's zone may take a few seconds to fully
    /// replicate into our sharedDB. Forcing a token-less full fetch on the
    /// next refresh guarantees we read everything from scratch (including
    /// the PersonalRoot record) rather than asking CloudKit for "changes
    /// since <stale-token>" against a zone whose data hasn't propagated yet.
    func resetFriendZoneToken(ownerName: String) {
        let zoneIDs = friendTokens.keys.filter { $0.ownerName == ownerName }
        for zoneID in zoneIDs {
            friendTokens.removeValue(forKey: zoneID)
        }
    }

    /// Clear the locally-unfriended flag for `userID`. Called when the
    /// user explicitly re-engages with a previously-unfriended person
    /// (sending them a new friend request, or accepting one from them).
    func clearLocalUnfriend(userID: String) {
        guard locallyUnfriendedIDs.contains(userID) else { return }
        locallyUnfriendedIDs.remove(userID)
        LocalCache.save(Array(locallyUnfriendedIDs), forKey: LocalCacheKey.locallyUnfriendedIDs)
    }

    /// True iff the user has locally unfriended this person. Lets callers
    /// (e.g., the friend-search view) treat them as not-a-friend even
    /// though CloudKit may still surface their zone.
    func isLocallyUnfriended(userID: String) -> Bool {
        locallyUnfriendedIDs.contains(userID)
    }

    /// Upsert changed records by `recordName`, then drop anything deleted from
    /// the same zone (matched by `ownerUserID`).
    private static func merge<T: ZoneRecord>(
        _ changes: [T],
        deleted: Set<String>,
        ownerUserID: String,
        into array: inout [T]
    ) where T: HasUserID {
        for item in changes {
            if let i = array.firstIndex(where: { $0.recordName == item.recordName }) {
                array[i] = item
            } else {
                array.append(item)
            }
        }
        if !deleted.isEmpty {
            array.removeAll {
                $0.userID == ownerUserID && deleted.contains($0.recordName)
            }
        }
    }

    // MARK: - Habits (queries)

    func habits(for userID: String) -> [Habit] {
        habits
            .filter { $0.userID == userID && $0.archivedAt == nil }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func completion(habit: Habit, on date: Date) -> HabitCompletion? {
        let day = date.startOfDay
        return completions.first {
            $0.habitID == habit.id && $0.completedDate.startOfDay == day
        }
    }

    func isCompleted(habit: Habit, on date: Date) -> Bool {
        completion(habit: habit, on: date) != nil
    }

    func completionDates(habit: Habit) -> [Date] {
        completions.filter { $0.habitID == habit.id }.map { $0.completedDate }
    }

    // MARK: - Habits (mutations)

    @discardableResult
    func toggle(habit: Habit, on date: Date) -> Bool {
        let day = date.startOfDay
        if let existing = completion(habit: habit, on: day) {
            completions.removeAll { $0.id == existing.id }
            persistDelete([existing.recordName], privacy: habit.privacy)
            saveCache()
            return false
        }
        let new = HabitCompletion(
            id: UUID(),
            habitID: habit.id,
            userID: habit.userID,
            completedDate: day,
            createdAt: .now
        )
        completions.append(new)
        persistSave([new], privacy: habit.privacy)
        saveCache()
        return true
    }

    func addHabit(title: String, for userID: String, privacy: HabitPrivacy = .shared) {
        let habit = Habit(
            id: UUID(),
            userID: userID,
            title: title,
            privacy: privacy,
            createdAt: .now,
            archivedAt: nil
        )
        habits.append(habit)
        persistSave([habit], privacy: privacy)
        saveCache()
    }

    /// Edit a habit's title and/or privacy. A privacy change moves the
    /// habit record AND its completions between the shared and private
    /// zones (private records never ride a CKShare), so we delete from the
    /// old zone and re-save to the new one. A title-only change just
    /// re-saves in place.
    func updateHabit(_ habit: Habit, title: String, privacy: HabitPrivacy) {
        guard let i = habits.firstIndex(where: { $0.id == habit.id }) else { return }
        let oldPrivacy = habits[i].privacy
        habits[i].title = title
        habits[i].privacy = privacy
        let updated = habits[i]

        if oldPrivacy != privacy {
            let related = completions.filter { $0.habitID == habit.id }
            persistDelete(
                [habit.recordName] + related.map { $0.recordName },
                privacy: oldPrivacy
            )
            persistSave([updated] + related, privacy: privacy)
        } else {
            persistSave([updated], privacy: privacy)
        }
        saveCache()
    }

    func archive(habit: Habit) {
        guard let i = habits.firstIndex(where: { $0.id == habit.id }) else { return }
        habits[i].archivedAt = .now
        persistSave([habits[i]], privacy: habit.privacy)
        saveCache()
    }

    func delete(habit: Habit) {
        habits.removeAll { $0.id == habit.id }
        let staleCompletions = completions.filter { $0.habitID == habit.id }
        completions.removeAll { $0.habitID == habit.id }
        persistDelete([habit.recordName] + staleCompletions.map { $0.recordName }, privacy: habit.privacy)
        saveCache()
    }

    // MARK: - Goals (daily / weekly / monthly / yearly)

    func goals(for userID: String, period: GoalPeriod, periodStart: Date) -> [Goal] {
        let anchor = periodStart.startOfDay
        return goals
            .filter {
                $0.userID == userID
                && $0.period == period
                && $0.periodStartDate.startOfDay == anchor
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func unfinishedFromPrevious(userID: String, period: GoalPeriod, currentStart: Date) -> [Goal] {
        let previousStart = period.shift(currentStart, by: -1).startOfDay
        return goals.filter {
            $0.userID == userID
            && $0.period == period
            && $0.periodStartDate.startOfDay == previousStart
            && $0.completedAt == nil
        }
    }

    func toggleComplete(goal: Goal) {
        guard let i = goals.firstIndex(where: { $0.id == goal.id }) else { return }
        goals[i].completedAt = goals[i].completedAt == nil ? .now : nil
        persistSave([goals[i]])
        saveCache()
    }

    func addGoal(title: String, for userID: String, period: GoalPeriod, periodStart: Date) {
        let goal = Goal(
            id: UUID(),
            userID: userID,
            title: title,
            period: period,
            periodStartDate: periodStart,
            completedAt: nil,
            carriedFromID: nil,
            createdAt: .now
        )
        goals.append(goal)
        persistSave([goal])
        saveCache()
    }

    /// Edit a goal's title in place. Period + periodStart are fixed once
    /// created (changing them would move the goal to a different bucket,
    /// which is better expressed as delete + re-add).
    func updateGoal(_ goal: Goal, title: String) {
        guard let i = goals.firstIndex(where: { $0.id == goal.id }) else { return }
        goals[i].title = title
        persistSave([goals[i]])
        saveCache()
    }

    func carryForward(goal: Goal, to periodStart: Date) {
        let copy = Goal(
            id: UUID(),
            userID: goal.userID,
            title: goal.title,
            period: goal.period,
            periodStartDate: periodStart,
            completedAt: nil,
            carriedFromID: goal.id,
            createdAt: .now
        )
        goals.append(copy)
        persistSave([copy])
        saveCache()
    }

    func delete(goal: Goal) {
        goals.removeAll { $0.id == goal.id }
        persistDelete([goal.recordName])
        saveCache()
    }

    // MARK: - Write-through

    /// Goals are always shared, so they route to the shared zone unconditionally.
    private func persistSave(_ records: [any ZoneRecord]) {
        Task {
            do {
                try await repository.saveOwn(records)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    private func persistDelete(_ recordNames: [String]) {
        guard !recordNames.isEmpty else { return }
        Task {
            do {
                try await repository.deleteOwn(recordNames: recordNames)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    /// Habit + HabitCompletion writes route to the shared or private zone based
    /// on the habit's privacy. Private records never ride a CKShare and only
    /// sync across the user's own devices via the private DB.
    private func persistSave(_ records: [any ZoneRecord], privacy: HabitPrivacy) {
        Task {
            do {
                switch privacy {
                case .shared:  try await repository.saveOwn(records)
                case .private: try await repository.saveOwnPrivate(records)
                }
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    private func persistDelete(_ recordNames: [String], privacy: HabitPrivacy) {
        guard !recordNames.isEmpty else { return }
        Task {
            do {
                switch privacy {
                case .shared:  try await repository.deleteOwn(recordNames: recordNames)
                case .private: try await repository.deleteOwnPrivate(recordNames: recordNames)
                }
            } catch {
                lastError = error.localizedDescription
            }
        }
    }
}

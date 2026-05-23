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

    init(repository: any PersonalRepository = CloudKitPersonalRepository()) {
        self.repository = repository
    }

    // MARK: - Lifecycle

    /// Point the store at the signed-in user and do a full load (my shared zone
    /// + my private zone + every friend zone visible in the shared DB).
    func activate(currentUserID: String) async {
        self.currentUserID = currentUserID
        ownToken = nil
        ownPrivateToken = nil
        friendTokens = [:]
        habits = []; completions = []; goals = []; friends = []
        await load()
    }

    /// Full load — replaces all cached state. Loads my shared zone, then my
    /// private zone, then every friend zone I currently have access to.
    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let mine = try await repository.ownSnapshot(since: nil)
            ownToken = mine.token
            habits = mine.habits
            completions = mine.completions
            goals = mine.goals

            let minePrivate = try await repository.ownPrivateSnapshot(since: nil)
            ownPrivateToken = minePrivate.token
            habits.append(contentsOf: minePrivate.habits)
            completions.append(contentsOf: minePrivate.completions)
            // Goals are always shared, so we don't merge minePrivate.goals.

            let zones = try await repository.friendZones()
            var loadedFriends: [Friend] = []
            for zone in zones {
                let snap = try await repository.friendSnapshot(zoneID: zone.zoneID, since: nil)
                friendTokens[zone.zoneID] = snap.token
                habits.append(contentsOf: snap.habits)
                completions.append(contentsOf: snap.completions)
                goals.append(contentsOf: snap.goals)

                let userID = zone.zoneID.ownerName
                if let root = snap.root {
                    loadedFriends.append(Friend(
                        userID: userID,
                        displayName: root.displayName.isEmpty ? "Friend" : root.displayName,
                        avatarSymbol: root.avatarSymbol
                    ))
                } else {
                    // No root yet — friend's app hasn't written profile info.
                    loadedFriends.append(Friend(userID: userID, displayName: "Friend", avatarSymbol: "leaf"))
                }
            }
            friends = loadedFriends
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

            // Friend zones — pick up new ones, drop departed ones, delta-fetch the rest
            let zones = try await repository.friendZones()
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
                            avatarSymbol: root.avatarSymbol
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
                    friendTokens.removeValue(forKey: zone.zoneID)
                    let snap = try await repository.friendSnapshot(zoneID: zone.zoneID, since: nil)
                    friendTokens[zone.zoneID] = snap.token
                    // Replace this friend's data wholesale
                    let userID = zone.zoneID.ownerName
                    habits.removeAll { $0.userID == userID }
                    completions.removeAll { $0.userID == userID }
                    goals.removeAll { $0.userID == userID }
                    habits.append(contentsOf: snap.habits)
                    completions.append(contentsOf: snap.completions)
                    goals.append(contentsOf: snap.goals)
                }
            }
        } catch let error as CKError where error.code == .changeTokenExpired {
            ownToken = nil
            ownPrivateToken = nil
            friendTokens = [:]
            await load()
        } catch {
            lastError = error.localizedDescription
        }
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
    private func upsertFriend(userID: String, displayName: String, avatarSymbol: String) {
        if let i = friends.firstIndex(where: { $0.userID == userID }) {
            friends[i].displayName = displayName
            friends[i].avatarSymbol = avatarSymbol
        } else {
            friends.append(Friend(userID: userID, displayName: displayName, avatarSymbol: avatarSymbol))
        }
    }

    /// Look up a friend by user record ID.
    func friend(id userID: String) -> Friend? {
        friends.first { $0.userID == userID }
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
    }

    func archive(habit: Habit) {
        guard let i = habits.firstIndex(where: { $0.id == habit.id }) else { return }
        habits[i].archivedAt = .now
        persistSave([habits[i]], privacy: habit.privacy)
    }

    func delete(habit: Habit) {
        habits.removeAll { $0.id == habit.id }
        let staleCompletions = completions.filter { $0.habitID == habit.id }
        completions.removeAll { $0.habitID == habit.id }
        persistDelete([habit.recordName] + staleCompletions.map { $0.recordName }, privacy: habit.privacy)
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
    }

    func delete(goal: Goal) {
        goals.removeAll { $0.id == goal.id }
        persistDelete([goal.recordName])
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

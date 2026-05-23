import CloudKit
import Foundation
import Observation

/// The single observable store for everything inside the active Circle —
/// members, habits, check-ins, weekly goals, and messages.
///
/// Reads are synchronous against in-memory arrays so SwiftUI views stay simple.
/// Writes are optimistic: the local arrays update immediately, and the change is
/// pushed to CloudKit in the background. A `refresh()` (on launch, foreground,
/// or push) reconciles with the server so friends' changes appear.
@MainActor
@Observable
final class CircleStore {
    private let dataRepo: any CircleDataRepository

    /// The Circle this store is scoped to. Set via `activate`.
    private(set) var circle: TallyCircle?

    var members: [CircleMember] = []
    var habits: [Habit] = []
    var completions: [HabitCompletion] = []
    var goals: [Goal] = []
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
            members = []; habits = []; completions = []
            goals = []; circleMessages = []; directMessages = []
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
            habits = snap.habits
            completions = snap.completions
            goals = snap.goals
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
        Self.merge(snap.habits, deleted: deleted, into: &habits)
        Self.merge(snap.completions, deleted: deleted, into: &completions)
        Self.merge(snap.goals, deleted: deleted, into: &goals)
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
            persistDelete([existing.recordName])
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
        persistSave([new])
        return true
    }

    func addHabit(title: String, for userID: String) {
        let habit = Habit(
            id: UUID(),
            userID: userID,
            title: title,
            createdAt: .now,
            archivedAt: nil
        )
        habits.append(habit)
        persistSave([habit])
    }

    func archive(habit: Habit) {
        guard let i = habits.firstIndex(where: { $0.id == habit.id }) else { return }
        habits[i].archivedAt = .now
        persistSave([habits[i]])
    }

    func delete(habit: Habit) {
        habits.removeAll { $0.id == habit.id }
        let staleCompletions = completions.filter { $0.habitID == habit.id }
        completions.removeAll { $0.habitID == habit.id }
        persistDelete([habit.recordName] + staleCompletions.map { $0.recordName })
    }

    // MARK: - Goals (daily / weekly / monthly / yearly)

    /// Goals for `userID` at `period`, anchored at `periodStart` (the start of
    /// the day / Monday / 1st of month / Jan 1).
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

    /// Unfinished goals from the period immediately before `currentStart` — used
    /// to offer carry-over into the current period.
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

    /// Carry an unfinished goal into a later period of the same type. Inherits
    /// the source goal's period so a weekly carry stays weekly.
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

    private func persistDelete(_ recordNames: [String]) {
        guard let circle, !recordNames.isEmpty else { return }
        Task {
            do {
                try await dataRepo.delete(recordNames: recordNames, in: circle)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }
}

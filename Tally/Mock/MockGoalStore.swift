import Foundation
import Observation

@Observable
final class MockGoalStore {
    var goals: [WeeklyGoal]

    init(goals: [WeeklyGoal] = MockData.goals) {
        self.goals = goals
    }

    func goals(for userID: UUID, weekStart: Date) -> [WeeklyGoal] {
        let week = weekStart.startOfDay
        return goals.filter {
            $0.userID == userID && $0.weekStartDate.startOfDay == week
        }
    }

    func unfinishedFromLastWeek(userID: UUID, currentWeekStart: Date) -> [WeeklyGoal] {
        let last = currentWeekStart.adding(days: -7).startOfDay
        return goals.filter {
            $0.userID == userID
            && $0.weekStartDate.startOfDay == last
            && $0.completedAt == nil
        }
    }

    func toggleComplete(goal: WeeklyGoal) {
        guard let i = goals.firstIndex(where: { $0.id == goal.id }) else { return }
        if goals[i].completedAt == nil {
            goals[i].completedAt = .now
        } else {
            goals[i].completedAt = nil
        }
    }

    func add(title: String, for userID: UUID, weekStart: Date) {
        goals.append(WeeklyGoal(
            id: UUID(),
            userID: userID,
            title: title,
            weekStartDate: weekStart,
            completedAt: nil,
            carriedFromID: nil,
            createdAt: .now
        ))
    }

    func carryForward(goal: WeeklyGoal, to weekStart: Date) {
        goals.append(WeeklyGoal(
            id: UUID(),
            userID: goal.userID,
            title: goal.title,
            weekStartDate: weekStart,
            completedAt: nil,
            carriedFromID: goal.id,
            createdAt: .now
        ))
    }

    func delete(goal: WeeklyGoal) {
        goals.removeAll { $0.id == goal.id }
    }
}

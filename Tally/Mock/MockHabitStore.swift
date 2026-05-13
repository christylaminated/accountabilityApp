import Foundation
import Observation

@Observable
final class MockHabitStore {
    var habits: [Habit]
    var completions: [HabitCompletion]

    init(habits: [Habit] = MockData.allHabits,
         completions: [HabitCompletion] = MockData.completions) {
        self.habits = habits
        self.completions = completions
    }

    // MARK: Queries

    func habits(for userID: UUID) -> [Habit] {
        habits.filter { $0.userID == userID && $0.archivedAt == nil }
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

    func completions(userID: UUID, on date: Date) -> [HabitCompletion] {
        let day = date.startOfDay
        return completions.filter {
            $0.userID == userID && $0.completedDate.startOfDay == day
        }
    }

    // MARK: Mutations

    @discardableResult
    func toggle(habit: Habit, on date: Date) -> Bool {
        let day = date.startOfDay
        if let existing = completion(habit: habit, on: day) {
            completions.removeAll { $0.id == existing.id }
            return false
        }
        completions.append(HabitCompletion(
            id: UUID(),
            habitID: habit.id,
            userID: habit.userID,
            completedDate: day,
            createdAt: .now
        ))
        return true
    }

    func add(title: String, for userID: UUID) {
        habits.append(Habit(
            id: UUID(),
            userID: userID,
            title: title,
            createdAt: .now,
            archivedAt: nil
        ))
    }

    func archive(habit: Habit) {
        if let i = habits.firstIndex(where: { $0.id == habit.id }) {
            habits[i].archivedAt = .now
        }
    }

    func delete(habit: Habit) {
        habits.removeAll { $0.id == habit.id }
        completions.removeAll { $0.habitID == habit.id }
    }
}

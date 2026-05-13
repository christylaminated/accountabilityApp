import SwiftUI

struct HabitRowView: View {
    @Environment(AppState.self) private var appState
    let habit: Habit

    private var isDone: Bool {
        appState.habitStore.isCompleted(habit: habit, on: .now)
    }

    private var streak: Int {
        StreakCalculator.currentStreak(
            completions: appState.habitStore.completionDates(habit: habit),
            habitCreatedAt: habit.createdAt
        )
    }

    private var longest: Int {
        StreakCalculator.longestStreak(
            completions: appState.habitStore.completionDates(habit: habit),
            habitCreatedAt: habit.createdAt
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            CheckboxButton(isChecked: isDone, isEditable: true) {
                _ = appState.habitStore.toggle(habit: habit, on: .now)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(habit.title).font(.body.weight(.medium))
                HStack(spacing: 12) {
                    Label("\(streak)", systemImage: "flame.fill")
                        .foregroundStyle(streak > 0 ? Color.tallyAccent : .secondary)
                    Label("\(longest)", systemImage: "trophy.fill")
                        .foregroundStyle(.secondary)
                }
                .font(.caption.monospacedDigit())
            }
            Spacer()
        }
        .padding(14)
        .background(Color.tallyCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .contextMenu {
            Button(role: .destructive) {
                appState.habitStore.delete(habit: habit)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                appState.habitStore.archive(habit: habit)
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
        }
    }
}

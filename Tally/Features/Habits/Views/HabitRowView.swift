import SwiftUI

struct HabitRowView: View {
    @Environment(AppState.self) private var appState
    let habit: Habit

    private var isDone: Bool {
        appState.circleStore.isCompleted(habit: habit, on: .now)
    }

    private var streak: Int {
        StreakCalculator.currentStreak(
            completions: appState.circleStore.completionDates(habit: habit),
            habitCreatedAt: habit.createdAt
        )
    }

    private var longest: Int {
        StreakCalculator.longestStreak(
            completions: appState.circleStore.completionDates(habit: habit),
            habitCreatedAt: habit.createdAt
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            CheckboxButton(isChecked: isDone, isEditable: true) {
                _ = appState.circleStore.toggle(habit: habit, on: .now)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(habit.title).font(.body.weight(.medium))
                    if habit.privacy == .private {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 12) {
                    Label("\(streak)", systemImage: "flame.fill")
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(streak > 0 ? Color.tallyAccent : .secondary)
                    Label("\(longest)", systemImage: "trophy.fill")
                        .symbolRenderingMode(.monochrome)
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
                appState.circleStore.delete(habit: habit)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                appState.circleStore.archive(habit: habit)
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
        }
    }
}

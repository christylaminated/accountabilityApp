import SwiftUI

struct MemberRowView: View {
    @Environment(AppState.self) private var appState
    let member: CircleMember

    private var isMe: Bool { member.userID == appState.currentUserID }

    private var todayHabits: [Habit] {
        appState.personalStore.habits(for: member.userID)
    }

    private var completedCount: Int {
        todayHabits.filter { appState.personalStore.isCompleted(habit: $0, on: .now) }.count
    }

    private var allDone: Bool {
        !todayHabits.isEmpty && completedCount == todayHabits.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AvatarView(symbolName: member.avatarSymbol, size: 44)
                HStack(spacing: 6) {
                    Text(member.displayName)
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                    if isMe {
                        Text("you")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.tallyAccent.opacity(0.15))
                            .foregroundStyle(Color.tallyAccent)
                            .clipShape(Capsule())
                    }
                }
                Spacer()
                Text("\(completedCount)/\(todayHabits.count)")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold).monospacedDigit())
                    .foregroundStyle(allDone ? Color.tallyAccent : .secondary)
            }

            if todayHabits.isEmpty {
                Text("No habits yet")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                habitGrid
            }
        }
        .padding(16)
        .background(Color.tallyCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var habitGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 130, maximum: .infinity), spacing: 8)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(todayHabits) { habit in
                HabitPill(habit: habit, isEditable: isMe)
            }
        }
    }
}

private struct HabitPill: View {
    @Environment(AppState.self) private var appState
    let habit: Habit
    let isEditable: Bool

    private var isDone: Bool {
        appState.personalStore.isCompleted(habit: habit, on: .now)
    }

    var body: some View {
        Button {
            guard isEditable else { return }
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            _ = appState.personalStore.toggle(habit: habit, on: .now)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .symbolEffect(.bounce, value: isDone)
                Text(habit.title)
                    .lineLimit(1)
                    .font(.footnote.weight(.medium))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isDone ? Color.tallyAccent.opacity(0.18) : Color.tallyCanvas)
            .foregroundStyle(isDone ? Color.tallyAccent : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(!isEditable)
    }
}

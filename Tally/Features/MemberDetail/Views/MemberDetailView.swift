import SwiftUI

struct MemberDetailView: View {
    @Environment(AppState.self) private var appState
    let memberID: String

    private var member: CircleMember? {
        appState.circleStore.member(id: memberID)
    }

    private var isMe: Bool { memberID == appState.currentUserID }

    private var habits: [Habit] {
        appState.circleStore.habits(for: memberID)
    }

    private var goals: [Goal] {
        appState.circleStore.goals(
            for: memberID,
            period: .week,
            periodStart: WeekCalculator.weekStart(for: .now)
        )
    }

    var body: some View {
        Group {
            if let member {
                ScrollView {
                    VStack(spacing: 16) {
                        header(member)

                        section(title: "Today's habits") {
                            if habits.isEmpty {
                                infoCard("No habits yet")
                            } else {
                                ForEach(habits) { habit in
                                    MemberHabitRow(habit: habit, isEditable: isMe)
                                }
                            }
                        }

                        section(title: "This week's goals") {
                            if goals.isEmpty {
                                infoCard("No goals set this week")
                            } else {
                                ForEach(goals) { goal in
                                    HStack(spacing: 12) {
                                        Image(systemName: goal.completedAt != nil
                                              ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(goal.completedAt != nil
                                                             ? Color.tallyAccent : .secondary)
                                        Text(goal.title)
                                            .strikethrough(goal.completedAt != nil, color: .secondary)
                                            .foregroundStyle(goal.completedAt != nil
                                                             ? .secondary : .primary)
                                        Spacer()
                                    }
                                    .padding(14)
                                    .background(Color.tallyCard)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                }
                            }
                        }

                        NavigationLink {
                            HistoryCalendarView(targetUserID: memberID)
                        } label: {
                            actionCard(icon: "calendar", text: "View history", filled: false)
                        }

                        if !isMe {
                            NavigationLink {
                                DirectMessageThreadView(otherUserID: memberID)
                            } label: {
                                actionCard(
                                    icon: "bubble.left.and.bubble.right.fill",
                                    text: "Message \(member.displayName)",
                                    filled: true
                                )
                            }
                        }

                        Spacer().frame(height: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                .background(Color.tallyCanvas)
                .navigationTitle(member.displayName)
                .navigationBarTitleDisplayMode(.inline)
            } else {
                EmptyStateView(icon: "person.fill.questionmark", title: "Member not found", message: "")
            }
        }
    }

    // MARK: Subviews

    private func header(_ member: CircleMember) -> some View {
        HStack(spacing: 16) {
            AvatarView(symbolName: member.avatarSymbol, size: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text(member.displayName)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
            }
            Spacer()
        }
        .padding(16)
        .background(Color.tallyCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func infoCard(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.tallyCard)
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func actionCard(icon: String, text: String, filled: Bool) -> some View {
        HStack {
            Image(systemName: icon)
            Text(text)
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(filled ? Color.white.opacity(0.7) : Color.secondary.opacity(0.5))
        }
        .font(.body.weight(filled ? .semibold : .regular))
        .padding(14)
        .background(filled ? Color.tallyAccent : Color.tallyCard)
        .foregroundStyle(filled ? .white : .primary)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct MemberHabitRow: View {
    @Environment(AppState.self) private var appState
    let habit: Habit
    let isEditable: Bool

    private var isDone: Bool {
        appState.circleStore.isCompleted(habit: habit, on: .now)
    }

    private var streak: Int {
        StreakCalculator.currentStreak(
            completions: appState.circleStore.completionDates(habit: habit),
            habitCreatedAt: habit.createdAt
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            CheckboxButton(isChecked: isDone, isEditable: isEditable) {
                _ = appState.circleStore.toggle(habit: habit, on: .now)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.title).font(.body.weight(.medium))
                if streak > 0 {
                    Label("\(streak)-day streak", systemImage: "flame.fill")
                        .symbolRenderingMode(.monochrome)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.tallyAccent)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(Color.tallyCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

import SwiftUI

struct WeeklyGoalsView: View {
    @Environment(AppState.self) private var appState
    @State private var showAddSheet = false

    private var weekStart: Date {
        WeekCalculator.weekStart(for: .now)
    }

    private var goals: [WeeklyGoal] {
        appState.goalStore.goals(for: appState.currentUserID, weekStart: weekStart)
    }

    private var unfinishedLastWeek: [WeeklyGoal] {
        appState.goalStore.unfinishedFromLastWeek(
            userID: appState.currentUserID,
            currentWeekStart: weekStart
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.tallyCanvas.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        weekCard
                        if !unfinishedLastWeek.isEmpty {
                            carryOverSection
                        }
                        if goals.isEmpty {
                            EmptyStateView(
                                icon: "flag",
                                title: "No goals this week",
                                message: "Set a weekly intention you want to follow through on."
                            )
                            .padding(.top, 40)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(goals) { goal in
                                    GoalRow(goal: goal)
                                }
                            }
                        }
                        Spacer().frame(height: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Goals")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddGoalSheet(weekStart: weekStart)
            }
        }
    }

    private var weekCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("This week")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(weekRangeLabel)
                    .font(.title3.weight(.semibold))
            }
            Spacer()
            let done = goals.filter { $0.completedAt != nil }.count
            Text("\(done)/\(goals.count)")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(done == goals.count && !goals.isEmpty ? Color.tallyAccent : .secondary)
        }
        .padding(16)
        .background(Color.tallyCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var weekRangeLabel: String {
        let end = weekStart.adding(days: 6)
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return "\(fmt.string(from: weekStart)) – \(fmt.string(from: end))"
    }

    private var carryOverSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("From last week", systemImage: "arrow.uturn.forward")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(unfinishedLastWeek) { goal in
                HStack(spacing: 12) {
                    Text(goal.title)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        appState.goalStore.carryForward(goal: goal, to: weekStart)
                    } label: {
                        Text("Carry over")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.tallyAccent.opacity(0.15))
                            .foregroundStyle(Color.tallyAccent)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .background(Color.tallyCard)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }
}

private struct GoalRow: View {
    @Environment(AppState.self) private var appState
    let goal: WeeklyGoal

    private var isDone: Bool { goal.completedAt != nil }

    var body: some View {
        HStack(spacing: 12) {
            CheckboxButton(isChecked: isDone, isEditable: true) {
                appState.goalStore.toggleComplete(goal: goal)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.title)
                    .strikethrough(isDone, color: .secondary)
                    .foregroundStyle(isDone ? .secondary : .primary)
                if goal.carriedFromID != nil {
                    Label("Carried over", systemImage: "arrow.uturn.forward")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(Color.tallyCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .contextMenu {
            Button(role: .destructive) {
                appState.goalStore.delete(goal: goal)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

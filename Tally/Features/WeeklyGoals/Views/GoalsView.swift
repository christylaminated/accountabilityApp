import SwiftUI

/// Flat list of the signed-in user's goals — open goals on top (sorted by
/// nearest deadline, no-deadline at the bottom), completed goals below.
/// Goals persist until done or deleted; no period reset.
struct GoalsView: View {
    @Environment(AppState.self) private var appState
    @State private var showAddSheet = false

    private var openGoals: [Goal] {
        appState.circleStore.openGoals(for: appState.currentUserID)
    }

    private var completedGoals: [Goal] {
        appState.circleStore.goals(for: appState.currentUserID)
            .filter { $0.completedAt != nil }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.tallyCanvas.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if openGoals.isEmpty && completedGoals.isEmpty {
                            EmptyStateView(
                                icon: "flag",
                                title: "No goals yet",
                                message: "Tap + to set something you're working toward."
                            )
                            .padding(.top, 40)
                            .frame(maxWidth: .infinity)
                        } else {
                            if !openGoals.isEmpty {
                                section(title: "Open", count: openGoals.count) {
                                    ForEach(openGoals) { goal in
                                        GoalRow(goal: goal)
                                    }
                                }
                            }
                            if !completedGoals.isEmpty {
                                section(title: "Completed", count: completedGoals.count) {
                                    ForEach(completedGoals) { goal in
                                        GoalRow(goal: goal)
                                    }
                                }
                            }
                        }
                        Spacer().frame(height: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                .refreshable { await appState.refreshCircleData() }
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
                AddGoalSheet()
            }
        }
    }

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            VStack(spacing: 8) {
                content()
            }
        }
    }
}

private struct GoalRow: View {
    @Environment(AppState.self) private var appState
    let goal: Goal

    private var isDone: Bool { goal.completedAt != nil }

    var body: some View {
        HStack(spacing: 12) {
            CheckboxButton(isChecked: isDone, isEditable: true) {
                appState.circleStore.toggleComplete(goal: goal)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.title)
                    .strikethrough(isDone, color: .secondary)
                    .foregroundStyle(isDone ? .secondary : .primary)
                if let label = deadlineLabel {
                    Text(label.text)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(label.color)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(Color.tallyCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .contextMenu {
            Button(role: .destructive) {
                appState.circleStore.delete(goal: goal)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    /// `(text, color)` for a goal's deadline. Skipped entirely for completed
    /// goals — we don't nag about deadlines on things you already finished.
    private var deadlineLabel: (text: String, color: Color)? {
        guard let deadline = goal.deadline, !isDone else { return nil }
        let days = deadline.daysSince(.now)
        if days < 0 {
            return ("Overdue by \(-days) day\(-days == 1 ? "" : "s")", .red)
        }
        if days == 0 {
            return ("Due today", .orange)
        }
        if days == 1 {
            return ("Due tomorrow", Color.tallyAccent)
        }
        if days <= 7 {
            return ("Due in \(days) days", Color.tallyAccent)
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return ("Due \(fmt.string(from: deadline))", .secondary)
    }
}

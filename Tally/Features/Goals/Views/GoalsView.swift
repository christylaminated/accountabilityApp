import SwiftUI

/// Goals at four timescales — Day / Week / Month / Year — switched via a
/// segmented control. Each period has its own past/future navigation and
/// carry-over of unfinished goals from the immediately prior period.
struct GoalsView: View {
    @Environment(\.tallyAccent) private var tallyAccent
    @Environment(AppState.self) private var appState

    @State private var selectedPeriod: GoalPeriod = .week
    /// Offset from the current period (0 = current, -1 = previous, +1 = next).
    /// Reset to 0 whenever `selectedPeriod` changes so a switch lands you on now.
    @State private var periodOffset: Int = 0
    @State private var showAddSheet = false
    @State private var editingGoal: Goal?

    /// Start of the period currently being viewed.
    private var periodStart: Date {
        selectedPeriod.shift(selectedPeriod.startDate(for: .now), by: periodOffset)
    }

    private var isCurrentPeriod: Bool { periodOffset == 0 }

    private var goals: [Goal] {
        appState.personalStore.goals(
            for: appState.currentUserID,
            period: selectedPeriod,
            periodStart: periodStart
        )
    }

    private var unfinishedPrevious: [Goal] {
        appState.personalStore.unfinishedFromPrevious(
            userID: appState.currentUserID,
            period: selectedPeriod,
            currentStart: periodStart
        )
    }

    var body: some View {
        NavigationStack {
            // List (not ScrollView) so goal rows get a native trailing
            // swipe-to-delete. Row chrome stripped to preserve the
            // existing visual: no separators, no list background,
            // matched insets.
            List {
                periodPicker
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                periodCard
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))

                if isCurrentPeriod && !unfinishedPrevious.isEmpty {
                    carryOverSection
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                }

                if goals.isEmpty {
                    EmptyStateView(
                        icon: "flag",
                        title: "No goals for \(selectedPeriod.thisLabel)",
                        message: "Tap + to set your first goal for \(selectedPeriod.thisLabel)."
                    )
                    .padding(.top, 24)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } else {
                    ForEach(goals) { goal in
                        GoalRow(goal: goal)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    appState.personalStore.delete(goal: goal)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    editingGoal = goal
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(tallyAccent)
                            }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.tallyCanvas)
            .refreshable { await appState.refreshCircleData() }
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
                AddGoalSheet(period: selectedPeriod, periodStart: periodStart)
            }
            .sheet(item: $editingGoal) { goal in
                AddGoalSheet(
                    period: goal.period,
                    periodStart: goal.periodStartDate,
                    editing: goal
                )
            }
            .onChange(of: selectedPeriod) { _, _ in
                periodOffset = 0
            }
        }
    }

    // MARK: - Period picker

    private var periodPicker: some View {
        Picker("Period", selection: $selectedPeriod) {
            ForEach(GoalPeriod.allCases, id: \.self) { period in
                Text(period.displayName).tag(period)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Period nav card

    private var periodCard: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { periodOffset -= 1 }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(relativeLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(rangeLabel)
                    .font(.title3.weight(.semibold))
            }
            Spacer()
            let done = goals.filter { $0.completedAt != nil }.count
            Text("\(done)/\(goals.count)")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(
                    done == goals.count && !goals.isEmpty ? tallyAccent : .secondary
                )

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { periodOffset += 1 }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 14)
        .background(Color.tallyCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Carry-over

    private var carryOverSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                "From last \(selectedPeriod.displayName.lowercased())",
                systemImage: "arrow.uturn.forward"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)

            ForEach(unfinishedPrevious) { goal in
                HStack(spacing: 12) {
                    Text(goal.title)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        appState.personalStore.carryForward(goal: goal, to: periodStart)
                    } label: {
                        Text("Carry over")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(tallyAccent.opacity(0.15))
                            .foregroundStyle(tallyAccent)
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

    // MARK: - Labels

    /// "Today / This week / This month / This year" + relative offsets.
    private var relativeLabel: String {
        let n = periodOffset
        switch selectedPeriod {
        case .day:   return offsetLabel(n, singular: "day",   present: "Today",       next: "Tomorrow", prev: "Yesterday")
        case .week:  return offsetLabel(n, singular: "week",  present: "This week",   next: "Next week",  prev: "Last week")
        case .month: return offsetLabel(n, singular: "month", present: "This month",  next: "Next month", prev: "Last month")
        case .year:  return offsetLabel(n, singular: "year",  present: "This year",   next: "Next year",  prev: "Last year")
        }
    }

    private func offsetLabel(
        _ n: Int, singular: String,
        present: String, next: String, prev: String
    ) -> String {
        switch n {
        case 0:  return present
        case 1:  return next
        case -1: return prev
        case let n where n > 1:  return "In \(n) \(singular)s"
        default:                 return "\(-n) \(singular)s ago"
        }
    }

    /// Concrete date range for the selected period.
    private var rangeLabel: String {
        let fmt = DateFormatter()
        switch selectedPeriod {
        case .day:
            fmt.dateFormat = "EEEE, MMM d"
            return fmt.string(from: periodStart)
        case .week:
            fmt.dateFormat = "MMM d"
            let end = periodStart.adding(days: 6)
            return "\(fmt.string(from: periodStart)) – \(fmt.string(from: end))"
        case .month:
            fmt.dateFormat = "MMMM yyyy"
            return fmt.string(from: periodStart)
        case .year:
            fmt.dateFormat = "yyyy"
            return fmt.string(from: periodStart)
        }
    }
}

private struct GoalRow: View {
    @Environment(\.tallyAccent) private var tallyAccent
    @Environment(AppState.self) private var appState
    let goal: Goal

    private var isDone: Bool { goal.completedAt != nil }

    var body: some View {
        HStack(spacing: 12) {
            CheckboxButton(isChecked: isDone, isEditable: true) {
                appState.personalStore.toggleComplete(goal: goal)
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
                appState.personalStore.delete(goal: goal)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

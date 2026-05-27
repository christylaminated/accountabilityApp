import SwiftUI

struct HabitListView: View {
    @Environment(\.tallyAccent) private var tallyAccent
    @Environment(AppState.self) private var appState
    @State private var showAddSheet = false

    private var habits: [Habit] {
        appState.personalStore.habits(for: appState.currentUserID)
    }

    private var doneToday: Int {
        habits.filter { appState.personalStore.isCompleted(habit: $0, on: .now) }.count
    }

    private var allDone: Bool {
        !habits.isEmpty && doneToday == habits.count
    }

    /// "Days you've completed every habit in a row." Equivalent to the
    /// minimum across each habit's individual current streak — if every
    /// habit has streak ≥ K, every habit was done each of the last K days,
    /// which is the same as K consecutive all-done days.
    private var celebrationStreak: Int {
        guard !habits.isEmpty else { return 0 }
        let streaks = habits.map { habit in
            StreakCalculator.currentStreak(
                completions: appState.personalStore.completionDates(habit: habit),
                habitCreatedAt: habit.createdAt
            )
        }
        return streaks.min() ?? 0
    }

    var body: some View {
        NavigationStack {
            Color.tallyCanvas.ignoresSafeArea().overlay(content)
                .navigationTitle("Habits")
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
                    AddHabitSheet()
                }
                // Haptic only on the false→true transition, not on every
                // re-render. Unchecking the final habit silently retracts
                // the celebration — no haptic on the reverse direction.
                .onChange(of: allDone) { wasAllDone, nowAllDone in
                    if nowAllDone && !wasAllDone {
                        #if canImport(UIKit)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        #endif
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if habits.isEmpty {
            EmptyStateView(
                icon: "checkmark.circle",
                title: "No habits yet",
                message: "Add your first daily habit to start tracking."
            )
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    if allDone {
                        HabitCelebrationView(streakCount: celebrationStreak)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    progressCard
                    ForEach(habits) { habit in
                        HabitRowView(habit: habit)
                    }
                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                // Scoped to allDone so unrelated state changes (sheet
                // dismissals, habit additions) don't ride the same animation.
                .animation(.easeInOut(duration: 0.3), value: allDone)
            }
        }
    }

    private var progressCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Today")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(doneToday) of \(habits.count) done")
                    .font(.title3.weight(.semibold))
            }
            Spacer()
            ProgressGauge(value: habits.isEmpty ? 0 : Double(doneToday) / Double(habits.count))
        }
        .padding(16)
        .background(Color.tallyCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct ProgressGauge: View {
    @Environment(\.tallyAccent) private var tallyAccent
    let value: Double
    var body: some View {
        ZStack {
            Circle()
                .stroke(tallyAccent.opacity(0.15), lineWidth: 6)
            Circle()
                .trim(from: 0, to: value)
                .stroke(tallyAccent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring, value: value)
            Text("\(Int(value * 100))%")
                .font(.caption.monospacedDigit().weight(.semibold))
        }
        .frame(width: 56, height: 56)
    }
}

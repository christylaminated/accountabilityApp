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
            emptyState
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
        VStack(alignment: .leading, spacing: 10) {
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
            // Subtext only when no habit is done yet today. Once any
            // progress exists the ring carries the message; once all
            // done the inline celebration takes over.
            if doneToday == 0 {
                Text("If you were the person you want to be, what would you do today?")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.tallyTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Color.tallyCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// Empty state when the user has zero habits. Lives inline (rather
    /// than reusing the generic EmptyStateView) so the call-to-action
    /// can route through `showAddSheet` and the copy can be punchy
    /// without the icon + tagline scaffolding.
    private var emptyState: some View {
        VStack(spacing: 24) {
            Text("If you were the person you want to be, what would you do daily?")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.tallyTextPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
            Button {
                showAddSheet = true
            } label: {
                Label("Add your first habit", systemImage: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.tallyAccent)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

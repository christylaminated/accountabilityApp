import SwiftUI

struct HabitListView: View {
    @Environment(\.tallyAccent) private var tallyAccent
    @Environment(AppState.self) private var appState
    @State private var showAddSheet = false
    @State private var editingHabit: Habit?

    private var habits: [Habit] {
        appState.personalStore.habits(for: appState.currentUserID)
    }

    private var doneToday: Int {
        habits.filter { appState.personalStore.isCompleted(habit: $0, on: .now) }.count
    }

    private var allDone: Bool {
        !habits.isEmpty && doneToday == habits.count
    }

    /// Subtext shown beneath the progress card's count line. Ratchets
    /// across three states so the user feels the day move forward.
    private var progressSubtext: String {
        if doneToday == 0 {
            return "If you were the person you want to be, what would you do today?"
        } else if doneToday < habits.count {
            return "Do what your dream self would do."
        } else {
            return "Your future self will thank you."
        }
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
                .sheet(item: $editingHabit) { habit in
                    AddHabitSheet(editing: habit)
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
            // List (not ScrollView) so habit rows get native trailing
            // swipe actions for Archive + Delete. Row chrome is stripped
            // back to nothing (no separators, no list background, no
            // padded insets) so the page reads exactly like the previous
            // ScrollView layout.
            List {
                if allDone {
                    HabitCelebrationView(streakCount: celebrationStreak)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 6, trailing: 16))
                }
                progressCard
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 6, trailing: 16))

                ForEach(habits) { habit in
                    HabitRowView(habit: habit)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 6, trailing: 16))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                appState.personalStore.delete(habit: habit)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                appState.personalStore.archive(habit: habit)
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                            .tint(Color.tallyTextSecondary)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                editingHabit = habit
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(tallyAccent)
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.tallyCanvas)
            .animation(.easeInOut(duration: 0.3), value: allDone)
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
            // One subtext line per progress state, ratcheting from
            // aspirational ("if you were the person…") through nudge
            // ("dream self") to gratitude ("future self will thank
            // you"). Same type style across all three so the card
            // doesn't visually shift on each tick.
            Text(progressSubtext)
                .font(.system(size: 14))
                .foregroundStyle(Color.tallyTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
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

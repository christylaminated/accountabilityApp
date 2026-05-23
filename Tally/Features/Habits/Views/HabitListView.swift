import SwiftUI

struct HabitListView: View {
    @Environment(AppState.self) private var appState
    @State private var showAddSheet = false
    @State private var showCelebration = false

    private var habits: [Habit] {
        appState.personalStore.habits(for: appState.currentUserID)
    }

    private var doneToday: Int {
        habits.filter { appState.personalStore.isCompleted(habit: $0, on: .now) }.count
    }

    private var allDone: Bool {
        !habits.isEmpty && doneToday == habits.count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.tallyCanvas.ignoresSafeArea()
                if habits.isEmpty {
                    EmptyStateView(
                        icon: "checkmark.circle",
                        title: "No habits yet",
                        message: "Add your first daily habit to start tracking."
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            progressCard
                            ForEach(habits) { habit in
                                HabitRowView(habit: habit)
                            }
                            Spacer().frame(height: 24)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }
                }

                if showCelebration {
                    HabitCelebrationView()
                        .transition(.opacity.combined(with: .scale))
                        .zIndex(10)
                }
            }
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
            .onChange(of: doneToday) { _, _ in
                if allDone {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                        showCelebration = true
                    }
                    #if canImport(UIKit)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    #endif
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                        withAnimation { showCelebration = false }
                    }
                }
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
    let value: Double
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.tallyAccent.opacity(0.15), lineWidth: 6)
            Circle()
                .trim(from: 0, to: value)
                .stroke(Color.tallyAccent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring, value: value)
            Text("\(Int(value * 100))%")
                .font(.caption.monospacedDigit().weight(.semibold))
        }
        .frame(width: 56, height: 56)
    }
}

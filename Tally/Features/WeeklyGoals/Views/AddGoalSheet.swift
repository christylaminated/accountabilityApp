import SwiftUI

struct AddGoalSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let period: GoalPeriod
    let periodStart: Date

    @State private var title: String = ""

    private var trimmed: String {
        title.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal for \(period.thisLabel)") {
                    TextField(placeholder, text: $title, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .navigationTitle("New \(period.displayName.lowercased()) goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard !trimmed.isEmpty else { return }
                        appState.personalStore.addGoal(
                            title: trimmed,
                            for: appState.currentUserID,
                            period: period,
                            periodStart: periodStart
                        )
                        dismiss()
                    }
                    .disabled(trimmed.isEmpty)
                }
            }
        }
    }

    /// Period-appropriate placeholder so the example matches the timescale.
    private var placeholder: String {
        switch period {
        case .day:   return "e.g. Finish the report"
        case .week:  return "e.g. Run three times"
        case .month: return "e.g. Read two books"
        case .year:  return "e.g. Run a half-marathon"
        }
    }
}

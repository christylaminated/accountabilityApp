import SwiftUI

struct AddGoalSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let weekStart: Date
    @State private var title: String = ""

    private var trimmed: String {
        title.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal for this week") {
                    TextField("e.g. Finish 'Atomic Habits'", text: $title, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .navigationTitle("New goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard !trimmed.isEmpty else { return }
                        appState.goalStore.add(
                            title: trimmed,
                            for: appState.currentUserID,
                            weekStart: weekStart
                        )
                        dismiss()
                    }
                    .disabled(trimmed.isEmpty)
                }
            }
        }
    }
}

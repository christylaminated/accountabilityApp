import SwiftUI

struct AddHabitSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""

    private var trimmed: String {
        title.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Habit") {
                    TextField("e.g. Read 30 minutes", text: $title)
                        .autocorrectionDisabled(false)
                }
            }
            .navigationTitle("New habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard !trimmed.isEmpty else { return }
                        appState.circleStore.addHabit(title: trimmed, for: appState.currentUserID)
                        dismiss()
                    }
                    .disabled(trimmed.isEmpty)
                }
            }
        }
    }
}

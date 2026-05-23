import SwiftUI

struct AddGoalSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var setDeadline: Bool = false
    @State private var deadline: Date = .now.adding(days: 7).startOfDay

    private var trimmed: String {
        title.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal") {
                    TextField("e.g. Finish 'Atomic Habits'", text: $title, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section {
                    Toggle("Set deadline", isOn: $setDeadline.animation())
                    if setDeadline {
                        DatePicker(
                            "Deadline",
                            selection: $deadline,
                            in: Date.now.startOfDay...,
                            displayedComponents: .date
                        )
                    }
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
                        appState.circleStore.addGoal(
                            title: trimmed,
                            for: appState.currentUserID,
                            deadline: setDeadline ? deadline.startOfDay : nil
                        )
                        dismiss()
                    }
                    .disabled(trimmed.isEmpty)
                }
            }
        }
    }
}

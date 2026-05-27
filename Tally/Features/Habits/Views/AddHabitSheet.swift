import SwiftUI

struct AddHabitSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var isPrivate: Bool = false

    private var trimmed: String {
        title.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Habit") {
                    TextField("What would your dream self do daily?", text: $title)
                        .autocorrectionDisabled(false)
                }
                Section {
                    Toggle("Private", isOn: $isPrivate)
                } footer: {
                    Text("Private habits stay on your devices only — friends won't see them. They still count toward your streaks.")
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
                        appState.personalStore.addHabit(
                            title: trimmed,
                            for: appState.currentUserID,
                            privacy: isPrivate ? .private : .shared
                        )
                        dismiss()
                    }
                    .disabled(trimmed.isEmpty)
                }
            }
        }
    }
}

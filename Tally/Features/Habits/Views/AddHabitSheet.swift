import SwiftUI

struct AddHabitSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    /// When non-nil, the sheet edits this habit instead of creating a new one.
    let editing: Habit?

    @State private var title: String
    @State private var isPrivate: Bool

    init(editing: Habit? = nil) {
        self.editing = editing
        _title = State(initialValue: editing?.title ?? "")
        _isPrivate = State(initialValue: editing?.privacy == .private)
    }

    private var trimmed: String {
        title.trimmingCharacters(in: .whitespaces)
    }

    private var isEditing: Bool { editing != nil }

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
            .navigationTitle(isEditing ? "Edit habit" : "New habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") {
                        guard !trimmed.isEmpty else { return }
                        let privacy: HabitPrivacy = isPrivate ? .private : .shared
                        if let editing {
                            appState.personalStore.updateHabit(
                                editing,
                                title: trimmed,
                                privacy: privacy
                            )
                        } else {
                            appState.personalStore.addHabit(
                                title: trimmed,
                                for: appState.currentUserID,
                                privacy: privacy
                            )
                        }
                        dismiss()
                    }
                    .disabled(trimmed.isEmpty)
                }
            }
        }
    }
}

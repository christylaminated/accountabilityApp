import SwiftUI

struct DayDetailView: View {
    @Environment(\.tallyAccent) private var tallyAccent
    @Environment(AppState.self) private var appState
    let date: Date
    let userID: String

    // Private per-day note state. Only shown/edited on the user's OWN history —
    // the note lives in their private zone and would be meaningless (and a
    // privacy leak) on a friend's history screen.
    @State private var noteText: String = ""
    @State private var loadedNoteText: String = ""
    @State private var noteSaveFailed = false
    @State private var showSaved = false
    @FocusState private var noteFocused: Bool

    private var isOwnHistory: Bool { userID == appState.currentUserID }

    /// True when the field holds edits not yet written — drives the Save button.
    private var noteChanged: Bool {
        noteText.trimmingCharacters(in: .whitespacesAndNewlines) != loadedNoteText
    }

    private var habits: [Habit] {
        appState.personalStore.habits(for: userID).filter {
            $0.createdAt.startOfDay <= date.startOfDay
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(date, format: .dateTime.weekday(.wide).month().day())
                .font(.headline)

            if habits.isEmpty {
                Text("No habits tracked yet on this day")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(habits) { habit in
                    HStack(spacing: 10) {
                        Image(systemName: appState.personalStore.isCompleted(habit: habit, on: date)
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(appState.personalStore.isCompleted(habit: habit, on: date)
                                             ? tallyAccent : .secondary)
                        Text(habit.title)
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
            }

            if isOwnHistory {
                noteSection
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tallyCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        // Reload whenever the selected day changes (the view is reused).
        .task(id: date.startOfDay) {
            guard isOwnHistory else { return }
            let text = await appState.dayNote(for: date)?.text ?? ""
            noteText = text
            loadedNoteText = text
            noteSaveFailed = false
            showSaved = false
        }
        // Safety net only: persist unsaved edits if the detail disappears. The
        // Save button is the primary path (focus-loss isn't reliable with a
        // hardware keyboard, where Return inserts a newline instead of ending
        // editing).
        .onDisappear { persistNoteIfChanged() }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().padding(.vertical, 4)
            HStack(spacing: 6) {
                Image(systemName: "note.text")
                    .font(.subheadline)
                    .foregroundStyle(tallyAccent)
                Text("Note")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if noteSaveFailed {
                    Text("Not saved")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.tallyDestructive)
                } else if showSaved {
                    Label("Saved", systemImage: "checkmark")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            TextField("Write a note for this day…", text: $noteText, axis: .vertical)
                .lineLimit(5...14)
                .focused($noteFocused)
                .font(.subheadline)
                .frame(minHeight: 120, alignment: .topLeading)
                .padding(10)
                .background(Color.tallyCanvas)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                // Any edit clears the "Saved"/"Not saved" flags.
                .onChange(of: noteText) { _, _ in
                    showSaved = false
                    noteSaveFailed = false
                }

            Button {
                noteFocused = false
                persistNoteIfChanged(confirm: true)
            } label: {
                Text("Save note")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .foregroundStyle(noteChanged ? Color.tallyOnAccent : Color.tallyTextSecondary)
                    .background(noteChanged ? tallyAccent : Color.tallyCanvas)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(!noteChanged)
        }
    }

    /// Save only when the text actually changed, so re-selecting a day or
    /// leaving without edits doesn't hit CloudKit needlessly. `confirm` shows
    /// the "Saved" acknowledgement (used by the explicit Save button).
    private func persistNoteIfChanged(confirm: Bool = false) {
        guard isOwnHistory else { return }
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != loadedNoteText else {
            if confirm { showSaved = true }
            return
        }
        loadedNoteText = trimmed
        let day = date
        Task {
            let ok = await appState.saveDayNote(trimmed, for: day)
            noteSaveFailed = !ok
            if ok && confirm { showSaved = true }
        }
    }
}

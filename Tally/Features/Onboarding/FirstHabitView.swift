import SwiftUI

/// Screen 2 of the paywalled onboarding flow — the first habit.
///
/// Required (not skippable) by design: this is the load-bearing artifact
/// the user takes through the paywall. "I already made something" makes
/// the paywall feel like a continuation of the work they started rather
/// than a tollbooth. On submit the habit is saved immediately via
/// `AppState.completeFirstHabitEntry` (which writes a real Habit record
/// to the personal zone), and the flow advances to `.firstGoalEntry`.
struct FirstHabitView: View {
    @Environment(AppState.self) private var appState

    @State private var title: String = ""

    private var displayName: String {
        appState.ownCloudProfile?.displayName ?? ""
    }

    private var trimmed: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool { !trimmed.isEmpty && trimmed.count <= 100 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                titleField
                Spacer().frame(height: 8)
                submitButton
                Spacer().frame(height: 24)
            }
            .padding(.horizontal, 24)
            .padding(.top, 72)
        }
        .background(Color.tallyCanvas)
        .scrollDismissesKeyboard(.interactively)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Let's add your first habit, \(displayName).")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(Color.tallyTextPrimary)
            Text("If you were the person you want to be, what would your habits be?")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.tallyTextSecondary)
        }
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("e.g. Read 20 min", text: $title)
                .autocorrectionDisabled(false)
                .padding(14)
                .background(Color.tallyCard)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text("You can edit this later.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var submitButton: some View {
        Button {
            guard isValid else { return }
            appState.completeFirstHabitEntry(title: trimmed)
        } label: {
            Text("Continue")
                .font(.system(.body, design: .rounded, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(isValid ? Color.tallyAccent : Color.tallyTextSecondary.opacity(0.3))
                .foregroundStyle(Color.tallyOnAccent)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(!isValid)
    }
}

import SwiftUI

/// Screen 1 of the paywalled onboarding flow.
///
/// Collects just the display name — no username, no avatar, no theme.
/// Those land in screen 5 (ProfileCustomizationView). Keeping screen 1
/// minimal makes the first interaction as cheap as possible and earns
/// the right to ask for more later.
///
/// On submit, `AppState.completeDisplayNameEntry` saves the profile via
/// `ProfileRepository` (UserProfile + PersonalRoot), populates
/// `currentUserID` if it isn't already set, and advances to
/// `.firstHabitEntry`. From this screen forward every onboarding screen
/// displays the user's name in its headline.
struct NameEntryView: View {
    @Environment(AppState.self) private var appState

    @State private var name: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        !trimmed.isEmpty && trimmed.count <= 50
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                nameField

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Color.tallyDestructive)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

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
            Text("Welcome to Tally")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(Color.tallyTextPrimary)
            Text("What should we call you?")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.tallyTextSecondary)
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your name")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("e.g. Christy", text: $name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(false)
                .padding(14)
                .background(Color.tallyCard)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var submitButton: some View {
        Button(action: submit) {
            HStack(spacing: 8) {
                if isSubmitting {
                    ProgressView().tint(Color.tallyOnAccent)
                }
                Text(isSubmitting ? "Saving…" : "Continue")
                    .font(.system(.body, design: .rounded, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                isValid && !isSubmitting
                ? Color.tallyAccent
                : Color.tallyTextSecondary.opacity(0.3)
            )
            .foregroundStyle(Color.tallyOnAccent)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(!isValid || isSubmitting)
    }

    private func submit() {
        guard isValid, !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                try await appState.completeDisplayNameEntry(displayName: trimmed)
            } catch {
                errorMessage = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}

import SwiftUI

/// First-launch profile setup. Takes a display name + avatar emoji and hands the
/// pair off to a parent-supplied async closure (typically `AppState.saveProfile`).
/// On success, parent transitions onboarding state — this view doesn't dismiss
/// itself; the state machine drives navigation.
struct ProfileSetupView: View {
    /// Invoked when the user taps Continue with valid input.
    /// Throws so failures (network, CloudKit) surface back in this view.
    let onSubmit: (String, String) async throws -> Void

    @State private var displayName: String = ""
    @State private var emoji: String = "🌿"
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private static let emojiChoices: [String] = [
        "🌿", "☕", "🔥", "🌊", "🌙", "✨",
        "🍃", "🎯", "🧘", "💪", "📚", "🌸"
    ]

    private var trimmedName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        !trimmedName.isEmpty && trimmedName.count <= 50
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                nameField
                emojiPicker

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                submitButton

                Spacer().frame(height: 24)
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
        }
        .background(Color.tallyCanvas)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("Welcome to Tally")
                .font(.largeTitle.weight(.bold))
            Text("Pick a name and emoji your partner will see.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your name")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("e.g. Christy", text: $displayName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(false)
                .padding(14)
                .background(Color.tallyCard)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var emojiPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Avatar emoji")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            let columns = Array(
                repeating: GridItem(.flexible(), spacing: 8),
                count: 6
            )
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Self.emojiChoices, id: \.self) { choice in
                    Button {
                        emoji = choice
                    } label: {
                        Text(choice)
                            .font(.title)
                            .frame(width: 48, height: 48)
                            .background(
                                emoji == choice
                                ? Color.tallyAccent.opacity(0.2)
                                : Color.tallyCard
                            )
                            .clipShape(Circle())
                            .overlay(
                                Circle().stroke(
                                    emoji == choice ? Color.tallyAccent : .clear,
                                    lineWidth: 2
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var submitButton: some View {
        Button(action: submit) {
            HStack(spacing: 8) {
                if isSubmitting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }
                Text(isSubmitting ? "Saving…" : "Continue")
                    .font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                isValid && !isSubmitting
                ? Color.tallyAccent
                : Color.gray.opacity(0.3)
            )
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!isValid || isSubmitting)
    }

    private func submit() {
        guard isValid, !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                try await onSubmit(trimmedName, emoji)
                // Parent will transition state; this view goes away.
            } catch {
                errorMessage = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}

import SwiftUI

/// First-launch profile setup. Takes a display name + an SF Symbol avatar and
/// hands the pair to a parent-supplied async closure (typically `AppState.saveProfile`).
struct ProfileSetupView: View {
    /// Invoked with `(displayName, avatarSymbol)`. Throws so failures surface here.
    let onSubmit: (String, String) async throws -> Void

    @State private var displayName: String = ""
    @State private var avatarSymbol: String = "leaf"
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    /// Curated, Lucide-feeling SF Symbol options. Intentionally generic — not
    /// activity-specific — so they fit any user.
    private static let symbolChoices: [String] = [
        "leaf", "mountain.2", "flame", "drop",
        "moon", "sparkle", "book", "pencil",
        "target", "heart", "star", "sun.max"
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
                symbolPicker

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(.footnote, design: .rounded))
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
        .scrollDismissesKeyboard(.interactively)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text("Welcome to Tally")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
            Text("Pick a name and an icon your partner will see.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your name")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("e.g. Christy", text: $displayName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(false)
                .padding(14)
                .background(Color.tallyCard)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var symbolPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your icon")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
            let columns = Array(
                repeating: GridItem(.flexible(), spacing: 10),
                count: 6
            )
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Self.symbolChoices, id: \.self) { choice in
                    Button {
                        avatarSymbol = choice
                    } label: {
                        Image(systemName: choice)
                            .font(.system(size: 20, weight: .medium))
                            .frame(width: 52, height: 52)
                            .foregroundStyle(
                                avatarSymbol == choice ? Color.tallyAccent : Color.secondary
                            )
                            .background(
                                avatarSymbol == choice
                                ? Color.tallyAccent.opacity(0.18)
                                : Color.tallyCard
                            )
                            .clipShape(Circle())
                            .overlay(
                                Circle().stroke(
                                    avatarSymbol == choice ? Color.tallyAccent : .clear,
                                    lineWidth: 1.5
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
                    .font(.system(.body, design: .rounded, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                isValid && !isSubmitting
                ? Color.tallyAccent
                : Color.gray.opacity(0.3)
            )
            .foregroundStyle(.white)
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
                try await onSubmit(trimmedName, avatarSymbol)
            } catch {
                errorMessage = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}

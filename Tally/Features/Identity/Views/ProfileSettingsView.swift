import SwiftUI

/// Profile + appearance settings. Edit name, username, avatar, and the app's
/// theme. Name/avatar/username save to CloudKit; theme is local-only and
/// applies the moment a swatch is tapped — no save button needed.
struct ProfileSettingsView: View {
    @Environment(\.tallyAccent) private var tallyAccent
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String = ""
    @State private var avatarSymbol: String = "leaf"
    @State private var username: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    /// Same set as `ProfileSetupView` so onboarding and editing match.
    private static let symbolChoices: [String] = [
        "leaf", "mountain.2", "flame", "drop",
        "moon", "sparkle", "book", "pencil",
        "target", "heart", "star", "sun.max"
    ]

    private var trimmedName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Username is OK to save if empty (clears it) OR it satisfies the
    /// normalization rules (3–20 chars, letters/digits/underscore).
    private var usernameValid: Bool {
        trimmedUsername.isEmpty ||
            appState.usernameRepository.normalize(trimmedUsername) != nil
    }

    private var isValid: Bool {
        !trimmedName.isEmpty && trimmedName.count <= 50 && usernameValid
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Your name") {
                    TextField("Name", text: $displayName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(false)
                }

                Section {
                    HStack {
                        Text("@").foregroundStyle(.secondary)
                        TextField("username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                    }
                } header: {
                    Text("Username")
                } footer: {
                    Text("3–20 characters: letters, numbers, or underscores. Your username is how friends find you to send a request.")
                }

                Section("Your icon") {
                    symbolGrid
                        .padding(.vertical, 8)
                }

                Section("Theme") {
                    themeSwatchRow
                        .padding(.vertical, 8)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Color.tallyDestructive)
                    }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                    .disabled(!isValid || isSaving)
                }
            }
            .onAppear { loadFromAppState() }
        }
    }

    // MARK: - Pickers

    private var symbolGrid: some View {
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 10),
            count: 6
        )
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Self.symbolChoices, id: \.self) { choice in
                Button {
                    avatarSymbol = choice
                } label: {
                    Image(systemName: choice)
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(
                            avatarSymbol == choice ? tallyAccent : Color.secondary
                        )
                        .background(
                            avatarSymbol == choice
                            ? tallyAccent.opacity(0.18)
                            : Color.clear
                        )
                        .clipShape(Circle())
                        .overlay(
                            Circle().stroke(
                                avatarSymbol == choice ? tallyAccent : .clear,
                                lineWidth: 1.5
                            )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Four swatches — one per `TallyTheme`. Tap immediately switches the
    /// whole app (no save needed; theme is local state, not server state).
    /// The current selection gets a thick accent-colored ring; others stay
    /// flat. The fill is the theme's accent color so the swatch previews
    /// what the user will see.
    private var themeSwatchRow: some View {
        HStack(spacing: 18) {
            ForEach(TallyTheme.allCases) { theme in
                themeSwatch(theme)
            }
            Spacer()
        }
    }

    private func themeSwatch(_ theme: TallyTheme) -> some View {
        let isSelected = appState.theme == theme
        return Button {
            appState.setTheme(theme)
        } label: {
            VStack(spacing: 6) {
                Circle()
                    .fill(theme.accent)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Circle()
                            .stroke(Color.tallyTextPrimary,
                                    lineWidth: isSelected ? 2.5 : 0)
                            .padding(-4)
                    )
                    .overlay(
                        Group {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                    )
                Text(theme.displayName)
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.tallyTextPrimary : Color.tallyTextSecondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.displayName)
    }

    // MARK: - Lifecycle

    private func loadFromAppState() {
        displayName = appState.ownCloudProfile?.displayName ?? ""
        avatarSymbol = appState.ownCloudProfile?.avatarSymbol ?? "leaf"
        username = appState.ownCloudProfile?.username ?? ""
        // Theme isn't loaded here — it's already live via ThemeManager and
        // the swatch reads appState.theme directly.
    }

    private func save() async {
        guard isValid, !isSaving else { return }
        isSaving = true
        errorMessage = nil

        do {
            try await appState.updateProfile(
                displayName: trimmedName,
                avatarSymbol: avatarSymbol,
                username: trimmedUsername.isEmpty ? nil : trimmedUsername
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }
}

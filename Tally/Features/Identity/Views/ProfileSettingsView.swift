import SwiftUI

/// Profile + appearance settings. Edit name, username, avatar, and the app's
/// accent color. Saves name + avatar + username to CloudKit (name/avatar go
/// in the personal zone so friends see them; username goes in the public DB
/// so people can find you by it). Theme color is a local preference.
struct ProfileSettingsView: View {
    @Environment(\.tallyAccent) private var tallyAccent
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String = ""
    @State private var avatarSymbol: String = "leaf"
    @State private var username: String = ""
    @State private var themeColor: ThemeColor = .pink
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

                Section("App color") {
                    colorRow
                        .padding(.vertical, 4)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
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
                            avatarSymbol == choice ? themeColor.color : Color.secondary
                        )
                        .background(
                            avatarSymbol == choice
                            ? themeColor.color.opacity(0.18)
                            : Color.clear
                        )
                        .clipShape(Circle())
                        .overlay(
                            Circle().stroke(
                                avatarSymbol == choice ? themeColor.color : .clear,
                                lineWidth: 1.5
                            )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var colorRow: some View {
        HStack(spacing: 14) {
            ForEach(ThemeColor.allCases, id: \.self) { choice in
                Button {
                    themeColor = choice
                } label: {
                    Circle()
                        .fill(choice.color)
                        .frame(width: 30, height: 30)
                        .overlay(
                            Circle()
                                .stroke(
                                    themeColor == choice ? Color.primary : Color.clear,
                                    lineWidth: 2
                                )
                                .padding(-3)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(choice.displayName)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Lifecycle

    private func loadFromAppState() {
        displayName = appState.ownCloudProfile?.displayName ?? ""
        avatarSymbol = appState.ownCloudProfile?.avatarSymbol ?? "leaf"
        username = appState.ownCloudProfile?.username ?? ""
        themeColor = appState.themeColor
    }

    private func save() async {
        guard isValid, !isSaving else { return }
        isSaving = true
        errorMessage = nil

        // Theme change is local-only and instant; apply first so the rest of
        // the app reflects the new color before we dismiss.
        appState.setThemeColor(themeColor)

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

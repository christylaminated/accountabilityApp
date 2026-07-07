import SwiftUI

/// Onboarding step between profile setup and habits: create the Circle that will
/// hold this user's shared accountability data. Friends are invited later from
/// the dashboard — or, if a friend already sent an invite link, tapping it joins
/// their Circle and skips past this screen automatically.
struct CircleSetupView: View {
    @Environment(\.tallyAccent) private var tallyAccent
    @Environment(AppState.self) private var appState

    /// Invoked with the chosen Circle name. Throws so failures surface here.
    let onCreate: (String) async throws -> Void

    @State private var name: String = ""
    @State private var isCreating = false
    @State private var errorMessage: String?

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        !trimmed.isEmpty && trimmed.count <= 50
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                nameField

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Color.tallyDestructive)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                createButton
                inviteNote
                Spacer().frame(height: 24)
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)
        }
        .background(Color.tallyCanvas)
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            if name.isEmpty, let first = firstName {
                name = "\(first)'s Circle"
            }
        }
    }

    private var firstName: String? {
        appState.ownCloudProfile?.displayName
            .split(separator: " ").first.map(String.init)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2.circle.fill")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(tallyAccent)
            Text("Create your Circle")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
            Text("A Circle is the shared space where you and your friends see each other's habits and check-ins. You can invite people once you're in.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Circle name")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("e.g. Gym buddies", text: $name)
                .textInputAutocapitalization(.words)
                .padding(14)
                .background(Color.tallyCard)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var createButton: some View {
        Button(action: create) {
            HStack(spacing: 8) {
                if isCreating {
                    ProgressView().progressViewStyle(.circular).tint(Color.tallyOnAccent)
                }
                Text(isCreating ? "Creating…" : "Create Circle")
                    .font(.system(.body, design: .rounded, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isValid && !isCreating ? tallyAccent : Color.tallyTextSecondary.opacity(0.3))
            .foregroundStyle(Color.tallyOnAccent)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(!isValid || isCreating)
    }

    private var inviteNote: some View {
        Text("Got an invite from a friend? Just tap the link they sent — it'll bring you straight into their Circle.")
            .font(.system(.footnote, design: .rounded))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 320)
    }

    private func create() {
        guard isValid, !isCreating else { return }
        isCreating = true
        errorMessage = nil
        Task {
            do {
                try await onCreate(trimmed)
                // Parent transitions onboarding state; this view goes away.
            } catch {
                errorMessage = error.localizedDescription
                isCreating = false
            }
        }
    }
}

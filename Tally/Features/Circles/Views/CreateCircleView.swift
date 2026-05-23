import SwiftUI
import CloudKit

/// Create a Circle. On success, hand the new Circle back to the caller via
/// `onCreate` and dismiss — the parent then drives the invite presentation
/// (after this sheet has finished animating away, so UIKit's modal stack is
/// clear for `UICloudSharingController`).
struct CreateCircleView: View {
    @Environment(\.tallyAccent) private var tallyAccent
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    /// Called with the freshly-created Circle. Parent should remember it and
    /// present the invite sheet in its own `.sheet` `onDismiss`.
    let onCreate: (TallyCircle) -> Void

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
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 10) {
                        Image(systemName: "person.2.circle.fill")
                            .font(.system(size: 52, weight: .light))
                            .foregroundStyle(tallyAccent)
                        Text("Start a Circle")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                        Text("Name it, then send your partner the invite link. They tap it and they're in.")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 320)
                    }
                    .padding(.top, 24)

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

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(action: create) {
                        HStack(spacing: 8) {
                            if isCreating {
                                ProgressView().progressViewStyle(.circular).tint(.white)
                            }
                            Text(isCreating ? "Creating…" : "Create & invite")
                                .font(.system(.body, design: .rounded, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(isValid && !isCreating ? tallyAccent : Color.gray.opacity(0.3))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(!isValid || isCreating)

                    Spacer()
                }
                .padding(.horizontal, 24)
            }
            .background(Color.tallyCanvas)
            .navigationTitle("New Circle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func create() {
        guard isValid, !isCreating else { return }
        isCreating = true
        errorMessage = nil
        Task {
            do {
                let circle = try await appState.createCircle(name: trimmed, emoji: nil)
                onCreate(circle)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isCreating = false
            }
        }
    }
}

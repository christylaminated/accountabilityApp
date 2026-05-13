import SwiftUI

/// Root view. Switches on `AppState.onboardingState`:
///   • .checkingICloud      → loading spinner
///   • .needsSignIn(reason) → ICloudStatusGate
///   • .needsProfileSetup   → ProfileSetupView
///   • .ready               → MainTabView
///   • .error(message)      → recoverable error screen with Retry
///
/// Also re-checks account state when the scene returns to active, so signing
/// into iCloud in Settings and coming back here progresses the gate.
struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch appState.onboardingState {
            case .checkingICloud:
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Checking iCloud…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.tallyCanvas)

            case .needsSignIn(let reason):
                ICloudStatusGate(reason: reason) {
                    Task { await appState.refreshAccountState() }
                }

            case .needsProfileSetup:
                ProfileSetupView { name, emoji in
                    try await appState.saveProfile(displayName: name, avatarEmoji: emoji)
                }

            case .ready:
                MainTabView()

            case .error(let message):
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                    Text("Something went wrong")
                        .font(.title3.weight(.semibold))
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button("Try again") {
                        Task { await appState.refreshAccountState() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.tallyAccent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.tallyCanvas)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await appState.refreshAccountState() }
            }
        }
    }
}

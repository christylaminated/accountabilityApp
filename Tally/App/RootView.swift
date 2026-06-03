import SwiftUI

/// Root view. Switches on `AppState.onboardingState`:
///   • .checkingICloud          → loading spinner
///   • .needsSignIn(reason)     → ICloudStatusGate
///   • .displayNameEntry        → name entry (placeholder; commit c)
///   • .firstHabitEntry         → first habit (placeholder; commit c)
///   • .firstGoalEntry          → first goal (placeholder; commit c)
///   • .leaderboardPreview      → leaderboard preview (placeholder; commit c)
///   • .profileCustomization    → username + avatar + theme (placeholder; commit c)
///   • .paywall                 → paywall (placeholder; commit d)
///   • .celebration             → celebration (placeholder; commit d)
///   • .enteredMainApp          → MainTabView
///   • .error(message)          → recoverable error screen with Retry
///
/// Re-checks account state when scene returns to active so signing into iCloud
/// in Settings and coming back here progresses the gate automatically.
struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch appState.onboardingState {
            case .checkingICloud:
                LoadingScreen(label: "Checking iCloud…")

            case .needsSignIn(let reason):
                ICloudStatusGate(reason: reason) {
                    Task { await appState.refreshAccountState() }
                }

            case .displayNameEntry:
                NameEntryView()
                    .transition(.opacity)

            case .firstHabitEntry:
                FirstHabitView()
                    .transition(.opacity)

            case .firstGoalEntry:
                FirstGoalView()
                    .transition(.opacity)

            case .leaderboardPreview:
                LeaderboardPreviewView()
                    .transition(.opacity)

            case .profileCustomization:
                ProfileCustomizationView()
                    .transition(.opacity)

            case .paywall:
                PaywallView()
                    .transition(.opacity)

            case .celebration:
                CelebrationView()
                    .transition(.opacity)

            case .enteredMainApp:
                MainTabView()
                    .transition(.opacity)

            case .error(let message):
                ErrorScreen(message: message) {
                    Task { await appState.refreshAccountState() }
                }
            }
        }
        // Root background is theme-aware so every onboarding step + the
        // main tab view sit on the chosen palette's canvas. No more
        // system-grouped-background gray underneath.
        .background(Color.tallyCanvas.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.25), value: appState.onboardingState)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await appState.refreshAccountState()
                    await appState.refreshCircleData()
                }
            }
        }
    }
}

private struct LoadingScreen: View {
    let label: String
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(label)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.tallyCanvas)
    }
}

private struct ErrorScreen: View {
    let message: String
    let onRetry: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(Color.tallyTextSecondary)
            Text("Something went wrong")
                .font(.system(.title3, weight: .semibold))
                .foregroundStyle(Color.tallyTextPrimary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.tallyTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try again", action: onRetry)
                .buttonStyle(.borderedProminent)
                .tint(Color.tallyAccent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.tallyCanvas)
    }
}


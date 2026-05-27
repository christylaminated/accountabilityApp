import SwiftUI

/// Root view. Switches on `AppState.onboardingState`:
///   • .checkingICloud      → loading spinner
///   • .needsSignIn(reason) → ICloudStatusGate
///   • .needsProfileSetup   → ProfileSetupView  (name + emoji)
///   • .needsCircleSetup    → CircleSetupView   (create / join a Circle)
///   • .needsHabitsSetup    → HabitsSetupView   (daily habits)
///   • .needsGoalsSetup     → GoalsSetupView    (this week's intentions)
///   • .ready               → MainTabView
///   • .error(message)      → recoverable error screen with Retry
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

            case .needsProfileSetup:
                ProfileSetupView { name, symbol in
                    try await appState.saveProfile(displayName: name, avatarSymbol: symbol)
                }
                .transition(.opacity)

            case .needsCircleSetup:
                CircleSetupView { name in
                    try await appState.setUpInitialCircle(name: name)
                }
                .transition(.opacity)

            case .needsThemePick:
                ThemePickerOnboardingView { chosen in
                    appState.finishThemePick(chosen)
                }
                .transition(.opacity)

            case .needsHabitsSetup:
                HabitsSetupView { titles in
                    appState.saveInitialHabits(titles)
                }
                .transition(.opacity)

            case .needsGoalsSetup:
                GoalsSetupView { titles in
                    appState.saveInitialGoals(titles)
                }
                .transition(.opacity)

            case .ready:
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

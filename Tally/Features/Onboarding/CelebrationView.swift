import SwiftUI

/// Screen 7 — celebration. Confetti + greeting, then auto-advances to
/// `.enteredMainApp` after 2 seconds. Tapping anywhere advances early.
struct CelebrationView: View {
    @Environment(AppState.self) private var appState

    private var displayName: String {
        appState.ownCloudProfile?.displayName ?? ""
    }

    var body: some View {
        ZStack {
            Color.tallyCanvas.ignoresSafeArea()
            ConfettiView()
            VStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(Color.tallyAccent)
                Text("Welcome, \(displayName) —")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.tallyTextPrimary)
                Text("let's lock in.")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.tallyAccent)
                    .padding(.bottom, 8)
                Text("Tap to continue")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.tallyTextSecondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
        }
        .contentShape(Rectangle())
        .onTapGesture { advance() }
        .task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            advance()
        }
    }

    private func advance() {
        // Idempotent: state machine doesn't re-trigger if already past
        // .celebration, but guard anyway so a tap during the 2s sleep
        // doesn't fire completeCelebration twice.
        guard appState.onboardingState == .celebration else { return }
        Task { await appState.completeCelebration() }
    }
}

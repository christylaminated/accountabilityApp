import SwiftUI

@main
struct TallyApp: App {
    /// Bridges to UIKit so we can implement `application(_:userDidAcceptCloudKitShareWith:)`.
    /// The delegate writes incoming invites to `PendingShareBuffer.shared`; AppState
    /// drains that buffer. No environment plumbing needed — the buffer is a singleton.
    @UIApplicationDelegateAdaptor(TallyAppDelegate.self) private var appDelegate

    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                // App-wide rounded design — softer typographic feel without per-view font work.
                .fontDesign(.rounded)
                // Drive root tint from AppState so theme changes from profile
                // settings propagate to every tinted SwiftUI control.
                .tint(appState.accentColor)
        }
    }
}

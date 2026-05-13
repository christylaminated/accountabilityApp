import SwiftUI

@main
struct TallyApp: App {
    /// Bridges to UIKit so we can implement `application(_:userDidAcceptCloudKitShareWith:)`.
    /// The adapter also owns `PendingShareBuffer`, which gets injected into the
    /// SwiftUI environment so `ShareCoordinator` (step 3) can consume incoming invites.
    @UIApplicationDelegateAdaptor(TallyAppDelegate.self) private var appDelegate

    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                // TODO (step 3): Move PendingShareBuffer into AppState; remove this
                // environmentObject injection. Deep links can arrive before AppState
                // is fully initialized, so one source of truth there is cleaner.
                .environmentObject(appDelegate.pendingShares)
                // App-wide rounded design — softer typographic feel without per-view font work.
                .fontDesign(.rounded)
                .tint(.tallyAccent)
        }
    }
}

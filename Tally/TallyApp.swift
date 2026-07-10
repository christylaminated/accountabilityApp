import SwiftUI

@main
struct TallyApp: App {
    /// Bridges to UIKit so we can implement `application(_:userDidAcceptCloudKitShareWith:)`.
    /// The delegate writes incoming invites to `PendingShareBuffer.shared`; AppState
    /// drains that buffer. No environment plumbing needed — the buffer is a singleton.
    @UIApplicationDelegateAdaptor(TallyAppDelegate.self) private var appDelegate

    @State private var appState = TallyApp.makeAppState()
    @State private var themeManager = ThemeManager.shared
    /// Owns the RevenueCat session + entitlement state. Injected into the
    /// environment so downstream views (paywall, subscription gate, banner
    /// dismissals) can read `isSubscribed` and call purchase/restore via a
    /// single abstraction. No other module imports RevenueCat.
    @State private var subscriptionManager = TallyApp.makeSubscriptionManager()

    /// In DEBUG, launching with the `--demo` argument boots a fully-seeded,
    /// editable app for App Store screenshots (see `AppState.demo()`). Always
    /// the normal app in Release.
    @MainActor private static var isDemoLaunch: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--demo")
        #else
        return false
        #endif
    }

    @MainActor private static func makeAppState() -> AppState {
        #if DEBUG
        if isDemoLaunch { return AppState.demo() }
        #endif
        return AppState()
    }

    @MainActor private static func makeSubscriptionManager() -> SubscriptionManager {
        let manager = SubscriptionManager()
        #if DEBUG
        if isDemoLaunch { manager.debugBypassPaywall = true }
        #endif
        return manager
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(subscriptionManager)
                // Carry the whole theme through the environment so views
                // can pattern-match on it (mini-previews, etc.). Most views
                // should just read `Color.tally*` statics — they observe
                // `ThemeManager.shared` directly.
                .environment(\.tallyTheme, themeManager.current)
                // Back-compat: existing views read `\.tallyAccent`. Keep
                // it in sync with the current theme.
                .environment(\.tallyAccent, themeManager.current.accent)
                // Root tint drives SwiftUI controls (segmented pickers,
                // toolbar buttons) so theme changes propagate to them too.
                .tint(themeManager.current.accent)
        }
    }
}

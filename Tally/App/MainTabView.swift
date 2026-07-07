import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MainTabView: View {
    @Environment(AppState.self) private var appState

    /// Identity that changes whenever any visible-on-tab-bar theme value
    /// changes (preset case OR the user-picked accent hex for the Custom
    /// theme). Used as the `value:` on `.onChange` so we re-apply the
    /// `UITabBarAppearance` on theme switches AND on custom-color tweaks.
    private var themeKey: String {
        "\(appState.theme.rawValue)-\(ThemeManager.shared.customAccentHex)"
    }

    var body: some View {
        TabView {
            CircleDashboardView()
                .tabItem { Label("Today", systemImage: "house.fill") }

            HabitListView()
                .tabItem { Label("Habits", systemImage: "checkmark.circle.fill") }

            GoalsView()
                .tabItem { Label("Goals", systemImage: "flag.fill") }

            FriendsView()
                .tabItem { Label("Friends", systemImage: "person.2.fill") }

            NavigationStack {
                HistoryCalendarView()
            }
            .tabItem { Label("History", systemImage: "calendar") }
        }
        .tint(Color.tallyAccent)
        // Apply appearance on first appearance and re-apply whenever the
        // theme identity changes. Without this, the UITabBarAppearance
        // captures the launch-time accent and never updates, so a Berry →
        // Midnight switch (or Custom color tweak) leaves the bottom tab
        // looking like the old theme.
        .onAppear { applyTabBarAppearance() }
        .onChange(of: themeKey) { _, _ in applyTabBarAppearance() }
    }

    /// Reads the current theme's colors and writes them into the global
    /// `UITabBar.appearance()` defaults AND every currently-attached
    /// `UITabBar` instance in the window hierarchy. The hierarchy walk
    /// is what makes the live tab bar update — setting
    /// `UITabBar.appearance()` alone only affects future instances.
    private func applyTabBarAppearance() {
        #if canImport(UIKit)
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Color.tallyCanvas)
        appearance.shadowColor = .clear
        appearance.selectionIndicatorTintColor = .clear
        appearance.selectionIndicatorImage = UIImage()

        let item = UITabBarItemAppearance()
        item.selected.iconColor = UIColor(Color.tallyAccent)
        item.selected.titleTextAttributes = [
            .foregroundColor: UIColor(Color.tallyAccent)
        ]
        item.normal.iconColor = UIColor(Color.tallyTextSecondary)
        item.normal.titleTextAttributes = [
            .foregroundColor: UIColor(Color.tallyTextSecondary)
        ]
        appearance.stackedLayoutAppearance = item
        appearance.inlineLayoutAppearance = item
        appearance.compactInlineLayoutAppearance = item

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance

        // Reach into the running window hierarchy and update any live
        // UITabBar instances. UITabBar.appearance() only seeds new ones;
        // existing ones keep their original appearance until forcibly
        // overwritten.
        for window in UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows }) {
            for tabBar in Self.findTabBars(in: window.rootViewController) {
                tabBar.standardAppearance = appearance
                tabBar.scrollEdgeAppearance = appearance
            }
        }
        #endif
    }

    #if canImport(UIKit)
    /// Recursively collect every `UITabBar` reachable from `vc` — through
    /// child view controllers and through whatever is currently presented.
    /// Returns a list (rather than the first) so nested tab controllers in
    /// sheets / popovers also get refreshed.
    private static func findTabBars(in vc: UIViewController?) -> [UITabBar] {
        guard let vc else { return [] }
        var result: [UITabBar] = []
        if let tabVC = vc as? UITabBarController {
            result.append(tabVC.tabBar)
        }
        for child in vc.children {
            result.append(contentsOf: findTabBars(in: child))
        }
        if let presented = vc.presentedViewController {
            result.append(contentsOf: findTabBars(in: presented))
        }
        return result
    }
    #endif
}

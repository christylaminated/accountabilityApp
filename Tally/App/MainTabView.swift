import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MainTabView: View {
    init() {
        // Selected state is communicated through icon + label tint alone —
        // no pill behind the active item.
        //
        // Caveat: iOS 26's "Liquid Glass" tab bar renders the selection
        // background in a layer above standard UITabBar chrome, so
        // setting `selectionIndicatorTintColor` and the per-state item
        // appearances doesn't fully strip the pill on that OS. The
        // configuration below DOES correctly set the icon/label colors
        // (textSecondary unselected, accent selected) and zero out the
        // selection indicator on iOS 17/18. On iOS 26 a faint
        // system-drawn pill may remain behind the active item until
        // Apple ships an API to opt out (or we replace TabView with a
        // fully custom bar).
        #if canImport(UIKit)
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Color.tallyCanvas)
        appearance.shadowColor = .clear
        appearance.selectionIndicatorTintColor = .clear
        // Empty UIImage further suppresses the indicator on older OSes.
        appearance.selectionIndicatorImage = UIImage()

        let itemAppearance = UITabBarItemAppearance()
        itemAppearance.selected.iconColor = UIColor(Color.tallyAccent)
        itemAppearance.selected.titleTextAttributes = [
            .foregroundColor: UIColor(Color.tallyAccent)
        ]
        itemAppearance.normal.iconColor = UIColor(Color.tallyTextSecondary)
        itemAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor(Color.tallyTextSecondary)
        ]
        appearance.stackedLayoutAppearance = itemAppearance
        appearance.inlineLayoutAppearance = itemAppearance
        appearance.compactInlineLayoutAppearance = itemAppearance

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        #endif
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
    }
}

import SwiftUI

struct MainTabView: View {
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
        .tint(.tallyAccent)
    }
}

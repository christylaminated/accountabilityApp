import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            CircleDashboardView()
                .tabItem { Label("Today", systemImage: "house.fill") }

            HabitListView()
                .tabItem { Label("Habits", systemImage: "checkmark.circle.fill") }

            WeeklyGoalsView()
                .tabItem { Label("Goals", systemImage: "flag.fill") }

            DirectMessageListView()
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right.fill") }

            NavigationStack {
                HistoryCalendarView()
            }
            .tabItem { Label("History", systemImage: "calendar") }
        }
        .tint(.tallyAccent)
    }
}

import SwiftUI
import CloudKit

struct CircleDashboardView: View {
    @Environment(\.tallyAccent) private var tallyAccent
    @Environment(AppState.self) private var appState
    @State private var showProfileSettings = false
    @State private var showAddTodayGoal = false

    /// Time-of-day greeting. Updated when the view recomputes.
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Hey"
        }
    }

    private var firstName: String {
        let full = appState.ownCloudProfile?.displayName ?? ""
        return full.split(separator: " ").first.map(String.init) ?? full
    }

    private var avatarSymbol: String {
        appState.ownCloudProfile?.avatarSymbol ?? "leaf"
    }

    /// My day-period goals dated to today's startOfDay.
    private var todayGoals: [Goal] {
        appState.personalStore.goals(
            for: appState.currentUserID,
            period: .day,
            periodStart: Date.now.startOfDay
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    todayGoalsCard

                    ForEach(appState.dashboardMembers) { member in
                        NavigationLink(value: member.userID) {
                            MemberRowView(member: member)
                        }
                        .buttonStyle(.plain)
                    }

                    if appState.personalStore.friends.isEmpty {
                        addFriendCard
                    }

                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(Color.tallyCanvas)
            .refreshable { await appState.refreshCircleData() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(Date.now, format: .dateTime.weekday(.wide).month().day())
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showProfileSettings = true
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                }
            }
            .navigationDestination(for: String.self) { userID in
                MemberDetailView(memberID: userID)
            }
            .sheet(isPresented: $showProfileSettings) {
                ProfileSettingsView()
            }
            .sheet(isPresented: $showAddTodayGoal) {
                AddGoalSheet(period: .day, periodStart: Date.now.startOfDay)
            }
            .alert(
                "Couldn't share",
                isPresented: Binding(
                    get: { appState.lastCloudShareError != nil },
                    set: { if !$0 { appState.lastCloudShareError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { appState.lastCloudShareError = nil }
            } message: {
                Text(appState.lastCloudShareError ?? "")
            }
        }
    }

    private var headerCard: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: avatarSymbol)
                .font(.system(size: 26, weight: .medium))
                .frame(width: 64, height: 64)
                .foregroundStyle(tallyAccent)
                .background(tallyAccent.opacity(0.15))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text("\(greeting),")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(firstName + ".")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }

    /// Today-period goals card. Always visible: shows the goals if any, plus
    /// a "+" affordance to add one for today.
    private var todayGoalsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "flag")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tallyAccent)
                Text("Today's goals")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Spacer()
                Button {
                    showAddTodayGoal = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(tallyAccent)
                }
                .buttonStyle(.plain)
            }

            if todayGoals.isEmpty {
                Text("Nothing set for today yet — tap + to add one.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 8) {
                    ForEach(todayGoals) { goal in
                        TodayGoalRow(goal: goal)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.tallyCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// Empty-state card prompting the user to add their first friend. The
    /// "Add a friend" button mints their personal CKShare and opens the system
    /// invite sheet — accepting the link makes the two users mutual friends.
    private var addFriendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.title2)
                    .foregroundStyle(tallyAccent)
                Text("Bring your friends in")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
            }
            Text("Tally works best when you can see your friends' check-ins next to yours. Send an invite to add a friend.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                presentAddFriend()
            } label: {
                Text("Add a friend")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(tallyAccent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.tallyCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(tallyAccent.opacity(0.25), lineWidth: 1)
                )
        )
    }

    /// Mint-or-fetch my personal CKShare and present the system invite sheet.
    private func presentAddFriend() {
        let repo = appState.personalRepository
        CloudShareInvitePresenter.present {
            try await repo.makePersonalShare()
        }
    }
}

/// One row inside the dashboard's "Today's goals" card. Tappable checkbox +
/// strikethrough on completion.
private struct TodayGoalRow: View {
    @Environment(\.tallyAccent) private var tallyAccent
    @Environment(AppState.self) private var appState
    let goal: Goal

    private var isDone: Bool { goal.completedAt != nil }

    var body: some View {
        HStack(spacing: 10) {
            CheckboxButton(isChecked: isDone, isEditable: true) {
                appState.personalStore.toggleComplete(goal: goal)
            }
            Text(goal.title)
                .strikethrough(isDone, color: .secondary)
                .foregroundStyle(isDone ? .secondary : .primary)
                .lineLimit(2)
            Spacer()
        }
    }
}

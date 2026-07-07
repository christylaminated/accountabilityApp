import SwiftUI

/// Screen 4 of the paywalled onboarding flow — leaderboard preview.
///
/// Shows a fake leaderboard with four placeholder friends (Maya, Jordan,
/// Sam, Riley) and the real user pinned mid-pack (rank 3 of 5). The
/// user's row uses their actual display name and the real count of habits
/// they entered on screen 2 — creates a visible gap to close. Fakes get
/// plausible weekly habit counts (6–11).
///
/// Visually mirrors the dashboard's real `LeaderboardRow`. A small label
/// at the top makes the "preview" status explicit so we're not pretending
/// these people exist; the user already knows they have zero friends.
struct LeaderboardPreviewView: View {
    @Environment(AppState.self) private var appState

    private var displayName: String {
        appState.ownCloudProfile?.displayName ?? "You"
    }

    /// Real-from-PersonalStore count, falling back to 1 (the just-entered
    /// habit) if the store hasn't refreshed yet.
    private var myHabitCount: Int {
        let n = appState.personalStore.habits(for: appState.currentUserID).count
        return max(n, 1)
    }

    /// Five entries, user pinned at index 2 (rank 3). Mirrors the real
    /// dashboard leaderboard's metrics (streak + "X of Y today") so the
    /// preview honestly reflects what the user will see once they have
    /// friends. Numbers picked for vibe — the friend group is consistent,
    /// the user is starting their first day, and the bottom two haven't
    /// kicked it off yet.
    private var entries: [Entry] {
        [
            Entry(rank: 1, name: "Maya",      streak: 11, doneToday: 3, totalHabits: 4, isMe: false),
            Entry(rank: 2, name: "Jordan",    streak: 9,  doneToday: 4, totalHabits: 4, isMe: false),
            Entry(rank: 3, name: displayName, streak: 1,  doneToday: 0, totalHabits: myHabitCount, isMe: true),
            Entry(rank: 4, name: "Sam",       streak: 7,  doneToday: 0, totalHabits: 3, isMe: false),
            Entry(rank: 5, name: "Riley",     streak: 5,  doneToday: 1, totalHabits: 3, isMe: false),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.rank) { idx, entry in
                        row(entry)
                        if idx < entries.count - 1 {
                            Divider().background(Color.tallyDivider)
                        }
                    }
                }
                .padding(.vertical, 4)

                Text("You and your friends hold each other accountable. You got this.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.tallyTextSecondary)
                    .multilineTextAlignment(.leading)

                Spacer().frame(height: 12)
                continueButton
                Spacer().frame(height: 24)
            }
            .padding(.horizontal, 24)
            .padding(.top, 56)
        }
        .background(Color.tallyCanvas)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Preview — this is what your leaderboard will look like with friends")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(Color.tallyTextSecondary)
                .textCase(.uppercase)
            Text("Nice start, \(displayName).")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(Color.tallyTextPrimary)
        }
    }

    @ViewBuilder
    private func row(_ entry: Entry) -> some View {
        let isMe = entry.isMe
        HStack(spacing: 12) {
            Text("\(entry.rank)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(rankColor(for: entry.rank))
                .frame(width: 22)

            AvatarView(symbolName: "leaf", imageData: nil, size: 32)
                .overlay(Circle().stroke(Color.tallyAccent.opacity(0.30), lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.system(size: 15, weight: isMe ? .semibold : .medium))
                    .foregroundStyle(Color.tallyTextPrimary)
                Text(statusText(for: entry))
                    .font(.system(size: 13))
                    .foregroundStyle(statusColor(for: entry))
            }
            Spacer()
            if entry.streak > 0 {
                HStack(spacing: 3) {
                    Text("\(entry.streak)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.tallyTextPrimary)
                    Image(systemName: "flame.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.tallyAccent)
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, isMe ? 8 : 0)
        .background(isMe ? Color.tallyAccent.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Mirrors `LeaderboardRow.statusText` in CircleDashboardView so the
    /// preview reads identically to what users see once they have friends.
    private func statusText(for entry: Entry) -> String {
        guard entry.totalHabits > 0 else { return "No habits yet" }
        if entry.doneToday == 0 { return "Not started today" }
        if entry.doneToday == entry.totalHabits { return "All done today ✓" }
        return "\(entry.doneToday) of \(entry.totalHabits) today"
    }

    private func statusColor(for entry: Entry) -> Color {
        (entry.totalHabits > 0 && entry.doneToday == entry.totalHabits)
            ? Color.tallyAccent
            : Color.tallyTextSecondary
    }

    private func rankColor(for rank: Int) -> Color {
        switch rank {
        case 1:  Color(red: 0.85, green: 0.65, blue: 0.13) // gold
        case 2:  Color(red: 0.62, green: 0.62, blue: 0.66) // silver
        case 3:  Color(red: 0.72, green: 0.45, blue: 0.20) // bronze
        default: Color.tallyTextSecondary
        }
    }

    private var continueButton: some View {
        Button {
            appState.completeLeaderboardPreview()
        } label: {
            Text("Continue")
                .font(.system(.body, design: .rounded, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.tallyAccent)
                .foregroundStyle(Color.tallyOnAccent)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private struct Entry {
        let rank: Int
        let name: String
        let streak: Int
        let doneToday: Int
        let totalHabits: Int
        let isMe: Bool
    }
}

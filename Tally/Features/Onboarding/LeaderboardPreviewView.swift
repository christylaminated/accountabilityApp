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

    /// Five entries, user pinned at index 2 (rank 3). The ordering and
    /// numbers are picked for vibe, not a strict sort — the preview's job
    /// is to make the gap visible, not to model a real ranking algorithm.
    private var entries: [Entry] {
        [
            Entry(rank: 1, name: "Maya",     habits: 11, isMe: false),
            Entry(rank: 2, name: "Jordan",   habits: 9,  isMe: false),
            Entry(rank: 3, name: displayName, habits: myHabitCount, isMe: true),
            Entry(rank: 4, name: "Sam",      habits: 8,  isMe: false),
            Entry(rank: 5, name: "Riley",    habits: 6,  isMe: false),
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
                Text("\(entry.habits) habits this week")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.tallyTextSecondary)
            }
            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, isMe ? 8 : 0)
        .background(isMe ? Color.tallyAccent.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
        let habits: Int
        let isMe: Bool
    }
}

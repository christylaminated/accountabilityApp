import SwiftUI

/// The "Friends" tab — replaces the old Chat tab. Lists my friends (with the
/// "Add a friend" entry point) and my Groups (chat rooms). Tapping a Group
/// activates that Circle so its chat appears.
struct FriendsView: View {
    @Environment(AppState.self) private var appState
    @State private var showCreateGroup = false

    private var friends: [Friend] {
        appState.personalStore.friends
    }

    private var groups: [TallyCircle] {
        appState.allCircles
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    addFriendButton

                    section("Friends") {
                        if friends.isEmpty {
                            emptyCard("No friends yet — tap above to invite someone.")
                        } else {
                            ForEach(friends) { friend in
                                NavigationLink(value: friend.userID) {
                                    FriendRow(friend: friend)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    section("Groups") {
                        if groups.isEmpty {
                            emptyCard("No groups yet — start a group chat with your friends.")
                        } else {
                            ForEach(groups) { group in
                                NavigationLink {
                                    GroupChatHost(circle: group)
                                } label: {
                                    GroupRow(group: group)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        newGroupButton
                    }

                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(Color.tallyCanvas)
            .refreshable { await appState.refreshCircleData() }
            .navigationTitle("Friends")
            .navigationDestination(for: String.self) { userID in
                MemberDetailView(memberID: userID)
            }
            .sheet(isPresented: $showCreateGroup) {
                CreateCircleView { _ in /* no auto-invite for groups */ }
            }
        }
    }

    // MARK: - Subviews

    private var addFriendButton: some View {
        Button {
            let repo = appState.personalRepository
            CloudShareInvitePresenter.present {
                try await repo.makePersonalShare()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.title3)
                Text("Add a friend")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color.tallyCard)
            .foregroundStyle(Color.tallyAccent)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var newGroupButton: some View {
        Button {
            showCreateGroup = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                Text("New group")
                    .font(.system(.body, design: .rounded, weight: .medium))
                Spacer()
            }
            .padding(14)
            .background(Color.tallyCard)
            .foregroundStyle(Color.tallyAccent)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            VStack(spacing: 8) {
                content()
            }
        }
    }

    private func emptyCard(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.tallyCard)
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct FriendRow: View {
    let friend: Friend

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(symbolName: friend.avatarSymbol, size: 44)
            Text(friend.displayName)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Color.tallyCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct GroupRow: View {
    @Environment(AppState.self) private var appState
    let group: TallyCircle

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 18, weight: .medium))
                .frame(width: 44, height: 44)
                .foregroundStyle(Color.tallyAccent)
                .background(Color.tallyAccent.opacity(0.15))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(group.id == appState.activeCircle?.id
                     ? "Active group"
                     : "Group chat")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Color.tallyCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

/// Activates `circle` on the `CircleStore` when entered, then renders the
/// shared `CircleFeedView` against the active Circle. Multi-Group switching
/// works by activating whichever Group's chat the user navigates into.
private struct GroupChatHost: View {
    @Environment(AppState.self) private var appState
    let circle: TallyCircle

    var body: some View {
        CircleFeedView()
            .task { await appState.activateCircle(circle) }
    }
}

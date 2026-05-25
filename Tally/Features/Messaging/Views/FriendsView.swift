import SwiftUI

/// The "Friends" tab — replaces the old Chat tab. Lists my friends (with the
/// "Add a friend" entry point) and my Groups (chat rooms). Tapping a Group
/// activates that Circle so its chat appears.
struct FriendsView: View {
    @Environment(\.tallyAccent) private var tallyAccent
    @Environment(AppState.self) private var appState
    @State private var showCreateGroup = false
    @State private var showFriendSearch = false
    @State private var groupToDelete: TallyCircle?
    @State private var groupToLeave: TallyCircle?
    @State private var friendToUnfriend: Friend?
    @State private var unfriendError: String?

    private var friends: [Friend] {
        appState.personalStore.friends
    }

    private var groups: [TallyCircle] {
        appState.allCircles
    }

    private func isOwner(of group: TallyCircle) -> Bool {
        group.ownerID == appState.currentUserID
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    addFriendButton
                    findByUsernameButton

                    if let err = appState.lastFriendRequestError {
                        FriendRequestErrorBanner(message: err)
                    }
                    if !appState.incomingFriendRequests.isEmpty {
                        FriendRequestsSection()
                    }

                    section("Friends") {
                        if friends.isEmpty {
                            emptyCard("No friends yet — tap above to invite someone.")
                        } else {
                            ForEach(friends) { friend in
                                NavigationLink(value: friend.userID) {
                                    FriendRow(friend: friend)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        friendToUnfriend = friend
                                    } label: {
                                        Label("Unfriend", systemImage: "person.badge.minus")
                                    }
                                }
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
                                .contextMenu {
                                    if isOwner(of: group) {
                                        Button(role: .destructive) {
                                            groupToDelete = group
                                        } label: {
                                            Label("Delete group", systemImage: "trash")
                                        }
                                    } else {
                                        Button(role: .destructive) {
                                            groupToLeave = group
                                        } label: {
                                            Label("Leave group", systemImage: "rectangle.portrait.and.arrow.right")
                                        }
                                    }
                                }
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
            .sheet(isPresented: $showFriendSearch) {
                FriendSearchView()
            }
            .confirmationDialog(
                "Delete this group?",
                isPresented: Binding(
                    get: { groupToDelete != nil },
                    set: { if !$0 { groupToDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: groupToDelete
            ) { group in
                Button("Delete group", role: .destructive) {
                    Task { await appState.deleteCircle(group) }
                    groupToDelete = nil
                }
                Button("Cancel", role: .cancel) { groupToDelete = nil }
            } message: { _ in
                Text("This removes the group and its chat history for everyone. This can't be undone.")
            }
            .confirmationDialog(
                "Leave this group?",
                isPresented: Binding(
                    get: { groupToLeave != nil },
                    set: { if !$0 { groupToLeave = nil } }
                ),
                titleVisibility: .visible,
                presenting: groupToLeave
            ) { group in
                Button("Leave", role: .destructive) {
                    Task { await appState.leaveCircle(group) }
                    groupToLeave = nil
                }
                Button("Cancel", role: .cancel) { groupToLeave = nil }
            } message: { _ in
                Text("You'll stop seeing this group's chat. The other members stay in it.")
            }
            .confirmationDialog(
                "Unfriend?",
                isPresented: Binding(
                    get: { friendToUnfriend != nil },
                    set: { if !$0 { friendToUnfriend = nil } }
                ),
                titleVisibility: .visible,
                presenting: friendToUnfriend
            ) { friend in
                Button("Unfriend \(friend.displayName)", role: .destructive) {
                    let target = friend
                    friendToUnfriend = nil
                    Task {
                        do {
                            try await appState.unfriend(target)
                        } catch {
                            unfriendError = error.localizedDescription
                        }
                    }
                }
                Button("Cancel", role: .cancel) { friendToUnfriend = nil }
            } message: { friend in
                Text("\(friend.displayName) will no longer see your habits and goals. On their next refresh you'll disappear from their friends list too.")
            }
            .alert(
                "Couldn't unfriend",
                isPresented: Binding(
                    get: { unfriendError != nil },
                    set: { if !$0 { unfriendError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { unfriendError = nil }
            } message: {
                Text(unfriendError ?? "")
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
            .foregroundStyle(tallyAccent)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var findByUsernameButton: some View {
        Button {
            showFriendSearch = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                Text("Find by username")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color.tallyCard)
            .foregroundStyle(tallyAccent)
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
            .foregroundStyle(tallyAccent)
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
    @Environment(\.tallyAccent) private var tallyAccent
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
    @Environment(\.tallyAccent) private var tallyAccent
    @Environment(AppState.self) private var appState
    let group: TallyCircle

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 18, weight: .medium))
                .frame(width: 44, height: 44)
                .foregroundStyle(tallyAccent)
                .background(tallyAccent.opacity(0.15))
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
    @Environment(\.tallyAccent) private var tallyAccent
    @Environment(AppState.self) private var appState
    let circle: TallyCircle

    var body: some View {
        CircleFeedView()
            .task { await appState.activateCircle(circle) }
    }
}

import SwiftUI

/// Quick-access friends list — opened from the dashboard's top-right button.
/// Shows everyone I'm bidirectionally sharing with, plus an "Add a friend"
/// entry point. Group management lives elsewhere (inside a group's chat).
struct FriendsListSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    private var friends: [Friend] {
        appState.personalStore.friends
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    addFriendButton

                    if friends.isEmpty {
                        Text("No friends yet. Tap above to send an invite.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                            .padding(.top, 16)
                    } else {
                        ForEach(friends) { friend in
                            FriendListRow(friend: friend)
                        }
                    }

                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(Color.tallyCanvas)
            .navigationTitle("Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

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
}

private struct FriendListRow: View {
    let friend: Friend

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(symbolName: friend.avatarSymbol, size: 40)
            Text(friend.displayName)
                .font(.body.weight(.medium))
            Spacer()
        }
        .padding(14)
        .background(Color.tallyCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

import SwiftUI

struct DirectMessageListView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    NavigationLink {
                        CircleFeedView()
                    } label: {
                        FeedRow()
                    }
                    .buttonStyle(.plain)

                    if !appState.circleStore.otherMembers.isEmpty {
                        Text("DIRECT MESSAGES")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 16)
                            .padding(.horizontal, 4)
                    }

                    ForEach(appState.circleStore.otherMembers) { member in
                        NavigationLink {
                            DirectMessageThreadView(otherUserID: member.userID)
                        } label: {
                            DMThreadRow(otherUser: member)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(Color.tallyCanvas)
            .refreshable { await appState.refreshCircleData() }
            .navigationTitle("Messages")
        }
    }
}

private struct FeedRow: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 18, weight: .medium))
                .frame(width: 44, height: 44)
                .foregroundStyle(Color.tallyAccent)
                .background(Color.tallyAccent.opacity(0.15))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Circle feed")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(appState.circleStore.feed.last?.body ?? "No messages yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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

private struct DMThreadRow: View {
    @Environment(AppState.self) private var appState
    let otherUser: CircleMember

    private var unread: Int {
        appState.circleStore.unreadDMCount(
            for: appState.currentUserID,
            fromUser: otherUser.userID
        )
    }

    private var lastMessage: DirectMessage? {
        appState.circleStore.dmThread(
            between: appState.currentUserID,
            and: otherUser.userID
        ).last
    }

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(symbolName: otherUser.avatarSymbol, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(otherUser.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    if let last = lastMessage {
                        Text(last.createdAt, format: .relative(presentation: .named))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text(lastMessage?.body ?? "No messages yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    if unread > 0 {
                        Text("\(unread)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.tallyAccent)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(14)
        .background(Color.tallyCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

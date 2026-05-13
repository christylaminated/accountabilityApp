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

                    if !appState.otherMembers.isEmpty {
                        Text("DIRECT MESSAGES")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 16)
                            .padding(.horizontal, 4)
                    }

                    ForEach(appState.otherMembers) { profile in
                        NavigationLink {
                            DirectMessageThreadView(otherUserID: profile.id)
                        } label: {
                            DMThreadRow(otherUser: profile)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(Color.tallyCanvas)
            .navigationTitle("Messages")
        }
    }
}

private struct FeedRow: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 12) {
            Text(appState.activeCircle.emoji ?? "✨")
                .font(.system(size: 24))
                .frame(width: 44, height: 44)
                .background(Color.tallyAccent.opacity(0.15))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Circle feed")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                let last = appState.messageStore.feed(circleID: appState.activeCircleID).last
                Text(last?.body ?? "No messages yet")
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
    let otherUser: Profile

    private var unread: Int {
        appState.messageStore.unreadDMCount(
            for: appState.currentUserID,
            fromUser: otherUser.id,
            circleID: appState.activeCircleID
        )
    }

    private var lastMessage: DirectMessage? {
        appState.messageStore.dmThread(
            circleID: appState.activeCircleID,
            between: appState.currentUserID,
            and: otherUser.id
        ).last
    }

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(emoji: otherUser.avatarEmoji, size: 44)
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

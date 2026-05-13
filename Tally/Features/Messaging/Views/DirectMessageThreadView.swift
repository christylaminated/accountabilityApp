import SwiftUI

struct DirectMessageThreadView: View {
    @Environment(AppState.self) private var appState
    let otherUserID: UUID
    @State private var composerText: String = ""

    private var otherUser: Profile? {
        appState.profileStore.profile(id: otherUserID)
    }

    private var messages: [DirectMessage] {
        appState.messageStore.dmThread(
            circleID: appState.activeCircleID,
            between: appState.currentUserID,
            and: otherUserID
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(messages) { msg in
                            bubble(for: msg).id(msg.id)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }
                .onChange(of: messages.count) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onAppear {
                    proxy.scrollTo("bottom", anchor: .bottom)
                    appState.messageStore.markDMsRead(
                        circleID: appState.activeCircleID,
                        viewer: appState.currentUserID,
                        otherUser: otherUserID
                    )
                }
            }

            MessageComposerView(text: $composerText) { send() }
        }
        .background(Color.tallyCanvas)
        .navigationTitle(otherUser?.displayName ?? "Direct")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func bubble(for msg: DirectMessage) -> some View {
        let isMe = msg.senderID == appState.currentUserID
        return MessageBubbleView(
            text: msg.body,
            timestamp: msg.createdAt,
            isMe: isMe,
            senderEmoji: otherUser?.avatarEmoji ?? "",
            senderName: otherUser?.displayName ?? "",
            showSender: false
        )
    }

    private func send() {
        let body = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        appState.messageStore.sendDM(
            body: body,
            circleID: appState.activeCircleID,
            senderID: appState.currentUserID,
            recipientID: otherUserID
        )
        composerText = ""
    }
}

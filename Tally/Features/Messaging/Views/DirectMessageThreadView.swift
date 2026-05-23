import SwiftUI

struct DirectMessageThreadView: View {
    @Environment(AppState.self) private var appState
    let otherUserID: String
    @State private var composerText: String = ""

    private var otherUser: CircleMember? {
        appState.circleStore.member(id: otherUserID)
    }

    private var messages: [DirectMessage] {
        appState.circleStore.dmThread(
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
            senderSymbol: otherUser?.avatarSymbol ?? "person",
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
        appState.circleStore.sendDM(
            body: body,
            senderID: appState.currentUserID,
            recipientID: otherUserID
        )
        composerText = ""
    }
}

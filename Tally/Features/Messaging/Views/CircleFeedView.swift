import SwiftUI

struct CircleFeedView: View {
    @Environment(AppState.self) private var appState
    @State private var composerText: String = ""
    @State private var showSettings = false

    private var messages: [CircleMessage] {
        appState.circleStore.feed
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(groupedByDay(), id: \.0) { day, items in
                            Text(day)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 12)
                                .padding(.bottom, 4)
                            ForEach(items) { msg in
                                bubble(for: msg)
                                    .id(msg.id)
                            }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 12)
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button {
                    if appState.activeCircle != nil { showSettings = true }
                } label: {
                    HStack(spacing: 4) {
                        Text(appState.activeCircle?.name ?? "Circle")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showSettings) {
            if let circle = appState.activeCircle {
                CircleSettingsView(circle: circle)
            }
        }
    }

    private func bubble(for msg: CircleMessage) -> some View {
        let isMe = msg.senderID == appState.currentUserID
        let member = appState.circleStore.member(id: msg.senderID)
        return MessageBubbleView(
            text: msg.body,
            timestamp: msg.createdAt,
            isMe: isMe,
            senderSymbol: member?.avatarSymbol ?? "person",
            senderName: member?.displayName ?? "",
            showSender: !isMe
        )
    }

    private func send() {
        let body = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        appState.circleStore.sendCircleMessage(
            body: body,
            senderID: appState.currentUserID
        )
        composerText = ""
    }

    /// Group messages by day label, preserving chronological order of first-seen days.
    private func groupedByDay() -> [(String, [CircleMessage])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"

        func label(for date: Date) -> String {
            if Calendar.current.isDateInToday(date) { return "Today" }
            if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
            return formatter.string(from: date)
        }

        var ordered: [(String, [CircleMessage])] = []
        var indexByLabel: [String: Int] = [:]
        for msg in messages {
            let key = label(for: msg.createdAt)
            if let idx = indexByLabel[key] {
                ordered[idx].1.append(msg)
            } else {
                indexByLabel[key] = ordered.count
                ordered.append((key, [msg]))
            }
        }
        return ordered
    }
}

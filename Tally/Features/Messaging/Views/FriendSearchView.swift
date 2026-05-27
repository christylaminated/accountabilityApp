import SwiftUI

/// Find a user by their unique username and send them a friend request.
/// The request becomes an iOS-level CKShare invitation; the recipient sees a
/// system notification, taps to accept, and the friend graph wires up
/// automatically on both sides.
struct FriendSearchView: View {
    @Environment(\.tallyAccent) private var tallyAccent
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @State private var isSearching = false
    @State private var result: SearchState = .idle
    @State private var sendStatus: SendStatus = .idle

    private enum SearchState: Equatable {
        case idle
        case notFound
        case found(UserSearchResult)
        case error(String)
    }

    private enum SendStatus: Equatable {
        case idle, sending, sent, failed(String)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    searchField
                    resultSection
                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(Color.tallyCanvas)
            .navigationTitle("Find a friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Subviews

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "at")
                .foregroundStyle(.secondary)
            TextField("username", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .submitLabel(.search)
                .onSubmit { Task { await search() } }
            if isSearching {
                ProgressView()
            } else {
                Button("Search") { Task { await search() } }
                    .font(.subheadline.weight(.semibold))
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .background(Color.tallyCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var resultSection: some View {
        switch result {
        case .idle:
            Text("Type a username and tap Search.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        case .notFound:
            Text("No user with that username.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        case .error(let message):
            Text(message)
                .font(.footnote)
                .foregroundStyle(Color.tallyDestructive)
                .padding(.horizontal, 4)
        case .found(let user):
            foundCard(user)
        }
    }

    private func foundCard(_ user: UserSearchResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AvatarView(symbolName: user.avatarSymbol, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.displayName)
                        .font(.body.weight(.semibold))
                    Text("@\(user.username)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if isAlreadyFriend(user) {
                Label("Already friends", systemImage: "checkmark.seal.fill")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(tallyAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(tallyAccent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
            switch sendStatus {
            case .idle:
                Button {
                    Task { await sendRequest(to: user) }
                } label: {
                    Text(isSelf(user) ? "Send to yourself (test)" : "Send friend request")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(tallyAccent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            case .sending:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Sending…").font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            case .sent:
                Label("Sent — they'll see it in their friend requests when they open Tally.", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(tallyAccent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .failed(let message):
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Color.tallyDestructive)
            }
            }
        }
        .padding(16)
        .background(Color.tallyCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func isAlreadyFriend(_ user: UserSearchResult) -> Bool {
        appState.personalStore.friends.contains { $0.userID == user.userRecordName }
    }

    private func isSelf(_ user: UserSearchResult) -> Bool {
        let match = user.userRecordName == appState.currentUserID
        NSLog("[Tally] isSelf check: match=\(match) searchedUserRecordName=\(user.userRecordName) currentUserID=\(appState.currentUserID)")
        return match
    }

    // MARK: - Actions

    private func search() async {
        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        isSearching = true
        sendStatus = .idle
        defer { isSearching = false }
        do {
            if let user = try await appState.searchUser(byUsername: raw) {
                result = .found(user)
            } else {
                result = .notFound
            }
        } catch {
            result = .error(error.localizedDescription)
        }
    }

    private func sendRequest(to user: UserSearchResult) async {
        sendStatus = .sending
        do {
            try await appState.sendFriendRequest(to: user.userRecordName)
            sendStatus = .sent
        } catch {
            sendStatus = .failed(error.localizedDescription)
        }
    }
}

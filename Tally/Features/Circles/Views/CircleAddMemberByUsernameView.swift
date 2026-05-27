import SwiftUI

/// Search a user by username and add them to a Circle. Owner-only — non-owners
/// can't modify the share's participant list at the CloudKit boundary, so this
/// view is only presented when `isOwner == true` in CircleSettingsView.
///
/// Mirrors `FriendSearchView` for the search + result UI; the action delegates
/// to `AppState.addMemberToCircle` which calls `CircleRepository.addMember`.
struct CircleAddMemberByUsernameView: View {
    @Environment(\.tallyAccent) private var tallyAccent
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let circle: TallyCircle

    @State private var query: String = ""
    @State private var isSearching = false
    @State private var result: SearchState = .idle
    @State private var addStatus: AddStatus = .idle

    private enum SearchState: Equatable {
        case idle
        case notFound
        case found(UserSearchResult)
        case error(String)
    }

    private enum AddStatus: Equatable {
        case idle, adding, added, failed(String)
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
            .navigationTitle("Add to \(circle.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

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
                AvatarView(
                    symbolName: user.avatarSymbol,
                    imageData: user.avatarImageData,
                    size: 48
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.displayName)
                        .font(.body.weight(.semibold))
                    Text("@\(user.username)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            switch addStatus {
            case .idle:
                Button {
                    Task { await add(user) }
                } label: {
                    Text(isSelf(user) ? "That's you" : "Add to \(circle.name)")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(isSelf(user) ? Color.tallyTextSecondary.opacity(0.3) : tallyAccent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isSelf(user))
            case .adding:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Adding…").font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            case .added:
                Label("Invited — they'll see it in their group invites when they open Tally.", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(tallyAccent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .failed(let message):
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Color.tallyDestructive)
            }
        }
        .padding(16)
        .background(Color.tallyCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func isSelf(_ user: UserSearchResult) -> Bool {
        user.userRecordName == appState.currentUserID
    }

    private func search() async {
        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        isSearching = true
        addStatus = .idle
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

    private func add(_ user: UserSearchResult) async {
        addStatus = .adding
        do {
            try await appState.addMemberToCircle(circle, userRecordName: user.userRecordName)
            addStatus = .added
        } catch {
            addStatus = .failed(error.localizedDescription)
        }
    }
}

import SwiftUI
import CloudKit

/// Create a Group with members in one sheet. The user picks a name, ticks
/// which friends to invite (and optionally finds non-friends by username),
/// and on "Create & invite" we create the Circle, then fan out a public-DB
/// GroupInvite to every selected recipient in parallel.
///
/// On success the parent's `onCreate` runs and the sheet dismisses. If a
/// subset of invites fails (e.g., one recipient's identity couldn't be
/// resolved), the Circle is still created — we keep the sheet open and
/// show inline per-recipient errors so the user can see what failed
/// without losing the Group.
struct CreateCircleView: View {
    @Environment(\.tallyAccent) private var tallyAccent
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    /// Called with the freshly-created Circle, after invites have been sent
    /// (or partially failed). Retained from the original API.
    let onCreate: (TallyCircle) -> Void

    @State private var name: String = ""

    /// User IDs of friends ticked in the checklist.
    @State private var selectedFriendIDs: Set<String> = []

    /// Non-friend users resolved via the username-search subsection. Their
    /// IDs are always included as invite targets.
    @State private var extraInvitees: [UserSearchResult] = []

    /// Errors keyed by recipient user ID, surfaced inline next to each row
    /// after invites finish. A non-empty dict keeps the sheet open so the
    /// user can see what failed.
    @State private var inviteErrors: [String: String] = [:]

    @State private var isCreating = false
    @State private var createdCircle: TallyCircle?
    @State private var topLevelError: String?

    // Username search state
    @State private var showUsernameSearch = false
    @State private var usernameQuery: String = ""
    @State private var isSearchingUsername = false
    @State private var usernameSearchError: String?

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValidName: Bool {
        !trimmed.isEmpty && trimmed.count <= 50
    }

    private var friends: [Friend] { appState.personalStore.friends }

    private var totalInvitees: Int {
        selectedFriendIDs.count + extraInvitees.count
    }

    /// All recipient user IDs we'll fan invites out to. De-duped so a
    /// friend who was also username-searched only gets one invite.
    private var allInviteeIDs: [String] {
        var ids = Array(selectedFriendIDs)
        for u in extraInvitees where !selectedFriendIDs.contains(u.userRecordName) {
            ids.append(u.userRecordName)
        }
        return ids
    }

    /// True once the Circle is created and invites have all completed
    /// (whether they succeeded or failed). Drives the "Done" button.
    private var isDoneWithPartialErrors: Bool {
        createdCircle != nil && !isCreating && !inviteErrors.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    nameField
                    membersSection
                    if let topLevelError {
                        Text(topLevelError)
                            .font(.footnote)
                            .foregroundStyle(Color.tallyDestructive)
                    }
                    actionButton
                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            .background(Color.tallyCanvas)
            .navigationTitle(createdCircle == nil ? "New Group" : "Group created")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isDoneWithPartialErrors ? "Done" : "Cancel") {
                        if let circle = createdCircle {
                            onCreate(circle)
                        }
                        dismiss()
                    }
                    .disabled(isCreating)
                }
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(tallyAccent)
            Text("Start a group chat")
                .font(.system(.title3, design: .rounded, weight: .bold))
            Text("Name it, pick who's in, and they'll get an invite when you create it.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Group name")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("e.g. Gym buddies", text: $name)
                .textInputAutocapitalization(.words)
                .padding(14)
                .background(Color.tallyCard)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .disabled(createdCircle != nil)
        }
    }

    @ViewBuilder
    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Members")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if totalInvitees > 0 {
                    Text("\(totalInvitees) selected")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tallyAccent)
                }
            }
            friendsList
            extraInviteesList
            usernameSearchSubsection
        }
    }

    @ViewBuilder
    private var friendsList: some View {
        if friends.isEmpty {
            Text("No friends yet — use \"Add by username\" below to invite someone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.tallyCard)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            VStack(spacing: 6) {
                ForEach(friends) { friend in
                    friendRow(friend)
                }
            }
        }
    }

    private func friendRow(_ friend: Friend) -> some View {
        let isSelected = selectedFriendIDs.contains(friend.userID)
        let err = inviteErrors[friend.userID]
        return Button {
            toggleFriend(friend.userID)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    AvatarView(symbolName: friend.avatarSymbol, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(friend.displayName)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? tallyAccent : .secondary.opacity(0.5))
                }
                if let err {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(Color.tallyDestructive)
                        .padding(.leading, 52)
                }
            }
            .padding(12)
            .background(Color.tallyCard)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(createdCircle != nil)
    }

    @ViewBuilder
    private var extraInviteesList: some View {
        if !extraInvitees.isEmpty {
            VStack(spacing: 6) {
                ForEach(extraInvitees) { user in
                    extraInviteeRow(user)
                }
            }
        }
    }

    private func extraInviteeRow(_ user: UserSearchResult) -> some View {
        let err = inviteErrors[user.userRecordName]
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                AvatarView(
                    symbolName: user.avatarSymbol,
                    imageData: user.avatarImageData,
                    size: 40
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.displayName)
                        .font(.body.weight(.semibold))
                    Text("@\(user.username)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    extraInvitees.removeAll { $0.id == user.id }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .disabled(createdCircle != nil)
            }
            if let err {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(Color.tallyDestructive)
                    .padding(.leading, 52)
            }
        }
        .padding(12)
        .background(Color.tallyCard)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var usernameSearchSubsection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { showUsernameSearch.toggle() }
            } label: {
                HStack {
                    Image(systemName: "magnifyingglass")
                    Text(showUsernameSearch ? "Hide username search" : "Add by username")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: showUsernameSearch ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color.tallyCard)
                .foregroundStyle(tallyAccent)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(createdCircle != nil)

            if showUsernameSearch {
                HStack(spacing: 8) {
                    Image(systemName: "at").foregroundStyle(.secondary)
                    TextField("username", text: $usernameQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .submitLabel(.search)
                        .onSubmit { Task { await runUsernameSearch() } }
                    if isSearchingUsername {
                        ProgressView()
                    } else {
                        Button("Add") { Task { await runUsernameSearch() } }
                            .font(.subheadline.weight(.semibold))
                            .disabled(usernameQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(12)
                .background(Color.tallyCard)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if let usernameSearchError {
                    Text(usernameSearchError)
                        .font(.caption)
                        .foregroundStyle(Color.tallyDestructive)
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    private var actionButton: some View {
        Button(action: actionButtonTapped) {
            HStack(spacing: 8) {
                if isCreating {
                    ProgressView().tint(Color.tallyOnAccent)
                }
                Text(actionButtonText)
                    .font(.system(.body, design: .rounded, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(actionButtonEnabled ? tallyAccent : Color.tallyTextSecondary.opacity(0.3))
            .foregroundStyle(Color.tallyOnAccent)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(!actionButtonEnabled || isCreating)
    }

    private var actionButtonText: String {
        if isCreating { return "Creating…" }
        if isDoneWithPartialErrors { return "Done" }
        if totalInvitees == 0 { return "Create group" }
        return "Create & invite \(totalInvitees)"
    }

    private var actionButtonEnabled: Bool {
        if createdCircle != nil { return true } // "Done" always works
        return isValidName
    }

    // MARK: - Actions

    private func toggleFriend(_ id: String) {
        if selectedFriendIDs.contains(id) {
            selectedFriendIDs.remove(id)
        } else {
            selectedFriendIDs.insert(id)
        }
    }

    private func runUsernameSearch() async {
        let raw = usernameQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        isSearchingUsername = true
        usernameSearchError = nil
        defer { isSearchingUsername = false }
        do {
            guard let user = try await appState.searchUser(byUsername: raw) else {
                usernameSearchError = "No user with that username."
                return
            }
            if user.userRecordName == appState.currentUserID {
                usernameSearchError = "You can't invite yourself."
                return
            }
            // If they're already in the friends list, tick the existing row
            // instead of adding a duplicate entry below.
            if friends.contains(where: { $0.userID == user.userRecordName }) {
                selectedFriendIDs.insert(user.userRecordName)
            } else if !extraInvitees.contains(where: { $0.userRecordName == user.userRecordName }) {
                extraInvitees.append(user)
            }
            usernameQuery = ""
        } catch {
            usernameSearchError = error.localizedDescription
        }
    }

    private func actionButtonTapped() {
        if isDoneWithPartialErrors, let circle = createdCircle {
            onCreate(circle)
            dismiss()
            return
        }
        create()
    }

    private func create() {
        guard isValidName, !isCreating, createdCircle == nil else { return }
        isCreating = true
        topLevelError = nil
        inviteErrors = [:]

        Task {
            do {
                let circle = try await appState.createCircle(name: trimmed, emoji: nil)
                createdCircle = circle

                // Fan out invites in parallel. Each result lands in
                // `inviteErrors` keyed by recipient so the row UI can
                // surface failures next to the person who didn't get
                // the invite.
                let invitees = allInviteeIDs
                if !invitees.isEmpty {
                    var failures: [String: String] = [:]
                    await withTaskGroup(of: (String, Error?).self) { group in
                        for inviteeID in invitees {
                            group.addTask {
                                do {
                                    try await appState.sendGroupInvite(to: inviteeID, circle: circle)
                                    return (inviteeID, nil)
                                } catch {
                                    return (inviteeID, error)
                                }
                            }
                        }
                        for await (id, error) in group {
                            if let error {
                                failures[id] = error.localizedDescription
                            }
                        }
                    }
                    inviteErrors = failures
                }

                isCreating = false

                if inviteErrors.isEmpty {
                    onCreate(circle)
                    dismiss()
                }
                // Else: keep the sheet open, "Done" button now visible
                // with the per-row errors rendered alongside each row.
            } catch {
                topLevelError = error.localizedDescription
                isCreating = false
            }
        }
    }
}

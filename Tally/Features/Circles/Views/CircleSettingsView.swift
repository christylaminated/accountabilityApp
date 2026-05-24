import SwiftUI
import CloudKit

/// Manage a single Circle: see members, invite more, remove (owner), leave
/// (member), or delete (owner).
struct CircleSettingsView: View {
    @Environment(\.tallyAccent) private var tallyAccent
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let circle: TallyCircle

    @State private var members: [CircleMember] = []
    @State private var isLoading = true
    @State private var actionError: String?
    @State private var confirmDelete = false
    @State private var confirmLeave = false
    @State private var nameDraft: String = ""
    @State private var isSavingName = false
    @State private var showAddByUsername = false
    @FocusState private var nameFocused: Bool

    private var myRecordName: String { appState.currentUserID }
    private var isOwner: Bool { circle.ownerID == myRecordName }
    private var atCap: Bool { members.count >= Constants.maxCircleMembers }
    /// Live name — prefer the freshly loaded version from AppState (post-rename)
    /// so the header and "Add to …" sheet reflect edits without re-presenting.
    private var liveCircle: TallyCircle {
        appState.ownedCircles.first(where: { $0.id == circle.id })
            ?? appState.joinedCircles.first(where: { $0.id == circle.id })
            ?? circle
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    nameEditor
                    header

                    if isLoading {
                        ProgressView().padding(.top, 40)
                    } else {
                        membersSection
                        inviteSection
                        dangerZone
                    }

                    if let actionError {
                        Text(actionError)
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(.red)
                    }
                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(Color.tallyCanvas)
            .navigationTitle(liveCircle.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                nameDraft = liveCircle.name
                await load()
            }
            .confirmationDialog("Delete this Circle?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Circle", role: .destructive) { Task { await deleteCircle() } }
            } message: {
                Text("This removes the Circle and its history for everyone. This can't be undone.")
            }
            .confirmationDialog("Leave this Circle?", isPresented: $confirmLeave, titleVisibility: .visible) {
                Button("Leave", role: .destructive) { Task { await leave() } }
            }
            .sheet(isPresented: $showAddByUsername) {
                CircleAddMemberByUsernameView(circle: liveCircle)
            }
        }
    }

    /// Anyone in the Circle can rename it — all participants have .readWrite on
    /// the root record. Saves on blur or return; reverts on error.
    private var nameEditor: some View {
        VStack(spacing: 6) {
            HStack {
                TextField("Group name", text: $nameDraft)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onSubmit { Task { await saveName() } }
                    .disabled(isSavingName)
                if isSavingName { ProgressView() }
            }
            .padding(12)
            .background(Color.tallyCard)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onChange(of: nameFocused) { _, focused in
                if !focused { Task { await saveName() } }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("\(members.count)/\(Constants.maxCircleMembers) members")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var membersSection: some View {
        VStack(spacing: 8) {
            ForEach(members) { member in
                HStack(spacing: 12) {
                    AvatarView(symbolName: member.avatarSymbol, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.displayName)
                            .font(.system(.body, design: .rounded, weight: .medium))
                        Text(member.role == .owner ? "Owner" : "Member")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isOwner && member.userID != myRecordName {
                        Button(role: .destructive) {
                            Task { await remove(member) }
                        } label: {
                            Text("Remove")
                                .font(.system(.footnote, design: .rounded, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                    }
                }
                .padding(14)
                .background(Color.tallyCard)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var inviteSection: some View {
        VStack(spacing: 10) {
            if isOwner {
                Button {
                    showAddByUsername = true
                } label: {
                    Label(atCap ? "Group is full" : "Add by username", systemImage: "person.badge.plus")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(atCap ? Color.gray.opacity(0.3) : tallyAccent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(atCap)
            }

            Button {
                let repo = appState.circleRepository
                let target = liveCircle
                CloudShareInvitePresenter.present {
                    try await repo.makeShare(for: target)
                }
            } label: {
                Label("Share invite link", systemImage: "link")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.tallyCard)
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(atCap)
        }
    }

    @ViewBuilder
    private var dangerZone: some View {
        if isOwner {
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Text("Delete Circle")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        } else {
            Button(role: .destructive) {
                confirmLeave = true
            } label: {
                Text("Leave Circle")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        }
    }

    // MARK: -

    private func load() async {
        isLoading = true
        do {
            members = try await appState.circleRepository.members(of: liveCircle)
        } catch {
            actionError = error.localizedDescription
        }
        isLoading = false
    }

    private func saveName() async {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != liveCircle.name else {
            nameDraft = liveCircle.name
            return
        }
        isSavingName = true
        defer { isSavingName = false }
        do {
            try await appState.renameCircle(liveCircle, to: trimmed)
        } catch {
            actionError = error.localizedDescription
            nameDraft = liveCircle.name
        }
    }

    private func remove(_ member: CircleMember) async {
        do {
            try await appState.circleRepository.removeMember(member, from: liveCircle)
            await load()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func leave() async {
        do {
            try await appState.circleRepository.leaveCircle(liveCircle)
            await appState.loadCircles()
            dismiss()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func deleteCircle() async {
        do {
            try await appState.circleRepository.deleteCircle(liveCircle)
            await appState.loadCircles()
            dismiss()
        } catch {
            actionError = error.localizedDescription
        }
    }
}

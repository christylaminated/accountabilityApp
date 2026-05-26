import SwiftUI

/// Inbox of pending friend requests, rendered at the top of `FriendsView`.
/// Reads `AppState.incomingFriendRequests` — the list is filtered upstream
/// (reciprocal/auto-accept requests are processed silently, declined requests
/// are hidden locally, already-friends are excluded), so anything that lands
/// here is something the user genuinely needs to act on.
struct FriendRequestsSection: View {
    @Environment(\.tallyAccent) private var tallyAccent
    @Environment(AppState.self) private var appState

    var body: some View {
        let requests = appState.incomingFriendRequests
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Friend requests")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Spacer()
                if !requests.isEmpty {
                    Text("\(requests.count)")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(tallyAccent)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
            ForEach(requests) { request in
                FriendRequestRow(request: request)
            }
        }
    }
}

/// Surfaces the actual CloudKit error from `refreshFriendRequests` so we don't
/// fly blind when index config or schema deploys are wrong. Tap to dismiss.
struct FriendRequestErrorBanner: View {
    @Environment(AppState.self) private var appState
    let message: String

    var body: some View {
        Button {
            appState.lastFriendRequestError = nil
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Friend-request sync error")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    Text(message)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
            }
            .padding(12)
            .background(Color.orange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct FriendRequestRow: View {
    @Environment(\.tallyAccent) private var tallyAccent
    @Environment(AppState.self) private var appState

    let request: FriendRequest

    @State private var inFlight = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                AvatarView(symbolName: request.fromAvatarSymbol, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.fromDisplayName)
                        .font(.body.weight(.semibold))
                    Text("@\(request.fromUsername)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 10) {
                Button {
                    Task { await accept() }
                } label: {
                    Text("Accept")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(tallyAccent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(inFlight)

                Button {
                    Task { await decline() }
                } label: {
                    Text("Decline")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.tallyCard)
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(inFlight)
            }
            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(14)
        .background(Color.tallyCard)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func accept() async {
        inFlight = true
        defer { inFlight = false }
        do {
            try await appState.acceptFriendRequest(request)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func decline() async {
        inFlight = true
        defer { inFlight = false }
        await appState.declineFriendRequest(request)
    }
}

// MARK: - Group invites

/// Inbox of pending group/DM invites. Mirrors `FriendRequestsSection` and
/// reads from `AppState.incomingGroupInvites` (filtered upstream to drop
/// declined invites and invites for Circles I'm already in).
struct GroupInvitesSection: View {
    @Environment(\.tallyAccent) private var tallyAccent
    @Environment(AppState.self) private var appState

    var body: some View {
        let invites = appState.incomingGroupInvites
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Group invites")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Spacer()
                if !invites.isEmpty {
                    Text("\(invites.count)")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(tallyAccent)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
            ForEach(invites) { invite in
                GroupInviteRow(invite: invite)
            }
        }
    }
}

/// Surfaces CloudKit errors from `refreshGroupInvites` — typically the
/// "field not marked queryable" error you get if the GroupInvite schema
/// isn't fully deployed to Production. Tap to dismiss.
struct GroupInviteErrorBanner: View {
    @Environment(AppState.self) private var appState
    let message: String

    var body: some View {
        Button {
            appState.lastGroupInviteError = nil
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Group-invite sync error")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    Text(message)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
            }
            .padding(12)
            .background(Color.orange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct GroupInviteRow: View {
    @Environment(\.tallyAccent) private var tallyAccent
    @Environment(AppState.self) private var appState

    let invite: GroupInvite

    @State private var inFlight = false
    @State private var error: String?

    /// "@bob invited you to chat" for DMs, "@bob invited you to ‹name›"
    /// for normal Groups. Reads from the invite payload so we don't need
    /// the Circle record on hand to render.
    private var headline: String {
        switch invite.circleKind {
        case .dm:    return "wants to message you"
        case .group: return "invited you to \(invite.circleName)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                AvatarView(symbolName: invite.fromAvatarSymbol, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(invite.fromDisplayName)
                        .font(.body.weight(.semibold))
                    Text("@\(invite.fromUsername) — \(headline)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 10) {
                Button {
                    Task { await accept() }
                } label: {
                    Text("Accept")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(tallyAccent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(inFlight)

                Button {
                    Task { await decline() }
                } label: {
                    Text("Decline")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.tallyCard)
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(inFlight)
            }
            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(14)
        .background(Color.tallyCard)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func accept() async {
        inFlight = true
        defer { inFlight = false }
        do {
            try await appState.acceptGroupInvite(invite)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func decline() async {
        inFlight = true
        defer { inFlight = false }
        await appState.declineGroupInvite(invite)
    }
}

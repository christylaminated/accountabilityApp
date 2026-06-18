import SwiftUI

/// Persistent dismissible banner on the Today tab that nudges the user
/// to invite friends post-onboarding. Hides permanently when the user
/// either (a) sends their first friend request via
/// `AppState.sendFriendRequest` (signal:
/// `LocalCacheKey.hasSentFirstFriendRequest`), or (b) dismisses the
/// banner 3 times (signal: `LocalCacheKey.inviteBannerDismissCount`).
///
/// Tapping the row opens the existing friend search flow via a
/// `@Binding<Bool>` the dashboard owns (so it can present its existing
/// `FriendSearchView` sheet). The X icon increments the dismiss count.
struct InviteFriendsBanner: View {
    @Environment(\.tallyAccent) private var tallyAccent

    /// Set to true to open the dashboard's friend-search sheet. The
    /// dashboard owns the sheet so the banner stays presentation-agnostic.
    @Binding var presentFriendSearch: Bool

    /// Re-render driver. The dashboard increments this when it persists a
    /// dismissal (or, in production, after a `refreshAccountState`) so
    /// the banner re-evaluates `shouldShow`.
    @Binding var revision: Int

    /// Single source of truth — derived from LocalCache each render so we
    /// don't need to mirror state.
    private var shouldShow: Bool {
        _ = revision // tie computed value to the revision binding
        let sentOne = LocalCache.load(Bool.self, forKey: LocalCacheKey.hasSentFirstFriendRequest) ?? false
        guard !sentOne else { return false }
        let dismissals = LocalCache.load(Int.self, forKey: LocalCacheKey.inviteBannerDismissCount) ?? 0
        return dismissals < 3
    }

    var body: some View {
        if shouldShow {
            HStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tallyAccent)
                    .frame(width: 28, height: 28)
                    .background(tallyAccent.opacity(0.18))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Invite friends to lock in with you")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.tallyTextPrimary)
                    Text("You're more likely to stick with it together.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.tallyTextSecondary)
                }

                Spacer()

                Button {
                    presentFriendSearch = true
                } label: {
                    Text("Invite")
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(tallyAccent)
                        .foregroundStyle(Color.tallyOnAccent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.tallyTextSecondary)
                        .frame(width: 24, height: 24)
                        .background(Color.tallyTextSecondary.opacity(0.10))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .padding(12)
            .background(Color.tallyCard)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func dismiss() {
        let count = LocalCache.load(Int.self, forKey: LocalCacheKey.inviteBannerDismissCount) ?? 0
        LocalCache.save(count + 1, forKey: LocalCacheKey.inviteBannerDismissCount)
        revision += 1
    }
}

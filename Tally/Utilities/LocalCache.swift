import Foundation

/// Thin wrapper around `UserDefaults` for JSON-encoded `Codable` values.
/// Used to cache the user's profile + personal data so the dashboard renders
/// immediately on launch (instead of waiting for the iCloud round-trip).
/// CloudKit refresh still runs in the background and atomically replaces the
/// cached arrays when fresh data arrives.
enum LocalCache {
    private static let defaults = UserDefaults.standard
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func save<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? encoder.encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    static func load<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    static func remove(forKey key: String) {
        defaults.removeObject(forKey: key)
    }

    /// Wipe user-scoped cache keys — used on iCloud account change so we don't
    /// show the previous user's data after a sign-in switch. UI preferences
    /// like `themeColor` survive the wipe.
    static func clearAll() {
        for key in LocalCacheKey.userScoped {
            remove(forKey: key)
        }
    }
}

enum LocalCacheKey {
    static let currentUserID = "Tally.cache.currentUserID"
    static let ownProfile = "Tally.cache.ownProfile"
    static let personalStore = "Tally.cache.personalStore"
    /// Dedicated boolean flag — once true, we skip the "Checking iCloud…"
    /// spinner on launch and go straight to the dashboard. Decoupled from the
    /// profile/userID caches so a partial decode never traps us on the spinner.
    static let hasOnboarded = "Tally.cache.hasOnboarded"

    /// True once the user has issued their first friend request via
    /// `AppState.sendFriendRequest`. Used by `InviteFriendsBanner` to
    /// permanently hide once the user has engaged with the friend flow,
    /// even if the recipient later declines or unfriends.
    static let hasSentFirstFriendRequest = "Tally.cache.hasSentFirstFriendRequest"

    /// How many times the Today-tab Invite Friends banner has been
    /// dismissed. At 3 the banner hides permanently. Resets on account
    /// switch / deleteAccount (it's userScoped).
    static let inviteBannerDismissCount = "Tally.cache.inviteBannerDismissCount"

    /// DEBUG-only override: when true, `SubscriptionManager.isSubscribed`
    /// returns true regardless of the real RevenueCat state, so a dev can
    /// test post-paywall flows on a sandbox account without paying. The
    /// key is NOT in `userScoped` because it's a per-device dev flag, and
    /// reads/writes are wrapped in `#if DEBUG` blocks so Release builds
    /// can't honor it even if the value got injected.
    static let debugPaywallBypass = "Tally.cache.debugPaywallBypass"

    /// The last persisted step in the paywalled onboarding state machine.
    /// Stored as the rawValue of `AppState.PersistedOnboardingStep`. Lets us
    /// resume the user mid-flow if they kill the app between (say) entering
    /// their name and reaching the paywall. Only the in-flow steps are
    /// persisted; transient states (.checkingICloud, .needsSignIn, .error)
    /// are never written.
    static let onboardingStep = "Tally.cache.onboardingStep"
    /// UI preference — not user-scoped, kept across account changes.
    static let themeColor = "Tally.cache.themeColor"

    /// Friend-request IDs the user dismissed locally. Recipients can't delete
    /// public-DB records they didn't create, so "decline" means "hide in our
    /// inbox" — persisted here so the request stays gone across launches.
    static let declinedFriendRequestIDs = "Tally.cache.declinedFriendRequestIDs"

    /// Group-invite IDs the user dismissed locally. Same constraint as
    /// declinedFriendRequestIDs — only the inviting owner can delete the
    /// underlying record, so we hide locally and persist.
    static let declinedGroupInviteIDs = "Tally.cache.declinedGroupInviteIDs"

    /// User record names of friends the user has unfriended on this
    /// device. Persisted because the friend's zone still lives in our
    /// sharedDB until they too leave the share, and we don't call
    /// `CKShare.removeParticipant` on the friend's share anymore (it
    /// raises NSExceptions on iOS 26 under certain CloudKit states,
    /// crashing the app). `PersonalStore.refresh` filters friend zones
    /// against this set so unfriended friends stay gone across launches.
    static let locallyUnfriendedIDs = "Tally.cache.locallyUnfriendedIDs"

    /// User record names of senders whose original friend request we
    /// accepted (we joined their share) but whose RECIPROCAL share-out
    /// failed mid-flow (addFriendParticipant, makePersonalShare, or
    /// send-reciprocal threw). Retried from the polling task so the
    /// bidirectional graph eventually completes — without this a partial
    /// failure on the recipient side leaves the sender's friend list
    /// permanently empty for that friend.
    static let pendingReciprocalSenders = "Tally.cache.pendingReciprocalSenders"

    /// Record IDs of UnfriendNotifications we've already processed (added
    /// the unfriender to our locallyUnfriendedIDs). Persisted so we don't
    /// re-process the same notification on every poll tick. Reset on
    /// account delete + iCloud account switch.
    static let processedUnfriendNotificationIDs = "Tally.cache.processedUnfriendNotificationIDs"

    /// Target userIDs whose outbound UnfriendNotification write failed and
    /// is queued for retry. Same shape/lifecycle as pendingReciprocalSenders.
    static let pendingUnfriendTargets = "Tally.cache.pendingUnfriendTargets"

    /// "circleID|userID" composite keys for group/DM invite writes that
    /// failed and are queued for retry. Same shape/lifecycle as
    /// pendingReciprocalSenders.
    static let pendingGroupInvites = "Tally.cache.pendingGroupInvites"

    /// Per-Circle "last time the user opened the chat" timestamps.
    /// Compared against each Circle's latest message timestamp to decide
    /// whether a row in FriendsView should render in an "unread" style.
    /// Keyed by Circle.id.uuidString → Double (timeIntervalSince1970).
    static let circleLastReadAt = "Tally.cache.circleLastReadAt"

    /// Per-Circle "latest message timestamp last observed by this device".
    /// Updated by CircleStore whenever it loads / refreshes a circle's
    /// messages. Lets FriendsView render unread state for circles the
    /// user has already activated at least once.
    static let circleLastMessageAt = "Tally.cache.circleLastMessageAt"

    /// Cache keys cleared on iCloud account switch.
    static let userScoped: [String] = [
        currentUserID, ownProfile, personalStore, hasOnboarded, onboardingStep,
        declinedFriendRequestIDs, declinedGroupInviteIDs,
        locallyUnfriendedIDs, pendingReciprocalSenders,
        processedUnfriendNotificationIDs, pendingUnfriendTargets,
        pendingGroupInvites,
        hasSentFirstFriendRequest, inviteBannerDismissCount
    ]
}

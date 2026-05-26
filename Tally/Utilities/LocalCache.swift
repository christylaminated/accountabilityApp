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

    /// Cache keys cleared on iCloud account switch.
    static let userScoped: [String] = [
        currentUserID, ownProfile, personalStore, hasOnboarded,
        declinedFriendRequestIDs, declinedGroupInviteIDs
    ]
}

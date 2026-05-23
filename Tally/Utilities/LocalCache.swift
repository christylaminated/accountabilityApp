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

    /// Wipe every cache key — used on iCloud account change so we don't show
    /// the previous user's data after a sign-in switch.
    static func clearAll() {
        for key in LocalCacheKey.all {
            remove(forKey: key)
        }
    }
}

enum LocalCacheKey {
    static let currentUserID = "Tally.cache.currentUserID"
    static let ownProfile = "Tally.cache.ownProfile"
    static let personalStore = "Tally.cache.personalStore"

    static let all: [String] = [currentUserID, ownProfile, personalStore]
}

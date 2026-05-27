import CloudKit
import Foundation

/// In-memory `UsernameRepository` for previews and tests.
final class MockUsernameRepository: UsernameRepository, @unchecked Sendable {
    /// username → (displayName, avatarSymbol, userRecordName)
    var claims: [String: UserSearchResult] = [:]
    /// Pretend "my" user id — controls which claims are considered mine.
    var currentUserRecordName: String = "mock-self"

    func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard (3...20).contains(trimmed.count) else { return nil }
        return trimmed
    }

    func isAvailable(_ normalized: String) async throws -> Bool {
        guard let existing = claims[normalized] else { return true }
        return existing.userRecordName == currentUserRecordName
    }

    func claim(
        _ normalized: String,
        previousUsername: String?,
        displayName: String,
        avatarSymbol: String,
        avatarImageData: Data?
    ) async throws {
        if let prev = previousUsername, prev != normalized {
            claims.removeValue(forKey: prev)
        }
        if let existing = claims[normalized], existing.userRecordName != currentUserRecordName {
            throw UsernameError.alreadyTaken
        }
        claims[normalized] = UserSearchResult(
            username: normalized,
            displayName: displayName,
            avatarSymbol: avatarSymbol,
            avatarImageData: avatarImageData,
            userRecordName: currentUserRecordName
        )
    }

    func release(_ normalized: String) async throws {
        claims.removeValue(forKey: normalized)
    }

    func lookup(_ normalized: String) async throws -> UserSearchResult? {
        claims[normalized]
    }
}

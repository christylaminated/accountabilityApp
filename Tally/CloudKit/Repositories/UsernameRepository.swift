import CloudKit
import Foundation

/// One row of the global username directory — found by `UsernameRepository`.
struct UserSearchResult: Hashable, Identifiable {
    /// The normalized username (lowercase, alphanumeric + underscore).
    var username: String
    var displayName: String
    var avatarSymbol: String
    var userRecordName: String

    var id: String { username }
}

enum UsernameError: LocalizedError {
    case invalid
    case alreadyTaken

    var errorDescription: String? {
        switch self {
        case .invalid:      return "Username must be 3–20 characters: letters, numbers, or underscores."
        case .alreadyTaken: return "That username is already taken."
        }
    }
}

/// Global username directory backed by CloudKit's *public* database. The
/// `recordName` of each `UsernameClaim` record IS the normalized username,
/// so CloudKit enforces uniqueness for us (you can't save two records with
/// the same name in the same zone).
///
/// Lookups are by direct fetch (`db.record(for:)`) so no Queryable index is
/// needed in the CloudKit Dashboard.
protocol UsernameRepository: Sendable {
    /// Normalize and validate a raw username input.
    /// Returns nil if the input doesn't satisfy the rules
    /// (3–20 chars, letters / digits / underscore).
    func normalize(_ raw: String) -> String?

    /// Check whether `normalized` is claimable by the current user. True if
    /// nobody owns it, or the current user already owns it.
    func isAvailable(_ normalized: String) async throws -> Bool

    /// Claim `normalized` for the current user. Frees `previousUsername` (if
    /// different) before claiming. Throws `UsernameError.alreadyTaken` if
    /// someone else owns it.
    func claim(
        _ normalized: String,
        previousUsername: String?,
        displayName: String,
        avatarSymbol: String
    ) async throws

    /// Release the user's username (e.g., if they delete their account). No-op
    /// if there's nothing to release.
    func release(_ normalized: String) async throws

    /// Look up a user by exact username. Returns nil if no claim exists.
    func lookup(_ normalized: String) async throws -> UserSearchResult?
}

// MARK: - CloudKit implementation

struct CloudKitUsernameRepository: UsernameRepository {
    let client: CKClient
    static let recordType = "UsernameClaim"

    init(client: CKClient = .shared) {
        self.client = client
    }

    private var publicDB: CKDatabase { client.container.publicCloudDatabase }

    private static let allowedChars: CharacterSet = CharacterSet.lowercaseLetters
        .union(.decimalDigits)
        .union(CharacterSet(charactersIn: "_"))

    func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard (3...20).contains(trimmed.count) else { return nil }
        // Reject if any character is outside the allowed set.
        if trimmed.unicodeScalars.contains(where: { !Self.allowedChars.contains($0) }) {
            return nil
        }
        return trimmed
    }

    func isAvailable(_ normalized: String) async throws -> Bool {
        let recordID = CKRecord.ID(recordName: normalized)
        do {
            let existing = try await publicDB.record(for: recordID)
            // Available if it's already mine.
            return try await isCreatedByMe(existing)
        } catch let error as CKError where error.code == .unknownItem {
            return true
        }
    }

    func claim(
        _ normalized: String,
        previousUsername: String?,
        displayName: String,
        avatarSymbol: String
    ) async throws {
        // Release the old claim first (so re-naming "alice" → "alyce" frees
        // "alice" for someone else). Best-effort: ignore any delete failure.
        if let prev = previousUsername, prev != normalized {
            _ = try? await publicDB.deleteRecord(withID: CKRecord.ID(recordName: prev))
        }

        let recordID = CKRecord.ID(recordName: normalized)
        do {
            let existing = try await publicDB.record(for: recordID)
            // Someone has this name — has to be me to update it.
            guard try await isCreatedByMe(existing) else {
                throw UsernameError.alreadyTaken
            }
            existing["displayName"] = displayName
            existing["avatarSymbol"] = avatarSymbol
            _ = try await publicDB.save(existing)
        } catch let error as CKError where error.code == .unknownItem {
            // Unclaimed — claim it fresh.
            let record = CKRecord(recordType: Self.recordType, recordID: recordID)
            record["displayName"] = displayName
            record["avatarSymbol"] = avatarSymbol
            _ = try await publicDB.save(record)
        }
    }

    func release(_ normalized: String) async throws {
        _ = try? await publicDB.deleteRecord(withID: CKRecord.ID(recordName: normalized))
    }

    func lookup(_ normalized: String) async throws -> UserSearchResult? {
        let recordID = CKRecord.ID(recordName: normalized)
        do {
            let record = try await publicDB.record(for: recordID)
            guard
                let displayName = record["displayName"] as? String,
                let avatarSymbol = record["avatarSymbol"] as? String,
                let creatorID = record.creatorUserRecordID
            else { return nil }
            return UserSearchResult(
                username: normalized,
                displayName: displayName,
                avatarSymbol: avatarSymbol,
                userRecordName: try await resolveCreatorRecordName(creatorID)
            )
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    /// Did the *current* iCloud user create this record?
    ///
    /// CloudKit returns the `CKCurrentUserDefaultName` sentinel ("__defaultOwner__")
    /// for `creatorUserRecordID` when the current user is the creator — comparing
    /// directly to `client.userRecordID()` would give a false negative because
    /// the sentinel doesn't match the actual record ID string. Treat the sentinel
    /// as a yes, otherwise compare to our real ID.
    private func isCreatedByMe(_ record: CKRecord) async throws -> Bool {
        guard let creatorID = record.creatorUserRecordID else { return false }
        if creatorID.recordName == CKCurrentUserDefaultName { return true }
        let myUserID = try await client.userRecordID()
        return creatorID == myUserID
    }

    /// Same sentinel quirk as above but for the *outbound* path — `lookup` returns
    /// a record name that other code uses as a recipient ID. Substitute our real
    /// user record ID when the lookup hits our own record, so downstream
    /// equality checks (e.g., FriendRequest.toUserRecordName == currentUserID)
    /// actually match.
    private func resolveCreatorRecordName(_ creatorID: CKRecord.ID) async throws -> String {
        if creatorID.recordName == CKCurrentUserDefaultName {
            return try await client.userRecordID().recordName
        }
        return creatorID.recordName
    }
}

import CloudKit
import Foundation

/// CRUD for the user's own profile. Step 2 only exposes own-profile read/write —
/// partner profile lookup happens via `CircleMember` records in shared zones
/// (step 3), so this protocol stays narrow.
protocol ProfileRepository: Sendable {
    /// Fetch the signed-in user's profile. Returns nil if no profile exists yet
    /// (first-launch, pre-onboarding).
    func ownProfile() async throws -> UserProfile?

    /// Create or update the signed-in user's profile. Returns the saved record.
    /// `username` is optional — uniqueness is enforced separately by
    /// `UsernameRepository` against the public DB. `avatarImageData` is
    /// optional JPEG bytes (a user-uploaded photo); pass nil to keep the
    /// stored avatar (or remove it via `clearAvatarPhoto: true`).
    func saveOwnProfile(
        displayName: String,
        avatarSymbol: String,
        avatarImageData: Data?,
        clearAvatarPhoto: Bool,
        username: String?
    ) async throws -> UserProfile
}

/// CloudKit-backed implementation. Stores one `UserProfile` record at a fixed
/// recordName in the private DB's default zone — easy to look up without a query.
struct CloudKitProfileRepository: ProfileRepository {
    let client: CKClient

    /// Fixed recordName for the singleton UserProfile record. Using a stable name
    /// (rather than the user's iCloud recordName) avoids needing a query on the
    /// default private zone, which CloudKit limits.
    static let ownProfileRecordName = "ownProfile"

    init(client: CKClient = .shared) {
        self.client = client
    }

    private var ownProfileRecordID: CKRecord.ID {
        CKRecord.ID(recordName: Self.ownProfileRecordName)
    }

    func ownProfile() async throws -> UserProfile? {
        do {
            let record = try await client.privateDB.record(for: ownProfileRecordID)
            return UserProfile(record: record)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    func saveOwnProfile(
        displayName: String,
        avatarSymbol: String,
        avatarImageData: Data?,
        clearAvatarPhoto: Bool,
        username: String?
    ) async throws -> UserProfile {
        // Update-if-exists, create-if-not. CloudKit doesn't have an "upsert"
        // so we read first; on `.unknownItem` we build a fresh record.
        let record: CKRecord
        var existingPhoto: Data? = nil
        do {
            let existing = try await client.privateDB.record(for: ownProfileRecordID)
            existingPhoto = existing["avatarImageData"] as? Data
            record = existing
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: UserProfile.recordType, recordID: ownProfileRecordID)
        }

        // Three-way merge for the photo:
        //   - clearAvatarPhoto: force-nil (user removed their photo).
        //   - avatarImageData != nil: replace with the new photo.
        //   - both nil: keep what's already stored (avoids accidentally
        //     wiping the photo when the caller only intends to update name).
        let resolvedPhoto: Data?
        if clearAvatarPhoto {
            resolvedPhoto = nil
        } else if let avatarImageData {
            resolvedPhoto = avatarImageData
        } else {
            resolvedPhoto = existingPhoto
        }

        let profile = UserProfile(
            displayName: displayName,
            avatarSymbol: avatarSymbol,
            avatarImageData: resolvedPhoto,
            username: username,
            createdAt: (record["createdAt"] as? Date) ?? .now
        )
        profile.populate(record)
        _ = try await client.privateDB.save(record)
        return profile
    }
}

// MARK: - DayNote repository

/// CRUD for the user's private per-day history notes. Same storage strategy as
/// `ProfileRepository`: one record per day at a stable recordName in the private
/// DB's default zone, so a note is fetched directly by ID (no query) and never
/// syncs to friends (unlike the shared personal zone).
protocol DayNoteRepository: Sendable {
    /// The note for `day`, or nil if none has been written.
    func note(for day: Date) async throws -> DayNote?
    /// Create or overwrite the note for `note.day`.
    func save(_ note: DayNote) async throws
    /// Remove the note for `day` (used when the user clears the text).
    func delete(for day: Date) async throws
}

struct CloudKitDayNoteRepository: DayNoteRepository {
    let client: CKClient

    init(client: CKClient = .shared) {
        self.client = client
    }

    private func recordID(for day: Date) -> CKRecord.ID {
        CKRecord.ID(recordName: DayNote.recordName(for: day))
    }

    func note(for day: Date) async throws -> DayNote? {
        do {
            let record = try await client.privateDB.record(for: recordID(for: day))
            return DayNote(record: record)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    func save(_ note: DayNote) async throws {
        let id = recordID(for: note.day)
        let record: CKRecord
        do {
            record = try await client.privateDB.record(for: id)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: DayNote.recordType, recordID: id)
        }
        note.populate(record)
        _ = try await client.privateDB.save(record)
    }

    func delete(for day: Date) async throws {
        _ = try? await client.privateDB.deleteRecord(withID: recordID(for: day))
    }
}

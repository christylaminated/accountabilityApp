import Foundation
import Observation

/// In-memory profile repository for SwiftUI Previews and tests. Conforms to the
/// same `ProfileRepository` protocol the CloudKit implementation does, so views
/// and AppState don't care which one is injected.
///
/// Pass `profile: nil` to simulate the first-launch / pre-onboarding state.
@Observable
final class MockProfileRepository: ProfileRepository, @unchecked Sendable {
    private(set) var stored: UserProfile?

    init(profile: UserProfile? = UserProfile(
        displayName: "You",
        avatarSymbol: "leaf",
        avatarImageData: nil,
        username: nil,
        createdAt: .now
    )) {
        self.stored = profile
    }

    func ownProfile() async throws -> UserProfile? {
        return stored
    }

    func saveOwnProfile(
        displayName: String,
        avatarSymbol: String,
        avatarImageData: Data?,
        clearAvatarPhoto: Bool,
        username: String?
    ) async throws -> UserProfile {
        let resolvedPhoto: Data?
        if clearAvatarPhoto {
            resolvedPhoto = nil
        } else if let avatarImageData {
            resolvedPhoto = avatarImageData
        } else {
            resolvedPhoto = stored?.avatarImageData
        }
        let profile = UserProfile(
            displayName: displayName,
            avatarSymbol: avatarSymbol,
            avatarImageData: resolvedPhoto,
            username: username,
            createdAt: stored?.createdAt ?? .now
        )
        stored = profile
        return profile
    }
}

/// In-memory `DayNoteRepository` for previews and tests.
final class MockDayNoteRepository: DayNoteRepository, @unchecked Sendable {
    /// dayKey → note.
    var notes: [String: DayNote] = [:]

    func note(for day: Date) async throws -> DayNote? {
        notes[DayNote.dayKey(day)]
    }

    func save(_ note: DayNote) async throws {
        notes[DayNote.dayKey(note.day)] = note
    }

    func delete(for day: Date) async throws {
        notes.removeValue(forKey: DayNote.dayKey(day))
    }
}

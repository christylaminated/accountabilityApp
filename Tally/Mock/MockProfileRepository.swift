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
        username: String?
    ) async throws -> UserProfile {
        let profile = UserProfile(
            displayName: displayName,
            avatarSymbol: avatarSymbol,
            username: username,
            createdAt: stored?.createdAt ?? .now
        )
        stored = profile
        return profile
    }
}

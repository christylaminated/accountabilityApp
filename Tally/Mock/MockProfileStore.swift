import Foundation
import Observation

@Observable
final class MockProfileStore {
    var profiles: [Profile]

    init(profiles: [Profile] = MockData.profiles) {
        self.profiles = profiles
    }

    func profile(id: UUID) -> Profile? {
        profiles.first { $0.id == id }
    }

    /// Mirror the user's CloudKit profile into the mock layer so views that still
    /// read the mock (dashboard, member row) show the real name + symbol. Called
    /// from AppState after onboarding completes.
    func updateProfile(id: UUID, displayName: String, avatarSymbol: String) {
        guard let i = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[i].displayName = displayName
        profiles[i].avatarSymbol = avatarSymbol
    }
}

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
}

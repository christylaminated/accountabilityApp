import CloudKit
import Foundation

/// In-memory `CircleDataRepository` for SwiftUI previews and tests. No CloudKit.
final class MockCircleDataRepository: CircleDataRepository, @unchecked Sendable {
    var snapshot = CircleSnapshot()

    init(snapshot: CircleSnapshot = CircleSnapshot()) {
        self.snapshot = snapshot
    }

    func snapshot(for circle: TallyCircle, since token: CKServerChangeToken?) async throws -> CircleSnapshot {
        snapshot
    }

    func save(_ records: [any ZoneRecord], in circle: TallyCircle) async throws {}

    func delete(recordNames: [String], in circle: TallyCircle) async throws {}

    func subscribeToChanges(for circle: TallyCircle) async throws {}
}

import CloudKit
import Foundation

/// In-memory `CircleDataRepository` for SwiftUI previews and tests. No CloudKit.
final class MockCircleDataRepository: CircleDataRepository, @unchecked Sendable {
    var snapshot = CircleSnapshot()
    /// When true, `save` throws — lets tests exercise the send-failure /
    /// crash-durable-outbox path.
    var saveShouldFail = false
    /// Record names successfully saved, for test assertions.
    var savedRecordNames: [String] = []
    /// Record names passed to `delete`, for test assertions.
    var deletedRecordNames: [String] = []

    init(snapshot: CircleSnapshot = CircleSnapshot()) {
        self.snapshot = snapshot
    }

    func snapshot(for circle: TallyCircle, since token: CKServerChangeToken?) async throws -> CircleSnapshot {
        snapshot
    }

    func save(_ records: [any ZoneRecord], in circle: TallyCircle) async throws {
        if saveShouldFail {
            throw NSError(domain: "MockCircleDataRepository", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Circle zone not found"])
        }
        savedRecordNames.append(contentsOf: records.map(\.recordName))
    }

    func delete(recordNames: [String], in circle: TallyCircle) async throws {
        deletedRecordNames.append(contentsOf: recordNames)
    }

    func subscribeToChanges(for circle: TallyCircle) async throws {}
}

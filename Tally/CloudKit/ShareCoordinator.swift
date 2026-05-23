import CloudKit
import Foundation

/// Runs `CKAcceptSharesOperation` for an incoming Circle invite, then resolves
/// which Circle was joined so `AppState` can record membership + refresh.
struct ShareCoordinator {
    let client: CKClient

    init(client: CKClient = .shared) {
        self.client = client
    }

    /// Accept a pending share. Returns the Circle UUID derived from the shared
    /// zone name (zones are named `circle-{uuid}`). Throws on CK failure.
    @discardableResult
    func accept(_ metadata: CKShare.Metadata) async throws -> UUID {
        try await withCheckedThrowingContinuation { continuation in
            let op = CKAcceptSharesOperation(shareMetadatas: [metadata])
            op.qualityOfService = .userInitiated

            op.acceptSharesResultBlock = { result in
                switch result {
                case .success:
                    if let circleID = Self.circleID(from: metadata) {
                        continuation.resume(returning: circleID)
                    } else {
                        continuation.resume(
                            throwing: CKClientError.unexpected(
                                "Accepted share but couldn't resolve the Circle ID."
                            )
                        )
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            client.container.add(op)
        }
    }

    /// Derive the Circle UUID from the share's zone name. Prefer the hierarchical
    /// root's zone; fall back to the share record's zone.
    private static func circleID(from metadata: CKShare.Metadata) -> UUID? {
        let zoneName: String
        if let rootZone = metadata.hierarchicalRootRecordID?.zoneID.zoneName {
            zoneName = rootZone
        } else {
            zoneName = metadata.share.recordID.zoneID.zoneName
        }
        return CKClient.circleID(fromZoneName: zoneName)
    }
}

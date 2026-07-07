import CloudKit
import Foundation

/// Runs `CKAcceptSharesOperation` for an incoming CKShare invite. Doesn't
/// interpret what kind of share it is — the caller inspects the metadata
/// (via the helpers below) to route Circle vs personal-share accepts.
struct ShareCoordinator {
    let client: CKClient

    init(client: CKClient = .shared) {
        self.client = client
    }

    /// Accept a pending CKShare invite. Throws on CK failure.
    func acceptShare(_ metadata: CKShare.Metadata) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let op = CKAcceptSharesOperation(shareMetadatas: [metadata])
            op.qualityOfService = .userInitiated
            op.acceptSharesResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            client.container.add(op)
        }
    }

    /// Zone name of the share's root record — used to disambiguate which kind
    /// of share this is (Circle zones are `circle-<uuid>`, personal zones
    /// share the fixed `personalData` name).
    static func zoneName(from metadata: CKShare.Metadata) -> String {
        metadata.hierarchicalRootRecordID?.zoneID.zoneName
            ?? metadata.share.recordID.zoneID.zoneName
    }

    /// Convenience: extract a Circle UUID if this metadata represents a Circle
    /// share. Returns nil for personal-share invites or anything unrecognized.
    static func circleID(from metadata: CKShare.Metadata) -> UUID? {
        CKClient.circleID(fromZoneName: zoneName(from: metadata))
    }
}

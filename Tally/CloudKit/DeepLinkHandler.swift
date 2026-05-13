import SwiftUI
import CloudKit
import Combine

/// App-level delegate. Step 1 scope: capture incoming CKShare invite acceptances
/// and surface them through a shared buffer that `ShareCoordinator` (step 3) will
/// drain to run `CKAcceptSharesOperation`.
///
/// Push registration is added in step 7.
final class TallyAppDelegate: NSObject, UIApplicationDelegate {
    /// Buffer for pending share metadata. Wired into the SwiftUI environment by
    /// `TallyApp` so views and coordinators can observe and consume invites.
    let pendingShares = PendingShareBuffer()

    /// Invoked by iOS when the user taps a CKShare URL (Messages / AirDrop / email)
    /// and the system routes them back to Tally. The metadata identifies the share;
    /// `ShareCoordinator` will accept it via `CKAcceptSharesOperation`.
    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith metadata: CKShare.Metadata
    ) {
        pendingShares.set(metadata)
    }
}

/// Holds the most recent `CKShare.Metadata` received via deep link. Surfaces it via
/// `@Published` so SwiftUI views react. `ShareCoordinator` calls `consume()` once
/// it's ready to accept; that clears the buffer so a re-foregrounding doesn't
/// double-accept.
final class PendingShareBuffer: ObservableObject {
    @Published private(set) var metadata: CKShare.Metadata?

    func set(_ metadata: CKShare.Metadata) {
        self.metadata = metadata
    }

    /// Read-and-clear in one step. Returns nil if no invite is pending.
    @discardableResult
    func consume() -> CKShare.Metadata? {
        let m = metadata
        metadata = nil
        return m
    }
}

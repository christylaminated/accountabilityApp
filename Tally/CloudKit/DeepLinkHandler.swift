import SwiftUI
import CloudKit
import Combine

/// Posted when a CloudKit silent push tells us a Circle's data changed.
/// `AppState` observes this and refreshes the active Circle.
extension Notification.Name {
    static let tallyRemoteChange = Notification.Name("tallyRemoteChange")
    /// Posted (with the `Error` as the object) when the share sheet flow can't
    /// mint or save the CKShare. AppState surfaces this in an alert so the
    /// underlying iCloud error becomes visible instead of iOS's generic
    /// "A link couldn't be created" wrapper.
    static let tallyCloudShareError = Notification.Name("tallyCloudShareError")
}

/// App-level delegate. Captures incoming CKShare invite acceptances and registers
/// for the silent CloudKit pushes that drive live updates between friends.
final class TallyAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Silent (content-available) pushes need no user permission — just APNs
        // registration so CloudKit zone subscriptions can reach this device.
        application.registerForRemoteNotifications()
        return true
    }

    /// Invoked by iOS when the user taps a CKShare URL (Messages / AirDrop / email)
    /// and the system routes them back to Tally. We write to the shared buffer —
    /// not an AppState reference — because the deep link can fire before AppState
    /// is constructed (cold launch from the invite URL).
    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith metadata: CKShare.Metadata
    ) {
        PendingShareBuffer.shared.set(metadata)
    }

    /// A CloudKit zone subscription fired — a friend changed something. Tell
    /// `AppState` to pull the delta. Works in the foreground always, and in the
    /// background when the `remote-notification` background mode is enabled.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        NotificationCenter.default.post(name: .tallyRemoteChange, object: nil)
        return .newData
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Non-fatal: the app still works, just without live push (foreground
        // refresh and pull-to-refresh still sync).
        print("Remote notification registration failed: \(error.localizedDescription)")
    }
}

/// Single source of truth for a pending CKShare invite. A shared singleton so it
/// exists from first access — surviving the gap between a cold-launch deep link
/// and `AppState.init`. `AppState` reads it via `AppState.pendingShareBuffer`
/// (which points at `.shared`) and consumes it once accepted.
final class PendingShareBuffer: ObservableObject {
    static let shared = PendingShareBuffer()

    @Published private(set) var metadata: CKShare.Metadata?

    private init() {}

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

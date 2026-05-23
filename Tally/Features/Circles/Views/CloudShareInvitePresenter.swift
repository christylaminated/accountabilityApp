import CloudKit
import UIKit

/// Presents the system `UICloudSharingController` over the topmost view
/// controller — i.e., the way Apple's own sample code uses it.
///
/// Why not host it inside a SwiftUI `.sheet`? Because `UICloudSharingController`
/// expects to be *presented modally from* another view controller; its
/// `preparationHandler` lifecycle (and the share UI itself) doesn't render
/// when it's the root of a UIViewControllerRepresentable. You get a blank
/// sheet. Routing it through UIKit's modal presentation directly is the only
/// reliable way to get the share UI on screen.
@MainActor
enum CloudShareInvitePresenter {
    /// Present the system invite sheet. `prepare` runs when the controller asks
    /// for its share; it should return a SERVER-saved `CKShare` and the
    /// matching `CKContainer`.
    static func present(prepare: @escaping @Sendable () async throws -> (CKShare, CKContainer)) {
        guard let topVC = topViewController() else {
            print("CloudShareInvitePresenter: no view controller to present from")
            return
        }
        let controller = UICloudSharingController { _, completion in
            Task { @MainActor in
                do {
                    let (share, container) = try await prepare()
                    completion(share, container, nil)
                } catch {
                    // Surface the real CloudKit error to the UI instead of
                    // letting iOS swallow it into "A link couldn't be created".
                    NotificationCenter.default.post(name: .tallyCloudShareError, object: error)
                    completion(nil, nil, error)
                }
            }
        }
        // `.allowReadWrite` matches our trust model (participants write their
        // own habits / completions / messages). `.allowPrivate` keeps the
        // Circle invite-only.
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        controller.delegate = CloudShareDelegate.shared
        topVC.present(controller, animated: true)
    }

    /// Walk the foreground window's presentation stack to find the topmost VC
    /// (e.g., a currently-open SwiftUI sheet's host) and present from there.
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: { $0.isKeyWindow })
            ?? scenes.flatMap(\.windows).first
        var current = window?.rootViewController
        while let presented = current?.presentedViewController {
            current = presented
        }
        return current
    }
}

/// Singleton delegate — `UICloudSharingController.delegate` is `weak`, so we
/// need a long-lived object to back it across the share flow.
private final class CloudShareDelegate: NSObject, UICloudSharingControllerDelegate {
    static let shared = CloudShareDelegate()

    func cloudSharingController(
        _ csc: UICloudSharingController,
        failedToSaveShareWithError error: Error
    ) {
        // This fires when the controller's own save (e.g. adding a participant
        // or minting an invite link) fails. Surface the error so it's visible
        // in the app, not just buried in iOS's generic alert.
        NSLog("CKShare save failed: %@", String(describing: error))
        NotificationCenter.default.post(name: .tallyCloudShareError, object: error)
    }

    func itemTitle(for csc: UICloudSharingController) -> String? {
        "Join my Tally Circle"
    }

    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {}
    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {}
}

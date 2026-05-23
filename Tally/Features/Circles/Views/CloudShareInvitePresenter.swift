import CloudKit
import UIKit

/// Presents the system share sheet for a CKShare over the topmost view
/// controller — i.e., the way Apple recommends in iOS 17+.
///
/// History note: earlier versions used `UICloudSharingController` (with its
/// `preparationHandler` initializer). That class is deprecated as of iOS 17;
/// Apple's replacement is to pre-save the share and hand it to a regular
/// `UIActivityViewController` with the share + container as activity items.
/// The system knows how to share a `CKShare` — it extracts the invite URL and
/// routes it through whichever method the user picks (Messages, Mail, etc.).
@MainActor
enum CloudShareInvitePresenter {
    /// Mint/fetch the CKShare via `prepare`, then present the system share
    /// sheet. On failure, post `.tallyCloudShareError` so the app can surface
    /// the actual CloudKit error instead of swallowing it.
    static func present(prepare: @escaping @Sendable () async throws -> (CKShare, CKContainer)) {
        Task { @MainActor in
            do {
                let (share, container) = try await prepare()
                guard let topVC = topViewController() else {
                    print("CloudShareInvitePresenter: no view controller to present from")
                    return
                }
                let avc = UIActivityViewController(
                    activityItems: [share, container],
                    applicationActivities: nil
                )
                configureForIPad(avc, on: topVC)
                topVC.present(avc, animated: true)
            } catch {
                NotificationCenter.default.post(name: .tallyCloudShareError, object: error)
            }
        }
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

    /// Without a source view, `UIActivityViewController` crashes when presented
    /// as a popover on iPad. Anchor it to the top VC's center so it has
    /// somewhere to point at.
    private static func configureForIPad(
        _ avc: UIActivityViewController,
        on source: UIViewController
    ) {
        guard let popover = avc.popoverPresentationController else { return }
        popover.sourceView = source.view
        popover.sourceRect = CGRect(
            x: source.view.bounds.midX,
            y: source.view.bounds.midY,
            width: 0, height: 0
        )
        popover.permittedArrowDirections = []
    }
}

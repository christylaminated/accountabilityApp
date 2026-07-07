import Foundation
import Observation
import RevenueCat

/// Single point of contact between Tally and the IAP layer. Everything in
/// the app reads `isSubscribed` or `currentOffering` from here; nothing
/// else imports RevenueCat. Swap the underlying SDK by rewriting this
/// file and keeping the surface area the same.
///
/// Lifecycle:
///   - `init` configures `Purchases` once with the API key and starts a
///     `customerInfoStream` task so `isSubscribed` updates automatically
///     when the entitlement state changes (renewal, cancel, refund,
///     restore on another device).
///   - `refreshStatus()` is also called on demand (app launch, scene
///     foreground) to bring `isSubscribed` and `currentOffering` up to
///     date without waiting for the next stream event.
///
/// Errors / degraded states:
///   - `loadError` is set when the initial offerings fetch fails (e.g.
///     network down at launch). The paywall reads it to render a "Retry"
///     button instead of blocking the app entirely.
///   - `purchase(_:)` does NOT throw on user-cancellation; it just
///     completes and `isSubscribed` stays false. The paywall checks
///     `isSubscribed` after the call to decide whether to navigate.
///     Real failures (network, declined card) throw and surface as an
///     inline message.
@MainActor
@Observable
final class SubscriptionManager {
    /// The real RevenueCat-driven entitlement. Read through `isSubscribed`,
    /// which in Debug builds also honors `debugBypassPaywall`.
    private(set) var realIsSubscribed: Bool = false
    private(set) var currentOffering: Offering?
    private(set) var loadError: String?

    /// `true` if the user holds the `premium` entitlement OR (in Debug
    /// builds) the dev bypass toggle is on. The gate views read this; the
    /// underlying RevenueCat-state is in `realIsSubscribed` for when the
    /// distinction matters.
    var isSubscribed: Bool {
        #if DEBUG
        if debugBypassPaywall { return true }
        #endif
        return realIsSubscribed
    }

    #if DEBUG
    /// Per-device dev flag that flips `isSubscribed` true without an actual
    /// purchase. Persisted to LocalCache so it survives relaunch (devs
    /// shouldn't have to re-toggle every run). Stripped from Release.
    var debugBypassPaywall: Bool = false {
        didSet {
            LocalCache.save(debugBypassPaywall, forKey: LocalCacheKey.debugPaywallBypass)
        }
    }
    #endif

    private var customerInfoTask: Task<Void, Never>?

    init() {
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: SubscriptionConfig.revenueCatAPIKey)
        #if DEBUG
        self.debugBypassPaywall = LocalCache.load(Bool.self, forKey: LocalCacheKey.debugPaywallBypass) ?? false
        #endif
        startCustomerInfoStream()
        Task { [weak self] in await self?.refreshStatus() }
    }

    /// Refresh both entitlement state and the offerings catalog. Safe to
    /// call repeatedly — sets `loadError` on failure rather than throwing,
    /// so callers can render a degraded paywall without try/catch ceremony.
    func refreshStatus() async {
        do {
            let info = try await Purchases.shared.customerInfo()
            applyCustomerInfo(info)
            let offerings = try await Purchases.shared.offerings()
            // Prefer the explicitly-named offering; fall back to RC's
            // "current" so a misconfigured dashboard still surfaces packages.
            currentOffering = offerings.offering(identifier: SubscriptionConfig.offeringID)
                ?? offerings.current
            loadError = nil
        } catch {
            loadError = error.localizedDescription
            NSLog("[Tally] SubscriptionManager.refreshStatus failed: \(error.localizedDescription)")
        }
    }

    /// Attempt to purchase a package. Returns normally on success OR
    /// user-cancellation — the caller distinguishes them by reading
    /// `isSubscribed` afterward. Throws on real errors (network failure,
    /// payment decline, store error) so the paywall can show an inline
    /// message.
    func purchase(_ package: Package) async throws {
        let result = try await Purchases.shared.purchase(package: package)
        applyCustomerInfo(result.customerInfo)
        // result.userCancelled is intentionally NOT treated as an error —
        // the paywall stays put and the user can try again.
    }

    /// Restore previously-purchased entitlements (re-install, new device).
    /// Updates `isSubscribed` from the resulting CustomerInfo.
    func restorePurchases() async throws {
        let info = try await Purchases.shared.restorePurchases()
        applyCustomerInfo(info)
    }

    /// Subscribe to RevenueCat's live customer-info updates so a renewal
    /// or cancellation on another device flips `isSubscribed` here without
    /// requiring a manual refresh.
    private func startCustomerInfoStream() {
        customerInfoTask = Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                await MainActor.run { self?.applyCustomerInfo(info) }
            }
        }
    }

    private func applyCustomerInfo(_ info: CustomerInfo) {
        realIsSubscribed = info.entitlements[SubscriptionConfig.entitlementID]?.isActive == true
    }
}

import Foundation

/// RevenueCat configuration values. Single source of truth for the API key,
/// entitlement, offering, and product identifiers used by SubscriptionManager.
///
/// `revenueCatAPIKey` is a placeholder — replace with the real key from the
/// RevenueCat dashboard before shipping. The other identifiers must match
/// what's configured in App Store Connect + RevenueCat:
///   - Entitlement `premium` is granted by either subscription product.
///   - Offering `default` is the one the paywall reads packages from.
///   - Product IDs match the ASC subscriptions.
enum SubscriptionConfig {
    // TODO(christy): replace before shipping — RevenueCat public API key.
    static let revenueCatAPIKey = "REVENUECAT_API_KEY_HERE"

    static let entitlementID = "premium"
    static let offeringID = "default"

    static let monthlyProductID = "tally_monthly_5_99"
    static let annualProductID = "tally_annual_39_99"
}

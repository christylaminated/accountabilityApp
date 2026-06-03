import SwiftUI
import RevenueCat

/// Screen 6 — the paywall. Non-dismissible: there is no close button, no
/// drag indicator, no swipe-down gesture, and no back button. The user
/// either subscribes (or starts the free trial) or restores a previous
/// purchase. The display name is in the headline ("Lock in with [name]"
/// — known conversion lever).
///
/// On a successful purchase or restore, `SubscriptionManager.isSubscribed`
/// flips to true and we call `AppState.completePaywall()`. A canceled
/// system sheet leaves us silently on the paywall (no error shown). A
/// real failure (network, declined card) shows an inline message.
///
/// Degraded state: when `SubscriptionManager.currentOffering` is nil
/// because the offerings fetch failed (e.g. network down at launch), we
/// render a "Retry" button instead of disabled CTAs so the user can
/// recover without killing the app.
///
/// The legal disclosure text below the CTA is intentionally body-sized
/// (not micro-fine-print) — Apple requires it to be clearly readable in
/// review.
struct PaywallView: View {
    @Environment(AppState.self) private var appState
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(\.openURL) private var openURL

    @State private var selection: Selection = .annual
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var errorMessage: String?

    #if DEBUG
    @State private var heroTapCount: Int = 0
    @State private var showDebugMenu = false
    #endif

    // TODO(christy): replace with the real legal URLs before shipping.
    private let termsURL = URL(string: "https://example.com/tally-terms")!
    private let privacyURL = URL(string: "https://example.com/tally-privacy")!

    private var displayName: String {
        appState.ownCloudProfile?.displayName ?? "you"
    }

    private var offering: Offering? { subscriptions.currentOffering }
    private var annualPackage: Package? { offering?.annual }
    private var monthlyPackage: Package? { offering?.monthly }

    private var selectedPackage: Package? {
        switch selection {
        case .annual:  return annualPackage
        case .monthly: return monthlyPackage
        }
    }

    private var hasOfferings: Bool {
        annualPackage != nil || monthlyPackage != nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                hero
                valueBullets

                if hasOfferings {
                    priceCards
                    ctaButton
                    legalCopy
                } else {
                    degradedState
                }

                restoreButton
                links
                Spacer().frame(height: 24)
            }
            .padding(.horizontal, 24)
            .padding(.top, 56)
        }
        .background(Color.tallyCanvas)
        .scrollDismissesKeyboard(.interactively)
        // The non-dismissibility we promise the spec is enforced by:
        //   - presenting this view as a top-level state machine case,
        //     not a sheet (no system swipe-down).
        //   - no NavigationStack here (no back button).
        //   - no close X.
        .interactiveDismissDisabled(true)
        .task {
            if !hasOfferings && subscriptions.loadError != nil {
                await subscriptions.refreshStatus()
            }
            // If the entitlement is already true on appear (debug bypass,
            // restore from another device, RC stream raced ahead), advance
            // immediately. `completePaywall` is state-guarded so this is a
            // no-op when used as a lapse-cover over the main app.
            if subscriptions.isSubscribed {
                appState.completePaywall()
            }
        }
        // Fires when isSubscribed flips after the screen appeared — covers
        // real purchases that go through `purchase()`, restores, the
        // CustomerInfo stream catching up, AND the DEBUG bypass toggle.
        .onChange(of: subscriptions.isSubscribed) { _, isSub in
            if isSub { appState.completePaywall() }
        }
        #if DEBUG
        .sheet(isPresented: $showDebugMenu) {
            DebugPaywallMenu()
                .environment(subscriptions)
        }
        #endif
    }

    private var hero: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Color.tallyAccent)
            Text("Lock in with \(displayName).")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(Color.tallyTextPrimary)
                .multilineTextAlignment(.center)
        }
        // DEBUG-only: five taps on the hero opens the bypass menu. The
        // gesture is intentionally non-obvious so we don't ship a discoverable
        // skip button to users by accident; the whole block is stripped from
        // Release builds.
        #if DEBUG
        .contentShape(Rectangle())
        .onTapGesture {
            heroTapCount += 1
            if heroTapCount >= 5 {
                heroTapCount = 0
                showDebugMenu = true
            }
        }
        #endif
    }

    private var valueBullets: some View {
        VStack(alignment: .leading, spacing: 14) {
            bullet("Build habits with friends who hold you accountable.")
            bullet("See everyone's progress on one shared tally.")
            bullet("Lock in together, every day.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.tallyAccent)
                .padding(.top, 2)
            Text(text)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.tallyTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var priceCards: some View {
        VStack(spacing: 12) {
            if let annualPackage {
                priceCard(
                    package: annualPackage,
                    selection: .annual,
                    isAnnual: true
                )
            }
            if let monthlyPackage {
                priceCard(
                    package: monthlyPackage,
                    selection: .monthly,
                    isAnnual: false
                )
            }
        }
    }

    private func priceCard(package: Package, selection: Selection, isAnnual: Bool) -> some View {
        let isSelected = self.selection == selection
        let product = package.storeProduct
        let title = isAnnual ? "Annual" : "Monthly"
        let priceLine = "\(product.localizedPriceString)/\(isAnnual ? "year" : "month")"

        return Button {
            self.selection = selection
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundStyle(Color.tallyTextPrimary)
                        if isAnnual {
                            Text("BEST VALUE")
                                .font(.system(.caption2, design: .rounded, weight: .bold))
                                .tracking(0.6)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.tallyAccent)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }
                    Text(priceLine)
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .foregroundStyle(Color.tallyTextPrimary)
                    if isAnnual {
                        Text("$3.33/mo · save 44%")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.tallyTextSecondary)
                    }
                }
                Spacer()
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Color.tallyAccent : Color.tallyTextSecondary.opacity(0.5))
            }
            .padding(isAnnual ? 18 : 14)
            .frame(maxWidth: .infinity)
            .background(Color.tallyCard)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected ? Color.tallyAccent : Color.clear,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var ctaButton: some View {
        VStack(spacing: 12) {
            Button(action: purchase) {
                HStack(spacing: 8) {
                    if isPurchasing { ProgressView().tint(.white) }
                    Text(isPurchasing ? "Starting…" : "Start 3-Day Free Trial")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(selectedPackage == nil ? Color.tallyTextSecondary.opacity(0.3) : Color.tallyAccent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(selectedPackage == nil || isPurchasing)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.tallyDestructive)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var legalCopy: some View {
        Text(legalText)
            .font(.system(.subheadline, design: .rounded))
            .foregroundStyle(Color.tallyTextSecondary)
            .multilineTextAlignment(.leading)
    }

    /// Per Apple guidelines this must be clearly readable. Body-sized text,
    /// not fine print. Mentions trial length, post-trial price, cancellation
    /// path, and auto-renewal.
    private var legalText: String {
        let priceLine: String
        switch selection {
        case .annual:
            if let s = annualPackage?.storeProduct.localizedPriceString {
                priceLine = "\(s)/year"
            } else {
                priceLine = "the selected price"
            }
        case .monthly:
            if let s = monthlyPackage?.storeProduct.localizedPriceString {
                priceLine = "\(s)/month"
            } else {
                priceLine = "the selected price"
            }
        }
        return "3 days free, then \(priceLine). Cancel anytime in Settings. Auto-renews until cancelled."
    }

    private var restoreButton: some View {
        Button(action: restore) {
            HStack(spacing: 6) {
                if isRestoring { ProgressView().controlSize(.small) }
                Text(isRestoring ? "Restoring…" : "Restore Purchases")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
            }
            .foregroundStyle(Color.tallyAccent)
        }
        .buttonStyle(.plain)
        .disabled(isRestoring)
    }

    private var links: some View {
        HStack(spacing: 18) {
            Button("Terms of Service") { openURL(termsURL) }
                .buttonStyle(.plain)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.tallyTextSecondary)
            Text("·")
                .foregroundStyle(Color.tallyTextSecondary)
            Button("Privacy Policy") { openURL(privacyURL) }
                .buttonStyle(.plain)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.tallyTextSecondary)
        }
    }

    private var degradedState: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.tallyTextSecondary)
            Text("Couldn't load subscription options.")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.tallyTextPrimary)
            if let load = subscriptions.loadError {
                Text(load)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.tallyTextSecondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                Task { await subscriptions.refreshStatus() }
            } label: {
                Text("Retry")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.tallyAccent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Actions

    private func purchase() {
        guard let pkg = selectedPackage, !isPurchasing else { return }
        isPurchasing = true
        errorMessage = nil
        Task {
            defer { isPurchasing = false }
            do {
                try await subscriptions.purchase(pkg)
                // purchase() returns normally on success OR user-cancel;
                // distinguish via isSubscribed.
                if subscriptions.isSubscribed {
                    appState.completePaywall()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func restore() {
        guard !isRestoring else { return }
        isRestoring = true
        errorMessage = nil
        Task {
            defer { isRestoring = false }
            do {
                try await subscriptions.restorePurchases()
                if subscriptions.isSubscribed {
                    appState.completePaywall()
                } else {
                    errorMessage = "No previous purchase found on this Apple ID."
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private enum Selection {
        case annual
        case monthly
    }
}

#if DEBUG
/// Hidden debug menu for testing post-paywall flows on a sandbox account
/// without paying. Triggered by 5-tapping the paywall hero. Reads/writes
/// `SubscriptionManager.debugBypassPaywall`, persisted to LocalCache.
/// Stripped from Release builds.
private struct DebugPaywallMenu: View {
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(\.dismiss) private var dismiss

    @State private var bypass: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Bypass paywall (force isSubscribed = true)", isOn: $bypass)
                        .onChange(of: bypass) { _, new in
                            subscriptions.debugBypassPaywall = new
                        }
                } footer: {
                    Text("DEBUG only — this flag is stripped from Release builds. Persists to LocalCache so it survives relaunch.")
                }
            }
            .navigationTitle("Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                bypass = subscriptions.debugBypassPaywall
            }
        }
    }
}
#endif

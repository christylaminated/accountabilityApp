import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Explainer sheet shown when a CloudKit write fails because the user's
/// iCloud storage is full. Tells the user what the problem is, that it's
/// their Apple-wide iCloud storage (not Tally's), and walks them through
/// fixing it. Caller passes an `onRetry` closure invoked when the user
/// taps Try Again after presumably freeing space.
struct ICloudStorageFullSheet: View {
    let onRetry: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.tallyAccent) private var tallyAccent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                closeBar
                hero
                bodyCopy
                howToFix
                actions
                Spacer().frame(height: 12)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color.tallyCanvas)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var closeBar: some View {
        HStack {
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.tallyTextSecondary)
                    .frame(width: 30, height: 30)
                    .background(Color.tallyCard)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.top, 4)
    }

    private var hero: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.icloud.fill")
                .font(.system(size: 60, weight: .regular))
                .foregroundStyle(tallyAccent)
                .padding(.top, 4)
            Text("iCloud Storage Is Full")
                .font(.system(.title, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var bodyCopy: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tally syncs your habits, friends, and messages through your iCloud account. When iCloud has no room left, Tally can't save new changes — that's what's happening right now.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.tallyTextPrimary)

            Text("This is your Apple iCloud storage, shared across all your Apple apps — not something Tally controls. Tally itself only uses a few megabytes; the space is almost certainly being used by Photos or old device backups.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.tallyTextSecondary)
        }
    }

    private var howToFix: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How to free up space")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.tallyTextPrimary)
                .padding(.bottom, 2)

            StepRow(index: 1, text: "Open Settings → [Your Name] → iCloud → Manage Account Storage.")
            StepRow(index: 2, text: "See what's using space — usually Photos or backups for old devices.")
            StepRow(index: 3, text: "Delete old device backups you don't need, or turn off iCloud Photos.")
            StepRow(index: 4, text: "Or upgrade to iCloud+ — 50 GB is $0.99/month, with 200 GB and 2 TB tiers above that.")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tallyCard)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button(action: openSettings) {
                Text("Open Settings")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(tallyAccent)
                    .foregroundStyle(Color.tallyOnAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                dismiss()
                onRetry()
            } label: {
                Text("Try Again")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(Color.tallyTextPrimary)
                    .background(Color.tallyCard)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    /// Try the legacy `App-Prefs:` deep link first — when it works, it
    /// drops the user closer to the iCloud root than the per-app
    /// Settings page does. On any iOS where Apple has blocked the
    /// private scheme, the open completion reports `success == false`
    /// and we fall back to the app's own Settings entry (still one
    /// scroll away from iCloud).
    private func openSettings() {
        #if canImport(UIKit)
        let primary = URL(string: "App-Prefs:")
        let fallback = URL(string: UIApplication.openSettingsURLString)
        if let primary {
            UIApplication.shared.open(primary, options: [:]) { success in
                if !success, let fallback {
                    UIApplication.shared.open(fallback)
                }
            }
        } else if let fallback {
            UIApplication.shared.open(fallback)
        }
        #endif
    }
}

private struct StepRow: View {
    let index: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(.system(.footnote, design: .rounded, weight: .bold))
                .foregroundStyle(Color.tallyOnAccent)
                .frame(width: 22, height: 22)
                .background(Color.tallyAccent)
                .clipShape(Circle())
            Text(text)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.tallyTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    Color.tallyCanvas
        .sheet(isPresented: .constant(true)) {
            ICloudStorageFullSheet(onRetry: {})
        }
}

import SwiftUI
import CloudKit

/// Shown when CloudKit isn't available. Copy adapts to the specific reason,
/// and "Try again" lets the user re-check after fixing things in Settings.
struct ICloudStatusGate: View {
    @Environment(\.tallyAccent) private var tallyAccent
    let reason: CKAccountStatus
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "icloud.slash")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(tallyAccent)

            VStack(spacing: 12) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(bodyText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            Spacer()

            VStack(spacing: 12) {
                if showSettingsButton {
                    Button(action: openSettings) {
                        Text("Open Settings")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(tallyAccent)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                Button(action: onRetry) {
                    Text("Try again")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.tallyCard)
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }

            Spacer().frame(height: 24)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.tallyCanvas)
    }

    private var title: String {
        switch reason {
        case .noAccount:              return "Tally needs iCloud"
        case .restricted:             return "iCloud is restricted"
        case .couldNotDetermine:      return "Couldn't reach iCloud"
        case .temporarilyUnavailable: return "iCloud is unavailable"
        default:                      return "iCloud unavailable"
        }
    }

    private var bodyText: String {
        switch reason {
        case .noAccount:
            return "Tally syncs with your accountability partner through your iCloud account — no password or email needed. Open Settings, tap your name at the top, sign in, then come back here."
        case .restricted:
            return "iCloud is restricted on this device. Check Screen Time settings or any device-management profile."
        case .couldNotDetermine:
            return "We couldn't reach iCloud. Check your connection and try again."
        case .temporarilyUnavailable:
            return "iCloud is temporarily unavailable. We'll keep trying — give it a moment."
        default:
            return "iCloud isn't available right now."
        }
    }

    private var showSettingsButton: Bool {
        switch reason {
        case .noAccount, .restricted: return true
        default:                      return false
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

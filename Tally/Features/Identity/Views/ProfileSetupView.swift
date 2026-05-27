import SwiftUI
import CloudKit

/// First-launch profile setup. Takes a display name + an SF Symbol avatar and
/// hands the pair to a parent-supplied async closure (typically `AppState.saveProfile`).
struct ProfileSetupView: View {
    @Environment(\.tallyAccent) private var tallyAccent
    /// Invoked with `(displayName, avatarSymbol)`. Throws so failures surface here.
    let onSubmit: (String, String) async throws -> Void

    @State private var displayName: String = ""
    @State private var avatarSymbol: String = "leaf"
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    /// Curated, Lucide-feeling SF Symbol options. Intentionally generic — not
    /// activity-specific — so they fit any user.
    private static let symbolChoices: [String] = [
        "leaf", "mountain.2", "flame", "drop",
        "moon", "sparkle", "book", "pencil",
        "target", "heart", "star", "sun.max"
    ]

    private var trimmedName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        !trimmedName.isEmpty && trimmedName.count <= 50
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                nameField
                symbolPicker

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Color.tallyDestructive)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                submitButton
                Spacer().frame(height: 24)
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
        }
        .background(Color.tallyCanvas)
        .scrollDismissesKeyboard(.interactively)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text("Welcome to Tally")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
            Text("Pick a name and an icon your friends will see.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your name")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("e.g. Christy", text: $displayName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(false)
                .padding(14)
                .background(Color.tallyCard)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var symbolPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your icon")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
            let columns = Array(
                repeating: GridItem(.flexible(), spacing: 10),
                count: 6
            )
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Self.symbolChoices, id: \.self) { choice in
                    Button {
                        avatarSymbol = choice
                    } label: {
                        Image(systemName: choice)
                            .font(.system(size: 20, weight: .medium))
                            .frame(width: 52, height: 52)
                            .foregroundStyle(
                                avatarSymbol == choice ? tallyAccent : Color.secondary
                            )
                            .background(
                                avatarSymbol == choice
                                ? tallyAccent.opacity(0.18)
                                : Color.tallyCard
                            )
                            .clipShape(Circle())
                            .overlay(
                                Circle().stroke(
                                    avatarSymbol == choice ? tallyAccent : .clear,
                                    lineWidth: 1.5
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var submitButton: some View {
        Button(action: submit) {
            HStack(spacing: 8) {
                if isSubmitting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }
                Text(isSubmitting ? "Saving…" : "Continue")
                    .font(.system(.body, design: .rounded, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                isValid && !isSubmitting
                ? tallyAccent
                : Color.tallyTextSecondary.opacity(0.3)
            )
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(!isValid || isSubmitting)
    }

    private func submit() {
        guard isValid, !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                try await onSubmit(trimmedName, avatarSymbol)
            } catch {
                errorMessage = ProfileSetupView.friendlyMessage(for: error)
                isSubmitting = false
            }
        }
    }

    /// Translate the raw CloudKit error string ("Error saving record
    /// <CKRecordID: …> to server: Quota exceeded") into copy that tells
    /// the user what's wrong and what they can do about it. Falls
    /// through to `localizedDescription` for anything we haven't
    /// special-cased.
    static func friendlyMessage(for error: Error) -> String {
        if let ck = error as? CKError {
            switch ck.code {
            case .quotaExceeded:
                return "Your iCloud is full. Free up space in Settings → [Your Name] → iCloud → Manage Account Storage, or upgrade to iCloud+ — then come back and tap Continue."
            case .notAuthenticated:
                return "You're not signed into iCloud. Open Settings, sign in, then return to Tally."
            case .networkUnavailable, .networkFailure:
                return "No internet connection. Check your network and try again."
            case .accountTemporarilyUnavailable:
                return "iCloud is temporarily unavailable. Try again in a moment."
            case .serviceUnavailable, .zoneBusy:
                return "iCloud is busy right now. Try again in a few seconds."
            case .permissionFailure:
                return "Tally doesn't have permission to use your iCloud. Open Settings → [Your Name] → iCloud → Apps Using iCloud and make sure Tally is on."
            default:
                return ck.localizedDescription
            }
        }
        return error.localizedDescription
    }
}

// MARK: - Onboarding theme picker

/// Onboarding step shown after profile setup, before habits setup. Lets the
/// user pick one of the four themes. Default highlights `.classic` (the
/// monochrome default). Calls `onPicked(_:)` on Continue, which is wired to
/// `AppState.finishThemePick` so the choice persists and we advance.
struct ThemePickerOnboardingView: View {
    let onPicked: (TallyTheme) -> Void

    @State private var selected: TallyTheme = ThemeManager.shared.current

    var body: some View {
        VStack(spacing: 0) {
            header
            previewGrid
            continueButton
        }
        .background(Color.tallyCanvas.ignoresSafeArea())
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("Pick your style")
                .font(.system(.largeTitle, design: .serif, weight: .bold))
                .foregroundStyle(Color.tallyTextPrimary)
            Text("You can change this anytime in Profile.")
                .font(.subheadline)
                .foregroundStyle(Color.tallyTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.bottom, 30)
    }

    private var previewGrid: some View {
        let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(TallyTheme.allCases) { theme in
                    ThemePreviewCard(
                        theme: theme,
                        isSelected: selected == theme
                    ) {
                        selected = theme
                    }
                }
            }
            .padding(.horizontal, 20)

            // Show a color picker right where the user can see the
            // preview update live when they pick Custom. Hidden when
            // any other preset is selected.
            if selected == .custom {
                ColorPicker(
                    "Choose accent color",
                    selection: Binding(
                        get: { Color(tallyHex: ThemeManager.shared.customAccentHex) },
                        set: {
                            if let hex = onboardingHex(from: $0) {
                                ThemeManager.shared.customAccentHex = hex
                            }
                        }
                    ),
                    supportsOpacity: false
                )
                .font(.subheadline)
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
        }
    }

    /// Convert a SwiftUI Color to a 6-digit hex string. Mirrors the
    /// helper used in ProfileSettingsView; duplicated here to avoid
    /// cross-file dependencies during onboarding.
    private func onboardingHex(from color: Color) -> String? {
        #if canImport(UIKit)
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        let ri = Int(round(max(0, min(1, r)) * 255))
        let gi = Int(round(max(0, min(1, g)) * 255))
        let bi = Int(round(max(0, min(1, b)) * 255))
        return String(format: "%02X%02X%02X", ri, gi, bi)
        #else
        return nil
        #endif
    }

    private var continueButton: some View {
        Button {
            onPicked(selected)
        } label: {
            Text("Continue")
                .font(.system(.body, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(selected.accent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 32)
    }
}

/// One mini-preview card on the onboarding theme picker. Renders a simplified
/// Today-tab mockup using the theme's own palette so the user sees what
/// they're picking. Tapping selects (selection drives outer state via the
/// `onSelect` callback); a thick ring shows the current selection.
private struct ThemePreviewCard: View {
    let theme: TallyTheme
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                // Greeting line
                Text("Good evening,")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.textSecondary)
                Text("Christy.")
                    .font(.system(size: 14, design: .serif).bold())
                    .foregroundStyle(theme.textPrimary)
                // 7-dot streak chain
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { i in
                        Circle()
                            .fill(i < 4 ? theme.accent : theme.textSecondary.opacity(0.2))
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.top, 2)
                // Sample habit row
                HStack(spacing: 8) {
                    Text("Read 20 min")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    Circle()
                        .fill(theme.accent)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Image(systemName: "checkmark")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.white)
                        )
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(theme.card)
                )
                .padding(.top, 4)
                Spacer(minLength: 0)
                Text(theme.displayName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected ? Color.tallyTextPrimary : theme.textSecondary.opacity(0.18),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

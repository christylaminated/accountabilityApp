import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

/// Screen 5 of the paywalled onboarding flow.
///
/// Three sections in one screen:
///   1. Username — required, with debounced live availability check
///      (~400ms after typing stops). Suggestions on collision are
///      derived from the display name (numeric suffix, underscored
///      first/last, first-name + last-initial). Continue stays disabled
///      until the typed value is known-available + non-empty.
///   2. Avatar symbol — defaults to "leaf" so Continue is always
///      satisfiable as soon as the username clears.
///   3. Theme — defaults to .classic.
///
/// On Continue, `AppState.completeProfileCustomization` claims the
/// username (via `UsernameRepository` against the public DB), updates
/// avatar + theme, then advances to `.paywall`. A collision at claim
/// time (rare — the live check should have caught it) surfaces inline.
struct ProfileCustomizationView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.tallyAccent) private var tallyAccent

    @State private var username: String = ""
    @State private var avatarSymbol: String = "leaf"
    @State private var theme: TallyTheme = .classic

    /// Avatar photo bits. Photo is optional; falls back to `avatarSymbol`
    /// when none is picked. Resized + JPEG-compressed before storage to
    /// keep CloudKit writes small.
    @State private var avatarPhotoData: Data?
    @State private var pickedPhotoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false

    /// Result of the most recent availability check.
    @State private var usernameStatus: UsernameStatus = .idle
    @State private var usernameSuggestions: [String] = []

    /// Cancels the in-flight debounce when the user keeps typing.
    @State private var debounceTask: Task<Void, Never>?

    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private static let avatarChoices: [String] = [
        "leaf", "mountain.2", "flame", "drop",
        "moon", "sparkle", "book", "pencil",
        "target", "heart", "star", "sun.max",
    ]

    private var displayName: String {
        appState.ownCloudProfile?.displayName ?? ""
    }

    private var normalized: String? {
        appState.usernameRepository.normalize(username)
    }

    /// Continue is enabled only when the typed value is known-available.
    private var isValid: Bool {
        if case .available = usernameStatus { return true }
        return false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                photoSection
                usernameSection
                avatarSection
                themeSection

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Color.tallyDestructive)
                }

                submitButton
                Spacer().frame(height: 24)
            }
            .padding(.horizontal, 24)
            .padding(.top, 56)
        }
        .background(Color.tallyCanvas)
        .scrollDismissesKeyboard(.interactively)
        .onAppear { primeDefaultUsername() }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $pickedPhotoItem,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: pickedPhotoItem) { _, item in
            Task { await loadPickedPhoto(item) }
        }
    }

    // MARK: - Photo

    /// Optional photo upload. Tappable circular preview shows the picked
    /// photo or falls back to the selected SF Symbol avatar so users always
    /// see what their profile will look like.
    private var photoSection: some View {
        VStack(spacing: 12) {
            Button {
                showPhotoPicker = true
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    AvatarView(
                        symbolName: avatarSymbol,
                        imageData: avatarPhotoData,
                        size: 96
                    )
                    Image(systemName: "camera.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.tallyOnAccent)
                        .frame(width: 30, height: 30)
                        .background(tallyAccent)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.tallyCanvas, lineWidth: 2))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(avatarPhotoData == nil ? "Add photo" : "Change photo")

            HStack(spacing: 14) {
                Button {
                    showPhotoPicker = true
                } label: {
                    Text(avatarPhotoData == nil ? "Add a photo" : "Change photo")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tallyAccent)
                }
                .buttonStyle(.plain)
                if avatarPhotoData != nil {
                    Button {
                        avatarPhotoData = nil
                        pickedPhotoItem = nil
                    } label: {
                        Text("Remove")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.tallyDestructive)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Pulls the picked image off the PhotosPicker, decodes and resizes to
    /// 256pt square JPEG at 0.7 quality so CloudKit writes stay small.
    /// Mirrors ProfileSettingsView.loadPickedPhoto.
    private func loadPickedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let raw = try await item.loadTransferable(type: Data.self) else { return }
            #if canImport(UIKit)
            avatarPhotoData = resizeJPEG(raw, maxDimension: 256, quality: 0.7)
            #endif
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    #if canImport(UIKit)
    private func resizeJPEG(_ data: Data, maxDimension: CGFloat, quality: CGFloat) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(maxDimension / image.size.width, maxDimension / image.size.height, 1.0)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: quality)
    }
    #endif

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Personalize your Tally, \(displayName).")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(Color.tallyTextPrimary)
            Text("Friends will find you by username. Pick an icon and a theme — both are easy to change later.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.tallyTextSecondary)
        }
    }

    // MARK: - Username

    private var usernameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Username")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Text("@")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
                TextField("e.g. christy", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.asciiCapable)
                    .onChange(of: username) { _, _ in
                        scheduleAvailabilityCheck()
                    }
                statusIcon
            }
            .padding(14)
            .background(Color.tallyCard)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            usernameStatusLine
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch usernameStatus {
        case .idle, .invalid: EmptyView()
        case .checking:
            ProgressView().controlSize(.small)
        case .available:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(tallyAccent)
        case .taken:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Color.tallyDestructive)
        case .error:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Color.tallyDestructive)
        }
    }

    @ViewBuilder
    private var usernameStatusLine: some View {
        switch usernameStatus {
        case .idle:
            Text("3–20 characters: letters, numbers, or underscores.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
        case .invalid:
            Text("3–20 characters: letters, numbers, or underscores.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.tallyDestructive)
        case .checking:
            Text("Checking…")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
        case .available:
            Text("@\(normalized ?? username) is available.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(tallyAccent)
        case .taken:
            VStack(alignment: .leading, spacing: 6) {
                Text("@\(normalized ?? username) is taken.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.tallyDestructive)
                if !usernameSuggestions.isEmpty {
                    HStack(spacing: 8) {
                        Text("Try:")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                        ForEach(usernameSuggestions, id: \.self) { suggestion in
                            Button {
                                username = suggestion
                            } label: {
                                Text("@\(suggestion)")
                                    .font(.system(.caption, design: .rounded, weight: .semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(tallyAccent.opacity(0.18))
                                    .foregroundStyle(tallyAccent)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        case .error(let message):
            Text(message)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.tallyDestructive)
        }
    }

    // MARK: - Avatar

    private var avatarSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(avatarPhotoData == nil ? "Avatar" : "Fallback icon")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
            let columns = Array(
                repeating: GridItem(.flexible(), spacing: 10),
                count: 6
            )
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Self.avatarChoices, id: \.self) { choice in
                    Button {
                        avatarSymbol = choice
                    } label: {
                        Image(systemName: choice)
                            .font(.system(size: 20, weight: .medium))
                            .frame(width: 48, height: 48)
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

    // MARK: - Theme

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Theme")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                ForEach(TallyTheme.allCases) { t in
                    themeSwatch(t)
                }
                Spacer()
            }
        }
    }

    private func themeSwatch(_ t: TallyTheme) -> some View {
        let isSelected = theme == t
        return Button {
            theme = t
        } label: {
            VStack(spacing: 6) {
                Circle()
                    .fill(t.accent)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Circle()
                            .stroke(Color.tallyTextPrimary,
                                    lineWidth: isSelected ? 2.5 : 0)
                            .padding(-4)
                    )
                    .overlay(
                        Group {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Color.tallyOnAccent)
                            }
                        }
                    )
                Text(t.displayName)
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.tallyTextPrimary : Color.tallyTextSecondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t.displayName)
    }

    // MARK: - Continue

    private var submitButton: some View {
        Button(action: submit) {
            HStack(spacing: 8) {
                if isSubmitting {
                    ProgressView().tint(Color.tallyOnAccent)
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
            .foregroundStyle(Color.tallyOnAccent)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(!isValid || isSubmitting)
    }

    // MARK: - Logic

    /// Seed an initial username from displayName when the screen first
    /// appears (e.g. "Christy Lam" → "christylam"). Fires an availability
    /// check on that seed so a fresh user with a non-colliding name can
    /// tap Continue immediately.
    private func primeDefaultUsername() {
        guard username.isEmpty else { return }
        let seed = Self.baseSlug(from: displayName)
        guard !seed.isEmpty else { return }
        username = seed
        scheduleAvailabilityCheck()
    }

    private func scheduleAvailabilityCheck() {
        debounceTask?.cancel()
        errorMessage = nil
        usernameSuggestions = []
        let typed = username.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !typed.isEmpty else {
            usernameStatus = .idle
            return
        }
        guard let normalized = appState.usernameRepository.normalize(typed) else {
            usernameStatus = .invalid
            return
        }

        usernameStatus = .checking
        debounceTask = Task { [weak appState] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, let appState else { return }
            do {
                let available = try await appState.usernameRepository.isAvailable(normalized)
                if Task.isCancelled { return }
                await MainActor.run {
                    if available {
                        usernameStatus = .available
                    } else {
                        usernameStatus = .taken
                        usernameSuggestions = Self.suggestions(
                            base: normalized,
                            displayName: displayName
                        )
                    }
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    usernameStatus = .error(error.localizedDescription)
                }
            }
        }
    }

    private func submit() {
        guard isValid, !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                try await appState.completeProfileCustomization(
                    username: username,
                    avatarSymbol: avatarSymbol,
                    theme: theme,
                    avatarImageData: avatarPhotoData
                )
            } catch {
                errorMessage = error.localizedDescription
                isSubmitting = false
            }
        }
    }

    // MARK: - Username helpers

    /// Lowercased, non-alphanumeric stripped. Spaces dropped. Truncated
    /// to the 20-char cap.
    static func baseSlug(from raw: String) -> String {
        let cleaned = raw.lowercased().filter {
            $0.isLetter || $0.isNumber || $0 == "_"
        }
        return String(cleaned.prefix(20))
    }

    /// Three display-name-derived alternatives for when the user's first
    /// pick is taken. Filtered to keep only valid-length normalized
    /// candidates so a suggestion tap can land directly in `.available`.
    static func suggestions(base: String, displayName: String) -> [String] {
        var out: [String] = []

        // 1. Numeric suffix.
        let withNum = String(base.prefix(19)) + "2"
        out.append(withNum)

        // 2. Underscore-separated first/last (from displayName parts).
        let parts = displayName
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0) }
        if parts.count >= 2 {
            let underscored = (parts[0] + "_" + parts[1])
                .lowercased()
                .filter { $0.isLetter || $0.isNumber || $0 == "_" }
            let trimmed = String(underscored.prefix(20))
            if trimmed.count >= 3, !out.contains(trimmed), trimmed != base {
                out.append(trimmed)
            }
        }

        // 3. First name + last initial (e.g. "christyl").
        if parts.count >= 2, let lastInitial = parts[1].first {
            let combined = (parts[0] + String(lastInitial))
                .lowercased()
                .filter { $0.isLetter || $0.isNumber || $0 == "_" }
            let trimmed = String(combined.prefix(20))
            if trimmed.count >= 3, !out.contains(trimmed), trimmed != base {
                out.append(trimmed)
            }
        }

        // Final fallback if we still need a third option.
        if out.count < 3 {
            let trimmedBase = String(base.prefix(19)) + "3"
            if !out.contains(trimmedBase) { out.append(trimmedBase) }
        }

        return Array(out.prefix(3))
    }

    private enum UsernameStatus: Equatable {
        case idle
        case invalid
        case checking
        case available
        case taken
        case error(String)
    }
}

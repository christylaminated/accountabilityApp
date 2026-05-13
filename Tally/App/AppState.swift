import Foundation
import Observation
import CloudKit

/// Top-level app state. Holds:
///   • iCloud / onboarding gate state (`onboardingState`)
///   • The user's CloudKit profile once they've completed setup (`.ready(profile)`)
///   • Repository protocols for backend-mediated data (currently only `profileRepository`)
///   • Legacy mock stores for features that haven't been ported to CloudKit yet
///
/// As each feature swaps to CloudKit (steps 3-6), its mock store goes away and a
/// repository replaces it here. The view layer reads through these properties so
/// the swap is repository-only.
///
/// Marked `@MainActor` so mutations from async contexts always land on the main
/// thread (SwiftUI requires main-thread observation).
@MainActor
@Observable
final class AppState {
    enum OnboardingState: Equatable {
        case checkingICloud
        case needsSignIn(reason: CKAccountStatus)
        case needsProfileSetup
        case ready(UserProfile)
        case error(String)
    }

    // MARK: - Onboarding / identity

    var onboardingState: OnboardingState = .checkingICloud

    /// Convenience: the user's profile once onboarding is complete. Nil during
    /// any pre-ready state.
    var ownProfile: UserProfile? {
        if case .ready(let p) = onboardingState { return p }
        return nil
    }

    // MARK: - CloudKit-backed repositories

    let profileRepository: any ProfileRepository

    // MARK: - Legacy mock stores (still in use for unswapped features)
    //
    // Each of these is replaced by a CloudKit repository in a later step:
    //   • circleStore   → CircleRepository    (step 3)
    //   • habitStore    → HabitRepository     (step 4)
    //   • goalStore     → WeeklyGoalRepository(step 5)
    //   • messageStore  → MessageRepository   (step 6)
    //   • profileStore  → folded into CircleMember lookups (step 3)
    //
    // The currentUserID / activeCircleID are UUID-typed here for mock compatibility.
    // They get retyped to CloudKit identifiers as part of the step that swaps the
    // store that depends on them.

    var currentUserID: UUID
    var activeCircleID: UUID

    let profileStore: MockProfileStore
    let circleStore: MockCircleStore
    let habitStore: MockHabitStore
    let goalStore: MockGoalStore
    let messageStore: MockMessageStore

    // MARK: - Mock-era convenience accessors
    //
    // These exist so the unswapped feature views (dashboard, member detail, messaging
    // list, etc.) can read the current Circle / members without changing. Each one
    // gets retired alongside the feature that depends on it as we swap to CloudKit.

    var currentProfile: Profile {
        profileStore.profile(id: currentUserID) ?? MockData.profiles[0]
    }

    var activeCircle: TallyCircle {
        circleStore.circle(id: activeCircleID) ?? MockData.circle
    }

    var memberProfiles: [Profile] {
        circleStore.memberIDs(circleID: activeCircleID)
            .compactMap { profileStore.profile(id: $0) }
    }

    var otherMembers: [Profile] {
        memberProfiles.filter { $0.id != currentUserID }
    }

    // MARK: - Lifecycle

    /// Holds the NotificationCenter observer token. We use a tiny reference-type
    /// wrapper because `@MainActor` classes can't have a non-async deinit that
    /// touches isolated state. Storing the token here means the wrapper's own
    /// (nonisolated) deinit handles `removeObserver` when AppState deallocates,
    /// without us needing a deinit on AppState at all.
    private let observerHolder = NotificationObserverHolder()

    init(profileRepository: any ProfileRepository = CloudKitProfileRepository()) {
        self.profileRepository = profileRepository

        self.currentUserID  = MockData.christyID
        self.activeCircleID = MockData.circleID
        self.profileStore   = MockProfileStore()
        self.circleStore    = MockCircleStore()
        self.habitStore     = MockHabitStore()
        self.goalStore      = MockGoalStore()
        self.messageStore   = MockMessageStore()

        registerAccountChangeObserver()
        Task { await self.refreshAccountState() }
    }

    // No explicit deinit: when AppState deallocates, `observerHolder` does too,
    // and its deinit removes the NotificationCenter observer.

    // MARK: - Account status

    /// Subscribe to `CKAccountChanged`. When iCloud switches accounts or signs in/out,
    /// invalidate the identity cache in CKClient and re-run the gate.
    private func registerAccountChangeObserver() {
        observerHolder.token = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                await CKClient.shared.invalidateIdentityCache()
                await self?.refreshAccountState()
            }
        }
    }

    /// Re-check account status + own profile presence and update `onboardingState`.
    /// Called on launch, on `CKAccountChanged`, and on scene-foreground.
    func refreshAccountState() async {
        onboardingState = .checkingICloud

        let status: CKAccountStatus
        do {
            status = try await CKClient.shared.accountStatus()
        } catch {
            onboardingState = .error(error.localizedDescription)
            return
        }

        switch status {
        case .available:
            do {
                if let profile = try await profileRepository.ownProfile() {
                    onboardingState = .ready(profile)
                } else {
                    onboardingState = .needsProfileSetup
                }
            } catch {
                onboardingState = .error(error.localizedDescription)
            }

        case .noAccount, .restricted, .couldNotDetermine, .temporarilyUnavailable:
            onboardingState = .needsSignIn(reason: status)

        @unknown default:
            onboardingState = .needsSignIn(reason: .couldNotDetermine)
        }
    }

    // MARK: - Profile setup

    /// Called from `ProfileSetupView` on submit. Persists to CloudKit and flips
    /// the gate to `.ready`. Throws so the setup view can show the error and
    /// stay on screen.
    func saveProfile(displayName: String, avatarEmoji: String) async throws {
        let profile = try await profileRepository.saveOwnProfile(
            displayName: displayName,
            avatarEmoji: avatarEmoji
        )
        onboardingState = .ready(profile)
    }
}

/// Tiny reference-type wrapper around a NotificationCenter observer token. Lives
/// outside any actor isolation so its `deinit` can call `removeObserver` without
/// fighting Swift concurrency. When the owning `AppState` deallocates, this
/// instance does too, and cleanup happens automatically.
private final class NotificationObserverHolder {
    var token: (any NSObjectProtocol)?

    deinit {
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
    }
}

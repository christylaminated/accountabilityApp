import Foundation
import Observation
import CloudKit

/// Top-level app state. Holds:
///   • iCloud / onboarding gate state (`onboardingState`)
///   • The user's CloudKit profile once set up (`ownCloudProfile`)
///   • Repositories for backend-mediated data (currently only `profileRepository`)
///   • Legacy mock stores for features that haven't been ported to CloudKit yet
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
        case needsHabitsSetup
        case needsGoalsSetup
        case ready
        case error(String)
    }

    // MARK: - Onboarding / identity

    var onboardingState: OnboardingState = .checkingICloud

    /// The signed-in user's CloudKit profile. Set after fetch on launch and after
    /// the user submits ProfileSetupView. Used by any view that needs the user's
    /// real CK identity directly (most read through the mock profile store mirror).
    var ownCloudProfile: UserProfile?

    // MARK: - CloudKit-backed repositories

    let profileRepository: any ProfileRepository

    // MARK: - Legacy mock stores
    //
    // Each gets replaced by a CloudKit repository in a later step:
    //   • circleStore   → CircleRepository    (step 3)
    //   • habitStore    → HabitRepository     (step 4)
    //   • goalStore     → WeeklyGoalRepository(step 5)
    //   • messageStore  → MessageRepository   (step 6)
    //   • profileStore  → folded into CircleMember lookups (step 3)
    //
    // Pre-seeded mock data has been removed — these stores start empty. The user
    // fills them in via onboarding (habits / goals) or in-app add flows.

    var currentUserID: UUID
    var activeCircleID: UUID

    let profileStore: MockProfileStore
    let circleStore: MockCircleStore
    let habitStore: MockHabitStore
    let goalStore: MockGoalStore
    let messageStore: MockMessageStore

    // MARK: - Mock-era convenience accessors
    //
    // These exist so the unswapped feature views can read the active Circle /
    // members without changing. Retired alongside each feature as we port to CK.

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

    /// Holds the NotificationCenter observer token. Reference-type wrapper so its
    /// nonisolated `deinit` can do cleanup when AppState deallocates, without
    /// fighting `@MainActor` isolation.
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
    ///
    /// Habits/goals onboarding only triggers on the very first profile creation
    /// (same-session). Returning users with an existing profile go straight to `.ready`.
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
                    ownCloudProfile = profile
                    mirrorProfileToMock(profile)
                    onboardingState = .ready
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

    // MARK: - Onboarding transitions

    /// Called from `ProfileSetupView` on submit. Persists to CloudKit, mirrors the
    /// data to the mock profile store, and routes to habits setup.
    func saveProfile(displayName: String, avatarSymbol: String) async throws {
        let profile = try await profileRepository.saveOwnProfile(
            displayName: displayName,
            avatarSymbol: avatarSymbol
        )
        ownCloudProfile = profile
        mirrorProfileToMock(profile)
        onboardingState = .needsHabitsSetup
    }

    /// Called from `HabitsSetupView`. Persists each non-empty title as a habit,
    /// then routes to goals setup. Empty array is fine (user is skipping).
    func saveInitialHabits(_ titles: [String]) {
        for title in titles {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            habitStore.add(title: trimmed, for: currentUserID)
        }
        onboardingState = .needsGoalsSetup
    }

    /// Called from `GoalsSetupView`. Persists each non-empty title as a goal for
    /// the current Monday-anchored week, then routes to the main app.
    func saveInitialGoals(_ titles: [String]) {
        let weekStart = WeekCalculator.weekStart(for: .now)
        for title in titles {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            goalStore.add(title: trimmed, for: currentUserID, weekStart: weekStart)
        }
        onboardingState = .ready
    }

    // MARK: - Internals

    /// Copy the user's CK profile info onto the mock profile store so existing
    /// dashboard / member-row views (which still read the mock) display the real
    /// name and emoji. Drops away with the mock layer in CK Step 3.
    private func mirrorProfileToMock(_ profile: UserProfile) {
        profileStore.updateProfile(
            id: currentUserID,
            displayName: profile.displayName,
            avatarSymbol: profile.avatarSymbol
        )
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

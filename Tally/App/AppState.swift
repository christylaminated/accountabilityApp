import Foundation
import Observation
import CloudKit

/// Top-level app state. Holds:
///   • iCloud / onboarding gate state (`onboardingState`)
///   • The user's CloudKit profile once set up (`ownCloudProfile`)
///   • Repositories for profile + Circle lifecycle
///   • `circleStore` — the live data for the active Circle (members, habits,
///     check-ins, goals, messages), shared across every feature view
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
        case needsCircleSetup
        case needsHabitsSetup
        case needsGoalsSetup
        case ready
        case error(String)
    }

    // MARK: - Onboarding / identity

    var onboardingState: OnboardingState = .checkingICloud

    /// The signed-in user's CloudKit profile. Set after fetch on launch and after
    /// the user submits ProfileSetupView.
    var ownCloudProfile: UserProfile?

    /// Signed-in user's CloudKit record name. Empty until resolved on launch;
    /// every per-user lookup (own habits, own goals, "is this me") keys off it.
    var currentUserID: String = ""

    // MARK: - Repositories + store

    let profileRepository: any ProfileRepository
    let circleRepository: any CircleRepository
    let shareCoordinator: ShareCoordinator

    /// Live data for the active Circle — the single source the feature views read.
    let circleStore: CircleStore

    /// Points at `PendingShareBuffer.shared`. Single source of truth for an
    /// incoming CKShare invite — survives cold-launch deep links that arrive
    /// before this object exists.
    let pendingShareBuffer = PendingShareBuffer.shared

    // MARK: - Circle state (loaded from CloudKit)

    var ownedCircles: [TallyCircle] = []
    var joinedCircles: [TallyCircle] = []
    var isAcceptingShare = false
    var circleActionError: String?
    /// Latest CloudKit error from the share / invite flow. Set when the system
    /// share sheet fails to mint or save its CKShare, so the app can surface
    /// the real error instead of iOS's generic "A link couldn't be created".
    var lastCloudShareError: String?

    var allCircles: [TallyCircle] { ownedCircles + joinedCircles }

    /// The one Circle the app is focused on. Owned takes priority so a user who
    /// created their own Circle and invited friends stays anchored to it.
    var activeCircle: TallyCircle? { ownedCircles.first ?? joinedCircles.first }

    /// True only during the first run, so a returning user with a Circle skips
    /// straight past habits/goals setup to the main app.
    private var isFirstRunOnboarding = false

    // MARK: - Lifecycle

    /// Holds the NotificationCenter observer token. Reference-type wrapper so its
    /// nonisolated `deinit` can do cleanup when AppState deallocates.
    private let observerHolder = NotificationObserverHolder()

    init(
        profileRepository: any ProfileRepository = CloudKitProfileRepository(),
        circleRepository: any CircleRepository = CloudKitCircleRepository(),
        shareCoordinator: ShareCoordinator = ShareCoordinator(),
        circleStore: CircleStore? = nil
    ) {
        self.profileRepository = profileRepository
        self.circleRepository = circleRepository
        self.shareCoordinator = shareCoordinator
        self.circleStore = circleStore ?? CircleStore()

        registerAccountChangeObserver()
        Task { await self.refreshAccountState() }
    }

    // MARK: - Account status

    /// Wire up the two notifications AppState reacts to:
    ///   • `CKAccountChanged` — iCloud sign-in/out or account switch; re-run the gate.
    ///   • `tallyRemoteChange` — a CloudKit push says a friend changed something;
    ///     pull the Circle delta so it appears live.
    private func registerAccountChangeObserver() {
        observerHolder.tokens.append(
            NotificationCenter.default.addObserver(
                forName: .CKAccountChanged, object: nil, queue: nil
            ) { [weak self] _ in
                Task { @MainActor in
                    await CKClient.shared.invalidateIdentityCache()
                    await self?.refreshAccountState()
                }
            }
        )
        observerHolder.tokens.append(
            NotificationCenter.default.addObserver(
                forName: .tallyRemoteChange, object: nil, queue: nil
            ) { [weak self] _ in
                Task { @MainActor in
                    await self?.circleStore.refresh()
                }
            }
        )
        observerHolder.tokens.append(
            NotificationCenter.default.addObserver(
                forName: .tallyCloudShareError, object: nil, queue: nil
            ) { [weak self] notification in
                let message = (notification.object as? Error)?.localizedDescription
                    ?? "Unknown CloudKit sharing error."
                Task { @MainActor in
                    self?.lastCloudShareError = message
                }
            }
        )
    }

    /// Re-check account status + own profile and update `onboardingState`.
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
                currentUserID = try await CKClient.shared.userRecordID().recordName
                if let profile = try await profileRepository.ownProfile() {
                    ownCloudProfile = profile
                    await handleIncomingShareIfNeeded()
                    await loadCircles()
                    await enterMainAppOrCircleSetup()
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

    /// After auth + profile are confirmed: route to Circle setup if the user has
    /// no Circle yet, otherwise activate the store and show the main app.
    private func enterMainAppOrCircleSetup() async {
        guard let circle = activeCircle else {
            onboardingState = .needsCircleSetup
            return
        }
        await circleStore.activate(circle, currentUserID: currentUserID)
        onboardingState = .ready
    }

    // MARK: - Onboarding transitions

    /// Called from `ProfileSetupView` on submit. Persists to CloudKit, then routes
    /// to Circle setup. Marks this as a first run so habits/goals setup follows.
    func saveProfile(displayName: String, avatarSymbol: String) async throws {
        let profile = try await profileRepository.saveOwnProfile(
            displayName: displayName,
            avatarSymbol: avatarSymbol
        )
        ownCloudProfile = profile
        isFirstRunOnboarding = true
        onboardingState = .needsCircleSetup
        // If the user reached us by tapping a friend's invite link before
        // finishing their profile, the share is buffered — join it now so they
        // skip straight past Circle setup.
        await handleIncomingShareIfNeeded()
    }

    /// Called from `CircleSetupView`. Creates the user's first Circle, activates
    /// the store on it, and (on a first run) routes to habits setup.
    func setUpInitialCircle(name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = ownCloudProfile
        let circle = try await circleRepository.createCircle(
            name: trimmed.isEmpty ? "My Circle" : trimmed,
            emoji: nil,
            ownerDisplayName: profile?.displayName ?? "Me",
            ownerAvatarSymbol: profile?.avatarSymbol ?? "leaf"
        )
        await loadCircles()
        await circleStore.activate(circle, currentUserID: currentUserID)
        advancePastCircleSetup()
    }

    /// Move on from Circle setup — to habits on a first run, else straight to the
    /// main app. Used after creating a Circle or accepting an invite.
    private func advancePastCircleSetup() {
        onboardingState = isFirstRunOnboarding ? .needsHabitsSetup : .ready
    }

    /// Called from `HabitsSetupView`. Persists each non-empty title as a habit in
    /// the active Circle, then routes to goals setup.
    func saveInitialHabits(_ titles: [String]) {
        for title in titles {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            circleStore.addHabit(title: trimmed, for: currentUserID)
        }
        onboardingState = .needsGoalsSetup
    }

    /// Called from `GoalsSetupView`. Persists each non-empty title as a weekly
    /// goal for the current Monday-anchored week, then enters the main app.
    func saveInitialGoals(_ titles: [String]) {
        let weekStart = WeekCalculator.weekStart(for: .now)
        for title in titles {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            circleStore.addGoal(
                title: trimmed,
                for: currentUserID,
                period: .week,
                periodStart: weekStart
            )
        }
        isFirstRunOnboarding = false
        onboardingState = .ready
    }

    // MARK: - Circles (CloudKit)

    /// Fetch the user's owned + joined Circles from CloudKit. Best-effort —
    /// failures surface in `circleActionError` but don't block the app.
    func loadCircles() async {
        do {
            async let owned = circleRepository.ownedCircles()
            async let joined = circleRepository.joinedCircles()
            self.ownedCircles = try await owned
            self.joinedCircles = try await joined
        } catch {
            circleActionError = error.localizedDescription
        }
    }

    /// Create a Circle owned by the current user. The CKShare is minted lazily
    /// by `InviteSheetView`'s preparationHandler the first time the user opens
    /// the invite sheet — that's the Apple-blessed pattern and avoids the
    /// "couldn't create a link" error you get from pre-saved shares.
    @discardableResult
    func createCircle(name: String, emoji: String?) async throws -> TallyCircle {
        let profile = ownCloudProfile
        let circle = try await circleRepository.createCircle(
            name: name,
            emoji: emoji,
            ownerDisplayName: profile?.displayName ?? "Me",
            ownerAvatarSymbol: profile?.avatarSymbol ?? "leaf"
        )
        await loadCircles()
        if let active = activeCircle {
            await circleStore.activate(active, currentUserID: currentUserID)
        }
        return circle
    }

    /// If a CKShare invite is pending (from a tapped invite link), accept it,
    /// record our membership, then refresh. Called on reaching the gate and on
    /// scene-foreground.
    func handleIncomingShareIfNeeded() async {
        guard let metadata = pendingShareBuffer.consume() else { return }
        isAcceptingShare = true
        defer { isAcceptingShare = false }
        do {
            let circleID = try await shareCoordinator.accept(metadata)
            try await circleRepository.recordOwnMembership(
                circleID: circleID,
                displayName: ownCloudProfile?.displayName ?? "Me",
                avatarSymbol: ownCloudProfile?.avatarSymbol ?? "leaf"
            )
            await loadCircles()
            if let active = activeCircle {
                await circleStore.activate(active, currentUserID: currentUserID)
            }
            // A friend's invite accepted during Circle setup counts as setup done.
            if onboardingState == .needsCircleSetup {
                advancePastCircleSetup()
            }
        } catch {
            circleActionError = "Couldn't join the Circle: \(error.localizedDescription)"
        }
    }

    /// Pull the latest Circle data from CloudKit. Called on scene-foreground and
    /// when a CloudKit push notification arrives.
    func refreshCircleData() async {
        await circleStore.refresh()
    }
}

/// Tiny reference-type wrapper around a NotificationCenter observer token. Lives
/// outside any actor isolation so its `deinit` can call `removeObserver` without
/// fighting Swift concurrency.
private final class NotificationObserverHolder {
    var tokens: [any NSObjectProtocol] = []

    deinit {
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
    }
}

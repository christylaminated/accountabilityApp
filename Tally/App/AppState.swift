import Foundation
import Observation
import CloudKit
import SwiftUI

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

    /// The user's chosen accent-color preset. Mirrors `ThemeStore.shared` so
    /// `tallyAccent` and `appState.accentColor` agree. Persisted via
    /// `LocalCacheKey.themeColor` (under the hood inside ThemeStore).
    var themeColor: ThemeColor = ThemeStore.shared.currentColor

    /// Convenience: the actual SwiftUI Color for the current theme.
    var accentColor: Color { themeColor.color }

    // MARK: - Repositories + store

    let profileRepository: any ProfileRepository
    let circleRepository: any CircleRepository
    let personalRepository: any PersonalRepository
    let usernameRepository: any UsernameRepository
    let shareCoordinator: ShareCoordinator

    /// Live data for the active Circle — members + chat. Habits and goals
    /// moved out to `personalStore` in 3d.
    let circleStore: CircleStore

    /// The signed-in user's personal data — habits, completions, goals.
    /// Friends' data will load here too in 3e.
    let personalStore: PersonalStore

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
        personalRepository: any PersonalRepository = CloudKitPersonalRepository(),
        usernameRepository: any UsernameRepository = CloudKitUsernameRepository(),
        shareCoordinator: ShareCoordinator = ShareCoordinator(),
        circleStore: CircleStore? = nil,
        personalStore: PersonalStore? = nil
    ) {
        self.profileRepository = profileRepository
        self.circleRepository = circleRepository
        self.personalRepository = personalRepository
        self.usernameRepository = usernameRepository
        self.shareCoordinator = shareCoordinator
        self.circleStore = circleStore ?? CircleStore()
        self.personalStore = personalStore ?? PersonalStore(repository: personalRepository)

        // Skip the "Checking iCloud…" spinner on launch for returning users.
        // The `hasOnboarded` flag is the source of truth — written the moment
        // the user first reaches `.ready` — so even if the profile/userID
        // caches fail to decode for some reason, returning users still get
        // straight onto the dashboard. The background refresh below verifies
        // everything and fixes up any stale state.
        let hasOnboarded = LocalCache.load(Bool.self, forKey: LocalCacheKey.hasOnboarded) ?? false
        if hasOnboarded {
            self.currentUserID = LocalCache.load(String.self, forKey: LocalCacheKey.currentUserID) ?? ""
            self.ownCloudProfile = LocalCache.load(UserProfile.self, forKey: LocalCacheKey.ownProfile)
            self.onboardingState = .ready
        }
        NSLog("[Tally] AppState.init hasOnboarded=\(hasOnboarded) state=\(self.onboardingState)")

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
                    // Wipe caches so we never show the previous user's data
                    // after an iCloud account switch.
                    LocalCache.clearAll()
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
    ///
    /// If we already have a `.ready` state from cached identity + profile,
    /// we *don't* swap back to `.checkingICloud` — the user keeps seeing their
    /// dashboard while the refresh runs silently. Only a first launch (no
    /// cache) or a mid-onboarding state shows the spinner.
    func refreshAccountState() async {
        if onboardingState != .ready {
            onboardingState = .checkingICloud
        }

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
                LocalCache.save(currentUserID, forKey: LocalCacheKey.currentUserID)
                if let profile = try await profileRepository.ownProfile() {
                    persistProfile(profile)
                    // Idempotent — sets up the personal zone + root record the
                    // first time a user reaches the main app, then loads habits
                    // and goals from it. activate() preserves cached arrays
                    // on the in-memory store while the server fetch runs.
                    try? await personalRepository.ensurePersonalZone()
                    await personalStore.activate(currentUserID: currentUserID)
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

    /// After auth + profile are confirmed: activate the current Circle (if any)
    /// and show the main app. A user with zero Circles is a valid state —
    /// they're on the dashboard with the "Add a friend" prompt.
    /// (`hasOnboarded` is already set the moment the profile is fetched, in
    /// `persistProfile(_:)`, so even if Circle/store activation throws later
    /// the spinner-skip is unaffected on the next launch.)
    private func enterMainAppOrCircleSetup() async {
        if let circle = activeCircle {
            await circleStore.activate(circle, currentUserID: currentUserID)
        }
        onboardingState = .ready
    }

    /// Centralized profile-set with cache + onboarding-flag writes. The flag
    /// goes to disk the instant we have a profile in hand — so any subsequent
    /// failure (zone setup, share accept, Circle load) doesn't strand the
    /// user behind the spinner on the next launch.
    private func persistProfile(_ profile: UserProfile) {
        ownCloudProfile = profile
        LocalCache.save(profile, forKey: LocalCacheKey.ownProfile)
        LocalCache.save(true, forKey: LocalCacheKey.hasOnboarded)
        NSLog("[Tally] persisted profile + hasOnboarded=true")
    }

    // MARK: - Onboarding transitions

    /// Called from `ProfileSetupView` on submit. Persists to CloudKit, mirrors
    /// the user's name + avatar into their personal zone's root record so
    /// friends can render them, then routes to habits setup.
    func saveProfile(displayName: String, avatarSymbol: String) async throws {
        let profile = try await profileRepository.saveOwnProfile(
            displayName: displayName,
            avatarSymbol: avatarSymbol,
            username: nil
        )
        isFirstRunOnboarding = true

        // Centralized: sets ownCloudProfile, caches profile, flips hasOnboarded.
        persistProfile(profile)
        LocalCache.save(currentUserID, forKey: LocalCacheKey.currentUserID)

        // Ensure the personal zone exists, then write the friend-visible name
        // and avatar into PersonalRoot. Best-effort.
        try? await personalRepository.ensurePersonalZone()
        try? await personalRepository.updatePersonalRootProfile(
            displayName: displayName,
            avatarSymbol: avatarSymbol
        )

        onboardingState = .needsHabitsSetup
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
    /// main app. Used after creating a Circle or accepting an invite. Retained
    /// for backward compatibility; new onboarding no longer routes through
    /// `.needsCircleSetup` at all.
    private func advancePastCircleSetup() {
        onboardingState = isFirstRunOnboarding ? .needsHabitsSetup : .ready
    }

    /// Set `circle` as the active Circle and reload its members + chat.
    /// Called when the user taps into a Group from the Friends tab.
    func activateCircle(_ circle: TallyCircle) async {
        await circleStore.activate(circle, currentUserID: currentUserID)
    }

    /// Owner deletes a Group entirely — server-side zone deletion cascades to
    /// the chat, members, and the share. Reloads the Circle list and reactivates
    /// the next available Group, if any.
    func deleteCircle(_ circle: TallyCircle) async {
        do {
            try await circleRepository.deleteCircle(circle)
            await loadCircles()
            if let next = activeCircle {
                await circleStore.activate(next, currentUserID: currentUserID)
            }
        } catch {
            circleActionError = error.localizedDescription
        }
    }

    /// Participant leaves a Group (removes self from the share). Owners use
    /// `deleteCircle` instead.
    func leaveCircle(_ circle: TallyCircle) async {
        do {
            try await circleRepository.leaveCircle(circle)
            await loadCircles()
            if let next = activeCircle {
                await circleStore.activate(next, currentUserID: currentUserID)
            }
        } catch {
            circleActionError = error.localizedDescription
        }
    }

    // MARK: - Members / friends (dashboard composition)

    /// "Me" rendered as a `Friend` for symmetric iteration on the dashboard.
    var meAsFriend: Friend {
        Friend(
            userID: currentUserID,
            displayName: ownCloudProfile?.displayName ?? "Me",
            avatarSymbol: ownCloudProfile?.avatarSymbol ?? "leaf"
        )
    }

    /// Me plus every friend visible via the personal share graph. Drives the
    /// dashboard list and member-detail navigation.
    var dashboardMembers: [Friend] {
        [meAsFriend] + personalStore.friends
    }

    /// Look up a member (me or a friend) by user record name.
    func member(for userID: String) -> Friend? {
        if userID == currentUserID { return meAsFriend }
        return personalStore.friend(id: userID)
    }

    // MARK: - Profile editing

    /// Update the user's display name, avatar, and optional username
    /// post-onboarding. Saves to CloudKit (UserProfile + PersonalRoot so
    /// friends see the change) and refreshes the local cache. If a username
    /// is provided, it's claimed in the public DB (which throws if taken).
    func updateProfile(
        displayName: String,
        avatarSymbol: String,
        username: String?
    ) async throws {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized: String? = username.flatMap { usernameRepository.normalize($0) }

        // If a non-empty raw username was provided but it doesn't normalize,
        // surface that as an error rather than silently dropping it.
        if let raw = username, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, normalized == nil {
            throw UsernameError.invalid
        }

        // Claim or release the username (against the public directory) BEFORE
        // saving the profile, so a failure to claim doesn't leave the profile
        // pointing at an unowned name.
        let previous = ownCloudProfile?.username
        if let normalized {
            try await usernameRepository.claim(
                normalized,
                previousUsername: previous,
                displayName: trimmedName,
                avatarSymbol: avatarSymbol
            )
        } else if let previous {
            try? await usernameRepository.release(previous)
        }

        let profile = try await profileRepository.saveOwnProfile(
            displayName: trimmedName,
            avatarSymbol: avatarSymbol,
            username: normalized
        )
        persistProfile(profile)

        // Push to PersonalRoot so friends see the new name + avatar.
        try? await personalRepository.updatePersonalRootProfile(
            displayName: trimmedName,
            avatarSymbol: avatarSymbol
        )
    }

    // MARK: - Friend search + requests

    /// Look up a user by exact (case-insensitive) username. Returns nil if
    /// nobody has claimed that handle.
    func searchUser(byUsername raw: String) async throws -> UserSearchResult? {
        guard let normalized = usernameRepository.normalize(raw) else { return nil }
        return try await usernameRepository.lookup(normalized)
    }

    /// Send a friend request to a specific user — adds them as a participant
    /// on my personal CKShare. They receive an iOS system notification and
    /// become a friend when they accept. Their app reciprocally shares back
    /// via the existing `handleIncomingShareIfNeeded` flow.
    func sendFriendRequest(to userRecordName: String) async throws {
        let recordID = CKRecord.ID(recordName: userRecordName)
        try await personalRepository.addFriendParticipant(userRecordID: recordID)
        await personalStore.refresh()
    }

    /// Set the user's accent-color preset. Local-only — no CloudKit round-trip.
    /// Updates `ThemeStore` (which `tallyAccent` reads from) and flips
    /// our own observed `themeColor` to trigger SwiftUI re-renders.
    func setThemeColor(_ color: ThemeColor) {
        themeColor = color
        ThemeStore.shared.update(color)
    }

    /// Called from `HabitsSetupView`. Persists each non-empty title as a habit in
    /// the active Circle, then routes to goals setup.
    func saveInitialHabits(_ titles: [String]) {
        for title in titles {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            personalStore.addHabit(title: trimmed, for: currentUserID)
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
            personalStore.addGoal(
                title: trimmed,
                for: currentUserID,
                period: .week,
                periodStart: weekStart
            )
        }
        isFirstRunOnboarding = false
        LocalCache.save(true, forKey: LocalCacheKey.hasOnboarded)
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

    /// If a CKShare invite is pending (from a tapped invite link), accept it
    /// and route based on the share's zone: Circle invite → join the Circle;
    /// personal-share invite → become friends (reciprocally).
    /// Called on reaching the gate and on scene-foreground.
    func handleIncomingShareIfNeeded() async {
        guard let metadata = pendingShareBuffer.consume() else { return }
        isAcceptingShare = true
        defer { isAcceptingShare = false }
        do {
            try await shareCoordinator.acceptShare(metadata)

            if let circleID = ShareCoordinator.circleID(from: metadata) {
                // Circle invite — join the Circle.
                try await circleRepository.recordOwnMembership(
                    circleID: circleID,
                    displayName: ownCloudProfile?.displayName ?? "Me",
                    avatarSymbol: ownCloudProfile?.avatarSymbol ?? "leaf"
                )
                await loadCircles()
                if let active = activeCircle {
                    await circleStore.activate(active, currentUserID: currentUserID)
                }
                if onboardingState == .needsCircleSetup {
                    advancePastCircleSetup()
                }
            } else if ShareCoordinator.zoneName(from: metadata) == CloudKitPersonalRepository.zoneName {
                // Personal-share invite — become friends. Reciprocally add the
                // inviter as a participant on MY personal share so they see my
                // data too. Then refresh PersonalStore to load their data.
                if let ownerID = metadata.ownerIdentity.userRecordID {
                    try? await personalRepository.addFriendParticipant(userRecordID: ownerID)
                }
                await personalStore.refresh()
            }
        } catch {
            circleActionError = "Couldn't accept share: \(error.localizedDescription)"
        }
    }

    /// Pull the latest Circle + personal data from CloudKit. Called on
    /// scene-foreground and when a CloudKit push notification arrives.
    func refreshCircleData() async {
        await circleStore.refresh()
        await personalStore.refresh()
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

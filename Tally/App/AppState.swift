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
    /// New 8-step paywalled onboarding flow + the transient runtime states
    /// (sign-in gate, checking iCloud, error). The in-flow cases are mirrored
    /// in `PersistedOnboardingStep` and written to `LocalCacheKey.onboardingStep`
    /// on every transition so killing the app mid-flow resumes at the same step.
    /// Transient states (`.checkingICloud`, `.needsSignIn`, `.error`) are
    /// runtime-only and do not overwrite the persisted step.
    enum OnboardingState: Equatable {
        case checkingICloud
        case needsSignIn(reason: CKAccountStatus)
        case displayNameEntry        // screen 1
        case firstHabitEntry         // screen 2 (required)
        case firstGoalEntry          // screen 3 (skippable)
        case leaderboardPreview      // screen 4
        case profileCustomization    // screen 5 (username + avatar + theme)
        case paywall                 // screen 6 (non-dismissible)
        case celebration             // screen 7
        case enteredMainApp          // screen 8 / main app
        case error(String)
    }

    /// Stable, Codable mirror of the in-flow cases used for LocalCache
    /// persistence. Excludes transient runtime states so re-launch always
    /// resumes at a real step.
    enum PersistedOnboardingStep: String, Codable {
        case displayNameEntry
        case firstHabitEntry
        case firstGoalEntry
        case leaderboardPreview
        case profileCustomization
        case paywall
        case celebration
        case enteredMainApp
    }

    // MARK: - Onboarding / identity

    var onboardingState: OnboardingState = .checkingICloud {
        didSet { persistOnboardingStep() }
    }

    /// The signed-in user's CloudKit profile. Set after fetch on launch and after
    /// the user submits ProfileSetupView.
    var ownCloudProfile: UserProfile?

    /// Signed-in user's CloudKit record name. Empty until resolved on launch;
    /// every per-user lookup (own habits, own goals, "is this me") keys off it.
    var currentUserID: String = ""

    /// The user's currently-selected theme. Mirrors `ThemeManager.shared`
    /// so SwiftUI views can read `appState.theme` instead of poking the
    /// singleton directly. Setting this property here forwards to the
    /// manager via `setTheme(_:)` so persistence lives in one place.
    var theme: TallyTheme = ThemeManager.shared.current

    /// Convenience: the SwiftUI Color for the theme's accent. Retained so
    /// the existing `TallyApp` injection (which reads `accentColor`) keeps
    /// working without churning every callsite.
    var accentColor: Color { theme.accent }

    // MARK: - Repositories + store

    let profileRepository: any ProfileRepository
    let circleRepository: any CircleRepository
    let personalRepository: any PersonalRepository
    let usernameRepository: any UsernameRepository
    let friendRequestRepository: any FriendRequestRepository
    let groupInviteRepository: any GroupInviteRepository
    let unfriendNotificationRepository: any UnfriendNotificationRepository
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

    /// Circles created in this session that the server's `allRecordZones()`
    /// listing may not have surfaced yet (eventual consistency right after
    /// zone creation). `loadCircles` keeps these in `ownedCircles` until the
    /// server result includes them, so a freshly-created group/DM doesn't
    /// vanish from the Messages/Groups list between create and the server
    /// catching up.
    private var recentlyCreatedCircleIDs: Set<UUID> = []
    var isAcceptingShare = false
    var circleActionError: String?
    /// Latest CloudKit error from the share / invite flow. Set when the system
    /// share sheet fails to mint or save its CKShare, so the app can surface
    /// the real error instead of iOS's generic "A link couldn't be created".
    var lastCloudShareError: String?

    var allCircles: [TallyCircle] { ownedCircles + joinedCircles }

    /// Pending incoming friend requests addressed to me. Populated by
    /// `refreshFriendRequests()` on launch and scene-foreground. Reciprocal
    /// requests (auto-accepted) are processed and removed from this list
    /// before it's published, so the UI only ever shows fresh ones the user
    /// needs to act on.
    var incomingFriendRequests: [FriendRequest] = []

    /// User record names of people I've sent a friend request to that hasn't
    /// completed yet (target isn't in my friends list). Powers the "Request
    /// pending" UI state in `FriendSearchView` so the user doesn't keep
    /// hammering Send while the reciprocal-out is still propagating —
    /// that pattern previously created duplicate public-DB request records
    /// that the recipient's app correctly filters out (already-a-friend),
    /// making the sender think nothing was happening.
    var outgoingRequestTargetIDs: Set<String> = []

    /// Local-only set of declined request IDs. Since recipients can't delete
    /// records they didn't create, decline = hide in our UI. Persisted via
    /// LocalCache so the request stays hidden across launches.
    private var declinedRequestIDs: Set<String> = []

    /// Last error from the public-DB friend-request refresh, surfaced as a
    /// banner so we don't fly blind when CloudKit query-index config is wrong.
    /// Cleared on the next successful refresh.
    var lastFriendRequestError: String?

    /// Pending incoming group invites addressed to me. Same lifecycle as
    /// `incomingFriendRequests`: refreshed on launch and scene-foreground,
    /// filtered to hide locally-declined ones and invites for Circles I'm
    /// already in.
    var incomingGroupInvites: [GroupInvite] = []

    /// Local-only set of declined invite IDs (recipients can't delete
    /// public-DB records they didn't create).
    private var declinedGroupInviteIDs: Set<String> = []

    /// Last error from the public-DB group-invite refresh, surfaced as a
    /// banner. Cleared on the next successful refresh.
    var lastGroupInviteError: String?

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

    /// Long-lived poll that periodically calls `refreshFriendRequests`. CloudKit
    /// silent push for public-DB record changes is unreliable on TestFlight, so
    /// without this an accepted reciprocal only surfaces when the sender
    /// backgrounds and re-foregrounds the app. The poll keeps the sender's
    /// friend list within ~6s of live while they sit on the screen waiting.
    private var friendRequestPollTask: Task<Void, Never>?

    /// Re-entrancy guard so the periodic poll and a manual refresh (e.g. from
    /// pull-to-refresh or post-send) can't both auto-accept the same
    /// reciprocal record at the same time.
    private var isRefreshingFriendRequests = false

    /// Sender record names whose ORIGINAL friend request we accepted (we
    /// successfully joined their share — they already see us) but whose
    /// reciprocal-out step partially failed. Persisted so a relaunch
    /// doesn't lose them. Retried on every poll tick until each one
    /// succeeds — this is the fix for the recurring "they see me but I
    /// don't see them" symptom.
    private var pendingReciprocalSenders: Set<String> = []

    /// UnfriendNotification record IDs we've already applied locally.
    /// Persisted so the poll task doesn't keep re-applying the same
    /// hide-list mutation every 6s (idempotent in practice, but we still
    /// want to skip the work).
    private var processedUnfriendNotificationIDs: Set<String> = []

    /// Target userIDs whose `UnfriendNotification` write failed and needs
    /// retry. Exact mirror of `pendingReciprocalSenders`: a `Set<String>`
    /// persisted as `[String]`, retried every poll tick + on launch, each
    /// entry dequeued only on a confirmed successful write. Without this,
    /// a single failed notification send would leave the other person
    /// seeing me (and retaining access) forever.
    private var pendingUnfriendTargets: Set<String> = []

    /// Group/DM invites whose `GroupInvite` write failed and needs retry.
    /// Same `Set<String>` / `[String]` shape as `pendingReciprocalSenders`,
    /// but each entry is a composite `"circleID|userID"` key because an
    /// invite needs both the circle and the recipient. At flush, the
    /// circle is resolved from `allCircles` by id. Dequeued only on a
    /// confirmed successful invite write. Without this, a dropped DM/group
    /// invite never reaches the recipient and has no recovery.
    private var pendingGroupInvites: Set<String> = []

    init(
        profileRepository: any ProfileRepository = CloudKitProfileRepository(),
        circleRepository: any CircleRepository = CloudKitCircleRepository(),
        personalRepository: any PersonalRepository = CloudKitPersonalRepository(),
        usernameRepository: any UsernameRepository = CloudKitUsernameRepository(),
        friendRequestRepository: any FriendRequestRepository = CloudKitFriendRequestRepository(),
        groupInviteRepository: any GroupInviteRepository = CloudKitGroupInviteRepository(),
        unfriendNotificationRepository: any UnfriendNotificationRepository = CloudKitUnfriendNotificationRepository(),
        shareCoordinator: ShareCoordinator = ShareCoordinator(),
        circleStore: CircleStore? = nil,
        personalStore: PersonalStore? = nil
    ) {
        self.profileRepository = profileRepository
        self.circleRepository = circleRepository
        self.personalRepository = personalRepository
        self.usernameRepository = usernameRepository
        self.friendRequestRepository = friendRequestRepository
        self.groupInviteRepository = groupInviteRepository
        self.unfriendNotificationRepository = unfriendNotificationRepository
        self.shareCoordinator = shareCoordinator
        self.circleStore = circleStore ?? CircleStore()
        self.personalStore = personalStore ?? PersonalStore(repository: personalRepository)
        self.declinedRequestIDs = Set(
            LocalCache.load([String].self, forKey: LocalCacheKey.declinedFriendRequestIDs) ?? []
        )
        self.declinedGroupInviteIDs = Set(
            LocalCache.load([String].self, forKey: LocalCacheKey.declinedGroupInviteIDs) ?? []
        )
        self.pendingReciprocalSenders = Set(
            LocalCache.load([String].self, forKey: LocalCacheKey.pendingReciprocalSenders) ?? []
        )
        self.processedUnfriendNotificationIDs = Set(
            LocalCache.load([String].self, forKey: LocalCacheKey.processedUnfriendNotificationIDs) ?? []
        )
        self.pendingUnfriendTargets = Set(
            LocalCache.load([String].self, forKey: LocalCacheKey.pendingUnfriendTargets) ?? []
        )
        self.pendingGroupInvites = Set(
            LocalCache.load([String].self, forKey: LocalCacheKey.pendingGroupInvites) ?? []
        )

        // Skip the "Checking iCloud…" spinner on launch for returning users.
        // The `hasOnboarded` flag is the source of truth — written the moment
        // the user first reaches `.ready` — so even if the profile/userID
        // caches fail to decode for some reason, returning users still get
        // straight onto the dashboard. The background refresh below verifies
        // everything and fixes up any stale state.
        let hasOnboarded = LocalCache.load(Bool.self, forKey: LocalCacheKey.hasOnboarded) ?? false
        let persistedStepRaw = LocalCache.load(String.self, forKey: LocalCacheKey.onboardingStep)
        let persistedStep = persistedStepRaw.flatMap(PersistedOnboardingStep.init(rawValue:))

        if let persistedStep {
            // Resume mid-flow on relaunch. Profile + userID may or may not be
            // present depending on how far the user got; that's OK — each
            // step's view handles a partial profile.
            self.currentUserID = LocalCache.load(String.self, forKey: LocalCacheKey.currentUserID) ?? ""
            self.ownCloudProfile = LocalCache.load(UserProfile.self, forKey: LocalCacheKey.ownProfile)
            self.onboardingState = Self.state(from: persistedStep)
        } else if hasOnboarded {
            // Build-37 (and earlier) user with no persisted step: they finished
            // the old onboarding, so drop them straight into the main app.
            self.currentUserID = LocalCache.load(String.self, forKey: LocalCacheKey.currentUserID) ?? ""
            self.ownCloudProfile = LocalCache.load(UserProfile.self, forKey: LocalCacheKey.ownProfile)
            self.onboardingState = .enteredMainApp
        }
        NSLog("[Tally] AppState.init hasOnboarded=\(hasOnboarded) persistedStep=\(persistedStepRaw ?? "nil") state=\(self.onboardingState)")

        registerAccountChangeObserver()
        Task { await self.refreshAccountState() }
        startFriendRequestPolling()
    }

    /// Begin (or no-op if already running) the periodic friend-request poll.
    /// The task loops forever and is only cancelled if `stopFriendRequestPolling`
    /// is called explicitly — iOS suspends the Task naturally when the app
    /// backgrounds and resumes it on foreground, so we don't gate scenePhase.
    func startFriendRequestPolling() {
        guard friendRequestPollTask == nil else { return }
        friendRequestPollTask = Task { @MainActor [weak self] in
            // 6s cadence balances "feels live" against polling cost. Each
            // tick is one public-DB query for FriendRequest records keyed
            // on toUserRecordName == me, plus a follow-up outgoing query
            // only if reciprocals were found.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                if Task.isCancelled { return }
                guard let self else { return }
                // Skip when not signed-in or still onboarding — no point
                // hitting CloudKit before currentUserID is populated.
                guard !self.currentUserID.isEmpty,
                      self.onboardingState == .enteredMainApp else { continue }
                await self.refreshFriendRequests()
                // Drain the half-completed-accept queue. Each entry is a
                // sender we acknowledged but never successfully sent our
                // own share URL back to — without this, "they see me but
                // I don't see them" is permanent.
                await self.retryPendingReciprocals()
                // Apply any new unfriend notifications targeted at us so
                // a friend who unfriended us disappears from our friends
                // list within the next 6s, even though their share is
                // still technically in our sharedDB.
                await self.processUnfriendNotifications()
                // Retry any unfriend notifications WE failed to send, so a
                // dropped write still reaches the other person's device.
                await self.retryPendingUnfriendNotifications()
                // Pick up incoming group/DM invites on the same cadence.
                // Without this, a DM or group invite only surfaced on
                // launch / scene-foreground — so the peer wouldn't see a
                // new DM "on their tally" until they backgrounded the app.
                await self.refreshGroupInvites()
                // Retry any group/DM invite WE failed to send, so a dropped
                // invite write still reaches the recipient.
                await self.retryPendingGroupInvites()
            }
        }
    }

    func stopFriendRequestPolling() {
        friendRequestPollTask?.cancel()
        friendRequestPollTask = nil
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
    /// Map a persisted step back to a runtime OnboardingState.
    static func state(from step: PersistedOnboardingStep) -> OnboardingState {
        switch step {
        case .displayNameEntry:     return .displayNameEntry
        case .firstHabitEntry:      return .firstHabitEntry
        case .firstGoalEntry:       return .firstGoalEntry
        case .leaderboardPreview:   return .leaderboardPreview
        case .profileCustomization: return .profileCustomization
        case .paywall:              return .paywall
        case .celebration:          return .celebration
        case .enteredMainApp:       return .enteredMainApp
        }
    }

    /// Map an in-memory state to its persisted form, or nil for transient
    /// runtime states that must never overwrite the stored step.
    private static func persistedStep(from state: OnboardingState) -> PersistedOnboardingStep? {
        switch state {
        case .displayNameEntry:     return .displayNameEntry
        case .firstHabitEntry:      return .firstHabitEntry
        case .firstGoalEntry:       return .firstGoalEntry
        case .leaderboardPreview:   return .leaderboardPreview
        case .profileCustomization: return .profileCustomization
        case .paywall:              return .paywall
        case .celebration:          return .celebration
        case .enteredMainApp:       return .enteredMainApp
        case .checkingICloud, .needsSignIn, .error:
            return nil
        }
    }

    /// Called from `onboardingState.didSet`. Writes the current step to
    /// LocalCache so a relaunch picks up where we were; transient states
    /// leave the stored value untouched.
    private func persistOnboardingStep() {
        guard let step = Self.persistedStep(from: onboardingState) else { return }
        LocalCache.save(step.rawValue, forKey: LocalCacheKey.onboardingStep)
    }

    func refreshAccountState() async {
        if onboardingState != .enteredMainApp {
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
                    await refreshFriendRequests()
                    await refreshGroupInvites()
                    await processUnfriendNotifications()
                    await retryPendingUnfriendNotifications()
                    await retryPendingGroupInvites()
                    // Resume at whichever step is persisted, or fall through
                    // to the main app for a build-37 legacy user.
                    if let circle = activeCircle {
                        await circleStore.activate(circle, currentUserID: currentUserID)
                    }
                    if let stepRaw = LocalCache.load(String.self, forKey: LocalCacheKey.onboardingStep),
                       let step = PersistedOnboardingStep(rawValue: stepRaw) {
                        onboardingState = Self.state(from: step)
                    } else {
                        // Profile exists but no persisted step (legacy or
                        // direct-jump) — drop into the main app.
                        onboardingState = .enteredMainApp
                    }
                } else {
                    // No profile yet — start (or resume) the new flow.
                    if let stepRaw = LocalCache.load(String.self, forKey: LocalCacheKey.onboardingStep),
                       let step = PersistedOnboardingStep(rawValue: stepRaw) {
                        onboardingState = Self.state(from: step)
                    } else {
                        onboardingState = .displayNameEntry
                    }
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

    // Legacy `enterMainAppOrCircleSetup` (which set `.ready`) is gone —
    // the new flow's terminal step is `.enteredMainApp`, and
    // `refreshAccountState` activates the first circle inline.

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

    /// Called from `ProfileSetupView` on submit. Claims the username in the
    /// public DB (throws if taken or malformed), persists the profile to
    /// CloudKit, mirrors the user's name + avatar into their personal zone's
    /// root record so friends can render them, then routes to habits setup.
    func saveProfile(
        displayName: String,
        username: String,
        avatarSymbol: String,
        avatarImageData: Data? = nil
    ) async throws {
        // After a same-session `deleteAccount`, `currentUserID` was reset
        // to "" and the next launch's `refreshAccountState` hasn't run
        // yet — but the user is signed into the same iCloud account, so
        // we can re-fetch their userRecordID right here. Without this,
        // they'd reach `.ready` with an empty `currentUserID` and the
        // first friend-request send would throw "Not signed into
        // iCloud." even though they obviously ARE.
        if currentUserID.isEmpty {
            currentUserID = try await CKClient.shared.userRecordID().recordName
            LocalCache.save(currentUserID, forKey: LocalCacheKey.currentUserID)
        }

        // Normalize + claim BEFORE saving the profile so a name conflict
        // doesn't strand the user with a profile pointing at an unowned
        // username. Mirrors updateProfile's order of operations.
        guard let normalized = usernameRepository.normalize(username) else {
            throw UsernameError.invalid
        }
        try await usernameRepository.claim(
            normalized,
            previousUsername: nil,
            displayName: displayName,
            avatarSymbol: avatarSymbol,
            avatarImageData: avatarImageData
        )

        let profile = try await profileRepository.saveOwnProfile(
            displayName: displayName,
            avatarSymbol: avatarSymbol,
            avatarImageData: avatarImageData,
            clearAvatarPhoto: false,
            username: normalized
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
            avatarSymbol: avatarSymbol,
            avatarImageData: avatarImageData,
            clearAvatarPhoto: false
        )

        // Legacy saveProfile (used by the old ProfileSetupView) jumps straight
        // to the main app. The new paywalled flow uses
        // `completeDisplayNameEntry` → `completeProfileCustomization` instead.
        onboardingState = .enteredMainApp
        await handleIncomingShareIfNeeded()
    }

    /// Legacy theme-pick handler. Retained for source compatibility but no
    /// longer reachable from RootView — the new flow folds theme selection
    /// into `.profileCustomization`.
    func finishThemePick(_ chosen: TallyTheme) {
        setTheme(chosen)
        UserDefaults.standard.set(true, forKey: ThemeManager.hasPickedThemeKey)
        onboardingState = .enteredMainApp
    }

    /// Legacy first-circle bootstrap. Unreachable in the new flow.
    func setUpInitialCircle(name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = ownCloudProfile
        let circle = try await circleRepository.createCircle(
            name: trimmed.isEmpty ? "My Circle" : trimmed,
            emoji: nil,
            ownerDisplayName: profile?.displayName ?? "Me",
            ownerAvatarSymbol: profile?.avatarSymbol ?? "leaf",
            kind: .group,
            dmPeerID: nil
        )
        await loadCircles()
        await circleStore.activate(circle, currentUserID: currentUserID)
        onboardingState = .enteredMainApp
    }

    // MARK: - New paywalled-onboarding step completions

    /// Step 1 → Step 2. Fetches `currentUserID` if it isn't set yet (same
    /// safeguard as `saveProfile`'s post-delete-resignup path), writes a
    /// minimal `UserProfile` with the display name + default avatar (no
    /// username yet — that's collected in `.profileCustomization`),
    /// activates the personal store, and advances to `.firstHabitEntry`.
    func completeDisplayNameEntry(displayName: String) async throws {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if currentUserID.isEmpty {
            currentUserID = try await CKClient.shared.userRecordID().recordName
            LocalCache.save(currentUserID, forKey: LocalCacheKey.currentUserID)
        }
        let profile = try await profileRepository.saveOwnProfile(
            displayName: trimmed,
            avatarSymbol: "leaf",
            avatarImageData: nil,
            clearAvatarPhoto: false,
            username: nil
        )
        isFirstRunOnboarding = true
        persistProfile(profile)
        try? await personalRepository.ensurePersonalZone()
        try? await personalRepository.updatePersonalRootProfile(
            displayName: trimmed,
            avatarSymbol: "leaf",
            avatarImageData: nil,
            clearAvatarPhoto: false
        )
        await personalStore.activate(currentUserID: currentUserID)
        onboardingState = .firstHabitEntry
    }

    /// Step 2 → Step 3. Saves the required first habit and advances.
    func completeFirstHabitEntry(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        personalStore.addHabit(title: trimmed, for: currentUserID, privacy: .shared)
        onboardingState = .firstGoalEntry
    }

    /// Step 3 → Step 4 (entered a goal). Saves the goal at the period the
    /// user picked and advances to the leaderboard preview.
    func completeFirstGoalEntry(title: String, period: GoalPeriod) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let periodStart = period.startDate(for: .now)
            personalStore.addGoal(
                title: trimmed,
                for: currentUserID,
                period: period,
                periodStart: periodStart
            )
        }
        onboardingState = .leaderboardPreview
    }

    /// Step 3 → Step 4 (skipped).
    func skipFirstGoalEntry() {
        onboardingState = .leaderboardPreview
    }

    /// Step 4 → Step 5.
    func completeLeaderboardPreview() {
        onboardingState = .profileCustomization
    }

    /// Step 5 → Step 6. Claims the username (throws on collision), updates
    /// avatar + theme, then advances to the paywall.
    func completeProfileCustomization(
        username: String,
        avatarSymbol: String,
        theme: TallyTheme,
        avatarImageData: Data? = nil
    ) async throws {
        try await updateProfile(
            displayName: ownCloudProfile?.displayName ?? "",
            avatarSymbol: avatarSymbol,
            username: username,
            avatarImageData: avatarImageData,
            clearAvatarPhoto: false
        )
        setTheme(theme)
        UserDefaults.standard.set(true, forKey: ThemeManager.hasPickedThemeKey)
        onboardingState = .paywall
    }

    /// Step 6 → Step 7. Called by `PaywallView` once `isSubscribed` is true
    /// (either a real purchase, a successful restore, or the Debug bypass
    /// toggle). Guarded on the current state so the same call from the
    /// lapse-cover paywall (where `onboardingState == .enteredMainApp`)
    /// doesn't accidentally bounce the user back to celebration.
    func completePaywall() {
        guard onboardingState == .paywall else { return }
        onboardingState = .celebration
    }

    /// Step 7 → Step 8. Marks onboarding complete and enters the main app.
    func completeCelebration() async {
        isFirstRunOnboarding = false
        LocalCache.save(true, forKey: LocalCacheKey.hasOnboarded)
        if let circle = activeCircle {
            await circleStore.activate(circle, currentUserID: currentUserID)
        }
        onboardingState = .enteredMainApp
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
            // Server-side: zone deletion cascade-removed all records
            // inside (root, members, messages, summaries, the CKShare).
            // Local-side and side-channel cleanup:
            //   - LocalCache entries (lastReadAt / lastMessageAt) keyed
            //     by this circle's UUID become dead weight; remove them.
            //   - Any outgoing GroupInvite records in the public DB
            //     pointing at this circle become orphaned. Delete them
            //     so they don't continue to surface in recipients' inboxes
            //     or get re-processed in the cleanup pass.
            Self.removeCachedCircleEntries(circleID: circle.id)
            do {
                let outgoing = try await groupInviteRepository.outgoing(for: currentUserID)
                for inv in outgoing where inv.circleID == circle.id {
                    try? await groupInviteRepository.delete(inv)
                }
            } catch {
                NSLog("[Tally] deleteCircle: outgoing-invite cleanup failed (non-fatal): \(error.localizedDescription)")
            }
        } catch {
            circleActionError = error.localizedDescription
        }
    }

    /// Strip persisted per-circle bookkeeping (unread state, last-message
    /// timestamp) for a circle that no longer exists. Called after a
    /// successful delete or leave so the next launch doesn't render an
    /// unread dot for a phantom row.
    private static func removeCachedCircleEntries(circleID: UUID) {
        let key = circleID.uuidString
        for cacheKey in [LocalCacheKey.circleLastReadAt, LocalCacheKey.circleLastMessageAt] {
            var dict = LocalCache.load([String: Double].self, forKey: cacheKey) ?? [:]
            if dict.removeValue(forKey: key) != nil {
                LocalCache.save(dict, forKey: cacheKey)
            }
        }
    }

    /// Participant leaves a Group (removes self from the share). Owners use
    /// `deleteCircle` instead.
    func leaveCircle(_ circle: TallyCircle) async {
        do {
            try await circleRepository.leaveCircle(circle)
            // Clean the same local caches as deleteCircle — once we've
            // left, the circle is gone from our view and the bookkeeping
            // is dead weight.
            Self.removeCachedCircleEntries(circleID: circle.id)
            await loadCircles()
            if let next = activeCircle {
                await circleStore.activate(next, currentUserID: currentUserID)
            }
        } catch {
            circleActionError = error.localizedDescription
        }
    }

    /// Rename a Group. Any participant can do this — CKShare grants .readWrite
    /// on the root record. Reloads the Circle list so the header updates.
    func renameCircle(_ circle: TallyCircle, to newName: String) async throws {
        _ = try await circleRepository.rename(circle, to: newName)
        await loadCircles()
    }

    /// Owner-only: invite a known user (resolved via username search) to the
    /// active Group. Goes through `sendGroupInvite` so the recipient sees the
    /// invitation in their in-app inbox rather than relying on iOS's
    /// unreliable CKShare push notification.
    func addMemberToCircle(_ circle: TallyCircle, userRecordName: String) async throws {
        try await sendGroupInvite(to: userRecordName, circle: circle)
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
        username: String?,
        avatarImageData: Data? = nil,
        clearAvatarPhoto: Bool = false
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
            // Resolve which photo bytes to publish on the UsernameClaim:
            //   - clearAvatarPhoto: force-nil (user removed their photo)
            //   - avatarImageData != nil: replace with the new photo
            //   - both nil: keep what's already stored (name-only update)
            let publishedPhoto: Data?
            if clearAvatarPhoto {
                publishedPhoto = nil
            } else if let avatarImageData {
                publishedPhoto = avatarImageData
            } else {
                publishedPhoto = ownCloudProfile?.avatarImageData
            }
            try await usernameRepository.claim(
                normalized,
                previousUsername: previous,
                displayName: trimmedName,
                avatarSymbol: avatarSymbol,
                avatarImageData: publishedPhoto
            )
        } else if let previous {
            try? await usernameRepository.release(previous)
        }

        let profile = try await profileRepository.saveOwnProfile(
            displayName: trimmedName,
            avatarSymbol: avatarSymbol,
            avatarImageData: avatarImageData,
            clearAvatarPhoto: clearAvatarPhoto,
            username: normalized
        )
        persistProfile(profile)

        // Push to PersonalRoot so friends see the new name + avatar + photo.
        try? await personalRepository.updatePersonalRootProfile(
            displayName: trimmedName,
            avatarSymbol: avatarSymbol,
            avatarImageData: avatarImageData,
            clearAvatarPhoto: clearAvatarPhoto
        )
    }

    // MARK: - Friend search + requests

    /// Look up a user by exact (case-insensitive) username. Returns nil if
    /// nobody has claimed that handle.
    func searchUser(byUsername raw: String) async throws -> UserSearchResult? {
        guard let normalized = usernameRepository.normalize(raw) else { return nil }
        return try await usernameRepository.lookup(normalized)
    }

    /// Send a friend request to a specific user. Writes a FriendRequest record
    /// to CloudKit's public DB so the recipient's app can pick it up reliably —
    /// the prior design relied on iCloud system notifications firing when a
    /// participant was added to a CKShare, which doesn't actually fire across
    /// all account / iOS / TestFlight combinations and left requests invisible.
    /// The recipient sees it in their in-app inbox; on Accept their app fetches
    /// our personal share URL and accepts programmatically.
    func sendFriendRequest(to userRecordName: String) async throws {
        // NOTE: we deliberately do NOT clear locallyUnfriendedIDs here
        // anymore. The recipient's zone may still be in our sharedDB
        // (we don't leave their share on unfriend), so clearing the
        // filter on send would cause the next personalStore.refresh
        // to re-add them as a friend BEFORE they've accepted the new
        // request — which made the UI flip from "Send friend request"
        // straight to "Already friends" without ever showing "Sent".
        // The flag now clears in two places: acceptFriendRequest
        // (when we accept someone we'd previously unfriended) and the
        // reciprocal auto-accept loop (when our request is accepted
        // back). That keeps the unfriend filter on until the
        // bidirectional friendship is genuinely re-established.

        guard !currentUserID.isEmpty else {
            throw NSError(
                domain: "AppState.sendFriendRequest",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Not signed into iCloud."]
            )
        }
        guard let profile = ownCloudProfile else {
            throw NSError(
                domain: "AppState.sendFriendRequest",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Set up your profile before adding friends."]
            )
        }
        guard let username = profile.username, !username.isEmpty else {
            throw NSError(
                domain: "AppState.sendFriendRequest",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Pick a username in your profile before sending friend requests so they know who you are."]
            )
        }
        // Defense in depth: the UI hides the send button for existing friends,
        // but if someone hits this path another way we still refuse to create
        // a duplicate request that the recipient would just have to dismiss.
        if personalStore.friends.contains(where: { $0.userID == userRecordName }) {
            throw NSError(
                domain: "AppState.sendFriendRequest",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "You're already friends with this person."]
            )
        }
        // Mint (or fetch) my personal share so the recipient has a URL to accept.
        let (share, _) = try await personalRepository.makePersonalShare()
        guard let shareURL = share.url else {
            throw NSError(
                domain: "AppState.sendFriendRequest",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Couldn't get a share URL — try again in a moment."]
            )
        }

        NSLog("[Tally] sendFriendRequest: from=\(currentUserID) to=\(userRecordName)")
        let request = FriendRequest(
            id: UUID(),
            fromUserRecordName: currentUserID,
            toUserRecordName: userRecordName,
            shareURL: shareURL.absoluteString,
            fromDisplayName: profile.displayName,
            fromUsername: username,
            fromAvatarSymbol: profile.avatarSymbol,
            sentAt: .now,
            isReciprocal: false
        )
        try await friendRequestRepository.send(request)
        // Optimistically mark this target as having a pending outgoing
        // request so the search UI immediately switches from "Send" to
        // "Request pending" without waiting for the next 6s refresh.
        outgoingRequestTargetIDs.insert(userRecordName)
        // Persistent signal for `InviteFriendsBanner` to permanently hide
        // — once the user has invited *anyone*, the banner has served its
        // purpose, regardless of whether the request is accepted later.
        LocalCache.save(true, forKey: LocalCacheKey.hasSentFirstFriendRequest)
        // Refresh immediately so a self-send (or any quick verification) shows
        // up in the inbox without requiring a manual pull-to-refresh.
        await refreshFriendRequests()
    }

    /// Recipient accepts an incoming friend request.
    ///
    /// 1. Fetch the sender's share metadata from the URL embedded in the
    ///    request, then accept it via CKAcceptSharesOperation — this is what
    ///    makes the sender's zone appear in our shared DB.
    /// 2. Reciprocally add the sender as a participant on OUR personal share
    ///    so they get access to our data too (same code path the legacy
    ///    handleIncomingShareIfNeeded uses).
    /// 3. Write a reciprocal FriendRequest record back to the sender — when
    ///    their app polls, it auto-accepts (no UI prompt) and the bidirectional
    ///    friend graph is complete.
    /// 4. Refresh state so the friend appears immediately in the friends list.
    func acceptFriendRequest(_ request: FriendRequest) async throws {
        // Re-engagement: if I previously unfriended this person on
        // this device, clear the local filter now that I'm accepting
        // them back in.
        personalStore.clearLocalUnfriend(userID: request.fromUserRecordName)

        // Self-friending isn't a real CloudKit operation — you can't accept
        // your own CKShare. Treat it as a test artifact and just dismiss.
        if request.fromUserRecordName == currentUserID {
            markRequestDeclined(request)
            try? await friendRequestRepository.delete(request)
            await refreshFriendRequests()
            return
        }
        let shareURL = URL(string: request.shareURL)
        guard let shareURL else {
            throw NSError(
                domain: "AppState.acceptFriendRequest",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid share URL on the request."]
            )
        }
        let container = CKClient.shared.container
        let metadata = try await container.shareMetadata(for: shareURL)
        try await acceptShareMetadata(metadata)
        NSLog("[Tally] acceptFriendRequest: accepted share for sender=\(request.fromUserRecordName)")

        // Hide the inbox row immediately — the sender's side is unblocked
        // (we're a participant on their share, so they already see us in
        // their friend list). What's left is to ship OUR share URL back
        // to them so they can see us too. Decoupling that into a retryable
        // step means a flaky network or transient CloudKit error on the
        // reciprocal-out steps doesn't permanently strand the sender.
        markRequestDeclined(request)

        // Track this sender as needing reciprocal-out completion. The
        // pending set is consulted by the poll task and re-attempted
        // every 6s until each completes. Persisted so a relaunch
        // mid-flow doesn't lose the queue.
        pendingReciprocalSenders.insert(request.fromUserRecordName)
        persistPendingReciprocalSenders()

        // First-try attempt happens immediately — the poller backfills
        // retries if this throws.
        do {
            try await sendReciprocalShareBack(to: request.fromUserRecordName)
            pendingReciprocalSenders.remove(request.fromUserRecordName)
            persistPendingReciprocalSenders()
        } catch {
            NSLog("[Tally] acceptFriendRequest: reciprocal-out failed (queued for retry): \(error.localizedDescription)")
            lastFriendRequestError = "Friend added on your end. Still completing the connection — keep the app open a moment longer."
            // Don't re-throw: we want the inbox UI to clear, and the
            // pending-retry queue + poll loop will finish the job.
        }

        await personalStore.refresh()
        await refreshFriendRequests()
        NSLog("[Tally] acceptFriendRequest: done")
    }

    /// The post-acceptShareMetadata reciprocal-out steps, factored out so
    /// they can be retried idempotently from the poll task without
    /// re-running the share-metadata accept (which can't be retried
    /// safely after the first call). addFriendParticipant early-returns
    /// if the sender is already a participant, makePersonalShare returns
    /// the cached share if one exists, and friendRequestRepository.send
    /// just writes a new public-DB record — all idempotent or
    /// idempotent-enough that running this twice does no harm beyond a
    /// slightly redundant write.
    private func sendReciprocalShareBack(to senderRecordName: String) async throws {
        guard let profile = ownCloudProfile else {
            throw NSError(
                domain: "AppState.sendReciprocalShareBack",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Set up your profile before accepting friend requests."]
            )
        }

        let senderRecordID = CKRecord.ID(recordName: senderRecordName)
        // BEST-EFFORT, intentionally. `addFriendParticipant` uses
        // `CKFetchShareParticipantsOperation` which requires the sender
        // to be CloudKit-discoverable to us. Discoverability is granted
        // automatically once we accept their share (acceptShareMetadata
        // ran upstream), but the propagation lags — sometimes 30+s — and
        // until then the lookup throws `.permissionFailure`. Propagating
        // that throw used to abort the entire reciprocal-out flow on
        // every retry, indefinitely, which is the recurring "they accept
        // me but I never see them" bug the user has reported for weeks.
        //
        // Why we can swallow it: our personal share has
        // `publicPermission = .readOnly`, meaning ANY URL-bearer becomes
        // a participant when they accept the URL. The named-participant
        // slot is just a hint to CloudKit; the URL is what actually
        // grants access. So even if we never pre-add the sender, they
        // join via the URL once their app's acceptShareMetadata runs on
        // the reciprocal we're about to send.
        do {
            try await personalRepository.addFriendParticipant(userRecordID: senderRecordID)
            NSLog("[Tally] sendReciprocalShareBack: added sender as participant on my share")
        } catch {
            NSLog("[Tally] sendReciprocalShareBack: addFriendParticipant failed — non-fatal, share has publicPermission=.readOnly so the sender will join via the URL: \(error.localizedDescription)")
        }

        let (myShare, _) = try await personalRepository.makePersonalShare()
        NSLog("[Tally] sendReciprocalShareBack: makePersonalShare share=\(myShare.recordID.recordName) url=\(myShare.url?.absoluteString ?? "nil")")

        // CloudKit can take a beat to populate `.url` on freshly-saved
        // shares. Refetch the share a few times to give it room to
        // settle. If it's still nil after the window, throw so the
        // pending-retry queue picks it up next tick.
        var resolvedShare = myShare
        var urlRetries = 0
        while resolvedShare.url == nil && urlRetries < 4 {
            NSLog("[Tally] sendReciprocalShareBack: share URL not yet populated, retry \(urlRetries + 1)")
            try await Task.sleep(nanoseconds: 500_000_000)
            let refreshed = try await CKClient.shared.privateDB.record(for: resolvedShare.recordID)
            if let s = refreshed as? CKShare {
                resolvedShare = s
            }
            urlRetries += 1
        }
        guard let myShareURL = resolvedShare.url else {
            throw NSError(
                domain: "AppState.sendReciprocalShareBack",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Couldn't get a share URL from CloudKit — will retry."]
            )
        }

        let reciprocal = FriendRequest(
            id: UUID(),
            fromUserRecordName: currentUserID,
            toUserRecordName: senderRecordName,
            shareURL: myShareURL.absoluteString,
            fromDisplayName: profile.displayName,
            fromUsername: profile.username ?? "",
            fromAvatarSymbol: profile.avatarSymbol,
            sentAt: .now,
            isReciprocal: true
        )
        try await friendRequestRepository.send(reciprocal)
        NSLog("[Tally] sendReciprocalShareBack: reciprocal sent id=\(reciprocal.id)")
    }

    /// Walk the pending-reciprocal queue and retry each. Invoked from the
    /// poll task on every tick. Each successful retry removes the entry
    /// from the queue; failures stay queued for the next tick.
    private func retryPendingReciprocals() async {
        guard !pendingReciprocalSenders.isEmpty else { return }
        // Snapshot the set since the iteration body mutates it.
        let toRetry = pendingReciprocalSenders
        for senderRecordName in toRetry {
            do {
                try await sendReciprocalShareBack(to: senderRecordName)
                pendingReciprocalSenders.remove(senderRecordName)
                persistPendingReciprocalSenders()
                NSLog("[Tally] retryPendingReciprocals: completed for \(senderRecordName)")
            } catch {
                NSLog("[Tally] retryPendingReciprocals: still failing for \(senderRecordName): \(error.localizedDescription)")
            }
        }
    }

    private func persistPendingReciprocalSenders() {
        LocalCache.save(Array(pendingReciprocalSenders), forKey: LocalCacheKey.pendingReciprocalSenders)
    }

    /// Poll the public DB for `UnfriendNotification` records addressed to
    /// us. For each one we haven't already processed, add the unfriender
    /// to our locallyUnfriendedIDs (via `dropFriendLocally`) so they
    /// vanish from our friends list. This is the "B receives notification
    /// that A unfriended them" half of the symmetric unfriend flow.
    ///
    /// We can't delete the record from public DB (only the creator can),
    /// so we track processed IDs in a local set so we don't keep
    /// re-applying the same hide every 6s. The sender's outgoing-cleanup
    /// pass eventually deletes the record.
    func processUnfriendNotifications() async {
        guard !currentUserID.isEmpty else { return }
        do {
            let incoming = try await unfriendNotificationRepository.incoming(for: currentUserID)
            for notif in incoming {
                let idStr = notif.id.uuidString
                if processedUnfriendNotificationIDs.contains(idStr) { continue }
                NSLog("[Tally] processUnfriendNotifications: applying unfriend from=\(notif.fromUserRecordName) id=\(idStr)")
                // `dropFriendLocally` adds to locallyUnfriendedIDs, removes
                // their cached habits/goals/completions, and saves to
                // LocalCache. Idempotent if they were already in the set.
                personalStore.dropFriendLocally(userID: notif.fromUserRecordName)

                // ALSO revoke their access to OUR data. The unfriender
                // already cut our access to theirs (their `unfriend` call
                // removed us from their share); we mirror it by removing
                // them from OUR share. Without this, the person who got
                // unfriended would retain latent read access to the
                // unfriender's zone — they'd be hidden in the UI but could
                // still technically sync the data. Safe to call: this
                // operates on OUR OWN share (we're the owner), not the
                // other person's share, so it doesn't hit the iOS 26
                // removeParticipant crash. Best-effort.
                do {
                    let outcome = try await personalRepository.removeFriendParticipant(
                        userRecordID: CKRecord.ID(recordName: notif.fromUserRecordName)
                    )
                    NSLog("[Tally] processUnfriendNotifications: revoke outcome=\(outcome) for \(notif.fromUserRecordName)")
                } catch {
                    NSLog("[Tally] processUnfriendNotifications: revoke failed (non-fatal): \(error.localizedDescription)")
                }
                processedUnfriendNotificationIDs.insert(idStr)
            }
            LocalCache.save(
                Array(processedUnfriendNotificationIDs),
                forKey: LocalCacheKey.processedUnfriendNotificationIDs
            )

            // Outgoing cleanup: delete any UnfriendNotifications we sent
            // that are older than 7 days. The recipient's app polls
            // every 6s when foregrounded; 7 days is a generous window
            // covering "phone off all week," after which the record is
            // safe to drop. We're the creator so we have delete rights.
            let outgoing = try await unfriendNotificationRepository.outgoing(for: currentUserID)
            let weekAgo = Date.now.addingTimeInterval(-7 * 24 * 60 * 60)
            for r in outgoing where r.sentAt < weekAgo {
                try? await unfriendNotificationRepository.delete(r)
            }

            // Refresh so the UI immediately reflects any new unfriends.
            await personalStore.refresh()
        } catch {
            NSLog("[Tally] processUnfriendNotifications: failed: \(error.localizedDescription)")
        }
    }

    /// Hide the request locally. We can't delete the underlying record (only
    /// the sender can), so we remember the ID in LocalCache and filter it out.
    func declineFriendRequest(_ request: FriendRequest) async {
        markRequestDeclined(request)
        await refreshFriendRequests()
    }

    /// Remove a friend on both sides:
    ///   1. Drop them from MY personal CKShare so they lose read access to my
    ///      zone — on their next refresh my data disappears from their friend
    ///      list.
    ///   2. Remove MYSELF from THEIR share so their zone drops out of my
    ///      sharedDB — without this their profile would linger in my friend
    ///      list because CloudKit still considers me a participant on their
    ///      share. Non-owners can self-remove via sharedDB, so this works.
    ///
    /// Step 1 is the trust-relevant half (revokes their access). Step 2 is
    /// the bookkeeping half (clears my own view). Step 2 is best-effort; if
    /// it fails we still want step 1 to stick.
    func unfriend(_ friend: Friend) async throws {
        let recordID = CKRecord.ID(recordName: friend.userID)
        NSLog("[Tally] unfriend: start friend=\(friend.userID)")

        // Clear any stale flag from a previous unfriend attempt.
        lastUnfriendCleanupError = nil

        // Step 1: revoke their access to my zone — the trust-relevant half.
        // A THROW here is a real CloudKit write failure (network): the
        // standard "Couldn't unfriend" alert shows and the friend stays in
        // the list (correct — nothing happened, retry). A returned outcome
        // means no write error, but we must distinguish the cases:
        //   .revoked / .alreadyAbsent → they have no access → finish cleanly.
        //   .refused(reason)          → couldn't revoke, access MAY remain.
        //     Per product decision we PROCEED + FLAG rather than abort: a
        //     corrupt state (e.g. owner-role participant) never self-heals,
        //     so aborting would make this friend permanently un-unfriendable.
        //     We still drop them locally + notify their device, but set
        //     `lastUnfriendCleanupError` so the unrevoked access is visible.
        let revoke = try await personalRepository.removeFriendParticipant(userRecordID: recordID)
        switch revoke {
        case .revoked, .alreadyAbsent:
            NSLog("[Tally] unfriend: step 1 ok (\(revoke)) — friend has no access to my data")
        case .refused(let reason):
            NSLog("[Tally] unfriend: step 1 REFUSED — \(reason)")
            lastUnfriendCleanupError = "Removed them from your side, but couldn't confirm their access to your data was revoked — they may still see your data. (\(reason)) Try unfriending again."
        }

        // Step 2 used to be `leaveFriendShare` (calling
        // CKShare.removeParticipant on the friend's share via
        // sharedDB). That API has been observed raising
        // NSInternalInconsistencyException on iOS 26 under various
        // CloudKit states — an Obj-C exception Swift `try` can't catch,
        // so the app aborts. We've replaced it with a persistent local
        // filter: `dropFriendLocally` marks the friend in
        // `personalStore.locallyUnfriendedIDs` (saved to LocalCache),
        // and `PersonalStore.load` / `.refresh` filter friend zones
        // against that set so the friend stays gone across launches
        // even though their zone technically remains in our sharedDB.
        personalStore.dropFriendLocally(userID: friend.userID)

        // Step 3: tell THEIR app about the unfriend. Without this, their
        // PersonalStore.refresh would still see us in their friends list
        // indefinitely (we revoked their data access in step 1, but the
        // zone reference stays in their sharedDB and they have no signal
        // to drop us). Their app polls UnfriendNotifications via the
        // same 6s loop that polls FriendRequests; when this one arrives
        // they add us to THEIR locallyUnfriendedIDs and we vanish from
        // their friend list — symmetric to the local-filter unfriend we
        // just did.
        //
        // Enqueue the target BEFORE attempting the send (mirrors how
        // acceptFriendRequest enqueues into pendingReciprocalSenders before
        // sendReciprocalShareBack). The entry is removed only on a confirmed
        // successful write; if the send throws, it stays queued and the 6s
        // poll + launch flush retry it until it lands. This closes the gap
        // where a single failed notification left the other person seeing
        // us (and retaining access) forever.
        pendingUnfriendTargets.insert(friend.userID)
        persistPendingUnfriendTargets()
        await flushUnfriendNotification(to: friend.userID)

        await personalStore.refresh()
        await refreshFriendRequests()
        NSLog("[Tally] unfriend: done")
    }

    /// Attempt to send a single UnfriendNotification; dequeue on success.
    /// Shared by `unfriend` (first try) and `retryPendingUnfriendNotifications`
    /// (poll retries) — same role `sendReciprocalShareBack` plays for the
    /// reciprocal queue.
    private func flushUnfriendNotification(to targetUserID: String) async {
        guard !currentUserID.isEmpty else { return }
        do {
            let notification = UnfriendNotification(
                id: UUID(),
                fromUserRecordName: currentUserID,
                toUserRecordName: targetUserID,
                sentAt: .now
            )
            try await unfriendNotificationRepository.send(notification)
            pendingUnfriendTargets.remove(targetUserID)
            persistPendingUnfriendTargets()
            NSLog("[Tally] unfriend: UnfriendNotification sent to=\(targetUserID) id=\(notification.id)")
        } catch {
            NSLog("[Tally] unfriend: UnfriendNotification send failed (queued for retry): \(error.localizedDescription)")
        }
    }

    /// Flush the unfriend-notification retry queue. Called every poll tick
    /// and on launch. Each entry is dequeued inside `flushUnfriendNotification`
    /// only on a confirmed successful write.
    private func retryPendingUnfriendNotifications() async {
        guard !pendingUnfriendTargets.isEmpty else { return }
        // Snapshot before iterating — flushUnfriendNotification mutates the
        // set on success (same approach as retryPendingReciprocals).
        let toRetry = pendingUnfriendTargets
        for targetUserID in toRetry {
            await flushUnfriendNotification(to: targetUserID)
        }
    }

    private func persistPendingUnfriendTargets() {
        LocalCache.save(Array(pendingUnfriendTargets), forKey: LocalCacheKey.pendingUnfriendTargets)
    }

    /// Surfaced when step 2 of unfriend (leaving the friend's share)
    /// failed but step 1 succeeded — the trust-relevant half is done,
    /// the cleanup half wasn't. Read by views that want to flag this to
    /// the user without blocking the unfriend flow.
    var lastUnfriendCleanupError: String?

    /// Surfaced when an unfriend was kicked off from MemberDetailView's
    /// "dismiss-then-unfriend" path and the whole operation failed.
    /// Since the view was already popped, errors can't be shown via the
    /// usual in-view alert; FriendsView watches this and surfaces a
    /// banner on its next render.
    var lastUnfriendError: String?

    /// Delete the user's account: wipe every CloudKit record + zone we
    /// own, release the username claim, clear local cache, and reset
    /// onboarding so the next launch starts at ProfileSetupView.
    ///
    /// Each step is best-effort. If one step fails (network, quota,
    /// permission) we log and keep going — we'd rather end up partially
    /// cleaned up than half-stuck with no way to recover. After all
    /// steps the local state is fully reset regardless.
    ///
    /// Things we DON'T delete:
    ///   - Shared zones we're a participant on (friends' personal zones,
    ///     joined circle zones). Those belong to other users — we can't
    ///     delete them, and trying to `share.removeParticipant(self)` on
    ///     iOS 26 has been known to raise NSExceptions Swift can't catch
    ///     (see the unfriend-crash history). Their apps will drop us
    ///     naturally when their next refresh fails to find our zone.
    ///   - Incoming public-DB FriendRequest / GroupInvite records
    ///     written by other users. Those aren't ours to delete.
    func deleteAccount() async {
        NSLog("[Tally] deleteAccount: start userID=\(currentUserID)")
        let userID = currentUserID
        let username = ownCloudProfile?.username

        // 1. Public DB — release the global username claim so the name
        //    is freed up for someone else to claim.
        if let username, !username.isEmpty {
            do {
                try await usernameRepository.release(username)
                NSLog("[Tally] deleteAccount: released username \(username)")
            } catch {
                NSLog("[Tally] deleteAccount: release username failed (non-fatal): \(error.localizedDescription)")
            }
        }

        // 2. Public DB — delete outgoing friend requests + group invites.
        //    These were created by us; the public-DB record-level
        //    permission lets the creator delete them.
        if !userID.isEmpty {
            do {
                let frs = try await friendRequestRepository.outgoing(for: userID)
                for r in frs {
                    try? await friendRequestRepository.delete(r)
                }
                NSLog("[Tally] deleteAccount: deleted \(frs.count) outgoing FriendRequests")
            } catch {
                NSLog("[Tally] deleteAccount: outgoing FR cleanup failed (non-fatal): \(error.localizedDescription)")
            }
            do {
                let invs = try await groupInviteRepository.outgoing(for: userID)
                for inv in invs {
                    try? await groupInviteRepository.delete(inv)
                }
                NSLog("[Tally] deleteAccount: deleted \(invs.count) outgoing GroupInvites")
            } catch {
                NSLog("[Tally] deleteAccount: outgoing GI cleanup failed (non-fatal): \(error.localizedDescription)")
            }
            do {
                let notifs = try await unfriendNotificationRepository.outgoing(for: userID)
                for notif in notifs {
                    try? await unfriendNotificationRepository.delete(notif)
                }
                NSLog("[Tally] deleteAccount: deleted \(notifs.count) outgoing UnfriendNotifications")
            } catch {
                NSLog("[Tally] deleteAccount: outgoing UN cleanup failed (non-fatal): \(error.localizedDescription)")
            }
        }

        // 2.5. Notify every current friend that we're leaving. Reuses the
        //      existing UnfriendNotification path: their app processes it
        //      to drop us from their local friends list/leaderboard within
        //      a poll cycle instead of waiting for them to refresh and
        //      discover our shared zone is gone. Best-effort — failures
        //      just mean their app will fall back to implicit detection
        //      on next refresh.
        let friendIDsForNotify = personalStore.friends.map { $0.userID }
        if !userID.isEmpty, !friendIDsForNotify.isEmpty {
            for friendID in friendIDsForNotify {
                do {
                    let notification = UnfriendNotification(
                        id: UUID(),
                        fromUserRecordName: userID,
                        toUserRecordName: friendID,
                        sentAt: .now
                    )
                    try await unfriendNotificationRepository.send(notification)
                } catch {
                    NSLog("[Tally] deleteAccount: notify friend \(friendID) failed (non-fatal): \(error.localizedDescription)")
                }
            }
            NSLog("[Tally] deleteAccount: notified \(friendIDsForNotify.count) friends")
        }

        // 2.6. Leave every joined-but-not-owned circle. `leaveCircle`
        //      deletes our own CircleMember record from the owner's zone
        //      AND drops us from the CKShare in one server op. Without
        //      this, our member record would tombstone-leak: the group
        //      owner's app would keep showing us as a former member
        //      with our (now-deleted) display name. Best-effort per
        //      circle.
        for circle in joinedCircles {
            do {
                try await circleRepository.leaveCircle(circle)
                NSLog("[Tally] deleteAccount: left joined circle \(circle.id)")
            } catch {
                NSLog("[Tally] deleteAccount: leave circle \(circle.id) failed (non-fatal): \(error.localizedDescription)")
            }
        }

        // 3. Private DB — delete every owned Circle zone. Zone deletion
        //    cascades to the root, members, messages, and the CKShare in
        //    one server-side op.
        do {
            let zones = try await CKClient.shared.ownedCircleZones()
            for zone in zones {
                try? await CKClient.shared.deletePrivateZone(named: zone.zoneID.zoneName)
            }
            NSLog("[Tally] deleteAccount: deleted \(zones.count) owned circle zones")
        } catch {
            NSLog("[Tally] deleteAccount: circle-zone cleanup failed (non-fatal): \(error.localizedDescription)")
        }

        // 4. Private DB — delete the personal data zones (shared + private).
        //    These cascade to habits, completions, goals, and our personal
        //    CKShare. Friends' sharedDB will lose our zone on their next
        //    refresh.
        try? await CKClient.shared.deletePrivateZone(named: CloudKitPersonalRepository.zoneName)
        try? await CKClient.shared.deletePrivateZone(named: CloudKitPersonalRepository.privateZoneName)
        NSLog("[Tally] deleteAccount: deleted personal zones")

        // 5. Private DB — delete the singleton UserProfile record in the
        //    default zone. Not in a custom zone so it doesn't fall under
        //    the cascading zone deletes above.
        let profileID = CKRecord.ID(recordName: CloudKitProfileRepository.ownProfileRecordName)
        _ = try? await CKClient.shared.privateDB.deleteRecord(withID: profileID)
        NSLog("[Tally] deleteAccount: deleted UserProfile record")

        // 6. Snapshot the post-resignup hide-lists BEFORE clearAll.
        //    `deleteAccount` is most often "delete then immediately
        //    re-onboard with the same iCloud account" — same iCloud means
        //    same `userRecordID`, so old incoming FriendRequests / old
        //    GroupInvites the user can't delete (not the creator) and old
        //    friends' shared zones in sharedDB will all re-appear unless
        //    we explicitly remember to hide them. Public-DB records we
        //    DID create were deleted in steps 2; this handles everything
        //    else.
        let allDeclinedRequests = declinedRequestIDs
            .union(incomingFriendRequests.map { $0.id.uuidString })
        let allDeclinedInvites = declinedGroupInviteIDs
            .union(incomingGroupInvites.map { $0.id.uuidString })
        let allLocallyUnfriended = Set(personalStore.friends.map { $0.userID })
        NSLog("[Tally] deleteAccount: snapshot hide-lists requests=\(allDeclinedRequests.count) invites=\(allDeclinedInvites.count) friends=\(allLocallyUnfriended.count)")

        // 7. Local cleanup — wipe every cached row, then re-save just the
        //    cross-account hide-lists from the snapshot above so a same-
        //    iCloud re-signup starts clean (no ghost friends, no ghost
        //    pending requests).
        LocalCache.clearAll()
        LocalCache.save(Array(allDeclinedRequests),
                        forKey: LocalCacheKey.declinedFriendRequestIDs)
        LocalCache.save(Array(allDeclinedInvites),
                        forKey: LocalCacheKey.declinedGroupInviteIDs)
        LocalCache.save(Array(allLocallyUnfriended),
                        forKey: LocalCacheKey.locallyUnfriendedIDs)

        // 8. Theme — wipe the user's color preference too. Previous
        //    behavior kept it as "UI preference"; user feedback was that
        //    a delete-account should mean delete-everything. Set in-memory
        //    to defaults (so the running app instantly reverts to Classic),
        //    THEN remove the persisted keys (the didSet on ThemeManager
        //    re-wrote them when we set above, so the removeObject is the
        //    actual erase).
        ThemeManager.shared.current = .classic
        ThemeManager.shared.customAccentHex = ThemeManager.defaultCustomAccentHex
        UserDefaults.standard.removeObject(forKey: ThemeManager.storageKey)
        UserDefaults.standard.removeObject(forKey: ThemeManager.customAccentKey)
        UserDefaults.standard.removeObject(forKey: ThemeManager.hasPickedThemeKey)
        theme = .classic

        // 9. In-memory store wipe — habits, completions, goals, friends,
        //    change tokens, circle members, messages, optimistic-send
        //    queues. `@Observable` so the UI re-renders blank immediately.
        personalStore.reset()
        circleStore.reset()

        // 10. Reset every AppState field so the UI is fully clean and
        //     RootView lands on ProfileSetupView for a fresh onboarding.
        ownCloudProfile = nil
        currentUserID = ""
        ownedCircles = []
        joinedCircles = []
        recentlyCreatedCircleIDs = []
        incomingFriendRequests = []
        incomingGroupInvites = []
        declinedRequestIDs = []
        declinedGroupInviteIDs = []
        outgoingRequestTargetIDs = []
        pendingReciprocalSenders = []
        processedUnfriendNotificationIDs = []
        pendingUnfriendTargets = []
        pendingGroupInvites = []
        lastCloudShareError = nil
        lastFriendRequestError = nil
        lastGroupInviteError = nil
        isFirstRunOnboarding = true
        // Account-delete resets the persisted step too so the user lands at
        // the start of the new paywalled flow on their next sign-in.
        LocalCache.remove(forKey: LocalCacheKey.onboardingStep)
        onboardingState = .displayNameEntry
        NSLog("[Tally] deleteAccount: done")
    }

    private func markRequestDeclined(_ request: FriendRequest) {
        declinedRequestIDs.insert(request.id.uuidString)
        LocalCache.save(Array(declinedRequestIDs), forKey: LocalCacheKey.declinedFriendRequestIDs)
    }

    /// Poll the public DB for requests addressed to me. Auto-processes
    /// reciprocal requests (silently accept the sender's share so the
    /// friend graph completes), then publishes the remaining fresh requests
    /// to `incomingFriendRequests` for the inbox UI. Also runs the outgoing
    /// cleanup: any request I sent where the target is now my friend is
    /// deleted from the public DB so it doesn't pile up forever.
    func refreshFriendRequests() async {
        guard !currentUserID.isEmpty else { return }
        // Re-entrancy guard: prevent the 6s poll and a same-instant manual
        // refresh from both racing the auto-accept loop on the same
        // reciprocal record. Without this, two concurrent passes can each
        // try to acceptShareMetadata on the same URL.
        guard !isRefreshingFriendRequests else { return }
        isRefreshingFriendRequests = true
        defer { isRefreshingFriendRequests = false }
        do {
            let incoming = try await friendRequestRepository.incoming(for: currentUserID)
            // Clear any stale error message from a previous failed refresh.
            lastFriendRequestError = nil
            NSLog("[Tally] refreshFriendRequests: incoming=\(incoming.count) for userID=\(currentUserID)")

            // Auto-process reciprocal requests first — these arrive when a
            // friend accepted MY earlier request. We need to accept their
            // share silently so we see their data too.
            //
            // A reciprocal is only hidden locally when the accept SUCCEEDS.
            // If the accept throws (network blip, transient CloudKit error),
            // we leave the record alone so the next refresh retries it —
            // otherwise a single hiccup would permanently strand the sender
            // without the recipient's data.
            for r in incoming where r.isReciprocal {
                NSLog("[Tally] reciprocal: processing from=\(r.fromUserRecordName) id=\(r.id)")
                guard let url = URL(string: r.shareURL) else {
                    NSLog("[Tally] reciprocal: malformed URL — hiding")
                    markRequestDeclined(r)
                    continue
                }
                do {
                    let metadata = try await CKClient.shared.container.shareMetadata(for: url)
                    NSLog("[Tally] reciprocal: fetched metadata")
                    try await acceptShareMetadata(metadata)
                    NSLog("[Tally] reciprocal: acceptShareMetadata ok")
                    // Re-engagement: a reciprocal from this user means
                    // we sent them a request and they accepted it back.
                    // If they were previously in our local-unfriend filter,
                    // clear them now so personalStore.refresh below picks
                    // their zone back into the friend graph.
                    personalStore.clearLocalUnfriend(userID: r.fromUserRecordName)
                    // Force a full re-fetch of this friend's zone on the
                    // next refresh. Without this, if we'd previously
                    // accepted-then-lost this share, a stale change token
                    // could cause us to ask CloudKit for "changes since X"
                    // and miss the initial PersonalRoot record we need to
                    // turn the zone into a Friend row.
                    personalStore.resetFriendZoneToken(ownerName: r.fromUserRecordName)
                    // CloudKit eventual consistency: the friend's zone may
                    // not appear in our sharedDB immediately after
                    // acceptShareMetadata returns. We've seen real-world
                    // gaps north of 15s. Retry every 3s for ~30s before
                    // giving up and leaving the reciprocal record around
                    // for the next 6s poll to retry.
                    var visible = false
                    for attempt in 0..<10 {
                        await personalStore.refresh()
                        if personalStore.friends.contains(where: { $0.userID == r.fromUserRecordName }) {
                            NSLog("[Tally] reciprocal: friend visible after attempt \(attempt + 1)")
                            visible = true
                            break
                        }
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                    }
                    if visible {
                        markRequestDeclined(r)
                    } else {
                        NSLog("[Tally] reciprocal: friend never appeared after 10 retries — leaving record for next refresh")
                        // Surface to UI so the user sees the app is trying
                        // (and trying again). Previously this was silent —
                        // user just saw "no friend in list" with no signal.
                        lastFriendRequestError = "Connecting to your new friend… If this persists, try restarting the app."
                    }
                } catch {
                    NSLog("[Tally] reciprocal: auto-accept failed (will retry next refresh): \(error.localizedDescription)")
                    // Surface to UI so a persistent failure isn't invisible.
                    lastFriendRequestError = "Couldn't complete friend connection: \(error.localizedDescription)"
                }
            }

            let friendIDs = Set(personalStore.friends.map(\.userID))
            incomingFriendRequests = incoming.filter { r in
                !r.isReciprocal
                    && !declinedRequestIDs.contains(r.id.uuidString)
                    && !friendIDs.contains(r.fromUserRecordName)
            }

            // Cleanup pass: delete any of MY outgoing requests where the
            // target is now a confirmed friend — the request has served
            // its purpose and only pollutes the public DB otherwise.
            let outgoing = try await friendRequestRepository.outgoing(for: currentUserID)
            for r in outgoing where friendIDs.contains(r.toUserRecordName) {
                try? await friendRequestRepository.delete(r)
            }
            // Publish remaining outgoing-pending targets so FriendSearchView
            // can show "Request pending" instead of "Send" for people I've
            // already messaged. Filter to only NON-reciprocal records I
            // created — reciprocals are an internal mechanic, not a
            // user-visible "request."
            outgoingRequestTargetIDs = Set(
                outgoing
                    .filter { !$0.isReciprocal && !friendIDs.contains($0.toUserRecordName) }
                    .map(\.toUserRecordName)
            )
            // Refresh friends so an accepted reciprocal shows up in the list.
            await personalStore.refresh()
        } catch {
            NSLog("[Tally] refreshFriendRequests failed: \(error.localizedDescription)")
            lastFriendRequestError = error.localizedDescription
        }
    }

    // MARK: - Group invites

    /// Send a group invite to `userRecordName`, inviting them to `circle`.
    /// Writes a `GroupInvite` to the public DB *and* adds them as a CKShare
    /// participant — same belt-and-suspenders pattern as friend requests:
    /// the participant entry establishes their identity on the share; the
    /// public-DB record is the discovery mechanism that actually reaches
    /// them on TestFlight without relying on iCloud system notifications.
    ///
    /// Owner-only. Non-owners can't modify the share's participant list, so
    /// CloudKit will reject the underlying call from anyone but the owner.
    func sendGroupInvite(to userRecordName: String, circle: TallyCircle) async throws {
        guard !currentUserID.isEmpty else {
            throw NSError(
                domain: "AppState.sendGroupInvite",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Not signed into iCloud."]
            )
        }
        guard let profile = ownCloudProfile else {
            throw NSError(
                domain: "AppState.sendGroupInvite",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Set up your profile before inviting friends."]
            )
        }
        guard circle.ownerID == currentUserID else {
            throw NSError(
                domain: "AppState.sendGroupInvite",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Only the group's creator can invite new members."]
            )
        }
        guard userRecordName != currentUserID else {
            throw NSError(
                domain: "AppState.sendGroupInvite",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "You can't invite yourself."]
            )
        }

        // Enqueue BEFORE the fallible work (makeShare / send), mirroring how
        // acceptFriendRequest enqueues into pendingReciprocalSenders. Removed
        // only on a confirmed successful invite write below; if anything
        // throws in between, the entry stays queued and the 6s poll + launch
        // flush retry it. Centralizing here means all callers (DM via
        // openOrCreateDM, the group fan-out in CreateCircleView, and
        // addMemberToCircle) get retry coverage without changing the views.
        let inviteKey = Self.groupInviteKey(circleID: circle.id, userID: userRecordName)
        pendingGroupInvites.insert(inviteKey)
        persistPendingGroupInvites()

        // Mint/fetch the share so we have a URL for the invite.
        let (share, _) = try await circleRepository.makeShare(for: circle)
        guard let shareURL = share.url else {
            throw NSError(
                domain: "AppState.sendGroupInvite",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Couldn't get an invite link — try again in a moment."]
            )
        }

        // Add as participant. Best-effort — the URL + publicPermission also
        // grants access on accept, so a hiccup here doesn't sink the invite.
        do {
            try await circleRepository.addMember(userRecordName: userRecordName, to: circle)
        } catch {
            NSLog("[Tally] sendGroupInvite: addMember failed: \(error.localizedDescription)")
        }

        let invite = GroupInvite(
            id: UUID(),
            fromUserRecordName: currentUserID,
            toUserRecordName: userRecordName,
            circleID: circle.id,
            circleName: circle.name,
            circleKind: circle.kind,
            dmPeerID: circle.dmPeerID,
            shareURL: shareURL.absoluteString,
            fromDisplayName: profile.displayName,
            fromUsername: profile.username ?? "",
            fromAvatarSymbol: profile.avatarSymbol,
            sentAt: .now
        )
        try await groupInviteRepository.send(invite)
        // Confirmed write — dequeue.
        pendingGroupInvites.remove(inviteKey)
        persistPendingGroupInvites()
        // Refresh in case we want to surface our own outgoing in the future,
        // or to surface a clear error banner if the schema isn't ready.
        await refreshGroupInvites()
    }

    /// Composite retry-queue key for a group/DM invite. `|` can't appear in
    /// a UUID or a CloudKit user record name, so it's a safe separator.
    private static func groupInviteKey(circleID: UUID, userID: String) -> String {
        "\(circleID.uuidString)|\(userID)"
    }

    private func persistPendingGroupInvites() {
        LocalCache.save(Array(pendingGroupInvites), forKey: LocalCacheKey.pendingGroupInvites)
    }

    /// Flush the group/DM-invite retry queue. Called every poll tick + on
    /// launch. Each key is `"circleID|userID"`; the circle is resolved from
    /// `allCircles`. `sendGroupInvite` itself dequeues on success — so a
    /// still-failing invite simply stays for the next tick. Entries whose
    /// circle no longer exists (deleted) or whose key is malformed are
    /// dropped so the queue can't grow unbounded.
    private func retryPendingGroupInvites() async {
        guard !pendingGroupInvites.isEmpty else { return }
        // Snapshot before iterating — sendGroupInvite mutates the set on
        // success (same approach as retryPendingReciprocals).
        let toRetry = pendingGroupInvites
        for key in toRetry {
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, let circleID = UUID(uuidString: parts[0]) else {
                pendingGroupInvites.remove(key)
                persistPendingGroupInvites()
                continue
            }
            let userID = parts[1]
            guard let circle = allCircles.first(where: { $0.id == circleID }) else {
                // Circle not currently in allCircles. Could be a genuine
                // delete OR just a transient empty list (loadCircles failed
                // this cycle). We do NOT drop here — dropping on a transient
                // miss would silently lose a valid pending invite. Skip and
                // leave it queued; it retries next tick once allCircles is
                // populated. (Mirrors pendingReciprocalSenders, which only
                // ever removes on success.)
                NSLog("[Tally] retryPendingGroupInvites: circle \(circleID) not loaded — skipping this tick")
                continue
            }
            // sendGroupInvite re-enqueues (no-op, already present) and
            // dequeues on success.
            try? await sendGroupInvite(to: userID, circle: circle)
        }
    }

    /// Recipient accepts a group invite. Order matters: the share-accept is
    /// the load-bearing step (it makes us a participant), so the circle must
    /// surface the instant that succeeds — the member-record write is
    /// secondary and must never block the circle from appearing.
    func acceptGroupInvite(_ invite: GroupInvite) async throws {
        guard let shareURL = URL(string: invite.shareURL) else {
            throw NSError(
                domain: "AppState.acceptGroupInvite",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid invite link."]
            )
        }
        let container = CKClient.shared.container
        let metadata = try await container.shareMetadata(for: shareURL)

        // 1. JOIN. Once this succeeds we're a participant on the circle zone.
        //    A throw here leaves the invite un-declined so it retries — we
        //    haven't actually joined, so re-surfacing it is correct.
        try await acceptShareMetadata(metadata)

        // 2. Confirmed join — hide the invite from the inbox now (we can't
        //    delete the record; the owner's cleanup pass removes it once
        //    they see us as a member). Marking declined is gated on the
        //    JOIN succeeding, nothing later.
        markGroupInviteDeclined(invite)

        // 3. Surface the circle immediately. Previously `recordOwnMembership`
        //    ran BEFORE this and threw "Joined Circle zone not found" on
        //    post-join eventual consistency, skipping `loadCircles` entirely
        //    — so a freshly-joined DM/group wouldn't appear until a later
        //    poll. Now the circle shows the moment we're a participant.
        await loadCircles()

        // 4. Write our member row so the OWNER sees us in their member list.
        //    Best-effort: it commonly fails on the first try right after
        //    joining (the zone isn't yet listed in sharedDB), so we retry a
        //    few times — but it NEVER throws out of this function and NEVER
        //    blocks the circle from appearing. If it ultimately fails, we
        //    still have the circle + can message; only the owner's member
        //    list is briefly incomplete.
        let profile = ownCloudProfile
        for attempt in 0..<3 {
            do {
                try await circleRepository.recordOwnMembership(
                    circleID: invite.circleID,
                    displayName: profile?.displayName ?? "Me",
                    avatarSymbol: profile?.avatarSymbol ?? "leaf"
                )
                break
            } catch {
                NSLog("[Tally] acceptGroupInvite: recordOwnMembership attempt \(attempt + 1) failed (non-fatal): \(error.localizedDescription)")
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }

        await refreshGroupInvites()
    }

    /// Hide the invite locally without accepting it.
    func declineGroupInvite(_ invite: GroupInvite) async {
        markGroupInviteDeclined(invite)
        await refreshGroupInvites()
    }

    private func markGroupInviteDeclined(_ invite: GroupInvite) {
        declinedGroupInviteIDs.insert(invite.id.uuidString)
        LocalCache.save(Array(declinedGroupInviteIDs), forKey: LocalCacheKey.declinedGroupInviteIDs)
    }

    /// Poll the public DB for incoming group invites and surface fresh ones
    /// in `incomingGroupInvites`. Also runs the owner-side cleanup: any
    /// outgoing invite where the recipient now appears in the Circle's
    /// member list (or any Circle the recipient is in that I own) is no
    /// longer pending and gets removed from the public DB.
    func refreshGroupInvites() async {
        guard !currentUserID.isEmpty else { return }
        do {
            let incoming = try await groupInviteRepository.incoming(for: currentUserID)
            lastGroupInviteError = nil
            NSLog("[Tally] refreshGroupInvites: incoming=\(incoming.count) for userID=\(currentUserID)")

            // Auto-accept DM invites from confirmed friends. A DM is a
            // low-friction action between two people who already
            // mutually consented to friending — making them tap Accept
            // every time someone DMs them is just friction. Group
            // invites still go to the inbox so the user can decide.
            let friendIDs = Set(personalStore.friends.map(\.userID))
            for inv in incoming where inv.circleKind == .dm
                && friendIDs.contains(inv.fromUserRecordName)
                && !declinedGroupInviteIDs.contains(inv.id.uuidString) {
                NSLog("[Tally] refreshGroupInvites: auto-accepting DM from friend=\(inv.fromUserRecordName) circle=\(inv.circleID)")
                do {
                    try await acceptGroupInvite(inv)
                } catch {
                    NSLog("[Tally] refreshGroupInvites: DM auto-accept failed (will retry): \(error.localizedDescription)")
                }
            }

            // Surface invites that aren't declined and don't reference a
            // Circle I'm already in. Joined circles always include accepted
            // ones, so once the user accepts, the inbox quietly empties.
            // Auto-accepted DMs (above) just got declined-locally inside
            // acceptGroupInvite, so they fall out of this filter too.
            let myCircleIDs = Set(allCircles.map(\.id))
            incomingGroupInvites = incoming.filter { inv in
                !declinedGroupInviteIDs.contains(inv.id.uuidString)
                    && !myCircleIDs.contains(inv.circleID)
            }

            // Cleanup outgoing invites whose recipient is now a member.
            // We only have membership for circles we own (members live in
            // our private DB) and circles we've joined. For circles I own,
            // I can fetch members directly to confirm acceptance.
            let outgoing = try await groupInviteRepository.outgoing(for: currentUserID)
            for inv in outgoing {
                if let owned = ownedCircles.first(where: { $0.id == inv.circleID }) {
                    if let members = try? await circleRepository.members(of: owned),
                       members.contains(where: { $0.userID == inv.toUserRecordName }) {
                        try? await groupInviteRepository.delete(inv)
                    }
                }
            }
        } catch {
            NSLog("[Tally] refreshGroupInvites failed: \(error.localizedDescription)")
            lastGroupInviteError = error.localizedDescription
        }
    }

    /// Accept a CKShare.Metadata via CKAcceptSharesOperation. Used by both the
    /// in-app friend-request accept and the auto-reciprocal pass.
    private func acceptShareMetadata(_ metadata: CKShare.Metadata) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let op = CKAcceptSharesOperation(shareMetadatas: [metadata])
            op.acceptSharesResultBlock = { result in
                switch result {
                case .success:           continuation.resume(returning: ())
                case .failure(let err):  continuation.resume(throwing: err)
                }
            }
            CKClient.shared.container.add(op)
        }
    }

    /// Switch the active theme. Local-only — no CloudKit round-trip.
    /// Updates `ThemeManager` (the source of truth for `Color.tallyAccent`
    /// and friends) and mirrors the value onto our own observed `theme`
    /// property so SwiftUI re-renders.
    func setTheme(_ theme: TallyTheme) {
        self.theme = theme
        ThemeManager.shared.current = theme
    }

    /// Called from `HabitsSetupView`. Persists each non-empty title as a habit in
    /// the active Circle, then routes to goals setup.
    func saveInitialHabits(_ titles: [String]) {
        for title in titles {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            personalStore.addHabit(title: trimmed, for: currentUserID)
        }
        onboardingState = .enteredMainApp  // legacy; new flow uses completeFirstHabitEntry
    }

    /// Called from `GoalsSetupView`. Persists each non-empty title as a
    /// `.day`-period goal dated to today, so the entries land in the
    /// dashboard's "TO DO TODAY" section the moment onboarding finishes.
    func saveInitialGoals(_ titles: [String]) {
        let todayStart = GoalPeriod.day.startDate(for: .now)
        for title in titles {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            personalStore.addGoal(
                title: trimmed,
                for: currentUserID,
                period: .day,
                periodStart: todayStart
            )
        }
        isFirstRunOnboarding = false
        LocalCache.save(true, forKey: LocalCacheKey.hasOnboarded)
        onboardingState = .enteredMainApp  // legacy; new flow uses completeFirstGoalEntry
    }

    // MARK: - Circles (CloudKit)

    /// Fetch the user's owned + joined Circles from CloudKit. Best-effort —
    /// failures surface in `circleActionError` but don't block the app.
    func loadCircles() async {
        do {
            async let owned = circleRepository.ownedCircles()
            async let joined = circleRepository.joinedCircles()
            let serverOwned = try await owned
            let serverJoined = try await joined

            let serverIDs = Set((serverOwned + serverJoined).map(\.id))
            // The server has surfaced these — they no longer need optimistic
            // preservation.
            recentlyCreatedCircleIDs.subtract(serverIDs)
            // Keep any circle we created this session that the server's
            // zone listing hasn't caught up to yet, so it doesn't disappear
            // from the UI between create and propagation.
            let optimistic = ownedCircles.filter {
                recentlyCreatedCircleIDs.contains($0.id) && !serverIDs.contains($0.id)
            }
            self.ownedCircles = serverOwned + optimistic
            self.joinedCircles = serverJoined
        } catch {
            circleActionError = error.localizedDescription
        }
    }

    /// Record a freshly-created circle in `ownedCircles` + the optimistic-keep
    /// set so it shows immediately and survives the next `loadCircles` even
    /// if the server zone listing is still catching up.
    private func optimisticallyAdd(_ circle: TallyCircle) {
        recentlyCreatedCircleIDs.insert(circle.id)
        if !ownedCircles.contains(where: { $0.id == circle.id }) {
            ownedCircles.append(circle)
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
            ownerAvatarSymbol: profile?.avatarSymbol ?? "leaf",
            kind: .group,
            dmPeerID: nil
        )
        optimisticallyAdd(circle)
        await loadCircles()
        if let active = activeCircle {
            await circleStore.activate(active, currentUserID: currentUserID)
        }
        return circle
    }

    /// Find an existing 1:1 DM Circle with `friend`, or create one. Used by the
    /// "Message" button on a friend's profile so DMs are one tap away without
    /// the user having to create a Group manually.
    ///
    /// Lookup matches a `.dm` Circle where either:
    ///   • I own it and `dmPeerID == friend.userID`, or
    ///   • The friend owns it and `dmPeerID == currentUserID`.
    ///
    /// When creating a new DM we name it after the peer for cache friendliness
    /// (the chat view also re-derives the title from the live friend record at
    /// render time, so renames stay current). The other party gets added as a
    /// CKShare participant through the same `addMemberToCircle` path Groups
    /// use; once Commit 2 lands, that path will switch to the public-DB
    /// GroupInvite flow so DM invitations actually reach the peer.
    @discardableResult
    func openOrCreateDM(with friend: Friend) async throws -> TallyCircle {
        // 1. Look for an existing DM, on either side.
        if let existing = allCircles.first(where: { circle in
            circle.kind == .dm && circle.dmPeer(forViewer: currentUserID) == friend.userID
        }) {
            return existing
        }

        // 2. Create a fresh DM Circle.
        let profile = ownCloudProfile
        let circle = try await circleRepository.createCircle(
            name: friend.displayName,
            emoji: nil,
            ownerDisplayName: profile?.displayName ?? "Me",
            ownerAvatarSymbol: profile?.avatarSymbol ?? "leaf",
            kind: .dm,
            dmPeerID: friend.userID
        )
        // Show the DM in our own Messages list immediately — don't wait for
        // the server zone listing to catch up (which dropped freshly-created
        // DMs from the list, part of the "doesn't show up on my tally" bug).
        optimisticallyAdd(circle)

        // 3. Invite the peer via the public-DB GroupInvite flow so they
        // actually see the invitation on their device (the bare CKShare
        // participant-add doesn't reliably trigger an iCloud notification
        // on TestFlight, which is what motivated this rewrite).
        do {
            try await sendGroupInvite(to: friend.userID, circle: circle)
        } catch {
            NSLog("[Tally] openOrCreateDM: sendGroupInvite failed: \(error.localizedDescription)")
        }

        await loadCircles()
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
                // The legacy `.needsCircleSetup` step is gone — incoming circle
                // shares accepted during onboarding just append to the circle
                // list; the user keeps progressing through the new flow.
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
        await refreshFriendRequests()
        await refreshGroupInvites()
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

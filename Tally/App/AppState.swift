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
    let friendRequestRepository: any FriendRequestRepository
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

    /// Pending incoming friend requests addressed to me. Populated by
    /// `refreshFriendRequests()` on launch and scene-foreground. Reciprocal
    /// requests (auto-accepted) are processed and removed from this list
    /// before it's published, so the UI only ever shows fresh ones the user
    /// needs to act on.
    var incomingFriendRequests: [FriendRequest] = []

    /// Local-only set of declined request IDs. Since recipients can't delete
    /// records they didn't create, decline = hide in our UI. Persisted via
    /// LocalCache so the request stays hidden across launches.
    private var declinedRequestIDs: Set<String> = []

    /// Last error from the public-DB friend-request refresh, surfaced as a
    /// banner so we don't fly blind when CloudKit query-index config is wrong.
    /// Cleared on the next successful refresh.
    var lastFriendRequestError: String?

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
        friendRequestRepository: any FriendRequestRepository = CloudKitFriendRequestRepository(),
        shareCoordinator: ShareCoordinator = ShareCoordinator(),
        circleStore: CircleStore? = nil,
        personalStore: PersonalStore? = nil
    ) {
        self.profileRepository = profileRepository
        self.circleRepository = circleRepository
        self.personalRepository = personalRepository
        self.usernameRepository = usernameRepository
        self.friendRequestRepository = friendRequestRepository
        self.shareCoordinator = shareCoordinator
        self.circleStore = circleStore ?? CircleStore()
        self.personalStore = personalStore ?? PersonalStore(repository: personalRepository)
        self.declinedRequestIDs = Set(
            LocalCache.load([String].self, forKey: LocalCacheKey.declinedFriendRequestIDs) ?? []
        )

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
                    await refreshFriendRequests()
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

    /// Rename a Group. Any participant can do this — CKShare grants .readWrite
    /// on the root record. Reloads the Circle list so the header updates.
    func renameCircle(_ circle: TallyCircle, to newName: String) async throws {
        _ = try await circleRepository.rename(circle, to: newName)
        await loadCircles()
    }

    /// Owner-only: add a known user (resolved via username search) to the
    /// active Group. Throws if non-owner attempts — CloudKit rejects the
    /// share modification at the boundary.
    func addMemberToCircle(_ circle: TallyCircle, userRecordName: String) async throws {
        try await circleRepository.addMember(userRecordName: userRecordName, to: circle)
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

    /// Send a friend request to a specific user. Writes a FriendRequest record
    /// to CloudKit's public DB so the recipient's app can pick it up reliably —
    /// the prior design relied on iCloud system notifications firing when a
    /// participant was added to a CKShare, which doesn't actually fire across
    /// all account / iOS / TestFlight combinations and left requests invisible.
    /// The recipient sees it in their in-app inbox; on Accept their app fetches
    /// our personal share URL and accepts programmatically.
    func sendFriendRequest(to userRecordName: String) async throws {
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
        // Mint (or fetch) my personal share so the recipient has a URL to accept.
        let (share, _) = try await personalRepository.makePersonalShare()
        guard let shareURL = share.url else {
            throw NSError(
                domain: "AppState.sendFriendRequest",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Couldn't get a share URL — try again in a moment."]
            )
        }

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

        let senderRecordID = CKRecord.ID(recordName: request.fromUserRecordName)
        // Reciprocally add the sender to OUR personal share. This works because
        // it's our own share — we own it — so CloudKit allows the modification.
        try? await personalRepository.addFriendParticipant(userRecordID: senderRecordID)

        // Tell the sender's app to silently auto-accept our share too, since
        // iCloud's automatic notification on participant-add isn't reliable.
        if let profile = ownCloudProfile {
            let (myShare, _) = try await personalRepository.makePersonalShare()
            if let myShareURL = myShare.url {
                let reciprocal = FriendRequest(
                    id: UUID(),
                    fromUserRecordName: currentUserID,
                    toUserRecordName: request.fromUserRecordName,
                    shareURL: myShareURL.absoluteString,
                    fromDisplayName: profile.displayName,
                    fromUsername: profile.username ?? "",
                    fromAvatarSymbol: profile.avatarSymbol,
                    sentAt: .now,
                    isReciprocal: true
                )
                try? await friendRequestRepository.send(reciprocal)
            }
        }

        // The recipient can't delete the sender's original request (public-DB
        // security blocks non-creator writes). The sender's cleanup pass will
        // remove it when they detect us as a friend. Hide it locally so the
        // inbox UI reflects the action immediately.
        markRequestDeclined(request)
        await personalStore.refresh()
        await refreshFriendRequests()
    }

    /// Hide the request locally. We can't delete the underlying record (only
    /// the sender can), so we remember the ID in LocalCache and filter it out.
    func declineFriendRequest(_ request: FriendRequest) async {
        markRequestDeclined(request)
        await refreshFriendRequests()
    }

    /// Remove a friend: drop them from MY personal CKShare so they lose access
    /// to my data. This is a one-sided unfriend (CloudKit only lets the share
    /// owner modify the share, so I can't also remove myself from THEIR share —
    /// they'd have to do that on their end). On their next refresh my zone
    /// disappears from their sharedDB, so I drop off their friend list too.
    func unfriend(_ friend: Friend) async throws {
        let recordID = CKRecord.ID(recordName: friend.userID)
        try await personalRepository.removeFriendParticipant(userRecordID: recordID)
        await personalStore.refresh()
        // Also refresh requests in case any pending/outgoing involving this
        // user need to clear out now that they're no longer a friend.
        await refreshFriendRequests()
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
        do {
            let incoming = try await friendRequestRepository.incoming(for: currentUserID)
            // Clear any stale error message from a previous failed refresh.
            lastFriendRequestError = nil
            NSLog("[Tally] refreshFriendRequests: incoming=\(incoming.count) for userID=\(currentUserID)")

            // Auto-process reciprocal requests first — these arrive when a
            // friend accepted MY earlier request. We need to accept their
            // share silently so we see their data too.
            for r in incoming where r.isReciprocal {
                if let url = URL(string: r.shareURL) {
                    do {
                        let metadata = try await CKClient.shared.container.shareMetadata(for: url)
                        try await acceptShareMetadata(metadata)
                    } catch {
                        NSLog("[Tally] Auto-accept reciprocal failed: \(error.localizedDescription)")
                    }
                }
                // Hide it locally; the sender will clean up the record.
                markRequestDeclined(r)
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
            // Refresh friends so an accepted reciprocal shows up in the list.
            await personalStore.refresh()
        } catch {
            NSLog("[Tally] refreshFriendRequests failed: \(error.localizedDescription)")
            lastFriendRequestError = error.localizedDescription
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
        await refreshFriendRequests()
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

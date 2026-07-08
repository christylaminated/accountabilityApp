import Testing
import CloudKit
import Foundation
@testable import Tally

/// Covers the friend lifecycle the unfriend / delete-account work touches:
///   add friend → unfriend (persisted hide) → re-add (clear hide) and the
///   distinct "their account was deleted" path (erase, NO persisted hide).
///
/// Scope note: these exercise `PersonalStore` (the suppression/erase engine)
/// and `AppState.processUnfriendNotifications` (the erase-vs-hide decision)
/// with in-memory mocks. `AppState.deleteAccount` itself is NOT covered — it
/// calls `CKClient.shared` directly (zone deletes), so it can't run without a
/// live CloudKit account.
///
/// `.serialized` because every case shares `UserDefaults.standard` via
/// `LocalCache`; `init()` wipes the user-scoped keys before each test.
@MainActor
@Suite("FriendLifecycle", .serialized)
struct FriendLifecycleTests {

    init() {
        LocalCache.clearAll()
        // Keep message-save retry loops from running in real time in tests.
        CircleStore.messageSaveRetryDelayNanos = 1_000
    }

    // MARK: - Helpers

    /// A friend's personal zone as it appears in our sharedDB, keyed by their
    /// user record name (the `ownerName`).
    private func zone(_ owner: String) -> CKRecordZone {
        CKRecordZone(zoneID: CKRecordZone.ID(zoneName: "personalData", ownerName: owner))
    }

    /// A mock personal repository whose sharedDB surfaces `owners` as friends.
    private func repo(friendOwners owners: [String]) -> MockPersonalRepository {
        let mock = MockPersonalRepository()
        mock.friendZoneList = owners.map(zone)
        return mock
    }

    /// A store that has already loaded `owners` as friends.
    private func loadedStore(_ owners: [String]) async -> (PersonalStore, MockPersonalRepository) {
        let mock = repo(friendOwners: owners)
        let store = PersonalStore(repository: mock)
        await store.activate(currentUserID: "me")
        return (store, mock)
    }

    private func hasFriend(_ store: PersonalStore, _ id: String) -> Bool {
        store.friends.contains { $0.userID == id }
    }

    // MARK: - Adding friends

    @Test func addingFriend_surfacesFromSharedZones() async {
        let (store, _) = await loadedStore(["alice", "bob"])
        #expect(hasFriend(store, "alice"))
        #expect(hasFriend(store, "bob"))
        #expect(store.friends.count == 2)
    }

    // MARK: - Unfriend (persisted hide)

    @Test func unfriend_removesFriendAndHidesAcrossRefresh() async {
        let (store, _) = await loadedStore(["alice"])

        store.dropFriendLocally(userID: "alice")
        #expect(!hasFriend(store, "alice"))
        #expect(store.isLocallyUnfriended(userID: "alice"))

        // Their zone is still in sharedDB; a refresh must NOT bring them back.
        await store.refresh()
        #expect(!hasFriend(store, "alice"))
    }

    @Test func unfriend_persistsAcrossRelaunch() async {
        let (store, mock) = await loadedStore(["alice"])
        store.dropFriendLocally(userID: "alice")

        // Fresh store == app relaunch. Same sharedDB (zone still present),
        // same LocalCache. The persisted hide must keep alice gone.
        let relaunched = PersonalStore(repository: mock)
        await relaunched.activate(currentUserID: "me")
        #expect(!hasFriend(relaunched, "alice"))
        #expect(relaunched.isLocallyUnfriended(userID: "alice"))
    }

    // MARK: - Re-adding a previously unfriended friend

    @Test func reAddFriend_afterUnfriend_clearsHideAndReappears() async {
        let (store, _) = await loadedStore(["alice"])
        store.dropFriendLocally(userID: "alice")
        #expect(!hasFriend(store, "alice"))

        // Re-friending clears the hide (what acceptFriendRequest /
        // handleIncomingShareIfNeeded do under the hood).
        store.clearLocalUnfriend(userID: "alice")
        #expect(!store.isLocallyUnfriended(userID: "alice"))

        await store.refresh()
        #expect(hasFriend(store, "alice"))
    }

    // MARK: - Account deletion (erase, NO persisted tombstone)

    @Test func deletedAccount_erasesFriendWithoutPersistedTombstone() async {
        let (store, _) = await loadedStore(["alice"])

        store.eraseDeletedFriend(userID: "alice")
        #expect(!hasFriend(store, "alice"))
        // The crux: a deletion does NOT leave a persisted hide-list entry.
        #expect(!store.isLocallyUnfriended(userID: "alice"))

        // In-session refresh still suppresses the flicker while the zone
        // deletion propagates.
        await store.refresh()
        #expect(!hasFriend(store, "alice"))
    }

    @Test func deletedAccount_leavesNoResidueOnceZoneIsGone() async {
        let (store, mock) = await loadedStore(["alice"])
        store.eraseDeletedFriend(userID: "alice")

        // Their zone has now actually been destroyed server-side.
        mock.friendZoneList = []

        let relaunched = PersonalStore(repository: mock)
        await relaunched.activate(currentUserID: "me")
        #expect(!hasFriend(relaunched, "alice"))
        // No tombstone left behind — fully erased, not hidden.
        #expect(!relaunched.isLocallyUnfriended(userID: "alice"))
    }

    /// The session guard is intentionally NOT persisted. This documents the
    /// contract: erase relies on the zone being gone, not on a durable hide —
    /// the opposite of `unfriend_persistsAcrossRelaunch`.
    @Test func deletedAccount_sessionGuardIsNotPersisted() async {
        let (store, mock) = await loadedStore(["alice"])
        store.eraseDeletedFriend(userID: "alice")

        // Relaunch while the zone (hypothetically) still lingers: with no
        // persisted hide and a fresh in-memory guard, alice resurfaces —
        // exactly why we depend on the zone actually being deleted.
        let relaunched = PersonalStore(repository: mock)
        await relaunched.activate(currentUserID: "me")
        #expect(hasFriend(relaunched, "alice"))
    }

    // MARK: - UnfriendNotification deletion flag round-trips through CloudKit

    @Test func deletionFlag_roundTripsThroughCKRecord() {
        for flag in [true, false] {
            let notif = UnfriendNotification(
                id: UUID(),
                fromUserRecordName: "a",
                toUserRecordName: "b",
                sentAt: Date(),
                isAccountDeletion: flag
            )
            let record = CKRecord(recordType: UnfriendNotification.recordType)
            notif.populate(record)
            let decoded = UnfriendNotification(record: record)
            #expect(decoded?.isAccountDeletion == flag)
        }
    }

    @Test func deletionFlag_defaultsFalseWhenFieldMissing() {
        // Older records written before the field existed must decode as a
        // plain unfriend, never a hard erase.
        let record = CKRecord(recordType: UnfriendNotification.recordType)
        record["id"] = UUID().uuidString
        record["fromUserRecordName"] = "a"
        record["toUserRecordName"] = "b"
        record["sentAt"] = Date()
        let decoded = UnfriendNotification(record: record)
        #expect(decoded != nil)
        #expect(decoded?.isAccountDeletion == false)
    }

    // MARK: - Receiving side: erase-vs-hide decision in AppState

    /// Build an AppState wired entirely to in-memory mocks. On the test
    /// simulator there's no signed-in iCloud, so the init's background
    /// `refreshAccountState` short-circuits at `.noAccount` and never touches
    /// the state we assert on.
    private func appState(
        personal: MockPersonalRepository,
        store: PersonalStore,
        notifications: MockUnfriendNotificationRepository,
        friendRequests: MockFriendRequestRepository = MockFriendRequestRepository()
    ) -> AppState {
        let app = AppState(
            profileRepository: MockProfileRepository(),
            circleRepository: MockCircleRepository(),
            personalRepository: personal,
            usernameRepository: MockUsernameRepository(),
            friendRequestRepository: friendRequests,
            groupInviteRepository: MockGroupInviteRepository(),
            unfriendNotificationRepository: notifications,
            personalStore: store
        )
        app.stopFriendRequestPolling()
        app.currentUserID = "me"
        return app
    }

    @Test func receivingDeletionNotification_erasesFriendNoTombstone() async {
        let personal = repo(friendOwners: ["alice"])
        let store = PersonalStore(repository: personal)
        await store.activate(currentUserID: "me")
        #expect(hasFriend(store, "alice"))

        let notif = UnfriendNotification(
            id: UUID(), fromUserRecordName: "alice", toUserRecordName: "me",
            sentAt: Date(), isAccountDeletion: true
        )
        let app = appState(
            personal: personal, store: store,
            notifications: MockUnfriendNotificationRepository(notifications: [notif])
        )

        await app.processUnfriendNotifications()

        #expect(!hasFriend(store, "alice"))
        // Deletion → erased, not hidden.
        #expect(!store.isLocallyUnfriended(userID: "alice"))
    }

    @Test func receivingUnfriendNotification_hidesFriendWithTombstone() async {
        let personal = repo(friendOwners: ["alice"])
        let store = PersonalStore(repository: personal)
        await store.activate(currentUserID: "me")

        let notif = UnfriendNotification(
            id: UUID(), fromUserRecordName: "alice", toUserRecordName: "me",
            sentAt: Date(), isAccountDeletion: false
        )
        let app = appState(
            personal: personal, store: store,
            notifications: MockUnfriendNotificationRepository(notifications: [notif])
        )

        await app.processUnfriendNotifications()

        #expect(!hasFriend(store, "alice"))
        // Plain unfriend → persisted hide (their zone still exists).
        #expect(store.isLocallyUnfriended(userID: "alice"))
    }

    // MARK: - Unfriend (sending side) — server-side mutual cleanup

    @Test func unfriend_doesServerSideMutualCleanupAndNotifies() async throws {
        let personal = repo(friendOwners: ["alice"])
        let store = PersonalStore(repository: personal)
        await store.activate(currentUserID: "me")
        #expect(hasFriend(store, "alice"))
        let notifs = MockUnfriendNotificationRepository()
        let app = appState(personal: personal, store: store, notifications: notifs)

        try await app.unfriend(Friend(userID: "alice", displayName: "Alice", avatarSymbol: "leaf"))

        // Left their share server-side → their zone leaves my sharedDB (not just
        // a local hide).
        #expect(personal.leftFriendShares.contains("alice"))
        // Notified their device so it drops me — a plain unfriend, not a deletion.
        let outgoing = try await notifs.outgoing(for: "me")
        #expect(outgoing.contains { $0.toUserRecordName == "alice" && !$0.isAccountDeletion })
        // Gone from my list and persistently hidden as a backstop.
        #expect(!hasFriend(store, "alice"))
        #expect(store.isLocallyUnfriended(userID: "alice"))
    }

    // MARK: - Stale reciprocal must not resurrect a removed friend

    /// The "old friends come back after I delete my account" bug: a friend I
    /// originally added left a reciprocal FriendRequest in the public DB that I
    /// can't delete. After delete + re-onboard (same iCloud) that stale
    /// reciprocal must NOT be auto-accepted, because I never re-requested them.
    @Test func staleReciprocalFromHiddenFriend_isNotResurrected() async {
        // Scenario: I deleted my account (resetAt), and a leftover reciprocal
        // from a former friend predates that reset.
        let resetAt = Date()
        LocalCache.save(resetAt, forKey: LocalCacheKey.accountResetAt)

        let personal = repo(friendOwners: [])      // their zone already gone from view
        let store = PersonalStore(repository: personal)
        await store.activate(currentUserID: "me")
        store.dropFriendLocally(userID: "alice")   // alice is hidden (removed)
        #expect(store.isLocallyUnfriended(userID: "alice"))

        // A leftover reciprocal from alice, sent BEFORE my reset, no outgoing req.
        let stale = FriendRequest(
            id: UUID(), fromUserRecordName: "alice", toUserRecordName: "me",
            shareURL: "https://www.icloud.com/share/stale", fromDisplayName: "Alice",
            fromUsername: "alice", fromAvatarSymbol: "leaf",
            sentAt: resetAt.addingTimeInterval(-3600), isReciprocal: true
        )
        let app = appState(
            personal: personal, store: store,
            notifications: MockUnfriendNotificationRepository(),
            friendRequests: MockFriendRequestRepository(requests: [stale])
        )

        await app.refreshFriendRequests()

        // Must still be hidden — the stale reciprocal was declined, not accepted.
        #expect(store.isLocallyUnfriended(userID: "alice"))
        #expect(!hasFriend(store, "alice"))
    }

    /// After delete, every incoming request addressed to me is captured into
    /// the declined list (persisted). On re-setup it must NOT show in the inbox
    /// — "I deleted my account, it shouldn't still say they sent me a request."
    @Test func declinedIncomingRequest_staysHiddenAfterResetup() async {
        let reqID = UUID()
        // Simulate the persisted post-delete state.
        LocalCache.save([reqID.uuidString], forKey: LocalCacheKey.declinedFriendRequestIDs)

        let personal = repo(friendOwners: [])
        let store = PersonalStore(repository: personal)
        await store.activate(currentUserID: "me")
        let req = FriendRequest(
            id: reqID, fromUserRecordName: "bob", toUserRecordName: "me",
            shareURL: "https://www.icloud.com/share/x", fromDisplayName: "Bob",
            fromUsername: "bob", fromAvatarSymbol: "leaf", sentAt: Date(), isReciprocal: false
        )
        let app = appState(
            personal: personal, store: store,
            notifications: MockUnfriendNotificationRepository(),
            friendRequests: MockFriendRequestRepository(requests: [req])
        )

        await app.refreshFriendRequests()

        #expect(app.incomingFriendRequests.isEmpty)
    }

    /// Sender-side cleanup: when I learn someone unfriended me / deleted their
    /// account, the request records I created for them get deleted from the
    /// public DB — so they're truly gone, not just hidden, even across a
    /// reinstall on their side.
    @Test func processingDeletionNotification_deletesMyOutgoingRecordsToThatPerson() async {
        let personal = repo(friendOwners: [])
        let store = PersonalStore(repository: personal)
        await store.activate(currentUserID: "me")

        // A request I created addressed to alice (+ one to carol we must keep).
        let toAlice = FriendRequest(
            id: UUID(), fromUserRecordName: "me", toUserRecordName: "alice",
            shareURL: "https://www.icloud.com/share/a", fromDisplayName: "Me",
            fromUsername: "me", fromAvatarSymbol: "leaf", sentAt: Date(), isReciprocal: false
        )
        let toCarol = FriendRequest(
            id: UUID(), fromUserRecordName: "me", toUserRecordName: "carol",
            shareURL: "https://www.icloud.com/share/c", fromDisplayName: "Me",
            fromUsername: "me", fromAvatarSymbol: "leaf", sentAt: Date(), isReciprocal: false
        )
        let frRepo = MockFriendRequestRepository(requests: [toAlice, toCarol])
        // Alice's account-deletion notification to me.
        let notif = UnfriendNotification(
            id: UUID(), fromUserRecordName: "alice", toUserRecordName: "me",
            sentAt: Date(), isAccountDeletion: true
        )
        let app = appState(
            personal: personal, store: store,
            notifications: MockUnfriendNotificationRepository(notifications: [notif]),
            friendRequests: frRepo
        )

        await app.processUnfriendNotifications()

        let remaining = (try? await frRepo.outgoing(for: "me")) ?? []
        // My request to alice is gone; unrelated request to carol survives.
        #expect(!remaining.contains { $0.toUserRecordName == "alice" })
        #expect(remaining.contains { $0.toUserRecordName == "carol" })
    }

    // MARK: - Crash-durable DM outbox

    @Test func sendDM_persistsToDurableOutboxImmediately() async {
        let mock = MockCircleDataRepository()
        mock.saveShouldFail = true                     // the send will fail
        let store = CircleStore(dataRepo: mock)
        let dm = TallyCircle(
            id: UUID(), name: "dm", emoji: nil, ownerID: "me",
            createdAt: Date(), kind: .dm, dmPeerID: "bob"
        )
        await store.activate(dm, currentUserID: "me")

        store.sendDM(body: "hello", senderID: "me", recipientID: "bob")

        // Written to disk synchronously, BEFORE the (failing) network attempt —
        // so a crash/force-quit right now wouldn't lose the message.
        let outbox = LocalCache.load([DirectMessage].self,
                                     forKey: LocalCacheKey.pendingDirectMessages) ?? []
        #expect(outbox.contains { $0.body == "hello" && $0.circleID == dm.id })
    }

    @Test func sendCircleMessage_persistsToDurableOutboxImmediately() async {
        let mock = MockCircleDataRepository()
        mock.saveShouldFail = true
        let store = CircleStore(dataRepo: mock)
        let group = TallyCircle(
            id: UUID(), name: "group", emoji: nil, ownerID: "me",
            createdAt: Date(), kind: .group, dmPeerID: nil
        )
        await store.activate(group, currentUserID: "me")

        store.sendCircleMessage(body: "gm", senderID: "me")

        let outbox = LocalCache.load([CircleMessage].self,
                                     forKey: LocalCacheKey.pendingCircleMessages) ?? []
        #expect(outbox.contains { $0.body == "gm" && $0.circleID == group.id })
    }

    // MARK: - Exception shim actually catches at RUNTIME (crash-safety linchpin)

    @Test func exceptionShim_catchesRaisedNSException() {
        // If the shim did NOT catch it, `.raise()` would tear down the whole
        // test process — so a passing assertion is genuine runtime proof that
        // the Obj-C @try/@catch works, not just that it compiles.
        let caught = ExceptionCatcherProbe.didCatchException {
            NSException(name: .genericException, reason: "boom", userInfo: nil).raise()
        }
        #expect(caught)
    }

    @Test func exceptionShim_passesThroughNormalBlock() {
        var ran = false
        let caught = ExceptionCatcherProbe.didCatchException { ran = true }
        #expect(ran)
        #expect(!caught)
    }

    // MARK: - Former-friend requests stay gone after a reset

    /// The reported bug: after deleting my account, an OLD friend's request
    /// still shows. Any request that predates my account reset must be
    /// suppressed — crucially WITHOUT relying on the former-friend hide-list
    /// (which can be incomplete) — while a genuinely NEW request still shows.
    @Test func requestBeforeReset_isSuppressed_newOneShows() async {
        let resetAt = Date()
        LocalCache.save(resetAt, forKey: LocalCacheKey.accountResetAt)

        let personal = repo(friendOwners: [])
        let store = PersonalStore(repository: personal)
        await store.activate(currentUserID: "me")
        // NOTE: alice is deliberately NOT in the hide-list — suppression must
        // work purely from the timestamp, which is the whole point of the fix.

        // An OLD request from alice (before the reset) and a NEW one (after).
        let oldReq = FriendRequest(
            id: UUID(), fromUserRecordName: "alice", toUserRecordName: "me",
            shareURL: "https://www.icloud.com/share/old", fromDisplayName: "Alice",
            fromUsername: "alice", fromAvatarSymbol: "leaf",
            sentAt: resetAt.addingTimeInterval(-3600), isReciprocal: false
        )
        let newReq = FriendRequest(
            id: UUID(), fromUserRecordName: "alice", toUserRecordName: "me",
            shareURL: "https://www.icloud.com/share/new", fromDisplayName: "Alice",
            fromUsername: "alice", fromAvatarSymbol: "leaf",
            sentAt: resetAt.addingTimeInterval(3600), isReciprocal: false
        )
        let app = appState(
            personal: personal, store: store,
            notifications: MockUnfriendNotificationRepository(),
            friendRequests: MockFriendRequestRepository(requests: [oldReq, newReq])
        )

        await app.refreshFriendRequests()

        // Old (pre-reset) request suppressed; new (post-reset) one still shows.
        #expect(!app.incomingFriendRequests.contains { $0.id == oldReq.id })
        #expect(app.incomingFriendRequests.contains { $0.id == newReq.id })
    }

    // MARK: - Cancel / retract an outgoing friend request

    @Test func cancelFriendRequest_deletesRecordAndClearsPending() async throws {
        let personal = repo(friendOwners: [])
        let store = PersonalStore(repository: personal)
        await store.activate(currentUserID: "me")
        let mine = FriendRequest(
            id: UUID(), fromUserRecordName: "me", toUserRecordName: "alice",
            shareURL: "https://www.icloud.com/share/a", fromDisplayName: "Me",
            fromUsername: "me", fromAvatarSymbol: "leaf", sentAt: Date(), isReciprocal: false
        )
        let frRepo = MockFriendRequestRepository(requests: [mine])
        let app = appState(
            personal: personal, store: store,
            notifications: MockUnfriendNotificationRepository(), friendRequests: frRepo
        )
        app.outgoingRequestTargetIDs = ["alice"]

        try await app.cancelFriendRequest(to: "alice")

        // Record is deleted from the public DB (so it leaves their inbox)…
        let remaining = (try? await frRepo.outgoing(for: "me")) ?? []
        #expect(!remaining.contains { $0.toUserRecordName == "alice" })
        // …and the local pending flag is cleared so the UI flips back to Send.
        #expect(!app.outgoingRequestTargetIDs.contains("alice"))
    }

    // MARK: - Friend-symmetry self-heal

    /// An AppState wired for reconcile: signed in, in the main app, with a
    /// profile (sendReciprocalShareBack requires one). `addFriendParticipant`
    /// appends to `personal.friends`, which we use as the observable "a repair
    /// was attempted for this friend" signal.
    private func reconcileApp(personal: MockPersonalRepository, store: PersonalStore) -> AppState {
        let app = appState(
            personal: personal, store: store,
            notifications: MockUnfriendNotificationRepository()
        )
        app.onboardingState = .enteredMainApp
        app.ownCloudProfile = UserProfile(
            displayName: "Me", avatarSymbol: "leaf",
            avatarImageData: nil, username: "me", createdAt: Date()
        )
        return app
    }

    @Test func selfHeal_skipsFriendWhoAlreadySeesMe() async {
        let personal = repo(friendOwners: ["alice"])
        personal.personalShareParticipants = ["alice"]   // alice already sees me
        let store = PersonalStore(repository: personal)
        await store.activate(currentUserID: "me")
        let app = reconcileApp(personal: personal, store: store)

        await app.reconcileFriendSymmetry(trigger: "test")

        // Already symmetric → no repair attempted.
        #expect(!personal.friends.contains { $0.recordName == "alice" })
    }

    @Test func selfHeal_bailsWhenParticipantsUnreadable() async {
        let personal = repo(friendOwners: ["alice"])
        personal.personalShareParticipantsError = NSError(domain: "test", code: 1)
        let store = PersonalStore(repository: personal)
        await store.activate(currentUserID: "me")
        let app = reconcileApp(personal: personal, store: store)

        await app.reconcileFriendSymmetry(trigger: "test")

        // Conservative: couldn't read who sees me → do nothing.
        #expect(!personal.friends.contains { $0.recordName == "alice" })
    }

    @Test func selfHeal_skipsUnfriendedPerson() async {
        let personal = repo(friendOwners: ["alice"])
        personal.personalShareParticipants = []          // alice can't see me
        let store = PersonalStore(repository: personal)
        await store.activate(currentUserID: "me")
        store.dropFriendLocally(userID: "alice")         // but I unfriended her
        let app = reconcileApp(personal: personal, store: store)

        await app.reconcileFriendSymmetry(trigger: "test")

        // Never re-friend someone who was explicitly unfriended.
        #expect(!personal.friends.contains { $0.recordName == "alice" })
    }

    @Test func selfHeal_repairsOneWayFriend() async {
        let personal = repo(friendOwners: ["alice"])
        personal.personalShareParticipants = []          // alice can't see me
        let store = PersonalStore(repository: personal)
        await store.activate(currentUserID: "me")
        let app = reconcileApp(personal: personal, store: store)

        await app.reconcileFriendSymmetry(trigger: "test")

        // One-way → repair attempted: alice re-added as a participant on my
        // share. (The reciprocal send can't fully complete against the mock's
        // URL-less share, but the repair path ran — which is what we assert.)
        #expect(personal.friends.contains { $0.recordName == "alice" })
    }

    @Test func selfHeal_reSharesToSeenFriend_afterRecentReset() async {
        // I deleted my account moments ago → my zone/share are brand new.
        LocalCache.save(Date.now, forKey: LocalCacheKey.accountResetAt)
        let personal = repo(friendOwners: ["alice"])
        // Alice APPEARS to already see me… but her acceptance is of my old,
        // destroyed share, so she actually can't (the reported bug).
        personal.personalShareParticipants = ["alice"]
        let store = PersonalStore(repository: personal)
        await store.activate(currentUserID: "me")
        let app = reconcileApp(personal: personal, store: store)

        await app.reconcileFriendSymmetry(trigger: "test")

        // Post-reset we don't trust the stale participant list → re-send my
        // share so she can re-accept my new zone.
        #expect(personal.friends.contains { $0.recordName == "alice" })
    }

    @Test func selfHeal_skipsSeenFriend_whenNoRecentReset() async {
        // No reset (clean LocalCache) → steady-state behaviour: a friend who
        // already sees me is NOT re-shared to.
        let personal = repo(friendOwners: ["alice"])
        personal.personalShareParticipants = ["alice"]
        let store = PersonalStore(repository: personal)
        await store.activate(currentUserID: "me")
        let app = reconcileApp(personal: personal, store: store)

        await app.reconcileFriendSymmetry(trigger: "test")

        #expect(!personal.friends.contains { $0.recordName == "alice" })
    }

    // MARK: - Avatar claim self-heal

    /// An AppState wired for the avatar self-heal, exposing the passed-in
    /// username repo so the test can seed/inspect the public `UsernameClaim`.
    private func avatarApp(username: MockUsernameRepository) -> AppState {
        let personal = repo(friendOwners: [])
        let store = PersonalStore(repository: personal)
        let app = AppState(
            profileRepository: MockProfileRepository(),
            circleRepository: MockCircleRepository(),
            personalRepository: personal,
            usernameRepository: username,
            friendRequestRepository: MockFriendRequestRepository(),
            groupInviteRepository: MockGroupInviteRepository(),
            unfriendNotificationRepository: MockUnfriendNotificationRepository(),
            personalStore: store
        )
        app.stopFriendRequestPolling()
        app.currentUserID = "me"
        app.onboardingState = .enteredMainApp
        return app
    }

    private func profile(photo: Data?) -> UserProfile {
        UserProfile(
            displayName: "Me", avatarSymbol: "leaf",
            avatarImageData: photo, username: "me", createdAt: Date()
        )
    }

    @Test func avatarSelfHeal_republishesWhenClaimMissingPhoto() async throws {
        let username = MockUsernameRepository()
        // Claim exists but carries NO photo (pre-deploy / quota-interrupted drift).
        try await username.claim("me", previousUsername: nil, displayName: "Me",
                                 avatarSymbol: "leaf", avatarImageData: nil)
        let app = avatarApp(username: username)
        let photo = Data([0x01, 0x02, 0x03])
        app.ownCloudProfile = profile(photo: photo)

        await app.reconcileAvatarClaim(trigger: "test")

        // The searchable claim now carries the local photo.
        let claim = try await username.lookup("me")
        #expect(claim?.avatarImageData == photo)
    }

    @Test func avatarSelfHeal_leavesExistingClaimPhotoUntouched() async throws {
        let username = MockUsernameRepository()
        let existing = Data([0x09, 0x09])
        try await username.claim("me", previousUsername: nil, displayName: "Me",
                                 avatarSymbol: "leaf", avatarImageData: existing)
        let app = avatarApp(username: username)
        app.ownCloudProfile = profile(photo: Data([0x01, 0x02, 0x03]))

        await app.reconcileAvatarClaim(trigger: "test")

        // Claim already had a photo → no overwrite (guard skips on claimBytes>0).
        let claim = try await username.lookup("me")
        #expect(claim?.avatarImageData == existing)
    }

    @Test func avatarSelfHeal_noWriteWhenNoLocalPhoto() async throws {
        let username = MockUsernameRepository()
        try await username.claim("me", previousUsername: nil, displayName: "Me",
                                 avatarSymbol: "leaf", avatarImageData: nil)
        let app = avatarApp(username: username)
        app.ownCloudProfile = profile(photo: nil)   // nothing to publish

        await app.reconcileAvatarClaim(trigger: "test")

        let claim = try await username.lookup("me")
        #expect(claim?.avatarImageData == nil)
    }

    // MARK: - Unread indicator: only opening a conversation clears it

    @Test func unread_activeCircleStaysUnread_untilOpened() async {
        // A DM with an incoming message. Fresh UUID → no stale read state.
        let dm = TallyCircle(
            id: UUID(), name: "dm", emoji: nil, ownerID: "me",
            createdAt: Date(), kind: .dm, dmPeerID: "bob"
        )
        let incoming = CircleMessage(
            id: UUID(), circleID: dm.id, senderID: "bob",
            body: "hi", createdAt: Date()
        )
        let mock = MockCircleDataRepository(
            snapshot: CircleSnapshot(circleMessages: [incoming])
        )
        let store = CircleStore(dataRepo: mock)
        // Activating makes `dm` the store's "active" circle AND records its
        // latest-message time (via load()). The user has NOT opened the thread.
        await store.activate(dm, currentUserID: "me")

        // A plain refresh (what pull-to-refresh triggers) must NOT clear the dot
        // for a conversation the user never opened — even though it's "active".
        store.recomputeUnread(for: [dm])
        #expect(store.unreadCircleIDs.contains(dm.id))

        // Only opening the conversation (markCircleRead) clears it.
        store.markCircleRead(circleID: dm.id)
        #expect(!store.unreadCircleIDs.contains(dm.id))

        // And it stays clear across a subsequent refresh.
        store.recomputeUnread(for: [dm])
        #expect(!store.unreadCircleIDs.contains(dm.id))
    }

    // MARK: - Removing a DM when the peer deletes their account

    private func conversationApp(circleRepo: MockCircleRepository) -> AppState {
        let personal = repo(friendOwners: [])
        let store = PersonalStore(repository: personal)
        let app = AppState(
            profileRepository: MockProfileRepository(),
            circleRepository: circleRepo,
            personalRepository: personal,
            usernameRepository: MockUsernameRepository(),
            friendRequestRepository: MockFriendRequestRepository(),
            groupInviteRepository: MockGroupInviteRepository(),
            unfriendNotificationRepository: MockUnfriendNotificationRepository(),
            personalStore: store
        )
        app.stopFriendRequestPolling()
        app.currentUserID = "me"
        return app
    }

    @Test func removeConversations_deletesOwnedDMAndPersistsHide() async {
        // A DM we own with bob (messages live in OUR zone).
        let dm = TallyCircle(
            id: UUID(), name: "bob", emoji: nil, ownerID: "me",
            createdAt: Date(), kind: .dm, dmPeerID: "bob"
        )
        let circleRepo = MockCircleRepository(owned: [dm])
        let app = conversationApp(circleRepo: circleRepo)
        app.ownedCircles = [dm]

        await app.removeConversations(withPeer: "bob")

        // Dropped from the list…
        #expect(!app.ownedCircles.contains { $0.id == dm.id })
        // …the owned zone is deleted server-side (messages gone for both)…
        #expect(!circleRepo.owned.contains { $0.id == dm.id })
        // …and the hide is persisted so a lagging reload can't resurrect it.
        let persisted = LocalCache.load([String].self, forKey: LocalCacheKey.removedCircleIDs) ?? []
        #expect(persisted.contains(dm.id.uuidString))
    }

    @Test func removeConversations_dropsPeerOwnedDMLocally() async {
        // A DM bob owns (we're a participant) — we can't delete bob's zone, but
        // we still drop it locally + persist the hide.
        let dm = TallyCircle(
            id: UUID(), name: "bob", emoji: nil, ownerID: "bob",
            createdAt: Date(), kind: .dm, dmPeerID: "me"
        )
        let circleRepo = MockCircleRepository(joined: [dm])
        let app = conversationApp(circleRepo: circleRepo)
        app.joinedCircles = [dm]

        await app.removeConversations(withPeer: "bob")

        #expect(!app.joinedCircles.contains { $0.id == dm.id })
        let persisted = LocalCache.load([String].self, forKey: LocalCacheKey.removedCircleIDs) ?? []
        #expect(persisted.contains(dm.id.uuidString))
    }

    @Test func removeConversations_leavesUnrelatedCirclesAlone() async {
        // A group (not a DM) and a DM with someone else must be untouched.
        let group = TallyCircle(
            id: UUID(), name: "grp", emoji: nil, ownerID: "me",
            createdAt: Date(), kind: .group, dmPeerID: nil
        )
        let otherDM = TallyCircle(
            id: UUID(), name: "carol", emoji: nil, ownerID: "me",
            createdAt: Date(), kind: .dm, dmPeerID: "carol"
        )
        let app = conversationApp(circleRepo: MockCircleRepository(owned: [group, otherDM]))
        app.ownedCircles = [group, otherDM]

        await app.removeConversations(withPeer: "bob")

        #expect(app.ownedCircles.contains { $0.id == group.id })
        #expect(app.ownedCircles.contains { $0.id == otherDM.id })
    }

    // MARK: - Private per-day history notes

    private func dayNoteApp(_ repo: MockDayNoteRepository) -> AppState {
        let personal = self.repo(friendOwners: [])
        let store = PersonalStore(repository: personal)
        let app = appState(personal: personal, store: store,
                           notifications: MockUnfriendNotificationRepository())
        app.dayNoteRepository = repo
        return app
    }

    @Test func dayNote_savesAndReloadsForSameDay() async {
        let repo = MockDayNoteRepository()
        let app = dayNoteApp(repo)
        let day = Date(timeIntervalSince1970: 1_700_000_000)   // fixed instant

        let saved = await app.saveDayNote("  showed up anyway  ", for: day)
        #expect(saved)
        // Trimmed on save…
        let note = await app.dayNote(for: day)
        #expect(note?.text == "showed up anyway")
        // …and keyed by day, so a later time on the same day reads it back.
        let laterSameDay = day.addingTimeInterval(6 * 60 * 60)
        let sameDayNote = await app.dayNote(for: laterSameDay)
        #expect(sameDayNote?.text == "showed up anyway")
    }

    @Test func dayNote_clearingTextDeletesTheNote() async {
        let repo = MockDayNoteRepository()
        let app = dayNoteApp(repo)
        let day = Date(timeIntervalSince1970: 1_700_000_000)

        _ = await app.saveDayNote("temporary", for: day)
        #expect(await app.dayNote(for: day) != nil)

        // Emptying the text removes the record rather than storing a blank note.
        _ = await app.saveDayNote("   ", for: day)
        #expect(await app.dayNote(for: day) == nil)
        #expect(repo.notes.isEmpty)
    }

    @Test func dayNote_separateDaysAreIndependent() async {
        let repo = MockDayNoteRepository()
        let app = dayNoteApp(repo)
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        let day2 = day1.addingTimeInterval(48 * 60 * 60)   // two days later

        _ = await app.saveDayNote("day one", for: day1)
        _ = await app.saveDayNote("day two", for: day2)

        #expect(await app.dayNote(for: day1)?.text == "day one")
        #expect(await app.dayNote(for: day2)?.text == "day two")
    }

    @Test func senderAvatar_resolvesFriendSelfAndStranger() async {
        let personal = repo(friendOwners: [])
        let store = PersonalStore(repository: personal)
        let friendPhoto = Data([0xAA, 0xBB])
        store.friends = [Friend(userID: "alice", displayName: "Alice",
                                avatarSymbol: "leaf", avatarImageData: friendPhoto)]
        let app = appState(personal: personal, store: store,
                           notifications: MockUnfriendNotificationRepository())
        let myPhoto = Data([0x01])
        app.ownCloudProfile = UserProfile(
            displayName: "Me", avatarSymbol: "leaf",
            avatarImageData: myPhoto, username: "me", createdAt: Date()
        )

        // Friend's message → their synced photo + current symbol.
        #expect(app.senderAvatar(for: "alice").imageData == friendPhoto)
        #expect(app.senderAvatar(for: "alice").symbol == "leaf")
        // Own message (currentUserID == "me") → our own profile photo.
        #expect(app.senderAvatar(for: "me").imageData == myPhoto)
        // Non-friend group member → nil photo, so AvatarView shows the symbol.
        #expect(app.senderAvatar(for: "stranger").imageData == nil)
    }

    @Test func avatarSelfHeal_runsAtMostOncePerSession() async throws {
        let username = MockUsernameRepository()
        try await username.claim("me", previousUsername: nil, displayName: "Me",
                                 avatarSymbol: "leaf", avatarImageData: nil)
        let app = avatarApp(username: username)
        app.ownCloudProfile = profile(photo: Data([0x01, 0x02, 0x03]))

        await app.reconcileAvatarClaim(trigger: "first")   // repairs
        // Simulate the claim drifting back to no-photo, then run again.
        try await username.claim("me", previousUsername: "me", displayName: "Me",
                                 avatarSymbol: "leaf", avatarImageData: nil)
        await app.reconcileAvatarClaim(trigger: "second")  // guarded — no-op

        let claim = try await username.lookup("me")
        #expect(claim?.avatarImageData == nil)   // second run did not re-repair
    }
}

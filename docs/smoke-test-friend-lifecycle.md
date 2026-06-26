# Smoke test: friend lifecycle (manual, two accounts)

These flows depend on real CloudKit sharing across two iCloud users and cannot
be exercised by the unit tests (which use in-memory mocks). Run this checklist
on a real build before shipping changes to friending, unfriend, or account
deletion.

## Setup

- **Two devices/simulators**, each signed into a **different iCloud account**.
  - Device **A** → iCloud user **Alice**
  - Device **B** → iCloud user **Bob**
- Build **40+** installed on both. Same CloudKit environment on both
  (Development for a dev build, or Production via TestFlight).
- **Watch the console** (`[Tally]` logs) on both devices — every step below logs
  what it did, which is the fastest way to see where a flow stalls.

> CloudKit is eventually-consistent. "after sync" below means: give it up to
> ~30s, and foreground each app at least once (background → foreground) to force
> a refresh. The 6s poll also drives most updates while foregrounded.

---

## 1. Add a friend — both directions must see it

1. On **A (Alice)**, send a friend request to **Bob**.
2. On **B (Bob)**, the request appears. Accept it.
3. **Expect (B):** Alice appears in Bob's friends list / leaderboard.
4. **Expect (A):** within ~30s (foreground A if needed), Bob appears in Alice's
   friends list too.

✅ Pass: **both** see each other.
❌ Fail: only one side sees the other after a minute of both apps foregrounded
(if so, capture both consoles — look for `sendReciprocalShareBack` /
`reconcileFriendSymmetry` lines).

---

## 2. Unfriend — both apps drop the friendship

Precondition: Alice & Bob are mutual friends (from test 1).

1. On **A (Alice)**, unfriend Bob.
2. **Expect (A):** Bob disappears from Alice's list immediately.
3. **Expect (B):** within ~30s (foreground B), Alice disappears from Bob's list.
4. **Expect:** neither can see the other's data. Console on A shows
   `unfriend: left friend's share server-side`; console on B shows
   `processUnfriendNotifications: applying unfriend`.

✅ Pass: both lists no longer show the other, and neither side reappears on a
later foreground.
❌ Fail: Bob still sees Alice after a minute foregrounded, or Alice reappears.

---

## 3. Delete account + reinstall — clean slate, no ghost friends

This is the important one. Precondition: Alice has at least one friend (Bob)
**and** is a member of at least one circle owned by Bob.

1. On **B (Bob)**, create a circle and invite **Alice**; Alice accepts so she's a
   member of Bob's circle.
2. On **A (Alice)**, **delete account** (Settings → delete).
3. **Expect (B):** within ~30s, Alice disappears from Bob's friends list **and**
   from Bob's circle's member list.
4. On **A**, **delete the app entirely**, then **reinstall** and sign in with the
   **same** iCloud account (Alice). Complete onboarding.
5. **Expect (A):** Alice's friends list is **empty** — Bob does **not** reappear.
   No ghost friends, no leftover circles.

✅ Pass: reinstalled Alice has zero friends and zero old circles.
❌ Fail: Bob (or any old friend) reappears after reinstall — capture A's console
during onboarding and the `deleteAccount` logs from step 2.

> Why this can still lag: a friend's zone leaves Alice's sharedDB only once the
> server processes the `leaveFriendShare` removal. If you reinstall within a
> second or two of deleting, give it a moment and relaunch.

---

## 4. Self-heal — repair a one-way friendship without going overboard

Goal: force the "only one of us sees it" state, then confirm the self-heal fixes
it on launch/foreground — and that it does **not** re-friend someone unfriended.

**Force a half-failed state:** the easiest reproduction is to interrupt the
reciprocal. On **B (Bob)**, accept Alice's request, then immediately kill the app
(swipe-close) before it finishes syncing, while toggling Airplane Mode on briefly
so the reciprocal write fails. Result you want: **Bob sees Alice, Alice does NOT
see Bob.**

1. Confirm the asymmetry: Bob's list shows Alice; Alice's list does **not** show
   Bob (give it a minute to rule out plain lag).
2. On **B (Bob)**, background then foreground the app (or relaunch).
3. **Expect:** console shows `reconcileFriendSymmetry(...): one-way friend ...
   re-sending my share` then `repaired ...`.
4. **Expect (A):** within ~30s, Bob now appears in Alice's list. Symmetric.

**Do-not-overdo-it checks:**
- Foreground B several more times. **Expect:** no repeated repair for the same
  friend in the same session (console logs at most one `repaired` per friend per
  session). No duplicate/phantom friends appear.
- Unfriend someone, then foreground. **Expect:** the self-heal does **not**
  re-add them (console never logs a repair for a hide-listed user).

✅ Pass: the one-way friendship becomes mutual after a foreground, with no
repeated/again-and-again repairs and no resurrection of unfriended people.

---

## Notes / things beyond this change's scope

- **CloudKit schema (action required before TestFlight/Prod):** account deletion
  now writes `UnfriendNotification.isAccountDeletion` (Int64). Deploy the schema
  to **Production** in the CloudKit Dashboard before a production build, or those
  writes fail. (Dev auto-creates the field on first save.)
- **Self-heal only fixes the direction it can see.** Each device repairs
  "people I can see who can't see me." The opposite direction is repaired by the
  *other* device running the same self-heal. So a fully one-way friendship
  becomes symmetric only after **both** users foreground the app at least once.
  This is by design (conservative — a device never acts on data it can't see),
  but worth knowing when diagnosing.
- **Reinstall cleanliness depends on `leaveFriendShare` landing.** It's now
  crash-safe (Obj-C exception shim) and best-effort per friend. If a particular
  friend's share removal fails (network), that one zone could linger in the
  sharedDB until a later cleanup; the others are unaffected.
- **The exception shim can't be unit-tested** (it's behind the app bridging
  header). Its whole purpose is to stop an iOS 26 crash on
  `CKShare.removeParticipant`, so verify on a real iOS 26 device that unfriend
  (test 2) and delete (test 3) never crash mid-operation.
- **Potential follow-up (not done here):** `deleteAccount` still calls
  `CKClient.shared` directly, so it has no unit-test coverage. Abstracting
  `CKClient` behind a protocol would let us test the deletion orchestration.

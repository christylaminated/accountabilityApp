# Smoke test: friends, messaging & account lifecycle (manual, two accounts)

These flows depend on real CloudKit sharing across two iCloud users and can't be
exercised by the unit tests (which use in-memory mocks). Run this on a real build
before shipping changes to friending, messaging, unfriend, or account deletion.

## Setup

- **Two real phones** (best — CloudKit sharing is flaky on simulators), each
  signed into a **different iCloud account**.
  - Phone **A** → iCloud user **Alice**
  - Phone **B** → iCloud user **Bob**
- **Build 46+** installed on both, from the **same** environment:
  - **Xcode Run** = Development CloudKit.
  - **TestFlight** = Production CloudKit. Your existing friends live wherever you
    made them — test in that environment.
- Optional but useful: watch `[Tally]` logs in **Console.app** (Mac → Console →
  pick the phone → filter `Tally`). Works for TestFlight builds too.

> **Timing.** The app polls every ~2s while foregrounded, and a silent **push**
> should make friend/DM updates near-instant even backgrounded. "after sync"
> below means: give it a few seconds; if nothing, foreground each app once.

---

## 1. Add a friend — both sides see each other (fast)

1. On **A**, send Bob a friend request.
2. On **B**, the request appears → Accept.
3. **Expect (B):** Alice appears in Bob's friends list.
4. **Expect (A):** Bob appears in Alice's list within ~1–2s (near-instant if push
   fired; a foreground forces it).

✅ Pass: **both** see each other, quickly.
❌ Fail: only one side sees the other after both apps are foregrounded ~30s.

---

## 2. Cancel (retract) a friend request

1. On **A**, send Bob a request but **do not** accept on B.
2. On **A**, open **Find a friend** → search Bob → the card shows **"Request
   pending"** with a **Cancel request** button → tap it.
3. **Expect (A):** the card flips back to **"Send friend request."**
4. **Expect (B):** within a few seconds, the request **disappears** from Bob's
   friend-requests inbox.

✅ Pass: the request is gone on both sides.

---

## 3. Unfriend — both apps drop it, mutually

Precondition: Alice & Bob are mutual friends.

1. On **A**, unfriend Bob.
2. **Expect (A):** Bob disappears immediately.
3. **Expect (B):** within a few seconds, Alice disappears from Bob's list.
4. **Expect:** neither can see the other's data, and neither reappears on a later
   foreground. (Console A: `unfriend: left friend's share server-side`;
   Console B: `processUnfriendNotifications: applying unfriend`.)
5. **iOS 26 crash check:** the unfriend must **not crash** the app (this is what
   the exception shim guards — it's runtime-tested, but confirm on-device).

✅ Pass: both lists drop the other, no crash, no reappearance.

---

## 4. Direct messages — auto-appear, send, and survive a crash

Precondition: Alice & Bob are **mutual** friends.

1. On **A**, open Bob's profile → **Message** → send "hi".
2. **Expect (B):** the DM shows up **in Direct Messages** — **not** as a "request"
   to accept. (If it shows as a request, the friendship is one-way → see test 6.)
3. **Expect:** "hi" arrives on B; no **"couldn't send the last message"** error.
4. **Crash-durability:** on **A**, type a message and hit send, then
   **immediately force-quit** the app (swipe up) before it confirms. Reopen A and
   the DM thread → the message should still be there and **go out** (not lost).

✅ Pass: DM lands in Messages (not requests), sends cleanly, and a mid-send
force-quit doesn't lose it.

---

## 5. Group chat — send and survive a crash

1. On **A**, create a group circle and invite Bob; Bob accepts.
2. On **A**, send a group message → **Expect (B):** it arrives, no send error.
3. **Crash-durability:** send a group message on **A**, force-quit before it
   confirms, reopen → the message should still send.

✅ Pass: group messages send, and a mid-send force-quit doesn't lose them.

---

## 6. Self-heal — repair a one-way friendship, conservatively

Goal: force "only one of us sees it," then confirm it self-corrects.

**Force it:** on **B**, accept Alice's request, then immediately kill the app
(swipe-close) while briefly toggling Airplane Mode so the reciprocal write fails.
Target state: **Bob sees Alice, Alice does NOT see Bob.**

1. Confirm the asymmetry (give it a minute to rule out plain lag).
2. Foreground **both** apps (this is required — each phone repairs only the
   direction it can see; push should trigger it automatically).
3. **Expect (A):** Bob now appears within a few seconds.
   (Console B: `reconcileFriendSymmetry(...): one-way friend ... re-sending`.)

**Do-not-overdo-it checks:**
- Foreground B several more times → **no** repeated repair for the same friend in
  a session, no duplicate/phantom friends.
- Unfriend someone, then foreground → the self-heal must **not** re-add them.

✅ Pass: becomes mutual after both foreground, with no over-repair and no
resurrection of unfriended people.

---

## 7. Delete account — clean slate on re-setup AND reinstall

Precondition: Alice has ≥1 friend (Bob) and is a member of a circle Bob owns.

1. On **A**, **delete account** (Settings → delete).
2. **Expect (B):** within a few seconds (foreground B), Alice disappears from
   Bob's friends list **and** from Bob's circle members.
3. On **A**, **set up again** with the **same** iCloud account (do **not** delete
   the app). Complete onboarding.
4. **Expect (A):** friends list **empty**; **no old friend requests** in the
   inbox; no ghost circles.
5. **Reinstall variant:** delete the **app**, reinstall, sign in as Alice.
   **Expect (A):** still a clean slate (see caveats for the timing dependency).

✅ Pass: after delete + re-setup, Alice has zero friends, zero old requests, zero
old circles — and the same after a full reinstall (given the other device has
processed the deletion signal).

---

## Status of known limitations (read before interpreting a "fail")

- **Push delivery is unverified off-device.** The subscriptions are created at
  runtime and no schema deploy is needed, but whether a silent push actually
  wakes the app is exactly what test 1/4/6 confirm. It's **additive** — if push
  doesn't fire, the 2s poll still syncs (just not backgrounded/instant), so it
  can't make anything worse than polling.
- **Self-heal needs both devices to foreground** for a fully one-way friendship
  to become mutual — each phone only repairs the direction it can see. By design.
- **Reinstall cleanliness depends on the other side processing the signal.** On
  delete, Alice leaves each friend's share server-side (crash-safe shim) AND asks
  each friend's app to drop her. If a friend's app hasn't foregrounded yet, its
  cleanup is pending — so a reinstall in that window can briefly show a stale
  friend/request until the friend's app catches up.
- **Pending requests from non-friends** (someone who requested you but never
  became a friend) aren't notified on delete, so on a *full reinstall* one could
  still reappear. Same-install re-setup is covered (timestamp suppression).
- **Crash-durable messages cover the message body**, retried on reopen. If a send
  fails permanently (not just eventual-consistency lag), the message stays in the
  local outbox and retries when you reopen the conversation.

## Avatar photo sync (build 53)
Friends who search you by username should see your uploaded photo.
1. **You:** set a profile photo. On another account, search you by username →
   your photo shows in the result. Do the reverse (they set a photo, you search
   them).
2. **Pre-existing claim self-heal:** if your searchable photo was missing (a
   claim written before the schema field was deployed, or a quota-interrupted
   save), it re-publishes automatically on next cold launch — verify the friend
   sees your photo after you relaunch the app once.

**Requires (verify in CloudKit Dashboard → Production):** the `UsernameClaim`
record type must have an `avatarImageData` field of type **Bytes** deployed to
**Production**. Without it, CloudKit silently drops the photo on save (no error)
and search shows no picture — the app logs a ⚠️ `verifyAvatarPersisted` warning
when this happens. Note: the public `UsernameClaim` write does *not* count
against a user's personal iCloud storage quota, so a friend low on storage can
still update their searchable photo even when the private-DB writes fail.

## CloudKit schema
- Already deployed: `UnfriendNotification.isAccountDeletion` (Int64) in
  Production. **No further schema changes are needed** for anything in build 46
  (push subscriptions are created at runtime; they query already-indexed fields).
- **Confirm** `UsernameClaim.avatarImageData` (Bytes) is present in **Production**
  (see Avatar photo sync above) — required for search results to show photos.

## Verified in code (not needing this manual run)
25+ unit tests cover the suppression/erase/cancel logic, the deletion-flag
CloudKit round-trip, the exception shim **at runtime** (proves the iOS 26 crash
is caught), and the crash-durable message outbox. Green tests prove the logic;
this checklist proves the live two-device behavior.

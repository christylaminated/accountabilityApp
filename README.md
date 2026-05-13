# Tally

Small-group accountability app for iOS. Backend is CloudKit (iCloud-based, no server, no API keys). v1 boots into a mock-data preview by default; CloudKit repositories land step-by-step. Full setup walkthrough — iCloud entitlement, capability checklist, TestFlight — comes with CK Step 9.

## What's in this folder

```
accountability/
├── Tally/                   ← Swift sources
│   ├── CloudKit/            ← CKClient, repositories, share + push (built step-by-step)
│   └── Mock/                ← in-memory stores for SwiftUI Previews + UI preview build
├── TallyTests/              ← test stubs
├── project.yml              ← XcodeGen spec — generates Tally.xcodeproj + entitlements
└── README.md
```

Inside `Tally/`:
- `App/`       — `TallyApp`, `RootView`, `MainTabView`, `AppState`, `Constants`
- `Models/`    — Swift structs; conform to `CKRecordConvertible` as repositories land
- `CloudKit/`  — `CKClient`, `CKRecordConvertible`, `DeepLinkHandler`, repositories
- `Mock/`      — `MockData` seed + mock repositories used by Previews and the mock-UI preview
- `Features/`  — one folder per feature: Dashboard, Habits, WeeklyGoals, MemberDetail, Messaging, History
- `Shared/`    — `AvatarView`, `CheckboxButton`, `EmptyStateView`, color theme, Date extensions
- `Utilities/` — `StreakCalculator`, `WeekCalculator` (pure, backend-agnostic, unit-testable)

---

## Run it (option A — XcodeGen, recommended)

XcodeGen reads `project.yml` and generates a valid Xcode project. Two commands.

```bash
brew install xcodegen
cd /Users/christylam/Claude/accountability
xcodegen
```

Then:

1. Open `Tally.xcodeproj` (it was just generated next to the sources).
2. Pick a simulator (iPhone 15 Pro is fine).
3. **Cmd+R** to run.

If you edit `project.yml` later (adding a target, changing settings), re-run `xcodegen` and reopen.

---

## Run it (option B — manual Xcode setup, no extra tools)

If you'd rather not install XcodeGen:

1. **Xcode → File → New → Project → iOS → App.** Settings:
   - Product Name: `Tally`
   - Team: your Apple ID
   - Organization Identifier: `com.christylam`
   - Bundle Identifier: `com.christylam.tally`
   - Interface: SwiftUI
   - Language: Swift
   - Storage: None
   - **Include Tests: Yes**
2. Save the project somewhere **outside** `/Users/christylam/Claude/accountability/` (e.g. `~/Desktop/TallyXcode/`). Picking the same folder will conflict with the existing `Tally/` source directory.
3. In Xcode's project navigator:
   - **Delete** the auto-generated `TallyApp.swift` and `ContentView.swift` (Xcode's stubs).
   - **Drag** the entire `/Users/christylam/Claude/accountability/Tally/` folder into the `Tally` group. In the dialog: check **"Create groups"**, target = **Tally**, choose **"Reference files in place"** (uncheck *Copy if needed*) so edits made here stay canonical.
   - Drag `TallyTests/StreakCalculatorTests.swift` and `TallyTests/WeekCalculatorTests.swift` into the `TallyTests` group, target = **TallyTests**.
4. **Cmd+R**.

---

## What you should see

Boots straight into the **Today** tab with two members (you = Christy 🌿, partner = Jeff ☕). No login screen — `AppState` is hardcoded to Christy. Tabs across the bottom:

- **Today** — dashboard with both members' habit grids. Tap your own pills to check off; partner's are read-only. Tap a member row to see their full detail.
- **Habits** — your habits list. Tap circle to check off (haptic). Long-press to delete/archive. "+" to add. When everything's done, a celebration overlay flashes for ~1.8s.
- **Goals** — current week's goals, Monday-anchored. Last week's unfinished goals appear at the top with a "Carry over" button. "+" to add.
- **Chat** — circle feed at the top, DM thread with Jeff below. Both work; sending a message appends in-memory.
- **History** — month grid of completion intensity. Tap a day to see what was checked. Swipe months with the arrows; future days are disabled.

Everything is in-memory — quit the app and your check-offs reset.

---

## Swap to real backend later

When we wire up Supabase:

1. Run `Supabase/schema.sql` in your project's SQL editor.
2. Delete `Tally/Mock/`.
3. Add `Tally/Supabase/SupabaseClient.swift` + `Tally/Supabase/Repositories/*.swift`.
4. In `AppState.swift`, replace the `Mock*Store` types with the new repositories. Method names stay the same (`profile(id:)`, `toggle(habit:on:)`, `feed(circleID:)`, etc.).
5. Add a `Secrets.swift` (gitignored) for the Supabase URL + anon key.

Views don't change. The mock stores were designed with the same API the real repositories will have.

---

## Notes

- iOS 17+ required (`@Observable`, `symbolEffect(.bounce:)`, `Date.adding(_:)` extensions).
- Light + dark mode work via system colors (`Color.tallyCanvas` etc. use `UIColor.systemGroupedBackground`).
- Haptics: `UIImpactFeedbackGenerator` on check-offs and message sends; `UINotificationFeedbackGenerator(.success)` when all today's habits are done.
- No view models for the preview — views read stores directly via `AppState` in the environment. We'll introduce a view-model layer when the real backend lands (so async/error states have somewhere to live).
- Mock data uses a seeded RNG so the heatmap looks the same on every launch.

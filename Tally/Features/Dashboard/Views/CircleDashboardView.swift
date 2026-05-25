import SwiftUI
import CloudKit

struct CircleDashboardView: View {
    @Environment(\.tallyAccent) private var tallyAccent
    @Environment(AppState.self) private var appState
    @State private var showProfileSettings = false
    @State private var showAddTodayGoal = false

    #if DEBUG
    // Schema-seeding UI state. Wrapped in `#if DEBUG` so the whole mechanism
    // is compiled out of Release builds (TestFlight, App Store). Trigger:
    // 5-tap on the avatar in the header card.
    @State private var debugShowSeedConfirm = false
    @State private var debugSeedResult: String?
    @State private var debugSeedError: String?
    @State private var debugIsSeeding = false
    #endif

    /// Time-of-day greeting. Updated when the view recomputes.
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Hey"
        }
    }

    private var firstName: String {
        let full = appState.ownCloudProfile?.displayName ?? ""
        return full.split(separator: " ").first.map(String.init) ?? full
    }

    private var avatarSymbol: String {
        appState.ownCloudProfile?.avatarSymbol ?? "leaf"
    }

    /// My day-period goals dated to today's startOfDay.
    private var todayGoals: [Goal] {
        appState.personalStore.goals(
            for: appState.currentUserID,
            period: .day,
            periodStart: Date.now.startOfDay
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let err = appState.lastFriendRequestError {
                        FriendRequestErrorBanner(message: err)
                    }
                    if !appState.incomingFriendRequests.isEmpty {
                        FriendRequestsSection()
                    }
                    headerCard
                    todayGoalsCard

                    ForEach(appState.dashboardMembers) { member in
                        NavigationLink(value: member.userID) {
                            MemberRowView(member: member)
                        }
                        .buttonStyle(.plain)
                    }

                    if appState.personalStore.friends.isEmpty {
                        addFriendCard
                    }

                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(Color.tallyCanvas)
            .refreshable { await appState.refreshCircleData() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(Date.now, format: .dateTime.weekday(.wide).month().day())
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showProfileSettings = true
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                }
            }
            .navigationDestination(for: String.self) { userID in
                MemberDetailView(memberID: userID)
            }
            .sheet(isPresented: $showProfileSettings) {
                ProfileSettingsView()
            }
            .sheet(isPresented: $showAddTodayGoal) {
                AddGoalSheet(period: .day, periodStart: Date.now.startOfDay)
            }
            .alert(
                "Couldn't share",
                isPresented: Binding(
                    get: { appState.lastCloudShareError != nil },
                    set: { if !$0 { appState.lastCloudShareError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { appState.lastCloudShareError = nil }
            } message: {
                Text(appState.lastCloudShareError ?? "")
            }
            #if DEBUG
            .alert(
                "[DEBUG] Seed CloudKit schema?",
                isPresented: $debugShowSeedConfirm
            ) {
                Button("Cancel", role: .cancel) {}
                Button("Seed") { Task { await runDebugSeed() } }
            } message: {
                Text("Writes a FriendRequest record to the public DB so CloudKit auto-creates the schema. Then deploy dev → prod and mark toUserRecordName as Queryable.")
            }
            .alert(
                "Seed complete",
                isPresented: Binding(
                    get: { debugSeedResult != nil },
                    set: { if !$0 { debugSeedResult = nil } }
                )
            ) {
                Button("OK", role: .cancel) { debugSeedResult = nil }
            } message: {
                Text(debugSeedResult ?? "")
            }
            .alert(
                "Seed failed",
                isPresented: Binding(
                    get: { debugSeedError != nil },
                    set: { if !$0 { debugSeedError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { debugSeedError = nil }
            } message: {
                Text(debugSeedError ?? "")
            }
            #endif
        }
    }

    #if DEBUG
    private func runDebugSeed() async {
        debugIsSeeding = true
        defer { debugIsSeeding = false }
        do {
            let result = try await DebugSchemaSeeder.seed(appState: appState)
            print("[DebugSchemaSeeder] Seeded \(result.seededTypes.joined(separator: ", "))")
            for id in result.recordIDs {
                print("[DebugSchemaSeeder] Seed record: \(id)")
            }
            debugSeedResult = "Seeded: \(result.seededTypes.joined(separator: ", "))." +
                "\n\nRecord ID logged to console — search Xcode for [DebugSchemaSeeder]." +
                "\n\nNext: in CloudKit Dashboard → Development → Schema → Record Types → FriendRequest, mark `toUserRecordName` as Queryable (and Sortable). Then Deploy Schema Changes…"
        } catch {
            debugSeedError = error.localizedDescription
        }
    }
    #endif

    private var headerCard: some View {
        HStack(alignment: .center, spacing: 14) {
            avatarBadge
            VStack(alignment: .leading, spacing: 4) {
                Text("\(greeting),")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(firstName + ".")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }

    private var avatarBadge: some View {
        let view = Image(systemName: avatarSymbol)
            .font(.system(size: 26, weight: .medium))
            .frame(width: 64, height: 64)
            .foregroundStyle(tallyAccent)
            .background(tallyAccent.opacity(0.15))
            .clipShape(Circle())
        #if DEBUG
        return view
            .contentShape(Circle())
            .onTapGesture(count: 5) {
                debugShowSeedConfirm = true
            }
        #else
        return view
        #endif
    }

    /// Today-period goals card. Always visible: shows the goals if any, plus
    /// a "+" affordance to add one for today.
    private var todayGoalsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "flag")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tallyAccent)
                Text("Today's goals")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Spacer()
                Button {
                    showAddTodayGoal = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(tallyAccent)
                }
                .buttonStyle(.plain)
            }

            if todayGoals.isEmpty {
                Text("Nothing set for today yet — tap + to add one.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 8) {
                    ForEach(todayGoals) { goal in
                        TodayGoalRow(goal: goal)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.tallyCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// Empty-state card prompting the user to add their first friend. The
    /// "Add a friend" button mints their personal CKShare and opens the system
    /// invite sheet — accepting the link makes the two users mutual friends.
    private var addFriendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.title2)
                    .foregroundStyle(tallyAccent)
                Text("Bring your friends in")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
            }
            Text("Tally works best when you can see your friends' check-ins next to yours. Send an invite to add a friend.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                presentAddFriend()
            } label: {
                Text("Add a friend")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(tallyAccent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.tallyCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(tallyAccent.opacity(0.25), lineWidth: 1)
                )
        )
    }

    /// Mint-or-fetch my personal CKShare and present the system invite sheet.
    private func presentAddFriend() {
        let repo = appState.personalRepository
        CloudShareInvitePresenter.present {
            try await repo.makePersonalShare()
        }
    }
}

/// One row inside the dashboard's "Today's goals" card. Tappable checkbox +
/// strikethrough on completion.
private struct TodayGoalRow: View {
    @Environment(\.tallyAccent) private var tallyAccent
    @Environment(AppState.self) private var appState
    let goal: Goal

    private var isDone: Bool { goal.completedAt != nil }

    var body: some View {
        HStack(spacing: 10) {
            CheckboxButton(isChecked: isDone, isEditable: true) {
                appState.personalStore.toggleComplete(goal: goal)
            }
            Text(goal.title)
                .strikethrough(isDone, color: .secondary)
                .foregroundStyle(isDone ? .secondary : .primary)
                .lineLimit(2)
            Spacer()
        }
    }
}

#if DEBUG
/// DEBUG-only helper to coax CloudKit into auto-creating a record type's
/// schema by writing a sample record. Triggered by a 5-tap on the dashboard
/// avatar. Wrapped in `#if DEBUG` so the gesture, alerts, and this enum are
/// all compiled out of Release builds — TestFlight and App Store builds
/// can't reach it.
///
/// Currently seeds `FriendRequest`. Update when new record types are added
/// that need schema seeding before a prod deploy.
enum DebugSchemaSeeder {
    static let seedMarker = "[schema_seed_v1_DELETE_ME]"

    struct SeedResult {
        let seededTypes: [String]
        let recordIDs: [String]
    }

    @MainActor
    static func seed(appState: AppState) async throws -> SeedResult {
        let userID = appState.currentUserID
        guard !userID.isEmpty else {
            throw NSError(
                domain: "DebugSchemaSeeder",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No CloudKit user ID — sign into iCloud first."]
            )
        }

        // Seed FriendRequest: self → self with a placeholder share URL.
        // CloudKit doesn't validate the URL field, so a non-functional value
        // is fine — the goal is only schema creation.
        let req = FriendRequest(
            id: UUID(),
            fromUserRecordName: userID,
            toUserRecordName: userID,
            shareURL: "https://icloud.com/share/seed-placeholder",
            fromDisplayName: seedMarker,
            fromUsername: "seed",
            fromAvatarSymbol: "leaf",
            sentAt: .now,
            isReciprocal: false
        )
        try await appState.friendRequestRepository.send(req)

        return SeedResult(
            seededTypes: ["FriendRequest"],
            recordIDs: ["public / \(req.id.uuidString)"]
        )
    }
}
#endif

import SwiftUI
import CloudKit

/// "Today" tab. Premium-feeling dashboard: serif greeting, 7-dot streak
/// chain, habit cards with spring + haptics on toggle, conditional goals
/// section, and friend activity rows (or a subtle invite banner when the
/// user has no friends yet).
struct CircleDashboardView: View {
    @Environment(AppState.self) private var appState
    @State private var showProfileSettings = false
    @State private var showAddTodayGoal = false
    @State private var showFriendSearch = false
    /// Day the user is currently viewing on the Today tab. Defaults to today
    /// and changes when they tap a past dot in the streak chain — the rest
    /// of the page re-scopes to that day (habits + goals are read-only when
    /// not today).
    @State private var selectedDay: Date = Date.now.startOfDay

    #if DEBUG
    @State private var debugShowSeedConfirm = false
    @State private var debugSeedResult: String?
    @State private var debugSeedError: String?
    #endif

    // MARK: - Derived data

    private var today: Date { Date.now.startOfDay }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12:  return "Good morning,"
        case 12..<17: return "Good afternoon,"
        case 17..<22: return "Good evening,"
        default:      return "Hey,"
        }
    }

    private var firstName: String {
        let full = appState.ownCloudProfile?.displayName ?? ""
        return full.split(separator: " ").first.map(String.init) ?? full
    }

    private var myHabits: [Habit] {
        appState.personalStore.habits(for: appState.currentUserID)
    }

    /// Day-period goals dated to `selectedDay` for the signed-in user. When
    /// the user is on today (default) this is "today's goals"; when they've
    /// scrubbed to a past day via the streak chain, it's that day's goals.
    private var todayGoals: [Goal] {
        appState.personalStore.goals(
            for: appState.currentUserID,
            period: .day,
            periodStart: selectedDay
        )
    }

    /// True only when the user is viewing today (live state). Toggling
    /// completion is disabled in past-day views to avoid back-dating.
    private var isViewingToday: Bool {
        selectedDay == today
    }

    private var friends: [Friend] {
        appState.personalStore.friends
    }

    /// The 7 calendar days the streak chain renders, oldest first.
    private var streakDays: [Date] {
        (0..<7).map { Calendar.current.date(byAdding: .day, value: -(6 - $0), to: today) ?? today }
    }

    /// Set of startOfDay dates in the last 7 days where the user completed
    /// at least one habit. Used to fill the streak-chain dots.
    private var activeDayKeys: Set<Date> {
        let store = appState.personalStore
        var keys: Set<Date> = []
        for habit in myHabits {
            for date in store.completionDates(habit: habit) {
                keys.insert(date.startOfDay)
            }
        }
        return keys
    }

    /// Consecutive days backwards from today (or yesterday if today is
    /// empty) with ≥1 completion. Mirrors per-habit streak semantics so
    /// the streak doesn't visibly break the moment a new day starts.
    private var currentStreak: Int {
        let active = activeDayKeys
        var cursor = today
        if !active.contains(cursor) { cursor = cursor.adding(days: -1) }
        var n = 0
        while active.contains(cursor) {
            n += 1
            cursor = cursor.adding(days: -1)
        }
        return n
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    headerArea
                    streakSection
                    habitsSection
                    goalsSection
                    if friends.isEmpty {
                        inviteBanner
                    } else {
                        friendsSection
                    }
                    Color.clear.frame(height: 80)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .background(Color.tallyCanvas.ignoresSafeArea())
            .refreshable { await appState.refreshCircleData() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showProfileSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.body)
                            .foregroundStyle(Color.tallyTextSecondary)
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
                AddGoalSheet(period: .day, periodStart: today)
            }
            .sheet(isPresented: $showFriendSearch) {
                FriendSearchView()
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

    // MARK: - Sections

    /// Date line + greeting + serif name. No avatar — the user knows who
    /// they are and the space is better spent.
    private var headerArea: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Date label. DEBUG-only: five taps fire the schema seeder
            // (used to be on the avatar; the avatar's gone now).
            Group {
                let dateText = Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.tallyTextSecondary)
                #if DEBUG
                dateText
                    .contentShape(Rectangle())
                    .onTapGesture(count: 5) { debugShowSeedConfirm = true }
                #else
                dateText
                #endif
            }
            Text(greeting)
                .font(.system(size: 16))
                .foregroundStyle(Color.tallyTextSecondary)
                .padding(.top, 4)
            Text(firstName.isEmpty ? "Hello." : firstName + ".")
                .font(.system(.largeTitle, design: .serif, weight: .bold))
                .foregroundStyle(Color.tallyTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    /// 7-dot streak chain + streak count. Tapping a past or today dot
    /// scrubs `selectedDay` so the rest of the page (habits, goals) shows
    /// that day's state inline. Stays on the Today tab — no navigation push.
    /// Future dots stay non-interactive.
    private var streakSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                ForEach(streakDays, id: \.self) { day in
                    Button {
                        guard day.startOfDay <= today.startOfDay else { return }
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedDay = day.startOfDay
                        }
                        #if canImport(UIKit)
                        UISelectionFeedbackGenerator().selectionChanged()
                        #endif
                    } label: {
                        StreakDot(
                            day: day,
                            today: today,
                            isActive: activeDayKeys.contains(day.startOfDay),
                            isSelected: day.startOfDay == selectedDay
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(day.startOfDay > today.startOfDay)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                if currentStreak > 0 {
                    Text("\(currentStreak)-day streak")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.tallyStreak)
                }
                if !isViewingToday {
                    if currentStreak > 0 {
                        Text("·")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.tallyTextSecondary)
                    }
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedDay = today
                        }
                    } label: {
                        Text("Back to today")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.tallyAccent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
        }
    }

    /// Habit cards — the hero section. Header reads "Today" when on today,
    /// otherwise the scrubbed day's name so users know they're looking at
    /// historical state.
    private var habitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(habitsSectionTitle)
            if myHabits.isEmpty {
                emptyHabitsCard
            } else {
                VStack(spacing: 10) {
                    ForEach(myHabits) { habit in
                        HabitCard(
                            habit: habit,
                            date: selectedDay,
                            isEditable: isViewingToday
                        )
                    }
                }
            }
        }
    }

    private var habitsSectionTitle: String {
        if isViewingToday { return "Today" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: selectedDay)
    }

    private var emptyHabitsCard: some View {
        VStack(spacing: 12) {
            Text("Start a streak — add your first habit")
                .font(.system(size: 14).italic())
                .foregroundStyle(Color.tallyTextSecondary)
                .frame(maxWidth: .infinity)
            // We don't push the user into an in-context add flow here —
            // the Habits tab has the full editor. A nudge is enough.
        }
        .padding(.vertical, 24)
    }

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Goals".uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Color.tallyTextSecondary)
                Spacer()
                Button {
                    showAddTodayGoal = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.tallyTextSecondary)
                }
                .buttonStyle(.plain)
            }
            Rectangle()
                .fill(Color.tallyDivider)
                .frame(height: 1)
            if sortedTodayGoals.isEmpty {
                Button {
                    showAddTodayGoal = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.tallyTextSecondary)
                        Text("Add a goal for today")
                            .font(.system(size: 14).italic())
                            .foregroundStyle(Color.tallyTextSecondary)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 10) {
                    ForEach(sortedTodayGoals) { goal in
                        GoalRow(goal: goal)
                    }
                }
            }
        }
    }

    /// Completed goals sink to the bottom of the list.
    private var sortedTodayGoals: [Goal] {
        todayGoals.sorted { lhs, rhs in
            if (lhs.completedAt == nil) != (rhs.completedAt == nil) {
                return lhs.completedAt == nil
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Your friends")
            VStack(spacing: 0) {
                ForEach(Array(sortedFriends.enumerated()), id: \.element.userID) { idx, friend in
                    NavigationLink(value: friend.userID) {
                        FriendActivityRow(friend: friend)
                    }
                    .buttonStyle(.plain)
                    if idx < sortedFriends.count - 1 {
                        Divider()
                            .background(Color.tallyDivider)
                    }
                }
            }
        }
    }

    /// Most recently active friends first. "Recent" = latest completion
    /// timestamp across all their habits; friends with no completions
    /// today fall to the bottom.
    private var sortedFriends: [Friend] {
        friends.sorted { a, b in
            let aLast = latestCompletion(for: a) ?? .distantPast
            let bLast = latestCompletion(for: b) ?? .distantPast
            return aLast > bLast
        }
    }

    private func latestCompletion(for friend: Friend) -> Date? {
        let store = appState.personalStore
        var latest: Date?
        for habit in store.habits(for: friend.userID) {
            for date in store.completionDates(habit: habit) {
                if latest == nil || date > latest! { latest = date }
            }
        }
        return latest
    }

    private var inviteBanner: some View {
        Button {
            showFriendSearch = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.tallyTextSecondary)
                Text("Add a friend to keep each other accountable")
                    .font(.system(size: 14).italic())
                    .foregroundStyle(Color.tallyTextSecondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.tallyTextSecondary)
            }
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    /// Standard section header — uppercase small-caps, semibold, 13pt,
    /// textSecondary, with a hairline beneath.
    private func sectionHeader(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Color.tallyTextSecondary)
            Rectangle()
                .fill(Color.tallyDivider)
                .frame(height: 1)
        }
    }

    #if DEBUG
    private func runDebugSeed() async {
        do {
            let result = try await DebugSchemaSeeder.seed(appState: appState)
            print("[DebugSchemaSeeder] Seeded \(result.seededTypes.joined(separator: ", "))")
            for id in result.recordIDs {
                print("[DebugSchemaSeeder] Seed record: \(id)")
            }
            debugSeedResult = "Seeded: \(result.seededTypes.joined(separator: ", "))." +
                "\n\nNext: in CloudKit Dashboard → Development → Schema → Record Types → FriendRequest, mark `toUserRecordName` as Queryable (and Sortable). Then Deploy Schema Changes…"
        } catch {
            debugSeedError = error.localizedDescription
        }
    }
    #endif
}

// MARK: - StreakDot

/// One of the 7 circles in the streak chain. Past + active = filled. Today
/// + not active = outlined and pulsing. Future = ghosted. When `isSelected`
/// is true (the user has scrubbed to this day) the dot gets a halo ring
/// so they can see what they're looking at.
private struct StreakDot: View {
    let day: Date
    let today: Date
    let isActive: Bool
    let isSelected: Bool

    /// Day-of-week initial below the dot (M, T, W, T, F, S, S).
    private var initial: String {
        let f = DateFormatter()
        f.dateFormat = "EEEEE" // single-letter day
        return f.string(from: day)
    }

    private var isToday: Bool { day.startOfDay == today.startOfDay }
    private var isPast: Bool { day.startOfDay < today.startOfDay }
    private var isFuture: Bool { day.startOfDay > today.startOfDay }

    @State private var pulse: Bool = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if isFuture {
                    Circle()
                        .stroke(Color.tallyTextSecondary.opacity(0.20), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                } else if isToday && !isActive {
                    Circle()
                        .stroke(Color.tallyAccent, lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                        .opacity(pulse ? 1.0 : 0.4)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                                pulse = true
                            }
                        }
                } else if isActive {
                    Circle()
                        .fill(Color.tallyAccent)
                        .frame(width: 20, height: 20)
                } else { // missed past day
                    Circle()
                        .stroke(Color.tallyTextSecondary.opacity(0.30), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                }
            }
            // Halo for the scrubbed-to day.
            .overlay(
                Group {
                    if isSelected {
                        Circle()
                            .stroke(Color.tallyAccent.opacity(0.5), lineWidth: 1)
                            .frame(width: 28, height: 28)
                    }
                }
            )
            Text(initial)
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.tallyTextPrimary : Color.tallyTextSecondary)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - HabitCard

/// Full-width habit card with spring + haptic on toggle. Scoped to `date`
/// so the same card renders historical state when the user scrubs the
/// streak chain to a past day. Toggling is gated by `isEditable` to
/// prevent back-dating completions.
private struct HabitCard: View {
    @Environment(AppState.self) private var appState
    let habit: Habit
    let date: Date
    let isEditable: Bool

    private var isDone: Bool {
        appState.personalStore.isCompleted(habit: habit, on: date)
    }

    var body: some View {
        HStack(spacing: 14) {
            Text(habit.title)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.tallyTextPrimary)
                .lineLimit(2)
            Spacer()
            checkbox
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 72)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isDone
                      ? Color.tallyCompleted.opacity(0.08)
                      : Color.tallyCard)
        )
        .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
        .opacity(isEditable ? 1.0 : 0.85)
        .contentShape(Rectangle())
        .onTapGesture { if isEditable { toggle() } }
    }

    private var checkbox: some View {
        ZStack {
            Circle()
                .stroke(Color.tallyAccent, lineWidth: 2)
                .frame(width: 28, height: 28)
            Circle()
                .fill(Color.tallyAccent)
                .frame(width: 28, height: 28)
                .scaleEffect(isDone ? 1 : 0)
                .opacity(isDone ? 1 : 0)
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .scaleEffect(isDone ? 1 : 0)
                .opacity(isDone ? 1 : 0)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isDone)
    }

    private func toggle() {
        let willComplete = !isDone
        #if canImport(UIKit)
        let style: UIImpactFeedbackGenerator.FeedbackStyle = willComplete ? .medium : .light
        UIImpactFeedbackGenerator(style: style).impactOccurred()
        #endif
        _ = appState.personalStore.toggle(habit: habit, on: date)
    }
}

// MARK: - GoalRow

private struct GoalRow: View {
    @Environment(AppState.self) private var appState
    let goal: Goal

    private var isDone: Bool { goal.completedAt != nil }

    var body: some View {
        HStack(spacing: 12) {
            checkbox
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.title)
                    .font(.system(size: 15))
                    .strikethrough(isDone, color: Color.tallyTextSecondary)
                    .foregroundStyle(isDone ? Color.tallyTextSecondary : Color.tallyTextPrimary)
                    .lineLimit(2)
                Text("Due today")
                    .font(.system(size: 12))
                    .foregroundStyle(isDone ? Color.tallyTextSecondary : Color.tallyAccent)
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { appState.personalStore.toggleComplete(goal: goal) }
    }

    private var checkbox: some View {
        ZStack {
            Circle()
                .stroke(Color.tallyAccent, lineWidth: 1.5)
                .frame(width: 22, height: 22)
            Circle()
                .fill(Color.tallyAccent)
                .frame(width: 22, height: 22)
                .scaleEffect(isDone ? 1 : 0)
                .opacity(isDone ? 1 : 0)
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .scaleEffect(isDone ? 1 : 0)
                .opacity(isDone ? 1 : 0)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isDone)
    }
}

// MARK: - FriendActivityRow

private struct FriendActivityRow: View {
    @Environment(AppState.self) private var appState
    let friend: Friend

    private var habits: [Habit] {
        appState.personalStore.habits(for: friend.userID)
    }

    private var doneToday: Int {
        habits.filter { appState.personalStore.isCompleted(habit: $0, on: .now) }.count
    }

    private var statusText: String {
        let total = habits.count
        guard total > 0 else { return "No habits yet" }
        if doneToday == 0 { return "Not started today" }
        if doneToday == total { return "All done today ✓" }
        return "\(doneToday) of \(total) today"
    }

    private var statusColor: Color {
        (habits.isEmpty == false && doneToday == habits.count)
            ? Color.tallyAccent
            : Color.tallyTextSecondary
    }

    /// Latest completion timestamp today, formatted as relative ("2h ago").
    private var relativeRecentLabel: String? {
        let dayStart = Date.now.startOfDay
        let store = appState.personalStore
        var latest: Date?
        for habit in habits {
            for date in store.completionDates(habit: habit) where date >= dayStart {
                if latest == nil || date > latest! { latest = date }
            }
        }
        guard let latest else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: latest, relativeTo: .now)
    }

    private var streakCount: Int {
        var max = 0
        for habit in habits {
            let s = StreakCalculator.currentStreak(
                completions: appState.personalStore.completionDates(habit: habit),
                habitCreatedAt: habit.createdAt
            )
            if s > max { max = s }
        }
        return max
    }

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(
                symbolName: friend.avatarSymbol,
                imageData: friend.avatarImageData,
                size: 32
            )
            .overlay(
                Circle().stroke(Color.tallyAccent.opacity(0.30), lineWidth: 1)
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.tallyTextPrimary)
                HStack(spacing: 4) {
                    Text(statusText)
                        .foregroundStyle(statusColor)
                    if let recent = relativeRecentLabel {
                        Text("· \(recent)")
                            .foregroundStyle(Color.tallyTextSecondary)
                    }
                }
                .font(.system(size: 13))
            }
            Spacer()
            if streakCount > 0 {
                HStack(spacing: 3) {
                    Text("\(streakCount)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.tallyTextPrimary)
                    Image(systemName: "flame.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.tallyAccent)
                }
            }
        }
        .padding(.vertical, 12)
    }
}

#if DEBUG
/// DEBUG-only helper to coax CloudKit into auto-creating a record type's
/// schema by writing a sample record. Triggered by 5-tap on the dashboard
/// date label.
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

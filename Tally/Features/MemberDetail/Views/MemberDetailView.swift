import SwiftUI

struct MemberDetailView: View {
    @Environment(\.tallyAccent) private var tallyAccent
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let memberID: String

    @State private var dmCircle: TallyCircle?
    @State private var isOpeningDM = false
    @State private var dmError: String?
    @State private var showUnfriendConfirm = false
    @State private var isUnfriending = false
    @State private var unfriendError: String?

    private var member: Friend? {
        appState.member(for: memberID)
    }

    private var isMe: Bool { memberID == appState.currentUserID }

    private var isFriend: Bool {
        appState.personalStore.friends.contains { $0.userID == memberID }
    }

    private var canDM: Bool { !isMe && isFriend }
    private var canUnfriend: Bool { !isMe && isFriend }

    private var habits: [Habit] {
        appState.personalStore.habits(for: memberID)
    }

    /// Today's day-period goals (their "to-do today" list) for the member.
    /// Surfacing this on the profile lets the user see what their friend
    /// is working on right now and tap Message to encourage them
    /// specifically.
    private var todayGoals: [Goal] {
        appState.personalStore.goals(
            for: memberID,
            period: .day,
            periodStart: Date.now.startOfDay
        )
    }

    private var goals: [Goal] {
        appState.personalStore.goals(
            for: memberID,
            period: .week,
            periodStart: WeekCalculator.weekStart(for: .now)
        )
    }

    var body: some View {
        Group {
            if let member {
                ScrollView {
                    VStack(spacing: 16) {
                        header(member)

                        section(title: "Today's habits") {
                            if habits.isEmpty {
                                infoCard("No habits yet")
                            } else {
                                ForEach(habits) { habit in
                                    MemberHabitRow(habit: habit, isEditable: isMe)
                                }
                            }
                        }

                        section(title: "Today's to-dos") {
                            if todayGoals.isEmpty {
                                infoCard("Nothing on the list today")
                            } else {
                                ForEach(todayGoals) { goal in
                                    todayGoalRow(goal)
                                }
                            }
                        }

                        section(title: "This week's goals") {
                            if goals.isEmpty {
                                infoCard("No goals set this week")
                            } else {
                                ForEach(goals) { goal in
                                    HStack(spacing: 12) {
                                        Image(systemName: goal.completedAt != nil
                                              ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(goal.completedAt != nil
                                                             ? tallyAccent : .secondary)
                                        Text(goal.title)
                                            .strikethrough(goal.completedAt != nil, color: .secondary)
                                            .foregroundStyle(goal.completedAt != nil
                                                             ? .secondary : .primary)
                                        Spacer()
                                    }
                                    .padding(14)
                                    .background(Color.tallyCard)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                }
                            }
                        }

                        if canDM {
                            messageButton
                        }

                        NavigationLink {
                            HistoryCalendarView(targetUserID: memberID)
                        } label: {
                            actionCard(icon: "calendar", text: "View history", filled: false)
                        }

                        if canUnfriend {
                            unfriendButton
                        }

                        Spacer().frame(height: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                .background(Color.tallyCanvas)
                .navigationTitle(member.displayName)
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(item: $dmCircle) { circle in
                    GroupChatHost(circle: circle)
                }
                .alert(
                    "Couldn't open message",
                    isPresented: Binding(
                        get: { dmError != nil },
                        set: { if !$0 { dmError = nil } }
                    )
                ) {
                    Button("OK", role: .cancel) { dmError = nil }
                } message: {
                    Text(dmError ?? "")
                }
                .confirmationDialog(
                    "Unfriend \(member.displayName)?",
                    isPresented: $showUnfriendConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Unfriend", role: .destructive) { performUnfriend() }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("\(member.displayName) will lose access to your habits and goals, and you'll lose access to theirs. They'll drop off both friend lists on the next refresh.")
                }
                .alert(
                    "Couldn't unfriend",
                    isPresented: Binding(
                        get: { unfriendError != nil },
                        set: { if !$0 { unfriendError = nil } }
                    )
                ) {
                    Button("OK", role: .cancel) { unfriendError = nil }
                } message: {
                    Text(unfriendError ?? "")
                }
            } else {
                EmptyStateView(icon: "person.fill.questionmark", title: "Member not found", message: "")
            }
        }
    }

    // MARK: Subviews

    private func header(_ member: Friend) -> some View {
        HStack(spacing: 16) {
            AvatarView(
                symbolName: member.avatarSymbol,
                imageData: member.avatarImageData,
                size: 72
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(member.displayName)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
            }
            Spacer()
        }
        .padding(16)
        .background(Color.tallyCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    /// One row in the friend's "Today's to-dos" section. Read-only: the
    /// viewer (me) can't toggle someone else's goals, so this just
    /// renders state with strikethrough on completion.
    private func todayGoalRow(_ goal: Goal) -> some View {
        let isDone = goal.completedAt != nil
        return HStack(spacing: 12) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isDone ? tallyAccent : .secondary)
            Text(goal.title)
                .strikethrough(isDone, color: .secondary)
                .foregroundStyle(isDone ? .secondary : .primary)
            Spacer()
        }
        .padding(14)
        .background(Color.tallyCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func infoCard(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.tallyCard)
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func actionCard(icon: String, text: String, filled: Bool) -> some View {
        HStack {
            Image(systemName: icon)
            Text(text)
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(filled ? Color.white.opacity(0.7) : Color.secondary.opacity(0.5))
        }
        .font(.body.weight(filled ? .semibold : .regular))
        .padding(14)
        .background(filled ? tallyAccent : Color.tallyCard)
        .foregroundStyle(filled ? .white : .primary)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var messageButton: some View {
        Button {
            openDM()
        } label: {
            HStack {
                Image(systemName: "bubble.left.fill")
                Text(isOpeningDM ? "Opening…" : "Message")
                Spacer()
                if isOpeningDM {
                    ProgressView().tint(Color.tallyOnAccent)
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color.white.opacity(0.7))
                }
            }
            .font(.body.weight(.semibold))
            .padding(14)
            .background(tallyAccent)
            .foregroundStyle(Color.tallyOnAccent)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(isOpeningDM)
    }

    private var unfriendButton: some View {
        Button(role: .destructive) {
            showUnfriendConfirm = true
        } label: {
            HStack {
                Image(systemName: "person.badge.minus")
                Text(isUnfriending ? "Unfriending…" : "Unfriend")
                Spacer()
                if isUnfriending {
                    ProgressView()
                }
            }
            .font(.body.weight(.medium))
            .padding(14)
            .background(Color.tallyCard)
            .foregroundStyle(Color.tallyDestructive)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(isUnfriending)
    }

    private func performUnfriend() {
        guard let member, !isUnfriending else { return }
        // Capture the target FIRST so we can dismiss before any state
        // mutation happens. Previous flow awaited unfriend (which
        // mutates personalStore.friends mid-call), then dismissed; that
        // forced SwiftUI to re-render MemberDetailView with member==nil
        // (switching to the "Member not found" branch) immediately
        // before the nav pop, which crashed under iOS 26's navigation
        // stack. Popping the view first avoids that re-render entirely.
        let target = member
        isUnfriending = true
        dismiss()
        Task {
            do {
                try await appState.unfriend(target)
            } catch {
                // The view is already gone — surface via a global app
                // error field so the friends list can flag it on its
                // next refresh instead of trying to alert from a popped
                // controller.
                NSLog("[Tally] unfriend failed after dismiss: \(error.localizedDescription)")
                appState.lastUnfriendError = error.localizedDescription
            }
        }
    }

    private func openDM() {
        guard let member, !isOpeningDM else { return }
        isOpeningDM = true
        Task {
            defer { isOpeningDM = false }
            do {
                let circle = try await appState.openOrCreateDM(with: member)
                // Activate the DM on CircleStore BEFORE pushing navigation, so
                // the chat view renders with the right circle's content (title
                // + feed) immediately instead of briefly flashing the
                // previously-active Circle (e.g., a Group chat the user was
                // last in) while the activate roundtrip is in flight.
                await appState.activateCircle(circle)
                dmCircle = circle
            } catch {
                dmError = error.localizedDescription
            }
        }
    }
}

private struct MemberHabitRow: View {
    @Environment(\.tallyAccent) private var tallyAccent
    @Environment(AppState.self) private var appState
    let habit: Habit
    let isEditable: Bool

    private var isDone: Bool {
        appState.personalStore.isCompleted(habit: habit, on: .now)
    }

    private var streak: Int {
        StreakCalculator.currentStreak(
            completions: appState.personalStore.completionDates(habit: habit),
            habitCreatedAt: habit.createdAt
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            CheckboxButton(isChecked: isDone, isEditable: isEditable) {
                _ = appState.personalStore.toggle(habit: habit, on: .now)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.title).font(.body.weight(.medium))
                if streak > 0 {
                    Label("\(streak)-day streak", systemImage: "flame.fill")
                        .symbolRenderingMode(.monochrome)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(tallyAccent)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(Color.tallyCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

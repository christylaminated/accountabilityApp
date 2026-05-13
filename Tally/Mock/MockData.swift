import Foundation

/// Seed data for the mock UI preview. Two users, one circle, a few weeks of habit history,
/// goals (current week + last week), and sample feed/DM threads.
enum MockData {
    // Fixed UUIDs so identity stays stable across launches.
    static let christyID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let jeffID    = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    static let circleID  = UUID(uuidString: "00000000-0000-0000-0000-000000001000")!

    static let profiles: [Profile] = [
        Profile(id: christyID, username: "christy", displayName: "Christy",
                avatarEmoji: "🌿", createdAt: .now.adding(days: -60)),
        Profile(id: jeffID, username: "jeff", displayName: "Jeff",
                avatarEmoji: "☕", createdAt: .now.adding(days: -45))
    ]

    static let circle = TallyCircle(
        id: circleID,
        name: "Inner Circle",
        emoji: "✨",
        ownerID: christyID,
        createdAt: .now.adding(days: -45)
    )

    static let members: [CircleMember] = [
        CircleMember(circleID: circleID, userID: christyID, role: .owner,
                     joinedAt: .now.adding(days: -45)),
        CircleMember(circleID: circleID, userID: jeffID,    role: .member,
                     joinedAt: .now.adding(days: -30))
    ]

    static let christyHabits: [Habit] = [
        Habit(id: UUID(), userID: christyID, title: "Morning yoga",
              createdAt: .now.adding(days: -40), archivedAt: nil),
        Habit(id: UUID(), userID: christyID, title: "Read 30 min",
              createdAt: .now.adding(days: -40), archivedAt: nil),
        Habit(id: UUID(), userID: christyID, title: "No phone before 9am",
              createdAt: .now.adding(days: -30), archivedAt: nil),
        Habit(id: UUID(), userID: christyID, title: "Drink 2L water",
              createdAt: .now.adding(days: -25), archivedAt: nil),
        Habit(id: UUID(), userID: christyID, title: "Journal",
              createdAt: .now.adding(days: -20), archivedAt: nil)
    ]

    static let jeffHabits: [Habit] = [
        Habit(id: UUID(), userID: jeffID, title: "Lift weights",
              createdAt: .now.adding(days: -30), archivedAt: nil),
        Habit(id: UUID(), userID: jeffID, title: "Spanish (15 min)",
              createdAt: .now.adding(days: -28), archivedAt: nil),
        Habit(id: UUID(), userID: jeffID, title: "Walk the dog",
              createdAt: .now.adding(days: -28), archivedAt: nil),
        Habit(id: UUID(), userID: jeffID, title: "Meditate",
              createdAt: .now.adding(days: -14), archivedAt: nil)
    ]

    static let allHabits: [Habit] = christyHabits + jeffHabits

    /// Procedurally seeded completion history. Probability varies per habit so the
    /// heatmap and streaks look interesting in the calendar view.
    static let completions: [HabitCompletion] = {
        var result: [HabitCompletion] = []
        let today = Date.now.startOfDay

        func seed(habit: Habit, probability: Double, seed: UInt64) {
            var rng = SeededGenerator(seed: seed)
            var day = habit.createdAt.startOfDay
            while day <= today {
                let r = Double(rng.next()) / Double(UInt64.max)
                if r < probability {
                    result.append(HabitCompletion(
                        id: UUID(),
                        habitID: habit.id,
                        userID: habit.userID,
                        completedDate: day,
                        createdAt: day
                    ))
                }
                day = day.adding(days: 1)
            }
        }

        // Christy — generally consistent, varies by habit
        seed(habit: christyHabits[0], probability: 0.88, seed: 11)
        seed(habit: christyHabits[1], probability: 0.65, seed: 22)
        seed(habit: christyHabits[2], probability: 0.55, seed: 33)
        seed(habit: christyHabits[3], probability: 0.78, seed: 44)
        seed(habit: christyHabits[4], probability: 0.72, seed: 55)

        // Jeff — also varied
        seed(habit: jeffHabits[0], probability: 0.62, seed: 66)
        seed(habit: jeffHabits[1], probability: 0.50, seed: 77)
        seed(habit: jeffHabits[2], probability: 0.90, seed: 88)
        seed(habit: jeffHabits[3], probability: 0.42, seed: 99)

        return result
    }()

    static let goals: [WeeklyGoal] = {
        let currentWeek = WeekCalculator.weekStart(for: .now)
        let lastWeek = currentWeek.adding(days: -7)
        return [
            WeeklyGoal(id: UUID(), userID: christyID,
                       title: "Finish 'Atomic Habits'",
                       weekStartDate: currentWeek, completedAt: nil,
                       carriedFromID: nil, createdAt: currentWeek),
            WeeklyGoal(id: UUID(), userID: christyID,
                       title: "Send the recipe to Mom",
                       weekStartDate: currentWeek,
                       completedAt: .now.adding(days: -1),
                       carriedFromID: nil, createdAt: currentWeek),
            WeeklyGoal(id: UUID(), userID: christyID,
                       title: "Plan weekend hike",
                       weekStartDate: currentWeek, completedAt: nil,
                       carriedFromID: nil, createdAt: currentWeek),
            // Last week — unfinished, available to carry over
            WeeklyGoal(id: UUID(), userID: christyID,
                       title: "Call dentist",
                       weekStartDate: lastWeek, completedAt: nil,
                       carriedFromID: nil, createdAt: lastWeek),

            WeeklyGoal(id: UUID(), userID: jeffID,
                       title: "Sign up for the 10k",
                       weekStartDate: currentWeek,
                       completedAt: .now.adding(days: -2),
                       carriedFromID: nil, createdAt: currentWeek),
            WeeklyGoal(id: UUID(), userID: jeffID,
                       title: "Cook 3 dinners at home",
                       weekStartDate: currentWeek, completedAt: nil,
                       carriedFromID: nil, createdAt: currentWeek)
        ]
    }()

    static let circleMessages: [CircleMessage] = {
        let now = Date.now
        return [
            CircleMessage(id: UUID(), circleID: circleID, senderID: jeffID,
                          body: "Morning! Anyone else find it hard to get up today?",
                          createdAt: now.adding(days: -2).adding(hours: -3)),
            CircleMessage(id: UUID(), circleID: circleID, senderID: christyID,
                          body: "Yes 😅 but yoga done",
                          createdAt: now.adding(days: -2).adding(hours: -2)),
            CircleMessage(id: UUID(), circleID: circleID, senderID: jeffID,
                          body: "Respect. Got the morning walk in.",
                          createdAt: now.adding(days: -2).adding(hours: -2)),
            CircleMessage(id: UUID(), circleID: circleID, senderID: christyID,
                          body: "Big week ahead — pushing the reading streak.",
                          createdAt: now.adding(days: -1).adding(hours: -8)),
            CircleMessage(id: UUID(), circleID: circleID, senderID: jeffID,
                          body: "Let's go! Signing up for the 10k today.",
                          createdAt: now.adding(days: -1).adding(hours: -6)),
            CircleMessage(id: UUID(), circleID: circleID, senderID: christyID,
                          body: "🔥🔥🔥",
                          createdAt: now.adding(days: -1).adding(hours: -6)),
            CircleMessage(id: UUID(), circleID: circleID, senderID: jeffID,
                          body: "Journal done today. Streak intact.",
                          createdAt: now.adding(hours: -4))
        ]
    }()

    static let directMessages: [DirectMessage] = {
        let now = Date.now
        return [
            DirectMessage(id: UUID(), circleID: circleID,
                          senderID: jeffID, recipientID: christyID,
                          body: "Hey, still on for the hike Sunday?",
                          createdAt: now.adding(days: -1).adding(hours: -10),
                          readAt: now.adding(days: -1).adding(hours: -9)),
            DirectMessage(id: UUID(), circleID: circleID,
                          senderID: christyID, recipientID: jeffID,
                          body: "Yes! What time?",
                          createdAt: now.adding(days: -1).adding(hours: -9),
                          readAt: now.adding(days: -1).adding(hours: -9)),
            DirectMessage(id: UUID(), circleID: circleID,
                          senderID: jeffID, recipientID: christyID,
                          body: "8am at the trailhead?",
                          createdAt: now.adding(days: -1).adding(hours: -8),
                          readAt: now.adding(days: -1).adding(hours: -8)),
            DirectMessage(id: UUID(), circleID: circleID,
                          senderID: christyID, recipientID: jeffID,
                          body: "Perfect. Bringing coffee.",
                          createdAt: now.adding(days: -1).adding(hours: -8),
                          readAt: nil),
            DirectMessage(id: UUID(), circleID: circleID,
                          senderID: jeffID, recipientID: christyID,
                          body: "You're the best 🙏",
                          createdAt: now.adding(hours: -2),
                          readAt: nil)
        ]
    }()
}

/// Tiny deterministic RNG so the seeded heatmap is reproducible across launches.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 0xdeadbeef : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

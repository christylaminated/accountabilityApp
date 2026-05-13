import Foundation

/// Bare-minimum seed for the local mock layer. After the CloudKit pivot, this no
/// longer contains pre-baked habits / goals / messages — the user enters their
/// own during onboarding. We keep a single profile + circle + membership so the
/// existing UI has a `currentUserID` and `activeCircleID` to read from until
/// CK Step 3 lands real Circles.
///
/// The mock profile's displayName + avatarEmoji are overwritten with whatever
/// the user picks in `ProfileSetupView`, so the dashboard always reflects them.
enum MockData {
    /// Stable identifier for the local user inside the mock layer. Bridged to the
    /// real CloudKit identity in AppState (this stays UUID-typed for now to keep
    /// the mock stores compiling; the UUID→String refactor lands in CK Step 3a).
    static let christyID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let circleID  = UUID(uuidString: "00000000-0000-0000-0000-000000001000")!

    /// Placeholder profile — fields get overwritten when the user finishes
    /// `ProfileSetupView`. Treat the seeded values as defaults that never ship.
    static let profiles: [Profile] = [
        Profile(
            id: christyID,
            username: "you",
            displayName: "You",
            avatarSymbol: "leaf",
            createdAt: .now
        )
    ]

    static let circle = TallyCircle(
        id: circleID,
        name: "Your Circle",
        emoji: "✨",
        ownerID: christyID,
        createdAt: .now
    )

    static let members: [CircleMember] = [
        CircleMember(
            circleID: circleID,
            userID: christyID,
            role: .owner,
            joinedAt: .now
        )
    ]

    // Everything below starts empty. Habits / goals / messages get added by the
    // user during onboarding and through the in-app add flows.

    static let allHabits: [Habit] = []
    static let completions: [HabitCompletion] = []
    static let goals: [WeeklyGoal] = []
    static let circleMessages: [CircleMessage] = []
    static let directMessages: [DirectMessage] = []
}

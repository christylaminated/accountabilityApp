import Foundation

enum Constants {
    /// Hard cap on Circle membership. Mirrored in `CKShare.participantLimit`
    /// when invites are generated. Change here to bump the cap app-wide.
    static let maxCircleMembers: Int = 5

    /// The app's CloudKit container identifier. Matches the iCloud entitlement.
    static let cloudKitContainerID = "iCloud.com.christylam.tally"

    /// Client-side cap on the friend graph — how many participants we'll add to
    /// a user's personal CKShare before refusing. CloudKit's hard ceiling is
    /// ~100; this is a comfortable margin below it. Easy to bump if needed.
    static let maxPersonalShareParticipants: Int = 50
}

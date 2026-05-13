import Foundation

enum Constants {
    /// Hard cap on Circle membership. Mirrored in `CKShare.participantLimit`
    /// when invites are generated. Change here to bump the cap app-wide.
    static let maxCircleMembers: Int = 5

    /// The app's CloudKit container identifier. Matches the iCloud entitlement.
    static let cloudKitContainerID = "iCloud.com.christylam.tally"
}

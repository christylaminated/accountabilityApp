import SwiftUI
import CloudKit

struct CircleDashboardView: View {
    @Environment(AppState.self) private var appState
    @State private var manageCircle: TallyCircle?

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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard

                    ForEach(appState.circleStore.orderedMembers) { member in
                        NavigationLink(value: member.userID) {
                            MemberRowView(member: member)
                        }
                        .buttonStyle(.plain)
                    }

                    if appState.circleStore.otherMembers.isEmpty {
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
            }
            .navigationDestination(for: String.self) { userID in
                MemberDetailView(memberID: userID)
            }
            .toolbar {
                if let circle = appState.activeCircle {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            manageCircle = circle
                        } label: {
                            Image(systemName: "person.2")
                        }
                    }
                }
            }
            .sheet(item: $manageCircle) { circle in
                CircleSettingsView(circle: circle)
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
        }
    }

    private var headerCard: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: avatarSymbol)
                .font(.system(size: 26, weight: .medium))
                .frame(width: 64, height: 64)
                .foregroundStyle(Color.tallyAccent)
                .background(Color.tallyAccent.opacity(0.15))
                .clipShape(Circle())
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

    /// Empty-state card prompting the user to add their first friend. The
    /// "Add a friend" button mints their personal CKShare and opens the system
    /// invite sheet — accepting the link makes the two users mutual friends.
    private var addFriendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.title2)
                    .foregroundStyle(Color.tallyAccent)
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
                    .background(Color.tallyAccent)
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
                        .strokeBorder(Color.tallyAccent.opacity(0.25), lineWidth: 1)
                )
        )
    }

    /// Mint-or-fetch my personal CKShare and present the system invite sheet.
    /// Whoever accepts the link becomes my friend (and reciprocally I become
    /// theirs when their app processes the accept).
    private func presentAddFriend() {
        let repo = appState.personalRepository
        CloudShareInvitePresenter.present {
            try await repo.makePersonalShare()
        }
    }
}

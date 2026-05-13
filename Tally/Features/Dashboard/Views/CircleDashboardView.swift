import SwiftUI

struct CircleDashboardView: View {
    @Environment(AppState.self) private var appState

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
        let full = appState.currentProfile.displayName
        return full.split(separator: " ").first.map(String.init) ?? full
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard

                    ForEach(appState.memberProfiles) { profile in
                        NavigationLink(value: profile.id) {
                            MemberRowView(profile: profile)
                        }
                        .buttonStyle(.plain)
                    }

                    if appState.otherMembers.isEmpty {
                        invitePartnerCard
                    }

                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(Color.tallyCanvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(Date.now, format: .dateTime.weekday(.wide).month().day())
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .navigationDestination(for: UUID.self) { userID in
                MemberDetailView(memberID: userID)
            }
        }
    }

    private var headerCard: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: appState.currentProfile.avatarSymbol)
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

    private var invitePartnerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.title2)
                    .foregroundStyle(Color.tallyAccent)
                Text("Bring your partner in")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
            }
            Text("Tally works best when you can see someone else's check-ins next to yours. Send an invite to start a Circle.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                // Wired up in CK Step 3 (InviteSheetView).
            } label: {
                Text("Invite a friend")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.tallyAccent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(true)
            .opacity(0.85)
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
}

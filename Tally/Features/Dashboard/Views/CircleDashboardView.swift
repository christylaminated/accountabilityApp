import SwiftUI

struct CircleDashboardView: View {
    @Environment(AppState.self) private var appState

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
                    Spacer().frame(height: 16)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
            .background(Color.tallyCanvas)
            .navigationTitle(appState.activeCircle.name)
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: UUID.self) { userID in
                MemberDetailView(memberID: userID)
            }
        }
    }

    private var headerCard: some View {
        HStack(spacing: 12) {
            Text(appState.activeCircle.emoji ?? "✨")
                .font(.system(size: 32))
            VStack(alignment: .leading, spacing: 2) {
                Text("Today")
                    .font(.headline)
                Text(Date.now, format: .dateTime.weekday(.wide).month().day())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(appState.memberProfiles.count)/\(Constants.maxCircleMembers)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.tallyDivider.opacity(0.3))
                .clipShape(Capsule())
        }
        .padding(16)
        .background(Color.tallyCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

import SwiftUI

/// Screen 3 of the paywalled onboarding flow — first goal (skippable).
///
/// Lets the user add one weekly or monthly goal. Saved immediately via
/// `AppState.completeFirstGoalEntry` (which writes a real Goal record),
/// or `skipFirstGoalEntry` if they tap Skip. Either path advances to
/// `.leaderboardPreview`.
struct FirstGoalView: View {
    @Environment(AppState.self) private var appState

    @State private var title: String = ""
    @State private var period: GoalPeriod = .week

    private var displayName: String {
        appState.ownCloudProfile?.displayName ?? ""
    }

    private var trimmed: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool { !trimmed.isEmpty && trimmed.count <= 100 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                fields
                Spacer().frame(height: 8)
                actions
                Spacer().frame(height: 24)
            }
            .padding(.horizontal, 24)
            .padding(.top, 72)
        }
        .background(Color.tallyCanvas)
        .scrollDismissesKeyboard(.interactively)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What's a weekly or monthly goal, \(displayName)?")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(Color.tallyTextPrimary)
            Text("Something concrete you'd like to hit — you can add more later.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.tallyTextSecondary)
        }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("e.g. Run 3 times this week", text: $title, axis: .vertical)
                .lineLimit(1...3)
                .padding(14)
                .background(Color.tallyCard)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Picker("Period", selection: $period) {
                Text("Weekly").tag(GoalPeriod.week)
                Text("Monthly").tag(GoalPeriod.month)
            }
            .pickerStyle(.segmented)
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                guard isValid else { return }
                appState.completeFirstGoalEntry(title: trimmed, period: period)
            } label: {
                Text("Continue")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(isValid ? Color.tallyAccent : Color.tallyTextSecondary.opacity(0.3))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(!isValid)

            Button {
                appState.skipFirstGoalEntry()
            } label: {
                Text("Skip for now")
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
    }
}

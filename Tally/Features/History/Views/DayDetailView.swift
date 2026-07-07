import SwiftUI

struct DayDetailView: View {
    @Environment(\.tallyAccent) private var tallyAccent
    @Environment(AppState.self) private var appState
    let date: Date
    let userID: String

    private var habits: [Habit] {
        appState.personalStore.habits(for: userID).filter {
            $0.createdAt.startOfDay <= date.startOfDay
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(date, format: .dateTime.weekday(.wide).month().day())
                .font(.headline)

            if habits.isEmpty {
                Text("No habits tracked yet on this day")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(habits) { habit in
                    HStack(spacing: 10) {
                        Image(systemName: appState.personalStore.isCompleted(habit: habit, on: date)
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(appState.personalStore.isCompleted(habit: habit, on: date)
                                             ? tallyAccent : .secondary)
                        Text(habit.title)
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tallyCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

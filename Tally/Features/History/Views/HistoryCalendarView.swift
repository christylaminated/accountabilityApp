import SwiftUI

struct HistoryCalendarView: View {
    @Environment(AppState.self) private var appState
    private let explicitTargetID: String?
    @State private var displayedMonth: Date = .now.startOfMonth
    @State private var selectedDay: Date?

    init(targetUserID: String? = nil) {
        self.explicitTargetID = targetUserID
    }

    private var targetUserID: String {
        explicitTargetID ?? appState.currentUserID
    }

    private var member: CircleMember? {
        appState.circleStore.member(id: targetUserID)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                monthHeader
                weekdayHeader
                daysGrid
                if let day = selectedDay {
                    DayDetailView(date: day, userID: targetUserID)
                        .transition(.opacity)
                }
                Spacer().frame(height: 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(Color.tallyCanvas)
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var navTitle: String {
        if let member { return "\(member.displayName)'s history" }
        return "History"
    }

    private var monthHeader: some View {
        HStack {
            Button {
                displayedMonth = displayedMonth.adding(days: -1).startOfMonth
                selectedDay = nil
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
            }
            Spacer()
            Text(displayedMonth, format: .dateTime.month(.wide).year())
                .font(.title3.weight(.semibold))
            Spacer()
            Button {
                let next = displayedMonth.adding(days: 35).startOfMonth
                if next <= Date.now.startOfMonth {
                    displayedMonth = next
                    selectedDay = nil
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
            }
            .disabled(displayedMonth >= Date.now.startOfMonth)
        }
        .foregroundStyle(.primary)
    }

    private var weekdayHeader: some View {
        HStack {
            ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { d in
                Text(d)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var daysGrid: some View {
        let days = monthDays(for: displayedMonth)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, slot in
                if let day = slot {
                    DayCell(
                        date: day,
                        userID: targetUserID,
                        isSelected: selectedDay?.startOfDay == day.startOfDay
                    ) {
                        withAnimation { selectedDay = day }
                    }
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
    }

    /// 6 weeks × 7 days = 42 slots aligned Monday-first. nil entries pad the leading and
    /// trailing weeks.
    private func monthDays(for date: Date) -> [Date?] {
        let cal = Date.local
        let firstOfMonth = date.startOfMonth
        // Monday=0, Tuesday=1, ..., Sunday=6
        let weekdayMon0 = (cal.component(.weekday, from: firstOfMonth) + 5) % 7
        let range = cal.range(of: .day, in: .month, for: firstOfMonth) ?? 1..<29

        var slots: [Date?] = Array(repeating: nil, count: weekdayMon0)
        for d in range {
            slots.append(cal.date(byAdding: .day, value: d - 1, to: firstOfMonth))
        }
        while slots.count % 7 != 0 { slots.append(nil) }
        return slots
    }
}

private struct DayCell: View {
    @Environment(AppState.self) private var appState
    let date: Date
    let userID: String
    let isSelected: Bool
    let onTap: () -> Void

    private var completionRate: Double {
        let habits = appState.circleStore.habits(for: userID).filter {
            $0.createdAt.startOfDay <= date.startOfDay
        }
        guard !habits.isEmpty else { return 0 }
        let done = habits.filter {
            appState.circleStore.isCompleted(habit: $0, on: date)
        }.count
        return Double(done) / Double(habits.count)
    }

    private var fillColor: Color {
        switch completionRate {
        case 0:           return Color.tallyHeat0
        case 0..<0.25:    return Color.tallyHeat1
        case 0.25..<0.5:  return Color.tallyHeat2
        case 0.5..<0.75:  return Color.tallyHeat3
        default:          return Color.tallyHeat4
        }
    }

    private var isFuture: Bool { date.startOfDay > Date.now.startOfDay }
    private var dayNumber: Int { Date.local.component(.day, from: date) }
    private var isToday: Bool { date.startOfDay == Date.now.startOfDay }

    var body: some View {
        Button(action: onTap) {
            Text("\(dayNumber)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(isFuture ? Color.secondary.opacity(0.5) : (completionRate > 0.5 ? Color.white : Color.primary))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(isFuture ? Color.clear : fillColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isSelected ? Color.tallyAccent : (isToday ? Color.tallyAccent.opacity(0.5) : Color.clear),
                            lineWidth: isSelected ? 2 : 1
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
    }
}

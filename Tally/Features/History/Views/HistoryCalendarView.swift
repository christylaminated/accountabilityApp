import SwiftUI

struct HistoryCalendarView: View {
    @Environment(\.tallyAccent) private var tallyAccent
    @Environment(AppState.self) private var appState
    private let explicitTargetID: String?
    @State private var displayedMonth: Date = .now.startOfMonth
    @State private var selectedDay: Date?
    // Tapping the month/year header opens a picker to jump to any month/year.
    @State private var showMonthPicker = false
    @State private var pickerMonth = 1
    @State private var pickerYear = 2000

    init(targetUserID: String? = nil) {
        self.explicitTargetID = targetUserID
    }

    private var targetUserID: String {
        explicitTargetID ?? appState.currentUserID
    }

    /// Earliest year the jump-picker offers. Generous so old months are
    /// reachable even though there's no habit data that far back.
    private static let earliestYear = 2000
    private var currentYear: Int { Date.local.component(.year, from: .now) }

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
        .sheet(isPresented: $showMonthPicker) {
            monthYearPicker
        }
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
            Button {
                let comps = Date.local.dateComponents([.year, .month], from: displayedMonth)
                pickerMonth = comps.month ?? 1
                pickerYear = comps.year ?? currentYear
                showMonthPicker = true
            } label: {
                HStack(spacing: 4) {
                    Text(displayedMonth, format: .dateTime.month(.wide).year())
                        .font(.title3.weight(.semibold))
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
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

    // MARK: - Jump-to-month picker

    private var monthYearPicker: some View {
        NavigationStack {
            HStack(spacing: 0) {
                Picker("Month", selection: $pickerMonth) {
                    ForEach(1...12, id: \.self) { m in
                        Text(monthName(m)).tag(m)
                    }
                }
                .pickerStyle(.wheel)
                Picker("Year", selection: $pickerYear) {
                    // Plain String avoids the locale thousands separator ("2,026").
                    ForEach(Self.earliestYear...currentYear, id: \.self) { y in
                        Text(String(y)).tag(y)
                    }
                }
                .pickerStyle(.wheel)
            }
            .padding(.horizontal)
            .navigationTitle("Jump to month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showMonthPicker = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { applyMonthPicker() }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func monthName(_ month: Int) -> String {
        var comps = DateComponents()
        comps.year = 2000
        comps.month = month
        comps.day = 1
        guard let date = Date.local.date(from: comps) else { return "\(month)" }
        return date.formatted(.dateTime.month(.wide))
    }

    private func applyMonthPicker() {
        var comps = DateComponents()
        comps.year = pickerYear
        comps.month = pickerMonth
        comps.day = 1
        if let date = Date.local.date(from: comps) {
            // Clamp to the current month — the calendar never shows the future
            // (matches the disabled "next" chevron).
            displayedMonth = min(date.startOfMonth, Date.now.startOfMonth)
            selectedDay = nil
        }
        showMonthPicker = false
    }
}

private struct DayCell: View {
    @Environment(\.tallyAccent) private var tallyAccent
    @Environment(AppState.self) private var appState
    let date: Date
    let userID: String
    let isSelected: Bool
    let onTap: () -> Void

    private var completionRate: Double {
        let habits = appState.personalStore.habits(for: userID).filter {
            $0.createdAt.startOfDay <= date.startOfDay
        }
        guard !habits.isEmpty else { return 0 }
        let done = habits.filter {
            appState.personalStore.isCompleted(habit: $0, on: date)
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
                // High-completion cells have a near-solid accent fill,
                // so use `tallyOnAccent` (which flips luminance in Classic
                // dark mode) instead of literal `.white`. Otherwise white
                // text on the dark-mode near-white accent is invisible.
                .foregroundStyle(
                    isFuture
                        ? Color.tallyTextSecondary.opacity(0.5)
                        : (completionRate > 0.5
                            ? Color.tallyOnAccent
                            : Color.tallyTextPrimary)
                )
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(isFuture ? Color.clear : fillColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isSelected ? tallyAccent : (isToday ? tallyAccent.opacity(0.5) : Color.clear),
                            lineWidth: isSelected ? 2 : 1
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
    }
}

import SwiftUI

/// The month at a glance: a day's steps inside the date itself.
///
/// This is the view the concept is built around — the one thing StepUp did
/// that earned it a place on the phone. Two rules follow from that and are
/// worth keeping:
///
/// 1. The step count is *inside* the date cell, not on a detail screen.
/// 2. Each row carries that week's weight in the trailing gutter, so activity
///    and outcome are read together rather than on separate screens. The row
///    and the weekly average are the same week by construction — `MonthGrid`
///    keys rows the way `TrendEngine` keys weeks, and a test holds them to it.
struct MonthCalendarView: View {
    let grid: MonthGrid
    let activity: ActivityStore
    let weeklyAverages: [Date: WeeklyAverage]
    /// Called when a day that has already happened is tapped. The grid shows
    /// an abbreviated step count — "8.4k" — because that is what fits inside
    /// a date cell; the exact figure lives behind this.
    var onSelect: (Date) -> Void = { _ in }

    private var calendar: Calendar { activity.calendar }

    var body: some View {
        VStack(spacing: 10) {
            headerRow
            ForEach(grid.weeks) { week in
                weekRow(week)
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 4) {
            ForEach(Array(MonthGrid.weekdayInitials(calendar: calendar).enumerated()), id: \.offset) { _, initial in
                Text(initial)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
            Text("lb")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: gutterWidth)
        }
    }

    private func weekRow(_ week: MonthGrid.Week) -> some View {
        HStack(spacing: 4) {
            ForEach(week.days) { day in
                let isFuture = day.date > calendar.startOfDay(for: .now)
                Button {
                    onSelect(day.date)
                } label: {
                    dayCell(day)
                }
                .buttonStyle(.plain)
                // A future day or one from a neighbouring month has nothing
                // to show, so it is not offered as something to tap.
                .disabled(isFuture || !day.isInMonth)
                .frame(maxWidth: .infinity)
            }
            weekWeight(week)
                .frame(width: gutterWidth)
        }
    }

    private let gutterWidth: CGFloat = 46

    // MARK: - Day

    @ViewBuilder
    private func dayCell(_ day: MonthGrid.Day) -> some View {
        let steps = activity.activity(on: day.date)?.steps
        let isToday = calendar.isDateInToday(day.date)
        let isFuture = day.date > calendar.startOfDay(for: .now)

        VStack(spacing: 1) {
            Text(calendar.component(.day, from: day.date), format: .number)
                .font(.system(size: 15, weight: isToday ? .bold : .medium, design: .rounded))
                .foregroundStyle(dayNumberColor(isInMonth: day.isInMonth, isToday: isToday))

            // A day with no reading shows nothing rather than "0" — the phone
            // being elsewhere is not the same as standing still. A day that
            // has not happened shows nothing either, whatever the source says.
            Text(isFuture ? " " : (steps.map(Self.abbreviated) ?? " "))
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(day.isInMonth ? .secondary : .quaternary)
                .monospacedDigit()
        }
        .frame(height: 42)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 9)
                .fill(fill(steps: steps, inMonth: day.isInMonth, isFuture: isFuture))
        }
        .overlay {
            if isToday {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(day: day, steps: steps))
    }

    private func dayNumberColor(isInMonth: Bool, isToday: Bool) -> Color {
        if !isInMonth { return .primary.opacity(0.22) }
        return isToday ? .accentColor : .primary
    }

    /// Intensity scales with how close the day came to the goal, so a strong
    /// month is recognisable without reading a single number.
    private func fill(steps: Int?, inMonth: Bool, isFuture: Bool) -> Color {
        guard inMonth, !isFuture, let steps else { return .clear }
        let share = min(Double(steps) / Double(activity.dailyStepGoal), 1.0)
        return Color.accentColor.opacity(0.06 + share * 0.26)
    }

    private func accessibilityLabel(day: MonthGrid.Day, steps: Int?) -> String {
        let date = day.date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        guard let steps else { return "\(date), no step data" }
        return "\(date), \(steps) steps"
    }

    /// 8,421 → "8.4k". Four characters is what fits inside a date cell on the
    /// narrowest iPhone, and the exact count is available on the day's detail.
    static func abbreviated(_ steps: Int) -> String {
        if steps < 1_000 { return "\(steps)" }
        let thousands = Double(steps) / 1_000
        return thousands < 10
            ? String(format: "%.1fk", thousands)
            : String(format: "%.0fk", thousands)
    }

    // MARK: - Week weight

    @ViewBuilder
    private func weekWeight(_ week: MonthGrid.Week) -> some View {
        if let average = weeklyAverages[week.start] {
            VStack(spacing: 1) {
                Text(average.pounds, format: .number.precision(.fractionLength(1)))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(average.isReliable ? .primary : .secondary)
                if !average.isReliable {
                    // Said rather than hidden: an average of one weigh-in is
                    // not the same claim as an average of six.
                    Text("\(average.entryCount)×")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(height: 42)
            .accessibilityLabel(
                "Week of \(week.start.formatted(.dateTime.day().month())), average \(average.pounds.formatted(.number.precision(.fractionLength(1)))) pounds from \(average.entryCount) weigh-ins"
            )
        } else {
            Text("–")
                .font(.system(size: 11))
                .foregroundStyle(.quaternary)
                .frame(height: 42)
                .accessibilityHidden(true)
        }
    }
}

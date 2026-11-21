import SwiftUI

/// The year at a glance — the month view's design law, scaled up.
///
/// Twelve small month grids, each day tinted by how close it came to the
/// goal, so a strong season is visible before a single number is read. The
/// figures underneath are all counted over days that reported, never over
/// 365, and the screen says how many of those there were.
struct YearView: View {
    @Bindable var activity: ActivityStore
    @Bindable var weight: WeightStore
    /// Tapping a month hands the date back so Home can jump to it.
    var onSelectMonth: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var year: Int

    private var calendar: Calendar { activity.calendar }

    init(
        activity: ActivityStore,
        weight: WeightStore,
        year: Int? = nil,
        onSelectMonth: @escaping (Date) -> Void
    ) {
        self.activity = activity
        self.weight = weight
        self.onSelectMonth = onSelectMonth
        _year = State(initialValue: year ?? Calendar.current.component(.year, from: .now))
    }

    private var summary: YearSummary { activity.yearSummary(year) }

    private var isCurrentYear: Bool {
        year == calendar.component(.year, from: .now)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if summary.hasData {
                    totals
                    highlights
                    months
                    weightOverYear
                } else {
                    empty
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        // No navigation title: the header below carries the year, with the
        // arrows and the day count attached to it. A bar title would just be
        // the same four digits again, two rows up.
        .navigationBarTitleDisplayMode(.inline)
        .task(id: year) { await activity.loadYear(year) }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            yearButton("chevron.left", label: "Previous year") { year -= 1 }
            Spacer()
            VStack(spacing: 1) {
                Text(String(year))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                if summary.hasData {
                    // How much of the year this is actually describing.
                    Text("\(summary.daysWithData) day\(summary.daysWithData == 1 ? "" : "s") recorded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            yearButton("chevron.right", label: "Next year", disabled: isCurrentYear) { year += 1 }
        }
    }

    private func yearButton(
        _ symbol: String, label: String, disabled: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.headline)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? Color.secondary : Color.accentColor)
        .disabled(disabled)
        .accessibilityLabel(label)
    }

    // MARK: - Totals

    private var totals: some View {
        HStack(spacing: 10) {
            tile(summary.totalSteps.formatted(.number.notation(.compactName)), "total steps")
            tile(HomeView.grouped(summary.averageSteps), "a day")
            tile("\(summary.daysAtGoal)", "days at goal")
        }
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(.background, in: .rect(cornerRadius: 14))
    }

    // MARK: - Highlights

    @ViewBuilder
    private var highlights: some View {
        VStack(spacing: 0) {
            if let best = summary.bestDay {
                highlight(
                    "Best day",
                    detail: best.date.formatted(.dateTime.weekday(.wide).day().month(.wide)),
                    value: HomeView.grouped(best.steps),
                    symbol: "flame"
                )
            }
            if let month = summary.bestMonth {
                Divider().padding(.leading, 48)
                highlight(
                    "Strongest month",
                    detail: monthName(month.month),
                    // Said out loud, because "strongest" by average and
                    // "strongest" by total are different months and the
                    // screen should not leave which one ambiguous.
                    value: "\(HomeView.grouped(month.averageSteps))/day",
                    symbol: "calendar"
                )
            }
        }
        .background(.background, in: .rect(cornerRadius: 16))
    }

    private func highlight(_ title: String, detail: String, value: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
    }

    private func monthName(_ index: Int) -> String {
        calendar.monthSymbols[index]
    }

    // MARK: - Twelve months

    private var months: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Every day").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(0..<12, id: \.self) { index in
                    Button {
                        if let date = calendar.date(from: DateComponents(year: year, month: index + 1, day: 1)) {
                            onSelectMonth(date)
                            dismiss()
                        }
                    } label: {
                        MiniMonth(
                            year: year,
                            month: index + 1,
                            activity: activity,
                            calendar: calendar
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(summary.monthlyDaysWithData[index] == 0)
                }
            }
        }
    }

    // MARK: - Weight

    @ViewBuilder
    private var weightOverYear: some View {
        let points = weight.trend.filter { calendar.component(.year, from: $0.date) == year }
        if let first = points.first, let last = points.last, points.count > 1 {
            let change = last.pounds - first.pounds
            VStack(alignment: .leading, spacing: 7) {
                Text("Weight").font(.headline)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(change > 0 ? "+" : "")\(change, format: .number.precision(.fractionLength(1)))")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(change < 0 ? .green : .primary)
                    Text("lb across the year").font(.subheadline).foregroundStyle(.secondary)
                }
                Text("\(first.pounds, format: .number.precision(.fractionLength(1))) → \(last.pounds, format: .number.precision(.fractionLength(1))) lb, measured on the trend rather than on single weigh-ins.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.background, in: .rect(cornerRadius: 16))
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing recorded in \(String(year)).").font(.subheadline.weight(.medium))
            Text("Apple Health has no activity for this year. If you were using a different phone then, its data may not have come across.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background, in: .rect(cornerRadius: 16))
    }
}

// MARK: - Mini month

/// One month as a block of day squares, tinted by how close each came to the
/// goal. Small enough that twelve fit on a phone, and dense enough that a
/// strong stretch is visible as a shape rather than as a number.
private struct MiniMonth: View {
    let year: Int
    let month: Int
    let activity: ActivityStore
    let calendar: Calendar

    private var grid: MonthGrid? {
        calendar.date(from: DateComponents(year: year, month: month, day: 1))
            .map { MonthGrid.make(containing: $0, calendar: calendar) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(calendar.shortMonthSymbols[month - 1])
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let grid {
                VStack(spacing: 2) {
                    ForEach(grid.weeks) { week in
                        HStack(spacing: 2) {
                            ForEach(week.days) { day in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(fill(day))
                                    .aspectRatio(1, contentMode: .fit)
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: .rect(cornerRadius: 12))
    }

    private func fill(_ day: MonthGrid.Day) -> Color {
        guard day.isInMonth else { return .clear }
        guard day.date <= calendar.startOfDay(for: .now) else { return .primary.opacity(0.04) }
        guard let steps = activity.activity(on: day.date)?.steps else {
            // A day with no reading is drawn, but drawn as absent — distinct
            // from both a quiet day and a day outside the month.
            return .primary.opacity(0.07)
        }
        let share = min(Double(steps) / Double(activity.dailyStepGoal), 1.0)
        return Color.accentColor.opacity(0.14 + share * 0.72)
    }
}

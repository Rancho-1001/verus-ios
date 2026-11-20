import SwiftUI

/// Home: how is today going, and how is the month going?
///
/// The concept gives this screen three seconds to answer both. So today's
/// numbers sit at the top with no tap required, and the month calendar is
/// immediately under them — nothing else competes for the first screenful.
struct HomeView: View {
    @Bindable var weight: WeightStore
    @Bindable var activity: ActivityStore

    @State private var monthAnchor: Date = .now

    private var calendar: Calendar { activity.calendar }

    private var grid: MonthGrid {
        MonthGrid.make(containing: monthAnchor, calendar: calendar)
    }

    private var weeklyAverages: [Date: WeeklyAverage] {
        Dictionary(uniqueKeysWithValues: weight.weeklyAverages.map { ($0.weekStart, $0) })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    today
                    calendarCard
                    monthSummary
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Verus")
            .task(id: grid.month) { await activity.load(grid: grid) }
        }
    }

    // MARK: - Today

    private var today: some View {
        HStack(spacing: 10) {
            metric(
                "Steps",
                value: activity.today.map { Self.grouped($0.steps) } ?? "—",
                caption: goalCaption,
                systemImage: "figure.walk"
            )
            metric(
                "Active",
                value: activity.today.map { "\(Int($0.activeKilocalories))" } ?? "—",
                caption: "kcal burned",
                systemImage: "flame"
            )
            metric(
                "Weight",
                value: weight.trendPounds.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—",
                caption: trendCaption,
                systemImage: "scalemass"
            )
        }
    }

    /// The headline weight is the trend; this line carries the raw reading, so
    /// both are visible and only one is the claim.
    private var trendCaption: String {
        guard let latest = weight.latestEntry else { return "no weigh-ins yet" }
        guard calendar.isDateInToday(latest.date) else {
            return "trend · last \(latest.date.formatted(.dateTime.day().month()))"
        }
        return "trend · today \(latest.pounds.formatted(.number.precision(.fractionLength(1))))"
    }

    private var goalCaption: String {
        guard let steps = activity.today?.steps else { return "no data yet" }
        let remaining = activity.dailyStepGoal - steps
        return remaining > 0
            ? "\(Self.grouped(remaining)) to goal"
            : "goal met"
    }

    private func metric(_ title: String, value: String, caption: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 13)
        .background(.background, in: .rect(cornerRadius: 14))
    }

    // MARK: - Calendar

    private var calendarCard: some View {
        VStack(spacing: 14) {
            HStack {
                Button { step(by: -1) } label: {
                    Image(systemName: "chevron.left").font(.subheadline.weight(.semibold))
                }
                .accessibilityLabel("Previous month")

                Spacer()
                Text(grid.month, format: .dateTime.month(.wide).year())
                    .font(.headline)
                    .contentTransition(.numericText())
                Spacer()

                Button { step(by: 1) } label: {
                    Image(systemName: "chevron.right").font(.subheadline.weight(.semibold))
                }
                .accessibilityLabel("Next month")
                .disabled(isShowingCurrentMonth)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)

            MonthCalendarView(
                grid: grid,
                activity: activity,
                weeklyAverages: weeklyAverages
            )
        }
        .padding(16)
        .background(.background, in: .rect(cornerRadius: 18))
    }

    private var isShowingCurrentMonth: Bool {
        calendar.isDate(grid.month, equalTo: .now, toGranularity: .month)
    }

    private func step(by months: Int) {
        guard let next = calendar.date(byAdding: .month, value: months, to: monthAnchor) else { return }
        withAnimation(.snappy(duration: 0.22)) { monthAnchor = next }
    }

    // MARK: - Month summary

    private var monthSummary: some View {
        HStack(spacing: 10) {
            summaryTile(
                value: activity.averageSteps(in: grid).map(Self.grouped) ?? "—",
                label: "avg steps/day"
            )
            summaryTile(
                value: "\(activity.daysAtGoal(in: grid))",
                label: "days at goal"
            )
            summaryTile(
                value: monthWeightDelta,
                label: "weight this month"
            )
        }
    }

    /// Change across the month, measured trend-to-trend rather than
    /// weigh-in to weigh-in, so a heavy first morning cannot invent a loss.
    private var monthWeightDelta: String {
        let days = grid.weeks.flatMap(\.days).filter(\.isInMonth).map(\.date)
        guard let first = days.first, let last = days.last else { return "—" }
        let points = weight.trend.filter { $0.date >= first && $0.date <= last }
        guard let start = points.first, let end = points.last, points.count > 1 else { return "—" }
        let delta = end.pounds - start.pounds
        return "\(delta > 0 ? "+" : "")\(delta.formatted(.number.precision(.fractionLength(1))))"
    }

    private func summaryTile(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.background, in: .rect(cornerRadius: 14))
    }

    static func grouped(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }
}

#Preview {
    HomeView(
        weight: WeightStore(fileURL: nil),
        activity: ActivityStore()
    )
}

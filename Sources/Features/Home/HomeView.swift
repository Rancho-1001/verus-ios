import SwiftUI

/// Home: how is today going, and how is the month going?
///
/// The concept gives this screen three seconds to answer both. So today's
/// numbers sit at the top with no tap required, and the month calendar is
/// immediately under them — nothing else competes for the first screenful.
struct HomeView: View {
    @Bindable var weight: WeightStore
    @Bindable var activity: ActivityStore
    @Bindable var food: FoodStore

    @State private var monthAnchor: Date = .now
    @State private var selectedDay: Date?

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
                    sourceBanner
                    today
                    calendarCard
                    monthSummary
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Verus")
            .task(id: grid.month) { await activity.load(grid: grid) }
            .sheet(item: $selectedDay) { day in
                DayDetailSheet(day: day, activity: activity, weight: weight, food: food)
            }
        }
    }

    // MARK: - Where the numbers came from

    /// Shown whenever the figures on screen are not the user's own.
    ///
    /// The rule this enforces: sample data is never silent. An empty calendar
    /// would teach nothing about what the app does, so the screen fills in —
    /// and then says plainly that it has, every time, until real data arrives.
    @ViewBuilder
    private var sourceBanner: some View {
        switch activity.state {
        case .live:
            EmptyView()

        case .needsPermission:
            banner(
                icon: "heart.text.square",
                title: "Showing sample data",
                detail: "Connect Apple Health and this becomes your own steps and energy.",
                action: ("Connect", { Task { await activity.requestPermission(for: grid) } })
            )

        case .noDataFromHealth:
            banner(
                icon: "exclamationmark.triangle",
                title: "Apple Health returned nothing",
                // Deliberately not "you denied access" — HealthKit does not
                // report denied reads, so claiming to know would be a guess.
                detail: "Either there is no data for this month, or Verus was not granted access to read it. Settings › Health › Data Access shows which.",
                action: ("Open Settings", openSettings)
            )

        case .unavailable:
            banner(
                icon: "heart.slash",
                title: "Apple Health is unavailable here",
                detail: "Showing sample data so the screen still means something.",
                action: nil
            )

        case .failed(let message):
            banner(
                icon: "exclamationmark.triangle",
                title: "Could not read Apple Health",
                detail: message,
                action: ("Try again", { Task { await activity.load(grid: grid) } })
            )
        }
    }

    private func banner(
        icon: String,
        title: String,
        detail: String,
        action: (label: String, run: () -> Void)?
    ) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.orange)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let action {
                    Button(action.label, action: action.run)
                        .font(.caption.weight(.semibold))
                        .padding(.top, 3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.orange.opacity(0.09), in: .rect(cornerRadius: 14))
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
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
                monthButton("chevron.left", label: "Previous month") { step(by: -1) }
                Spacer()
                // The title is the way in to the year. A sixth tab would push
                // the tab bar into iOS's "More" menu, and the year belongs
                // next to the month rather than beside Food and Weight.
                NavigationLink {
                    YearView(activity: activity, weight: weight) { month in
                        monthAnchor = month
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(grid.month, format: .dateTime.month(.wide).year())
                            .font(.headline)
                            .contentTransition(.numericText())
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the year")
                Spacer()
                monthButton("chevron.right", label: "Next month", disabled: isShowingCurrentMonth) {
                    step(by: 1)
                }
            }

            MonthCalendarView(
                grid: grid,
                activity: activity,
                weeklyAverages: weeklyAverages,
                onSelect: { selectedDay = $0 }
            )
        }
        .padding(16)
        .background(.background, in: .rect(cornerRadius: 18))
    }

    /// A month arrow with a thumb-sized hit area.
    ///
    /// The first version was a bare `Image` in a `.plain` button, which makes
    /// the tappable region the glyph itself — around 12 points square against
    /// Apple's 44-point minimum. A mouse in the simulator hits that every
    /// time and a thumb essentially never does, which is why it survived
    /// until the app ran on a real phone.
    private func monthButton(
        _ symbol: String,
        label: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(width: 44, height: 44)
                // Without this the frame is decoration and only the glyph
                // takes the tap.
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? Color.secondary : Color.accentColor)
        .disabled(disabled)
        .accessibilityLabel(label)
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

/// `sheet(item:)` needs an Identifiable, and a bare `Date` is not one.
extension Date: @retroactive Identifiable {
    public var id: TimeInterval { timeIntervalSince1970 }
}

#Preview {
    HomeView(
        weight: WeightStore(fileURL: nil, health: nil),
        activity: ActivityStore(health: nil),
        food: FoodStore(fileURL: nil)
    )
}

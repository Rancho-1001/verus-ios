import SwiftUI

/// Which of today's three numbers is being expanded.
enum TodayMetric: String, CaseIterable, Identifiable, Sendable {
    case steps, active, weight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .steps: "Steps"
        case .active: "Active"
        case .weight: "Weight"
        }
    }

    var symbol: String {
        switch self {
        case .steps: "figure.walk"
        case .active: "flame"
        case .weight: "scalemass"
        }
    }
}

/// One of today's numbers, in full.
///
/// Home gives each metric a card roughly an inch wide, which holds a figure,
/// a caption and a coloured rule — and nothing else. Everything that did not
/// fit is here: the exact counts, the month behind them, the streak, the
/// composition a smart scale reported. The cards look like buttons because
/// they are buttons, and this is what they open.
struct TodayMetricSheet: View {
    let metric: TodayMetric
    let activity: ActivityStore
    let weight: WeightStore
    let grid: MonthGrid

    @Environment(\.dismiss) private var dismiss

    private var calendar: Calendar { activity.calendar }

    var body: some View {
        NavigationStack {
            List {
                switch metric {
                case .steps: stepsSections
                case .active: activeSections
                case .weight: weightSections
                }
            }
            .navigationTitle(metric.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Steps

    @ViewBuilder
    private var stepsSections: some View {
        let today = activity.today
        let goal = activity.dailyStepGoal

        Section {
            headline(
                value: today.map { HomeView.grouped($0.steps) } ?? "—",
                unit: "steps today",
                standing: activity.todayStepStanding,
                share: GoalStanding.share(value: today?.steps, goal: goal),
                detail: stepsHeadlineDetail
            )
            GoalStandingLegend(stepGoal: goal)
        }

        Section("Today") {
            if let today {
                row("Steps", today.steps.formatted(.number.grouping(.automatic)))
                if let miles = today.miles {
                    row("Distance", "\(miles.formatted(.number.precision(.fractionLength(2)))) mi")
                } else {
                    // Said rather than left out: a day can have steps and no
                    // distance, and the reason is worth one line.
                    row("Distance", "not recorded")
                }
                row("Goal", goal.formatted(.number.grouping(.automatic)))
            } else {
                Text("Apple Health has nothing for today yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }

        Section {
            row("Average a day", activity.averageSteps(in: grid).map(HomeView.grouped) ?? "—")
            row("Days at goal", "\(activity.daysAtGoal(in: grid))")
            row("Total steps", HomeView.grouped(activity.totalSteps(in: grid)))
            if let miles = activity.totalMiles(in: grid) {
                row("Total distance", "\(miles.formatted(.number.precision(.fractionLength(1)))) mi")
            }
        } header: {
            Text(grid.month, format: .dateTime.month(.wide).year())
        } footer: {
            Text("Averaged over the days that reported, not over the whole month.")
        }

        Section {
            row("Current", "\(activity.currentStreak) day\(activity.currentStreak == 1 ? "" : "s")")
            row("Longest", "\(activity.longestStreak) day\(activity.longestStreak == 1 ? "" : "s")")
        } header: {
            Text("Streak")
        } footer: {
            Text("A day still in progress does not break a streak. A day with no reading does.")
        }

        Section("Last 7 days") {
            ForEach(activity.recentDays(7), id: \.self) { day in
                dayRow(day) { reading in
                    reading.map { HomeView.grouped($0.steps) } ?? "—"
                } standing: { reading in
                    GoalStanding.standing(value: reading?.steps, goal: goal)
                }
            }
        }
    }

    private var stepsHeadlineDetail: String {
        guard let steps = activity.today?.steps else { return "no reading yet today" }
        let remaining = activity.dailyStepGoal - steps
        return remaining > 0
            ? "\(HomeView.grouped(remaining)) to go of \(HomeView.grouped(activity.dailyStepGoal))"
            : "\(HomeView.grouped(-remaining)) past the \(HomeView.grouped(activity.dailyStepGoal)) goal"
    }

    // MARK: - Active energy

    @ViewBuilder
    private var activeSections: some View {
        let today = activity.today
        let goal = Double(activity.dailyActiveEnergyGoal)

        Section {
            headline(
                value: today.map { "\(Int($0.activeKilocalories))" } ?? "—",
                unit: "kcal burned today",
                standing: activity.todayActiveStanding,
                share: GoalStanding.share(value: today?.activeKilocalories, goal: goal),
                detail: activeHeadlineDetail
            )
        }

        Section {
            if let today {
                row("Active", "\(Int(today.activeKilocalories)) kcal")
                row("Resting", "\(Int(today.restingKilocalories)) kcal")
                row("Total burned", "\(Int(today.totalKilocalories)) kcal")
            } else {
                Text("Apple Health has nothing for today yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Today")
        } footer: {
            Text("Resting energy is what the body spends existing — Health estimates it, and the Food screen counts intake against the total rather than against active alone.")
        }

        if !todaysWorkouts.isEmpty {
            Section("Workouts today") {
                ForEach(todaysWorkouts) { workout in
                    HStack {
                        Label(workout.kind, systemImage: workout.symbol)
                        Spacer()
                        Text(workoutDetail(workout))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }

        Section {
            row(
                "Average a day",
                activity.averageActiveKilocalories(in: grid)
                    .map { "\(Int($0.rounded())) kcal" } ?? "—"
            )
        } header: {
            Text(grid.month, format: .dateTime.month(.wide).year())
        }

        Section("Last 7 days") {
            ForEach(activity.recentDays(7), id: \.self) { day in
                dayRow(day) { reading in
                    reading.map { "\(Int($0.activeKilocalories)) kcal" } ?? "—"
                } standing: { reading in
                    GoalStanding.standing(value: reading?.activeKilocalories, goal: goal)
                }
            }
        }
    }

    private var activeHeadlineDetail: String {
        guard let active = activity.today?.activeKilocalories else { return "no reading yet today" }
        let remaining = Double(activity.dailyActiveEnergyGoal) - active
        return remaining > 0
            ? "\(Int(remaining.rounded())) kcal to go of \(activity.dailyActiveEnergyGoal)"
            : "\(Int((-remaining).rounded())) kcal past the \(activity.dailyActiveEnergyGoal) goal"
    }

    private var todaysWorkouts: [Workout] {
        activity.workouts
            .filter { calendar.isDateInToday($0.start) }
            .sorted { $0.start > $1.start }
    }

    private func workoutDetail(_ workout: Workout) -> String {
        var parts = [workout.durationText]
        if let miles = workout.miles {
            parts.append("\(miles.formatted(.number.precision(.fractionLength(2)))) mi")
        }
        if let kcal = workout.activeKilocalories {
            parts.append("\(Int(kcal)) kcal")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Weight

    @ViewBuilder
    private var weightSections: some View {
        Section {
            headline(
                value: weight.trendPounds.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—",
                unit: "lb trend",
                standing: weight.standing,
                share: nil,
                detail: weightHeadlineDetail
            )
        }

        if let latest = weight.latestEntry {
            Section {
                row("Weight", "\(latest.pounds.formatted(.number.precision(.fractionLength(1)))) lb")
                row("Taken", latest.date.formatted(.dateTime.weekday().day().month().hour().minute()))
                compositionRows(for: latest)
            } header: {
                Text("Last weigh-in")
            } footer: {
                // Deliberately does not name a source. Verus cannot tell a
                // figure a smart scale wrote from one typed in on the Weight
                // screen, so it does not claim to.
                Text(latest.hasComposition
                     ? "Composition recorded with this weigh-in."
                     : "This weigh-in carried weight only. A scale that writes body fat to Apple Health will show it here.")
            }
        }

        Section {
            row("This week", weight.thisWeek.map { "\($0.pounds.formatted(.number.precision(.fractionLength(1)))) lb" } ?? "—")
            row("Change this month", monthDelta)
            row("Rate", rateText)
        } header: {
            Text("Movement")
        } footer: {
            Text("Measured on the smoothed trend rather than between single weigh-ins, so one heavy morning cannot invent a gain.")
        }

        Section("Where this ends up") {
            projectionRow
        }

        Section {
            row("Weight", "\(goalPounds.formatted(.number.precision(.fractionLength(0)))) lb")
            row(
                "Body fat",
                weight.goalBodyFatPercent
                    .map { "\($0.formatted(.number.precision(.fractionLength(0))))%" } ?? "not set"
            )
            if let relationship = relationshipText {
                Text(relationship)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Goals")
        }
    }

    @ViewBuilder
    private func compositionRows(for entry: WeightEntry) -> some View {
        if let fat = entry.bodyFatPercent {
            row("Body fat", "\(fat.formatted(.number.precision(.fractionLength(1))))%")
        }
        if let fatMass = entry.fatKilograms {
            row(
                "Fat mass",
                "\((fatMass * WeightEntry.poundsPerKilogram).formatted(.number.precision(.fractionLength(1)))) lb"
            )
        }
        if let lean = entry.bestLeanKilograms {
            row(
                entry.isLeanMeasured ? "Lean mass" : "Lean mass (derived)",
                "\((lean * WeightEntry.poundsPerKilogram).formatted(.number.precision(.fractionLength(1)))) lb"
            )
        }
        if let bmi = entry.bodyMassIndex {
            row("BMI", bmi.formatted(.number.precision(.fractionLength(1))))
        }
    }

    private var weightHeadlineDetail: String {
        guard weight.trendPounds != nil else { return "no weigh-ins yet" }
        let count = weight.entries.count
        return "smoothed from \(count) weigh-in\(count == 1 ? "" : "s")"
    }

    /// Trend-to-trend across the month on screen, the same figure the Home
    /// summary tile shows — computed here from the same grid so the two
    /// cannot disagree.
    private var monthDelta: String {
        let days = grid.weeks.flatMap(\.days).filter(\.isInMonth).map(\.date)
        guard let first = days.first, let last = days.last else { return "—" }
        let points = weight.trend.filter { $0.date >= first && $0.date <= last }
        guard let start = points.first, let end = points.last, points.count > 1 else { return "—" }
        let delta = end.pounds - start.pounds
        return "\(delta > 0 ? "+" : "")\(delta.formatted(.number.precision(.fractionLength(1)))) lb"
    }

    private var rateText: String {
        guard let rate = weight.rateKilogramsPerWeek else { return "not enough data" }
        let pounds = rate * WeightEntry.poundsPerKilogram
        return "\(pounds > 0 ? "+" : "")\(pounds.formatted(.number.precision(.fractionLength(1)))) lb/week"
    }

    /// The same five cases the Weight screen prints, because they are the
    /// only five the engine can return — there is no "on track!" branch to
    /// fall back on when the data does not support a date.
    @ViewBuilder
    private var projectionRow: some View {
        switch weight.projection {
        case .reached:
            Label("Goal reached", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .notEnoughData(let needed):
            Label("\(needed) more days of weigh-ins before a projection", systemImage: "clock")
                .foregroundStyle(.secondary)
        case .tooSlowToProject:
            Label("The trend is flat — no honest date to give", systemImage: "equal.circle")
                .foregroundStyle(.secondary)
        case .movingAway(let rate):
            Label(
                "Moving away at \(abs(rate * WeightEntry.poundsPerKilogram).formatted(.number.precision(.fractionLength(1)))) lb a week",
                systemImage: "arrow.up.right"
            )
            .foregroundStyle(.orange)
        case .onTrack(let date, let weeks, _):
            VStack(alignment: .leading, spacing: 3) {
                Label(
                    "\(goalPounds.formatted(.number.precision(.fractionLength(0)))) lb by \(date.formatted(.dateTime.month(.wide).year()))",
                    systemImage: "target"
                )
                Text("about \(Int(weeks.rounded())) weeks at your current pace")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var goalPounds: Double { weight.goalKilograms * WeightEntry.poundsPerKilogram }

    private var relationshipText: String? {
        guard let goalFat = weight.goalBodyFatPercent else { return nil }
        let fat = goalFat.formatted(.number.precision(.fractionLength(0)))
        switch weight.goalRelationship {
        case .noBodyFatRecorded:
            return nil
        case .converge(let at):
            return "\(fat)% body fat lands at about \(at.formatted(.number.precision(.fractionLength(0)))) lb — the same place as the weight goal."
        case .bodyFatReachedFirst(let at):
            return "\(fat)% body fat arrives around \(at.formatted(.number.precision(.fractionLength(0)))) lb, before the scale goal."
        case .weightReachedFirst(let at):
            return "\(fat)% body fat needs about \(at.formatted(.number.precision(.fractionLength(0)))) lb — below the weight goal."
        }
    }

    // MARK: - Pieces

    private func headline(
        value: String,
        unit: String,
        standing: GoalStanding,
        share: Double?,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    .foregroundStyle(standing.valueColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unit)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let share {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.07))
                        Capsule()
                            .fill(standing.color.opacity(0.8))
                            .frame(width: max(proxy.size.width * share, share > 0 ? 4 : 0))
                    }
                }
                .frame(height: 6)
            }
            Label(detail, systemImage: standing.symbol)
                .font(.footnote)
                .foregroundStyle(standing == .unknown ? Color.secondary : standing.color)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    /// A day in the trailing list: the date, the figure, and a dot in the
    /// band's colour so the week reads as a shape rather than as seven
    /// numbers.
    private func dayRow(
        _ day: Date,
        value: (DailyActivity?) -> String,
        standing: (DailyActivity?) -> GoalStanding
    ) -> some View {
        let reading = activity.activity(on: day)
        let band = standing(reading)
        return HStack(spacing: 10) {
            Circle()
                .fill(band == .unknown ? Color.primary.opacity(0.12) : band.color.opacity(0.85))
                .frame(width: 9, height: 9)
            Text(calendar.isDateInToday(day)
                 ? "Today"
                 : day.formatted(.dateTime.weekday(.abbreviated).day().month()))
            Spacer()
            Text(value(reading))
                .foregroundStyle(reading == nil ? .tertiary : .secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(day.formatted(.dateTime.weekday(.wide).day().month())), \(value(reading)), \(band.label)"
        )
    }
}

#Preview {
    TodayMetricSheet(
        metric: .steps,
        activity: ActivityStore(health: nil),
        weight: WeightStore(fileURL: nil, health: nil),
        grid: MonthGrid.make(containing: .now, calendar: .current)
    )
}

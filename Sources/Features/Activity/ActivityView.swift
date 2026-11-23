import Charts
import SwiftUI

/// Activity: am I moving as much as I think I am, week over week?
///
/// That question is the concept's own wording for this screen, and it decides
/// the hierarchy. The headline is a *weekly average*, not today's count —
/// today is already on Home, and a single day cannot answer a question about
/// weeks. The chart underneath is one bar per week for the same reason.
struct ActivityView: View {
    @Bindable var activity: ActivityStore

    private var calendar: Calendar { activity.calendar }

    /// Twelve weeks is a quarter: long enough to show a season changing,
    /// short enough that each bar is still wide enough to read on a phone.
    private var chartWeeks: [ActivityWeek] {
        Array(activity.weeks.suffix(12))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    headline
                    streaks
                    weeklyChart
                    workoutHistory
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Activity")
            .task { await activity.loadRecent() }
        }
    }

    // MARK: - Headline

    private var headline: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("This week, per day")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.6)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(thisWeek.map { HomeView.grouped($0.averageSteps) } ?? "—")
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                Text("steps")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            changeLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var thisWeek: ActivityWeek? { activity.weeks.last }

    /// Every branch is a state the rollup can actually produce. A week still
    /// running is said to be running rather than compared as if it were done —
    /// three days into a week, "down 40%" is arithmetic, not information.
    @ViewBuilder
    private var changeLine: some View {
        if let week = thisWeek, !week.isFinished(calendar: calendar) {
            Label(
                "\(week.daysWithData) day\(week.daysWithData == 1 ? "" : "s") in — too early to compare",
                systemImage: "clock"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        } else if let change = activity.weekOverWeekChange {
            let up = change >= 0
            Label(
                "\(up ? "Up" : "Down") \(abs(change).formatted(.percent.precision(.fractionLength(0)))) on last week",
                systemImage: up ? "arrow.up.right" : "arrow.down.right"
            )
            .font(.subheadline)
            .foregroundStyle(up ? .green : .orange)
        } else {
            Label("No previous week to compare against yet", systemImage: "calendar")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Streaks

    private var streaks: some View {
        HStack(spacing: 10) {
            streakTile(
                value: activity.currentStreak,
                label: "day streak",
                caption: "at \(HomeView.grouped(activity.dailyStepGoal))+",
                tint: activity.currentStreak > 0 ? .orange : .secondary
            )
            streakTile(
                value: activity.longestStreak,
                label: "longest run",
                caption: "best so far",
                tint: .secondary
            )
            streakTile(
                value: thisWeek?.daysAtGoal ?? 0,
                label: "days at goal",
                caption: "this week",
                tint: .secondary
            )
        }
    }

    private func streakTile(value: Int, label: String, caption: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(tint == .secondary ? .primary : tint)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11, weight: .medium))
            Text(caption)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.card, in: .rect(cornerRadius: 14))
    }

    // MARK: - Weekly chart

    private var weeklyChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("By week")
                .font(.headline)

            if chartWeeks.isEmpty {
                Text("No activity recorded yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 180)
                    .background(Color.card, in: .rect(cornerRadius: 16))
            } else {
                Chart {
                    ForEach(chartWeeks) { week in
                        BarMark(
                            x: .value("Week", week.start, unit: .weekOfYear),
                            y: .value("Steps per day", week.averageSteps)
                        )
                        .cornerRadius(5)
                        // An unfinished week is drawn faint. It is a real
                        // number over fewer days, and showing it at full
                        // strength beside finished weeks would invite reading
                        // it as a collapse rather than as a week in progress.
                        .foregroundStyle(
                            week.isFinished(calendar: calendar)
                                ? Color.accentColor
                                : Color.accentColor.opacity(0.35)
                        )
                    }
                    RuleMark(y: .value("Goal", activity.dailyStepGoal))
                        .lineStyle(.init(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(.green.opacity(0.8))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("goal").font(.caption2).foregroundStyle(.green)
                        }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let steps = value.as(Int.self) {
                                Text(MonthCalendarView.abbreviated(steps))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { value in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                    }
                }
                .frame(height: 190)
                .padding(14)
                .background(Color.card, in: .rect(cornerRadius: 16))
            }
        }
    }

    // MARK: - Workouts

    private var recentWorkouts: [Workout] {
        guard let cutoff = calendar.date(byAdding: .day, value: -28, to: .now) else { return [] }
        return activity.workouts(onOrAfter: cutoff)
    }

    @ViewBuilder
    private var workoutHistory: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Workouts").font(.headline)
                Spacer()
                Text("last 4 weeks")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if recentWorkouts.isEmpty {
                Text("Nothing logged in the last four weeks. Workouts recorded on your phone or watch appear here on their own.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color.card, in: .rect(cornerRadius: 16))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentWorkouts.prefix(12).enumerated()), id: \.element.id) { index, workout in
                        workoutRow(workout)
                        if index < min(recentWorkouts.count, 12) - 1 {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .background(Color.card, in: .rect(cornerRadius: 16))
            }
        }
    }

    private func workoutRow(_ workout: Workout) -> some View {
        HStack(spacing: 12) {
            Image(systemName: workout.symbol)
                .font(.system(size: 15))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(workout.kind).font(.subheadline.weight(.medium))
                Text(workout.start, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(workout.durationText)
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                HStack(spacing: 5) {
                    if let miles = workout.miles, miles >= 0.1 {
                        Text("\(miles, format: .number.precision(.fractionLength(1))) mi")
                    }
                    if let kcal = workout.activeKilocalories {
                        Text("\(Int(kcal)) kcal")
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
    }
}

#Preview {
    ActivityView(activity: ActivityStore())
}

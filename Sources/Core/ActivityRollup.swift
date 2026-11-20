import Foundation

/// A week of activity, summarised.
///
/// `daysWithData` travels alongside the totals for the same reason
/// `WeeklyAverage.entryCount` does on the weight side: an average over two
/// days and an average over seven are not the same claim, and the screen says
/// which it is holding.
struct ActivityWeek: Identifiable, Hashable, Sendable {
    let start: Date
    let totalSteps: Int
    let daysWithData: Int
    let daysAtGoal: Int
    let activeKilocalories: Double

    var id: Date { start }

    /// Averaged over the days that reported, not over seven. A week where the
    /// phone was left at home twice was not a week of five-sevenths effort.
    var averageSteps: Int {
        daysWithData > 0 ? totalSteps / daysWithData : 0
    }

    /// Every day of the week reported. Says how dense the data is, not
    /// whether the week is over.
    var hasEveryDay: Bool { daysWithData >= 7 }

    /// The week has ended.
    ///
    /// This is the distinction the UI actually wants, and conflating it with
    /// `hasEveryDay` was a bug: a finished week where the phone was left at
    /// home one day is still a finished week, and drawing it as "in progress"
    /// made the chart alternate at random.
    func isFinished(asOf now: Date = .now, calendar: Calendar) -> Bool {
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return true }
        return end <= now
    }
}

/// Summaries over daily activity. Pure, so every case below is testable
/// without a month of real walking.
enum ActivityRollup {

    /// Groups days into weeks, newest last. Weeks with no data at all are
    /// omitted rather than reported as zeroes.
    static func weeks(
        from byDay: [Date: DailyActivity],
        goal: Int,
        calendar: Calendar
    ) -> [ActivityWeek] {
        guard !byDay.isEmpty else { return [] }

        let grouped = Dictionary(grouping: byDay.values) { activity in
            calendar.dateInterval(of: .weekOfYear, for: activity.day)?.start
                ?? calendar.startOfDay(for: activity.day)
        }

        return grouped
            .map { start, days in
                ActivityWeek(
                    start: start,
                    totalSteps: days.reduce(0) { $0 + $1.steps },
                    daysWithData: days.count,
                    daysAtGoal: days.count { $0.steps >= goal },
                    activeKilocalories: days.reduce(0) { $0 + $1.activeKilocalories }
                )
            }
            .sorted { $0.start < $1.start }
    }

    /// Consecutive days meeting the goal, counting back from today.
    ///
    /// One judgement call, and it is the whole reason this is a function and
    /// not a loop in a view: **a day still in progress does not break a
    /// streak.** At nine in the morning nobody has walked 15,000 steps, and an
    /// app that zeroes a three-week streak every midnight is an app that
    /// teaches you to stop looking at it. So if today has not met the goal
    /// yet, the count starts at yesterday; if today *has*, it counts.
    ///
    /// A day that is genuinely missing — no reading at all — does break the
    /// streak, because we have no evidence it was walked.
    static func currentStreak(
        from byDay: [Date: DailyActivity],
        goal: Int,
        asOf today: Date,
        calendar: Calendar
    ) -> Int {
        let startOfToday = calendar.startOfDay(for: today)
        var streak = 0
        var day = startOfToday

        // Today counts only if it already qualifies; otherwise step back one
        // day and judge the streak on finished days alone.
        if (byDay[startOfToday]?.steps ?? 0) < goal {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) else {
                return 0
            }
            day = yesterday
        }

        while let activity = byDay[day], activity.steps >= goal {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }

        return streak
    }

    /// The longest run of goal-meeting days anywhere in the data.
    static func longestStreak(
        from byDay: [Date: DailyActivity],
        goal: Int,
        calendar: Calendar
    ) -> Int {
        let qualifying = byDay.values
            .filter { $0.steps >= goal }
            .map { calendar.startOfDay(for: $0.day) }
            .sorted()
        guard !qualifying.isEmpty else { return 0 }

        var longest = 1
        var run = 1
        for (previous, current) in zip(qualifying, qualifying.dropFirst()) {
            let gap = calendar.dateComponents([.day], from: previous, to: current).day ?? 0
            run = gap == 1 ? run + 1 : 1
            longest = max(longest, run)
        }
        return longest
    }

    /// This week against last, as a share: +0.12 is twelve per cent more.
    ///
    /// Returns `nil` when last week has no data to compare against, rather
    /// than reporting an infinite improvement over nothing.
    static func weekOverWeekChange(_ weeks: [ActivityWeek]) -> Double? {
        guard weeks.count >= 2 else { return nil }
        let this = weeks[weeks.count - 1]
        let last = weeks[weeks.count - 2]
        guard last.averageSteps > 0 else { return nil }
        return (Double(this.averageSteps) - Double(last.averageSteps)) / Double(last.averageSteps)
    }
}

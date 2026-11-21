import Foundation

/// A year of activity, summarised.
///
/// Everything here is counted over **days that reported**, never over 365.
/// A year with two months of data is not a year of mostly standing still,
/// and `daysWithData` travels alongside every figure so the screen can say
/// how much of the year it is actually describing.
struct YearSummary: Equatable, Sendable {
    let year: Int
    let totalSteps: Int
    let daysWithData: Int
    let daysAtGoal: Int
    let activeKilocalories: Double

    /// The single best day, if any day reported.
    let bestDay: (date: Date, steps: Int)?

    /// Step totals and day counts per month, index 0 = January. Months with
    /// no data have zero of both, and the pair is what lets the UI tell a
    /// quiet month from an unrecorded one.
    let monthlySteps: [Int]
    let monthlyDaysWithData: [Int]

    /// Averaged over days that reported.
    var averageSteps: Int {
        daysWithData > 0 ? totalSteps / daysWithData : 0
    }

    /// The month with the highest daily average, among months that reported.
    /// Highest *average* rather than highest total, so a fully logged
    /// February does not lose to a half-logged August.
    var bestMonth: (month: Int, averageSteps: Int)? {
        let candidates = (0..<12).compactMap { index -> (Int, Int)? in
            guard monthlyDaysWithData[index] > 0 else { return nil }
            return (index, monthlySteps[index] / monthlyDaysWithData[index])
        }
        guard let best = candidates.max(by: { $0.1 < $1.1 }) else { return nil }
        return (month: best.0, averageSteps: best.1)
    }

    var hasData: Bool { daysWithData > 0 }

    static func == (a: YearSummary, b: YearSummary) -> Bool {
        a.year == b.year
            && a.totalSteps == b.totalSteps
            && a.daysWithData == b.daysWithData
            && a.daysAtGoal == b.daysAtGoal
            && a.bestDay?.date == b.bestDay?.date
            && a.bestDay?.steps == b.bestDay?.steps
            && a.monthlySteps == b.monthlySteps
            && a.monthlyDaysWithData == b.monthlyDaysWithData
    }
}

extension ActivityRollup {

    /// Summarises one calendar year from whatever days are present.
    static func yearSummary(
        from byDay: [Date: DailyActivity],
        goal: Int,
        year: Int,
        calendar: Calendar
    ) -> YearSummary {
        var monthlySteps = Array(repeating: 0, count: 12)
        var monthlyDays = Array(repeating: 0, count: 12)
        var total = 0
        var days = 0
        var atGoal = 0
        var energy = 0.0
        var best: (date: Date, steps: Int)?

        for activity in byDay.values {
            let components = calendar.dateComponents([.year, .month], from: activity.day)
            guard components.year == year, let month = components.month else { continue }

            let index = month - 1
            monthlySteps[index] += activity.steps
            monthlyDays[index] += 1

            total += activity.steps
            days += 1
            energy += activity.activeKilocalories
            if activity.steps >= goal { atGoal += 1 }
            // Ties go to the earlier day: the first time you hit a number is
            // the day worth remembering.
            if best == nil || activity.steps > best!.steps
                || (activity.steps == best!.steps && activity.day < best!.date) {
                best = (date: activity.day, steps: activity.steps)
            }
        }

        return YearSummary(
            year: year,
            totalSteps: total,
            daysWithData: days,
            daysAtGoal: atGoal,
            activeKilocalories: energy,
            bestDay: best,
            monthlySteps: monthlySteps,
            monthlyDaysWithData: monthlyDays
        )
    }

    /// Years that have at least one day of data, newest first — what the year
    /// picker can actually offer.
    static func yearsWithData(
        from byDay: [Date: DailyActivity],
        calendar: Calendar
    ) -> [Int] {
        Set(byDay.keys.compactMap { calendar.dateComponents([.year], from: $0).year })
            .sorted(by: >)
    }
}

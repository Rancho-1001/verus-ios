import Foundation
import Testing

@testable import Verus

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    c.firstWeekday = 2
    return c
}()

private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    DateComponents(calendar: cal, timeZone: cal.timeZone,
                   year: year, month: month, day: day).date!
}

private func activity(_ steps: Int, _ year: Int, _ month: Int, _ day: Int) -> (Date, DailyActivity) {
    let d = cal.startOfDay(for: date(year, month, day))
    return (d, DailyActivity(day: d, steps: steps, activeKilocalories: Double(steps) * 0.04, restingKilocalories: 1_700))
}

private let goal = 15_000

@Suite("Year summary")
struct YearSummaryTests {

    @Test("an empty year reports no data rather than a year of zeroes")
    func emptyYear() {
        let summary = ActivityRollup.yearSummary(from: [:], goal: goal, year: 2026, calendar: cal)
        #expect(!summary.hasData)
        #expect(summary.averageSteps == 0)
        #expect(summary.bestDay == nil)
        #expect(summary.bestMonth == nil)
    }

    @Test("the average is over days that reported, not over 365")
    func averageOverReportedDays() {
        // Ten days at 20,000 and nothing else. A year is not mostly standing
        // still because it was not mostly logged.
        let days = Dictionary(uniqueKeysWithValues: (1...10).map { activity(20_000, 2026, 3, $0) })
        let summary = ActivityRollup.yearSummary(from: days, goal: goal, year: 2026, calendar: cal)
        #expect(summary.daysWithData == 10)
        #expect(summary.totalSteps == 200_000)
        #expect(summary.averageSteps == 20_000)  // not 200_000 / 365 = 547
        #expect(summary.daysAtGoal == 10)
    }

    @Test("days from other years are excluded")
    func scopedToTheYear() {
        let days = Dictionary(uniqueKeysWithValues: [
            activity(10_000, 2025, 12, 31),
            activity(20_000, 2026, 1, 1),
            activity(30_000, 2027, 1, 1),
        ])
        let summary = ActivityRollup.yearSummary(from: days, goal: goal, year: 2026, calendar: cal)
        #expect(summary.daysWithData == 1)
        #expect(summary.totalSteps == 20_000)
    }

    @Test("the best day is the highest, and ties go to the earlier one")
    func bestDay() throws {
        let days = Dictionary(uniqueKeysWithValues: [
            activity(12_000, 2026, 2, 3),
            activity(31_000, 2026, 6, 14),
            activity(31_000, 2026, 9, 2),   // same count, later date
            activity(9_000, 2026, 11, 20),
        ])
        let summary = ActivityRollup.yearSummary(from: days, goal: goal, year: 2026, calendar: cal)
        let best = try #require(summary.bestDay)
        #expect(best.steps == 31_000)
        // The first time you hit a number is the day worth remembering.
        #expect(cal.component(.month, from: best.date) == 6)
    }

    @Test("monthly totals land in the right months")
    func monthlyBuckets() {
        let days = Dictionary(uniqueKeysWithValues: [
            activity(10_000, 2026, 1, 5),
            activity(10_000, 2026, 1, 6),
            activity(8_000, 2026, 7, 1),
        ])
        let summary = ActivityRollup.yearSummary(from: days, goal: goal, year: 2026, calendar: cal)
        #expect(summary.monthlySteps[0] == 20_000)   // January
        #expect(summary.monthlyDaysWithData[0] == 2)
        #expect(summary.monthlySteps[6] == 8_000)    // July
        #expect(summary.monthlySteps[3] == 0)        // April, untouched
        #expect(summary.monthlyDaysWithData[3] == 0)
    }

    @Test("the best month is by daily average, not by total")
    func bestMonthIsAnAverage() throws {
        // February: 3 days at 25,000 → average 25,000, total 75,000.
        // August: 20 days at 12,000 → average 12,000, total 240,000.
        // The bigger total belongs to the weaker month; a half-logged month
        // must not win on volume alone, and a fully logged one must not lose.
        var days: [Date: DailyActivity] = [:]
        for d in 1...3 { let (k, v) = activity(25_000, 2026, 2, d); days[k] = v }
        for d in 1...20 { let (k, v) = activity(12_000, 2026, 8, d); days[k] = v }

        let summary = ActivityRollup.yearSummary(from: days, goal: goal, year: 2026, calendar: cal)
        #expect(summary.monthlySteps[7] > summary.monthlySteps[1])  // August has the bigger total

        let best = try #require(summary.bestMonth)
        #expect(best.month == 1)  // but February wins on average
        #expect(best.averageSteps == 25_000)
    }

    @Test("a month with no data cannot be the best month")
    func emptyMonthsExcluded() throws {
        let days = Dictionary(uniqueKeysWithValues: [activity(9_000, 2026, 5, 1)])
        let summary = ActivityRollup.yearSummary(from: days, goal: goal, year: 2026, calendar: cal)
        let best = try #require(summary.bestMonth)
        #expect(best.month == 4)  // May, the only one with anything in it
    }

    @Test("miles are summed over the days that reported one")
    func distance() throws {
        let days: [Date: DailyActivity] = Dictionary(uniqueKeysWithValues: (1...3).map { day in
            let d = cal.startOfDay(for: date(2026, 4, day))
            return (d, DailyActivity(
                day: d, steps: 12_000, activeKilocalories: 480, restingKilocalories: 1_700,
                // Three days at a mile and a half each.
                distanceMeters: day == 2 ? nil : 1.5 * DailyActivity.metersPerMile
            ))
        })
        let summary = ActivityRollup.yearSummary(from: days, goal: goal, year: 2026, calendar: cal)
        let miles = try #require(summary.miles)
        // The day with no distance contributes nothing rather than a zero
        // that drags the total down — and the step count still counts.
        #expect(abs(miles - 3.0) < 0.001)
        #expect(summary.daysWithData == 3)
    }

    @Test("a year with no distance reports none rather than zero miles")
    func noDistance() {
        let days = Dictionary(uniqueKeysWithValues: [activity(9_000, 2026, 5, 1)])
        let summary = ActivityRollup.yearSummary(from: days, goal: goal, year: 2026, calendar: cal)
        #expect(summary.distanceMeters == 0)
        #expect(summary.miles == nil)
    }

    @Test("only years with data are offered, newest first")
    func yearsWithData() {
        let days = Dictionary(uniqueKeysWithValues: [
            activity(10_000, 2024, 6, 1),
            activity(10_000, 2026, 1, 1),
            activity(10_000, 2026, 5, 1),
        ])
        #expect(ActivityRollup.yearsWithData(from: days, calendar: cal) == [2026, 2024])
        #expect(ActivityRollup.yearsWithData(from: [:], calendar: cal).isEmpty)
    }
}

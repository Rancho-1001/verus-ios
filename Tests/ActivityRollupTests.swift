import Foundation
import Testing

@testable import Verus

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    c.firstWeekday = 2
    return c
}()

/// Monday 2 November 2026.
private let monday = DateComponents(
    calendar: cal, timeZone: cal.timeZone, year: 2026, month: 11, day: 2
).date!

private func day(_ offset: Int) -> Date {
    cal.date(byAdding: .day, value: offset, to: monday)!
}

/// Days of activity starting at `monday`, one entry per step count given.
/// A `nil` is a day with no reading at all.
private func activity(_ steps: [Int?], from offset: Int = 0) -> [Date: DailyActivity] {
    var result: [Date: DailyActivity] = [:]
    for (index, value) in steps.enumerated() {
        guard let value else { continue }
        let date = day(offset + index)
        result[date] = DailyActivity(
            day: date,
            steps: value,
            activeKilocalories: Double(value) * 0.04,
            restingKilocalories: 1_700
        )
    }
    return result
}

private let goal = 15_000

// MARK: - Weeks

@Suite("Activity weeks")
struct ActivityWeekTests {

    @Test("no data means no weeks")
    func empty() {
        #expect(ActivityRollup.weeks(from: [:], goal: goal, calendar: cal).isEmpty)
    }

    @Test("a week totals and counts its days")
    func totalsOneWeek() throws {
        let weeks = ActivityRollup.weeks(
            from: activity([16_000, 14_000, 15_000, 9_000, 20_000, 12_000, 18_000]),
            goal: goal, calendar: cal
        )
        let week = try #require(weeks.first)
        #expect(weeks.count == 1)
        #expect(week.totalSteps == 104_000)
        #expect(week.daysWithData == 7)
        #expect(week.daysAtGoal == 4)  // 16k, 15k, 20k, 18k
        #expect(week.hasEveryDay)
    }

    @Test("the average is over days that reported, not over seven")
    func averageIgnoresMissingDays() throws {
        // Three days at 18,000 and four days the phone was elsewhere.
        let weeks = ActivityRollup.weeks(
            from: activity([18_000, 18_000, 18_000, nil, nil, nil, nil]),
            goal: goal, calendar: cal
        )
        let week = try #require(weeks.first)
        #expect(week.daysWithData == 3)
        #expect(week.averageSteps == 18_000)  // not 54_000 / 7 = 7_714
        #expect(!week.hasEveryDay)
    }

    @Test("a finished week with a missing day is still finished")
    func finishedIsAboutTimeNotDensity() throws {
        // The bug this pins: `isComplete` meant "all seven days reported", and
        // the chart used it to decide which bars were still in progress. A
        // week from two months ago where the phone was left at home once came
        // out faint, so the chart appeared to alternate at random.
        let weeks = ActivityRollup.weeks(
            from: activity([18_000, 18_000, nil, 18_000, 18_000, 18_000, 18_000]),
            goal: goal, calendar: cal
        )
        let week = try #require(weeks.first)
        let wellAfter = cal.date(byAdding: .day, value: 30, to: monday)!

        #expect(!week.hasEveryDay)                                 // six of seven
        #expect(week.isFinished(asOf: wellAfter, calendar: cal))   // but over
    }

    @Test("a week still running is not finished")
    func currentWeekIsUnfinished() throws {
        let weeks = ActivityRollup.weeks(
            from: activity([18_000, 18_000, 18_000]), goal: goal, calendar: cal
        )
        let week = try #require(weeks.first)
        // Thursday of the same week.
        #expect(!week.isFinished(asOf: day(3), calendar: cal))
    }

    @Test("days split across a week boundary make two weeks, in order")
    func splitsOnBoundary() {
        let weeks = ActivityRollup.weeks(
            from: activity(Array(repeating: 10_000, count: 10)),
            goal: goal, calendar: cal
        )
        #expect(weeks.count == 2)
        #expect(weeks[0].daysWithData == 7)
        #expect(weeks[1].daysWithData == 3)
        #expect(weeks[0].start < weeks[1].start)
    }
}

// MARK: - Streaks

@Suite("Streaks")
struct StreakTests {

    @Test("a day still in progress does not break the streak")
    func todayInProgressIsForgiven() {
        // Three strong finished days, and today is only part-walked.
        let data = activity([16_000, 17_000, 18_000, 4_000])
        let streak = ActivityRollup.currentStreak(
            from: data, goal: goal, asOf: day(3), calendar: cal
        )
        // Counting back from yesterday: three days. Not zero.
        #expect(streak == 3)
    }

    @Test("today counts as soon as it qualifies")
    func todayCountsOnceMet() {
        let data = activity([16_000, 17_000, 18_000, 15_500])
        let streak = ActivityRollup.currentStreak(
            from: data, goal: goal, asOf: day(3), calendar: cal
        )
        #expect(streak == 4)
    }

    @Test("a finished day below goal ends the streak")
    func missedDayBreaksIt() {
        let data = activity([16_000, 17_000, 9_000, 18_000, 16_000])
        let streak = ActivityRollup.currentStreak(
            from: data, goal: goal, asOf: day(4), calendar: cal
        )
        #expect(streak == 2)  // day 4 and day 3 only
    }

    @Test("a day with no reading at all breaks the streak")
    func missingDayBreaksIt() {
        // No evidence the gap day was walked, so it cannot be credited.
        let data = activity([16_000, 17_000, nil, 18_000, 16_000])
        let streak = ActivityRollup.currentStreak(
            from: data, goal: goal, asOf: day(4), calendar: cal
        )
        #expect(streak == 2)
    }

    @Test("no data means no streak rather than a crash")
    func emptyIsZero() {
        #expect(ActivityRollup.currentStreak(from: [:], goal: goal, asOf: day(3), calendar: cal) == 0)
    }

    @Test("the longest streak is found wherever it sits in the data")
    func longest() {
        //            ✓       ✓      ✗      ✓       ✓       ✓      ✗      ✓
        let data = activity([16_000, 16_000, 1_000, 16_000, 16_000, 16_000, 1_000, 16_000])
        #expect(ActivityRollup.longestStreak(from: data, goal: goal, calendar: cal) == 3)
    }

    @Test("a single qualifying day is a streak of one")
    func singleDay() {
        #expect(ActivityRollup.longestStreak(from: activity([16_000]), goal: goal, calendar: cal) == 1)
    }
}

// MARK: - Week over week

@Suite("Week over week")
struct WeekOverWeekTests {

    @Test("more steps than last week reads as a positive share")
    func improvement() throws {
        // 10,000/day then 12,000/day.
        var data = activity(Array(repeating: 10_000, count: 7))
        data.merge(activity(Array(repeating: 12_000, count: 7), from: 7)) { a, _ in a }

        let weeks = ActivityRollup.weeks(from: data, goal: goal, calendar: cal)
        let change = try #require(ActivityRollup.weekOverWeekChange(weeks))
        #expect(abs(change - 0.2) < 0.001)
    }

    @Test("one week of data gives no comparison rather than a fake one")
    func needsTwoWeeks() {
        let weeks = ActivityRollup.weeks(
            from: activity(Array(repeating: 10_000, count: 7)), goal: goal, calendar: cal
        )
        #expect(ActivityRollup.weekOverWeekChange(weeks) == nil)
    }

    @Test("a previous week of nothing gives no comparison, not infinite gain")
    func noDivisionByZero() {
        var data = activity(Array(repeating: 0, count: 7))
        data.merge(activity(Array(repeating: 12_000, count: 7), from: 7)) { a, _ in a }
        let weeks = ActivityRollup.weeks(from: data, goal: goal, calendar: cal)
        #expect(ActivityRollup.weekOverWeekChange(weeks) == nil)
    }
}

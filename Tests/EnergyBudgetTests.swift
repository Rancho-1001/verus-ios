import Foundation
import Testing

@testable import Verus

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    c.firstWeekday = 2
    return c
}()

private let today = DateComponents(
    calendar: cal, timeZone: cal.timeZone, year: 2026, month: 11, day: 20, hour: 12
).date!

private func day(_ offset: Int, hour: Int = 12) -> Date {
    cal.date(byAdding: .day, value: offset, to: today)!
        .addingTimeInterval(TimeInterval((hour - 12) * 3600))
}

private func food(
    _ kcal: Double,
    on offset: Int = 0,
    meal: Meal = .lunch,
    protein: Double? = nil,
    name: String = "Something"
) -> FoodEntry {
    FoodEntry(
        date: day(offset), name: name, kilocalories: kcal,
        proteinGrams: protein, meal: meal
    )
}

private func burned(_ active: Double, resting: Double = 1_700, on offset: Int = 0) -> DailyActivity {
    DailyActivity(
        day: cal.startOfDay(for: day(offset)),
        steps: 10_000,
        activeKilocalories: active,
        restingKilocalories: resting
    )
}

// MARK: - Balance

@Suite("A day's energy balance")
struct BalanceTests {

    @Test("nothing logged and nothing burned is no data, not a zero balance")
    func untouchedDay() {
        let result = EnergyBudget.day(today, entries: [], activity: nil, now: today, calendar: cal)
        #expect(result.balance == .noData)
    }

    @Test("food logged with no burn figure gives an intake, not an invented deficit")
    func intakeOnly() {
        // The honest failure: without expenditure there is no budget. Guessing
        // a plausible burn here would be guessing the deficit too.
        let result = EnergyBudget.day(
            today, entries: [food(600), food(900)], activity: nil, now: today, calendar: cal
        )
        #expect(result.balance == .intakeOnly(kilocalories: 1_500))
    }

    @Test("burn with nothing logged is not a deficit the size of the burn")
    func unloggedDayIsNotADeficit() {
        // The bug this pins: a day with 2,000 kcal of burn and no food logged
        // came back as .known(intake: 0, net: -2000) and was presented as a
        // 2,000 calorie deficit. It is an unlogged day. Calling it a deficit
        // flatters the user and poisons every average built on top of it.
        let result = EnergyBudget.day(
            today, entries: [], activity: burned(500), now: today, calendar: cal
        )
        #expect(result.balance == .burnOnly(kilocalories: 2_200))
        #expect(result.balance.intake == 0)
    }

    @Test("unlogged days are left out of the average, not counted as huge deficits")
    func unloggedDaysDoNotSkewTheAverage() throws {
        // Two logged days at -400, and five days where the phone recorded
        // burn but nothing was eaten into the app. The average must be -400.
        var days = (1...2).map { offset in
            EnergyBudget.day(
                day(-offset), entries: [food(1_800, on: -offset)],
                activity: burned(500, on: -offset), now: today, calendar: cal
            )
        }
        days += (3...7).map { offset in
            EnergyBudget.day(
                day(-offset), entries: [], activity: burned(500, on: -offset),
                now: today, calendar: cal
            )
        }
        let average = try #require(EnergyBudget.averageNet(from: days))
        #expect(abs(average + 400) < 0.001)
    }

    @Test("both known gives a net, and a deficit is negative")
    func deficit() {
        let result = EnergyBudget.day(
            today,
            entries: [food(1_800)],
            activity: burned(500),   // 500 active + 1700 resting = 2200
            now: today, calendar: cal
        )
        #expect(result.balance == .known(intake: 1_800, burn: 2_200, net: -400))
    }

    @Test("eating more than you burn reads as a positive net")
    func surplus() throws {
        let result = EnergyBudget.day(
            today, entries: [food(2_900)], activity: burned(400), now: today, calendar: cal
        )
        guard case .known(_, _, let net) = result.balance else {
            Issue.record("expected .known, got \(result.balance)")
            return
        }
        #expect(net > 0)
        #expect(abs(net - 800) < 0.001)
    }

    @Test("only the chosen day's food counts")
    func ignoresOtherDays() {
        let result = EnergyBudget.day(
            today,
            entries: [food(500, on: 0), food(9_999, on: -1), food(9_999, on: 1)],
            activity: burned(300),
            now: today, calendar: cal
        )
        #expect(result.balance.intake == 500)
        #expect(result.itemCount == 1)
    }
}

// MARK: - In progress

@Suite("Today is not over")
struct InProgressTests {

    @Test("today is flagged as still running")
    func todayIsInProgress() {
        let result = EnergyBudget.day(today, entries: [food(900)], activity: burned(300), now: today, calendar: cal)
        #expect(result.isInProgress)
    }

    @Test("a past day is settled")
    func yesterdayIsFinished() {
        let result = EnergyBudget.day(
            day(-1), entries: [food(2_000, on: -1)], activity: burned(500, on: -1),
            now: today, calendar: cal
        )
        #expect(!result.isInProgress)
    }
}

// MARK: - Macros

@Suite("Macros")
struct MacroTests {

    @Test("macro totals come only from items that carried them")
    func partialMacros() {
        // Three items, one with protein. The total is real but it is a total
        // over one item, and the count travels with it so the screen can say
        // so instead of implying the day is fully logged.
        let result = EnergyBudget.day(
            today,
            entries: [food(400, protein: 30), food(500), food(600)],
            activity: burned(300), now: today, calendar: cal
        )
        #expect(result.proteinGrams == 30)
        #expect(result.itemsWithMacros == 1)
        #expect(result.itemCount == 3)
    }
}

// MARK: - Grouping

@Suite("Grouping by meal")
struct MealGroupingTests {

    @Test("meals come back in the order of the day, and empty ones are absent")
    func mealOrder() {
        let grouped = EnergyBudget.byMeal([
            food(300, meal: .dinner),
            food(200, meal: .breakfast),
            food(100, meal: .snack),
        ])
        #expect(grouped.map(\.meal) == [.breakfast, .dinner, .snack])
        #expect(!grouped.map(\.meal).contains(.lunch))
    }

    @Test("a meal's items are chronological within it")
    func withinMeal() {
        let early = FoodEntry(date: day(0, hour: 7), name: "A", kilocalories: 100, meal: .breakfast)
        let late = FoodEntry(date: day(0, hour: 9), name: "B", kilocalories: 100, meal: .breakfast)
        let grouped = EnergyBudget.byMeal([late, early])
        #expect(grouped.first?.entries.map(\.name) == ["A", "B"])
    }

    @Test("a meal suggests itself from the time of day")
    func suggestion() {
        #expect(Meal.suggested(at: day(0, hour: 8), calendar: cal) == .breakfast)
        #expect(Meal.suggested(at: day(0, hour: 13), calendar: cal) == .lunch)
        #expect(Meal.suggested(at: day(0, hour: 19), calendar: cal) == .dinner)
        #expect(Meal.suggested(at: day(0, hour: 23), calendar: cal) == .snack)
    }
}

// MARK: - Averages

@Suite("Average net")
struct AverageNetTests {

    private func days(_ specs: [(offset: Int, intake: Double, active: Double)]) -> [EnergyBudget.Day] {
        specs.map { spec in
            EnergyBudget.day(
                day(spec.offset),
                entries: [food(spec.intake, on: spec.offset)],
                activity: burned(spec.active, on: spec.offset),
                now: today, calendar: cal
            )
        }
    }

    @Test("today is left out so a part-day cannot drag the average down")
    func excludesToday() throws {
        // Two finished days at -400, plus today showing -1,900 because it is
        // only lunchtime. The average must be -400, not -900.
        let all = days([(-2, 1_800, 500), (-1, 1_800, 500), (0, 300, 500)])
        let average = try #require(EnergyBudget.averageNet(from: all))
        #expect(abs(average + 400) < 0.001)
    }

    @Test("days without both numbers are left out, not counted as zero")
    func excludesIncompleteDays() throws {
        var all = days([(-2, 1_800, 500), (-1, 1_800, 500)])
        all.append(
            EnergyBudget.day(day(-3), entries: [food(1_000, on: -3)], activity: nil, now: today, calendar: cal)
        )
        let average = try #require(EnergyBudget.averageNet(from: all))
        #expect(abs(average + 400) < 0.001)
    }

    @Test("no qualifying days gives no average rather than a balanced zero")
    func nothingToAverage() {
        let onlyToday = days([(0, 1_200, 400)])
        #expect(EnergyBudget.averageNet(from: onlyToday) == nil)
        #expect(EnergyBudget.averageNet(from: []) == nil)
    }
}

// MARK: - Implied loss

@Suite("What a deficit implies")
struct ImpliedLossTests {

    @Test("a 500 kcal daily deficit implies about a pound a week")
    func conventionalArithmetic() {
        let pounds = EnergyBudget.impliedPoundsPerWeek(fromDailyNet: -500)
        #expect(abs(pounds + 1) < 0.001)
    }

    @Test("a surplus implies gaining, with the sign to match")
    func surplusGains() {
        #expect(EnergyBudget.impliedPoundsPerWeek(fromDailyNet: 500) > 0)
    }
}

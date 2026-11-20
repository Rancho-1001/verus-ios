import Foundation
import Testing

@testable import Verus

/// A fixed calendar so none of these tests depend on where the machine is or
/// what time it is run. Gregorian, UTC, weeks starting Monday.
private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    c.firstWeekday = 2
    return c
}()

/// 1 January 2026 was a Thursday.
private let origin = DateComponents(
    calendar: cal, timeZone: cal.timeZone,
    year: 2026, month: 1, day: 1, hour: 7
).date!

private func day(_ offset: Int, hour: Int = 7) -> Date {
    cal.date(byAdding: .day, value: offset, to: origin)!
        .addingTimeInterval(TimeInterval((hour - 7) * 3600))
}

/// Weigh-ins on consecutive days, in pounds, starting at `origin`.
private func entries(_ pounds: [Double], startingAt offset: Int = 0) -> [WeightEntry] {
    pounds.enumerated().map { index, lb in
        WeightEntry.fromPounds(lb, date: day(offset + index))
    }
}

// MARK: - Weekly averages

@Suite("Weekly averages — the true weight of the week")
struct WeeklyAverageTests {

    @Test("no entries means no weeks, not a week of zero")
    func empty() {
        #expect(TrendEngine.weeklyAverages(from: [], calendar: cal).isEmpty)
    }

    @Test("a week's weigh-ins average to its true weight")
    func averagesOneWeek() throws {
        // Thu–Sun of the same week: 180, 181, 179, 180 → 180.0
        let weeks = TrendEngine.weeklyAverages(
            from: entries([180, 181, 179, 180]),
            calendar: cal
        )
        let week = try #require(weeks.first)
        #expect(weeks.count == 1)
        #expect(week.entryCount == 4)
        #expect(abs(week.pounds - 180.0) < 0.000_1)
    }

    @Test("weigh-ins split across a week boundary make two weeks")
    func splitsOnWeekBoundary() {
        // Thu 1 Jan → Wed 7 Jan. With weeks starting Monday, 5 Jan opens a new
        // one, so this is 4 days + 3 days rather than a single seven-day run.
        let weeks = TrendEngine.weeklyAverages(from: entries(Array(repeating: 180, count: 7)), calendar: cal)
        #expect(weeks.count == 2)
        #expect(weeks[0].entryCount == 4)
        #expect(weeks[1].entryCount == 3)
        #expect(weeks[0].weekStart < weeks[1].weekStart)
    }

    @Test("a week with too few weigh-ins is reported but flagged unreliable")
    func reliabilityIsCarriedNotHidden() {
        let weeks = TrendEngine.weeklyAverages(from: entries([180, 179]), calendar: cal)
        #expect(weeks.count == 1)
        #expect(weeks[0].isReliable == false)
    }

    @Test("weeks come back in chronological order whatever order they went in")
    func sorted() {
        let shuffled = entries(Array(repeating: 180, count: 21)).shuffled()
        let weeks = TrendEngine.weeklyAverages(from: shuffled, calendar: cal)
        #expect(weeks == weeks.sorted { $0.weekStart < $1.weekStart })
    }
}

// MARK: - Smoothed trend

@Suite("Smoothed daily trend")
struct SmoothedTrendTests {

    @Test("the first weigh-in seeds the line instead of being smoothed from nothing")
    func firstPointIsTheReading() throws {
        let trend = TrendEngine.smoothedTrend(from: entries([180]), calendar: cal)
        let point = try #require(trend.first)
        #expect(abs(point.pounds - 180) < 0.000_1)
    }

    @Test("one heavy morning moves the trend far less than it moves the scale")
    func spikeIsAbsorbed() throws {
        // Fourteen steady days, then a 6 lb jump — a salty dinner, not six
        // pounds of fat. The trend should barely notice.
        var pounds = Array(repeating: 180.0, count: 14)
        pounds.append(186)
        let trend = TrendEngine.smoothedTrend(from: entries(pounds), calendar: cal)
        let last = try #require(trend.last)

        #expect(abs((last.rawKilograms ?? 0) * WeightEntry.poundsPerKilogram - 186) < 0.000_1)
        // With α = 0.10 the line takes a tenth of the gap: ~180.6, not 186.
        #expect(last.pounds < 181.0)
        #expect(last.pounds > 180.0)
    }

    @Test("days without a weigh-in carry the trend forward rather than closing the gap")
    func gapsAreRealDays() throws {
        // Weigh in on day 0, vanish for a fortnight, weigh in on day 14.
        let sparse = [
            WeightEntry.fromPounds(180, date: day(0)),
            WeightEntry.fromPounds(175, date: day(14)),
        ]
        let trend = TrendEngine.smoothedTrend(from: sparse, calendar: cal)
        // 15 calendar days, not 2 data points — otherwise the chart would
        // show a fortnight's loss as a single overnight step.
        #expect(trend.count == 15)
        #expect(trend.filter { $0.rawKilograms != nil }.count == 2)
    }

    @Test("two readings on one day keep the later one")
    func laterReadingWinsTheDay() throws {
        let sameDay = [
            WeightEntry.fromPounds(185, date: day(0, hour: 6)),
            WeightEntry.fromPounds(180, date: day(0, hour: 9)),
        ]
        let trend = TrendEngine.smoothedTrend(from: sameDay, calendar: cal)
        #expect(trend.count == 1)
        #expect(abs(try #require(trend.first).pounds - 180) < 0.000_1)
    }
}

// MARK: - Rate

@Suite("Rate of change")
struct RateTests {

    @Test("four days is not enough to claim a rate")
    func refusesTooFewDays() {
        let trend = TrendEngine.smoothedTrend(from: entries([180, 179.5, 179, 178.5]), calendar: cal)
        #expect(TrendEngine.rateKilogramsPerWeek(trend: trend) == nil)
    }

    @Test("a steady decline reads as a negative rate")
    func detectsLoss() throws {
        // 28 days losing 0.2 lb/day ≈ 1.4 lb/week.
        let pounds = (0..<28).map { 180 - Double($0) * 0.2 }
        let trend = TrendEngine.smoothedTrend(from: entries(pounds), calendar: cal)
        let rate = try #require(TrendEngine.rateKilogramsPerWeek(trend: trend))
        #expect(rate < 0)
        let lbPerWeek = rate * WeightEntry.poundsPerKilogram
        // The smoothed line lags the raw one, so it reads a little under the
        // true 1.4 — but it must be in the right neighbourhood, not half it.
        #expect(lbPerWeek < -0.8)
        #expect(lbPerWeek > -1.5)
    }

    @Test("a flat month reads as about zero, not as drift")
    func flatIsFlat() throws {
        let trend = TrendEngine.smoothedTrend(from: entries(Array(repeating: 180, count: 28)), calendar: cal)
        let rate = try #require(TrendEngine.rateKilogramsPerWeek(trend: trend))
        #expect(abs(rate) < TrendEngine.flatRateThreshold)
    }
}

// MARK: - Projection

@Suite("Projection — the app will not invent a date")
struct ProjectionTests {

    private func goal(_ pounds: Double) -> Double { pounds / WeightEntry.poundsPerKilogram }

    @Test("too little data gives no date")
    func notEnoughData() {
        let trend = TrendEngine.smoothedTrend(from: entries([180, 179, 178]), calendar: cal)
        let p = TrendEngine.projection(
            trend: trend, goalKilograms: goal(150), asOf: day(3), calendar: cal
        )
        #expect(p == .notEnoughData(needed: 14))
    }

    @Test("a flat trend refuses to project rather than promising a far date")
    func flatRefuses() {
        let trend = TrendEngine.smoothedTrend(from: entries(Array(repeating: 180, count: 30)), calendar: cal)
        let p = TrendEngine.projection(
            trend: trend, goalKilograms: goal(150), asOf: day(30), calendar: cal
        )
        #expect(p == .tooSlowToProject)
    }

    @Test("gaining while aiming to lose is named, not silently projected")
    func movingAwayIsSaidOutLoud() throws {
        let pounds = (0..<30).map { 180 + Double($0) * 0.15 }
        let trend = TrendEngine.smoothedTrend(from: entries(pounds), calendar: cal)
        let p = TrendEngine.projection(
            trend: trend, goalKilograms: goal(150), asOf: day(30), calendar: cal
        )
        guard case .movingAway(let rate) = p else {
            Issue.record("expected .movingAway, got \(p)")
            return
        }
        #expect(rate > 0)
    }

    @Test("already under the goal reads as reached")
    func reached() {
        let trend = TrendEngine.smoothedTrend(from: entries(Array(repeating: 145, count: 20)), calendar: cal)
        let p = TrendEngine.projection(
            trend: trend, goalKilograms: goal(150), asOf: day(20), calendar: cal
        )
        #expect(p == .reached)
    }

    @Test("a real decline gives a date, and the date is in the future")
    func onTrack() throws {
        // 180 → 174 over 30 days, aiming for 150.
        let pounds = (0..<30).map { 180 - Double($0) * 0.2 }
        let trend = TrendEngine.smoothedTrend(from: entries(pounds), calendar: cal)
        let today = day(30)
        let p = TrendEngine.projection(
            trend: trend, goalKilograms: goal(150), asOf: today, calendar: cal
        )
        guard case .onTrack(let date, let weeks, let rate) = p else {
            Issue.record("expected .onTrack, got \(p)")
            return
        }
        #expect(date > today)
        #expect(weeks > 0)
        #expect(rate < 0)
    }

    @Test("a slower pace always projects a later date — the projection cannot flatter")
    func slowerIsNeverSooner() throws {
        func dateFor(lossPerDay: Double) throws -> Date {
            let pounds = (0..<30).map { 180 - Double($0) * lossPerDay }
            let trend = TrendEngine.smoothedTrend(from: entries(pounds), calendar: cal)
            let p = TrendEngine.projection(
                trend: trend, goalKilograms: goal(150), asOf: day(30), calendar: cal
            )
            guard case .onTrack(let date, _, _) = p else {
                Issue.record("expected .onTrack for \(lossPerDay) lb/day, got \(p)")
                throw CancellationError()
            }
            return date
        }
        #expect(try dateFor(lossPerDay: 0.1) > dateFor(lossPerDay: 0.3))
    }
}

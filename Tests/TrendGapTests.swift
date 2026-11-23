import Foundation
import Testing

@testable import Verus

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/Detroit")!
    c.firstWeekday = 2
    return c
}()

private func day(_ month: Int, _ day: Int, _ hour: Int = 7) -> Date {
    DateComponents(
        calendar: cal, timeZone: cal.timeZone,
        year: 2026, month: month, day: day, hour: hour
    ).date!
}

@Suite("Smoothing across gaps")
struct TrendGapTests {

    @Test("weighing in daily is unchanged: alpha once a day")
    func dailyIsUnaffected() throws {
        // The rule is per elapsed day, so a daily series must behave exactly
        // as it always did — 180 then 190 lands a tenth of the way up.
        let entries = [
            WeightEntry.fromPounds(180, date: day(11, 1)),
            WeightEntry.fromPounds(190, date: day(11, 2)),
        ]
        let trend = TrendEngine.smoothedTrend(from: entries, calendar: cal)
        let last = try #require(trend.last)
        #expect(abs(last.pounds - 181.0) < 0.01)
    }

    @Test("a reading after a fortnight of silence counts for a fortnight")
    func gapCompounds() throws {
        // Fourteen days at alpha 0.10 is 1 - 0.9^14 ≈ 0.771 of the way,
        // not 0.10 of the way. The old rule left the line at 181.
        let entries = [
            WeightEntry.fromPounds(180, date: day(11, 1)),
            WeightEntry.fromPounds(190, date: day(11, 15)),
        ]
        let trend = TrendEngine.smoothedTrend(from: entries, calendar: cal)
        let last = try #require(trend.last)
        #expect(abs(last.pounds - 187.71) < 0.05)
    }

    @Test("after a month away the old trend has no claim left")
    func longGapNearlyReplaces() throws {
        let entries = [
            WeightEntry.fromPounds(180, date: day(9, 1)),
            WeightEntry.fromPounds(190, date: day(10, 1)),
        ]
        let trend = TrendEngine.smoothedTrend(from: entries, calendar: cal)
        let last = try #require(trend.last)
        // 1 - 0.9^30 ≈ 0.958: the reading, near enough.
        #expect(last.pounds > 189.5)
        #expect(last.pounds < 190.0)
    }

    @Test("a fortnightly logger is not stuck eight months behind")
    func sparseLoggerKeepsUp() throws {
        // The shape of the file that found this: a reading every twelve
        // days, drifting down two pounds over four months. The old rule
        // moved the line a tenth of a pound per reading and finished the
        // period barely off where it started.
        var entries: [WeightEntry] = []
        var pounds = 184.0
        for step in 0..<10 {
            let date = cal.date(byAdding: .day, value: step * 12, to: day(7, 1))!
            entries.append(WeightEntry.fromPounds(pounds, date: date))
            pounds -= 0.5
        }
        let trend = try #require(TrendEngine.smoothedTrend(from: entries, calendar: cal).last)
        let lastReading = try #require(entries.last).pounds

        // Within a pound of the last reading — a trend, still lagging, but
        // recognisably about the same month.
        #expect(abs(trend.pounds - lastReading) < 1.0)
    }

    @Test("the trend still lags a single morning, which is the point")
    func stillSmooths() throws {
        // Gap-aware does not mean "follow the scale". Four steady mornings
        // and then a salty one: the line must not jump to it.
        let entries = (0..<4).map {
            WeightEntry.fromPounds(180, date: day(11, 1 + $0))
        } + [WeightEntry.fromPounds(186, date: day(11, 5))]
        let trend = try #require(TrendEngine.smoothedTrend(from: entries, calendar: cal).last)
        #expect(abs(trend.pounds - 180.6) < 0.05)
    }

    @Test("one weigh-in is itself, with nothing to smooth against")
    func singleReading() throws {
        let trend = TrendEngine.smoothedTrend(
            from: [WeightEntry.fromPounds(180, date: day(11, 1))], calendar: cal
        )
        #expect(trend.count == 1)
        #expect(abs(try #require(trend.first).pounds - 180) < 0.01)
    }
}

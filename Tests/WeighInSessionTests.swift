import Foundation
import Testing

@testable import Verus

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/Detroit")!
    c.firstWeekday = 2
    return c
}()

private func at(_ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
    DateComponents(
        calendar: cal, timeZone: cal.timeZone,
        year: 2026, month: 11, day: day, hour: hour, minute: minute, second: second
    ).date!
}

@Suite("Weigh-in sessions")
struct WeighInSessionTests {

    @Test("a scale's burst is one weigh-in, and the settled reading wins")
    func burstCollapses() throws {
        // Taken from a real file: two records thirty-one seconds apart.
        let burst = [
            WeightEntry.fromPounds(180.4, date: at(11, 23, 29, 14), bodyFatPercent: 25.3),
            WeightEntry.fromPounds(177.9, date: at(11, 23, 29, 45), bodyFatPercent: 24.5),
        ]
        let collapsed = WeighInSession.collapse(burst)
        #expect(collapsed.count == 1)
        let kept = try #require(collapsed.first)
        #expect(abs(kept.pounds - 177.9) < 0.05)
        // The whole row is kept, so the composition belongs to the weight
        // beside it rather than to some other reading.
        #expect(kept.bodyFatPercent == 24.5)
    }

    @Test("three records chained seconds apart are still one weigh-in")
    func chainedBurst() {
        let burst = [
            WeightEntry.fromPounds(184.0, date: at(6, 23, 24, 14)),
            WeightEntry.fromPounds(182.9, date: at(6, 23, 24, 32)),
            WeightEntry.fromPounds(183.7, date: at(6, 23, 24, 55)),
        ]
        #expect(WeighInSession.collapse(burst).count == 1)
    }

    @Test("two minutes apart is two weigh-ins")
    func separateSessions() {
        // The closest pair in real data that is genuinely two sessions.
        let entries = [
            WeightEntry.fromPounds(175.0, date: at(21, 17, 30, 31)),
            WeightEntry.fromPounds(180.0, date: at(21, 17, 32, 30)),
        ]
        #expect(WeighInSession.collapse(entries).count == 2)
    }

    @Test("a slow drip does not chain into one endless session")
    func spanIsCapped() {
        // A reading every eighty seconds for twelve minutes is not one step
        // onto a scale, however short each gap is.
        let entries = (0..<9).map { i in
            WeightEntry.fromPounds(180, date: at(10, 7, 0, 0).addingTimeInterval(Double(i) * 80))
        }
        #expect(WeighInSession.collapse(entries).count > 1)
    }

    @Test("ordinary daily weigh-ins are untouched")
    func dailyWeighIns() {
        let entries = (0..<10).map { i in
            WeightEntry.fromPounds(180 - Double(i) * 0.2, date: at(1 + i, 7, 5, i * 3))
        }
        #expect(WeighInSession.collapse(entries).count == 10)
        #expect(WeighInSession.superseded(in: entries).isEmpty)
    }

    @Test("one morning on the scale cannot make a week look reliable")
    func reliabilityIsNotInflated() throws {
        // The bug this file exists for. Three records from a single session
        // used to count as three weigh-ins, and three is the bar a week has
        // to clear before the app treats its average as settled.
        let burst = [
            WeightEntry.fromPounds(184.0, date: at(17, 23, 24, 14), bodyFatPercent: 26.3),
            WeightEntry.fromPounds(182.9, date: at(17, 23, 24, 32), bodyFatPercent: 26.0),
            WeightEntry.fromPounds(183.7, date: at(17, 23, 24, 55), bodyFatPercent: 26.2),
        ]
        let raw = TrendEngine.weeklyAverages(from: burst, calendar: cal)
        #expect(try #require(raw.first).isReliable)  // what it used to say

        let sessions = TrendEngine.weeklyAverages(
            from: WeighInSession.collapse(burst), calendar: cal
        )
        let week = try #require(sessions.first)
        #expect(week.entryCount == 1)
        #expect(!week.isReliable)
        #expect(abs(week.pounds - 183.7) < 0.05)
    }

    @Test("the superseded records are named, not thrown away")
    func supersededAreIdentified() {
        let first = WeightEntry.fromPounds(180.4, date: at(11, 23, 29, 14))
        let second = WeightEntry.fromPounds(177.9, date: at(11, 23, 29, 45))
        let lonely = WeightEntry.fromPounds(179.0, date: at(12, 8, 0, 0))

        let superseded = WeighInSession.superseded(in: [first, second, lonely])
        #expect(superseded == [first.id])
    }

    @Test("an empty list collapses to an empty list")
    func empty() {
        #expect(WeighInSession.collapse([]).isEmpty)
        #expect(WeighInSession.superseded(in: []).isEmpty)
    }
}

import Foundation
import Testing

@testable import Verus

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    c.firstWeekday = 2
    return c
}()

private func at(_ day: Int, hour: Int = 7, minute: Int = 0) -> Date {
    DateComponents(
        calendar: cal, timeZone: cal.timeZone,
        year: 2026, month: 11, day: day, hour: hour, minute: minute
    ).date!
}

@Suite("Body metrics")
struct BodyMetricsTests {

    // MARK: - Matching a scale's samples to the weigh-in

    @Test("a reading taken with the weigh-in is attached to it")
    func nearestInsideTolerance() {
        let weighIn = at(10, hour: 7, minute: 0)
        let samples = [BodyMetricSample(date: at(10, hour: 7, minute: 0), value: 18.2)]
        #expect(BodyMetrics.nearest(to: weighIn, in: samples) == 18.2)
    }

    @Test("last night's reading is not attached to this morning's weigh-in")
    func nearestOutsideTolerance() {
        let weighIn = at(10, hour: 7)
        let samples = [BodyMetricSample(date: at(9, hour: 22), value: 19.4)]
        #expect(BodyMetrics.nearest(to: weighIn, in: samples) == nil)
    }

    @Test("two weigh-ins in one quarter of an hour each take their own reading")
    func nearestWins() {
        let samples = [
            BodyMetricSample(date: at(10, hour: 7, minute: 0), value: 18.0),
            BodyMetricSample(date: at(10, hour: 7, minute: 10), value: 18.9),
        ]
        #expect(BodyMetrics.nearest(to: at(10, hour: 7, minute: 1), in: samples) == 18.0)
        #expect(BodyMetrics.nearest(to: at(10, hour: 7, minute: 9), in: samples) == 18.9)
    }

    @Test("composition fills the gaps and never overwrites what is there")
    func enrich() throws {
        let typed = WeightEntry(
            date: at(10), kilograms: 81.2,
            // Typed by hand on the Weight screen.
            bodyFatPercent: 17.0
        )
        let fromScale = WeightEntry(date: at(11), kilograms: 81.0)

        let enriched = BodyMetrics.enrich(
            [typed, fromScale],
            bodyFatPercent: [
                BodyMetricSample(date: at(10), value: 18.2),
                BodyMetricSample(date: at(11), value: 18.4),
            ],
            leanKilograms: [BodyMetricSample(date: at(11), value: 66.1)],
            bodyMassIndex: [BodyMetricSample(date: at(11), value: 24.6)]
        )

        // The hand-typed figure outranks the one matched out of Health.
        #expect(enriched[0].bodyFatPercent == 17.0)
        #expect(enriched[0].leanKilograms == nil)

        #expect(enriched[1].bodyFatPercent == 18.4)
        #expect(enriched[1].leanKilograms == 66.1)
        #expect(enriched[1].bodyMassIndex == 24.6)
        #expect(enriched[1].isLeanMeasured)

        // Fat mass and derived lean are views of the same reading, not a
        // second source of truth.
        let fat = try #require(enriched[1].fatKilograms)
        #expect(abs(fat - 81.0 * 0.184) < 0.000_1)
    }

    // MARK: - Merging a sync into what is already stored

    @Test("a weigh-in Verus wrote to Health does not come back as a second one")
    func noDoubles() {
        let stored = [WeightEntry(date: at(10, hour: 7), kilograms: 81.23)]
        // Health hands it back with a different id, a slightly different
        // instant and the same weight. Same day, same 100 g: same morning.
        let imported = [WeightEntry(date: at(10, hour: 7, minute: 30), kilograms: 81.21)]

        let result = BodyMetrics.merge(existing: stored, imported: imported, calendar: cal)
        #expect(result.entries.count == 1)
        #expect(result.added == 0)
        #expect(result.enriched == 0)
    }

    @Test("a weigh-in already stored is completed, not skipped")
    func duplicatesAreEnriched() throws {
        // This is the case the whole function exists for: earlier versions
        // read weight alone, so the scale's own body fat is sitting in Health
        // next to a row that would never ask for it again.
        let stored = [WeightEntry(date: at(10, hour: 7), kilograms: 81.2)]
        let imported = [
            WeightEntry(
                date: at(10, hour: 7), kilograms: 81.2,
                bodyFatPercent: 18.2, leanKilograms: 66.4, bodyMassIndex: 24.7
            )
        ]

        let result = BodyMetrics.merge(existing: stored, imported: imported, calendar: cal)
        #expect(result.added == 0)
        #expect(result.enriched == 1)
        #expect(result.entries.count == 1)
        let entry = try #require(result.entries.first)
        #expect(entry.bodyFatPercent == 18.2)
        #expect(entry.leanKilograms == 66.4)
        #expect(entry.bodyMassIndex == 24.7)
        // The stored row keeps its identity — the sync completed it rather
        // than replacing it.
        #expect(entry.id == stored[0].id)
    }

    @Test("a second import changes nothing")
    func mergeIsIdempotent() {
        let imported = [
            WeightEntry(date: at(10), kilograms: 81.2, bodyFatPercent: 18.2),
            WeightEntry(date: at(11), kilograms: 81.0, bodyFatPercent: 18.1),
        ]
        let first = BodyMetrics.merge(existing: [], imported: imported, calendar: cal)
        #expect(first.added == 2)

        let second = BodyMetrics.merge(
            existing: first.entries, imported: imported, calendar: cal
        )
        #expect(second.added == 0)
        #expect(second.enriched == 0)
        #expect(second.entries == first.entries)
    }

    @Test("new weigh-ins arrive in date order")
    func sorted() {
        let imported = [
            WeightEntry(date: at(14), kilograms: 80.4),
            WeightEntry(date: at(12), kilograms: 80.9),
        ]
        let stored = [WeightEntry(date: at(13), kilograms: 80.7)]
        let result = BodyMetrics.merge(existing: stored, imported: imported, calendar: cal)
        #expect(result.added == 2)
        let dates = result.entries.map(\.date)
        #expect(dates == dates.sorted())
    }

    @Test("two weigh-ins on the same day at different weights both count")
    func sameDayDifferentWeight() {
        // Morning and evening differ by more than 100 g, so they are two
        // weigh-ins — the dedupe must not swallow the second one.
        let imported = [
            WeightEntry(date: at(10, hour: 7), kilograms: 81.2),
            WeightEntry(date: at(10, hour: 21), kilograms: 82.6),
        ]
        let result = BodyMetrics.merge(existing: [], imported: imported, calendar: cal)
        #expect(result.added == 2)
    }
}

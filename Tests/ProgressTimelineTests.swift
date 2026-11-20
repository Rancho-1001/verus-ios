import Foundation
import Testing

@testable import Verus

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    c.firstWeekday = 2
    return c
}()

private let origin = DateComponents(
    calendar: cal, timeZone: cal.timeZone, year: 2026, month: 9, day: 1, hour: 8
).date!

private func day(_ offset: Int) -> Date {
    cal.date(byAdding: .day, value: offset, to: origin)!
}

private func photo(_ offset: Int) -> ProgressPhoto {
    ProgressPhoto(date: day(offset), filename: "photo-\(offset).jpg")
}

/// A smoothed trend falling steadily from 180 lb at 0.2 lb/day.
private func trend(days: Int) -> [TrendPoint] {
    (0..<days).map { offset in
        let pounds = 180 - Double(offset) * 0.2
        return TrendPoint(
            date: cal.startOfDay(for: day(offset)),
            kilograms: pounds / WeightEntry.poundsPerKilogram,
            rawKilograms: nil
        )
    }
}

@Suite("Progress timeline")
struct ProgressTimelineTests {

    @Test("nothing recorded means an empty timeline")
    func empty() {
        #expect(
            ProgressTimeline.build(photos: [], measurements: [], trend: [], calendar: cal).isEmpty
        )
    }

    @Test("a day only earns a place if it has a photo or a measurement")
    func weighInsAloneDoNotMakeMoments() {
        // Thirty days of weigh-ins and one photograph.
        let moments = ProgressTimeline.build(
            photos: [photo(10)], measurements: [], trend: trend(days: 30), calendar: cal
        )
        #expect(moments.count == 1)
    }

    @Test("the timeline runs newest first")
    func newestFirst() throws {
        let moments = ProgressTimeline.build(
            photos: [photo(0), photo(14), photo(28)],
            measurements: [], trend: trend(days: 30), calendar: cal
        )
        #expect(moments.count == 3)
        #expect(moments == moments.sorted { $0.day > $1.day })
        #expect(try #require(moments.first).day == cal.startOfDay(for: day(28)))
    }

    @Test("the change is measured against the previous photo, not the first")
    func deltaIsAgainstThePrevious() throws {
        // 0.2 lb/day, so a fortnight is 2.8 lb.
        let moments = ProgressTimeline.build(
            photos: [photo(0), photo(14), photo(28)],
            measurements: [], trend: trend(days: 30), calendar: cal
        )
        let newest = try #require(moments.first)
        let change = try #require(newest.changeSincePreviousPounds)
        #expect(change < 0)
        #expect(abs(change + 2.8) < 0.01)
    }

    @Test("the earliest moment has no change to report")
    func firstHasNoDelta() throws {
        let moments = ProgressTimeline.build(
            photos: [photo(0), photo(14)],
            measurements: [], trend: trend(days: 30), calendar: cal
        )
        #expect(try #require(moments.last).changeSincePreviousPounds == nil)
    }

    @Test("a photo during a gap in weigh-ins does not reset the comparison")
    func gapDoesNotRebaseTheDelta() throws {
        // Trend covers days 0–9 only. Photos on 0, 20 (no trend) and… there is
        // no trend on day 20, so the day-20 card reports no change — and the
        // baseline must stay at day 0 rather than being cleared, which is what
        // the `if let` in the builder is guarding.
        let moments = ProgressTimeline.build(
            photos: [photo(0), photo(20)],
            measurements: [], trend: trend(days: 10), calendar: cal
        )
        let newest = try #require(moments.first)
        #expect(newest.trendPounds == nil)
        #expect(newest.changeSincePreviousPounds == nil)
    }

    @Test("several photos on one day group into a single moment")
    func groupsByDay() throws {
        let morning = ProgressPhoto(date: day(5), filename: "a.jpg")
        let evening = ProgressPhoto(
            date: cal.date(byAdding: .hour, value: 10, to: day(5))!, filename: "b.jpg"
        )
        let moments = ProgressTimeline.build(
            photos: [evening, morning], measurements: [], trend: trend(days: 10), calendar: cal
        )
        #expect(moments.count == 1)
        let moment = try #require(moments.first)
        #expect(moment.photos.count == 2)
        #expect(moment.photos[0].filename == "a.jpg")  // chronological within the day
    }

    @Test("measurements sort waist first")
    func measurementOrder() throws {
        let readings = [
            BodyMeasurement.fromInches(15, date: day(3), site: .arm),
            BodyMeasurement.fromInches(36, date: day(3), site: .waist),
            BodyMeasurement.fromInches(42, date: day(3), site: .chest),
        ]
        let moments = ProgressTimeline.build(
            photos: [], measurements: readings, trend: [], calendar: cal
        )
        let sites = try #require(moments.first).measurements.map(\.site)
        #expect(sites == [.waist, .chest, .arm])
    }
}

@Suite("Measurement summaries")
struct MeasurementSummaryTests {

    @Test("the latest reading per site is what is shown")
    func latestWins() throws {
        let readings = [
            BodyMeasurement.fromInches(38, date: day(0), site: .waist),
            BodyMeasurement.fromInches(36, date: day(30), site: .waist),
            BodyMeasurement.fromInches(42, date: day(10), site: .chest),
        ]
        let latest = ProgressTimeline.latestMeasurements(from: readings)
        #expect(latest.count == 2)
        let waist = try #require(latest.first { $0.site == .waist })
        #expect(abs(waist.inches - 36) < 0.001)
    }

    @Test("a single reading is a starting point, not a change")
    func oneReadingIsNoChange() {
        let readings = [BodyMeasurement.fromInches(38, date: day(0), site: .waist)]
        #expect(ProgressTimeline.change(for: .waist, in: readings) == nil)
    }

    @Test("a shrinking waist reads as a negative change")
    func waistChange() throws {
        let readings = [
            BodyMeasurement.fromInches(38, date: day(0), site: .waist),
            BodyMeasurement.fromInches(36, date: day(30), site: .waist),
        ]
        let change = try #require(ProgressTimeline.change(for: .waist, in: readings))
        #expect(change < 0)
        #expect(abs(change / 2.54 + 2) < 0.001)  // two inches down
    }

    @Test("a site never measured has no change")
    func unmeasuredSite() {
        let readings = [BodyMeasurement.fromInches(38, date: day(0), site: .waist)]
        #expect(ProgressTimeline.change(for: .thigh, in: readings) == nil)
    }
}

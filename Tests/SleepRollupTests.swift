import Foundation
import Testing

@testable import Verus

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/Detroit")!
    c.firstWeekday = 2
    return c
}()

private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    DateComponents(
        calendar: cal, timeZone: cal.timeZone,
        year: 2026, month: 11, day: day, hour: hour, minute: minute
    ).date!
}

private func night(_ day: Int) -> Date {
    cal.startOfDay(for: at(day, 12))
}

@Suite("Sleep")
struct SleepRollupTests {

    @Test("a night belongs to the morning it ends on")
    func attributedToWakeDay() throws {
        // Asleep 11pm Monday the 9th, awake 7am Tuesday the 10th. The
        // question "how did I sleep last night" is asked on Tuesday.
        let sessions = [SleepSession(start: at(9, 23), end: at(10, 7))]
        let hours = SleepRollup.hoursByNight(sessions, calendar: cal)
        #expect(hours[night(9)] == nil)
        let slept = try #require(hours[night(10)])
        #expect(abs(slept - 8) < 0.001)
    }

    @Test("the same night written by two sources counts once")
    func overlappingSourcesAreNotDoubled() throws {
        // A watch and a sleep app both record it, offset by a few minutes.
        // Adding them would report sixteen hours.
        let sessions = [
            SleepSession(start: at(9, 23, 0), end: at(10, 7, 0)),
            SleepSession(start: at(9, 23, 12), end: at(10, 6, 48)),
        ]
        let hours = SleepRollup.hoursByNight(sessions, calendar: cal)
        let slept = try #require(hours[night(10)])
        #expect(abs(slept - 8) < 0.001)
    }

    @Test("partly overlapping stretches merge into the span they cover")
    func partialOverlap() throws {
        let sessions = [
            SleepSession(start: at(9, 23), end: at(10, 3)),
            SleepSession(start: at(10, 2), end: at(10, 7)),   // starts before the first ends
        ]
        let hours = SleepRollup.hoursByNight(sessions, calendar: cal)
        let slept = try #require(hours[night(10)])
        #expect(abs(slept - 8) < 0.001)   // 11pm to 7am, not 4 + 5
    }

    @Test("a separate nap on the same day adds to it")
    func napsAddUp() throws {
        let sessions = [
            SleepSession(start: at(9, 23), end: at(10, 7)),    // the night
            SleepSession(start: at(10, 14), end: at(10, 15)),  // an afternoon hour
        ]
        let hours = SleepRollup.hoursByNight(sessions, calendar: cal)
        let slept = try #require(hours[night(10)])
        #expect(abs(slept - 9) < 0.001)
    }

    @Test("waking across a clock change is measured in real time")
    func daylightSaving() throws {
        // 1 November 2026, 2am becomes 1am in Detroit. Asleep 11pm to 7am by
        // the clock is nine real hours, and the sleep that happened is what
        // the user slept.
        let sessions = [
            SleepSession(
                start: DateComponents(calendar: cal, timeZone: cal.timeZone,
                                      year: 2026, month: 10, day: 31, hour: 23).date!,
                end: DateComponents(calendar: cal, timeZone: cal.timeZone,
                                    year: 2026, month: 11, day: 1, hour: 7).date!
            )
        ]
        let hours = SleepRollup.hoursByNight(sessions, calendar: cal)
        let morning = cal.startOfDay(
            for: DateComponents(calendar: cal, timeZone: cal.timeZone,
                                year: 2026, month: 11, day: 1, hour: 12).date!
        )
        let slept = try #require(hours[morning])
        #expect(abs(slept - 9) < 0.001)
    }

    @Test("a zero-length or backwards record is dropped rather than counted")
    func degenerateSessions() {
        let sessions = [
            SleepSession(start: at(10, 3), end: at(10, 3)),
            SleepSession(start: at(10, 5), end: at(10, 4)),
        ]
        #expect(SleepRollup.hoursByNight(sessions, calendar: cal).isEmpty)
        #expect(SleepRollup.merge(sessions).isEmpty)
    }

    @Test("no records at all is no entry, not a night of zero hours")
    func noRecords() {
        #expect(SleepRollup.hoursByNight([], calendar: cal).isEmpty)
    }
}

@Suite("BMI")
struct BodyMassIndexTests {

    @Test("BMI is kilograms over metres squared")
    func arithmetic() throws {
        let bmi = try #require(
            BodyComposition.bodyMassIndex(weightKilograms: 81.0, heightMeters: 1.80)
        )
        #expect(abs(bmi - 25.0) < 0.01)
    }

    @Test("no height means no BMI, never an assumed one")
    func withoutHeight() {
        #expect(BodyComposition.bodyMassIndex(weightKilograms: 81, heightMeters: nil) == nil)
        // Outside anything a person measures: a data error, not a short person.
        #expect(BodyComposition.bodyMassIndex(weightKilograms: 81, heightMeters: 0.2) == nil)
        #expect(BodyComposition.bodyMassIndex(weightKilograms: 81, heightMeters: 3.4) == nil)
        #expect(BodyComposition.bodyMassIndex(weightKilograms: 0, heightMeters: 1.8) == nil)
    }
}

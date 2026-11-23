import Foundation
import Testing

@testable import Verus

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/Detroit")!
    c.firstWeekday = 2
    return c
}()

private func at(_ day: Int, _ hour: Int, _ minute: Int, _ second: Int) -> Date {
    DateComponents(
        calendar: cal, timeZone: cal.timeZone,
        year: 2026, month: 11, day: day, hour: hour, minute: minute, second: second
    ).date!
}

/// Seeded entries all carry the launch instant's time of day, to the second.
private func seededRun(_ count: Int, startingDay: Int = 1, pounds: Double = 175) -> [WeightEntry] {
    (0..<count).map { offset in
        WeightEntry.fromPounds(
            pounds + Double(offset) * 0.1, date: at(startingDay + offset, 8, 9, 52)
        )
    }
}

@Suite("Seeded weigh-ins")
struct SampleWeighInTests {

    @Test("a run of entries sharing one exact second is seeded data")
    func clusterIsFound() {
        let entries = seededRun(21)
        #expect(SampleWeighIn.seeded(in: entries, calendar: cal).count == 21)
        #expect(SampleWeighIn.purge(entries, calendar: cal).isEmpty)
    }

    @Test("real weigh-ins around them are kept, in order")
    func realEntriesSurvive() throws {
        let real = [
            WeightEntry.fromPounds(181.5, date: at(16, 16, 51, 37), bodyFatPercent: 25.6),
            WeightEntry.fromPounds(179.4, date: at(23, 18, 51, 53), bodyFatPercent: 25.1),
            // No body fat, but nothing else shares its second.
            WeightEntry.fromPounds(180.2, date: at(20, 7, 14, 3)),
        ]
        let cleaned = SampleWeighIn.purge(seededRun(17) + real, calendar: cal)
        #expect(cleaned.count == 3)
        #expect(cleaned.map(\.date) == cleaned.map(\.date).sorted())
        #expect(cleaned.contains { $0.bodyFatPercent == 25.1 })
    }

    @Test("two batches seeded at different launches are both found")
    func twoClusters() {
        // Exactly the shape of the file this was written for: one run at
        // 08:09:52 and another at 09:09:52.
        let first = seededRun(21, startingDay: 1)
        let second = (0..<17).map { offset in
            WeightEntry.fromPounds(174 + Double(offset) * 0.1, date: at(2 + offset, 9, 9, 52))
        }
        #expect(SampleWeighIn.purge(first + second, calendar: cal).isEmpty)
    }

    @Test("a weigh-in carrying body composition is never seeded data")
    func compositionIsProofOfLife() {
        // The generator never produced body fat, so an entry that has it was
        // measured — even if it somehow shared a second with a run.
        var entries = seededRun(10)
        entries.append(
            WeightEntry.fromPounds(180, date: at(1, 8, 9, 52), bodyFatPercent: 24.9)
        )
        let cleaned = SampleWeighIn.purge(entries, calendar: cal)
        #expect(cleaned.count == 1)
        #expect(cleaned.first?.bodyFatPercent == 24.9)
    }

    @Test("a coincidence is not a loop")
    func smallClustersAreLeftAlone() {
        // Seven weigh-ins at the same second would be extraordinary; the
        // threshold is eight, and below it nothing is touched.
        let entries = seededRun(7)
        #expect(SampleWeighIn.seeded(in: entries, calendar: cal).isEmpty)
        #expect(SampleWeighIn.purge(entries, calendar: cal).count == 7)
    }

    @Test("weighing at the same minute every morning is not seeded data")
    func sameMinuteDifferentSeconds() {
        // A disciplined person on a scale at 7:02 every day still lands on a
        // different second each time. Only the exact second is a machine.
        let entries = (0..<20).map { offset in
            WeightEntry.fromPounds(
                180, date: at(1 + offset, 7, 2, (offset * 7) % 60)
            )
        }
        #expect(SampleWeighIn.purge(entries, calendar: cal).count == 20)
    }

    @Test("a clean file is returned untouched")
    func nothingToDo() {
        let entries = [
            WeightEntry.fromPounds(181.5, date: at(16, 16, 51, 37)),
            WeightEntry.fromPounds(179.4, date: at(23, 18, 51, 53)),
        ]
        #expect(SampleWeighIn.purge(entries, calendar: cal) == entries)
    }
}

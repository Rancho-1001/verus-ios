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

private func reading(
    _ id: UUID,
    _ date: Date,
    _ kcal: Double,
    name: String? = nil,
    source: String = "MyFitnessPal"
) -> DietaryReading {
    DietaryReading(
        healthIdentifier: id, date: date, kilocalories: kcal,
        foodName: name, sourceName: source
    )
}

private let window = at(1, 0)...at(30, 23)

@Suite("Dietary import")
struct DietaryImportTests {

    @Test("a meal logged elsewhere becomes an entry at the right meal of day")
    func readingBecomesEntry() throws {
        let id = UUID()
        let entries = DietaryImport.entries(
            from: [reading(id, at(10, 8, 30), 420, name: "Oats and berries")],
            calendar: cal
        )
        let entry = try #require(entries.first)
        #expect(entry.name == "Oats and berries")
        #expect(entry.kilocalories == 420)
        #expect(entry.meal == .breakfast)
        #expect(entry.source == .appleHealth)
        #expect(entry.healthIdentifier == id)
        #expect(entry.externalSourceName == "MyFitnessPal")
    }

    @Test("a record with no food name is labelled with the app that wrote it")
    func unnamedFood() throws {
        let entries = DietaryImport.entries(
            from: [reading(UUID(), at(10, 13), 610, source: "Lose It!")],
            calendar: cal
        )
        #expect(try #require(entries.first).name == "Lose It!")
    }

    @Test("macros attach to a food that is alone at its timestamp")
    func macrosAttach() throws {
        let time = at(10, 19)
        let entries = DietaryImport.entries(
            from: [reading(UUID(), time, 700, name: "Chicken and rice")],
            protein: [BodyMetricSample(date: time, value: 52)],
            carbs: [BodyMetricSample(date: time, value: 71)],
            fat: [BodyMetricSample(date: time, value: 18)],
            calendar: cal
        )
        let entry = try #require(entries.first)
        #expect(entry.proteinGrams == 52)
        #expect(entry.carbGrams == 71)
        #expect(entry.fatGrams == 18)
    }

    @Test("three foods logged at one instant get no macros rather than guessed ones")
    func ambiguousMacros() {
        // Logging a breakfast of three items usually writes all three at the
        // same second. There is no way to know whose protein is whose, and
        // splitting it evenly would be inventing data.
        let time = at(10, 8)
        let readings = [
            reading(UUID(), time, 220, name: "Toast"),
            reading(UUID(), time, 180, name: "Eggs"),
            reading(UUID(), time, 90, name: "Orange juice"),
        ]
        let entries = DietaryImport.entries(
            from: readings,
            protein: [BodyMetricSample(date: time, value: 24)],
            calendar: cal
        )
        #expect(entries.count == 3)
        #expect(entries.allSatisfy { $0.proteinGrams == nil })
        // The calories still stand — only the macros are withheld.
        #expect(entries.reduce(0) { $0 + $1.kilocalories } == 490)
    }

    @Test("a macro written for a different meal is not borrowed")
    func macrosOutsideTolerance() throws {
        let entries = DietaryImport.entries(
            from: [reading(UUID(), at(10, 19), 700)],
            protein: [BodyMetricSample(date: at(10, 13), value: 40)],
            calendar: cal
        )
        #expect(try #require(entries.first).proteinGrams == nil)
    }

    // MARK: - Merging

    @Test("importing twice does not log lunch twice")
    func idempotent() {
        let imported = DietaryImport.entries(
            from: [reading(UUID(), at(10, 13), 610), reading(UUID(), at(10, 19), 700)],
            calendar: cal
        )
        let first = DietaryImport.merge(existing: [], imported: imported, window: window)
        #expect(first.added == 2)

        let second = DietaryImport.merge(
            existing: first.entries, imported: imported, window: window
        )
        #expect(second.added == 0)
        #expect(second.updated == 0)
        #expect(second.removed == 0)
        #expect(second.entries.count == 2)
    }

    @Test("what the user logged in Verus is never touched")
    func manualEntriesSurvive() {
        let typed = FoodEntry(
            date: at(10, 12), name: "Jollof", kilocalories: 540, meal: .lunch
        )
        // Nothing in the import matches it, and it is inside the window —
        // the prune must not take it, because it was never Health's to
        // delete.
        let result = DietaryImport.merge(
            existing: [typed],
            imported: DietaryImport.entries(
                from: [reading(UUID(), at(10, 19), 700)], calendar: cal
            ),
            window: window
        )
        #expect(result.removed == 0)
        #expect(result.entries.contains(typed))
        #expect(result.entries.count == 2)
    }

    @Test("a figure corrected in the other app is corrected here")
    func editedElsewhere() throws {
        let id = UUID()
        let stored = DietaryImport.entries(
            from: [reading(id, at(10, 13), 1_800, name: "Lunch")], calendar: cal
        )
        // The user noticed the extra zero and fixed it in MyFitnessPal.
        let corrected = DietaryImport.entries(
            from: [reading(id, at(10, 13), 180, name: "Lunch")], calendar: cal
        )

        let result = DietaryImport.merge(existing: stored, imported: corrected, window: window)
        #expect(result.added == 0)
        #expect(result.updated == 1)
        let entry = try #require(result.entries.first)
        #expect(entry.kilocalories == 180)
        // Same row, not a replacement: the local identity is kept.
        #expect(entry.id == stored[0].id)
    }

    @Test("a meal deleted in the other app is deleted here")
    func deletedElsewhere() {
        let stored = DietaryImport.entries(
            from: [reading(UUID(), at(10, 13), 610), reading(UUID(), at(10, 19), 700)],
            calendar: cal
        )
        // Only the second one still exists in Health.
        let remaining = [stored[1]]
        let result = DietaryImport.merge(existing: stored, imported: remaining, window: window)
        #expect(result.removed == 1)
        #expect(result.entries.count == 1)
        #expect(result.entries.first?.kilocalories == 700)
    }

    @Test("an older entry outside the window read is left alone")
    func pruningStopsAtTheWindow() {
        // Last month was not asked about, so its absence from this import is
        // not evidence that it was deleted.
        let old = DietaryImport.entries(
            from: [reading(UUID(), at(2, 13), 500)], calendar: cal
        )
        let recentWindow = at(20, 0)...at(30, 23)
        let result = DietaryImport.merge(existing: old, imported: [], window: recentWindow)
        #expect(result.removed == 0)
        #expect(result.entries.count == 1)
    }

    @Test("imported meals land in the day's budget alongside typed ones")
    func feedsTheBudget() throws {
        let typed = FoodEntry(date: at(10, 8), name: "Oats", kilocalories: 400, meal: .breakfast)
        let imported = DietaryImport.entries(
            from: [reading(UUID(), at(10, 13), 610)], calendar: cal
        )
        let merged = DietaryImport.merge(existing: [typed], imported: imported, window: window)

        let day = EnergyBudget.day(
            at(10, 21),
            entries: merged.entries,
            activity: DailyActivity(
                day: cal.startOfDay(for: at(10, 12)), steps: 12_000,
                activeKilocalories: 600, restingKilocalories: 1_700
            ),
            calendar: cal
        )
        guard case .known(let intake, _, _) = day.balance else {
            Issue.record("expected both intake and burn to be known")
            return
        }
        #expect(intake == 1_010)
    }
}

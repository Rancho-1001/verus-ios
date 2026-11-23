import Foundation
import Observation

/// Logged food.
///
/// Same storage shape as the other stores: a JSON file in Application
/// Support, on the device, no account and no server. Food logs are less
/// sensitive than progress photographs but they are still a record of
/// somebody's eating, so they get the same treatment and the same file
/// protection.
@MainActor
@Observable
final class FoodStore {

    private(set) var entries: [FoodEntry] = []

    var calendar: Calendar = {
        var c = Calendar.current
        c.firstWeekday = 2
        return c
    }()

    private let fileURL: URL?
    private let health: HealthKitService?

    /// What the last sync did, for the screen to report rather than leaving
    /// the user to spot the difference.
    private(set) var lastImportCount = 0
    private(set) var lastRemovedCount = 0
    private(set) var isSyncing = false

    init(
        fileURL: URL? = FoodStore.defaultFileURL,
        health: HealthKitService? = HealthKitService.isAvailable ? HealthKitService() : nil
    ) {
        self.fileURL = fileURL
        self.health = health
        load()
    }

    // MARK: - Apple Health

    /// Pulls in food logged elsewhere.
    ///
    /// Verus writes nothing to Health's dietary types, so everything that
    /// comes back was logged in another app and the two sets cannot
    /// double-count. The merge rules — including deleting rows the other app
    /// deleted — are in `DietaryImport.merge`.
    ///
    /// Thirty days rather than a year: a food log is dense, and nobody is
    /// scrolling back to last March in this app.
    @discardableResult
    func syncFromHealth(days: Int = 30) async -> Int {
        guard let health else { return 0 }
        let end = Date.now
        guard let start = calendar.date(byAdding: .day, value: -days, to: end) else { return 0 }

        isSyncing = true
        defer { isSyncing = false }

        guard let imported = try? await health.dietaryEntries(
            from: start, to: end, calendar: calendar
        ) else { return 0 }

        let result = DietaryImport.merge(
            existing: entries, imported: imported, window: start...end
        )
        if result.added > 0 || result.updated > 0 || result.removed > 0 {
            entries = result.entries
            save()
        }
        lastImportCount = result.added
        lastRemovedCount = result.removed
        return result.added
    }

    /// Whether anything on screen came from another app — what decides
    /// whether the Food screen explains where its numbers are from.
    var hasHealthEntries: Bool { entries.contains(where: \.isFromHealth) }

    static var defaultFileURL: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask,
                 appropriateFor: nil, create: true)
            .appendingPathComponent("food-entries.json")
    }

    // MARK: - Reading

    func entries(on day: Date) -> [FoodEntry] {
        entries
            .filter { calendar.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.date < $1.date }
    }

    func day(_ date: Date, activity: DailyActivity?) -> EnergyBudget.Day {
        EnergyBudget.day(date, entries: entries, activity: activity, calendar: calendar)
    }

    /// The last `count` days, newest first, so the screen can show a short
    /// history without loading everything ever logged.
    func recentDays(_ count: Int, activity: (Date) -> DailyActivity?) -> [EnergyBudget.Day] {
        (0..<count).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: .now) else { return nil }
            return day(date, activity: activity(date))
        }
    }

    // MARK: - Writing

    func add(_ entry: FoodEntry) {
        entries.append(entry)
        entries.sort { $0.date < $1.date }
        save()
    }

    func delete(_ entry: FoodEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    // MARK: - Persistence

    /// `FoodEntry` stays free of Codable so the storage format can change
    /// without the domain type following it around.
    private struct Stored: Codable {
        let id: UUID
        let date: Date
        let name: String
        let kilocalories: Double
        let proteinGrams: Double?
        let carbGrams: Double?
        let fatGrams: Double?
        let meal: Meal
        let source: FoodEntry.Source
        /// Added after the first release: optional in, optional out, so a
        /// file written by the earlier version still decodes.
        let healthIdentifier: UUID?
        let externalSourceName: String?

        init(_ entry: FoodEntry) {
            id = entry.id
            date = entry.date
            name = entry.name
            kilocalories = entry.kilocalories
            proteinGrams = entry.proteinGrams
            carbGrams = entry.carbGrams
            fatGrams = entry.fatGrams
            meal = entry.meal
            source = entry.source
            healthIdentifier = entry.healthIdentifier
            externalSourceName = entry.externalSourceName
        }

        var entry: FoodEntry {
            FoodEntry(
                id: id, date: date, name: name, kilocalories: kilocalories,
                proteinGrams: proteinGrams, carbGrams: carbGrams, fatGrams: fatGrams,
                meal: meal, source: source,
                healthIdentifier: healthIdentifier, externalSourceName: externalSourceName
            )
        }
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([Stored].self, from: data))?
            .map(\.entry)
            .sorted { $0.date < $1.date } ?? []
    }

    private func save() {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries.map(Stored.init)) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}

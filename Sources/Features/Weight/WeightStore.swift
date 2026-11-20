import Foundation
import Observation

/// Weigh-ins, and everything the Weight screen derives from them.
///
/// Storage is a JSON file in Application Support. That is a deliberate choice
/// for v1: one user, one device, no account, no server — so health data never
/// leaves the phone and there is nothing to breach. When sync across devices
/// becomes a requirement, this is the single type that has to change.
@MainActor
@Observable
final class WeightStore {

    private(set) var entries: [WeightEntry] = []

    /// Target weight. 150 lb is a starting value, not a claim about the user —
    /// it is editable on the Goals sheet and persists from there.
    var goalKilograms: Double = 150 / WeightEntry.poundsPerKilogram {
        didSet { UserDefaults.standard.set(goalKilograms, forKey: Self.goalWeightKey) }
    }

    /// Target body fat, as a percentage. Optional as a goal: plenty of people
    /// track weight and never own a body-fat scale, and the Weight screen must
    /// make sense for them too.
    var goalBodyFatPercent: Double? = nil {
        didSet {
            if let goalBodyFatPercent {
                UserDefaults.standard.set(goalBodyFatPercent, forKey: Self.goalBodyFatKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.goalBodyFatKey)
            }
        }
    }

    private static let goalWeightKey = "goal.weightKilograms"
    private static let goalBodyFatKey = "goal.bodyFatPercent"

    var calendar: Calendar = {
        var c = Calendar.current
        c.firstWeekday = 2  // weeks run Monday–Sunday
        return c
    }()

    private let fileURL: URL?
    private let health: HealthKitService?

    /// Set when a write to Apple Health fails. The weigh-in is still saved
    /// locally — Health is a mirror, not the record.
    private(set) var healthWriteError: String?
    /// How many weigh-ins the last sync pulled in from other apps.
    private(set) var lastImportCount = 0

    init(
        fileURL: URL? = WeightStore.defaultFileURL,
        health: HealthKitService? = HealthKitService.isAvailable ? HealthKitService() : nil,
        seedWhenEmpty: Bool = true
    ) {
        self.fileURL = fileURL
        self.health = health

        // Assigning a property inside its own class's initialiser does not
        // fire `didSet`, so restoring a saved goal here does not write it
        // straight back out again.
        let defaults = UserDefaults.standard
        if let saved = defaults.object(forKey: Self.goalWeightKey) as? Double, saved > 0 {
            goalKilograms = saved
        }
        if let savedFat = defaults.object(forKey: Self.goalBodyFatKey) as? Double {
            goalBodyFatPercent = savedFat
        }

        load()
        if entries.isEmpty && seedWhenEmpty {
            entries = Self.sampleEntries()
        }
    }

    // MARK: - Apple Health

    /// Pulls weigh-ins recorded elsewhere — a smart scale, the Health app
    /// itself, another tracker — and merges them in.
    ///
    /// Verus writes its own entries back to Health, so a naive import would
    /// read them straight back and double every morning. Entries are matched
    /// on the day plus the weight to a tenth of a kilogram; anything that
    /// close on the same day is the same weigh-in, whichever app recorded it.
    @discardableResult
    func syncFromHealth(since: Date? = nil) async -> Int {
        guard let health else { return 0 }
        let start = since
            ?? calendar.date(byAdding: .month, value: -6, to: .now)
            ?? .distantPast

        guard let imported = try? await health.weightEntries(from: start, to: .now) else {
            return 0
        }

        var known = Set(entries.map(fingerprint))
        var added = 0
        for entry in imported where !known.contains(fingerprint(entry)) {
            known.insert(fingerprint(entry))
            entries.append(entry)
            added += 1
        }

        if added > 0 {
            entries.sort { $0.date < $1.date }
            save()
        }
        lastImportCount = added
        return added
    }

    /// Same day, same weight to 100 g — the same weigh-in.
    private func fingerprint(_ entry: WeightEntry) -> String {
        let day = calendar.startOfDay(for: entry.date).timeIntervalSince1970
        return "\(Int(day))|\((entry.kilograms * 10).rounded())"
    }

    // MARK: - Derived

    var weeklyAverages: [WeeklyAverage] {
        TrendEngine.weeklyAverages(from: entries, calendar: calendar)
    }

    var trend: [TrendPoint] {
        TrendEngine.smoothedTrend(from: entries, calendar: calendar)
    }

    var rateKilogramsPerWeek: Double? {
        TrendEngine.rateKilogramsPerWeek(trend: trend)
    }

    var projection: TrendEngine.Projection {
        TrendEngine.projection(
            trend: trend,
            goalKilograms: goalKilograms,
            asOf: .now,
            calendar: calendar
        )
    }

    /// The headline number: the smoothed trend, not this morning's reading.
    var trendPounds: Double? { trend.last?.pounds }

    var latestEntry: WeightEntry? { entries.max { $0.date < $1.date } }

    /// The most recent body-fat reading, from whenever it was taken.
    ///
    /// Not "today's", because body fat is measured far less often than weight
    /// — a scale that reports it may be used weekly, or never. The latest
    /// figure is the best estimate of current composition, and the UI says
    /// when it was taken rather than implying it is fresh.
    var latestBodyFatEntry: WeightEntry? {
        entries.filter { $0.bodyFatPercent != nil }.max { $0.date < $1.date }
    }

    var latestBodyFatPercent: Double? { latestBodyFatEntry?.bodyFatPercent }

    /// How the weight goal and the body-fat goal relate at the current
    /// composition. `.noBodyFatRecorded` whenever either is missing.
    var goalRelationship: BodyComposition.GoalRelationship {
        guard let current = trend.last?.kilograms, let goalFat = goalBodyFatPercent else {
            return .noBodyFatRecorded
        }
        return BodyComposition.relationship(
            currentWeightKilograms: current,
            currentBodyFatPercent: latestBodyFatPercent,
            goalWeightKilograms: goalKilograms,
            goalBodyFatPercent: goalFat
        )
    }

    var thisWeek: WeeklyAverage? { weeklyAverages.last }

    // MARK: - Mutation

    func record(pounds: Double, on date: Date = .now, bodyFatPercent: Double? = nil) {
        let entry = WeightEntry.fromPounds(pounds, date: date, bodyFatPercent: bodyFatPercent)
        entries.append(entry)
        entries.sort { $0.date < $1.date }
        save()

        // Health is a mirror. The weigh-in is already saved locally above, so
        // a failure here loses nothing — it is reported and the morning still
        // counts.
        guard let health else { return }
        healthWriteError = nil
        Task { [weak self] in
            do {
                try await health.save(entry: entry)
            } catch {
                self?.healthWriteError = error.localizedDescription
            }
        }
    }

    func delete(_ entry: WeightEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    // MARK: - Persistence

    static var defaultFileURL: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask,
                 appropriateFor: nil, create: true)
            .appendingPathComponent("weight-entries.json")
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([StoredEntry].self, from: data))?
            .map(\.entry)
            .sorted { $0.date < $1.date } ?? []
    }

    private func save() {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries.map(StoredEntry.init)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// `WeightEntry` stays free of Codable so the storage format can change
    /// without the domain type following it around.
    private struct StoredEntry: Codable {
        let id: UUID
        let date: Date
        let kilograms: Double
        let bodyFatPercent: Double?

        init(_ entry: WeightEntry) {
            id = entry.id
            date = entry.date
            kilograms = entry.kilograms
            bodyFatPercent = entry.bodyFatPercent
        }

        var entry: WeightEntry {
            WeightEntry(id: id, date: date, kilograms: kilograms, bodyFatPercent: bodyFatPercent)
        }
    }

    // MARK: - Sample data

    /// Six weeks of plausible weigh-ins so the screen has something to show
    /// before the first real morning. Noisy on purpose — a clean line would
    /// make the smoothing look like it was doing nothing.
    static func sampleEntries() -> [WeightEntry] {
        var generator = SeededGenerator(seed: 20_261_120)
        let cal = Calendar.current
        return (0..<42).compactMap { dayOffset -> WeightEntry? in
            // Skip the odd day, the way real logging actually goes.
            guard Int.random(in: 0..<10, using: &generator) > 0 else { return nil }
            let date = cal.date(byAdding: .day, value: -(41 - dayOffset), to: .now)!
            let trend = 180.0 - Double(dayOffset) * 0.16
            let noise = Double.random(in: -1.2...1.2, using: &generator)
            return WeightEntry.fromPounds(trend + noise, date: date)
        }
    }

    /// Deterministic noise: the sample data looks the same on every launch, so
    /// a screenshot taken today matches one taken tomorrow.
    private struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed &* 6_364_136_223_846_793_005 &+ 1 }
        mutating func next() -> UInt64 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return state
        }
    }
}

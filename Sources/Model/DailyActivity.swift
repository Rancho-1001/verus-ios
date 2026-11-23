import Foundation

/// One day's activity, as the phone already knows it.
///
/// Every field is optional-by-absence rather than zero: a day with no entry
/// means "we have no reading", which is a different claim from "you took no
/// steps". The calendar draws those two states differently and must be able
/// to tell them apart.
struct DailyActivity: Identifiable, Hashable, Sendable {
    /// Midnight of the day, in the calendar that produced it.
    let day: Date
    let steps: Int
    /// Active energy in kilocalories.
    let activeKilocalories: Double
    /// Resting energy in kilocalories. Needed later so the Food screen can
    /// show intake against total burn rather than against active burn alone.
    let restingKilocalories: Double
    /// Walking and running distance in metres, when Health reported any.
    ///
    /// Optional rather than zero, and it is a separate reading from steps
    /// rather than a sum derived from them: the phone measures distance with
    /// GPS and stride length, so a 10,000-step hill walk and a 10,000-step
    /// flat walk are not the same distance. Multiplying steps by an assumed
    /// stride would be inventing a number the phone already knows.
    let distanceMeters: Double?

    /// Defaulted so the two dozen places that construct a day for a test do
    /// not all have to say "no distance".
    init(
        day: Date,
        steps: Int,
        activeKilocalories: Double,
        restingKilocalories: Double,
        distanceMeters: Double? = nil
    ) {
        self.day = day
        self.steps = steps
        self.activeKilocalories = activeKilocalories
        self.restingKilocalories = restingKilocalories
        self.distanceMeters = distanceMeters
    }

    var id: Date { day }

    var totalKilocalories: Double { activeKilocalories + restingKilocalories }

    static let metersPerMile = 1_609.344

    /// Distance in miles, when there is a distance to report.
    var miles: Double? { distanceMeters.map { $0 / Self.metersPerMile } }
}

/// Where daily activity comes from.
///
/// The Home screen talks to this and not to HealthKit. Today the only
/// implementation is sample data; `HealthKitActivitySource` lands behind the
/// same two methods and nothing above this line changes. That also keeps the
/// screen buildable and previewable on a machine with no Health permissions,
/// which is most of the time.
protocol ActivitySource: Sendable {
    /// Daily totals for every day in the range that has a reading, keyed by
    /// midnight of that day. Days with no data are simply absent.
    func dailyActivity(from start: Date, to end: Date) async throws -> [Date: DailyActivity]

    /// Workouts in the range, newest last.
    func workouts(from start: Date, to end: Date) async throws -> [Workout]
}

extension ActivitySource {
    /// A source that knows about steps but not workouts is a legitimate
    /// source, so this is a default rather than a requirement.
    func workouts(from start: Date, to end: Date) async throws -> [Workout] { [] }
}

/// Deterministic stand-in until HealthKit is wired up.
///
/// Seeded from the day itself, so the same date always produces the same
/// numbers — a screenshot taken today matches one taken tomorrow, and a bug
/// that only shows on a 3,000-step Sunday stays reproducible.
struct SampleActivitySource: ActivitySource {
    var calendar: Calendar = .current
    /// The concept's own target: roughly 15,000 steps a day.
    var typicalSteps = 15_000

    func dailyActivity(from start: Date, to end: Date) async throws -> [Date: DailyActivity] {
        var result: [Date: DailyActivity] = [:]
        var day = calendar.startOfDay(for: start)
        // Never past today. HealthKit cannot report a day that has not
        // happened, and sample data that does would hide the empty-future
        // case the calendar has to draw correctly.
        let last = min(calendar.startOfDay(for: end), calendar.startOfDay(for: .now))

        while day <= last {
            defer { day = calendar.date(byAdding: .day, value: 1, to: day) ?? last.addingTimeInterval(1) }

            // A handful of days have no reading at all — the phone was off, or
            // left at home. The calendar must render those as blank, not zero.
            let seed = UInt64(abs(day.timeIntervalSince1970.rounded()))
            var rng = SeededGenerator(seed: seed)
            guard Int.random(in: 0..<14, using: &rng) > 0 else { continue }

            // Weekends run lighter, which is what makes the month grid worth
            // looking at — a uniform month would prove nothing about the view.
            let weekday = calendar.component(.weekday, from: day)
            let isWeekend = weekday == 1 || weekday == 7
            let centre = Double(typicalSteps) * (isWeekend ? 0.62 : 1.0)
            let steps = max(0, Int(centre * Double.random(in: 0.55...1.35, using: &rng)))

            result[day] = DailyActivity(
                day: day,
                steps: steps,
                // Roughly 0.04 kcal per step for a ~180 lb walker, plus a
                // baseline for everything that is not walking.
                activeKilocalories: Double(steps) * 0.04 + Double.random(in: 40...220, using: &rng),
                restingKilocalories: Double.random(in: 1_600...1_750, using: &rng),
                // Sample data is allowed to derive distance from steps, since
                // there is no phone to ask. Real data never does — see the
                // note on `distanceMeters`.
                distanceMeters: Double(steps) * Double.random(in: 0.70...0.80, using: &rng)
            )
        }
        return result
    }
}

extension SampleActivitySource {

    /// A plausible week's training, repeated: runs, strength, the odd walk.
    /// Same seeding rule as the step data — a given day always produces the
    /// same session, so screenshots do not drift.
    func workouts(from start: Date, to end: Date) async throws -> [Workout] {
        let kinds: [(String, String, Double, Double?)] = [
            ("Run", "figure.run", 420, 5_200),
            ("Strength", "dumbbell", 310, nil),
            ("Walk", "figure.walk", 180, 3_100),
            ("HIIT", "figure.highintensity.intervaltraining", 350, nil),
            ("Cycle", "bicycle", 460, 14_800),
        ]

        var result: [Workout] = []
        var day = calendar.startOfDay(for: start)
        let last = min(calendar.startOfDay(for: end), calendar.startOfDay(for: .now))

        while day <= last {
            defer { day = calendar.date(byAdding: .day, value: 1, to: day) ?? last.addingTimeInterval(1) }

            var rng = SeededGenerator(seed: UInt64(abs(day.timeIntervalSince1970.rounded())) &+ 77)
            // Roughly four sessions a week.
            guard Int.random(in: 0..<7, using: &rng) < 4 else { continue }

            let (kind, symbol, kcal, metres) = kinds[Int.random(in: 0..<kinds.count, using: &rng)]
            let startHour = Int.random(in: 6...19, using: &rng)
            let minutes = Double(Int.random(in: 25...75, using: &rng))
            guard let begin = calendar.date(byAdding: .hour, value: startHour, to: day) else { continue }

            result.append(
                Workout(
                    start: begin,
                    end: begin.addingTimeInterval(minutes * 60),
                    kind: kind,
                    symbol: symbol,
                    activeKilocalories: kcal * (minutes / 45),
                    distanceMeters: metres.map { $0 * (minutes / 45) }
                )
            )
        }
        return result
    }
}

/// xorshift64. Not for anything that needs real randomness — only for sample
/// data that has to look varied and be identical on every run.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = (seed &* 6_364_136_223_846_793_005) &+ 1_442_695_040_888_963_407 | 1 }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

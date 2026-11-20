import Foundation
import HealthKit

/// Everything Verus asks Apple Health for.
///
/// One thing about HealthKit shapes this whole file: **it never tells you that
/// a read was denied.** Apple treats "this app may not see your steps" as
/// itself private, so a denied read type returns an empty result that is
/// indistinguishable from a genuinely empty week. `authorizationStatus` only
/// reports write permission honestly.
///
/// So there is no `isAuthorized` here, because there could not be an honest
/// one. What the app can know is whether it has *asked*, and whether anything
/// came back — and those two together are what `ActivityStore` uses to decide
/// whether to suggest checking Settings. Guessing harder than that would mean
/// telling the user something we do not know.
final class HealthKitService: @unchecked Sendable {

    /// `HKHealthStore` is documented as safe to call from any thread, which is
    /// what the `@unchecked` above is standing on. It is not `Sendable` only
    /// because Apple has not annotated it.
    private let store = HKHealthStore()

    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        var c = calendar
        c.firstWeekday = 2
        self.calendar = c
    }

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: - Types

    private static let stepType = HKQuantityType(.stepCount)
    private static let activeEnergyType = HKQuantityType(.activeEnergyBurned)
    private static let restingEnergyType = HKQuantityType(.basalEnergyBurned)
    private static let bodyMassType = HKQuantityType(.bodyMass)
    private static let bodyFatType = HKQuantityType(.bodyFatPercentage)

    private static var readTypes: Set<HKObjectType> {
        [stepType, activeEnergyType, restingEnergyType, bodyMassType, bodyFatType,
         HKObjectType.workoutType()]
    }

    /// Only weight is written back. Verus does not invent steps or energy, so
    /// asking to write them would be asking for permission it has no use for.
    private static var writeTypes: Set<HKSampleType> { [bodyMassType] }

    // MARK: - Authorization

    enum HealthKitError: LocalizedError {
        case unavailable
        case queryFailed(String)

        var errorDescription: String? {
            switch self {
            case .unavailable:
                "Apple Health is not available on this device."
            case .queryFailed(let detail):
                detail
            }
        }
    }

    /// Presents the permission sheet. Returns once the user has answered.
    ///
    /// A successful return means only that the sheet was shown and dismissed —
    /// *not* that anything was granted. See the note at the top of this file.
    func requestAuthorization() async throws {
        guard Self.isAvailable else { throw HealthKitError.unavailable }
        try await store.requestAuthorization(toShare: Self.writeTypes, read: Self.readTypes)
    }

    /// Whether the permission sheet has ever been shown for our write type.
    /// `.notDetermined` is the one status that is reliable and useful: it means
    /// we have not asked yet.
    var hasRequestedAuthorization: Bool {
        guard Self.isAvailable else { return false }
        return store.authorizationStatus(for: Self.bodyMassType) != .notDetermined
    }

    // MARK: - Daily totals

    /// Daily sums for one quantity type, keyed by midnight of each day.
    ///
    /// Days with no samples are left out rather than recorded as zero — a
    /// phone left at home is missing data, not a day of stillness, and the
    /// calendar draws those two differently.
    private func dailySums(
        of type: HKQuantityType,
        unit: HKUnit,
        from start: Date,
        to end: Date
    ) async throws -> [Date: Double] {
        let anchor = calendar.startOfDay(for: start)
        let endOfRange = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
        let predicate = HKQuery.predicateForSamples(
            withStart: anchor, end: endOfRange, options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchor,
                intervalComponents: DateComponents(day: 1)
            )

            query.initialResultsHandler = { [calendar] _, results, error in
                if let error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error.localizedDescription))
                    return
                }
                guard let results else {
                    continuation.resume(returning: [:])
                    return
                }

                var totals: [Date: Double] = [:]
                results.enumerateStatistics(from: anchor, to: endOfRange) { statistics, _ in
                    guard let sum = statistics.sumQuantity() else { return }
                    totals[calendar.startOfDay(for: statistics.startDate)] = sum.doubleValue(for: unit)
                }
                continuation.resume(returning: totals)
            }

            store.execute(query)
        }
    }

    // MARK: - Weight

    /// Every weigh-in Health knows about in the range, newest last.
    func weightEntries(from start: Date, to end: Date) async throws -> [WeightEntry] {
        guard Self.isAvailable else { throw HealthKitError.unavailable }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: Self.bodyMassType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error.localizedDescription))
                    return
                }
                let entries = (samples as? [HKQuantitySample] ?? []).map { sample in
                    WeightEntry(
                        date: sample.startDate,
                        kilograms: sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                    )
                }
                continuation.resume(returning: entries)
            }
            store.execute(query)
        }
    }

    // MARK: - Workouts

    /// Workouts in the range, newest last.
    ///
    /// These are the same records Strava and Apple Fitness read — a run
    /// logged on the watch arrives here without the user entering anything,
    /// which is the whole claim behind replacing that part of the stack.
    func workouts(from start: Date, to end: Date) async throws -> [Workout] {
        guard Self.isAvailable else { throw HealthKitError.unavailable }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error.localizedDescription))
                    return
                }
                let workouts = (samples as? [HKWorkout] ?? []).map { workout in
                    Workout(
                        start: workout.startDate,
                        end: workout.endDate,
                        kind: Self.name(for: workout.workoutActivityType),
                        symbol: Self.symbol(for: workout.workoutActivityType),
                        activeKilocalories: workout
                            .statistics(for: HKQuantityType(.activeEnergyBurned))?
                            .sumQuantity()?
                            .doubleValue(for: .kilocalorie()),
                        distanceMeters: workout
                            .statistics(for: HKQuantityType(.distanceWalkingRunning))?
                            .sumQuantity()?
                            .doubleValue(for: .meter())
                    )
                }
                continuation.resume(returning: workouts)
            }
            store.execute(query)
        }
    }

    /// A readable name for the handful of activity types this user actually
    /// logs. Anything else falls back to "Workout" rather than to a raw
    /// enum case — `HKWorkoutActivityType` has over eighty members and
    /// most of them would never appear here.
    static func name(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: "Run"
        case .walking: "Walk"
        case .hiking: "Hike"
        case .cycling: "Cycle"
        case .swimming: "Swim"
        case .traditionalStrengthTraining, .functionalStrengthTraining: "Strength"
        case .highIntensityIntervalTraining: "HIIT"
        case .yoga: "Yoga"
        case .coreTraining: "Core"
        case .elliptical: "Elliptical"
        case .rowing: "Row"
        case .stairClimbing, .stairs: "Stairs"
        case .soccer: "Football"
        case .basketball: "Basketball"
        default: "Workout"
        }
    }

    static func symbol(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: "figure.run"
        case .walking: "figure.walk"
        case .hiking: "figure.hiking"
        case .cycling: "bicycle"
        case .swimming: "figure.pool.swim"
        case .traditionalStrengthTraining, .functionalStrengthTraining: "dumbbell"
        case .highIntensityIntervalTraining: "figure.highintensity.intervaltraining"
        case .yoga: "figure.yoga"
        case .coreTraining: "figure.core.training"
        case .elliptical: "figure.elliptical"
        case .rowing: "figure.rower"
        case .stairClimbing, .stairs: "figure.stairs"
        case .soccer: "figure.soccer"
        case .basketball: "figure.basketball"
        default: "figure.mixed.cardio"
        }
    }

    /// Writes a weigh-in back, so the rest of the phone stays in step.
    ///
    /// Write permission *is* honestly reported, so this one can refuse up
    /// front rather than silently doing nothing.
    func save(entry: WeightEntry) async throws {
        guard Self.isAvailable else { throw HealthKitError.unavailable }
        guard store.authorizationStatus(for: Self.bodyMassType) == .sharingAuthorized else {
            throw HealthKitError.queryFailed("Verus is not allowed to write weight to Apple Health.")
        }
        let sample = HKQuantitySample(
            type: Self.bodyMassType,
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: entry.kilograms),
            start: entry.date,
            end: entry.date
        )
        try await store.save(sample)
    }
}

// MARK: - ActivitySource

extension HealthKitService: ActivitySource {

    func dailyActivity(from start: Date, to end: Date) async throws -> [Date: DailyActivity] {
        guard Self.isAvailable else { throw HealthKitError.unavailable }

        // Three independent queries, run together rather than in sequence —
        // a month of three types is three round trips, and they do not depend
        // on each other.
        async let steps = dailySums(of: Self.stepType, unit: .count(), from: start, to: end)
        async let active = dailySums(of: Self.activeEnergyType, unit: .kilocalorie(), from: start, to: end)
        async let resting = dailySums(of: Self.restingEnergyType, unit: .kilocalorie(), from: start, to: end)

        let (stepsByDay, activeByDay, restingByDay) = try await (steps, active, resting)

        // A day counts as known if *any* of the three reported. Energy without
        // steps is a real state — a swim, a cycle — and dropping those days
        // would blank out exactly the days someone trained hardest.
        let days = Set(stepsByDay.keys)
            .union(activeByDay.keys)
            .union(restingByDay.keys)

        return Dictionary(uniqueKeysWithValues: days.map { day in
            (day, DailyActivity(
                day: day,
                steps: Int((stepsByDay[day] ?? 0).rounded()),
                activeKilocalories: activeByDay[day] ?? 0,
                restingKilocalories: restingByDay[day] ?? 0
            ))
        })
    }
}

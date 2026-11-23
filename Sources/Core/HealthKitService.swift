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
    private static let distanceType = HKQuantityType(.distanceWalkingRunning)
    private static let activeEnergyType = HKQuantityType(.activeEnergyBurned)
    private static let restingEnergyType = HKQuantityType(.basalEnergyBurned)
    private static let exerciseTimeType = HKQuantityType(.appleExerciseTime)
    private static let flightsType = HKQuantityType(.flightsClimbed)
    private static let restingHeartRateType = HKQuantityType(.restingHeartRate)
    private static let hrvType = HKQuantityType(.heartRateVariabilitySDNN)
    private static let heightType = HKQuantityType(.height)
    private static let waistType = HKQuantityType(.waistCircumference)
    private static let sleepType = HKCategoryType(.sleepAnalysis)
    private static let dietaryEnergyType = HKQuantityType(.dietaryEnergyConsumed)
    private static let proteinType = HKQuantityType(.dietaryProtein)
    private static let carbsType = HKQuantityType(.dietaryCarbohydrates)
    private static let fatType = HKQuantityType(.dietaryFatTotal)
    private static let bodyMassType = HKQuantityType(.bodyMass)
    private static let bodyFatType = HKQuantityType(.bodyFatPercentage)
    private static let leanMassType = HKQuantityType(.leanBodyMass)
    private static let bodyMassIndexType = HKQuantityType(.bodyMassIndex)

    /// What a connected scale writes, beyond the weight itself.
    ///
    /// These four are the whole of what HealthKit models of body
    /// composition. A scale's own app may also show body water, bone mass,
    /// visceral fat or a "metabolic age"; Apple Health has no type for any of
    /// them, so they never reach Verus and Verus does not pretend to have
    /// them.
    private static var bodyCompositionTypes: [HKQuantityType] {
        [bodyMassType, bodyFatType, leanMassType, bodyMassIndexType]
    }

    /// Everything Verus asks to read.
    ///
    /// The list is deliberately not "everything HealthKit has". There is no
    /// wildcard in HealthKit anyway — the types must be named — but the rule
    /// applied here is stricter than the API's: **a type is requested only if
    /// something on a screen shows it.** A permission sheet of a hundred and
    /// seventy toggles is how an app gets Don't Allow tapped, and reading
    /// data that lands nowhere is asking for something for no reason.
    ///
    /// So: movement and energy for the calendar and the Activity screen;
    /// body composition for the Weight screen; height for a BMI the app can
    /// work out itself; waist for the Progress screen's measurements; resting
    /// heart rate, HRV and sleep for the rest figures on a day's detail.
    private static var readTypes: Set<HKObjectType> {
        Set(bodyCompositionTypes as [HKObjectType]).union([
            stepType, distanceType, activeEnergyType, restingEnergyType,
            exerciseTimeType, flightsType,
            restingHeartRateType, hrvType, sleepType,
            heightType, waistType,
            dietaryEnergyType, proteinType, carbsType, fatType,
            HKObjectType.workoutType(),
        ])
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

    /// Whether asking again would actually show the user something.
    ///
    /// This matters every time a version adds a read type. Someone who
    /// granted steps, energy and weight months ago has never been asked about
    /// distance or body fat, and those reads would quietly return nothing —
    /// the same silence a denial produces, since HealthKit does not
    /// distinguish them. `getRequestStatusForAuthorization` is the one honest
    /// answer available here: it reports whether any requested type is still
    /// undecided, without revealing what was decided.
    var hasTypesNotYetRequested: Bool {
        get async {
            guard Self.isAvailable else { return false }
            return await withCheckedContinuation { continuation in
                store.getRequestStatusForAuthorization(
                    toShare: Self.writeTypes, read: Self.readTypes
                ) { status, _ in
                    continuation.resume(returning: status == .shouldRequest)
                }
            }
        }
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

    /// Daily averages for a quantity Health records as readings rather than
    /// as a running total.
    ///
    /// Steps add up; a heart rate does not. Summing six resting heart rate
    /// samples would report a pulse of 350, so these go through
    /// `.discreteAverage` and days with no reading stay absent.
    private func dailyAverages(
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
                options: .discreteAverage,
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
                var values: [Date: Double] = [:]
                results.enumerateStatistics(from: anchor, to: endOfRange) { statistics, _ in
                    guard let average = statistics.averageQuantity() else { return }
                    values[calendar.startOfDay(for: statistics.startDate)] = average.doubleValue(for: unit)
                }
                continuation.resume(returning: values)
            }

            store.execute(query)
        }
    }

    /// The date of the oldest step sample Health holds.
    ///
    /// The year view used to offer every year back to the start of the
    /// calendar, so someone whose data begins in 2022 could page back to
    /// 2019 and read "nothing recorded" three times. One query answers it:
    /// the earliest sample there is.
    func earliestActivityDate() async throws -> Date? {
        guard Self.isAvailable else { throw HealthKitError.unavailable }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: Self.stepType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error.localizedDescription))
                    return
                }
                continuation.resume(returning: samples?.first?.startDate)
            }
            store.execute(query)
        }
    }

    // MARK: - Sleep

    /// Hours asleep, keyed by the morning each night ended on.
    ///
    /// Only the asleep values count: `inBed` is time spent lying there, which
    /// is a different claim and one the user did not make. Overlapping
    /// records from several sources are merged rather than added — see
    /// `SleepRollup`.
    private func sleepHours(from start: Date, to end: Date) async throws -> [Date: Double] {
        // A night that ends inside the range may have begun before it, so the
        // window reaches back a day.
        let windowStart = calendar.date(byAdding: .day, value: -1, to: start) ?? start
        let predicate = HKQuery.predicateForSamples(
            withStart: windowStart, end: end, options: []
        )
        let asleep = Set(HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue))

        let sessions: [SleepSession] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: Self.sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error.localizedDescription))
                    return
                }
                let stretches = (samples as? [HKCategorySample] ?? [])
                    .filter { asleep.contains($0.value) }
                    .map { SleepSession(start: $0.startDate, end: $0.endDate) }
                continuation.resume(returning: stretches)
            }
            store.execute(query)
        }

        return SleepRollup.hoursByNight(sessions, calendar: calendar)
    }

    // MARK: - Food

    /// Meals logged in other apps, with their macros where they can be
    /// matched.
    ///
    /// Verus does not write food to Health, so everything read here came
    /// from somewhere else and nothing can be read back as a duplicate of
    /// Verus's own log. `DietaryImport` says what depends on that.
    func dietaryEntries(from start: Date, to end: Date, calendar: Calendar) async throws -> [FoodEntry] {
        guard Self.isAvailable else { throw HealthKitError.unavailable }

        async let energy = dietaryReadings(from: start, to: end)
        async let protein = quantitySamples(of: Self.proteinType, unit: .gram(), from: start, to: end)
        async let carbs = quantitySamples(of: Self.carbsType, unit: .gram(), from: start, to: end)
        async let fat = quantitySamples(of: Self.fatType, unit: .gram(), from: start, to: end)

        let (readings, proteinSamples, carbSamples, fatSamples) =
            try await (energy, protein, carbs, fat)

        return DietaryImport.entries(
            from: readings,
            protein: proteinSamples,
            carbs: carbSamples,
            fat: fatSamples,
            calendar: calendar
        )
    }

    private func dietaryReadings(from start: Date, to end: Date) async throws -> [DietaryReading] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: Self.dietaryEnergyType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error.localizedDescription))
                    return
                }
                let readings = (samples as? [HKQuantitySample] ?? []).map { sample in
                    DietaryReading(
                        healthIdentifier: sample.uuid,
                        date: sample.startDate,
                        kilocalories: sample.quantity.doubleValue(for: .kilocalorie()),
                        // Most logging apps put the food's name here. The
                        // ones that do not fall back to their own name,
                        // which at least says where the number came from.
                        foodName: sample.metadata?[HKMetadataKeyFoodType] as? String,
                        sourceName: sample.sourceRevision.source.name
                    )
                }
                continuation.resume(returning: readings)
            }
            store.execute(query)
        }
    }

    // MARK: - Body measurements

    /// The most recent height on file, in metres — what lets Verus work out a
    /// BMI for a scale that does not send one.
    func latestHeightMeters() async throws -> Double? {
        guard Self.isAvailable else { throw HealthKitError.unavailable }
        let samples = try await quantitySamples(
            of: Self.heightType, unit: .meter(),
            from: .distantPast, to: .now
        )
        return samples.last?.value
    }

    /// Waist measurements in centimetres, for the Progress screen's tape
    /// measurements — which are stored in centimetres for the same reason.
    func waistSamples(from start: Date, to end: Date) async throws -> [BodyMetricSample] {
        guard Self.isAvailable else { throw HealthKitError.unavailable }
        return try await quantitySamples(
            of: Self.waistType, unit: .meterUnit(with: .centi), from: start, to: end
        )
    }

    // MARK: - Weight

    /// Every weigh-in Health knows about in the range, newest last — with
    /// whatever body composition was recorded alongside it.
    ///
    /// A connected scale writes weight, body fat, lean mass and BMI as four
    /// separate samples taken at the same instant. All four are read here and
    /// stitched back together by `BodyMetrics`, so one step onto the scale
    /// arrives in Verus as one weigh-in rather than as four unrelated
    /// numbers.
    func weightEntries(from start: Date, to end: Date) async throws -> [WeightEntry] {
        guard Self.isAvailable else { throw HealthKitError.unavailable }

        async let weights = quantitySamples(
            of: Self.bodyMassType, unit: .gramUnit(with: .kilo), from: start, to: end
        )
        // Body fat comes out of HealthKit as a fraction — 0.182, not 18.2 —
        // and the whole app reads it as a percentage. The conversion happens
        // here, at the boundary, and nowhere else.
        async let bodyFat = quantitySamples(
            of: Self.bodyFatType, unit: .percent(), from: start, to: end
        )
        async let lean = quantitySamples(
            of: Self.leanMassType, unit: .gramUnit(with: .kilo), from: start, to: end
        )
        async let bmi = quantitySamples(
            of: Self.bodyMassIndexType, unit: .count(), from: start, to: end
        )

        let (weightSamples, fatSamples, leanSamples, bmiSamples) =
            try await (weights, bodyFat, lean, bmi)

        let entries = weightSamples.map {
            WeightEntry(date: $0.date, kilograms: $0.value)
        }

        return BodyMetrics.enrich(
            entries,
            bodyFatPercent: fatSamples.map { BodyMetricSample(date: $0.date, value: $0.value * 100) },
            leanKilograms: leanSamples,
            bodyMassIndex: bmiSamples
        )
    }

    /// Individual samples of one quantity type, oldest first.
    ///
    /// Unlike `dailySums` this does not bucket by day: a weigh-in is an
    /// instant, and the instant is what ties it to the body-fat reading taken
    /// with it.
    private func quantitySamples(
        of type: HKQuantityType,
        unit: HKUnit,
        from start: Date,
        to end: Date
    ) async throws -> [BodyMetricSample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error.localizedDescription))
                    return
                }
                let values = (samples as? [HKQuantitySample] ?? []).map {
                    BodyMetricSample(date: $0.startDate, value: $0.quantity.doubleValue(for: unit))
                }
                continuation.resume(returning: values)
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

        // Four independent queries, run together rather than in sequence —
        // a month of four types is four round trips, and they do not depend
        // on each other.
        async let steps = dailySums(of: Self.stepType, unit: .count(), from: start, to: end)
        async let distance = dailySums(of: Self.distanceType, unit: .meter(), from: start, to: end)
        async let active = dailySums(of: Self.activeEnergyType, unit: .kilocalorie(), from: start, to: end)
        async let resting = dailySums(of: Self.restingEnergyType, unit: .kilocalorie(), from: start, to: end)
        async let exercise = dailySums(of: Self.exerciseTimeType, unit: .minute(), from: start, to: end)
        async let flights = dailySums(of: Self.flightsType, unit: .count(), from: start, to: end)
        // Averaged, not summed — see `dailyAverages`.
        async let heartRate = dailyAverages(
            of: Self.restingHeartRateType, unit: .count().unitDivided(by: .minute()),
            from: start, to: end
        )
        async let hrv = dailyAverages(
            of: Self.hrvType, unit: .secondUnit(with: .milli), from: start, to: end
        )
        async let sleep = sleepHours(from: start, to: end)

        let (stepsByDay, distanceByDay, activeByDay, restingByDay) =
            try await (steps, distance, active, resting)
        let (exerciseByDay, flightsByDay, heartRateByDay, hrvByDay, sleepByDay) =
            try await (exercise, flights, heartRate, hrv, sleep)

        // A day counts as known if *any* of them reported. Energy without
        // steps is a real state — a swim, a cycle — and dropping those days
        // would blank out exactly the days someone trained hardest. Sleep and
        // heart rate are deliberately **not** in this union: a night's sleep
        // does not make a day of movement exist, and letting it would draw
        // calendar cells for days the phone recorded nothing else about.
        let days = Set(stepsByDay.keys)
            .union(distanceByDay.keys)
            .union(activeByDay.keys)
            .union(restingByDay.keys)
            .union(exerciseByDay.keys)
            .union(flightsByDay.keys)

        return Dictionary(uniqueKeysWithValues: days.map { day in
            (day, DailyActivity(
                day: day,
                steps: Int((stepsByDay[day] ?? 0).rounded()),
                activeKilocalories: activeByDay[day] ?? 0,
                restingKilocalories: restingByDay[day] ?? 0,
                distanceMeters: distanceByDay[day],
                exerciseMinutes: exerciseByDay[day],
                flightsClimbed: flightsByDay[day].map { Int($0.rounded()) },
                restingHeartRate: heartRateByDay[day],
                heartRateVariabilityMilliseconds: hrvByDay[day],
                sleepHours: sleepByDay[day]
            ))
        })
    }
}

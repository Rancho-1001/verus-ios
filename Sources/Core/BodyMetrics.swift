import Foundation

/// One reading of one body measurement, as Apple Health stores it.
struct BodyMetricSample: Hashable, Sendable {
    let date: Date
    let value: Double
}

/// Putting a smart scale's readings back together.
///
/// A connected scale does not write one record. It writes four or five
/// separate samples — weight, body fat, lean mass, BMI — each its own entry
/// in Apple Health, tied together by nothing but the instant they were taken.
/// HealthKit has no notion of "this body-fat reading belongs to that
/// weigh-in", so matching them up is the app's job.
///
/// That is what this file does, and it is pure on purpose: the matching rule
/// is the part that can be subtly wrong, so it is the part that gets tests
/// rather than a device and a hopeful look at the screen.
enum BodyMetrics {

    /// How far apart two samples can be and still be the same step onto the
    /// scale. A scale writes its samples within a second or two of each
    /// other; fifteen minutes is loose enough to survive a slow sync and
    /// tight enough that this morning's weigh-in cannot borrow last night's
    /// body fat.
    static let matchTolerance: TimeInterval = 15 * 60

    /// The value measured nearest `date`, if one falls inside `tolerance`.
    ///
    /// Nearest rather than first: if a scale was stepped on twice in a
    /// quarter of an hour, each weigh-in should take the body fat recorded
    /// with it, not the earlier one.
    static func nearest(
        to date: Date,
        in samples: [BodyMetricSample],
        tolerance: TimeInterval = matchTolerance
    ) -> Double? {
        samples
            .filter { abs($0.date.timeIntervalSince(date)) <= tolerance }
            .min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }?
            .value
    }

    /// Fills in each weigh-in's composition from samples taken at the same
    /// moment. Fields that are already set are left alone.
    static func enrich(
        _ entries: [WeightEntry],
        bodyFatPercent: [BodyMetricSample] = [],
        leanKilograms: [BodyMetricSample] = [],
        bodyMassIndex: [BodyMetricSample] = [],
        tolerance: TimeInterval = matchTolerance
    ) -> [WeightEntry] {
        guard !bodyFatPercent.isEmpty || !leanKilograms.isEmpty || !bodyMassIndex.isEmpty else {
            return entries
        }
        return entries.map { entry in
            entry.filling(
                bodyFatPercent: nearest(to: entry.date, in: bodyFatPercent, tolerance: tolerance),
                leanKilograms: nearest(to: entry.date, in: leanKilograms, tolerance: tolerance),
                bodyMassIndex: nearest(to: entry.date, in: bodyMassIndex, tolerance: tolerance)
            )
        }
    }

    /// What a sync did.
    struct MergeResult: Equatable, Sendable {
        let entries: [WeightEntry]
        /// Weigh-ins that were not here before.
        let added: Int
        /// Weigh-ins that were already here and gained a composition figure
        /// they did not have.
        let enriched: Int
    }

    /// Merges weigh-ins read from Apple Health into the ones already stored.
    ///
    /// Two rules, and the second one is why this function exists at all:
    ///
    /// 1. A weigh-in already stored is not added twice. Verus writes its own
    ///    entries back to Health, so a naive import would read them straight
    ///    back and double every morning. Same day and same weight to a tenth
    ///    of a kilogram is the same weigh-in, whichever app recorded it.
    ///
    /// 2. A match is **enriched**, not skipped. Earlier versions read weight
    ///    alone, so a scale's weigh-ins are already stored stripped of the
    ///    body fat and lean mass that came with them. Skipping a duplicate
    ///    would mean those readings could never arrive — the data would be
    ///    sitting in Health, matching a row that would never ask for it again.
    static func merge(
        existing: [WeightEntry],
        imported: [WeightEntry],
        calendar: Calendar
    ) -> MergeResult {
        var result = existing
        var indexByFingerprint: [String: Int] = [:]
        for (index, entry) in result.enumerated() {
            indexByFingerprint[fingerprint(entry, calendar: calendar)] = index
        }

        var added = 0
        var enriched = 0

        for entry in imported {
            let key = fingerprint(entry, calendar: calendar)
            guard let index = indexByFingerprint[key] else {
                indexByFingerprint[key] = result.count
                result.append(entry)
                added += 1
                continue
            }
            let before = result[index]
            let after = before.filling(
                bodyFatPercent: entry.bodyFatPercent,
                leanKilograms: entry.leanKilograms,
                bodyMassIndex: entry.bodyMassIndex
            )
            if after != before {
                result[index] = after
                enriched += 1
            }
        }

        if added > 0 || enriched > 0 {
            result.sort { $0.date < $1.date }
        }
        return MergeResult(entries: result, added: added, enriched: enriched)
    }

    /// Same day, same weight to 100 g — the same weigh-in.
    static func fingerprint(_ entry: WeightEntry, calendar: Calendar) -> String {
        let day = calendar.startOfDay(for: entry.date).timeIntervalSince1970
        return "\(Int(day))|\((entry.kilograms * 10).rounded())"
    }
}

import Foundation

/// One dietary-energy record as Apple Health holds it.
struct DietaryReading: Hashable, Sendable {
    /// The Health sample's own identifier — stable across reads, which is
    /// what makes an exact re-import possible.
    let healthIdentifier: UUID
    let date: Date
    let kilocalories: Double
    /// What was eaten, when the app that logged it said so. Many do not.
    let foodName: String?
    /// The app that wrote the record.
    let sourceName: String
}

/// Food logged in another app, brought in through Apple Health.
///
/// The question this file answers is the one that kept dietary data out of
/// Verus until now: **if two apps have today's lunch, which one is the
/// budget built from?**
///
/// The answer here is that there is no overlap to resolve, because Verus
/// does not write food to Health. Every dietary record in Health came from
/// somewhere else, so the whole day is simply Verus's own entries plus the
/// external ones, with nothing counted twice. That holds only while Verus
/// stays read-only on dietary types — if it ever writes a meal back, this
/// file needs a rule for its own echo, the way `BodyMetrics` has one for
/// weight.
enum DietaryImport {

    /// How close a macronutrient sample must be to count as part of the same
    /// food. Apps write a food's calories and its macros within the same
    /// second; a minute is loose enough for a slow sync and tight enough not
    /// to borrow from the next item.
    static let macroTolerance: TimeInterval = 60

    /// Turns Health's records into entries the Food screen can show.
    ///
    /// Macros are attached only when a reading is alone at its timestamp.
    /// Logging a breakfast of three items usually writes all three at the
    /// same instant, and there is no way to tell which protein sample
    /// belongs to which — so rather than distribute them by guesswork, the
    /// calories stand on their own and the macros are left off.
    static func entries(
        from readings: [DietaryReading],
        protein: [BodyMetricSample] = [],
        carbs: [BodyMetricSample] = [],
        fat: [BodyMetricSample] = [],
        calendar: Calendar,
        tolerance: TimeInterval = macroTolerance
    ) -> [FoodEntry] {
        readings.map { reading in
            let alone = readings.allSatisfy { other in
                other.healthIdentifier == reading.healthIdentifier
                    || abs(other.date.timeIntervalSince(reading.date)) > tolerance
            }
            return FoodEntry(
                date: reading.date,
                name: reading.foodName ?? reading.sourceName,
                kilocalories: reading.kilocalories,
                proteinGrams: alone
                    ? BodyMetrics.nearest(to: reading.date, in: protein, tolerance: tolerance)
                    : nil,
                carbGrams: alone
                    ? BodyMetrics.nearest(to: reading.date, in: carbs, tolerance: tolerance)
                    : nil,
                fatGrams: alone
                    ? BodyMetrics.nearest(to: reading.date, in: fat, tolerance: tolerance)
                    : nil,
                meal: Meal.suggested(at: reading.date, calendar: calendar),
                source: .appleHealth,
                healthIdentifier: reading.healthIdentifier,
                externalSourceName: reading.sourceName
            )
        }
    }

    struct MergeResult: Equatable, Sendable {
        let entries: [FoodEntry]
        let added: Int
        /// Rows whose figures changed in the app that wrote them.
        let updated: Int
        /// Rows deleted in the app that wrote them, and so deleted here.
        let removed: Int
    }

    /// Merges an import into what is already stored.
    ///
    /// Three things happen, and the third is the one that is easy to leave
    /// out: a record deleted in the app that wrote it is deleted here too.
    /// Without that, correcting a mistyped 1,800 kcal lunch in MyFitnessPal
    /// would leave the wrong figure in Verus for ever, and the budget would
    /// quietly disagree with the app the user actually fixed.
    ///
    /// Pruning is confined to `window`, the range that was just read.
    /// Anything outside it was not asked about and so is not evidence of
    /// anything.
    static func merge(
        existing: [FoodEntry],
        imported: [FoodEntry],
        window: ClosedRange<Date>
    ) -> MergeResult {
        let importedByIdentifier = Dictionary(
            imported.compactMap { entry in entry.healthIdentifier.map { ($0, entry) } },
            uniquingKeysWith: { first, _ in first }
        )

        var result: [FoodEntry] = []
        var updated = 0
        var removed = 0

        for entry in existing {
            // Anything the user logged in Verus is untouched, always.
            guard entry.source == .appleHealth, let identifier = entry.healthIdentifier else {
                result.append(entry)
                continue
            }
            if let fresh = importedByIdentifier[identifier] {
                let merged = entry.updated(from: fresh)
                if merged != entry { updated += 1 }
                result.append(merged)
            } else if window.contains(entry.date) {
                // Was in this range, is not in Health any more: deleted there.
                removed += 1
            } else {
                result.append(entry)
            }
        }

        let known = Set(result.compactMap(\.healthIdentifier))
        var added = 0
        for entry in imported {
            guard let identifier = entry.healthIdentifier, !known.contains(identifier) else { continue }
            result.append(entry)
            added += 1
        }

        if added > 0 || updated > 0 || removed > 0 {
            result.sort { $0.date < $1.date }
        }
        return MergeResult(entries: result, added: added, updated: updated, removed: removed)
    }
}

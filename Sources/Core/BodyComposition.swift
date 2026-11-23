import Foundation

/// How a weight goal and a body-fat goal relate to each other.
///
/// The concept asks for this explicitly: *"At that goal weight, the weight
/// and body-fat goals converge — the projection should make relationships
/// like that visible, not just draw a line to a date."*
///
/// The arithmetic is simple and rests on one assumption, stated here rather
/// than buried: **lean mass is held constant.** That is roughly true of a
/// careful deficit with resistance training and badly false of a crash diet,
/// which is why every result carries the assumption into the UI rather than
/// presenting itself as a measurement.
enum BodyComposition {

    /// Lean mass — everything that is not fat.
    ///
    /// Returns `nil` for a percentage outside (0, 100): zero per cent body fat
    /// is not survivable and a hundred is not a person, so both are data entry
    /// errors rather than edge cases to model.
    static func leanKilograms(weightKilograms: Double, bodyFatPercent: Double) -> Double? {
        guard bodyFatPercent > 0, bodyFatPercent < 100, weightKilograms > 0 else { return nil }
        return weightKilograms * (1 - bodyFatPercent / 100)
    }

    /// The weight at which a body-fat target is reached, if lean mass holds.
    ///
    /// Losing a kilogram of fat removes a kilogram from the scale *and* lowers
    /// the percentage, so the two goals are not independent — this is the
    /// weight where the second one lands.
    static func weightForBodyFat(
        targetPercent: Double,
        leanKilograms: Double
    ) -> Double? {
        guard targetPercent > 0, targetPercent < 100, leanKilograms > 0 else { return nil }
        return leanKilograms / (1 - targetPercent / 100)
    }

    /// What the two goals mean together.
    enum GoalRelationship: Equatable, Sendable {
        /// No body fat recorded, so there is nothing to relate.
        case noBodyFatRecorded
        /// The body-fat target lands within `tolerance` of the weight target.
        /// Reaching one is reaching the other.
        case converge(atPounds: Double)
        /// Body fat arrives first: you would be under the target percentage
        /// while still above the target weight.
        case bodyFatReachedFirst(atPounds: Double)
        /// Weight arrives first: you would hit the target weight still above
        /// the target percentage.
        case weightReachedFirst(atPounds: Double)
    }

    /// Within this many pounds, the two goals are the same goal. Two pounds is
    /// inside the error of any consumer body-fat measurement, so splitting
    /// hairs below it would be false precision.
    static let convergenceTolerancePounds = 2.0

    /// Relates a weight goal and a body-fat goal at the user's current
    /// composition.
    static func relationship(
        currentWeightKilograms: Double,
        currentBodyFatPercent: Double?,
        goalWeightKilograms: Double,
        goalBodyFatPercent: Double
    ) -> GoalRelationship {
        guard let bodyFat = currentBodyFatPercent,
              let lean = leanKilograms(
                  weightKilograms: currentWeightKilograms, bodyFatPercent: bodyFat
              ),
              let weightAtTargetFat = weightForBodyFat(
                  targetPercent: goalBodyFatPercent, leanKilograms: lean
              )
        else {
            return .noBodyFatRecorded
        }

        let atPounds = weightAtTargetFat * WeightEntry.poundsPerKilogram
        let goalPounds = goalWeightKilograms * WeightEntry.poundsPerKilogram
        let difference = atPounds - goalPounds

        if abs(difference) <= convergenceTolerancePounds {
            return .converge(atPounds: atPounds)
        }
        // The body-fat target lands at a *higher* weight than the weight goal,
        // so coming down the scale crosses it first.
        return difference > 0
            ? .bodyFatReachedFirst(atPounds: atPounds)
            : .weightReachedFirst(atPounds: atPounds)
    }

    /// Body mass index: kilograms over metres squared.
    ///
    /// Here rather than on `WeightEntry` because it needs a height, which is
    /// a fact about the person and not about the weigh-in. Returns `nil`
    /// without one — a BMI from an assumed height is a number with no
    /// meaning, and the UI would have no way to tell it from a real one.
    static func bodyMassIndex(weightKilograms: Double, heightMeters: Double?) -> Double? {
        guard let heightMeters, heightMeters > 0.5, heightMeters < 2.8, weightKilograms > 0 else {
            return nil
        }
        return weightKilograms / (heightMeters * heightMeters)
    }

    /// Body fat at a given weight, holding lean mass — the inverse of
    /// `weightForBodyFat`, used to say what the scale target implies.
    static func bodyFatPercent(
        atWeightKilograms weight: Double,
        leanKilograms lean: Double
    ) -> Double? {
        guard weight > 0, lean > 0, lean < weight else { return nil }
        return (1 - lean / weight) * 100
    }
}

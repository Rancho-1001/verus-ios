import Foundation

/// A single weigh-in.
///
/// Mass is stored in kilograms and only in kilograms. The app is read in
/// pounds and Apple Health hands back whichever unit you ask it for, so the
/// one place a unit can be confused is the boundary — and the way to make that
/// impossible is to have exactly one internal unit and convert at the edges.
/// `pounds` is a view of the same number, never a second source of truth.
struct WeightEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    /// The instant of the weigh-in. Grouping into days and weeks is done by
    /// the caller's `Calendar`, never by truncating this value.
    let date: Date
    let kilograms: Double
    /// Percent, 0–100. Optional because a scale that reports body fat is not
    /// a given, and the concept treats body fat as a secondary goal.
    let bodyFatPercent: Double?
    /// Lean mass in kilograms **as the scale measured it**, not as the app
    /// worked it out. Kept separate from the derived figure in
    /// `BodyComposition` so the screen can say which one it is showing.
    let leanKilograms: Double?
    /// Body mass index, as whatever recorded it calculated it. Stored rather
    /// than derived because BMI needs a height Verus does not ask for, and a
    /// smart scale already knows it.
    let bodyMassIndex: Double?

    init(
        id: UUID = UUID(),
        date: Date,
        kilograms: Double,
        bodyFatPercent: Double? = nil,
        leanKilograms: Double? = nil,
        bodyMassIndex: Double? = nil
    ) {
        self.id = id
        self.date = date
        self.kilograms = kilograms
        self.bodyFatPercent = bodyFatPercent
        self.leanKilograms = leanKilograms
        self.bodyMassIndex = bodyMassIndex
    }

    var pounds: Double { kilograms * Self.poundsPerKilogram }

    /// Fat mass, in kilograms — the part of the scale reading that is fat.
    var fatKilograms: Double? { bodyFatPercent.map { kilograms * $0 / 100 } }

    /// Lean mass as best known: measured if the scale reported it, otherwise
    /// derived from weight and body fat. `isLeanMeasured` says which, because
    /// a measurement and an inference should not be displayed as the same
    /// kind of fact.
    var bestLeanKilograms: Double? {
        leanKilograms
            ?? bodyFatPercent.flatMap {
                BodyComposition.leanKilograms(weightKilograms: kilograms, bodyFatPercent: $0)
            }
    }

    var isLeanMeasured: Bool { leanKilograms != nil }

    /// True when this weigh-in carries anything beyond the weight itself —
    /// what tells a smart-scale reading apart from a number typed in.
    var hasComposition: Bool {
        bodyFatPercent != nil || leanKilograms != nil || bodyMassIndex != nil
    }

    /// A copy with any missing composition field filled in. Never overwrites
    /// a value that is already there: a figure the user typed outranks one
    /// matched out of Apple Health.
    func filling(
        bodyFatPercent fat: Double? = nil,
        leanKilograms lean: Double? = nil,
        bodyMassIndex bmi: Double? = nil
    ) -> WeightEntry {
        WeightEntry(
            id: id,
            date: date,
            kilograms: kilograms,
            bodyFatPercent: bodyFatPercent ?? fat,
            leanKilograms: leanKilograms ?? lean,
            bodyMassIndex: bodyMassIndex ?? bmi
        )
    }

    var mass: Measurement<UnitMass> { .init(value: kilograms, unit: .kilograms) }

    static let poundsPerKilogram = 2.204_622_621_848_776

    static func fromPounds(
        _ pounds: Double,
        id: UUID = UUID(),
        date: Date,
        bodyFatPercent: Double? = nil,
        leanKilograms: Double? = nil,
        bodyMassIndex: Double? = nil
    ) -> WeightEntry {
        WeightEntry(
            id: id,
            date: date,
            kilograms: pounds / poundsPerKilogram,
            bodyFatPercent: bodyFatPercent,
            leanKilograms: leanKilograms,
            bodyMassIndex: bodyMassIndex
        )
    }
}

/// The true weight of a week: the average of every weigh-in inside it.
///
/// `entryCount` travels with the average because an average of one weigh-in
/// and an average of seven are not the same claim, and the UI says so rather
/// than presenting both as settled fact.
struct WeeklyAverage: Identifiable, Hashable, Sendable {
    /// Midnight on the first day of the week, in the calendar that produced it.
    let weekStart: Date
    let kilograms: Double
    let entryCount: Int

    var id: Date { weekStart }
    var pounds: Double { kilograms * WeightEntry.poundsPerKilogram }

    /// Below this, the week is shown but not treated as a reliable data point
    /// for rate or projection. Three is the smallest number that can outvote a
    /// single bad morning.
    static let reliableEntryCount = 3

    var isReliable: Bool { entryCount >= Self.reliableEntryCount }
}

/// A point on the smoothed daily trend line.
struct TrendPoint: Identifiable, Hashable, Sendable {
    let date: Date
    /// The smoothed value — what the app calls the trend.
    let kilograms: Double
    /// The raw weigh-in for that day, when there was one. Kept so the chart
    /// can show the scatter behind the line: the concept asks for daily
    /// fluctuation to be visible, just not to be the headline.
    let rawKilograms: Double?

    var id: Date { date }
    var pounds: Double { kilograms * WeightEntry.poundsPerKilogram }
}

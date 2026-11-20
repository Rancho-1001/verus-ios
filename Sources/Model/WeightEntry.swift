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

    init(id: UUID = UUID(), date: Date, kilograms: Double, bodyFatPercent: Double? = nil) {
        self.id = id
        self.date = date
        self.kilograms = kilograms
        self.bodyFatPercent = bodyFatPercent
    }

    var pounds: Double { kilograms * Self.poundsPerKilogram }

    var mass: Measurement<UnitMass> { .init(value: kilograms, unit: .kilograms) }

    static let poundsPerKilogram = 2.204_622_621_848_776

    static func fromPounds(
        _ pounds: Double,
        id: UUID = UUID(),
        date: Date,
        bodyFatPercent: Double? = nil
    ) -> WeightEntry {
        WeightEntry(
            id: id,
            date: date,
            kilograms: pounds / poundsPerKilogram,
            bodyFatPercent: bodyFatPercent
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

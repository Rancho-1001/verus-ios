import Foundation

/// A workout, as Apple Health recorded it.
///
/// Deliberately not an `HKWorkout`. The views and the rollups should not have
/// to import HealthKit to know how long a run was, and keeping a plain value
/// type here means the whole Activity screen is previewable and testable with
/// no Health permissions at all.
struct Workout: Identifiable, Hashable, Sendable {
    let id: UUID
    let start: Date
    let end: Date
    /// A readable name: "Run", "Strength training", "Walk".
    let kind: String
    /// SF Symbol for the kind.
    let symbol: String
    let activeKilocalories: Double?
    let distanceMeters: Double?

    init(
        id: UUID = UUID(),
        start: Date,
        end: Date,
        kind: String,
        symbol: String,
        activeKilocalories: Double? = nil,
        distanceMeters: Double? = nil
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.kind = kind
        self.symbol = symbol
        self.activeKilocalories = activeKilocalories
        self.distanceMeters = distanceMeters
    }

    var duration: TimeInterval { end.timeIntervalSince(start) }

    var durationText: String {
        let minutes = Int(duration / 60)
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }

    /// Miles, since the concept's user is in Michigan and thinks in pounds.
    var miles: Double? {
        distanceMeters.map { $0 / DailyActivity.metersPerMile }
    }
}

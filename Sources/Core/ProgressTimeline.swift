import Foundation

/// One day on the progress timeline.
///
/// A day earns a place here by having a photograph or a measurement on it.
/// The weight is attached rather than qualifying: a day of weigh-ins with no
/// photo belongs on the Weight screen, not on a timeline whose job is showing
/// what the change looked like.
struct ProgressMoment: Identifiable, Hashable, Sendable {
    let day: Date
    let photos: [ProgressPhoto]
    let measurements: [BodyMeasurement]
    /// The smoothed trend on that day, if the weight record reaches it.
    let trendPounds: Double?
    /// Change in trend since the previous moment on the timeline — the
    /// "cause and effect" the concept asks this screen to show. `nil` on the
    /// earliest moment, and whenever either end has no trend to compare.
    let changeSincePreviousPounds: Double?

    var id: Date { day }

    var hasContent: Bool { !photos.isEmpty || !measurements.isEmpty }
}

/// Builds the progress timeline.
///
/// Pure, so the ordering and the deltas can be tested without writing a
/// single photograph to disk.
enum ProgressTimeline {

    /// Newest first, which is the order the screen scrolls in.
    ///
    /// Deltas are computed against the *previous* moment chronologically, so
    /// a card reading "−4.2 lb since" always means since the photo below it.
    static func build(
        photos: [ProgressPhoto],
        measurements: [BodyMeasurement],
        trend: [TrendPoint],
        calendar: Calendar
    ) -> [ProgressMoment] {
        let photosByDay = Dictionary(grouping: photos) { calendar.startOfDay(for: $0.date) }
        let measurementsByDay = Dictionary(grouping: measurements) { calendar.startOfDay(for: $0.date) }

        var trendByDay: [Date: Double] = [:]
        for point in trend {
            trendByDay[calendar.startOfDay(for: point.date)] = point.pounds
        }

        let days = Set(photosByDay.keys).union(measurementsByDay.keys).sorted()

        // Oldest first while the deltas are computed, then reversed. Doing it
        // the other way round is how a delta ends up with its sign flipped.
        var moments: [ProgressMoment] = []
        var previousTrend: Double?

        for day in days {
            let trendHere = trendByDay[day]
            let change: Double? = {
                guard let trendHere, let previousTrend else { return nil }
                return trendHere - previousTrend
            }()

            moments.append(
                ProgressMoment(
                    day: day,
                    photos: (photosByDay[day] ?? []).sorted { $0.date < $1.date },
                    measurements: (measurementsByDay[day] ?? [])
                        .sorted { $0.site.sortOrder < $1.site.sortOrder },
                    trendPounds: trendHere,
                    changeSincePreviousPounds: change
                )
            )

            // Only advance the baseline when this moment had a trend of its
            // own. Otherwise a photo taken during a gap in weigh-ins would
            // silently reset the comparison and the next card would understate
            // the change.
            if let trendHere { previousTrend = trendHere }
        }

        return moments.reversed()
    }

    /// The latest value for each site, newest first by site order.
    ///
    /// What the top of the screen shows: where the tape reads today, not
    /// every reading ever taken.
    static func latestMeasurements(
        from measurements: [BodyMeasurement]
    ) -> [BodyMeasurement] {
        Dictionary(grouping: measurements, by: \.site)
            .compactMap { _, readings in readings.max { $0.date < $1.date } }
            .sorted { $0.site.sortOrder < $1.site.sortOrder }
    }

    /// Change in one site between its first and latest reading.
    /// `nil` when there is only one reading — a single measurement is a
    /// starting point, not a change.
    static func change(for site: MeasurementSite, in measurements: [BodyMeasurement]) -> Double? {
        let readings = measurements.filter { $0.site == site }.sorted { $0.date < $1.date }
        guard let first = readings.first, let last = readings.last, readings.count > 1 else {
            return nil
        }
        return last.centimetres - first.centimetres
    }
}

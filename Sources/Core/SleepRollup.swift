import Foundation

/// One stretch of being asleep, as something recorded it.
struct SleepSession: Hashable, Sendable {
    let start: Date
    let end: Date

    var duration: TimeInterval { max(end.timeIntervalSince(start), 0) }
}

/// Turning sleep records into "hours slept last night".
///
/// Two things make this harder than summing durations, and both are why it
/// is a pure function with tests rather than a loop inside a view.
///
/// **A night belongs to the morning it ends on.** Sleep from 11pm Monday to
/// 7am Tuesday is Tuesday's figure, because "how did I sleep last night" is a
/// question asked on Tuesday. Attributing it to Monday would put last night's
/// eight hours on a row the user has already stopped looking at.
///
/// **Sources overlap.** A watch, the phone and a sleep-tracking app can all
/// write the same night, and summing them reports twenty-four hours of sleep
/// in a day that had eight. Intervals are merged before anything is added up,
/// so overlapping records count once.
enum SleepRollup {

    static func hoursByNight(
        _ sessions: [SleepSession],
        calendar: Calendar
    ) -> [Date: Double] {
        let merged = merge(sessions)
        var hours: [Date: Double] = [:]
        for session in merged where session.duration > 0 {
            let night = calendar.startOfDay(for: session.end)
            hours[night, default: 0] += session.duration / 3_600
        }
        return hours
    }

    /// Overlapping or touching stretches become one. Sorted by start, so a
    /// single pass is enough.
    static func merge(_ sessions: [SleepSession]) -> [SleepSession] {
        let ordered = sessions
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }
        guard var current = ordered.first else { return [] }

        var merged: [SleepSession] = []
        for session in ordered.dropFirst() {
            if session.start <= current.end {
                // Overlapping, or butted up against each other: one stretch.
                current = SleepSession(start: current.start, end: max(current.end, session.end))
            } else {
                merged.append(current)
                current = session
            }
        }
        merged.append(current)
        return merged
    }
}

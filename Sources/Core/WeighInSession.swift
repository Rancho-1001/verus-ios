import Foundation

/// One step onto the scale, however many records it produced.
///
/// A connected scale does not write one weigh-in per session. It writes a
/// burst: a reading as the weight settles, another when it has, sometimes a
/// third when the impedance measurement finishes. Pulled from Apple Health
/// they arrive as separate samples seconds apart —
///
///     23:29:14   180.4 lb   25.3% fat
///     23:29:45   177.9 lb   24.5% fat
///
/// — and both are genuine records of what the scale said. They are not two
/// weigh-ins.
///
/// Left alone this does real damage in one specific place. `TrendEngine`
/// already takes the last reading of each day, so the trend line is safe;
/// the weekly average is not. It averages every entry in the week, so a
/// burst of three counts three times — and `WeeklyAverage.isReliable` asks
/// for three weigh-ins before it will treat a week as settled, which means
/// **one morning on the scale could make a week look reliable**. That is
/// exactly the kind of false confidence the weekly average exists to
/// prevent.
enum WeighInSession {

    /// Readings closer together than this are the same step onto the scale.
    ///
    /// Ninety seconds is drawn from the data rather than guessed: every
    /// burst observed so far spans nine to forty-five seconds, and the
    /// closest pair that is genuinely two sessions is two minutes apart.
    static let window: TimeInterval = 90

    /// However long a burst runs, it stops being one session after this.
    /// Without the cap, a reading every eighty seconds for an hour would
    /// chain into a single "session", which it plainly is not.
    static let maximumSpan: TimeInterval = 5 * 60

    /// One entry per session: the **last** reading of each burst.
    ///
    /// Last rather than first or averaged. A scale's later reading is its
    /// settled one, and averaging would produce a weight that was never
    /// measured — then leave the body fat, lean mass and BMI belonging to
    /// some other reading sitting beside it. Keeping one real row whole
    /// means every figure on screen was recorded together.
    static func collapse(
        _ entries: [WeightEntry],
        within window: TimeInterval = window
    ) -> [WeightEntry] {
        let ordered = entries.sorted { $0.date < $1.date }
        guard var current = ordered.first else { return [] }

        var kept: [WeightEntry] = []
        var sessionStart = current.date

        for entry in ordered.dropFirst() {
            let isSameSession = entry.date.timeIntervalSince(current.date) <= window
                && entry.date.timeIntervalSince(sessionStart) <= maximumSpan
            if isSameSession {
                current = entry   // a later reading supersedes the one before
            } else {
                kept.append(current)
                current = entry
                sessionStart = entry.date
            }
        }
        kept.append(current)
        return kept
    }

    /// The entries a collapse would drop — what the list view greys out, so
    /// the record still shows everything the scale wrote.
    static func superseded(
        in entries: [WeightEntry],
        within window: TimeInterval = window
    ) -> Set<UUID> {
        let kept = Set(collapse(entries, within: window).map(\.id))
        return Set(entries.map(\.id)).subtracting(kept)
    }
}

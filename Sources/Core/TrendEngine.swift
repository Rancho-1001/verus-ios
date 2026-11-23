import Foundation

/// The maths behind "the trend is the product".
///
/// Everything here is a pure function of the entries it is given. No storage,
/// no clock of its own, no HealthKit — the calendar and the "today" it reasons
/// from are both passed in, which is what makes every case below testable
/// without waiting a week for real data to accumulate.
enum TrendEngine {

    // MARK: - Weekly averages

    /// Groups weigh-ins into weeks and averages each one.
    ///
    /// The concept's method, stated plainly: weigh in daily, and take the
    /// weekly average as the true weight of the week. Weeks with no weigh-ins
    /// are absent rather than zero — a gap in the record is a gap, not a
    /// sudden drop to nothing.
    static func weeklyAverages(
        from entries: [WeightEntry],
        calendar: Calendar
    ) -> [WeeklyAverage] {
        guard !entries.isEmpty else { return [] }

        let grouped = Dictionary(grouping: entries) { entry in
            calendar.dateInterval(of: .weekOfYear, for: entry.date)?.start
                ?? calendar.startOfDay(for: entry.date)
        }

        return grouped
            .map { weekStart, weekEntries in
                WeeklyAverage(
                    weekStart: weekStart,
                    kilograms: weekEntries.reduce(0) { $0 + $1.kilograms } / Double(weekEntries.count),
                    entryCount: weekEntries.count
                )
            }
            .sorted { $0.weekStart < $1.weekStart }
    }

    // MARK: - Daily smoothed trend

    /// The default smoothing factor for the daily trend line.
    ///
    /// An exponentially weighted moving average with α = 0.10 gives roughly a
    /// nineteen-day centre of mass: slow enough that one salty dinner barely
    /// moves it, fast enough to turn within a fortnight when the real trend
    /// turns. This is the number to tune first if the line feels wrong in
    /// daily use — it is the only arbitrary constant in this file.
    static let defaultSmoothingFactor = 0.10

    /// Builds the smoothed daily trend.
    ///
    /// Days without a weigh-in still get a point, carrying the previous
    /// smoothed value forward. That matters: if missing days were skipped, a
    /// fortnight away from the scale would compress into a single step and the
    /// chart would imply a change that never happened.
    static func smoothedTrend(
        from entries: [WeightEntry],
        calendar: Calendar,
        alpha: Double = defaultSmoothingFactor
    ) -> [TrendPoint] {
        guard !entries.isEmpty else { return [] }
        precondition(alpha > 0 && alpha <= 1, "alpha must be in (0, 1]")

        // One weigh-in per day: the last of that day wins, since a later
        // reading on the same day is a correction more often than it is noise.
        var byDay: [Date: WeightEntry] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.date)
            if let existing = byDay[day], existing.date >= entry.date { continue }
            byDay[day] = entry
        }

        let days = byDay.keys.sorted()
        guard let first = days.first, let last = days.last else { return [] }

        var points: [TrendPoint] = []
        var smoothed: Double?
        var lastReadingDay: Date?
        var day = first

        while day <= last {
            let raw = byDay[day]?.kilograms
            if let raw {
                if let previous = smoothed, let lastReadingDay {
                    // **Elapsed days, not readings.** The first version moved
                    // the line by alpha once per weigh-in, which is only a
                    // nineteen-day average if you weigh in daily. Weigh in
                    // once a fortnight and nineteen readings span eight
                    // months — the line then sits stubbornly above a scale
                    // that has been saying something else since the summer,
                    // which is exactly the complaint that found this.
                    //
                    // Compounding alpha over the gap fixes it: a reading the
                    // next day moves the line by alpha as before, one a
                    // fortnight later moves it most of the way, and one after
                    // a month of silence all but replaces a trend that has
                    // no claim to still be true.
                    let gap = calendar.dateComponents([.day], from: lastReadingDay, to: day).day ?? 1
                    let weight = 1 - pow(1 - alpha, Double(max(gap, 1)))
                    smoothed = previous + weight * (raw - previous)
                } else {
                    // The first reading seeds the line rather than being
                    // smoothed towards zero from nothing.
                    smoothed = raw
                }
                lastReadingDay = day
            }
            if let smoothed {
                points.append(TrendPoint(date: day, kilograms: smoothed, rawKilograms: raw))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        return points
    }

    // MARK: - Rate of change

    /// How fast the trend is actually moving, in kilograms per week.
    ///
    /// Negative means losing. Measured by least-squares fit over the smoothed
    /// line rather than by subtracting the first point from the last, because
    /// endpoints are exactly where a single odd morning does the most damage.
    ///
    /// Returns `nil` when the window holds fewer than `minimumDays` points —
    /// the honest answer to "how fast am I losing?" after four days is that we
    /// do not know yet.
    static func rateKilogramsPerWeek(
        trend: [TrendPoint],
        overLastDays windowDays: Int = 28,
        minimumDays: Int = 14
    ) -> Double? {
        let window = Array(trend.suffix(windowDays))
        guard window.count >= minimumDays else { return nil }

        // x in days from the first point in the window, y in kilograms.
        let first = window[0].date
        let xs = window.map { $0.date.timeIntervalSince(first) / 86_400 }
        let ys = window.map(\.kilograms)
        let n = Double(window.count)

        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n

        var numerator = 0.0
        var denominator = 0.0
        for (x, y) in zip(xs, ys) {
            numerator += (x - meanX) * (y - meanY)
            denominator += (x - meanX) * (x - meanX)
        }
        guard denominator > 0 else { return nil }

        return (numerator / denominator) * 7  // per day → per week
    }

    // MARK: - Projection

    /// What the app is willing to say about reaching a goal.
    ///
    /// There is deliberately no case that returns a date from a guess. The
    /// concept's rule is that the app never flatters the user with a faster
    /// date than the data supports, and the way to guarantee that in code is
    /// to make "a date" unrepresentable unless the data earned one.
    enum Projection: Equatable, Sendable {
        /// Already at or past the goal.
        case reached
        /// Fewer than `needed` days of trend: no rate, so no projection.
        case notEnoughData(needed: Int)
        /// The trend is flat enough that any date would be invented.
        case tooSlowToProject
        /// The trend is moving away from the goal. `rateKilogramsPerWeek`
        /// is surfaced so the UI can say how fast, rather than only that.
        case movingAway(rateKilogramsPerWeek: Double)
        /// A real date, with the pace it assumes shown alongside it.
        case onTrack(date: Date, weeks: Double, rateKilogramsPerWeek: Double)
    }

    /// Below this the trend counts as flat. 0.05 kg/week is about 0.1 lb — far
    /// inside the noise of a bathroom scale, and a rate that would put any
    /// goal years away.
    static let flatRateThreshold = 0.05

    /// Projects when the goal is reached, or declines to.
    static func projection(
        trend: [TrendPoint],
        goalKilograms: Double,
        asOf today: Date,
        calendar: Calendar,
        minimumDays: Int = 14
    ) -> Projection {
        guard let current = trend.last?.kilograms else {
            return .notEnoughData(needed: minimumDays)
        }

        let remaining = current - goalKilograms
        // Within 100 g of goal counts as arrived; chasing the last few grams
        // of a smoothed line is not a goal, it is an asymptote.
        if abs(remaining) < 0.1 { return .reached }
        if remaining < 0 { return .reached }

        guard let rate = rateKilogramsPerWeek(trend: trend, minimumDays: minimumDays) else {
            return .notEnoughData(needed: minimumDays)
        }

        if abs(rate) < flatRateThreshold { return .tooSlowToProject }
        // Goal is below current weight, so progress means a negative rate.
        if rate > 0 { return .movingAway(rateKilogramsPerWeek: rate) }

        let weeks = remaining / -rate
        guard weeks.isFinite, weeks > 0 else { return .tooSlowToProject }

        guard let date = calendar.date(
            byAdding: .day,
            value: Int((weeks * 7).rounded()),
            to: calendar.startOfDay(for: today)
        ) else {
            return .tooSlowToProject
        }

        return .onTrack(date: date, weeks: weeks, rateKilogramsPerWeek: rate)
    }
}

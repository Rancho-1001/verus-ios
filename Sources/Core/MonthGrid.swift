import Foundation

/// The shape of a month as a calendar draws it: whole weeks, padded at both
/// ends with the neighbouring months' days so every row holds seven.
///
/// Pure date arithmetic, separated from the view because this is where
/// off-by-one errors live — a month that starts on the first weekday, a
/// February that fits in exactly four rows, a locale where the week starts on
/// Sunday. None of that is visible in a screenshot until it is wrong.
struct MonthGrid: Equatable, Sendable {

    struct Day: Hashable, Identifiable, Sendable {
        /// Midnight.
        let date: Date
        /// False for the padding days borrowed from the months either side.
        let isInMonth: Bool
        var id: Date { date }
    }

    struct Week: Hashable, Identifiable, Sendable {
        /// Midnight of the row's first day. This is the same value
        /// `TrendEngine.weeklyAverages` keys a week by, given the same
        /// calendar — which is what lets the row line up with its weight.
        let start: Date
        /// Always exactly seven.
        let days: [Day]
        var id: Date { start }
    }

    /// Midnight on the first of the month this grid represents.
    let month: Date
    let weeks: [Week]

    /// Builds the grid containing `date`.
    ///
    /// Returns an empty grid only if the calendar cannot resolve the month,
    /// which in practice means a corrupt calendar rather than a date problem.
    static func make(containing date: Date, calendar: Calendar) -> MonthGrid {
        guard let monthInterval = calendar.dateInterval(of: .month, for: date),
              let firstWeek = calendar.dateInterval(of: .weekOfYear, for: monthInterval.start)
        else {
            return MonthGrid(month: calendar.startOfDay(for: date), weeks: [])
        }

        let monthStart = monthInterval.start
        var weeks: [Week] = []
        var cursor = firstWeek.start

        // Rows until the one holding the last day of the month is done.
        // `monthInterval.end` is midnight on the 1st of the *next* month, so
        // the loop stops as soon as a row starts on or after it.
        while cursor < monthInterval.end {
            var days: [Day] = []
            for offset in 0..<7 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: cursor) else { break }
                days.append(
                    Day(
                        date: day,
                        isInMonth: calendar.isDate(day, equalTo: monthStart, toGranularity: .month)
                    )
                )
            }
            guard days.count == 7 else { break }
            weeks.append(Week(start: cursor, days: days))
            guard let next = calendar.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = next
        }

        return MonthGrid(month: monthStart, weeks: weeks)
    }

    /// Weekday initials in the grid's column order, e.g. M T W T F S S.
    ///
    /// Taken from the calendar's own symbols and rotated, rather than derived
    /// from a reference date. The first attempt here built a date from a UTC
    /// timestamp and read it through a local-timezone calendar, which landed a
    /// day early and printed Sunday-first headings over a Monday-first grid —
    /// a bug invisible in any test that did not pin the time zone.
    static func weekdayInitials(calendar: Calendar, locale: Locale = .current) -> [String] {
        var c = calendar
        c.locale = locale
        // `veryShortWeekdaySymbols` is always Sunday-first, whatever
        // `firstWeekday` says, so the rotation has to be applied by hand.
        let symbols = c.veryShortWeekdaySymbols
        guard symbols.count == 7 else { return symbols }
        let shift = max(0, min(6, calendar.firstWeekday - 1))
        return Array(symbols[shift...] + symbols[..<shift])
    }
}

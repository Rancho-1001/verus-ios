import Foundation
import Testing

@testable import Verus

private func calendar(firstWeekday: Int = 2) -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    c.firstWeekday = firstWeekday
    return c
}

private func date(_ year: Int, _ month: Int, _ day: Int, _ cal: Calendar) -> Date {
    DateComponents(calendar: cal, timeZone: cal.timeZone,
                   year: year, month: month, day: day, hour: 12).date!
}

@Suite("Month grid")
struct MonthGridTests {

    @Test("every row holds exactly seven days")
    func rowsAreWhole() {
        let cal = calendar()
        // A year of months, so a February and a 31-day month starting on a
        // Sunday both get covered without naming them.
        for month in 1...12 {
            let grid = MonthGrid.make(containing: date(2026, month, 15, cal), calendar: cal)
            for week in grid.weeks {
                #expect(week.days.count == 7, "month \(month) has a short row")
            }
        }
    }

    @Test("a month covers four to six rows and no more")
    func plausibleRowCount() {
        let cal = calendar()
        for month in 1...12 {
            let grid = MonthGrid.make(containing: date(2026, month, 15, cal), calendar: cal)
            #expect((4...6).contains(grid.weeks.count), "month \(month): \(grid.weeks.count) rows")
        }
    }

    @Test("every day of the month appears exactly once")
    func noDayLostOrDoubled() {
        let cal = calendar()
        let grid = MonthGrid.make(containing: date(2026, 11, 20, cal), calendar: cal)
        let inMonth = grid.weeks.flatMap(\.days).filter(\.isInMonth)

        #expect(inMonth.count == 30)  // November
        #expect(Set(inMonth.map(\.date)).count == 30)

        let days = inMonth.map { cal.component(.day, from: $0.date) }.sorted()
        #expect(days == Array(1...30))
    }

    @Test("padding days are marked as outside the month")
    func paddingIsFlagged() throws {
        let cal = calendar()
        // 1 Nov 2026 is a Sunday, so a Monday-first grid pads the whole first
        // row with October — the widest padding case there is.
        let grid = MonthGrid.make(containing: date(2026, 11, 20, cal), calendar: cal)
        let firstRow = try #require(grid.weeks.first)

        let leadingAreOutside = firstRow.days.prefix(6).allSatisfy { !$0.isInMonth }
        #expect(leadingAreOutside)
        #expect(firstRow.days[6].isInMonth)
        #expect(cal.component(.day, from: firstRow.days[6].date) == 1)
    }

    @Test("a month starting on the first weekday gets no leading padding")
    func noPaddingWhenAligned() throws {
        let cal = calendar()  // Monday-first
        // 1 June 2026 is a Monday.
        let grid = MonthGrid.make(containing: date(2026, 6, 10, cal), calendar: cal)
        let firstRow = try #require(grid.weeks.first)
        let wholeRowInMonth = firstRow.days.allSatisfy(\.isInMonth)
        #expect(wholeRowInMonth)
        #expect(cal.component(.day, from: firstRow.days[0].date) == 1)
    }

    @Test("the week start matches the one TrendEngine groups weights by")
    func rowsAlignWithWeeklyAverages() throws {
        // This is the whole premise of the home screen: a calendar row and a
        // weekly weight must be the same week. If these two ever disagree the
        // screen would quietly show one week's steps beside another's weight.
        let cal = calendar()
        let grid = MonthGrid.make(containing: date(2026, 11, 20, cal), calendar: cal)

        let entries = grid.weeks.flatMap(\.days).map {
            WeightEntry.fromPounds(180, date: $0.date)
        }
        let averages = TrendEngine.weeklyAverages(from: entries, calendar: cal)
        let averageStarts = Set(averages.map(\.weekStart))

        for week in grid.weeks {
            #expect(averageStarts.contains(week.start), "row \(week.start) has no matching week")
        }
    }

    @Test("a Sunday-first calendar shifts the columns, and still holds every day")
    func respectsFirstWeekday() throws {
        let sunday = calendar(firstWeekday: 1)
        let grid = MonthGrid.make(containing: date(2026, 11, 20, sunday), calendar: sunday)
        let firstRow = try #require(grid.weeks.first)

        // 1 Nov 2026 is a Sunday, so a Sunday-first grid needs no padding —
        // the exact opposite of the Monday-first case above.
        #expect(firstRow.days[0].isInMonth)
        #expect(sunday.component(.day, from: firstRow.days[0].date) == 1)
        #expect(grid.weeks.flatMap(\.days).filter(\.isInMonth).count == 30)
    }

    @Test("there are seven weekday initials and they start on the calendar's first day")
    func weekdayHeadings() {
        let us = Locale(identifier: "en_US")
        let monday = MonthGrid.weekdayInitials(calendar: calendar(firstWeekday: 2), locale: us)
        let sunday = MonthGrid.weekdayInitials(calendar: calendar(firstWeekday: 1), locale: us)

        #expect(monday.count == 7)
        #expect(sunday.count == 7)
        #expect(monday == ["M", "T", "W", "T", "F", "S", "S"])
        #expect(sunday == ["S", "M", "T", "W", "T", "F", "S"])
    }

    @Test("the headings do not shift with the time zone")
    func weekdayHeadingsIgnoreTimeZone() {
        // The first version of this derived the headings from a reference
        // date built in UTC and read through a local calendar. West of
        // Greenwich that landed a day early and printed Sunday-first headings
        // over a Monday-first grid. Every zone must give the same answer.
        let us = Locale(identifier: "en_US")
        for zone in ["UTC", "America/Detroit", "Pacific/Kiritimati", "Pacific/Pago_Pago"] {
            var c = Calendar(identifier: .gregorian)
            c.timeZone = TimeZone(identifier: zone)!
            c.firstWeekday = 2
            #expect(
                MonthGrid.weekdayInitials(calendar: c, locale: us) == ["M", "T", "W", "T", "F", "S", "S"],
                "\(zone) shifted the headings"
            )
        }
    }

    @Test("the headings line up with where the grid actually puts the days")
    func headingsMatchColumns() throws {
        // The bug that prompted this test was a header and a grid that
        // disagreed: both were internally consistent, so only comparing them
        // to each other catches it.
        let us = Locale(identifier: "en_US")
        for firstWeekday in 1...7 {
            var c = Calendar(identifier: .gregorian)
            c.timeZone = TimeZone(identifier: "America/Detroit")!
            c.firstWeekday = firstWeekday
            c.locale = us

            let grid = MonthGrid.make(containing: date(2026, 11, 20, c), calendar: c)
            let headings = MonthGrid.weekdayInitials(calendar: c, locale: us)
            let firstRow = try #require(grid.weeks.first)

            let symbols = c.veryShortWeekdaySymbols
            for (column, day) in firstRow.days.enumerated() {
                let weekday = c.component(.weekday, from: day.date)  // 1 = Sunday
                #expect(
                    headings[column] == symbols[weekday - 1],
                    "firstWeekday \(firstWeekday), column \(column): header says \(headings[column]) but the date is a \(symbols[weekday - 1])"
                )
            }
        }
    }
}

import Foundation
import Observation

/// Daily activity for the month on screen.
///
/// Holds a month at a time rather than everything, because the Home screen
/// only ever draws one and a HealthKit query for five years of steps is not
/// something to run on a view appearing.
@MainActor
@Observable
final class ActivityStore {

    private(set) var byDay: [Date: DailyActivity] = [:]
    private(set) var isLoading = false
    /// Set when a load fails. The screen shows the calendar regardless — a
    /// month with no step data is still a usable month view.
    private(set) var loadError: String?

    /// The concept's stated target: roughly 15,000 steps a day.
    var dailyStepGoal = 15_000

    var calendar: Calendar
    private let source: ActivitySource

    init(source: ActivitySource = SampleActivitySource(), calendar: Calendar = .current) {
        var c = calendar
        c.firstWeekday = 2  // Monday, matching WeightStore and TrendEngine
        self.calendar = c
        self.source = source
    }

    func activity(on day: Date) -> DailyActivity? {
        byDay[calendar.startOfDay(for: day)]
    }

    var today: DailyActivity? { activity(on: .now) }

    /// Loads every day the grid can show, padding days included — otherwise
    /// the first and last rows would be blank for no reason the user can see.
    func load(grid: MonthGrid) async {
        guard let first = grid.weeks.first?.days.first?.date,
              let last = grid.weeks.last?.days.last?.date
        else { return }

        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            byDay = try await source.dailyActivity(from: first, to: last)
        } catch {
            loadError = error.localizedDescription
        }
    }

    // MARK: - Month summary

    /// Average daily steps across the days in `grid` that have a reading.
    ///
    /// Days with no reading are left out rather than counted as zero: a phone
    /// left at home is missing data, and averaging it in as a zero would
    /// understate the month and discourage the user for no reason.
    func averageSteps(in grid: MonthGrid) -> Int? {
        let values = grid.weeks
            .flatMap(\.days)
            .filter(\.isInMonth)
            .compactMap { activity(on: $0.date)?.steps }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / values.count
    }

    /// Days in the month that met the goal.
    func daysAtGoal(in grid: MonthGrid) -> Int {
        grid.weeks
            .flatMap(\.days)
            .filter(\.isInMonth)
            .compactMap { activity(on: $0.date)?.steps }
            .count { $0 >= dailyStepGoal }
    }

    func totalSteps(forWeekStarting start: Date) -> Int? {
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let values = days.compactMap { activity(on: $0)?.steps }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }
}

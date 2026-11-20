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

    /// What the numbers on screen actually are.
    ///
    /// This exists because HealthKit will not say whether a read was denied,
    /// so the app has to reason from what it has: did we ask, and did anything
    /// arrive. Every state other than `.live` is shown to the user — sample
    /// data is never presented as if it were theirs.
    enum SourceState: Equatable, Sendable {
        /// Real data from Apple Health.
        case live
        /// The permission sheet has not been shown yet.
        case needsPermission
        /// We asked, and Health returned nothing for the whole month. Either
        /// the read was declined or there genuinely is no data; HealthKit does
        /// not distinguish, so neither does this.
        case noDataFromHealth
        /// No HealthKit on this device at all.
        case unavailable
        /// A query failed outright.
        case failed(String)

        var isShowingSampleData: Bool { self != .live }
    }

    /// Accumulates rather than replaces. The Home screen loads a month at a
    /// time and the Activity screen wants a quarter; merging means navigating
    /// back through months builds up the history both of them read from,
    /// instead of each view evicting the other's data.
    private(set) var byDay: [Date: DailyActivity] = [:]
    private(set) var workouts: [Workout] = []
    private(set) var state: SourceState = .needsPermission
    private(set) var isLoading = false

    /// Steps a day to aim at. 15,000 is the concept's stated target and the
    /// starting value; it is editable on the Goals sheet and persists there.
    var dailyStepGoal = 15_000 {
        didSet { UserDefaults.standard.set(dailyStepGoal, forKey: Self.stepGoalKey) }
    }

    private static let stepGoalKey = "goal.dailySteps"

    var calendar: Calendar

    private let health: HealthKitService?
    private let sample: ActivitySource

    init(
        health: HealthKitService? = HealthKitService.isAvailable ? HealthKitService() : nil,
        sample: ActivitySource = SampleActivitySource(),
        calendar: Calendar = .current
    ) {
        var c = calendar
        c.firstWeekday = 2  // Monday, matching WeightStore and TrendEngine
        self.calendar = c
        self.health = health
        self.sample = sample
        if let saved = UserDefaults.standard.object(forKey: Self.stepGoalKey) as? Int, saved > 0 {
            dailyStepGoal = saved
        }
        if health == nil { state = .unavailable }
    }

    func activity(on day: Date) -> DailyActivity? {
        byDay[calendar.startOfDay(for: day)]
    }

    var today: DailyActivity? { activity(on: .now) }

    // MARK: - Permission

    var canRequestPermission: Bool {
        health != nil && state != .live
    }

    /// Shows the Health permission sheet, then reloads.
    ///
    /// Returning from this says the sheet was answered, not that anything was
    /// granted — the reload is what finds out.
    func requestPermission(for grid: MonthGrid) async {
        guard let health else { return }
        do {
            try await health.requestAuthorization()
        } catch {
            state = .failed(error.localizedDescription)
            return
        }
        await load(grid: grid)
    }

    // MARK: - Loading

    /// Loads every day the grid can show, padding days included — otherwise
    /// the first and last rows would be blank for no reason the user can see.
    func load(grid: MonthGrid) async {
        guard let first = grid.weeks.first?.days.first?.date,
              let last = grid.weeks.last?.days.last?.date
        else { return }
        await load(from: first, to: last)
    }

    /// The trailing window the Activity screen reads, so week-over-week has
    /// something to compare against on first launch.
    func loadRecent(weeks: Int = 12) async {
        let last = Date.now
        guard let first = calendar.date(byAdding: .day, value: -(weeks * 7), to: last) else { return }
        await load(from: first, to: last)
    }

    private func load(from first: Date, to last: Date) async {
        isLoading = true
        defer { isLoading = false }

        guard let health else {
            await loadSample(from: first, to: last, state: .unavailable)
            return
        }

        guard health.hasRequestedAuthorization else {
            await loadSample(from: first, to: last, state: .needsPermission)
            return
        }

        do {
            let live = try await health.dailyActivity(from: first, to: last)
            if live.isEmpty {
                // Asked, and nothing came back. Could be a declined read,
                // could be a genuinely empty month. HealthKit will not say.
                await loadSample(from: first, to: last, state: .noDataFromHealth)
            } else {
                merge(live, workouts: try? await health.workouts(from: first, to: last))
                state = .live
            }
        } catch {
            await loadSample(from: first, to: last, state: .failed(error.localizedDescription))
        }
    }

    /// Fills the screen with sample data and records *why*, so the view can
    /// say so. A calendar with nothing in it teaches the user nothing about
    /// what the app does; a calendar labelled "sample" teaches them both.
    private func loadSample(from first: Date, to last: Date, state newState: SourceState) async {
        let days = (try? await sample.dailyActivity(from: first, to: last)) ?? [:]
        let sessions = try? await sample.workouts(from: first, to: last)
        // Live and sample data must never mix: a calendar half real and half
        // invented would be labelled one or the other and wrong either way.
        if state == .live { byDay = [:]; workouts = [] }
        merge(days, workouts: sessions)
        state = newState
    }

    private func merge(_ days: [Date: DailyActivity], workouts sessions: [Workout]?) {
        byDay.merge(days) { _, new in new }
        guard let sessions else { return }
        var seen = Set(workouts.map(\.start))
        for session in sessions where !seen.contains(session.start) {
            seen.insert(session.start)
            workouts.append(session)
        }
        workouts.sort { $0.start < $1.start }
    }

    // MARK: - Rollups

    var weeks: [ActivityWeek] {
        ActivityRollup.weeks(from: byDay, goal: dailyStepGoal, calendar: calendar)
    }

    var currentStreak: Int {
        ActivityRollup.currentStreak(from: byDay, goal: dailyStepGoal, asOf: .now, calendar: calendar)
    }

    var longestStreak: Int {
        ActivityRollup.longestStreak(from: byDay, goal: dailyStepGoal, calendar: calendar)
    }

    var weekOverWeekChange: Double? {
        ActivityRollup.weekOverWeekChange(weeks)
    }

    func workouts(onOrAfter date: Date) -> [Workout] {
        workouts.filter { $0.start >= date }.sorted { $0.start > $1.start }
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

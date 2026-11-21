import Foundation

/// Intake against expenditure for one day.
///
/// This is the comparison the concept says the whole product exists to make:
/// *"intake and expenditure finally in the same place — the comparison the
/// current four-app stack cannot make at all, because food is missing from
/// it."*
///
/// Two honesty problems come with it, and both are modelled rather than
/// papered over:
///
/// 1. **Burn may be missing.** No Health permission, no phone in the pocket —
///    and then there is no budget to show, only an intake. Inventing a
///    plausible expenditure here would be inventing the deficit too.
/// 2. **Today is not over.** By mid-morning you have burned a few hundred
///    calories and eaten a few hundred more, and the difference between them
///    means almost nothing. A finished day's balance is a fact; a running
///    day's balance is a progress bar.
enum EnergyBudget {

    /// The state of one day's energy balance.
    enum Balance: Equatable, Sendable {
        /// Nothing logged and nothing burned — an untouched day.
        case noData
        /// Food logged, but no expenditure to compare it against.
        case intakeOnly(kilocalories: Double)
        /// Expenditure known, but nothing logged to compare it against.
        ///
        /// Emphatically *not* a deficit the size of the day's burn. A day
        /// with no food logged is an unlogged day, and calling it a 2,000
        /// calorie deficit would be the exact flattery this app exists to
        /// avoid — it would also poison every average built on top of it.
        case burnOnly(kilocalories: Double)
        /// Both known. `net` is intake minus burn: negative is a deficit.
        case known(intake: Double, burn: Double, net: Double)

        var intake: Double {
            switch self {
            case .noData, .burnOnly: 0
            case .intakeOnly(let kilocalories): kilocalories
            case .known(let intake, _, _): intake
            }
        }
    }

    /// Everything the Food screen needs for a single day.
    struct Day: Equatable, Sendable {
        let date: Date
        let balance: Balance
        let proteinGrams: Double
        let carbGrams: Double
        let fatGrams: Double
        /// True while the day is still running, so the UI can present a
        /// running total rather than a verdict.
        let isInProgress: Bool
        /// How many logged items carried macro figures. A protein total over
        /// three of seven items is not the day's protein, and the screen says
        /// so rather than implying completeness.
        let itemsWithMacros: Int
        let itemCount: Int
    }

    /// Builds the day from logged food and whatever Health reported.
    ///
    /// `activity` is optional because a day with no reading is a real state —
    /// see `DailyActivity`, where absence means "no reading", not "zero".
    static func day(
        _ date: Date,
        entries: [FoodEntry],
        activity: DailyActivity?,
        now: Date = .now,
        calendar: Calendar
    ) -> Day {
        let startOfDay = calendar.startOfDay(for: date)
        let todays = entries.filter { calendar.isDate($0.date, inSameDayAs: startOfDay) }

        let intake = todays.reduce(0) { $0 + $1.kilocalories }
        let burn = activity?.totalKilocalories

        let balance: Balance = {
            let hasBurn = (burn ?? 0) > 0
            switch (todays.isEmpty, hasBurn) {
            case (true, false):
                return .noData
            case (true, true):
                return .burnOnly(kilocalories: burn ?? 0)
            case (false, false):
                return .intakeOnly(kilocalories: intake)
            case (false, true):
                return .known(intake: intake, burn: burn ?? 0, net: intake - (burn ?? 0))
            }
        }()

        let withMacros = todays.count { $0.proteinGrams != nil || $0.carbGrams != nil || $0.fatGrams != nil }

        return Day(
            date: startOfDay,
            balance: balance,
            proteinGrams: todays.compactMap(\.proteinGrams).reduce(0, +),
            carbGrams: todays.compactMap(\.carbGrams).reduce(0, +),
            fatGrams: todays.compactMap(\.fatGrams).reduce(0, +),
            isInProgress: calendar.isDate(startOfDay, inSameDayAs: now),
            itemsWithMacros: withMacros,
            itemCount: todays.count
        )
    }

    /// Groups a day's food by meal, in meal order, skipping meals with
    /// nothing in them.
    static func byMeal(_ entries: [FoodEntry]) -> [(meal: Meal, entries: [FoodEntry])] {
        Dictionary(grouping: entries, by: \.meal)
            .sorted { $0.key.sortOrder < $1.key.sortOrder }
            .map { (meal: $0.key, entries: $0.value.sorted { $0.date < $1.date }) }
    }

    /// Average daily net over the finished days in a range.
    ///
    /// Today is excluded on purpose: a part-day would drag the average toward
    /// a deficit that has not happened yet. Days without both numbers are
    /// excluded too, since a net cannot be computed from one of them.
    ///
    /// Returns `nil` rather than zero when nothing qualifies — no data is not
    /// the same as perfect balance.
    static func averageNet(
        from days: [Day]
    ) -> Double? {
        let nets = days
            .filter { !$0.isInProgress }
            .compactMap { day -> Double? in
                guard case .known(_, _, let net) = day.balance else { return nil }
                return net
            }
        guard !nets.isEmpty else { return nil }
        return nets.reduce(0, +) / Double(nets.count)
    }

    /// Roughly how much weight a sustained daily net implies, in pounds a week.
    ///
    /// Uses the conventional 3,500 kcal per pound of fat. That figure is a
    /// simplification — real bodies adapt, and the number overstates loss over
    /// long periods — so the UI presents it as an expectation to compare
    /// against the measured trend, never as a replacement for it. The measured
    /// trend is what the app believes.
    static let kilocaloriesPerPound = 3_500.0

    static func impliedPoundsPerWeek(fromDailyNet net: Double) -> Double {
        net * 7 / kilocaloriesPerPound
    }
}

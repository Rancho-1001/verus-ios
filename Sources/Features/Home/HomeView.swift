import SwiftUI

/// Home: how is today going, and how is the month going?
///
/// The concept gives this screen three seconds to answer both. So today's
/// numbers sit at the top with no tap required, and the month calendar is
/// immediately under them — nothing else competes for the first screenful.
struct HomeView: View {
    @Bindable var weight: WeightStore
    @Bindable var activity: ActivityStore
    @Bindable var food: FoodStore

    @State private var monthAnchor: Date = .now
    @State private var selectedDay: Date?
    @State private var expandedMetric: TodayMetric?
    @State private var isShowingSettings = false
    @State private var shareItems: [Any]?

    private var calendar: Calendar { activity.calendar }

    private var grid: MonthGrid {
        MonthGrid.make(containing: monthAnchor, calendar: calendar)
    }

    private var weeklyAverages: [Date: WeeklyAverage] {
        Dictionary(uniqueKeysWithValues: weight.weeklyAverages.map { ($0.weekStart, $0) })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    sourceBanner
                    today
                    calendarCard
                    monthSummary
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            // The title is drawn in the content rather than by the
            // navigation bar, because a large navigation title occupies its
            // own row *below* the bar — so a toolbar button sits above it
            // and to the right of nothing, which is what "not aligned"
            // looked like. Drawn here, the name and the buttons share a
            // line because they are in the same `HStack`.
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isShowingSettings) {
                SettingsSheet(weight: weight, activity: activity)
            }
            .sheet(isPresented: .init(
                get: { shareItems != nil },
                set: { if !$0 { shareItems = nil } }
            )) {
                if let shareItems {
                    ShareSheet(items: shareItems)
                }
            }
            .task(id: grid.month) { await activity.load(grid: grid) }
            // The weigh-ins a smart scale wrote to Apple Health are pulled in
            // here, on the first screen, rather than waiting for the Weight
            // tab to be opened: the trend on this screen and the week column
            // in the calendar are both built from them.
            .task { await weight.syncFromHealth() }
            .sheet(item: $selectedDay) { day in
                DayDetailSheet(day: day, activity: activity, weight: weight, food: food)
            }
            .sheet(item: $expandedMetric) { metric in
                TodayMetricSheet(metric: metric, activity: activity, weight: weight, grid: grid)
            }
        }
    }

    // MARK: - Title

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Verus")
                .font(.system(size: 34, weight: .bold))
            Spacer()
            HStack(spacing: 18) {
                headerButton("square.and.arrow.up", label: "Share this month", action: share)
                headerButton("gearshape", label: "Settings") { isShowingSettings = true }
            }
        }
        .padding(.top, 4)
    }

    /// Thumb-sized, like the month arrows. The glyph is around 20 points;
    /// the tappable area is 44.
    private func headerButton(
        _ symbol: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .medium))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .accessibilityLabel(label)
    }

    // MARK: - Where the numbers came from

    /// Shown whenever the figures on screen are not the user's own.
    ///
    /// The rule this enforces: sample data is never silent. An empty calendar
    /// would teach nothing about what the app does, so the screen fills in —
    /// and then says plainly that it has, every time, until real data arrives.
    @ViewBuilder
    private var sourceBanner: some View {
        switch activity.state {
        case .live:
            EmptyView()

        case .needsPermission:
            banner(
                icon: "heart.text.square",
                title: "Showing sample data",
                detail: "Connect Apple Health and this becomes your own steps and energy.",
                action: ("Connect", { Task { await activity.requestPermission(for: grid) } })
            )

        case .noDataFromHealth:
            banner(
                icon: "exclamationmark.triangle",
                title: "Apple Health returned nothing",
                // Deliberately not "you denied access" — HealthKit does not
                // report denied reads, so claiming to know would be a guess.
                detail: "Either there is no data for this month, or Verus was not granted access to read it. Settings › Health › Data Access shows which.",
                action: ("Open Settings", openSettings)
            )

        case .unavailable:
            banner(
                icon: "heart.slash",
                title: "Apple Health is unavailable here",
                detail: "Showing sample data so the screen still means something.",
                action: nil
            )

        case .failed(let message):
            banner(
                icon: "exclamationmark.triangle",
                title: "Could not read Apple Health",
                detail: message,
                action: ("Try again", { Task { await activity.load(grid: grid) } })
            )
        }
    }

    private func banner(
        icon: String,
        title: String,
        detail: String,
        action: (label: String, run: () -> Void)?
    ) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.orange)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let action {
                    Button(action.label, action: action.run)
                        .font(.caption.weight(.semibold))
                        .padding(.top, 3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.orange.opacity(0.09), in: .rect(cornerRadius: 14))
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Today

    private var today: some View {
        HStack(spacing: 10) {
            ForEach(TodayMetric.allCases) { metric in
                Button { expandedMetric = metric } label: {
                    tile(metric)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens today's \(metric.title.lowercased()) in full")
            }
        }
    }

    /// One of today's three numbers.
    ///
    /// Each metric keeps its own colour — steps red, active green, weight
    /// blue — so the three cards are told apart at a glance rather than
    /// read. That is a different job from the calendar's red, amber and
    /// green, which are a verdict on a day; these are an identity. The rule
    /// under each number is what says how far along today is.
    private func tile(_ metric: TodayMetric) -> some View {
        let colour = metric.color
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Label(metric.title, systemImage: metric.symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            Text(value(for: metric))
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(colour)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption(for: metric))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            progressBar(colour: colour, share: share(for: metric))
                .padding(.top, 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 13)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.card)
                .overlay {
                    RoundedRectangle(cornerRadius: 14).fill(colour.opacity(0.09))
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(metric.title), \(value(for: metric)), \(caption(for: metric))"
        )
    }

    /// A 3-point rule under each tile, in the metric's own colour. `nil`
    /// leaves the track invisible but still laid out, so the three cards
    /// keep the same height — weight has no "share of today's goal" to draw,
    /// and inventing one would be the kind of flattery this app is built to
    /// avoid.
    @ViewBuilder
    private func progressBar(colour: Color, share: Double?) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(share == nil ? .clear : Color.primary.opacity(0.07))
                if let share {
                    Capsule()
                        .fill(colour.opacity(0.8))
                        .frame(width: max(proxy.size.width * share, share > 0 ? 3 : 0))
                }
            }
        }
        .frame(height: 3)
    }

    // MARK: - What each tile says

    private func value(for metric: TodayMetric) -> String {
        switch metric {
        case .steps:
            activity.today.map { Self.grouped($0.steps) } ?? "—"
        case .active:
            activity.today.map { "\(Int($0.activeKilocalories))" } ?? "—"
        case .weight:
            weight.trendPounds.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—"
        }
    }

    private func caption(for metric: TodayMetric) -> String {
        switch metric {
        case .steps: stepsCaption
        case .active: activeCaption
        case .weight: trendCaption
        }
    }

    private func share(for metric: TodayMetric) -> Double? {
        switch metric {
        case .steps:
            GoalStanding.share(value: activity.today?.steps, goal: activity.dailyStepGoal)
        case .active:
            GoalStanding.share(
                value: activity.today?.activeKilocalories,
                goal: Double(activity.dailyActiveEnergyGoal)
            )
        case .weight:
            nil
        }
    }

    /// The headline weight is the trend; this line carries the raw reading, so
    /// both are visible and only one is the claim.
    /// The headline weight is the trend, which is deliberately not the last
    /// reading — so the last reading is named here, with its date. Without
    /// it the tile looks like a scale that disagrees with the scale.
    private var trendCaption: String {
        guard let latest = weight.latestEntry else { return "no weigh-ins yet" }
        let pounds = latest.pounds.formatted(.number.precision(.fractionLength(1)))
        guard calendar.isDateInToday(latest.date) else {
            return "trend · \(pounds) on \(latest.date.formatted(.dateTime.day().month()))"
        }
        return "trend · \(pounds) today"
    }

    /// Distance first when the phone reported one, then the gap to the goal.
    ///
    /// The miles are the phone's own measurement, not steps multiplied by an
    /// assumed stride — which is why a day can have steps and no distance,
    /// and why this line shrinks to the goal alone when it does.
    private var stepsCaption: String {
        guard let today = activity.today else { return "no data yet" }
        let remaining = activity.dailyStepGoal - today.steps
        // Past the goal the line says nothing about the goal. The colour and
        // the full rule underneath have already said it, and a caption that
        // repeats them is a third voice agreeing with the first two.
        let goalPart = remaining > 0 ? "\(Self.grouped(remaining)) to goal" : ""
        guard let miles = today.miles else { return goalPart }
        return goalPart.isEmpty
            ? "\(miles.formatted(.number.precision(.fractionLength(1)))) mi"
            : "\(miles.formatted(.number.precision(.fractionLength(1)))) mi · \(goalPart)"
    }

    private var activeCaption: String {
        guard let today = activity.today else { return "no data yet" }
        let remaining = Double(activity.dailyActiveEnergyGoal) - today.activeKilocalories
        return remaining > 0 ? "\(Int(remaining.rounded())) kcal to goal" : ""
    }

    // MARK: - Calendar

    private var calendarCard: some View {
        VStack(spacing: 14) {
            HStack {
                monthButton("chevron.left", label: "Previous month") { step(by: -1) }
                Spacer()
                // The title is the way in to the year. A sixth tab would push
                // the tab bar into iOS's "More" menu, and the year belongs
                // next to the month rather than beside Food and Weight.
                NavigationLink {
                    YearView(activity: activity, weight: weight) { month in
                        monthAnchor = month
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(grid.month, format: .dateTime.month(.wide).year())
                            .font(.headline)
                            .contentTransition(.numericText())
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the year")
                Spacer()
                monthButton("chevron.right", label: "Next month", disabled: isShowingCurrentMonth) {
                    step(by: 1)
                }
            }

            MonthCalendarView(
                grid: grid,
                activity: activity,
                weeklyAverages: weeklyAverages,
                onSelect: { selectedDay = $0 }
            )
        }
        .padding(16)
        .background(Color.card, in: .rect(cornerRadius: 18))
    }

    /// A month arrow with a thumb-sized hit area.
    ///
    /// The first version was a bare `Image` in a `.plain` button, which makes
    /// the tappable region the glyph itself — around 12 points square against
    /// Apple's 44-point minimum. A mouse in the simulator hits that every
    /// time and a thumb essentially never does, which is why it survived
    /// until the app ran on a real phone.
    private func monthButton(
        _ symbol: String,
        label: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(width: 44, height: 44)
                // Without this the frame is decoration and only the glyph
                // takes the tap.
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? Color.secondary : Color.accentColor)
        .disabled(disabled)
        .accessibilityLabel(label)
    }

    private var isShowingCurrentMonth: Bool {
        calendar.isDate(grid.month, equalTo: .now, toGranularity: .month)
    }

    private func step(by months: Int) {
        guard let next = calendar.date(byAdding: .month, value: months, to: monthAnchor) else { return }
        withAnimation(.snappy(duration: 0.22)) { monthAnchor = next }
    }

    // MARK: - Month summary

    private var monthSummary: some View {
        HStack(spacing: 8) {
            summaryTile(
                value: activity.averageSteps(in: grid).map(Self.grouped) ?? "—",
                label: "avg steps/day"
            )
            // Shown only when Health reported a distance for the month. A
            // zero here would read as "you walked nowhere" rather than "the
            // phone recorded no distance".
            if let miles = activity.totalMiles(in: grid) {
                summaryTile(
                    value: miles.formatted(.number.precision(.fractionLength(0))),
                    label: "miles"
                )
            }
            summaryTile(
                value: "\(activity.daysAtGoal(in: grid))",
                label: "days at goal"
            )
            summaryTile(
                value: monthWeightDelta,
                label: "weight this month"
            )
        }
    }

    /// Change across the month, measured trend-to-trend rather than
    /// weigh-in to weigh-in, so a heavy first morning cannot invent a loss.
    private var monthWeightDelta: String {
        let days = grid.weeks.flatMap(\.days).filter(\.isInMonth).map(\.date)
        guard let first = days.first, let last = days.last else { return "—" }
        let points = weight.trend.filter { $0.date >= first && $0.date <= last }
        guard let start = points.first, let end = points.last, points.count > 1 else { return "—" }
        let delta = end.pounds - start.pounds
        return "\(delta > 0 ? "+" : "")\(delta.formatted(.number.precision(.fractionLength(1))))"
    }

    private func summaryTile(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.card, in: .rect(cornerRadius: 14))
    }

    // MARK: - Sharing

    /// Renders the month to an image and hands it to the system share
    /// sheet.
    ///
    /// Rendered rather than screenshotted, so what leaves the phone is the
    /// month and its three figures — not the permission banner, the tab bar
    /// and the weekly weight column that happen to be on screen. Nothing is
    /// sent anywhere: the share sheet opens and the user chooses, or does
    /// not.
    @MainActor
    private func share() {
        // Pinned to light. `ImageRenderer` would otherwise inherit the
        // app's theme, and a near-black card dropped into a chat is harder
        // to read than a white one — the share should look the same
        // whoever sends it and whatever they have the app set to.
        let card = MonthShareCard(grid: grid, activity: activity)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        let caption = "\(grid.month.formatted(.dateTime.month(.wide).year())) in Verus"
        if let image = renderer.uiImage {
            shareItems = [MonthShareItem(image: image, caption: caption)]
        } else {
            // A failed render is not a reason to do nothing — the figures
            // are the point and they fit in a line of text.
            shareItems = [shareText]
        }
    }

    private var shareText: String {
        var parts = ["\(grid.month.formatted(.dateTime.month(.wide).year())) in Verus"]
        if let average = activity.averageSteps(in: grid) {
            parts.append("\(Self.grouped(average)) steps a day")
        }
        if let miles = activity.totalMiles(in: grid) {
            parts.append("\(miles.formatted(.number.precision(.fractionLength(0)))) miles")
        }
        parts.append("\(activity.daysAtGoal(in: grid)) days at goal")
        return parts.joined(separator: " · ")
    }

    static func grouped(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }
}

/// `sheet(item:)` needs an Identifiable, and a bare `Date` is not one.
extension Date: @retroactive Identifiable {
    public var id: TimeInterval { timeIntervalSince1970 }
}

#Preview {
    HomeView(
        weight: WeightStore(fileURL: nil, health: nil),
        activity: ActivityStore(health: nil),
        food: FoodStore(fileURL: nil)
    )
}

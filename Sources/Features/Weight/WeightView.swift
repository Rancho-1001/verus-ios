import Charts
import SwiftUI

/// The Weight screen: daily weigh-in, weekly truth.
///
/// The hierarchy is the argument. The trend is the largest thing on screen;
/// this morning's reading sits under it in grey. That is the whole point of
/// the product stated in type sizes — the number you stood on the scale for is
/// not the number that matters.
struct WeightView: View {
    @Bindable var store: WeightStore
    @State private var entryText = ""
    @FocusState private var entryFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    headline
                    chart
                    weighIn
                    weeks
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Weight")
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // MARK: - Headline

    private var headline: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your true weight")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.6)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let trend = store.trendPounds {
                    Text(trend, format: .number.precision(.fractionLength(1)))
                        .font(.system(size: 60, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText())
                } else {
                    Text("—")
                        .font(.system(size: 60, weight: .semibold, design: .rounded))
                }
                Text("lb")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if let latest = store.latestEntry {
                Text("Last weigh-in \(latest.pounds, format: .number.precision(.fractionLength(1))) lb · \(latest.date, format: .dateTime.weekday().day().month())")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }

            projectionLine
                .font(.subheadline)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Every branch here is a case the engine can actually return. There is no
    /// `else { "on track!" }` — if the data does not support a date, the
    /// screen says what it does support instead.
    @ViewBuilder
    private var projectionLine: some View {
        switch store.projection {
        case .reached:
            Label("Goal reached", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)

        case .notEnoughData(let needed):
            Label("Keep weighing in — \(needed) days of data before a projection",
                  systemImage: "clock")
                .foregroundStyle(.secondary)

        case .tooSlowToProject:
            Label("The trend is flat — no honest date to give yet",
                  systemImage: "equal.circle")
                .foregroundStyle(.secondary)

        case .movingAway(let rate):
            Label("Trending up \(abs(rate * WeightEntry.poundsPerKilogram), format: .number.precision(.fractionLength(1))) lb/week",
                  systemImage: "arrow.up.right")
                .foregroundStyle(.orange)

        case .onTrack(let date, _, let rate):
            VStack(alignment: .leading, spacing: 2) {
                Label("\(goalPounds, format: .number.precision(.fractionLength(0))) lb by \(date, format: .dateTime.month().year())",
                      systemImage: "target")
                    .foregroundStyle(.primary)
                Text("at \(abs(rate * WeightEntry.poundsPerKilogram), format: .number.precision(.fractionLength(1))) lb/week, your current pace")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var goalPounds: Double { store.goalKilograms * WeightEntry.poundsPerKilogram }

    // MARK: - Chart

    private var chart: some View {
        Chart {
            ForEach(store.trend) { point in
                if let raw = point.rawKilograms {
                    PointMark(
                        x: .value("Day", point.date),
                        y: .value("Weight", raw * WeightEntry.poundsPerKilogram)
                    )
                    .foregroundStyle(.secondary.opacity(0.35))
                    .symbolSize(18)
                }
            }
            ForEach(store.trend) { point in
                LineMark(
                    x: .value("Day", point.date),
                    y: .value("Trend", point.pounds)
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(.init(lineWidth: 3))
                .foregroundStyle(Color.accentColor)
            }
            RuleMark(y: .value("Goal", goalPounds))
                .lineStyle(.init(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(.green.opacity(0.7))
                .annotation(position: .top, alignment: .leading) {
                    Text("Goal").font(.caption2).foregroundStyle(.green)
                }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: 220)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(.background, in: .rect(cornerRadius: 16))
    }

    // MARK: - Weigh in

    private var weighIn: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This morning")
                .font(.headline)
            HStack(spacing: 12) {
                TextField("0.0", text: $entryText)
                    .keyboardType(.decimalPad)
                    .focused($entryFocused)
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                    .frame(maxWidth: 140)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.background, in: .rect(cornerRadius: 12))
                Text("lb").foregroundStyle(.secondary)
                Spacer()
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(parsedEntry == nil)
            }
        }
    }

    private var parsedEntry: Double? {
        guard let value = Double(entryText.trimmingCharacters(in: .whitespaces)) else { return nil }
        // A bathroom scale will not read outside this, so a number outside it
        // is a typo — 18 instead of 180, or a stray digit.
        guard (50...700).contains(value) else { return nil }
        return value
    }

    private func save() {
        guard let value = parsedEntry else { return }
        withAnimation(.snappy) {
            store.record(pounds: value)
            entryText = ""
            entryFocused = false
        }
    }

    // MARK: - Weeks

    private var weeks: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("By week")
                .font(.headline)
            VStack(spacing: 0) {
                ForEach(store.weeklyAverages.reversed().prefix(6)) { week in
                    HStack {
                        Text(week.weekStart, format: .dateTime.day().month())
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !week.isReliable {
                            Text("\(week.entryCount) weigh-in\(week.entryCount == 1 ? "" : "s")")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Text(week.pounds, format: .number.precision(.fractionLength(1)))
                            .monospacedDigit()
                            .fontWeight(.medium)
                            .foregroundStyle(week.isReliable ? .primary : .secondary)
                    }
                    .padding(.vertical, 11)
                    .padding(.horizontal, 14)
                    if week.weekStart != store.weeklyAverages.reversed().prefix(6).last?.weekStart {
                        Divider().padding(.leading, 14)
                    }
                }
            }
            .background(.background, in: .rect(cornerRadius: 16))
        }
    }
}

#Preview {
    WeightView(store: WeightStore(fileURL: nil))
}

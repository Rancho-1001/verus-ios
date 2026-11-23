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
    @Bindable var activity: ActivityStore
    @State private var entryText = ""
    @State private var bodyFatText = ""
    @State private var isEditingGoals = false
    @FocusState private var entryFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    headline
                    chart
                    composition
                    weighIn
                    weeks
                    ledger
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Weight")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Goals", systemImage: "target") { isEditingGoals = true }
                        .accessibilityLabel("Goals and settings")
                }
            }
            .sheet(isPresented: $isEditingGoals) {
                SettingsSheet(weight: store, activity: activity)
            }
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

    /// What the scale measured besides the weight.
    ///
    /// A connected scale writes body fat, lean mass and BMI to Apple Health
    /// as separate records taken at the same instant; Verus reads all of them
    /// and puts them back together, so this card is the one place where one
    /// step onto the scale is shown as one reading.
    ///
    /// Silent when nothing has ever arrived, rather than showing an empty
    /// card — for a scale that reports weight alone, it never will, and a
    /// card full of dashes would imply otherwise.
    /// The weigh-in the card describes: the last one that carried
    /// composition, or simply the last one when a height is on file and a
    /// BMI can be worked out from it.
    private var compositionEntry: WeightEntry? {
        store.latestCompositionEntry ?? (store.heightMeters != nil ? store.latestEntry : nil)
    }

    @ViewBuilder
    private var composition: some View {
        if let entry = compositionEntry {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Composition").font(.headline)
                    Spacer()
                    Text(entry.date, format: .dateTime.day().month())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    if let fat = entry.bodyFatPercent {
                        compositionTile(
                            "\(fat.formatted(.number.precision(.fractionLength(1))))%", "body fat"
                        )
                    }
                    if let fatMass = entry.fatKilograms {
                        compositionTile(pounds(fatMass), "lb fat")
                    }
                    if let lean = entry.bestLeanKilograms {
                        compositionTile(
                            pounds(lean),
                            entry.isLeanMeasured ? "lb lean" : "lb lean, derived"
                        )
                    }
                    if let bmi = store.bodyMassIndex(for: entry) {
                        compositionTile(
                            bmi.value.formatted(.number.precision(.fractionLength(1))),
                            bmi.isMeasured ? "BMI" : "BMI, your height"
                        )
                    }
                }

                if let relationship = goalRelationshipText {
                    Text(relationship)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.background, in: .rect(cornerRadius: 16))
        }
    }

    private func compositionTile(_ value: String, _ label: String) -> some View {
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
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(Color(.systemGroupedBackground), in: .rect(cornerRadius: 12))
    }

    private func pounds(_ kilograms: Double) -> String {
        (kilograms * WeightEntry.poundsPerKilogram)
            .formatted(.number.precision(.fractionLength(1)))
    }

    /// The way in to every weigh-in, and the only place they can be deleted.
    private var ledger: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink {
                WeighInListView(store: store)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("All weigh-ins").font(.subheadline.weight(.medium))
                        Text(store.isShowingSampleEntries
                             ? "Sample data — the first real weigh-in replaces it"
                             : "\(store.entries.count) recorded")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(.background, in: .rect(cornerRadius: 16))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    /// The concept asks for the relationship between the weight goal and the
    /// body-fat goal to be visible, not just a date on a chart.
    private var goalRelationshipText: String? {
        guard let goalFat = store.goalBodyFatPercent else { return nil }
        let fat = goalFat.formatted(.number.precision(.fractionLength(0)))
        switch store.goalRelationship {
        case .noBodyFatRecorded:
            return nil
        case .converge(let at):
            return "\(fat)% body fat lands at about \(at.formatted(.number.precision(.fractionLength(0)))) lb — the same place as your weight goal."
        case .bodyFatReachedFirst(let at):
            return "\(fat)% body fat arrives around \(at.formatted(.number.precision(.fractionLength(0)))) lb, before the scale goal."
        case .weightReachedFirst(let at):
            return "\(fat)% body fat needs about \(at.formatted(.number.precision(.fractionLength(0)))) lb — below your weight goal."
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
            // A failed write to Health is said out loud. The weigh-in is
            // already saved locally, so this is not an error the user has to
            // act on — but silently dropping it would mean their other apps
            // quietly fall out of step with no sign that anything happened.
            if let error = store.healthWriteError {
                Label(error, systemImage: "heart.slash")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.bottom, 2)
            }
            HStack(spacing: 10) {
                TextField("0.0", text: $entryText)
                    .keyboardType(.decimalPad)
                    .focused($entryFocused)
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                    .frame(maxWidth: 118)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.background, in: .rect(cornerRadius: 12))
                Text("lb").foregroundStyle(.secondary)

                // Optional, and visibly so. A scale that reports body fat is
                // not a given, and a required field here would make the
                // morning weigh-in slower for everyone who has not got one.
                TextField("—", text: $bodyFatText)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .frame(maxWidth: 62)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 13)
                    .background(.background, in: .rect(cornerRadius: 12))
                Text("%").foregroundStyle(.secondary)

                Spacer(minLength: 0)
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(parsedEntry == nil || parsedBodyFat == nil)
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

    /// `.some(nil)` is an empty field, which is fine. `.none` is a number
    /// outside anything a body-fat scale reports, which is a typo.
    private var parsedBodyFat: Double?? {
        let trimmed = bodyFatText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .some(nil) }
        guard let value = Double(trimmed), (3...60).contains(value) else { return .none }
        return .some(value)
    }

    private func save() {
        guard let value = parsedEntry, case .some(let fat) = parsedBodyFat else { return }
        withAnimation(.snappy) {
            store.record(pounds: value, bodyFatPercent: fat)
            entryText = ""
            bodyFatText = ""
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
    WeightView(store: WeightStore(fileURL: nil, health: nil), activity: ActivityStore(health: nil))
}

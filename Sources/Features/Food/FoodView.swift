import SwiftUI

/// Food: intake and expenditure in the same place.
///
/// The concept's claim for this screen is that the four-app stack cannot make
/// this comparison at all, because food is missing from it. So the comparison
/// is the headline, and everything else on the screen serves it.
///
/// Photo logging is not here yet. The button exists and says so plainly
/// rather than being hidden, because the accuracy of a vision model on real
/// food is an open question and shipping it before answering that would be
/// the one thing the product cannot afford to get wrong.
struct FoodView: View {
    @Bindable var food: FoodStore
    @Bindable var activity: ActivityStore
    @Bindable var weight: WeightStore

    @State private var isAddingFood = false

    private var calendar: Calendar { activity.calendar }

    private var today: EnergyBudget.Day {
        food.day(.now, activity: activity.today)
    }

    private var todaysEntries: [FoodEntry] { food.entries(on: .now) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    balance
                    actions
                    meals
                    expectation
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Food")
            .sheet(isPresented: $isAddingFood) {
                FoodEntrySheet(food: food)
            }
            .task { await activity.loadRecent(weeks: 2) }
            // Meals logged in another app arrive here rather than having to
            // be typed in twice. Verus writes nothing back, so the two sets
            // cannot double-count — see `DietaryImport`.
            .task { await food.syncFromHealth() }
        }
    }

    // MARK: - Balance

    @ViewBuilder
    private var balance: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(today.isInProgress ? "Today so far" : "Today")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.6)

            switch today.balance {
            case .noData:
                Text("—")
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                Text("Log something and it appears here against what you have burned.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

            case .burnOnly(let burned):
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("—")
                        .font(.system(size: 52, weight: .semibold, design: .rounded))
                    Text("\(Int(burned)) burned").font(.title3.weight(.medium)).foregroundStyle(.secondary)
                }
                Text("Nothing logged yet, so there is no balance to show. An unlogged day is not a deficit.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

            case .intakeOnly(let kilocalories):
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("\(Int(kilocalories))")
                        .font(.system(size: 52, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("kcal in").font(.title3.weight(.medium)).foregroundStyle(.secondary)
                }
                // No burn figure means no budget. Saying "deficit unknown" is
                // the honest version; inventing an expenditure would invent
                // the deficit along with it.
                Label(
                    "No energy data from Apple Health today, so there is no budget to compare against.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.top, 2)

            case .known(let intake, let burn, let net):
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("\(net > 0 ? "+" : "")\(Int(net))")
                        .font(.system(size: 52, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText())
                        .foregroundStyle(net <= 0 ? .primary : Color.orange)
                    Text("kcal").font(.title3.weight(.medium)).foregroundStyle(.secondary)
                }
                Text("\(Int(intake)) eaten · \(Int(burn)) burned")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if today.isInProgress {
                    // By mid-morning you have burned a few hundred and eaten a
                    // few hundred, and the difference between them means
                    // almost nothing. Say so rather than presenting it as a
                    // verdict on the day.
                    Label("The day is still running — both numbers are still going up.",
                          systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
            }

            if today.itemsWithMacros > 0 {
                macroRow
                    .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var macroRow: some View {
        HStack(spacing: 10) {
            macroTile("Protein", grams: today.proteinGrams)
            macroTile("Carbs", grams: today.carbGrams)
            macroTile("Fat", grams: today.fatGrams)
        }
        .overlay(alignment: .bottomLeading) {
            // A protein total over three of seven items is not the day's
            // protein, and the screen says which it is.
            if today.itemsWithMacros < today.itemCount {
                Text("from \(today.itemsWithMacros) of \(today.itemCount) items")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .offset(y: 15)
            }
        }
        .padding(.bottom, today.itemsWithMacros < today.itemCount ? 15 : 0)
    }

    private func macroTile(_ label: String, grams: Double) -> some View {
        VStack(spacing: 2) {
            Text("\(Int(grams))g")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(Color.card, in: .rect(cornerRadius: 12))
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                isAddingFood = true
            } label: {
                Label("Log food", systemImage: "plus")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.card, in: .rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            // Present and disabled rather than absent. Hiding it would hide
            // the plan; disabling it with a reason states where the product
            // actually is.
            VStack(spacing: 2) {
                Label("Photo", systemImage: "camera")
                    .font(.subheadline.weight(.medium))
                Text("not yet")
                    .font(.system(size: 9))
            }
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(.background.opacity(0.5), in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.quaternary, style: .init(lineWidth: 1, dash: [4, 3]))
            }
            .accessibilityLabel("Photo logging, not available yet")
        }
    }

    // MARK: - Meals

    @ViewBuilder
    private var meals: some View {
        let grouped = EnergyBudget.byMeal(todaysEntries)
        if grouped.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Nothing logged today.").font(.subheadline.weight(.medium))
                Text("Anything logged in another app that writes to Apple Health appears here on its own. Photo logging is the plan and is not built yet — the accuracy of a calorie estimate from a photograph is still an open question, and it is not worth shipping before it is answered. Manual entry works now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.card, in: .rect(cornerRadius: 16))
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(grouped, id: \.meal) { group in
                    mealSection(group.meal, entries: group.entries)
                }
            }
        }
    }

    private func mealSection(_ meal: Meal, entries: [FoodEntry]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(meal.label, systemImage: meal.symbol)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(entries.reduce(0) { $0 + $1.kilocalories })) kcal")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Text(entry.name).font(.subheadline)
                                if entry.isEstimate {
                                    Text("est.")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(.orange)
                                }
                            }
                            if let detail = detailLine(entry) {
                                Text(detail)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        Text("\(Int(entry.kilocalories))")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .contentShape(.rect)
                    // Was `.swipeActions`, which does nothing outside a
                    // `List` — the gesture simply never fired, so a logged
                    // meal could not be removed at all. A context menu works
                    // anywhere and is one long press.
                    .contextMenu {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            food.delete(entry)
                        }
                    }
                    if index < entries.count - 1 {
                        Divider().padding(.leading, 14)
                    }
                }
            }
            .background(Color.card, in: .rect(cornerRadius: 14))
        }
    }

    /// Where a figure came from, and what was in it.
    ///
    /// Said on the row rather than in a footnote: a number Verus was handed
    /// by another app is a different kind of claim from one typed in here,
    /// and the screen should not flatten the two.
    private func detailLine(_ entry: FoodEntry) -> String? {
        var parts: [String] = []
        // Not when the row is already named after the app — an app that
        // writes no food name gives "Health / via Health", which says the
        // same thing twice.
        if entry.isFromHealth, let source = entry.externalSourceName, source != entry.name {
            parts.append("via \(source)")
        }
        if let protein = entry.proteinGrams {
            parts.append("P \(Int(protein.rounded()))g")
        }
        if let carbs = entry.carbGrams {
            parts.append("C \(Int(carbs.rounded()))g")
        }
        if let fat = entry.fatGrams {
            parts.append("F \(Int(fat.rounded()))g")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - What it implies

    /// The conventional 3,500 kcal per pound, set beside the measured trend.
    ///
    /// Deliberately framed as an expectation to compare against, not a
    /// replacement for the scale. Real bodies adapt and the arithmetic
    /// overstates loss over long periods — the trend is what the app
    /// believes, and this is the thing the trend gets to disagree with.
    @ViewBuilder
    private var expectation: some View {
        let days = food.recentDays(14) { activity.activity(on: $0) }
        if let average = EnergyBudget.averageNet(from: days) {
            let implied = EnergyBudget.impliedPoundsPerWeek(fromDailyNet: average)
            let measured = weight.rateKilogramsPerWeek.map { $0 * WeightEntry.poundsPerKilogram }

            VStack(alignment: .leading, spacing: 7) {
                Text("What the logging implies").font(.headline)
                Text("Averaging \(Int(average)) kcal a day over the finished days of the last fortnight, which works out at about \(abs(implied), format: .number.precision(.fractionLength(1))) lb a week \(implied < 0 ? "down" : "up").")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let measured {
                    Text("Your scale says \(abs(measured), format: .number.precision(.fractionLength(1))) lb a week \(measured < 0 ? "down" : "up"). Where the two disagree, believe the scale — this figure assumes an unchanging body and complete logging, and neither is ever quite true.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.card, in: .rect(cornerRadius: 16))
        }
    }
}

// MARK: - Entry sheet

private struct FoodEntrySheet: View {
    @Bindable var food: FoodStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var meal: Meal = .suggested(at: .now, calendar: .current)

    private var parsedCalories: Double? {
        guard let value = Double(calories.trimmingCharacters(in: .whitespaces)) else { return nil }
        return (0...10_000).contains(value) ? value : nil
    }

    private func grams(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let value = Double(trimmed), (0...2_000).contains(value) else {
            return nil
        }
        return value
    }

    private var isValid: Bool {
        parsedCalories != nil && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What was it?", text: $name)
                    HStack {
                        Text("Calories")
                        Spacer()
                        TextField("0", text: $calories)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(maxWidth: 90)
                        Text("kcal").foregroundStyle(.secondary)
                    }
                    Picker("Meal", selection: $meal) {
                        ForEach(Meal.allCases.sorted { $0.sortOrder < $1.sortOrder }) { meal in
                            Text(meal.label).tag(meal)
                        }
                    }
                }

                Section {
                    macroField("Protein", text: $protein)
                    macroField("Carbs", text: $carbs)
                    macroField("Fat", text: $fat)
                } header: {
                    Text("Macros")
                } footer: {
                    Text("Optional. Anything left empty is left out of the day's totals rather than counted as zero.")
                }
            }
            .navigationTitle("Log food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!isValid)
                }
            }
        }
    }

    private func macroField(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("—", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(maxWidth: 70)
            Text("g").foregroundStyle(.secondary)
        }
    }

    private func save() {
        guard let kcal = parsedCalories else { return }
        food.add(
            FoodEntry(
                date: .now,
                name: name.trimmingCharacters(in: .whitespaces),
                kilocalories: kcal,
                proteinGrams: grams(protein),
                carbGrams: grams(carbs),
                fatGrams: grams(fat),
                meal: meal
            )
        )
        dismiss()
    }
}

#Preview {
    FoodView(
        food: FoodStore(fileURL: nil),
        activity: ActivityStore(health: nil),
        weight: WeightStore(fileURL: nil, health: nil)
    )
}

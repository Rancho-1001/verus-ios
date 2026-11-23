import SwiftUI

/// One day, in full.
///
/// The calendar shows "8.4k" because four characters is what fits inside a
/// date cell. This is where the exact figures live — and it exists because a
/// grid of tappable-looking squares that do nothing when tapped is a worse
/// answer than either a plain grid or a working one.
struct DayDetailSheet: View {
    let day: Date
    let activity: ActivityStore
    let weight: WeightStore
    let food: FoodStore

    @Environment(\.dismiss) private var dismiss

    private var calendar: Calendar { activity.calendar }
    private var reading: DailyActivity? { activity.activity(on: day) }

    private var weighIns: [WeightEntry] {
        weight.entries
            .filter { calendar.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.date < $1.date }
    }

    private var trendPounds: Double? {
        weight.trend.first { calendar.isDate($0.date, inSameDayAs: day) }?.pounds
    }

    private var workouts: [Workout] {
        activity.workouts
            .filter { calendar.isDate($0.start, inSameDayAs: day) }
            .sorted { $0.start < $1.start }
    }

    private var meals: [FoodEntry] { food.entries(on: day) }

    var body: some View {
        NavigationStack {
            List {
                if let reading {
                    Section("Movement") {
                        row("Steps", value: reading.steps.formatted(.number.grouping(.automatic)))
                        if let miles = reading.miles {
                            row("Distance", value: "\(miles.formatted(.number.precision(.fractionLength(2)))) mi")
                        }
                        row("Active energy", value: "\(Int(reading.activeKilocalories)) kcal")
                        row("Resting energy", value: "\(Int(reading.restingKilocalories)) kcal")
                        row("Total burned", value: "\(Int(reading.totalKilocalories)) kcal")
                    }
                } else {
                    Section {
                        // Absence is a fact worth stating. A zero here would
                        // claim the day was spent motionless.
                        Text("No activity recorded. Apple Health has nothing for this day — the phone was probably elsewhere.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if !workouts.isEmpty {
                    Section("Workouts") {
                        ForEach(workouts) { workout in
                            HStack {
                                Label(workout.kind, systemImage: workout.symbol)
                                Spacer()
                                Text(workout.durationText)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }

                if !weighIns.isEmpty || trendPounds != nil {
                    Section("Weight") {
                        ForEach(weighIns) { entry in
                            row(
                                entry.date.formatted(.dateTime.hour().minute()),
                                value: "\(entry.pounds.formatted(.number.precision(.fractionLength(1)))) lb"
                            )
                            // Everything else the scale sent, indented under
                            // the weigh-in it belongs to — a smart scale
                            // writes these as separate records in Health and
                            // this is where they go back together.
                            if let fat = entry.bodyFatPercent {
                                detail("Body fat", value: "\(fat.formatted(.number.precision(.fractionLength(1))))%")
                            }
                            if let lean = entry.bestLeanKilograms {
                                detail(
                                    entry.isLeanMeasured ? "Lean mass" : "Lean mass (derived)",
                                    value: "\((lean * WeightEntry.poundsPerKilogram).formatted(.number.precision(.fractionLength(1)))) lb"
                                )
                            }
                            if let bmi = entry.bodyMassIndex {
                                detail("BMI", value: bmi.formatted(.number.precision(.fractionLength(1))))
                            }
                        }
                        if let trendPounds {
                            HStack {
                                Text("Trend")
                                Spacer()
                                Text("\(trendPounds.formatted(.number.precision(.fractionLength(1)))) lb")
                                    .monospacedDigit()
                                    .fontWeight(.medium)
                            }
                        }
                    }
                }

                if !meals.isEmpty {
                    Section("Food") {
                        ForEach(meals) { entry in
                            HStack {
                                Text(entry.name)
                                Spacer()
                                Text("\(Int(entry.kilocalories)) kcal")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }
            .navigationTitle(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    /// A row that belongs to the one above it: smaller, indented, and clearly
    /// subordinate to the weigh-in it describes.
    private func detail(_ title: String, value: String) -> some View {
        HStack {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.leading, 14)
    }
}

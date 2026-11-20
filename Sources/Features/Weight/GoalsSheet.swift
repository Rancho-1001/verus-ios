import SwiftUI

/// Setting the three numbers the rest of the app aims at.
///
/// The body-fat goal is optional on purpose. Plenty of people track weight
/// and never own a body-fat scale, and every screen has to make sense for
/// them — so the field can be left empty and nothing downstream breaks.
struct GoalsSheet: View {
    @Bindable var weight: WeightStore
    @Bindable var activity: ActivityStore
    @Environment(\.dismiss) private var dismiss

    @State private var weightText = ""
    @State private var bodyFatText = ""
    @State private var stepsText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Weight") {
                    field("Target", text: $weightText, unit: "lb")
                }

                Section {
                    field("Target", text: $bodyFatText, unit: "%")
                } header: {
                    Text("Body fat")
                } footer: {
                    Text("Optional. Leave it empty if you do not measure body fat.")
                }

                Section("Activity") {
                    field("Steps a day", text: $stepsText, unit: "")
                }

                if let line = relationshipLine {
                    Section {
                        Label {
                            Text(line).font(.footnote)
                        } icon: {
                            Image(systemName: "arrow.triangle.merge")
                                .foregroundStyle(Color.accentColor)
                        }
                    } footer: {
                        Text("Assumes you keep the lean mass you have now. Losing muscle alongside fat moves this number up.")
                    }
                }
            }
            .navigationTitle("Goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!isValid)
                }
            }
            .onAppear(perform: fill)
        }
    }

    private func field(_ title: String, text: Binding<String>, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("—", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(maxWidth: 90)
            if !unit.isEmpty {
                Text(unit).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Parsing

    private var parsedWeight: Double? {
        guard let value = Double(weightText.trimmingCharacters(in: .whitespaces)) else { return nil }
        return (50...700).contains(value) ? value : nil
    }

    /// `nil` means "not set", which is valid. The `.some(nil)` / `.none`
    /// distinction matters: an empty field is a legitimate choice, whereas
    /// "45%" typed by mistake is not.
    private var parsedBodyFat: Double?? {
        let trimmed = bodyFatText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .some(nil) }
        guard let value = Double(trimmed), (3...60).contains(value) else { return .none }
        return .some(value)
    }

    private var parsedSteps: Int? {
        guard let value = Int(stepsText.trimmingCharacters(in: .whitespaces)) else { return nil }
        return (1_000...100_000).contains(value) ? value : nil
    }

    private var isValid: Bool {
        parsedWeight != nil && parsedSteps != nil && parsedBodyFat != nil
    }

    // MARK: - The relationship

    /// Shown live as the goals are typed, which is the point: the concept
    /// asks for the relationship between the two targets to be visible, not
    /// just a date on a chart.
    private var relationshipLine: String? {
        guard let goalPounds = parsedWeight,
              case .some(let goalFat?) = parsedBodyFat,
              let current = weight.trend.last?.kilograms,
              let latestFat = weight.latestBodyFatPercent
        else { return nil }

        let relationship = BodyComposition.relationship(
            currentWeightKilograms: current,
            currentBodyFatPercent: latestFat,
            goalWeightKilograms: goalPounds / WeightEntry.poundsPerKilogram,
            goalBodyFatPercent: goalFat
        )

        let fat = goalFat.formatted(.number.precision(.fractionLength(0)))
        switch relationship {
        case .noBodyFatRecorded:
            return nil
        case .converge(let at):
            return "These are the same goal: at your current lean mass, \(fat)% body fat lands at \(at.formatted(.number.precision(.fractionLength(0)))) lb."
        case .bodyFatReachedFirst(let at):
            return "You would reach \(fat)% body fat at about \(at.formatted(.number.precision(.fractionLength(0)))) lb — before the scale target. The rest of the way down is weight, not fat."
        case .weightReachedFirst(let at):
            return "Hitting \(goalPounds.formatted(.number.precision(.fractionLength(0)))) lb would leave you above \(fat)% body fat — that target needs about \(at.formatted(.number.precision(.fractionLength(0)))) lb at your current lean mass."
        }
    }

    // MARK: - Load and save

    private func fill() {
        weightText = (weight.goalKilograms * WeightEntry.poundsPerKilogram)
            .formatted(.number.precision(.fractionLength(0)))
        bodyFatText = weight.goalBodyFatPercent
            .map { $0.formatted(.number.precision(.fractionLength(0))) } ?? ""
        stepsText = "\(activity.dailyStepGoal)"
    }

    private func save() {
        guard let pounds = parsedWeight,
              let steps = parsedSteps,
              case .some(let fat) = parsedBodyFat
        else { return }
        weight.goalKilograms = pounds / WeightEntry.poundsPerKilogram
        weight.goalBodyFatPercent = fat
        activity.dailyStepGoal = steps
        dismiss()
    }
}

import SwiftUI

/// The goals the rest of the app aims at, and the handful of facts about
/// where its numbers come from.
///
/// There is one of these, reached from Home and from the Weight screen,
/// rather than a Goals sheet in one place and a Settings sheet in another
/// holding the same four fields. Verus has four numbers to set and nothing
/// to configure beyond them: no account, no sync, no theme, no units switch
/// yet. A settings screen padded out to look substantial would be inventing
/// decisions for the user to make.
///
/// The body-fat goal is optional on purpose. Plenty of people track weight
/// and never own a body-fat scale, and every screen has to make sense for
/// them — so the field can be left empty and nothing downstream breaks.
struct SettingsSheet: View {
    @Bindable var weight: WeightStore
    @Bindable var activity: ActivityStore
    @Environment(\.dismiss) private var dismiss

    @State private var weightText = ""
    @State private var bodyFatText = ""
    @State private var stepsText = ""
    @State private var activeText = ""

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

                Section {
                    field("Steps a day", text: $stepsText, unit: "")
                    field("Active energy", text: $activeText, unit: "kcal")
                } header: {
                    Text("Activity")
                } footer: {
                    // Both of these now decide a colour, not just a caption:
                    // the Home tiles turn red under half the goal, amber on
                    // the way and green at it. Said here so the numbers are
                    // understood as the lines they are.
                    Text("The month calendar reads against the step goal: red under half, amber on the way, green at it.")
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

                Section {
                    LabeledContent("Apple Health", value: healthStatus)
                    Button("Open Health settings", action: openSettings)
                } header: {
                    Text("Where the numbers come from")
                } footer: {
                    // The honest version of this, which most apps get
                    // wrong: Apple does not tell an app that a read was
                    // refused, so Verus cannot list what it is allowed to
                    // see. It can say what arrived.
                    Text("Apple Health never tells an app which readings it was refused, so Verus can only report what arrived. Health › Data Access shows what it is actually allowed to read.")
                }

                Section {
                    LabeledContent("Version", value: Self.version)
                    LabeledContent("Made by", value: "Nyansapo Labs")
                } footer: {
                    Text("Everything Verus records stays on this phone. There is no account and no server.")
                }
            }
            .navigationTitle("Settings")
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

    /// What the app can honestly say about its Health access: whether it
    /// asked, and whether anything came back.
    private var healthStatus: String {
        switch activity.state {
        case .live: "Reading your data"
        case .needsPermission: "Not connected yet"
        case .noDataFromHealth: "Connected, nothing arrived"
        case .unavailable: "Unavailable on this device"
        case .failed: "Last read failed"
        }
    }

    static var version: String {
        let bundle = Bundle.main
        let short = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
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

    /// Active kilocalories a day. The range is what a person can plausibly
    /// burn moving; anything outside it is a typo rather than an ambition.
    private var parsedActive: Int? {
        guard let value = Int(activeText.trimmingCharacters(in: .whitespaces)) else { return nil }
        return (50...5_000).contains(value) ? value : nil
    }

    private var isValid: Bool {
        parsedWeight != nil && parsedSteps != nil && parsedBodyFat != nil && parsedActive != nil
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
        activeText = "\(activity.dailyActiveEnergyGoal)"
    }

    private func save() {
        guard let pounds = parsedWeight,
              let steps = parsedSteps,
              let active = parsedActive,
              case .some(let fat) = parsedBodyFat
        else { return }
        weight.goalKilograms = pounds / WeightEntry.poundsPerKilogram
        weight.goalBodyFatPercent = fat
        activity.dailyStepGoal = steps
        activity.dailyActiveEnergyGoal = active
        dismiss()
    }
}

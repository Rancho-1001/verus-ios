import SwiftUI

/// Every weigh-in, and the only place one can be removed.
///
/// This screen exists for two reasons. The first is ordinary: a mistyped
/// weight — 1800 instead of 180 — bends the trend for a fortnight, and until
/// now there was no way to take it back out.
///
/// The second is a bug this screen is the remedy for. Early versions filled
/// an empty store with six weeks of sample weigh-ins so the chart meant
/// something on first launch, and then saved the whole array the first time a
/// real weigh-in was recorded — writing the invented mornings into the file
/// alongside the real one. New installs cannot hit that any more
/// (`WeightStore.isShowingSampleEntries`), but a file that already has them
/// needs a way out, and that way is here.
struct WeighInListView: View {
    @Bindable var store: WeightStore

    @State private var isConfirmingClear = false

    private var entries: [WeightEntry] {
        store.entries.sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            if store.isShowingSampleEntries {
                Section {
                    Label(
                        "These are sample weigh-ins, not yours. The first real one — typed in, or read from Apple Health — replaces them.",
                        systemImage: "info.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }

            if store.purgedSampleCount > 0 {
                Section {
                    Label(
                        "\(store.purgedSampleCount) sample weigh-ins were cleared out of this list. They were seeded by an early version and saved by mistake, and they were pulling the trend down. Your own weigh-ins are untouched.",
                        systemImage: "sparkles"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    Task { await store.syncFromHealth() }
                } label: {
                    HStack {
                        Label("Import from Apple Health", systemImage: "heart.text.square")
                        Spacer()
                        if store.isSyncing {
                            ProgressView()
                        }
                    }
                }
                .disabled(store.isSyncing)
            } footer: {
                Text(syncFooter)
            }

            Section {
                ForEach(entries) { entry in
                    row(entry)
                }
                .onDelete(perform: delete)
            } header: {
                Text(countHeader)
            } footer: {
                Text("Swipe a weigh-in to delete it. Deleting here does not remove it from Apple Health — the Health app is where that lives.")
            }

            // Thirty-nine rows is too many to swipe away one at a time, and
            // the sample-data bug left exactly that behind on the phones that
            // hit it. Apple Health keeps the real history, so starting over
            // from it is a recovery rather than a loss — with the one caveat
            // the confirmation spells out.
            if !store.entries.isEmpty && !store.isShowingSampleEntries {
                Section {
                    Button("Start over from Apple Health", role: .destructive) {
                        isConfirmingClear = true
                    }
                } footer: {
                    Text("Clears every weigh-in stored in Verus and reads them back from Apple Health. Anything Verus never managed to write there will not come back.")
                }
            }
        }
        .navigationTitle("Weigh-ins")
        .toolbar { EditButton() }
        .confirmationDialog(
            "Delete all \(store.entries.count) weigh-ins in Verus and re-import from Apple Health?",
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear and re-import", role: .destructive) {
                Task {
                    store.deleteAll()
                    await store.syncFromHealth()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Apple Health is not touched. Weigh-ins it does not have are gone for good.")
        }
    }

    /// Records, and how many of them are actually separate weigh-ins.
    private var countHeader: String {
        let records = entries.count
        let sessions = store.sessions.count
        guard sessions < records else {
            return "\(records) weigh-in\(records == 1 ? "" : "s")"
        }
        return "\(sessions) weigh-in\(sessions == 1 ? "" : "s") · \(records) records"
    }

    private var syncFooter: String {
        guard store.lastSyncAt != nil else {
            return "Pulls weigh-ins and body composition recorded by a smart scale or another app. Runs on its own when Verus opens; this is for when you want it now."
        }
        if store.lastImportCount == 0 && store.lastEnrichedCount == 0 {
            return "Last check found nothing new."
        }
        var parts: [String] = []
        if store.lastImportCount > 0 {
            parts.append("\(store.lastImportCount) weigh-in\(store.lastImportCount == 1 ? "" : "s") added")
        }
        if store.lastEnrichedCount > 0 {
            // Worth naming separately: these were already here, and what
            // arrived was the body fat and lean mass that came with them.
            parts.append("\(store.lastEnrichedCount) completed with body composition")
        }
        return parts.joined(separator: ", ") + "."
    }

    private func row(_ entry: WeightEntry) -> some View {
        let superseded = store.supersededIDs.contains(entry.id)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(entry.pounds, format: .number.precision(.fractionLength(1))) lb")
                    .font(.body.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(superseded ? .secondary : .primary)
                Spacer()
                Text(entry.date, format: .dateTime.weekday(.abbreviated).day().month().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let detail = compositionDetail(entry) {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            // Kept and shown, but not counted twice. A scale writes two or
            // three records as a weigh-in settles; the last one is the
            // reading, and saying so is better than quietly dropping the
            // others from a list that claims to be the record.
            if superseded {
                Text("superseded by a reading moments later")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func compositionDetail(_ entry: WeightEntry) -> String? {
        var parts: [String] = []
        if let fat = entry.bodyFatPercent {
            parts.append("\(fat.formatted(.number.precision(.fractionLength(1))))% fat")
        }
        if let lean = entry.leanKilograms {
            parts.append("\((lean * WeightEntry.poundsPerKilogram).formatted(.number.precision(.fractionLength(1)))) lb lean")
        }
        if let bmi = entry.bodyMassIndex {
            parts.append("BMI \(bmi.formatted(.number.precision(.fractionLength(1))))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func delete(_ offsets: IndexSet) {
        let list = entries
        for index in offsets {
            store.delete(list[index])
        }
    }
}

#Preview {
    NavigationStack {
        WeighInListView(store: WeightStore(fileURL: nil, health: nil))
    }
}

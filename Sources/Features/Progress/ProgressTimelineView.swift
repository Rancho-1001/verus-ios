import PhotosUI
import SwiftUI

/// Progress: one timeline, so cause and effect are read together.
///
/// Named `ProgressTimelineView` rather than `ProgressView` because SwiftUI
/// already owns that name and shadowing it would make every spinner in the
/// app ambiguous.
///
/// The ordering is the argument. Each card carries a photograph, the trend
/// weight on that day, and the change since the card below it — so scrolling
/// down is scrolling backwards through the journey, with the numbers attached
/// to the picture rather than on a separate screen.
struct ProgressTimelineView: View {
    @Bindable var progress: ProgressStore
    @Bindable var weight: WeightStore

    @State private var pickerItem: PhotosPickerItem?
    @State private var isAddingMeasurement = false
    @State private var zoomed: ProgressPhoto?

    private var moments: [ProgressMoment] {
        progress.timeline(trend: weight.trend)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    actions
                    measurementSummary
                    timeline
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Progress")
            // Waist measurements recorded elsewhere arrive here rather than
            // having to be typed in twice.
            .task { await progress.syncWaistFromHealth() }
            .sheet(isPresented: $isAddingMeasurement) {
                MeasurementEntrySheet(progress: progress)
            }
            .sheet(item: $zoomed) { photo in
                PhotoDetailSheet(photo: photo, progress: progress)
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task { await load(item) }
            }
        }
    }

    private func load(_ item: PhotosPickerItem) async {
        defer { pickerItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else { return }
        // Dated now rather than from the photograph's own metadata: a picture
        // chosen from the library may be months old, and silently backdating
        // it would move a card down the timeline for reasons the user cannot
        // see. The date is editable on the card instead.
        progress.addPhoto(image)
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 10) {
            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                Label("Add photo", systemImage: "camera")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.card, in: .rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            Button {
                isAddingMeasurement = true
            } label: {
                Label("Measure", systemImage: "ruler")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.card, in: .rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Measurements

    @ViewBuilder
    private var measurementSummary: some View {
        let latest = progress.latestMeasurements
        if !latest.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Latest measurements").font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(latest) { reading in
                            measurementTile(reading)
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    private func measurementTile(_ reading: BodyMeasurement) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(reading.site.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text("\(reading.inches, format: .number.precision(.fractionLength(1)))\"")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
            if let change = progress.change(for: reading.site) {
                let inches = change / 2.54
                Text("\(inches > 0 ? "+" : "")\(inches, format: .number.precision(.fractionLength(1)))\" overall")
                    .font(.system(size: 10))
                    .foregroundStyle(inches < 0 ? .green : .secondary)
            } else {
                Text("first reading")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(minWidth: 92, alignment: .leading)
        .padding(.vertical, 11)
        .padding(.horizontal, 13)
        .background(Color.card, in: .rect(cornerRadius: 14))
    }

    // MARK: - Timeline

    @ViewBuilder
    private var timeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Timeline").font(.headline)

            if moments.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Nothing here yet.")
                        .font(.subheadline.weight(.medium))
                    Text("Add a photo or a measurement and it lands on this timeline beside your weight trend, so you can see what changed and what it looked like.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Photos stay on this phone. They are not uploaded anywhere, and they are encrypted while it is locked.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color.card, in: .rect(cornerRadius: 16))
            } else {
                ForEach(moments) { moment in
                    momentCard(moment)
                }
            }
        }
    }

    private func momentCard(_ moment: ProgressMoment) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(moment.day, format: .dateTime.weekday(.abbreviated).day().month(.wide))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let trend = moment.trendPounds {
                    Text("\(trend, format: .number.precision(.fractionLength(1))) lb")
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 13)
            .padding(.bottom, moment.changeSincePreviousPounds == nil ? 11 : 2)

            if let change = moment.changeSincePreviousPounds {
                Text("\(change > 0 ? "+" : "")\(change, format: .number.precision(.fractionLength(1))) lb since the last entry")
                    .font(.caption)
                    .foregroundStyle(change < 0 ? .green : .secondary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 11)
            }

            if !moment.photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(moment.photos) { photo in
                            Button { zoomed = photo } label: {
                                thumbnail(photo)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                }
                .padding(.bottom, 12)
            }

            if !moment.measurements.isEmpty {
                HStack(spacing: 14) {
                    ForEach(moment.measurements) { reading in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(reading.site.label)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text("\(reading.inches, format: .number.precision(.fractionLength(1)))\"")
                                .font(.caption.weight(.medium))
                                .monospacedDigit()
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 13)
            }
        }
        .background(Color.card, in: .rect(cornerRadius: 16))
    }

    @ViewBuilder
    private func thumbnail(_ photo: ProgressPhoto) -> some View {
        if let image = progress.image(for: photo) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 132, height: 176)
                .clipShape(.rect(cornerRadius: 11))
        } else {
            RoundedRectangle(cornerRadius: 11)
                .fill(.quaternary)
                .frame(width: 132, height: 176)
                .overlay {
                    Image(systemName: "photo").foregroundStyle(.tertiary)
                }
        }
    }
}

// MARK: - Measurement entry

private struct MeasurementEntrySheet: View {
    @Bindable var progress: ProgressStore
    @Environment(\.dismiss) private var dismiss

    @State private var site: MeasurementSite = .waist
    @State private var value = ""

    private var parsed: Double? {
        guard let inches = Double(value.trimmingCharacters(in: .whitespaces)) else { return nil }
        // A tape around a human limb or torso does not read outside this.
        return (5...80).contains(inches) ? inches : nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Where", selection: $site) {
                    ForEach(MeasurementSite.allCases.sorted { $0.sortOrder < $1.sortOrder }) { site in
                        Text(site.label).tag(site)
                    }
                }
                HStack {
                    TextField("0.0", text: $value)
                        .keyboardType(.decimalPad)
                        .monospacedDigit()
                    Text("inches").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add measurement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let parsed else { return }
                        progress.record(parsed, site: site)
                        dismiss()
                    }
                    .disabled(parsed == nil)
                }
            }
        }
        .presentationDetents([.height(240)])
    }
}

// MARK: - Photo detail

private struct PhotoDetailSheet: View {
    let photo: ProgressPhoto
    @Bindable var progress: ProgressStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image = progress.image(for: photo) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
            .navigationTitle(photo.date.formatted(.dateTime.day().month(.wide).year()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Delete", role: .destructive) { confirmingDelete = true }
                }
            }
            .confirmationDialog(
                "Delete this photo?",
                isPresented: $confirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete photo", role: .destructive) {
                    progress.delete(photo)
                    dismiss()
                }
            } message: {
                Text("The image file is removed from this phone. This cannot be undone.")
            }
        }
    }
}

#Preview {
    ProgressTimelineView(
        progress: ProgressStore(root: nil),
        weight: WeightStore(fileURL: nil, health: nil)
    )
}

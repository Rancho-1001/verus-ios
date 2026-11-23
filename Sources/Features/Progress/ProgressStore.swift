import Foundation
import Observation
import UIKit

/// Progress photographs and body measurements.
///
/// Three decisions about storage, all of them deliberate, because section 9
/// of the concept asks for this to be designed before launch rather than
/// patched after it.
///
/// **The photographs never leave the device.** They are written inside the
/// app's own container, not to the shared photo library and not to any
/// server. There is no upload path in this file to go wrong later.
///
/// **They are encrypted while the phone is locked.** Each file is written with
/// `.completeFileProtection`, so the bytes are unreadable until the device is
/// unlocked — the default is weaker, and the default is not good enough for
/// photographs somebody took of their own body.
///
/// **Deleting means deleting.** Removing an entry removes the file, not just
/// the row that points at it. Orphaned images in a container are the thing
/// that makes a "delete my data" promise a lie.
@MainActor
@Observable
final class ProgressStore {

    private(set) var photos: [ProgressPhoto] = []
    private(set) var measurements: [BodyMeasurement] = []
    private(set) var lastError: String?

    var calendar: Calendar = {
        var c = Calendar.current
        c.firstWeekday = 2
        return c
    }()

    private let root: URL?
    private var thumbnails: [String: UIImage] = [:]
    private let health: HealthKitService?

    /// How many waist measurements the last sync brought across.
    private(set) var lastWaistImportCount = 0

    init(
        root: URL? = ProgressStore.defaultRoot,
        health: HealthKitService? = HealthKitService.isAvailable ? HealthKitService() : nil
    ) {
        self.root = root
        self.health = health
        createDirectories()
        load()
    }

    // MARK: - Apple Health

    /// Pulls waist measurements recorded elsewhere — a smart tape, the Health
    /// app, a scale that estimates it — into the tape measurements this
    /// screen already keeps.
    ///
    /// Only the waist. Health has no type for a chest or a thigh, so those
    /// stay hand-entered, and nothing here pretends otherwise. Matching is
    /// the same shape as the weigh-in rule: same day and the same figure to a
    /// millimetre is the same measurement, whichever app wrote it.
    @discardableResult
    func syncWaistFromHealth(since: Date? = nil) async -> Int {
        guard let health else { return 0 }
        let start = since
            ?? calendar.date(byAdding: .year, value: -1, to: .now)
            ?? .distantPast
        guard let samples = try? await health.waistSamples(from: start, to: .now),
              !samples.isEmpty
        else {
            lastWaistImportCount = 0
            return 0
        }

        var known = Set(measurements.filter { $0.site == .waist }.map(waistFingerprint))
        var added = 0
        for sample in samples {
            let measurement = BodyMeasurement(
                date: sample.date, site: .waist, centimetres: sample.value
            )
            let key = waistFingerprint(measurement)
            guard !known.contains(key) else { continue }
            known.insert(key)
            measurements.append(measurement)
            added += 1
        }

        if added > 0 {
            measurements.sort { $0.date < $1.date }
            save()
        }
        lastWaistImportCount = added
        return added
    }

    private func waistFingerprint(_ measurement: BodyMeasurement) -> String {
        let day = calendar.startOfDay(for: measurement.date).timeIntervalSince1970
        return "\(Int(day))|\((measurement.centimetres * 10).rounded())"
    }

    // MARK: - Locations

    static var defaultRoot: URL? {
        try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        .appendingPathComponent("Progress", isDirectory: true)
    }

    private var photosDirectory: URL? {
        root?.appendingPathComponent("Photos", isDirectory: true)
    }

    private var indexURL: URL? {
        root?.appendingPathComponent("index.json")
    }

    private func createDirectories() {
        guard let photosDirectory else { return }
        try? FileManager.default.createDirectory(
            at: photosDirectory, withIntermediateDirectories: true
        )
    }

    func url(for photo: ProgressPhoto) -> URL? {
        photosDirectory?.appendingPathComponent(photo.filename)
    }

    // MARK: - Timeline

    func timeline(trend: [TrendPoint]) -> [ProgressMoment] {
        ProgressTimeline.build(
            photos: photos, measurements: measurements, trend: trend, calendar: calendar
        )
    }

    var latestMeasurements: [BodyMeasurement] {
        ProgressTimeline.latestMeasurements(from: measurements)
    }

    func change(for site: MeasurementSite) -> Double? {
        ProgressTimeline.change(for: site, in: measurements)
    }

    // MARK: - Photos

    /// The longest edge a stored photograph keeps.
    ///
    /// 1600 points is sharp on every current iPhone at full width and about a
    /// tenth the bytes of an original. A timeline of fifty untouched camera
    /// photographs is hundreds of megabytes, and nothing on screen is better
    /// for it.
    private static let maxDimension: CGFloat = 1_600

    @discardableResult
    func addPhoto(_ image: UIImage, on date: Date = .now) -> ProgressPhoto? {
        guard let photosDirectory else { return nil }

        let scaled = Self.downscaled(image, maxDimension: Self.maxDimension)
        guard let data = scaled.jpegData(compressionQuality: 0.82) else {
            lastError = "Could not encode that photograph."
            return nil
        }

        let photo = ProgressPhoto(date: date, filename: "\(UUID().uuidString).jpg")
        let destination = photosDirectory.appendingPathComponent(photo.filename)

        do {
            try data.write(to: destination, options: [.atomic, .completeFileProtection])
        } catch {
            lastError = "Could not save that photograph: \(error.localizedDescription)"
            return nil
        }

        photos.append(photo)
        photos.sort { $0.date < $1.date }
        thumbnails[photo.filename] = scaled
        save()
        lastError = nil
        return photo
    }

    func image(for photo: ProgressPhoto) -> UIImage? {
        if let cached = thumbnails[photo.filename] { return cached }
        guard let url = url(for: photo),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data)
        else { return nil }
        thumbnails[photo.filename] = image
        return image
    }

    /// Removes the record *and* the file behind it.
    func delete(_ photo: ProgressPhoto) {
        if let url = url(for: photo) {
            try? FileManager.default.removeItem(at: url)
        }
        thumbnails[photo.filename] = nil
        photos.removeAll { $0.id == photo.id }
        save()
    }

    private static func downscaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - Measurements

    func record(_ inches: Double, site: MeasurementSite, on date: Date = .now) {
        measurements.append(.fromInches(inches, date: date, site: site))
        measurements.sort { $0.date < $1.date }
        save()
    }

    func delete(_ measurement: BodyMeasurement) {
        measurements.removeAll { $0.id == measurement.id }
        save()
    }

    // MARK: - Persistence

    private struct Index: Codable {
        struct StoredPhoto: Codable {
            let id: UUID
            let date: Date
            let filename: String
        }
        struct StoredMeasurement: Codable {
            let id: UUID
            let date: Date
            let site: MeasurementSite
            let centimetres: Double
        }
        var photos: [StoredPhoto] = []
        var measurements: [StoredMeasurement] = []
    }

    private func load() {
        guard let indexURL, let data = try? Data(contentsOf: indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let index = try? decoder.decode(Index.self, from: data) else { return }

        // A record whose file has gone is dropped rather than kept as a grey
        // box forever. Files do vanish — a restore from a partial backup, a
        // failed write — and a timeline full of placeholders is worse than a
        // shorter honest one.
        photos = index.photos
            .map { ProgressPhoto(id: $0.id, date: $0.date, filename: $0.filename) }
            .filter { photo in
                guard let url = url(for: photo) else { return false }
                return FileManager.default.fileExists(atPath: url.path)
            }
            .sorted { $0.date < $1.date }

        measurements = index.measurements
            .map { BodyMeasurement(id: $0.id, date: $0.date, site: $0.site, centimetres: $0.centimetres) }
            .sorted { $0.date < $1.date }
    }

    private func save() {
        guard let indexURL else { return }
        let index = Index(
            photos: photos.map { .init(id: $0.id, date: $0.date, filename: $0.filename) },
            measurements: measurements.map {
                .init(id: $0.id, date: $0.date, site: $0.site, centimetres: $0.centimetres)
            }
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(index) else { return }
        try? data.write(to: indexURL, options: [.atomic, .completeFileProtection])
    }
}

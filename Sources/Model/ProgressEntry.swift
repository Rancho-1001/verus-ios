import Foundation

/// A progress photograph.
///
/// The image itself is never carried in this type — only the file name it
/// lives under. Loading a dozen full-resolution photographs into memory to
/// draw a scrolling list is how a photo timeline becomes a slideshow, and
/// keeping the bytes out of the model makes that mistake harder to make.
struct ProgressPhoto: Identifiable, Hashable, Sendable {
    let id: UUID
    let date: Date
    /// File name inside the photos directory. Never an absolute path: the
    /// container path changes between installs and across devices, so a
    /// stored absolute path is a broken path waiting to happen.
    let filename: String

    init(id: UUID = UUID(), date: Date, filename: String) {
        self.id = id
        self.date = date
        self.filename = filename
    }
}

/// Where on the body a tape measure went.
enum MeasurementSite: String, CaseIterable, Codable, Sendable, Identifiable {
    case waist, chest, hips, thigh, arm, neck

    var id: String { rawValue }

    var label: String {
        switch self {
        case .waist: "Waist"
        case .chest: "Chest"
        case .hips: "Hips"
        case .thigh: "Thigh"
        case .arm: "Arm"
        case .neck: "Neck"
        }
    }

    /// Shown first, because waist is the one measurement that tracks body
    /// composition closely enough to be worth taking weekly — the others are
    /// useful but secondary.
    var sortOrder: Int {
        switch self {
        case .waist: 0
        case .chest: 1
        case .hips: 2
        case .thigh: 3
        case .arm: 4
        case .neck: 5
        }
    }
}

/// One tape measurement.
///
/// Stored in centimetres and only in centimetres, for the same reason weight
/// is stored only in kilograms: one internal unit, converted at the edges, so
/// there is exactly one place a unit can be confused.
struct BodyMeasurement: Identifiable, Hashable, Sendable {
    let id: UUID
    let date: Date
    let site: MeasurementSite
    let centimetres: Double

    init(id: UUID = UUID(), date: Date, site: MeasurementSite, centimetres: Double) {
        self.id = id
        self.date = date
        self.site = site
        self.centimetres = centimetres
    }

    var inches: Double { centimetres / 2.54 }

    static func fromInches(
        _ inches: Double,
        id: UUID = UUID(),
        date: Date,
        site: MeasurementSite
    ) -> BodyMeasurement {
        BodyMeasurement(id: id, date: date, site: site, centimetres: inches * 2.54)
    }
}

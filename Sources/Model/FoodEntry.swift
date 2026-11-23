import Foundation

/// When a thing was eaten. Used for grouping the day, not for arithmetic —
/// the budget does not care which meal a calorie arrived in.
enum Meal: String, CaseIterable, Codable, Sendable, Identifiable {
    case breakfast, lunch, dinner, snack

    var id: String { rawValue }

    var label: String {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .snack: "Snack"
        }
    }

    var symbol: String {
        switch self {
        case .breakfast: "sunrise"
        case .lunch: "sun.max"
        case .dinner: "moon"
        case .snack: "carrot"
        }
    }

    var sortOrder: Int {
        switch self {
        case .breakfast: 0
        case .lunch: 1
        case .dinner: 2
        case .snack: 3
        }
    }

    /// A sensible default for the time of day, so logging lunch at one in the
    /// afternoon takes one fewer tap.
    static func suggested(at date: Date, calendar: Calendar) -> Meal {
        switch calendar.component(.hour, from: date) {
        case 4..<11: .breakfast
        case 11..<16: .lunch
        case 16..<22: .dinner
        default: .snack
        }
    }
}

/// One logged item of food.
///
/// `source` is carried because it changes how the number should be read. A
/// figure typed off a packet is not the same claim as a vision model's guess
/// at a plate, and the UI has to be able to say which it is showing. The
/// concept is explicit that estimates must be presented as estimates.
struct FoodEntry: Identifiable, Hashable, Sendable {
    enum Source: String, Codable, Sendable {
        /// Typed in by the user.
        case manual
        /// Estimated from a photograph. Not reachable yet — the photo path is
        /// gated on the accuracy spike — but the case exists so the storage
        /// format does not have to change when it lands.
        case photoEstimate
        /// Logged in another app and read out of Apple Health.
        case appleHealth
    }

    let id: UUID
    let date: Date
    let name: String
    let kilocalories: Double
    let proteinGrams: Double?
    let carbGrams: Double?
    let fatGrams: Double?
    let meal: Meal
    let source: Source
    /// The Apple Health sample this came from.
    ///
    /// Carried so a re-import can recognise its own rows exactly rather than
    /// guessing from the day and the calorie count — two identical snacks an
    /// hour apart are two entries, and a matching rule loose enough to
    /// survive an edit would merge them.
    let healthIdentifier: UUID?
    /// The app that wrote it, as Health reports it — "MyFitnessPal", "Lose
    /// It!". Shown so a number logged somewhere else is readable as such.
    let externalSourceName: String?

    init(
        id: UUID = UUID(),
        date: Date,
        name: String,
        kilocalories: Double,
        proteinGrams: Double? = nil,
        carbGrams: Double? = nil,
        fatGrams: Double? = nil,
        meal: Meal,
        source: Source = .manual,
        healthIdentifier: UUID? = nil,
        externalSourceName: String? = nil
    ) {
        self.id = id
        self.date = date
        self.name = name
        self.kilocalories = kilocalories
        self.proteinGrams = proteinGrams
        self.carbGrams = carbGrams
        self.fatGrams = fatGrams
        self.meal = meal
        self.source = source
        self.healthIdentifier = healthIdentifier
        self.externalSourceName = externalSourceName
    }

    var isEstimate: Bool { source == .photoEstimate }

    var isFromHealth: Bool { source == .appleHealth }

    var hasMacros: Bool {
        proteinGrams != nil || carbGrams != nil || fatGrams != nil
    }

    /// A copy carrying another row's figures, keeping this row's identity.
    /// Used when an entry is edited in the app that wrote it.
    func updated(from other: FoodEntry) -> FoodEntry {
        FoodEntry(
            id: id,
            date: other.date,
            name: other.name,
            kilocalories: other.kilocalories,
            proteinGrams: other.proteinGrams,
            carbGrams: other.carbGrams,
            fatGrams: other.fatGrams,
            meal: other.meal,
            source: other.source,
            healthIdentifier: other.healthIdentifier,
            externalSourceName: other.externalSourceName
        )
    }
}

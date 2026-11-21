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

    init(
        id: UUID = UUID(),
        date: Date,
        name: String,
        kilocalories: Double,
        proteinGrams: Double? = nil,
        carbGrams: Double? = nil,
        fatGrams: Double? = nil,
        meal: Meal,
        source: Source = .manual
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
    }

    var isEstimate: Bool { source == .photoEstimate }
}

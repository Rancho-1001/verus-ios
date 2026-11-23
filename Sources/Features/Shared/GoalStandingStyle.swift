import SwiftUI

/// How the three bands look.
///
/// Kept apart from `GoalStanding` itself so the thresholds stay testable
/// without SwiftUI, and gathered in one file so the month calendar, the year
/// grid and the Home tiles cannot drift into three different reds.
extension GoalStanding {

    /// The band's colour. System reds, oranges and greens rather than fixed
    /// hex values, so they shift correctly between light and dark mode and
    /// follow the accessibility settings that increase contrast.
    var color: Color {
        switch self {
        case .unknown: .secondary
        case .short: .red
        case .closing: .orange
        case .met: .green
        }
    }

    /// The wash behind a day's number in the calendar and the year grid.
    ///
    /// Deliberately faint, and faint across all three bands: the number
    /// printed on top is the thing being read, and a saturated cell wins that
    /// fight. `share` gives a little gradation inside each band, so a 14,000
    /// step day is a shade warmer than an 8,000 step one without changing
    /// what colour it is.
    func fill(share: Double) -> Color {
        guard self != .unknown else { return .primary.opacity(0.05) }
        return color.opacity(0.13 + min(max(share, 0), 1) * 0.15)
    }

    /// For a tile that wants to say its standing with more than a number.
    var tileTint: Color {
        self == .unknown ? .clear : color.opacity(0.09)
    }

    /// The colour a value is printed in. `.unknown` stays `.primary`: a day
    /// with no reading is not a bad day, and colouring it would say it was.
    var valueColor: Color {
        self == .unknown ? .primary : color
    }

    var symbol: String {
        switch self {
        case .unknown: "questionmark.circle"
        case .short: "arrow.down.circle"
        case .closing: "arrow.up.circle"
        case .met: "checkmark.circle.fill"
        }
    }

    /// Spoken, never printed.
    ///
    /// Nothing on screen says "goal met" any more — the colour says it, and
    /// a caption repeating it is a second voice agreeing with the first.
    /// This string exists for VoiceOver, where there is no colour to read,
    /// and for the roughly one man in twelve who cannot tell this app's red
    /// from its green.
    var label: String {
        switch self {
        case .unknown: "no reading"
        case .short: "under half"
        case .closing: "halfway there"
        case .met: "goal met"
        }
    }
}

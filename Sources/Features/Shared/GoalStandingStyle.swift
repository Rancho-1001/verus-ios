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
    /// This started faint, on the theory that the number printed on top is
    /// the thing being read and a saturated cell would win that fight. In
    /// use it was the wrong trade: at 0.13 to 0.28 the three bands were
    /// three pastels, and telling them apart at arm's length — which is the
    /// entire job — meant looking rather than glancing.
    ///
    /// 0.30 to 0.65 is deep enough to read as red, amber and green while
    /// still carrying black text in light mode and white text in dark.
    /// `share` keeps a little gradation inside each band, so a 14,000 step
    /// day is warmer than an 8,000 step one without changing what colour it
    /// is.
    func fill(share: Double) -> Color {
        guard self != .unknown else { return .primary.opacity(0.06) }
        return color.opacity(0.30 + min(max(share, 0), 1) * 0.35)
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

extension Color {

    /// The fill for a card sitting on the grouped background.
    ///
    /// Not `.background`. That resolves to `systemBackground`, which is
    /// **pure black in dark mode** — the same colour as the grouped page
    /// behind it, so every card in the app quietly dissolved into the
    /// background the moment a dark theme existed. `secondarySystemGrouped`
    /// is the one that is white on grey in light mode and #1C1C1E on black
    /// in dark, which is what a card wants in both.
    static let card = Color(.secondarySystemGroupedBackground)
}

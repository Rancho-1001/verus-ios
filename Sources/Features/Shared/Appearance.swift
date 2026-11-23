import SwiftUI

/// Light, dark, or whatever the phone is doing.
///
/// The app was built to follow the system and mostly still does — every
/// colour in it is a system colour or an opacity over one, which is why
/// dark mode needed a preference rather than a redesign. This exists
/// because following the phone is not always what somebody wants: a weigh-in
/// happens at six in the morning in a dark bathroom, and a screen that goes
/// white at that hour is a reason not to open the app.
enum Appearance: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// `nil` hands the decision back to iOS, which is what `.system` means.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// The one key, named once, so the root view and the settings sheet
    /// cannot drift apart over a typo.
    static let storageKey = "appearance"
}

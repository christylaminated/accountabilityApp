import SwiftUI
import Foundation
import Observation

/// The four curated themes the user picks from. Classic is monochrome — the
/// default, intentionally restrained. Sage / Berry / Midnight are color
/// options the user opts into.
///
/// Each case carries the full palette so views can derive any role
/// (background, card, accent, destructive, etc.) from the current theme
/// without per-call branching.
enum TallyTheme: String, CaseIterable, Codable, Hashable, Identifiable {
    case classic
    case sage
    case berry
    case midnight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic:  "Classic"
        case .sage:     "Sage"
        case .berry:    "Berry"
        case .midnight: "Midnight"
        }
    }

    var accent: Color         { Color(tallyHex: paletteHex.accent) }
    var background: Color     { Color(tallyHex: paletteHex.background) }
    var card: Color           { Color(tallyHex: paletteHex.card) }
    var completed: Color      { Color(tallyHex: paletteHex.completed) }
    var streak: Color         { Color(tallyHex: paletteHex.streak) }
    var textPrimary: Color    { Color(tallyHex: paletteHex.textPrimary) }
    var textSecondary: Color  { Color(tallyHex: paletteHex.textSecondary) }
    var destructive: Color    { Color(tallyHex: paletteHex.destructive) }

    private struct PaletteHex {
        var accent: String
        var background: String
        var card: String
        var completed: String
        var streak: String
        var textPrimary: String
        var textSecondary: String
        var destructive: String
    }

    private var paletteHex: PaletteHex {
        switch self {
        case .classic:
            return PaletteHex(
                accent: "1A1A1A",
                background: "FFFFFF",
                card: "F5F5F5",
                completed: "1A1A1A",
                streak: "1A1A1A",
                textPrimary: "1A1A1A",
                textSecondary: "8E8E8E",
                destructive: "D44638"
            )
        case .sage:
            return PaletteHex(
                accent: "A8B5A0",
                background: "FAF9F6",
                card: "FFFFFF",
                completed: "A8B5A0",
                streak: "8B9E82",
                textPrimary: "1A1A1A",
                textSecondary: "6B6B6B",
                destructive: "D44638"
            )
        case .berry:
            return PaletteHex(
                accent: "C4849A",
                background: "FFFAF8",
                card: "FFFFFF",
                completed: "C4849A",
                streak: "B07388",
                textPrimary: "1A1A1A",
                textSecondary: "6B6B6B",
                destructive: "D44638"
            )
        case .midnight:
            return PaletteHex(
                accent: "7B9EB8",
                background: "F8FAFB",
                card: "FFFFFF",
                completed: "7B9EB8",
                streak: "6889A0",
                textPrimary: "1A1A1A",
                textSecondary: "6B6B6B",
                destructive: "D44638"
            )
        }
    }
}

// MARK: - ThemeManager

/// Observable singleton holding the currently-selected theme. SwiftUI views
/// that read `Color.tallyAccent` / `Color.tallyCard` / the `\.tallyTheme`
/// environment value (all of which internally observe `ThemeManager.shared`)
/// re-render automatically when `current` changes.
///
/// Persisted under `UserDefaults` key `selectedTheme`. Default `.classic` so
/// the app opens monochrome — color is opt-in.
@Observable
final class ThemeManager: @unchecked Sendable {
    static let shared = ThemeManager()

    static let storageKey = "selectedTheme"
    /// Set to true once the user has been through the onboarding theme picker.
    /// Lets us skip the picker on subsequent launches.
    static let hasPickedThemeKey = "hasPickedTheme"

    var current: TallyTheme {
        didSet {
            UserDefaults.standard.set(current.rawValue, forKey: Self.storageKey)
        }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.storageKey)
            ?? TallyTheme.classic.rawValue
        self.current = TallyTheme(rawValue: raw) ?? .classic
    }

    /// Convenience setter that also records that onboarding has shown the
    /// picker (so we don't show it again next launch).
    func pick(_ theme: TallyTheme) {
        current = theme
        UserDefaults.standard.set(true, forKey: Self.hasPickedThemeKey)
    }
}

// MARK: - Color hex helper

extension Color {
    /// Decode a 6-digit RGB hex string ("1A1A1A") into a SwiftUI Color.
    /// Tolerant of a leading "#". Falls back to black on malformed input
    /// rather than crashing — palette strings are hard-coded so this is
    /// strictly belt-and-suspenders.
    init(tallyHex hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        self.init(
            red:   Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8)  & 0xFF) / 255.0,
            blue:  Double( rgb        & 0xFF) / 255.0
        )
    }
}

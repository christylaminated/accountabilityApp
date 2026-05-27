import SwiftUI
import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// The four curated themes the user picks from. Classic is monochrome — the
/// default, intentionally restrained. Sage / Berry / Midnight are color
/// options the user opts into.
///
/// Every role (accent / background / card / textPrimary / textSecondary /
/// completed / streak / destructive) carries BOTH a light-mode hex and a
/// dark-mode hex. Returned Colors are wrapped in a UIColor dynamic
/// provider so SwiftUI re-resolves them when the system's
/// `userInterfaceStyle` flips.
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

    var accent: Color        { Color(tallyAdaptive: palette.accent) }
    var background: Color    { Color(tallyAdaptive: palette.background) }
    var card: Color          { Color(tallyAdaptive: palette.card) }
    var completed: Color     { Color(tallyAdaptive: palette.completed) }
    var streak: Color        { Color(tallyAdaptive: palette.streak) }
    var textPrimary: Color   { Color(tallyAdaptive: palette.textPrimary) }
    var textSecondary: Color { Color(tallyAdaptive: palette.textSecondary) }
    var destructive: Color   { Color(tallyAdaptive: palette.destructive) }

    /// Light + dark hex strings for one role.
    struct HexPair {
        var light: String
        var dark: String
    }

    private struct Palette {
        var accent: HexPair
        var background: HexPair
        var card: HexPair
        var completed: HexPair
        var streak: HexPair
        var textPrimary: HexPair
        var textSecondary: HexPair
        var destructive: HexPair
    }

    /// Destructive renders the same coral-red in every theme, both modes —
    /// it's the warning signal, not a brand color.
    private static let destructive = HexPair(light: "D44638", dark: "D44638")

    private var palette: Palette {
        switch self {
        case .classic:
            return Palette(
                accent:        HexPair(light: "1A1A1A", dark: "F5F5F5"),
                background:    HexPair(light: "FFFFFF", dark: "000000"),
                card:          HexPair(light: "F5F5F5", dark: "1C1C1E"),
                completed:     HexPair(light: "1A1A1A", dark: "F5F5F5"),
                streak:        HexPair(light: "1A1A1A", dark: "F5F5F5"),
                textPrimary:   HexPair(light: "1A1A1A", dark: "FFFFFF"),
                textSecondary: HexPair(light: "8E8E8E", dark: "8E8E8E"),
                destructive:   Self.destructive
            )
        case .sage:
            return Palette(
                accent:        HexPair(light: "A8B5A0", dark: "A8B5A0"),
                background:    HexPair(light: "FAF9F6", dark: "1A1817"),
                card:          HexPair(light: "FFFFFF", dark: "252321"),
                completed:     HexPair(light: "A8B5A0", dark: "A8B5A0"),
                streak:        HexPair(light: "8B9E82", dark: "B8C5B0"),
                textPrimary:   HexPair(light: "1A1A1A", dark: "FAF9F6"),
                textSecondary: HexPair(light: "6B6B6B", dark: "8E8E8E"),
                destructive:   Self.destructive
            )
        case .berry:
            return Palette(
                accent:        HexPair(light: "C4849A", dark: "C4849A"),
                background:    HexPair(light: "FFFAF8", dark: "1E1818"),
                card:          HexPair(light: "FFFFFF", dark: "2A2222"),
                completed:     HexPair(light: "C4849A", dark: "C4849A"),
                streak:        HexPair(light: "B07388", dark: "D49AAE"),
                textPrimary:   HexPair(light: "1A1A1A", dark: "FFFAF8"),
                textSecondary: HexPair(light: "6B6B6B", dark: "8E8E8E"),
                destructive:   Self.destructive
            )
        case .midnight:
            return Palette(
                accent:        HexPair(light: "7B9EB8", dark: "7B9EB8"),
                background:    HexPair(light: "F8FAFB", dark: "14171A"),
                card:          HexPair(light: "FFFFFF", dark: "1F2328"),
                completed:     HexPair(light: "7B9EB8", dark: "7B9EB8"),
                streak:        HexPair(light: "6889A0", dark: "9AB8CC"),
                textPrimary:   HexPair(light: "1A1A1A", dark: "F8FAFB"),
                textSecondary: HexPair(light: "6B6B6B", dark: "8E8E8E"),
                destructive:   Self.destructive
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

// MARK: - Color hex / adaptive helpers

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

    /// Build an adaptive Color that flips between two hex strings based on
    /// the current `userInterfaceStyle`. Internally wraps a UIColor with a
    /// dynamic provider, so SwiftUI re-resolves it automatically when the
    /// system switches between light and dark mode.
    init(tallyAdaptive pair: TallyTheme.HexPair) {
        #if canImport(UIKit)
        let lightUI = UIColor(tallyHex: pair.light)
        let darkUI  = UIColor(tallyHex: pair.dark)
        self.init(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? darkUI : lightUI
        })
        #else
        self.init(tallyHex: pair.light)
        #endif
    }
}

#if canImport(UIKit)
extension UIColor {
    /// Hex-string init parallel to `Color.init(tallyHex:)` — used when we
    /// need a UIColor for dynamic-provider wrapping.
    convenience init(tallyHex hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        self.init(
            red:   CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8)  & 0xFF) / 255.0,
            blue:  CGFloat( rgb        & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}
#endif

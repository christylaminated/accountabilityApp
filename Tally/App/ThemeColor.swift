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
    /// Single-accent custom palette. The accent color comes from
    /// `ThemeManager.shared.customAccentHex`; the rest of the palette
    /// (background, card, text, etc.) is derived to keep light/dark
    /// contrast safe regardless of which accent the user picked.
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic:  "Classic"
        case .sage:     "Sage"
        case .berry:    "Berry"
        case .midnight: "Midnight"
        case .custom:   "Custom"
        }
    }

    var accent: Color {
        if self == .custom {
            return Color(tallyHex: ThemeManager.shared.customAccentHex)
        }
        return Color(tallyAdaptive: palette.accent)
    }
    var background: Color {
        if self == .custom { return TallyTheme.customBackground }
        return Color(tallyAdaptive: palette.background)
    }
    var card: Color {
        if self == .custom { return TallyTheme.customCard }
        return Color(tallyAdaptive: palette.card)
    }
    var completed: Color {
        if self == .custom {
            return Color(tallyHex: ThemeManager.shared.customAccentHex)
        }
        return Color(tallyAdaptive: palette.completed)
    }
    var streak: Color {
        if self == .custom {
            return Color(tallyHex: ThemeManager.shared.customAccentHex)
        }
        return Color(tallyAdaptive: palette.streak)
    }
    var textPrimary: Color {
        if self == .custom { return TallyTheme.customTextPrimary }
        return Color(tallyAdaptive: palette.textPrimary)
    }
    var textSecondary: Color {
        if self == .custom { return TallyTheme.customTextSecondary }
        return Color(tallyAdaptive: palette.textSecondary)
    }
    var destructive: Color {
        if self == .custom {
            return Color(tallyAdaptive: Self.destructive)
        }
        return Color(tallyAdaptive: palette.destructive)
    }
    /// Foreground color to use ON TOP of an accent-colored surface (button
    /// fill, message bubble for the current user, heatmap high-completion
    /// cells). In Classic the accent flips between near-black (light mode)
    /// and near-white (dark mode), so the on-accent color flips too. The
    /// colored themes keep this as white in both modes because their accent
    /// stays a mid-tone in both modes. Custom themes check the accent's
    /// luminance to pick a contrasting text color.
    var onAccent: Color {
        if self == .custom {
            let isLightAccent = TallyTheme.relativeLuminance(
                hex: ThemeManager.shared.customAccentHex
            ) > 0.5
            return isLightAccent
                ? Color(tallyHex: "1A1A1A")
                : Color(tallyHex: "FFFFFF")
        }
        return Color(tallyAdaptive: palette.onAccent)
    }

    // MARK: - Custom palette derivations (neutral light/dark surfaces)

    /// Custom-theme backgrounds and text reuse neutral hex values that
    /// stay readable regardless of the user's accent pick. Only the
    /// accent itself comes from `customAccentHex`.
    private static let customBackground = Color(
        tallyAdaptive: HexPair(light: "FFFFFF", dark: "0F0F0F")
    )
    private static let customCard = Color(
        tallyAdaptive: HexPair(light: "F5F5F5", dark: "1C1C1E")
    )
    private static let customTextPrimary = Color(
        tallyAdaptive: HexPair(light: "1A1A1A", dark: "FFFFFF")
    )
    private static let customTextSecondary = Color(
        tallyAdaptive: HexPair(light: "8E8E8E", dark: "8E8E8E")
    )

    /// Approximation of WCAG relative luminance. Used to decide whether
    /// text on a user-picked accent should be light or dark.
    static func relativeLuminance(hex: String) -> Double {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8)  & 0xFF) / 255.0
        let b = Double( rgb        & 0xFF) / 255.0
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

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
        var onAccent: HexPair
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
                destructive:   Self.destructive,
                // Classic is the only theme whose accent flips luminance
                // between modes, so onAccent flips too: white text on dark
                // accent (light mode), black text on light accent (dark mode).
                onAccent:      HexPair(light: "FFFFFF", dark: "1A1A1A")
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
                destructive:   Self.destructive,
                onAccent:      HexPair(light: "FFFFFF", dark: "FFFFFF")
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
                destructive:   Self.destructive,
                onAccent:      HexPair(light: "FFFFFF", dark: "FFFFFF")
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
                destructive:   Self.destructive,
                onAccent:      HexPair(light: "FFFFFF", dark: "FFFFFF")
            )
        case .custom:
            // Never reached at runtime — every color accessor
            // short-circuits before consulting `palette` when
            // self == .custom. Exists only so the switch is
            // exhaustive. Returns Classic's palette as a stand-in.
            return Palette(
                accent:        HexPair(light: "1A1A1A", dark: "F5F5F5"),
                background:    HexPair(light: "FFFFFF", dark: "000000"),
                card:          HexPair(light: "F5F5F5", dark: "1C1C1E"),
                completed:     HexPair(light: "1A1A1A", dark: "F5F5F5"),
                streak:        HexPair(light: "1A1A1A", dark: "F5F5F5"),
                textPrimary:   HexPair(light: "1A1A1A", dark: "FFFFFF"),
                textSecondary: HexPair(light: "8E8E8E", dark: "8E8E8E"),
                destructive:   Self.destructive,
                onAccent:      HexPair(light: "FFFFFF", dark: "1A1A1A")
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
    static let customAccentKey = "customAccentHex"
    /// Set to true once the user has been through the onboarding theme picker.
    /// Lets us skip the picker on subsequent launches.
    static let hasPickedThemeKey = "hasPickedTheme"

    /// Default accent for the custom theme until the user has picked one.
    /// Picked to be friendly in both light and dark mode.
    static let defaultCustomAccentHex = "9F7AEA" // muted violet

    var current: TallyTheme {
        didSet {
            UserDefaults.standard.set(current.rawValue, forKey: Self.storageKey)
        }
    }

    /// Hex string for the user-picked accent when `current == .custom`.
    /// Falls back to `defaultCustomAccentHex` if never set. Persisted to
    /// UserDefaults so the choice survives across launches.
    var customAccentHex: String {
        didSet {
            UserDefaults.standard.set(customAccentHex, forKey: Self.customAccentKey)
        }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.storageKey)
            ?? TallyTheme.classic.rawValue
        self.current = TallyTheme(rawValue: raw) ?? .classic
        self.customAccentHex = UserDefaults.standard.string(forKey: Self.customAccentKey)
            ?? Self.defaultCustomAccentHex
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

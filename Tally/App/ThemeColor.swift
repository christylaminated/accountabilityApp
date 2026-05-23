import SwiftUI
import Foundation

/// Curated accent-color presets the user can switch between in profile
/// settings. Persisted to UserDefaults via `ThemeStore`; `Color.tallyAccent`
/// reads from the singleton so the chosen color shows everywhere.
enum ThemeColor: String, CaseIterable, Codable, Hashable {
    case pink, rose, peach, amber, mint, teal, blue, indigo, purple

    /// The actual SwiftUI Color for each preset. The `.pink` value matches
    /// the historical `tallyAccent` so existing installs see no change unless
    /// the user picks a different theme.
    var color: Color {
        switch self {
        case .pink:   Color(red: 245/255, green: 166/255, blue: 193/255)
        case .rose:   Color(red: 235/255, green: 110/255, blue: 120/255)
        case .peach:  Color(red: 250/255, green: 178/255, blue: 130/255)
        case .amber:  Color(red: 240/255, green: 195/255, blue:  95/255)
        case .mint:   Color(red: 130/255, green: 200/255, blue: 160/255)
        case .teal:   Color(red:  90/255, green: 195/255, blue: 185/255)
        case .blue:   Color(red: 120/255, green: 170/255, blue: 230/255)
        case .indigo: Color(red: 135/255, green: 135/255, blue: 215/255)
        case .purple: Color(red: 180/255, green: 130/255, blue: 215/255)
        }
    }

    var displayName: String {
        switch self {
        case .pink:   "Pink"
        case .rose:   "Rose"
        case .peach:  "Peach"
        case .amber:  "Amber"
        case .mint:   "Mint"
        case .teal:   "Teal"
        case .blue:   "Blue"
        case .indigo: "Indigo"
        case .purple: "Purple"
        }
    }
}

/// In-memory singleton mirroring the user's current theme. Lets the static
/// `Color.tallyAccent` look up the current color without needing AppState in
/// scope. `AppState.setThemeColor(_:)` updates this and SwiftUI's observation
/// of AppState's own `themeColor` property triggers the visible re-render.
final class ThemeStore: @unchecked Sendable {
    static let shared = ThemeStore()

    private(set) var currentColor: ThemeColor

    private init() {
        let raw = UserDefaults.standard.string(forKey: LocalCacheKey.themeColor)
            ?? ThemeColor.pink.rawValue
        self.currentColor = ThemeColor(rawValue: raw) ?? .pink
    }

    /// Updates the in-memory color and persists the choice. Called by
    /// AppState when the user picks a theme in settings.
    func update(_ color: ThemeColor) {
        currentColor = color
        UserDefaults.standard.set(color.rawValue, forKey: LocalCacheKey.themeColor)
    }
}

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension Color {
    /// Static accessor for non-SwiftUI contexts (rare). For views, read the
    /// `\.tallyAccent` SwiftUI environment value instead — it triggers proper
    /// re-render when the theme changes.
    static var tallyAccent: Color {
        ThemeStore.shared.currentColor.color
    }

    #if canImport(UIKit)
    /// Page background. Adapts to light/dark via system color.
    static let tallyCanvas = Color(UIColor.systemGroupedBackground)

    /// Card / surface inside the canvas.
    static let tallyCard = Color(UIColor.secondarySystemGroupedBackground)

    /// Subtle separator.
    static let tallyDivider = Color(UIColor.separator)

    static let tallyHeat0 = Color(UIColor.tertiarySystemFill)
    #else
    static let tallyCanvas = Color.gray.opacity(0.08)
    static let tallyCard = Color.white
    static let tallyDivider = Color.gray.opacity(0.3)
    static let tallyHeat0 = Color.gray.opacity(0.1)
    #endif

    // Heatmap (history calendar): derived from the current accent so they
    // follow the theme too.
    static var tallyHeat1: Color { tallyAccent.opacity(0.25) }
    static var tallyHeat2: Color { tallyAccent.opacity(0.50) }
    static var tallyHeat3: Color { tallyAccent.opacity(0.75) }
    static var tallyHeat4: Color { tallyAccent }
}

// MARK: - SwiftUI environment plumbing for the accent color

/// SwiftUI environment key carrying the current theme accent. `TallyApp`
/// injects this from `appState.accentColor` so descendants that read
/// `@Environment(\.tallyAccent)` re-render reactively when the user changes
/// their theme in profile settings.
private struct TallyAccentEnvironmentKey: EnvironmentKey {
    static let defaultValue: Color = ThemeStore.shared.currentColor.color
}

extension EnvironmentValues {
    var tallyAccent: Color {
        get { self[TallyAccentEnvironmentKey.self] }
        set { self[TallyAccentEnvironmentKey.self] = newValue }
    }
}

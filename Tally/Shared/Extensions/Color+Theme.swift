import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension Color {
    /// Primary accent. Reads from `ThemeStore.shared` so the user's chosen
    /// theme is reflected everywhere. Views observing `AppState.themeColor`
    /// re-render automatically when the theme changes (the AppState mutator
    /// updates the singleton + flips the observed property in one go).
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

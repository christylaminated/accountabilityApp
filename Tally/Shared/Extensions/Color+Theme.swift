import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension Color {
    /// Warm coral — primary accent.
    static let tallyAccent = Color(red: 230/255, green: 113/255, blue: 88/255)

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

    // Heatmap (history calendar): coral with increasing opacity.
    static let tallyHeat1 = Color(red: 230/255, green: 113/255, blue: 88/255).opacity(0.25)
    static let tallyHeat2 = Color(red: 230/255, green: 113/255, blue: 88/255).opacity(0.50)
    static let tallyHeat3 = Color(red: 230/255, green: 113/255, blue: 88/255).opacity(0.75)
    static let tallyHeat4 = Color(red: 230/255, green: 113/255, blue: 88/255)
}

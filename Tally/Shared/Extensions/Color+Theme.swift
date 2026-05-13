import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension Color {
    /// Soft dusty pink — primary accent.
    static let tallyAccent = Color(red: 245/255, green: 166/255, blue: 193/255)

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

    // Heatmap (history calendar): accent pink with increasing opacity.
    static let tallyHeat1 = Color(red: 245/255, green: 166/255, blue: 193/255).opacity(0.25)
    static let tallyHeat2 = Color(red: 245/255, green: 166/255, blue: 193/255).opacity(0.50)
    static let tallyHeat3 = Color(red: 245/255, green: 166/255, blue: 193/255).opacity(0.75)
    static let tallyHeat4 = Color(red: 245/255, green: 166/255, blue: 193/255)
}

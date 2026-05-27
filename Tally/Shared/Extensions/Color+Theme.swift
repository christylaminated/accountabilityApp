import SwiftUI

// MARK: - Themed color accessors

extension Color {
    /// Accent color from the currently-selected theme.
    static var tallyAccent: Color {
        ThemeManager.shared.current.accent
    }

    /// Page background. Theme-aware — pure white in Classic, warm cream in
    /// Sage, etc. Replaces the system-grouped-background look from earlier.
    static var tallyCanvas: Color {
        ThemeManager.shared.current.background
    }

    /// Surface used for cards, rows, and elevated content. Theme-aware.
    static var tallyCard: Color {
        ThemeManager.shared.current.card
    }

    /// Subtle separator color. Derived from theme's secondary text at low
    /// opacity so it always reads as a quiet hairline against the canvas.
    static var tallyDivider: Color {
        ThemeManager.shared.current.textSecondary.opacity(0.10)
    }

    /// Primary content color (habit names, friend names, the user's name).
    static var tallyTextPrimary: Color {
        ThemeManager.shared.current.textPrimary
    }

    /// Secondary content color (timestamps, helper text, section headers).
    static var tallyTextSecondary: Color {
        ThemeManager.shared.current.textSecondary
    }

    /// Errors, warnings, overdue badges. Consistent across all themes.
    static var tallyDestructive: Color {
        ThemeManager.shared.current.destructive
    }

    /// Color applied to a completed item (checkbox fill, completed-state
    /// tint). Distinct from accent so themes can vary (e.g., classic uses
    /// the same near-black for both, sage uses sage green).
    static var tallyCompleted: Color {
        ThemeManager.shared.current.completed
    }

    /// Streak emphasis color. Slightly deeper than accent in colored themes;
    /// identical to accent in Classic.
    static var tallyStreak: Color {
        ThemeManager.shared.current.streak
    }

    // Heatmap (history calendar): derived from the current accent so they
    // follow the theme too.
    static var tallyHeat0: Color { tallyCard }
    static var tallyHeat1: Color { tallyAccent.opacity(0.25) }
    static var tallyHeat2: Color { tallyAccent.opacity(0.50) }
    static var tallyHeat3: Color { tallyAccent.opacity(0.75) }
    static var tallyHeat4: Color { tallyAccent }
}

// MARK: - SwiftUI environment plumbing

/// Carries the whole current `TallyTheme` so views can pattern-match on
/// it (e.g., to conditionally render mini-previews in different palettes).
/// Most views should just read the `Color.tally*` statics — they observe
/// `ThemeManager.shared` and re-render automatically.
private struct TallyThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue: TallyTheme = .classic
}

/// Kept for back-compat with the many views that already read
/// `@Environment(\.tallyAccent)`. New code can also read it; both stay in
/// sync because we inject it from the same `ThemeManager.current.accent`.
private struct TallyAccentEnvironmentKey: EnvironmentKey {
    static let defaultValue: Color = TallyTheme.classic.accent
}

extension EnvironmentValues {
    var tallyTheme: TallyTheme {
        get { self[TallyThemeEnvironmentKey.self] }
        set { self[TallyThemeEnvironmentKey.self] = newValue }
    }

    var tallyAccent: Color {
        get { self[TallyAccentEnvironmentKey.self] }
        set { self[TallyAccentEnvironmentKey.self] = newValue }
    }
}

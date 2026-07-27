//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ViewConstants.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - View Constants

/// Centralized visual constants used throughout TUIkit's views.
///
/// Keeping opacity values and other visual parameters in one place ensures
/// consistency and makes global adjustments easy. All values are `Double`
/// for direct use with ``Color/opacity(_:)``.
public enum ViewConstants {

    // MARK: - Focus & Selection Opacity

    /// Minimum accent opacity during focus pulsing animation (dim phase).
    ///
    /// The span to ``focusPulseMax`` has to survive quantisation: a terminal
    /// without truecolor (Apple Terminal ≤ 15 — see
    /// `Documentation/Terminal-compatibility.md`) rounds every step onto the
    /// 256-colour cube, and the old 0.35...0.50 span came out as **two**
    /// distinct colours on the default palette — a flicker rather than a
    /// breath, and visibly fewer steps than the button cap's 0.20...0.45.
    /// Widened downwards so the pulse reads as a pulse there too; the bright
    /// end stays put because it is the one the readability floor is measured
    /// against (`PaletteContrastAuditTests` fails at 0.54).
    public static let focusPulseMin: Double = 0.22

    /// Maximum accent opacity during focus pulsing animation (bright phase).
    public static let focusPulseMax: Double = 0.50

    /// Background opacity for selected (but unfocused) rows.
    public static let selectedBackground: Double = 0.25

    /// Background opacity for alternating row tinting.
    public static let alternatingRowBackground: Double = 0.15

    /// Accent opacity for focus borders and indicator caps in their dim state.
    public static let focusBorderDim: Double = 0.20

    /// Foreground opacity for disabled interactive controls.
    public static let disabledForeground: Double = 0.50

    /// Accent opacity for selection indicator bullets.
    public static let selectionIndicator: Double = 0.60

    /// Accent opacity for focused button caps pulsing bright phase.
    public static let buttonCapPulseBright: Double = 0.45

    /// Accent opacity for the background tint of a control while
    /// the cursor is hovering over it (not focused, not pressed).
    /// Sits between the static unfocused tint
    /// (``focusBorderDim`` = 0.20) and the focused max-pulse
    /// (``buttonCapPulseBright`` = 0.45) so the affordance is
    /// visible without competing with focus itself.
    public static let hoverBackground: Double = 0.32

    // MARK: - Interaction

    /// Number of rows scrolled per mouse-wheel tick in Lists,
    /// Tables, and other scrollable selection views.
    ///
    /// Matches the macOS / Windows / web default of three lines
    /// per detent — a single line per tick feels sluggish for
    /// wheel-driven scrolling. Wheel events scroll the viewport
    /// directly; they do not move the selection (the model
    /// matches Finder, Explorer, etc.).
    public static let mouseWheelScrollLines: Int = 3

    // MARK: - Default Strings

    /// Default placeholder text for empty List and Table views.
    public static let emptyListPlaceholder = "No items"
}

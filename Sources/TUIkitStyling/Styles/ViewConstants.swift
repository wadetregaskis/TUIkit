//  🖥️ TUIkit — Terminal UI Kit for Swift
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
    /// The span to ``focusPulseMax`` is bounded at the bright end by
    /// readability: this fill sits behind arbitrary row content, which keeps its
    /// own foreground, and `PaletteContrastAuditTests` measures that pair.
    ///
    /// How many *distinct* shades the span yields is a separate question and no
    /// longer this constant's problem — on a terminal without truecolor the
    /// pulse walks the rendered steps rather than sampling a continuous lerp
    /// (see `Color.pulseRamp(from:to:depth:samples:)`), so a narrow span
    /// degrades to fewer, evenly-timed shades instead of to a stutter.
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

    /// The contrast floor a framework-chosen label colour must clear against
    /// the face it is drawn on (WCAG's large-text / UI-component ratio).
    ///
    /// Named rather than repeated as a literal because it has to hold for the
    /// **disabled** state too, which is the state that had been skipping it:
    /// a colour computed against the page background but painted on a
    /// control's accent-tinted face was landing at 1.0–1.6 there, and the
    /// 256-colour cube then quantised five of the sixteen built-in palettes to
    /// a foreground and background that were the *same entry* — a disabled
    /// button that read as an empty box.
    ///
    /// Applied with ``Color/ensuringRenderedContrast(atLeast:against:)``, not
    /// the plain floor: the cube moves the FACE too, and a label that clears
    /// this against the true colour can be under it against the drawn one.
    public static let labelContrastFloor: Double = 3.0

    /// The floor for a **disabled** label, which is lower on purpose.
    ///
    /// WCAG exempts inactive components from its contrast minimum, and the
    /// reason is exactly this one: on a 256-colour terminal the cube leaves very
    /// few entries above a control's own face, and pinning both states to
    /// ``labelContrastFloor`` lands them on the SAME one — Green, Homebrew, Red,
    /// Ocean, Red Sands and Amber all drew a disabled button's label in the
    /// identical colour to an enabled one. A disabled label only has to stay
    /// legible and clearly off the face; it must not compete with the live
    /// control beside it.
    ///
    /// 2.4, which is where Green picks `#00af00` (2.71:1) instead of collapsing
    /// onto the enabled label's `#00d700` (4.07:1).
    public static let disabledLabelContrastFloor: Double = 2.4

    /// The floor between one piece of chrome and another it sits on — a
    /// scrollbar's thumb against its own track.
    ///
    /// Lower than either label floor, and deliberately: both of these are quiet
    /// by design and neither is text. What it has to guarantee is only that the
    /// two remain TELLABLE APART, at every phase of a breath — a thumb that
    /// fades to its track's colour on the way past takes the scroll position
    /// with it, which is what "the scroller goes momentarily invisible" was.
    ///
    /// 1.6, which clears the 256-colour cube's spacing between adjacent
    /// greyscale rungs without lifting the dim end of the pulse enough to stop
    /// it reading as a breath.
    public static let chromeSeparationFloor: Double = 1.6

    /// Accent opacity for selection indicator bullets.
    public static let selectionIndicator: Double = 0.60

    /// Accent opacity for the background tint of a control while
    /// the cursor is hovering over it (not focused, not pressed).
    /// Sits between the static unfocused tint
    /// (``focusBorderDim`` = 0.20) and the focused max-pulse
    /// (`buttonCapPulseBright` = 0.45) so the affordance is
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

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

    /// The least contrast between the two ENDS of a chrome breath for the
    /// breath to be seen at all.
    ///
    /// Lower again than ``chromeSeparationFloor``, and for a different reason:
    /// that one separates two things sitting side by side, and this separates
    /// one thing at two moments. What it has to beat is the 256-colour cube —
    /// two ends that quantise onto the same entry are not a breath, they are a
    /// still bar. Measured across the shipped palettes, the ones that visibly
    /// breathe sit at 1.11 and up, and the ones reported as not breathing at
    /// all sat at exactly 1.00: Ocean's accent is already `215,255,255` and one
    /// step further from the page is the same colour, and Man Page's had been
    /// pushed to black by its own track separation.
    public static let chromePulseFloor: Double = 1.15

    /// How much of the resting colour survives at the far end of a chrome
    /// breath that has nowhere to lift to — the rest being the extreme it is
    /// further from.
    ///
    /// A fixed proportion rather than another contrast walk: that walks
    /// lightness in 1% steps, and a colour already near an extreme needs a
    /// large move before its contrast changes at all, so the walk stopped short
    /// every time on exactly the palettes that needed it. Four fifths is always
    /// a visible change and never more than a breath.
    public static let chromePulseDepth: Double = 0.8

    /// The least contrast a scroll TRACK keeps against the page it sits on.
    ///
    /// A groove is meant to be quiet, not absent. 1.45 is just under the
    /// quietest the shipped profiles derived on their own (Red's 1.49), so
    /// constraining the track against the ACCENT — which moves it along the
    /// foreground-to-background line — cannot make any of them fainter than the
    /// faintest that was already shipping.
    public static let chromeGrooveFloor: Double = 1.45

    /// Accent opacity for selection indicator bullets.
    public static let selectionIndicator: Double = 0.60

    /// Accent opacity for the background tint of a control while
    /// the cursor is hovering over it (not focused, not pressed).
    /// Sits between the static unfocused tint (``focusBorderDim`` = 0.20) and
    /// the focused row-background fill (``focusPulseMax`` = 0.50), so the
    /// affordance is visible without competing with focus itself.
    ///
    /// The upper anchor used to be named as a button CAP's bright pulse, at a
    /// value neither the constant nor the name has any more: it was renamed and
    /// then deleted, and a cap is no longer bounded for readability at all — so
    /// it was never the right thing to bracket a background tint against.
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
    /// English, and the fallback only: the views resolve their default through
    /// `ViewConstants.localizedEmptyListPlaceholder` (in the umbrella module,
    /// where the localization service lives) so the one framework-owned
    /// string an empty list shows is translated like every other.
    public static let emptyListPlaceholder = "No items"
}

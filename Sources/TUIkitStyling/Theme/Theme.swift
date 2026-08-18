//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Theme.swift
//
//  Created by LAYERED.work
//  License: MIT  and palette registry.
//

// MARK: - Palette Protocol

/// A palette defines the color scheme for a TUIkit application.
///
/// Palettes provide semantic colors that views use for consistent styling.
/// TUIkit includes several predefined palettes inspired by classic terminals.
///
/// Conforms to ``Cyclable`` so it can be managed by a `ThemeManager`.
///
/// # Usage
///
/// ```swift
/// // Set the app palette
/// paletteManager.setCurrent(SystemPalette(.amber))
///
/// // Use palette colors in views
/// Text("Hello").foregroundStyle(.palette.foreground)
/// ```
public protocol Palette: Cyclable {
    // MARK: - Background Colors

    /// The app background color (darkest).
    var background: Color { get }

    /// Status bar background.
    ///
    /// Defaults to ``appHeaderBackground``: the header and the status bar are
    /// the same chrome, one strip at each end of the page, and a palette that
    /// tinted them differently read as an accident rather than a decision.
    /// State it only for a palette that genuinely wants the two ends to differ.
    var statusBarBackground: Color { get }

    /// App header background.
    ///
    /// The stated tone for the app's chrome — the status bar follows it, and it
    /// is also what ``liftedBackground`` reads as the palette's "a surface sits
    /// here" answer.
    var appHeaderBackground: Color { get }

    /// Dimming overlay background for alerts and dialogs.
    var overlayBackground: Color { get }

    // MARK: - Foreground Colors

    /// Primary text/foreground color.
    var foreground: Color { get }

    /// Secondary text color (less prominent).
    var foregroundSecondary: Color { get }

    /// Tertiary text color (even less prominent).
    var foregroundTertiary: Color { get }

    /// Quaternary text color (dimmest foreground, used for subtle UI elements like spinner tracks).
    var foregroundQuaternary: Color { get }

    // MARK: - Accent Colors

    /// Primary accent color for interactive elements.
    var accent: Color { get }

    // MARK: - Semantic Colors

    /// Color for success states.
    var success: Color { get }

    /// Color for warning states.
    var warning: Color { get }

    /// Color for error states.
    var error: Color { get }

    /// Color for informational states.
    var info: Color { get }

    // MARK: - UI Element Colors

    /// Border color for boxes, cards, etc.
    var border: Color { get }

    /// Background color for focused list/table rows.
    var focusBackground: Color { get }

    /// Text cursor color for TextField and SecureField.
    ///
    /// Defaults to `accent` if not explicitly set. Custom palettes can override
    /// this to provide a distinct cursor color independent of the accent.
    var cursorColor: Color { get }

    /// The field surface behind editable text (TextField, SecureField,
    /// TextEditor).
    ///
    /// Defaults to ``Palette/liftedBackground`` — the same surface the tab
    /// strip uses, so a field and a tab island read as the same material, and
    /// so fields stay readable on light and dark palettes alike (a fixed dark
    /// tint rendered dark-on-light fields unreadable). Custom palettes can
    /// override for a distinct field tone.
    var fieldBackground: Color { get }
}

// MARK: - Default Palette Implementation

extension Palette {
    // MARK: - Background Defaults

    public var statusBarBackground: Color { appHeaderBackground }
    public var appHeaderBackground: Color { background }
    public var overlayBackground: Color { background }

    // MARK: - Foreground Defaults

    public var foregroundSecondary: Color { foreground }
    public var foregroundTertiary: Color { foreground }
    public var foregroundQuaternary: Color { foregroundTertiary }

    // MARK: - UI Element Defaults

    public var focusBackground: Color { foregroundTertiary.opacity(0.3, over: background) }

    public var cursorColor: Color { accent }

    public var fieldBackground: Color { liftedBackground }

    /// A surface that sits ON the page and must be visible as one: the tab
    /// strip's island, the field behind editable text.
    ///
    /// ``appHeaderBackground`` when the palette gave it a value of its own, and
    /// otherwise a small step from ``background`` toward ``foreground``.
    ///
    /// The fallback is the whole point. `appHeaderBackground` itself defaults to
    /// `background`, so a palette that never overrode it — Green, Novel, Red
    /// Sands and Solid Colors among the built-ins — handed every "subtle lift"
    /// caller the page colour: fields and tab chips drew a background exactly
    /// equal to what was already there, which is the same as drawing none.
    ///
    /// Toward the FOREGROUND rather than a fixed lighten or darken, because the
    /// palettes disagree about which way is up: a light page needs its surfaces
    /// darker and a dark page needs them lighter, and the foreground is the
    /// palette's own statement of which end it lives at. It also keeps the hue,
    /// so a green page lifts to a green surface rather than a grey one.
    public var liftedBackground: Color {
        let base = background.resolve(with: self)
        let stated = appHeaderBackground.resolve(with: self)
        // Compared after DOWNSAMPLING, not in truecolour. Several palettes state
        // a header tone a hair off the page — distinct as 24-bit numbers, the
        // same cube entry on a 256-colour terminal, and therefore invisible
        // exactly where a surface most needs to be seen. Green, Novel, Red Sands
        // and Solid Colors were all in that state, and comparing raw values
        // called them "stated" and left them flat.
        if stated.downsampledToPalette256() != base.downsampledToPalette256() { return stated }

        // AWAY from the text first — a well, not a highlight. Stepping toward
        // the foreground is the obvious move and it is the wrong one: it eats
        // the very contrast the text needs, and measurably so (Novel's tertiary
        // and Red Sands' foreground both fell under the readability floor at a
        // 20% step). Away from the text, contrast can only improve.
        let text = foreground.resolve(with: self)
        let away = Color.lerp(base, Self.extreme(furthestFrom: text), phase: Self.surfaceRecess)
        if away.downsampledToPalette256() != base.downsampledToPalette256() { return away }

        // …unless the page is already AT that extreme, where there is nowhere
        // further to go. Then the surface has to come toward the text, and the
        // contrast it costs is small precisely because the page is extreme.
        return Color.lerp(base, text, phase: Self.surfaceLift)
    }

    /// Black or white, whichever `color` is further from — the direction a
    /// surface moves to get out of the text's way.
    private static func extreme(furthestFrom color: Color) -> Color {
        (color.relativeLuminance ?? 0) > 0.5 ? Color.rgb(0, 0, 0) : Color.rgb(255, 255, 255)
    }

    /// How far ``liftedBackground`` steps toward the foreground.
    ///
    /// Small enough that the surface reads as the same material as the page —
    /// the point is a boundary, not a panel — and large enough to survive the
    /// 256-colour cube, where anything finer rounds back onto the background
    /// and the lift disappears on exactly the terminal least able to spare it.
    /// 0.20 is the measured floor: at 0.14 the Novel profile's cream page and
    /// brown text still land on one cube entry.
    static var surfaceLift: Double { 0.20 }

    /// How far the recessed (away-from-text) surface steps toward its extreme.
    /// Larger than ``surfaceLift`` because it can afford to be: moving away
    /// from the text costs no contrast, and pages that are already near an
    /// extreme need a bigger push to clear the 256-colour cube at all.
    static var surfaceRecess: Double { 0.35 }

    // MARK: - Control faces

    /// The accent tint an unfocused control's face rests at — a button's fill,
    /// a picker's, a toggle's brackets.
    public var restingControlFace: Color {
        accent.opacity(ViewConstants.focusBorderDim, over: background)
    }

    /// The face while the pointer is over the control (and it is not focused).
    ///
    /// A step further into the accent than ``restingControlFace``, and — this
    /// is the part a fixed opacity cannot do — far enough that the *terminal*
    /// can show the difference. The two used to be 0.20 and 0.32, which is a
    /// clear difference in 24-bit colour and no difference at all on a
    /// 256-colour terminal for **nine of the sixteen** built-in palettes: Green,
    /// Amber, Red, Violet, Homebrew, Man Page, Novel, Ocean and Red Sands all
    /// quantised both tints onto one cube entry, so hovering those themes did
    /// nothing visible.
    ///
    /// So the tint walks toward the accent until the cube separates it, and
    /// stops at the first step that does — the smallest visible difference,
    /// rather than a louder constant that would out-shout focus on the palettes
    /// that never needed it. Compared after downsampling on every terminal, not
    /// only where the depth demands it, so a hover looks the same everywhere
    /// (the rule ``liftedBackground`` already follows, for the same reason).
    public var hoveredControlFace: Color {
        let resting = restingControlFace.resolve(with: self).downsampledToPalette256()
        var tint = ViewConstants.hoverBackground
        while tint < 1.0 {
            let candidate = accent.opacity(tint, over: background)
            if candidate.resolve(with: self).downsampledToPalette256() != resting {
                return candidate
            }
            tint += Self.hoverTintStep
        }
        // The accent itself, which is as far as this direction goes. A palette
        // whose accent cannot be told from its own 20% tint has nothing left to
        // hover with.
        return accent
    }

    /// How coarsely ``hoveredControlFace`` searches for a visible step.
    ///
    /// Fine enough that a palette needing only a nudge gets one, coarse enough
    /// that the search is a handful of iterations on a render path: the worst
    /// built-in (Homebrew's near-black green) resolves in five.
    static var hoverTintStep: Double { 0.06 }
}

extension Palette {
    /// The more readable of the palette's foreground / background on
    /// `surface`, nudged (hue-preserving) until it reaches body-text
    /// contrast (4.5:1) where possible.
    ///
    /// For text over accent-tinted fills (selections, filled indicators),
    /// where the winning side flips between dark and light palettes: a dark
    /// palette's selection fill is a deepened accent that wants the light
    /// foreground; a light palette's is a pastel that wants the dark one.
    /// Saturated mid-tone fills (Grass's amber over green) beat both sides,
    /// so the winner is then pushed toward readable via
    /// ``Color/ensuringContrast(atLeast:against:)``.
    public func readableText(on surface: Color) -> Color {
        let winner =
            foreground.contrastRatio(against: surface) >= background.contrastRatio(against: surface)
            ? foreground
            : background
        return winner.ensuringContrast(atLeast: 4.5, against: surface)
    }
}

// MARK: - Palette Registry

/// Registry of available palettes.
public struct PaletteRegistry {
    /// The classic-phosphor presets, built from ``SystemPalette/Preset``.
    ///
    /// Order: Green → Amber → Red → Violet → Blue → White
    public static let phosphorPresets: [any Palette] = SystemPalette.Preset.allCases.map { SystemPalette($0) }

    /// Recreations of the built-in macOS Terminal.app profiles, built from
    /// ``TerminalProfilePalette/Profile``.
    ///
    /// Order: Basic → Grass → Homebrew → Man Page → Novel → Ocean → Pro →
    /// Red Sands → Silver Aerogel → Solid Colors
    public static let terminalProfiles: [any Palette] = TerminalProfilePalette.Profile.allCases.map {
        TerminalProfilePalette($0)
    }

    /// All built-in palettes in cycling order: the phosphor presets first, then
    /// the Terminal.app profiles.
    public static let all: [any Palette] = phosphorPresets + terminalProfiles

    /// Finds a palette by ID.
    public static func palette(withId id: String) -> (any Palette)? {
        all.first { $0.id == id }
    }

    /// Finds a palette by name.
    public static func palette(withName name: String) -> (any Palette)? {
        all.first { $0.name == name }
    }
}

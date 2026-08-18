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
    /// ``appHeaderBackground`` when the palette stated a tone that can actually
    /// be seen against the page, and otherwise the page's own hue with its
    /// lightness stepped until it can.
    ///
    /// The fallback is the whole point. `appHeaderBackground` itself defaults to
    /// `background`, so a palette that never overrode it handed every "subtle
    /// lift" caller the page colour: fields and tab chips drew a background
    /// exactly equal to what was already there, which is the same as drawing
    /// none.
    ///
    /// **How far** is measured in ``Color/perceivedLightness`` (see
    /// ``surfaceSeparation``), not in contrast ratios and not in cube entries.
    /// A cube-entry difference is a yes/no that says nothing about size — Man
    /// Page's stated tone and Novel's derived one both cleared it while sitting
    /// ΔL\* 0.5 and 3.4 from their pages, which is to say invisibly. And a
    /// contrast *ratio* cannot judge shades of the same colour at all: it
    /// flattens at both ends of the range, scoring two plainly different
    /// near-blacks at 1.08 and two plainly different creams at 1.05.
    ///
    /// **Which way** is away from the text where there is room for it — a well,
    /// not a highlight, and moving away from the text can only improve its
    /// contrast. Where there is not (a page already at its extreme: Basic's
    /// white, Homebrew's black, Man Page's near-white cream), the surface comes
    /// toward the text instead, and stops before the text stops being readable
    /// on it.
    ///
    /// Both directions are a **lightness** step in the page's own hue, so a
    /// green page lifts to a green surface and a brick page to a brick one.
    /// Stepping toward black or white in RGB instead — which is what this did —
    /// desaturates as it goes, and on the phosphor palettes it turned the field
    /// grey.
    public var liftedBackground: Color {
        let base = background.resolve(with: self)
        let text = foreground.resolve(with: self)

        let stated = appHeaderBackground.resolve(with: self)
        if Self.isVisiblySeparate(stated, from: base) { return stated }

        // Away from the text first, then toward it. The second walk is the one
        // that can cost readability, so only it carries the guard.
        let textIsLighter = (text.perceivedLightness ?? 0) > (base.perceivedLightness ?? 0)
        if let away = Self.surface(steppingFrom: base, lighter: !textIsLighter) { return away }
        if let toward = Self.surface(steppingFrom: base, lighter: textIsLighter, readableFor: text) {
            return toward
        }
        // Nothing cleared the floor in either direction (a mid-grey page whose
        // text sits right beside it, say). The best available step still beats
        // the page colour, which is what "no surface at all" would draw.
        return Self.surface(steppingFrom: base, lighter: !textIsLighter, orBestEffort: true)
            ?? base
    }

    /// Whether `candidate` reads as a different shade from `page` — both as the
    /// palette states it and as a 256-colour terminal will paint it, since a
    /// step that survives one and not the other is invisible on half the
    /// terminals in use.
    static func isVisiblySeparate(_ candidate: Color, from page: Color) -> Bool {
        guard candidate.lightnessDifference(from: page) >= surfaceSeparation else { return false }
        return candidate.downsampledToPalette256().lightnessDifference(
            from: page.downsampledToPalette256()) >= surfaceSeparation / 2
    }

    /// Walks the page's own colour up or down in brightness until the surface
    /// is visibly separate from it.
    ///
    /// - Parameters:
    ///   - base: the page colour.
    ///   - lighter: which way to walk.
    ///   - text: when given, the colour that has to stay readable on the result
    ///     — the guard for walking *toward* the text.
    ///   - orBestEffort: return the furthest step reached even if it never
    ///     cleared the floor, rather than `nil`.
    /// - Returns: the surface, or `nil` when this direction ran out of range
    ///   (or out of readability) first.
    static func surface(
        steppingFrom base: Color, lighter: Bool, readableFor text: Color? = nil,
        orBestEffort: Bool = false
    ) -> Color? {
        var factor = 1.0
        var best: Color?
        while factor > 0, factor < Self.surfaceFactorLimit {
            factor += lighter ? surfaceStep : -surfaceStep
            let candidate = scaled(base, by: factor)
            if let text,
                text.downsampledToPalette256().contrastRatio(
                    against: candidate.downsampledToPalette256()) < ViewConstants.labelContrastFloor
            {
                break  // one step further would be unreadable; stop at what we have
            }
            best = candidate
            if isVisiblySeparate(candidate, from: base) { return candidate }
            // Saturation — every channel pinned at an end — is the only real
            // stall. A step that rounds back onto the page is NOT one: scaling
            // a channel of 5 by 1.04 lands on 5 again, and a near-black page
            // needs several steps before the arithmetic bites.
            if candidate.isSaturated(atWhite: lighter) { break }
        }
        return orBestEffort ? best : nil
    }

    /// `base` with every channel scaled by `factor` — brighter above 1, darker
    /// below.
    ///
    /// Scaling rather than mixing toward black or white, because mixing
    /// desaturates as it goes: a phosphor palette's near-black page mixed 10%
    /// toward white is grey, not dark green, and the field then reads as a hole
    /// in the theme rather than part of it. Scaling holds the channel ratios, so
    /// the surface keeps the page's hue.
    ///
    /// A page with nothing to scale (Homebrew's and Pro's pure black) is the one
    /// case that has to mix: there is no hue to preserve and no product but
    /// zero, so the step becomes a lerp toward the extreme.
    private static func scaled(_ base: Color, by factor: Double) -> Color {
        guard let (red, green, blue) = base.rgbComponents else { return base }
        func channels(_ factor: Double) -> Color {
            func channel(_ value: UInt8) -> UInt8 {
                UInt8(clamping: Int((Double(value) * factor).rounded()))
            }
            return Color.rgb(channel(red), channel(green), channel(blue))
        }

        // Brightening a page whose brightest channel is already near 255 would
        // clip it, and clipping ONE channel is what shifts the hue — Solid
        // Colors' cream came out 29° yellower. So the scaling stops at the
        // factor that just fits, and what is left of the request is delivered
        // as a blend toward white, which is what more light on a nearly-lit
        // surface actually looks like: same hue, less saturation.
        let brightest = Double(max(red, green, blue))
        if factor > 1, brightest > 0, factor * brightest > 255 {
            let fits = 255 / brightest
            return Color.lerp(channels(fits), Color.rgb(255, 255, 255), phase: 1 - fits / factor)
        }

        let scaled = channels(factor)
        guard scaled == base else { return scaled }
        // Nothing to scale at all (a pure black page): mix instead.
        return Color.lerp(
            base, factor > 1 ? Color.rgb(255, 255, 255) : Color.rgb(0, 0, 0),
            phase: min(1, abs(factor - 1)))
    }

    /// Black or white, whichever `color` is further from — the direction a
    /// colour moves to get out of another one's way.
    static func extreme(furthestFrom color: Color) -> Color {
        (color.relativeLuminance ?? 0) > 0.5 ? Color.rgb(0, 0, 0) : Color.rgb(255, 255, 255)
    }

    /// How far apart a surface and its page have to be, in
    /// ``Color/perceivedLightness``.
    ///
    /// 10 is the measured value. The palettes that read as having no surface at
    /// all sat at ΔL\* 0.5–5.9 (Man Page 0.5, Ocean 2.9, Novel 3.4, Blue 3.8),
    /// and the ones nobody complained about at 8.7–18.7 (Basic 8.7, Red Sands
    /// 9.5, Solid Colors 14.3, Homebrew 15.2, Green 18.7). 10 clears the whole
    /// first group and leaves the second where it is — and, applied as a target
    /// rather than a per-palette constant, it makes a field look like the same
    /// affordance on every theme instead of ranging from invisible to a panel.
    static var surfaceSeparation: Double { 10 }

    /// How much brighter (or darker) each step of the surface walk makes the
    /// page. Fine enough that the result overshoots the floor by little, coarse
    /// enough to terminate quickly.
    static var surfaceStep: Double { 0.04 }

    /// Where the brightening walk gives up: a surface eight times the page's own
    /// brightness has stopped being "the page, lit" whatever the arithmetic says.
    static var surfaceFactorLimit: Double { 8 }

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

    /// A foreground lifted to answer the pointer.
    ///
    /// A control with no fill of its own — a toggle, a link, a radio button —
    /// cannot answer a hover with a *face* the way a `Button` does. It draws
    /// over whatever its parent drew, so painting a background behind it is
    /// both wrong (the colour is a guess about someone else's view) and ugly.
    /// It answers with its foreground instead: the same colour, stepped AWAY
    /// from the page until the terminal can show the difference.
    ///
    /// Away from the page rather than toward the accent, for two reasons. A
    /// hover has to be visible on every palette, and the phosphor presets set
    /// `accent` to the foreground's own hue — a step toward the accent is no
    /// step at all there. And away from the page cannot be mistaken for the one
    /// thing a hover must never look like: a fade TOWARD the background, which
    /// reads as disabled. (The toggle spent a while doing exactly that, and the
    /// pointer made an enabled control look switched off.)
    ///
    /// Compared after downsampling — like ``hoveredControlFace`` and
    /// ``liftedBackground``, and for the same reason: a lift finer than the
    /// 256-colour cube is no lift at all on the terminals least able to spare
    /// one, and a hover should look the same everywhere.
    public func hoveredForeground(_ base: Color) -> Color {
        let resolved = base.resolve(with: self)
        let page = background.resolve(with: self)
        let resting = resolved.downsampledToPalette256()

        /// The first step toward `target` the cube can tell from `resolved`,
        /// or nil when that whole direction quantises back onto it.
        func stepped(toward target: Color) -> Color? {
            var phase = Self.hoverForegroundLift
            while phase < 1.0 {
                let candidate = Color.lerp(resolved, target, phase: phase)
                if candidate.downsampledToPalette256() != resting { return candidate }
                phase += Self.hoverForegroundLift
            }
            return target.downsampledToPalette256() != resting ? target : nil
        }

        // 1. Away from the page: brighter on a dark palette, darker on a light
        //    one. Contrast can only improve, so the lift can never be mistaken
        //    for the fade a disabled control gets.
        if let lifted = stepped(toward: Self.extreme(furthestFrom: page)) { return lifted }
        // 2. …unless the colour is already AT that extreme — white text on
        //    black, black on cream — where there is nowhere further to go. Then
        //    toward the accent, which lifts in hue instead of in lightness.
        if let tinted = stepped(toward: accent.resolve(with: self)) { return tinted }
        // 3. …and if the accent is that same colour again, the only direction
        //    left is toward the page. One step, so it reads as a touch rather
        //    than the fade that means "disabled" — and no built-in palette gets
        //    this far.
        return stepped(toward: page) ?? resolved
    }

    /// How coarsely ``hoveredForeground(_:)`` searches for a visible step.
    ///
    /// Coarser than ``hoverTintStep``: a fill is read as an area and a small
    /// shift registers, while a foreground is read as a few glyphs and has to
    /// move further to be noticed at all. Every built-in palette resolves in
    /// one or two steps.
    static var hoverForegroundLift: Double { 0.22 }

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

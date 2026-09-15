//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Theme.swift
//
//  Palette protocol, default implementations, environment integration,
//  and palette registry.
//
//  Created by LAYERED.work
//  License: MIT

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
///
/// # Changing a palette's colours
///
/// TUIkit keeps what it drew under one frame's palette for later frames, so it
/// has to notice when the palette changes. A palette that is `Equatable` is
/// compared by value: one edited in place — a theme editor that keeps a
/// preset's `id` while the user adjusts its colours — redraws in the new
/// colours on the next frame. A palette that is not `Equatable` is known only
/// by its ``Cyclable/id``, so if its colours can change, conform it to
/// `Equatable` or give it a new `id` whenever they do.
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

/// Defaults for every optional role on ``Palette``.
///
/// A conforming palette states the handful of colours it actually cares about
/// — ``Palette/background``, ``Palette/foreground``, ``Palette/accent`` — and
/// inherits the rest from here. The defaults are deliberately *collapsing*
/// rather than invented: each falls back to a colour the palette has already
/// named, so a two-colour palette renders coherently (everything simply reads
/// as foreground-on-background) instead of picking tones that clash with it.
/// The framework never assumes a role is distinct; it only assumes it exists.
extension Palette {
    // MARK: - Background Defaults

    /// The status bar's surface. Defaults to ``appHeaderBackground``, so the
    /// two bars that frame the screen match without a palette naming both.
    public var statusBarBackground: Color { appHeaderBackground }

    /// The app header's surface. Defaults to the page ``background``, which
    /// makes the header read as part of the page rather than as a separate
    /// band; a palette that wants a distinct chrome tone overrides it.
    public var appHeaderBackground: Color { background }

    /// The surface behind modal content — dialogs, alerts, popovers, menus.
    /// Defaults to the page ``background`` so an overlay is legible on any
    /// palette; the separation from the page comes from its border and its
    /// backdrop, not from a different fill.
    public var overlayBackground: Color { background }

    // MARK: - Foreground Defaults

    /// Text of secondary importance — captions, supporting detail. Defaults
    /// to full ``foreground``: a palette that has not named a dimmer tone gets
    /// readable text rather than a guess at one.
    public var foregroundSecondary: Color { foreground }

    /// Text of tertiary importance — placeholders, disabled labels, scrollbar
    /// tracks. Defaults to ``foreground`` for the reason
    /// ``foregroundSecondary`` does.
    public var foregroundTertiary: Color { foreground }

    /// The faintest text tier — inactive track fill, the quietest chrome.
    /// Defaults to ``foregroundTertiary``, so a palette that names three tiers
    /// gets a sensible fourth for free.
    public var foregroundQuaternary: Color { foregroundTertiary }

    // MARK: - UI Element Defaults

    /// The wash behind a focused control. Defaults to the tertiary foreground
    /// at 30% *composited over* the background rather than made translucent —
    /// terminals have no alpha, so the blend has to be resolved to a concrete
    /// cell colour (see ``Color/opacity(_:over:)``, and
    /// `Documentation/Terminal-compatibility.md` on the 256-colour cube).
    ///
    /// Over a background with no RGB (``Color/default``, or the terminal's own
    /// before it has reported it) there is no colour 30% of the way to show, so
    /// the default is the background itself.
    public var focusBackground: Color { derivedFocusBackground() }

    /// What the default `focusBackground` derives from this palette's other
    /// roles: the tertiary foreground at 30% composited over the background.
    ///
    /// The default's body, as a function a palette's own override does not
    /// replace. So it still answers "what would the default be here" for a
    /// palette that states its own `focusBackground`, or for a wrapper that
    /// forwards one.
    package func derivedFocusBackground() -> Color {
        foregroundTertiary.opacity(0.3, over: background)
    }

    /// The text caret's colour. Defaults to ``accent``, so the caret is the
    /// same hue as the rest of the palette's active-element cues.
    public var cursorColor: Color { accent }

    /// The default well: the palette's stated chrome tone when it is a *well's*
    /// worth of separation from the page, and otherwise the page stepped by
    /// `wellSeparation`.
    ///
    /// Deliberately not ``liftedBackground``, which is a plane. The two are the
    /// same material and different depths: a tab body or a header strip is a
    /// large area, where a small step reads clearly, and a field is a small one
    /// that has to announce an edge. Sharing one number made the choice between
    /// them: at a plane's step Novel's fields disappeared, and at a well's every
    /// tab body shouted.
    public var fieldBackground: Color { derivedFieldBackground() }

    /// What the default `fieldBackground` derives from this palette's other
    /// roles: the stated chrome tone when it is a well's worth of separation
    /// from the page, and otherwise the page stepped by `wellSeparation`.
    ///
    /// The default's body, as a function a palette's own override does not
    /// replace, for the reason `derivedFocusBackground()` gives.
    package func derivedFieldBackground() -> Color {
        let base = background.resolve(with: self)
        let stated = appHeaderBackground.resolve(with: self)
        if Self.isVisiblySeparate(stated, from: base, separation: Self.wellSeparation) {
            return stated
        }
        return surface(steppedFrom: base, separation: Self.wellSeparation)
    }

    /// The field surface for a field drawn on `surface` instead of on the page.
    ///
    /// On the page this is ``fieldBackground`` itself — including any tone the
    /// palette stated for its chrome. Anywhere else it is a well stepped off
    /// whatever is actually behind the field, because the palette's one answer
    /// is the page's answer, and a container that already took a step would
    /// hand the field its own colour back.
    public func fieldBackground(on surface: Color) -> Color {
        let page = background.resolve(with: self)
        let resolved = surface.resolve(with: self)
        guard resolved != page else { return fieldBackground }
        return self.surface(steppedFrom: resolved, separation: Self.wellSeparation)
    }

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
    /// `planeSeparation`), not in contrast ratios and not in cube entries.
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
        let stated = appHeaderBackground.resolve(with: self)
        // The palette's own opinion wins when it can be seen — but it is an
        // opinion about a COLOUR, not about what a coarse terminal will make of
        // it, and on a 256-colour one several palettes' chrome tone quantises
        // to a saturated corner. Held to the same quiet standard as a derived
        // step (see `quietest`).
        if Self.isVisiblySeparate(stated, from: base, separation: Self.planeSeparation) {
            return Self.quietest(stated, steppedFrom: base, separation: Self.planeSeparation)
        }
        return surface(steppedFrom: base, separation: Self.planeSeparation)
    }

    /// The same step, taken from an arbitrary surface rather than from the page
    /// — what a control drawn INSIDE another surface needs.
    ///
    /// ``liftedBackground`` answers "a surface on the page", and a `TextField`
    /// asking that question while sitting in a `TabView`'s body got the tab's
    /// own colour back: the two surfaces are one step off the page each, which
    /// is to say the same step, and the field vanished into the tab. Stepping
    /// from what is actually behind the control keeps the field a field
    /// wherever it is put.
    public func lifted(from base: Color) -> Color {
        surface(steppedFrom: base.resolve(with: self), separation: Self.planeSeparation)
    }

    /// Which way this palette's surfaces climb: `true` when a surface is
    /// *lighter* than what it sits on.
    ///
    /// Decided ONCE, for the whole palette, and that is the point. Deciding it
    /// per surface — "away from the text, from wherever I am" — makes the
    /// ladder fold back on itself: on a dark theme the tab body steps lighter
    /// (its page has no room to go darker), and then a field inside that body,
    /// asking the same question from its new position, steps *darker* and lands
    /// back on the page colour. Which is exactly what it looked like: a hole
    /// punched through the tab, on ten of the sixteen built-in palettes.
    ///
    /// Three rules, in order:
    ///
    /// 1. The palette's own **stated chrome tone**, when it has a visible
    ///    opinion. `appHeaderBackground` is where a palette says which way its
    ///    chrome sits; a derivation that ran the other way would cross back
    ///    over the page between rungs.
    /// 2. Otherwise **away from the text**, where the page has room for it — a
    ///    well, not a highlight, and moving away from the text can only improve
    ///    its contrast.
    /// 3. Otherwise **toward the text** (a page already at its extreme: Basic's
    ///    white, Homebrew's black, Man Page's near-white cream), where the walk
    ///    itself stops before the text stops being readable.
    var surfacesRunLighter: Bool {
        let page = background.resolve(with: self).perceivedLightness ?? 0
        let stated = appHeaderBackground.resolve(with: self).perceivedLightness ?? page
        if abs(stated - page) >= Self.planeSeparation { return stated > page }
        let text = foreground.resolve(with: self).perceivedLightness ?? 0
        let awayIsLighter = text <= page
        // "Room" in the same units as the step: how much L\* is left between
        // the page and the end of the range in that direction.
        let room = awayIsLighter ? 100 - page : page
        return room >= Self.planeSeparation ? awayIsLighter : !awayIsLighter
    }

    /// One rung of the ladder: `base` stepped by `separation` in the palette's
    /// surface direction, in `base`'s own hue.
    ///
    /// The direction is a preference; *not looking like the page* is the
    /// invariant. Where the preferred direction runs out — a 256-colour
    /// terminal derives Red's field by brightening a dark red until the cube
    /// can tell it apart, and the light text on it stops being readable first —
    /// the other direction is taken instead, but only if it lands somewhere
    /// that is still visibly not the page.
    func surface(steppedFrom base: Color, separation: Double) -> Color {
        let lighter = surfacesRunLighter
        let text = foreground.resolve(with: self)
        let page = background.resolve(with: self)

        /// Only a walk that moves TOWARD the text can cost readability, and
        /// only that one carries the guard.
        func guardText(_ lighter: Bool) -> Color? {
            let towardText =
                lighter == ((text.perceivedLightness ?? 0) > (base.perceivedLightness ?? 0))
            return towardText ? text : nil
        }

        if let preferred = Self.surfaceWalk(
            from: base, lighter: lighter, separation: separation,
            readableFor: guardText(lighter))
        {
            return Self.quietest(preferred, steppedFrom: base, separation: separation)
        }
        if base != page,
            let other = Self.surfaceWalk(
                from: base, lighter: !lighter, separation: separation,
                readableFor: guardText(!lighter)),
            Self.isVisiblySeparate(other, from: page, separation: separation)
        {
            return Self.quietest(other, steppedFrom: base, separation: separation)
        }
        // Best-effort rather than `base`: a step that fell short of the floor
        // still beats handing back the colour that is already there, which is
        // what "no surface at all" would draw.
        guard
            let best = Self.surfaceWalk(
                from: base, lighter: lighter, separation: separation,
                readableFor: guardText(lighter), orBestEffort: true)
        else { return base }
        return Self.quietest(best, steppedFrom: base, separation: separation)
    }

    /// The quieter of a hue-preserving step and a neutral one, when the
    /// terminal's palette makes the hue-preserving step shout.
    ///
    /// ``surfaceWalk`` scales the base colour, which keeps its hue — the right
    /// thing on a terminal that paints what it is given. On a 256-colour one it
    /// is the reason a dark theme's tab body came out as a solid block of its
    /// own hue: the cube's darkest coloured rung is 0x5F, so a walk that stays
    /// in a near-black green has nowhere to land but `(0, 95, 0)`, three times
    /// the step that was asked for. Amber was worse — its walk landed on
    /// `(95, 0, 0)`, a red surface on an amber theme — because the cube's
    /// nearest coloured entry to a dark brown is not brown.
    ///
    /// The greyscale ramp has 24 rungs where the colour cube has 6, so a
    /// neutral of the right lightness is available where a hued one is not.
    /// It is taken only when it is genuinely quieter: the hue-preserving step
    /// must overshoot (more than twice the separation asked for, once the
    /// terminal has quantised it) and the neutral must still clear the floor.
    /// On a truecolor terminal nothing overshoots and this never fires, so the
    /// hue is kept wherever it can be shown.
    static func quietest(
        _ preferred: Color, steppedFrom base: Color, separation: Double
    ) -> Color {
        guard ColorDepth.current < .truecolor else { return preferred }
        let quantisedBase = base.downsampledToPalette256()
        let quantisedPreferred = preferred.downsampledToPalette256()
        let overshoot = quantisedPreferred.lightnessDifference(from: quantisedBase)

        /// How saturated a colour is, in the crudest useful sense: the spread
        /// between its strongest and weakest channel.
        func spread(_ colour: Color) -> Int {
            guard let rgb = colour.rgbComponents else { return 0 }
            let channels = [Int(rgb.red), Int(rgb.green), Int(rgb.blue)]
            return (channels.max() ?? 0) - (channels.min() ?? 0)
        }

        // Two ways the cube can shout. It can overshoot in LIGHTNESS — a
        // near-black green landing on `(0, 95, 0)`. Or it can invent SATURATION
        // the page never had, which is how an amber theme's tab body came out
        // red: `(10, 8, 5)` is barely tinted, and the cube's nearest coloured
        // entry to it is a corner. Half a cube rung of new spread is enough to
        // call that.
        let inventedChroma = spread(quantisedPreferred) - spread(quantisedBase) > 48
        guard overshoot > separation * 2 || inventedChroma else { return preferred }

        // A grey of the base's own lightness, walked the same way the hued step
        // was — so it clears the same floor rather than landing wherever the
        // hued step happened to. Amber found this: a neutral at the hued step's
        // lightness was still too dark to separate from its page.
        let baseLightness = base.perceivedLightness ?? 0
        let level = UInt8(max(0, min(255, (baseLightness / 100) * 255)))
        // Carrying `base`'s alpha, because this grey is a stand-in for the page and
        // `scaled` carries the alpha of whatever it stepped FROM. Built opaque, the
        // neutral branch handed back an opaque surface where the hued branch carried
        // one — the two answers to the same question disagreeing about a third thing.
        let greyBase = Color.rgb(level, level, level).carryingAlpha(of: base)
        let lighter = (preferred.perceivedLightness ?? baseLightness) > baseLightness
        guard
            let neutral = surfaceWalk(
                from: greyBase, lighter: lighter, separation: separation),
            isVisiblySeparate(neutral, from: base, separation: separation)
        else { return preferred }
        let quantisedNeutral = neutral.downsampledToPalette256()
        let neutralOvershoot = quantisedNeutral.lightnessDifference(from: quantisedBase)
        let quieter =
            inventedChroma
            ? spread(quantisedNeutral) < spread(quantisedPreferred)
            : neutralOvershoot < overshoot
        return quieter ? neutral : preferred
    }

    /// Whether `candidate` reads as a different shade from `page` — measured in
    /// the colours this terminal will actually paint.
    ///
    /// On a terminal that paints what it is given, the step IS the step. On one
    /// that snaps everything to the 6×6×6 cube, a step finer than the cube is
    /// no step at all, so the walk has to keep going until the cube separates
    /// the two — and in dark saturated hues, where the cube's rungs are 95
    /// apart, that costs a much bigger jump. Asking for the cube's jump on
    /// **every** terminal is what made a field inside a dark tab body come out
    /// three times the intended step: a bright green block, on a theme whose
    /// whole point is that it is nearly black.
    ///
    /// So this one is depth-aware, where ``hoveredControlFace`` deliberately is
    /// not. A hover's tint is small and its consistency across terminals is
    /// worth more than the fidelity; a surface's overshoot is a large area of
    /// the wrong colour, and surfaces cannot look the same on both terminals
    /// anyway — the cube moves the page too.
    static func isVisiblySeparate(
        _ candidate: Color, from page: Color, separation: Double
    ) -> Bool {
        guard candidate.lightnessDifference(from: page) >= separation else { return false }
        guard ColorDepth.current < .truecolor else { return true }
        return candidate.downsampledToPalette256().lightnessDifference(
            from: page.downsampledToPalette256()) >= separation / 2
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
    static func surfaceWalk(
        from base: Color, lighter: Bool, separation: Double, readableFor text: Color? = nil,
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
            if isVisiblySeparate(candidate, from: base, separation: separation) {
                return candidate
            }
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
    ///
    /// The result carries `base`'s alpha: a surface derived from a translucent page is
    /// translucent, one wash all the way down. §39.
    private static func scaled(_ base: Color, by factor: Double) -> Color {
        // Every exit through one `carryingAlpha(of: base)`: a surface derived from a
        // translucent page is translucent, and the arithmetic in between works on the
        // three channels that exist. The three-tuple is why this has to be said HERE
        // rather than relied upon — `rgbComponents` has no fourth element, so nothing
        // below could carry the alpha even by accident, and `Color.lerp` (which does
        // carry it, as a fourth channel) would interpolate it toward an opaque extreme
        // and land on a value that is neither the page's nor opaque. That is §28.1's
        // alpha-184 hover lift, and one exit is what keeps it from recurring here.
        stepping(base, by: factor).carryingAlpha(of: base)
    }

    /// The lightness step itself, on the three channels that exist.
    ///
    /// Its alpha is meaningless — every return builds a fresh opaque colour, or a
    /// `lerp` between two of them — and ``scaled(_:by:)`` supplies the real one.
    private static func stepping(_ base: Color, by factor: Double) -> Color {
        guard let (red, green, blue) = base.rgbComponents else { return base }
        func stepped(_ factor: Double) -> (red: UInt8, green: UInt8, blue: UInt8) {
            func channel(_ value: UInt8) -> UInt8 {
                UInt8(clamping: Int((Double(value) * factor).rounded()))
            }
            return (channel(red), channel(green), channel(blue))
        }
        func channels(_ factor: Double) -> Color {
            let channels = stepped(factor)
            return Color.rgb(channels.red, channels.green, channels.blue)
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

        let walked = stepped(factor)
        // Asked of the CHANNELS, not of the two `Color`s. `Color` is `Hashable` over
        // its value AND its alpha, so `scaled == base` answered "different" for two
        // colours that are the same colour, and this branch — the one case that has
        // to mix — was then never reached:
        //
        //   * a page at `.rgb(0, 0, 0).opacity(0.5)`, because `channels` builds an
        //     opaque colour and 255 != 128;
        //   * a page at `.ansi(.black)`, because the rebuilt one is `.rgb`, so the
        //     CASE differs even at full opacity.
        //
        // In both, every surface came back as the page colour itself, which this
        // function's own note calls "the same as drawing none" — a field, a tab body
        // and a well all invisible, after 175 futile steps of `surfaceWalk` each.
        guard walked == (red, green, blue) else {
            return Color.rgb(walked.red, walked.green, walked.blue)
        }
        // Nothing to scale at all (a pure black page): mix instead. From the
        // channels rather than from `base`, so this exit's alpha is as meaningless as
        // the others' and its caller supplies the only one that means anything.
        return Color.lerp(
            Color.rgb(red, green, blue),
            factor > 1 ? Color.rgb(255, 255, 255) : Color.rgb(0, 0, 0),
            phase: min(1, abs(factor - 1)))
    }

    /// Black or white, whichever `color` is further from — the direction a
    /// colour moves to get out of another one's way.
    ///
    /// Judged in ``Color/perceivedLightness``, like every other "which of these
    /// is lighter" question in this file. A relative-luminance threshold reads
    /// the middle of the range wrongly: Silver Aerogel's `#929292` page is
    /// plainly a light grey (L\* 61) and luminance calls it dark (0.29), so the
    /// hover lift walked TOWARD the page instead of away from it — dimming the
    /// affordance it exists to brighten, and on a light palette erasing it.
    static func extreme(furthestFrom color: Color) -> Color {
        (color.perceivedLightness ?? 0) > 50 ? Color.rgb(0, 0, 0) : Color.rgb(255, 255, 255)
    }

    /// How far a **plane** sits from what is behind it, in
    /// ``Color/perceivedLightness`` — a tab body, a header strip, an island.
    ///
    /// Half a well's step, because a plane is a large area and a large area
    /// needs less of a difference to read as one: more of it lands on the
    /// retina, and its edges run beside the thing they are being compared with.
    /// At a well's step the tab bodies stopped reading as the same page and
    /// started reading as panels.
    ///
    /// 5 also keeps the stated tones of the palettes that have an opinion about
    /// their chrome — Novel 5.9, Red Sands 5.7, Silver Aerogel 5.8, Grass and
    /// Ocean 6.9, Solid Colors 7.0, Basic 8.7, Homebrew and Pro 16.6 — while
    /// still deriving one for the phosphor presets (2.5–4.5) and Man Page
    /// (1.8), which is where the missing-surface reports came from.
    static var planeSeparation: Double { 5 }

    /// How far a **well** sits from what is behind it, in
    /// ``Color/perceivedLightness`` — the field behind editable text.
    ///
    /// 10 is the measured value. The fields that read as no field at all sat at
    /// ΔL\* 0.5–5.9 (Man Page 0.5, Ocean 2.9, Novel 3.4/5.9, Blue 3.8), and the
    /// ones nobody complained about at 8.7–18.7 (Basic 8.7, Red Sands 9.5,
    /// Solid Colors 14.3, Homebrew 15.2, Green 18.7). 10 clears the whole first
    /// group and leaves the second where it is — and, applied as a target
    /// rather than a per-palette constant, it makes a field look like the same
    /// affordance on every theme instead of ranging from invisible to a panel.
    static var wellSeparation: Double { 10 }

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
    ///
    /// When the accent or the background has no RGB (``Color/default``, or a
    /// colour of the terminal's own that it has not reported), no 20% tint can be
    /// mixed, and the face is the background itself.
    public var restingControlFace: Color {
        accent.opacity(ViewConstants.focusBorderDim, over: background)
    }

    /// Whether a tint of the accent over the page can be measured: both have RGB.
    ///
    /// A control that answers the pointer with a fill mixes the accent into the
    /// page. Where either has no RGB (`Color.default`, or a colour of the
    /// terminal's own that it has not reported), that mix has no RGB between its
    /// ends: every share of it is the page or the whole accent (Opacity as
    /// composition §75), so no tint of it can be checked for a visible step, nor
    /// a label on it for contrast.
    package var accentTintIsMeasurable: Bool {
        accent.resolve(with: self).rgbComponents != nil
            && background.resolve(with: self).rgbComponents != nil
    }

    /// A label's ink under the pointer, on a control whose hover is a fill: a
    /// standard button's or a menu picker's face, a menu row's wash.
    ///
    /// Where the accent tint measures, the fill shows the hover and the ink is
    /// left as it is. Where it does not, the fill is the page and shows nothing,
    /// so the ink is lifted instead (``hoveredForeground(_:)``). Opacity as
    /// composition §82.
    package func hoveredLabel(_ ink: Color) -> Color {
        accentTintIsMeasurable ? ink : hoveredForeground(ink)
    }

    /// A glyph's ink under the pointer, where the hover draws the glyph in the
    /// accent tint over the page: a Stepper's or a Slider's arrows.
    ///
    /// The tint, where it measures. Where it does not it is the page, which on
    /// the terminal's own page the foreground slot spells as 39, so the glyph's
    /// `resting` ink is lifted instead (``hoveredForeground(_:)``). Opacity as
    /// composition §82.
    package func hoveredGlyph(resting: Color) -> Color {
        accentTintIsMeasurable
            ? accent.opacity(ViewConstants.hoverBackground, over: background)
            : hoveredForeground(resting)
    }

    /// The face while the pointer is over the control.
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
    /// So the tint walks toward the accent until the cube separates it —
    /// compared after downsampling on every terminal, not only where the depth
    /// demands it, so a hover looks the same everywhere (the rule
    /// ``liftedBackground`` already follows, for the same reason).
    ///
    /// It walks `hoverSeparationSteps` distinguishable entries rather than
    /// stopping at the first. The first is what the *terminal* can show; it was
    /// not what a *person* notices, which is what "the highlight effect for
    /// mouse hover is a bit too subtle" was about. Counting cube entries rather
    /// than raising the opacity keeps the adaptive property that mattered: a
    /// palette with a coarse accent ramp still gets exactly two visible steps,
    /// and one with a fine ramp does not get a shout.
    ///
    /// When the accent or the page has no RGB components (``Color/default``, or
    /// a colour of the terminal's own that it has not reported), this is
    /// ``restingControlFace``. The terminal decides what such a colour paints,
    /// so no tint of it can be checked for a visible step, nor the label on it
    /// for contrast.
    public var hoveredControlFace: Color {
        // Not left to the walk finding nothing. A blend with an unmeasurable side has
        // no RGB between its ends, so every tint below is one end or the other: the
        // page, or the whole accent. Whichever end the blend picks, the walk could
        // only stay at rest or jump to a solid accent under a label nobody can check,
        // and the second is not a hover.
        guard accentTintIsMeasurable else { return restingControlFace }
        let resting = restingControlFace.resolve(with: self).downsampledToPalette256()
        var distinct: [Color] = []
        var furthest: Color?
        var tint = ViewConstants.hoverBackground
        while tint < 1.0 {
            let candidate = accent.opacity(tint, over: background)
            let quantised = candidate.resolve(with: self).downsampledToPalette256()
            if quantised != resting, !distinct.contains(quantised) {
                distinct.append(quantised)
                furthest = candidate
                if distinct.count >= Self.hoverSeparationSteps { return candidate }
            }
            tint += Self.hoverTintStep
        }
        // Ran out of room: the furthest visibly-different tint found — or, when
        // there was none, the accent SPENT against the page, the ground
        // `restingControlFace` composites over (§21.1). This was the one exit of
        // either face that did not composite: it returned the raw accent, so at
        // `.tint(.clear)` merely pointing at a button put a transparent colour into
        // the caps' emitter. An opaque accent comes back untouched, spelling and
        // all (§29.1). A palette whose accent cannot be told from its own 20% tint
        // has nothing left to hover with (§49).
        return furthest ?? accent.spendingAlpha(over: background)
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
    ///
    /// A colour the terminal decides is not stepped in RGB: a slot
    /// (``Color/ansi(_:)``), a 256-colour index below 16, or ``Color/default``.
    /// A step in RGB would re-spell a name the user's terminal profile keeps as
    /// a triple the profile does not. It climbs a ladder of names instead: a
    /// standard slot to its bright twin (``ANSIColor/brightTwin``), a bright
    /// slot to the terminal's default foreground, SGR 39, which has no rung
    /// above it and comes back unchanged. While the terminal has not reported
    /// the colours involved, the first rung spelled differently is taken. Once
    /// it has, the first rung that is visibly different and no harder to read
    /// against the page is taken, or none.
    ///
    /// An RGB ink on a page with no RGB components (``Color/default``, or the
    /// terminal's own page before it has reported it) comes back unchanged:
    /// there is no lightness to step away from, and no way to tell whether a
    /// step would show.
    public func hoveredForeground(_ base: Color) -> Color {
        let resolved = base.resolve(with: self)
        let page = background.resolve(with: self)
        // A colour the terminal decides climbs its ladder of names, measured or not.
        // The walk below lerps toward RGB: a reported slot came back as a triple the
        // user's profile does not keep, and an unreported one came back unchanged,
        // which on a control whose fill cannot be measured either was no hover at all.
        if resolved.isTerminalDefined { return resolved.hoverLadderLift(over: page) }
        // An RGB ink needs a measured page, or no lift. An unmeasured page read as
        // lightness 0 in `extreme(furthestFrom:)`, so the walk lifted toward RGB white
        // whatever the terminal paints, invisibly on a light one.
        guard resolved.rgbComponents != nil, page.rgbComponents != nil else { return resolved }
        let resting = resolved.downsampledToPalette256()

        /// The step toward `target` that is `hoverSeparationSteps`
        /// distinguishable cube entries away from `resolved`, or the furthest
        /// one this direction reaches, or nil when the whole direction
        /// quantises back onto it.
        ///
        /// The extra steps are a preference, not a requirement: a candidate is
        /// only taken past the first if it is no HARDER to read against the
        /// page than the first was. Walking away from the page (the usual
        /// case) can only improve that, so it always gets its full travel;
        /// walking toward the accent or the page is where a second step could
        /// make a hovered label dimmer than the minimum-visible version
        /// already was, and it is refused there. Silver Aerogel found this:
        /// its foreground is already at the extreme, so its lift is a hue
        /// step, and two of them took a label to 1.99:1.
        func stepped(toward target: Color) -> Color? {
            var distinct: [Color] = []
            var best: Color?
            var floor = 0.0
            var phase = Self.hoverForegroundLift
            while phase < 1.0 {
                let candidate = Color.lerp(resolved, target, phase: phase)
                let quantised = candidate.downsampledToPalette256()
                if quantised != resting, !distinct.contains(quantised) {
                    let contrast = quantised.contrastRatio(against: page)
                    if best == nil {
                        // The first visible step sets the bar the rest must clear.
                        floor = contrast
                        best = candidate
                    } else if contrast >= floor {
                        best = candidate
                    } else {
                        return best
                    }
                    distinct.append(quantised)
                    if distinct.count >= Self.hoverSeparationSteps { return best }
                }
                phase += Self.hoverForegroundLift
            }
            if best == nil, target.downsampledToPalette256() != resting { return target }
            return best
        }

        // 1. Away from the page: brighter on a dark palette, darker on a light
        //    one. Contrast can only improve, so the lift can never be mistaken
        //    for the fade a disabled control gets.
        // 2. …unless the colour is already AT that extreme — white text on
        //    black, black on cream — where there is nowhere further to go. Then
        //    toward the accent, which lifts in hue instead of in lightness.
        // 3. …and if the accent is that same colour again, the only direction
        //    left is toward the page. One step, so it reads as a touch rather
        //    than the fade that means "disabled" — and no built-in palette gets
        //    this far.
        let lifted =
            stepped(toward: Self.extreme(furthestFrom: page))
            ?? stepped(toward: accent.resolve(with: self))
            ?? stepped(toward: page)
            ?? resolved
        // A hover lift is a re-SPELLING — the same ink, written a step further
        // from the page — so it ends in `carryingAlpha`, exactly as
        // ``Color/ensuringContrast(atLeast:against:)`` does.
        //
        // It did not, and the number that came out was the tell: a translucent
        // base at alpha 128 came back at **184**. Neither carried (128) nor spent
        // (255), because both arms of `stepped(toward:)` lose the alpha in a
        // different way — `Color.lerp` interpolates it as a fourth channel toward
        // an opaque target, and the `best == nil` fallback returns that target
        // outright. So `.tint(.red.opacity(0.5))` was half-restored by the mere
        // presence of the pointer, and then tripped the emitter's assertion in
        // whichever control drew the label two frames later.
        //
        // Carried and not composited, deliberately: compositing here would spend
        // the alpha against a ground this function had to *guess*, where carrying
        // leaves it for the composite that knows the real one.
        return lifted.carryingAlpha(of: resolved)
    }

    /// How coarsely ``hoveredForeground(_:)`` searches for a visible step.
    ///
    /// Coarser than ``hoverTintStep``: a fill is read as an area and a small
    /// shift registers, while a foreground is read as a few glyphs and has to
    /// move further to be noticed at all. Every built-in palette resolves in
    /// one or two steps.
    static var hoverForegroundLift: Double { 0.22 }

    /// How many *distinguishable* steps a hover moves away from rest.
    ///
    /// One is the least the terminal can show and the least that can be
    /// guaranteed on a coarse palette; it is not what a person notices when the
    /// thing under the pointer is a few cells of a busy page. Two is, and it
    /// still adapts — a palette needing a large opacity change to cross one cube
    /// entry gets a large one, and a palette needing a nudge gets two nudges
    /// rather than a shout.
    static var hoverSeparationSteps: Int { 2 }

    /// How coarsely ``hoveredControlFace`` searches for a visible step.
    ///
    /// Fine enough that a palette needing only a nudge gets one, coarse enough
    /// that the search is a handful of iterations on a render path: the worst
    /// built-in (Homebrew's near-black green) resolves in five.
    static var hoverTintStep: Double { 0.06 }
}

extension Palette {
    /// The two ends a focus pulse breathes between, for a mark drawn in the
    /// accent over the page.
    ///
    /// One definition, in one place, because the two ends have to agree three
    /// ways at once: with the colour the view *draws*, with the endpoints the
    /// ``AnimatedCellRun`` that replays it is built from — a run made from a
    /// different pair jumps the moment the run loop takes over from the render
    /// — and with every other pulsing control on screen, which is the only
    /// reason a pulse reads as one property of the UI rather than as several
    /// controls that happen to blink.
    ///
    /// Over ``background`` specifically: ``Color/opacity(_:)`` alone fades
    /// toward black, which on a light palette is not a dimmer accent but a
    /// different colour.
    ///
    /// - Parameter surface: What the mark is drawn over, when that is not the
    ///   page — a filled row, a well. The dim end is blended toward it, so the
    ///   pulse stays a pulse of the accent rather than a fade toward the page's
    ///   colour somewhere the page is not.
    public func accentPulse(over surface: Color? = nil) -> (dim: Color, bright: Color) {
        // Both ends spend a translucent tint's alpha against the same stated
        // ground — `Color.breathEnds(dimmedTo:over:)` is where that rule and the
        // reason an opaque colour must not be re-spelled both live, shared with
        // the three other pulse pairs that had each got it wrong differently.
        accent.breathEnds(dimmedTo: ViewConstants.focusPulseMin, over: surface ?? background)
    }

    /// The two ends a focus pulse breathes between, for a FILL that content is
    /// drawn on top of — a selected row's background, a highlighted date cell,
    /// a dragging split-view divider.
    ///
    /// The dim end is the same; the bright end stops at ``ViewConstants/focusPulseMax``
    /// rather than reaching the accent, and that is the whole difference between
    /// the two. A fill carries arbitrary foreground content that keeps its own
    /// colour, so the bright end is bounded by what that content stays readable
    /// against — the pair `PaletteContrastAuditTests` measures. A mark drawn IN
    /// the accent has nothing on top of it and can go all the way.
    ///
    /// When the accent or the ground has no RGB (``Color/default``, or a colour of
    /// the terminal's own that it has not reported), neither end can be mixed, and
    /// both are the bright one. For an opaque accent that is the accent: the bright
    /// end is exactly half, and a blend with such a side keeps the colour at half.
    /// Mixed, the dim end at 22% would be the ground itself, and the fill would blink
    /// between the page and a solid accent; held, it is still, and leaves no run.
    /// ``accentPulse(over:)`` holds its bright end the same way, through
    /// ``Color/breathEnds(dimmedTo:over:)``. A translucent accent's own alpha counts
    /// toward the half, so one fainter than that holds the ground.
    ///
    /// - Parameter surface: What the fill sits on, when that is not the page.
    public func accentFillPulse(over surface: Color? = nil) -> (dim: Color, bright: Color) {
        let ground = surface ?? background
        let bright = accent.opacity(ViewConstants.focusPulseMax, over: ground)
        // `Color.breathEnds(dimmedTo:over:)`'s rule for a side with no RGB, applied to
        // this pair's own bright end, which stops short of the accent.
        guard accent.rgbComponents != nil, ground.rgbComponents != nil else { return (bright, bright) }
        return (accent.opacity(ViewConstants.focusPulseMin, over: ground), bright)
    }
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
    ///
    /// On a surface with no RGB components (``Color/default``, or the
    /// terminal's own background before it has reported it) this is
    /// `foreground`, unchanged: neither side can be measured against it, so
    /// neither is chosen or floored for it.
    public func readableText(on surface: Color) -> Color {
        // Said outright rather than left to the tie below, where both ratios are 0
        // and `>=` happens to pick the foreground.
        guard surface.rgbComponents != nil else { return foreground }
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
    /// ``AppleTerminalPalette/Profile``.
    ///
    /// Order: Basic → Grass → Homebrew → Man Page → Novel → Ocean → Pro →
    /// Red Sands → Silver Aerogel → Solid Colors
    public static let appleTerminalProfiles: [any Palette] = AppleTerminalPalette.Profile.allCases.map {
        AppleTerminalPalette($0)
    }

    /// All built-in palettes in cycling order: the phosphor presets first, then
    /// the Terminal.app profiles.
    public static let all: [any Palette] = phosphorPresets + appleTerminalProfiles

    /// Finds a palette by ID.
    public static func palette(withId id: String) -> (any Palette)? {
        all.first { $0.id == id }
    }

    /// Finds a palette by name.
    public static func palette(withName name: String) -> (any Palette)? {
        all.first { $0.name == name }
    }
}

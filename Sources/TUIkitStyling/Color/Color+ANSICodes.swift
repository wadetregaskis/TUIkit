//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Color+ANSICodes.swift
//
//  A colour's own SGR parameters, at whatever depth the terminal has.
//
//  Created by Wade Tregaskis
//  License: MIT

extension Color {
    /// This colour downsampled to fit `depth`.
    ///
    /// Colours that already fit pass through unchanged; higher-depth ones are
    /// quantised to the nearest representable value.
    ///
    /// - Parameter depth: The target colour depth.
    /// - Returns: The downsampled colour.
    package func downsampled(to depth: ColorDepth) -> Color {
        switch (depth, value) {
        case (.truecolor, _), (.noColor, _):
            return self
        case (.palette256, .rgb):
            return downsampledToPalette256()
        case (.basic16, .rgb), (.basic16, .palette256):
            return downsampledToANSI16()
        default:
            return self
        }
    }

    /// The SGR parameters that set this colour as the FOREGROUND, downsampled
    /// to `depth`. Empty at ``ColorDepth/noColor``, which draws no colour at
    /// all.
    ///
    /// - Parameter depth: The colour depth to quantise for.
    /// - Returns: The parameter strings, ready to join with `;`.
    package func foregroundCodes(depth: ColorDepth = ColorDepth.current) -> [String] {
        // NO ALPHA CHECK HERE, and it is worth saying why, because the obvious
        // improvement is to add one and it was tried and measured.
        //
        // A fully transparent colour has a sensible answer available — emit no
        // parameters, so the cell keeps the colour it had — and returning it here
        // would stop an unmigrated path rendering `.clear` as the solid black its
        // underlying value is. But this function is the hottest in the framework
        // (SGR emission was once measured at 97% of a truecolor frame), and in a
        // RELEASE build the assertion below compiles out entirely, so a check is
        // genuinely new work on every colour emitted. Paired A/B, 16 reps:
        //
        //   with `if alpha == 0 { return [] }`   textwall +3.3%  fanout +3.0%
        //   merged into the `.noColor` guard      textwall +0.9%  fanout +2.1%
        //
        // — a permanent tax on every page to protect a path that has not been
        // migrated. So it is not paid here. The place it costs nothing is the PAINT
        // SITE, which runs once per view rather than once per run, and which is
        // where each of §16's entry points gets it as that entry point is migrated.
        //
        // Making it free by giving `ColorValue` a `.transparent` case does not work
        // either, and not for cost reasons: it would strip the components, and
        // `Gradient(colors: [.red, .clear])` needs them to fade toward a
        // transparent RED, while `.red.opacity(0)` animated back up must return red
        // rather than black.
        //
        // A translucent colour reaching this line therefore means the view that
        // painted it does not yet carry alpha to the compositor.
        //
        // An assertion rather than a `fatalError` (which is what `.semantic`
        // gets): this is an unmigrated path rather than a broken invariant, and it
        // degrades to what the framework did before alpha existed. Loud in a debug
        // build, never a crash in someone's terminal. Section 16 of
        // `Documentation/Opacity as composition.md` lists which paths honour it.
        assert(
            isOpaque,
            "a translucent colour reached the ANSI emitter (alpha \(alpha)): the view "
                + "that painted it does not carry alpha to the compositor, so it renders "
                + "opaque. See 'Opacity as composition.md' §16; prefer .opacity(_:) on "
                + "the VIEW for a fade that works everywhere.")
        if depth == .noColor { return [] }
        switch downsampled(to: depth).value {
        case .standard(let ansi): return ["\(ansi.foregroundCode)"]
        case .bright(let ansi): return ["\(ansi.brightForegroundCode)"]
        case .palette256(let index): return ["38", "5", "\(index)"]
        case .rgb(let red, let green, let blue): return ["38", "2", "\(red)", "\(green)", "\(blue)"]
        case .terminalForeground: return ["\(ANSIColor.default.foregroundCode)"]
        // No SGR names the default BACKGROUND as a foreground. Once the terminal
        // has reported it, this slot gets that RGB, quantised as an `.rgb` of it
        // would be; `downsampled` left it alone above because it cannot see the
        // slot. Until then there is no RGB to spell and none is guessed, so this
        // slot gets its own default.
        case .terminalBackground:
            guard let paper = rgbComponents else { return ["\(ANSIColor.default.foregroundCode)"] }
            return Color.rgb(paper.red, paper.green, paper.blue).foregroundCodes(depth: depth)
        case .semantic:
            fatalError(
                "Semantic color must be resolved before rendering. Call Color.resolve(with:) first."
            )
        }
    }

    /// The BACKGROUND twin of ``foregroundCodes(depth:)``.
    ///
    /// - Parameter depth: The colour depth to quantise for.
    /// - Returns: The parameter strings, ready to join with `;`.
    package func backgroundCodes(depth: ColorDepth = ColorDepth.current) -> [String] {
        // NO ALPHA CHECK HERE, and it is worth saying why, because the obvious
        // improvement is to add one and it was tried and measured.
        //
        // A fully transparent colour has a sensible answer available — emit no
        // parameters, so the cell keeps the colour it had — and returning it here
        // would stop an unmigrated path rendering `.clear` as the solid black its
        // underlying value is. But this function is the hottest in the framework
        // (SGR emission was once measured at 97% of a truecolor frame), and in a
        // RELEASE build the assertion below compiles out entirely, so a check is
        // genuinely new work on every colour emitted. Paired A/B, 16 reps:
        //
        //   with `if alpha == 0 { return [] }`   textwall +3.3%  fanout +3.0%
        //   merged into the `.noColor` guard      textwall +0.9%  fanout +2.1%
        //
        // — a permanent tax on every page to protect a path that has not been
        // migrated. So it is not paid here. The place it costs nothing is the PAINT
        // SITE, which runs once per view rather than once per run, and which is
        // where each of §16's entry points gets it as that entry point is migrated.
        //
        // Making it free by giving `ColorValue` a `.transparent` case does not work
        // either, and not for cost reasons: it would strip the components, and
        // `Gradient(colors: [.red, .clear])` needs them to fade toward a
        // transparent RED, while `.red.opacity(0)` animated back up must return red
        // rather than black.
        //
        // A translucent colour reaching this line therefore means the view that
        // painted it does not yet carry alpha to the compositor.
        //
        // An assertion rather than a `fatalError` (which is what `.semantic`
        // gets): this is an unmigrated path rather than a broken invariant, and it
        // degrades to what the framework did before alpha existed. Loud in a debug
        // build, never a crash in someone's terminal. Section 16 of
        // `Documentation/Opacity as composition.md` lists which paths honour it.
        assert(
            isOpaque,
            "a translucent colour reached the ANSI emitter (alpha \(alpha)): the view "
                + "that painted it does not carry alpha to the compositor, so it renders "
                + "opaque. See 'Opacity as composition.md' §16; prefer .opacity(_:) on "
                + "the VIEW for a fade that works everywhere.")
        if depth == .noColor { return [] }
        switch downsampled(to: depth).value {
        case .standard(let ansi): return ["\(ansi.backgroundCode)"]
        case .bright(let ansi): return ["\(ansi.brightBackgroundCode)"]
        case .palette256(let index): return ["48", "5", "\(index)"]
        case .rgb(let red, let green, let blue): return ["48", "2", "\(red)", "\(green)", "\(blue)"]
        case .terminalBackground: return ["\(ANSIColor.default.backgroundCode)"]
        // The twin of the foreground's arm: no SGR names the default foreground
        // as a background, so this is the reported RGB, quantised, or this slot's
        // own default while there is none.
        case .terminalForeground:
            guard let ink = rgbComponents else { return ["\(ANSIColor.default.backgroundCode)"] }
            return Color.rgb(ink.red, ink.green, ink.blue).backgroundCodes(depth: depth)
        case .semantic:
            fatalError(
                "Semantic color must be resolved before rendering. Call Color.resolve(with:) first."
            )
        }
    }

    /// The whole escape sequence that sets this colour as the background, or
    /// `""` where the depth draws no colour.
    ///
    /// - Parameter depth: The colour depth to quantise for.
    /// - Returns: The escape sequence.
    package func backgroundEscape(depth: ColorDepth = ColorDepth.current) -> String {
        let codes = backgroundCodes(depth: depth)
        guard !codes.isEmpty else { return "" }
        return "\u{1B}[" + codes.joined(separator: ";") + "m"
    }
}

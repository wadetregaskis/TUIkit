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
        // FULLY transparent paints no colour at all. That is an ANSWER rather than
        // a degradation, and the only one available without a backdrop: emitting
        // nothing leaves the cell the colour it already had, which is what
        // transparent means. It is also the one case where getting it wrong is
        // alarming, because `.clear`'s underlying value is black: at full strength
        // `.border(.clear)` is a solid black box.
        //
        // Checked BEFORE the assertion because it is not a gap. `.clear` is public
        // API, and a reader writing it deserves the sensible answer rather than a
        // trap, on every path, migrated or not.
        if alpha == 0 { return [] }
        // PARTIAL alpha has no answer here — there is no backdrop to blend
        // against — so reaching this line means the view that painted it does not
        // yet carry alpha to the compositor.
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
        // FULLY transparent paints no colour at all. That is an ANSWER rather than
        // a degradation, and the only one available without a backdrop: emitting
        // nothing leaves the cell the colour it already had, which is what
        // transparent means. It is also the one case where getting it wrong is
        // alarming, because `.clear`'s underlying value is black: at full strength
        // `.border(.clear)` is a solid black box.
        //
        // Checked BEFORE the assertion because it is not a gap. `.clear` is public
        // API, and a reader writing it deserves the sensible answer rather than a
        // trap, on every path, migrated or not.
        if alpha == 0 { return [] }
        // PARTIAL alpha has no answer here — there is no backdrop to blend
        // against — so reaching this line means the view that painted it does not
        // yet carry alpha to the compositor.
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

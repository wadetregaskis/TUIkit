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
        // A translucent colour has no SGR spelling — the terminal has no alpha
        // channel, so the only honest answer is the one the compositor gives,
        // which is a concrete colour blended against what is behind the cell.
        // Reaching here with one means a path emitted a colour without stamping
        // an `OpacityRegion` for it; the cell renders at full strength and the
        // reader sees a solid colour where they asked for a faint one.
        //
        // An assertion rather than a `fatalError` (which is what `.semantic`
        // gets) because unlike an unresolved semantic colour this degrades to
        // exactly today's behaviour: opaque. Loud in every debug and test build,
        // and never a crash in someone's terminal. The paths still to be
        // migrated are listed in `Documentation/Opacity as composition.md`.
        assert(isOpaque, "translucent colour reached \(#function): alpha \(alpha)")
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
        // A translucent colour has no SGR spelling — the terminal has no alpha
        // channel, so the only honest answer is the one the compositor gives,
        // which is a concrete colour blended against what is behind the cell.
        // Reaching here with one means a path emitted a colour without stamping
        // an `OpacityRegion` for it; the cell renders at full strength and the
        // reader sees a solid colour where they asked for a faint one.
        //
        // An assertion rather than a `fatalError` (which is what `.semantic`
        // gets) because unlike an unresolved semantic colour this degrades to
        // exactly today's behaviour: opaque. Loud in every debug and test build,
        // and never a crash in someone's terminal. The paths still to be
        // migrated are listed in `Documentation/Opacity as composition.md`.
        assert(isOpaque, "translucent colour reached \(#function): alpha \(alpha)")
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

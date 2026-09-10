//  🖥️ TUIkit — Terminal UI Kit for Swift
//  BorderRenderer.swift
//
//  Created by LAYERED.work
//  License: MIT

/// Reusable building blocks for border rendering.
///
/// Each method produces a single rendered line (`String`) that callers
/// append to a `[String]` array for `FrameBuffer` construction.
/// This eliminates duplicated border-assembly code across Views and Modifiers.
///
/// Uses standard box-drawing characters (┌─┐│└─┘├─┤) with configurable
/// ``BorderStyle`` presets (line, rounded, doubleLine, heavy).
enum BorderRenderer {

    /// The total width consumed by left + right border characters (1 + 1 = 2).
    static let borderWidthOverhead = 2

    /// The breathing focus indicator character.
    static let focusIndicator: Character = "●"

    /// The width of the focus indicator prefix (indicator + space).
    static let focusIndicatorWidth = 2
}

// MARK: - Focus Indicator

extension BorderRenderer {
    /// The two ends a focus affordance breathes between, given the colour it
    /// rests at: that colour dimmed to ``ViewConstants/focusBorderDim`` over
    /// the surface it is DRAWN ON, and the colour itself.
    ///
    /// **Both ends come from the affordance's OWN colour**, and that is the
    /// whole of the fix for the first version of a `Link`'s breath: it breathed
    /// between the label's resting colour and `palette.accent`, and a `Link`
    /// rests AT the accent, so the two ends were the same colour and a focused
    /// link did not move. It appeared to work under the pointer only because
    /// hover lifts the resting colour away from the accent, which accidentally
    /// gave the breath somewhere to go.
    ///
    /// The bright end is where the affordance already is, so the peak of the
    /// breath looks exactly like an unfocused one and the signal is the MOTION.
    ///
    /// **`surface` is what is behind the ink, not the page.** They are the same
    /// colour until a container paints one, and then they are not:
    /// ``EnvironmentValues/enclosingSurface`` is the caller's answer. Dimming
    /// over the page inside a `TabView` body put a focused link's quiet end at
    /// the exact luminance of the tab it sat on — 1.01:1 on Homebrew, where
    /// compositing over the tab's own colour gives 1.61:1.
    static func breathEnds(from resting: Color, on surface: Color) -> (dim: Color, bright: Color) {
        (dim: resting.opacity(ViewConstants.focusBorderDim, over: surface), bright: resting)
    }

    /// ``breathEnds(from:on:)`` for the ● — the accent's breath.
    ///
    /// Handed to `SelectionEmphasisCycle.colors(dim:bright:)` by a caller
    /// drawing the WHOLE cycle, which is every caller there is. Separate from
    /// ``focusIndicatorPrefix(isFocused:color:)`` for exactly that reason: the
    /// prefix used to take a `SelectionEmphasis` and resolve its own colour,
    /// which meant a caller drawing sixteen frames rebuilt the pulse ramp
    /// sixteen times.
    ///
    /// The ends come from the shared selection clock's palette, not from
    /// `pulsePhase` — that is the other timer (2.0 s against the selection
    /// clock's 0.8 s), so a plain button visibly lagged every list cursor and
    /// menu row on the same screen, and `.selectionIndicatorStyle(.none/.blink)`
    /// never reached it at all.
    static func focusIndicatorEnds(
        palette: any Palette, on surface: Color
    ) -> (dim: Color, bright: Color) {
        breathEnds(from: palette.accent, on: surface)
    }

    /// Renders a pulsing focus indicator for inline focusable elements, at one
    /// point of the cycle.
    ///
    /// Uses the same `●` character and colour interpolation as Focus Sections,
    /// ensuring visual consistency across all focusable components.
    ///
    /// - Parameters:
    ///   - isFocused: Whether the element is currently focused.
    ///   - color: This frame's colour, from
    ///     ``focusIndicatorEnds(palette:on:)`` through the cycle.
    /// - Returns: A 2-character string: `"● "` (colored) when focused, `"  "` when not.
    static func focusIndicatorPrefix(isFocused: Bool, color: Color) -> String {
        guard isFocused else {
            return "  "  // 2 spaces for alignment (matches focusIndicatorWidth)
        }
        return ANSIRenderer.colorize(String(focusIndicator), foreground: color) + " "
    }
}

// MARK: - Border Rendering

extension BorderRenderer {
    /// Whether a top border of this width actually draws the focus ●.
    ///
    /// One definition, because two things depend on the answer: the border
    /// draws the glyph, and the container leaves an ``AnimatedCellRun`` over the
    /// cell it landed in. Disagree, and the run repaints a corner forever.
    ///
    /// A titled border always has room — the title is truncated to fit around
    /// the ● — while a plain one needs an inner cell to spare.
    /// One run of a border's band, coloured the one way.
    ///
    /// Every glyph this type emits goes through here, which is what keeps two
    /// facts true together. First, the incantation
    /// `colorize(_, foreground: color, background: fill(style, color))` was
    /// written thirteen times and is now written once. Second — and this is the
    /// load-bearing part — the bytes state the colour's ``Color/opaqueSpelling``,
    /// because an SGR emitter has no backdrop and so cannot composite. A faded
    /// border's alpha travels separately, as the regions
    /// ``opacityClaims(outerWidth:height:style:color:title:titleColor:focusIndicatorColor:dividerRows:)``
    /// produces.
    ///
    /// That pairing is a rule about this type, not about a call site: a new
    /// drawing function that reached for `ANSIRenderer.colorize` directly would
    /// hand the emitter a translucent colour and trip its assertion. Going
    /// through here it cannot.
    ///
    /// - Parameters:
    ///   - text: The glyphs.
    ///   - style: The border style, which decides whether a field is painted.
    ///   - color: The border colour — the field, and the ink unless `ink` says
    ///     otherwise.
    ///   - ink: A foreground that is not the border's own: a title, a focus dot.
    ///   - bold: Whether the run is bold (a title is).
    private static func band(
        _ text: String, style: BorderStyle, color: Color, ink: Color? = nil, bold: Bool = false
    ) -> String {
        ANSIRenderer.colorize(
            text, foreground: (ink ?? color).opaqueSpelling,
            background: fill(style, color)?.opaqueSpelling, bold: bold)
    }

    /// The background a border's cells take, or `nil` for a style that draws
    /// only its glyph. See ``BorderStyle/paintsBackground``.
    static func fill(_ style: BorderStyle, _ color: Color) -> Color? {
        style.paintsBackground ? color : nil
    }

    /// A colour that has to stay readable on whatever the border paints.
    ///
    /// A title and a focus dot sit among a border's cells, so on an opaque
    /// style they are drawn ON the band rather than in a gap through it — which
    /// means they are no longer being read against the page. Floored against
    /// what they actually land on, through the 256-colour cube, exactly as a
    /// control's label is floored against its face.
    static func legible(_ ink: Color, on style: BorderStyle, _ color: Color) -> Color {
        guard style.paintsBackground else { return ink }
        return ink.ensuringRenderedContrast(
            atLeast: ViewConstants.labelContrastFloor, against: color)
    }

    /// One side wall, drawn the one way.
    ///
    /// Public because three places used to build this by hand —
    /// `_ContainerViewCore`'s animating wall, the drop-down's frame, and the
    /// chrome rule — and a wall that an animation draws differently from the
    /// one `standardContentLine` draws is a seam down the side of the box.
    static func wall(style: BorderStyle, color: Color) -> String {
        band(String(style.vertical), style: style, color: color)
    }

    /// A horizontal rule in a style — the divider inside a menu, the chrome
    /// rule — drawn the same way the box's own top and bottom are.
    static func rule(style: BorderStyle, width: Int, color: Color) -> String {
        band(
            String(repeating: style.horizontal, count: max(0, width)),
            style: style, color: color)
    }

    static func showsFocusIndicator(innerWidth: Int, hasTitle: Bool) -> Bool {
        hasTitle || max(0, innerWidth) > 1
    }

    // MARK: - The alpha half of a translucent border

    /// The ``OpacityRegion``s a standard-style box's own cells owe, given the
    /// colours it was drawn in.
    ///
    /// A border colour is `.border(.red.opacity(0.5))`'s destination, and this is
    /// the half of that paint the emitters cannot do: `foregroundCodes` has no
    /// backdrop, so the bytes state ``Color/opaqueSpelling`` and the alpha travels
    /// here. See `Documentation/Opacity as composition.md`.
    ///
    /// ## Why the frame and not the whole rectangle
    ///
    /// Because a box's translucency belongs to its walls. One region over the
    /// box's full extent would fade the content it was drawn around — which no
    /// colour asked for, and which is visibly wrong the moment anything is inside
    /// it. So: the top band, the bottom row, and the two wall columns between.
    ///
    /// Every cell is claimed exactly once. Overlapping claims MULTIPLY at the
    /// resolver (`OpacityResolution` folds them), so a divider row taking the full
    /// width on top of the wall columns would square the alpha at its two end
    /// cells — a pair of darker pips down the side of the box. The divider
    /// therefore claims only the columns between the walls, and a box one row or
    /// one column across claims that row or column once rather than twice.
    ///
    /// ## The title and the focus dot are their own ink
    ///
    /// They sit IN the band — an opaque border with an unpainted title cell reads
    /// as a broken one — so their cells take the border's FIELD and their own INK.
    /// A span whose ink is opaque yields no claim at all, which is what makes the
    /// two common shapes both come out right: a translucent border with an opaque
    /// title fades the band and leaves the letters, and an opaque border with a
    /// translucent title fades only the letters.
    ///
    /// - Parameters:
    ///   - outerWidth: The box's full width, walls included.
    ///   - height: The box's full height, top and bottom bands included.
    ///   - style: The border style, which decides whether a field is painted.
    ///   - color: The border colour, as it was drawn this frame.
    ///   - title: The title as given — truncated here exactly as the band
    ///     truncates it.
    ///   - titleColor: The title's colour, already resolved.
    ///   - focusIndicatorColor: The focus dot's colour, if one is drawn.
    ///   - dividerRow: The row holding a `├───┤` rule, in the box's own
    ///     coordinates, when there is one.
    /// - Returns: The regions, or an empty array when every colour is opaque.
    static func opacityClaims(
        outerWidth: Int, height: Int, style: BorderStyle, color: Color,
        title: String? = nil, titleColor: Color? = nil,
        focusIndicatorColor: Color? = nil, dividerRow: Int? = nil
    ) -> [OpacityRegion] {
        // The colours FIRST, before any geometry and before anything allocates.
        // Every box in nearly every app is drawn in opaque colours, and a bordered
        // spine reaches here once per level per frame, so the answer for one wants
        // to be three comparisons and a shared empty array.
        guard !color.isOpaque || titleColor?.isOpaque == false
            || focusIndicatorColor?.isOpaque == false
        else { return [] }
        guard outerWidth > 0, height > 0 else { return [] }
        let field = fill(style, color)
        var claims: [OpacityRegion] = []
        func add(x: Int, y: Int, width: Int, height: Int, ink: Color?) {
            if let claim = OpacityRegion.claim(
                offsetX: x, offsetY: y, width: width, height: height, ink: ink, field: field)
            {
                claims.append(claim)
            }
        }

        // The top band, span by span, in the order `standardTopBorder` draws
        // them. `column` is where the next span starts, so the arms cannot
        // disagree about what precedes them.
        let innerWidth = outerWidth - 2
        var column = 1  // the corner
        add(x: 0, y: 0, width: 1, height: 1, ink: color)
        if let indicator = focusIndicatorColor,
            showsFocusIndicator(innerWidth: innerWidth, hasTitle: title != nil)
        {
            add(
                x: column, y: 0, width: 1, height: 1,
                ink: legible(indicator, on: style, color))
            column += 1
        }
        if let title, let fitted = fittedTitle(title, innerWidth: innerWidth) {
            // The title always starts one inner cell in, whether that cell held
            // the dot or a `─`, so a band with no dot has a border span to close
            // before the title begins.
            if column < 1 + titleUsedLeftWidth {
                add(
                    x: column, y: 0, width: 1 + titleUsedLeftWidth - column, height: 1,
                    ink: color)
                column = 1 + titleUsedLeftWidth
            }
            // ` title ` — the two spaces are painted in the band too.
            let titleWidth = min(fitted.strippedLength + 2, max(0, outerWidth - column))
            add(
                x: column, y: 0, width: titleWidth, height: 1,
                ink: titleColor.map { legible($0, on: style, color) })
            column += titleWidth
        }
        add(x: column, y: 0, width: outerWidth - column, height: 1, ink: color)

        guard height > 1 else { return claims }
        add(x: 0, y: height - 1, width: outerWidth, height: 1, ink: color)

        let interior = height - 2
        guard interior > 0 else { return claims }
        add(x: 0, y: 1, width: 1, height: interior, ink: color)
        // A box one column across has one wall, which is both of them.
        if outerWidth > 1 {
            add(x: outerWidth - 1, y: 1, width: 1, height: interior, ink: color)
        }
        // Between the walls only — see the note above on multiplication.
        if let dividerRow, dividerRow > 0, dividerRow < height - 1 {
            add(x: 1, y: dividerRow, width: outerWidth - 2, height: 1, ink: color)
        }
        return claims
    }

    /// The one inner cell a titled top border spends before the title starts —
    /// the `─` or the `●` after the corner.
    static let titleUsedLeftWidth = 1

    /// The title as a titled top border will actually draw it, or `nil` for one
    /// that collapses to unbroken border.
    ///
    /// Extracted because two things now need it and they must not disagree: the
    /// border draws the title, and ``inkClaims(outerWidth:height:style:color:title:titleColor:focusIndicatorColor:dividerRows:)``
    /// says which columns it lands in. A claim computed from the untruncated
    /// title fades cells the title never reached.
    ///
    /// - Parameters:
    ///   - title: The title as given.
    ///   - innerWidth: The content width, borders excluded. Clamped at zero.
    /// - Returns: The truncated title, or `nil` when it is blank or has no room
    ///   — both of which draw a continuous band instead.
    static func fittedTitle(_ title: String, innerWidth: Int) -> String? {
        // The decoration after the corner (─ or ●) occupies one inner cell and
        // the title display adds two spaces of padding. Truncate the title so the
        // whole top border fits exactly within `innerWidth`.
        let maxTitleWidth = max(0, max(0, innerWidth) - titleUsedLeftWidth - 2)
        let fitted =
            title.strippedLength > maxTitleWidth
            ? title.ansiAwarePrefix(visibleCount: maxTitleWidth)
            : title
        return fitted.stripped.allSatisfy(\.isWhitespace) ? nil : fitted
    }

    /// Renders a plain top border line.
    ///
    ///     ┌──────────────┐
    ///
    /// - Parameters:
    ///   - style: The border style providing corner and edge characters.
    ///   - innerWidth: The width of the content area (excluding borders).
    ///   - color: The foreground color for the border.
    ///   - focusIndicatorColor: If non-nil, renders a ● after the top-left corner
    ///     in this color. Used for the breathing focus section indicator.
    /// - Returns: A colorized top border string.
    static func standardTopBorder(
        style: BorderStyle,
        innerWidth: Int,
        color: Color,
        focusIndicatorColor: Color? = nil
    ) -> String {
        // (The room check lives in `showsFocusIndicator` — see below.)
        // A border can be asked to draw into a terminal narrower than its own
        // two frame characters, making `innerWidth` (width - 2) negative — and a
        // negative count traps `String(repeating:count:)`. Clamp on the way in:
        // every count below derives from this, so one clamp covers them all, and
        // a degenerate border is drawn (and clipped) instead of killing the app.
        let innerWidth = max(0, innerWidth)
        if let indicatorColor = focusIndicatorColor,
            showsFocusIndicator(innerWidth: innerWidth, hasTitle: false)
        {
            // ╭●──────────────╮
            let leftCorner = band(String(style.topLeft), style: style, color: color)
            let indicator = band(
                String(focusIndicator), style: style, color: color,
                ink: legible(indicatorColor, on: style, color))
            let remainingWidth = innerWidth - 1  // -1 for the ● character
            let rest = band(
                String(repeating: style.horizontal, count: remainingWidth)
                    + String(style.topRight),
                style: style, color: color)
            return leftCorner + indicator + rest
        }

        let line =
            String(style.topLeft)
            + String(repeating: style.horizontal, count: innerWidth)
            + String(style.topRight)
        return band(line, style: style, color: color)
    }

    /// Renders a top border line with an inline title.
    ///
    ///     ┌─ Title ──────┐   (without focus indicator)
    ///     ┌● Title ──────┐   (with focus indicator)
    ///
    /// - Parameters:
    ///   - style: The border style.
    ///   - innerWidth: The content width.
    ///   - color: The border color.
    ///   - title: The title text.
    ///   - titleColor: The title foreground color.
    ///   - focusIndicatorColor: If non-nil, renders a ● between the corner
    ///     and the title. Used for the breathing focus section indicator.
    /// - Returns: A colorized top border string with embedded title.
    static func standardTopBorder(
        style: BorderStyle,
        innerWidth: Int,
        color: Color,
        title: String,
        titleColor: Color,
        focusIndicatorColor: Color? = nil
    ) -> String {
        let innerWidth = max(0, innerWidth)  // see standardTopBorder: negative traps
        let fitted = fittedTitle(title, innerWidth: innerWidth)

        let leftPart: String
        if let indicatorColor = focusIndicatorColor {
            // ╭● Title
            let corner = band(String(style.topLeft), style: style, color: color)
            let indicator = band(
                String(focusIndicator), style: style, color: color,
                ink: legible(indicatorColor, on: style, color))
            leftPart = corner + indicator
        } else {
            // ╭─ Title
            leftPart = band(
                String(style.topLeft) + String(style.horizontal),
                style: style, color: color)
        }

        // A title that fits in no room, or is blank, would render as `╭─  ─╮` —
        // a gap in the border. `fittedTitle` answers `nil` for those, and the
        // border is drawn continuous `╭────╮` (keeping any focus dot).
        guard let fittedTitle = fitted else {
            let fill = String(repeating: style.horizontal, count: max(0, innerWidth - 1))
                + String(style.topRight)
            return leftPart + band(fill, style: style, color: color)
        }

        // The title sits IN the band rather than in a gap punched through it: an
        // opaque border with an unpainted title cell reads as a broken band.
        let titleStyled = band(
            " \(fittedTitle) ", style: style, color: color,
            ink: legible(titleColor, on: style, color), bold: true)
        let rightPartLength = max(
            0, innerWidth - titleUsedLeftWidth - fittedTitle.strippedLength - 2)
        let rightPart = band(
            String(repeating: style.horizontal, count: rightPartLength) + String(style.topRight),
            style: style, color: color)
        return leftPart + titleStyled + rightPart
    }

    /// Renders a plain bottom border line.
    ///
    ///     └──────────────┘
    ///
    /// - Parameters:
    ///   - style: The border style.
    ///   - innerWidth: The content width.
    ///   - color: The border color.
    /// - Returns: A colorized bottom border string.
    static func standardBottomBorder(
        style: BorderStyle,
        innerWidth: Int,
        color: Color
    ) -> String {
        let innerWidth = max(0, innerWidth)  // see standardTopBorder: negative traps
        let line =
            String(style.bottomLeft)
            + String(repeating: style.horizontal, count: innerWidth)
            + String(style.bottomRight)
        return band(line, style: style, color: color)
    }

    /// Renders a horizontal divider with T-junctions.
    ///
    ///     ├──────────────┤
    ///
    /// - Parameters:
    ///   - style: The border style (uses leftT, horizontal, rightT).
    ///   - innerWidth: The content width.
    ///   - color: The border color.
    /// - Returns: A colorized divider string.
    static func standardDivider(
        style: BorderStyle,
        innerWidth: Int,
        color: Color
    ) -> String {
        let innerWidth = max(0, innerWidth)  // see standardTopBorder: negative traps
        let line =
            String(style.leftT)
            + String(repeating: style.horizontal, count: innerWidth)
            + String(style.rightT)
        return band(line, style: style, color: color)
    }

    /// Wraps a single content line with vertical side borders.
    ///
    ///     │ padded content │
    ///
    /// If `backgroundColor` is provided, `applyPersistentBackground` is used
    /// so the background survives inner ANSI resets.
    ///
    /// - Parameters:
    ///   - content: The content string (will be padded to `innerWidth`).
    ///   - innerWidth: The target content width.
    ///   - style: The border style (for the vertical character).
    ///   - color: The border color.
    ///   - backgroundColor: Optional background applied to the content area.
    /// - Returns: The bordered content line.
    static func standardContentLine(
        content: String,
        innerWidth: Int,
        style: BorderStyle,
        color: Color,
        backgroundColor: Color? = nil
    ) -> String {
        let innerWidth = max(0, innerWidth)  // see standardTopBorder: negative traps
        return contentLine(
            content: content,
            innerWidth: innerWidth,
            vertical: wall(style: style, color: color),
            backgroundColor: backgroundColor
        )
    }

    /// Builds a run of bordered content lines that share one border style and
    /// colour (a container's body or footer).
    ///
    /// Computes the coloured vertical border ONCE for the whole run instead of
    /// per line: the bar is identical for every line of a border, but the
    /// per-line ``standardContentLine`` re-ran `colorize(String(vertical))` —
    /// a String allocation — for each one. A container body of N lines paid N
    /// of those (plus N for the right bar's reuse) every frame; this pays one.
    ///
    /// - Parameters:
    ///   - contents: The content strings, one per line.
    ///   - innerWidth: The target content width (each line is fitted to it).
    ///   - style: The border style (for the vertical character).
    ///   - color: The border colour.
    ///   - backgroundColor: Optional background applied to the content area.
    /// - Returns: The bordered content lines, in order.
    /// - Parameter contentWidth: When non-`nil`, the known visible width of
    ///   *every* line in `contents` (they are uniform). Lets each line skip its
    ///   own `strippedLength` re-measure — the dominant cost when a deeply-nested
    ///   layout re-borders the same lines at every level. Pass `nil` (the
    ///   default) when the lines may be ragged, to measure each individually.
    static func standardContentLines(
        contents: [String],
        innerWidth: Int,
        style: BorderStyle,
        color: Color,
        backgroundColor: Color? = nil,
        contentWidth: Int? = nil
    ) -> [String] {
        let innerWidth = max(0, innerWidth)  // see standardTopBorder: negative traps
        let vertical = wall(style: style, color: color)
        return contents.map {
            contentLine(
                content: $0,
                innerWidth: innerWidth,
                vertical: vertical,
                backgroundColor: backgroundColor,
                knownWidth: contentWidth
            )
        }
    }

    /// Fits one content string into a bordered line, given the already-coloured
    /// vertical bar. Measures the content's visible width ONCE and reuses it for
    /// both the truncate-vs-pad decision and the padding amount (the old code
    /// measured it twice: once for the width check, once inside
    /// `padToVisibleWidth`). For an already-styled line that second measure took
    /// the allocating ANSI path, so the dedup removes real churn per line.
    private static func contentLine(
        content: String,
        innerWidth: Int,
        vertical: String,
        backgroundColor: Color?,
        knownWidth: Int? = nil
    ) -> String {
        let innerWidth = max(0, innerWidth)  // see standardTopBorder: negative traps
        // Fit the content to exactly `innerWidth`: truncate if it is wider
        // (ANSI-aware) so it cannot displace the right border, pad if narrower.
        // `knownWidth` is the caller-supplied visible width when the line is part
        // of a uniform-width run — using it skips the per-line re-measure. It is
        // safe even when it exceeds `innerWidth`: the truncate branch clips to
        // `innerWidth` regardless, and a uniform run clips identically.
        let width = knownWidth ?? content.strippedLength
        // The unstyled case — every bordered line in a tree that sets no row
        // background, which is nearly all of them — is assembled in ONE
        // reserved buffer: wall, content, the pad run, reset, wall. The
        // `+`-chain it replaces allocated an intermediate String per link
        // (and `String(repeating:)` a sixth for the padding), and this runs
        // per content line per container per frame — O(depth²) down a nested
        // spine, where it was the single hottest string site: 13.3% of a
        // `deep` frame in `String.+` alone, over an allocation profile with
        // `_allocateStringStorage` at 13.9%.
        if backgroundColor == nil {
            let pad = width < innerWidth ? innerWidth - width : 0
            var line = ""
            if width > innerWidth {
                // A wide char straddling the clip column is excluded, leaving
                // the prefix up to a cell short — pad the shortfall so the
                // right border stays aligned (same pattern as _ListCore's row
                // clipping). Rare enough to keep the simple spelling.
                let clipped = content.ansiAwarePrefix(
                    visibleCount: innerWidth, knownVisibleWidth: width
                ).padToVisibleWidth(innerWidth)
                line.reserveCapacity(
                    vertical.utf8.count * 2 + clipped.utf8.count + ANSIRenderer.reset.utf8.count)
                line += vertical
                line += clipped
            } else {
                line.reserveCapacity(
                    vertical.utf8.count * 2 + content.utf8.count + pad
                        + ANSIRenderer.reset.utf8.count)
                line += vertical
                line += content
                if pad > 0 { line += asciiSpaces(pad) }
            }
            line += ANSIRenderer.reset
            line += vertical
            return line
        }
        let fittedLine: String
        if width > innerWidth {
            fittedLine = content.ansiAwarePrefix(
                visibleCount: innerWidth, knownVisibleWidth: width
            ).padToVisibleWidth(innerWidth)
        } else if width == innerWidth {
            fittedLine = content
        } else {
            fittedLine = content + String(repeating: " ", count: innerWidth - width)
        }
        let styledContent = fittedLine.withPersistentBackground(backgroundColor)
        return vertical + styledContent + ANSIRenderer.reset + vertical
    }
}

//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OpacityBlend.swift
//
//  The cell arithmetic under `resolvingOpacity`: a rendered row taken apart
//  into per-column cells, one cell blended at a time, and the result re-emitted
//  as a self-contained span. The RULES — which glyph draws, what "behind"
//  means, what a yielded cell keeps — are documented at `OpacityResolution.swift`
//  and in `Documentation/Opacity as composition.md` §10.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitStyling

// MARK: - The span

extension FrameBuffer {

    /// One cell of a rendered row, taken apart far enough to blend it.
    ///
    /// `style` carries everything SGR says that is NOT colour — bold, dim,
    /// underline, inverse — so a faded bold label stays bold. The two colours
    /// are pulled out separately because they are the only part the blend
    /// touches, and `SGRState` deliberately keeps them as parameter lists
    /// rather than as `Color`s (it lives a module below `Color`).
    struct RowCell {
        var character: Character
        var style: SGRState
        var foreground: Color?
        var background: Color?
    }

    /// The blended replacement for `columns` of `source`, as a self-contained
    /// string that starts and ends at the terminal's default state.
    ///
    /// `alpha` returns `nil` for a column no region covers, which passes the
    /// source cell through untouched — a row can be covered in part, and a span
    /// that runs from the leftmost to the rightmost covered column is one
    /// splice instead of one per region.
    static func blendedSpan(
        source: String,
        destination: String,
        columns: Range<Int>,
        destinationShift: Int,
        alpha: (Int) -> Double?,
        surface: Color,
        defaultForeground: Color
    ) -> String {
        let sourceCells = cells(
            in: source, through: columns.upperBound,
            defaultForeground: defaultForeground, surface: surface)
        let behindCells = cells(
            in: destination, through: columns.upperBound + destinationShift,
            defaultForeground: defaultForeground, surface: surface)

        var span = ""
        var emitted = SGRState()
        var column = columns.lowerBound
        var lastSourceCell: RowCell?
        while column < columns.upperBound {
            // A nil column is the continuation of a wide source character —
            // but the walk advances by what it EMITS, so reaching one means
            // the character did NOT claim it: the glyph yielded its contest
            // (or the region is at zero) and a narrow replacement took only
            // its start column. The continuation must then yield on its own —
            // skipping it left the span a column short per yielded character,
            // and the splice then replaced too few columns and let unfaded
            // source glyphs through. It yields as a space wearing the
            // character's own styling, so the blend's ordinary rules apply.
            let cell =
                sourceCells[column]
                ?? RowCell(
                    character: " ", style: lastSourceCell?.style ?? SGRState(),
                    foreground: lastSourceCell?.foreground,
                    background: lastSourceCell?.background)
            if sourceCells[column] != nil { lastSourceCell = cell }
            // Bounds-checked rather than trusted: a negative shift is legal —
            // `composited` accepts one — and would index before the start.
            let behindColumn = column + destinationShift
            let behind =
                behindCells.indices.contains(behindColumn) ? behindCells[behindColumn] : nil
            var blended = blend(
                source: cell, destination: behind, alpha: alpha(column),
                surface: surface, defaultForeground: defaultForeground)
            // A revealed DESTINATION character can be wide, and the walk
            // advances by what it emits: a two-column character from a
            // one-column decision would swallow the next source column's own
            // answer — a cell the region might not even cover. Emitting it
            // whole is safe only when the source's character here has the
            // same footprint (those continuation columns were already
            // nobody's decision) and the footprint fits inside the span.
            // Anywhere else one column of the destination's FIELD stands in:
            // half a glyph cannot be drawn, and the field is what the cell
            // shows wherever its glyph cannot be.
            let width = max(1, blended.character.terminalWidth)
            if width > 1, blended.character != cell.character,
                width != max(1, cell.character.terminalWidth)
                    || column + width > columns.upperBound
            {
                blended.character = " "
            }
            span += blended.style.rendered(changingFrom: emitted)
            span.append(blended.character)
            emitted = blended.style
            column += max(1, blended.character.terminalWidth)
        }
        // Close the span rather than leaving its styling open: `splicing`
        // restores the line's own state where the span ends, and an open
        // background would otherwise reach the cell after it.
        span += SGRState().rendered(changingFrom: emitted)
        return span
    }

    /// The destination's cell with the source's paint composited onto its
    /// field — the shared shape of every rule where the destination keeps its
    /// character: a space, and a glyph contest resolved in the destination's
    /// favour. The veil tints the surface under the text, never the text; a
    /// source that paints nothing at all tints nothing at all.
    ///
    /// "Paint" is the source cell's average: its background, with its ink
    /// mixed in by the ink's coverage — a yielded glyph does not stop being
    /// light. A source with ink but no background contributes only the ink,
    /// at `alpha` scaled by its coverage.
    private static func compositingField(
        of source: RowCell, onto destination: RowCell?, alpha: Double, behind: Color,
        defaultForeground: Color
    ) -> RowCell {
        let coverage = source.character.inkCoverage
        let paint: Color?
        let weight: Double
        if let background = source.background {
            paint =
                coverage > 0
                ? (source.foreground ?? defaultForeground).compositing(coverage, over: background)
                : background
            weight = alpha
        } else if coverage > 0 {
            paint = source.foreground ?? defaultForeground
            weight = alpha * coverage
        } else {
            paint = nil
            weight = 0
        }
        guard let paint, weight > 0 else {
            return destination ?? RowCell(character: " ", style: SGRState())
        }
        let faded = paint.compositing(weight, over: behind)
        var kept = destination ?? RowCell(character: " ", style: SGRState())
        kept.background = faded
        kept.style = kept.style.settingBackground(faded)
        return kept
    }

    /// The average colour a cell DISPLAYS — its ink and its field mixed by the
    /// ink's coverage — which is what "behind" means to a glyph drawn over it.
    ///
    /// This is the difference between text fading over a `█`-drawn swatch
    /// blending toward the swatch's colour (its FOREGROUND) and blending
    /// toward whatever background happened to sit under the blocks. A missing
    /// cell shows the surface.
    private static func averageDisplay(
        of cell: RowCell?, surface: Color, defaultForeground: Color
    ) -> Color {
        guard let cell else { return surface }
        let field = cell.background ?? surface
        let coverage = cell.character.inkCoverage
        guard coverage > 0 else { return field }
        return (cell.foreground ?? defaultForeground).compositing(coverage, over: field)
    }

    /// One cell's answer.
    private static func blend(
        source: RowCell, destination: RowCell?, alpha: Double?,
        surface: Color, defaultForeground: Color
    ) -> RowCell {
        // Uncovered: the source stands as it is.
        guard let alpha else { return source }
        // Fully opaque: the layer wins the cell outright — and that is a
        // different statement from "the source stands as it is", which is what
        // this used to say and which put the range's only discontinuity at its
        // top.
        //
        // A cell that names no background has none to win WITH. There is
        // nothing to blend and nothing to paint, so what is behind it shows —
        // at 1 exactly as at 0.999, which is the rule the whole range below
        // follows. Taking the source verbatim instead punched those cells out
        // to the ambient surface: text over a coloured field that read
        // correctly at 99% and gained a black (or, on a light terminal, white)
        // rectangle at 100%, and a fade breathing up to 1 that flickered once
        // per cycle as it touched the top.
        //
        // What DOES snap at 1 is the pane rule below: under a translucent pane
        // the destination keeps its own character (the veil tints the surface
        // under text, never the text), and an OPAQUE pane is not a veil — a
        // source blank carrying a background hides what is behind it. That
        // discontinuity is the deliberate one, and it is in the character
        // rather than the colour, which is where a cell grid puts every other
        // one.
        if alpha >= 1 {
            guard source.background == nil else { return source }
            // Painting nothing at all — no background and no ink — leaves the
            // destination exactly as it was, which is what keeps a fully opaque
            // container's padding from blanking the rectangle it covers.
            if source.character == " ", !source.style.paintsInkOnBlankCell {
                return destination ?? source
            }
            guard let background = destination?.background else { return source }
            var result = source
            result.background = background
            result.style = source.style.settingBackground(background)
            return result
        }
        // At zero the source contributes nothing at all, and the destination
        // is not merely approximated, it is UNTOUCHED: character, colours and
        // attributes — re-emitted through the span, so equivalent styling
        // rather than identical bytes. Every blend below converges here as
        // alpha does, so this is a shortcut, not a discontinuity.
        guard alpha > 0 else {
            return destination ?? RowCell(character: " ", style: SGRState())
        }
        // What the destination actually shows where it paints nothing of its
        // own. A cell with no background is not transparent to the terminal —
        // it is the surface.
        let behind = destination?.background ?? surface
        // A space carries no ink, so it yields the character and composites only
        // its background — and where it has none, it changes nothing at all.
        // That last part is what makes a faded `VStack`'s padding transparent
        // instead of a rectangle of blanks punched through the page.
        //
        // At EVERY alpha, not only above the glyph threshold: colours can blend
        // at any strength — the threshold exists because two characters cannot
        // share a cell, and a space is not a character contest. Gating this on
        // ½ made a translucent panel vanish whole at the midpoint instead of
        // fading smoothly to nothing.
        //
        // "Space" means NO INK, which is more than the character: an
        // underlined or struck-through space draws a pattern in its foreground
        // colour, and falls through to the glyph rules below. (A REVERSED
        // space never reaches here as one — `cells` normalises it into a
        // solid fill, background and all.)
        if source.character == " ", !source.style.paintsInkOnBlankCell {
            return compositingField(
                of: source, onto: destination, alpha: alpha, behind: behind,
                defaultForeground: defaultForeground)
        }
        // Matching characters are not a contest at all: the source's ink sits
        // exactly where the destination's does, so the channels blend in
        // PARALLEL — foreground toward foreground, background toward
        // background — and the cell cross-fades continuously through every
        // alpha with no threshold anywhere. This is what makes a colour
        // change on unchanged text exact: the same label fading between two
        // colourings passes through every intermediate, rather than fading
        // toward the field and popping at ½.
        if let destination, destination.character == source.character {
            var result = source
            let foreground = (source.foreground ?? defaultForeground)
                .compositing(alpha, over: destination.foreground ?? defaultForeground)
            let background =
                source.background.map { $0.compositing(alpha, over: behind) }
                ?? destination.background
            // Weight cannot blend: bold, underline and their kin are on or
            // off, so the glyph's non-colour styling follows whichever side
            // alpha favours.
            let style = alpha >= 0.5 ? source.style : destination.style
            result.foreground = foreground
            result.background = background
            result.style = style.settingForeground(foreground).settingBackground(background)
            return result
        }
        // The threshold decides a CONTEST — two glyphs wanting one cell — and
        // only applies where there is one. Where the destination is blank, the
        // source's character draws at any alpha, fading toward what is behind
        // it and reaching invisibility at 0 with nothing to pop: gating it on ½
        // made text over a plain panel vanish at the midpoint of a fade when
        // there was never anything to reveal underneath it.
        //
        // Where the destination DOES have a character, below ½ the source's
        // glyph is not drawn and the destination keeps its own — under the
        // same field composite a space gets, because to the yielded cell the
        // source IS a pane of background. Without this, a translucent panel
        // over text would tint every cell around a character and none holding
        // one, and read as a sieve rather than a veil.
        //
        // "Has a character" is the same no-ink question as above, asked of the
        // destination: an underlined blank underneath is something to reveal.
        if alpha < 0.5, let destination,
            destination.character != " " || destination.style.paintsInkOnBlankCell
        {
            return compositingField(
                of: source, onto: destination, alpha: alpha, behind: behind,
                defaultForeground: defaultForeground)
        }
        // A drawn glyph covers the WHOLE destination cell — ink included — so
        // what it fades toward is the average colour that cell displays, not
        // its bare field. Text thinning out over a block-drawn swatch moves
        // toward the swatch's colour; over ordinary text the average is nearly
        // all field and this reduces to what it always was.
        let covered = averageDisplay(
            of: destination, surface: surface, defaultForeground: defaultForeground)
        let fadedBackground = source.background.map { $0.compositing(alpha, over: covered) }
        var result = source
        let foreground = (source.foreground ?? defaultForeground).compositing(alpha, over: covered)
        // Where neither side paints a background, the cell keeps naming none —
        // which is the surface, and is what it named before.
        let background = fadedBackground ?? destination?.background
        result.foreground = foreground
        result.background = background
        result.style = source.style.settingForeground(foreground).settingBackground(background)
        return result
    }

    /// `line` taken apart into one entry per COLUMN, up to `width`.
    ///
    /// `nil` where a wide character claims a column it did not start, and where
    /// the line ran out. Indexed by column so the two sides line up without
    /// either having to be walked twice.
    ///
    /// Cells are normalised to the colours they DISPLAY: reverse video (SGR 7)
    /// swaps which colour fills the cell and which the ink draws in, so it is
    /// folded in here — colours exchanged, the attribute dropped — and every
    /// blend rule downstream sees the cell the viewer sees. Without this, a
    /// reversed space read as a blank when it is a solid fill, and the field
    /// behind a reversed cell read as its background when the viewer sees its
    /// foreground. The defaults are parameters because the unstated side of a
    /// reversed cell shows the terminal's OTHER default: ink from the default
    /// background (`surface`), field from the default foreground.
    private static func cells(
        in line: String, through width: Int,
        defaultForeground: Color, surface: Color
    ) -> [RowCell?] {
        var result = [RowCell?](repeating: nil, count: max(0, width))
        guard width > 0, !line.isEmpty else { return result }
        var state = SGRState()
        var foreground: Color?
        var background: Color?
        var column = 0
        for segment in line.ansiSegments() {
            switch segment {
            case .ansi(let sequence, let isSGR):
                state.apply(sequence)
                guard isSGR else { continue }
                SGRColorRewrite.readingColors(sequence) { which, color in
                    switch which {
                    case .foreground: foreground = color
                    case .background: background = color
                    case .reset: foreground = nil; background = nil
                    }
                }
            case .visible(let character):
                guard column < width else { return result }
                if character.terminalWidth == 0 {
                    // A zero-width scalar — a combining mark separated from
                    // its base by an escape. It has no cell of its own; it
                    // belongs to the nearest preceding character, and granting
                    // it a column displaced every colour decision after it one
                    // cell to the right of the real row. (At the row's very
                    // start there is no base, and nothing to attach to.)
                    var owner = column - 1
                    while owner >= 0, result[owner] == nil { owner -= 1 }
                    if owner >= 0, var cell = result[owner] {
                        let combined = String(cell.character) + String(character)
                        if combined.count == 1, let merged = combined.first {
                            cell.character = merged
                            result[owner] = cell
                        }
                    }
                    continue
                }
                var cell = RowCell(
                    character: character, style: state,
                    foreground: foreground, background: background)
                if state.reversesVideo {
                    var unreversed = state
                    unreversed.apply("\u{1B}[27m")
                    cell.foreground = background ?? surface
                    cell.background = foreground ?? defaultForeground
                    // The STYLE's colour parameters swap too, not only the
                    // cell's fields: several blend outcomes re-emit the style
                    // as it stands — an uncovered column passing through, the
                    // zero-alpha reveal, a yielded contest that sets only the
                    // background — and a style still holding the unswapped
                    // lists would display the ink and field exchanged, with
                    // the inversion that used to exchange them back stripped.
                    cell.style = unreversed
                        .settingForeground(cell.foreground)
                        .settingBackground(cell.background)
                }
                result[column] = cell
                column += max(1, character.terminalWidth)
            }
        }
        return result
    }
}

// MARK: - Setting a colour on a parsed state

extension SGRState {
    /// This state with its foreground replaced. `nil` is the terminal's
    /// default (SGR 39) — what a cell that named no colour of its own had.
    ///
    /// Written as an `apply` of the sequence that would set it rather than as a
    /// stored property, because `SGRState` deliberately keeps its colours as
    /// SGR parameter lists: it lives a module below ``Color`` and cannot hold
    /// one. Folding in the sequence is the same operation the parse performs,
    /// so there is one code path for "what colour is in force".
    func settingForeground(_ color: Color?) -> Self {
        var result = self
        result.apply(Self.sgr(color.map { ANSIRenderer.foregroundCodes(for: $0) } ?? ["39"]))
        return result
    }

    /// This state with its background replaced. `nil` is SGR 49.
    func settingBackground(_ color: Color?) -> Self {
        var result = self
        result.apply(Self.sgr(color.map { ANSIRenderer.backgroundCodes(for: $0) } ?? ["49"]))
        return result
    }

    private static func sgr(_ codes: [String]) -> String {
        "\u{1B}[" + codes.joined(separator: ";") + "m"
    }
}

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
        fieldsFrom: String? = nil,
        alpha: (Int) -> Double?,
        surface: Color,
        defaultForeground: Color
    ) -> String {
        let sourceCells = cells(
            in: source, through: columns.upperBound,
            defaultForeground: defaultForeground, surface: surface)
        // The row a run's frame is spliced INTO, when the source is a frame:
        // a frame cell stating no background wears that row's, exactly as the
        // splice will give it, so it is blended as the cell it replaces.
        let fieldCells = fieldsFrom.map {
            cells(in: $0, through: columns.upperBound, defaultForeground: defaultForeground, surface: surface)
        }
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
            var cell =
                sourceCells[column]
                ?? RowCell(
                    character: " ", style: lastSourceCell?.style ?? SGRState(),
                    foreground: lastSourceCell?.foreground,
                    background: lastSourceCell?.background)
            if sourceCells[column] != nil { lastSourceCell = cell }
            if cell.background == nil, let field = fieldCells?[column]?.background {
                cell.background = field
                cell.style = cell.style.settingBackground(field)
            }
            // Bounds-checked rather than trusted: a negative shift is legal —
            // `composited` accepts one — and would index before the start.
            let behindColumn = column + destinationShift
            let behind =
                behindCells.indices.contains(behindColumn) ? behindCells[behindColumn] : nil
            let coverage = alpha(column)
            var blended = blend(
                source: cell, destination: behind, alpha: coverage,
                surface: surface, defaultForeground: defaultForeground)
            // A change the display cannot represent is not drawn as a change.
            // See `settled(_:replacing:)`.
            if coverage != nil {
                // Against what the destination SHOWS, not what it names: a
                // cell with no background of its own is not transparent to the
                // terminal, it is the surface — which is the whole reason the
                // arithmetic above reads it that way too. Comparing against
                // `nil` skipped exactly the cells the fault was reported on.
                let foreground = Self.settled(
                    blended.foreground, replacing: behind?.foreground ?? defaultForeground)
                let background = Self.settled(
                    blended.background, replacing: behind?.background ?? surface)
                if foreground != blended.foreground || background != blended.background {
                    blended.foreground = foreground
                    blended.background = background
                    blended.style =
                        blended.style
                        .settingForeground(foreground)
                        .settingBackground(background)
                }
            }
            // Inside a span, "no background" cannot be left unsaid. SGR 49 is
            // the TERMINAL's default — white on a light profile — and a span is
            // spliced into a row that opened with the PAGE's, so a cell emitted
            // as 49 stops inheriting the row and shows the terminal instead.
            // The arithmetic above already reads a missing background as
            // `surface` (that is what `behind` is); the answer has to say so
            // too. Reported as the spaces of a faded label punching white cells
            // through the band underneath it.
            //
            // Only for columns a region actually covers: an uncovered column
            // passes the source through, and the source is part of a row that
            // has not been taken apart.
            if coverage != nil, blended.background == nil {
                blended.background = surface
                blended.style = blended.style.settingBackground(surface)
            }
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

    /// A colour the display cannot tell from the one it is replacing, left as
    /// it was.
    ///
    /// A composite at a low alpha lands very close to what is behind it, and on
    /// a 256-colour terminal "very close" can still quantise to a distant cube
    /// entry: the cube is sparse, and the nearest entry to a faintly tinted
    /// near-black may be a saturated one. Reported as a label at 1% opacity
    /// drawing a visible green band over the demo behind it — the arithmetic was
    /// right to within three units per channel, and the cube turned three units
    /// into ninety-five.
    ///
    /// The rule is "never round further from the truth than staying put would
    /// be": if the blended colour is nearer to what was already there than to
    /// the entry it would otherwise take, it keeps what was already there. That
    /// makes the composite MONOTONE in the only sense a cell grid can be —
    /// nothing changes until the change is big enough to be represented — and
    /// it is why 1% now looks like 1%.
    ///
    /// Only where the display quantises. A truecolor terminal draws what it is
    /// given and the two are never further apart than they are.
    private static func settled(_ blended: Color?, replacing existing: Color?) -> Color? {
        guard ColorDepth.current == .palette256, let blended, let existing else { return blended }
        guard let truth = blended.rgbComponents, let was = existing.rgbComponents,
            let entry = blended.downsampledToPalette256().rgbComponents
        else { return blended }
        func squaredDistance(
            _ lhs: (red: UInt8, green: UInt8, blue: UInt8),
            _ rhs: (red: UInt8, green: UInt8, blue: UInt8)
        ) -> Int {
            let red = Int(lhs.red) - Int(rhs.red)
            let green = Int(lhs.green) - Int(rhs.green)
            let blue = Int(lhs.blue) - Int(rhs.blue)
            return red * red + green * green + blue * blue
        }
        return squaredDistance(truth, was) <= squaredDistance(truth, entry) ? existing : blended
    }

    /// What a cell shows where its glyph draws — its ink where it paints one,
    /// and its FIELD where it does not, because a cell with no glyph is what
    /// its field shows. `nil` where it states neither: a blank carrying no
    /// background of its own paints nothing at all, and so paints nothing into
    /// this channel either.
    ///
    /// Read the same way on both sides of the blend, which is what keeps a
    /// space from being a case of its own. A veil's blank cell covers the text
    /// under it exactly as much as it covers the field around it, so both
    /// channels move toward the veil's colour by the same alpha and the cell
    /// fades evenly. The same reading is what lets a label thin out over an
    /// empty page: the page's blank cells show their field, and that is the
    /// colour the label fades into.
    private static func displayedInk(of cell: RowCell?, defaultForeground: Color) -> Color? {
        guard let cell else { return nil }
        guard cell.character != " " || cell.style.paintsInkOnBlankCell else {
            return cell.background
        }
        return cell.foreground ?? defaultForeground
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
        // Each channel blends with its own counterpart and nothing else: ink
        // toward ink, field toward field. This is the whole model — the two
        // never mix, so nothing has to estimate how much of a cell a glyph
        // inks. An earlier design averaged a cell's ink into its field by an
        // estimated coverage and blended that single "paint" value, which made
        // a yielded glyph tint the cell it lost (0.43 alpha × 0.15 coverage of
        // a bright foreground is a visible 6.5% wash) and made blank cells and
        // lettered ones behave differently for no reason a viewer could see.
        //
        // Both channels are read through the same pair of questions, asked of
        // both sides, so a space is not a case: what does this cell show where
        // a glyph draws, and what does it show where none does. A cell that
        // states nothing in a channel contributes nothing to it and the other
        // side survives untouched — which is emptiness, not blankness, and is
        // what keeps a faded `VStack`'s padding transparent instead of a
        // rectangle punched through the page.
        let sourceInk = displayedInk(of: source, defaultForeground: defaultForeground)
        let destinationInk =
            displayedInk(of: destination, defaultForeground: defaultForeground) ?? surface
        let destinationField = destination?.background ?? surface

        // ``Color/opacity(_:over:)``, the ENCODED-sRGB mix, not
        // ``Color/compositing(_:over:)``'s linear-light one — see
        // `OpacityFade.fading` and `Documentation/Opacity as composition.md`.
        let foreground =
            sourceInk.map { $0.opacity(alpha, over: destinationInk) } ?? destination?.foreground
        let background =
            source.background.map { $0.opacity(alpha, over: destinationField) }
            ?? destination?.background

        // Only the glyph needs a DECISION, because a cell can hold one and
        // the contest is between GLYPHS: the cell shows whichever side paints
        // one, and where both do, ½ decides. A side painting no glyph is not a
        // candidate — it has nothing to draw, and "drawing" it would mean
        // erasing the side that does.
        let sourcePaintsInk = source.character != " " || source.style.paintsInkOnBlankCell
        let destinationPaintsInk =
            destination.map { $0.character != " " || $0.style.paintsInkOnBlankCell } ?? false
        let sourceDraws = sourcePaintsInk && (!destinationPaintsInk || alpha >= 0.5)
        // Weight cannot blend — bold, underline and their kin are on or off —
        // so the non-colour styling comes from whichever side drew the glyph.
        var result = sourceDraws ? source : (destination ?? RowCell(character: " ", style: SGRState()))
        result.foreground = foreground
        result.background = background
        result.style = result.style.settingForeground(foreground).settingBackground(background)
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
        result.apply(Self.sgr(color.map { $0.foregroundCodes() } ?? ["39"]))
        return result
    }

    /// This state with its background replaced. `nil` is SGR 49.
    func settingBackground(_ color: Color?) -> Self {
        var result = self
        result.apply(Self.sgr(color.map { $0.backgroundCodes() } ?? ["49"]))
        return result
    }

    private static func sgr(_ codes: [String]) -> String {
        "\u{1B}[" + codes.joined(separator: ";") + "m"
    }
}

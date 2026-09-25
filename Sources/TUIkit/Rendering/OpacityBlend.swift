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
        /// Whether the line had reverse video (SGR 7) in force on this cell.
        ///
        /// Not the 7 itself: `cells(in:through:defaultForeground:surface:)` has
        /// already exchanged the two colours above and dropped the attribute from
        /// `style`, so every blend rule reads what the cell displays. This is the
        /// only trace of it, kept for the one question the exchange cannot answer:
        /// whether the blended answer needs the 7 back to be spelled at all
        /// (``spelledWithReverseWhereNeeded(_:)``).
        var isReversed = false
        /// Whether the line STATES the terminal's own field here — an `ESC[49m`
        /// still in force, not yet undone by a reset or a colour — rather than
        /// naming none.
        ///
        /// Both read as no `background`, and to the blend they are the same cell.
        /// Only a run's frame asks the difference, because the painters around a run
        /// disagree about a stated 49 and each field-less cell of a frame is blended
        /// from what they painted under it (`blendedSpan`'s `fieldsFrom` and
        /// `fieldsUnderStatedDefault`).
        var statesTerminalField = false
    }

    /// What one cell's three channels are worth, resolved from the region
    /// covering it.
    ///
    /// Three numbers rather than one because a layer's opacity and a colour's
    /// are different claims — see ``OpacityRegion/inkOpacity``. `layer` decides
    /// the glyph contest; `ink` and `field` only scale their own channel, and
    /// each multiplies the layer's on the way in.
    struct CellAlpha {
        var layer: Double
        var ink: Double
        var field: Double

        init(layer: Double, ink: Double = 1, field: Double = 1) {
            self.layer = layer
            self.ink = ink
            self.field = field
        }

        /// The layer-only spelling, for a caller that has one number.
        static func layer(_ value: Double) -> Self { Self(layer: value) }
    }

    /// The blended replacement for `columns` of `source`, as a self-contained
    /// string that starts and ends at the terminal's default state.
    ///
    /// `alpha` returns `nil` for a column no region covers, which passes the
    /// source cell through untouched — a row can be covered in part, and a span
    /// that runs from the leftmost to the rightmost covered column is one
    /// splice instead of one per region.
    ///
    /// `fieldsFrom` and `fieldsUnderStatedDefault` are for a source that is a run's
    /// FRAME: the fields its containers painted under a cell the frame states no
    /// field for, and under one it puts on the terminal's own by stating `ESC[49m`
    /// — a run's two records (`AnimatedCellRun.ground`,
    /// `AnimatedCellRun.groundUnderStatedDefault`), which the splice draws those
    /// cells over, so each is blended as the cell the splice will show.
    static func blendedSpan(
        source: String,
        destination: String,
        columns: Range<Int>,
        destinationShift: Int,
        fieldsFrom: String? = nil,
        fieldsUnderStatedDefault: String? = nil,
        alpha: (Int) -> CellAlpha?,
        surface: Color,
        defaultForeground: Color
    ) -> String {
        // Pinned rather than clamped: the span is documented as already trimmed to
        // the source's own coordinates, and the walk below indexes `sourceCells` by
        // absolute column with no bounds test — a negative start is `sourceCells[-1]`
        // and aborts. Clamping here instead would silently draw the frame's leading
        // cells at the wrong columns, which is how it went unnoticed; the caller is
        // the only place that knows which cells to drop.
        assert(
            columns.lowerBound >= 0,
            "blendedSpan's span starts left of the source's first column "
                + "(\(columns)): trim it at the caller, which knows what to cut")
        let sourceCells = cells(
            in: source, through: columns.upperBound,
            defaultForeground: defaultForeground, surface: surface)
        // The row a run's frame is spliced INTO, when the source is a frame:
        // a frame cell stating no background wears that row's, exactly as the
        // splice will give it, so it is blended as the cell it replaces.
        let fieldCells = fieldsFrom.map {
            cells(in: $0, through: columns.upperBound, defaultForeground: defaultForeground, surface: surface)
        }
        // And under a cell the frame states the terminal's own field for, what the
        // painters made of THAT: nothing where they let the 49 through, their field
        // where they read it as none. Nothing painted, nothing recorded: the
        // terminal's own.
        let statedDefaultFieldCells = fieldsUnderStatedDefault.map {
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
                    background: lastSourceCell?.background,
                    isReversed: lastSourceCell?.isReversed ?? false,
                    // The character's whole field, including whether it states
                    // the terminal's own: a wide glyph's second column read the
                    // ground where the first read the record under a stated 49.
                    statesTerminalField: lastSourceCell?.statesTerminalField ?? false)
            if sourceCells[column] != nil { lastSourceCell = cell }
            if cell.background == nil,
                let field = (cell.statesTerminalField ? statedDefaultFieldCells : fieldCells)?[column]?.background
            {
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
            // Only where a reversed cell reached this column, on either side: a fill
            // merely stated as the terminal's foreground is spelled here as it is
            // outside a composite, so the two never disagree.
            if cell.isReversed || behind?.isReversed == true {
                blended = Self.spelledWithReverseWhereNeeded(blended)
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
        source: RowCell, destination: RowCell?, alpha: CellAlpha?,
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
        // Every channel, not just the layer: `opacity: 1, inkOpacity: 0.5` is a
        // translucent ink at full layer strength, and the old single test took
        // "the layer wins the cell outright" and returned the source verbatim —
        // eating the colour's alpha whole.
        if alpha.layer >= 1, alpha.ink >= 1, alpha.field >= 1 {
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
        // The LAYER only. Ink at 0 with the layer at 1 is "no glyph, but the
        // field still paints" — not "the source contributes nothing", which
        // would make `.clear` text erase the background it was drawn on.
        guard alpha.layer > 0 else {
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
        //
        // TWO blends for the ink, in this order, because a colour's alpha and a
        // layer's resolve against different things — which is what compositing
        // IS: resolve a layer's own pixels first, then composite the layer over
        // the backdrop.
        //
        // A translucent INK is paint on a surface, and the surface is the field
        // the glyph is drawn on — this layer's own background where it has one,
        // and otherwise the field it will inherit. Never the destination's INK:
        // the source glyph displaced that glyph by winning the cell, so it is
        // not behind anything.
        //
        // This was one multiplied blend against `destinationInk`, and the bug
        // was visible by default in `Table`: a row paints its own background,
        // and translucent ink over it faded toward the PAGE behind the row
        // rather than toward the row. It also put the range's discontinuity at
        // ink 0, where "blend fully toward the destination's ink" means "draw an
        // invisible glyph in the displaced glyph's colour" — dots in the colour
        // of the letters they replaced.
        //
        // The LAYER's blend still resolves against `destinationInk`, unchanged:
        // that one is a contest between two layers' glyphs, and blending toward
        // the loser's colour is what makes a fade over text read as a dissolve.
        // The layer's own field, at its OWN alpha only: the surface this layer's
        // glyphs actually sit on. A translucent field has to be resolved BEFORE
        // the ink blends over it, or the glyph is drawn against a colour its own
        // cell does not end up having — 40% green over FULL red, sitting on a
        // background that is 40% red.
        let fieldWithinLayer =
            source.background.map { $0.opacity(alpha.field, over: destinationField) }
        let ownField = fieldWithinLayer ?? destinationField
        let inkWithinLayer = sourceInk.map { $0.opacity(alpha.ink, over: ownField) }
        let foreground =
            inkWithinLayer.map { $0.opacity(alpha.layer, over: destinationInk) }
            ?? destination?.foreground
        // The field takes the second blend too, and lands on exactly the number
        // one multiplied blend gave: a field is the bottom of its own layer, so
        // both of its backdrops are `destinationField`, and sequential blends
        // against ONE backdrop multiply exactly
        // (`c.opacity(a, over: d).opacity(b, over: d) == c.opacity(a * b, over: d)`).
        // Written as two steps regardless, because the first step is the value the
        // ink needs above and computing it twice is how the two drift apart.
        let background =
            fieldWithinLayer.map { $0.opacity(alpha.layer, over: destinationField) }
            ?? destination?.background

        // Only the glyph needs a DECISION, because a cell can hold one and
        // the contest is between GLYPHS: the cell shows whichever side paints
        // one, and where both do, ½ decides. A side painting no glyph is not a
        // candidate — it has nothing to draw, and "drawing" it would mean
        // erasing the side that does.
        // A TRANSPARENT ink is still in the contest, and this is the one place
        // where a terminal's answer differs from a raster's on purpose.
        //
        // `alpha.ink == 0` does not mean "no glyph". It means the glyph's colour
        // is nothing — which in a cell grid is indistinguishable from painting it
        // in the exact colour of the field, and that is what the blend above
        // produces. Nobody expects `.foregroundColor(.black)` on a black field to
        // let text behind show through, and `.clear` is that colour with the
        // field's name instead of black's.
        //
        // The reason it matters more here than it would on a canvas: a cell's
        // character is the SELECTABLE text. Dropping the glyph makes the cell
        // hold whatever a sibling drew, so a transparent label would be copied out
        // of the terminal as the text underneath it. Emitting it keeps copy and
        // paste honest. Removing something from the picture is what `.hidden()`,
        // `.opacity(0)` and simply not drawing it are for; a transparent colour is
        // a colour.
        let sourcePaintsInk =
            source.character != " " || source.style.paintsInkOnBlankCell
        let destinationPaintsInk =
            destination.map { $0.character != " " || $0.style.paintsInkOnBlankCell } ?? false
        // The LAYER's alpha decides the contest, never the ink's. The contest is
        // between two layers' glyphs — how present this layer is — while a
        // translucent ink has no contest at all: it is one cell's own glyph over
        // its own field, and at 0.4 it should draw faintly rather than disappear.
        let sourceDraws = sourcePaintsInk && (!destinationPaintsInk || alpha.layer >= 0.5)
        // Weight cannot blend — bold, underline and their kin are on or off —
        // so the non-colour styling comes from whichever side drew the glyph.
        var result = sourceDraws ? source : (destination ?? RowCell(character: " ", style: SGRState()))
        result.foreground = foreground
        result.background = background
        result.style = result.style.settingForeground(foreground).settingBackground(background)
        // A glyph whose ink is the page the terminal has not reported, drawn ON that
        // page, draws nothing. It is invisible, but the foreground slot has no
        // spelling for that page and emits 39, so the glyph would show at full
        // strength in the terminal's foreground. It gets here because a blend with
        // no RGB snaps: a label faded below ½ over such a page becomes the page,
        // and so does an ink whose own alpha is below ½, even where its layer is
        // whole and wins the contest. Dropping the glyph makes both a cut at ½, the
        // side of it rule 9 already puts the colours on.
        // The attributes that ink a blank cell go with it (rule 6).
        //
        // This is where §12's "a transparent ink keeps its glyph" gives way. That
        // rule keeps copy and paste honest by emitting the glyph in the field's
        // colour, which here cannot be emitted. `Opacity as composition` §76.
        if Self.isTheUnreportedPageOnItself(ink: foreground, field: background ?? surface) {
            result.character = " "
            result.style.apply("\u{1B}[24;25;29m")
        }
        return result
    }

    /// Whether `ink` is the terminal's page, unreported, and `field` is that page too.
    ///
    /// Only `.terminalBackground`, and only with no RGB. Reported, the foreground
    /// slot spells it as its RGB, so the glyph is emitted in the field's colour as
    /// any other invisible ink is. On a different field the glyph is visible
    /// ink, in the wrong colour (39), and dropping it would lose it.
    ///
    /// Shared with `OpacityFade`, whose rewrite of a drawn line reaches the same
    /// cell (`Opacity as composition` §83).
    static func isTheUnreportedPageOnItself(ink: Color?, field: Color) -> Bool {
        guard let ink, case .terminalBackground = ink.value, case .terminalBackground = field.value else {
            return false
        }
        return ink.rgbComponents == nil
    }

    /// `cell` spelled with reverse video where its colours have no spelling without it.
    ///
    /// A reversed cell is blended in the colours it displays, and the answer is
    /// emitted in them with the 7 dropped. That is exact wherever each colour has a
    /// spelling in the slot it lands in. The terminal's own pair, before the terminal
    /// reports it, has none there: the page as ink emits 39, the terminal's
    /// foreground, and the terminal's foreground as a field emits 49, the page. So
    /// the cell came out un-reversed. Stated the other way round, the field in the
    /// foreground slot and the ink in the background slot, with the 7, both are
    /// exact, and so is every colour that means the same in either slot.
    ///
    /// Two colours mean different things in the two slots, so neither is ever moved
    /// across: a default (`nil`, or `Color.default`), which is 39 in one and 49 in the
    /// other, and the half of the terminal's pair that has no spelling in the slot it
    /// would move to.
    ///
    /// Where neither spelling states both, the ink and the field are the same colour
    /// of the terminal's, so the glyph cannot be seen. It is dropped with the
    /// attributes that ink a blank cell, as ``isTheUnreportedPageOnItself(ink:field:)``
    /// drops one, and the blank takes whichever spelling states its field.
    /// `Opacity as composition` §85.
    private static func spelledWithReverseWhereNeeded(_ cell: RowCell) -> RowCell {
        let paintsInk = cell.character != " " || cell.style.paintsInkOnBlankCell
        let inkIsSpelled = !paintsInk || !isUnreported(cell.foreground, page: true)
        let fieldIsSpelled = !isUnreported(cell.background, page: false)
        guard !inkIsSpelled || !fieldIsSpelled else { return cell }
        var result = cell
        let inkMoves = !paintsInk || movesAcrossSlots(cell.foreground, asPage: false)
        if !(inkMoves && movesAcrossSlots(cell.background, asPage: true)) {
            result.character = " "
            result.style.apply("\u{1B}[24;25;29m")
            guard !fieldIsSpelled else { return result }
        }
        result.style.apply("\u{1B}[7m")
        let ink = movesAcrossSlots(cell.foreground, asPage: false) ? cell.foreground : nil
        result.style = result.style.settingForeground(cell.background).settingBackground(ink)
        return result
    }

    /// Whether `colour` is the terminal's page (`page`) or its foreground, unreported.
    private static func isUnreported(_ colour: Color?, page: Bool) -> Bool {
        guard let colour, colour.rgbComponents == nil else { return false }
        switch colour.value {
        case .terminalBackground: return page
        case .terminalForeground: return !page
        default: return false
        }
    }

    /// Whether `colour` shows the same colour spelled in the other slot: an ink in the
    /// background slot, or a field (`asPage`) in the foreground slot.
    private static func movesAcrossSlots(_ colour: Color?, asPage: Bool) -> Bool {
        guard let colour else { return false }
        if case .terminalDefault = colour.value { return false }
        return !isUnreported(colour, page: asPage)
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
        // `ESC[49m` is the one background report that is `nil`.
        var statesTerminalField = false
        var column = 0
        line.forEachANSISegment { segment in
            switch segment {
            case .ansi(let sequence, let isSGR):
                state.apply(sequence)
                guard isSGR else { return true }
                SGRColorRewrite.readingColors(sequence) { which, color in
                    switch which {
                    case .foreground: foreground = color
                    case .background: background = color; statesTerminalField = color == nil
                    case .reset: foreground = nil; background = nil; statesTerminalField = false
                    }
                }
            case .visible(let character):
                // Past the last cell of the row nothing further can be
                // recorded, so the walk is finished.
                guard column < width else { return false }
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
                    return true
                }
                var cell = RowCell(
                    character: character, style: state,
                    foreground: foreground, background: background,
                    statesTerminalField: statesTerminalField)
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
                    cell.isReversed = true
                }
                result[column] = cell
                column += max(1, character.terminalWidth)
            }
            return true
        }
        return result
    }
}

// MARK: - Setting a colour on a parsed state

extension SGRState {
    /// This state with its foreground replaced. `nil` is the terminal's
    /// default (SGR 39) — what a cell that named no colour of its own had.
    ///
    /// The colour is handed over in the form ``SGRState`` actually keeps — a
    /// named code, a 256-colour index, or three components — not as the
    /// parameter list that spells it. Both routes reach the same state, and
    /// `SGRStateColourSetterTests` pins them equal; this one skips the array
    /// and up-to-five `String`s ``Color/foregroundCodes(depth:)`` builds and
    /// the `Int` parse per code that read them back. Two rounds of the same
    /// removal: the sequence build and its reparse went first (a parse per cell
    /// of every translucent overlay, 17% of that page's frame), and this is the
    /// parameter list that was still passing between them.
    ///
    /// - Parameters:
    ///   - color: The colour, or `nil` for the terminal's default.
    ///   - depth: The depth to quantise for. Defaults to the current one, read
    ///     once per call exactly as the list route read it.
    func settingForeground(_ color: Color?, depth: ColorDepth = ColorDepth.current) -> Self {
        var result = self
        // NIL FIRST, THEN THE DEPTH — not the other way round. This is not a
        // "handle the easy case early" ordering, it is the whole correctness of
        // the function. `nil` means CLEAR the colour, and it clears at every
        // depth, ``ColorDepth/noColor`` included. It is a NON-nil colour at
        // `.noColor` that has to leave the state untouched, because there a
        // colour has no SGR form at all — `foregroundCodes` returns `[]`, and
        // ``SGRState/setForeground(parameters:)`` guards that emptiness rather
        // than applying it. Opening with `guard depth != .noColor` instead
        // would silently stop `nil` clearing on a monochrome terminal, which is
        // the same shape as the fault that guard was written for: a faded bold
        // heading coming back unemphasised.
        guard let color else {
            result.setForeground(nil)  // the SGRState.Colour? overload: SGR 39
            return result
        }
        guard depth != .noColor else { return result }
        result.setForeground(color.sgrForeground(depth: depth))
        return result
    }

    /// This state with its background replaced. `nil` is SGR 49.
    ///
    /// The background twin of ``settingForeground(_:depth:)``, nil-before-depth
    /// rule and all.
    ///
    /// - Parameters:
    ///   - color: The colour, or `nil` for the terminal's default.
    ///   - depth: The depth to quantise for.
    func settingBackground(_ color: Color?, depth: ColorDepth = ColorDepth.current) -> Self {
        var result = self
        // See ``settingForeground(_:depth:)``: nil clears at every depth, a
        // colour at `.noColor` changes nothing.
        guard let color else {
            result.setBackground(nil)  // the SGRState.Colour? overload: SGR 49
            return result
        }
        guard depth != .noColor else { return result }
        result.setBackground(color.sgrBackground(depth: depth))
        return result
    }
}

// MARK: - A colour in the form the state keeps

// Here rather than beside ``Color/foregroundCodes(depth:)``, and not because
// this is where it is used: `SGRState` and `Color` are declared as SIBLING
// modules with no dependency either way, so neither can name the other's type.
// This module is the lowest one that sees both, which makes it the only place
// the mapping can be written.
extension Color {
    /// This colour as the value ``SGRState`` holds for a FOREGROUND slot, at
    /// `depth`.
    ///
    /// The same answer ``foregroundCodes(depth:)`` spells — same downsample,
    /// same codes — without the parameter list in between. The slot matters
    /// only for the NAMED colours (30–37 and 90–97 against 40–47 and 100–107)
    /// and for the two carried terminal colours (39 or 49 in their own slot);
    /// the 256-colour and 24-bit forms carry their 38/48 introducer at render
    /// time, from whichever slot they were stored in, so they are the same
    /// value either way.
    ///
    /// Not defined at ``ColorDepth/noColor``: the answer there is "change
    /// nothing", which no colour value can express. The caller checks — see
    /// ``SGRState/settingForeground(_:depth:)``.
    ///
    /// - Parameter depth: The colour depth to quantise for, never `.noColor`.
    /// - Returns: The colour in `SGRState`'s own form.
    fileprivate func sgrForeground(depth: ColorDepth) -> SGRState.Colour {
        assert(isOpaque, "translucent colour reached sgrForeground: alpha \(alpha)")
        switch downsampled(to: depth).value {
        case .ansi(let slot): return .named(Int(slot.foregroundCode))
        case .palette256(let index): return .indexed(Int(index))
        case .rgb(let red, let green, let blue): return .rgb(Int(red), Int(green), Int(blue))
        case .terminalDefault, .terminalForeground: return .named(Int(ANSIColor.defaultForegroundCode))
        // The other slot: the reported RGB, quantised, or this slot's own default
        // while there is none, as `foregroundCodes` spells it.
        case .terminalBackground:
            guard let paper = rgbComponents else { return .named(Int(ANSIColor.defaultForegroundCode)) }
            return Color.rgb(paper.red, paper.green, paper.blue).sgrForeground(depth: depth)
        case .semantic:
            fatalError(
                "Semantic color must be resolved before rendering. Call Color.resolve(with:) first."
            )
        }
    }

    /// The BACKGROUND twin of ``sgrForeground(depth:)``.
    ///
    /// Kept as a twin rather than folded into one function with a slot
    /// parameter, to match ``foregroundCodes(depth:)`` /
    /// ``backgroundCodes(depth:)`` exactly: four functions with the same shape
    /// in two files, and the codes read off the same two ``ANSIColor``
    /// properties, is easier to keep honest than three plus a branch.
    ///
    /// - Parameter depth: The colour depth to quantise for, never `.noColor`.
    /// - Returns: The colour in `SGRState`'s own form.
    fileprivate func sgrBackground(depth: ColorDepth) -> SGRState.Colour {
        assert(isOpaque, "translucent colour reached sgrBackground: alpha \(alpha)")
        switch downsampled(to: depth).value {
        case .ansi(let slot): return .named(Int(slot.backgroundCode))
        case .palette256(let index): return .indexed(Int(index))
        case .rgb(let red, let green, let blue): return .rgb(Int(red), Int(green), Int(blue))
        case .terminalDefault, .terminalBackground: return .named(Int(ANSIColor.defaultBackgroundCode))
        // The other slot: the reported RGB, quantised, or this slot's own default
        // while there is none, as `backgroundCodes` spells it.
        case .terminalForeground:
            guard let ink = rgbComponents else { return .named(Int(ANSIColor.defaultBackgroundCode)) }
            return Color.rgb(ink.red, ink.green, ink.blue).sgrBackground(depth: depth)
        case .semantic:
            fatalError(
                "Semantic color must be resolved before rendering. Call Color.resolve(with:) first."
            )
        }
    }
}

// MARK: - A region's three channels

extension OpacityRegion {
    /// This region's three channels, as one cell's worth of alpha.
    ///
    /// On `OpacityRegion` rather than in the resolver so every caller that
    /// substitutes an alpha for a region — the row rebuild, the run replay, the
    /// cycle phases — reads the same three fields. `OpacityRegion` lives a module
    /// below `FrameBuffer.CellAlpha`, hence the extension here rather than there.
    var cellAlpha: FrameBuffer.CellAlpha {
        FrameBuffer.CellAlpha(layer: opacity, ink: inkOpacity, field: fieldOpacity)
    }
}

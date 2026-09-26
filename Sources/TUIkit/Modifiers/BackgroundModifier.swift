//  🖥️ TUIkit — Terminal UI Kit for Swift
//  BackgroundModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore
import TUIkitStyling

/// A modifier that fills the background of a view with a ``ShapeStyle``.
///
/// - Important: This is framework infrastructure. Use `.background()` on any
///   ``View`` instead of instantiating this type directly.
public struct BackgroundModifier<S: ShapeStyle>: ViewModifier {
    /// What to fill with.
    let style: S

    /// Fills at this modifier's own type, which is the right owner only when
    /// nothing encloses it — a direct call, never the render path. `ModifiedView`
    /// calls `_modify(buffer:context:owner:)` instead and names itself.
    public func modify(buffer: FrameBuffer, context: RenderContext) -> FrameBuffer {
        _modify(buffer: buffer, context: context, owner: Self.self)
    }

    public func _modify(
        buffer: FrameBuffer, context: RenderContext, owner: Any.Type
    ) -> FrameBuffer {
        guard !buffer.isEmpty else { return buffer }
        let width = buffer.width
        // Through the animator, so a change inside `withAnimation` moves rather
        // than jumping — a colour and every stop of a ramp alike. Returns the
        // paint untouched when nothing is moving.
        //
        // Keyed on the ENCLOSING `ModifiedView`, not on `Self`: this type is not
        // generic over the content, so two `.background`s around one view are
        // one type at one identity and shared a single animation record — the
        // inner one painted the outer's colour for a frame and both fades were
        // then abandoned.
        let paint = PaintAnimation.resolving(
            style.paint(in: context.environment), owner: owner, context: context)

        // A ramp is resolved over the view being filled — its own box, or the
        // rectangle a `.gradientExtent(.subtree)` named. `nil` from the sampler
        // means "not a ramp, or a degenerate one", and both mean paint flat.
        let extent =
            context.gradientFrame ?? GradientFrame(width: width, height: buffer.lines.count)

        // A ramp behind NOTHING — blank cells, which is what a gradient used as
        // a view, or `.background` on a spacer, puts in front of it — can be
        // a picture where the terminal draws them: one colour a pixel instead
        // of one a cell. Behind text it cannot, because a placeholder cell is
        // the image and holds no character; those cells paint below.
        // A TRANSLUCENT ramp never takes the picture path, whatever the terminal
        // can draw. `GradientRaster.picture` sends `rgbComponents` in an `.rgb`
        // format and there is no alpha in it, so this path silently rendered a
        // translucent ramp at full strength — while the cell path below trips the
        // emitter's assertion for the same gradient. Which of those a developer
        // met depended on their terminal: a translucent ramp was quietly wrong on
        // kitty and Ghostty, and loudly unsupported on Apple Terminal.
        //
        // Declining is a better answer than transmitting real RGBA even where the
        // protocol allows it, because the terminal would composite against the
        // cells' own background rather than against what TUIkit knows is behind
        // them — the guess this whole design exists to avoid. Sub-cell smoothness
        // is lost for translucent ramps, and for a ramp with a colour that has no
        // RGB, which `GradientRaster.picture` declines because a pixel cannot hold
        // it.
        if case .gradient = paint, buffer.animatedCells.isEmpty, buffer.isBlank,
            paint.isOpaqueThroughout,
            let graphics = context.gradientGraphics(
                token: "gradient-\(context.identity.path)-\(ObjectIdentifier(owner).hashValue)"),
            let picture = GradientRaster.picture(
                paint: paint, frame: extent, columns: width, rows: buffer.lines.count,
                cellPixels: graphics.cellPixels),
            let lines = graphics.store.placeholderRows(
                token: graphics.token,
                signature: GradientImageSignature(
                    paint: paint, frame: extent, width: picture.width, height: picture.height),
                columns: width, rows: buffer.lines.count,
                pixels: { (picture.bytes, picture.format, picture.width, picture.height) })
        {
            return buffer.replacingLines(lines)
        }

        guard
            let sampler = RampSampler(
                paint: paint, extent: extent, depth: ColorDepth.current,
                cellAspect: context.environment.imageCellAspect)
        else {
            let resolved = paint.representative.resolve(with: context.environment.palette)
            // Fully transparent: paint nothing, which is what `.background` with
            // no background means. Returned whole rather than filled with an
            // invisible colour, and no region either — there is no claim to make
            // about cells this modifier did not touch.
            if resolved.alpha == 0 { return buffer }
            var filledBuffer = buffer.replacingLines(
                buffer.lines.map {
                    filled($0.padToVisibleWidth(width), with: resolved.opaqueSpelling)
                })
            // The rectangle is exactly what was painted: every row was padded to
            // `width` just above, so the claim and the paint agree by
            // construction. A FIELD claim only — the content's own ink is already
            // in these lines and a background says nothing about it, which is what
            // lets `Text("x").background(.red.opacity(0.5))` fade the field and
            // leave the letter alone.
            let claim = OpacityRegion.claim(width: width, height: buffer.lines.count, field: resolved)
            // Said of the fill alone, cell by cell: the fill the cell shows where the
            // content leaves it the field, beneath the content's own field where it
            // states one (§105). Folded with the content's fades as one claim, a label
            // faded inside the fill scaled the fill under it, and the fill's alpha
            // scaled a field the content stated itself.
            filledBuffer.opacityRegions += buffer.claimingPainterField(claim.map { [$0] } ?? [], spelled: resolved.opaqueSpelling.backgroundEscape())
            // The content's runs are drawn on this fill wherever a frame leaves a
            // cell bare, and a replay has no line to read that off: the same fill
            // on their grounds (`AnimatedCellRun.ground`).
            filledBuffer.paintRunGrounds { _, ground in filled(ground, with: resolved.opaqueSpelling) }
            // An opaque fill is the backdrop of every fade inside it, so they are
            // spent here, against it (§96). Carried up, `Text("x").opacity(0.3)
            // .background(.blue)` met the blue at the root as the faded label's
            // own field and faded it toward the page with the label: 30% of the
            // way on a page with an RGB, and on the terminal's own page — a colour
            // with no RGB, the heavier side winning — all the way.
            guard claim == nil else { return filledBuffer }
            return filledBuffer.resolvingOpacity(
                onOpaqueFill: { nil }, surface: resolved, palette: context.environment.palette)
        }

        let palette = context.environment.palette
        // What of this ramp's translucency can be said with rectangles. The two
        // shapes that can are most of what is asked for — an evenly faded ramp,
        // and a ramp down a page — and the one that cannot is a fade running
        // ALONG a row, which stays unhonoured and stays loud: its entries go to
        // the emitter as they are, so `Color+ANSICodes.swift`'s assertion fires.
        // Asked of the STOPS first, which is two or three comparisons: opaque
        // endpoints cannot interpolate to a translucent entry, so an ordinary
        // gradient never walks its sampled ramp. `alphaShape` is O(ramp) and a
        // ramp is one entry per cell of the run, per background, per frame.
        //
        // Deliberately NOT hoisted to share with the picture guard above. That
        // guard reaches its own `isOpaqueThroughout` only after `buffer.isBlank`,
        // which is false for a ramp behind text — the common case — so hoisting
        // makes every background pay for it instead of sharing anything. Measured:
        // this whole arm is `gradients` +0.2% [-0.4%, +0.4%] against having none
        // of it, hoisted or not.
        let alphaShape: RampSampler.AlphaShape =
            paint.isOpaqueThroughout ? .opaque : sampler.alphaShape
        /// The alphas themselves, not `Double(alpha) / 255`: the division belongs in
        /// `OpacityRegion.claim`, which is the one place a claim is derived, and this
        /// was one of three sites doing it by hand.
        var rowFieldAlphas: [UInt8] = []
        // One background escape per ramp ENTRY, built on demand and reused by
        // every later run that lands on the same entry. This is
        // `PaintRenderer.band`'s `sequences` table on the background side, and
        // for the same reason: an escape is not a lookup. `backgroundEscape()`
        // re-quantises the colour, spells it as an array of up to five
        // parameter strings, joins them, concatenates twice, and evaluates
        // `ColorDepth.current` — two task-local reads — as its default
        // argument. A block fill walks every entry once per ROW, so all of
        // that was asked once per run.
        //
        // Deliberately NOT sized here: the `variesAcrossRow` fast path below
        // never touches the table, and an array per fill to hold one entry is
        // what `band`'s own note measured as the entire cost of
        // `.gradientExtent(.subtree)`.
        var escapes: [String?] = []
        /// The background escape for ramp entry `entry`, from the table above —
        /// reused by every later run, and every later ROW, that lands on the same
        /// entry.
        func escape(forEntry entry: Int) -> String {
            if escapes.isEmpty {
                escapes = [String?](repeating: nil, count: sampler.ramp.count)
            }
            // Bound with `if let` rather than tested for `nil` and then read
            // again with `??`: this runs once per run, and each `[String?]`
            // subscript is a retain and release of the cached string, so the
            // two-read spelling gives back part of what the table saves.
            if let cached = escapes[entry] { return cached }
            let colour = sampler.ramp[entry].resolve(with: palette)
            let built = ANSIRenderer.backgroundCode(for: colour.opaqueSpelling)
            escapes[entry] = built
            return built
        }
        /// `cells` — `width` of them — cut at `runs`' boundaries and each piece
        /// filled with its entry: a row of the content, or a run's ground.
        ///
        /// The cut carries the styling that was in force where it fell, so the
        /// content's own colours survive being divided; the pieces are joined and
        /// closed once at the end.
        ///
        /// All the cuts at once: a smooth ramp changes colour at nearly every
        /// column, and slicing one run at a time rebuilt this row's segment list
        /// and rescanned it from the first byte for each of them.
        func painted(_ cells: String, over runs: [(columns: Range<Int>, entry: Int)], width: Int) -> String {
            var result = ""
            // What THIS path emits, which is not two bytes a cell: a run per
            // cell, each an SGR introducer (~19 bytes at truecolor) plus a
            // reset, on top of whatever escapes the content already carried.
            // `band` reserves 25 bytes a CELL for the same shape
            // (PaintRenderer.swift:180); the cell count here is `width`, not
            // `cells.utf8.count`, because `cells` already contains the
            // content's own escapes and multiplying those by 25 would reserve
            // tens of kilobytes for a heavily styled row.
            result.reserveCapacity(width * 25 + cells.utf8.count + 16)
            cells.ansiAwareSlicedRuns(
                runCount: runs.count,
                width: { runs[$0].columns.count },
                receive: { index, slice in
                    let escape = escape(forEntry: runs[index].entry)
                    // `applyPersistentBackground` spelled out rather than
                    // called: it IS `escape + restating(escape,
                    // afterResetsIn:)`, and it built that sum as one more heap
                    // string just so this could append it. Appending the two
                    // halves is the same bytes without the throwaway.
                    //
                    // `""` — which is what a `.noColor` depth gives — restates
                    // nothing and appends nothing, exactly as before: the empty
                    // guard is inside `restating` itself, and a built-but-empty
                    // escape stores as `.some("")`, so `if let` does not
                    // mistake it for one that has not been built.
                    result += escape
                    result += ANSIRenderer.restating(escape, afterResetsIn: slice)
                })
            return result + ANSIRenderer.reset
        }
        /// Row `row` of the content — or of nothing but the ramp — painted.
        func paintedRow(_ padded: String, row: Int) -> String {
            guard sampler.variesAcrossRow else {
                // One colour for the whole row: the same single persistent-fill
                // this modifier has always emitted, and no per-cell work at all.
                let colour = sampler.colour(row: row).resolve(with: palette)
                if case .perRow = alphaShape { rowFieldAlphas.append(colour.alpha) }
                return filled(padded, with: colour.opaqueSpelling)
            }
            // Otherwise the row is cut at the ramp's own boundaries and each
            // piece filled.
            return painted(padded, over: sampler.runs(row: row, cells: width), width: width)
        }
        let lines = buffer.lines.enumerated().map { row, line in
            paintedRow(line.padToVisibleWidth(width), row: row)
        }

        // Background colouring is a styling pass — content stays in
        // place (no horizontal or vertical shift), so overlays and
        // hit-test regions carry through unshifted. Using the bare
        // FrameBuffer(lines:) initializer here would silently drop
        // the child's regions, breaking clicks on any control with a
        // .background() modifier applied to it.
        var ramped = buffer.replacingLines(lines)
        // FIELD claims only, as the flat arm makes: the content's own ink is
        // already in these lines and a background says nothing about it.
        //
        // Said of the ramp alone, cell by cell, as the flat arm's are (§105).
        ramped.opacityRegions += Self.saidOfTheRamp(
            for: alphaShape, rowAlphas: rowFieldAlphas, over: buffer, sampler: sampler, width: width,
            palette: palette, escape: escape(forEntry:))
        // And each run's ground, painted as its row was over the run's columns —
        // the ramp's cells differ across a row, so each piece gets its own entry,
        // exactly as the row's did (`AnimatedCellRun.ground`).
        ramped.paintRunGrounds { run, ground in
            guard sampler.variesAcrossRow else {
                return filled(ground, with: sampler.colour(row: run.offsetY).resolve(with: palette).opaqueSpelling)
            }
            let columns = run.offsetX..<(run.offsetX + run.width)
            let under = sampler.runs(row: run.offsetY, cells: width).compactMap { piece -> (columns: Range<Int>, entry: Int)? in
                let kept = piece.columns.clamped(to: columns)
                guard !kept.isEmpty else { return nil }
                return ((kept.lowerBound - run.offsetX)..<(kept.upperBound - run.offsetX), piece.entry)
            }
            return painted(ground, over: under, width: run.width)
        }
        // An opaque ramp is the backdrop of every fade inside it, as a flat fill
        // is (§96), and a different one under each cell: the fade is spent over
        // the ramp alone, painted as the content was.
        guard case .opaque = alphaShape else { return ramped }
        let blank = String(repeating: " ", count: width)
        return ramped.resolvingOpacity(
            onOpaqueFill: { FrameBuffer(lines: buffer.lines.indices.map { paintedRow(blank, row: $0) }) },
            surface: palette.background, palette: palette)
    }

    /// The ramp's ``fieldClaims(for:width:rows:rowAlphas:sampler:)`` over `content`,
    /// said of the ramp alone (`FrameBuffer.claimingPainterField(_:spelledAt:)`, §105):
    /// beneath a field the content states itself, the ramp's entry at that cell, spelled
    /// as the row painted it (`escape`, by entry).
    private static func saidOfTheRamp(
        for alphaShape: RampSampler.AlphaShape, rowAlphas: [UInt8], over content: FrameBuffer,
        sampler: RampSampler, width: Int, palette: any Palette, escape: (Int) -> String
    ) -> [OpacityRegion] {
        let claims = fieldClaims(
            for: alphaShape, width: width, rows: content.lines.count, rowAlphas: rowAlphas, sampler: sampler)
        var entries: [Int: [(columns: Range<Int>, entry: Int)]] = [:]
        return content.claimingPainterField(claims) { row, column in
            guard sampler.variesAcrossRow else {
                return ANSIRenderer.backgroundCode(for: sampler.colour(row: row).resolve(with: palette).opaqueSpelling)
            }
            let pieces = entries[row] ?? sampler.runs(row: row, cells: width)
            entries[row] = pieces
            return escape(pieces.first { $0.columns.contains(column) }?.entry ?? 0)
        }
    }

    /// The FIELD claims a ramp of this shape owes over a `width` × `rows` block.
    ///
    /// Field claims only, as the flat arm makes: the content's own ink is already in
    /// these lines and a background says nothing about it.
    ///
    /// Its own function because ``paintedBackground`` reached the body-length limit
    /// with the third shape — and because it is the half of that function with no
    /// bytes in it, which makes the split a real seam rather than a place to hide four
    /// lines.
    private static func fieldClaims(
        for alphaShape: RampSampler.AlphaShape, width: Int, rows: Int,
        rowAlphas: [UInt8], sampler: RampSampler
    ) -> [OpacityRegion] {
        var painted: [OpacityRegion] = []
        switch alphaShape {
        case .opaque:
            break
        case .uniform(let alpha):
            painted.append(
                OpacityRegion(
                    offsetX: 0, offsetY: 0, width: width, height: rows,
                    opacity: 1, fieldOpacity: OpacityRegion.opacity(of: alpha)))
        case .perRow:
            // One rectangle per row, in the order the rows were painted, so the
            // claim and the paint cannot disagree about which alpha is where.
            //
            // Built directly rather than through `OpacityRegion.claim`, which answers
            // `nil` for a fully opaque paint: a scrim's top rows ARE opaque, and
            // dropping them would leave the claims no longer index-aligned with the
            // rows they were painted for. The `nil` contract is right where a claim
            // is optional and wrong where the set of them is a sequence.
            painted += rowAlphas.enumerated().map { row, alpha in
                OpacityRegion(
                    offsetX: 0, offsetY: row, width: width, height: 1,
                    opacity: 1, fieldOpacity: OpacityRegion.opacity(of: alpha))
            }
        case .perColumn:
            // One FULL-HEIGHT strip per run of equal alpha. Row 0 answers for every
            // row by construction — that is what `perColumn` means — so the runs are
            // walked once rather than per row, and `alphaRuns` coalesces on the alpha
            // rather than on the ramp entry, so a smooth eighty-column fade between
            // two equally-faded stops is ONE rectangle and not eighty.
            painted += sampler.alphaRuns(row: 0, columns: 0..<width)
                .map { run in
                    OpacityRegion(
                        offsetX: run.columns.lowerBound, offsetY: 0, width: run.columns.count,
                        height: rows, opacity: 1,
                        fieldOpacity: OpacityRegion.opacity(of: run.alpha))
                }
        case .perCell:
            // The same runs, asked per ROW — which is the whole difference between
            // this shape and the one above, and why they are not one case here as
            // they are in `PaintRenderer.claims`: a strip cannot span rows that
            // disagree, so the height is 1 and the walk repeats.
            //
            // This is the shape whose claim count grows with the block's AREA
            // rather than its width, and the only one that does. §36 measures it.
            for row in 0..<rows {
                painted += sampler.alphaRuns(row: row, columns: 0..<width)
                    .map { run in
                        OpacityRegion(
                            offsetX: run.columns.lowerBound, offsetY: row,
                            width: run.columns.count, height: 1, opacity: 1,
                            fieldOpacity: OpacityRegion.opacity(of: run.alpha))
                    }
            }
        }
        return painted
    }

    /// Applies background color to a string, preserving existing formatting.
    ///
    /// Uses a *persistent* background (re-applied after every interior reset)
    /// so child content that emits its own ANSI resets — Text, a Slider's track,
    /// a Toggle's brackets — doesn't punch holes in the fill. A final reset
    /// closes the run so the colour doesn't bleed past the line.
    private func filled(_ string: String, with color: Color) -> String {
        ANSIRenderer.applyPersistentBackground(string, color: color) + ANSIRenderer.reset
    }
}

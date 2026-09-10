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
        // is lost for translucent ramps only.
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
            if let claim = OpacityRegion.claim(
                width: width, height: buffer.lines.count, field: resolved)
            {
                filledBuffer.opacityRegions.append(claim)
            }
            return filledBuffer
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
        // Spelled opaque ONLY where the alpha is being carried. Spelling it opaque
        // everywhere would silence the assertion for the case that is not
        // honoured, turning a loud gap into a discarded alpha.
        let carriesAlpha = alphaShape != .perCell
        var rowFieldAlphas: [Double] = []
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
        let lines = buffer.lines.enumerated().map { row, line -> String in
            let padded = line.padToVisibleWidth(width)
            guard sampler.variesAcrossRow else {
                // One colour for the whole row: the same single persistent-fill
                // this modifier has always emitted, and no per-cell work at all.
                let colour = sampler.colour(row: row).resolve(with: palette)
                if carriesAlpha { rowFieldAlphas.append(Double(colour.alpha) / 255) }
                return filled(
                    padded, with: carriesAlpha ? colour.opaqueSpelling : colour)
            }
            // Otherwise the row is cut at the ramp's own boundaries and each
            // piece filled. The cut carries the styling that was in force where
            // it fell, so the content's own colours survive being divided; the
            // pieces are joined and closed once at the end.
            //
            // All the cuts at once: a smooth ramp changes colour at nearly every
            // column, and slicing one run at a time rebuilt this row's segment
            // list and rescanned it from the first byte for each of them.
            let runs = sampler.runs(row: row, cells: width)
            if escapes.isEmpty {
                escapes = [String?](repeating: nil, count: sampler.ramp.count)
            }
            var result = ""
            // What THIS path emits, which is not two bytes a cell: a run per
            // cell, each an SGR introducer (~19 bytes at truecolor) plus a
            // reset, on top of whatever escapes the content already carried.
            // `band` reserves 25 bytes a CELL for the same shape
            // (PaintRenderer.swift:180); the cell count here is `width`, not
            // `padded.utf8.count`, because `padded` already contains the
            // content's own escapes and multiplying those by 25 would reserve
            // tens of kilobytes for a heavily styled row.
            result.reserveCapacity(width * 25 + padded.utf8.count + 16)
            padded.ansiAwareSlicedRuns(
                runCount: runs.count,
                width: { runs[$0].columns.count },
                receive: { index, slice in
                    let entry = runs[index].entry
                    // One background escape per ramp ENTRY, reused by every
                    // later run — and every later ROW — that lands on the same
                    // one. `PaintRenderer.band`'s `sequences` table on the
                    // background side, for the same reason: an escape is not a
                    // lookup. `backgroundEscape()` re-quantises the colour,
                    // spells it as an array of up to five parameter strings,
                    // joins them, concatenates twice, and evaluates
                    // `ColorDepth.current` — two task-local reads — as its
                    // default argument. A block fill walks every entry once per
                    // ROW, so all of that was asked once per run.
                    //
                    // Bound with `if let` rather than tested for `nil` and then
                    // read again with `??`: this runs once per run, and each
                    // `[String?]` subscript is a retain and release of the
                    // cached string, so the two-read spelling gives back part
                    // of what the table saves.
                    let escape: String
                    if let cached = escapes[entry] {
                        escape = cached
                    } else {
                        let colour = sampler.ramp[entry].resolve(with: palette)
                        escape = ANSIRenderer.backgroundCode(
                            for: carriesAlpha ? colour.opaqueSpelling : colour)
                        escapes[entry] = escape
                    }
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

        // Background colouring is a styling pass — content stays in
        // place (no horizontal or vertical shift), so overlays and
        // hit-test regions carry through unshifted. Using the bare
        // FrameBuffer(lines:) initializer here would silently drop
        // the child's regions, breaking clicks on any control with a
        // .background() modifier applied to it.
        var painted = buffer.replacingLines(lines)
        // FIELD claims only, as the flat arm makes: the content's own ink is
        // already in these lines and a background says nothing about it.
        switch alphaShape {
        case .opaque, .perCell:
            break
        case .uniform(let alpha):
            painted.opacityRegions.append(
                OpacityRegion(
                    offsetX: 0, offsetY: 0, width: width, height: buffer.lines.count,
                    opacity: 1, fieldOpacity: Double(alpha) / 255))
        case .perRow:
            // One rectangle per row, in the order the rows were painted, so the
            // claim and the paint cannot disagree about which alpha is where.
            painted.opacityRegions += rowFieldAlphas.enumerated().map { row, alpha in
                OpacityRegion(
                    offsetX: 0, offsetY: row, width: width, height: 1,
                    opacity: 1, fieldOpacity: alpha)
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

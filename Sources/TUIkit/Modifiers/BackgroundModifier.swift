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
    /// calls ``_modify(buffer:context:owner:)`` instead and names itself.
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
        if case .gradient = paint, buffer.animatedCells.isEmpty, buffer.isBlank,
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
            return buffer.replacingLines(
                buffer.lines.map { filled($0.padToVisibleWidth(width), with: resolved) })
        }

        let palette = context.environment.palette
        let lines = buffer.lines.enumerated().map { row, line -> String in
            let padded = line.padToVisibleWidth(width)
            guard sampler.variesAcrossRow else {
                // One colour for the whole row: the same single persistent-fill
                // this modifier has always emitted, and no per-cell work at all.
                return filled(padded, with: sampler.colour(row: row).resolve(with: palette))
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
            var result = ""
            result.reserveCapacity(padded.utf8.count * 2 + 16)
            padded.ansiAwareSlicedRuns(
                runCount: runs.count,
                width: { runs[$0].columns.count },
                receive: { index, slice in
                    result += ANSIRenderer.applyPersistentBackground(
                        slice, color: runs[index].colour.resolve(with: palette))
                })
            return result + ANSIRenderer.reset
        }

        // Background colouring is a styling pass — content stays in
        // place (no horizontal or vertical shift), so overlays and
        // hit-test regions carry through unshifted. Using the bare
        // FrameBuffer(lines:) initializer here would silently drop
        // the child's regions, breaking clicks on any control with a
        // .background() modifier applied to it.
        return buffer.replacingLines(lines)
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

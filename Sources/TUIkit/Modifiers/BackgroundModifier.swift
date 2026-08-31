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

    public func modify(buffer: FrameBuffer, context: RenderContext) -> FrameBuffer {
        guard !buffer.isEmpty else { return buffer }
        let width = buffer.width
        let paint = style.paint(in: context.environment)

        // A ramp is resolved over the view being filled — its own box, or the
        // rectangle a `.gradientExtent(.subtree)` named. `nil` from the sampler
        // means "not a ramp, or a degenerate one", and both mean paint flat.
        let extent =
            context.gradientFrame ?? GradientFrame(width: width, height: buffer.lines.count)
        guard
            let sampler = RampSampler(
                paint: paint, extent: extent, depth: ColorDepth.current,
                cellAspect: context.environment.imageCellAspect)
        else {
            // Through the animator, so a change to the colour inside
            // `withAnimation` fades rather than jumps. Returns the colour
            // untouched when nothing is moving.
            let animated = ColorAnimation.resolving(
                paint.representative, owner: Self.self, context: context)
            let resolved = animated.resolve(with: context.environment.palette)
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
            // piece filled. `ansiAwareSlice` carries the styling that was in
            // force at the cut, so the content's own colours survive being
            // divided; the pieces are joined and closed once at the end.
            var result = ""
            result.reserveCapacity(padded.utf8.count * 2 + 16)
            for run in sampler.runs(row: row, cells: width) {
                let slice = padded.ansiAwareSlice(
                    visibleStart: run.columns.lowerBound, visibleCount: run.columns.count)
                result += ANSIRenderer.applyPersistentBackground(
                    slice, color: run.colour.resolve(with: palette))
            }
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

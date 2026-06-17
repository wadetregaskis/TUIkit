//  🖥️ TUIKit — Terminal UI Kit for Swift
//  BackgroundModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

/// A modifier that fills the background of a view with a color.
///
/// - Important: This is framework infrastructure. Use `.background()` on any
///   ``View`` instead of instantiating this type directly.
public struct BackgroundModifier: ViewModifier {
    /// The background color.
    let color: Color

    public func modify(buffer: FrameBuffer, context: RenderContext) -> FrameBuffer {
        guard !buffer.isEmpty else { return buffer }

        let resolvedColor = color.resolve(with: context.environment.palette)
        let width = buffer.width
        var lines: [String] = []

        for line in buffer.lines {
            // Pad the line to full width so background covers everything
            let paddedLine = line.padToVisibleWidth(width)

            // Fill the whole line with the background. The child's own ANSI
            // resets (a Text's trailing reset, a Slider track, a Toggle's `[`)
            // would otherwise clear our background for the rest of the line —
            // so re-apply it after every reset (persistent background) and
            // close with a single reset at the line end to avoid bleed.
            let colored = applyBackground(to: paddedLine, color: resolvedColor)
            lines.append(colored)
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
    private func applyBackground(to string: String, color: Color) -> String {
        ANSIRenderer.applyPersistentBackground(string, color: color) + ANSIRenderer.reset
    }
}

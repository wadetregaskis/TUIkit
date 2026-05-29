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

            // We need to handle existing ANSI codes in the line
            // For simplicity, we wrap the whole line with background
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
    private func applyBackground(to string: String, color: Color) -> String {
        ANSIRenderer.backgroundCode(for: color) + string + ANSIRenderer.reset
    }
}

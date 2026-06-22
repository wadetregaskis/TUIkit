//  🖥️ TUIKit — Terminal UI Kit for Swift
//  DimmedModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

/// A modifier that strips all styling from content and replaces it with
/// a uniform dimmed appearance using only two colors.
///
/// When showing overlays, alerts, or dialogs, the background content
/// should visually recede. This modifier removes all ANSI formatting
/// (borders, backgrounds, colors) and all decorative characters
/// (box-drawing, indicators) — then re-renders each line
/// with a dimmed foreground on `palette.overlayBackground`.
/// The result is a flat, de-emphasized text layer with no visual ornaments.
public struct DimmedModifier<Content: View>: View {
    /// The content to dim.
    let content: Content

    public var body: Never {
        fatalError("DimmedModifier renders via Renderable")
    }
}

// MARK: - Equatable Conformance

extension DimmedModifier: @preconcurrency Equatable where Content: Equatable {
    public static func == (lhs: DimmedModifier<Content>, rhs: DimmedModifier<Content>) -> Bool {
        lhs.content == rhs.content
    }
}

// MARK: - Ornament Characters

/// Characters that are purely decorative and should be replaced with spaces
/// when flattening content for dimmed overlay backgrounds.
///
/// Includes box-drawing characters (light, rounded, double, heavy)
/// and UI indicators (▸, ●, ▶).
private enum DimmedOrnaments {
    static let characters: Set<Character> = {
        var chars = Set<Character>()

        // Box-drawing: light
        chars.formUnion(["┌", "┐", "└", "┘", "─", "│", "├", "┤", "┬", "┴", "┼"])
        // Box-drawing: rounded
        chars.formUnion(["╭", "╮", "╰", "╯"])
        // Box-drawing: double
        chars.formUnion(["╔", "╗", "╚", "╝", "═", "║", "╠", "╣", "╦", "╩", "╬"])
        // Box-drawing: heavy
        chars.formUnion(["┏", "┓", "┗", "┛", "━", "┃", "┣", "┫", "┳", "┻", "╋"])
        // UI indicators
        chars.formUnion(["▸", "◂", "▶", "◀", "●", "▪"])

        return chars
    }()
}

// MARK: - Renderable

extension DimmedModifier: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let contentBuffer = TUIkit.renderToBuffer(content, context: context)

        guard !contentBuffer.isEmpty else {
            return contentBuffer
        }

        let palette = context.environment.palette
        let foreground = palette.foregroundTertiary
        let background = palette.overlayBackground

        // Strip all ANSI codes and ornament characters, then re-apply
        // uniform dimmed styling. This removes borders and indicators —
        // leaving only plain text on a uniform dimmed background.
        let dimmedLines = contentBuffer.lines.map { line -> String in
            flattenLine(line, foreground: foreground, background: background, width: contentBuffer.width)
        }

        // Intentionally use the bare FrameBuffer(lines:) initializer
        // rather than `contentBuffer.replacingLines(...)`: dimming
        // is applied to background content behind a modal / alert,
        // and that background MUST become fully inert while the
        // modal is up.
        //
        // - hit-test regions are dropped so clicks on dimmed
        //   buttons / text fields / etc. don't fire (the modal
        //   above is responsible for intercepting input).
        // - overlay layers are dropped so a popover / picker that
        //   was open on the background before the modal appeared
        //   doesn't continue to draw on top, half-bright, in front
        //   of the dimmed backdrop.
        //
        // The intent is "this layer is a flat, non-interactive
        // backdrop". If you find yourself wanting to preserve
        // either, you almost certainly want a different modifier.
        return FrameBuffer(lines: dimmedLines)
    }

    /// Strips all ANSI formatting and ornament characters from a line,
    /// then applies uniform dimmed colors.
    ///
    /// The line is padded to the full buffer width so the dimmed background
    /// covers the entire row without gaps.
    ///
    /// - Parameters:
    ///   - line: The original line with ANSI codes and ornaments.
    ///   - foreground: The dimmed foreground color.
    ///   - background: The dimmed background color.
    ///   - width: The target width to pad to.
    /// - Returns: The flattened, uniformly styled line.
    private func flattenLine(_ line: String, foreground: Color, background: Color, width: Int) -> String {
        let stripped = line.stripped
        let cleaned = String(stripped.map { DimmedOrnaments.characters.contains($0) ? " " : $0 })
        let paddedText = cleaned.padding(toLength: width, withPad: " ", startingAt: 0)

        var style = TextStyle()
        style.foregroundColor = foreground
        style.backgroundColor = background
        style.isDim = true

        return ANSIRenderer.render(paddedText, with: style)
            .withPersistentBackground(background)
    }
}

// MARK: - Layoutable

extension DimmedModifier: Layoutable {
    /// Dimming rewrites each line in place — same line count, each padded to the
    /// content width — so the dimmed layer is exactly `content`'s size and
    /// flexibility.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

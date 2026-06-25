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
        let palette = context.environment.palette
        return contentBuffer.dimmedAsBackdrop(
            foreground: palette.foregroundTertiary, background: palette.overlayBackground)
    }
}

extension FrameBuffer {
    /// Returns a flat, inert, dimmed copy of this buffer for use as the backdrop
    /// behind a modal / alert: every line is stripped of ANSI codes and ornament
    /// characters (borders, indicators) and re-rendered as a dimmed `foreground`
    /// on a uniform `background`, padded to the full width so no gaps show.
    ///
    /// Hit-test regions and nested overlay layers are intentionally dropped — the
    /// backdrop MUST be fully inert while the modal is up: clicks on dimmed
    /// controls must not fire (the modal intercepts input), and a popover/picker
    /// that was open behind the modal must not keep drawing half-bright on top.
    public func dimmedAsBackdrop(foreground: Color, background: Color) -> FrameBuffer {
        guard !isEmpty else { return self }
        let width = self.width
        let dimmed = lines.map { line -> String in
            let cleaned = String(line.stripped.map { DimmedOrnaments.characters.contains($0) ? " " : $0 })
            let paddedText = cleaned.padding(toLength: width, withPad: " ", startingAt: 0)
            var style = TextStyle()
            style.foregroundColor = foreground
            style.backgroundColor = background
            style.isDim = true
            return ANSIRenderer.render(paddedText, with: style).withPersistentBackground(background)
        }
        return FrameBuffer(lines: dimmed)
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

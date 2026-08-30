//  🖥️ TUIkit — Terminal UI Kit for Swift
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
        // Box-drawing: block and blank (`Appearance.block`). Without these a
        // block-bordered page behind a modal kept its solid bands at full
        // strength while everything around them receded — the loudest chrome
        // on the page was the only thing that did not dim.
        chars.formUnion(["█", "▀", "▄", "▌", "▐"])
        // UI indicators
        chars.formUnion(["▸", "◂", "▶", "◀", "●", "▪"])

        return chars
    }()
}

// MARK: - Renderable

extension DimmedModifier: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Rendered through the backdrop isolation, so what LOOKS inert IS
        // inert. `.dimmed()` flattens its content to a recessive text layer;
        // that is a statement about the content's role, and content in that
        // role must not still be reachable by Tab, still run its `onKeyPress`,
        // still fire a `.keyboardShortcut` or still publish status-bar items.
        // It stops being clickable already — the flatten drops the buffer's
        // hit-test regions — so the mouse was the only channel it had closed.
        //
        // The same helper the presentation modifiers use for the page beneath
        // a modal, and for the same reason. State storage stays shared, so a
        // dimmed subtree keeps its `@State` and its scroll position.
        let contentBuffer = TUIkit.renderToBuffer(
            content, context: context.isolatedForBackground())
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
    ///
    /// ``FrameBuffer/animatedCells`` are **kept**, each frame flattened by the
    /// same rule as the lines. Inert is a statement about INPUT: a backdrop the
    /// user can see is a backdrop that has to keep moving, and a run is the only
    /// way it can move without a full render per tick. Dropped, an indeterminate
    /// bar behind a sheet advanced only when something else happened to render —
    /// which on the Example's Progress page was about 2.5 times a second against
    /// the 30 it managed with no dialog up, and every one of those ticks a whole
    /// re-render of page, dim and dialog.
    ///
    /// A run whose frames all flatten to the SAME picture is dropped instead:
    /// the block glyphs an indeterminate bar animates in are ornaments, so a
    /// `.pulse` bar has nothing left to show once they are spaces, and keeping
    /// its run alive would hold the clock open to repaint an unchanging row.
    public func dimmedAsBackdrop(foreground: Color, background: Color) -> FrameBuffer {
        guard !isEmpty else { return self }
        let width = self.width
        let wrap = Flattening(foreground: foreground, background: background)
        var result = FrameBuffer(lines: lines.map { wrap($0, toWidth: width) })
        result.animatedCells = animatedCells.compactMap { run in
            let dimmed = AnimatedCellRun(
                offsetX: run.offsetX, offsetY: run.offsetY, width: run.width,
                frames: run.frames.map { wrap($0, toWidth: run.width) },
                frameDuration: run.frameDuration, clock: run.clock)
            return dimmed.isAnimating ? dimmed : nil
        }
        return result
    }
}

/// The one styling every flattened row and every frame of every flattened run
/// is wrapped in, derived once.
///
/// Every one of them is the same two colours and the same dim, so
/// `ANSIRenderer.render` was re-deriving one `TextStyle`'s codes, re-joining
/// them and then re-scanning the result for resets to make the background
/// persistent — per line, and per frame of every run on the page. A backdrop
/// carrying a few indeterminate progress bars is several hundred of those a
/// render. See ``ANSIRenderer/styleSequence(for:)``, which exists for exactly
/// this and says so.
private struct Flattening {
    private let prefix: String
    private let suffix: String

    init(foreground: Color, background: Color) {
        var style = TextStyle()
        style.foregroundColor = foreground
        style.backgroundColor = background
        style.isDim = true
        let backgroundCode = ANSIRenderer.backgroundCode(for: background)
        // Byte-for-byte what `render(_:with:) + withPersistentBackground(_:)`
        // produced: the persistent background re-states itself after each
        // reset, and flattened text is stripped, so the only reset is the one
        // `render` closes with. The trailing reset terminates the background at
        // the line's edge — left active it bleeds into whatever is composited
        // to the right (the same class as the List `.plain` selection bleed).
        if let sequence = ANSIRenderer.styleSequence(for: style) {
            prefix = backgroundCode + sequence
            suffix = ANSIRenderer.reset + backgroundCode + ANSIRenderer.reset
        } else {
            prefix = backgroundCode
            suffix = ANSIRenderer.reset
        }
    }

    /// One row — or one frame of a run covering part of a row — stripped of its
    /// styling and ornaments and re-rendered dim.
    ///
    /// Shared so that a run's frames are flattened by exactly the rule its row
    /// was: the splice puts them into a line that is one uniform dim span, and
    /// a frame carrying any other styling would show as a bright notch in it.
    func callAsFunction(_ text: String, toWidth width: Int) -> String {
        let cleaned = String(
            text.stripped.map { DimmedOrnaments.characters.contains($0) ? " " : $0 })
        // Pad in CELLS, not code units: `padding(toLength:)` counts UTF-16
        // units, so a line with CJK (1 unit, 2 cells) came out too wide and
        // NFD combining sequences (2 units, 1 cell) too narrow — the
        // backdrop's right edge then drifted behind every modal over such
        // content. `padToVisibleWidth` measures like the rest of the layout.
        return prefix + cleaned.padToVisibleWidth(width) + suffix
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

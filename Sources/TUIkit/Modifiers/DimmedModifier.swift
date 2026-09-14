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
    /// Hit-test regions are intentionally dropped — the backdrop MUST be fully
    /// inert while the modal is up, and clicks on dimmed controls must not fire
    /// (the modal intercepts input anyway, but the regions would still be there to
    /// be hit if the modal ever failed to).
    ///
    /// ``FrameBuffer/overlays`` are **kept**, and this comment used to say they
    /// were dropped. They ride through because a backdrop is dimmed *under* a
    /// modal and anything still waiting to be drawn above it must not vanish; the
    /// modal's own panel is one of them. (The concern the old wording named — a
    /// popover left open behind the modal drawing half-bright on top — is handled
    /// where the layers are composited, not by discarding them here.)
    ///
    /// The content's ``FrameBuffer/opacityRegions`` are dropped, and unlike the hit
    /// regions that is because they have been CONSUMED rather than suppressed. The
    /// flatten rewrites every cell to one foreground on one background, so a region
    /// saying "these cells are 40% translucent" no longer describes anything that is
    /// there: honouring it would fade the DIM toward whatever is behind the page.
    ///
    /// What replaces them is ONE region of the flatten's own, because the two colours
    /// it washes everything in can themselves be translucent — `overlayBackground`
    /// and `foregroundTertiary` both carry a faded theme's alpha since §39, and both
    /// reached the emitter and trapped (§68.5). The dim is flat, which is a statement
    /// about it being one colour everywhere and not about that colour being opaque:
    /// whether it is, is the theme's business. So the FIELD is claimed — every cell
    /// of a backdrop is painted in it, and a translucent theme means the terminal
    /// shows through the wash — while the INK is SPENT against that field, because a
    /// dimmed row's glyphs sit on the wash and nowhere else, and an ink claim would
    /// also cover the blanks between words, where there is no glyph to blend and what
    /// is behind would show through a cell this one painted. Stated because a bare
    /// `FrameBuffer(lines:)` that re-attaches some payloads and not others is the
    /// shape a dropped payload hides in, and the next reader should not have to
    /// work out which of these three drops was an oversight.
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
    /// A kept run's per-frame alpha (``AnimatedCellRun/alpha``) is dropped, and that
    /// too is consumed rather than lost, unlike the rebuilds that must carry it. The
    /// payload describes what the run's ORIGINAL colours owed, and the flatten repaints
    /// every frame in the wash's two, so the one field claim below is true of every
    /// frame. Kept, it would also sit under that claim, and the resolver multiplies a
    /// payload into whatever covers it, so the wash's field would be faded twice on
    /// every frame the payload spoke for.
    ///
    /// A run whose frames all flatten to the SAME picture is dropped instead:
    /// the block glyphs an indeterminate bar animates in are ornaments, so a
    /// `.pulse` bar has nothing left to show once they are spaces, and keeping
    /// its run alive would hold the clock open to repaint an unchanging row.
    public func dimmedAsBackdrop(foreground: Color, background: Color) -> FrameBuffer {
        guard !isEmpty else { return self }
        let width = self.width
        // Opaque bytes for both channels, and the field's alpha claimed below. The
        // ink is spent against the field rather than claimed beside it — see the
        // note above on why the two channels are answered differently.
        let wrap = Flattening(
            foreground: foreground.spendingAlpha(over: background),
            background: background.opaqueSpelling)
        var result = FrameBuffer(lines: lines.map { wrap($0, toWidth: width) })
        // Pending layers ride through: a backdrop is dimmed under a modal,
        // and anything still waiting to be drawn above it must not vanish.
        result.overlays = overlays
        result.animatedCells = animatedCells.compactMap { run in
            let dimmed = AnimatedCellRun(
                offsetX: run.offsetX, offsetY: run.offsetY, width: run.width,
                frames: run.frames.map { wrap($0, toWidth: run.width) },
                frameDuration: run.frameDuration, clock: run.clock)
            return dimmed.isAnimating ? dimmed : nil
        }
        // One rectangle, over everything the wash covers — the runs included, whose
        // frames are flattened to the same two colours, so the static claim a run
        // replays under is true of every frame of it.
        result.opacityRegions =
            OpacityRegion.claim(
                width: width, height: result.lines.count, field: background)
            .map { [$0] } ?? []
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
        // A row carrying a terminal-graphics image is passed through
        // UNCHANGED, and this is not an exemption from dimming so much as a
        // recognition that there is nothing here to dim. Such a row is
        // U+10EEEE placeholders whose FOREGROUND COLOUR is the image's id, not
        // a colour — the picture's pixels live in the terminal. Flattening it
        // replaced that id with the backdrop's grey, so the cells named an
        // image that does not exist and the terminal drew NOTHING: a page with
        // a picture on it lost the picture entirely the moment any sheet or
        // alert opened, which is erasure rather than dimming.
        //
        // The whole row rather than the placeholder runs within it, because
        // the alternative is splitting a line into dimmed and undimmed spans
        // to save the case of text sharing a row with a picture — more
        // machinery than that case is worth, against a bug whose current cost
        // is the picture disappearing.
        //
        // The picture therefore keeps its own brightness behind a modal. That
        // is the honest ceiling: dimming it would mean re-transmitting the
        // pixels darker, or deleting the placement and putting it back on
        // dismissal, and both are real costs for a modal that is usually up
        // for a second.
        guard !text.unicodeScalars.contains(.terminalImagePlaceholder) else { return text }
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

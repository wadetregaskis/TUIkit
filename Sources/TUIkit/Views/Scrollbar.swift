//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Scrollbar.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Scrollbar configuration

/// How end arrows are drawn on a scrollbar.
public enum ScrollbarArrows: Sendable, Hashable, CaseIterable {
    /// No arrows; the track spans the whole scrollbar.
    case none
    /// One arrow at each end pointing away from the centre (`▲` … `▼`,
    /// `◀` … `▶`) — the classic scrollbar.
    case single
    /// Both arrows at each end (`▲▼` … `▲▼`), as on a classic Mac scrollbar.
    case double
}

/// *Whether* a scrolling view says it can scroll — SwiftUI's
/// `ScrollIndicatorVisibility`, spelled the same.
///
/// This is one half of the question; ``ScrollIndicatorStyle`` is the other.
/// Visibility governs whether ANY indicator is drawn, style governs which one.
/// SwiftUI has only the one half because a graphical scroll view has only one
/// kind of indicator — a terminal also has the "42 more rows below" line, and
/// conflating "show me nothing" with "show me the other kind" would leave no
/// way to ask for nothing at all.
///
/// The case names are SwiftUI's, which is what matters at a call site: nobody
/// writes the type, they write `.scrollIndicators(.visible)`.
public enum ScrollIndicatorVisibility: Sendable, Hashable, CaseIterable {
    /// Let the scrolling view decide — here, show an indicator while the
    /// content overflows its viewport. The default.
    ///
    /// SwiftUI defines `.automatic` as deferring to "the policies of the
    /// component accepting the visibility configuration", which is a
    /// delegation rather than a behaviour: on macOS it resolves through the
    /// user's *Show scroll bars* preference and overlay scrollers that fade.
    /// A terminal has neither, so the policy is stated here, and overflow is
    /// the only thing there is to go on.
    case automatic
    /// Always show the indicator (even when everything fits).
    ///
    /// A scrollbar then draws a full-length thumb. The text style has nothing
    /// to say about content that isn't there, so it still draws nothing —
    /// ``automatic`` and ``visible`` are the same thing for it.
    case visible
    /// Do not show any indicator.
    case hidden
    /// Never show any indicator.
    ///
    /// In SwiftUI this differs from ``hidden``: that one is a request a
    /// platform convention may still override, this one is unconditional.
    /// Nothing here can override a hidden indicator, so the two behave
    /// identically — it exists so that source written against SwiftUI compiles
    /// and means what it says.
    case never
}

/// *Which* indicator a scrolling view draws, when ``ScrollIndicatorVisibility``
/// says to draw one.
///
/// TUI-specific: SwiftUI has no equivalent because it has only one kind of
/// indicator to choose from.
public enum ScrollIndicatorStyle: Sendable, Hashable, CaseIterable {
    /// A scrollbar along the trailing edge (vertical) or the bottom
    /// (horizontal): a thumb sized to the visible fraction and positioned at
    /// sub-cell precision, so it shows *where* in the content the viewport is.
    /// Costs one column (or row) of the viewport, for the bar's whole length.
    ///
    /// The default, and the only style the horizontal axis has.
    case scrollbar
    /// A line of text at each edge that has content behind it — "3 more rows
    /// above", "42 more rows below". Names *how much* is hidden rather than
    /// showing where the viewport sits, and costs a row only at an edge that
    /// actually has something to report.
    ///
    /// Vertical only: there is no horizontal equivalent, so a horizontally
    /// scrolling view under this style still draws its bar.
    case text
}

extension ScrollIndicatorVisibility {
    /// Whether an indicator is drawn at all, given whether the content
    /// overflows.
    ///
    /// The one place the four cases are turned into a yes/no. Every scrolling
    /// view asked this question by hand before, as `!= .hidden && (== .visible
    /// || overflows)` — a shape that silently answers "yes" for any case added
    /// later, which is exactly what ``never`` would have been.
    ///
    /// - Parameter overflowing: Whether the content exceeds its viewport.
    ///   An autoclosure because deciding that can mean measuring the whole
    ///   content, and the fixed cases (``hidden``, ``visible``, ``never``)
    ///   never need to know.
    func showsIndicator(overflowing: @autoclosure () -> Bool) -> Bool {
        switch self {
        case .visible: true
        case .automatic: overflowing()
        case .hidden, .never: false
        }
    }
}

/// What a scrolling view draws this frame to show that it scrolls: at most one
/// of a bar and the text lines, resolved from a visibility and a style.
///
/// The two are separate flags rather than an enum because the arithmetic reads
/// them separately — a bar narrows the content by a column for its whole
/// height, text steals a row at an overflowing edge — and because "neither" is
/// a real answer (``ScrollIndicatorVisibility/hidden``).
struct ResolvedScrollIndicators {
    /// A scrollbar is reserved down the trailing edge.
    let bar: Bool
    /// "N more above / below" lines are reserved at the overflowing edges.
    let text: Bool

    /// Nothing is drawn: the content scrolls silently.
    static let none = Self(bar: false, text: false)
}

extension EnvironmentValues {
    /// The vertical indicator this subtree's scrolling views draw.
    ///
    /// - Parameter overflowing: Whether the content exceeds its viewport.
    ///   An autoclosure for the reason ``ScrollIndicatorVisibility/showsIndicator(overflowing:)``
    ///   takes one: only ``ScrollIndicatorVisibility/automatic`` has to know,
    ///   and finding out can mean measuring the whole content.
    func verticalScrollIndicators(
        overflowing: @autoclosure () -> Bool
    ) -> ResolvedScrollIndicators {
        guard verticalScrollIndicatorVisibility.showsIndicator(overflowing: overflowing())
        else { return .none }
        switch scrollIndicatorStyle {
        case .scrollbar: return ResolvedScrollIndicators(bar: true, text: false)
        case .text: return ResolvedScrollIndicators(bar: false, text: true)
        }
    }

    /// Whether this subtree's horizontally scrolling views reserve a bottom
    /// scrollbar. There is no horizontal text indicator, so the style does not
    /// enter into it — a `.text` subtree still gets its horizontal bar.
    func showsHorizontalScrollbar(overflowing: @autoclosure () -> Bool) -> Bool {
        horizontalScrollIndicatorVisibility.showsIndicator(overflowing: overflowing())
    }
}

/// Which edges carry a scrollbar.
public struct ScrollbarEdges: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// The right edge (the default for vertical scrolling).
    public static let trailing = Self(rawValue: 1 << 0)
    /// The left edge.
    public static let leading = Self(rawValue: 1 << 1)
    /// The bottom edge (the default for horizontal scrolling).
    public static let bottom = Self(rawValue: 1 << 2)
    /// The top edge.
    public static let top = Self(rawValue: 1 << 3)
}

// MARK: - Environment & modifiers

// `.automatic` by default, as in SwiftUI: a view that scrolls says so.
//
// It is not free — `.automatic` has to know whether the content overflows, and
// on a ScrollView finding that out means measuring the content — but the
// alternative was worse than the cost. With scrollbars opt-in, the only way to
// get a plain scrolling view was to leave the visibility alone, so `.hidden`
// had to keep drawing the text indicators to say anything at all; there was
// then no value of this that meant "no indicator", and asking for one silently
// switched styles instead. See ``ScrollIndicatorStyle``.
private struct VerticalScrollIndicatorVisibilityKey: EnvironmentKey {
    static let defaultValue: ScrollIndicatorVisibility = .automatic
}

private struct HorizontalScrollIndicatorVisibilityKey: EnvironmentKey {
    static let defaultValue: ScrollIndicatorVisibility = .automatic
}

private struct ScrollIndicatorStyleKey: EnvironmentKey {
    static let defaultValue: ScrollIndicatorStyle = .scrollbar
}

private struct ScrollbarArrowsKey: EnvironmentKey {
    static let defaultValue: ScrollbarArrows = .single
}

private struct ScrollbarProportionalKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether scrolling views in this subtree draw a VERTICAL indicator —
    /// SwiftUI's `\.verticalScrollIndicatorVisibility`. Defaults to
    /// ``ScrollIndicatorVisibility/automatic``.
    ///
    /// Set through ``View/scrollIndicators(_:axes:)``; two values rather than
    /// one because that modifier takes an axis set, and a view scrolling both
    /// ways must be able to show one indicator and not the other.
    public internal(set) var verticalScrollIndicatorVisibility: ScrollIndicatorVisibility {
        get { self[VerticalScrollIndicatorVisibilityKey.self] }
        set { self[VerticalScrollIndicatorVisibilityKey.self] = newValue }
    }

    /// Whether scrolling views in this subtree draw a HORIZONTAL scrollbar —
    /// SwiftUI's `\.horizontalScrollIndicatorVisibility`. Defaults to
    /// ``ScrollIndicatorVisibility/automatic``.
    public internal(set) var horizontalScrollIndicatorVisibility: ScrollIndicatorVisibility {
        get { self[HorizontalScrollIndicatorVisibilityKey.self] }
        set { self[HorizontalScrollIndicatorVisibilityKey.self] = newValue }
    }

    /// Which indicator scrolling views in this subtree draw, when their
    /// visibility says to draw one. Defaults to
    /// ``ScrollIndicatorStyle/scrollbar``.
    ///
    /// Set through ``View/scrollIndicatorStyle(_:)``. One value for both axes:
    /// only the vertical axis has a choice to make (see
    /// ``ScrollIndicatorStyle/text``).
    public internal(set) var scrollIndicatorStyle: ScrollIndicatorStyle {
        get { self[ScrollIndicatorStyleKey.self] }
        set { self[ScrollIndicatorStyleKey.self] = newValue }
    }

    /// The end-arrow style for scrollbars in this subtree. Defaults to
    /// ``ScrollbarArrows/single``.
    public var scrollbarArrows: ScrollbarArrows {
        get { self[ScrollbarArrowsKey.self] }
        set { self[ScrollbarArrowsKey.self] = newValue }
    }

    /// Whether a scrollbar's thumb is sized to the visible/total ratio (`true`,
    /// the default) or a fixed one cell (`false`).
    public var scrollbarProportionalThumb: Bool {
        get { self[ScrollbarProportionalKey.self] }
        set { self[ScrollbarProportionalKey.self] = newValue }
    }
}

extension View {
    /// Sets whether scrolling views (``ScrollView``, ``Table``, ``List``) within
    /// this view show that they scroll.
    ///
    /// Mirrors SwiftUI's `scrollIndicators(_:axes:)`, and governs *whether* an
    /// indicator is drawn, not which one — that is
    /// ``View/scrollIndicatorStyle(_:)``. So `.hidden` and `.never` mean no
    /// indicator of any kind, and the default,
    /// ``ScrollIndicatorVisibility/automatic``, shows one whenever the content
    /// overflows its viewport.
    ///
    /// ```swift
    /// ScrollView { content }.scrollIndicators(.hidden)   // scrolls silently
    /// ScrollView([.horizontal, .vertical]) { grid }
    ///     .scrollIndicators(.visible, axes: .vertical)   // always, one axis
    /// ```
    ///
    /// - Parameters:
    ///   - visibility: When an indicator is drawn.
    ///   - axes: Which axes it applies to. Defaults to both.
    /// - Returns: A view whose scrolling descendants follow the setting.
    public func scrollIndicators(
        _ visibility: ScrollIndicatorVisibility,
        axes: Axis.Set = [.horizontal, .vertical]
    ) -> some View {
        // Each axis is written only when named, which is what lets two calls
        // compose — `.scrollIndicators(.visible, axes: .vertical)` above
        // `.scrollIndicators(.automatic, axes: .horizontal)` leaves each bar
        // with its own policy instead of the second clobbering the first.
        // `transformEnvironment` rather than `environment` for exactly that: an
        // unnamed axis has to keep whatever it inherited, which is a value this
        // call cannot see.
        transformEnvironment(\.verticalScrollIndicatorVisibility) {
            if axes.contains(.vertical) { $0 = visibility }
        }
        .transformEnvironment(\.horizontalScrollIndicatorVisibility) {
            if axes.contains(.horizontal) { $0 = visibility }
        }
    }

    /// Sets which indicator scrolling views within this view draw — a
    /// scrollbar (the default) or "N more above / below" text.
    ///
    /// TUI-specific, and orthogonal to ``View/scrollIndicators(_:axes:)``:
    /// visibility decides whether anything is drawn, this decides what. A view
    /// whose indicators are hidden draws nothing whatever this says.
    ///
    /// ```swift
    /// List(rows) { … }.scrollIndicatorStyle(.text)   // "42 more rows below"
    /// ```
    ///
    /// - Parameter style: The indicator to draw.
    /// - Returns: A view whose scrolling descendants follow the setting.
    public func scrollIndicatorStyle(_ style: ScrollIndicatorStyle) -> some View {
        environment(\.scrollIndicatorStyle, style)
    }

    /// Sets the end-arrow style of scrollbars within this view.
    public func scrollbarArrows(_ arrows: ScrollbarArrows) -> some View {
        environment(\.scrollbarArrows, arrows)
    }

    /// Sets whether scrollbar thumbs within this view are sized proportionally to
    /// the visible region (`true`) or a fixed single cell (`false`).
    public func scrollbarProportionalThumb(_ proportional: Bool) -> some View {
        environment(\.scrollbarProportionalThumb, proportional)
    }
}

// MARK: - Track cell

/// One cell of a rendered scrollbar track.
///
/// `inverted` distinguishes the two anchorings that share a glyph set: a
/// bottom-/left-anchored partial is drawn directly (thumb colour as the glyph
/// ink), while a top-/right-anchored partial is drawn by *inverting* the
/// complementary block — the thumb colour becomes the cell background — because
/// Unicode has no top-/right-anchored partial-block series. See
/// ``ScrollbarRenderer``.
struct ScrollbarCell: Equatable {
    /// The block glyph (or a space for an empty track cell, `█` for a full one).
    let glyph: Character
    /// `true` when the thumb colour is the cell *background* (top/right anchor).
    let inverted: Bool

    static let empty = Self(glyph: " ", inverted: false)
    static let full = Self(glyph: "█", inverted: false)
}

/// The three colours a scrollbar draws with: the thumb (handle), the track
/// (groove behind it), and the end arrows.
struct ScrollbarColors {
    let thumb: Color
    let track: Color
    let arrow: Color

    /// The standard palette for a bar that doubles as its container's focus
    /// indicator: quiet secondary/tertiary tones unfocused, and a PULSING
    /// accent thumb + arrows when focused — the same SelectionIndicator
    /// convention (and `.selectionIndicatorStyle` knob) every other focused
    /// control breathes with. The steady accent alone was too subtle a
    /// focus cue.
    @MainActor
    static func focusIndicating(isFocused: Bool, context: RenderContext) -> Self {
        let palette = context.environment.palette
        // §1.2 of the scroll-anchoring spec: when the user may not adjust the
        // scroll position, the chrome still renders — in a disabled state. One
        // step quieter than the resting bar, so the view reads as pinned rather
        // than as having no more content.
        guard context.environment.isScrollEnabled else {
            return Self(
                thumb: palette.foregroundTertiary,
                track: palette.foregroundQuaternary,
                arrow: palette.foregroundQuaternary)
        }
        guard isFocused else {
            return Self(
                thumb: palette.foregroundSecondary,
                track: palette.foregroundQuaternary,
                arrow: palette.foregroundTertiary)
        }
        // The cycle, not the live phase: building it reads no clock, so a
        // focused bar no longer forces a full re-render on every tick. The
        // cells are handed to the run loop instead — see `focusCycle` and
        // ``AnimatedCellRun``.
        let cycle = context.environment.selectionEmphasis.cycle(true)
        return Self(
            thumb: cycle.colorNow(dim: Self.pulseDim(palette), bright: palette.accent),
            track: palette.foregroundQuaternary,
            arrow: cycle.colorNow(dim: Self.pulseDim(palette), bright: palette.accent))
    }

    /// The bar with a given accent for its thumb and arrows — one frame of the
    /// focused bar's cycle.
    static func accented(_ accent: Color, palette: any Palette) -> Self {
        Self(thumb: accent, track: palette.foregroundQuaternary, arrow: accent)
    }

    /// The recessive end of the focused bar's breath.
    @MainActor
    static func pulseDim(_ palette: any Palette) -> Color {
        palette.accent.opacity(ViewConstants.focusPulseMin, over: palette.background)
    }

    /// The bar's breathing cycle, or nil when nothing about it moves — not
    /// focused, scrolling disabled, or `.selectionIndicatorStyle(.none)`.
    ///
    /// A caller that gets a cycle must hand the bar's cells to the run loop as
    /// ``AnimatedCellRun``s; a caller that gets nil has a still bar and needs no
    /// runs. Nothing here reads a clock.
    @MainActor
    static func focusCycle(
        isFocused: Bool, context: RenderContext
    ) -> SelectionEmphasisCycle? {
        guard context.environment.isScrollEnabled, isFocused else { return nil }
        let cycle = context.environment.selectionEmphasis.cycle(true)
        return cycle.isAnimating ? cycle : nil
    }
}

// MARK: - Renderer

/// Computes the sub-cell-precise glyphs for a scrollbar track.
///
/// The thumb's size is proportional to `viewport / extent` and its position to
/// `offset / (extent − viewport)`, both measured in *eighths* of a cell so the
/// thumb's ends can land at fractional cell positions. The fractional ends use
/// partial block glyphs; a minimum thumb of one whole cell guarantees the two
/// ends always fall in different cells, so each partial cell is cleanly anchored
/// to one edge.
enum ScrollbarRenderer {
    /// The `count` track cells for the given scroll metrics.
    ///
    /// - Parameters:
    ///   - count: The track length, in cells.
    ///   - extent: The total content size (lines, or columns).
    ///   - viewport: The visible size.
    ///   - offset: The current scroll offset, in `0...(extent − viewport)`.
    ///   - proportional: When `true` the thumb is sized to `viewport / extent`;
    ///     when `false` it is a fixed one cell.
    ///   - vertical: `true` for a vertical scrollbar (lower-block glyphs,
    ///     inverting for the top-anchored end); `false` for a horizontal one
    ///     (left-block glyphs, inverting for the right-anchored end).
    static func trackCells(
        count: Int, extent: Int, viewport: Int, offset: Int,
        proportional: Bool = true, vertical: Bool
    ) -> [ScrollbarCell] {
        guard count > 0 else { return [] }
        // Everything fits: the thumb fills the whole track.
        guard extent > viewport, viewport > 0 else {
            return Array(repeating: .full, count: count)
        }

        let span = thumbSpan(
            count: count, extent: extent, viewport: viewport, offset: offset, proportional: proportional)
        let start = span.start
        let end = span.end

        var cells: [ScrollbarCell] = []
        cells.reserveCapacity(count)
        for cell in 0..<count {
            let cellLo = cell * 8
            let lo = max(start, cellLo) - cellLo  // 0...8 within the cell
            let hi = min(end, cellLo + 8) - cellLo
            if hi <= lo {
                cells.append(.empty)
            } else if lo == 0 && hi == 8 {
                cells.append(.full)
            } else if lo == 0 {
                // Covered from the cell's start edge (top / left).
                cells.append(
                    vertical
                        ? ScrollbarCell(glyph: Self.lowerBlock(8 - hi), inverted: true)
                        : ScrollbarCell(glyph: Self.leftBlock(hi), inverted: false))
            } else {
                // Covered to the cell's far edge (bottom / right).
                cells.append(
                    vertical
                        ? ScrollbarCell(glyph: Self.lowerBlock(8 - lo), inverted: false)
                        : ScrollbarCell(glyph: Self.leftBlock(lo), inverted: true))
            }
        }
        return cells
    }

    /// The thumb's covered sub-cell range `start..<end` (eighths of a cell) within
    /// a `count`-cell track, shared by ``trackCells`` (rendering) and the hit-test
    /// (interaction) so the two never disagree about where the thumb is. The range
    /// spans `0...(count*8)`; the thumb is at least one whole cell (8 sub-units).
    static func thumbSpan(
        count: Int, extent: Int, viewport: Int, offset: Int, proportional: Bool
    ) -> (start: Int, end: Int) {
        let totalSub = count * 8
        guard count > 0, extent > viewport, viewport > 0 else { return (0, totalSub) }
        let proportionalSub = Int((Double(viewport) / Double(extent) * Double(totalSub)).rounded())
        let thumbSub = min(totalSub, max(8, proportional ? proportionalSub : 8))
        let travel = totalSub - thumbSub
        let maxOffset = extent - viewport
        let rawStart = maxOffset > 0
            ? Int((Double(offset) / Double(maxOffset) * Double(travel)).rounded())
            : 0
        let start = max(0, min(travel, rawStart))
        return (start, start + thumbSub)
    }

    /// The lower block filled `eighths`/8 from the bottom: `▁`…`▇`, `█` at 8.
    static func lowerBlock(_ eighths: Int) -> Character {
        guard eighths >= 1 else { return " " }
        return Character(UnicodeScalar(0x2580 + min(8, eighths))!)
    }

    /// The left block filled `eighths`/8 from the left: `▏`…`▉`, `█` at 8.
    static func leftBlock(_ eighths: Int) -> Character {
        guard eighths >= 1 else { return " " }
        return Character(UnicodeScalar(0x2590 - min(8, eighths))!)
    }

    /// Styles one track cell.
    ///
    /// Fully-covered and empty cells are drawn as a *space* coloured by background
    /// — the thumb colour and the track colour respectively — never as a `█` glyph.
    /// Two reasons: adjacent block glyphs leave a hairline gap in some terminals
    /// (notably Terminal.app, the same gap seen between box-drawing characters),
    /// whereas contiguous background colour is seamless; and a background fill
    /// covers the *whole* cell, so a one-cell thumb is as solid as a multi-cell one
    /// instead of looking thinner. Only the fractional end cells need a partial
    /// glyph: a bottom-/left-anchored end draws the partial block in the thumb
    /// colour over the track, an inverted (top-/right-anchored) end swaps them so
    /// the thumb colour is the cell background — which is also how the two anchors
    /// Unicode lacks a partial-block series for are produced.
    static func styledCell(_ cell: ScrollbarCell, thumb: Color, track: Color) -> String {
        if cell.glyph == " " {
            return ANSIRenderer.colorize(" ", background: track)
        }
        if cell.glyph == "█" {
            return ANSIRenderer.colorize(" ", background: thumb)
        }
        if cell.inverted {
            return ANSIRenderer.colorize(String(cell.glyph), foreground: track, background: thumb)
        }
        return ANSIRenderer.colorize(String(cell.glyph), foreground: thumb, background: track)
    }

    /// The number of cells an arrow configuration reserves at each *end* combined
    /// (so a vertical bar loses this many track cells overall).
    static func arrowReserve(_ arrows: ScrollbarArrows) -> Int {
        switch arrows {
        case .none: return 0
        case .single: return 2
        case .double: return 4
        }
    }

    /// A vertical scrollbar `height` cells tall: a `▲`/`▼` arrow assembly at each
    /// end (per `arrows`) wrapped around a sub-cell-precise track. Returns one
    /// styled single-cell string per line. Arrows are dropped if the bar is too
    /// short to also show a track.
    static func verticalScrollbar(
        height: Int, extent: Int, viewport: Int, offset: Int,
        arrows: ScrollbarArrows, proportional: Bool, colors: ScrollbarColors
    ) -> [String] {
        guard height > 0 else { return [] }
        let reserve = height > arrowReserve(arrows) ? arrowReserve(arrows) : 0
        let trackLen = height - reserve
        let lines = trackCells(
            count: trackLen, extent: extent, viewport: viewport, offset: offset,
            proportional: proportional, vertical: true
        ).map { styledCell($0, thumb: colors.thumb, track: colors.track) }

        guard reserve > 0 else { return lines }
        let up = ANSIRenderer.colorize("▲", foreground: colors.arrow, background: colors.track)
        let down = ANSIRenderer.colorize("▼", foreground: colors.arrow, background: colors.track)
        // `single` → ▲ … ▼; `double` → ▲▼ … ▲▼ (both arrows at each end).
        let head = reserve == 4 ? [up, down] : [up]
        let tail = reserve == 4 ? [up, down] : [down]
        return head + lines + tail
    }

    /// The vertical bar's animation runs: one per row whose cell actually
    /// changes across the cycle.
    ///
    /// Built by rendering the WHOLE bar once per colour of the cycle and
    /// keeping the rows that differ — so the glyph logic (thumb spans in
    /// eighths, partial end cells, arrow reserve) is written once and the
    /// animation cannot disagree with the render about which cells are thumb.
    /// Empty track cells come out identical at every colour and so earn no run,
    /// which is what keeps a tall bar from repainting its whole length 20 times
    /// a second to move a two-cell thumb.
    ///
    /// Offsets are relative to the bar's own column, row 0 — the caller knows
    /// where the bar sits and shifts them.
    @MainActor
    static func verticalScrollbarRuns(
        height: Int, extent: Int, viewport: Int, offset: Int,
        arrows: ScrollbarArrows, proportional: Bool,
        cycle: SelectionEmphasisCycle, palette: any Palette
    ) -> [AnimatedCellRun] {
        let frames = cycle.colors(dim: ScrollbarColors.pulseDim(palette), bright: palette.accent)
            .map { accent in
                verticalScrollbar(
                    height: height, extent: extent, viewport: viewport, offset: offset,
                    arrows: arrows, proportional: proportional,
                    colors: .accented(accent, palette: palette))
            }
        guard let first = frames.first else { return [] }
        return (0..<first.count).compactMap { row in
            let cells = frames.map { $0.indices.contains(row) ? $0[row] : "" }
            guard Set(cells).count > 1 else { return nil }
            return AnimatedCellRun(
                offsetX: 0, offsetY: row, width: cells[0].strippedLength,
                frames: cells, clock: .cursor)
        }
    }

    /// The horizontal bar's run: the whole bar row.
    ///
    /// One run rather than per-cell, because a horizontal bar is a single row
    /// and splitting it would mean diffing styled cells to find the animated
    /// span. The static track cells are repainted with it — one row's worth of
    /// bytes per tick, which is the price of not writing a second cell-diffing
    /// routine that could disagree with the renderer.
    @MainActor
    static func horizontalScrollbarRun(
        width: Int, extent: Int, viewport: Int, offset: Int,
        arrows: ScrollbarArrows, proportional: Bool,
        cycle: SelectionEmphasisCycle, palette: any Palette
    ) -> AnimatedCellRun? {
        let frames = cycle.colors(dim: ScrollbarColors.pulseDim(palette), bright: palette.accent)
            .map { accent in
                horizontalScrollbar(
                    width: width, extent: extent, viewport: viewport, offset: offset,
                    arrows: arrows, proportional: proportional,
                    colors: .accented(accent, palette: palette))
            }
        guard let first = frames.first, Set(frames).count > 1 else { return nil }
        return AnimatedCellRun(
            offsetX: 0, offsetY: 0, width: first.strippedLength,
            frames: frames, clock: .cursor)
    }

    /// A horizontal scrollbar `width` cells wide: a `◀`/`▶` arrow assembly at each
    /// end wrapped around a sub-cell-precise track, joined into one styled string.
    static func horizontalScrollbar(
        width: Int, extent: Int, viewport: Int, offset: Int,
        arrows: ScrollbarArrows, proportional: Bool, colors: ScrollbarColors
    ) -> String {
        guard width > 0 else { return "" }
        let reserve = width > arrowReserve(arrows) ? arrowReserve(arrows) : 0
        let trackLen = width - reserve
        let trackStr = trackCells(
            count: trackLen, extent: extent, viewport: viewport, offset: offset,
            proportional: proportional, vertical: false
        ).map { styledCell($0, thumb: colors.thumb, track: colors.track) }.joined()

        guard reserve > 0 else { return trackStr }
        let left = ANSIRenderer.colorize("◀", foreground: colors.arrow, background: colors.track)
        let right = ANSIRenderer.colorize("▶", foreground: colors.arrow, background: colors.track)
        let head = reserve == 4 ? left + right : left
        let tail = reserve == 4 ? left + right : right
        return head + trackStr + tail
    }
}

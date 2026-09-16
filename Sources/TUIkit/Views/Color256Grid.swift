//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Color256Grid.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitStyling

// MARK: - State indices

/// `StateStorage` property indices for ``_Color256GridCore``.
private enum Color256GridStateIndex {
    static let focusID = 0
    static let handler = 1
}

// MARK: - Layout

/// The xterm-256 palette, laid out the way it is *structured* rather than as a
/// flat 16×16 block: the 16 system colours as two groups of eight (standard /
/// bright), the 216-colour cube as its six red slices — each a 6×6 green×blue
/// block — arranged in two rows of three, then the 24-step greyscale ramp.
///
/// A "visual row" is a list of palette indices with `nil` marking a one-cell
/// gap (between the two system groups, and between cube blocks). ``place(cellWidth:)``
/// turns the rows into positioned ``Cell``s, centred within the widest row, so
/// rendering, hit-testing, and arrow-key navigation all read the same geometry.
enum Palette256Layout {
    /// A placed swatch: its palette index and top-left position in the buffer.
    struct Cell: Equatable, Sendable {
        let index: Int
        let x: Int
        let y: Int
        let width: Int
    }

    /// How the palette's three sections are folded — the knob that lets the
    /// grid trade width for height when the space on offer is narrow.
    ///
    /// The cube's six red slices tile `cubeColumns` blocks across; the two
    /// strips (system 16, greyscale 24) wrap at `stripColumns` swatches.
    struct Arrangement: Equatable, Sendable {
        /// Cube blocks per row: 3 (the preferred 3×2), 2, or 1.
        var cubeColumns: Int
        /// Swatches per strip row: 16 (unwrapped), 8, or 4.
        var stripColumns: Int
    }

    /// Widest first — the arrangement chooser walks these and takes the first
    /// that fits, so the preferred 3-wide cube and unwrapped strips win
    /// whenever there is room for them.
    static let arrangements: [Arrangement] = [
        Arrangement(cubeColumns: 3, stripColumns: 16),
        Arrangement(cubeColumns: 2, stripColumns: 16),
        Arrangement(cubeColumns: 2, stripColumns: 8),
        Arrangement(cubeColumns: 1, stripColumns: 8),
        Arrangement(cubeColumns: 1, stripColumns: 4),
    ]

    /// The arrangement this palette is laid out in when nothing constrains it.
    static let preferred = arrangements[0]

    /// The visual rows of the palette in its preferred arrangement.
    static let rows: [[Int?]] = rows(preferred)

    /// The widest row of the preferred arrangement, in cells.
    static let widthInCells: Int = widthInCells(preferred)

    /// The widest row of `arrangement`, in cells — its centring reference and
    /// the width it needs.
    static func widthInCells(_ arrangement: Arrangement) -> Int {
        rows(arrangement).map(\.count).max() ?? 0
    }

    /// The widest arrangement whose grid fits in `availableWidth` cells, or the
    /// narrowest one when even that overflows (better a scrollbar than a lie).
    ///
    /// `availableWidth` of zero or less means "unconstrained" — a measure pass
    /// with nothing to go on gets the preferred arrangement rather than the
    /// most cramped one.
    static func arrangement(cellWidth: Int, availableWidth: Int) -> Arrangement {
        guard availableWidth > 0 else { return preferred }
        return arrangements.first { widthInCells($0) * cellWidth <= availableWidth }
            ?? arrangements[arrangements.count - 1]
    }

    /// The visual rows for a given arrangement (see the type doc for the
    /// section order).
    static func rows(_ arrangement: Arrangement) -> [[Int?]] {
        var rows: [[Int?]] = []

        /// A run of swatches wrapped at `perRow`, with the standard/bright gap
        /// kept when the system 16 fits on one line.
        func strip(_ values: [Int], perRow: Int, gapAfter: Int? = nil) -> [[Int?]] {
            stride(from: 0, to: values.count, by: perRow).map { start in
                let slice = Array(values[start..<min(start + perRow, values.count)])
                guard let gapAfter, slice.count > gapAfter else { return slice.map { Int?($0) } }
                return slice[..<gapAfter].map { Int?($0) } + [nil]
                    + slice[gapAfter...].map { Int?($0) }
            }
        }

        // System 16: standard 0–7, a gap, bright 8–15 — the gap only when the
        // two groups share a line.
        rows.append(
            contentsOf: strip(
                Array(0...15), perRow: arrangement.stripColumns,
                gapAfter: arrangement.stripColumns >= 16 ? 8 : nil))
        rows.append([])  // spacer

        // 6×6×6 cube: index = 16 + 36·r + 6·g + b. Each red slice r is a 6×6
        // green×blue block; the slices tile `cubeColumns` across.
        func cubeBlockRow(_ reds: [Int]) -> [[Int?]] {
            (0..<6).map { green -> [Int?] in
                var row: [Int?] = []
                for (i, r) in reds.enumerated() {
                    if i > 0 { row.append(nil) }  // gap between blocks
                    for blue in 0..<6 { row.append(16 + 36 * r + 6 * green + blue) }
                }
                return row
            }
        }
        let perRow = max(1, arrangement.cubeColumns)
        for start in stride(from: 0, to: 6, by: perRow) {
            rows.append(contentsOf: cubeBlockRow(Array(start..<min(start + perRow, 6))))
            rows.append([])  // spacer
        }

        // Greyscale ramp: 232–255 (24 steps). Its natural 24 is wider than the
        // system strip's 16, so it wraps at a multiple that keeps its rows even.
        let greyPerRow = arrangement.stripColumns >= 16 ? 24 : arrangement.stripColumns
        rows.append(contentsOf: strip(Array(232...255), perRow: greyPerRow))
        return rows
    }

    /// Positions every swatch for a given cell width and arrangement, centring
    /// each row within the widest. Returns the cells plus the overall
    /// width/height in cells.
    static func place(
        cellWidth: Int, arrangement: Arrangement = preferred
    ) -> (cells: [Cell], width: Int, height: Int) {
        let rows = rows(arrangement)
        let gridWidth = (rows.map(\.count).max() ?? 0) * cellWidth
        var cells: [Cell] = []
        for (y, row) in rows.enumerated() {
            let lead = max(0, (gridWidth - row.count * cellWidth) / 2)
            var x = lead
            for entry in row {
                if let index = entry {
                    cells.append(Cell(index: index, x: x, y: y, width: cellWidth))
                }
                x += cellWidth
            }
        }
        return (cells, gridWidth, rows.count)
    }
}

// MARK: - Focus handler

/// Focus handler for the 256-colour grid: owns the cursor index and moves it
/// with the arrow keys, writing the chosen palette colour through `selection`
/// live (so the panel's preview tracks the cursor). Enter/Space re-commit the
/// current cell.
///
/// Because the grid is no longer a uniform 16×16, navigation is *spatial*: it
/// reads the placed-cell geometry (refreshed each render into ``placements``)
/// and moves to the nearest swatch in the arrow's direction — left/right stay
/// within the visual row, up/down jump to the nearest cell by column, skipping
/// the gaps between sections.
final class Color256GridHandler: PersistedFocusable {
    var focusID: String
    var canBeFocused: Bool

    /// The cursor's palette index, 0–255.
    private(set) var cursor: Int

    /// The colour being edited; cursor moves write `.palette256(index)` to it.
    var selection: Binding<Color>

    /// The current frame's placed cells — set by the renderer so navigation
    /// matches exactly what's on screen.
    var placements: [Palette256Layout.Cell] = []

    init(focusID: String, cursor: Int, selection: Binding<Color>, canBeFocused: Bool = true) {
        self.focusID = focusID
        self.cursor = max(0, min(255, cursor))
        self.selection = selection
        self.canBeFocused = canBeFocused
    }

    /// Clamps `index` to 0–255, stores it, and writes it to `selection`.
    func commit(to index: Int) {
        cursor = max(0, min(255, index))
        selection.wrappedValue = .palette256(UInt8(cursor))
    }

    /// Moves the cursor to `index` *without* writing `selection` — used to keep
    /// the highlighted cell tracking the current colour (which may have been
    /// set elsewhere, e.g. another tab) until the user actually picks a swatch.
    func syncCursor(to index: Int) {
        cursor = max(0, min(255, index))
    }

    func handleKeyEvent(_ event: KeyEvent) -> Bool {
        switch event.key {
        case .up: moveVertical(-1); return true
        case .down: moveVertical(1); return true
        case .left: moveHorizontal(-1); return true
        case .right: moveHorizontal(1); return true
        case .enter, .space: commit(to: cursor); return true
        default: return false
        }
    }

    /// Left/right within the current visual row (crosses block/group gaps).
    private func moveHorizontal(_ direction: Int) {
        guard let current = placements.first(where: { $0.index == cursor }) else { return }
        let candidates = placements.filter {
            $0.y == current.y && (direction > 0 ? $0.x > current.x : $0.x < current.x)
        }
        if let next = candidates.min(by: { abs($0.x - current.x) < abs($1.x - current.x) }) {
            commit(to: next.index)
        }
    }

    /// Up/down to the nearest cell by column, preferring the closest row (so a
    /// move skips the blank rows that separate the sections).
    private func moveVertical(_ direction: Int) {
        guard let current = placements.first(where: { $0.index == cursor }) else { return }
        let candidates = placements.filter { direction > 0 ? $0.y > current.y : $0.y < current.y }
        if let next = candidates.min(by: { cost($0, from: current) < cost($1, from: current) }) {
            commit(to: next.index)
        }
    }

    /// Row distance dominates column distance, so a vertical move lands on the
    /// nearest row first, then the nearest column within it.
    private func cost(_ cell: Palette256Layout.Cell, from: Palette256Layout.Cell) -> Int {
        abs(cell.y - from.y) * 1000 + abs(cell.x - from.x)
    }
}

// MARK: - Renderable core

/// Renders the xterm 256-colour palette as a focusable grid of swatches with an
/// arrow-navigable cursor. Procedural (per-cell background colour + cursor
/// bullet) so it's a private `_*Core` ``Renderable``; the public surface is
/// ``ColorPickerPanel``'s "256 (Xterm)" tab via ``_Palette256Editor``.
///
/// `showNumbers` widens each swatch from one cell (a plain colour block) to
/// three, printing the palette index inside it.
struct _Color256GridCore: View, Renderable {
    let selection: Binding<Color>
    var showNumbers: Bool = false
    var focusID: String?

    var body: Never { fatalError("_Color256GridCore renders via Renderable") }

    private typealias StateIndex = Color256GridStateIndex

    /// The cell width for the current mode: two cells for a roughly-square,
    /// easy-to-see colour block, or five cells with numbers — wide enough that a
    /// three-digit index sits centred with a space either side, so adjacent
    /// numbers never run together.
    private var cellWidth: Int { showNumbers ? 5 : 2 }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let isDisabled = !context.environment.isEnabled
        let stateStorage = context.stateStorage!

        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context,
            explicitFocusID: focusID,
            defaultPrefix: "color256",
            propertyIndex: StateIndex.focusID
        )

        let handlerKey = StateStorage.StateKey(
            identity: context.identity, propertyIndex: StateIndex.handler)
        let handlerBox: StateBox<Color256GridHandler> = stateStorage.storage(
            for: handlerKey,
            default: Color256GridHandler(
                focusID: persistedFocusID,
                cursor: Self.nearestIndex(of: selection.wrappedValue, palette: context.environment.palette),
                selection: selection,
                canBeFocused: !isDisabled
            )
        )
        let handler = handlerBox.value
        handler.selection = selection
        handler.canBeFocused = !isDisabled
        // Keep the highlighted cell on the swatch nearest the current colour (an
        // exact match for a palette entry, otherwise the closest cube/grey cell)
        // so the cursor tracks colours set on other tabs rather than defaulting
        // to black. The grid's own navigation writes `.palette256(cursor)`, so this
        // round-trips to the same cell.
        handler.syncCursor(to: Self.nearestIndex(of: selection.wrappedValue, palette: context.environment.palette))

        if !context.isMeasuring {
            FocusRegistration.register(
            context: context, handler: handler, focusID: persistedFocusID)
        }
        let isFocused = FocusRegistration.isFocused(context: context, focusID: persistedFocusID)
        // The CYCLE, not this tick's colour: the cursor swatch's mark is handed
        // to the run loop rather than rebuilt by re-rendering the whole panel
        // (and the page behind it) on every tick.
        //
        // Drawing only — see `RenderContext.indicatesFocus(_:)`. The check mark
        // on the cursor swatch announces focus, so it goes with the effect; the
        // keys never read this.
        let cycle = context.environment.selectionEmphasis.cycle(context.indicatesFocus(isFocused))
        let indicator = cycle.frames[cycle.step % max(1, cycle.frames.count)]

        // Fold the palette to whatever the width on offer allows — 3 cube blocks
        // across and unwrapped strips when there is room, narrower profiles when
        // there is not. Scrolling is the last resort, not the first.
        let arrangement = Palette256Layout.arrangement(
            cellWidth: cellWidth, availableWidth: context.availableWidth)
        let (lines, cells) = Self.renderGrid(
            cursor: handler.cursor, indicator: indicator,
            cellWidth: cellWidth, showNumbers: showNumbers,
            palette: context.environment.palette, arrangement: arrangement)
        handler.placements = cells

        var buffer = FrameBuffer(lines: lines)
        // One run, over the cursor swatch alone: it is the only cell whose
        // appearance moves, and `cells` already says exactly where it landed.
        if !context.isMeasuring, cycle.isAnimating,
            let placement = cells.first(where: { $0.index == handler.cursor }),
            case let cursorEnds = Self.cursorMarkEnds(
                forIndex: placement.index, palette: context.environment.palette),
            // Equal ends (a swatch or an ink with no RGB) are a still mark.
            cycle.isAnimating(dim: cursorEnds.dim, bright: cursorEnds.bright)
        {
            buffer.animatedCells = [
                AnimatedCellRun(
                    offsetX: placement.x, offsetY: placement.y, width: cellWidth,
                    // One ramp for the run: the mark's two ends are the swatch
                    // under the cursor, which does not change while the cycle
                    // plays, so `colors` builds the ramp once where the old
                    // `frames.map { cellText(indicator: $0) }` built one per
                    // frame.
                    frames: cycle.colors(
                        dim: cursorEnds.dim, bright: cursorEnds.bright
                    ).map {
                        Self.cellText(
                            index: placement.index, cellWidth: cellWidth,
                            mark: (color: $0, isBold: cycle.isFocused), showNumbers: showNumbers,
                            palette: context.environment.palette)
                    },
                    frameTicks: cycle.frameTicks, clock: cycle.clock)
            ]
        }

        // Mouse: clicking any swatch commits its index (fixes the grid ignoring
        // clicks). One handler per cell so the click maps to an exact index
        // without any event-coordinate arithmetic.
        if !context.isMeasuring, let dispatcher = context.environment.mouseEventDispatcher {
            let focusManager = context.environment.focusManager
            for cell in cells {
                let index = cell.index
                let handlerID = dispatcher.register { event in
                    guard event.phase == .released, event.button == .left else {
                        return event.phase == .pressed && event.button == .left
                    }
                    focusManager?.focus(id: persistedFocusID)
                    handler.commit(to: index)
                    return true
                }
                // Mouse-only: no `focusID`. Carrying it on all 256 identical
                // one-line cells is what broke arrow-key reveal —
                // `revealTarget` resolves a within-control move to the SMALLEST
                // region under the id, and with 256 of the same height that is
                // whichever came first (the top-left swatch), never the cursor.
                // Nothing else reads a region's focusID, and the click closure
                // focuses the grid explicitly, so dropping it costs nothing.
                buffer.hitTestRegions.append(
                    HitTestRegion(
                        offsetX: cell.x, offsetY: cell.y, width: cell.width, height: 1,
                        handlerID: handlerID))
            }
            publishRevealRegions(
                to: &buffer, cells: cells, cursor: handler.cursor,
                focusID: persistedFocusID, dispatcher: dispatcher)
        }

        return buffer
    }

    /// Publishes the two regions the reveal contract asks for — the same shape
    /// `List` and `Table` publish, and for the same reason.
    ///
    /// `FrameBuffer.revealTarget` reads the UNION of the id's regions when focus
    /// has just arrived (show the whole grid) and the SMALLEST when focus moved
    /// WITHIN the control (show only what changed — here, the swatch the arrow
    /// keys just landed on). So the grid needs exactly one whole-grid region and
    /// one cursor-sized region, not one per swatch.
    ///
    /// Both carry an inert handler: these exist to be measured, not clicked —
    /// the per-cell regions above own the mouse, and they are registered after
    /// these so they win the hit test.
    private func publishRevealRegions(
        to buffer: inout FrameBuffer, cells: [Palette256Layout.Cell], cursor: Int,
        focusID: String, dispatcher: MouseEventDispatcher
    ) {
        guard !cells.isEmpty else { return }
        let inert = dispatcher.register { _ in false }
        let top = cells.map(\.y).min() ?? 0
        let bottom = cells.map(\.y).max() ?? 0
        let left = cells.map(\.x).min() ?? 0
        let right = cells.map { $0.x + $0.width }.max() ?? 0
        buffer.hitTestRegions.insert(
            HitTestRegion(
                offsetX: left, offsetY: top, width: max(1, right - left),
                height: bottom - top + 1, handlerID: inert, focusID: focusID),
            at: 0)
        if let cell = cells.first(where: { $0.index == cursor }) {
            buffer.hitTestRegions.insert(
                HitTestRegion(
                    offsetX: cell.x, offsetY: cell.y, width: cell.width, height: 1,
                    handlerID: inert, focusID: focusID),
                at: 1)
        }
    }

    // MARK: Rendering

    /// Builds the grid lines and the geometry of every placed swatch. Each cell
    /// is the palette colour as a background; the cursor cell shows a check, and in
    /// `showNumbers` mode every cell its index, in the theme palette's readable ink
    /// for that swatch (`ContrastingLabel.on`), so it stays visible on any colour,
    /// including mid-grey, and (when focused) animates per
    /// ``View/selectionIndicatorStyle(_:)``.
    static func renderGrid(
        cursor: Int, indicator: SelectionEmphasis, cellWidth: Int, showNumbers: Bool,
        palette: any Palette,
        arrangement: Palette256Layout.Arrangement = Palette256Layout.preferred
    ) -> (lines: [String], cells: [Palette256Layout.Cell]) {
        let rows = Palette256Layout.rows(arrangement)
        let gridWidth = (rows.map(\.count).max() ?? 0) * cellWidth
        // Resolved once, outside the loop: one cell in the whole grid is the
        // cursor, and its two ends depend only on which swatch that is.
        let ends = cursorMarkEnds(forIndex: cursor, palette: palette)
        let cursorMark = (
            color: indicator.color(dim: ends.dim, bright: ends.bright),
            isBold: indicator.isFocused)
        var lines: [String] = []
        var cells: [Palette256Layout.Cell] = []
        for (y, row) in rows.enumerated() {
            if row.isEmpty {
                lines.append("")
                continue
            }
            let lead = max(0, (gridWidth - row.count * cellWidth) / 2)
            var line = String(repeating: " ", count: lead)
            var x = lead
            for entry in row {
                if let index = entry {
                    line += cellText(
                        index: index, cellWidth: cellWidth,
                        mark: index == cursor ? cursorMark : nil, showNumbers: showNumbers,
                        palette: palette)
                    cells.append(Palette256Layout.Cell(index: index, x: x, y: y, width: cellWidth))
                } else {
                    line += String(repeating: " ", count: cellWidth)  // gap
                }
                x += cellWidth
            }
            lines.append(line)
        }
        return (lines, cells)
    }

    /// The two ends the cursor swatch's mark breathes between: the swatch's own
    /// colour, and the tone that reads on it.
    ///
    /// Named apart from ``cellText(index:cellWidth:mark:showNumbers:palette:)`` so a
    /// caller drawing the whole cycle can hand them to
    /// `SelectionEmphasisCycle.colors(dim:bright:)` ONCE. `cellText` used to
    /// take a `SelectionEmphasis` and resolve the mark itself, which rebuilt
    /// the pulse ramp for every frame of the run.
    static func cursorMarkEnds(forIndex index: Int, palette: any Palette) -> (dim: Color, bright: Color) {
        // `clamping`, because this is reached with a CURSOR rather than with a
        // cell index off the layout table. The handler keeps its cursor in
        // 0...255, but this is a static entry point and a plain `UInt8(_:)`
        // would trap rather than draw something wrong. Both ends are the one
        // clamped swatch.
        let swatch = Color.palette256(UInt8(clamping: index))
        // The ink twice where either end has no RGB, as `_SwatchGridCore.markEnds` is.
        return Color.breathEnds(dim: swatch, bright: ContrastingLabel.on(swatch, palette: palette))
    }

    /// The rendered content of one swatch: the selection check, the palette index
    /// (in `showNumbers` mode), or a plain colour block.
    ///
    /// `mark` is what makes a cell the CURSOR cell — non-nil says "draw the
    /// check here", in the colour this frame of the cycle calls for. One
    /// parameter rather than an `isCursor` flag beside a colour, so the two
    /// cannot disagree.
    static func cellText(
        index: Int, cellWidth: Int, mark: (color: Color, isBold: Bool)?, showNumbers: Bool,
        palette: any Palette
    ) -> String {
        let color = Color.palette256(UInt8(index))
        let foreground = ContrastingLabel.on(color, palette: palette)
        if let mark {
            // A check, centred on the swatch, in the palette's readable ink for the
            // swatch so it shows on any colour; when focused it animates (per
            // `.selectionIndicatorStyle`) between the swatch colour and that ink,
            // and is bold.
            return ANSIRenderer.colorize(
                centred(_SwatchGridCore.selectionMark, in: cellWidth),
                foreground: mark.color, background: color, bold: mark.isBold)
        }
        if showNumbers {
            return ANSIRenderer.colorize(centred(String(index), in: cellWidth), foreground: foreground, background: color)
        }
        return ANSIRenderer.colorize(String(repeating: " ", count: cellWidth), background: color)
    }

    /// Centres `text` within `width` cells (a trailing-biased split for odd gaps).
    private static func centred(_ text: String, in width: Int) -> String {
        let length = text.count
        guard width > length else { return text }
        let left = (width - length) / 2
        return String(repeating: " ", count: left) + text
            + String(repeating: " ", count: width - length - left)
    }

    /// The palette index of `color` if it is a 256-palette colour, else nil.
    static func index(of color: Color) -> Int? {
        if case .palette256(let n) = color.value { return Int(n) }
        return nil
    }

    /// The palette index whose swatch best represents `color`: an exact match
    /// for a palette colour, otherwise the nearest 6×6×6-cube / greyscale cell
    /// (resolving a semantic colour first). Used to seed/track the cursor so it
    /// reflects the current colour rather than defaulting to index 0 (black).
    static func nearestIndex(of color: Color, palette: any Palette) -> Int {
        if let exact = index(of: color) { return exact }
        if case .palette256(let n) = color.resolve(with: palette).downsampledToPalette256().value {
            return Int(n)
        }
        return 0
    }
}

// MARK: - Layout

extension _Color256GridCore: Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        // O(rows): the footprint follows from the arrangement, no need to place
        // all 256 cells just to size it (this is measured for every tab-width
        // probe). The width offered decides how far the palette folds, so the
        // report answers "at THIS width, here is what I need" — the proposal
        // first, then the context, because a measure with neither is asking for
        // the natural size.
        let offered = proposal.width ?? context.availableWidth
        let arrangement = Palette256Layout.arrangement(
            cellWidth: cellWidth, availableWidth: offered)
        return ViewSize(
            width: Palette256Layout.widthInCells(arrangement) * cellWidth,
            height: Palette256Layout.rows(arrangement).count,
            isWidthFlexible: false,
            isHeightFlexible: false
        )
    }
}

// MARK: - Tab content

/// The "256 (Xterm)" tab's content: the swatch grid plus a toggle that switches
/// the swatches between compact colour blocks and three-cell numbered cells.
///
/// `showNumbers` is an `@AppStorage`-backed **preference**, not per-tab `@State`:
/// it survives leaving and re-entering the tab and persists across relaunches, so
/// a user who prefers numbered swatches keeps them. The key is namespaced to the
/// picker so it won't collide with an app's own settings.
struct _Palette256Editor: View {
    let selection: Binding<Color>
    @AppStorage("tuikit.colorPicker.palette256.showNumbers") private var showNumbers = false

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            _Color256GridCore(selection: selection, showNumbers: showNumbers)
            Toggle("Show numbers", isOn: $showNumbers)
        }
    }
}

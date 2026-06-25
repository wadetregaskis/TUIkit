//  🖥️ TUIKit — Terminal UI Kit for Swift
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

    /// The visual rows of the palette (see the type doc for the section order).
    static let rows: [[Int?]] = build()

    /// The widest row, in cells — the centring reference and the grid width.
    static let widthInCells: Int = rows.map(\.count).max() ?? 0

    private static func build() -> [[Int?]] {
        var rows: [[Int?]] = []

        // System 16: standard 0–7, a gap, bright 8–15.
        rows.append((0...7).map { Int?($0) } + [nil] + (8...15).map { Int?($0) })
        rows.append([])  // spacer

        // 6×6×6 cube: index = 16 + 36·r + 6·g + b. Each red slice r is a 6×6
        // green×blue block; the slices tile as two rows of three.
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
        rows.append(contentsOf: cubeBlockRow([0, 1, 2]))
        rows.append([])  // spacer
        rows.append(contentsOf: cubeBlockRow([3, 4, 5]))
        rows.append([])  // spacer

        // Greyscale ramp: 232–255 (24 steps).
        rows.append((232...255).map { Int?($0) })
        return rows
    }

    /// Positions every swatch for a given cell width, centring each row within
    /// the widest. Returns the cells plus the overall pixel width/height.
    static func place(cellWidth: Int) -> (cells: [Cell], width: Int, height: Int) {
        let gridWidth = widthInCells * cellWidth
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
final class Color256GridHandler: Focusable {
    let focusID: String
    var canBeFocused: Bool

    /// The cursor's palette index, 0–255.
    private(set) var cursor: Int

    /// The colour being edited; cursor moves write `.palette(index)` to it.
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
        selection.wrappedValue = .palette(UInt8(cursor))
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
        let stateStorage = context.environment.stateStorage!

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
        // to black. The grid's own navigation writes `.palette(cursor)`, so this
        // round-trips to the same cell.
        handler.syncCursor(to: Self.nearestIndex(of: selection.wrappedValue, palette: context.environment.palette))

        if !context.isMeasuring {
            FocusRegistration.register(context: context, handler: handler)
        }
        let isFocused = FocusRegistration.isFocused(context: context, focusID: persistedFocusID)
        let indicator = SelectionIndicator.resolve(isFocused: isFocused, context: context)

        let (lines, cells) = Self.renderGrid(
            cursor: handler.cursor, indicator: indicator,
            cellWidth: cellWidth, showNumbers: showNumbers)
        handler.placements = cells

        var buffer = FrameBuffer(lines: lines)

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
                buffer.hitTestRegions.append(
                    HitTestRegion(
                        offsetX: cell.x, offsetY: cell.y, width: cell.width, height: 1,
                        handlerID: handlerID, focusID: persistedFocusID))
            }
        }

        return buffer
    }

    // MARK: Rendering

    /// Builds the grid lines and the geometry of every placed swatch. Each cell
    /// is the palette colour as a background; the cursor cell shows a check in a
    /// contrasting foreground so it stays visible on any colour, including
    /// mid-grey, and (when focused) animates per ``SelectionIndicatorStyle``.
    static func renderGrid(
        cursor: Int, indicator: SelectionIndicator.Resolution, cellWidth: Int, showNumbers: Bool
    ) -> (lines: [String], cells: [Palette256Layout.Cell]) {
        let gridWidth = Palette256Layout.widthInCells * cellWidth
        var lines: [String] = []
        var cells: [Palette256Layout.Cell] = []
        for (y, row) in Palette256Layout.rows.enumerated() {
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
                        isCursor: index == cursor, indicator: indicator, showNumbers: showNumbers)
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

    /// The rendered content of one swatch: the selection check, the palette index
    /// (in `showNumbers` mode), or a plain colour block.
    private static func cellText(
        index: Int, cellWidth: Int, isCursor: Bool,
        indicator: SelectionIndicator.Resolution, showNumbers: Bool
    ) -> String {
        let color = Color.palette(UInt8(index))
        let foreground = contrast(forIndex: index)
        if isCursor {
            // A check, centred on the swatch, in a contrasting tone so it shows on
            // any colour; when focused it animates (per SelectionIndicatorStyle)
            // between the swatch colour and that contrasting tone, and is bold.
            let markerColor = indicator.color(dim: color, bright: foreground)
            return ANSIRenderer.colorize(
                centred(_SwatchGridCore.selectionMark, in: cellWidth),
                foreground: markerColor, background: color, bold: indicator.isFocused)
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

    /// Black or white, whichever reads better on palette colour `index`.
    static func contrast(forIndex index: Int) -> Color {
        let c = Color.palette(UInt8(index)).rgbComponents ?? (0, 0, 0)
        let luminance = 0.299 * Double(c.red) + 0.587 * Double(c.green) + 0.114 * Double(c.blue)
        return luminance > 140 ? .rgb(0, 0, 0) : .rgb(255, 255, 255)
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
        // O(1): the grid's footprint is fixed by the layout, no need to place all
        // 256 cells just to size it (this is measured for every tab-width probe).
        return ViewSize(
            width: Palette256Layout.widthInCells * cellWidth,
            height: Palette256Layout.rows.count,
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

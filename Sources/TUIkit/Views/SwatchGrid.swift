//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SwatchGrid.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitStyling

// MARK: - State indices

/// `StateStorage` property indices for ``_SwatchGridCore``.
private enum SwatchGridStateIndex {
    static let focusID = 0
    static let handler = 1
}

// MARK: - Focus handler

/// Focus handler for a uniform grid of colour swatches: owns a cursor index into
/// the entries and moves it with the arrow keys (left/right by one, up/down by a
/// row), committing the chosen colour through `selection` live. Enter/Space
/// re-commit the current cell.
final class SwatchGridHandler: PersistedFocusable {
    var focusID: String
    var canBeFocused: Bool

    /// The cursor's index into ``entries``.
    private(set) var cursor: Int

    var selection: Binding<Color>
    var entries: [Color]
    var columns: Int

    init(
        focusID: String, cursor: Int, selection: Binding<Color>,
        entries: [Color], columns: Int, canBeFocused: Bool = true
    ) {
        self.focusID = focusID
        self.selection = selection
        self.entries = entries
        self.columns = max(1, columns)
        self.cursor = entries.isEmpty ? 0 : max(0, min(entries.count - 1, cursor))
        self.canBeFocused = canBeFocused
    }

    /// Clamps `index` to the entries, stores it, and writes its colour out.
    func commit(to index: Int) {
        guard !entries.isEmpty else { return }
        cursor = max(0, min(entries.count - 1, index))
        selection.wrappedValue = entries[cursor]
    }

    /// Moves the cursor to `index` *without* writing `selection` — tracks the
    /// current colour (possibly set elsewhere) until the user picks a swatch.
    func syncCursor(to index: Int) {
        guard !entries.isEmpty else { return }
        cursor = max(0, min(entries.count - 1, index))
    }

    func handleKeyEvent(_ event: KeyEvent) -> Bool {
        switch event.key {
        case .up: move(by: -columns); return true
        case .down: move(by: columns); return true
        case .left: move(by: -1); return true
        case .right: move(by: 1); return true
        case .enter, .space: commit(to: cursor); return true
        default: return false
        }
    }

    private func move(by delta: Int) {
        let target = cursor + delta
        // Vertical moves off the grid are no-ops; horizontal moves clamp.
        guard target >= 0, target < entries.count else { return }
        commit(to: target)
    }
}

// MARK: - Renderable core

/// A focusable, mouse-clickable grid of arbitrary colour swatches, laid out in a
/// fixed number of columns. The cursor cell shows a bullet (`●` focused, `○`
/// not) in a contrasting foreground so it stays visible on any swatch. Procedural
/// rendering, so it's a private `_*Core` ``Renderable``; the public surface is
/// the curated palette tabs of ``ColorPickerPanel`` (greyscale, web-safe, …).
struct _SwatchGridCore: View, Renderable {
    let entries: [Color]
    let columns: Int
    let selection: Binding<Color>
    var cellWidth: Int = 2
    /// Swatch height in lines. Each grid row renders `cellHeight` identical
    /// coloured lines; the cursor's check sits on the middle one.
    var cellHeight: Int = 1
    /// When true, the selection marker is drawn only if the bound colour exactly
    /// matches one of the swatches — never on a merely-nearest cell. For discrete
    /// palettes (web-safe, crayons) a "nearest" marker would misleadingly imply
    /// the shown colour is selected when it isn't.
    var exactMatchOnly: Bool = false
    var focusID: String?

    var body: Never { fatalError("_SwatchGridCore renders via Renderable") }

    private typealias StateIndex = SwatchGridStateIndex

    private var rows: Int { entries.isEmpty ? 0 : (entries.count + columns - 1) / columns }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        guard !entries.isEmpty else { return FrameBuffer() }
        let isDisabled = !context.environment.isEnabled
        let stateStorage = context.stateStorage!
        let palette = context.environment.palette

        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context, explicitFocusID: focusID,
            defaultPrefix: "swatchgrid", propertyIndex: StateIndex.focusID)

        let handlerKey = StateStorage.StateKey(
            identity: context.identity, propertyIndex: StateIndex.handler)
        let handlerBox: StateBox<SwatchGridHandler> = stateStorage.storage(
            for: handlerKey,
            default: SwatchGridHandler(
                focusID: persistedFocusID,
                cursor: Self.nearestIndex(of: selection.wrappedValue, in: entries, palette: palette),
                selection: selection, entries: entries, columns: columns,
                canBeFocused: !isDisabled))
        let handler = handlerBox.value
        handler.selection = selection
        handler.entries = entries
        handler.columns = columns
        handler.canBeFocused = !isDisabled
        // Track the swatch nearest the current colour (an exact match when the
        // colour is one of the entries) so the cursor reflects the bound colour
        // rather than defaulting to the first swatch.
        handler.syncCursor(to: Self.nearestIndex(of: selection.wrappedValue, in: entries, palette: palette))

        if !context.isMeasuring {
            FocusRegistration.register(
            context: context, handler: handler, focusID: persistedFocusID)
        }
        let isFocused = FocusRegistration.isFocused(context: context, focusID: persistedFocusID)
        // The CYCLE, not this tick's colour: the cursor swatch's mark is handed
        // to the run loop rather than rebuilt by re-rendering the whole panel
        // on every tick. Resolved once (the phase is shared across cells); each
        // cell applies it against its own colour.
        //
        // Drawing only — see `RenderContext.indicatesFocus(_:)`. The check mark
        // on the cursor swatch announces focus, so it goes with the effect; the
        // keys never read this.
        let cycle = context.environment.selectionEmphasis.cycle(context.indicatesFocus(isFocused))
        let indicator = cycle.frames[cycle.step % max(1, cycle.frames.count)]

        // Whether to draw the cursor marker at all. With exactMatchOnly, only
        // when the bound colour is genuinely one of the swatches (the cursor
        // still tracks the nearest cell for navigation, just unmarked).
        let resolvedSelection = selection.wrappedValue.resolve(with: palette)
        let markerVisible = !exactMatchOnly
            || entries.contains { $0.resolve(with: palette) == resolvedSelection }

        var lines: [String] = []
        let markRow = cellHeight / 2  // the sub-line that carries the cursor check
        // Resolved once, outside the loops: one sub-line of one cell carries the
        // mark, and its two ends are the swatch sitting under the cursor.
        let cursorMark = entries.indices.contains(handler.cursor)
            ? Self.markEnds(for: entries[handler.cursor], palette: palette)
            : nil
        let cursorMarkNow = cursorMark.map {
            (color: indicator.color(dim: $0.dim, bright: $0.bright), isBold: indicator.isFocused)
        }
        for row in 0..<rows {
            var sublines = [String](repeating: "", count: max(1, cellHeight))
            for col in 0..<columns {
                let index = row * columns + col
                guard index < entries.count else { break }
                let isCursor = markerVisible && index == handler.cursor
                for h in sublines.indices {
                    sublines[h] += cellText(
                        entries[index], cellWidth: cellWidth, palette: palette,
                        mark: isCursor && h == markRow ? cursorMarkNow : nil)
                }
            }
            lines.append(contentsOf: sublines)
        }
        var buffer = FrameBuffer(lines: lines)
        // One run, over the cursor swatch's marked sub-line alone: it is the
        // only cell whose appearance moves. Its column is the cell's, its row
        // the `markRow` sub-line of the cell's row — the same two numbers the
        // draw above used.
        if !context.isMeasuring, cycle.isAnimating, markerVisible,
            handler.cursor >= 0, handler.cursor < entries.count,
            // Non-nil exactly when the cursor is in range, which the two
            // conditions above have just established — bound here so the run's
            // ends are the same two colours the draw above used, with no
            // second lookup and no fallback that could silently differ.
            let ends = cursorMark,
            // Equal ends (a swatch or an ink with no RGB) are a still mark.
            cycle.isAnimating(dim: ends.dim, bright: ends.bright)
        {
            let row = handler.cursor / columns
            let col = handler.cursor % columns
            buffer.animatedCells = [
                AnimatedCellRun(
                    offsetX: col * cellWidth, offsetY: row * max(1, cellHeight) + markRow,
                    width: cellWidth,
                    // One ramp for the run: the mark's ends are the swatch
                    // under the cursor, which does not change while the cycle
                    // plays, so `colors` builds the ramp once where the old
                    // `frames.map { cellText(indicator: $0) }` built one per
                    // frame.
                    frames: cycle.colors(dim: ends.dim, bright: ends.bright).map {
                        cellText(
                            entries[handler.cursor], cellWidth: cellWidth, palette: palette,
                            mark: (color: $0, isBold: cycle.isFocused))
                    },
                    frameTicks: cycle.frameTicks, clock: cycle.clock)
            ]
        }

        // Mouse: clicking a swatch commits it. One handler per cell.
        if !context.isMeasuring, let dispatcher = context.environment.mouseEventDispatcher {
            let focusManager = context.environment.focusManager
            for row in 0..<rows {
                for col in 0..<columns {
                    let index = row * columns + col
                    guard index < entries.count else { break }
                    let handlerID = dispatcher.register(in: context) { event in
                        guard event.phase == .released, event.button == .left else {
                            return event.phase == .pressed && event.button == .left
                        }
                        focusManager?.focus(id: persistedFocusID)
                        handler.commit(to: index)
                        return true
                    }
                    buffer.hitTestRegions.append(
                        HitTestRegion(
                            offsetX: col * cellWidth, offsetY: row * cellHeight,
                            width: cellWidth, height: cellHeight,
                            handlerID: handlerID, focusID: persistedFocusID))
                }
            }
        }

        return buffer
    }

    /// The selected swatch's mark: a check, centred on the swatch. Drawn in the
    /// palette's readable ink for the swatch (`ContrastingLabel.on`), so it reads on
    /// any colour and follows the theme.
    static let selectionMark = "✔"

    /// The two ends the cursor swatch's mark breathes between: the swatch's own
    /// colour, and the tone that reads on it.
    ///
    /// Named apart from ``cellText(_:cellWidth:palette:mark:)`` so a caller
    /// drawing the whole cycle can hand them to
    /// `SelectionEmphasisCycle.colors(dim:bright:)` ONCE. `cellText` used to
    /// take a `SelectionEmphasis` and resolve the mark itself, which rebuilt
    /// the pulse ramp for every frame of the run.
    ///
    /// The ink twice where either end has no RGB (`Color.breathEnds(dim:bright:)`): the
    /// cycle's blend would snap, and the mark would blink between the swatch it sits on,
    /// which hides it, and the ink (§79.1).
    static func markEnds(for color: Color, palette: any Palette) -> (dim: Color, bright: Color) {
        Color.breathEnds(dim: color.resolve(with: palette), bright: ContrastingLabel.on(color, palette: palette))
    }

    /// One swatch: the colour as a background, with a check on the selected cell.
    /// The check is in the palette's readable ink for the swatch, so it stays visible
    /// on any swatch; when the grid is focused it animates (per
    /// ``View/selectionIndicatorStyle(_:)``) between the swatch colour and that ink —
    /// breathing/blinking/steady — and is bold.
    ///
    /// `mark` is what makes a cell the CURSOR cell — non-nil says "draw the
    /// check here", in the colour this frame of the cycle calls for. One
    /// parameter rather than an `isCursor` flag beside a colour, so the two
    /// cannot disagree.
    private func cellText(
        _ color: Color, cellWidth: Int, palette: any Palette,
        mark: (color: Color, isBold: Bool)?
    ) -> String {
        guard let mark else {
            return ANSIRenderer.colorize(String(repeating: " ", count: cellWidth), background: color)
        }
        return ANSIRenderer.colorize(
            Self.centred(Self.selectionMark, in: cellWidth),
            foreground: mark.color, background: color, bold: mark.isBold)
    }

    /// Centres `text` within `width` cells (a trailing-biased split for odd gaps).
    static func centred(_ text: String, in width: Int) -> String {
        let length = text.count
        guard width > length else { return text }
        let left = (width - length) / 2
        return String(repeating: " ", count: left) + text
            + String(repeating: " ", count: width - length - left)
    }

    /// The index of the entry that best matches `color`: an exact match if the
    /// colour is one of the entries, otherwise the nearest by RGB distance
    /// (resolving a semantic colour first). 0 if there are no entries.
    ///
    /// A terminal slot measures as the colour the terminal reported for it, or
    /// xterm's value while it has reported none (`Color.estimatedRGB`).
    static func nearestIndex(of color: Color, in entries: [Color], palette: any Palette) -> Int {
        guard !entries.isEmpty else { return 0 }
        if let exact = entries.firstIndex(of: color) { return exact }
        let target = color.resolve(with: palette).estimatedRGB ?? (0, 0, 0)
        var best = 0
        var bestDistance = Int.max
        for (i, entry) in entries.enumerated() {
            let c = entry.resolve(with: palette).estimatedRGB ?? (0, 0, 0)
            let dr = Int(c.red) - Int(target.red)
            let dg = Int(c.green) - Int(target.green)
            let db = Int(c.blue) - Int(target.blue)
            let distance = dr * dr + dg * dg + db * db
            if distance < bestDistance {
                bestDistance = distance
                best = i
            }
        }
        return best
    }
}

// MARK: - Layout

extension _SwatchGridCore: Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        ViewSize(
            width: columns * cellWidth,
            height: rows * cellHeight,
            isWidthFlexible: false,
            isHeightFlexible: false)
    }
}

// MARK: - Named swatch grid

/// A swatch grid plus a read-out of the focused swatch's name — for palettes
/// whose colours have names (CSS named colours, macOS crayons). The name tracks
/// the swatch nearest the bound colour, which is exactly where the grid's cursor
/// sits, so navigating updates the grid and the read-out together.
struct _NamedSwatchGrid: View {
    let entries: [(name: String, color: Color)]
    let columns: Int
    let selection: Binding<Color>
    /// Forwarded to the grid; also gates the name read-out, so a discrete palette
    /// (e.g. crayons) shows no name unless the colour exactly matches a swatch.
    var exactMatchOnly: Bool = false
    var cellWidth: Int = 2
    var cellHeight: Int = 1
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            _SwatchGridCore(
                entries: entries.map(\.color), columns: columns,
                selection: selection, cellWidth: cellWidth, cellHeight: cellHeight,
                exactMatchOnly: exactMatchOnly)
            Text(currentName).foregroundStyle(.palette.foregroundSecondary)
        }
    }

    private var currentName: String {
        let colors = entries.map(\.color)
        let resolved = selection.wrappedValue.resolve(with: palette)
        if exactMatchOnly {
            // Only name a swatch the colour genuinely is — no nearest fallback.
            return entries.first { $0.color.resolve(with: palette) == resolved }?.name ?? ""
        }
        let index = _SwatchGridCore.nearestIndex(of: selection.wrappedValue, in: colors, palette: palette)
        return entries.indices.contains(index) ? entries[index].name : ""
    }
}

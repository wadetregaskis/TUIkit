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

// MARK: - Focus handler

/// Focus handler for the 256-colour grid: owns the cursor index and moves it
/// with the arrow keys, writing the chosen palette colour through `selection`
/// live (so the panel's preview tracks the cursor). Enter/Space re-commit the
/// current cell.
final class Color256GridHandler: Focusable {
    let focusID: String
    var canBeFocused: Bool

    /// The cursor's palette index, 0–255.
    private(set) var cursor: Int

    /// The colour being edited; cursor moves write `.palette(index)` to it.
    var selection: Binding<Color>

    init(focusID: String, cursor: Int, selection: Binding<Color>, canBeFocused: Bool = true) {
        self.focusID = focusID
        self.cursor = max(0, min(255, cursor))
        self.selection = selection
        self.canBeFocused = canBeFocused
    }

    /// Moves the cursor by `delta` (clamped) and commits the new colour.
    private func move(by delta: Int) {
        commit(to: cursor + delta)
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
        case .up: move(by: -Color256GridMetrics.columns); return true
        case .down: move(by: Color256GridMetrics.columns); return true
        case .left: move(by: -1); return true
        case .right: move(by: 1); return true
        case .enter, .space: commit(to: cursor); return true
        default: return false
        }
    }
}

// MARK: - Grid metrics

/// Shared layout constants so the handler's vertical step, `sizeThatFits`, and
/// the renderer all agree on the grid shape.
enum Color256GridMetrics {
    /// Columns in the grid; 16 columns × 16 rows covers the 256 palette.
    static let columns = 16
    static let rows = 16
    /// Each cell is two cells wide (a legible swatch).
    static let cellWidth = 2
    static var width: Int { columns * cellWidth }
    static var height: Int { rows }
}

// MARK: - Renderable core

/// Renders the xterm 256-colour palette as a focusable 16×16 grid of swatches
/// with an arrow-navigable cursor. Procedural (per-cell background colour +
/// cursor frame) so it's a private `_*Core` ``Renderable``; the public surface
/// is ``ColorPickerPanel``'s 256 tab.
struct _Color256GridCore: View, Renderable {
    let selection: Binding<Color>
    var focusID: String? = nil

    var body: Never { fatalError("_Color256GridCore renders via Renderable") }

    private typealias StateIndex = Color256GridStateIndex

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
        // Keep the highlighted cell on the swatch nearest the current colour
        // (an exact match when the colour is a palette entry, otherwise the
        // closest cube/grey cell). This tracks colours set on other tabs and
        // fixes the cursor defaulting to black when the colour isn't a palette
        // entry. The grid's own navigation writes `.palette(cursor)`, so this
        // round-trips to the same cell.
        handler.syncCursor(to: Self.nearestIndex(of: selection.wrappedValue, palette: context.environment.palette))

        if !context.isMeasuring {
            FocusRegistration.register(context: context, handler: handler)
        }
        let isFocused = FocusRegistration.isFocused(context: context, focusID: persistedFocusID)

        return FrameBuffer(lines: Self.renderGrid(cursor: handler.cursor, isFocused: isFocused))
    }

    // MARK: Rendering

    /// Builds the grid lines: each cell is the palette colour as a background;
    /// the cursor cell is framed `[]` (focused) or `()` (unfocused) in a
    /// contrasting foreground.
    static func renderGrid(cursor: Int, isFocused: Bool) -> [String] {
        var lines: [String] = []
        for row in 0..<Color256GridMetrics.rows {
            var line = ""
            for col in 0..<Color256GridMetrics.columns {
                let index = row * Color256GridMetrics.columns + col
                let color = Color.palette(UInt8(index))
                if index == cursor {
                    line += ANSIRenderer.colorize(
                        isFocused ? "[]" : "()",
                        foreground: contrast(forIndex: index),
                        background: color)
                } else {
                    line += ANSIRenderer.colorize("  ", background: color)
                }
            }
            lines.append(line)
        }
        return lines
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
        ViewSize(
            width: Color256GridMetrics.width,
            height: Color256GridMetrics.height,
            isWidthFlexible: false,
            isHeightFlexible: false
        )
    }
}

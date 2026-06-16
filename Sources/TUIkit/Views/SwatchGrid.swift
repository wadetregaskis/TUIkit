//  🖥️ TUIKit — Terminal UI Kit for Swift
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
final class SwatchGridHandler: Focusable {
    let focusID: String
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
    var focusID: String? = nil

    var body: Never { fatalError("_SwatchGridCore renders via Renderable") }

    private typealias StateIndex = SwatchGridStateIndex

    private var rows: Int { entries.isEmpty ? 0 : (entries.count + columns - 1) / columns }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        guard !entries.isEmpty else { return FrameBuffer() }
        let isDisabled = !context.environment.isEnabled
        let stateStorage = context.environment.stateStorage!
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
            FocusRegistration.register(context: context, handler: handler)
        }
        let isFocused = FocusRegistration.isFocused(context: context, focusID: persistedFocusID)

        var lines: [String] = []
        for row in 0..<rows {
            var line = ""
            for col in 0..<columns {
                let index = row * columns + col
                guard index < entries.count else { break }
                line += cellText(
                    entries[index], cellWidth: cellWidth, palette: palette,
                    isCursor: index == handler.cursor, isFocused: isFocused)
            }
            lines.append(line)
        }
        var buffer = FrameBuffer(lines: lines)

        // Mouse: clicking a swatch commits it. One handler per cell.
        if !context.isMeasuring, let dispatcher = context.environment.mouseEventDispatcher {
            let focusManager = context.environment.focusManager
            for row in 0..<rows {
                for col in 0..<columns {
                    let index = row * columns + col
                    guard index < entries.count else { break }
                    let handlerID = dispatcher.register { event in
                        guard event.phase == .released, event.button == .left else {
                            return event.phase == .pressed && event.button == .left
                        }
                        focusManager.focus(id: persistedFocusID)
                        handler.commit(to: index)
                        return true
                    }
                    buffer.hitTestRegions.append(
                        HitTestRegion(
                            offsetX: col * cellWidth, offsetY: row,
                            width: cellWidth, height: 1,
                            handlerID: handlerID, focusID: persistedFocusID))
                }
            }
        }

        return buffer
    }

    /// One swatch: the colour as a background, with a contrasting cursor marker.
    /// A two-or-more-cell swatch uses the half-block pair "▐▌", which abut into
    /// one contiguous bar centred on the swatch (a lone "●" would sit in one half
    /// of an even-width cell, and the half-circles ◖◗ render as two separated
    /// pieces); a one-cell swatch falls back to ●/○. Bold marks keyboard focus.
    private func cellText(
        _ color: Color, cellWidth: Int, palette: any Palette, isCursor: Bool, isFocused: Bool
    ) -> String {
        guard isCursor else {
            return ANSIRenderer.colorize(String(repeating: " ", count: cellWidth), background: color)
        }
        let marker = cellWidth >= 2 ? "▐▌" : (isFocused ? "●" : "○")
        return ANSIRenderer.colorize(
            Self.centred(marker, in: cellWidth),
            foreground: Self.contrast(for: color, palette: palette),
            background: color, bold: isFocused)
    }

    /// Centres `text` within `width` cells (a trailing-biased split for odd gaps).
    static func centred(_ text: String, in width: Int) -> String {
        let length = text.count
        guard width > length else { return text }
        let left = (width - length) / 2
        return String(repeating: " ", count: left) + text
            + String(repeating: " ", count: width - length - left)
    }

    /// Black or white, whichever reads better on `color`.
    static func contrast(for color: Color, palette: any Palette) -> Color {
        let c = color.resolve(with: palette).rgbComponents ?? (0, 0, 0)
        let luminance = 0.299 * Double(c.red) + 0.587 * Double(c.green) + 0.114 * Double(c.blue)
        return luminance > 140 ? .rgb(0, 0, 0) : .rgb(255, 255, 255)
    }

    /// The index of the entry that best matches `color`: an exact match if the
    /// colour is one of the entries, otherwise the nearest by RGB distance
    /// (resolving a semantic colour first). 0 if there are no entries.
    static func nearestIndex(of color: Color, in entries: [Color], palette: any Palette) -> Int {
        guard !entries.isEmpty else { return 0 }
        if let exact = entries.firstIndex(of: color) { return exact }
        let target = color.resolve(with: palette).rgbComponents ?? (0, 0, 0)
        var best = 0
        var bestDistance = Int.max
        for (i, entry) in entries.enumerated() {
            let c = entry.resolve(with: palette).rgbComponents ?? (0, 0, 0)
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
            height: rows,
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
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            _SwatchGridCore(entries: entries.map(\.color), columns: columns, selection: selection)
            Text(currentName).foregroundStyle(.palette.foregroundSecondary)
        }
    }

    private var currentName: String {
        let colors = entries.map(\.color)
        let index = _SwatchGridCore.nearestIndex(of: selection.wrappedValue, in: colors, palette: palette)
        return entries.indices.contains(index) ? entries[index].name : ""
    }
}

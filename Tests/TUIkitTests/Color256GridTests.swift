//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Color256GridTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

/// A reference holder so a `Binding<Color>` can be read back in tests.
private final class ColorBox {
    var color: Color
    init(_ color: Color) { self.color = color }
    var binding: Binding<Color> { Binding(get: { self.color }, set: { self.color = $0 }) }
}

@MainActor
@Suite("Color256Grid — handler")
struct Color256GridHandlerTests {

    @Test("Grid metrics cover the 256 palette as 16×16")
    func metrics() {
        #expect(Color256GridMetrics.columns == 16)
        #expect(Color256GridMetrics.rows == 16)
        #expect(Color256GridMetrics.columns * Color256GridMetrics.rows == 256)
        #expect(Color256GridMetrics.width == 32)  // 16 cols × 2-wide cells
        #expect(Color256GridMetrics.height == 16)
    }

    @Test("commit clamps to 0…255 and writes .palette(index)")
    func commitClamps() {
        let box = ColorBox(.rgb(0, 0, 0))
        let handler = Color256GridHandler(focusID: "g", cursor: 0, selection: box.binding)
        handler.commit(to: 5)
        #expect(handler.cursor == 5)
        #expect(box.color == .palette(5))
        handler.commit(to: 999)
        #expect(handler.cursor == 255)
        handler.commit(to: -3)
        #expect(handler.cursor == 0)
    }

    @Test("Arrow keys move the cursor by the grid stride and commit live")
    func arrowNavigation() {
        let box = ColorBox(.rgb(0, 0, 0))
        let handler = Color256GridHandler(focusID: "g", cursor: 0, selection: box.binding)
        #expect(handler.handleKeyEvent(KeyEvent(key: .down)))   // +16
        #expect(handler.cursor == 16)
        #expect(box.color == .palette(16))
        #expect(handler.handleKeyEvent(KeyEvent(key: .right)))  // +1
        #expect(handler.cursor == 17)
        #expect(handler.handleKeyEvent(KeyEvent(key: .up)))     // -16
        #expect(handler.cursor == 1)
        #expect(handler.handleKeyEvent(KeyEvent(key: .left)))   // -1 → 0
        #expect(handler.cursor == 0)
        #expect(handler.handleKeyEvent(KeyEvent(key: .left)))   // clamp at 0
        #expect(handler.cursor == 0)
        // An unrelated key is not consumed.
        #expect(!handler.handleKeyEvent(KeyEvent(key: .tab)))
    }

    @Test("index(of:) recovers a palette index, else nil")
    func indexOf() {
        #expect(_Color256GridCore.index(of: .palette(42)) == 42)
        #expect(_Color256GridCore.index(of: .rgb(1, 2, 3)) == nil)
    }

    @Test("Cursor seeds from a palette-colour selection")
    func cursorSeeds() {
        let box = ColorBox(.palette(123))
        let handler = Color256GridHandler(
            focusID: "g", cursor: _Color256GridCore.index(of: box.color) ?? 0, selection: box.binding)
        #expect(handler.cursor == 123)
    }

    @Test("nearestIndex matches an exact palette colour and approximates others")
    func nearestIndex() {
        let palette = SystemPalette(.green)
        // Exact palette entries map to themselves.
        #expect(_Color256GridCore.nearestIndex(of: .palette(200), palette: palette) == 200)
        // Pure colours map to their cube corners (index 16 = black, 231 = white).
        #expect(_Color256GridCore.nearestIndex(of: .rgb(0, 0, 0), palette: palette) == 16)
        #expect(_Color256GridCore.nearestIndex(of: .rgb(255, 255, 255), palette: palette) == 231)
        // A 24-bit colour with no exact entry still resolves to a real index.
        let approx = _Color256GridCore.nearestIndex(of: .rgb(38, 139, 210), palette: palette)
        #expect((0...255).contains(approx))
        // A semantic colour resolves first, then maps (no crash, a real index).
        let accentIdx = _Color256GridCore.nearestIndex(of: .palette.accent, palette: palette)
        #expect((0...255).contains(accentIdx))
    }

    @Test("The grid highlights the nearest cell for a non-palette colour, not black")
    func gridSeedsNearestNotBlack() {
        // White is not a 256-palette entry value, but its nearest cell is 231 —
        // the grid must seed there, not at index 0 (black). (Bug: it always
        // showed black selected.)
        let box = ColorBox(.rgb(255, 255, 255))
        let buffer = renderToBuffer(
            _Color256GridCore(selection: box.binding, focusID: "grid-seed"),
            context: makeRenderContext(width: 40, height: 18))
        // The framed cursor "[]"/"()" must NOT be on the first (black) cell, and
        // must appear somewhere (white's nearest cube cell, index 231, is row 14).
        let lines = buffer.lines.map { $0.stripped }
        func framed(_ s: String) -> Bool { s.contains("[") || s.contains("(") }
        #expect(!framed(lines[0]), "cursor is NOT on the first (black) cell: \(lines[0])")
        #expect(lines.contains(where: framed), "cursor is shown on a cell")
    }
}

@MainActor
@Suite("Color256Grid — rendering")
struct Color256GridRenderTests {

    @Test("Renders 16 colourful rows with a framed cursor cell")
    func rendersGrid() {
        let focused = _Color256GridCore.renderGrid(cursor: 0, isFocused: true)
        #expect(focused.count == 16)
        #expect(focused.allSatisfy { $0.contains("\u{1B}[") }, "every row carries colour escapes")
        #expect(focused.contains { $0.contains("48;5;") }, "cells use the indexed 256-colour background")
        #expect(focused[0].contains("[]"), "the focused cursor cell is framed []")
        // Unfocused draws the cursor as () instead.
        let unfocused = _Color256GridCore.renderGrid(cursor: 0, isFocused: false)
        #expect(unfocused[0].contains("()"))
    }

    @Test("Contrast picks black on light cells and white on dark cells")
    func contrast() {
        // Cube index 16 is (0,0,0) → needs a light marker; 231 is (255,255,255) → dark.
        #expect(_Color256GridCore.contrast(forIndex: 16) == .rgb(255, 255, 255))
        #expect(_Color256GridCore.contrast(forIndex: 231) == .rgb(0, 0, 0))
    }
}

@MainActor
@Suite("Color256Grid — focus integration")
struct Color256GridFocusTests {

    @Test("Once focused, arrows route to the grid, move the cursor, and select live")
    func focusedNavigation() {
        let box = ColorBox(.rgb(0, 0, 0))
        let ctx = makeRenderContext()
        let focusManager = ctx.environment.focusManager
        let grid = _Color256GridCore(selection: box.binding, focusID: "grid-test")

        // Rendering registers the handler; as the sole focusable it auto-focuses,
        // so the cursor cell is framed [] (the focused marker, not ()).
        let rendered = renderToBuffer(grid, context: ctx).lines.joined()
        #expect(focusManager.isFocused(id: "grid-test"), "the grid is focusable")
        #expect(rendered.contains("[]"), "focused cursor frame")

        // The cursor seeds at black's nearest cube cell (index 16), not 0.
        // Arrow keys route to the grid and write the colour live: down a row
        // (+16) → 32, then right (+1) → 33.
        #expect(focusManager.dispatchKeyEvent(KeyEvent(key: .down)))
        #expect(box.color == .palette(32))
        #expect(focusManager.dispatchKeyEvent(KeyEvent(key: .right)))
        #expect(box.color == .palette(33))
    }
}

@MainActor
@Suite("ColorPickerPanel — 256 tab")
struct ColorPickerPanel256TabTests {

    @Test("256 is a channelless tab present in the strip")
    func tabPresent() {
        #expect(ColorPickerPanel.Mode.allCases.contains(.palette256))
        #expect(ColorPickerPanel.Mode.palette256.channels.isEmpty)
        let view = ColorPickerPanel(
            "C", selection: .constant(.rgb(10, 20, 30)), isPresented: .constant(true))
        let text = renderToBuffer(view, context: makeRenderContext()).lines.joined(separator: "\n")
        #expect(text.contains("256"))
    }
}

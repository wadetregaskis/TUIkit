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
@Suite("Color256Grid — layout")
struct Color256GridLayoutTests {

    @Test("The layout places all 256 palette entries, each exactly once")
    func placesEveryEntry() {
        let cells = Palette256Layout.place(cellWidth: 1).cells
        #expect(cells.count == 256)
        #expect(Set(cells.map(\.index)) == Set(0...255), "every index 0…255 appears once")
    }

    @Test("Sections follow the xterm structure: 16 system, 216 cube, 24 grey")
    func sectionStructure() {
        // The greyscale ramp is the widest row (24 cells), so it sets the grid width.
        #expect(Palette256Layout.widthInCells == 24)
        // First non-empty row is the 16 system colours as two groups of eight
        // (a single gap between), i.e. 17 columns of content.
        let system = Palette256Layout.rows.first { !$0.isEmpty }!
        #expect(system.compactMap { $0 } == Array(0...15))
        #expect(system.count == 17, "8 + gap + 8")
        // The last row is the 24-step greyscale ramp 232…255.
        let grey = Palette256Layout.rows.last { !$0.isEmpty }!
        #expect(grey.compactMap { $0 } == Array(232...255))
    }

    @Test("Cell width tracks the numbers toggle: 1 cell compact, 3 with numbers")
    func cellWidthScales() {
        #expect(Palette256Layout.place(cellWidth: 1).width == 24)
        #expect(Palette256Layout.place(cellWidth: 3).width == 72)
        #expect(Palette256Layout.place(cellWidth: 1).height == Palette256Layout.rows.count)
    }
}

@MainActor
@Suite("Color256Grid — handler")
struct Color256GridHandlerTests {

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

    @Test("Arrow keys move spatially through the placed swatches and commit live")
    func arrowNavigation() {
        let box = ColorBox(.rgb(0, 0, 0))
        let handler = Color256GridHandler(focusID: "g", cursor: 16, selection: box.binding)
        // Navigation reads the placed geometry the renderer produces.
        handler.placements = Palette256Layout.place(cellWidth: 1).cells

        // 16 is the top-left of the cube's first red slice (green 0, blue 0).
        #expect(handler.handleKeyEvent(KeyEvent(key: .down)))   // → green 1 (index 22)
        #expect(handler.cursor == 22)
        #expect(box.color == .palette(22))
        #expect(handler.handleKeyEvent(KeyEvent(key: .right)))  // → blue 1 (index 23)
        #expect(handler.cursor == 23)
        #expect(handler.handleKeyEvent(KeyEvent(key: .up)))     // → green 0, blue 1 (index 17)
        #expect(handler.cursor == 17)
        #expect(handler.handleKeyEvent(KeyEvent(key: .left)))   // → blue 0 (index 16)
        #expect(handler.cursor == 16)
        // An unrelated key is not consumed.
        #expect(!handler.handleKeyEvent(KeyEvent(key: .tab)))
    }

    @Test("Left/right stay within the visual row; an edge move is a no-op")
    func horizontalStaysInRow() {
        let box = ColorBox(.palette(232))  // first greyscale cell, left edge of its row
        let handler = Color256GridHandler(focusID: "g", cursor: 232, selection: box.binding)
        handler.placements = Palette256Layout.place(cellWidth: 1).cells
        #expect(handler.handleKeyEvent(KeyEvent(key: .left)))  // already at the left edge
        #expect(handler.cursor == 232, "no cell to the left, so the cursor holds")
        #expect(handler.handleKeyEvent(KeyEvent(key: .right)))
        #expect(handler.cursor == 233, "moves one along the greyscale row")
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
}

@MainActor
@Suite("Color256Grid — rendering")
struct Color256GridRenderTests {

    @Test("Renders the sectioned grid with a contrasting bullet on the cursor cell")
    func rendersGrid() {
        let (focused, cells) = _Color256GridCore.renderGrid(
            cursor: 16, indicator: .steady(isFocused: true), cellWidth: 2, showNumbers: false)
        #expect(focused.count == Palette256Layout.rows.count)
        #expect(cells.count == 256)
        let nonEmpty = focused.filter { !$0.isEmpty }
        #expect(nonEmpty.allSatisfy { $0.contains("\u{1B}[") }, "every content row carries colour escapes")
        #expect(focused.contains { $0.contains("48;5;") }, "cells use the indexed 256-colour background")
        // The cursor cell is marked with a contrasting check.
        #expect(focused.contains { $0.contains("✔") }, "the cursor cell shows the selection check")
    }

    @Test("Numbers mode prints each index in a five-cell swatch, never run together")
    func numbersMode() {
        // cursor 0 keeps 16/255 as numbered (non-cursor) cells.
        let (lines, _) = _Color256GridCore.renderGrid(
            cursor: 0, indicator: .steady(isFocused: true), cellWidth: 5, showNumbers: true)
        let joined = lines.joined()
        #expect(joined.contains("16"), "an index is printed in the swatch")
        #expect(joined.contains("255"), "the last greyscale index is printed")
        // Five-cell swatches keep at least a space between adjacent indices — the
        // three-cell layout used to render e.g. "100101102" with no separation.
        #expect(!joined.contains("100101"), "adjacent three-digit indices don't run together")
        #expect(!joined.contains("232233"), "…not even along the dense greyscale row")
    }

    @Test("Contrast picks black on light cells and white on dark cells")
    func contrast() {
        // Cube index 16 is (0,0,0) → needs a light marker; 231 is (255,255,255) → dark.
        #expect(_Color256GridCore.contrast(forIndex: 16) == .rgb(255, 255, 255))
        #expect(_Color256GridCore.contrast(forIndex: 231) == .rgb(0, 0, 0))
    }

    @Test("The grid highlights the nearest cell for a non-palette colour, not black")
    func gridSeedsNearestNotBlack() {
        // White is not a 256-palette entry value, but its nearest cell is 231 —
        // the grid must seed there, not at index 0 (black). (Bug: it always
        // showed black selected.)
        let box = ColorBox(.rgb(255, 255, 255))
        let buffer = renderToBuffer(
            _Color256GridCore(selection: box.binding, focusID: "grid-seed"),
            context: makeRenderContext(width: 64, height: 24))  // ≥48 so the 2-wide grid isn't clipped
        let lines = buffer.lines.map { $0.stripped }
        func bulleted(_ s: String) -> Bool { s.contains("✔") }
        // index 231 lives in the cube's last red slice, well below the first row.
        #expect(!bulleted(lines.first { !$0.isEmpty } ?? ""), "cursor is NOT on the first (black) row")
        #expect(lines.contains(where: bulleted), "cursor is shown on a cell")
    }
}

@MainActor
@Suite("Color256Grid — focus + mouse integration")
struct Color256GridFocusTests {

    @Test("Once focused, arrows route to the grid, move the cursor, and select live")
    func focusedNavigation() {
        let box = ColorBox(.rgb(0, 0, 0))
        let ctx = makeRenderContext()
        let focusManager = ctx.environment.focusManager
        let grid = _Color256GridCore(selection: box.binding, focusID: "grid-test")

        // Rendering registers the handler; as the sole focusable it auto-focuses,
        // so the cursor cell shows the filled bullet.
        let rendered = renderToBuffer(grid, context: ctx).lines.joined()
        #expect(focusManager.isFocused(id: "grid-test"), "the grid is focusable")
        #expect(rendered.contains("✔"), "the cursor cell shows the selection check")

        // The cursor seeds at black's nearest cube cell (index 16). Down a green
        // step → 22, then right a blue step → 23.
        #expect(focusManager.dispatchKeyEvent(KeyEvent(key: .down)))
        #expect(box.color == .palette(22))
        #expect(focusManager.dispatchKeyEvent(KeyEvent(key: .right)))
        #expect(box.color == .palette(23))
    }

    @Test("Clicking a swatch commits that palette index (the grid responds to the mouse)")
    func mouseClickSelects() {
        let box = ColorBox(.rgb(0, 0, 0))
        let tui = TUIContext()
        let fm = FocusManager()
        let grid = _Color256GridCore(selection: box.binding, focusID: "grid-mouse")

        var env = EnvironmentValues()
        env.focusManager = fm
        env.mouseEventDispatcher = tui.mouseEventDispatcher
        let ctx = RenderContext(availableWidth: 64, availableHeight: 24, environment: env, tuiContext: tui)
        fm.beginRenderPass()
        let buffer = renderToBuffer(grid, context: ctx)
        fm.endRenderPass()

        // Every swatch is a hit region now.
        #expect(buffer.hitTestRegions.count == 256, "one clickable region per swatch")
        // Click the greyscale row's last cell (index 255), bottom-right of the
        // grid. Swatches are two cells wide, so place with that width.
        let cells = Palette256Layout.place(cellWidth: 2).cells
        let target = cells.first { $0.index == 255 }!
        tui.mouseEventDispatcher.setRegions(buffer.hitTestRegions)
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: target.x, y: target.y))
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: target.x, y: target.y))
        #expect(box.color == .palette(255), "the clicked swatch is selected, got \(box.color)")
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

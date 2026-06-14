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

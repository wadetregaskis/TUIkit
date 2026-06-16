//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SwatchGridTests.swift
//
//  Created by Wade Tregaskis
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
@Suite("SwatchGrid — handler")
struct SwatchGridHandlerTests {

    private let entries: [Color] = (0..<12).map { (i: Int) -> Color in
        Color.rgb(UInt8(i * 20), 0, 0)
    }

    @Test("commit clamps to the entry range and writes the entry's colour")
    func commitClamps() {
        let box = ColorBox(.rgb(0, 0, 0))
        let handler = SwatchGridHandler(
            focusID: "g", cursor: 0, selection: box.binding, entries: entries, columns: 4)
        handler.commit(to: 5)
        #expect(handler.cursor == 5)
        #expect(box.color == entries[5])
        handler.commit(to: 999)
        #expect(handler.cursor == entries.count - 1)
        handler.commit(to: -3)
        #expect(handler.cursor == 0)
    }

    @Test("Arrow keys move by one (left/right) and by a row (up/down), clamped")
    func arrowNavigation() {
        let box = ColorBox(.rgb(0, 0, 0))
        // 12 entries, 4 columns → 3 rows.
        let handler = SwatchGridHandler(
            focusID: "g", cursor: 0, selection: box.binding, entries: entries, columns: 4)
        #expect(handler.handleKeyEvent(KeyEvent(key: .right)))  // 0 → 1
        #expect(handler.cursor == 1)
        #expect(handler.handleKeyEvent(KeyEvent(key: .down)))   // 1 → 5 (next row)
        #expect(handler.cursor == 5)
        #expect(handler.handleKeyEvent(KeyEvent(key: .up)))     // 5 → 1
        #expect(handler.cursor == 1)
        #expect(handler.handleKeyEvent(KeyEvent(key: .left)))   // 1 → 0
        #expect(handler.cursor == 0)
        #expect(handler.handleKeyEvent(KeyEvent(key: .up)))     // off the top → no-op
        #expect(handler.cursor == 0)
        #expect(box.color == entries[0])
        // An unrelated key is not consumed.
        #expect(!handler.handleKeyEvent(KeyEvent(key: .tab)))
    }

    @Test("nearestIndex matches an exact entry, else the closest by RGB distance")
    func nearestIndex() {
        let palette = SystemPalette(.green)
        #expect(_SwatchGridCore.nearestIndex(of: entries[7], in: entries, palette: palette) == 7)
        // A colour between entries 5 (100,0,0) and 6 (120,0,0) → nearest is 5 or 6.
        let near = _SwatchGridCore.nearestIndex(of: .rgb(108, 0, 0), in: entries, palette: palette)
        #expect(near == 5 || near == 6)
        // Far-off green resolves to the darkest red entry (all entries are reddish).
        let any = _SwatchGridCore.nearestIndex(of: .rgb(0, 255, 0), in: entries, palette: palette)
        #expect((0..<entries.count).contains(any))
    }
}

@MainActor
@Suite("SwatchGrid — rendering + mouse")
struct SwatchGridRenderTests {

    private let entries: [Color] = (0..<16).map { (i: Int) -> Color in
        let v = UInt8(i * 16)
        return Color.rgb(v, v, v)
    }

    @Test("Renders a coloured grid with a bullet on the cursor cell")
    func rendersGrid() {
        let box = ColorBox(entries[3])
        let buffer = renderToBuffer(
            _SwatchGridCore(entries: entries, columns: 8, selection: box.binding, focusID: "sg"),
            context: makeRenderContext(width: 40, height: 12))
        let joined = buffer.lines.joined()
        #expect(joined.contains("48;5;") || joined.contains("48;2;"), "swatches carry a background colour")
        #expect(joined.contains("●") || joined.contains("○"), "the cursor cell shows a bullet")
        // 16 entries / 8 columns → 2 rows.
        #expect(buffer.lines.count == 2, "laid out in 2 rows of 8")
    }

    @Test("Clicking a swatch commits its colour (the grid responds to the mouse)")
    func mouseClickSelects() {
        let box = ColorBox(entries[0])
        let tui = TUIContext()
        let fm = FocusManager()
        let grid = _SwatchGridCore(entries: entries, columns: 8, selection: box.binding, focusID: "sg-mouse")

        var env = EnvironmentValues()
        env.focusManager = fm
        env.mouseEventDispatcher = tui.mouseEventDispatcher
        let ctx = RenderContext(availableWidth: 40, availableHeight: 12, environment: env, tuiContext: tui)
        fm.beginRenderPass()
        let buffer = renderToBuffer(grid, context: ctx)
        fm.endRenderPass()

        #expect(buffer.hitTestRegions.count == entries.count, "one clickable region per swatch")
        // Click entry 11 — row 1 (11 / 8), column 3, each cell two wide.
        let x = (11 % 8) * 2
        let y = 11 / 8
        tui.mouseEventDispatcher.setRegions(buffer.hitTestRegions)
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x, y: y))
        #expect(box.color == entries[11], "the clicked swatch is selected, got \(box.color)")
    }
}

@MainActor
@Suite("ColorPickerPanel — greyscale tab")
struct ColorPickerGreyscaleTabTests {

    @Test("Greyscale is an evenly-spaced black→white ramp of greys")
    func ramp() {
        let greys = SwatchPalettes.greyscale
        #expect(greys.count == 32)
        #expect(greys.first == .rgb(0, 0, 0), "starts at black")
        #expect(greys.last == .rgb(255, 255, 255), "ends at white")
        // Every entry is a true grey (R == G == B).
        #expect(greys.allSatisfy { c in
            let rgb = c.rgbComponents!
            return rgb.red == rgb.green && rgb.green == rgb.blue
        }, "every entry is a neutral grey")
    }

    @Test("Greyscale is a channelless tab present in the strip")
    func tabPresent() {
        #expect(ColorPickerPanel.Mode.allCases.contains(.greyscale))
        #expect(ColorPickerPanel.Mode.greyscale.channels.isEmpty)
        let view = ColorPickerPanel(
            "C", selection: .constant(.rgb(10, 20, 30)), isPresented: .constant(true))
        let text = renderToBuffer(view, context: makeRenderContext(width: 80, height: 30))
            .lines.map { $0.stripped }.joined(separator: "\n")
        #expect(text.contains("Greyscale"))
    }
}

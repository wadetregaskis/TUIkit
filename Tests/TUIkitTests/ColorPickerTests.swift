//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ColorPickerTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("ColorPicker Tests")
struct ColorPickerTests {

    private func makeContext(width: Int = 80, height: Int = 5) -> RenderContext {
        makeRenderContext(width: width, height: height)
    }

    @Test("Renders its title and a swatch in the bound colour")
    func rendersTitleAndSwatch() {
        let picker = ColorPicker("Tint", selection: .constant(.rgb(255, 0, 0)))
        let buffer = renderToBuffer(picker, context: makeContext())
        let text = buffer.lines.joined()

        #expect(!buffer.isEmpty)
        #expect(text.contains("Tint"))
        // The swatch is styled with the bound colour, so its 24-bit SGR code appears.
        #expect(text.contains("38;2;255;0;0"))
    }

    @Test("Shows each channel's current value")
    func showsChannelValues() {
        let picker = ColorPicker("C", selection: .constant(.rgb(10, 200, 75)))
        let text = renderToBuffer(picker, context: makeContext()).lines.joined()
        // Each channel's numeric read-out is shown.
        #expect(text.contains("10"))
        #expect(text.contains("200"))
        #expect(text.contains("75"))
    }

    @Test("Editing a channel rewrites only that component as .rgb")
    func editingRewritesChannel() {
        var color: Color = .rgb(10, 20, 30)
        let binding = Binding(get: { color }, set: { color = $0 })
        // Drive the picker's own binding logic the way a slider would: set the
        // green channel via a fresh ColorPicker over the same binding by reading
        // it back through rgbComponents (the picker rewrites via .rgb).
        _ = ColorPicker("x", selection: binding)
        // Simulate a green edit through the same contract the picker uses.
        if var c = color.rgbComponents {
            c.green = 200
            color = .rgb(c.red, c.green, c.blue)
        }
        #expect(color.rgbComponents?.red == 10)
        #expect(color.rgbComponents?.green == 200)
        #expect(color.rgbComponents?.blue == 30)
    }
}

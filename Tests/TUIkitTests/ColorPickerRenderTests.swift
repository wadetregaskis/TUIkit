//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ColorPickerRenderTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT
//
//  Buffer-level render audit for the terminal colour pickers: the inline
//  `ColorPicker` (a swatch plus R/G/B channel sliders) and the modal
//  `ColorPickerPanel` (a Dialog with a preview, model tabs, and a channel
//  editor). Asserts the rendered FrameBuffer shows the expected chrome.

import Testing

@testable import TUIkit

@MainActor
@Suite("ColorPicker rendering")
struct ColorPickerRenderTests {

    /// All rendered lines joined — the pickers lay content out in 2D, so most
    /// assertions are "does the picker draw this somewhere" rather than
    /// per-line exact matches.
    private func joined(_ v: some View, w: Int = 64, h: Int = 30) -> String {
        renderToBuffer(v, context: makeRenderContext(width: w, height: h))
            .lines.map { $0.stripped }.joined(separator: "\n")
    }

    // MARK: - Inline ColorPicker

    @Test("Inline ColorPicker draws its title, a live swatch and R/G/B channel sliders")
    func inlineColorPickerChrome() {
        let out = joined(ColorPicker("Accent", selection: .constant(.red)), w: 60, h: 4)
        #expect(out.contains("Accent"), "title shown: \(out)")
        #expect(out.contains("███"), "live swatch shown")
        // One labelled slider per RGB component (label + slider's left arrow).
        #expect(out.contains("R ◀") && out.contains("G ◀") && out.contains("B ◀"),
                "three labelled channel sliders: \(out)")
    }

    @Test("Inline ColorPicker's channels reflect the bound colour")
    func inlineColorPickerReflectsBinding() {
        // The picker is stateless — the bound colour is the single source of
        // truth, so editing a different colour must change what is drawn.
        let red = joined(ColorPicker("T", selection: .constant(.red)), w: 60, h: 4)
        let blue = joined(ColorPicker("T", selection: .constant(.blue)), w: 60, h: 4)
        #expect(red != blue, "different colours fill the channels differently")
    }

    // MARK: - Modal ColorPickerPanel

    @Test("ColorPickerPanel draws the dialog title, preview, every model tab and Done")
    func panelChrome() {
        let out = joined(
            ColorPickerPanel("Theme Colour", selection: .constant(.red), isPresented: .constant(true)))
        #expect(out.contains("Theme Colour"), "dialog title: \(out)")
        // All six model tabs are present in the TabView strip (the active one is
        // highlighted by background colour, not brackets).
        #expect(out.contains("RGB"), "RGB tab: \(out)")
        #expect(out.contains("HSL") && out.contains("HSB") && out.contains("CMYK"))
        #expect(out.contains("Semantic") && out.contains("256"), "the semantic + 256-grid tabs")
        // Preview read-outs: hex and rgb(...) for the current colour.
        #expect(out.contains("#") && out.contains("rgb("), "hex + rgb read-outs present")
        #expect(out.contains("Done"))
    }

    @Test("ColorPickerPanel's RGB editor shows the three channel sliders")
    func panelRGBChannels() {
        let out = joined(
            ColorPickerPanel("Pick", selection: .constant(.red), isPresented: .constant(true)))
        // Default mode is RGB: a labelled slider row per channel.
        #expect(out.contains("◀") && out.contains("▶"), "channel sliders render arrows: \(out)")
        #expect(out.contains("R ◀") && out.contains("G ◀") && out.contains("B ◀"),
                "one slider row per RGB channel")
    }

    @Test("ColorPickerPanel shows a large (10×5) gap-free preview swatch")
    func panelLargePreview() {
        let raw = renderToBuffer(
            ColorPickerPanel("C", selection: .constant(.rgb(205, 100, 50)), isPresented: .constant(true)),
            context: makeRenderContext(width: 64, height: 40)
        ).lines
        // The swatch is spaces filled with the colour's background (no █ glyphs,
        // which leave hairline gaps). It tops the panel, five rows tall — so the
        // first handful of lines each carry a background SGR (`48;…`).
        let filledNearTop = raw.prefix(7).filter { $0.contains("48;") }
        #expect(filledNearTop.count >= 5, "preview swatch is ≥5 background-filled rows: \(filledNearTop.count)")
        // The swatch rows are blank once stripped (spaces, not █ glyphs) — they
        // carry only a background colour.
        let strippedTop = raw.prefix(7).map { $0.stripped }
        #expect(strippedTop.contains { $0.contains("          ") && !$0.contains("█") },
                "the swatch uses background fill, not block glyphs")
    }

    @Test("An RGB channel row shows editable percent, integer and hex fields")
    func panelChannelEditableFields() {
        let lines = renderToBuffer(
            ColorPickerPanel("Pick", selection: .constant(.rgb(205, 100, 50)), isPresented: .constant(true)),
            context: makeRenderContext(width: 70, height: 30)
        ).lines.map { $0.stripped }
        let rRow = lines.first { $0.contains("R ◀") } ?? ""
        // Three representations of red = 205: 80% of 255, the integer 205, and 0xCD.
        #expect(rRow.contains("80%"), "percentage field: \(rRow)")
        #expect(rRow.contains("205"), "integer field: \(rRow)")
        #expect(rRow.contains("0xCD"), "hex field: \(rRow)")
        // Each sits in a TextField (end caps), and the slider no longer prints %.
        #expect(rRow.contains("▐") && rRow.contains("▌"), "editable fields with end caps: \(rRow)")
    }

    @Test("Channels with a 0–100 range show a single (percent) field, no duplicate integer")
    func panelNoDuplicateFields() {
        // CMYK channels are 0–100, where the integer and percentage coincide — so
        // only one field is shown, not two identical ones. (Switch to CMYK first.)
        let box = ColorBoxRef(.rgb(200, 100, 50))
        let ctx = makeRenderContext(width: 70, height: 30)
        let fm = ctx.environment.focusManager!
        let panel = ColorPickerPanel("C", selection: box.binding, isPresented: .constant(true))
        func render() -> [String] { renderToBuffer(panel, context: ctx).lines.map { $0.stripped } }
        _ = render()
        _ = fm.dispatchKeyEvent(KeyEvent(key: .tab))                 // hex field → strip
        for _ in 0..<3 { _ = fm.dispatchKeyEvent(KeyEvent(key: .right)) }  // → CMYK
        let cRow = render().first { $0.contains("C ◀") } ?? ""
        // A percent field is present; there is exactly one capped field on the row.
        #expect(cRow.contains("%"), "CMYK channel shows a percentage field: \(cRow)")
        #expect(cRow.filter { $0 == "▐" }.count == 1, "exactly one field, no duplicate: \(cRow)")
    }

    @Test("ColorPickerPanel renders inside a bordered dialog")
    func panelHasBorder() {
        let lines = renderToBuffer(
            ColorPickerPanel("Edit", selection: .constant(.green), isPresented: .constant(true)),
            context: makeRenderContext(width: 64, height: 30)
        ).lines.map { $0.stripped }
        // A Dialog draws a box: some line carries a top-border corner glyph.
        #expect(lines.contains { $0.contains("╭") || $0.contains("┌") }, "dialog has a top border")
        #expect(lines.contains { $0.contains("╰") || $0.contains("└") }, "dialog has a bottom border")
    }
}

/// A reference holder so a `Binding<Color>` can be read back in render tests.
private final class ColorBoxRef {
    var color: Color
    init(_ color: Color) { self.color = color }
    var binding: Binding<Color> { Binding(get: { self.color }, set: { self.color = $0 }) }
}

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

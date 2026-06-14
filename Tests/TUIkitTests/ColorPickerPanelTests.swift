//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ColorPickerPanelTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("ColorPickerPanel — channel model")
struct ColorPickerPanelChannelTests {

    typealias Panel = ColorPickerPanel

    // MARK: Mode metadata

    @Test("Each mode exposes the right channels with correct bounds")
    func modeChannels() {
        #expect(Panel.Mode.rgb.channels.map(\.label) == ["R", "G", "B"])
        #expect(Panel.Mode.hsl.channels.map(\.label) == ["H", "S", "L"])
        #expect(Panel.Mode.hsb.channels.map(\.label) == ["H", "S", "B"])
        #expect(Panel.Mode.cmyk.channels.map(\.label) == ["C", "M", "Y", "K"])
        #expect(Panel.Mode.rgb.channels.map(\.upperBound) == [255, 255, 255])
        #expect(Panel.Mode.hsl.channels.map(\.upperBound) == [360, 100, 100])
        #expect(Panel.Mode.cmyk.channels.map(\.upperBound) == [100, 100, 100, 100])
    }

    // MARK: RGB (exact)

    @Test("RGB channelValue reads the components")
    func rgbRead() {
        let c = Color.rgb(10, 20, 30)
        #expect(Panel.channelValue(of: c, mode: .rgb, index: 0) == 10)
        #expect(Panel.channelValue(of: c, mode: .rgb, index: 1) == 20)
        #expect(Panel.channelValue(of: c, mode: .rgb, index: 2) == 30)
    }

    @Test("RGB set rewrites only the chosen channel, clamped")
    func rgbSet() {
        let c = Color.rgb(10, 20, 30)
        #expect(Panel.color(bySetting: 200, at: 1, mode: .rgb, of: c).rgbComponents! == (10, 200, 30))
        // Clamps above 255 and below 0.
        #expect(Panel.color(bySetting: 999, at: 0, mode: .rgb, of: c).rgbComponents!.red == 255)
        #expect(Panel.color(bySetting: -5, at: 2, mode: .rgb, of: c).rgbComponents!.blue == 0)
    }

    // MARK: HSL / HSB / CMYK (match the colour-space constructor exactly)

    @Test("Setting an HSL channel matches the .hsl constructor with that channel changed")
    func hslSetMatchesConstructor() {
        let c = Color.rgb(200, 100, 50)
        let hsl = Color.rgbToHSL(red: 200, green: 100, blue: 50)
        // index 1 = saturation
        let viaPanel = Panel.color(bySetting: 42, at: 1, mode: .hsl, of: c)
        let viaCtor = Color.hsl(hsl.hue, 42, hsl.lightness)
        #expect(viaPanel.rgbComponents! == viaCtor.rgbComponents!)
    }

    @Test("Setting an HSB channel matches the .hsb constructor")
    func hsbSetMatchesConstructor() {
        let c = Color.rgb(200, 100, 50)
        let hsb = Color.rgbToHSB(red: 200, green: 100, blue: 50)
        let viaPanel = Panel.color(bySetting: 42, at: 2, mode: .hsb, of: c)  // brightness
        let viaCtor = Color.hsb(hsb.hue, hsb.saturation, 42)
        #expect(viaPanel.rgbComponents! == viaCtor.rgbComponents!)
    }

    @Test("Setting a CMYK channel matches the .cmyk constructor (4 channels)")
    func cmykSetMatchesConstructor() {
        let c = Color.rgb(200, 100, 50)
        let cmyk = Color.rgbToCMYK(red: 200, green: 100, blue: 50)
        let viaPanel = Panel.color(bySetting: 25, at: 3, mode: .cmyk, of: c)  // black
        let viaCtor = Color.cmyk(cmyk.cyan, cmyk.magenta, cmyk.yellow, 25)
        #expect(viaPanel.rgbComponents! == viaCtor.rgbComponents!)
    }

    @Test("Channel indices are not swapped: editing S differs from editing L")
    func channelOrderNotSwapped() {
        let c = Color.rgb(200, 100, 50)
        let editS = Panel.color(bySetting: 80, at: 1, mode: .hsl, of: c).rgbComponents!
        let editL = Panel.color(bySetting: 80, at: 2, mode: .hsl, of: c).rgbComponents!
        #expect(editS != editL, "setting saturation must not behave like setting lightness")
    }

    // MARK: Read-out formatting

    @Test("Hex and rgb read-outs format components, and degrade for nil")
    func readouts() {
        #expect(Panel.hexString((80, 160, 255)) == "#50A0FF")
        #expect(Panel.rgbString((80, 160, 255)) == "rgb(80, 160, 255)")
        #expect(Panel.hexString(nil) == "#------")
        #expect(Panel.rgbString(nil).contains("—"))
    }
}

@MainActor
@Suite("ColorPickerPanel — rendering")
struct ColorPickerPanelRenderTests {

    @Test("Renders the title, preview read-outs, tab labels and default RGB channels")
    func rendersDefault() {
        let view = ColorPickerPanel(
            "Accent", selection: .constant(.rgb(80, 160, 255)), isPresented: .constant(true))
        let text = renderToBuffer(view, context: makeRenderContext()).lines.joined(separator: "\n")
        // Title + preview read-outs derived from the bound colour.
        #expect(text.contains("Accent"))
        #expect(text.contains("#50A0FF"))
        #expect(text.contains("rgb(80, 160, 255)"))
        // All four model tabs are present.
        for tab in ["RGB", "HSL", "HSB", "CMYK"] {
            #expect(text.contains(tab), "missing tab \(tab)")
        }
        // Default RGB channel read-outs show the bound components.
        #expect(text.contains("255"))
        #expect(text.contains("160"))
    }
}

@MainActor
@Suite("ColorPickerPanel — semantic tab")
struct ColorPickerPanelSemanticTests {

    @Test("Semantic is a tab with no numeric channels")
    func semanticIsChannelless() {
        #expect(ColorPickerPanel.Mode.allCases.contains(.semantic))
        #expect(ColorPickerPanel.Mode.semantic.channels.isEmpty)
    }

    @Test("Semantic table maps names to palette-role references")
    func semanticTable() {
        let table = ColorPickerPanel.semanticColors
        #expect(table.contains { $0.name == "Accent" && $0.color == .palette.accent })
        #expect(table.contains { $0.name == "Error" && $0.color == .palette.error })
        // Distinct roles are distinct colour references.
        #expect(Color.palette.accent != Color.palette.success)
        // The core roles are offered.
        let names = Set(table.map(\.name))
        #expect(names.isSuperset(of: ["Foreground", "Accent", "Success", "Warning", "Error", "Background"]))
    }

    @Test("A semantic selection resolves to a concrete read-out, and the tab shows")
    func semanticPreviewResolves() {
        let view = ColorPickerPanel(
            "Tint", selection: .constant(.palette.accent), isPresented: .constant(true))
        let text = renderToBuffer(view, context: makeRenderContext()).lines.joined(separator: "\n")
        #expect(!text.contains("#------"), "a semantic colour should resolve, not blank out")
        #expect(text.contains("Semantic"), "the Semantic tab should be present")
    }
}

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

// MARK: - Crash-safety / fuzz

/// Hammers the channel model and the panel's rendering with awkward inputs —
/// the colour picker "crashes a lot" reports trace back to colour-space maths
/// that trapped on out-of-range / non-finite values (`.hsl`), so these tests
/// assert the whole surface stays trap-free.
@MainActor
@Suite("ColorPickerPanel — crash safety")
struct ColorPickerPanelCrashSafetyTests {

    typealias Panel = ColorPickerPanel

    /// A spread of seed colours: rgb extremes, grays, mid-tones, 256-palette
    /// entries, and semantic colours (whose `rgbComponents` is nil until
    /// resolved — the channel model must cope).
    static let seeds: [Color] = [
        .rgb(0, 0, 0), .rgb(255, 255, 255), .rgb(255, 0, 0), .rgb(0, 255, 0),
        .rgb(0, 0, 255), .rgb(128, 128, 128), .rgb(38, 139, 210), .rgb(200, 100, 50),
        .rgb(1, 254, 130), .rgb(254, 1, 1),
        .palette(0), .palette(15), .palette(16), .palette(123), .palette(231), .palette(255),
        .red, .green, .blue, .palette.accent, .palette.success, .palette.error,
    ]

    static let channelModes: [Panel.Mode] = [.rgb, .hsl, .hsb, .cmyk]

    @Test("channelValue never traps and is finite, for every mode/channel/seed")
    func channelValueIsFinite() {
        for mode in Self.channelModes {
            for seed in Self.seeds {
                for index in mode.channels.indices {
                    let v = Panel.channelValue(of: seed, mode: mode, index: index)
                    #expect(v.isFinite, "channelValue(\(mode), \(index)) on \(seed) was \(v)")
                }
            }
        }
    }

    @Test("color(bySetting:) never traps and yields a concrete RGB, across a value sweep")
    func setChannelNeverTraps() {
        for mode in Self.channelModes {
            for seed in Self.seeds {
                for index in mode.channels.indices {
                    let bound = mode.channels[index].upperBound
                    // Below-range, the bounds, midpoints, and well past the top —
                    // a slider clamps, but the constructor must be robust anyway.
                    for value in [-1000.0, -1, 0, bound / 2, bound, bound + 1, bound + 1000] {
                        let out = Panel.color(bySetting: value, at: index, mode: mode, of: seed)
                        #expect(out.rgbComponents != nil,
                                "set \(mode) ch\(index)=\(value) on \(seed) did not yield RGB")
                    }
                }
            }
        }
    }

    @Test("A full GET→SET→GET round-trip on every channel stays trap-free and finite")
    func roundTripStable() {
        for mode in Self.channelModes {
            for seed in Self.seeds {
                for index in mode.channels.indices {
                    let v = Panel.channelValue(of: seed, mode: mode, index: index)
                    let edited = Panel.color(bySetting: v, at: index, mode: mode, of: seed)
                    let again = Panel.channelValue(of: edited, mode: mode, index: index)
                    #expect(again.isFinite)
                }
            }
        }
    }

    @Test("The panel renders without trapping for every seed colour")
    func rendersForEverySeed() {
        for seed in Self.seeds {
            let view = ColorPickerPanel("C", selection: .constant(seed), isPresented: .constant(true))
            let buffer = renderToBuffer(view, context: makeRenderContext(width: 64, height: 30))
            #expect(!buffer.lines.isEmpty, "panel produced no output for \(seed)")
            // The preview read-out resolves the seed to a concrete hex (never blanks).
            let text = buffer.lines.map { $0.stripped }.joined(separator: "\n")
            #expect(text.contains("#") && !text.contains("#------"), "resolved hex read-out for \(seed)")
        }
    }

    /// A reference box so the panel's binding writes are observable.
    private final class Box {
        var color: Color
        init(_ c: Color) { color = c }
        var binding: Binding<Color> { Binding(get: { self.color }, set: { self.color = $0 }) }
    }

    @Test("Activating the HSL tab switches the editor to H/S/L channels")
    func switchToHSLTabRendersChannels() {
        let box = Box(.rgb(38, 139, 210))
        let ctx = makeRenderContext(width: 64, height: 30)
        let fm = ctx.environment.focusManager
        let panel = ColorPickerPanel("C", selection: box.binding, isPresented: .constant(true))
        func render() -> String {
            renderToBuffer(panel, context: ctx).lines.map { $0.stripped }.joined(separator: "\n")
        }

        // First render auto-focuses the first tab ("[RGB]"). Tab → the HSL tab;
        // Enter activates it, flipping the panel's `mode` to .hsl.
        _ = render()
        _ = fm.dispatchKeyEvent(KeyEvent(key: .tab))
        _ = fm.dispatchKeyEvent(KeyEvent(key: .enter))
        let out = render()

        #expect(out.contains("[HSL]"), "HSL is now the active (bracketed) tab: \(out)")
        #expect(out.contains("H ") && out.contains("S ") && out.contains("L "),
                "the HSL channel rows are shown")
    }

    @Test("A long stream of key events through the live panel never traps")
    func keyEventMonkeyDoesNotTrap() {
        let box = Box(.rgb(200, 100, 50))
        let ctx = makeRenderContext(width: 64, height: 30)
        let fm = ctx.environment.focusManager
        let panel = ColorPickerPanel("C", selection: box.binding, isPresented: .constant(true))
        func render() { _ = renderToBuffer(panel, context: ctx) }
        render()

        // Cycle focus through tabs / channels / grid and drive every kind of
        // edit. Switching to HSL/HSB/CMYK then hammering End/Home/arrows is the
        // path that used to trap in the colour-space maths.
        let keys: [Key] = [.tab, .enter, .end, .home, .right, .left, .up, .down, .space]
        for i in 0..<240 {
            _ = fm.dispatchKeyEvent(KeyEvent(key: keys[i % keys.count]))
            render()
        }
        // Reaching here means none of the 240 events trapped. The drive really
        // exercised the panel — the bound colour was rewritten away from its seed.
        #expect(box.color != .rgb(200, 100, 50), "the key stream actually edited the colour")
    }

    @Test("Clicking every hit region across re-renders never traps (mouse path)")
    func mouseClickMonkeyDoesNotTrap() {
        let box = Box(.rgb(38, 139, 210))
        let ctx = makeRenderContext(width: 64, height: 30) { environment, tui in
            environment.mouseEventDispatcher = tui.mouseEventDispatcher
        }
        let dispatcher = ctx.environment.mouseEventDispatcher!
        let panel = ColorPickerPanel("C", selection: box.binding, isPresented: .constant(true))

        // Several passes: each pass clicks the centre of every current hit region
        // (tabs switch the model, slider tracks set a value from the click x), then
        // re-renders — so later passes land on whatever editor the clicks revealed,
        // including the HSL/HSB/CMYK channel sliders and the 256 grid.
        for _ in 0..<6 {
            let buffer = renderToBuffer(panel, context: ctx)
            let regions = buffer.hitTestRegions
            dispatcher.setRegions(regions)
            for region in regions {
                let x = region.offsetX + max(0, region.width / 2)
                let y = region.offsetY + max(0, region.height / 2)
                _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
                _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x, y: y))
            }
        }
        // Final render must still succeed after all that clicking.
        #expect(!renderToBuffer(panel, context: ctx).lines.isEmpty)
    }
}

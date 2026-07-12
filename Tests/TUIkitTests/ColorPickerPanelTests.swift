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

    @Test("color(from:) builds RGB straight from the channels, clamped")
    func rgbSet() {
        #expect(Panel.color(from: [10, 200, 30], mode: .rgb).rgbComponents! == (10, 200, 30))
        // Clamps above 255 and below 0.
        #expect(Panel.color(from: [999, 20, 30], mode: .rgb).rgbComponents!.red == 255)
        #expect(Panel.color(from: [10, 20, -5], mode: .rgb).rgbComponents!.blue == 0)
        // A short array reads missing channels as 0 rather than trapping.
        #expect(Panel.color(from: [10], mode: .rgb).rgbComponents! == (10, 0, 0))
    }

    // MARK: HSL / HSB / CMYK (match the colour-space constructor exactly)

    @Test("Building an HSL colour matches the .hsl constructor for the same channels")
    func hslSetMatchesConstructor() {
        let hsl = Color.rgbToHSL(red: 200, green: 100, blue: 50)
        // index 1 = saturation
        let viaPanel = Panel.color(from: [hsl.hue, 42, hsl.lightness], mode: .hsl)
        let viaCtor = Color.hsl(hsl.hue, 42, hsl.lightness)
        #expect(viaPanel.rgbComponents! == viaCtor.rgbComponents!)
    }

    @Test("Building an HSB colour matches the .hsb constructor")
    func hsbSetMatchesConstructor() {
        let hsb = Color.rgbToHSB(red: 200, green: 100, blue: 50)
        let viaPanel = Panel.color(from: [hsb.hue, hsb.saturation, 42], mode: .hsb)  // index 2 = brightness
        let viaCtor = Color.hsb(hsb.hue, hsb.saturation, 42)
        #expect(viaPanel.rgbComponents! == viaCtor.rgbComponents!)
    }

    @Test("Building a CMYK colour matches the .cmyk constructor (4 channels)")
    func cmykSetMatchesConstructor() {
        let cmyk = Color.rgbToCMYK(red: 200, green: 100, blue: 50)
        let viaPanel = Panel.color(from: [cmyk.cyan, cmyk.magenta, cmyk.yellow, 25], mode: .cmyk)  // index 3 = black
        let viaCtor = Color.cmyk(cmyk.cyan, cmyk.magenta, cmyk.yellow, 25)
        #expect(viaPanel.rgbComponents! == viaCtor.rgbComponents!)
    }

    @Test("Channel indices are not swapped: editing S differs from editing L")
    func channelOrderNotSwapped() {
        let hsl = Color.rgbToHSL(red: 200, green: 100, blue: 50)
        let editS = Panel.color(from: [hsl.hue, 80, hsl.lightness], mode: .hsl).rgbComponents!
        let editL = Panel.color(from: [hsl.hue, hsl.saturation, 80], mode: .hsl).rgbComponents!
        #expect(editS != editL, "setting saturation must not behave like setting lightness")
    }

    // MARK: Over-determined models keep the values you typed (#3)

    @Test("color(from:) keeps over-determined channels a round-trip would have lost")
    func overdeterminedChannelsSurvive() {
        // CMYK with K=100 is black. The old read-modify-write read C/M/Y back
        // out of that black as zero — so you couldn't hold a non-zero C/M/Y at
        // K=100. color(from:) builds straight from the channels: the result is
        // still black, but the supplied C/M/Y are honoured, not forced to zero.
        #expect(Panel.color(from: [50, 50, 50, 100], mode: .cmyk).rgbComponents! == (0, 0, 0))

        // A grey is equal C/M/Y with K=0. The round-trip collapsed equal C/M/Y
        // into K, so nudging one of C/M/Y moved K instead. color(from:) keeps
        // them independent: raising cyan alone changes the colour.
        let grey = Panel.color(from: [50, 50, 50, 0], mode: .cmyk).rgbComponents!
        let cyanUp = Panel.color(from: [80, 50, 50, 0], mode: .cmyk).rgbComponents!
        #expect(grey != cyanUp, "raising cyan alone must change the colour")

        // HSL hue is undefined on a grey, so the round-trip lost it. color(from:)
        // retains hue through zero saturation — raising S later reveals it.
        let greyHue = Panel.color(from: [200, 0, 50], mode: .hsl).rgbComponents!
        #expect(greyHue.red == greyHue.green && greyHue.green == greyHue.blue,
                "zero saturation is grey regardless of hue")
        let satUp = Panel.color(from: [200, 60, 50], mode: .hsl).rgbComponents!
        #expect(!(satUp.red == satUp.green && satUp.green == satUp.blue),
                "raising saturation reveals the retained hue")
    }

    // MARK: Read-out formatting

    @Test("Hex and rgb read-outs format components, and degrade for nil")
    func readouts() {
        #expect(Panel.hexString((80, 160, 255)) == "#50A0FF")
        #expect(Panel.rgbString((80, 160, 255)) == "rgb(80, 160, 255)")
        #expect(Panel.hexString(nil) == "#------")
        #expect(Panel.rgbString(nil).contains("—"))
    }

    // MARK: Editable channel read-out

    @Test("A typed/pasted channel value keeps the digits and clamps to range")
    func channelTextParsing() {
        #expect(Panel.channelValue(parsing: "255", into: 0...255) == 255)
        #expect(Panel.channelValue(parsing: "999", into: 0...255) == 255)  // over → clamp
        #expect(Panel.channelValue(parsing: "", into: 0...255) == 0)        // empty → lower
        #expect(Panel.channelValue(parsing: " 42 ", into: 0...100) == 42)   // trims non-digits
        #expect(Panel.channelValue(parsing: "abc", into: 0...360) == 0)     // no digits → lower
        #expect(Panel.channelValue(parsing: "1x2x3", into: 0...360) == 123) // digits only
    }

    @Test("A typed/pasted percentage scales to the channel's range, clamped 0…100")
    func percentParsing() {
        #expect(Panel.channelValue(parsingPercent: "100%", upperBound: 255) == 255)
        #expect(Panel.channelValue(parsingPercent: "50", upperBound: 100) == 50)
        #expect(Panel.channelValue(parsingPercent: "50%", upperBound: 360) == 180)  // of the range
        #expect(Panel.channelValue(parsingPercent: "999%", upperBound: 255) == 255) // clamps at 100%
        #expect(Panel.channelValue(parsingPercent: "", upperBound: 255) == 0)       // empty → 0
    }

    @Test("A typed/pasted hex value parses to a 0…255 channel, prefix-tolerant")
    func hexParsing() {
        #expect(Panel.channelValue(parsingHex: "0xFF") == 255)
        #expect(Panel.channelValue(parsingHex: "ff") == 255)        // no prefix
        #expect(Panel.channelValue(parsingHex: "#CD") == 205)       // #-prefixed
        #expect(Panel.channelValue(parsingHex: "0x00") == 0)
        #expect(Panel.channelValue(parsingHex: "1FF") == 255)       // > 255 clamps
        #expect(Panel.channelValue(parsingHex: "") == 0)            // empty → 0
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

    @Test("color(from:) never traps and yields a concrete RGB, across a channel sweep")
    func setChannelNeverTraps() {
        for mode in Self.channelModes {
            // Seed the channels from each seed colour, then sweep one channel at
            // a time below-range, at the bounds, midpoints, and well past the top
            // — a slider/field clamps, but the build must be robust anyway.
            for seed in Self.seeds {
                var base = mode.channels.indices.map {
                    Panel.channelValue(of: seed, mode: mode, index: $0)
                }
                for index in mode.channels.indices {
                    let bound = mode.channels[index].upperBound
                    for value in [-1000.0, -1, 0, bound / 2, bound, bound + 1, bound + 1000] {
                        var channels = base
                        channels[index] = value
                        let out = Panel.color(from: channels, mode: mode)
                        #expect(out.rgbComponents != nil,
                                "build \(mode) ch\(index)=\(value) on \(seed) did not yield RGB")
                    }
                    base[index] = bound  // vary the rest of the sweep too
                }
            }
        }
    }

    @Test("A full GET→build→GET round-trip on every channel stays trap-free and finite")
    func roundTripStable() {
        for mode in Self.channelModes {
            for seed in Self.seeds {
                let channels = mode.channels.indices.map {
                    Panel.channelValue(of: seed, mode: mode, index: $0)
                }
                let edited = Panel.color(from: channels, mode: mode)
                for index in mode.channels.indices {
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
        let fm = ctx.environment.focusManager!
        let panel = ColorPickerPanel("C", selection: box.binding, isPresented: .constant(true))
        func render() -> String {
            renderToBuffer(panel, context: ctx).lines.map { $0.stripped }.joined(separator: "\n")
        }

        // First render auto-focuses the preview's hex field; one Tab moves to the
        // TabView strip (on the RGB tab). A Right arrow then moves the selection
        // to the next tab (HSL), flipping `mode`.
        _ = render()
        _ = fm.dispatchKeyEvent(KeyEvent(key: .tab))    // hex field → strip
        _ = fm.dispatchKeyEvent(KeyEvent(key: .right))  // RGB → HSL
        let out = render()

        #expect(out.contains("HSL"), "HSL tab present: \(out)")
        #expect(out.contains("H ") && out.contains("S ") && out.contains("L "),
                "the HSL channel rows are shown")
    }

    @Test("Switching RGB → HSL → RGB does not corrupt the colour (no slider-state leak across tabs)")
    func tabRoundTripPreservesColour() {
        // The reported Bug B: after viewing HSL on white, returning to RGB changed
        // the colour (e.g. to #646464) and the RGB sliders were stuck at 0…100 —
        // the HSL channels' state leaking onto the RGB sliders. Each tab now has
        // isolated identity, so the round-trip is lossless.
        let box = Box(.rgb(255, 255, 255))  // white
        let tui = TUIContext()
        let fm = FocusManager()
        let panel = ColorPickerPanel("C", selection: box.binding, isPresented: .constant(true))
        func render() -> String {
            var env = EnvironmentValues()
            env.focusManager = fm
            let ctx = RenderContext(
                availableWidth: 64, availableHeight: 30, environment: env, tuiContext: tui)
            return renderToBuffer(panel, context: ctx).lines.map { $0.stripped }.joined(separator: "\n")
        }
        _ = render()                                       // RGB tab, hex field auto-focused
        _ = fm.dispatchKeyEvent(KeyEvent(key: .tab))       // hex field → strip
        _ = fm.dispatchKeyEvent(KeyEvent(key: .right))     // → HSL
        let hsl = render()
        #expect(hsl.contains("H ") && hsl.contains("L "), "actually switched to HSL: \(hsl)")
        _ = fm.dispatchKeyEvent(KeyEvent(key: .left))      // → RGB
        _ = render()
        #expect(box.color.rgbComponents! == (255, 255, 255),
                "white survived the round-trip, got \(box.color.rgbComponents!)")
    }

    @Test("HSL hue survives a trip through zero saturation (stateful editor, #3)")
    func hueSurvivesZeroSaturation() {
        // The stateless round-trip lost hue on a grey: desaturating to S=0 made
        // the colour grey, and re-reading HSL from that grey returned hue 0 — so
        // raising S again produced red, not the colour you started from. The
        // stateful editor holds the channels, so the hue is retained across S=0
        // and reappears when saturation comes back.
        let box = Box(.hsl(120, 50, 50))  // a mid-saturation green
        let tui = TUIContext()
        let fm = FocusManager()
        let panel = ColorPickerPanel("C", selection: box.binding, isPresented: .constant(true))
        // A render-loop-faithful pass: begin/endRenderPass prune the focus of the
        // tab we switched away from, so Tab navigates the *current* editor (not a
        // stale slider left registered by the previous tab).
        func render() {
            var env = EnvironmentValues()
            env.focusManager = fm
            let ctx = RenderContext(
                availableWidth: 64, availableHeight: 40, environment: env, tuiContext: tui)
            fm.beginRenderPass()
            _ = renderToBuffer(panel, context: ctx)
            fm.endRenderPass()
        }

        render()
        _ = fm.dispatchKeyEvent(KeyEvent(key: .tab)); render()     // hex field → strip
        _ = fm.dispatchKeyEvent(KeyEvent(key: .right)); render()   // RGB → HSL
        // Focus order on the HSL tab: strip, [H slider, H %, H int], [S slider, …]
        // — H has both % and integer fields, so four Tabs reach the S slider.
        for _ in 0..<4 { _ = fm.dispatchKeyEvent(KeyEvent(key: .tab)); render() }
        _ = fm.dispatchKeyEvent(KeyEvent(key: .home)); render()    // S → 0: colour goes grey
        let grey = box.color.rgbComponents!
        #expect(grey.red == grey.green && grey.green == grey.blue,
                "S=0 desaturates to grey, got \(grey)")
        _ = fm.dispatchKeyEvent(KeyEvent(key: .end)); render()     // S → 100: the retained hue returns
        let c = box.color.rgbComponents!
        // The retained hue ~120 is green, so the green channel dominates. The old
        // round-trip would have produced red here (green would NOT dominate).
        #expect(c.green > c.red && c.green > c.blue,
                "the retained green hue reappears, not red — got \(c)")
    }

    @Test("A long stream of key events through the live panel never traps")
    func keyEventMonkeyDoesNotTrap() {
        let box = Box(.rgb(200, 100, 50))
        let ctx = makeRenderContext(width: 64, height: 30)
        let fm = ctx.environment.focusManager!
        let panel = ColorPickerPanel("C", selection: box.binding, isPresented: .constant(true))
        // Render-loop-faithful: begin/endRenderPass so focus navigation stays
        // clean across the many tab switches the key stream triggers.
        func render() { fm.beginRenderPass(); _ = renderToBuffer(panel, context: ctx); fm.endRenderPass() }
        render()

        // First reach a channel slider and edit it, so the test demonstrably
        // exercises editing: Tab off the preview hex field onto the strip, again
        // into the R slider, then End drives it to its maximum.
        _ = fm.dispatchKeyEvent(KeyEvent(key: .tab)); render()   // hex field → strip
        _ = fm.dispatchKeyEvent(KeyEvent(key: .tab)); render()   // strip → R slider
        _ = fm.dispatchKeyEvent(KeyEvent(key: .end)); render()   // R → max
        #expect(box.color != .rgb(200, 100, 50),
                "reached and edited a channel, got \(box.color.rgbComponents!)")

        // Then cycle focus through tabs / channels / grid and drive every kind of
        // edit. Switching to HSL/HSB/CMYK then hammering End/Home/arrows is the
        // path that used to trap in the colour-space maths — none of it may trap.
        let keys: [Key] = [.tab, .enter, .end, .home, .right, .left, .up, .down, .space]
        for i in 0..<240 {
            _ = fm.dispatchKeyEvent(KeyEvent(key: keys[i % keys.count]))
            render()
        }
        // Reaching here means none of the 240 events trapped, and the panel still
        // renders.
        #expect(!renderToBuffer(panel, context: ctx).lines.isEmpty)
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

    /// A palette whose `accent` slot mirrors a binding — exactly the shape
    /// ThemePage uses (`selection` is a key-path binding *into the palette the
    /// view also resolves against*).
    private struct EditedPalette: Palette {
        let id = "edited"
        let name = "Edited"
        let background = Color.black
        let foreground = Color.white
        var accent: Color
        let success = Color.green
        let warning = Color.yellow
        let error = Color.red
        let info = Color.blue
        let border = Color.brightBlack
    }

    @Test("Clicking semantic swatches while the selection is bound into the palette never traps")
    func paletteBoundSemanticSelectionDoesNotTrap() {
        // Reproduces the real crash: the selection writes into `palette.accent`,
        // and that same palette is the environment the panel resolves against —
        // so a semantic pick makes `accent` a semantic reference, and every later
        // render must still resolve to concrete RGB.
        final class Holder { var color: Color = .rgb(0, 0, 255) }
        let holder = Holder()
        let selection = Binding<Color>(get: { holder.color }, set: { holder.color = $0 })

        let tui = TUIContext()
        let fm = FocusManager()
        let panel = ColorPickerPanel("Accent", selection: selection, isPresented: .constant(true))

        func renderAndClickEach() {
            var env = EnvironmentValues()
            env.focusManager = fm
            env.mouseEventDispatcher = tui.mouseEventDispatcher
            env.palette = EditedPalette(accent: holder.color)  // accent reflects the live selection
            let ctx = RenderContext(
                availableWidth: 70, availableHeight: 44, environment: env, tuiContext: tui)
            let buffer = renderToBuffer(panel, context: ctx)
            tui.mouseEventDispatcher.setRegions(buffer.hitTestRegions)
            for r in buffer.hitTestRegions {
                let x = r.offsetX + max(0, r.width / 2)
                let y = r.offsetY + max(0, r.height / 2)
                _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
                _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x, y: y))
            }
        }

        // Deterministically: render, click the Semantic tab (5th tab → region 4),
        // re-render, then click each semantic-row button — re-rendering against
        // the palette each click mutates. Assert we actually drove a semantic
        // selection (so the test can't false-pass by never reaching a swatch).
        func render() -> FrameBuffer {
            var env = EnvironmentValues()
            env.focusManager = fm
            env.mouseEventDispatcher = tui.mouseEventDispatcher
            env.palette = EditedPalette(accent: holder.color)
            let ctx = RenderContext(
                availableWidth: 70, availableHeight: 44, environment: env, tuiContext: tui)
            return renderToBuffer(panel, context: ctx)
        }
        func click(_ r: HitTestRegion) {
            tui.mouseEventDispatcher.setRegions([r])
            let x = r.offsetX + max(0, r.width / 2)
            let y = r.offsetY + max(0, r.height / 2)
            _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
            _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x, y: y))
        }

        let tabRegions = render().hitTestRegions
        #expect(tabRegions.count >= 6, "the six model tabs register hit regions")
        click(tabRegions[4])  // the Semantic tab (rgb,hsl,hsb,cmyk,semantic,256)

        let semanticView = render()
        // Semantic-row buttons follow the six tabs in render order.
        let rowRegions = Array(semanticView.hitTestRegions.dropFirst(6))
        #expect(!rowRegions.isEmpty, "the semantic tab shows selectable role rows")
        var everSemantic = false
        for row in rowRegions {
            click(row)
            _ = render()  // re-render against the palette the click just mutated
            if case .semantic = holder.color.value { everSemantic = true }
        }
        // The selection must hold a CONCRETE colour — the semantic tab snapshots
        // the role's value rather than storing a `.semantic` reference, so the
        // palette slot it's bound to never goes semantic (which would crash a
        // consumer that reads `palette.accent` directly).
        #expect(!everSemantic, "the selection never becomes a semantic reference")
        #expect(holder.color.rgbComponents != nil, "selection resolved to a concrete colour")
        #expect(holder.color != .rgb(0, 0, 255), "clicking a role actually changed the selection")
    }
}

// MARK: - Layout

@MainActor
@Suite("ColorPickerPanel — layout")
struct ColorPickerPanelLayoutTests {

    private func width(at available: Int) -> Int {
        renderToBuffer(
            ColorPickerPanel("Pick", selection: .constant(.rgb(10, 20, 30)), isPresented: .constant(true)),
            context: makeRenderContext(width: available, height: 40)
        ).width
    }

    @Test("The panel sizes to its content, not the full available width")
    func sizesToFit() {
        // On a narrow screen it fits within it — the (now ten-tab) strip wraps
        // across rows rather than overflowing.
        #expect(width(at: 80) < 80, "panel fits a narrow screen, got \(width(at: 80))")
        // On a very wide screen it does NOT grow to fill the width: it caps at
        // its natural single-row width and leaves the rest of the screen empty.
        let wide = width(at: 200)
        #expect(wide < 120, "panel does not fill a wide screen, got \(wide)")
        #expect(width(at: 300) == wide, "width caps at content, independent of extra available width")
    }
}

@MainActor
@Suite("ColorPickerPanel — editable fields (#2, #3, #4, #10)")
struct ColorPickerEditableFieldTests {

    private final class Box {
        var color: Color
        init(_ c: Color) { color = c }
        var binding: Binding<Color> { Binding(get: { self.color }, set: { self.color = $0 }) }
    }

    /// A render-loop-faithful harness: begin/endRenderPass each frame so focus
    /// navigation and the fields' focus-aware editing behave like the real loop.
    private func harness(_ box: Box) -> (render: () -> [String], fm: FocusManager) {
        let tui = TUIContext()
        let fm = FocusManager()
        let panel = ColorPickerPanel("C", selection: box.binding, isPresented: .constant(true))
        let render: () -> [String] = {
            var env = EnvironmentValues()
            env.focusManager = fm
            let ctx = RenderContext(
                availableWidth: 72, availableHeight: 40, environment: env, tuiContext: tui)
            fm.beginRenderPass()
            let buffer = renderToBuffer(panel, context: ctx)
            fm.endRenderPass()
            return buffer.lines.map { $0.stripped }
        }
        return (render, fm)
    }

    @Test("Hue's integer field is shown in degrees with a ° suffix (#3)")
    func hueDegrees() {
        let box = Box(.hsl(120, 50, 50))
        let (render, fm) = harness(box)
        _ = render()
        _ = fm.dispatchKeyEvent(KeyEvent(key: .tab))      // combined-hex → strip
        _ = fm.dispatchKeyEvent(KeyEvent(key: .right))    // → HSL
        let hRow = render().first { $0.contains("H ◀") } ?? ""
        #expect(hRow.contains("120°"), "hue shows degrees with a ° suffix: \(hRow)")
    }

    @Test("A focused hex field shows raw edits and reflects them live, not reformatted (#10)")
    func hexFieldRawWhileFocused() {
        let box = Box(.rgb(200, 16, 16))  // R = 200 = 0xC8
        let (render, fm) = harness(box)
        _ = render()
        // Tab to the red hex field. (By id, not a fixed count: the number of
        // stops before it depends on which ViewThatFits row layout the panel
        // width selects, which has changed before — e.g. when conditional
        // children stopped occupying phantom stack slots.)
        for _ in 0..<12 where fm.currentFocusedID != "RGB-0-hex" {
            _ = fm.dispatchKeyEvent(KeyEvent(key: .tab))
            _ = render()
        }
        #expect(fm.currentFocusedID == "RGB-0-hex", "focused the red hex field")
        _ = fm.dispatchKeyEvent(KeyEvent(key: .backspace))   // 0xC8 → 0xC
        let row = render().first { $0.contains("R ◀") } ?? ""
        // Shows the raw "0xC" — NOT reformatted/padded back to "0x0C".
        #expect(row.contains("0xC") && !row.contains("0x0C"), "raw, un-padded while editing: \(row)")
        // …and the value reflects it live (0xC = 12).
        #expect(box.color.rgbComponents!.red == 12, "live value, got \(box.color.rgbComponents!.red)")
    }

    @Test("Typing a digit into a cleared percent field yields that percent, not a reformatted one (#4)")
    func percentFieldNoReformat() {
        let box = Box(.hsl(120, 50, 50))  // S = 50%
        let (render, fm) = harness(box)
        _ = render()
        _ = fm.dispatchKeyEvent(KeyEvent(key: .tab))      // → strip
        _ = fm.dispatchKeyEvent(KeyEvent(key: .right))    // → HSL
        _ = render()
        // strip → H slider → H% → H int → S slider → S%.
        for _ in 0..<5 { _ = fm.dispatchKeyEvent(KeyEvent(key: .tab)); _ = render() }
        #expect(fm.currentFocusedID == "HSL-1-pct", "focused the saturation percent field")
        // Clear "50%" (%, 0, 5) then type 9 → "9", i.e. 9% — not 90%.
        for _ in 0..<3 { _ = fm.dispatchKeyEvent(KeyEvent(key: .backspace)); _ = render() }
        _ = fm.dispatchKeyEvent(KeyEvent(key: .character("9"))); _ = render()
        let s = ColorPickerPanel.channelValue(of: box.color, mode: .hsl, index: 1)
        #expect((8.0...10.0).contains(s), "typing 9 gives ~9%, not 90%, got \(s)")
    }

    @Test("The combined hex field accepts edits and updates the colour when valid (#2)")
    func combinedHexEdits() {
        let box = Box(.rgb(89, 192, 109))  // #59C06D, combined-hex auto-focused
        let (render, fm) = harness(box)
        _ = render()  // focus settles on the hex field at endRenderPass
        _ = render()  // a focused frame, as the real loop produces before the user types
        #expect(fm.currentFocusedID == "combined-hex", "the hex field takes initial focus")
        // Backspace the blue pair and retype it as FF — a render per keystroke,
        // exactly as the real loop drives it.
        _ = fm.dispatchKeyEvent(KeyEvent(key: .backspace)); _ = render()
        _ = fm.dispatchKeyEvent(KeyEvent(key: .backspace)); _ = render()
        // Mid-edit ("#59C0") is invalid hex, so the colour is unchanged so far…
        #expect(box.color.rgbComponents! == (89, 192, 109), "invalid partial leaves the colour")
        _ = fm.dispatchKeyEvent(KeyEvent(key: .character("F"))); _ = render()
        _ = fm.dispatchKeyEvent(KeyEvent(key: .character("F"))); _ = render()
        // …and completing it to #59C0FF updates the colour.
        #expect(box.color.rgbComponents! == (89, 192, 255), "completed hex set the colour, got \(box.color.rgbComponents!)")
    }
}

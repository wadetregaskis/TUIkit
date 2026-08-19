//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ColorPickerSwatchTests.swift
//
//  The swatch is the picker's other half: SwiftUI's opens the platform colour
//  panel, and this one opens `ColorPickerPanel`. It is therefore a control —
//  focusable, hoverable, activatable — and the one control that must NOT show
//  any of that by re-colouring itself, because its colour is its content.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("ColorPicker swatch")
struct ColorPickerSwatchTests {

    /// Parks focus so the swatch can be rendered *un*-focused (a fresh
    /// `FocusManager` auto-focuses its first registrant, which is the swatch).
    private final class FocusSentinel: Focusable {
        let focusID = "swatch-test-sentinel"
        func handleKeyEvent(_ event: KeyEvent) -> Bool { false }
    }

    private func picker(_ color: Color = .rgb(200, 40, 40)) -> ColorPicker {
        ColorPicker("Accent", selection: .constant(color))
    }

    /// The truecolor SGR a colour renders as, so an assertion can name the
    /// palette entry it means rather than "some escape changed".
    private func code(_ color: Color, _ palette: any Palette) -> String {
        let rgb = color.resolve(with: palette).rgbComponents!
        return "38;2;\(rgb.red);\(rgb.green);\(rgb.blue)"
    }

    // MARK: - Appearance

    @Test("A resting swatch is an unbroken block of its colour")
    func restingSwatchIsSolid() {
        let context = makeRenderContext(width: 60, height: 4)
        context.environment.focusManager!.register(FocusSentinel())
        let buffer = renderToBuffer(picker(), context: context)
        let out = buffer.lines.map { $0.stripped }.joined()

        #expect(out.contains("███"), "three solid cells: \(out)")
        // (The sliders' knobs are bullets too, so the question is specifically
        // whether the SWATCH broke: "█●█" is the marked form.)
        #expect(!out.contains("█●█"), "no marker when nothing is pointing at it: \(out)")
    }

    @Test("A focused swatch marks its CENTRE CELL and keeps its colour")
    func focusIsACentreBullet() {
        withColorDepth(.truecolor) {
            let context = makeRenderContext(width: 60, height: 4)
            // First registrant takes the focus, and that is the swatch.
            let buffer = renderToBuffer(picker(), context: context)
            let out = buffer.lines.map { $0.stripped }.joined()

            #expect(out.contains("█●█"), "the middle cell carries the state: \(out)")
            // The swatch's own colour is untouched — the whole point of marking
            // the centre cell instead of re-colouring the body.
            let painted = buffer.lines.joined()
            #expect(
                painted.contains("48;2;200;40;40"),
                "the swatch still paints its colour: \(painted)")
            // The centre cell is the ONLY difference from resting: the two
            // outer cells stay solid.
            #expect(out.contains("███") == false, "the swatch is marked, not solid: \(out)")
        }
    }

    @Test("The pointer marks a resting swatch")
    func hoverIsADimBullet() {
        withColorDepth(.truecolor) {
            let context = makeRenderContext(width: 60, height: 4)
            let dispatcher = context.environment.mouseEventDispatcher!
            dispatcher.setActiveSupport(.full)
            context.environment.focusManager!.register(FocusSentinel())

            let view = picker()
            let regions = renderToBuffer(view, context: context).hitTestRegions
            dispatcher.setRegions(regions)
            guard let region = regions.first(where: { $0.width == _ColorSwatchButtonStyle.width })
            else {
                Issue.record("expected a hit-test region the width of the swatch")
                return
            }
            _ = dispatcher.dispatch(
                MouseEvent(
                    button: .none, phase: .moved,
                    x: region.offsetX + 1, y: region.offsetY))

            let buffer = renderToBuffer(view, context: context)
            let out = buffer.lines.map { $0.stripped }.joined()
            #expect(out.contains("█●█"), "hover marks the centre cell too: \(out)")
            // …in the swatch's own colour, not a highlight fill over it.
            #expect(
                buffer.lines.joined().contains("48;2;200;40;40"),
                "the swatch keeps its colour under the pointer")
        }
    }

    // MARK: - Activation

    /// A frame with the run loop's own pass bracketing, so `@State` (the
    /// picker's `isEditing`) survives from one frame to the next.
    private func render(_ view: some View, tui: TUIContext, fm: FocusManager) -> String {
        var env = EnvironmentValues()
        env.focusManager = fm
        env.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 72, availableHeight: 24, environment: env, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        fm.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        fm.endRenderPass()
        tui.stateStorage.endRenderPass()
        // A presented modal floats to the screen root as an overlay layer, so
        // the page's own lines never hold it.
        let all = buffer.lines + buffer.overlays.flatMap(\.content.lines)
        return all.map { $0.stripped }.joined(separator: "\n")
    }

    @Test("Return on the swatch opens the full editor")
    func returnOpensThePanel() {
        let tui = TUIContext()
        let fm = FocusManager()
        let view = picker()

        let closed = render(view, tui: tui, fm: fm)
        #expect(!closed.contains("CMYK"), "the panel is not up yet: \(closed)")

        #expect(fm.dispatchKeyEvent(KeyEvent(key: .enter)), "the swatch took the key")
        let opened = render(view, tui: tui, fm: fm)
        // A tab strip only the full editor has.
        #expect(opened.contains("CMYK"), "the full editor is up: \(opened)")
    }

    // MARK: - Layout

    @Test("The label column obeys .colorPickerLabelWidth")
    func labelWidthMovesTheSwatch() {
        func swatchColumn(_ view: some View) -> Int? {
            let context = makeRenderContext(width: 72, height: 4)
            context.environment.focusManager!.register(FocusSentinel())
            let line = renderToBuffer(view, context: context).lines
                .map { $0.stripped }.first { $0.contains("███") }
            return line?.range(of: "███").map { line!.distance(from: line!.startIndex, to: $0.lowerBound) }
        }

        let standard = swatchColumn(picker())
        let widened = swatchColumn(picker().colorPickerLabelWidth(30))
        #expect(standard != nil && widened != nil, "a swatch on both")
        #expect(widened! > standard!, "a wider label column pushes the swatch right")
        #expect(widened! - standard! == 12, "…by exactly the extra width: 30 - 18")
    }
}

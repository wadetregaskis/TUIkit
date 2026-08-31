//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DisabledControlInteractionTests.swift
//
//  A disabled control answers neither the keyboard nor the pointer. The
//  keyboard half was already true; the pointer half was true only for a control
//  disabled by its OWN modifier, because the helper that registers the handlers
//  read `self.isDisabled` while the render read own-plus-cascaded.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Disabled controls answer nothing")
struct DisabledControlInteractionTests {

    /// Renders `view` twice (register, then read persisted state) and arms the
    /// dispatcher with whatever regions it emitted.
    private func armed<V: View>(_ view: V, context: RenderContext) -> MouseEventDispatcher {
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(MouseSupport.full)
        _ = renderToBuffer(view, context: context)
        dispatcher.setRegions(renderToBuffer(view, context: context).hitTestRegions)
        return dispatcher
    }

    private func click(_ dispatcher: MouseEventDispatcher, x: Int, y: Int) {
        for phase in [MousePhase.pressed, .released] {
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: phase, x: x, y: y))
        }
    }

    @Test("A slider disabled by its container ignores the pointer")
    func disabledSliderIgnoresThePointer() {
        for byContainer in [false, true] {
            let context = makeRenderContext(width: 40, height: 6)
            var value = 0.5
            let binding = Binding(get: { value }, set: { value = $0 })
            let slider = Slider(value: binding, in: 0...1)
            // The two ways to disable it. Only the first used to reach the
            // pointer wiring.
            let view =
                byContainer
                ? AnyView(VStack { slider }.disabled()) : AnyView(slider.disabled())
            let dispatcher = armed(view, context: context)
            // Well into the track, where a live slider jumps the value.
            click(dispatcher, x: 20, y: 0)
            #expect(
                value == 0.5,
                "disabled \(byContainer ? "by container" : "by modifier"); moved to \(value)")
        }
    }

    @Test("A stepper disabled by its container ignores the pointer")
    func disabledStepperIgnoresThePointer() {
        for byContainer in [false, true] {
            let context = makeRenderContext(width: 40, height: 6)
            var value = 5
            let binding = Binding(get: { value }, set: { value = $0 })
            let stepper = Stepper("Count", value: binding, in: 0...10)
            let view =
                byContainer
                ? AnyView(VStack { stepper }.disabled()) : AnyView(stepper.disabled())
            let dispatcher = armed(view, context: context)
            // Every cell of the row, so whichever one carries the ▶ is hit.
            for x in 0..<20 { click(dispatcher, x: x, y: 0) }
            #expect(
                value == 5,
                "disabled \(byContainer ? "by container" : "by modifier"); stepped to \(value)")
        }
    }

    @Test("A control that becomes disabled loses the focus it was holding")
    func disablingTakesTheFocus() {
        let context = makeRenderContext(width: 40, height: 6)
        let focus = context.environment.focusManager!
        var enabled = true
        let view = VStack {
            Slider(value: .constant(0.5), in: 0...1)
        }
        // Live: it registers, takes the automatic first focus, and holds it.
        focus.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        focus.endRenderPass()
        let held = focus.focusableIDsInActiveSection()
        #expect(held.count == 1, "the slider is the only stop: \(held)")
        #expect(focus.isFocused(id: held[0]))

        // Disabled: it declines focus, and the pass that notices takes it away
        // rather than leaving the keyboard pointed at something inert.
        enabled = false
        focus.beginRenderPass()
        _ = renderToBuffer(view.disabled(!enabled), context: context)
        focus.endRenderPass()
        #expect(focus.focusableIDsInActiveSection().isEmpty)
        #expect(!focus.isFocused(id: held[0]), "the focus stayed on a disabled control")
    }
}

// MARK: - What a disabled control looks like

@MainActor
@Suite("A disabled track is visibly disabled")
struct DisabledTrackTests {

    /// The reported fault: on the green palette a disabled slider drew a track
    /// indistinguishable from a live one, and only its label said otherwise.
    ///
    /// Only the FILLED colour used to change, and only some track styles draw
    /// with it — `.bar` and the gradients fill in the ACCENT, which was handed
    /// over undimmed whatever the state. So the assertion is about the accent
    /// specifically: a live track that paints it must have a disabled twin that
    /// does not, or nothing about the fill has changed.
    @Test("A disabled track never paints the live accent")
    func aDisabledTrackDropsTheAccent() {
        let styles: [(String, TrackStyle)] = [
            ("block", .block), ("blockFine", .blockFine), ("shade", .shade),
            ("bar", .bar), ("dot", .dot), ("braille", .braille),
        ]
        var sawAnAccentTrack = false
        for palette in PaletteRegistry.all {
            // As it reaches the terminal: `38;5;n` or `38;2;r;g;b`, joined the
            // way an SGR sequence joins its parameters.
            let accent = palette.accent.resolve(with: palette)
                .foregroundCodes()
                .joined(separator: ";")
            guard !accent.isEmpty else { continue }
            for (name, style) in styles {
                func draw(_ disabled: Bool) -> String {
                    var context = makeRenderContext(width: 40, height: 3)
                    context.environment.palette = palette
                    let slider = Slider(value: .constant(0.5), in: 0...1).trackStyle(style)
                    return renderToBuffer(
                        disabled ? AnyView(slider.disabled()) : AnyView(slider),
                        context: context
                    ).lines.joined()
                }
                let live = draw(false)
                guard live.contains(accent) else { continue }
                sawAnAccentTrack = true
                #expect(
                    !draw(true).contains(accent),
                    "\(palette.name)/\(name): a disabled track still paints the live accent")
            }
        }
        #expect(sawAnAccentTrack, "no track style paints the accent; this test asserts nothing")
    }
}

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

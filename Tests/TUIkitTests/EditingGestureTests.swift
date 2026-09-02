//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EditingGestureTests.swift
//
//  `onEditingChanged`, from the POINTER — the gesture the callback exists for.
//
//  SwiftUI describes it in terms of the pointer and only the pointer: a
//  `Slider`'s editing "begins when the user starts to drag the thumb along the
//  slider's track", a `Stepper`'s when "the user may touch and hold the
//  increment or decrement button". TUIkit had it wired to the keyboard alone —
//  a path SwiftUI has no equivalent of — because both views write their value
//  from their own mouse closure rather than through the handler that owns the
//  callback. So the one gesture it was designed around reported nothing.
//
//  `TextField`'s is not here because it is not the same shape: it begins on
//  focus and ends on blur, which a click satisfies on its way in.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Editing gestures report through the pointer")
struct EditingGestureTests {

    /// The widest region a control emits — its own body, as against the
    /// single-cell arrow zones a `Stepper` adds inside it.
    private func widestRegion(_ buffer: FrameBuffer) -> HitTestRegion? {
        buffer.hitTestRegions.max { $0.width < $1.width }
    }

    // MARK: - Slider

    @Test("A press on the track begins editing and the release ends it")
    func sliderPressAndRelease() {
        var value = 0.5
        var reports: [Bool] = []
        let context = makeRenderContext(width: 40, height: 1)
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.full)

        let slider = Slider(
            value: Binding(get: { value }, set: { value = $0 }), in: 0...1, step: 0.1,
            onEditingChanged: { reports.append($0) })
        let buffer = renderToBuffer(slider, context: context)
        dispatcher.setRegions(buffer.hitTestRegions)
        guard let region = widestRegion(buffer) else {
            Issue.record("expected a slider hit-test region")
            return
        }
        let x = region.offsetX + region.width / 2
        let y = region.offsetY

        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
        #expect(reports == [true], "the press began the edit: \(reports)")
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x, y: y))
        #expect(reports == [true, false], "the release ended it: \(reports)")
    }

    /// Once per GESTURE, not once per cell. A drag reports many positions and
    /// the value moves with every one of them; an app told "editing began"
    /// forty times over one drag would take each as a separate edit.
    @Test("A drag begins editing exactly once")
    func sliderDragBeginsOnce() {
        var value = 0.1
        var reports: [Bool] = []
        let context = makeRenderContext(width: 40, height: 1)
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.full)

        let slider = Slider(
            value: Binding(get: { value }, set: { value = $0 }), in: 0...1, step: 0.05,
            onEditingChanged: { reports.append($0) })
        let buffer = renderToBuffer(slider, context: context)
        dispatcher.setRegions(buffer.hitTestRegions)
        guard let region = widestRegion(buffer) else {
            Issue.record("expected a slider hit-test region")
            return
        }
        let y = region.offsetY
        let start = region.offsetX + 3

        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: start, y: y))
        for step in 1...8 {
            _ = dispatcher.dispatch(
                MouseEvent(button: .left, phase: .dragged, x: start + step, y: y))
        }
        #expect(reports == [true], "one report for the whole drag: \(reports)")
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: start + 8, y: y))
        #expect(reports == [true, false], "and one at the end: \(reports)")
        #expect(value > 0.1, "the drag actually moved it")
    }

    /// A wheel notch is a discrete adjustment like an arrow key rather than a
    /// hold, so it begins the edit and leaves the end to focus loss — there is
    /// no release to end it on. Asserted so the asymmetry is deliberate rather
    /// than forgotten.
    @Test("A wheel notch begins editing and leaves the end to focus loss")
    func sliderWheelBegins() {
        var value = 0.5
        var reports: [Bool] = []
        let context = makeRenderContext(width: 40, height: 1)
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)

        let slider = Slider(
            value: Binding(get: { value }, set: { value = $0 }), in: 0...1, step: 0.1,
            onEditingChanged: { reports.append($0) })
        let buffer = renderToBuffer(slider, context: context)
        dispatcher.setRegions(buffer.hitTestRegions)
        guard let region = widestRegion(buffer) else {
            Issue.record("expected a slider hit-test region")
            return
        }
        _ = dispatcher.dispatch(
            MouseEvent(
                button: .scrollDown, phase: .scrolled,
                x: region.offsetX + region.width / 2, y: region.offsetY))
        #expect(reports == [true], "the notch began the edit: \(reports)")
    }

    // MARK: - Stepper

    /// The `Stepper`'s arrows are a hold: press begins, release ends, and the
    /// auto-repeat runs between them — the same span, reported.
    @Test("A press on a Stepper arrow begins editing and the release ends it")
    func stepperArrowPressAndRelease() {
        var value = 5
        var reports: [Bool] = []
        let context = makeRenderContext(width: 20, height: 1)
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.full)

        let stepper = Stepper(
            "Count", value: Binding(get: { value }, set: { value = $0 }), in: 0...10,
            onEditingChanged: { reports.append($0) })
        let buffer = renderToBuffer(stepper, context: context)
        dispatcher.setRegions(buffer.hitTestRegions)
        // The single-cell zones are the arrows; the widest is the row itself.
        guard let arrow = buffer.hitTestRegions.first(where: { $0.width == 1 }) else {
            Issue.record("expected an arrow hit-test region: \(buffer.hitTestRegions)")
            return
        }
        _ = dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: arrow.offsetX, y: arrow.offsetY))
        #expect(reports == [true], "the press began the edit: \(reports)")
        _ = dispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: arrow.offsetX, y: arrow.offsetY))
        #expect(reports == [true, false], "the release ended it: \(reports)")
    }

    @Test("A wheel notch over a Stepper begins editing")
    func stepperWheelBegins() {
        var value = 5
        var reports: [Bool] = []
        let context = makeRenderContext(width: 20, height: 1)
        let dispatcher = context.environment.mouseEventDispatcher!
        dispatcher.setActiveSupport(.standard)

        let stepper = Stepper(
            "Count", value: Binding(get: { value }, set: { value = $0 }), in: 0...10,
            onEditingChanged: { reports.append($0) })
        let buffer = renderToBuffer(stepper, context: context)
        dispatcher.setRegions(buffer.hitTestRegions)
        guard let region = widestRegion(buffer) else {
            Issue.record("expected a stepper hit-test region")
            return
        }
        _ = dispatcher.dispatch(
            MouseEvent(
                button: .scrollDown, phase: .scrolled,
                x: region.offsetX + region.width / 2, y: region.offsetY))
        #expect(reports == [true], "the notch began the edit: \(reports)")
        #expect(value > 5, "and actually stepped it")
    }
}

//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StepperOverflowTests.swift
//
//  Regression tests for GitHub-class bug: a bounded integer Stepper whose
//  value sits within `step` of the type's representable maximum/minimum
//  trapped on the next press. `increment`/`decrement` computed
//  `value.advanced(by: step)` and THEN clamped — so the candidate overflowed
//  the type before the clamp could pin it to the bound. `Stepper(value: $n,
//  in: 0...Int.max)` held at the top, or `Int.min...0` at the bottom, crashed.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Stepper bound overflow safety")
struct StepperOverflowTests {
    @Test("Incrementing at a bound == Int.max pins instead of overflowing")
    func incrementAtIntMax() {
        var v = Int.max - 2
        let handler = StepperHandler(
            focusID: "s", value: Binding(get: { v }, set: { v = $0 }),
            bounds: 0...Int.max, step: 1)
        for _ in 0..<10 { handler.increment() }  // pushes to and past the ceiling
        #expect(v == Int.max, "pinned at the upper bound, no overflow trap")
    }

    @Test("Decrementing at a bound == Int.min pins instead of underflowing")
    func decrementAtIntMin() {
        var v = Int.min + 2
        let handler = StepperHandler(
            focusID: "s", value: Binding(get: { v }, set: { v = $0 }),
            bounds: Int.min...0, step: 1)
        for _ in 0..<10 { handler.decrement() }
        #expect(v == Int.min, "pinned at the lower bound, no underflow trap")
    }

    @Test("A step that would overshoot the ceiling lands exactly on it")
    func largeStepOvershootLandsOnBound() {
        var v = Int.max - 3
        let handler = StepperHandler(
            focusID: "s", value: Binding(get: { v }, set: { v = $0 }),
            bounds: 0...Int.max, step: 10)  // 10 > the 3 of room
        handler.increment()
        #expect(v == Int.max, "clamped to the bound without overflowing, got \(v)")
    }

    @Test("A step that would undershoot the floor lands exactly on it")
    func largeStepUndershootLandsOnBound() {
        var v = Int.min + 3
        let handler = StepperHandler(
            focusID: "s", value: Binding(get: { v }, set: { v = $0 }),
            bounds: Int.min...0, step: 10)
        handler.decrement()
        #expect(v == Int.min, "clamped to the bound without underflowing, got \(v)")
    }

    @Test("Ordinary in-range stepping is unchanged")
    func ordinaryStepping() {
        var v = 5
        let handler = StepperHandler(
            focusID: "s", value: Binding(get: { v }, set: { v = $0 }),
            bounds: 0...10, step: 2)
        handler.increment()
        #expect(v == 7)
        handler.increment()  // 9
        handler.increment()  // would be 11 → clamp to 10
        #expect(v == 10)
        handler.decrement()  // 8
        #expect(v == 8)
    }

    @Test("A Double stepper from NaN / infinity clamps into range without trapping")
    func doubleExtremesClamp() {
        for start in [Double.nan, Double.infinity, -Double.infinity] {
            var v = start
            let handler = StepperHandler(
                focusID: "s", value: Binding(get: { v }, set: { v = $0 }),
                bounds: 0.0...10.0, step: 1.0)
            handler.increment()
            handler.clampValue()
            #expect(v.isFinite && (0.0...10.0).contains(v), "start \(start) -> \(v)")
        }
    }

    @Test("A disabled control's label dims with it (Stepper and Picker)")
    @MainActor
    func disabledLabelDims() {
        // The label is part of the control: `.disabled` must dim it along
        // with the chrome, not leave it bright beside greyed arrows (the
        // Image pages' "Glyphs" stepper read as enabled while inert).
        func firstLine(_ view: some View) -> String {
            renderToBuffer(view, context: makeRenderContext(width: 40, height: 4))
                .lines.first ?? ""
        }
        let enabledStepper = firstLine(Stepper("Glyphs", value: .constant(3), in: 0...9))
        let disabledStepper = firstLine(
            Stepper("Glyphs", value: .constant(3), in: 0...9).disabled(true))
        #expect(enabledStepper.stripped == disabledStepper.stripped, "same glyphs either way")
        #expect(
            labelColour(of: enabledStepper) != labelColour(of: disabledStepper),
            "the disabled label carries a different (dimmed) colour")

        let enabledPicker = firstLine(
            Picker("Mode", selection: .constant(0)) { Text("A").tag(0) })
        let disabledPicker = firstLine(
            Picker("Mode", selection: .constant(0)) { Text("A").tag(0) }.disabled(true))
        #expect(
            labelColour(of: enabledPicker) != labelColour(of: disabledPicker),
            "the picker's label dims too")
    }

    /// The first foreground SGR (38;…) sequence in the line — the label is
    /// the first coloured run.
    private func labelColour(of line: String) -> String {
        guard let range = line.range(of: "\u{1B}\\[38;[0-9;]*m", options: .regularExpression)
        else { return "" }
        return String(line[range])
    }
}

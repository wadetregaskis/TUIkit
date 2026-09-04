//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StepperOverflowTests.swift
//
//  Regression tests for GitHub-class bug: a bounded integer Stepper whose
//  value sits within `step` of the type's representable maximum/minimum
//  trapped on the next press. `increment`/`decrement` computed
//  `value.advanced(by: step)` and THEN clamped — so the candidate overflowed
//  the type before the clamp could pin it to the bound. `Stepper(value: $n,
//  in: 0...Int.max)` held at the top, or `Int.min...0` at the bottom, crashed.
//
//  Then the guard that fixed it trapped in its own right: it pivoted off the
//  BOUND (`upperBound - step`), which underflows whenever the ceiling sits
//  within `step` of the type's opposite extreme — including on an unsigned
//  type with an ordinary range narrower than the step.
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

    @Test("A ceiling within `step` of the type's MINIMUM pins instead of trapping")
    func ceilingNearTypeMinimum() {
        // The overshoot guard used to pivot off the BOUND, computing
        // `upperBound - step`; with the ceiling this close to `Int.min` that
        // subtraction underflowed before any value was compared to it.
        var v = Int.min
        let handler = StepperHandler(
            focusID: "s", value: Binding(get: { v }, set: { v = $0 }),
            bounds: Int.min...(Int.min + 2), step: 5)
        handler.increment()
        #expect(v == Int.min + 2, "pinned at the ceiling, got \(v)")
    }

    @Test("A floor within `step` of the type's MAXIMUM pins instead of trapping")
    func floorNearTypeMaximum() {
        // The mirror: `lowerBound + step` overflowed.
        var v = Int.max
        let handler = StepperHandler(
            focusID: "s", value: Binding(get: { v }, set: { v = $0 }),
            bounds: (Int.max - 2)...Int.max, step: 5)
        handler.decrement()
        #expect(v == Int.max - 2, "pinned at the floor, got \(v)")
    }

    @Test("An unsigned range narrower than the step needs no extreme bound")
    func unsignedRangeNarrowerThanStep() {
        // Nothing exotic here: on an unsigned value type the same pivot is
        // `2 - 5`, which underflows for an ordinary small range.
        var v: UInt = 0
        let handler = StepperHandler(
            focusID: "s", value: Binding(get: { v }, set: { v = $0 }),
            bounds: UInt(0)...UInt(2), step: 5)
        handler.increment()
        #expect(v == 2, "clamped to the ceiling, got \(v)")
        handler.decrement()
        #expect(v == 0, "clamped to the floor, got \(v)")
    }

    @Test("An UNBOUNDED stepper pins at the type's extremes instead of trapping")
    func unboundedAtTypeExtremes() {
        // No bounds means no clamp to hide behind: the raw `advanced(by:)`
        // overflowed the type on the press.
        var high = Int.max
        let up = StepperHandler(
            focusID: "s", value: Binding(get: { high }, set: { high = $0 }), step: 3)
        up.increment()
        #expect(high == Int.max, "saturated at the type's maximum, got \(high)")

        var low = Int.min
        let down = StepperHandler(
            focusID: "s", value: Binding(get: { low }, set: { low = $0 }), step: 3)
        down.decrement()
        #expect(low == Int.min, "saturated at the type's minimum, got \(low)")
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

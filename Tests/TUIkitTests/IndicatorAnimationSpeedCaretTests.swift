//  🖥️ TUIkit — Terminal UI Kit for Swift
//  IndicatorAnimationSpeedCaretTests.swift
//
//  `.indicatorAnimationSpeed(_:for: .textCursor)` reaching the caret of a
//  `TextField`, a `SecureField` and a `TextEditor`, checked on the one run a focused
//  field leaves for its caret. The holds, at every speed, are in
//  `CursorBlinkRegularityTests`.
//  Durations are compared in whole nanoseconds, the unit a run's steps are counted
//  in.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Indicator animation speed on the text caret")
struct IndicatorAnimationSpeedCaretTests {
    /// The caret run a focused `view` leaves, as (frames, frame length in ticks), or
    /// `nil` when it leaves anything but exactly one run.
    private func caret(_ view: some View) -> (frames: Int, frameTicks: Int)? {
        let runs = renderToBuffer(view, context: makeRenderContext(width: 30, height: 6)).animatedCells
        guard runs.count == 1, let run = runs.first else { return nil }
        return (run.frames.count, run.frameTicks)
    }

    private func blinkingField() -> some View {
        TextField("Name", text: Binding.constant("Ada")).textCursor(.block, animation: .blink)
    }

    /// A blink is a sequence of two frames, so its frames stretch: 21-tick (350 ms)
    /// halves at the standard speed are 10.5 ticks at twice it, which rounds to 11.
    @Test("A text field's caret blinks in 11-tick halves, 183,333,333 ns, at twice the speed")
    func blinkAtDoubleSpeed() throws {
        let seen = try #require(caret(blinkingField().indicatorAnimationSpeed(2, for: .textCursor)))
        #expect(seen.frames == 2)
        #expect(seen.frameTicks == 11)
    }

    /// A pulse is a ramp of 3-tick (50 ms) frames, so half as fast is twice as many
    /// frames.
    @Test("A text field's pulsing caret takes 1.6 s at half the speed, in 50 ms frames")
    func pulseAtHalfSpeed() throws {
        let field = TextField("Name", text: Binding.constant("Ada")).textCursor(.block, animation: .pulse)
        let seen = try #require(caret(field.indicatorAnimationSpeed(.halfSpeed, for: .textCursor)))
        #expect(seen.frames == 32)
        #expect(seen.frameTicks == 3)
    }

    @Test("Unset, a text field's caret blinks in the standard 350 ms halves")
    func unsetIsTheStandardBlink() throws {
        let seen = try #require(caret(blinkingField()))
        #expect(seen.frames == 2)
        #expect(seen.frameTicks == 21)
    }

    @Test("A secure field's and an editor's carets blink at the speed set for the caret")
    func everyCaretReadsIt() throws {
        let secure = SecureField("Password", text: Binding.constant("hunter2"))
            .textCursor(.block, animation: .blink).indicatorAnimationSpeed(2, for: .textCursor)
        let editor = TextEditor(text: Binding.constant("hello"))
            .textCursor(.block, animation: .blink).indicatorAnimationSpeed(0.5, for: .textCursor)
        #expect(try #require(caret(secure)).frameTicks == 11)
        #expect(try #require(caret(editor)).frameTicks == 42)
    }

    @Test("The nearest setting for the caret wins, and a setting for another kind leaves it alone")
    func nearestWins() throws {
        // A speed for the focus emphasis does not reach the caret.
        #expect(
            try #require(caret(blinkingField().indicatorAnimationSpeed(2, for: .focusEmphasis))).frameTicks
                == 21)
        // `.all` does.
        #expect(try #require(caret(blinkingField().indicatorAnimationSpeed(2))).frameTicks == 11)
        // Inner `.textCursor` at 0.5 inside outer `.all` at 2.
        #expect(
            try #require(
                caret(blinkingField().indicatorAnimationSpeed(0.5, for: .textCursor).indicatorAnimationSpeed(2))
            ).frameTicks == 42)
    }
}

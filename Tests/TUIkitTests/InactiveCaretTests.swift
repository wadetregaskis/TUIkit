//  🖥️ TUIkit — Terminal UI Kit for Swift
//  InactiveCaretTests.swift
//
//  A text caret is the insertion point, not a focus indicator, so it stays
//  when a view does not appear active, as it stays under
//  `focusEffectDisabled`. What it stops doing there is moving: one still
//  frame, visible, dimmed to the pulse's dim end, whatever its animation. A
//  terminal draws its own cursor hollow in an unfocused window; TUIkit draws
//  the caret as cells, so the dim is that cue.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("A text caret holds still, dimmed, while a view does not appear active")
struct InactiveCaretTests {

    /// The three text inputs that draw a caret.
    enum Field: String, CaseIterable, CustomTestStringConvertible {
        case textField, secureField, textEditor

        var testDescription: String { rawValue }

        @MainActor var view: AnyView {
            switch self {
            case .textField: AnyView(TextField("Name", text: .constant("hi")))
            case .secureField: AnyView(SecureField("Pin", text: .constant("hi")))
            case .textEditor: AnyView(TextEditor(text: .constant("hi")))
            }
        }

        var size: (width: Int, height: Int) {
            self == .textEditor ? (24, 4) : (30, 3)
        }
    }

    // MARK: - The cycle

    @Test(
        "An inactive caret's cycle is one visible state at the pulse's dim end",
        arguments: TextCursorStyle.Animation.allCases)
    func cycleIsOneDimState(animation: TextCursorStyle.Animation) {
        let caret = Color.rgb(80, 240, 120)
        let field = Color.rgb(12, 14, 12)
        let dim = caret.breathEnds(dimmedTo: ViewConstants.focusPulseMin, over: field).dim
        let cycle = TextFieldContentRenderer.computeCursorCycle(
            baseColor: caret, over: field, animation: animation, speed: .standard,
            cursorTimer: nil, appearsActive: false)
        #expect(cycle.states.count == 1)
        #expect(!cycle.isAnimating)
        #expect(cycle.now.visible)
        #expect(cycle.now.color == dim)
    }

    // MARK: - Drawn

    /// `field` focused, under `animation`, where it does or does not appear
    /// active, with a live cursor clock: the frame and whether it read the clock.
    private func render(
        _ field: Field, animation: TextCursorStyle.Animation, appearsActive: Bool,
        effectDisabled: Bool = false
    ) -> (buffer: FrameBuffer, readClock: Bool) {
        let timer = CursorTimer(renderNotifier: AppState())
        let context = makeRenderContext(width: field.size.width, height: field.size.height) { environment, _ in
            environment.cursorTimer = timer
        }
        let view = field.view
            .textCursor(.block, animation: animation)
            .focusEffectDisabled(effectDisabled)
            .environment(\.appearsActive, appearsActive)
        timer.beginFrameReadTracking()
        let buffer = renderToBuffer(view, context: context)
        return (buffer, timer.didReadThisFrame)
    }

    @Test(
        "A focused field that does not appear active leaves no caret run and reads no clock",
        arguments: Field.allCases, TextCursorStyle.Animation.allCases)
    func inactiveCaretIsStill(field: Field, animation: TextCursorStyle.Animation) throws {
        let breathing = render(field, animation: .pulse, appearsActive: true)
        let run = try #require(breathing.buffer.animatedCells.first, "the premise: a focused caret pulses")
        // The pulse's dim end, drawn by the active caret itself: its cycle starts
        // bright and reaches the dim end halfway.
        let dimFrame = run.frames[run.frames.count / 2]

        let inactive = render(field, animation: animation, appearsActive: false)
        #expect(inactive.buffer.animatedCells.isEmpty, "\(inactive.buffer.animatedCells.count) runs left")
        #expect(!inactive.readClock)
        #expect(
            inactive.buffer.lines.contains { $0.contains(dimFrame) },
            "the caret is drawn, at the pulse's dim end")
    }

    @Test(
        "The caret animates again once the field appears active",
        arguments: Field.allCases, [TextCursorStyle.Animation.pulse, .blink])
    func activeCaretAnimates(field: Field, animation: TextCursorStyle.Animation) {
        let active = render(field, animation: animation, appearsActive: true)
        #expect(!active.buffer.animatedCells.isEmpty)
    }

    @Test(
        "focusEffectDisabled does not still the caret of a field that appears active",
        arguments: Field.allCases)
    func effectDisabledCaretAnimates(field: Field) {
        let disabled = render(field, animation: .pulse, appearsActive: true, effectDisabled: true)
        #expect(!disabled.buffer.animatedCells.isEmpty)
    }
}

//  🖥️ TUIKit — Terminal UI Kit for Swift
//  RevealWholeControlTests.swift
//
//  Arriving AT a control reveals the control; moving WITHIN one reveals only
//  what moved.
//
//  Tabbing into a List means you went to the *list* — so show as much of it as
//  fits, border and header included, rather than scrolling just far enough to
//  clear its first row. (The row getting selected is a side effect of
//  arriving.) Once the List already holds focus, Up/Down is moving between
//  rows, not regarding the list as a whole, so only the row need be in view —
//  which is what keeps a cursor visible while walking a long table.
//
//  Both behaviours come from the same regions: a focusable container emits a
//  whole-control region AND a smaller one for its active row.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@Suite("Reveal target: whole control vs the part that moved")
struct RevealTargetTests {

    private func region(y: Int, h: Int, focusID: String?) -> HitTestRegion {
        HitTestRegion(
            offsetX: 0, offsetY: y, width: 10, height: h,
            handlerID: HitTestRegion.HandlerID(0), focusID: focusID)
    }

    /// A bordered List: the whole control at 0..<12, its selected row at 5.
    private func buffer() -> FrameBuffer {
        var buffer = FrameBuffer(lines: Array(repeating: "", count: 12))
        buffer.hitTestRegions = [
            region(y: 5, h: 1, focusID: "list"),
            region(y: 0, h: 12, focusID: "list"),
        ]
        return buffer
    }

    @Test("arriving at the control targets all of it, border included")
    func wholeControlOnArrival() {
        let target = buffer().revealTarget(focusID: "list", wholeControl: true)
        #expect(target?.top == 0, "must start at the control's top: \(String(describing: target))")
        #expect(target?.height == 12, "must span the whole control: \(String(describing: target))")
    }

    @Test("moving within the control targets only the active row")
    func rowOnInnerMove() {
        let target = buffer().revealTarget(focusID: "list", wholeControl: false)
        #expect(target?.top == 5, "must target the row that moved: \(String(describing: target))")
        #expect(target?.height == 1, "and only that row: \(String(describing: target))")
    }

    @Test("region order does not matter")
    func orderIndependent() {
        var flipped = FrameBuffer(lines: Array(repeating: "", count: 12))
        flipped.hitTestRegions = [
            region(y: 0, h: 12, focusID: "list"),
            region(y: 5, h: 1, focusID: "list"),
        ]
        #expect(flipped.revealTarget(focusID: "list", wholeControl: true)?.height == 12)
        #expect(flipped.revealTarget(focusID: "list", wholeControl: false)?.top == 5)
    }

    @Test("other controls are ignored; an unknown id has no target")
    func ignoresOthers() {
        var mixed = FrameBuffer(lines: Array(repeating: "", count: 12))
        mixed.hitTestRegions = [
            region(y: 0, h: 3, focusID: "list"),
            region(y: 9, h: 2, focusID: "button"),
            region(y: 11, h: 1, focusID: nil),
        ]
        let target = mixed.revealTarget(focusID: "list", wholeControl: true)
        #expect(target?.top == 0 && target?.height == 3, "got \(String(describing: target))")
        #expect(mixed.revealTarget(focusID: "absent", wholeControl: true) == nil)
    }

    /// The cases above hand-build their regions. This one renders a real
    /// control inside a real `.border()`, which is where the geometry actually
    /// comes from — and where it was wrong: the container shifts a child's
    /// regions past the rule without growing them, so the reveal put the
    /// control's content flush with the viewport edge and left the rule itself
    /// one row outside.
    @MainActor
    @Test("A border drawn by a wrapper is part of the whole-control reveal")
    func wrapperBorderJoinsTheReveal() throws {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        let focusManager = FocusManager()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 30, availableHeight: 10,
            environment: environment, tuiContext: tui)

        tui.mouseEventDispatcher.beginRenderPass()
        focusManager.beginRenderPass()
        let view = Button("Press") {}.focusID("btn").border()
        let buffer = renderToBuffer(view, context: context)

        let whole = try #require(buffer.revealTarget(focusID: "btn", wholeControl: true))
        let inner = try #require(buffer.revealTarget(focusID: "btn", wholeControl: false))
        #expect(
            whole.top == inner.top - 1,
            "the rule above the button belongs to it: whole \(whole), inner \(inner)")
        #expect(
            whole.top + whole.height == inner.top + inner.height + 1,
            "…and the rule below it too")
        #expect(
            (inner.top, inner.height) == (1, 1),
            """
            the within-control target stays the bare content — a cursor moving \
            row to row must not keep re-revealing the frame
            """)
    }
}

//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollOverscrollTests.swift
//
//  §1.5 of the scroll-anchoring spec: how far past an edge a scrollable may be
//  pushed, and what that looks like.
//
//  The excursion is deliberately NOT an out-of-range `scrollOffset` — that was
//  measured to trap rather than misdraw (§3.3). These tests pin both halves of
//  that: the offset never leaves `[0, maxOffset]`, and the excursion still moves
//  the content on screen.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("A scrollable can be pushed past its edges")
struct ScrollOverscrollTests {

    private func handler(
        extent: Int = 100, viewport: Int = 10, top: Int = 0, bottom: Int = 0
    ) -> ScrollViewHandler {
        let handler = ScrollViewHandler(focusID: "sv")
        handler.contentHeight = extent
        handler.viewportHeight = viewport
        handler.wheelEdgeHold.delayNanos = 0
        handler.overscrollState.resolve(
            top: top == 0 ? .none : .rows(top),
            bottom: bottom == 0 ? .none : .rows(bottom),
            viewportHeight: viewport)
        return handler
    }

    // MARK: - The allowance

    @Test("The allowance resolves absolutely and relative to the viewport")
    func allowanceResolution() {
        #expect(ScrollOverscroll.none.resolved(viewportHeight: 20) == 0)
        #expect(ScrollOverscroll.rows(5).resolved(viewportHeight: 20) == 5)
        #expect(ScrollOverscroll.viewport(minus: 1).resolved(viewportHeight: 20) == 19)
        #expect(
            ScrollOverscroll.viewport(minus: 0).resolved(viewportHeight: 20) == 20,
            "minus: 0 is a whole viewport — the content may leave the screen")
        #expect(
            ScrollOverscroll.viewport(minus: 99).resolved(viewportHeight: 20) == 0,
            "a shortfall past the viewport height floors at zero, never negative")
        #expect(ScrollOverscroll.rows(-3).resolved(viewportHeight: 20) == 0)
    }

    // MARK: - The state machine

    @Test("Reaching the edge does not overscroll; the NEXT push does")
    func grazingTheEdgeDoesNotStick() {
        let sv = handler(bottom: 4)
        sv.scrollOffset = sv.maxOffset - 1

        // This step is spent arriving at the edge — the graze.
        #expect(sv.userScrollFine(by: 3))
        #expect(sv.scrollOffset == sv.maxOffset)
        #expect(
            sv.overscrollState.excursion == 0,
            """
            §1.3: a scroll that merely lands on the edge must not stick. It is \
            the step the content can no longer absorb that is unambiguous.
            """)

        // The next one has nowhere to go but the allowance.
        #expect(sv.userScrollFine(by: 3))
        #expect(sv.overscrollState.excursion == 3)
        #expect(sv.scrollOffset == sv.maxOffset, "and the offset stayed in range")
    }

    @Test("The excursion is bounded by the allowance at that end", arguments: [1, 4, 9])
    func excursionIsBounded(_ allowance: Int) {
        let sv = handler(top: allowance, bottom: allowance)
        sv.scrollOffset = 0
        for _ in 0..<20 { _ = sv.userScrollFine(by: -3) }
        #expect(sv.overscrollState.excursion == -allowance)
        #expect(sv.scrollOffset == 0, "the offset never went negative")

        sv.scrollOffset = sv.maxOffset
        sv.overscrollState.excursion = 0
        for _ in 0..<20 { _ = sv.userScrollFine(by: 3) }
        #expect(sv.overscrollState.excursion == allowance)
        #expect(sv.scrollOffset == sv.maxOffset, "nor past the maximum")
    }

    @Test("The two ends are independent")
    func endsAreIndependent() {
        let sv = handler(top: 0, bottom: 6)
        sv.scrollOffset = 0
        for _ in 0..<5 { _ = sv.userScrollFine(by: -2) }
        #expect(sv.overscrollState.excursion == 0, "no allowance at the top")

        sv.scrollOffset = sv.maxOffset
        for _ in 0..<5 { _ = sv.userScrollFine(by: -2) }  // scroll back up first
        sv.scrollOffset = sv.maxOffset
        for _ in 0..<5 { _ = sv.userScrollFine(by: 2) }
        #expect(sv.overscrollState.excursion == 6, "but six rows at the bottom")
    }

    @Test("Coming back unwinds the excursion before the content moves")
    func unwindingComesFirst() {
        let sv = handler(bottom: 5)
        sv.scrollOffset = sv.maxOffset
        _ = sv.userScrollFine(by: 4)  // (after the graze-consuming step is unnecessary: already at edge)
        #expect(sv.overscrollState.excursion == 4)

        // A smaller step back only unwinds.
        #expect(sv.userScrollFine(by: -1))
        #expect(sv.overscrollState.excursion == 3)
        #expect(sv.scrollOffset == sv.maxOffset, "the content itself has not moved yet")

        // A larger one unwinds the rest AND scrolls with the leftover.
        #expect(sv.userScrollFine(by: -5))
        #expect(sv.overscrollState.excursion == 0)
        #expect(
            sv.scrollOffset == sv.maxOffset - 2,
            "the 2 lines left after unwinding 3 scrolled the content")
    }

    @Test("A view whose content fits can still be pushed")
    func fittingContentStillOverscrolls() {
        // Owner decision: the allowance is not conditional on there being
        // anything to scroll. Note this diverges from `scroll(by:)`'s
        // `extent > viewportHeight` guard, so it cannot ride on that path.
        let sv = handler(extent: 4, viewport: 10, top: 3, bottom: 3)
        #expect(sv.maxOffset == 0, "nothing to scroll")
        for _ in 0..<10 { _ = sv.userScrollFine(by: 1) }
        #expect(sv.overscrollState.excursion == 3)
        #expect(sv.scrollOffset == 0)
    }

    @Test("Without an allowance the user path is exactly the ordinary one")
    func inertWithoutAnAllowance() {
        let sv = handler()  // no allowance
        sv.scrollOffset = sv.maxOffset
        #expect(!sv.userScrollFine(by: 5), "blocked at the edge, as before")
        #expect(sv.overscrollState.excursion == 0)
        sv.scrollOffset = 0
        #expect(!sv.userScrollFine(by: -5))
        #expect(sv.overscrollState.excursion == 0)
        #expect(sv.userScrollFine(by: 5), "and ordinary movement is untouched")
        #expect(sv.scrollOffset == 5)
    }

    @Test("A programmatic jump leaves no excursion behind")
    func programmaticJumpsClearIt() {
        let sv = handler(top: 5, bottom: 5)
        sv.scrollOffset = sv.maxOffset
        _ = sv.userScrollFine(by: 4)
        #expect(sv.overscrollState.excursion == 4)

        sv.scrollToTop()
        #expect(
            sv.overscrollState.excursion == 0,
            "Home aims at an exact edge; an excursion under it would offset it")

        sv.scrollOffset = 0
        _ = sv.userScrollFine(by: -4)
        #expect(sv.overscrollState.excursion == -4)
        sv.scrollToBottom()
        #expect(sv.overscrollState.excursion == 0)
    }

    @Test("A shrinking viewport pulls a relative excursion back inside it")
    func resolveReclampsTheExcursion() {
        let sv = ScrollViewHandler(focusID: "sv")
        sv.contentHeight = 100
        sv.viewportHeight = 20
        sv.overscrollState.resolve(top: .none, bottom: .viewport(minus: 0), viewportHeight: 20)
        sv.scrollOffset = sv.maxOffset
        for _ in 0..<30 { _ = sv.userScrollFine(by: 3) }
        #expect(sv.overscrollState.excursion == 20)

        // The terminal shrank: the allowance shrank with it.
        sv.viewportHeight = 6
        sv.overscrollState.resolve(top: .none, bottom: .viewport(minus: 0), viewportHeight: 6)
        #expect(sv.overscrollState.excursion == 6, "and the excursion came back inside it")
    }

    // MARK: - Through a real render

    private func lines(_ view: some View, height: Int = 8) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: 20, height: height))
            .lines.map(\.stripped)
    }

    private func longContent() -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<40, id: \.self) { Text("line \($0)") }
            }
        }
    }

    @Test("The excursion slides the content and leaves blank rows behind it")
    func excursionRendersAsBlankRows() {
        let ctx = makeRenderContext(width: 20, height: 8) { environment, tui in
            environment.mouseEventDispatcher = tui.mouseEventDispatcher
            environment.scrollOverscrollTop = .rows(3)
        }
        let dispatcher = ctx.environment.mouseEventDispatcher!
        let view = longContent()

        let first = renderToBuffer(view, context: ctx)
        dispatcher.setRegions(first.hitTestRegions)
        #expect(
            first.lines.map(\.stripped).first?.contains("line 0") == true,
            "the view starts against its top edge")

        // Already at the top, so this tick has nowhere to go but the allowance —
        // no graze step to spend first.
        _ = dispatcher.dispatch(MouseEvent(button: .scrollUp, phase: .scrolled, x: 2, y: 2))
        let pushed = renderToBuffer(view, context: ctx).lines.map(\.stripped)

        let blanks = pushed.prefix(while: { $0.trimmingCharacters(in: .whitespaces).isEmpty }).count
        #expect(
            blanks == 3,
            """
            three blank rows opened above the content — the allowance, in full:
            \(pushed.joined(separator: "\n"))
            """)
        #expect(
            pushed.dropFirst(blanks).first?.contains("line 0") == true,
            "and the content that was at the top is now below them")
        #expect(
            pushed.count == first.lines.count,
            "the viewport is the same height — the content slid within it")
    }

    @Test("A control pushed down the screen is still clickable where it is drawn")
    func hitRegionsSlideWithTheContent() {
        let ctx = makeRenderContext(width: 24, height: 8) { environment, tui in
            environment.mouseEventDispatcher = tui.mouseEventDispatcher
            environment.scrollOverscrollTop = .rows(2)
        }
        let dispatcher = ctx.environment.mouseEventDispatcher!
        let tapped = Flag()
        let view = ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Button("Press") { tapped.value = true }
                ForEach(0..<40, id: \.self) { Text("line \($0)") }
            }
        }

        let first = renderToBuffer(view, context: ctx)
        dispatcher.setRegions(first.hitTestRegions)
        _ = dispatcher.dispatch(MouseEvent(button: .scrollUp, phase: .scrolled, x: 2, y: 4))

        let pushed = renderToBuffer(view, context: ctx)
        dispatcher.setRegions(pushed.hitTestRegions)
        let screen = pushed.lines.map(\.stripped)
        guard let row = screen.firstIndex(where: { $0.contains("Press") }) else {
            Issue.record("the button is not on screen:\n\(screen.joined(separator: "\n"))")
            return
        }
        #expect(row == 2, "the button slid down by the 2-row excursion, got row \(row)")

        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 3, y: row))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 3, y: row))
        #expect(
            tapped.value,
            "its hit region came with it — a control must be clickable where it is drawn")
    }

    @Test("Overscrolling does not invent content for the indicators to count")
    func indicatorsIgnoreTheExcursion() {
        let sv = handler(bottom: 5)
        sv.scrollOffset = sv.maxOffset
        _ = sv.userScrollFine(by: 4)
        #expect(sv.overscrollState.excursion == 4)
        #expect(!sv.hasContentBelow, "there is still nothing below — the rows ran out")
        #expect(sv.rowsBelow == 0)
        #expect(sv.hasContentAbove, "and everything above is still above")
        #expect(sv.rowsAbove == sv.scrollOffset)
    }
}

/// A settable flag for callbacks fired from a mouse handler.
@MainActor
private final class Flag {
    var value = false
}
